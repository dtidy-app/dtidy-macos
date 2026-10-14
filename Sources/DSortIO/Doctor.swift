import DSortCore
import Foundation

public struct DoctorCheck: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case pass, warn, fail }

    public var name: String
    public var status: Status
    public var detail: String
}

/// Read-only environment checks for `dsort doctor`.
public struct Doctor: Sendable {
    public let ops: any FileOps
    public let environment: Environment

    public init(ops: any FileOps = RealFileOps(), environment: Environment = .current) {
        self.ops = ops
        self.environment = environment
    }

    public func run(configPath explicit: String?, rootOverride: String?) -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        func add(_ name: String, _ status: DoctorCheck.Status, _ detail: String) {
            checks.append(DoctorCheck(name: name, status: status, detail: detail))
        }

        // Config: parsed and validated, but a missing root is reported by the root check.
        let configPath = Paths.configFile(explicit: explicit, environment: environment)
        var config = Config.default
        var configProblems: [String] = []
        if FileManager.default.fileExists(atPath: configPath) {
            if let data = FileManager.default.contents(atPath: configPath) {
                do { config = try ConfigParser.parse(data) } catch { configProblems = error.issues.map(\.description) }
            } else {
                configProblems = ["cannot read the file"]
            }
        } else if explicit != nil {
            configProblems = ["file not found"]
        }
        if let rootOverride { config.root = rootOverride }
        if configProblems.isEmpty {
            configProblems = ConfigValidator.validate(config, home: environment.home, fileExists: { _ in true })
                .map(\.description)
        }
        let source = FileManager.default.fileExists(atPath: configPath) ? configPath : "\(configPath) (not found; built-in defaults)"
        add("config", configProblems.isEmpty ? .pass : .fail,
            configProblems.isEmpty ? source : "\(source): " + configProblems.joined(separator: "; "))

        // Root folder: readable, and on a volume with the features dsort relies on.
        let root = ConfigLoader.canonicalPath(Paths.expandTilde(config.root, home: environment.home))
        do {
            let count = try ops.listDirectory(root).count
            add("root", .pass, "\(root) is readable (\(count) items)")
            if let caps = ops.volumeCapabilities(root) {
                add("exclusive rename", caps.renameExclusive ? .pass : .fail,
                    caps.renameExclusive ? "supported" : "the volume does not support RENAME_EXCL; dsort cannot move safely")
                add("path from file ID", caps.pathFromID ? .pass : .warn,
                    caps.pathFromID ? "supported" : "undo cannot follow files that were moved after sorting")
            } else {
                add("volume", .warn, "could not read the volume's capabilities")
            }
        } catch {
            let explanation = PermissionHelp.error(for: error, root: root, environment: environment)
            add("root", .fail, explanation.message)
        }

        // Data directory, lock, and history.
        let dataDirectory = Paths.dataDirectory(environment: environment)
        add("data directory", .pass, dataDirectory)
        let held = RunLock.isHeld(dataDirectory: dataDirectory)
        add("lock", held ? .warn : .pass, held ? "held by a running dsort process" : "free")
        let history = LedgerStore(environment: environment).load()
        let interrupted = history.interruptedSortRuns
        add("history", interrupted.isEmpty ? .pass : .warn,
            "\(history.ledgers.count) ledgers in \(Paths.historyDirectory(environment: environment))"
                + (interrupted.isEmpty ? "" : "; \(interrupted.count) interrupted run(s): run `dsort recover`"))
        return checks
    }
}

extension Render {
    public static func text(_ checks: [DoctorCheck]) -> String {
        let width = checks.map(\.name.count).max() ?? 0
        return checks.map { check in
            let mark = switch check.status { case .pass: "ok  "; case .warn: "warn"; case .fail: "FAIL" }
            let indent = String(repeating: " ", count: width + 9)
            let detail = check.detail.replacingOccurrences(of: "\n", with: "\n" + indent)
            return "  [\(mark)] \(check.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(detail)"
        }.joined(separator: "\n") + "\n"
    }
}
