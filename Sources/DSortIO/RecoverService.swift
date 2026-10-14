import DSortCore
import Foundation

/// The result of reconciling one interrupted run.
public struct RecoveredRun: Codable, Sendable, Equatable {
    public var target: String
    public var runId: String
    public var moved: Int
    public var notMoved: Int
    public var lost: Int
}

/// Reconciles sort runs that stopped before their commit record, so they can be undone.
public struct RecoverService: Sendable {
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

    public func recover() throws -> [RecoveredRun] {
        let lock = try RunLock.acquire(dataDirectory: Paths.dataDirectory(environment: environment))
        defer { withExtendedLifetime(lock) {} }

        let store = LedgerStore(environment: environment)
        return try store.load().interruptedSortRuns.reversed().map { run in
            let started = now()
            let id = RunID.make(at: started)
            let ledger = try store.create(runId: id)
            var result = RecoveredRun(target: run.runId, runId: id, moved: 0, notMoved: 0, lost: 0)
            try write(ledger) {
                try ledger.appendDurably(.run(RunHeader(
                    run: id, kind: .recover, ts: RunID.timestamp(started), root: run.root, recovers: run.runId)))
                for move in run.moves {
                    let (state, at) = locate(move, in: run)
                    switch state {
                    case .moved: result.moved += 1
                    case .notMoved: result.notMoved += 1
                    case .lost: result.lost += 1
                    }
                    try ledger.append(.state(seq: move.seq, state: state, at: at))
                }
                try ledger.appendDurably(.commit([
                    "moved": result.moved, "not-moved": result.notMoved, "lost": result.lost,
                ]))
            }
            return result
        }
    }

    /// Each rename is atomic, so a planned file is either still at its source or moved.
    func locate(_ move: MoveRecord, in run: SortRun) -> (RecoveredState, String?) {
        let docid = run.tracked[move.seq]?.docid ?? 0
        let destination = run.destination(move.seq) ?? move.dst
        if let probe = probe(destination), Reconciler.matches(probe, recorded: move.id, docid: docid) {
            return (.moved, destination)
        }
        if let probe = probe(move.src), probe.identity.sameFile(as: move.id) {
            return (.notMoved, move.src)
        }
        // Moved by someone else since: let undo find it later.
        if let path = try? ops.pathForFile(fsid: move.id.fsid, ino: move.id.ino),
           let probe = probe(path), probe.identity.sameFile(as: move.id) {
            return (path == move.src ? .notMoved : .moved, path)
        }
        return (.lost, nil)
    }

    private func probe(_ path: String) -> Probe? {
        guard let info = try? ops.lstat(path), let fsid = try? ops.fsid(path) else { return nil }
        return Probe(identity: FileIdentity(fsid: fsid, ino: info.ino, birth: info.birth), docid: ops.documentID(path))
    }

    private func write(_ ledger: LedgerWriter, _ body: () throws -> Void) throws(DSortError) {
        do { try body() } catch {
            let reason = (error as? SysError)?.reason ?? "\(error)"
            throw DSortError(.partial, "Cannot write the recover ledger \(ledger.path): \(reason)")
        }
    }
}

extension Render {
    public static func text(_ runs: [RecoveredRun]) -> String {
        guard !runs.isEmpty else { return "Nothing to recover: no interrupted runs.\n" }
        return runs.map {
            "Recovered run \($0.target): \($0.moved) moved, \($0.notMoved) not moved, \($0.lost) not found. "
                + "It can now be undone with `dsort undo \($0.target)`."
        }.joined(separator: "\n") + "\n"
    }
}
