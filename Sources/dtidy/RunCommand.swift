import ArgumentParser
import DTidyCore
import DTidyIO

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run", abstract: "Sort the Desktop (default command).",
        discussion: """
            Scans the top level of the root folder (~/Desktop unless the config or --root says \
            otherwise) and moves each eligible item into its bucket folder with an atomic rename that \
            never overwrites. Hidden items, symbolic links, bucket folders, plain folders (by default) and \
            recently modified files (10 seconds by default) are skipped. The plan is written to the run \
            ledger before the first move, so the run can be reversed with `dtidy undo`. A run refuses to \
            start while an interrupted run exists; reconcile it with `dtidy recover` first.

            EXAMPLES:
              dtidy run
                  Sort the Desktop.
              dtidy run --dry-run
                  Show the plan without changing anything (same as `dtidy plan`).
              dtidy run --root ~/Downloads --json
                  Sort another folder and print the result as JSON.
            """)

    @OptionGroup var options: ScanOptions

    @Flag(name: .long, help: "Show the plan without changing anything (same as `dtidy plan`).")
    var dryRun = false

    func run() throws {
        try finish {
            let loaded = try ConfigLoader.load(explicit: options.configOptions.config, rootOverride: options.root)
            let report = try SortService().run(loaded.resolved, dryRun: dryRun)
            if !dryRun && report.moves.isEmpty && !options.json {
                print("Nothing to sort in \(report.root) (\(report.skips.count) skipped).")
            } else {
                emit(report, json: options.json, text: Render.text)
            }
            return report.failedCount > 0 ? .partial : .ok
        }
    }
}
