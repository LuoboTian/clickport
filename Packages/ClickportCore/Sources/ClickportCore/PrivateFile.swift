import Foundation
import Darwin

public enum PrivateFile {
    public static func write(_ data: Data, to url: URL) throws {
        guard url.isLocalFileURL else { throw TargetError.notFileURL }
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = parent.appendingPathComponent(".pending-\(UUID().uuidString)")
        let descriptor = Darwin.open(staging.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: staging) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard Darwin.rename(staging.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

public enum DirectoryScope {
    public static func covers(_ target: URL, within directory: URL) -> Bool {
        guard target.isLocalFileURL, directory.isLocalFileURL else { return false }
        let base = canonicalPath(directory).pathComponents
        let item = canonicalPath(target).pathComponents
        return item.count >= base.count && Array(item.prefix(base.count)) == base
    }
    private static func canonicalPath(_ url: URL) -> URL {
        // Foundation does not always resolve ancestor symlinks when the final file does not exist.
        var ancestor = url
        var remaining: [String] = []
        while ancestor.path != "/" && !FileManager.default.fileExists(atPath: ancestor.path) {
            remaining.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var result = ancestor.resolvingSymlinksInPath()
        for component in remaining.reversed() { result.appendPathComponent(component) }
        return result.standardizedFileURL
    }
}
