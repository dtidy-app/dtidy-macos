import DSortCore
import Darwin
import Foundation
import Testing
@testable import DSortIO

@Suite struct RunLockTests {
    @Test func secondHolderIsRefusedWithExitCode75() throws {
        let tmp = TempDir()
        let first = try RunLock.acquire(dataDirectory: tmp.path)
        #expect(RunLock.isHeld(dataDirectory: tmp.path))
        do {
            _ = try RunLock.acquire(dataDirectory: tmp.path)
            Issue.record("second lock should fail")
        } catch {
            #expect(error.exit == .lockHeld)
        }
        withExtendedLifetime(first) {}
    }

    @Test func lockIsReleasedWhenDropped() throws {
        let tmp = TempDir()
        do { _ = try RunLock.acquire(dataDirectory: tmp.path) }
        #expect(!RunLock.isHeld(dataDirectory: tmp.path))
        _ = try RunLock.acquire(dataDirectory: tmp.path)
    }
}

@Suite struct ExecutorTests {
    @Test func normalRunMovesEverythingAndRecordsIt() throws {
        let f = Fixture()
        f.file("invoice.pdf")
        f.file("photo.png")
        f.file("IMG_0001.jpg")
        let shot = f.file("Screenshot 2026-10-14 at 16.48.54.png")
        markScreenCapture(shot)
        f.tmp.dir("Desktop/Project")
        f.file(".hidden")
        f.file("fresh.pdf", age: 1)

        let report = try f.service().run(f.config, dryRun: false)
        let runId = try #require(report.runId)
        #expect(report.failedCount == 0)
        #expect(report.doneCount == 4)
        #expect(f.exists("PDFs/invoice.pdf"))
        #expect(f.exists("Images/photo.png"))
        #expect(f.exists("Images/_Inbox/IMG_0001.jpg"))
        #expect(f.exists("Images/_Screenshots/Screenshot 2026-10-14 at 16.48.54.png"))
        #expect(f.exists("Project") && f.exists(".hidden") && f.exists("fresh.pdf"))
        #expect(f.isTracked("PDFs/invoice.pdf"))

        let records = f.ledgerRecords(runId)
        let sealedAt = try #require(records.firstIndex(of: .sealed(moves: 4)))
        let firstMove = try #require(records.firstIndex { if case .move = $0 { return true }; return false })
        #expect(firstMove < sealedAt)
        #expect(records.last == .commit(["done": 4, "failed": 0]))
        let tracked = records.compactMap { r -> TrackInfo? in
            if case .tracked(_, let docid, let byUs) = r { return TrackInfo(docid: docid, byUs: byUs) }
            return nil
        }
        #expect(tracked.count == 4 && tracked.allSatisfy { $0.byUs && $0.docid != 0 })
        #expect(f.store.load().sortRun(runId)?.state == .committed)
    }

    @Test func nameTakenAfterPlanningIsRetargeted() throws {
        let f = Fixture()
        f.file("invoice.pdf", "mine")
        f.tmp.dir("Desktop/PDFs")
        let ops = FaultyOps()
        var raced = false
        ops.beforeRename = { _, to in
            if !raced, to.hasSuffix("PDFs/invoice.pdf") {
                raced = true
                try! Data("intruder".utf8).write(to: URL(fileURLWithPath: to))
            }
        }
        let report = try f.service(ops).run(f.config, dryRun: false)
        #expect(report.moves.map(\.dst) == [Paths.join(f.root, "PDFs/invoice (1).pdf")])
        #expect(f.contents("PDFs/invoice.pdf") == "intruder")
        #expect(f.contents("PDFs/invoice (1).pdf") == "mine")
        let records = f.ledgerRecords(report.runId!)
        #expect(records.contains(.retarget(seq: 1, dst: Paths.join(f.root, "PDFs/invoice (1).pdf"))))
        #expect(f.store.load().sortRun(report.runId!)?.destination(1) == Paths.join(f.root, "PDFs/invoice (1).pdf"))
    }

    @Test func crossVolumeMoveIsRefused() throws {
        let f = Fixture()
        f.file("invoice.pdf")
        f.file("photo.png")
        let ops = FaultyOps()
        ops.beforeRename = { from, _ in
            if from.hasSuffix("invoice.pdf") { throw SysError(EXDEV, "rename", from) }
        }
        let report = try f.service(ops).run(f.config, dryRun: false)
        #expect(report.failedCount == 1)
        #expect(report.moves.first { $0.src.hasSuffix("invoice.pdf") }?.reason == "cross-volume")
        #expect(f.exists("invoice.pdf"))
        #expect(f.exists("Images/photo.png"))
        #expect(f.ledgerRecords(report.runId!).contains(.fail(seq: 1, errno: EXDEV, reason: "cross-volume")))
    }

    @Test func alreadyTrackedFileIsNotChanged() throws {
        let f = Fixture()
        let p = f.file("notes.txt")
        #expect(try RealFileOps().addTrackedFlag(p))
        let report = try f.service().run(f.config, dryRun: false)
        let records = f.ledgerRecords(report.runId!)
        #expect(records.contains { if case .tracked(1, let d, false) = $0 { return d != 0 }; return false })
    }

    @Test func trackingFailureDoesNotBlockTheMove() throws {
        let f = Fixture()
        f.file("notes.txt")
        let ops = FaultyOps()
        ops.trackedFlagError = ENOTSUP
        let report = try f.service(ops).run(f.config, dryRun: false)
        #expect(report.doneCount == 1)
        #expect(f.ledgerRecords(report.runId!).contains(.tracked(seq: 1, docid: 0, byUs: false)))
    }

    @Test func itemChangedSinceScanIsNotMoved() throws {
        let f = Fixture()
        let p = f.file("a.pdf")
        let plan = try f.service().makePlan(f.config)
        unlink(p)
        f.file("a.pdf", "new file")
        let ledger = try f.store.create(runId: "r1")
        let report = try Executor().execute(plan, runId: "r1", ledger: ledger, startedAt: Date())
        #expect(report.moves.first?.reason == "changed")
        #expect(f.contents("a.pdf") == "new file")
    }

    @Test func nothingToSortWritesNoLedger() throws {
        let f = Fixture()
        f.file(".hidden")
        let report = try f.service().run(f.config, dryRun: false)
        #expect(report.runId == nil && report.moves.isEmpty)
        #expect(f.store.load().ledgers.isEmpty)
    }

    @Test func dryRunChangesNothingIncludingLockAndLedger() throws {
        let f = Fixture()
        f.file("invoice.pdf")
        let before = f.snapshot()
        let report = try f.service().run(f.config, dryRun: true)
        #expect(report.dryRun && report.moves.count == 1)
        #expect(f.snapshot() == before)
        #expect(!f.isTracked("invoice.pdf"))
    }
}

@Suite struct InterruptedRunTests {
    @Test func newSortIsRefusedUntilRecovered() throws {
        let f = Fixture()
        f.file("a.pdf")
        let w = try f.store.create(runId: "20260101T000000Z-aaaaaaaaaaaa")
        try w.append(.run(RunHeader(run: "20260101T000000Z-aaaaaaaaaaaa", kind: .sort, ts: "2026-01-01T00:00:00.000Z", root: f.root)))
        try w.append(.sealed(moves: 0))
        do {
            _ = try f.service().run(f.config, dryRun: false)
            Issue.record("expected refusal")
        } catch let error as DSortError {
            #expect(error.exit == .partial)
            #expect(error.message.contains("dsort recover"))
        }
        #expect(f.exists("a.pdf"))
    }
}
