import AppKit
import SwiftUI

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    var showSettings: (() -> Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings?()
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

struct SettingsScene: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel
    let lifecycle: AppLifecycle
    var body: some View {
        SettingsRoot(model: model)
            .onAppear { lifecycle.showSettings = { openWindow(id: "settings") } }
    }
}
