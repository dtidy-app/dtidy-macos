import DSortCore
import Foundation
@testable import DSortIO

struct SimulatedCrash: Error {}

/// Real filesystem operations with hooks for injecting failures.
final class FaultyOps: FileOps, @unchecked Sendable {
    let base = RealFileOps()
    var listError: SysError?
    /// Called before each real rename; throw to make the rename fail.
    var beforeRename: ((String, String) throws -> Void)?
    /// After this many successful renames, the next rename throws `SimulatedCrash`.
    var crashAfterRenames: Int?
    var trackedFlagError: Int32?
    private(set) var renames = 0

    func listDirectory(_ path: String) throws(SysError) -> [String] {
        if let listError { throw listError }
        return try base.listDirectory(path)
    }
    func lstat(_ path: String) throws(SysError) -> StatInfo { try base.lstat(path) }
    func fsid(_ path: String) throws(SysError) -> [Int32] { try base.fsid(path) }
    func isPackage(_ path: String) -> Bool { base.isPackage(path) }
    func isScreenCapture(_ path: String) -> Bool { base.isScreenCapture(path) }
    func makeDirectory(_ path: String) throws(SysError) { try base.makeDirectory(path) }
    func removeDirectory(_ path: String) throws(SysError) { try base.removeDirectory(path) }
    func renameExclusive(_ from: String, _ to: String) throws {
        if let limit = crashAfterRenames, renames >= limit { throw SimulatedCrash() }
        try beforeRename?(from, to)
        try base.renameExclusive(from, to)
        renames += 1
    }
    func addTrackedFlag(_ path: String) throws(SysError) -> Bool {
        if let code = trackedFlagError { throw SysError(code, "chflags", path) }
        return try base.addTrackedFlag(path)
    }
    func documentID(_ path: String) -> UInt32 { base.documentID(path) }
    func pathForFile(fsid: [Int32], ino: UInt64) throws(SysError) -> String { try base.pathForFile(fsid: fsid, ino: ino) }
    func findDocument(_ docID: UInt32, under roots: [String]) -> String? { base.findDocument(docID, under: roots) }
    func volumeCapabilities(_ path: String) -> VolumeCapabilities? { base.volumeCapabilities(path) }
}
