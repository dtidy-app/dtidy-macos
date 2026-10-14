/// One move the run intends to make.
public struct PlannedMove: Codable, Sendable, Equatable {
    public var seq: Int
    public var name: String
    /// Absolute source path.
    public var src: String
    /// Absolute destination path, with any collision suffix already applied.
    public var dst: String
    /// Destination folder relative to the root.
    public var bucket: String
    public var rule: String
    public var identity: FileIdentity
}

public struct PlannedSkip: Codable, Sendable, Equatable {
    public var name: String
    public var reason: SkipReason
}

/// Everything a run would do, computed without touching the filesystem.
public struct Plan: Codable, Sendable, Equatable {
    public var root: String
    /// Absolute paths of folders to create, parents before children.
    public var mkdirs: [String]
    public var moves: [PlannedMove]
    public var skips: [PlannedSkip]
}

public enum Planner {
    /// Every folder (relative to the root) that the moves in `decisions` would need,
    /// including intermediate folders. The caller lists the existing names of each.
    public static func neededDirectories(_ decisions: [Decision]) -> [String] {
        var dirs: Set<String> = []
        for case .move(let to, _) in decisions {
            let parts = to.split(separator: "/")
            for i in 1...parts.count { dirs.insert(parts[..<i].joined(separator: "/")) }
        }
        return dirs.sorted(by: shallowFirst)
    }

    /// Builds the plan.
    ///
    /// - Parameters:
    ///   - existing: for each folder from `neededDirectories` that already exists, the names
    ///     it contains. A folder missing from the dictionary does not exist yet.
    ///   - caseSensitive: whether the volume distinguishes names that differ only by case.
    public static func plan(
        root: String, entries: [Entry], decisions: [Decision],
        existing: [String: [String]], caseSensitive: Bool
    ) -> Plan {
        precondition(entries.count == decisions.count)
        let key = { (name: String) -> String in caseSensitive ? Names.nfc(name) : Names.key(name) }
        var taken = existing.mapValues { Set($0.map(key)) }

        var moves: [PlannedMove] = []
        var skips: [PlannedSkip] = []
        var usedBuckets: Set<String> = []
        let order = entries.indices.sorted { entries[$0].name < entries[$1].name }

        for i in order {
            let entry = entries[i]
            switch decisions[i] {
            case .skip(let reason):
                skips.append(PlannedSkip(name: entry.name, reason: reason))
            case .move(let bucket, let rule):
                var name = entry.name
                var n = 0
                while taken[bucket, default: []].contains(key(name)) {
                    n += 1
                    name = SuffixNamer.numbered(entry.name, n)
                }
                taken[bucket, default: []].insert(key(name))
                usedBuckets.insert(bucket)
                moves.append(PlannedMove(
                    seq: moves.count + 1, name: entry.name, src: entry.path,
                    dst: Paths.join(Paths.join(root, bucket), name),
                    bucket: bucket, rule: rule, identity: entry.identity))
            }
        }

        let mkdirs = neededDirectories(usedBuckets.map { .move(to: $0, rule: "") })
            .filter { existing[$0] == nil }
            .map { Paths.join(root, $0) }
        return Plan(root: root, mkdirs: mkdirs, moves: moves, skips: skips)
    }

    /// Orders paths so every parent comes before its children.
    static func shallowFirst(_ a: String, _ b: String) -> Bool {
        let (da, db) = (a.split(separator: "/").count, b.split(separator: "/").count)
        return da != db ? da < db : a < b
    }
}
