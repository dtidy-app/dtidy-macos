/// Everything one run recorded, for `dtidy show`.
public struct RunDetail: Codable, Sendable, Equatable {
    public struct Move: Codable, Sendable, Equatable {
        public var seq: Int
        public var src: String
        public var plannedDst: String
        public var dst: String
        public var rule: String
        /// done, failed, pending (interrupted), or a recovered state.
        public var status: String
        public var reason: String?
        public var docid: UInt32?
        public var trackedByUs: Bool?
        /// The latest undo outcome for this entry, if an undo touched it.
        public var undo: UndoOutcome?
    }

    public struct UndoEntry: Codable, Sendable, Equatable {
        public var seq: Int
        public var outcome: UndoOutcome
        public var from: String?
        public var to: String?
        public var detail: String?
    }

    public struct RecoverEntry: Codable, Sendable, Equatable {
        public var seq: Int
        public var state: RecoveredState
        public var at: String?
    }

    public var summary: RunSummary
    public var root: String
    public var moves: [Move]?
    public var entries: [UndoEntry]?
    public var states: [RecoverEntry]?
}

extension History {
    public func detail(_ runId: String) -> RunDetail? {
        guard let file = ledger(runId) else { return nil }
        var detail = RunDetail(summary: summary(file), root: file.header.root)
        switch file.header.kind {
        case .sort:
            let run = sortRun(runId)!
            detail.moves = run.moves.map { m in
                var status = run.done.contains(m.seq) ? "done" : run.failed[m.seq] != nil ? "failed" : "pending"
                if let state = run.recovered?[m.seq]?.state { status = state.rawValue }
                return RunDetail.Move(
                    seq: m.seq, src: m.src, plannedDst: m.dst, dst: run.destination(m.seq) ?? m.dst, rule: m.rule,
                    status: status, reason: run.failed[m.seq], docid: run.tracked[m.seq]?.docid,
                    trackedByUs: run.tracked[m.seq]?.byUs, undo: run.lastUndo[m.seq])
            }
        case .undo:
            detail.entries = file.records.compactMap {
                guard case .undone(let seq, let outcome, let from, let to, let text) = $0 else { return nil }
                return RunDetail.UndoEntry(seq: seq, outcome: outcome, from: from, to: to, detail: text)
            }
        case .recover:
            detail.states = file.records.compactMap {
                guard case .state(let seq, let state, let at) = $0 else { return nil }
                return RunDetail.RecoverEntry(seq: seq, state: state, at: at)
            }
        }
        return detail
    }
}

extension Render {
    static func counts(_ counts: [String: Int]) -> String {
        counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    public static func text(_ summaries: [RunSummary]) -> String {
        guard !summaries.isEmpty else { return "No runs recorded yet.\n" }
        let rows = summaries.map { s in
            [s.runId, s.kind.rawValue, s.startedAt, s.state.rawValue, counts(s.counts) + (s.target.map { "  (of \($0))" } ?? "")]
        }
        let header = ["RUN ID", "KIND", "STARTED", "STATE", "COUNTS"]
        let widths = (0..<4).map { i in ([header] + rows).map { $0[i].count }.max()! }
        func line(_ row: [String]) -> String {
            (0..<4).map { row[$0].padding(toLength: widths[$0], withPad: " ", startingAt: 0) }.joined(separator: "  ")
                + "  " + row[4]
        }
        return ([line(header)] + rows.map(line)).joined(separator: "\n") + "\n"
    }

    public static func text(_ detail: RunDetail) -> String {
        let s = detail.summary
        let rel = { relative($0, to: detail.root) }
        var lines = ["Run \(s.runId) (\(s.kind.rawValue), \(s.state.rawValue)), started \(s.startedAt), root \(detail.root)"]
        if let target = s.target { lines.append("Acts on run \(target)") }
        for m in detail.moves ?? [] {
            var line = "  \(String(m.seq).leftPad(4))  \(m.status.padding(toLength: 9, withPad: " ", startingAt: 0)) \(rel(m.src)) -> \(rel(m.dst))  [\(m.rule)]"
            if let reason = m.reason { line += "  (\(reason))" }
            if let undo = m.undo { line += "  undo: \(undo.rawValue)" }
            lines.append(line)
        }
        for e in detail.entries ?? [] {
            var line = "  \(String(e.seq).leftPad(4))  \(e.outcome.rawValue.padding(toLength: 17, withPad: " ", startingAt: 0))"
            if let from = e.from { line += " \(rel(from))" }
            if let to = e.to { line += " -> \(rel(to))" }
            if let text = e.detail { line += "  (\(text))" }
            lines.append(line)
        }
        for e in detail.states ?? [] {
            lines.append("  \(String(e.seq).leftPad(4))  \(e.state.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(e.at.map(rel) ?? "")")
        }
        lines.append("Counts: \(counts(s.counts))")
        return lines.joined(separator: "\n") + "\n"
    }
}

extension String {
    func leftPad(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
