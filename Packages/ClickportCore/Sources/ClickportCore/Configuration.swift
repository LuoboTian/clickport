import Foundation
import Darwin

public enum MenuGroup: String, Codable, CaseIterable, Sendable {
    case applications, templates, operations, directories
}
public enum BuiltinAction: String, Codable, CaseIterable, Sendable {
    case copyPath, hide, unhide, unhideChildren, airDrop, deletePermanently
}
public enum ActionReference: Codable, Hashable, Sendable {
    case builtin(BuiltinAction)
    case application(UUID)
    case template(UUID)
    case directory(UUID)
}
public struct ApplicationEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var enabled: Bool
    public var arguments: [String]
    public var environment: [String: String]
    public var newInstance: Bool
    public init(id: UUID = UUID(), name: String, url: URL, enabled: Bool = true,
                arguments: [String] = [], environment: [String: String] = [:], newInstance: Bool = false) {
        self.id = id; self.name = name; self.url = url; self.enabled = enabled
        self.arguments = arguments; self.environment = environment; self.newInstance = newInstance
    }
}
public struct DirectoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var enabled: Bool
    public init(id: UUID = UUID(), name: String, url: URL, enabled: Bool = true) {
        self.id = id; self.name = name; self.url = url; self.enabled = enabled
    }
}
public struct TemplateEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var fileExtension: String
    public var source: URL?
    public var enabled: Bool
    public init(id: UUID = UUID(), name: String, fileExtension: String, source: URL? = nil, enabled: Bool = true) {
        self.id = id; self.name = name; self.fileExtension = fileExtension; self.source = source; self.enabled = enabled
    }
    public var displayName: String {
        if let original = Self.defaults.first(where: { $0.id == id }), original.name == name { return L10n.text(name) }
        return name
    }
    public static let defaults: [Self] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "纯文本", fileExtension: "txt"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Markdown", fileExtension: "md"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "JSON", fileExtension: "json")
    ]
}
public struct Configuration: Codable, Equatable, Sendable {
    public static let maximumBytes = 4 * 1024 * 1024
    public var schemaVersion = 1
    public var showMenuBar = true
    public var applications: [ApplicationEntry] = []
    public var directories: [DirectoryEntry] = []
    public var templates = TemplateEntry.defaults
    public var enabledActions: Set<BuiltinAction> = [.copyPath, .hide, .unhide, .unhideChildren, .airDrop]
    public var groups = MenuGroup.allCases
    public var shortcuts: [ActionReference] = [.builtin(.copyPath)]
    public init() {}

    /// Commit an asynchronous import without resurrecting removed entries or
    /// overwriting names and enabled states edited while its copy was running.
    public mutating func applyImportedTemplate(_ imported: TemplateEntry, replacing original: TemplateEntry?) -> Bool {
        guard let original else {
            guard !templates.contains(where: { $0.id == imported.id }) else { return false }
            templates.append(imported)
            return true
        }
        guard imported.id == original.id,
              let index = templates.firstIndex(where: { $0.id == original.id }),
              templates[index].source == original.source,
              templates[index].fileExtension == original.fileExtension else { return false }
        var replacement = imported
        replacement.name = templates[index].name
        replacement.enabled = templates[index].enabled
        templates[index] = replacement
        return true
    }

    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw ConfigurationError.invalid("schemaVersion") }
        guard groups.count == MenuGroup.allCases.count, Set(groups).count == groups.count else {
            throw ConfigurationError.invalid("groups")
        }
        guard shortcuts.count <= 5, Set(shortcuts).count == shortcuts.count,
              !shortcuts.contains(.builtin(.deletePermanently)) else { throw ConfigurationError.invalid("shortcuts") }
        guard Set(applications.map(\.id)).count == applications.count,
              Set(directories.map(\.id)).count == directories.count,
              Set(templates.map(\.id)).count == templates.count else { throw ConfigurationError.invalid("duplicate id") }
        for (index, app) in applications.enumerated() {
            guard !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  app.url.isLocalFileURL, app.url.pathExtension == "app",
                  app.environment.allSatisfy({ !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.contains("\0") && !$0.value.contains("\0") }),
                  app.arguments.allSatisfy({ !$0.contains("\0") }) else { throw ConfigurationError.invalid("applications[\(index)]") }
        }
        for (index, directory) in directories.enumerated() {
            guard directory.url.isLocalFileURL, !directory.name.isEmpty else { throw ConfigurationError.invalid("directories[\(index)]") }
        }
        for (index, template) in templates.enumerated() {
            guard !template.name.isEmpty, TemplateLibrary.supportedExtensions.contains(template.fileExtension),
                  template.source?.isLocalFileURL != false,
                  template.source != nil || ["txt", "md", "json"].contains(template.fileExtension) else {
                throw ConfigurationError.invalid("templates[\(index)]")
            }
        }
        for (index, action) in shortcuts.enumerated() {
            let exists: Bool
            switch action {
            case .builtin: exists = true
            case .application(let id): exists = applications.contains { $0.id == id }
            case .directory(let id): exists = directories.contains { $0.id == id }
            case .template(let id): exists = templates.contains { $0.id == id }
            }
            guard exists else { throw ConfigurationError.invalid("shortcuts[\(index)]") }
        }
        return self
    }
    /// Portable export deliberately excludes environment values and authorization bookmarks.
    public func exportData() throws -> Data {
        var portable = try validated()
        for index in portable.applications.indices { portable.applications[index].environment = [:] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(portable)
        try Self.validateSize(data.count)
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        try validateSize(data.count)
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    public static func readAsync(from url: URL) async throws -> Self {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let configuration = try read(from: url)
            try Task.checkCancellation()
            return configuration
        }
        return try await withTaskCancellationHandler {
            let configuration = try await worker.value
            try Task.checkCancellation()
            return configuration
        } onCancel: {
            worker.cancel()
        }
    }
    public static func read(from url: URL) throws -> Self {
        guard url.isLocalFileURL else { throw ConfigurationError.invalid("请选择普通配置文件") }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
            throw ConfigurationError.invalid("请选择普通配置文件")
        }
        try validateSize(Int(info.st_size))
        // One extra byte detects growth after fstat without an unbounded read.
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try decode(data)
    }
    static func validateSize(_ count: Int) throws {
        guard count <= maximumBytes else { throw ConfigurationError.invalid("配置文件不能超过 4 MB") }
    }
}
public enum ConfigurationError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let node): return L10n.format("配置无效：%@", L10n.text(node)) }
    }
}
