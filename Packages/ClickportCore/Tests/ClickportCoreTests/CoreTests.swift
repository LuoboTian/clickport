import Foundation
import Testing
import Darwin
@testable import ClickportCore

@Test func configurationFileReadsAreBoundedAndRejectSpecialFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("settings.json")
    let store = ConfigurationStore(url: file)
    try store.save(Configuration())
    #expect(try Configuration.read(from: file) == Configuration())
    let original = try Data(contentsOf: file)
    let oversized = Data(repeating: 0x20, count: Configuration.maximumBytes + 1)
    let large = root.appendingPathComponent("large.json")
    try oversized.write(to: large)
    #expect(throws: ConfigurationError.self) { try Configuration.read(from: large) }
    #expect(throws: ConfigurationError.self) { try store.importData(oversized) }
    var oversizedConfiguration = Configuration()
    oversizedConfiguration.applications = [.init(name: String(repeating: "x", count: Configuration.maximumBytes), url: URL(fileURLWithPath: "/fixture/Example.app"))]
    #expect(throws: ConfigurationError.self) { try store.save(oversizedConfiguration) }
    #expect(throws: ConfigurationError.self) { try oversizedConfiguration.exportData() }
    #expect(try Data(contentsOf: file) == original)
    let link = root.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(throws: (any Error).self) { try Configuration.read(from: link) }
    let pipe = root.appendingPathComponent("pipe.json")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws: ConfigurationError.self) { try Configuration.read(from: pipe) }
    #expect(throws: ConfigurationError.self) { try Configuration.read(from: root) }
    #expect(try Data(contentsOf: file) == original)
}

@Test func pathsPreserveOriginalCharactersAndSelection() throws {
    let paths = ["/sample/a %20 中文.txt", "/sample/b.txt"]
    let context = TargetContext(selected: paths.map { URL(fileURLWithPath: $0) }, directory: URL(fileURLWithPath: "/wrong"))
    #expect(try context.pathsForClipboard() == paths.joined(separator: "\n"))
}
@Test func blankContextCopiesDirectoryButCannotDeleteIt() throws {
    let context = TargetContext(selected: [], directory: URL(fileURLWithPath: "/sample"))
    #expect(try context.pathsForClipboard() == "/sample")
    #expect(throws: TargetError.self) { try context.deletionTargets() }
}

@Test func requestsRejectExpiryFutureDatesAndPreviousHostSession() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    var request = ActionRequest(action: .builtin(.copyPath), context: .init(selected: [], directory: URL(fileURLWithPath: "/sample")))
    request.createdAt = now.addingTimeInterval(-1)
    try request.validate(now: now, sessionStartedAt: now.addingTimeInterval(-2))
    #expect(throws: ConfigurationError.self) { try request.validate(now: now, sessionStartedAt: now) }
    request.createdAt = now.addingTimeInterval(-120)
    #expect(throws: ConfigurationError.self) { try request.validate(now: now) }
    request.createdAt = now.addingTimeInterval(6)
    #expect(throws: ConfigurationError.self) { try request.validate(now: now) }
    request.createdAt = now
    try request.validate(now: now, sessionStartedAt: now)
}

@Test func inboxDrainsInvalidEntriesAndConsumesValidRequestOnlyOnce() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    for number in 0..<25 {
        let name = String(format: "00000000-0000-0000-0000-%012d.json", number)
        try Data("invalid".utf8).write(to: root.appendingPathComponent(name))
    }
    var request = ActionRequest(action: .builtin(.copyPath), context: .init(selected: [], directory: root))
    request.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    request.createdAt = now
    try JSONEncoder().encode(request).write(to: root.appendingPathComponent(request.id.uuidString + ".json"))
    let inbox = RequestInbox(directory: root)
    #expect(try inbox.takeNext(sessionStartedAt: now, now: now) == nil)
    #expect(try inbox.takeNext(sessionStartedAt: now, now: now)?.id == request.id)
    #expect(try inbox.takeNext(sessionStartedAt: now, now: now) == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func inboxRejectsSymlinksAndOversizeWithoutTouchingLinkedFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let inboxURL = root.appendingPathComponent("Requests")
    try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original.txt")
    try Data("preserve".utf8).write(to: original)
    try FileManager.default.createSymbolicLink(at: inboxURL.appendingPathComponent(UUID().uuidString + ".json"), withDestinationURL: original)
    try Data(repeating: 0, count: RequestInbox.maximumBytes).write(to: inboxURL.appendingPathComponent(UUID().uuidString + ".json"))
    #expect(try RequestInbox(directory: inboxURL).takeNext(sessionStartedAt: Date()) == nil)
    #expect(try String(contentsOf: original, encoding: .utf8) == "preserve")
    #expect(try FileManager.default.contentsOfDirectory(atPath: inboxURL.path).isEmpty)
}
@Test func multipleTargetsRequireExplicitCreationDirectory() {
    let context = TargetContext(selected: [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")], directory: nil)
    #expect(throws: TargetError.self) { try context.creationDirectory { _ in true } }
}
@Test func creationUsesSelectedDirectoryOrFileParent() throws {
    let item = URL(fileURLWithPath: "/sample/item")
    let context = TargetContext(selected: [item], directory: URL(fileURLWithPath: "/wrong"))
    #expect(try context.creationDirectory { _ in true } == item)
    #expect(try context.creationDirectory { _ in false }.path == "/sample")
}
@Test func newlinePathsAreNotSilentlySplit() {
    #expect(throws: TargetError.self) {
        try TargetContext(selected: [URL(fileURLWithPath: "/sample/a\nb")], directory: nil).pathsForClipboard()
    }
}
@Test func dangerousOrDanglingShortcutsAreRejected() {
    var config = Configuration()
    config.shortcuts = [.builtin(.deletePermanently)]
    #expect(throws: ConfigurationError.self) { try config.validated() }
    config.shortcuts = [.application(UUID())]
    #expect(throws: ConfigurationError.self) { try config.validated() }
}
@Test func exportOmitsEnvironmentValues() throws {
    var config = Configuration()
    config.applications = [.init(name: "Example", url: URL(fileURLWithPath: "/Applications/Example.app"), environment: ["SECRET": "fixture-value"])]
    let data = try config.exportData()
    #expect(!String(decoding: data, as: UTF8.self).contains("fixture-value"))
    #expect(try Configuration.decode(data).applications[0].environment.isEmpty)
    #expect(config.applications[0].environment["SECRET"] == "fixture-value")
}
@Test func invalidImportPreservesSavedConfiguration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ConfigurationStore(url: root.appendingPathComponent("config.json"))
    var initial = Configuration(); initial.showMenuBar = false
    try store.save(initial)
    var invalid = Configuration(); invalid.schemaVersion = 999
    #expect(throws: ConfigurationError.self) { try store.importData(JSONEncoder().encode(invalid)) }
    #expect(try store.load() == initial)
}

@Test func creationNeverOverwritesAndJSONIsValid() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let template = TemplateEntry.defaults[2]
    let first = try FileOperations.create(template: template, in: root)
    try Data("preserve".utf8).write(to: first)
    let second = try FileOperations.create(template: template, in: root)
    #expect(first != second)
    #expect(try String(contentsOf: first, encoding: .utf8) == "preserve")
    #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: second)) is [String: Any])
}

@Test func importedTemplateContentsArePreserved() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    let content = Data("Template content\n".utf8)
    try content.write(to: source)
    let result = try FileOperations.create(template: .init(name: "Example", fileExtension: "txt", source: source), in: root)
    #expect(try Data(contentsOf: result) == content)
}

@Test func templateImportCommitPreservesEditsAndRejectsObsoleteResults() {
    let original = TemplateEntry(name: "Original", fileExtension: "txt", source: URL(fileURLWithPath: "/fixture/old.txt"))
    var imported = original
    imported.source = URL(fileURLWithPath: "/fixture/new.txt")
    var configuration = Configuration()
    configuration.templates = [original]
    configuration.templates[0].name = "Renamed during import"
    configuration.templates[0].enabled = false
    let committedReplacement = configuration.applyImportedTemplate(imported, replacing: original)
    #expect(committedReplacement)
    #expect(configuration.templates[0].source == imported.source)
    #expect(configuration.templates[0].name == "Renamed during import")
    #expect(!configuration.templates[0].enabled)
    let committed = configuration
    let committedStaleReplacement = configuration.applyImportedTemplate(imported, replacing: original)
    #expect(!committedStaleReplacement)
    #expect(configuration == committed)
    configuration.templates = []
    let resurrectedRemovedEntry = configuration.applyImportedTemplate(imported, replacing: original)
    #expect(!resurrectedRemovedEntry)
    #expect(configuration.templates.isEmpty)
    let inserted = configuration.applyImportedTemplate(imported, replacing: nil)
    #expect(inserted)
    let insertedDuplicate = configuration.applyImportedTemplate(imported, replacing: nil)
    #expect(!insertedDuplicate)
    #expect(configuration.templates.count == 1)
}

@Test func failedCreationLeavesNoDocumentOrStagingDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let template = TemplateEntry(name: "Missing", fileExtension: "txt", source: root.appendingPathComponent("missing.txt"))
    #expect(throws: (any Error).self) { try FileOperations.create(template: template, in: root) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func configurationCannotIntroduceUnsupportedTemplateTypes() throws {
    var configuration = Configuration()
    configuration.templates = [.init(name: "Unsupported", fileExtension: "html", source: URL(fileURLWithPath: "/fixture/source.html"))]
    let data = try JSONEncoder().encode(configuration)
    #expect(throws: ConfigurationError.self) { try Configuration.decode(data) }
}

@Test func configuredTemplateCannotPublishFakeOfficeOrChangedJSON() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    try Data("Not an Office document".utf8).write(to: source)
    var configuration = Configuration()
    configuration.templates = [.init(name: "Office", fileExtension: "docx", source: source)]
    let imported = try Configuration.decode(JSONEncoder().encode(configuration))
    #expect(throws: ConfigurationError.self) { try FileOperations.create(template: imported.templates[0], in: root) }
    let original = root.appendingPathComponent("source.json")
    try Data("{}".utf8).write(to: original)
    let library = TemplateLibrary(root: root.appendingPathComponent("library"))
    let snapshot = try library.importTemplate(from: original)
    try Data("invalid JSON".utf8).write(to: #require(snapshot.source))
    #expect(throws: (any Error).self) { try FileOperations.create(template: snapshot, in: root) }
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(!names.contains(where: { $0.hasPrefix("Untitled") || $0.hasPrefix(".clickport-create-") }))
    #expect(try Data(contentsOf: original) == Data("{}".utf8))
}

@Test func configuredTemplateCannotPublishSymbolicLinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original.txt")
    try Data("preserve".utf8).write(to: original)
    let link = root.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
    let entry = TemplateEntry(name: "Link", fileExtension: "txt", source: link)
    #expect(throws: ConfigurationError.self) { try FileOperations.create(template: entry, in: root) }
    #expect(try Data(contentsOf: original) == Data("preserve".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["link.txt", "original.txt"])
}

@Test func concurrentCreationPublishesUniqueCompleteDocuments() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let urls = try await withThrowingTaskGroup(of: URL.self) { group in
        for _ in 0..<20 {
            group.addTask { try FileOperations.create(template: TemplateEntry.defaults[2], in: root) }
        }
        var results: [URL] = []
        for try await result in group { results.append(result) }
        return results
    }
    #expect(Set(urls).count == 20)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 20)
    for url in urls { #expect(try String(contentsOf: url, encoding: .utf8) == "{}\n") }
}

@Test func cancelledCreationDoesNotPublishOrLeaveStaging() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await FileOperations.createAsync(template: TemplateEntry.defaults[2], in: root)
    }
    do {
        _ = try await task.value
        Issue.record("Cancelled creation must throw")
    } catch is CancellationError { }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    let created = try await FileOperations.createAsync(template: TemplateEntry.defaults[2], in: root)
    #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: created)) is [String: Any])
}

@Test func disabledSourcesHideMenuEntriesWithoutLosingShortcuts() {
    var config = Configuration()
    config.enabledActions.remove(.copyPath)
    let plan = MenuPlanner.plan(configuration: config, context: .init(selected: [], directory: URL(fileURLWithPath: "/sample")), isDirectory: { _ in true })
    #expect(plan.shortcuts.isEmpty)
    #expect(config.shortcuts == [.builtin(.copyPath)])
    #expect(!plan.sections.flatMap(\.actions).contains { $0.reference == .builtin(.deletePermanently) })
}

@Test func hiddenChildEnumerationDoesNotRecurse() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let nested = root.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let direct = root.appendingPathComponent("direct.txt")
    let inner = nested.appendingPathComponent("inner.txt")
    try Data().write(to: direct); try Data().write(to: inner)
    try FileOperations.setHidden(true, at: direct)
    try FileOperations.setHidden(true, at: inner)
    let items = try FileOperations.hiddenChildren(in: root)
    #expect(items.map(\.lastPathComponent) == ["direct.txt"])
    try FileOperations.setHidden(false, at: direct)
    #expect(try inner.resourceValues(forKeys: [.isHiddenKey]).isHidden == true)
}

@Test func savedConfigurationIsPrivateAfterInitialAndReplacementWrites() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ConfigurationStore(url: root.appendingPathComponent("config.json"))
    try store.save(Configuration())
    let initial = try FileManager.default.attributesOfItem(atPath: store.url.path)
    #expect((initial[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.url.path)
    var next = Configuration(); next.showMenuBar = false
    try store.save(next)
    let replaced = try FileManager.default.attributesOfItem(atPath: store.url.path)
    #expect((replaced[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try store.load() == next)
}

@Test func configurationRejectsInvalidEnvironmentAndPreservesArgumentBoundaries() throws {
    var config = Configuration()
    config.applications = [.init(name: "Example", url: URL(fileURLWithPath: "/Applications/Example.app"), arguments: ["a b", "$(not-a-shell-command)", "中文"], environment: ["EXAMPLE": "a b"])]
    let roundTrip = try Configuration.decode(JSONEncoder().encode(config))
    #expect(roundTrip.applications.first?.arguments == config.applications.first?.arguments)
    config.applications[0].environment = ["INVALID=KEY": "value"]
    #expect(throws: ConfigurationError.self) { try config.validated() }
}

@Test func diagnosticsAreBoundedAndContainOnlyAllowedFields() throws {
    var log = DiagnosticLog(capacity: 2)
    log.record(.applicationStarted)
    log.record(.configurationSaved)
    log.record(.errorPresented)
    let objects = try #require(JSONSerialization.jsonObject(with: log.exportData()) as? [[String: Any]])
    #expect(objects.count == 2)
    #expect(objects.allSatisfy { Set($0.keys) == ["date", "event"] })
    #expect(objects.first?["event"] as? String == "configurationSaved")
}

@Test func importedSnapshotSurvivesOriginalRemovalAndReplacementKeepsIdentity() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("example.txt")
    let library = TemplateLibrary(root: root.appendingPathComponent("library"))
    try Data("first".utf8).write(to: original)
    let entry = try library.importTemplate(from: original)
    try FileManager.default.removeItem(at: original)
    #expect(try String(contentsOf: #require(entry.source), encoding: .utf8) == "first")
    try Data("second".utf8).write(to: original)
    let replacement = try library.importTemplate(from: original, replacing: entry)
    #expect(replacement.id == entry.id)
    #expect(replacement.source != entry.source)
    #expect(try String(contentsOf: #require(entry.source), encoding: .utf8) == "first")
    #expect(try String(contentsOf: #require(replacement.source), encoding: .utf8) == "second")
    try library.removeSnapshot(entry.source)
    #expect(FileManager.default.fileExists(atPath: original.path))
    let created = try FileOperations.create(template: replacement, in: root)
    #expect(try String(contentsOf: created, encoding: .utf8) == "second")
}

@Test func invalidTemplateImportLeavesExistingSnapshotUntouched() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("example.json")
    let library = TemplateLibrary(root: root.appendingPathComponent("library"))
    try Data("{}".utf8).write(to: original)
    let initial = try library.importTemplate(from: original)
    try Data("not JSON".utf8).write(to: original)
    #expect(throws: (any Error).self) { try library.importTemplate(from: original, replacing: initial) }
    #expect(try String(contentsOf: #require(initial.source), encoding: .utf8) == "{}")
    let fakeOffice = root.appendingPathComponent("empty.docx")
    try Data().write(to: fakeOffice)
    #expect(throws: ConfigurationError.self) { try library.importTemplate(from: fakeOffice) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.root.path).count == 1)
}

@Test func templateCleanupCannotRemoveOriginalsAndSymlinksAreRejected() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("original.txt")
    try Data("keep".utf8).write(to: original)
    let library = TemplateLibrary(root: root.appendingPathComponent("library"))
    try library.removeSnapshot(original)
    #expect(FileManager.default.fileExists(atPath: original.path))
    let link = root.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
    #expect(throws: ConfigurationError.self) { try library.importTemplate(from: link) }
}

@Test func dotfileUnhideDoesNotReportFalseSuccessOrRename() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent(".example")
    try Data("preserve".utf8).write(to: file)
    #expect(throws: ConfigurationError.self) { try FileOperations.setHidden(false, at: file) }
    #expect(try String(contentsOf: file, encoding: .utf8) == "preserve")
}

@Test func menuDraftPreservesSourceChangesAndDropsOnlyDeletedReferences() throws {
    var config = Configuration()
    let app = ApplicationEntry(name: "Example", url: URL(fileURLWithPath: "/Applications/Example.app"))
    config.applications = [app]
    var draft = MenuCustomization(configuration: config)
    draft.shortcuts = [.application(app.id), .builtin(.copyPath)]
    draft.groups.reverse()
    config.applications[0].enabled = false
    config.showMenuBar = false
    draft.reconcile(with: config)
    let saved = try draft.applying(to: config)
    #expect(saved.shortcuts == [.application(app.id), .builtin(.copyPath)])
    #expect(!saved.applications[0].enabled)
    #expect(!saved.showMenuBar)
    #expect(saved.groups == MenuGroup.allCases.reversed())
    config.applications = []
    draft.reconcile(with: config)
    #expect(draft.shortcuts == [.builtin(.copyPath)])
}

@Test func invalidMenuDraftCannotReplaceEffectiveConfiguration() {
    let config = Configuration()
    var draft = MenuCustomization(configuration: config)
    draft.shortcuts = [.builtin(.deletePermanently)]
    #expect(throws: ConfigurationError.self) { try draft.applying(to: config) }
    #expect(config.shortcuts == [.builtin(.copyPath)])
}

@Test func itemMenuDoesNotTreatClickedFileAsCurrentDirectory() throws {
    let file = URL(fileURLWithPath: "/example/document.txt")
    let context = TargetContext.captured(containerMenu: false, target: file, selection: [file])
    #expect(context.directory?.path == "/example")
    #expect(context.selected == [file])
    let folder = URL(fileURLWithPath: "/example/folder", isDirectory: true)
    let folderContext = TargetContext.captured(containerMenu: false, target: folder, selection: [folder])
    #expect(folderContext.directory?.path == "/example")
    #expect(try folderContext.creationDirectory { _ in true } == folder)
}

@Test func blankMenuIgnoresResidualSelectionAndSearchDoesNotGuessDirectory() {
    let folder = URL(fileURLWithPath: "/example")
    let file = URL(fileURLWithPath: "/elsewhere/document.txt")
    let blank = TargetContext.captured(containerMenu: true, target: folder, selection: [file])
    #expect(blank.selected.isEmpty)
    #expect(blank.directory == folder)
    let search = TargetContext.captured(containerMenu: false, target: file, selection: [file, folder])
    #expect(search.directory == nil)
    #expect(search.selected.count == 2)
}

@Test func actionRequestRejectsInvalidAuxiliaryDirectory() {
    let context = TargetContext(selected: [URL(fileURLWithPath: "/example/file")], directory: URL(string: "https://example.invalid"))
    let request = ActionRequest(action: .builtin(.unhideChildren), context: context)
    #expect(throws: ConfigurationError.self) { try request.validate() }
}

@Test func batchContinuesAfterIndividualFailures() async {
    let urls = ["first", "failed", "last"].map { URL(fileURLWithPath: "/fixture/" + $0) }
    let result = await BatchOperation.run(urls) { url in
        #expect(!Thread.isMainThread)
        if url.lastPathComponent == "failed" { throw TargetError.noTarget }
    }
    #expect(result.completed == 2)
    #expect(result.failures.map(\.url) == [urls[1]])
    #expect(result.attempted == 3)
    #expect(!result.cancelled)
}

@Test func cancellingBatchStopsBeforeNextItem() async {
    let urls = (0..<10).map { URL(fileURLWithPath: "/fixture/\($0)") }
    let result = await BatchOperation.run(urls, operation: { _ in }, progress: { _, _ in
        withUnsafeCurrentTask { $0?.cancel() }
    })
    #expect(result.cancelled)
    #expect(result.attempted == 1)
}

@Test func directoryScopeUsesComponentsAndRejectsSymlinkEscapes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let allowed = root.appendingPathComponent("allowed", isDirectory: true)
    let other = root.appendingPathComponent("allowed-other", isDirectory: true)
    try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(DirectoryScope.covers(allowed.appendingPathComponent("file.txt"), within: allowed))
    #expect(DirectoryScope.covers(allowed, within: allowed))
    #expect(!DirectoryScope.covers(other.appendingPathComponent("file.txt"), within: allowed))
    let link = allowed.appendingPathComponent("escape")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
    #expect(!DirectoryScope.covers(link.appendingPathComponent("file.txt"), within: allowed))
    #expect(!DirectoryScope.covers(URL(string: "https://example.invalid")!, within: allowed))
}

@Test func onlyOneHostCanOwnInboxAndOwnershipIsReleased() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var first: HostLock? = try HostLock(root: root)
    withExtendedLifetime(first) {
        #expect(throws: ConfigurationError.self) { try HostLock(root: root) }
    }
    first = nil
    let next = try HostLock(root: root)
    withExtendedLifetime(next) {
        #expect(throws: ConfigurationError.self) { try HostLock(root: root) }
    }
}

@Test func sharedLocalizationIncludesAllFiveLanguages() {
    let expected = ["en": "Copy Path", "zh-Hans": "复制路径", "ja": "パスをコピー", "es": "Copiar ruta", "fr": "Copier le chemin"]
    for (language, translation) in expected {
        #expect(L10n.text("复制路径", language: language) == translation)
        #expect(L10n.text("新建 %@", language: language).contains("%@"))
    }
}

@Test func localizationPreservesUserProvidedNames() {
    let customName = "My % folder 中文"
    let template = TemplateEntry(id: TemplateEntry.defaults[0].id, name: customName, fileExtension: "txt")
    #expect(template.displayName == customName)
    var config = Configuration()
    let application = ApplicationEntry(name: customName, url: URL(fileURLWithPath: "/Applications/Example.app"))
    config.applications = [application]
    let plan = MenuPlanner.plan(configuration: config, context: .init(selected: [], directory: URL(fileURLWithPath: "/sample")), isDirectory: { _ in true })
    #expect(plan.sections.flatMap(\.actions).first { $0.reference == .application(application.id) }?.title == customName)
}

@Test func localizedDynamicMessagesPreserveValuesAndDestructiveWarning() {
    let path = "/fixture/100% 中文.txt"
    for language in ["en", "zh-Hans", "ja", "es", "fr"] {
        let notice = L10n.format("目录：%@\n将显示直接包含的 %@ 个隐藏项目，不处理子目录内部。", path, "12", language: language)
        #expect(notice.contains(path))
        #expect(notice.contains("12"))
        #expect(!notice.contains("%@"))
        let warning = L10n.format("%@\n\n此操作不经过废纸篓，无法撤销。文件夹内的内容也会被删除。", "fixture.txt", language: language)
        #expect(warning.hasPrefix("fixture.txt\n\n"))
        #expect(warning.count > "fixture.txt\n\n".count)
    }
    #expect(L10n.format("已完成 %@ / %@ 项", "3", "5", language: "en") == "Completed 3 / 5 items")
}

@Test func releaseLinksAcceptPublicHTTPSAndRejectUnsafeOrUnsetValues() {
    let links = ReleaseLinks(gitHub: "https://github.com/example/project", updates: "https://example.com/releases", feedback: "https://example.com/issues")
    #expect(links.gitHub?.host == "github.com")
    #expect(links.updates?.path == "/releases")
    #expect(links.feedback?.path == "/issues")
    for input in ["", "$(CLICKPORT_GITHUB_URL)", "javascript:alert(1)", "file:///tmp/example", "http://example.com", "https://user:password@example.com", "https://example.com?token=value", "https://example.com/\npath"] {
        #expect(ReleaseLinks(gitHub: input).gitHub == nil)
    }
}

@Test func hidingSymbolicLinkDoesNotChangeDestinationFlags() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("destination.txt")
    let link = root.appendingPathComponent("shortcut.txt")
    try Data("preserved".utf8).write(to: destination)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    var original = stat()
    #expect(lstat(destination.path, &original) == 0)
    try FileOperations.setHidden(true, at: link)
    var target = stat()
    var shortcut = stat()
    #expect(lstat(destination.path, &target) == 0)
    #expect(lstat(link.path, &shortcut) == 0)
    #expect(target.st_flags == original.st_flags)
    #expect(shortcut.st_flags & UInt32(UF_HIDDEN) != 0)
    try FileOperations.setHidden(false, at: link)
    #expect(lstat(link.path, &shortcut) == 0)
    #expect(shortcut.st_flags & UInt32(UF_HIDDEN) == 0)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "preserved")
}

@Test func templateValidationRejectsSpecialPackageEntriesAndOversizedFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let package = root.appendingPathComponent("example.pages", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("fixture".utf8).write(to: package.appendingPathComponent("contents"))
    let pipe = package.appendingPathComponent("pending")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws: ConfigurationError.self) { try TemplateLibrary.validateSource(package, extension: "pages") }
    let oversized = root.appendingPathComponent("large.txt")
    #expect(FileManager.default.createFile(atPath: oversized.path, contents: nil))
    let handle = try FileHandle(forWritingTo: oversized)
    try handle.truncate(atOffset: 256 * 1024 * 1024 + 1)
    try handle.close()
    #expect(throws: ConfigurationError.self) { try TemplateLibrary.validateSource(oversized, extension: "txt") }
    #expect(throws: ConfigurationError.self) {
        try TemplateLibrary.validateSource(URL(string: "https://example.invalid/template.txt")!, extension: "txt")
    }
}

@Test func cancelledTemplateImportPreservesSourceAndCreatesNoSnapshot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.txt")
    try Data("preserved".utf8).write(to: source)
    let library = TemplateLibrary(root: root.appendingPathComponent("library"))
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await library.importTemplateAsync(from: source)
    }
    do {
        _ = try await task.value
        Issue.record("Cancelled import unexpectedly succeeded")
    } catch is CancellationError {} catch { throw error }
    #expect(!FileManager.default.fileExists(atPath: library.root.path))
    #expect(try String(contentsOf: source, encoding: .utf8) == "preserved")
    let imported = try await library.importTemplateAsync(from: source)
    #expect(try String(contentsOf: #require(imported.source), encoding: .utf8) == "preserved")
}

@Test func templatePackageRequiresReadableFileContents() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let package = root.appendingPathComponent("example.pages", isDirectory: true)
    let nested = package.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: nested.path)
        try? FileManager.default.removeItem(at: root)
    }
    #expect(throws: ConfigurationError.self) { try TemplateLibrary.validateSource(package, extension: "pages") }
    try Data("fixture".utf8).write(to: nested.appendingPathComponent("contents"))
    try TemplateLibrary.validateSource(package, extension: "pages")
    // Include a readable sibling, so partial traversal cannot look like a valid package.
    try Data("sibling".utf8).write(to: package.appendingPathComponent("readable"))
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: nested.path)
    #expect(throws: (any Error).self) { try TemplateLibrary.validateSource(package, extension: "pages") }
}

@Test func batchCooperativeCancellationStopsWithoutAddingFailure() async {
    let urls = ["completed", "cancelled", "must-not-run"].map { URL(fileURLWithPath: "/fixture/" + $0) }
    let result = await BatchOperation.run(urls) { url in
        if url.lastPathComponent == "cancelled" { throw CancellationError() }
        if url.lastPathComponent == "must-not-run" { Issue.record("Batch continued after cancellation") }
    }
    #expect(result.cancelled)
    #expect(result.completed == 1)
    #expect(result.attempted == 1)
    #expect(result.failures.isEmpty)
}

@Test func inboxRejectsPipesMismatchedIdentityAndOldSessionsBeforeValidRequest() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    let context = TargetContext(selected: [], directory: root)
    let pipe = root.appendingPathComponent("00000000-0000-0000-0000-000000000001.json")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    var mismatched = ActionRequest(action: .builtin(.copyPath), context: context)
    mismatched.createdAt = now
    try JSONEncoder().encode(mismatched).write(to: root.appendingPathComponent("00000000-0000-0000-0000-000000000002.json"))
    var oldSession = ActionRequest(action: .builtin(.copyPath), context: context)
    oldSession.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    oldSession.createdAt = now.addingTimeInterval(-1)
    try JSONEncoder().encode(oldSession).write(to: root.appendingPathComponent(oldSession.id.uuidString + ".json"))
    var valid = ActionRequest(action: .builtin(.copyPath), context: context)
    valid.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    valid.createdAt = now
    try JSONEncoder().encode(valid).write(to: root.appendingPathComponent(valid.id.uuidString + ".json"))
    let received = try RequestInbox(directory: root).takeNext(sessionStartedAt: now, now: now)
    #expect(received?.id == valid.id)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test func deletionTargetsDeduplicateAndOrderChildrenBeforeParents() throws {
    let parent = URL(fileURLWithPath: "/fixture/folder", isDirectory: true)
    let child = parent.appendingPathComponent("child.txt")
    let sibling = parent.appendingPathComponent("other.txt")
    let context = TargetContext(selected: [parent, child, sibling, child], directory: parent)
    #expect(try context.deletionTargets() == [child, sibling, parent])
    let root = TargetContext(selected: [URL(fileURLWithPath: "/")], directory: nil)
    #expect(throws: TargetError.self) { try root.deletionTargets() }
    let normalizedRoot = TargetContext(selected: [URL(fileURLWithPath: "/fixture/..")], directory: nil)
    #expect(throws: TargetError.self) { try normalizedRoot.deletionTargets() }
    let noSelection = TargetContext(selected: [], directory: parent)
    #expect(throws: TargetError.self) { try noSelection.deletionTargets() }
}

@Test func fileURLsRejectDiscardedAuthorityAndSuffixBeforeIO() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("literal # ? %20 中文.txt")
    try Data("preserve".utf8).write(to: file)
    #expect(file.isLocalFileURL)
    try TemplateLibrary.validateSource(file, extension: "txt")
    #expect(try TargetContext(selected: [file], directory: root).pathsForClipboard() == file.path)
    var localHost = URLComponents(url: file, resolvingAgainstBaseURL: true)!
    localHost.host = "localhost"
    #expect(localHost.url!.isLocalFileURL)
    let invalid = ["file://remote.invalid/tmp/example.txt", "file:///tmp/example.txt?query", "file:///tmp/example.txt#fragment", "file://user@localhost/tmp/example.txt", "file://localhost:99/tmp/example.txt", "file:///tmp/example%00.txt"]
    for value in invalid {
        let url = try #require(URL(string: value))
        #expect(url.isFileURL)
        #expect(!url.isLocalFileURL)
        #expect(!DirectoryScope.covers(url, within: URL(fileURLWithPath: "/")))
        #expect(throws: TargetError.self) { try TargetContext(selected: [url], directory: nil).pathsForClipboard() }
        var config = Configuration()
        config.directories = [.init(name: "Fixture", url: url)]
        #expect(throws: ConfigurationError.self) { try config.validated() }
    }
    var disguised = URLComponents(url: file, resolvingAgainstBaseURL: true)!
    disguised.host = "remote.invalid"
    let remoteFile = try #require(disguised.url)
    #expect(throws: TargetError.self) { try PrivateFile.write(Data("replace".utf8), to: remoteFile) }
    #expect(throws: ConfigurationError.self) { try FileOperations.setHidden(true, at: remoteFile) }
    #expect(throws: ConfigurationError.self) { try TemplateLibrary.validateSource(remoteFile, extension: "txt") }
    #expect(try String(contentsOf: file, encoding: .utf8) == "preserve")
    #expect(try file.resourceValues(forKeys: [.isHiddenKey]).isHidden != true)
    var remoteDirectory = URLComponents(url: root, resolvingAgainstBaseURL: true)!
    remoteDirectory.host = "remote.invalid"
    #expect(throws: ConfigurationError.self) {
        try FileOperations.create(template: .init(name: "Text", fileExtension: "txt"), in: remoteDirectory.url!)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [file.lastPathComponent])
}

@Test func asynchronousConfigurationReadPreservesDataAndHonorsCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("settings.json")
    let store = ConfigurationStore(url: file)
    var saved = Configuration()
    saved.showMenuBar = false
    saved.groups.reverse()
    try store.save(saved)
    let bytes = try Data(contentsOf: file)
    #expect(try await Configuration.readAsync(from: file) == saved)
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await Configuration.readAsync(from: file)
    }
    do {
        _ = try await cancelled.value
        Issue.record("Cancelled configuration read unexpectedly succeeded")
    } catch is CancellationError {
        // Cancellation is a distinct result, never a default configuration.
    }
    #expect(try Data(contentsOf: file) == bytes)
    let invalid = root.appendingPathComponent("invalid.json")
    try Data("{}".utf8).write(to: invalid)
    do {
        _ = try await Configuration.readAsync(from: invalid)
        Issue.record("Invalid configuration unexpectedly loaded")
    } catch is DecodingError {
        // A failed read cannot replace the existing configuration.
    }
    #expect(try store.load() == saved)
}

@Test func suspendedActionsRejectChangedDefinitionsButAllowUnrelatedPreferences() {
    var original = Configuration()
    let app = ApplicationEntry(name: "Editor", url: URL(fileURLWithPath: "/fixture/Editor.app"))
    let directory = DirectoryEntry(name: "Destination", url: URL(fileURLWithPath: "/fixture/original"))
    let template = TemplateEntry(name: "Document", fileExtension: "txt", source: URL(fileURLWithPath: "/fixture/source.txt"))
    original.applications = [app]
    original.directories = [directory]
    original.templates.append(template)
    let actions: [ActionReference] = [.application(app.id), .directory(directory.id), .template(template.id), .builtin(.hide)]
    var unrelated = original
    unrelated.showMenuBar.toggle()
    unrelated.groups.reverse()
    unrelated.shortcuts = []
    for action in actions {
        #expect(unrelated.hasSameEnabledAction(action, as: original))
    }
    var changed = original
    changed.directories[0].url = URL(fileURLWithPath: "/fixture/outside-authorized-directory")
    #expect(!changed.hasSameEnabledAction(.directory(directory.id), as: original))
    changed = original
    changed.applications[0].url = URL(fileURLWithPath: "/fixture/Other.app")
    #expect(!changed.hasSameEnabledAction(.application(app.id), as: original))
    changed = original
    changed.applications[0].arguments = ["--different-mode"]
    #expect(!changed.hasSameEnabledAction(.application(app.id), as: original))
    changed = original
    changed.applications[0].environment = ["MODE": "different"]
    #expect(!changed.hasSameEnabledAction(.application(app.id), as: original))
    changed = original
    changed.templates[changed.templates.count - 1].source = URL(fileURLWithPath: "/fixture/replaced.txt")
    #expect(!changed.hasSameEnabledAction(.template(template.id), as: original))
    changed = original
    changed.enabledActions.remove(.hide)
    changed.applications[0].enabled = false
    changed.directories.removeAll()
    changed.templates.removeAll { $0.id == template.id }
    for action in actions {
        #expect(!changed.hasSameEnabledAction(action, as: original))
    }
    #expect(!original.hasSameEnabledAction(.application(UUID()), as: original))
}

@Test func menuEntriesShareOneFileTypeSnapshot() {
    var config = Configuration()
    config.shortcuts = [.builtin(.copyPath), .builtin(.airDrop)]
    let item = URL(fileURLWithPath: "/fixture/changing-item")
    var reads = 0
    let plan = MenuPlanner.plan(configuration: config, context: .init(selected: [item], directory: nil)) { _ in
        reads += 1
        // A later filesystem observation could differ after a replacement.
        return reads == 1
    }
    #expect(reads == 1)
    let all = plan.shortcuts + plan.sections.flatMap(\.actions)
    let copyEntries = all.filter { $0.reference == .builtin(.copyPath) }
    #expect(copyEntries.count == 2)
    #expect(Set(copyEntries.map(\.title)).count == 1)
    let sharingEntries = all.filter { $0.reference == .builtin(.airDrop) }
    #expect(sharingEntries.count == 2)
    #expect(sharingEntries.allSatisfy { !$0.enabled })

    let selected = (0..<1000).map { URL(fileURLWithPath: "/fixture/file-\($0).txt") }
    var calls: [URL: Int] = [:]
    let largePlan = MenuPlanner.plan(configuration: config, context: .init(selected: selected, directory: nil)) { url in
        calls[url, default: 0] += 1
        return false
    }
    #expect(calls.count == selected.count)
    #expect(calls.values.allSatisfy { $0 == 1 })
    #expect(largePlan.shortcuts.first { $0.reference == .builtin(.airDrop) }?.enabled == true)
}

@Test func launchRequestPreservesTypedValuesAndRejectsTampering() throws {
    let entry = ApplicationEntry(name: "Fixture", url: URL(fileURLWithPath: "/Applications/Fixture.app"),
                                 arguments: ["", "two words", "中文", "$(literal)"], environment: ["VALUE": "a=b 中文"], newInstance: true)
    let request = try LaunchRequest(entry: entry, targets: [URL(fileURLWithPath: "/tmp/中文 %20.txt")])
    let decoded = try LaunchRequest.decode(JSONEncoder().encode(request))
    #expect(decoded.entry == entry)
    #expect(decoded.targets == request.targets)
    var modified = request
    modified.entry.arguments.append("extra")
    #expect(throws: (any Error).self) { try modified.validated() }
    modified = request; modified.createdAt = Date().addingTimeInterval(-31)
    #expect(throws: (any Error).self) { try modified.validated() }
    modified = request; modified.targets = [URL(string: "file://remote/test")!]
    #expect(throws: (any Error).self) { try modified.validated() }
    #expect(throws: (any Error).self) { try LaunchRequest.decode(Data(repeating: 0, count: LaunchRequest.maximumBytes + 1)) }
}

@Test func launchRequestRejectsDisabledAndOversizedConfiguration() throws {
    var entry = ApplicationEntry(name: "Fixture", url: URL(fileURLWithPath: "/Applications/Fixture.app"), enabled: false)
    let targets = [URL(fileURLWithPath: "/tmp/test.txt")]
    #expect(throws: (any Error).self) { try LaunchRequest(entry: entry, targets: targets).validated() }
    entry.enabled = true; entry.arguments = Array(repeating: "a", count: 257)
    #expect(throws: (any Error).self) { try LaunchRequest(entry: entry, targets: targets).validated() }
    entry.arguments = [String(repeating: "a", count: LaunchRequest.maximumBytes)]
    #expect(throws: (any Error).self) { try LaunchRequest(entry: entry, targets: targets).validated() }
    entry.arguments = []
    #expect(throws: (any Error).self) { try LaunchRequest(entry: entry, targets: []).validated() }
}
