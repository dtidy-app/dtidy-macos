import ArgumentParser
import Foundation
import DTidyCore
import DTidyIO

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config", abstract: "Manage the configuration file.",
        subcommands: [ConfigInit.self, ConfigPath.self, ConfigValidate.self])
}

struct ConfigInit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init", abstract: "Write the built-in defaults to the config file.")

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
        commandName: "path", abstract: "Print the config file path in effect and whether it exists.")

    @OptionGroup var options: ConfigOptions

    func run() throws {
        let path = Paths.configFile(explicit: options.config, environment: .current)
        let exists = FileManager.default.fileExists(atPath: path)
        print("\(path) (\(exists ? "exists" : "not found; using built-in defaults"))")
    }
}

struct ConfigValidate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate", abstract: "Validate the config file without scanning.")

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
