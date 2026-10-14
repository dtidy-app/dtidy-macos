import ArgumentParser

/// Options shared by commands that read the configuration.
struct ConfigOptions: ParsableArguments {
    @Option(
        name: .long, help: "Path to the config file (default: ~/.config/dtidy/config.json).",
        completion: .file(extensions: ["json"]))
    var config: String?
}

/// Options shared by commands that scan the root folder.
struct ScanOptions: ParsableArguments {
    @OptionGroup var configOptions: ConfigOptions

    @Option(name: .long, help: "Folder to sort instead of the configured root.", completion: .directory)
    var root: String?

    @Flag(name: .long, help: "Write the result as JSON on stdout.")
    var json = false
}
