import ArgumentParser
import DSortCore
import Foundation

/// Runs a command body, prints any `DSortError` to stderr, and ends the process with the
/// body's `DSortExit` code. Every subcommand goes through this so exit codes stay uniform.
func finish(_ body: () throws -> DSortExit) throws {
    let code: DSortExit
    do {
        code = try body()
    } catch let error as DSortError {
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
