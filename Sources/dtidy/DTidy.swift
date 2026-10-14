import ArgumentParser
import DTidyCore

@main
struct DTidy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dtidy",
        abstract: "Sort loose items on the macOS Desktop into folders, with undo.",
        version: DTidyVersion.current,
        subcommands: [
            RunCommand.self, PlanCommand.self, UndoCommand.self, RecoverCommand.self,
            HistoryCommand.self, ShowCommand.self, DoctorCommand.self, ConfigCommand.self,
        ],
        defaultSubcommand: RunCommand.self
    )
}
