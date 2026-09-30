// Compile-only API probe. It does not register or enable an extension.
import AppKit
import FinderSync
import SwiftUI

struct ProbeSettings: View {
    var body: some View { Form { Text("Settings probe") } }
}

@MainActor
final class ProbeExtension: FIFinderSync {
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        let selection = controller.selectedItemURLs() ?? []
        let menu = NSMenu(title: "Probe")
        menu.addItem(withTitle: "Selection: \(selection.count), target: \(target != nil)", action: nil, keyEquivalent: "")
        return menu
    }
}

@MainActor
func configureLaunch() -> NSWorkspace.OpenConfiguration {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--example"]
    configuration.environment = ["PROBE_MODE": "1"]
    configuration.createsNewApplicationInstance = true
    return configuration
}
