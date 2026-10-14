import ArgumentParser
import DTidyCore
import DTidyIO
import Foundation

/// Runs a command body, prints any `DTidyError` to stderr, and ends the process with the
/// body's `DTidyExit` code. Every subcommand goes through this so exit codes stay uniform.
func finish(_ body: () throws -> DTidyExit) throws {
    let code: DTidyExit
    do {
        code = try body()
    } catch let error as DTidyError {
        printError(error.message)
        code = error.exit
    } catch let error as ExitCode {
        throw error
    } catch {
        printError("Unexpected error: \(error)")
        code = .partial
    }
    if code != .ok { throw ExitCode(code.rawValue) }
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Run IDs for shell completion, filtered by what the user has typed. Reads only the history
/// directory: no lock, config, or root access, and an unreadable history yields no candidates.
func runIdCandidates(prefix: String, from pick: (History) -> [String]) -> [String] {
    pick(LedgerStore(environment: .current).load()).filter { $0.hasPrefix(prefix) }
}
