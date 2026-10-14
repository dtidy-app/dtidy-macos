import Foundation

public enum RunKind: String, Codable, Sendable {
    case sort, undo, recover
}

/// First record of every ledger.
public struct RunHeader: Codable, Sendable, Equatable {
    public var v: Int
    public var run: String
    public var kind: RunKind
    /// Start time, ISO 8601 UTC with fractional seconds.
    public var ts: String
    public var root: String
    public var tool: String
    /// For undo ledgers: the sort run being reversed.
    public var reverts: String?
    /// For recover ledgers: the interrupted sort run being reconciled.
    public var recovers: String?

    public init(run: String, kind: RunKind, ts: String, root: String, reverts: String? = nil, recovers: String? = nil) {
        self.v = 1
        self.run = run
        self.kind = kind
        self.ts = ts
        self.root = root
        self.tool = DSortVersion.current
        self.reverts = reverts
        self.recovers = recovers
    }
}

public struct MoveRecord: Codable, Sendable, Equatable {
    public var seq: Int
    public var src: String
    public var dst: String
    public var rule: String
    public var id: FileIdentity

    public init(seq: Int, src: String, dst: String, rule: String, id: FileIdentity) {
        self.seq = seq
        self.src = src
        self.dst = dst
        self.rule = rule
        self.id = id
    }
}

/// Outcome of undoing one entry. The first three resolve the entry; the rest leave it open.
public enum UndoOutcome: String, Codable, Sendable, CaseIterable {
    case restored
    case restoredRenamed = "restored-renamed"
    case alreadyRestored = "already-restored"
    case inTrash = "in-trash"
    case missing
    case inaccessible
    case replaced
    case skippedConflict = "skipped-conflict"
    case failed

    public var resolves: Bool { self == .restored || self == .restoredRenamed || self == .alreadyRestored }
}

/// What `recover` found for one planned move of an interrupted run.
public enum RecoveredState: String, Codable, Sendable {
    case moved
    case notMoved = "not-moved"
    /// Found neither at its source nor its destination; undo will look for it.
    case lost
}

/// One line of a ledger file. Encoded as a flat JSON object whose `t` field names the case.
public enum LedgerRecord: Sendable, Equatable {
    case run(RunHeader)
    case mkdir(path: String)
    case move(MoveRecord)
    /// The plan is complete and flushed; moves start after this record.
    case sealed(moves: Int)
    case tracked(seq: Int, docid: UInt32, byUs: Bool)
    /// The move will use `dst` instead of the planned destination (flushed before the rename).
    case retarget(seq: Int, dst: String)
    case done(seq: Int)
    case fail(seq: Int, errno: Int32?, reason: String)
    /// Undo intent: about to rename `from` to `to` (flushed before the rename).
    case restore(seq: Int, from: String, to: String)
    case undone(seq: Int, outcome: UndoOutcome, from: String?, to: String?, detail: String?)
    case rmdir(path: String)
    case state(seq: Int, state: RecoveredState, at: String?)
    /// Last record of a finished run, with outcome counts.
    case commit([String: Int])
}

extension LedgerRecord: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct Mkdir: Codable { var path: String }
    private struct Sealed: Codable { var moves: Int }
    private struct Tracked: Codable { var seq: Int; var docid: UInt32; var byUs: Bool }
    private struct Retarget: Codable { var seq: Int; var dst: String }
    private struct Done: Codable { var seq: Int }
    private struct Fail: Codable { var seq: Int; var errno: Int32?; var reason: String }
    private struct Restore: Codable { var seq: Int; var from: String; var to: String }
    private struct Undone: Codable {
        var seq: Int; var outcome: UndoOutcome; var from: String?; var to: String?; var detail: String?
    }
    private struct State: Codable { var seq: Int; var state: RecoveredState; var at: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: Key("t"))
        switch type {
        case "run": self = .run(try RunHeader(from: decoder))
        case "mkdir": self = .mkdir(path: try Mkdir(from: decoder).path)
        case "move": self = .move(try MoveRecord(from: decoder))
        case "sealed": self = .sealed(moves: try Sealed(from: decoder).moves)
        case "tracked":
            let r = try Tracked(from: decoder)
            self = .tracked(seq: r.seq, docid: r.docid, byUs: r.byUs)
        case "retarget":
            let r = try Retarget(from: decoder)
            self = .retarget(seq: r.seq, dst: r.dst)
        case "done": self = .done(seq: try Done(from: decoder).seq)
        case "fail":
            let r = try Fail(from: decoder)
            self = .fail(seq: r.seq, errno: r.errno, reason: r.reason)
        case "restore":
            let r = try Restore(from: decoder)
            self = .restore(seq: r.seq, from: r.from, to: r.to)
        case "undone":
            let r = try Undone(from: decoder)
            self = .undone(seq: r.seq, outcome: r.outcome, from: r.from, to: r.to, detail: r.detail)
        case "rmdir": self = .rmdir(path: try Mkdir(from: decoder).path)
        case "state":
            let r = try State(from: decoder)
            self = .state(seq: r.seq, state: r.state, at: r.at)
        case "commit":
            var counts: [String: Int] = [:]
            for key in c.allKeys where key.stringValue != "t" {
                counts[key.stringValue] = try c.decode(Int.self, forKey: key)
            }
            self = .commit(counts)
        default:
            throw DecodingError.dataCorruptedError(forKey: Key("t"), in: c, debugDescription: "unknown record type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        func tag(_ name: String) throws { try c.encode(name, forKey: Key("t")) }
        switch self {
        case .run(let h): try tag("run"); try h.encode(to: encoder)
        case .mkdir(let path): try tag("mkdir"); try Mkdir(path: path).encode(to: encoder)
        case .move(let m): try tag("move"); try m.encode(to: encoder)
        case .sealed(let n): try tag("sealed"); try Sealed(moves: n).encode(to: encoder)
        case .tracked(let seq, let docid, let byUs):
            try tag("tracked"); try Tracked(seq: seq, docid: docid, byUs: byUs).encode(to: encoder)
        case .retarget(let seq, let dst): try tag("retarget"); try Retarget(seq: seq, dst: dst).encode(to: encoder)
        case .done(let seq): try tag("done"); try Done(seq: seq).encode(to: encoder)
        case .fail(let seq, let errno, let reason):
            try tag("fail"); try Fail(seq: seq, errno: errno, reason: reason).encode(to: encoder)
        case .restore(let seq, let from, let to):
            try tag("restore"); try Restore(seq: seq, from: from, to: to).encode(to: encoder)
        case .undone(let seq, let outcome, let from, let to, let detail):
            try tag("undone")
            try Undone(seq: seq, outcome: outcome, from: from, to: to, detail: detail).encode(to: encoder)
        case .rmdir(let path): try tag("rmdir"); try Mkdir(path: path).encode(to: encoder)
        case .state(let seq, let state, let at): try tag("state"); try State(seq: seq, state: state, at: at).encode(to: encoder)
        case .commit(let counts):
            try tag("commit")
            for (key, value) in counts.sorted(by: { $0.key < $1.key }) { try c.encode(value, forKey: Key(key)) }
        }
    }
}

public enum LedgerCodec {
    /// One record as a single JSON line, newline included.
    public static func line(_ record: LedgerRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(record) + Data("\n".utf8)
    }

    /// Parses a ledger file. A final line without its newline is a write cut short by a
    /// crash and is ignored; an unreadable line elsewhere marks the ledger corrupt.
    public static func parse(_ data: Data) -> (records: [LedgerRecord], truncatedTail: Bool, corrupt: Bool) {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        var truncated = false
        if let last = lines.last {
            if last.isEmpty { lines.removeLast() } else { lines.removeLast(); truncated = true }
        }
        var records: [LedgerRecord] = []
        var corrupt = false
        let decoder = JSONDecoder()
        for line in lines where !line.isEmpty {
            if let record = try? decoder.decode(LedgerRecord.self, from: Data(line)) {
                records.append(record)
            } else {
                corrupt = true
            }
        }
        return (records, truncated, corrupt)
    }
}

public enum RunID {
    /// `YYYYMMDDTHHMMSSZ-` followed by 12 random hex digits.
    public static func make(at date: Date, random: UInt64 = UInt64.random(in: 0...UInt64.max)) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let stamp = String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        return stamp + "-" + String(format: "%012llx", random & 0xFFFF_FFFF_FFFF)
    }

    /// ISO 8601 UTC timestamp with milliseconds, used in ledger headers.
    public static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
