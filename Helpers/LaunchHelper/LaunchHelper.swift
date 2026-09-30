import AppKit
import ClickportCore

/// Each authenticated connection accepts one launch. No launch retry on reconnect.
final class LaunchService: NSObject, LaunchHelperProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false
    private var closed = false

    func invalidate() { lock.withLock { closed = true } }

    func launch(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) {
        let accepted = lock.withLock {
            guard !consumed, !closed else { return false }
            consumed = true
            return true
        }
        guard accepted, let request = try? LaunchRequest.decode(data) else {
            Self.respond(.init(failure: .invalidRequest), to: reply)
            return
        }
        Task { @MainActor in
            guard self.lock.withLock({ !self.closed }),
                  (try? request.validated()) != nil,
                  LaunchHistory.accept(request.id),
                  (try? request.entry.url.resourceValues(forKeys: [.isApplicationKey]).isApplication) == true,
                  request.targets.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                Self.respond(.init(failure: .rejected), to: reply)
                return
            }
            let submittedAt = Date()
            let options = NSWorkspace.OpenConfiguration()
            options.arguments = request.entry.arguments
            options.environment = request.entry.environment
            options.createsNewApplicationInstance = request.entry.newInstance
            options.allowsRunningApplicationSubstitution = false
            NSWorkspace.shared.open(request.targets, withApplicationAt: request.entry.url, configuration: options) { app, error in
                let result: LaunchReply
                if error != nil { result = .init(failure: .failed) }
                else if let launchedAt = app?.launchDate { result = .init(reusedProcess: launchedAt < submittedAt) }
                else { result = .init(failure: .unknown) }
                Self.respond(result, to: reply)
            }
        }
    }
    private static func respond(_ value: LaunchReply, to reply: @Sendable (Data) -> Void) {
        reply((try? JSONEncoder().encode(value)) ?? Data())
    }
}

@MainActor private enum LaunchHistory {
    static var recent: [UUID: Date] = [:]
    static func accept(_ id: UUID) -> Bool {
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0.value) < 60 }
        guard recent[id] == nil, recent.count < 256 else { return false }
        recent[id] = now
        return true
    }
}

final class LaunchListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid(),
              let requirement = try? LaunchPeerIdentity.requirement(identifier: "org.clickport.app") else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: LaunchHelperProtocol.self)
        let service = LaunchService()
        connection.exportedObject = service
        connection.invalidationHandler = { @Sendable in service.invalidate() }
        connection.interruptionHandler = { @Sendable in service.invalidate() }
        connection.resume()
        return true
    }
}

@main struct LaunchHelperMain {
    static func main() {
        let delegate = LaunchListener()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        withExtendedLifetime(delegate) { listener.resume() }
    }
}
