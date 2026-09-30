import Foundation

/// Keeps unsaved menu edits separate from immediately saved source settings.
public struct MenuCustomization: Equatable, Sendable {
    public var groups: [MenuGroup]
    public var shortcuts: [ActionReference]
    public init(configuration: Configuration = Configuration()) {
        groups = configuration.groups
        shortcuts = configuration.shortcuts
    }
    public mutating func reconcile(with configuration: Configuration) {
        shortcuts.removeAll { !configuration.contains($0) }
    }
    public func applying(to configuration: Configuration) throws -> Configuration {
        var result = configuration
        result.groups = groups
        result.shortcuts = shortcuts.filter { configuration.contains($0) }
        return try result.validated()
    }
}

extension Configuration {
    public func contains(_ reference: ActionReference) -> Bool {
        switch reference {
        case .builtin: true
        case .application(let id): applications.contains { $0.id == id }
        case .directory(let id): directories.contains { $0.id == id }
        case .template(let id): templates.contains { $0.id == id }
        }
    }
    public func isEnabled(_ reference: ActionReference) -> Bool {
        switch reference {
        case .builtin(let action): enabledActions.contains(action)
        case .application(let id): applications.contains { $0.id == id && $0.enabled }
        case .directory(let id): directories.contains { $0.id == id && $0.enabled }
        case .template(let id): templates.contains { $0.id == id && $0.enabled }
        }
    }
}
