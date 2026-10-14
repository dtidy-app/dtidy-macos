import DTidyCore
import Darwin
import Foundation
@testable import DTidyIO

/// A temp "home" with a Desktop-like root, separate config and data directories,
/// and helpers to run dtidy services against it.
final class Fixture {
    let tmp = TempDir()
    let root: String
    let env: Environment

    init() {
        root = tmp.dir("Desktop")
        env = Environment(home: tmp.path, variables: [
            "XDG_DATA_HOME": tmp.sub("data"), "XDG_CONFIG_HOME": tmp.sub("cfg"), "TERM_PROGRAM": "Apple_Terminal",
        ])
    }

    var config: ResolvedConfig { try! ConfigLoader.load(explicit: nil, rootOverride: root, environment: env).resolved }
    var store: LedgerStore { LedgerStore(environment: env) }
    var dataDirectory: String { Paths.dataDirectory(environment: env) }

    @discardableResult
    func file(_ name: String, _ contents: String = "x", age: TimeInterval = 3600) -> String {
        tmp.file("Desktop/" + name, contents, age: age)
    }

    func service(_ ops: any FileOps = RealFileOps()) -> SortService {
        SortService(ops: ops, environment: env)
    }

    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: Paths.join(root, rel)) }

    func contents(_ rel: String) -> String? {
        FileManager.default.contents(atPath: Paths.join(root, rel)).map { String(decoding: $0, as: UTF8.self) }
    }

    func ledgerRecords(_ runId: String) -> [LedgerRecord] {
        store.load().ledger(runId)?.records ?? []
    }

    func isTracked(_ rel: String) -> Bool { (try? RealFileOps().lstat(Paths.join(root, rel)))?.isTracked ?? false }

    /// Every path under the temp dir, with sizes, for byte-level "nothing changed" checks.
    func snapshot() -> [String: Int] {
        var result: [String: Int] = [:]
        let e = FileManager.default.enumerator(atPath: tmp.path)!
        for case let rel as String in e {
            let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.sub(rel))
            result[rel] = (attrs?[.size] as? Int) ?? -1
        }
        return result
    }
}
