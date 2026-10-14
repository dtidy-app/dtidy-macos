import ArgumentParser
import DSortCore
import DSortIO

struct PlanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan", abstract: "Show what a run would do, without changing anything.")

    @OptionGroup var options: ScanOptions

    func run() throws {
        try finish {
            let loaded = try ConfigLoader.load(explicit: options.configOptions.config, rootOverride: options.root)
            let plan = try SortService().makePlan(loaded.resolved)
            emit(RunReport(plan: plan), json: options.json, text: Render.text)
            return .ok
        }
    }
}
