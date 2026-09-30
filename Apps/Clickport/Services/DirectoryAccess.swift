import AppKit
import Observation
import ClickportCore

@MainActor @Observable
final class DirectoryAccess {
    struct Grant: Codable, Identifiable {
        var id: UUID
        var displayPath: String
        var bookmark: Data
    }
    private(set) var grants: [Grant] = []
    private let storage: URL
    private(set) var loadError: String?

    init() {
        storage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clickport/authorizations.json")
        do {
            if FileManager.default.fileExists(atPath: storage.path) {
                grants = try JSONDecoder().decode([Grant].self, from: Data(contentsOf: storage))
            }
        } catch { loadError = L10n.text("授权记录无法读取，请重新选择所需目录。") }
    }
    func revoke(_ grant: Grant) throws {
        let next = grants.filter { $0.id != grant.id }
        try persist(next)
    }
    @discardableResult
    func chooseDirectory(for target: URL? = nil) throws -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("允许访问")
        panel.message = target.map { L10n.format("请允许访问包含此目标的目录：%@", $0.path) } ?? L10n.text("选择允许 Clickport 执行文件操作的目录，可在设置中撤销。")
        if let target {
            let isDirectory = (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            panel.directoryURL = isDirectory ? target : target.deletingLastPathComponent()
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let target, !DirectoryScope.covers(target, within: url) {
            throw ConfigurationError.invalid(L10n.text("所选目录不包含操作目标"))
        }
        return try rememberSelectedDirectory(url)
    }
    /// Only call with a directory explicitly returned by an NSOpenPanel. A file
    /// URL from an imported configuration or an extension request is not consent.
    @discardableResult
    func rememberSelectedDirectory(_ url: URL) throws -> URL {
        guard url.isLocalFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ConfigurationError.invalid(L10n.text("请选择可访问的目录"))
        }
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        var next = grants.filter { $0.displayPath != url.path }
        next.append(.init(id: UUID(), displayPath: url.path, bookmark: bookmark))
        try persist(next)
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
    /// The caller must balance every returned URL with stopAccessingSecurityScopedResource().
    func beginAccess(to targets: [URL], requestIfNeeded: Bool = true) throws -> [URL] {
        var leases: [URL] = []
        do {
            for target in targets {
                if leases.contains(where: { DirectoryScope.covers(target, within: $0) }) { continue }
                var acquired = false
                for grant in grants {
                    var stale = false
                    guard let root = try? URL(resolvingBookmarkData: grant.bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
                          !stale, root.startAccessingSecurityScopedResource() else { continue }
                    if DirectoryScope.covers(target, within: root) {
                        leases.append(root); acquired = true; break
                    }
                    root.stopAccessingSecurityScopedResource()
                }
                if !acquired {
                    guard requestIfNeeded else { throw CancellationError() }
                    guard let root = try chooseDirectory(for: target) else { throw CancellationError() }
                    guard root.startAccessingSecurityScopedResource() else { throw ConfigurationError.invalid(L10n.text("目录授权不可用，请重新选择")) }
                    leases.append(root)
                }
            }
            return leases
        } catch {
            for root in leases { root.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    private func persist(_ next: [Grant]) throws {
        try PrivateFile.write(JSONEncoder().encode(next), to: storage)
        grants = next
        loadError = nil
    }
}
