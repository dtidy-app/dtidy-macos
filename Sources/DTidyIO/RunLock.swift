import DTidyCore
import Darwin
import Foundation

/// An exclusive `flock` on `<data>/lock`, held for the lifetime of the value. The kernel
/// releases it when the process exits, so a crash never leaves a stale lock behind.
public final class RunLock {
    public let path: String
    private let fd: Int32

    private init(path: String, fd: Int32) {
        self.path = path
        self.fd = fd
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }

    public static func lockPath(dataDirectory: String) -> String {
        Paths.join(dataDirectory, "lock")
    }

    /// Takes the lock without waiting; throws exit code 75 when another process holds it.
    public static func acquire(dataDirectory: String) throws(DTidyError) -> RunLock {
        let path = lockPath(dataDirectory: dataDirectory)
        try? FileManager.default.createDirectory(
            atPath: dataDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            throw DTidyError(.partial, "Cannot open the lock file \(path): \(String(cString: strerror(errno)))")
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK {
                throw DTidyError(.lockHeld, "Another dtidy process is running (lock: \(path)). Try again when it finishes.")
            }
            throw DTidyError(.partial, "Cannot lock \(path): \(String(cString: strerror(code)))")
        }
        return RunLock(path: path, fd: fd)
    }

    /// Whether another process holds the lock right now. Does not create the lock file.
    public static func isHeld(dataDirectory: String) -> Bool {
        let fd = open(lockPath(dataDirectory: dataDirectory), O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }
}
