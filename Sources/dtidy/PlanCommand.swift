import ArgumentParser
import DTidyCore
import DTidyIO

struct PlanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan", abstract: "Show what a run would do, without changing anything.",
        discussion: """
            Prints every move, every folder that would be created, and every skipped item with its \
            reason, using the same rules as `dtidy run`. Nothing is changed: no files, folders, flags, \
            ledger or lock. Each move names the rule that matched: a triage rule's name, extension, type \
            or fallback. Skip reasons are hidden, bucket, symlink, special, folder, skip-glob, never-move \
            and too-recent.

            EXAMPLES:
              dtidy plan
                  Preview a run on the Desktop (or the configured root).
              dtidy plan --root ~/Downloads
                  Preview another folder.
              dtidy plan --json
                  Print the plan as JSON on stdout.
            """)

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
