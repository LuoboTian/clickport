import AppKit

/// FR-01 / FR-02 manual integration fixture. Never included in the product.
@MainActor
final class LaunchReceiver: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var received: [String] = []
    private let startedAt = Date()
    private let label = NSTextField(wrappingLabelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Launch Receiver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApplication.shared.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 300),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Clickport Launch Receiver"
        label.frame = NSRect(x: 20, y: 20, width: 610, height: 260)
        label.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        record()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        received.append(contentsOf: urls.map(\.path))
        record()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func record() {
        let process = ProcessInfo.processInfo
        let arguments = Array(process.arguments.dropFirst())
        let environmentValue = process.environment["CLICKPORT_TEST_VALUE"] ?? ""
        let payload: [String: Any] = [
            "processID": process.processIdentifier,
            "startedAt": startedAt.timeIntervalSince1970,
            "arguments": arguments,
            "testEnvironment": environmentValue,
            "receivedURLs": received
        ]
        let output = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("receiver-\(process.processIdentifier).json")
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output, options: .atomic)
            label.stringValue = "Integration test receiver\nProcess: \(process.processIdentifier)\nReceived URLs: \(received.count)\nArguments: \(arguments)\nTest environment: \(environmentValue)"
        } catch {
            label.stringValue = "Fixture could not write its local result: \(error.localizedDescription)"
        }
    }
}

@main
struct ReceiverMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = LaunchReceiver()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
