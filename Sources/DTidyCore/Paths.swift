import Foundation

/// The parts of the process environment dtidy depends on, injectable for tests.
public struct Environment: Sendable {
    public var home: String
    public var variables: [String: String]

    public init(home: String, variables: [String: String]) {
        self.home = home
        self.variables = variables
    }

    public static var current: Environment {
        Environment(home: NSHomeDirectory(), variables: ProcessInfo.processInfo.environment)
    }

    /// The value of `name`, or nil when unset or empty.
    public func nonEmpty(_ name: String) -> String? {
        guard let value = variables[name], !value.isEmpty else { return nil }
        return value
    }
}

public enum Paths {
    /// Expands a leading `~` or `~/` to `home`. Other paths are returned unchanged.
    public static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// `--config` if given, else `$XDG_CONFIG_HOME/dtidy/config.json`, else `~/.config/dtidy/config.json`.
    public static func configFile(explicit: String?, environment: Environment) -> String {
        if let explicit { return expandTilde(explicit, home: environment.home) }
        let base = environment.nonEmpty("XDG_CONFIG_HOME") ?? environment.home + "/.config"
        return base + "/dtidy/config.json"
    }

    /// `$XDG_DATA_HOME/dtidy`, else `~/Library/Application Support/dtidy`.
    public static func dataDirectory(environment: Environment) -> String {
        if let xdg = environment.nonEmpty("XDG_DATA_HOME") { return xdg + "/dtidy" }
        return environment.home + "/Library/Application Support/dtidy"
    }

    public static func historyDirectory(environment: Environment) -> String {
        dataDirectory(environment: environment) + "/history"
    }

    /// `child` joined onto `parent` with exactly one separator.
    public static func join(_ parent: String, _ child: String) -> String {
        parent.hasSuffix("/") ? parent + child : parent + "/" + child
    }

    public static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }
}

public enum Names {
    /// Comparison key for file names on a case- and normalization-insensitive volume.
    public static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Unicode NFC form, used before pattern matching.
    public static func nfc(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
    }
}
