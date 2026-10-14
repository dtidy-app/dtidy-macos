import ArgumentParser
import DSortCore

@main
struct DSort: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dsort",
        abstract: "Sort loose items on the macOS Desktop into folders, with undo.",
        version: DSortVersion.current,
        subcommands: [
            RunCommand.self, PlanCommand.self, UndoCommand.self, RecoverCommand.self,
            HistoryCommand.self, ShowCommand.self, DoctorCommand.self, ConfigCommand.self,
        ],
        defaultSubcommand: RunCommand.self
    )
}
