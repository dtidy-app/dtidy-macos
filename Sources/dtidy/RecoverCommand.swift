import ArgumentParser
import DTidyCore
import DTidyIO

struct RecoverCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recover", abstract: "Reconcile runs that were interrupted, so they can be undone.")

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
