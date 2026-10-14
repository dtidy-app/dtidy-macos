import DTidyCore
import Darwin
import Foundation

/// A failed system call, carrying its errno.
public struct SysError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: Int32
    public let operation: String
    public let path: String

    public init(_ code: Int32, _ operation: String, _ path: String) {
        self.code = code
        self.operation = operation
        self.path = path
    }

    public var description: String { "\(operation) \(path): \(String(cString: strerror(code)))" }
    public var reason: String { String(cString: strerror(code)) }
}

/// The result of `lstat`, reduced to what dtidy needs.
public struct StatInfo: Sendable, Equatable {
    public var kind: EntryKind
    public var dev: Int32
    public var ino: UInt64
    public var birth: Double
    public var modified: Double
    public var flags: UInt32

    public var isTracked: Bool { flags & UInt32(UF_TRACKED) != 0 }
}

public struct VolumeCapabilities: Sendable, Equatable {
    public var renameExclusive: Bool
    public var pathFromID: Bool
    public var caseSensitive: Bool
}

/// Every filesystem operation dtidy performs. The real implementation calls Darwin directly;
/// tests wrap it to inject failures such as EEXIST races, EXDEV, EACCES, or a crash.
public protocol FileOps: Sendable {
    func listDirectory(_ path: String) throws(SysError) -> [String]
    func lstat(_ path: String) throws(SysError) -> StatInfo
    /// The `f_fsid` of the volume holding `path`.
    func fsid(_ path: String) throws(SysError) -> [Int32]
    func isPackage(_ path: String) -> Bool
    /// Whether `com.apple.metadata:kMDItemIsScreenCapture` is set and decodes to true.
    func isScreenCapture(_ path: String) -> Bool
    func makeDirectory(_ path: String) throws(SysError)
    func removeDirectory(_ path: String) throws(SysError)
    /// Atomic rename that fails with EEXIST if `to` exists (`renamex_np` + `RENAME_EXCL`).
    /// Failures are `SysError`; any other error aborts the run, leaving it to `dtidy recover`.
    func renameExclusive(_ from: String, _ to: String) throws
    /// Sets `UF_TRACKED`; returns false when it was already set.
    func addTrackedFlag(_ path: String) throws(SysError) -> Bool
    /// The kernel document identifier, or 0 when the file has none.
    func documentID(_ path: String) -> UInt32
    /// The current path of the file with inode `ino` on volume `fsid` (`fsgetpath`).
    func pathForFile(fsid: [Int32], ino: UInt64) throws(SysError) -> String
    /// Recursively searches `roots` for a file with document identifier `docID`.
    func findDocument(_ docID: UInt32, under roots: [String]) -> String?
    func volumeCapabilities(_ path: String) -> VolumeCapabilities?
}

public struct RealFileOps: FileOps {
    public init() {}

    public func listDirectory(_ path: String) throws(SysError) -> [String] {
        guard let dir = opendir(path) else { throw SysError(errno, "opendir", path) }
        defer { closedir(dir) }
        var names: [String] = []
        while let ent = readdir(dir) {
            let name = withUnsafeBytes(of: ent.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(ent.pointee.d_namlen)), as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    public func lstat(_ path: String) throws(SysError) -> StatInfo {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else { throw SysError(errno, "lstat", path) }
        let kind: EntryKind = switch st.st_mode & S_IFMT {
        case S_IFREG: .file
        case S_IFDIR: .folder
        case S_IFLNK: .symlink
        default: .special
        }
        return StatInfo(
            kind: kind, dev: st.st_dev, ino: st.st_ino,
            birth: Double(st.st_birthtimespec.tv_sec) + Double(st.st_birthtimespec.tv_nsec) / 1e9,
            modified: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9,
            flags: st.st_flags)
    }

    public func fsid(_ path: String) throws(SysError) -> [Int32] {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { throw SysError(errno, "statfs", path) }
        return [fs.f_fsid.val.0, fs.f_fsid.val.1]
    }

    public func isPackage(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }

    public func isScreenCapture(_ path: String) -> Bool {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0, size <= 4096 else { return false }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW) == size else { return false }
        let value = try? PropertyListSerialization.propertyList(from: Data(buffer), format: nil)
        return (value as? Bool) == true
    }

    public func makeDirectory(_ path: String) throws(SysError) {
        guard mkdir(path, 0o755) == 0 else { throw SysError(errno, "mkdir", path) }
    }

    public func removeDirectory(_ path: String) throws(SysError) {
        guard rmdir(path) == 0 else { throw SysError(errno, "rmdir", path) }
    }

    public func renameExclusive(_ from: String, _ to: String) throws {
        guard renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 else { throw SysError(errno, "rename", from) }
    }

    public func addTrackedFlag(_ path: String) throws(SysError) -> Bool {
        let info = try lstat(path)
        if info.isTracked { return false }
        guard lchflags(path, info.flags | UInt32(UF_TRACKED)) == 0 else { throw SysError(errno, "chflags", path) }
        return true
    }

    public func documentID(_ path: String) -> UInt32 {
        // A fresh URL has no cached resource values, so this reads the current ID.
        let value = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.documentIdentifierKey])
        return value?.documentIdentifier.map { UInt32(truncatingIfNeeded: $0) } ?? 0
    }

    public func pathForFile(fsid: [Int32], ino: UInt64) throws(SysError) -> String {
        guard fsid.count == 2 else { throw SysError(EINVAL, "fsgetpath", "inode \(ino)") }
        var id = fsid_t(val: (fsid[0], fsid[1]))
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 2)
        let n = fsgetpath(&buffer, buffer.count, &id, ino)
        guard n > 0 else { throw SysError(errno, "fsgetpath", "inode \(ino)") }
        // n counts the terminating NUL.
        return String(decoding: buffer.prefix(n - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func findDocument(_ docID: UInt32, under roots: [String]) -> String? {
        guard docID != 0 else { return nil }
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.documentIdentifierKey],
                options: [], errorHandler: { _, _ in true })
            else { continue }
            for case let url as URL in walker {
                let id = (try? url.resourceValues(forKeys: [.documentIdentifierKey]))?.documentIdentifier
                if let id, UInt32(truncatingIfNeeded: id) == docID { return url.path }
            }
        }
        return nil
    }

    public func volumeCapabilities(_ path: String) -> VolumeCapabilities? {
        struct Buffer {
            var length: UInt32 = 0
            var caps = vol_capabilities_attr_t()
        }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)
        var buffer = Buffer()
        guard getattrlist(path, &request, &buffer, MemoryLayout<Buffer>.size, 0) == 0 else { return nil }
        let format = buffer.caps.capabilities.0 & buffer.caps.valid.0
        let interfaces = buffer.caps.capabilities.1 & buffer.caps.valid.1
        return VolumeCapabilities(
            renameExclusive: interfaces & UInt32(VOL_CAP_INT_RENAME_EXCL) != 0,
            pathFromID: format & UInt32(VOL_CAP_FMT_PATH_FROM_ID) != 0,
            caseSensitive: format & UInt32(VOL_CAP_FMT_CASE_SENSITIVE) != 0)
    }
}
