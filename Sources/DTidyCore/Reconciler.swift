/// What was observed about a file at some path.
public struct Probe: Sendable, Equatable {
    public var identity: FileIdentity
    /// The kernel document ID, 0 when the file has none.
    public var docid: UInt32

    public init(identity: FileIdentity, docid: UInt32) {
        self.identity = identity
        self.docid = docid
    }
}

/// The result of asking the kernel for the current path of the recorded inode.
public enum Lookup: Sendable, Equatable {
    /// The inode is at this path; `probe` is nil if the path could not be examined.
    case path(String, Probe?)
    /// The kernel positively reported that no such file exists (ENOENT).
    case notFound
    /// Any other failure, such as permission denied.
    case error(String)
}

/// Where the recorded file is, as far as dtidy can tell.
public enum Location: Sendable, Equatable {
    case found(String)
    /// A lookup failed for a reason other than "does not exist".
    case inaccessible(String)
    /// Something else now occupies the recorded destination, and the file was not found.
    case replaced(String)
    case missing
}

/// What undo should do with one entry.
public enum UndoAction: Sendable, Equatable {
    case restore(from: String)
    case report(UndoOutcome, at: String?, detail: String?)
}

/// The undo decision table. Pure: every filesystem observation is passed in.
public enum Reconciler {
    /// Same volume, inode, and birth time; or the same non-zero document ID.
    public static func matches(_ probe: Probe, recorded: FileIdentity, docid: UInt32) -> Bool {
        probe.identity.sameFile(as: recorded) || (docid != 0 && probe.docid == docid)
    }

    /// Finds the recorded file.
    ///
    /// - Parameters:
    ///   - candidates: known paths with what is there now (nil when nothing is), checked in
    ///     order: the recorded destination first, then the original path and earlier
    ///     restore targets.
    ///   - lookup: the kernel's path for the recorded inode; called only if no candidate matches.
    ///   - scan: a search of the run's bucket folders by document ID; called only when needed.
    public static func locate(
        recorded: FileIdentity, docid: UInt32, candidates: [(path: String, probe: Probe?)],
        lookup: () -> Lookup, scan: () -> String?
    ) -> Location {
        for candidate in candidates {
            if let probe = candidate.probe, matches(probe, recorded: recorded, docid: docid) {
                return .found(candidate.path)
            }
        }
        switch lookup() {
        case .path(let path, let probe?) where probe.identity.sameFile(as: recorded):
            return .found(path)
        case .path, .notFound:
            break  // A different file reusing the inode number counts as not found.
        case .error(let reason):
            return .inaccessible(reason)
        }
        if docid != 0, let path = scan() { return .found(path) }
        if let destination = candidates.first, destination.probe != nil { return .replaced(destination.path) }
        return .missing
    }

    /// Turns a location into an action. `restored` holds the original path and every path an
    /// earlier undo restored this entry to.
    public static func action(for location: Location, restored: [String], byPath: Bool) -> UndoAction {
        switch location {
        case .found(let path):
            if isInTrash(path) { return .report(.inTrash, at: path, detail: nil) }
            if restored.contains(path) { return .report(.alreadyRestored, at: path, detail: nil) }
            return .restore(from: path)
        case .inaccessible(let reason):
            return .report(.inaccessible, at: nil, detail: reason)
        case .replaced(let path):
            return byPath ? .restore(from: path) : .report(.replaced, at: path, detail: nil)
        case .missing:
            return .report(.missing, at: nil, detail: nil)
        }
    }

    public static func isInTrash(_ path: String) -> Bool {
        path.contains("/.Trash/") || path.contains("/.Trashes/")
    }
}

/// One entry of an undo result.
public struct UndoEntryReport: Codable, Sendable, Equatable {
    public var seq: Int
    /// The original path on the Desktop.
    public var src: String
    /// Where the file was found, if anywhere.
    public var foundAt: String?
    public var restoredTo: String?
    public var outcome: UndoOutcome
    public var detail: String?

    public init(seq: Int, src: String, foundAt: String? = nil, restoredTo: String? = nil, outcome: UndoOutcome, detail: String? = nil) {
        self.seq = seq
        self.src = src
        self.foundAt = foundAt
        self.restoredTo = restoredTo
        self.outcome = outcome
        self.detail = detail
    }
}

/// The result of `dtidy undo`.
public struct UndoReport: Codable, Sendable, Equatable {
    public var dryRun: Bool
    /// The undo's own run ID (nil for a dry run or when there was nothing to do).
    public var runId: String?
    /// The sort run being reversed (nil when there was nothing to undo).
    public var target: String?
    public var root: String?
    public var entries: [UndoEntryReport]
    public var removedFolders: [String]

    public init(dryRun: Bool, runId: String? = nil, target: String? = nil, root: String? = nil,
                entries: [UndoEntryReport] = [], removedFolders: [String] = []) {
        self.dryRun = dryRun
        self.runId = runId
        self.target = target
        self.root = root
        self.entries = entries
        self.removedFolders = removedFolders
    }

    public var counts: [String: Int] {
        entries.reduce(into: [:]) { $0[$1.outcome.rawValue, default: 0] += 1 }
    }

    /// Every entry restored or already restored.
    public var isComplete: Bool { entries.allSatisfy { $0.outcome.resolves } }
}

extension Render {
    public static func text(_ report: UndoReport) -> String {
        guard let target = report.target, let root = report.root else { return "Nothing to undo.\n" }
        let rel = { relative($0, to: root) }
        var lines = ["Undo of run \(target)\(report.dryRun ? " (dry run, nothing changed)" : ""):"]
        for e in report.entries {
            var line = "  \(e.outcome.rawValue.padding(toLength: 17, withPad: " ", startingAt: 0)) "
            switch e.outcome {
            case .restored, .restoredRenamed:
                line += "\(rel(e.foundAt ?? "?")) -> \(rel(e.restoredTo ?? e.src))"
            default:
                line += rel(e.src)
                if let at = e.foundAt, e.outcome != .alreadyRestored { line += "  (now at \(at))" }
            }
            if let detail = e.detail { line += "  (\(detail))" }
            lines.append(line)
        }
        for dir in report.removedFolders {
            lines.append("  \("removed folder".padding(toLength: 17, withPad: " ", startingAt: 0)) \(rel(dir))")
        }
        let resolved = report.entries.filter { $0.outcome.resolves }.count
        var summary = "\(report.dryRun ? "Would resolve" : "Resolved") \(resolved) of \(report.entries.count) entries"
        let open = report.entries.count - resolved
        if open > 0 { summary += "; \(open) need attention" }
        summary += "."
        if let runId = report.runId { summary += " Undo run \(runId)." }
        if open > 0 && !report.dryRun { summary += " After fixing them, run `dtidy undo \(target)` to retry." }
        lines.append(summary)
        return lines.joined(separator: "\n") + "\n"
    }
}
