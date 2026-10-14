import ArgumentParser
import Testing
@testable import dtidy

/// Every command reachable from `dtidy`, with its full name ("dtidy config init").
func allCommands(_ command: any ParsableCommand.Type = DTidy.self, prefix: String = "") -> [(String, any ParsableCommand.Type)] {
    let config = command.configuration
    let name = prefix.isEmpty ? config.commandName ?? "dtidy" : prefix + " " + (config.commandName ?? "?")
    return [(name, command)] + config.subcommands.flatMap { allCommands($0, prefix: name) }
}

@Suite struct HelpTests {
    @Test func everyCommandDocumentsItself() {
        let lacking = allCommands().compactMap { name, command -> String? in
            let config = command.configuration
            var missing: [String] = []
            if config.abstract.isEmpty { missing.append("abstract") }
            if config.discussion.isEmpty { missing.append("discussion") }
            if !config.discussion.contains("EXAMPLES:") { missing.append("EXAMPLES:") }
            return missing.isEmpty ? nil : "\(name) (\(missing.joined(separator: ", ")))"
        }
        #expect(lacking.isEmpty, "commands without full help: \(lacking.joined(separator: "; "))")
    }

    @Test func overviewListsExitCodesAndLocations() {
        let help = DTidy.helpMessage(columns: 200)
        for line in [
            "0   Every planned action succeeded.",
            "1   Some items failed",
            "64  Usage or configuration error.",
            "75  Another dtidy process holds the lock.",
            "77  macOS denied access to the folder.",
            "~/.config/dtidy/config.json",
            "~/Library/Application Support/dtidy",
            "$XDG_CONFIG_HOME/dtidy/config.json",
            "$XDG_DATA_HOME/dtidy",
            "dtidy doctor",
        ] {
            #expect(help.contains(line), "top-level help lacks \(line)")
        }
    }

    /// argument-parser answers every help request with its own internal `HelpCommand`, so no
    /// dtidy command (and none of its config, root or lock access) runs.
    @Test(arguments: [["--help"], ["-h"], ["run", "--help"], ["undo", "-h"], ["config", "init", "--help"], ["help", "config", "init"]])
    func helpRequestsNeverRunACommand(_ arguments: [String]) throws {
        let command = try DTidy.parseAsRoot(arguments)
        #expect(String(describing: type(of: command)) == "HelpCommand", "\(arguments) parsed into \(type(of: command))")
    }

    @Test func nestedHelpShowsTheSubcommand() {
        #expect(DTidy.helpMessage(for: ConfigInit.self).contains("Write the built-in defaults"))
    }
}

@Suite struct CompletionScriptTests {
    static let subcommands = ["run", "plan", "undo", "recover", "history", "show", "doctor", "config", "init", "path", "validate"]

    @Test(arguments: [CompletionShell.zsh, .bash, .fish])
    func scriptCoversEverySubcommandAndCallsBackForRunIDs(_ shell: CompletionShell) {
        let script = DTidy.completionScript(for: shell)
        for name in Self.subcommands {
            #expect(script.contains(name), "\(shell) script lacks \(name)")
        }
        #expect(script.contains("---completion"), "\(shell) script has no run-ID callback")
    }
}
