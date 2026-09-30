import Foundation
import ClickportCore

@MainActor final class LaunchHelperClient {
    /// Keep the connection and completion on one actor: errors, timeout and reply race.
    private var connection: NSXPCConnection?
    private var completion: CheckedContinuation<Bool, any Error>?
    private var activeID: UUID?
    private var timeout: Task<Void, Never>?

    func open(_ urls: [URL], with entry: ApplicationEntry) async throws -> Bool {
        guard completion == nil else { throw LaunchFailure.unavailable }
        try Task.checkCancellation()
        let request = try LaunchRequest(entry: entry, targets: urls).validated()
        let data = try JSONEncoder().encode(request)
        let requirement = try LaunchPeerIdentity.requirement(identifier: LaunchPeerIdentity.serviceName)
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            activeID = request.id
            let connection = NSXPCConnection(serviceName: LaunchPeerIdentity.serviceName)
            self.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: LaunchHelperProtocol.self)
            connection.setCodeSigningRequirement(requirement)
            connection.interruptionHandler = { @Sendable [weak self] in
                Task { @MainActor in self?.finish(.failure(LaunchFailure.unknown), id: request.id) }
            }
            connection.invalidationHandler = { @Sendable [weak self] in
                Task { @MainActor in self?.finish(.failure(LaunchFailure.unknown), id: request.id) }
            }
            connection.resume()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.finish(.failure(LaunchFailure.unknown), id: request.id)
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable [weak self] _ in
                Task { @MainActor in self?.finish(.failure(LaunchFailure.unknown), id: request.id) }
            }) as? LaunchHelperProtocol else {
                finish(.failure(LaunchFailure.unavailable), id: request.id); return
            }
            proxy.launch(data) { [weak self] response in
                let reply = response.count <= 4096 ? try? JSONDecoder().decode(LaunchReply.self, from: response) : nil
                Task { @MainActor in
                    guard let reply else { self?.finish(.failure(LaunchFailure.unknown), id: request.id); return }
                    if let failure = reply.failure { self?.finish(.failure(failure), id: request.id) }
                    else { self?.finish(.success(reply.reusedProcess), id: request.id) }
                }
            }
        }
    }

    private func finish(_ result: Result<Bool, any Error>, id: UUID) {
        guard activeID == id, let completion else { return }
        self.completion = nil
        activeID = nil
        timeout?.cancel(); timeout = nil
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate(); connection = nil
        completion.resume(with: result)
    }
}
