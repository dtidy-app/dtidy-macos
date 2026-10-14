import ArgumentParser
import DSortCore
import DSortIO

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "history", abstract: "List past runs, newest first.")

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
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show every recorded action of one run.")

    @Argument(help: "The run ID, as listed by `dsort history`.")
    var runId: String

    @Flag(name: .long, help: "Write the result as JSON on stdout.")
    var json = false

    func run() throws {
        try finish {
            guard let detail = LedgerStore(environment: .current).load().detail(runId) else {
                throw DSortError(.usage, "No run with ID \(runId). List runs with `dsort history`.")
            }
            emit(detail, json: json, text: Render.text)
            return .ok
        }
    }
}
