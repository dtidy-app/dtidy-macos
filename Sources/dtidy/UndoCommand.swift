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
            """)

    @Argument(help: "The sort run to undo (default: the most recent one not yet fully reverted).")
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
