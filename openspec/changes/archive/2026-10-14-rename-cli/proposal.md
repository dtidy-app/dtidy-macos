# Proposal

## Why

The name `dsort` is already taken by a command that macOS users can have installed. GNU dateutils ships `dsort(1)`, which sorts lines by date, and Homebrew's `dateutils` formula installs it as `/opt/homebrew/bin/dsort`. Two `dsort` binaries would conflict in `PATH`, over the zsh `_dsort` completion file, and in Homebrew, which would also block a future homebrew-core formula. Nothing has been released and the repository has no remote yet, so renaming now costs only a mechanical edit. After a release it would also mean migrating users and breaking scripts.

The new name is `dtidy`, short for "desktop tidy". No Homebrew formula or cask uses it, and a GitHub repository search finds no repositories with that name.

## What Changes

- **BREAKING** The command is renamed from `dsort` to `dtidy`: the binary, the SwiftPM product and executable target, the `commandName`, and every user-facing message that names a command (for example "Run `dtidy recover`").
- **BREAKING** The per-user locations move with the name:
  - config: `$XDG_CONFIG_HOME/dtidy/config.json`, else `~/.config/dtidy/config.json`
  - data: `$XDG_DATA_HOME/dtidy`, else `~/Library/Application Support/dtidy`
  - The history directory and lock follow the data directory.

  Existing `dsort` locations are neither read nor migrated, because no release has shipped.
- Internal names follow the new name so no stale name remains in the code: the modules `DSortCore` and `DSortIO`, the test targets, and the types `DSortError`, `DSortExit` and `DSortVersion`.
- The example launchd agent becomes `examples/local.dtidy.plist` with the label `local.dtidy`.
- The specs, `docs/`, `README.md` and `AGENTS.md` use the new name. Archived OpenSpec changes stay as they are, as the historical record.
- Out of scope: behaviour, exit codes, the ledger record format and its contents, the version number, the local checkout folder name, and the future GitHub repository name.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

Every requirement that names the command or its directories is restated with the new name. The behaviour of each requirement is unchanged.

- `platform-macos`: default locations become `~/Library/Application Support/dtidy` and `~/.config/dtidy/config.json`; the other requirements change only the command name.
- `sort-configuration`: the config resolution order uses `$XDG_CONFIG_HOME/dtidy/config.json`; the `config` commands become `dtidy config …`.
- `run-ledger`: the data directory is `$XDG_DATA_HOME/dtidy`; the `history`, `show` and `recover` commands are renamed.
- `run-undo`: `dtidy undo` and its messages.
- `sort-execution`: `dtidy plan`, `run`, `doctor` and the lock-contention wording.
- `item-classification`: no change, because it never names the command.

## Impact

- **Code:**
  - `Package.swift`
  - `Sources/dsort` (renamed to `Sources/dtidy`), `Sources/DSortCore`, `Sources/DSortIO`
  - `Tests/DSortCoreTests`, `Tests/DSortIOTests`
  - the message strings in about 10 files
  - the path tests in `ConfigTests` and `LedgerTests`
- **Docs:** `README.md`, `AGENTS.md`, `docs/architecture.md`, `docs/ledger-format.md`, `docs/platform-macos.md`, `docs/porting.md`, `examples/`.
- **Users:** none outside the author's machine. A local scratch history under `~/Library/Application Support/dsort` stops appearing in `history`. The design explains how to move it by hand.
- **Follow-on changes:** `add-shell-completion-and-help` and `add-homebrew-distribution` build on the new name.
