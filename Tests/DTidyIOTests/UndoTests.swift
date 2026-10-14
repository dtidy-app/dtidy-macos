import DTidyCore
import Darwin
import Foundation
import Testing
@testable import DTidyIO

extension Fixture {
    /// Sorts the root at a fixed clock so consecutive runs order deterministically.
    @discardableResult
    func sort(at time: Double = 1_800_000_000, ops: any FileOps = RealFileOps()) throws -> String {
        let service = SortService(ops: ops, environment: env, now: { time })
        return try #require(try service.run(config, dryRun: false).runId)
    }

    func undo(_ runId: String? = nil, dryRun: Bool = false, onConflict: ConflictPolicy = .suffix,
              byPath: Bool = false, ops: any FileOps = RealFileOps()) throws -> UndoReport {
        try UndoService(ops: ops, environment: env, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            .undo(runId: runId, dryRun: dryRun, onConflict: onConflict, byPath: byPath)
    }

    func mv(_ from: String, _ to: String) {
        try! FileManager.default.createDirectory(atPath: Paths.parent(Paths.join(root, to)), withIntermediateDirectories: true)
        try! FileManager.default.moveItem(atPath: Paths.join(root, from), toPath: Paths.join(root, to))
    }

    func safeSave(_ rel: String, _ contents: String) {
        let path = Paths.join(root, rel)
        let temp = path + ".new"
        try! Data(contents.utf8).write(to: URL(fileURLWithPath: temp))
        _ = try! FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: temp))
    }
}

@Suite struct UndoLocateTests {
    @Test func plainUndoRestoresAndRemovesFolders() throws {
        let f = Fixture()
        f.file("a.pdf", "A")
        f.file("photo.png", "P")
        let run = try f.sort()
        let report = try f.undo()
        #expect(report.target == run)
        #expect(report.entries.map(\.outcome) == [.restored, .restored])
        #expect(f.contents("a.pdf") == "A" && f.contents("photo.png") == "P")
        #expect(!f.exists("PDFs") && !f.exists("Images"))
        #expect(Set(report.removedFolders) == [Paths.join(f.root, "PDFs"), Paths.join(f.root, "Images")])
        #expect(f.isTracked("a.pdf"))
        #expect(f.store.load().sortRun(run)?.state == .reverted)
        #expect(report.isComplete)
    }

    @Test func fileRenamedIntoSubfolderIsFound() throws {
        let f = Fixture()
        f.file("invoice.pdf", "I")
        try f.sort()
        f.mv("PDFs/invoice.pdf", "PDFs/paid/invoice-2026.pdf")
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .restored)
        #expect(report.entries.first?.foundAt == Paths.join(f.root, "PDFs/paid/invoice-2026.pdf"))
        #expect(f.contents("invoice.pdf") == "I")
        #expect(f.exists("PDFs/paid"))
    }

    @Test func safeSavedFileIsFoundByDocumentID() throws {
        let f = Fixture()
        f.file("notes.txt", "v1")
        try f.sort()
        f.safeSave("Documents/notes.txt", "v2")
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .restored)
        #expect(f.contents("notes.txt") == "v2")
    }

    @Test func renamedThenSafeSavedFileIsFoundByScan() throws {
        let f = Fixture()
        f.file("notes.txt", "v1")
        try f.sort()
        f.mv("Documents/notes.txt", "Documents/2026/renamed.txt")
        f.safeSave("Documents/2026/renamed.txt", "v2")
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .restored)
        #expect(report.entries.first?.foundAt == Paths.join(f.root, "Documents/2026/renamed.txt"))
        #expect(f.contents("notes.txt") == "v2")
    }

    @Test func takenOriginalNameIsRestoredWithSuffix() throws {
        let f = Fixture()
        f.file("report.pdf", "old")
        try f.sort()
        f.file("report.pdf", "new")
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .restoredRenamed)
        #expect(f.contents("report.pdf") == "new")
        #expect(f.contents("report (restored).pdf") == "old")
    }

    @Test func secondConflictGetsNumberedSuffix() throws {
        let f = Fixture()
        f.file("report.pdf", "old")
        try f.sort()
        f.file("report.pdf", "new")
        f.file("report (restored).pdf", "other")
        #expect(try f.undo().entries.first?.restoredTo == Paths.join(f.root, "report (restored 2).pdf"))
    }

    @Test func conflictSkipLeavesEntryInPlace() throws {
        let f = Fixture()
        f.file("report.pdf", "old")
        let run = try f.sort()
        f.file("report.pdf", "new")
        let report = try f.undo(onConflict: .skip)
        #expect(report.entries.first?.outcome == .skippedConflict)
        #expect(f.contents("PDFs/report.pdf") == "old")
        #expect(f.store.load().sortRun(run)?.state == .partiallyReverted)
    }

    @Test func fileInTrashIsReportedNotRestored() throws {
        let f = Fixture()
        f.file("old.pdf")
        try f.sort()
        let trash = f.tmp.dir(".Trash")
        try FileManager.default.moveItem(atPath: Paths.join(f.root, "PDFs/old.pdf"), toPath: trash + "/old.pdf")
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .inTrash)
        #expect(report.entries.first?.foundAt == trash + "/old.pdf")
        #expect(FileManager.default.fileExists(atPath: trash + "/old.pdf"))
        #expect(!f.exists("old.pdf"))
    }

    @Test func deletedFileIsMissing() throws {
        let f = Fixture()
        f.file("gone.pdf")
        try f.sort()
        unlink(Paths.join(f.root, "PDFs/gone.pdf"))
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .missing)
        #expect(!f.exists("gone.pdf"))
        #expect(!report.isComplete)
    }

    @Test func fileInUnreadableFolderIsInaccessibleNotMissing() throws {
        let f = Fixture()
        f.file("secret.pdf")
        try f.sort()
        f.mv("PDFs/secret.pdf", "PDFs/locked/secret.pdf")
        chmod(Paths.join(f.root, "PDFs/locked"), 0o000)
        defer { chmod(Paths.join(f.root, "PDFs/locked"), 0o755) }
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .inaccessible)
        #expect(report.entries.first?.detail == "Permission denied")
    }

    @Test func replacedFileNeedsByPath() throws {
        let f = Fixture()
        f.file("a.pdf", "original")
        // Untracked (document ID 0): for tracked files the kernel carries the ID over to a
        // file recreated at the same path, so they are never "replaced".
        let ops = FaultyOps()
        ops.trackedFlagError = ENOTSUP
        let run = try f.sort(ops: ops)
        unlink(Paths.join(f.root, "PDFs/a.pdf"))
        f.file("PDFs/a.pdf", "different")
        #expect(try f.undo().entries.first?.outcome == .replaced)
        #expect(f.contents("PDFs/a.pdf") == "different")
        let second = try f.undo(run, byPath: true)
        #expect(second.entries.first?.outcome == .restored)
        #expect(f.contents("a.pdf") == "different")
    }

    @Test func trackedFileRecreatedAtSamePathCountsAsTheSameDocument() throws {
        let f = Fixture()
        f.file("a.pdf", "original")
        try f.sort()
        unlink(Paths.join(f.root, "PDFs/a.pdf"))
        f.file("PDFs/a.pdf", "rewritten")
        #expect(try f.undo().entries.first?.outcome == .restored)
        #expect(f.contents("a.pdf") == "rewritten")
    }

    @Test func foldersWithUserFilesStayAndDSStoreOnlyFoldersGo() throws {
        let f = Fixture()
        f.file("a.pdf")
        f.file("b.png")
        try f.sort()
        f.file("PDFs/mine.pdf")
        f.file("Images/.DS_Store")
        let report = try f.undo()
        #expect(f.exists("PDFs/mine.pdf"))
        #expect(!f.exists("Images"))
        #expect(report.removedFolders == [Paths.join(f.root, "Images")])
    }

    @Test func alreadyRestoredEntriesAreLeftAlone() throws {
        let f = Fixture()
        f.file("a.pdf", "A")
        let run = try f.sort()
        f.mv("PDFs/a.pdf", "a.pdf")
        let report = try f.undo()
        #expect(report.entries.first?.outcome == .alreadyRestored)
        #expect(f.store.load().sortRun(run)?.state == .reverted)
    }
}

@Suite struct UndoTargetTests {
    @Test func defaultTargetIsNewestUnrevertedRun() throws {
        let f = Fixture()
        f.file("a.pdf")
        let first = try f.sort(at: 1_800_000_000)
        f.file("b.pdf")
        let second = try f.sort(at: 1_800_000_100)
        #expect(try f.undo().target == second)
        #expect(f.exists("b.pdf") && f.exists("PDFs/a.pdf"))
        #expect(try f.undo().target == first)
        #expect(try f.undo().target == nil)
    }

    @Test func undoAndRecoverRunsAreNotTargets() throws {
        let f = Fixture()
        f.file("a.pdf")
        try f.sort()
        let undoRun = try #require(try f.undo().runId)
        do {
            _ = try f.undo(undoRun)
            Issue.record("expected refusal")
        } catch let error as DTidyError {
            #expect(error.exit == .usage)
        }
    }

    @Test func unknownRunIsAUsageError() {
        let f = Fixture()
        #expect { try f.undo("nope") } throws: { ($0 as? DTidyError)?.exit == .usage }
    }

    @Test func partialUndoRetriesOnlyUnresolvedEntries() throws {
        let f = Fixture()
        f.file("a.pdf")
        f.file("b.pdf")
        let run = try f.sort()
        f.mv("PDFs/b.pdf", "PDFs/locked/b.pdf")
        chmod(Paths.join(f.root, "PDFs/locked"), 0o000)
        let first = try f.undo()
        #expect(first.entries.map(\.outcome) == [.restored, .inaccessible])
        #expect(f.store.load().sortRun(run)?.state == .partiallyReverted)

        chmod(Paths.join(f.root, "PDFs/locked"), 0o755)
        let second = try f.undo(run)
        #expect(second.entries.map(\.seq) == [2])
        #expect(second.entries.first?.outcome == .restored)
        #expect(f.store.load().sortRun(run)?.state == .reverted)
        #expect(f.exists("a.pdf") && f.exists("b.pdf"))
    }

    @Test func interruptedRunMustBeRecoveredFirst() throws {
        let f = Fixture()
        f.file("a.pdf")
        let ops = FaultyOps()
        ops.crashAfterRenames = 0
        #expect(throws: SimulatedCrash.self) { try f.sort(ops: ops) }
        let run = try #require(f.store.load().interruptedSortRuns.first?.runId)
        #expect { try f.undo(run) } throws: { ($0 as? DTidyError)?.message.contains("dtidy recover") == true }
        #expect(try f.undo().target == nil)
    }
}

@Suite struct UndoDryRunTests {
    @Test func dryRunPredictsAndChangesNothing() throws {
        let f = Fixture()
        f.file("a.pdf", "old")
        f.file("b.png")
        try f.sort()
        f.file("a.pdf", "new")
        let before = f.snapshot()
        let report = try f.undo(dryRun: true)
        #expect(f.snapshot() == before)
        #expect(report.dryRun && report.runId == nil)
        #expect(report.entries.map(\.outcome) == [.restoredRenamed, .restored])
        #expect(report.entries.first?.restoredTo == Paths.join(f.root, "a (restored).pdf"))
        #expect(Set(report.removedFolders) == [Paths.join(f.root, "Images"), Paths.join(f.root, "PDFs")])
    }
}
