/// The user configuration, as stored in `config.json`.
///
/// A config file is the complete configuration: omitted scalar fields take the documented
/// default below, but the rule lists (`triage`, `categories`) are empty unless given.
public struct Config: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var root: String
    public var minAgeSeconds: Double
    public var sortFolders: Bool
    public var skipGlobs: [String]
    public var neverMove: [String]
    public var triage: [TriageRule]
    public var categories: [Category]
    public var fallback: String

    public init(
        version: Int = Config.currentVersion,
        root: String = Defaults.root,
        minAgeSeconds: Double = Defaults.minAgeSeconds,
        sortFolders: Bool = Defaults.sortFolders,
        skipGlobs: [String] = Defaults.skipGlobs,
        neverMove: [String] = Defaults.neverMove,
        triage: [TriageRule] = [],
        categories: [Category] = [],
        fallback: String = Defaults.fallback
    ) {
        self.version = version
        self.root = root
        self.minAgeSeconds = minAgeSeconds
        self.sortFolders = sortFolders
        self.skipGlobs = skipGlobs
        self.neverMove = neverMove
        self.triage = triage
        self.categories = categories
        self.fallback = fallback
    }

    /// Per-field defaults used when a config file omits a field.
    public enum Defaults {
        public static let root = "~/Desktop"
        public static let minAgeSeconds: Double = 10
        public static let sortFolders = false
        public static let skipGlobs = ["*.download", "*.crdownload", "*.part"]
        public static let neverMove: [String] = []
        public static let fallback = "Other"
    }

    public static let screenshotPattern =
        #"^(Screenshot|Screen Shot|Ekran Resmi|Bildschirmfoto|Capture d['’]écran) \d{4}-\d{2}-\d{2}"#
    public static let cameraPattern = #"^(IMG_|DSC_|DSCF|PXL_)\d+"#

    /// The built-in configuration used when no config file exists. `dtidy config init`
    /// writes exactly this value, so the file and the built-ins cannot drift apart.
    public static let `default` = Config(
        triage: [
            TriageRule(name: "screenshot", screenCapture: true, to: "Images/_Screenshots"),
            TriageRule(name: "screenshot-name", regex: screenshotPattern, to: "Images/_Screenshots"),
            TriageRule(name: "camera", regex: cameraPattern, to: "Images/_Inbox"),
        ],
        categories: [
            Category(to: "Images", types: ["public.image"]),
            Category(to: "Videos", types: ["public.movie"]),
            Category(to: "Audio", types: ["public.audio"]),
            Category(to: "PDFs", types: ["com.adobe.pdf"]),
            Category(
                to: "Code",
                extensions: ["ts", "tsx", "jsx", "kt", "kts", "json", "yml", "yaml", "toml"],
                types: ["public.source-code"]),
            // Before Archives: OpenDocument files also conform to public.archive.
            Category(to: "Documents", extensions: ["doc", "tex"], types: ["public.composite-content", "public.text"]),
            Category(to: "Archives", types: ["public.archive", "public.disk-image"]),
        ]
    )

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, root, minAgeSeconds, sortFolders, skipGlobs, neverMove, triage, categories, fallback
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        root = try c.decodeIfPresent(String.self, forKey: .root) ?? Defaults.root
        minAgeSeconds = try c.decodeIfPresent(Double.self, forKey: .minAgeSeconds) ?? Defaults.minAgeSeconds
        sortFolders = try c.decodeIfPresent(Bool.self, forKey: .sortFolders) ?? Defaults.sortFolders
        skipGlobs = try c.decodeIfPresent([String].self, forKey: .skipGlobs) ?? Defaults.skipGlobs
        neverMove = try c.decodeIfPresent([String].self, forKey: .neverMove) ?? Defaults.neverMove
        triage = try c.decodeIfPresent([TriageRule].self, forKey: .triage) ?? []
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        fallback = try c.decodeIfPresent(String.self, forKey: .fallback) ?? Defaults.fallback
    }
}

/// A triage rule: routes items matching the screen-capture metadata or a name pattern.
/// Exactly one of `screenCapture` (which must be `true`) and `regex` is set.
public struct TriageRule: Codable, Sendable, Equatable {
    public var name: String
    public var screenCapture: Bool?
    public var regex: String?
    public var to: String

    public init(name: String, screenCapture: Bool? = nil, regex: String? = nil, to: String) {
        self.name = name
        self.screenCapture = screenCapture
        self.regex = regex
        self.to = to
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case name, screenCapture, regex, to }
}

/// A category: routes items by file name extension (checked first, across all categories)
/// or by system type conformance (checked in category order).
public struct Category: Codable, Sendable, Equatable {
    public var to: String
    public var extensions: [String]?
    public var types: [String]?

    public init(to: String, extensions: [String]? = nil, types: [String]? = nil) {
        self.to = to
        self.extensions = extensions
        self.types = types
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case to, extensions, types }
}
