/// Process exit codes, taken from sysexits(3).
public enum DTidyExit: Int32, Sendable, Codable {
    /// Every planned action succeeded.
    case ok = 0
    /// Some items failed or were left unresolved.
    case partial = 1
    /// Usage or configuration error (EX_USAGE).
    case usage = 64
    /// Another dtidy process holds the run lock (EX_TEMPFAIL).
    case lockHeld = 75
    /// Permission denied by the OS (EX_NOPERM).
    case noPermission = 77
}

/// An error that carries the exit code the CLI should end with.
public struct DTidyError: Error, CustomStringConvertible, Sendable {
    public let exit: DTidyExit
    public let message: String

    public init(_ exit: DTidyExit, _ message: String) {
        self.exit = exit
        self.message = message
    }

    public var description: String { message }
}
