/// Process exit codes, taken from sysexits(3).
public enum DSortExit: Int32, Sendable, Codable {
    /// Every planned action succeeded.
    case ok = 0
    /// Some items failed or were left unresolved.
    case partial = 1
    /// Usage or configuration error (EX_USAGE).
    case usage = 64
    /// Another dsort process holds the run lock (EX_TEMPFAIL).
    case lockHeld = 75
    /// Permission denied by the OS (EX_NOPERM).
    case noPermission = 77
}

/// An error that carries the exit code the CLI should end with.
public struct DSortError: Error, CustomStringConvertible, Sendable {
    public let exit: DSortExit
    public let message: String

    public init(_ exit: DSortExit, _ message: String) {
        self.exit = exit
        self.message = message
    }

    public var description: String { message }
}
