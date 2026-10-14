import ArgumentParser
import DTidyCore
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
