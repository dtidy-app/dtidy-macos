import DSortCore
import Foundation

/// Lists the top level of the root folder as entries, without following symlinks or
/// reading file contents.
public struct Scanner: Sendable {
    public let ops: any FileOps
    public let environment: Environment

    public init(ops: any FileOps = RealFileOps(), environment: Environment = .current) {
        self.ops = ops
        self.environment = environment
    }

    public func scan(_ root: String) throws(DSortError) -> [Entry] {
        let names: [String]
        let fsid: [Int32]
        do {
            names = try ops.listDirectory(root)
            fsid = try ops.fsid(root)
        } catch {
            throw PermissionHelp.error(for: error, root: root, environment: environment)
        }

        return names.compactMap { name in
            let path = Paths.join(root, name)
            // An item that vanished since the listing is simply not part of this run.
            guard let info = try? ops.lstat(path) else { return nil }
            var kind = info.kind
            if kind == .folder && ops.isPackage(path) { kind = .package }
            let screenCapture = (kind == .file || kind == .package) && ops.isScreenCapture(path)
            return Entry(
                name: name, path: path, kind: kind,
                identity: FileIdentity(fsid: fsid, ino: info.ino, birth: info.birth),
                modified: info.modified, isScreenCapture: screenCapture)
        }
    }
}

/// Explains macOS privacy (TCC) and permission failures.
public enum PermissionHelp {
    public static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Maps a failure to read `root` to a `DSortError` with the right exit code.
    public static func error(for error: SysError, root: String, environment: Environment) -> DSortError {
        switch error.code {
        case EPERM, EACCES:
            return DSortError(.noPermission, message(root: root, environment: environment, error: error))
        case ENOENT, ENOTDIR:
            return DSortError(.usage, "The folder to sort does not exist: \(root)")
        default:
            return DSortError(.partial, "Cannot read \(root): \(error.reason)")
        }
    }

    public static func message(root: String, environment: Environment, error: SysError) -> String {
        """
        Cannot read \(root): \(error.reason).
        macOS privacy controls block access for \(responsibleApp(environment)).
        Grant it access in System Settings > Privacy & Security > Files and Folders (Desktop Folder),
        or > Full Disk Access. To open that pane, run:
          open "\(settingsURL)"
        """
    }

    /// The app macOS holds responsible: the terminal when known, otherwise this binary.
    public static func responsibleApp(_ environment: Environment) -> String {
        let terminals = [
            "Apple_Terminal": "Terminal", "iTerm.app": "iTerm", "vscode": "Visual Studio Code",
            "WarpTerminal": "Warp", "ghostty": "Ghostty", "WezTerm": "WezTerm", "Hyper": "Hyper",
        ]
        if let program = environment.nonEmpty("TERM_PROGRAM") {
            return "the terminal app \"\(terminals[program] ?? program)\""
        }
        let binary = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "dsort"
        return "the dsort binary at \(binary)"
    }
}
