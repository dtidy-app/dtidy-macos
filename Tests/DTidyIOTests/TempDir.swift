import Foundation

/// A fresh temporary directory, removed when the value is deinitialized.
final class TempDir {
    let path: String

    init() {
        // realpath, not resolvingSymlinksInPath: the kernel reports /private/var/..., and
        // Foundation's resolver strips the /private prefix.
        let base = realpath(FileManager.default.temporaryDirectory.path, nil)!
        defer { free(base) }
        path = String(cString: base) + "/dtidy-test-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit {
        // Undo any chmod 000 a test left behind, then remove the tree.
        if let e = FileManager.default.enumerator(atPath: path) {
            for case let rel as String in e { chmod(path + "/" + rel, 0o755) }
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    func sub(_ rel: String) -> String { path + "/" + rel }

    @discardableResult
    func file(_ rel: String, _ contents: String = "x", age: TimeInterval = 3600) -> String {
        let p = sub(rel)
        try! FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! Data(contents.utf8).write(to: URL(fileURLWithPath: p))
        let past = Date().addingTimeInterval(-age)
        try! FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: p)
        return p
    }

    @discardableResult
    func dir(_ rel: String) -> String {
        let p = sub(rel)
        try! FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }
}
