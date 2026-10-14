import ArgumentParser
import DTidyCore
import DTidyIO

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Check permissions, volume, lock, history, and config. Changes nothing.")

    @OptionGroup var options: ScanOptions

    func run() throws {
        let checks = Doctor().run(configPath: options.configOptions.config, rootOverride: options.root)
        emit(checks, json: options.json, text: Render.text)
        if checks.contains(where: { $0.status == .fail }) { throw ExitCode(DTidyExit.partial.rawValue) }
    }
}
