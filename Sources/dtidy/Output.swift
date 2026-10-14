import DTidyCore
import Foundation

/// Writes a command result: JSON on stdout with `--json`, otherwise text on stdout.
func emit<T: Encodable>(_ value: T, json: Bool, text: (T) -> String) {
    print(json ? Render.json(value) : text(value), terminator: "")
}
