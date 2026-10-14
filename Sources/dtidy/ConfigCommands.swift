import ArgumentParser
import Foundation
import DTidyCore
import DTidyIO

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config", abstract: "Manage the configuration file.",
        discussion: """
            dtidy works without a config file. A config file sets the root folder, the bucket rules and \
            what is skipped, and it replaces the built-in rules rather than adding to them, so start from \
            `dtidy config init`. The file is read from --config, otherwise \
            $XDG_CONFIG_HOME/dtidy/config.json, otherwise ~/.config/dtidy/config.json.

            EXAMPLES:
              dtidy config init
                  Write the built-in defaults as a starting point.
              dtidy config path
                  Show which config file is in effect.
              dtidy config validate
                  Check the config file without touching the Desktop.
            """,
        subcommands: [ConfigInit.self, ConfigPath.self, ConfigValidate.self])
}

struct ConfigInit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init", abstract: "Write the built-in defaults to the config file.",
        discussion: """
            Writes the built-in defaults to the config file in effect, ready to edit. An existing file is \
            never overwritten: the command exits 64 instead.

            EXAMPLES:
              dtidy config init
                  Create ~/.config/dtidy/config.json.
              dtidy config init --config ./alt.json
                  Write the defaults to another file.
            """)

    @OptionGroup var options: ConfigOptions

    func run() throws {
        try finish {
            let path = Paths.configFile(explicit: options.config, environment: .current)
            try ConfigLoader.writeDefaults(to: path)
            print("Wrote the built-in defaults to \(path)")
            return .ok
        }
    }
}

struct ConfigPath: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path", abstract: "Print the config file path in effect and whether it exists.",
        discussion: """
            Shows which file dtidy would read, after applying --config and $XDG_CONFIG_HOME, and whether \
            it exists. When it does not, the built-in defaults are used.

            EXAMPLES:
              dtidy config path
                  Show the config file in effect.
              XDG_CONFIG_HOME=/tmp/cfg dtidy config path
                  See where the file would be with another config home.
            """)

    @OptionGroup var options: ConfigOptions

    func run() throws {
        let path = Paths.configFile(explicit: options.config, environment: .current)
        let exists = FileManager.default.fileExists(atPath: path)
        print("\(path) (\(exists ? "exists" : "not found; using built-in defaults"))")
    }
}

struct ConfigValidate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate", abstract: "Validate the config file without scanning.",
        discussion: """
            Loads and checks the config file without scanning the root folder. An invalid file exits 64 \
            and names the problem, such as an invalid destination or a pattern that does not compile. \
            Without a file, it reports that the built-in defaults are valid.

            EXAMPLES:
              dtidy config validate
                  Check the config file in effect.
              dtidy config validate --config ./alt.json
                  Check another file before using it.
            """)

    @OptionGroup var options: ConfigOptions

    func run() throws {
        try finish {
            let loaded = try ConfigLoader.load(explicit: options.config)
            if loaded.fileExists {
                print("Config is valid: \(loaded.path)")
            } else {
                print("No config file at \(loaded.path); the built-in defaults are valid.")
            }
            return .ok
        }
    }
}
