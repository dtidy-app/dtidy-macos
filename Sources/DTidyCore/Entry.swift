/// What kind of filesystem object a Desktop item is.
public enum EntryKind: String, Sendable, Codable {
    case file
    /// A directory the system presents as a single document or app (`.app`, `.rtfd`, …).
    case package
    case folder
    case symlink
    /// Sockets, FIFOs, devices.
    case special
}

/// Identifies a file across renames: volume, inode, and birth time (which guards against
/// a reused inode number).
public struct FileIdentity: Codable, Sendable, Hashable {
    /// The `f_fsid` of the file's volume, as two 32-bit halves.
    public var fsid: [Int32]
    public var ino: UInt64
    /// Birth time in seconds since 1970.
    public var birth: Double

    public init(fsid: [Int32], ino: UInt64, birth: Double) {
        self.fsid = fsid
        self.ino = ino
        self.birth = birth
    }

    /// Same volume, inode, and birth time.
    public func sameFile(as other: FileIdentity) -> Bool {
        fsid == other.fsid && ino == other.ino && abs(birth - other.birth) < 1e-6
    }
}

/// One item found at the top level of the root folder.
public struct Entry: Sendable, Equatable {
    public let name: String
    public let path: String
    public let kind: EntryKind
    public let identity: FileIdentity
    /// Modification time in seconds since 1970.
    public let modified: Double
    /// The item carries `com.apple.metadata:kMDItemIsScreenCapture` decoding to true.
    public let isScreenCapture: Bool

    public init(
        name: String, path: String, kind: EntryKind, identity: FileIdentity,
        modified: Double, isScreenCapture: Bool
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.identity = identity
        self.modified = modified
        self.isScreenCapture = isScreenCapture
    }
}

public enum SkipReason: String, Sendable, Codable {
    case hidden
    case bucket
    case symlink
    case special
    case folder
    case skipGlob = "skip-glob"
    case neverMove = "never-move"
    case tooRecent = "too-recent"
}

/// The classifier's verdict for one entry.
public enum Decision: Sendable, Equatable {
    case skip(SkipReason)
    /// Move into `to` (a folder path relative to the root); `rule` names the matching rule.
    case move(to: String, rule: String)
}
