# Design

## Context

The CLI is built on swift-argument-parser 1.8.2 (`Sources/dtidy`), and that already provides most of the mechanics:

- **Completion scripts.** `--generate-completion-script zsh|bash|fish` prints a script. An unknown shell exits 64 with nothing on stdout, which was checked against the current build. The scripts already complete subcommands and option names. `ConflictPolicy` is `CaseIterable`, so `--on-conflict` values complete without further work.
- **Callbacks.** An argument declared with `completion: .custom { words, index, prefix in … }` makes the script call back into the binary through a hidden `---completion` entry point (`__dtidy_custom_complete` in the zsh script). The binary prints the candidates and exits. No subcommand's `run()` or `validate()` executes.
- **Help.** `abstract` and `discussion` from each `CommandConfiguration` and the `help:` of each property feed both `--help` and the man page. Today only `undo` has a discussion.
- **Man page.** The `generate-manual` command plugin ships in the same package. `swift package generate-manual` builds dtidy in release mode and writes `.build/plugins/GenerateManual/outputs/dtidy/dtidy.1`, a single page with every subcommand's discussion. Its `.Dd` line carries the generation date, and its `EXIT STATUS` section is the generic mdoc `.Ex -std` line.
- **History.** `LedgerStore.load()` never throws. It skips unreadable files and returns an empty history when the directory is missing. `UndoService` picks the default target with `sortRuns.first { $0.isFinished && $0.state != .reverted && !$0.movedSeqs.isEmpty }`.
- **zsh.** macOS's `/bin/zsh` already has `/usr/local/share/zsh/site-functions` in its default `fpath`.

## Goals / Non-Goals

**Goals:**
- Run-ID completion that agrees with what `undo` and `show` accept.
- Help text written once and used for `--help`, `help`, and the man page.
- Tests that fail when a new command lacks help, or when completion or help regress.

**Non-Goals:**
- Descriptions next to completion candidates. argument-parser's custom completion returns plain strings.
- Generating the man page during `swift build`, or as part of the Homebrew build.
- A `dtidy completion <shell>` subcommand. The built-in flag already exists, and Homebrew's `generate_completions_from_executable(bin/"dtidy", "--generate-completion-script")` calls exactly that.

## Decisions

### One undo-eligibility rule, in Core
- Add `SortRun.isUndoable`, defined as `isFinished && state != .reverted && !movedSeqs.isEmpty`.
- Add two `History` helpers:
  - `undoableRunIds` (newest first)
  - `allRunIds` (newest first, every kind)
- `UndoService`'s default-target search switches to `isUndoable`.
- *Why:* the spec defines completion candidates as the runs undo could choose. Sharing the predicate means the two cannot drift, and the Core helpers are unit-testable without a disk.
- *Alternative considered:* re-derive the rule in the CLI closure. That duplicates the rule and leaves it untested.

### Completion closures stay thin and silent
- The closures in `UndoCommand` and `ShowCommand` call `LedgerStore(environment: .current).load()` and return the matching helper's IDs, filtered by `prefix`.
- They do not touch `RunLock`, `ConfigLoader`, the `Scanner`, or `Paths` creation helpers. `load()` already swallows errors, so the closure needs no `try`.
- *Why:* this covers the spec's no-side-effects and no-error requirement by construction. Filtering by prefix is cheap and keeps the output short for bash, which otherwise filters after the fact.

### Path completion via built-in kinds
- `--root` uses `.directory`. `--config` uses `.file(extensions: ["json"])`, and the generated scripts also allow directories so the user can navigate into them.
- No custom code is needed.

### Examples live inside `discussion`
- argument-parser has no separate examples field. Each `discussion` ends with an `EXAMPLES:` block of `  dtidy … ` lines, each followed by an indented explanation.
- The top-level `DTidy` discussion carries the exit-code table and the config and data locations, plus a pointer to `dtidy doctor`.
- *Why:* the same text then appears in `--help` and in the man page DESCRIPTION. The generic `EXIT STATUS` line the plugin emits stays; the specific codes are in DESCRIPTION.
- *Alternative considered:* post-process the man page to rewrite `EXIT STATUS`. That adds fragile text surgery for little gain.

### A CLI test target
- Add `Tests/DTidyCLITests`, depending on the `dtidy` executable target via `@testable import dtidy`. A throwaway package confirmed under Swift 6 that this works with an `@main` type.
- The tests:
  - walk `DTidy.configuration.subcommands` recursively and assert that each command has a non-empty `abstract`, a `discussion` and an `EXAMPLES:` block, naming any command that lacks one;
  - assert the top-level help (`DTidy.helpMessage()`) lists 0, 1, 64, 75 and 77 and both locations;
  - assert `DTidy.completionScript(for:)` for zsh, bash and fish mentions every subcommand and `---completion`.
- The run-ID logic is covered in `DTidyCoreTests`. One `DTidyIOTests` case loads a temp history with an unreadable and a corrupt ledger and checks that the readable IDs still come back.
- *Alternative considered:* spawn the built binary from tests. That's slower, and it depends on build-product paths.

### Committed man page, plus a staleness check
- `docs/man/dtidy.1` is committed. `make man` runs `swift package generate-manual` and copies the result there.
- `make check-man` regenerates it into a temporary directory and diffs it against the committed file, ignoring the `.Dd` date line.
- `AGENTS.md` gains a rule: changing help text means running `make man` in the same change.
- *Why:* the Homebrew formula and `make install` can install the page without running a SwiftPM plugin, which needs extra permissions and a second release build inside Homebrew's sandbox. The check keeps the committed page honest.
- *Alternative considered:* generate it at install time. That's simpler to keep fresh but makes every install slower and more fragile.

### Makefile for manual installs
- Targets: `build`, `install`, `uninstall`, `man`, `check-man`, `completions`. `PREFIX ?= /usr/local` and `DESTDIR` are supported.
- `install` copies:
  - `.build/release/dtidy` → `$(PREFIX)/bin/`
  - `docs/man/dtidy.1` → `$(PREFIX)/share/man/man1/`
  - the scripts generated by the just-built binary → `$(PREFIX)/share/zsh/site-functions/_dtidy`, `$(PREFIX)/share/bash-completion/completions/dtidy` and `$(PREFIX)/share/fish/vendor_completions.d/dtidy.fish`
- *Why:* with `PREFIX=/usr/local`, zsh finds `_dtidy` without any setup, and these are the same directories Homebrew uses under its own prefix. The README covers the shell-side prerequisites: `compinit` in `~/.zshrc`, `bash-completion@2` for bash, and nothing extra for fish.

## Risks / Trade-offs

- **The callback runs whichever `dtidy` is first in `PATH`, which may not be the one that generated the script.** → Acceptable; completion candidates come from history, which is shared. `make install` regenerates the scripts from the binary it installs.
- **Run-ID completion becomes slow with a very large history, because every ledger is parsed on each Tab.** → `load()` reads only the history directory. Measure with 1,000 synthetic ledgers in the IO test, and fall back to reading only ledger headers if a Tab takes more than about 100 ms.
- **The man page drifts from the help.** → `make check-man` plus the AGENTS.md rule. The Homebrew change can run `make check-man` before tagging.
- **`@testable import` of an executable target could stop working in a future toolchain.** → If it does, move the command types into a `DTidyCLI` library target and keep `Sources/dtidy` as a thin `main`. That's a mechanical change limited to the CLI layer.
- **`sudo make install` writes under `/usr/local` as root.** → `install` writes only the five listed files, and `uninstall` removes exactly those.

## Migration Plan

This change is additive. Users who installed by hand rerun `make install` to get the completions and the man page. Rollback is a revert.
