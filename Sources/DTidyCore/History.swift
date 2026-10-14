import Foundation

/// One parsed ledger file.
public struct LedgerFile: Sendable {
    public let header: RunHeader
    public let records: [LedgerRecord]
    public let truncatedTail: Bool
    public let corrupt: Bool

    /// Nil when the data does not start with a run header.
    public init?(_ data: Data) {
        let parsed = LedgerCodec.parse(data)
        guard case .run(let header)? = parsed.records.first else { return nil }
        self.header = header
        self.records = parsed.records
        self.truncatedTail = parsed.truncatedTail
        self.corrupt = parsed.corrupt
    }

    public var runId: String { header.run }

    public var commitCounts: [String: Int]? {
        for case .commit(let counts) in records.reversed() { return counts }
        return nil
    }
}

public enum RunState: String, Codable, Sendable {
    case committed
    case interrupted
    case recovered
    case reverted
    case partiallyReverted = "partially-reverted"
}

/// Tracking details recorded for one move.
public struct TrackInfo: Sendable, Equatable {
    public var docid: UInt32
    public var byUs: Bool

    public init(docid: UInt32, byUs: Bool) {
        self.docid = docid
        self.byUs = byUs
    }
}

/// A sort run, combined with everything later recover and undo ledgers recorded about it.
public struct SortRun: Sendable {
    public let header: RunHeader
    public let moves: [MoveRecord]
    public let mkdirs: [String]
    public let retargets: [Int: String]
    public let tracked: [Int: TrackInfo]
    public let done: Set<Int>
    public let failed: [Int: String]
    public let committed: Bool
    /// Per-seq results of `dtidy recover`, nil if the run was never recovered.
    public let recovered: [Int: (state: RecoveredState, at: String?)]?
    /// Seqs some undo already resolved (restored, restored-renamed, already-restored).
    public let resolved: Set<Int>
    /// The most recent undo outcome per seq.
    public let lastUndo: [Int: UndoOutcome]
    /// Every path an undo restored (or tried to restore) each seq to.
    public let restoreTargets: [Int: [String]]
    public let undoAttempted: Bool

    public var runId: String { header.run }
    public var root: String { header.root }

    /// Where the move put (or meant to put) the file: the retargeted name if any.
    public func destination(_ seq: Int) -> String? {
        retargets[seq] ?? moves.first { $0.seq == seq }?.dst
    }

    /// The entries an undo has to deal with: completed moves, or for a recovered run, what
    /// recovery found moved or could not find.
    public var movedSeqs: [Int] {
        let seqs: Set<Int>
        if let recovered {
            seqs = Set(recovered.filter { $0.value.state != .notMoved }.keys)
        } else {
            seqs = done
        }
        return seqs.sorted()
    }

    public var isFinished: Bool { committed || recovered != nil }

    public var state: RunState {
        guard isFinished else { return .interrupted }
        let moved = movedSeqs
        if !moved.isEmpty && Set(moved).isSubset(of: resolved) { return .reverted }
        if undoAttempted { return .partiallyReverted }
        return committed ? .committed : .recovered
    }
}

/// Summary of one run for `dtidy history`.
public struct RunSummary: Codable, Sendable, Equatable {
    public var runId: String
    public var kind: RunKind
    public var startedAt: String
    public var state: RunState
    public var counts: [String: Int]
    public var target: String?
}

/// All ledgers in the history directory, newest first.
public struct History: Sendable {
    public let ledgers: [LedgerFile]

    public init(_ ledgers: [LedgerFile]) {
        self.ledgers = ledgers.sorted { ($0.header.ts, $0.runId) > ($1.header.ts, $1.runId) }
    }

    public func ledger(_ runId: String) -> LedgerFile? {
        ledgers.first { $0.runId == runId }
    }

    public var sortRuns: [SortRun] {
        ledgers.filter { $0.header.kind == .sort }.compactMap { sortRun($0.runId) }
    }

    /// Sort runs that stopped before committing and were never recovered.
    public var interruptedSortRuns: [SortRun] {
        sortRuns.filter { $0.state == .interrupted }
    }

    /// Combines a sort run's own ledger with the recover and undo ledgers that reference it.
    public func sortRun(_ runId: String) -> SortRun? {
        guard let file = ledger(runId), file.header.kind == .sort else { return nil }
        var moves: [MoveRecord] = [], mkdirs: [String] = []
        var retargets: [Int: String] = [:], tracked: [Int: TrackInfo] = [:]
        var done: Set<Int> = [], failed: [Int: String] = [:]
        for record in file.records {
            switch record {
            case .move(let m): moves.append(m)
            case .mkdir(let path): mkdirs.append(path)
            case .retarget(let seq, let dst): retargets[seq] = dst
            case .tracked(let seq, let docid, let byUs): tracked[seq] = TrackInfo(docid: docid, byUs: byUs)
            case .done(let seq): done.insert(seq)
            case .fail(let seq, _, let reason): failed[seq] = reason
            default: break
            }
        }

        var recovered: [Int: (state: RecoveredState, at: String?)]?
        var resolved: Set<Int> = [], lastUndo: [Int: UndoOutcome] = [:], targets: [Int: [String]] = [:]
        var undoAttempted = false
        // Oldest first, so later undo outcomes overwrite earlier ones.
        for other in ledgers.reversed() {
            if other.header.recovers == runId, other.commitCounts != nil {
                var states: [Int: (state: RecoveredState, at: String?)] = [:]
                for case .state(let seq, let state, let at) in other.records { states[seq] = (state, at) }
                recovered = states
            }
            if other.header.reverts == runId {
                undoAttempted = true
                for record in other.records {
                    switch record {
                    case .restore(let seq, _, let to): targets[seq, default: []].append(to)
                    case .undone(let seq, let outcome, _, let to, _):
                        lastUndo[seq] = outcome
                        if outcome.resolves { resolved.insert(seq) }
                        if let to, outcome.resolves { targets[seq, default: []].append(to) }
                    default: break
                    }
                }
            }
        }

        return SortRun(
            header: file.header, moves: moves, mkdirs: mkdirs, retargets: retargets, tracked: tracked,
            done: done, failed: failed, committed: file.commitCounts != nil, recovered: recovered,
            resolved: resolved, lastUndo: lastUndo, restoreTargets: targets, undoAttempted: undoAttempted)
    }

    public func summary(_ file: LedgerFile) -> RunSummary {
        let h = file.header
        switch h.kind {
        case .sort:
            let run = sortRun(file.runId)!
            var counts = ["planned": run.moves.count, "done": run.done.count, "failed": run.failed.count]
            if let recovered = run.recovered {
                counts = ["planned": run.moves.count]
                for (_, value) in recovered { counts[value.state.rawValue, default: 0] += 1 }
            }
            if run.undoAttempted { counts["reverted"] = run.resolved.count }
            return RunSummary(runId: h.run, kind: h.kind, startedAt: h.ts, state: run.state, counts: counts)
        case .undo, .recover:
            var counts = file.commitCounts ?? [:]
            if file.commitCounts == nil {
                for record in file.records {
                    if case .undone(_, let outcome, _, _, _) = record { counts[outcome.rawValue, default: 0] += 1 }
                    if case .state(_, let state, _) = record { counts[state.rawValue, default: 0] += 1 }
                }
            }
            return RunSummary(
                runId: h.run, kind: h.kind, startedAt: h.ts,
                state: file.commitCounts == nil ? .interrupted : .committed,
                counts: counts, target: h.reverts ?? h.recovers)
        }
    }

    public var summaries: [RunSummary] { ledgers.map(summary) }
}
