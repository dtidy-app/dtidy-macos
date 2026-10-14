import DTidyCore
import Foundation

/// A configuration read from disk (or the built-in defaults) and validated.
public struct LoadedConfig: Sendable {
    public let path: String
    public let fileExists: Bool
    public let resolved: ResolvedConfig
}

public enum ConfigLoader {
    /// Loads the config in effect. A missing file means built-in defaults, except when the
    /// path was given explicitly. `rootOverride` replaces the configured root (`--root`).
    public static func load(
        explicit: String?, rootOverride: String? = nil, environment: Environment = .current
    ) throws(DTidyError) -> LoadedConfig {
        let path = Paths.configFile(explicit: explicit, environment: environment)
        let exists = FileManager.default.fileExists(atPath: path)
        if explicit != nil && !exists {
            throw DTidyError(.usage, "Config file not found: \(path)")
        }

        var config = Config.default
        if exists {
            guard let data = FileManager.default.contents(atPath: path) else {
                throw DTidyError(.usage, "Cannot read config file: \(path)")
            }
            do {
                config = try ConfigParser.parse(data)
            } catch {
                throw invalid(path, error.issues)
            }
        }
        if let rootOverride { config.root = rootOverride }

        do {
            let resolved = try ResolvedConfig(
                config, home: environment.home, fileExists: isDirectory, canonicalize: canonicalPath)
            return LoadedConfig(path: path, fileExists: exists, resolved: resolved)
        } catch {
            throw invalid(exists ? path : "built-in defaults", error.issues)
        }
    }

    /// Writes the built-in defaults to `path`, refusing to overwrite an existing file.
    public static func writeDefaults(to path: String) throws(DTidyError) {
        if FileManager.default.fileExists(atPath: path) {
            throw DTidyError(.usage, "Config file already exists, not overwriting: \(path)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(Config.default) + Data("\n".utf8)
            try FileManager.default.createDirectory(
                atPath: Paths.parent(path), withIntermediateDirectories: true)
            // O_EXCL via .withoutOverwriting closes the race with a concurrent writer.
            try data.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
        } catch {
            throw DTidyError(.usage, "Cannot write config file \(path): \(error.localizedDescription)")
        }
    }

    private static func invalid(_ source: String, _ issues: [ConfigIssue]) -> DTidyError {
        let lines = issues.map { "  - \($0)" }.joined(separator: "\n")
        return DTidyError(.usage, "Invalid config (\(source)):\n\(lines)")
    }

    /// The path with symlinks resolved, as `fsgetpath` reports it (`/tmp` -> `/private/tmp`).
    public static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
