/// Builds Finder-style alternative names for collisions: `doc (1).pdf`, `backup (1).tar.gz`,
/// `Tool (1).app`, `README (1)`, and for undo `report (restored).pdf`, `report (restored 2).pdf`.
public enum SuffixNamer {
    /// Multi-part extensions kept together when adding a suffix.
    public static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst"]
    /// The maximum length of a file name on APFS, in UTF-8 bytes.
    public static let maxNameBytes = 255

    /// `name (n).ext` for n >= 1.
    public static func numbered(_ name: String, _ n: Int) -> String {
        compose(name, suffix: " (\(n))")
    }

    /// `name (restored).ext` for n == 1, `name (restored n).ext` for n >= 2.
    public static func restored(_ name: String, _ n: Int) -> String {
        compose(name, suffix: n <= 1 ? " (restored)" : " (restored \(n))")
    }

    /// Splits `name` into a stem and an extension that includes its leading dot.
    public static func split(_ name: String) -> (stem: String, ext: String) {
        let lower = name.lowercased()
        for compound in compoundExtensions where lower.hasSuffix("." + compound) {
            let cut = name.index(name.endIndex, offsetBy: -(compound.count + 1))
            if cut > name.startIndex { return (String(name[..<cut]), String(name[cut...])) }
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex
        else { return (name, "") }
        return (String(name[..<dot]), String(name[dot...]))
    }

    /// Inserts `suffix` between stem and extension, trimming the stem (on a grapheme
    /// boundary) when the result would exceed `maxNameBytes`.
    static func compose(_ name: String, suffix: String) -> String {
        var (stem, ext) = split(name)
        while (stem + suffix + ext).utf8.count > maxNameBytes, !stem.isEmpty {
            stem.removeLast()
        }
        return stem + suffix + ext
    }
}
