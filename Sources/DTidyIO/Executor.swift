import DTidyCore
import Darwin
import Foundation

/// Carries out a plan: records it durably, then moves each item with an exclusive rename.
public struct Executor: Sendable {
    public let ops: any FileOps

    public init(ops: any FileOps = RealFileOps()) {
        self.ops = ops
    }

    /// The highest collision suffix tried before giving up on a move.
    static let maxSuffix = 1000

    /// Executes `plan`, writing every step to `ledger`.
    ///
    /// Throws `DTidyError` if the ledger cannot be written. Any error from `FileOps` that is
    /// not a `SysError` aborts immediately without a commit record, as a crash would.
    public func execute(_ plan: Plan, runId: String, ledger: LedgerWriter, startedAt: Date) throws -> RunReport {
        // 1. The plan, flushed before anything changes on disk.
        try record(ledger) {
            try ledger.append(.run(RunHeader(run: runId, kind: .sort, ts: RunID.timestamp(startedAt), root: plan.root)))
            for dir in plan.mkdirs { try ledger.append(.mkdir(path: dir)) }
            for m in plan.moves {
                try ledger.append(.move(MoveRecord(seq: m.seq, src: m.src, dst: m.dst, rule: m.rule, id: m.identity)))
            }
            try ledger.appendDurably(.sealed(moves: plan.moves.count))
        }

        // 2. Bucket folders. A folder that already exists (made by someone else meanwhile) is fine.
        for dir in plan.mkdirs {
            do { try ops.makeDirectory(dir) } catch where error.code == EEXIST {}
            catch { /* the moves into it fail below with the real reason */ }
        }

        // 3. The moves.
        let rootDev = try? ops.lstat(plan.root).dev
        var reports: [MoveReport] = []
        var done = 0, failed = 0
        for move in plan.moves {
            var report = MoveReport(seq: move.seq, src: move.src, dst: move.dst, rule: move.rule, status: .done)
            switch try perform(move, rootDev: rootDev, ledger: ledger) {
            case .moved(let dst):
                report.dst = dst
                try record(ledger) { try ledger.append(.done(seq: move.seq)) }
                done += 1
            case .failed(let errno, let reason):
                report.status = .failed
                report.reason = reason
                try record(ledger) { try ledger.append(.fail(seq: move.seq, errno: errno, reason: reason)) }
                failed += 1
            }
            reports.append(report)
        }

        try record(ledger) { try ledger.appendDurably(.commit(["done": done, "failed": failed])) }
        return RunReport(dryRun: false, runId: runId, root: plan.root, mkdirs: plan.mkdirs, moves: reports, skips: plan.skips)
    }

    enum Outcome {
        case moved(String)
        case failed(Int32?, String)
    }

    private func perform(_ move: PlannedMove, rootDev: Int32?, ledger: LedgerWriter) throws -> Outcome {
        let bucket = Paths.parent(move.dst)
        guard let bucketInfo = try? ops.lstat(bucket), bucketInfo.kind == .folder else {
            return .failed(ENOTDIR, "bucket-unavailable")
        }
        if let rootDev, bucketInfo.dev != rootDev { return .failed(EXDEV, "cross-volume") }

        // The item must still be the one that was planned.
        guard let current = try? ops.lstat(move.src) else { return .failed(ENOENT, "vanished") }
        if current.ino != move.identity.ino || abs(current.birth - move.identity.birth) > 1e-6 {
            return .failed(nil, "changed")
        }

        // Track the file so its document ID survives later safe saves. Failure is not fatal:
        // undo then falls back to inode and birth time for this file.
        let byUs = (try? ops.addTrackedFlag(move.src)) ?? false
        let docid = ops.documentID(move.src)
        try record(ledger) { try ledger.append(.tracked(seq: move.seq, docid: docid, byUs: byUs)) }

        var destination = move.dst
        var n = 0
        while true {
            do {
                try ops.renameExclusive(move.src, destination)
                return .moved(destination)
            } catch let error as SysError where error.code == EEXIST {
                // Taken since planning: record the next name durably, then retry.
                n += 1
                guard n <= Self.maxSuffix else { return .failed(EEXIST, "no free name") }
                destination = Paths.join(bucket, SuffixNamer.numbered(move.name, n))
                try record(ledger) { try ledger.appendDurably(.retarget(seq: move.seq, dst: destination)) }
            } catch let error as SysError where error.code == EXDEV {
                return .failed(EXDEV, "cross-volume")
            } catch let error as SysError {
                return .failed(error.code, error.reason)
            }
        }
    }

    private func record(_ ledger: LedgerWriter, _ body: () throws -> Void) throws(DTidyError) {
        do { try body() } catch {
            let reason = (error as? SysError)?.reason ?? "\(error)"
            throw DTidyError(.partial, "Cannot write the run ledger \(ledger.path): \(reason). Run `dtidy recover`.")
        }
    }
}
