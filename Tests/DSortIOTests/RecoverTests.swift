import DSortCore
import Foundation
import Testing
@testable import DSortIO

@Suite struct RecoverTests {
    @Test func crashAfterTwelveOfThirtyMovesIsRecoveredAndUndone() throws {
        let f = Fixture()
        for i in 1...30 { f.file(String(format: "doc%02d.pdf", i), "\(i)") }
        let ops = FaultyOps()
        ops.crashAfterRenames = 12
        #expect(throws: SimulatedCrash.self) { try f.sort(ops: ops) }

        let interrupted = try #require(f.store.load().interruptedSortRuns.first)
        #expect(f.store.load().sortRun(interrupted.runId)?.state == .interrupted)
        #expect { try f.sort() } throws: { ($0 as? DSortError)?.message.contains("dsort recover") == true }

        let recovered = try RecoverService(environment: f.env).recover()
        #expect(recovered.map(\.moved) == [12])
        #expect(recovered.map(\.notMoved) == [18])
        #expect(recovered.map(\.lost) == [0])
        #expect(f.store.load().sortRun(interrupted.runId)?.state == .recovered)
        #expect(try RecoverService(environment: f.env).recover().isEmpty)

        let undo = try f.undo()
        #expect(undo.target == interrupted.runId)
        #expect(undo.entries.count == 12)
        #expect(undo.entries.allSatisfy { $0.outcome == .restored })
        for i in 1...30 { #expect(f.contents(String(format: "doc%02d.pdf", i)) == "\(i)") }
        #expect(!f.exists("PDFs"))
        #expect(f.store.load().sortRun(interrupted.runId)?.state == .reverted)
    }

    @Test func fileMovedElsewhereAfterCrashIsCountedAsMoved() throws {
        let f = Fixture()
        f.file("a.pdf")
        let ops = FaultyOps()
        ops.crashAfterRenames = 1
        f.file("b.pdf")
        #expect(throws: SimulatedCrash.self) { try f.sort(ops: ops) }
        f.mv("PDFs/a.pdf", "PDFs/sub/a.pdf")
        let recovered = try RecoverService(environment: f.env).recover()
        #expect(recovered.first?.moved == 1 && recovered.first?.notMoved == 1)
        #expect(try f.undo().entries.first?.foundAt == Paths.join(f.root, "PDFs/sub/a.pdf"))
    }
}
