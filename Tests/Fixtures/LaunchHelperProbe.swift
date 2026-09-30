import AppKit
import ClickportCore

@MainActor final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let client = LaunchHelperClient()
    let status = NSTextField(wrappingLabelWithString: "Ready: run a new instance, then reuse it. Receiver shows the delivered values.")
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Launch Helper Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let root = NSMenu(); let item = NSMenuItem(); item.submenu = appMenu; root.addItem(item); NSApp.mainMenu = root
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Clickport Launch Helper Probe"
        let fresh = NSButton(title: "Launch new receiver", target: self, action: #selector(runNew))
        fresh.frame = NSRect(x: 20, y: 145, width: 250, height: 35)
        let reuse = NSButton(title: "Reuse receiver", target: self, action: #selector(runExisting))
        reuse.frame = NSRect(x: 280, y: 145, width: 230, height: 35)
        status.frame = NSRect(x: 20, y: 20, width: 600, height: 115)
        for view in [fresh, reuse, status] { window.contentView?.addSubview(view) }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func runNew() { run(newInstance: true) }
    @objc func runExisting() { run(newInstance: false) }
    func run(newInstance: Bool) {
        let resources = Bundle.main.resourceURL!
        let entry = ApplicationEntry(name: "Probe receiver", url: resources.appendingPathComponent("LaunchReceiver.app"), arguments: ["--probe", "two words", "中文", "", "literal%20"], environment: ["CLICKPORT_TEST_VALUE": "value 中文 %20"], newInstance: newInstance)
        let targets = ["alpha.txt", "two words.txt", "中文%20.txt"].map { resources.appendingPathComponent($0) }
        status.stringValue = "Waiting for authenticated XPC launch…"
        Task {
            do {
                let reused = try await client.open(targets, with: entry)
                status.stringValue = "SUCCESS — reused process: \(reused). Verify receiver values separately."
            } catch { status.stringValue = "FAILED — \(error)" }
        }
    }
}
@main struct ProbeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate(); app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
