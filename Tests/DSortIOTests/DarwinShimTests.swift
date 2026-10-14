import DSortCore
import Darwin
import Foundation
import Testing
@testable import DSortIO

/// Marks `path` as a screenshot the way macOS does: a binary plist holding `true`.
func markScreenCapture(_ path: String, _ value: Bool = true) {
    let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    let r = data.withUnsafeBytes { setxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, data.count, 0, 0) }
    precondition(r == 0)
}

@Suite struct DarwinShimTests {
    let ops = RealFileOps()

    @Test func exclusiveRenameRefusesCaseVariant() throws {
        let tmp = TempDir()
        let a = tmp.file("Doc.pdf", "1")
        let b = tmp.file("sub/doc.PDF", "2")
        #expect(throws: SysError(EEXIST, "rename", a)) { try ops.renameExclusive(a, b) }
        #expect(FileManager.default.fileExists(atPath: a))
        #expect(String(decoding: FileManager.default.contents(atPath: b)!, as: UTF8.self) == "2")
        try ops.renameExclusive(a, tmp.sub("sub/Free.pdf"))
        #expect(FileManager.default.fileExists(atPath: tmp.sub("sub/Free.pdf")))
    }

    @Test func trackedFileKeepsDocumentIDAcrossSafeSave() throws {
        let tmp = TempDir()
        let p = tmp.file("notes.txt", "v1")
        #expect(ops.documentID(p) == 0)
        #expect(try ops.addTrackedFlag(p) == true)
        #expect(try ops.addTrackedFlag(p) == false)
        let id = ops.documentID(p)
        #expect(id != 0)
        let inode = try ops.lstat(p).ino

        let replacement = tmp.file("notes.txt.new", "v2")
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: p), withItemAt: URL(fileURLWithPath: replacement))
        #expect(try ops.lstat(p).ino != inode)
        #expect(ops.documentID(p) == id)
    }

    @Test func pathForFileFollowsRenamesAndReportsDeletion() throws {
        let tmp = TempDir()
        let p = tmp.file("a.txt")
        let fsid = try ops.fsid(p)
        let ino = try ops.lstat(p).ino
        try ops.makeDirectory(tmp.sub("moved"))
        try ops.renameExclusive(p, tmp.sub("moved/b.txt"))
        #expect(try ops.pathForFile(fsid: fsid, ino: ino) == tmp.sub("moved/b.txt"))
        unlink(tmp.sub("moved/b.txt"))
        #expect(throws: SysError(ENOENT, "fsgetpath", "inode \(ino)")) { try ops.pathForFile(fsid: fsid, ino: ino) }
    }

    @Test func pathForFileReportsPermissionDenied() throws {
        let tmp = TempDir()
        let p = tmp.file("locked/inner/x.txt")
        let fsid = try ops.fsid(p)
        let ino = try ops.lstat(p).ino
        chmod(tmp.sub("locked"), 0o000)
        defer { chmod(tmp.sub("locked"), 0o755) }
        #expect(throws: SysError(EACCES, "fsgetpath", "inode \(ino)")) { try ops.pathForFile(fsid: fsid, ino: ino) }
    }

    @Test func screenCaptureAttributeIsDecoded() {
        let tmp = TempDir()
        let yes = tmp.file("shot.png"), no = tmp.file("export.png"), falseFlag = tmp.file("f.png")
        markScreenCapture(yes)
        markScreenCapture(falseFlag, false)
        #expect(ops.isScreenCapture(yes))
        #expect(!ops.isScreenCapture(no))
        #expect(!ops.isScreenCapture(falseFlag))
    }

    @Test func findDocumentSearchesRecursively() throws {
        let tmp = TempDir()
        let p = tmp.file("Bucket/deep/er/file.txt")
        _ = try ops.addTrackedFlag(p)
        let id = ops.documentID(p)
        #expect(ops.findDocument(id, under: [tmp.sub("Bucket")]) == p)
        #expect(ops.findDocument(id, under: [tmp.sub("nope")]) == nil)
        #expect(ops.findDocument(0, under: [tmp.sub("Bucket")]) == nil)
    }

    @Test func volumeCapabilitiesOfTempVolume() throws {
        let tmp = TempDir()
        let caps = try #require(ops.volumeCapabilities(tmp.path))
        #expect(caps.renameExclusive)
        #expect(caps.pathFromID)
    }
}

@Suite struct ScannerTests {
    @Test func scansEveryKindWithoutFollowingSymlinks() throws {
        let tmp = TempDir()
        tmp.file(".hidden")
        tmp.file("invoice.pdf")
        tmp.dir("Project")
        tmp.dir("toolkit-0.12.0-beta")
        tmp.file("Fake.app/Contents/Info.plist")
        let shot = tmp.file("Screenshot 2026-10-14 at 16.48.54.png")
        markScreenCapture(shot)
        symlink(tmp.sub("Project"), tmp.sub("link"))
        tmp.file("Project/nested.pdf")

        let entries = try Scanner(ops: RealFileOps()).scan(tmp.path)
        let kinds = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.kind) })
        #expect(kinds == [
            ".hidden": .file, "invoice.pdf": .file, "Project": .folder, "toolkit-0.12.0-beta": .folder,
            "Fake.app": .package, "Screenshot 2026-10-14 at 16.48.54.png": .file, "link": .symlink,
        ])
        #expect(entries.filter(\.isScreenCapture).map(\.name) == ["Screenshot 2026-10-14 at 16.48.54.png"])
        let pdf = try #require(entries.first { $0.name == "invoice.pdf" })
        #expect(pdf.path == tmp.sub("invoice.pdf"))
        #expect(pdf.identity.ino == (try RealFileOps().lstat(pdf.path)).ino)
    }
}

@Suite struct PermissionTests {
    @Test func tccDenialExitsNoPermissionNamingTheTerminal() {
        let tmp = TempDir()
        let ops = FaultyOps()
        ops.listError = SysError(EPERM, "opendir", tmp.path)
        let scanner = Scanner(ops: ops, environment: Environment(home: tmp.path, variables: ["TERM_PROGRAM": "Apple_Terminal"]))
        do {
            _ = try scanner.scan(tmp.path)
            Issue.record("expected a permission error")
        } catch {
            #expect(error.exit == .noPermission)
            #expect(error.message.contains("\"Terminal\""))
            #expect(error.message.contains("Privacy & Security"))
            #expect(error.message.contains(PermissionHelp.settingsURL))
        }
    }

    @Test func launchdDenialNamesTheBinary() {
        let message = PermissionHelp.message(root: "/r", environment: Environment(home: "/h", variables: [:]),
                                             error: SysError(EPERM, "opendir", "/r"))
        #expect(message.contains("the dsort binary at "))
    }

    @Test func missingRootIsAUsageError() {
        let error = PermissionHelp.error(for: SysError(ENOENT, "opendir", "/r"), root: "/r", environment: .current)
        #expect(error.exit == .usage)
    }
}
