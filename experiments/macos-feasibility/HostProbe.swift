import AppKit
@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Clickport Feasibility Probe"
        let label = NSTextField(wrappingLabelWithString: "Local Finder extension probe. Enable the extension in System Settings, then inspect the probe folder. No file operations are performed.")
        label.frame = NSRect(x: 24, y: 40, width: 392, height: 110)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
