import Foundation
import Testing
@testable import DSortCore

let testNow: Double = 1_800_000_000

func entry(
    _ name: String, kind: EntryKind = .file, age: Double = 3600, screenCapture: Bool = false, ino: UInt64 = 1
) -> Entry {
    Entry(
        name: name, path: "/Users/t/Desktop/" + name, kind: kind,
        identity: FileIdentity(fsid: [1, 26], ino: ino, birth: 1_700_000_000),
        modified: testNow - age, isScreenCapture: screenCapture)
}

func classifier(_ config: Config = .default) -> Classifier {
    Classifier(try! ResolvedConfig(config, home: "/Users/t", fileExists: { _ in true }))
}

@Suite struct SkipRuleTests {
    let c = classifier()

    @Test func hiddenItemsAreSkipped() {
        #expect(c.classify(entry(".DS_Store"), now: testNow) == .skip(.hidden))
        #expect(c.classify(entry(".localized"), now: testNow) == .skip(.hidden))
    }

    @Test func inProgressDownloadsAreSkipped() {
        #expect(c.classify(entry("installer.dmg.crdownload"), now: testNow) == .skip(.skipGlob))
        #expect(c.classify(entry("movie.mp4.download", kind: .package), now: testNow) == .skip(.skipGlob))
        #expect(c.classify(entry("x.PART"), now: testNow) == .skip(.skipGlob))
    }

    @Test func plainFoldersAreSkippedByDefault() {
        #expect(c.classify(entry("toolkit-0.12.0-beta", kind: .folder), now: testNow) == .skip(.folder))
        #expect(c.classify(entry("Project", kind: .folder), now: testNow) == .skip(.folder))
    }

    @Test func foldersAreSortedWhenEnabled() {
        var config = Config.default
        config.sortFolders = true
        #expect(classifier(config).classify(entry("Project", kind: .folder), now: testNow) == .move(to: "Other", rule: "fallback"))
    }

    @Test func packagesAreSortedAsFiles() {
        #expect(c.classify(entry("Tool.app", kind: .package), now: testNow) == .move(to: "Other", rule: "fallback"))
        #expect(c.classify(entry("Slides.key", kind: .package), now: testNow) == .move(to: "Documents", rule: "type"))
    }

    @Test func symlinksAreSkipped() {
        #expect(c.classify(entry("notes", kind: .symlink), now: testNow) == .skip(.symlink))
        #expect(c.classify(entry("photo.png", kind: .symlink), now: testNow) == .skip(.symlink))
    }

    @Test func specialFilesAreSkipped() {
        #expect(c.classify(entry("pipe", kind: .special), now: testNow) == .skip(.special))
    }

    @Test func recentItemsWaitForTheNextRun() {
        #expect(c.classify(entry("Screenshot 2026-10-14 at 16.48.54.png", age: 3, screenCapture: true), now: testNow) == .skip(.tooRecent))
        #expect(c.classify(entry("old.png", age: 10), now: testNow) == .move(to: "Images", rule: "type"))
    }

    @Test func neverMovePatternsAreHonored() {
        var config = Config.default
        config.neverMove = ["*.kdbx"]
        #expect(classifier(config).classify(entry("vault.kdbx"), now: testNow) == .skip(.neverMove))
        #expect(classifier(config).classify(entry("Vault.KDBX"), now: testNow) == .skip(.neverMove))
    }

    @Test func bucketFoldersAreNeverSorted() {
        #expect(c.classify(entry("Images", kind: .folder), now: testNow) == .skip(.bucket))
        #expect(c.classify(entry("other", kind: .folder), now: testNow) == .skip(.bucket))
        #expect(c.classify(entry("PDFs", kind: .folder), now: testNow) == .skip(.bucket))
    }
}

@Suite struct RoutingTests {
    let c = classifier()

    @Test func screenshotMetadataBeatsNameAndType() {
        #expect(c.classify(entry("diagram.png", screenCapture: true), now: testNow) == .move(to: "Images/_Screenshots", rule: "screenshot"))
    }

    @Test func exportedScreenshotIsDetectedByName() {
        #expect(c.classify(entry("Screenshot 2026-08-24 at 22.11.28.jpg"), now: testNow) == .move(to: "Images/_Screenshots", rule: "screenshot-name"))
    }

    @Test func decomposedAccentStillMatches() {
        let decomposed = "Capture d’e\u{301}cran 2026-01-02 a\u{300} 10.00.00.png"
        #expect(decomposed.unicodeScalars.contains("\u{301}"))
        #expect(c.classify(entry(decomposed), now: testNow) == .move(to: "Images/_Screenshots", rule: "screenshot-name"))
    }

    @Test func cameraImportsGoToTheInbox() {
        #expect(c.classify(entry("IMG_4821.HEIC"), now: testNow) == .move(to: "Images/_Inbox", rule: "camera"))
    }

    @Test func typeScriptIsNotTreatedAsVideo() {
        #expect(c.classify(entry("app.ts"), now: testNow) == .move(to: "Code", rule: "extension"))
        var config = Config.default
        config.categories.removeAll { $0.to == "Code" }
        #expect(classifier(config).classify(entry("app.ts"), now: testNow) == .move(to: "Videos", rule: "type"))
    }

    @Test func pdfIsRoutedByType() {
        #expect(c.classify(entry("invoice.pdf"), now: testNow) == .move(to: "PDFs", rule: "type"))
    }

    @Test func unknownExtensionFallsBack() {
        #expect(c.classify(entry("data.xyz123"), now: testNow) == .move(to: "Other", rule: "fallback"))
        #expect(c.classify(entry("README"), now: testNow) == .move(to: "Other", rule: "fallback"))
    }

    @Test func screenshotBeatsGenericImageCategory() {
        #expect(c.classify(entry("Screenshot 2026-10-14 at 16.48.54.png", screenCapture: true), now: testNow) == .move(to: "Images/_Screenshots", rule: "screenshot"))
    }

    @Test(arguments: [
        ("report.docx", "Documents"), ("notes.odt", "Documents"), ("sheet.xlsx", "Documents"),
        ("book.epub", "Documents"), ("paper.tex", "Documents"), ("todo.txt", "Documents"),
        ("backup.tar.gz", "Archives"), ("disk.dmg", "Archives"), ("Main.kt", "Code"),
        ("tool.swift", "Code"), ("data.json", "Code"), ("song.mp3", "Audio"), ("clip.mov", "Videos"),
        ("logo.svg", "Images"), ("photo.heic", "Images"),
    ])
    func defaultCategories(name: String, bucket: String) {
        guard case .move(let to, _) = c.classify(entry(name), now: testNow) else {
            Issue.record("\(name) was skipped"); return
        }
        #expect(to == bucket, "\(name)")
    }

    @Test func extensionOverridesAreCaseInsensitive() {
        #expect(c.classify(entry("APP.TS"), now: testNow) == .move(to: "Code", rule: "extension"))
    }

    @Test func emptyRuleListsSendEverythingToFallback() {
        #expect(classifier(Config(version: 1)).classify(entry("a.png", screenCapture: true), now: testNow) == .move(to: "Other", rule: "fallback"))
    }
}

@Suite struct DefaultPatternTests {
    let c = classifier()

    @Test(arguments: [
        "Screenshot 2026-10-14 at 16.48.54.png",
        "Screen Shot 2020-01-02 at 10.00.00 AM.png",
        "Ekran Resmi 2026-10-14 16.48.54.png",
        "Bildschirmfoto 2026-10-14 um 16.48.54.png",
        "Capture d’écran 2026-10-14 à 16.48.54.png",
        "Capture d'écran 2026-10-14 à 16.48.54.png",
    ])
    func screenshotNames(name: String) {
        #expect(c.classify(entry(name), now: testNow) == .move(to: "Images/_Screenshots", rule: "screenshot-name"))
    }

    @Test(arguments: ["IMG_4821.HEIC", "DSC_0001.JPG", "DSCF1234.RAF", "PXL_20260101_123456.jpg"])
    func cameraNames(name: String) {
        #expect(c.classify(entry(name), now: testNow) == .move(to: "Images/_Inbox", rule: "camera"))
    }

    @Test(arguments: ["My Screenshot 2026-10-14.png", "Screenshot.png", "IMG_.jpg", "img_1234.jpg", "DSCX1234.jpg"])
    func nonMatchingNames(name: String) {
        guard case .move(_, let rule) = c.classify(entry(name), now: testNow) else {
            Issue.record("skipped"); return
        }
        #expect(rule != "screenshot-name" && rule != "camera", "\(name)")
    }
}
