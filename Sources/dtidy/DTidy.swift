import ArgumentParser
import DTidyCore

@main
struct DTidy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dtidy",
        abstract: "Sort loose items on the macOS Desktop into folders, with undo.",
        discussion: """
            dtidy moves the loose items at the top level of a folder (the Desktop by default) into \
            bucket folders such as Images/, PDFs/ and Documents/. Every run is recorded in a ledger \
            before anything moves, so any run can be undone. Running `dtidy` without a subcommand \
            is the same as `dtidy run`.

            EXIT STATUS:
              0   Every planned action succeeded.
              1   Some items failed or were left unresolved, or an interrupted run needs \
            `dtidy recover`.
              64  Usage or configuration error.
              75  Another dtidy process holds the lock.
              77  macOS denied access to the folder.

            FILES:
              ~/.config/dtidy/config.json
                  The config file. --config or $XDG_CONFIG_HOME/dtidy/config.json take precedence.
              ~/Library/Application Support/dtidy
                  The data directory: run history and lock. $XDG_DATA_HOME/dtidy takes precedence.
              Run `dtidy doctor` to see the locations in effect.

            EXAMPLES:
              dtidy plan
                  Preview what a run would do, without changing anything.
              dtidy
                  Sort the Desktop.
              dtidy undo
                  Put back everything the most recent run moved.
            """,
        version: DTidyVersion.current,
        subcommands: [
            RunCommand.self, PlanCommand.self, UndoCommand.self, RecoverCommand.self,
            HistoryCommand.self, ShowCommand.self, DoctorCommand.self, ConfigCommand.self,
        ],
        defaultSubcommand: RunCommand.self
    )
}
