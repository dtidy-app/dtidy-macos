import DSortCore
import Darwin
import Foundation

/// Appends records to a new ledger file. The file is opened append-only and never rewritten.
public final class LedgerWriter {
    public let path: String
    private let fd: Int32

    private init(path: String, fd: Int32) {
        self.path = path
        self.fd = fd
    }

    deinit { close(fd) }

    /// Creates `<directory>/<runId>.jsonl`, failing if it already exists.
    public static func create(in directory: String, runId: String) throws(SysError) -> LedgerWriter {
        do {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw SysError(EACCES, "mkdir", directory)
        }
        let path = Paths.join(directory, runId + ".jsonl")
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SysError(errno, "open", path) }
        return LedgerWriter(path: path, fd: fd)
    }

    /// Whether the descriptor was opened with O_APPEND (exposed for tests).
    var isAppendOnly: Bool { fcntl(fd, F_GETFL) & O_APPEND != 0 }

    /// Writes one record as a single line in a single write call.
    public func append(_ record: LedgerRecord) throws(SysError) {
        let line: Data
        do { line = try LedgerCodec.line(record) } catch { throw SysError(EINVAL, "encode", path) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw SysError(written < 0 ? errno : EIO, "write", path) }
    }

    /// Orders everything written so far before any later filesystem change (F_BARRIERFSYNC),
    /// falling back to fsync where barriers are unsupported.
    public func barrier() throws(SysError) {
        if fcntl(fd, F_BARRIERFSYNC) == 0 { return }
        guard fsync(fd) == 0 else { throw SysError(errno, "fsync", path) }
    }

    /// Appends `record` and flushes it with a barrier.
    public func appendDurably(_ record: LedgerRecord) throws(SysError) {
        try append(record)
        try barrier()
    }
}

/// The history directory: every ledger file, read and parsed.
public struct LedgerStore: Sendable {
    public let directory: String

    public init(directory: String) {
        self.directory = directory
    }

    public init(environment: Environment) {
        self.init(directory: Paths.historyDirectory(environment: environment))
    }

    public func load() -> History {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let files = names.filter { $0.hasSuffix(".jsonl") }.compactMap { name -> LedgerFile? in
            FileManager.default.contents(atPath: Paths.join(directory, name)).flatMap(LedgerFile.init)
        }
        return History(files)
    }

    public func create(runId: String) throws(DSortError) -> LedgerWriter {
        do {
            return try LedgerWriter.create(in: directory, runId: runId)
        } catch {
            throw DSortError(.partial, "Cannot create the run ledger: \(error)")
        }
    }
}
