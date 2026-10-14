import DTidyCore
import Darwin
import Foundation

public enum ConflictPolicy: String, Sendable, CaseIterable {
    /// Restore as `name (restored).ext` when the original name is taken.
    case suffix
    /// Leave the entry in place and report it.
    case skip
}

/// Reverses a sort run.
public struct UndoService: Sendable {
    public let ops: any FileOps
    public let environment: Environment
    public let now: @Sendable () -> Date

    public init(
        ops: any FileOps = RealFileOps(), environment: Environment = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ops = ops
        self.environment = environment
        self.now = now
    }

    public func undo(
        runId: String?, dryRun: Bool, onConflict: ConflictPolicy = .suffix, byPath: Bool = false
    ) throws -> UndoReport {
        let lock = dryRun ? nil : try RunLock.acquire(dataDirectory: Paths.dataDirectory(environment: environment))
        defer { withExtendedLifetime(lock) {} }

        let store = LedgerStore(environment: environment)
        guard let run = try Self.target(store.load(), explicit: runId) else {
            return UndoReport(dryRun: dryRun)
        }
        let pending = run.movedSeqs.filter { !run.resolved.contains($0) }
        let moves = Dictionary(uniqueKeysWithValues: run.moves.map { ($0.seq, $0) })
        var report = UndoReport(dryRun: dryRun, target: run.runId, root: run.root)

        let ledger: LedgerWriter?
        if dryRun {
            ledger = nil
        } else {
            let started = now()
            let id = RunID.make(at: started)
            ledger = try store.create(runId: id)
            report.runId = id
            try record(ledger) {
                try $0.appendDurably(.run(RunHeader(
                    run: id, kind: .undo, ts: RunID.timestamp(started), root: run.root, reverts: run.runId)))
            }
        }

        for seq in pending {
            guard let move = moves[seq] else { continue }
            let action = Reconciler.action(
                for: locate(move, in: run), restored: [move.src] + (run.restoreTargets[seq] ?? []), byPath: byPath)
            let entry = try perform(action, move: move, policy: onConflict, ledger: ledger)
            report.entries.append(entry)
        }

        let leaving = Set(report.entries.filter { $0.outcome.resolves && $0.outcome != .alreadyRestored }.compactMap(\.foundAt))
        report.removedFolders = try removeEmptyFolders(run.mkdirs, leaving: leaving, dryRun: dryRun, ledger: ledger)
        try record(ledger) { try $0.appendDurably(.commit(report.counts)) }
        return report
    }

    /// The sort run to undo: the explicit one, or the newest finished run that still has
    /// unresolved entries. Nil means there is nothing to undo.
    static func target(_ history: History, explicit: String?) throws(DTidyError) -> SortRun? {
        if let explicit {
            guard let file = history.ledger(explicit) else {
                throw DTidyError(.usage, "No run with ID \(explicit). List runs with `dtidy history`.")
            }
            guard file.header.kind == .sort, let run = history.sortRun(explicit) else {
                throw DTidyError(.usage, "Run \(explicit) is a \(file.header.kind.rawValue) run; only sort runs can be undone.")
            }
            guard run.isFinished else {
                throw DTidyError(.partial, "Run \(explicit) was interrupted. Run `dtidy recover` first, then undo it.")
            }
            return run.state == .reverted || run.movedSeqs.isEmpty ? nil : run
        }
        return history.sortRuns.first { $0.isFinished && $0.state != .reverted && !$0.movedSeqs.isEmpty }
    }

    // MARK: - Locating

    func probe(_ path: String) -> Probe? {
        guard let info = try? ops.lstat(path), let fsid = try? ops.fsid(path) else { return nil }
        return Probe(identity: FileIdentity(fsid: fsid, ino: info.ino, birth: info.birth), docid: ops.documentID(path))
    }

    func locate(_ move: MoveRecord, in run: SortRun) -> Location {
        let destination = run.destination(move.seq) ?? move.dst
        let known = [destination, move.src] + (run.restoreTargets[move.seq] ?? [])
        return Reconciler.locate(
            recorded: move.id, docid: run.tracked[move.seq]?.docid ?? 0,
            candidates: known.map { (path: $0, probe: probe($0)) },
            lookup: {
                let path: String
                do throws(SysError) {
                    path = try ops.pathForFile(fsid: move.id.fsid, ino: move.id.ino)
                } catch {
                    return error.code == ENOENT ? .notFound : .error(error.reason)
                }
                return .path(path, probe(path))
            },
            scan: { ops.findDocument(run.tracked[move.seq]?.docid ?? 0, under: bucketRoots(run)) })
    }

    /// The top-level bucket folders the run created or moved files into.
    func bucketRoots(_ run: SortRun) -> [String] {
        let paths = run.mkdirs + run.moves.compactMap { run.destination($0.seq) }
        let tops = Set(paths.compactMap { path -> String? in
            Render.relative(path, to: run.root).split(separator: "/").first.map { Paths.join(run.root, String($0)) }
        })
        return tops.sorted().filter { (try? ops.lstat($0))?.kind == .folder }
    }

    // MARK: - Acting

    private func perform(_ action: UndoAction, move: MoveRecord, policy: ConflictPolicy, ledger: LedgerWriter?) throws -> UndoEntryReport {
        var entry = UndoEntryReport(seq: move.seq, src: move.src, outcome: .missing)
        switch action {
        case .report(let outcome, let at, let detail):
            entry.outcome = outcome
            entry.foundAt = at
            entry.detail = detail ?? hint(for: outcome)

        case .restore(let from):
            entry.foundAt = from
            let name = Paths.lastComponent(move.src)
            let parent = Paths.parent(move.src)
            let limit = policy == .skip ? 0 : Executor.maxSuffix
            var n = 0
            while true {
                let target = n == 0 ? move.src : Paths.join(parent, SuffixNamer.restored(name, n))
                if let ledger {
                    try record(ledger) { try $0.appendDurably(.restore(seq: move.seq, from: from, to: target)) }
                    do {
                        try ops.renameExclusive(from, target)
                    } catch let error as SysError where error.code == EEXIST {
                        n += 1
                        if n > limit { entry.outcome = .skippedConflict; entry.detail = "\(name) is taken"; break }
                        continue
                    } catch let error as SysError {
                        entry.outcome = .failed
                        entry.detail = error.reason
                        break
                    }
                } else if (try? ops.lstat(target)) != nil {
                    // Dry run: predict the name the restore would get.
                    n += 1
                    if n > limit { entry.outcome = .skippedConflict; entry.detail = "\(name) is taken"; break }
                    continue
                }
                entry.restoredTo = target
                entry.outcome = n == 0 ? .restored : .restoredRenamed
                break
            }
        }

        try record(ledger) {
            try $0.append(.undone(seq: move.seq, outcome: entry.outcome, from: entry.foundAt, to: entry.restoredTo, detail: entry.detail))
        }
        return entry
    }

    private func hint(for outcome: UndoOutcome) -> String? {
        switch outcome {
        case .inTrash: "in the Trash; put it back from there if you want it"
        case .missing: "the file no longer exists"
        case .replaced: "a different file is at the recorded place; use --by-path to restore it anyway"
        default: nil
        }
    }

    /// Removes the folders the run created, deepest first, when they are empty. A folder that
    /// holds only Finder's `.DS_Store` counts as empty. `leaving` lists files a dry run would
    /// have restored, so the prediction matches a real undo.
    private func removeEmptyFolders(
        _ mkdirs: [String], leaving: Set<String>, dryRun: Bool, ledger: LedgerWriter?
    ) throws -> [String] {
        var removed: [String] = []
        for dir in mkdirs.sorted(by: { $0.split(separator: "/").count > $1.split(separator: "/").count }) {
            guard let names = try? ops.listDirectory(dir) else { continue }
            let gone = leaving.union(removed)
            let remaining = names.filter { !gone.contains(Paths.join(dir, $0)) }
            guard remaining.isEmpty || remaining == [".DS_Store"] else { continue }
            if dryRun {
                removed.append(dir)
                continue
            }
            if remaining == [".DS_Store"] { unlink(Paths.join(dir, ".DS_Store")) }
            if (try? ops.removeDirectory(dir)) != nil {
                removed.append(dir)
                try record(ledger) { try $0.append(.rmdir(path: dir)) }
            }
        }
        return removed
    }

    private func record(_ ledger: LedgerWriter?, _ body: (LedgerWriter) throws -> Void) throws(DTidyError) {
        guard let ledger else { return }
        do { try body(ledger) } catch {
            let reason = (error as? SysError)?.reason ?? "\(error)"
            throw DTidyError(.partial, "Cannot write the undo ledger \(ledger.path): \(reason)")
        }
    }
}
