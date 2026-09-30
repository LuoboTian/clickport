import AppKit
import FinderSync
import ClickportCore

@objc(ClickportFinderExtension)
final class ClickportFinderExtension: FIFinderSync {
    private var requestsByTag: [Int: ActionRequest] = [:]
    private var nextTag = 1
    override init() {
        super.init()
        // Observing a root only requests Finder callbacks; it does not grant file access or scan contents.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return nil }
        requestsByTag.removeAll(keepingCapacity: true)
        let menu = NSMenu(title: "Clickport")
        menu.autoenablesItems = false
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "org.clickport.app").isEmpty else {
            let item = menu.addItem(withTitle: L10n.text("打开 Clickport 以使用右键操作…"), action: #selector(openHost), keyEquivalent: "")
            item.target = self
            return menu
        }
        do {
            let config = try SharedContainer.store().load()
            let controller = FIFinderSyncController.default()
            let target = controller.targetedURL()
            let selection = menuKind == .contextualMenuForContainer ? [] : (controller.selectedItemURLs() ?? [])
            let context = TargetContext.captured(containerMenu: menuKind == .contextualMenuForContainer, target: target, selection: selection)
            let plan = MenuPlanner.plan(configuration: config, context: context) { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
            func append(_ action: MenuAction, to parent: NSMenu) {
                let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self; item.isEnabled = action.enabled
                // Finder recreates menu items across the extension boundary. Keep the
                // captured context locally rather than relying on representedObject.
                item.tag = nextTag
                nextTag = nextTag == Int.max ? 1 : nextTag + 1
                requestsByTag[item.tag] = ActionRequest(action: action.reference, context: context)
                parent.addItem(item)
            }
            for action in plan.shortcuts { append(action, to: menu) }
            // Finder serializes extension separators as blank rows on some macOS versions.
            // Keep shortcuts and submenu entries contiguous.
            for section in plan.sections where !section.actions.isEmpty {
                let titles: [MenuGroup: String] = [.applications: "打开方式", .templates: "新建文件", .operations: "文件操作", .directories: "目录快捷入口"]
                let child = NSMenu(title: L10n.text(titles[section.group] ?? "Clickport")); child.autoenablesItems = false
                for action in section.actions { append(action, to: child) }
                let item = NSMenuItem(title: child.title, action: nil, keyEquivalent: "")
                item.submenu = child; menu.addItem(item)
            }
        } catch {
            let item = NSMenuItem(title: L10n.text("配置不可用，请打开 Clickport 检查…"), action: #selector(openHost), keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        return menu
    }
    @objc private func performAction(_ sender: NSMenuItem) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "org.clickport.app").isEmpty else {
            openHost()
            return
        }
        guard var request = requestsByTag.removeValue(forKey: sender.tag) else { return }
        request.createdAt = Date()
        do { try SharedContainer.submit(request) }
        catch { openHost() }
    }
    @objc private func openHost() {
        // Embedded extension: .app/Contents/PlugIns/extension.appex
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.openApplication(at: host, configuration: .init())
    }
}
