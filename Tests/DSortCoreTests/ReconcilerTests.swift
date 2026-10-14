import Testing
@testable import DSortCore

@Suite struct ReconcilerTests {
    let recorded = FileIdentity(fsid: [1, 26], ino: 100, birth: 1000.25)
    let docid: UInt32 = 296

    func probe(ino: UInt64 = 100, birth: Double = 1000.25, docid: UInt32 = 0) -> Probe {
        Probe(identity: FileIdentity(fsid: [1, 26], ino: ino, birth: birth), docid: docid)
    }

    func locate(_ candidates: [(String, Probe?)], lookup: Lookup = .notFound, scan: String? = nil,
                docid: UInt32? = nil) -> Location {
        Reconciler.locate(recorded: recorded, docid: docid ?? self.docid,
                          candidates: candidates.map { (path: $0.0, probe: $0.1) },
                          lookup: { lookup }, scan: { scan })
    }

    @Test func matchAtDestination() {
        #expect(locate([("/D/PDFs/a.pdf", probe())]) == .found("/D/PDFs/a.pdf"))
    }

    @Test func safeSavedFileMatchesByDocumentID() {
        #expect(locate([("/D/PDFs/a.pdf", probe(ino: 555, birth: 2000, docid: 296))]) == .found("/D/PDFs/a.pdf"))
    }

    @Test func reusedInodeDoesNotMatch() {
        let other = probe(ino: 100, birth: 9999, docid: 7)
        #expect(!Reconciler.matches(other, recorded: recorded, docid: docid))
        #expect(locate([("/D/PDFs/a.pdf", nil)], lookup: .path("/D/x", other)) == .missing)
    }

    @Test func zeroDocumentIDsNeverMatch() {
        #expect(!Reconciler.matches(probe(ino: 5, birth: 5, docid: 0), recorded: recorded, docid: 0))
    }

    @Test func userRenamedFileIsFoundByInode() {
        #expect(locate([("/D/PDFs/a.pdf", nil)], lookup: .path("/D/PDFs/paid/a-2026.pdf", probe()))
                == .found("/D/PDFs/paid/a-2026.pdf"))
    }

    @Test func movedAndSafeSavedFileIsFoundByScan() {
        #expect(locate([("/D/PDFs/a.pdf", nil)], lookup: .notFound, scan: "/D/PDFs/x/a.pdf") == .found("/D/PDFs/x/a.pdf"))
    }

    @Test func scanIsSkippedWithoutDocumentID() {
        var scanned = false
        let location = Reconciler.locate(recorded: recorded, docid: 0, candidates: [(path: "/D/a", probe: nil)],
                                         lookup: { .notFound }, scan: { scanned = true; return "/x" })
        #expect(location == .missing && !scanned)
    }

    @Test func permissionErrorIsInaccessibleNotMissing() {
        #expect(locate([("/D/PDFs/a.pdf", nil)], lookup: .error("Permission denied")) == .inaccessible("Permission denied"))
    }

    @Test func occupiedDestinationWithoutMatchIsReplaced() {
        #expect(locate([("/D/PDFs/a.pdf", probe(ino: 9, birth: 9, docid: 9))]) == .replaced("/D/PDFs/a.pdf"))
    }

    @Test func nothingAnywhereIsMissing() {
        #expect(locate([("/D/PDFs/a.pdf", nil), ("/D/a.pdf", nil)]) == .missing)
    }

    @Test func alreadyBackAtOriginalPath() {
        let location = locate([("/D/PDFs/a.pdf", nil), ("/D/a.pdf", probe())])
        #expect(location == .found("/D/a.pdf"))
        #expect(Reconciler.action(for: location, restored: ["/D/a.pdf"], byPath: false)
                == .report(.alreadyRestored, at: "/D/a.pdf", detail: nil))
    }

    @Test func actions() {
        #expect(Reconciler.action(for: .found("/D/PDFs/a.pdf"), restored: ["/D/a.pdf"], byPath: false) == .restore(from: "/D/PDFs/a.pdf"))
        #expect(Reconciler.action(for: .found("/Users/t/.Trash/a.pdf"), restored: [], byPath: false)
                == .report(.inTrash, at: "/Users/t/.Trash/a.pdf", detail: nil))
        #expect(Reconciler.action(for: .found("/Volumes/X/.Trashes/501/a.pdf"), restored: [], byPath: false)
                == .report(.inTrash, at: "/Volumes/X/.Trashes/501/a.pdf", detail: nil))
        #expect(Reconciler.action(for: .inaccessible("EPERM"), restored: [], byPath: false) == .report(.inaccessible, at: nil, detail: "EPERM"))
        #expect(Reconciler.action(for: .replaced("/D/PDFs/a.pdf"), restored: [], byPath: false) == .report(.replaced, at: "/D/PDFs/a.pdf", detail: nil))
        #expect(Reconciler.action(for: .replaced("/D/PDFs/a.pdf"), restored: [], byPath: true) == .restore(from: "/D/PDFs/a.pdf"))
        #expect(Reconciler.action(for: .missing, restored: [], byPath: true) == .report(.missing, at: nil, detail: nil))
    }
}
