import Foundation
import CryptoKit

/// FR-02: a bounded, typed launch request. Never interpreted as shell source.
public struct LaunchRequest: Codable, Sendable {
    public static let maximumBytes = 1024 * 1024
    public var id = UUID()
    public var createdAt = Date()
    public var entry: ApplicationEntry
    public var targets: [URL]
    public var configurationDigest: String

    public init(entry: ApplicationEntry, targets: [URL]) throws {
        self.entry = entry
        self.targets = targets
        configurationDigest = try Self.digest(entry)
    }

    public func validated(now: Date = Date()) throws -> Self {
        guard (-5..<30).contains(now.timeIntervalSince(createdAt)), entry.enabled,
              !targets.isEmpty, targets.count <= 10000,
              targets.allSatisfy(\.isLocalFileURL), entry.url.isLocalFileURL,
              entry.arguments.count <= 256, entry.environment.count <= 128,
              configurationDigest == (try Self.digest(entry)) else { throw LaunchFailure.invalidRequest }
        var configuration = Configuration()
        configuration.applications = [entry]
        _ = try configuration.validated()
        guard try JSONEncoder().encode(self).count <= Self.maximumBytes else { throw LaunchFailure.invalidRequest }
        return self
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw LaunchFailure.invalidRequest }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }

    private static func digest(_ entry: ApplicationEntry) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(entry)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum LaunchFailure: String, Error, Codable, Sendable {
    case invalidRequest, unavailable, unknown, rejected, failed
}

public struct LaunchReply: Codable, Sendable {
    public var reusedProcess: Bool
    public var failure: LaunchFailure?
    public init(reusedProcess: Bool = false, failure: LaunchFailure? = nil) {
        self.reusedProcess = reusedProcess; self.failure = failure
    }
}
