import DTidyCore
import Foundation
import Testing
@testable import DTidyIO

@Suite struct ConfigLoaderTests {
    @Test func initWritesValidDefaultsAndRefusesToOverwrite() throws {
        let tmp = TempDir()
        let env = Environment(home: tmp.path, variables: ["XDG_CONFIG_HOME": tmp.sub("cfg")])
        tmp.dir("Desktop")
        let path = Paths.configFile(explicit: nil, environment: env)

        try ConfigLoader.writeDefaults(to: path)
        let loaded = try ConfigLoader.load(explicit: nil, environment: env)
        #expect(loaded.fileExists)
        #expect(loaded.resolved.config == .default)

        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(throws: DTidyError.self) { try ConfigLoader.writeDefaults(to: path) }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    }

    @Test func missingExplicitFileIsAUsageError() {
        let tmp = TempDir()
        let env = Environment(home: tmp.path, variables: [:])
        do {
            _ = try ConfigLoader.load(explicit: tmp.sub("nope.json"), environment: env)
            Issue.record("expected an error")
        } catch {
            #expect(error.exit == .usage)
        }
    }

    @Test func rootOverrideReplacesConfiguredRoot() throws {
        let tmp = TempDir()
        let env = Environment(home: tmp.path, variables: ["XDG_CONFIG_HOME": tmp.sub("cfg")])
        let root = tmp.dir("elsewhere")
        let loaded = try ConfigLoader.load(explicit: nil, rootOverride: root, environment: env)
        #expect(loaded.resolved.root == root)
        #expect(loaded.fileExists == false)
    }
}
