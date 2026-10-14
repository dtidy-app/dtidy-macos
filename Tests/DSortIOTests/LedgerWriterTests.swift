import DSortCore
import Foundation
import Testing
@testable import DSortIO

@Suite struct LedgerWriterTests {
    @Test func writerIsAppendOnlyAndRefusesExistingFiles() throws {
        let tmp = TempDir()
        let writer = try LedgerWriter.create(in: tmp.sub("history"), runId: "r1")
        #expect(writer.isAppendOnly)
        try writer.append(.run(RunHeader(run: "r1", kind: .sort, ts: "t", root: "/D")))
        try writer.appendDurably(.sealed(moves: 0))
        #expect(throws: SysError.self) { try LedgerWriter.create(in: tmp.sub("history"), runId: "r1") }

        let file = try #require(LedgerFile(try Data(contentsOf: URL(fileURLWithPath: writer.path))))
        #expect(file.records.count == 2)
        let mode = try FileManager.default.attributesOfItem(atPath: writer.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func storeLoadsEveryLedger() throws {
        let tmp = TempDir()
        let store = LedgerStore(directory: tmp.sub("history"))
        for (id, ts) in [("a", "2026-01-01T00:00:00.000Z"), ("b", "2026-01-02T00:00:00.000Z")] {
            let w = try store.create(runId: id)
            try w.append(.run(RunHeader(run: id, kind: .sort, ts: ts, root: "/D")))
        }
        try Data("junk".utf8).write(to: URL(fileURLWithPath: tmp.sub("history/notes.txt")))
        #expect(store.load().ledgers.map(\.runId) == ["b", "a"])
    }
}
