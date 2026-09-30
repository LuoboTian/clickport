import Foundation

/// Captured at menu creation; never falls back to a later Finder selection.
public struct TargetContext: Sendable, Equatable, Codable {
    public let selected: [URL]
    public let directory: URL?
    public init(selected: [URL], directory: URL?) {
        self.selected = selected; self.directory = directory
    }
    public static func captured(containerMenu: Bool, target: URL?, selection: [URL]) -> Self {
        if containerMenu { return Self(selected: [], directory: target) }
        let items = selection.isEmpty ? target.map { [$0] } ?? [] : selection
        let parents = Set(items.map { $0.deletingLastPathComponent().standardizedFileURL })
        let directory: URL?
        if let target, items.contains(where: { $0.standardizedFileURL == target.standardizedFileURL }), parents.count == 1 {
            directory = target.deletingLastPathComponent()
        } else if let target, parents.count == 1, parents.contains(target.standardizedFileURL) {
            directory = target
        } else {
            // Search results may span directories. Do not invent a current directory for bulk actions.
            directory = nil
        }
        return Self(selected: items, directory: directory)
    }
    public var pathTargets: [URL] { selected.isEmpty ? directory.map { [$0] } ?? [] : selected }
    public func pathsForClipboard() throws -> String {
        guard !pathTargets.isEmpty else { throw TargetError.noTarget }
        guard pathTargets.allSatisfy(\.isLocalFileURL) else { throw TargetError.notFileURL }
        // Newlines in a filename cannot be represented unambiguously in a newline-delimited list.
        guard !pathTargets.contains(where: { $0.path.contains("\n") || $0.path.contains("\r") }) else {
            throw TargetError.ambiguousPath
        }
        return pathTargets.map(\.path).joined(separator: "\n")
    }
    public func creationDirectory(isDirectory: (URL) throws -> Bool) throws -> URL {
        if selected.count > 1 { throw TargetError.chooseDirectory }
        if let item = selected.first {
            guard item.isLocalFileURL else { throw TargetError.notFileURL }
            return try isDirectory(item) ? item : item.deletingLastPathComponent()
        }
        guard let directory, directory.isLocalFileURL else { throw TargetError.noTarget }
        return directory
    }
    public func deletionTargets() throws -> [URL] {
        guard !selected.isEmpty else { throw TargetError.noTarget }
        guard selected.allSatisfy({ $0.isLocalFileURL && $0.standardizedFileURL.path != "/" }) else { throw TargetError.notFileURL }
        var seen = Set<URL>()
        let unique = selected.filter { seen.insert($0).inserted }
        // Search results can contain both a directory and one of its descendants.
        // Process explicitly selected children first, without changing their URLs.
        return unique.enumerated().sorted { left, right in
            let leftDepth = left.element.pathComponents.count
            let rightDepth = right.element.pathComponents.count
            return leftDepth == rightDepth ? left.offset < right.offset : leftDepth > rightDepth
        }.map(\.element)
    }
}
public enum TargetError: Error, LocalizedError {
    case noTarget, notFileURL, chooseDirectory, ambiguousPath
    public var errorDescription: String? {
        switch self {
        case .noTarget: L10n.text("没有可用的操作目标。")
        case .notFileURL: L10n.text("不支持此目标。")
        case .chooseDirectory: L10n.text("已选择多个项目，请明确选择一个新建目录。")
        case .ambiguousPath: L10n.text("文件名含换行符，无法安全地按行复制路径。请先调整文件名。")
        }
    }
}
