import ArgumentParser
import DTidyCore
import DTidyIO

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history", abstract: "List past runs, newest first.",
        discussion: """
            Lists every recorded run with its run ID, kind (sort, undo, recover), start time, state and \
            counts. A run's state is committed, interrupted (run `dtidy recover`), recovered, \
            partially-reverted or reverted. Runs that moved nothing write no ledger and are not listed.

            EXAMPLES:
              dtidy history
                  List every run.
              dtidy history --limit 5
                  List the five most recent runs.
              dtidy history --json
                  Print the list as JSON on stdout.
            """)

    @Option(name: .long, help: "Show at most this many runs.")
    var limit: Int?

    @Flag(name: .long, help: "Write the result as JSON on stdout.")
    var json = false

    func validate() throws {
        if let limit, limit < 1 { throw ValidationError("--limit must be at least 1.") }
    }

    func run() throws {
        var summaries = LedgerStore(environment: .current).load().summaries
        if let limit { summaries = Array(summaries.prefix(limit)) }
        emit(summaries, json: json, text: Render.text)
    }
}

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show", abstract: "Show every recorded action of one run.",
        discussion: """
            Prints every recorded move of the run with its outcome and actual destination, including the \
            outcome of any undo of it. With shell completion installed, Tab completes run IDs.

            EXAMPLES:
              dtidy show 20261014T190912Z-3f9a0c1d2e4b
                  Show what that run did.
              dtidy show 20261014T190912Z-3f9a0c1d2e4b --json
                  Print the same details as JSON on stdout.
            """)

    @Argument(
        help: "The run ID, as listed by `dtidy history`.",
        completion: .custom { _, _, prefix in runIdCandidates(prefix: prefix) { $0.allRunIds } })
    var runId: String

    @Flag(name: .long, help: "Write the result as JSON on stdout.")
    var json = false

    func run() throws {
        try finish {
            guard let detail = LedgerStore(environment: .current).load().detail(runId) else {
                throw DTidyError(.usage, "No run with ID \(runId). List runs with `dtidy history`.")
            }
            emit(detail, json: json, text: Render.text)
            return .ok
        }
    }
}
