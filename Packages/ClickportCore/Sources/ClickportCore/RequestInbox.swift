import Foundation
import Darwin

/// A single host owns this inbox through HostLock. Invalid entries are consumed,
/// so malformed requests cannot permanently occupy the front of a polling batch.
public struct RequestInbox: Sendable {
    public static let maximumBytes = 4 * 1024 * 1024
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func takeNext(sessionStartedAt: Date, now: Date = Date()) throws -> ActionRequest? {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            .filter { url in
                guard url.pathExtension == "json",
                      UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                      let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
                return values.isDirectory != true || values.isSymbolicLink == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in candidates.prefix(20) {
            // O_NOFOLLOW prevents a replaced entry from reading outside the inbox.
            let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            var payload: Data?
            if descriptor >= 0 {
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                defer { try? handle.close() }
                var info = stat()
                if fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                   info.st_size >= 0, info.st_size < Self.maximumBytes {
                    payload = try? handle.read(upToCount: Self.maximumBytes)
                }
            }
            // Remove the entry itself, never a symlink's destination, before dispatch.
            try FileManager.default.removeItem(at: url)
            guard let payload, payload.count < Self.maximumBytes,
                  let request = try? JSONDecoder().decode(ActionRequest.self, from: payload),
                  request.id.uuidString.lowercased() == url.deletingPathExtension().lastPathComponent.lowercased(),
                  (try? request.validate(now: now, sessionStartedAt: sessionStartedAt)) != nil else { continue }
            return request
        }
        return nil
    }
}
