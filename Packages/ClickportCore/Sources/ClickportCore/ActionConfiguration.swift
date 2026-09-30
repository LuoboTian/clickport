import Foundation

extension Configuration {
    /// Recheck the selected action after suspended work or a modal permission panel.
    /// Unrelated preferences and menu ordering do not invalidate an action.
    public func hasSameEnabledAction(_ action: ActionReference, as previous: Configuration) -> Bool {
        guard isEnabled(action), previous.isEnabled(action) else { return false }
        switch action {
        case .builtin:
            return true
        case .application(let id):
            return applications.first { $0.id == id } == previous.applications.first { $0.id == id }
        case .directory(let id):
            return directories.first { $0.id == id } == previous.directories.first { $0.id == id }
        case .template(let id):
            return templates.first { $0.id == id } == previous.templates.first { $0.id == id }
        }
    }
}
