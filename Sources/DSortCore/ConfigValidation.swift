import Foundation
import UniformTypeIdentifiers

/// One problem found in a config file, located by a field path such as `triage[1].regex`.
public struct ConfigIssue: Sendable, Equatable, CustomStringConvertible {
    public let path: String
    public let message: String

    public init(_ path: String, _ message: String) {
        self.path = path
        self.message = message
    }

    public var description: String { path.isEmpty ? message : "\(path): \(message)" }
}

public struct ConfigIssues: Error, Sendable {
    public let issues: [ConfigIssue]
}

public enum ConfigParser {
    /// Parses config JSON, rejecting unknown fields at every level (Codable alone would
    /// silently ignore them) and reporting decoding errors with their field path.
    public static func parse(_ data: Data) throws(ConfigIssues) -> Config {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ConfigIssues(issues: [ConfigIssue("", "not valid JSON: \(error.localizedDescription)")])
        }
        guard let top = object as? [String: Any] else {
            throw ConfigIssues(issues: [ConfigIssue("", "the config must be a JSON object")])
        }
        var issues = unknownKeys(top, known: Config.CodingKeys.allCases.map(\.rawValue), at: "")
        for (key, known) in [
            ("triage", TriageRule.CodingKeys.allCases.map(\.rawValue)),
            ("categories", Category.CodingKeys.allCases.map(\.rawValue)),
        ] {
            for (i, item) in (top[key] as? [Any] ?? []).enumerated() {
                if let dict = item as? [String: Any] {
                    issues += unknownKeys(dict, known: known, at: "\(key)[\(i)]")
                }
            }
        }
        if !issues.isEmpty { throw ConfigIssues(issues: issues) }

        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch let error as DecodingError {
            throw ConfigIssues(issues: [describe(error)])
        } catch {
            throw ConfigIssues(issues: [ConfigIssue("", error.localizedDescription)])
        }
    }

    private static func unknownKeys(_ dict: [String: Any], known: [String], at path: String) -> [ConfigIssue] {
        dict.keys.sorted().filter { !known.contains($0) }.map {
            ConfigIssue(path.isEmpty ? $0 : "\(path).\($0)", "unknown field")
        }
    }

    private static func describe(_ error: DecodingError) -> ConfigIssue {
        func path(_ keys: [CodingKey]) -> String {
            keys.reduce("") { acc, key in
                if let i = key.intValue { return "\(acc)[\(i)]" }
                return acc.isEmpty ? key.stringValue : "\(acc).\(key.stringValue)"
            }
        }
        switch error {
        case .typeMismatch(let type, let ctx):
            return ConfigIssue(path(ctx.codingPath), "expected \(typeName(type))")
        case .valueNotFound(let type, let ctx):
            return ConfigIssue(path(ctx.codingPath), "expected \(typeName(type)), found null")
        case .keyNotFound(let key, let ctx):
            return ConfigIssue(path(ctx.codingPath + [key]), "required field is missing")
        case .dataCorrupted(let ctx):
            return ConfigIssue(path(ctx.codingPath), ctx.debugDescription)
        @unknown default:
            return ConfigIssue("", String(describing: error))
        }
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "a string"
        case is Int.Type: "an integer"
        case is Double.Type: "a number"
        case is Bool.Type: "true or false"
        default: "\(type)"
        }
    }
}

/// A validated configuration, ready for classification: paths expanded, patterns compiled,
/// type identifiers resolved.
public struct ResolvedConfig: @unchecked Sendable {
    // @unchecked: `Regex<AnyRegexOutput>` is immutable once compiled but not declared Sendable.

    public struct NameRule {
        public let name: String
        public let regex: Regex<AnyRegexOutput>
        public let to: String
    }

    public struct TypeRule {
        public let types: [UTType]
        public let to: String
    }

    public let config: Config
    /// Absolute path of the folder being sorted.
    public let root: String
    public let minAgeSeconds: Double
    public let sortFolders: Bool
    public let skipGlobs: [String]
    public let neverMove: [String]
    /// Destination of the first screen-capture triage rule, if any.
    public let screenCapture: (name: String, to: String)?
    public let nameRules: [NameRule]
    /// Lowercased extension (without dot) to destination, first configured mapping wins.
    public let extensionMap: [String: String]
    public let typeRules: [TypeRule]
    public let fallback: String
    /// NFC-normalized, lowercased first path component of every destination.
    public let bucketNames: Set<String>

    /// Validates `config` and resolves it. `fileExists` checks the expanded root;
    /// `canonicalize` turns it into the path the kernel reports (symlinks resolved).
    public init(
        _ config: Config, home: String, fileExists: (String) -> Bool,
        canonicalize: (String) -> String = { $0 }
    ) throws(ConfigIssues) {
        let issues = ConfigValidator.validate(config, home: home, fileExists: fileExists)
        if !issues.isEmpty { throw ConfigIssues(issues: issues) }

        self.config = config
        root = canonicalize(Paths.expandTilde(config.root, home: home))
        minAgeSeconds = config.minAgeSeconds
        sortFolders = config.sortFolders
        skipGlobs = config.skipGlobs
        neverMove = config.neverMove
        fallback = config.fallback

        screenCapture = config.triage.first { $0.screenCapture == true }.map { ($0.name, $0.to) }
        nameRules = config.triage.compactMap { rule in
            guard let pattern = rule.regex, let regex = try? Regex(pattern) else { return nil }
            return NameRule(name: rule.name, regex: regex, to: rule.to)
        }
        var extensionMap: [String: String] = [:]
        for category in config.categories {
            for ext in category.extensions ?? [] {
                let key = ConfigValidator.normalizeExtension(ext)
                if extensionMap[key] == nil { extensionMap[key] = category.to }
            }
        }
        self.extensionMap = extensionMap
        typeRules = config.categories.compactMap { category in
            let types = (category.types ?? []).compactMap { UTType($0) }
            return types.isEmpty ? nil : TypeRule(types: types, to: category.to)
        }
        let destinations = config.triage.map(\.to) + config.categories.map(\.to) + [config.fallback]
        bucketNames = Set(destinations.compactMap { $0.split(separator: "/").first.map { Names.key(String($0)) } })
    }
}

public enum ConfigValidator {
    /// Returns every problem in `config`; an empty array means it is valid.
    public static func validate(_ config: Config, home: String, fileExists: (String) -> Bool) -> [ConfigIssue] {
        var issues: [ConfigIssue] = []
        if config.version != Config.currentVersion {
            issues.append(ConfigIssue("version", "unsupported version \(config.version) (expected \(Config.currentVersion))"))
        }

        let root = Paths.expandTilde(config.root, home: home)
        if !root.hasPrefix("/") {
            issues.append(ConfigIssue("root", "must be an absolute path or start with ~/"))
        } else if !fileExists(root) {
            issues.append(ConfigIssue("root", "folder does not exist: \(root)"))
        }
        if !(config.minAgeSeconds >= 0) {
            issues.append(ConfigIssue("minAgeSeconds", "must be zero or more"))
        }

        for (i, rule) in config.triage.enumerated() {
            let at = "triage[\(i)]"
            if rule.name.isEmpty { issues.append(ConfigIssue("\(at).name", "must not be empty")) }
            switch (rule.screenCapture, rule.regex) {
            case (nil, nil):
                issues.append(ConfigIssue(at, "needs either \"screenCapture\": true or \"regex\""))
            case (.some, .some):
                issues.append(ConfigIssue(at, "set only one of \"screenCapture\" and \"regex\""))
            case (.some(let flag), nil) where !flag:
                issues.append(ConfigIssue("\(at).screenCapture", "must be true (remove the rule to disable it)"))
            case (nil, .some(let pattern)):
                do { _ = try Regex(pattern) } catch {
                    issues.append(ConfigIssue("\(at).regex", "does not compile: \(error)"))
                }
            default:
                break
            }
            issues += destinationIssues(rule.to, at: "\(at).to")
        }

        for (i, category) in config.categories.enumerated() {
            let at = "categories[\(i)]"
            if (category.extensions ?? []).isEmpty && (category.types ?? []).isEmpty {
                issues.append(ConfigIssue(at, "needs at least one entry in \"extensions\" or \"types\""))
            }
            for (j, ext) in (category.extensions ?? []).enumerated() where normalizeExtension(ext).isEmpty {
                issues.append(ConfigIssue("\(at).extensions[\(j)]", "must not be empty"))
            }
            for (j, id) in (category.types ?? []).enumerated() where UTType(id)?.isDeclared != true {
                issues.append(ConfigIssue("\(at).types[\(j)]", "unknown type identifier \"\(id)\""))
            }
            issues += destinationIssues(category.to, at: "\(at).to")
        }
        issues += destinationIssues(config.fallback, at: "fallback")
        return issues
    }

    /// A destination must be a relative path inside the root with no `.` or `..` parts.
    static func destinationIssues(_ destination: String, at path: String) -> [ConfigIssue] {
        if destination.isEmpty { return [ConfigIssue(path, "must not be empty")] }
        if destination.hasPrefix("/") || destination.hasPrefix("~") {
            return [ConfigIssue(path, "must be a relative folder path inside the root, not \"\(destination)\"")]
        }
        let parts = destination.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            return [ConfigIssue(path, "must not contain empty, \".\" or \"..\" components: \"\(destination)\"")]
        }
        return []
    }

    static func normalizeExtension(_ ext: String) -> String {
        (ext.hasPrefix(".") ? String(ext.dropFirst()) : ext).lowercased()
    }
}
