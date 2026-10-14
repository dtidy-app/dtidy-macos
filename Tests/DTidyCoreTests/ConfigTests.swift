import Foundation
import Testing
@testable import DTidyCore

private func parse(_ json: String) throws(ConfigIssues) -> Config {
    try ConfigParser.parse(Data(json.utf8))
}

private func issues(_ json: String, rootExists: Bool = true) -> [ConfigIssue] {
    do {
        let config = try parse(json)
        return ConfigValidator.validate(config, home: "/Users/t", fileExists: { _ in rootExists })
    } catch {
        return error.issues
    }
}

private func paths(_ json: String) -> [String] { issues(json).map(\.path) }

@Suite struct ConfigDecodingTests {
    @Test func minimalFileTakesDefaultsWithEmptyRuleLists() throws {
        let config = try parse(#"{"version": 1}"#)
        #expect(config.root == "~/Desktop")
        #expect(config.minAgeSeconds == 10)
        #expect(config.sortFolders == false)
        #expect(config.skipGlobs == ["*.download", "*.crdownload", "*.part"])
        #expect(config.neverMove == [])
        #expect(config.triage.isEmpty)
        #expect(config.categories.isEmpty)
        #expect(config.fallback == "Other")
    }

    @Test func defaultConfigRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Config.default)
        #expect(try ConfigParser.parse(data) == Config.default)
    }

    @Test func defaultConfigIsValid() {
        #expect(ConfigValidator.validate(.default, home: "/Users/t", fileExists: { _ in true }).isEmpty)
    }

    @Test func versionIsRequired() {
        #expect(paths("{}") == ["version"])
    }

    @Test func wrongTypeIsReportedWithFieldPath() {
        #expect(paths(#"{"version": 1, "categories": [{"to": 3}]}"#) == ["categories[0].to"])
    }
}

@Suite struct ConfigValidationTests {
    @Test func unknownVersionIsRejected() {
        #expect(paths(#"{"version": 2}"#) == ["version"])
    }

    @Test func unknownTopLevelFieldIsRejected() {
        #expect(paths(#"{"version": 1, "roots": "~/Desktop"}"#) == ["roots"])
    }

    @Test func unknownNestedFieldsAreRejected() {
        let json = #"{"version": 1, "triage": [{"name": "a", "regex": "x", "to": "A", "dest": "B"}], "categories": [{"to": "C", "type": ["public.image"]}]}"#
        #expect(Set(paths(json)) == ["triage[0].dest", "categories[0].type"])
    }

    @Test func regexThatDoesNotCompileIsRejected() {
        let found = issues(#"{"version": 1, "triage": [{"name": "s", "regex": "^(Screenshot", "to": "Images"}]}"#)
        #expect(found.map(\.path) == ["triage[0].regex"])
        #expect(found[0].message.contains("does not compile"))
    }

    @Test func triageNeedsExactlyOneMatcher() {
        #expect(paths(#"{"version": 1, "triage": [{"name": "s", "to": "A"}]}"#) == ["triage[0]"])
        #expect(paths(#"{"version": 1, "triage": [{"name": "s", "regex": "x", "screenCapture": true, "to": "A"}]}"#) == ["triage[0]"])
        #expect(paths(#"{"version": 1, "triage": [{"name": "s", "screenCapture": false, "to": "A"}]}"#) == ["triage[0].screenCapture"])
    }

    @Test func undeclaredTypeIdentifierIsRejected() {
        #expect(paths(#"{"version": 1, "categories": [{"to": "X", "types": ["com.example.nope"]}]}"#) == ["categories[0].types[0]"])
    }

    @Test(arguments: ["/Users/t/Docs", "~/Docs", "", "../Documents", "Images/../..", "./Images", "Images//Raw", "Images/"])
    func invalidDestinationIsRejected(destination: String) {
        let json = #"{"version": 1, "categories": [{"to": "\#(destination)", "types": ["public.image"]}]}"#
        #expect(paths(json) == ["categories[0].to"])
    }

    @Test func pathEscapeMessageNamesTheDestination() {
        let found = issues(#"{"version": 1, "categories": [{"to": "../Documents", "types": ["public.image"]}]}"#)
        #expect(found.first?.description.contains("categories[0].to") == true)
        #expect(found.first?.description.contains("../Documents") == true)
    }

    @Test func nestedRelativeDestinationIsAccepted() {
        #expect(paths(#"{"version": 1, "categories": [{"to": "Images/_Inbox", "types": ["public.image"]}]}"#).isEmpty)
    }

    @Test func missingRootIsRejected() {
        #expect(issues(#"{"version": 1}"#, rootExists: false).map(\.path) == ["root"])
    }

    @Test func relativeRootIsRejected() {
        #expect(paths(#"{"version": 1, "root": "Desktop"}"#) == ["root"])
    }

    @Test func emptyFallbackIsRejected() {
        #expect(paths(#"{"version": 1, "fallback": ""}"#) == ["fallback"])
    }

    @Test func categoryNeedsExtensionsOrTypes() {
        #expect(paths(#"{"version": 1, "categories": [{"to": "X"}]}"#) == ["categories[0]"])
    }

    @Test func malformedJSONIsReported() {
        #expect(issues("{").first?.message.contains("not valid JSON") == true)
        #expect(issues("[]").first?.message.contains("JSON object") == true)
    }
}

@Suite struct PathResolutionTests {
    let home = "/Users/t"

    @Test func explicitConfigWins() {
        let env = Environment(home: home, variables: ["XDG_CONFIG_HOME": "/x"])
        #expect(Paths.configFile(explicit: "./alt.json", environment: env) == "./alt.json")
        #expect(Paths.configFile(explicit: "~/alt.json", environment: env) == "/Users/t/alt.json")
    }

    @Test func xdgConfigHomeIsUsedWhenSet() {
        let env = Environment(home: home, variables: ["XDG_CONFIG_HOME": "/x"])
        #expect(Paths.configFile(explicit: nil, environment: env) == "/x/dtidy/config.json")
    }

    @Test func emptyXdgConfigHomeFallsBackToDotConfig() {
        for vars in [[:], ["XDG_CONFIG_HOME": ""]] {
            let env = Environment(home: home, variables: vars)
            #expect(Paths.configFile(explicit: nil, environment: env) == "/Users/t/.config/dtidy/config.json")
        }
    }

    @Test func tildeExpansion() {
        #expect(Paths.expandTilde("~/Desktop", home: home) == "/Users/t/Desktop")
        #expect(Paths.expandTilde("~", home: home) == "/Users/t")
        #expect(Paths.expandTilde("/abs", home: home) == "/abs")
        #expect(Paths.expandTilde("~other/x", home: home) == "~other/x")
    }

    @Test func resolvedRootIsExpanded() throws {
        let resolved = try ResolvedConfig(Config(version: 1), home: home, fileExists: { _ in true })
        #expect(resolved.root == "/Users/t/Desktop")
    }
}
