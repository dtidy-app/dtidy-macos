import DTidyCore
import Foundation
import Testing
@testable import DTidyIO

@Suite struct DoctorTests {
    @Test func healthyTempRootPassesAndChangesNothing() {
        let f = Fixture()
        f.file("a.pdf")
        let before = f.snapshot()
        let checks = Doctor(environment: f.env).run(configPath: nil, rootOverride: f.root)
        #expect(checks.allSatisfy { $0.status == .pass })
        #expect(Set(checks.map(\.name)).isSuperset(of: ["config", "root", "exclusive rename", "path from file ID", "lock", "history"]))
        #expect(f.snapshot() == before)
    }

    @Test func missingRootFails() {
        let f = Fixture()
        let checks = Doctor(environment: f.env).run(configPath: nil, rootOverride: f.tmp.sub("nope"))
        #expect(checks.first { $0.name == "root" }?.status == .fail)
    }

    @Test func invalidConfigFails() throws {
        let f = Fixture()
        let path = f.tmp.file("bad.json", #"{"version": 1, "fallback": "../x"}"#)
        let checks = Doctor(environment: f.env).run(configPath: path, rootOverride: f.root)
        #expect(checks.first { $0.name == "config" }?.status == .fail)
    }

    @Test func interruptedRunIsAWarning() throws {
        let f = Fixture()
        let w = try f.store.create(runId: "r1")
        try w.append(.run(RunHeader(run: "r1", kind: .sort, ts: "t", root: f.root)))
        let history = Doctor(environment: f.env).run(configPath: nil, rootOverride: f.root).first { $0.name == "history" }
        #expect(history?.status == .warn)
        #expect(history?.detail.contains("dtidy recover") == true)
    }
}
