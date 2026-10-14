import Darwin
import UniformTypeIdentifiers

/// Decides, without touching the filesystem, whether an entry is sorted and where.
///
/// Rules are evaluated in a fixed order and the first match wins: skip rules, screenshot
/// metadata, triage name patterns, extension overrides, type categories, fallback.
public struct Classifier: Sendable {
    public let config: ResolvedConfig

    public init(_ config: ResolvedConfig) {
        self.config = config
    }

    /// Rule names reported for matches that are not named triage rules.
    public enum RuleName {
        public static let `extension` = "extension"
        public static let type = "type"
        public static let fallback = "fallback"
    }

    /// Classifies `entry`; `now` is seconds since 1970, used for the minimum-age rule.
    public func classify(_ entry: Entry, now: Double) -> Decision {
        if let reason = skipReason(entry, now: now) { return .skip(reason) }

        if entry.isScreenCapture, let rule = config.screenCapture {
            return .move(to: rule.to, rule: rule.name)
        }
        let name = Names.nfc(entry.name)
        for rule in config.nameRules where (try? rule.regex.firstMatch(in: name)) != nil {
            return .move(to: rule.to, rule: rule.name)
        }

        let ext = Self.pathExtension(entry.name)
        if !ext.isEmpty, let to = config.extensionMap[ext] {
            return .move(to: to, rule: RuleName.extension)
        }
        if let type = Self.type(of: entry, extension: ext) {
            for rule in config.typeRules where rule.types.contains(where: { type.conforms(to: $0) }) {
                return .move(to: rule.to, rule: RuleName.type)
            }
        }
        return .move(to: config.fallback, rule: RuleName.fallback)
    }

    private func skipReason(_ entry: Entry, now: Double) -> SkipReason? {
        if entry.name.hasPrefix(".") { return .hidden }
        if config.bucketNames.contains(Names.key(entry.name)) { return .bucket }
        switch entry.kind {
        case .symlink: return .symlink
        case .special: return .special
        case .folder where !config.sortFolders: return .folder
        default: break
        }
        if Self.matchesAny(entry.name, config.skipGlobs) { return .skipGlob }
        if Self.matchesAny(entry.name, config.neverMove) { return .neverMove }
        if now - entry.modified < config.minAgeSeconds { return .tooRecent }
        return nil
    }

    /// Case-insensitive shell-style glob match on NFC-normalized names.
    static func matchesAny(_ name: String, _ globs: [String]) -> Bool {
        let name = Names.nfc(name)
        return globs.contains { fnmatch(Names.nfc($0), name, FNM_CASEFOLD) == 0 }
    }

    /// The lowercased text after the last dot, or "" when there is none (or only a leading dot).
    static func pathExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    /// The system type for an entry, derived from its extension only (contents are never read).
    static func type(of entry: Entry, extension ext: String) -> UTType? {
        guard !ext.isEmpty else { return entry.kind == .folder ? .folder : nil }
        // Packages resolve to their bundle type only when looked up as packages.
        return UTType(filenameExtension: ext, conformingTo: entry.kind == .package ? .package : .data)
    }
}
