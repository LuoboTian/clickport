import AppKit
import FinderSync
@objc(ClickportProbeExtension)
final class ClickportProbeExtension: FIFinderSync {
    override init() {
        super.init()
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("clickport-finder-fixture", isDirectory: true)
        FIFinderSyncController.default().directoryURLs = [root]
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let count = controller.selectedItemURLs()?.count ?? 0
        let hasTarget = controller.targetedURL() != nil
        let menu = NSMenu(title: "Clickport probe")
        menu.addItem(withTitle: "Probe: selected \(count), target \(hasTarget)", action: nil, keyEquivalent: "")
        return menu
    }
}
