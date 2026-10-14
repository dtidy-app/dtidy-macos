import Foundation
import Testing
@testable import DSortCore

let ident = FileIdentity(fsid: [16777230, 26], ino: 123456, birth: 1767225600.25)

func move(_ seq: Int, _ name: String = "a.pdf") -> MoveRecord {
    MoveRecord(seq: seq, src: "/D/\(name)", dst: "/D/PDFs/\(name)", rule: "type", id: ident)
}

func ledger(_ records: [LedgerRecord], tail: String = "") -> LedgerFile {
    var data = Data()
    for r in records { data += try! LedgerCodec.line(r) }
    return LedgerFile(data + Data(tail.utf8))!
}

func header(_ run: String, _ kind: RunKind, ts: String, reverts: String? = nil, recovers: String? = nil) -> LedgerRecord {
    .run(RunHeader(run: run, kind: kind, ts: ts, root: "/D", reverts: reverts, recovers: recovers))
}

@Suite struct RunIDTests {
    @Test func formatStartsWithUTCTime() {
        let date = Date(timeIntervalSince1970: 1_792_004_952) // 2026-10-14T19:09:12Z
        let id = RunID.make(at: date, random: 0x3f9a)
        #expect(id == "20261014T190912Z-000000003f9a")
    }

    @Test func thousandIDsInOneSecondAreUnique() {
        let date = Date()
        let ids = (0..<1000).map { _ in RunID.make(at: date) }
        #expect(Set(ids).count == 1000)
        #expect(Set(ids.map { $0.prefix(16) }).count == 1)
    }

    @Test func timestampsSortChronologically() {
        let a = RunID.timestamp(Date(timeIntervalSince1970: 1_791_996_552.1))
        let b = RunID.timestamp(Date(timeIntervalSince1970: 1_791_996_552.9))
        #expect(a < b)
        #expect(a.hasSuffix("Z"))
    }
}

@Suite struct DataPathTests {
    @Test func defaultDataDirectory() {
        let env = Environment(home: "/Users/t", variables: [:])
        #expect(Paths.historyDirectory(environment: env) == "/Users/t/Library/Application Support/dsort/history")
    }

    @Test func xdgDataHomeOverride() {
        let env = Environment(home: "/Users/t", variables: ["XDG_DATA_HOME": "/tmp/x"])
        #expect(Paths.historyDirectory(environment: env) == "/tmp/x/dsort/history")
        let empty = Environment(home: "/Users/t", variables: ["XDG_DATA_HOME": ""])
        #expect(Paths.dataDirectory(environment: empty) == "/Users/t/Library/Application Support/dsort")
    }
}

@Suite struct LedgerCodecTests {
    @Test func everyRecordTypeRoundTrips() throws {
        let records: [LedgerRecord] = [
            header("r1", .sort, ts: "2026-10-14T19:09:12.000Z"),
            .run(RunHeader(run: "u1", kind: .undo, ts: "t", root: "/D", reverts: "r1")),
            .mkdir(path: "/D/PDFs"),
            .move(move(1)),
            .sealed(moves: 1),
            .tracked(seq: 1, docid: 296, byUs: true),
            .retarget(seq: 1, dst: "/D/PDFs/a (1).pdf"),
            .done(seq: 1),
            .fail(seq: 2, errno: 18, reason: "cross-volume"),
            .fail(seq: 3, errno: nil, reason: "changed"),
            .restore(seq: 1, from: "/D/PDFs/a.pdf", to: "/D/a.pdf"),
            .undone(seq: 1, outcome: .restoredRenamed, from: "/D/PDFs/a.pdf", to: "/D/a (restored).pdf", detail: nil),
            .undone(seq: 2, outcome: .inaccessible, from: nil, to: nil, detail: "Permission denied"),
            .rmdir(path: "/D/PDFs"),
            .state(seq: 1, state: .notMoved, at: "/D/a.pdf"),
            .commit(["done": 41, "failed": 1]),
        ]
        for record in records {
            let line = try LedgerCodec.line(record)
            #expect(line.last == UInt8(ascii: "\n"))
            #expect(line.dropLast().contains(UInt8(ascii: "\n")) == false)
            #expect(try JSONDecoder().decode(LedgerRecord.self, from: line) == record)
        }
    }

    @Test func commitIsFlat() throws {
        let line = String(decoding: try LedgerCodec.line(.commit(["done": 41, "failed": 1])), as: UTF8.self)
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        #expect(object["t"] as? String == "commit")
        #expect(object["done"] as? Int == 41)
    }

    @Test func truncatedLastLineIsIgnored() {
        let file = ledger([header("r1", .sort, ts: "t"), .move(move(1)), .sealed(moves: 1)], tail: #"{"t":"done","se"#)
        #expect(file.truncatedTail)
        #expect(!file.corrupt)
        #expect(file.records.count == 3)
    }

    @Test func completeLineWithoutNewlineCountsAsTruncated() {
        let file = ledger([header("r1", .sort, ts: "t")], tail: #"{"t":"sealed","moves":0}"#)
        #expect(file.truncatedTail)
        #expect(file.records.count == 1)
    }

    @Test func badMiddleLineMarksCorrupt() {
        let file = ledger([header("r1", .sort, ts: "t")], tail: "garbage\n" + String(decoding: try! LedgerCodec.line(.sealed(moves: 0)), as: UTF8.self))
        #expect(file.corrupt)
        #expect(file.records.count == 2)
    }

    @Test func fileWithoutHeaderIsRejected() {
        #expect(LedgerFile(Data("not json\n".utf8)) == nil)
        #expect(LedgerFile(try! LedgerCodec.line(.sealed(moves: 0))) == nil)
    }
}

@Suite struct RunStateTests {
    let sortRecords: [LedgerRecord] = [
        header("r1", .sort, ts: "2026-01-01T00:00:00.000Z"),
        .mkdir(path: "/D/PDFs"), .move(move(1, "a.pdf")), .move(move(2, "b.pdf")), .sealed(moves: 2),
        .tracked(seq: 1, docid: 9, byUs: true), .done(seq: 1),
        .fail(seq: 2, errno: 18, reason: "cross-volume"),
    ]

    @Test func uncommittedRunIsInterrupted() {
        let history = History([ledger(sortRecords, tail: #"{"t":"com"#)])
        #expect(history.sortRun("r1")?.state == .interrupted)
        #expect(history.interruptedSortRuns.map(\.runId) == ["r1"])
        #expect(history.summaries.first?.state == .interrupted)
    }

    @Test func committedRun() {
        let run = History([ledger(sortRecords + [.commit(["done": 1, "failed": 1])])]).sortRun("r1")!
        #expect(run.state == .committed)
        #expect(run.movedSeqs == [1])
        #expect(run.tracked[1] == TrackInfo(docid: 9, byUs: true))
        #expect(run.failed[2] == "cross-volume")
    }

    @Test func undoReferencingSortRunRevertsIt() {
        let sort = ledger(sortRecords + [.commit(["done": 1, "failed": 1])])
        let undo = ledger([
            header("u1", .undo, ts: "2026-01-02T00:00:00.000Z", reverts: "r1"),
            .restore(seq: 1, from: "/D/PDFs/a.pdf", to: "/D/a.pdf"),
            .undone(seq: 1, outcome: .restored, from: "/D/PDFs/a.pdf", to: "/D/a.pdf", detail: nil),
            .commit(["restored": 1]),
        ])
        let history = History([sort, undo])
        #expect(history.sortRun("r1")?.state == .reverted)
        #expect(history.summaries.map(\.runId) == ["u1", "r1"])
        #expect(history.summaries[0].target == "r1")
    }

    @Test func unresolvedEntryLeavesRunPartiallyReverted() {
        var records = sortRecords
        records.append(contentsOf: [.done(seq: 2), .commit(["done": 2])])
        records.removeAll { $0 == .fail(seq: 2, errno: 18, reason: "cross-volume") }
        let undo = ledger([
            header("u1", .undo, ts: "2026-01-02T00:00:00.000Z", reverts: "r1"),
            .undone(seq: 1, outcome: .restored, from: nil, to: "/D/a.pdf", detail: nil),
            .undone(seq: 2, outcome: .missing, from: nil, to: nil, detail: nil),
        ])
        let run = History([ledger(records), undo]).sortRun("r1")!
        #expect(run.state == .partiallyReverted)
        #expect(run.resolved == [1])
        #expect(run.lastUndo[2] == .missing)
        #expect(run.restoreTargets[1] == ["/D/a.pdf"])
    }

    @Test func recoverLedgerMakesRunRecovered() {
        let recover = ledger([
            header("c1", .recover, ts: "2026-01-02T00:00:00.000Z", recovers: "r1"),
            .state(seq: 1, state: .moved, at: "/D/PDFs/a.pdf"),
            .state(seq: 2, state: .notMoved, at: "/D/b.pdf"),
            .commit(["moved": 1, "not-moved": 1]),
        ])
        let history = History([ledger(sortRecords), recover])
        let run = history.sortRun("r1")!
        #expect(run.state == .recovered)
        #expect(run.movedSeqs == [1])
        #expect(history.interruptedSortRuns.isEmpty)
    }

    @Test func retargetedDestinationWins() {
        let run = History([ledger(sortRecords + [.retarget(seq: 1, dst: "/D/PDFs/a (1).pdf")])]).sortRun("r1")!
        #expect(run.destination(1) == "/D/PDFs/a (1).pdf")
        #expect(run.destination(2) == "/D/PDFs/b.pdf")
    }
}

@Suite struct RunDetailTests {
    @Test func sortDetailShowsActualDestinationsAndUndoOutcome() throws {
        let sort = ledger([
            header("r1", .sort, ts: "2026-01-01T00:00:00.000Z"), .move(move(1)), .move(move(2, "b.pdf")),
            .sealed(moves: 2), .tracked(seq: 1, docid: 296, byUs: true), .retarget(seq: 1, dst: "/D/PDFs/a (1).pdf"),
            .done(seq: 1), .commit(["done": 1]),
        ])
        let undo = ledger([
            header("u1", .undo, ts: "2026-01-02T00:00:00.000Z", reverts: "r1"),
            .undone(seq: 1, outcome: .inTrash, from: "/Users/t/.Trash/a.pdf", to: nil, detail: nil),
        ])
        let history = History([sort, undo])
        let detail = try #require(history.detail("r1"))
        #expect(detail.moves?.map(\.dst) == ["/D/PDFs/a (1).pdf", "/D/PDFs/b.pdf"])
        #expect(detail.moves?.map(\.status) == ["done", "pending"])
        #expect(detail.moves?.first?.docid == 296)
        #expect(detail.moves?.first?.undo == .inTrash)
        #expect(history.detail("u1")?.entries?.map(\.outcome) == [.inTrash])
        #expect(history.detail("nope") == nil)
    }
}
