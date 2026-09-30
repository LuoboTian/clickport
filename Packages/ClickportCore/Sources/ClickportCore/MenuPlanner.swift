import Foundation

public struct MenuAction: Sendable, Equatable {
    public var title: String
    public var reference: ActionReference
    public var enabled: Bool
}
public struct MenuSection: Sendable, Equatable {
    public var group: MenuGroup
    public var actions: [MenuAction]
}
public struct MenuPlan: Sendable {
    public var shortcuts: [MenuAction]
    public var sections: [MenuSection]
}
public enum MenuPlanner {
    public static func plan(configuration: Configuration, context: TargetContext,
                            isDirectory: (URL) -> Bool) -> MenuPlan {
        // A shortcut and its grouped entry share one metadata snapshot. Avoid
        // repeated filesystem reads, especially for selections on slow volumes.
        var directoryTypes: [URL: Bool] = [:]
        func directoryType(_ url: URL) -> Bool {
            if let cached = directoryTypes[url] { return cached }
            let value = isDirectory(url)
            directoryTypes[url] = value
            return value
        }
        func action(_ ref: ActionReference) -> MenuAction? {
            switch ref {
            case .builtin(let builtin):
                guard configuration.enabledActions.contains(builtin) else { return nil }
                let selected = !context.selected.isEmpty
                let hasDirectory = context.directory != nil
                let title: String
                let enabled: Bool
                switch builtin {
                case .copyPath:
                    if context.selected.count > 1 { title = L10n.text("复制所选项路径") }
                    else if let item = context.selected.first { title = directoryType(item) ? L10n.text("复制文件夹路径") : L10n.text("复制文件路径") }
                    else { title = context.directory?.lastPathComponent == "Desktop" ? L10n.text("复制桌面路径") : L10n.text("复制当前文件夹路径") }
                    enabled = !context.pathTargets.isEmpty
                case .hide: title = L10n.text("隐藏选中项"); enabled = selected
                case .unhide: title = L10n.text("取消隐藏选中项"); enabled = selected
                case .unhideChildren: title = L10n.text("取消隐藏当前目录直接子项…"); enabled = hasDirectory
                case .airDrop: title = "AirDrop…"; enabled = selected && !context.selected.contains(where: directoryType)
                case .deletePermanently: title = L10n.text("直接删除…"); enabled = selected
                }
                if builtin == .deletePermanently && !selected { return nil }
                return MenuAction(title: title, reference: ref, enabled: enabled)
            case .application(let id):
                guard let entry = configuration.applications.first(where: { $0.id == id && $0.enabled }) else { return nil }
                return MenuAction(title: entry.name, reference: ref, enabled: !context.pathTargets.isEmpty)
            case .directory(let id):
                guard let entry = configuration.directories.first(where: { $0.id == id && $0.enabled }) else { return nil }
                return MenuAction(title: entry.name, reference: ref, enabled: true)
            case .template(let id):
                guard let entry = configuration.templates.first(where: { $0.id == id && $0.enabled }) else { return nil }
                return MenuAction(title: L10n.newFile(entry.displayName), reference: ref, enabled: !context.pathTargets.isEmpty)
            }
        }
        let sections = configuration.groups.map { group -> MenuSection in
            let refs: [ActionReference]
            switch group {
            case .applications: refs = configuration.applications.map { .application($0.id) }
            case .templates: refs = configuration.templates.map { .template($0.id) }
            case .operations: refs = BuiltinAction.allCases.map { .builtin($0) }
            case .directories: refs = configuration.directories.map { .directory($0.id) }
            }
            return MenuSection(group: group, actions: refs.compactMap(action))
        }
        return MenuPlan(shortcuts: configuration.shortcuts.compactMap(action), sections: sections)
    }
}
public struct ActionRequest: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var action: ActionReference
    public var context: TargetContext
    public init(action: ActionReference, context: TargetContext) {
        id = UUID(); createdAt = Date(); self.action = action; self.context = context
    }
    public func validate(now: Date = Date(), sessionStartedAt: Date? = nil) throws {
        guard now.timeIntervalSince(createdAt) >= -5, now.timeIntervalSince(createdAt) < 120,
              sessionStartedAt.map({ createdAt >= $0 }) ?? true,
              context.selected.count <= 10000,
              context.directory?.isLocalFileURL != false,
              context.pathTargets.allSatisfy(\.isLocalFileURL), !context.pathTargets.isEmpty || isDirectoryAction else {
            throw ConfigurationError.invalid("actionRequest")
        }
    }
    private var isDirectoryAction: Bool { if case .directory = action { return true }; return false }
}
