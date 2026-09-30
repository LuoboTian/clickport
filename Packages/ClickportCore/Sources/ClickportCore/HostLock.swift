import Foundation
import Darwin

/// One host owns the shared inbox. The kernel releases this lock when the process exits.
public final class HostLock {
    private let descriptor: Int32
    public init(root: URL) throws {
        let path = root.appendingPathComponent("host.lock").path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw ConfigurationError.invalid("已有 Clickport 实例正在运行，请退出旧版本后重新打开")
        }
        descriptor = fd
    }
    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}
