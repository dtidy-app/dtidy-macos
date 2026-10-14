import DTidyCore
import Foundation
import Testing
@testable import DTidyIO

/// The history reads behind run-ID completion: they must tolerate bad files, create nothing,
/// and stay fast enough to run on every Tab.
@Suite struct RunIDCompletionTests {
    func writeSortLedger(_ dir: String, _ id: String, ts: String) throws {
        var data = Data()
        for record: LedgerRecord in [
            .run(RunHeader(run: id, kind: .sort, ts: ts, root: "/D")),
            .move(MoveRecord(seq: 1, src: "/D/a.pdf", dst: "/D/PDFs/a.pdf", rule: "type",
                             id: FileIdentity(fsid: [1, 2], ino: 3, birth: 4))),
            .sealed(moves: 1), .done(seq: 1), .commit(["done": 1]),
        ] {
            data += try LedgerCodec.line(record)
        }
        try data.write(to: URL(fileURLWithPath: dir + "/" + id + ".jsonl"))
    }

    @Test func unreadableAndCorruptLedgersAreSkipped() throws {
        let tmp = TempDir()
        let dir = tmp.dir("history")
        try writeSortLedger(dir, "good", ts: "2026-01-02T00:00:00.000Z")
        try writeSortLedger(dir, "locked", ts: "2026-01-03T00:00:00.000Z")
        chmod(dir + "/locked.jsonl", 0o000)
        tmp.file("history/garbage.jsonl", "not a ledger\n")

        let history = LedgerStore(directory: dir).load()
        #expect(history.allRunIds == ["good"])
        #expect(history.undoableRunIds == ["good"])
    }

    @Test func missingDataDirectoryYieldsNothingAndIsNotCreated() {
        let tmp = TempDir()
        let env = Environment(home: tmp.path, variables: ["XDG_DATA_HOME": tmp.sub("data")])
        let history = LedgerStore(environment: env).load()
        #expect(history.allRunIds.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: tmp.sub("data")))
    }

    @Test func thousandLedgersLoadQuickly() throws {
        let tmp = TempDir()
        let dir = tmp.dir("history")
        for i in 0..<1000 {
            try writeSortLedger(dir, String(format: "r%04d", i), ts: String(format: "2026-01-01T00:00:%02d.%03dZ", i / 1000, i % 1000))
        }
        let clock = ContinuousClock()
        var ids: [String] = []
        let elapsed = clock.measure { ids = LedgerStore(directory: dir).load().undoableRunIds }
        #expect(ids.count == 1000)
        // The budget applies to the shipped release build (`swift test -c release`). Unoptimized
        // debug builds derive run state several times slower, so they only guard against blowups.
        #if DEBUG
        let budget = Duration.seconds(1)
        #else
        let budget = Duration.milliseconds(100)
        #endif
        #expect(elapsed < budget, "loading 1,000 ledgers took \(elapsed)")
    }
}
