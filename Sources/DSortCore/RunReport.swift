import Foundation

public enum MoveStatus: String, Codable, Sendable {
    case planned, done, failed
}

/// One move in a plan or run result.
public struct MoveReport: Codable, Sendable, Equatable {
    public var seq: Int
    public var src: String
    public var dst: String
    public var rule: String
    public var status: MoveStatus
    public var reason: String?

    public init(seq: Int, src: String, dst: String, rule: String, status: MoveStatus, reason: String? = nil) {
        self.seq = seq
        self.src = src
        self.dst = dst
        self.rule = rule
        self.status = status
        self.reason = reason
    }
}

/// The result of `dsort plan` or `dsort run`, shared by text and JSON output.
public struct RunReport: Codable, Sendable, Equatable {
    public var dryRun: Bool
    public var runId: String?
    public var root: String
    public var mkdirs: [String]
    public var moves: [MoveReport]
    public var skips: [PlannedSkip]

    public init(dryRun: Bool, runId: String?, root: String, mkdirs: [String], moves: [MoveReport], skips: [PlannedSkip]) {
        self.dryRun = dryRun
        self.runId = runId
        self.root = root
        self.mkdirs = mkdirs
        self.moves = moves
        self.skips = skips
    }

    /// A dry-run report: everything planned, nothing done.
    public init(plan: Plan) {
        self.init(
            dryRun: true, runId: nil, root: plan.root, mkdirs: plan.mkdirs,
            moves: plan.moves.map { MoveReport(seq: $0.seq, src: $0.src, dst: $0.dst, rule: $0.rule, status: .planned) },
            skips: plan.skips)
    }

    public var failedCount: Int { moves.filter { $0.status == .failed }.count }
    public var doneCount: Int { moves.filter { $0.status == .done }.count }
}

public enum Render {
    /// Pretty, key-sorted JSON with a trailing newline.
    public static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// `path` relative to `root` when it is inside it.
    public static func relative(_ path: String, to root: String) -> String {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    public static func text(_ report: RunReport) -> String {
        let rel = { relative($0, to: report.root) }
        var lines = [report.dryRun ? "Plan for \(report.root) (dry run, nothing changed):" : "Sorted \(report.root):"]
        for dir in report.mkdirs {
            lines.append("  mkdir   \(rel(dir))")
        }
        for move in report.moves {
            let label = switch move.status {
            case .planned: "move   "
            case .done: "moved  "
            case .failed: "FAILED "
            }
            var line = "  \(label) \(rel(move.src)) -> \(rel(move.dst))  [\(move.rule)]"
            if let reason = move.reason { line += "  (\(reason))" }
            lines.append(line)
        }
        for skip in report.skips {
            lines.append("  skip    \(skip.name)  (\(skip.reason.rawValue))")
        }

        let folders = plural(report.mkdirs.count, "folder")
        let skipped = "\(report.skips.count) skipped"
        if report.dryRun {
            lines.append("\(report.moves.count) to move, \(folders) to create, \(skipped).")
        } else {
            var summary = "Moved \(report.doneCount), failed \(report.failedCount), \(skipped), created \(folders)."
            if let runId = report.runId { summary += " Run \(runId); reverse it with `dsort undo`." }
            lines.append(summary)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func plural(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }
}
