# Design

## Context

The name appears in four places, and each needs different care:

1. **User-visible command name.** This covers `commandName` in `Sources/dsort/DSort.swift`, and the message strings that tell the user which command to run next. Those strings are in `Executor`, `Doctor`, `RecoverService`, `UndoService`, `RunLock`, `Scanner`, `RunReport`, `Reconciler`, `HistoryCommands` and `RunCommand`. Several tests assert on that text (`"dsort recover"`, `"the dsort binary at "`).
2. **On-disk locations.** `Paths.configFile` and `Paths.dataDirectory` in `Sources/DSortCore/Paths.swift` hard-code the `dsort` folder name. The history directory and `RunLock.lockPath` derive from the data directory. `ConfigTests` and `LedgerTests` assert the literal paths.
3. **Build identity.** The SwiftPM product and targets in `Package.swift`, plus the source and test directory names.
4. **Internal symbols.** `DSortError` (about 40 uses), `DSortExit`, `DSortVersion`, the module names `DSortCore` and `DSortIO` (in every `import`), and the `dsort-test-` temp prefix.

The ledger format does not contain the tool name. Its `tool` field holds `DSortVersion.current`, which is the string `"0.1.0"`. Ledgers written before the rename therefore stay valid byte for byte.

## Goals / Non-Goals

**Goals:**
- After the change, a case-sensitive search for `dsort`, `Dsort` and `DSort` over `Sources`, `Tests`, `Package.swift`, `docs`, `examples`, `README.md`, `AGENTS.md` and `openspec/specs` finds nothing.
- `swift build` and `swift test` pass, and `.build/debug/dtidy --help` shows `dtidy`.

**Non-Goals:**
- Reading, migrating or warning about the old `dsort` locations.
- Renaming the checkout folder (`dsort/dsort-mac`) or choosing the GitHub repository name. Those belong to `add-homebrew-distribution`.
- Editing archived changes under `openspec/changes/archive/`.

## Decisions

### Rename the internal modules and types too
`DSortCore` becomes `DTidyCore`, `DSortIO` becomes `DTidyIO`, the test targets become `DTidyCoreTests` and `DTidyIOTests`, and the types become `DTidyError`, `DTidyExit` and `DTidyVersion`.

- *Why:* nothing outside this repository depends on these names yet, so renaming is free now and only gets more expensive later. A half-renamed codebase would also leave `grep dsort` noisy forever and confuse porters reading `docs/porting.md`.
- *Spelling:* `DTidy` with two capitals, matching the existing `DSort` pattern.
- *Alternative considered:* rename only what users see and keep `DSort*` internally. That gives a smaller diff but permanent inconsistency.

### Rename with `git mv`, then substitute text in two passes
- Directories move with `git mv` so history follows the files.
- Pass one replaces `DSort` with `DTidy`, which covers identifiers and module names.
- Pass two replaces `dsort` with `dtidy` in lowercase, which covers the command, paths, messages, plist and docs.
- *Why:* every case-sensitive occurrence of `dsort`, `DSort` or `Dsort` refers to this tool.
- A case-insensitive search also matches `interruptedSortRuns` ("interrupte**dSort**Runs"). That identifier is unrelated to the tool name and stays as it is, so every check in this change searches case-sensitively.
- *Alternative considered:* hand-edit each file. That's slower and easier to get wrong over more than 60 files.

### Do not migrate the old locations
- *Why:* no release has shipped. The only existing data is the author's scratch history: one ledger in `~/Library/Application Support/dsort/history`.
- Adding a fallback or migration would put permanent code and spec text in place to serve one machine.
- If that history should carry over, it can be moved once by hand while no dsort process is running:
  `mv ~/Library/Application\ Support/dsort ~/Library/Application\ Support/dtidy`
  The ledger contents need no change.

### Spec deltas restate every requirement that names the tool
- The deltas restate 30 requirements in full under `MODIFIED`, identical apart from the name, so that the archived main specs carry no stale command names.
- Two `## Purpose` paragraphs, in `platform-macos` and `sort-configuration`, also name the tool. Deltas cannot change a Purpose, so those two are edited directly in the main specs as an apply task.

### launchd example
- The example becomes `examples/local.dtidy.plist`, with label `local.dtidy`, program `/usr/local/bin/dtidy` and log `/tmp/dtidy.log`.
- Anyone who loaded the old agent must `launchctl bootout` it first. The README section that explains loading it says so in one line.

## Risks / Trade-offs

- **The blanket substitution changes text it shouldn't.** → After both passes, review `git diff --stat` and spot-check the diff. `swift test` catches broken identifiers and changed message assertions. The goal's `grep` check catches anything missed.
- **The old launchd agent keeps running `/usr/local/bin/dsort` after the rename.** → Mentioned in the README note above; it affects only the author's machine.
- **SwiftPM keeps stale build products under the old target names.** → Run `swift package clean` (or delete `.build`) before the verification build.
- **`dtidy` is taken by someone later.** → The name was checked against Homebrew formulas and casks and GitHub repositories on 2026-10-14. A trademark search is the user's call and is outside this change.

## Migration Plan

1. Apply the rename in a single commit, so that one revert restores everything.
2. Optionally move the scratch history by hand, using the command above.
3. Rollback: `git revert` the commit. Any data written under `dtidy/` would need moving back the same way.
