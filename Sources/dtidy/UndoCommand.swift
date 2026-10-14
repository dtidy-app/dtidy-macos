import ArgumentParser
import DTidyCore
import DTidyIO

extension ConflictPolicy: ExpressibleByArgument {}

struct UndoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "undo",
        abstract: "Reverse a sort run (the most recent one by default).",
        discussion: """
            Each moved file is looked for at its recorded destination, then wherever the kernel says \
            its inode is now, then by document ID inside the run's bucket folders. Files are put back \
            with an exclusive rename, so nothing on the Desktop is ever overwritten.

            Without RUN_ID, the most recent sort run that is not fully reverted is undone. If an \
            original name is taken, the file comes back as `name (restored).ext`, unless \
            --on-conflict skip is given. A file found at its destination but with a different \
            identity is reported as replaced and left alone, unless --by-path is given. Bucket \
            folders the run created are removed once they are empty. Entries left unresolved can \
            be retried later with `dtidy undo RUN_ID`. Exits 0 only when every entry was restored or \
            already restored, otherwise 1.

            EXAMPLES:
              dtidy undo
                  Undo the most recent sort run.
              dtidy undo 20261014T190912Z-3f9a0c1d2e4b
                  Undo (or retry) one specific run; see `dtidy history` for run IDs.
              dtidy undo --dry-run
                  Show where each file was found and what would happen, without changing anything.
            """)

    @Argument(
        help: "The sort run to undo (default: the most recent one not yet fully reverted).",
        completion: .custom { _, _, prefix in runIdCandidates(prefix: prefix) { $0.undoableRunIds } })
    var runId: String?

    @Flag(name: .long, help: "Show what undo would do, without changing anything.")
    var dryRun = false

    @Option(name: .long, help: "When the original name is taken: suffix (restore as `name (restored).ext`) or skip.")
    var onConflict: ConflictPolicy = .suffix

    @Flag(name: .long, help: "Also restore files whose identity changed, by their recorded path.")
    var byPath = false

    @Flag(name: .long, help: "Write the result as JSON on stdout.")
    var json = false

    func run() throws {
        try finish {
            let report = try UndoService().undo(runId: runId, dryRun: dryRun, onConflict: onConflict, byPath: byPath)
            emit(report, json: json, text: Render.text)
            return report.isComplete ? .ok : .partial
        }
    }
}
