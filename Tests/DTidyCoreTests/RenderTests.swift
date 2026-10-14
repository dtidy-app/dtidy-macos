import Foundation
import Testing
@testable import DTidyCore

@Suite struct RenderTests {
    let plan = Plan(
        root: "/Users/t/Desktop",
        mkdirs: ["/Users/t/Desktop/PDFs"],
        moves: [PlannedMove(seq: 1, name: "a.pdf", src: "/Users/t/Desktop/a.pdf", dst: "/Users/t/Desktop/PDFs/a.pdf",
                            bucket: "PDFs", rule: "type", identity: FileIdentity(fsid: [1, 26], ino: 7, birth: 1))],
        skips: [PlannedSkip(name: ".DS_Store", reason: .hidden)])

    @Test func dryRunText() {
        #expect(Render.text(RunReport(plan: plan)) == """
            Plan for /Users/t/Desktop (dry run, nothing changed):
              mkdir   PDFs
              move    a.pdf -> PDFs/a.pdf  [type]
              skip    .DS_Store  (hidden)
            1 to move, 1 folder to create, 1 skipped.

            """)
    }

    @Test func runText() {
        var report = RunReport(plan: plan)
        report.dryRun = false
        report.runId = "20261014T190912Z-abc"
        report.moves[0].status = .failed
        report.moves[0].reason = "cross-volume"
        #expect(Render.text(report) == """
            Sorted /Users/t/Desktop:
              mkdir   PDFs
              FAILED  a.pdf -> PDFs/a.pdf  [type]  (cross-volume)
              skip    .DS_Store  (hidden)
            Moved 0, failed 1, 1 skipped, created 1 folder. Run 20261014T190912Z-abc; reverse it with `dtidy undo`.

            """)
    }

    @Test func dryRunJSON() throws {
        let json = Render.json(RunReport(plan: plan))
        #expect(json == """
            {
              "dryRun" : true,
              "mkdirs" : [
                "/Users/t/Desktop/PDFs"
              ],
              "moves" : [
                {
                  "dst" : "/Users/t/Desktop/PDFs/a.pdf",
                  "rule" : "type",
                  "seq" : 1,
                  "src" : "/Users/t/Desktop/a.pdf",
                  "status" : "planned"
                }
              ],
              "root" : "/Users/t/Desktop",
              "skips" : [
                {
                  "name" : ".DS_Store",
                  "reason" : "hidden"
                }
              ]
            }

            """)
        let decoded = try JSONDecoder().decode(RunReport.self, from: Data(json.utf8))
        #expect(decoded == RunReport(plan: plan))
    }
}
