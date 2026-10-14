# Design

## Context

- **Repository.** It is local only, with no remote. It holds four commits, all authored as `t-ilk <i@ilkers-MacBook-Pro.local>`. No `user.email` is configured, so git derived that address from the hostname, and GitHub would not link these commits to the author's account.
- **Version and build.** `DTidyVersion.current` (`Sources/DTidyCore/Version.swift`) is `"0.1.0"`, and `--version` and the ledger `tool` field read it. `make install` and `make check-man` already exist, `docs/man/dtidy.1` is committed, and `--generate-completion-script <shell>` prints the completion scripts.
- **Homebrew 7.0.9, as checked in its local source:**
  - `generate_completions_from_executable(bin/"dtidy", "--generate-completion-script")` appends the bare shell name by default, which matches dtidy's flag. It writes `etc/bash_completion.d/dtidy`, `share/zsh/site-functions/_dtidy` and `share/fish/vendor_completions.d/dtidy.fish`.
  - `brew tap-new` creates a tap with `tests.yml` (`brew test-bot`), `publish.yml` (bottles, triggered by a `pr-pull` label) and `autobump.yml` workflows.
- **Toolchain.** This machine has Xcode 27 with Swift 6.4. The package needs Swift tools 6.0 and macOS 14.
- **Names.** The GitHub name `dtidy` is unavailable. The public API reports it as not found, but GitHub's sign-up form refuses it, most likely because a hidden or suspended account holds it. So an API 404 is not proof that a name is free. The organization `dtidy-app` was created on 2026-10-14. `dtidy-app/dtidy-macos` exists: public, empty, default branch `main`. The `gh` CLI is not installed.

## Goals / Non-Goals

**Goals:**
- `brew install dtidy-app/tap/dtidy` works on a supported Mac, with completions and the man page, and installs a bottle where one exists.
- A repeatable release procedure that cannot tag a version the binary does not report.
- A public repository whose history and community files are ready for outside contributors.

**Non-Goals:**
- homebrew-core, which requires an established, notable project. Revisit after real usage.
- Signed or notarized binaries. Homebrew-built and bottled formulae are not quarantined, so Gatekeeper is not involved.
- Automating formula bumps from the dtidy-macos repository, because cross-repository tokens add a secret to manage. The tap's `autobump.yml` and `brew bump-formula-pr` cover it.

## Decisions

### One repository per OS, in a `dtidy-app` organization
- The repositories are:
  - `dtidy-app/dtidy-macos` (this one);
  - later `dtidy-app/dtidy-windows` and `dtidy-app/dtidy-linux`;
  - `dtidy-app/spec`, the shared OpenSpec store, when the second port starts (per `docs/porting.md`);
  - `dtidy-app/homebrew-tap`.
- *Why per OS:* each port uses its native toolchain and its own CI. Version numbers stay independent, so a Windows fix does not force a macOS release. A Homebrew tarball contains only Swift code, and the formula builds from the repository root with plain `vX.Y.Z` tags.
- *Why an organization:* the project name stays stable across platforms, and repositories can move in and out with redirects. The author owns it, and commits stay attributed to `t-ilk`.
- *Why `dtidy-app`:* `dtidy` was unavailable. `dtidy-app` keeps the tool name first, and only the owner part of the install command changes. The command stays `dtidy`.
- *Alternatives considered:*
  - a monorepo, which needs prefixed tags, a subfolder build and a mixed-toolchain CI, and only pays off if the ports share code;
  - repositories on the personal account, which works but splits the name once ports arrive.

### The tap is named `homebrew-tap`, so users run `brew install dtidy-app/tap/dtidy`
- A generic tap name can also hold future macOS tools from the organization. The command still reads as "dtidy".
- *Alternative considered:* `homebrew-dtidy`, which would give `dtidy-app/dtidy/dtidy`, a repetitive command.

### Rewrite authorship before the first push
- Set `user.email` (globally) to the GitHub noreply address `50845773+t-ilk@users.noreply.github.com`, which keeps the personal address private. 50845773 is `t-ilk`'s account ID.
- Then rewrite the four unpublished commits with `git rebase --root --exec 'git commit --amend --no-edit --author="t-ilk <50845773+t-ilk@users.noreply.github.com>"'`. Using `--author` instead of `--reset-author` keeps the original author dates. Commit messages, trees and `Co-Authored-By` trailers stay as they are.
- *Done 2026-10-14:* all commits carry the noreply address, and the tree is identical to before.
- *Why now:* rewriting is free before anything is pushed, and impossible to do cleanly afterwards.
- *Alternative considered:* keep the history. The commits would show an unlinked hostname email forever.

### The formula builds from source with SwiftPM, and the tap's CI publishes bottles
```ruby
class Dtidy < Formula
  desc "Sort loose Desktop items into folders, with undo"
  homepage "https://github.com/dtidy-app/dtidy-macos"
  url "https://github.com/dtidy-app/dtidy-macos/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "<from the release tarball>"
  license "GPL-3.0-or-later"
  head "https://github.com/dtidy-app/dtidy-macos.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "--configuration", "release"
    bin.install ".build/release/dtidy"
    generate_completions_from_executable(bin/"dtidy", "--generate-completion-script")
    man1.install "docs/man/dtidy.1"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/dtidy --version")
    ENV["XDG_DATA_HOME"] = testpath/"data"
    ENV["XDG_CONFIG_HOME"] = testpath/"config"
    (testpath/"root").mkpath
    touch testpath/"root/report.pdf"
    system "touch", "-t", "202001010000", testpath/"root/report.pdf"
    assert_match "PDFs/report.pdf", shell_output("#{bin}/dtidy plan --root #{testpath}/root")
    refute_path_exists testpath/"data/dtidy"
  end
end
```
- `--disable-sandbox` is needed because SwiftPM's own sandbox cannot nest inside Homebrew's.
- The test sets the file's modification time in the past, so the 10-second "too recent" rule does not skip it. It also checks that `plan` created no data directory. It works in `testpath`, so it never needs Desktop access.
- *Why `depends_on xcode`:* it is what Homebrew's Swift formulae use, and it states the Swift 6 requirement precisely. Users with bottles never need Xcode.
- *Alternative considered:* attach a prebuilt universal binary to each release and point the formula at it. That's faster for users without bottles, but it is an unsigned binary we would build and publish ourselves. Bottles give the same benefit through Homebrew's own pipeline.

### The release check is a Make target, and the release itself is manual
- `make release-check VERSION=X.Y.Z` fails unless all of these hold:
  - `.build/release/dtidy --version` equals `X.Y.Z`;
  - the working tree is clean;
  - `swift test` passes;
  - `make check-man` passes;
  - no `vX.Y.Z` tag exists yet.
- `docs/releasing.md` lists the steps:
  1. bump `DTidyVersion`;
  2. `make man`;
  3. commit;
  4. `make release-check`;
  5. `git tag -s`, or `-a` if no signing key is set up;
  6. push;
  7. create the GitHub Release;
  8. bump the formula (`brew bump-formula-pr --url … dtidy-app/tap/dtidy`, or the tap's autobump);
  9. label the pull request `pr-pull` to publish bottles.
- *Why manual:* releases are rare, and every step stays visible and reversible until the push.

### Community files
- **`CONTRIBUTING.md`** (about a page):
  - specs define behaviour, and changes go through `/opsx:propose`, then apply, then archive;
  - build and test with `swift test`, `make check-man` and `make man`;
  - contributions are licensed GPL-3.0-or-later;
  - a bug report includes `dtidy --version`, the macOS version and `dtidy doctor --json`.

  It links to `AGENTS.md`, `docs/` and `docs/releasing.md` rather than repeating them.
- **`SECURITY.md`:** report privately through GitHub's private vulnerability reporting on `dtidy-app/dtidy-macos`. The relevant risks are data loss or a file overwritten during sort or undo. It names the supported version (the latest release).
- No code of conduct or issue templates yet.

## Risks / Trade-offs

- **Organization lockout if `t-ilk` loses access.** → Two-factor authentication on the account is a prerequisite task. Adding a second owner is recommended in `CONTRIBUTING.md`'s maintainer notes, not required.
- **`test-bot` bottles only cover the macOS versions GitHub runners offer**, currently arm64 on recent macOS. → Those Macs get bottles, and the rest build from source with Xcode. This is documented in the README install section.
- **The release tarball's checksum changes if the tag is moved.** → Never move a published tag. The release check refuses an existing tag, and a wrong release is fixed with a new patch version.
- **SwiftPM fetches swift-argument-parser during the Homebrew build.** → `Package.resolved` pins the exact version, and Homebrew allows network access during source builds. A failing fetch shows up in the tap's CI before users hit it.
- **The organization name was unavailable.** → Resolved: `dtidy` was taken, and `dtidy-app` is used throughout. Moving to a different owner later would change the tap name in users' install commands, so `dtidy-app` should be treated as permanent.

## Migration Plan

The order matters, because each step depends on the previous one being public:
1. organization;
2. authorship rewrite;
3. push;
4. tag and Release;
5. tap and formula;
6. bottles;
7. docs that link to all of it.

Rollback before any tag: delete the repositories. After a tag: leave it, and fix forward with a new version.
