import ArgumentParser
import DTidyCore
import DTidyIO

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Check permissions, volume, lock, history, and config. Changes nothing.",
        discussion: """
            Reports whether the root folder is readable (and which app needs permission if it is not), \
            whether its volume supports exclusive renames and lookup by file ID, whether the lock is free, \
            whether any run is interrupted, and whether the config is valid. It also shows the config file \
            and data directory in effect. Exits 0 when every check passes, otherwise 1.

            EXAMPLES:
              dtidy doctor
                  Check the Desktop setup.
              dtidy doctor --root ~/Downloads
                  Check another folder.
              dtidy doctor --json
                  Print the checks as JSON on stdout.
            """)

    @OptionGroup var options: ScanOptions

    func run() throws {
        let checks = Doctor().run(configPath: options.configOptions.config, rootOverride: options.root)
        emit(checks, json: options.json, text: Render.text)
        if checks.contains(where: { $0.status == .fail }) { throw ExitCode(DTidyExit.partial.rawValue) }
    }
}
