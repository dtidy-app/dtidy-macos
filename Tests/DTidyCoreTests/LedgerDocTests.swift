import Foundation
import Testing
@testable import DTidyCore

/// Keeps `docs/ledger-format.md` in step with `LedgerRecord`: every record type must have a
/// `### \`<type>\`` section, and every example line in the document must decode.
@Suite struct LedgerDocTests {
    /// Mirrors the cases of `LedgerRecord`. Adding a case there breaks `kind(of:)` below,
    /// which leads here, which breaks `sample(_:)`: the compiler walks you to every update.
    enum Kind: CaseIterable {
        case run, mkdir, move, sealed, tracked, retarget, done, fail, restore, undone, rmdir, state, commit
    }

    static func kind(of record: LedgerRecord) -> Kind {
        switch record {
        case .run: .run
        case .mkdir: .mkdir
        case .move: .move
        case .sealed: .sealed
        case .tracked: .tracked
        case .retarget: .retarget
        case .done: .done
        case .fail: .fail
        case .restore: .restore
        case .undone: .undone
        case .rmdir: .rmdir
        case .state: .state
        case .commit: .commit
        }
    }

    static func sample(_ kind: Kind) -> LedgerRecord {
        let id = FileIdentity(fsid: [1, 26], ino: 1, birth: 1)
        return switch kind {
        case .run: .run(RunHeader(run: "r", kind: .sort, ts: "t", root: "/D"))
        case .mkdir: .mkdir(path: "/D/PDFs")
        case .move: .move(MoveRecord(seq: 1, src: "/D/a", dst: "/D/PDFs/a", rule: "type", id: id))
        case .sealed: .sealed(moves: 1)
        case .tracked: .tracked(seq: 1, docid: 1, byUs: true)
        case .retarget: .retarget(seq: 1, dst: "/D/PDFs/a (1)")
        case .done: .done(seq: 1)
        case .fail: .fail(seq: 1, errno: 18, reason: "cross-volume")
        case .restore: .restore(seq: 1, from: "/D/PDFs/a", to: "/D/a")
        case .undone: .undone(seq: 1, outcome: .restored, from: nil, to: nil, detail: nil)
        case .rmdir: .rmdir(path: "/D/PDFs")
        case .state: .state(seq: 1, state: .moved, at: nil)
        case .commit: .commit(["done": 1])
        }
    }

    static let documentPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/ledger-format.md").path

    static func document() throws -> String {
        try String(contentsOfFile: documentPath, encoding: .utf8)
    }

    /// The JSON lines inside the document's ```jsonl blocks, one array per block.
    static func exampleBlocks(_ text: String) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String]?
        for line in text.components(separatedBy: "\n") {
            if line == "```jsonl" { current = [] }
            else if line == "```", let block = current { blocks.append(block); current = nil }
            else if current != nil, !line.isEmpty { current!.append(line) }
        }
        return blocks
    }

    @Test func everyRecordTypeHasASection() throws {
        let text = try Self.document()
        for kind in Kind.allCases {
            let record = Self.sample(kind)
            #expect(Self.kind(of: record) == kind)
            let line = try LedgerCodec.line(record)
            let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
            let type = try #require(object["t"] as? String)
            #expect(text.contains("### `\(type)`"), "docs/ledger-format.md has no section for record type \"\(type)\"")
        }
    }

    @Test func exampleLinesDecodeAndShowARevertedRun() throws {
        let blocks = Self.exampleBlocks(try Self.document())
        #expect(blocks.count == 2)
        let decoder = JSONDecoder()
        for line in blocks.joined() {
            #expect((try? decoder.decode(LedgerRecord.self, from: Data(line.utf8))) != nil, "does not decode: \(line)")
        }
        let files = try blocks.map { block in
            try #require(LedgerFile(Data((block.joined(separator: "\n") + "\n").utf8)))
        }
        let history = History(files)
        let sort = try #require(history.sortRuns.first)
        #expect(sort.state == .reverted)
        #expect(sort.destination(2)?.hasSuffix("report (1).pdf") == true)
    }
}
