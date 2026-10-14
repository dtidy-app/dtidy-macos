import DSortCore
import Foundation

/// Scans, classifies, and plans a sort; executing the plan is `Executor`'s job.
public struct SortService: Sendable {
    public let ops: any FileOps
    public let environment: Environment
    public let now: @Sendable () -> Double

    public init(
        ops: any FileOps = RealFileOps(), environment: Environment = .current,
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.ops = ops
        self.environment = environment
        self.now = now
    }

    public func makePlan(_ config: ResolvedConfig) throws(DSortError) -> Plan {
        let root = config.root
        let entries = try Scanner(ops: ops, environment: environment).scan(root)
        let classifier = Classifier(config)
        let time = now()
        let decisions = entries.map { classifier.classify($0, now: time) }

        var existing: [String: [String]] = [:]
        for dir in Planner.neededDirectories(decisions) {
            let path = Paths.join(root, dir)
            guard let info = try? ops.lstat(path) else { continue }
            // Something that is not a folder blocks the bucket; the move into it will fail
            // and be recorded, rather than dsort creating a second item with that name.
            existing[dir] = info.kind == .folder ? ((try? ops.listDirectory(path)) ?? []) : []
        }
        let caseSensitive = ops.volumeCapabilities(root)?.caseSensitive ?? false
        return Planner.plan(
            root: root, entries: entries, decisions: decisions, existing: existing, caseSensitive: caseSensitive)
    }

    /// Sorts the root: takes the run lock, refuses to start after an unrecovered crash,
    /// plans, and executes. A dry run only plans. A plan with no moves writes no ledger.
    public func run(_ config: ResolvedConfig, dryRun: Bool) throws -> RunReport {
        if dryRun { return RunReport(plan: try makePlan(config)) }

        let dataDirectory = Paths.dataDirectory(environment: environment)
        let lock = try RunLock.acquire(dataDirectory: dataDirectory)
        defer { withExtendedLifetime(lock) {} }

        let store = LedgerStore(environment: environment)
        if let interrupted = store.load().interruptedSortRuns.first {
            throw DSortError(.partial, """
                Run \(interrupted.runId) was interrupted before it finished. \
                Run `dsort recover` to reconcile it before sorting again.
                """)
        }

        let plan = try makePlan(config)
        var report = RunReport(plan: plan)
        report.dryRun = false
        guard !plan.moves.isEmpty else { return report }

        let started = Date(timeIntervalSince1970: now())
        let runId = RunID.make(at: started)
        let ledger = try store.create(runId: runId)
        return try Executor(ops: ops).execute(plan, runId: runId, ledger: ledger, startedAt: started)
    }
}
