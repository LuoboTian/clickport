import SwiftUI
import AppKit
import ClickportCore

@main
struct ClickportApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var model = AppModel()
    var body: some Scene {
        Window("Clickport 设置", id: "settings") {
            SettingsScene(model: model, lifecycle: lifecycle)
        }
        .defaultSize(width: 860, height: 620)
        .commands { CommandGroup(replacing: .appSettings) { OpenSettingsButton() } }
        MenuBarExtra("Clickport", systemImage: model.processing ? "hourglass" : "cursorarrow.click", isInserted: Binding(
            get: { model.configuration.showMenuBar },
            set: { value in var next = model.configuration; next.showMenuBar = value; model.save(next) }
        )) {
            Text(L10n.text(model.extensionEnabled ? "Finder 扩展：已启用" : "Finder 扩展：未启用"))
            if model.processing { Text(model.progressMessage) }
            Divider()
            OpenSettingsButton()
            Divider()
            Button("退出 Clickport") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("设置…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut(",")
    }
}
