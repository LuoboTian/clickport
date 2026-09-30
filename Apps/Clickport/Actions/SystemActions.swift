import AppKit
import ClickportCore

/// macOS interaction adapters. Target selection and authorization remain in the caller.
@MainActor
final class SystemActions: NSObject, NSSharingServiceDelegate {
    private struct SharingSession {
        let service: NSSharingService
        let leases: [URL]
        let onFailure: (Error) -> Void
    }
    private let launchHelper = LaunchHelperClient()
    private var sharingSessions: [ObjectIdentifier: SharingSession] = [:]
    private let makeSharingService: () -> NSSharingService?
    private let activateForSharing: () -> Void
    private let releaseSharingScope: (URL) -> Void

    init(makeSharingService: @escaping () -> NSSharingService? = { NSSharingService(named: .sendViaAirDrop) },
         activateForSharing: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
         releaseSharingScope: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.makeSharingService = makeSharingService
        self.activateForSharing = activateForSharing
        self.releaseSharingScope = releaseSharingScope
        super.init()
    }
    func copyPaths(_ context: TargetContext) throws {
        let text = try context.pathsForClipboard()
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw ConfigurationError.invalid("剪贴板写入失败")
        }
    }
    func openDirectory(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else { throw ConfigurationError.invalid("无法打开目录") }
    }
    /// Returns whether LaunchServices reused an already running process.
    func open(_ urls: [URL], with entry: ApplicationEntry) async throws -> Bool {
        if !entry.arguments.isEmpty || !entry.environment.isEmpty {
            do { return try await launchHelper.open(urls, with: entry) }
            catch let failure as LaunchFailure {
                let message = failure == .unknown
                    ? "启动结果无法确认，请检查目标应用后再重试。"
                    : "启动助手未能完成请求，请检查应用位置与本机签名。"
                throw ConfigurationError.invalid(L10n.text(message))
            }
        }
        let existingProcesses = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let options = NSWorkspace.OpenConfiguration()
        options.arguments = entry.arguments
        options.environment = entry.environment
        options.createsNewApplicationInstance = entry.newInstance
        // Respect the configured installation when multiple app versions are running.
        options.allowsRunningApplicationSubstitution = false
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: entry.url, configuration: options) { application, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: application.map { existingProcesses.contains($0.processIdentifier) } ?? false) }
            }
        }
    }
    /// Transfers existing security scopes only after validation succeeds. Sharing outlives
    /// the request handler; terminal delegate callbacks release its scopes exactly once.
    func airDrop(_ items: [URL], transferring leases: inout [URL], onFailure: @escaping (Error) -> Void) throws {
        guard let service = makeSharingService() else {
            throw ConfigurationError.invalid("系统隔空投送服务不可用")
        }
        guard !items.isEmpty, service.canPerform(withItems: items) else {
            throw ConfigurationError.invalid("当前目标无法使用隔空投送")
        }
        guard sharingSessions[ObjectIdentifier(service)] == nil else {
            throw ConfigurationError.invalid("请先完成当前隔空投送操作")
        }
        sharingSessions[ObjectIdentifier(service)] = SharingSession(service: service, leases: leases, onFailure: onFailure)
        leases.removeAll()
        service.delegate = self
        activateForSharing()
        service.perform(withItems: items)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finishSharing(sharingService, error: nil)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        finishSharing(sharingService, error: error)
    }

    private func finishSharing(_ service: NSSharingService, error: Error?) {
        guard let session = sharingSessions.removeValue(forKey: ObjectIdentifier(service)) else { return }
        session.service.delegate = nil
        for root in session.leases { releaseSharingScope(root) }
        if let error { session.onFailure(error) }
    }
}
