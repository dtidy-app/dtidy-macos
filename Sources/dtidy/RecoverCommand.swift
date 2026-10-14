import ArgumentParser
import DTidyCore
import DTidyIO

struct RecoverCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recover", abstract: "Reconcile runs that were interrupted, so they can be undone.",
        discussion: """
            A run that was killed or lost power before it finished is listed as interrupted, and \
            `dtidy run` refuses to start until it is reconciled. Recover checks every planned move of each \
            interrupted run by file identity, records whether the file is at its source or its destination, \
            and marks the run as recovered. A recovered run can then be undone like any other run.

            EXAMPLES:
              dtidy recover
                  Reconcile every interrupted run.
              dtidy recover && dtidy undo
                  Reconcile, then put the files of the most recent run back.
            """)

    @Flag(name: .long, help: "Write the result as JSON on stdout.")
    var json = false

    func run() throws {
        try finish {
            let runs = try RecoverService().recover()
            emit(runs, json: json, text: Render.text)
            return .ok
        }
    }
}
