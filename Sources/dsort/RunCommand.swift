import ArgumentParser
import DSortCore
import DSortIO

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: "Sort the Desktop (default command).")

    @OptionGroup var options: ScanOptions

    @Flag(name: .long, help: "Show the plan without changing anything (same as `dsort plan`).")
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
