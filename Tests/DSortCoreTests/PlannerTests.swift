import Testing
@testable import DSortCore

@Suite struct SuffixNamerTests {
    @Test func plainExtension() {
        #expect(SuffixNamer.numbered("doc.pdf", 1) == "doc (1).pdf")
        #expect(SuffixNamer.numbered("doc.pdf", 12) == "doc (12).pdf")
    }

    @Test func compoundExtensionIsPreserved() {
        #expect(SuffixNamer.numbered("backup.tar.gz", 1) == "backup (1).tar.gz")
        #expect(SuffixNamer.numbered("toolkit-0.12.0-beta.tar.gz", 2) == "toolkit-0.12.0-beta (2).tar.gz")
        #expect(SuffixNamer.numbered("BACKUP.TAR.XZ", 1) == "BACKUP (1).TAR.XZ")
    }

    @Test func packageExtensionIsPreserved() {
        #expect(SuffixNamer.numbered("Tool.app", 1) == "Tool (1).app")
    }

    @Test func nameWithoutExtension() {
        #expect(SuffixNamer.numbered("README", 1) == "README (1)")
        #expect(SuffixNamer.numbered("trailing.", 1) == "trailing. (1)")
        #expect(SuffixNamer.numbered(".tar.gz", 1) == ".tar (1).gz")
    }

    @Test func restoredVariants() {
        #expect(SuffixNamer.restored("report.pdf", 1) == "report (restored).pdf")
        #expect(SuffixNamer.restored("report.pdf", 2) == "report (restored 2).pdf")
    }

    @Test func longNameIsTrimmedToFit() {
        let stem = String(repeating: "a", count: 250)
        let name = stem + ".pdf"                                   // 254 bytes
        let result = SuffixNamer.numbered(name, 1)
        #expect(result.utf8.count <= 255)
        #expect(result.hasSuffix(" (1).pdf"))
        #expect(result == String(repeating: "a", count: 247) + " (1).pdf")
    }

    @Test func trimmingKeepsGraphemesWhole() {
        let name = String(repeating: "é", count: 125) + ".txt"     // 2 bytes each: 254 bytes
        let result = SuffixNamer.numbered(name, 1)
        #expect(result.utf8.count <= 255)
        #expect(result.unicodeScalars.allSatisfy { $0 != "\u{FFFD}" })
        #expect(result.hasSuffix(" (1).txt"))
    }
}

@Suite struct PlannerTests {
    let root = "/Users/t/Desktop"
    let c = classifier()

    func plan(_ entries: [Entry], existing: [String: [String]] = [:], caseSensitive: Bool = false) -> Plan {
        let decisions = entries.map { c.classify($0, now: testNow) }
        return Planner.plan(root: root, entries: entries, decisions: decisions, existing: existing, caseSensitive: caseSensitive)
    }

    @Test func caseVariantCollisionGetsASuffix() {
        let p = plan([entry("Doc.pdf")], existing: ["PDFs": ["doc.PDF"]])
        #expect(p.moves.map(\.dst) == ["/Users/t/Desktop/PDFs/Doc (1).pdf"])
        #expect(p.mkdirs.isEmpty)
    }

    @Test func caseSensitiveVolumeKeepsTheName() {
        let p = plan([entry("Doc.pdf")], existing: ["PDFs": ["doc.PDF"]], caseSensitive: true)
        #expect(p.moves.map(\.dst) == ["/Users/t/Desktop/PDFs/Doc.pdf"])
    }

    @Test func twoItemsPlannedIntoOneName() {
        let p = plan([entry("a.pdf", ino: 1), entry("A.PDF", ino: 2)], caseSensitive: true)
        #expect(p.moves.map(\.dst) == ["/Users/t/Desktop/PDFs/A.PDF", "/Users/t/Desktop/PDFs/a.pdf"])
        let q = plan([entry("a.pdf", ino: 1), entry("A.PDF", ino: 2)], caseSensitive: false)
        #expect(q.moves.map(\.dst) == ["/Users/t/Desktop/PDFs/A.PDF", "/Users/t/Desktop/PDFs/a (1).pdf"])
    }

    @Test func noScreenshotsNoScreenshotFolder() {
        let p = plan([entry("invoice.pdf"), entry(".DS_Store")])
        #expect(p.mkdirs == ["/Users/t/Desktop/PDFs"])
        #expect(!p.mkdirs.contains { $0.contains("_Screenshots") })
    }

    @Test func intermediateFoldersComeFirstAndExistingOnesAreNotRecreated() {
        let shot = entry("Screenshot 2026-10-14 at 16.48.54.png", screenCapture: true, ino: 1)
        let p = plan([shot, entry("IMG_1.jpg", ino: 2)])
        #expect(p.mkdirs == ["/Users/t/Desktop/Images", "/Users/t/Desktop/Images/_Inbox", "/Users/t/Desktop/Images/_Screenshots"])
        let q = plan([shot], existing: ["Images": ["old.png"]])
        #expect(q.mkdirs == ["/Users/t/Desktop/Images/_Screenshots"])
    }

    @Test func movesAreNumberedInNameOrderAndSkipsAreListed() {
        let p = plan([entry("b.pdf", ino: 2), entry(".hidden"), entry("a.pdf", ino: 1)])
        #expect(p.moves.map(\.seq) == [1, 2])
        #expect(p.moves.map(\.name) == ["a.pdf", "b.pdf"])
        #expect(p.moves[0].identity.ino == 1)
        #expect(p.skips == [PlannedSkip(name: ".hidden", reason: .hidden)])
    }

    @Test func neededDirectoriesIncludeParents() {
        #expect(Planner.neededDirectories([.move(to: "Images/_Inbox", rule: ""), .skip(.hidden), .move(to: "PDFs", rule: "")])
                == ["Images", "PDFs", "Images/_Inbox"])
    }
}
