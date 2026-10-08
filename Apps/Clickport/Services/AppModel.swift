import AppKit
import SwiftUI
import FinderSync
import ServiceManagement
import ClickportCore

@MainActor @Observable
final class AppModel {
    var configuration = Configuration()
    let directoryAccess = DirectoryAccess()
    var diagnostics = DiagnosticLog()
    private(set) var operationFailures: [BatchResult.Failure] = []
    var errorMessage: String? {
        didSet { if errorMessage != nil { diagnostics.record(.errorPresented) } }
    }
    var extensionEnabled = false
    private(set) var loginStatus = SMAppService.mainApp.status
    var resultMessage = "" {
        didSet { if !resultMessage.isEmpty { diagnostics.record(.operationStatusChanged) } }
    }
    private var timer: Timer?
    private var polling = false
    private var pendingRequest: ActionRequest?
    private var store: ConfigurationStore?
    private var hostLock: HostLock?
    private var configurationReady = false
    private(set) var processing = false
    private(set) var progressMessage = ""
    private var actionTask: Task<Void, Never>?
    private let systemActions = SystemActions()
    private let sessionStartedAt = Date()
    init() {
        diagnostics.record(.applicationStarted)
        do {
            hostLock = try HostLock(root: SharedContainer.root())
            let store = try SharedContainer.store()
            self.store = store
            configuration = try store.load()
            if configuration.provisionDefaultApplications() { try store.save(configuration) }
            configurationReady = true
        } catch { errorMessage = error.localizedDescription }
        guard hostLock != nil else { return }
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }
    @discardableResult
    func save(_ candidate: Configuration) -> Bool {
        do {
            guard let store else { throw ConfigurationError.invalid(L10n.text("共享容器不可用")) }
            try store.save(candidate)
            configuration = candidate
            configurationReady = true
            diagnostics.record(.configurationSaved)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func importConfiguration(from url: URL, onSuccess: @escaping @MainActor () -> Void) {
        guard !processing else { errorMessage = L10n.text("请等待当前操作完成"); return }
        let original = configuration
        processing = true
        resultMessage = ""
        operationFailures = []
        progressMessage = L10n.text("正在导入配置…")
        // Keep the panel-selected URL's scope alive throughout the background read.
        let scoped = url.startAccessingSecurityScopedResource()
        actionTask = Task {
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
                processing = false; progressMessage = ""; actionTask = nil
            }
            do {
                let candidate = try await Configuration.readAsync(from: url)
                try Task.checkCancellation()
                guard configuration == original else {
                    throw ConfigurationError.invalid(L10n.text("读取期间设置已更改，请重新导入配置"))
                }
                if save(candidate) {
                    resultMessage = L10n.text("配置已导入")
                    onSuccess()
                }
            } catch is CancellationError {
                resultMessage = L10n.text("已取消导入")
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func importTemplate(from url: URL, replacing existing: TemplateEntry? = nil) {
        guard !processing else { errorMessage = L10n.text("请等待当前操作完成"); return }
        processing = true
        progressMessage = L10n.text("正在导入模板…")
        actionTask = Task {
            defer { processing = false; progressMessage = ""; actionTask = nil }
            do {
                let library = TemplateLibrary(root: try SharedContainer.root().appendingPathComponent("Templates", isDirectory: true))
                let entry = try await library.importTemplateAsync(from: url, replacing: existing)
                if Task.isCancelled {
                    try await Task.detached { try library.removeSnapshot(entry.source) }.value
                    resultMessage = L10n.text("已取消导入")
                    return
                }
                var next = configuration
                guard next.applyImportedTemplate(entry, replacing: existing) else {
                    try await Task.detached { try library.removeSnapshot(entry.source) }.value
                    throw ConfigurationError.invalid(L10n.text("模板配置已更改，请重新导入"))
                }
                let obsolete = save(next) ? existing?.source : entry.source
                try await Task.detached { try library.removeSnapshot(obsolete) }.value
            } catch is CancellationError {
                resultMessage = L10n.text("已取消导入")
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func removeTemplate(_ entry: TemplateEntry) {
        var next = configuration
        next.templates.removeAll { $0.id == entry.id }
        next.shortcuts.removeAll { $0 == .template(entry.id) }
        guard save(next) else { return }
        do { try TemplateLibrary(root: SharedContainer.root().appendingPathComponent("Templates", isDirectory: true)).removeSnapshot(entry.source) }
        catch { errorMessage = error.localizedDescription }
    }
    func enableCopy(_ enabled: Bool) {
        var next = configuration
        if enabled { next.enabledActions.insert(.copyPath) } else { next.enabledActions.remove(.copyPath) }
        save(next)
    }
    func setLoginItem(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch { errorMessage = error.localizedDescription }
        loginStatus = SMAppService.mainApp.status
    }
    /// Returns whether the configuration was committed. Login registration has
    /// its own system result and may still report an error after that commit.
    @discardableResult
    func resetSettings() -> Bool {
        guard !processing else { errorMessage = L10n.text("请等待当前操作完成后恢复默认设置"); return false }
        resultMessage = ""
        guard save(Configuration()) else { return false }
        operationFailures = []
        setLoginItem(false)
        // Login registration has its own status/error; this confirms only the saved configuration.
        resultMessage = L10n.text("配置已恢复默认")
        return true
    }
    var loginStatusText: String {
        switch loginStatus {
        case .enabled: L10n.text("已启用")
        case .requiresApproval: L10n.text("等待系统批准，请前往登录项设置")
        case .notRegistered: L10n.text("未启用")
        case .notFound: L10n.text("系统未找到登录项，可尝试重新启用；若仍失败，请重新安装应用。")
        @unknown default: L10n.text("状态暂不可用")
        }
    }
    func manageExtension() { FIFinderSyncController.showExtensionManagementInterface() }
    private func poll() async {
        loginStatus = SMAppService.mainApp.status
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
        guard configurationReady, !processing, !polling, let inbox = try? SharedContainer.inbox() else { return }
        polling = true
        defer { polling = false }
        let sessionStart = sessionStartedAt
        do {
            let request: ActionRequest
            if let pending = pendingRequest {
                request = pending
                pendingRequest = nil
            } else {
                guard let received = try await Task.detached(priority: .userInitiated, operation: {
                    try RequestInbox(directory: inbox).takeNext(sessionStartedAt: sessionStart)
                }).value else { return }
                request = received
            }
            let directoryTypes = await Task.detached(priority: .userInitiated) {
                var types: [URL: Bool] = [:]
                // This plan is only used to check the requested action's availability;
                // its titles are never displayed. Only AirDrop eligibility needs types.
                guard request.action == .builtin(.airDrop) else { return types }
                for url in Set(request.context.selected) {
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    types[url] = isDirectory
                    if isDirectory { break }
                }
                return types
            }.value
            // A template import may have started while the file reads were suspended.
            // Keep the consumed request in memory until that operation finishes.
            guard !processing else { pendingRequest = request; return }
            try request.validate(sessionStartedAt: sessionStart)
            // Settings can change while metadata is read. Use the current configuration.
            let plan = MenuPlanner.plan(configuration: configuration, context: request.context) {
                directoryTypes[$0] ?? false
            }
            guard (plan.shortcuts + plan.sections.flatMap(\.actions)).contains(where: { $0.reference == request.action && $0.enabled }) else {
                throw ConfigurationError.invalid(L10n.text("操作已关闭或目标不适用"))
            }
            processing = true
            progressMessage = L10n.text("正在处理…")
            actionTask = Task { await execute(request) }
            return
        } catch { errorMessage = error.localizedDescription }
    }
    private func confirm(title: String, detail: String, action: String, targets: [URL] = []) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("取消"))
        alert.addButton(withTitle: action)
        if !targets.isEmpty {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let list = NSTextView(frame: scroll.contentView.bounds)
            list.isEditable = false
            list.isSelectable = true
            list.isVerticallyResizable = true
            list.isHorizontallyResizable = false
            list.autoresizingMask = [.width]
            list.textContainer?.widthTracksTextView = true
            list.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            list.string = targets.enumerated().map { index, url in
                "\(index + 1). \(url.path)"
            }.joined(separator: "\n\n")
            list.setAccessibilityLabel(L10n.text("删除目标"))
            scroll.documentView = list
            alert.accessoryView = scroll
        }
        return alert.runModal() == .alertSecondButtonReturn
    }
    func cancelOperation() {
        actionTask?.cancel()
        progressMessage = L10n.text("将在当前项目处理结束后停止…")
    }
    private func performBatch(_ urls: [URL], operation: @escaping @Sendable (URL) throws -> Void) async {
        let result = await BatchOperation.run(urls, operation: operation) { [weak self] done, total in
            await MainActor.run { self?.progressMessage = L10n.format("正在处理 %@ / %@ 项", String(done), String(total)) }
        }
        operationFailures = result.failures
        resultMessage = L10n.format("已完成 %@ / %@ 项", String(result.completed), String(urls.count)) + (result.cancelled ? L10n.text(" · 已停止后续操作") : "")
        if !result.failures.isEmpty {
            errorMessage = resultMessage + "\n" + result.failures.prefix(8).map { "\($0.url.lastPathComponent)：\($0.message)" }.joined(separator: "\n")
        }
    }
    private func execute(_ request: ActionRequest) async {
        defer { processing = false; progressMessage = ""; actionTask = nil }
        operationFailures = []
        let originalConfiguration = configuration
        func validateCurrentAction() throws {
            try Task.checkCancellation()
            guard configuration.hasSameEnabledAction(request.action, as: originalConfiguration) else {
                throw ConfigurationError.invalid(L10n.text("操作配置已更改，请从 Finder 重新发起"))
            }
        }
        var leases: [URL] = []
        defer { for root in leases { root.stopAccessingSecurityScopedResource() } }
        do {
            let accessTargets: [URL]
            switch request.action {
            case .builtin(.copyPath): accessTargets = []
            case .template where request.context.selected.count > 1: accessTargets = []
            case .directory(let id): accessTargets = configuration.directories.first(where: { $0.id == id }).map { [$0.url] } ?? []
            case .builtin(.unhideChildren): accessTargets = request.context.directory.map { [$0] } ?? []
            default: accessTargets = request.context.pathTargets
            }
            leases = try directoryAccess.beginAccess(to: accessTargets)
            let requiresAllTargets: Bool
            switch request.action {
            case .template where request.context.selected.count > 1: requiresAllTargets = false
            case .directory, .builtin(.copyPath), .builtin(.hide), .builtin(.unhide), .builtin(.deletePermanently): requiresAllTargets = false
            default: requiresAllTargets = true
            }
            let targetsExist = await Task.detached {
                !requiresAllTargets || request.context.pathTargets.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
            }.value
            try Task.checkCancellation()
            try validateCurrentAction()
            guard targetsExist else {
                throw ConfigurationError.invalid(L10n.text("目标已删除或暂时不可访问"))
            }
            switch request.action {
            case .builtin(.copyPath):
                try systemActions.copyPaths(request.context)
                resultMessage = L10n.format("已复制 %@ 项路径", String(request.context.pathTargets.count))
            case .directory(let id):
                guard let entry = configuration.directories.first(where: { $0.id == id && $0.enabled }),
                      (try? URL(fileURLWithPath: entry.url.path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    throw ConfigurationError.invalid(L10n.text("目录不可访问，请在目录快捷入口中重新选择"))
                }
                try systemActions.openDirectory(entry.url)
                resultMessage = L10n.text("已请求打开目录")
            case .application(let id):
                guard let entry = configuration.applications.first(where: { $0.id == id && $0.enabled }),
                      FileManager.default.fileExists(atPath: entry.url.path) else {
                    throw ConfigurationError.invalid(L10n.text("应用已移动或卸载，请在打开方式中重新选择"))
                }
                let targets = try entry.openingTargets(request.context.pathTargets) {
                    try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                }
                let reused = try await systemActions.open(targets, with: entry)
                resultMessage = reused && (!entry.arguments.isEmpty || !entry.environment.isEmpty)
                    ? L10n.text("已交给运行中的应用；启动参数和环境变量只在新进程启动时生效。")
                    : L10n.text("已请求使用应用打开")
            case .template(let id):
                guard let template = configuration.templates.first(where: { $0.id == id && $0.enabled }) else { return }
                let directory: URL
                if request.context.selected.count > 1 {
                    let panel = NSOpenPanel()
                    panel.message = L10n.text("请选择新文件的目标目录")
                    panel.canChooseFiles = false; panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    let response = panel.runModal()
                    guard response == .OK, let chosen = panel.url else { return }
                    try directoryAccess.rememberSelectedDirectory(chosen)
                    leases += try directoryAccess.beginAccess(to: [chosen], requestIfNeeded: false)
                    directory = chosen
                } else {
                    directory = try await Task.detached {
                        try request.context.creationDirectory {
                            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                        }
                    }.value
                }
                try validateCurrentAction()
                let url = try await FileOperations.createAsync(template: template, in: directory)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                resultMessage = L10n.text("已创建文件")
            case .builtin(.hide), .builtin(.unhide):
                guard !request.context.selected.isEmpty else { throw ConfigurationError.invalid(L10n.text("请先选择文件或文件夹")) }
                let hidden = request.action == .builtin(.hide)
                await performBatch(request.context.selected) { try FileOperations.setHidden(hidden, at: $0) }
            case .builtin(.unhideChildren):
                guard let directory = request.context.directory else { throw ConfigurationError.invalid(L10n.text("当前目录不可用")) }
                let children = try await Task.detached(priority: .userInitiated) {
                    try FileOperations.hiddenChildren(in: directory)
                }.value
                try Task.checkCancellation()
                guard !children.isEmpty else { resultMessage = L10n.text("此目录没有隐藏项目"); return }
                guard confirm(title: L10n.text("显示目录中的隐藏项目？"), detail: L10n.format("目录：%@\n将显示直接包含的 %@ 个隐藏项目，不处理子目录内部。", directory.path, String(children.count)), action: L10n.text("显示项目")) else { return }
                try validateCurrentAction()
                await performBatch(children) { try FileOperations.setHidden(false, at: $0) }
            case .builtin(.deletePermanently):
                let targets = try request.context.deletionTargets()
                guard confirm(title: L10n.format("永久删除 %@ 个项目？", String(targets.count)), detail: L10n.text("此操作不经过废纸篓，无法撤销。文件夹内的内容也会被删除。请核对下方完整目标清单。"), action: L10n.text("永久删除"), targets: targets) else { return }
                try validateCurrentAction()
                await performBatch(targets) { try FileManager.default.removeItem(at: $0) }
            case .builtin(.airDrop):
                try systemActions.airDrop(request.context.selected, transferring: &leases) { [weak self] error in
                    self?.errorMessage = error.localizedDescription
                }
                resultMessage = L10n.text("已请求隔空投送，请在系统面板中继续")

            }
        } catch is CancellationError { resultMessage = L10n.text("已取消操作") }
        catch { errorMessage = error.localizedDescription }
    }
}
