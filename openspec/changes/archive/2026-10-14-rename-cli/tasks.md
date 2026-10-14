# Tasks

## 1. Build identity

- [x] 1.1 Rename the source and test directories with `git mv`: `Sources/dsort` → `Sources/dtidy`, `Sources/DSortCore` → `Sources/DTidyCore`, `Sources/DSortIO` → `Sources/DTidyIO`, `Tests/DSortCoreTests` → `Tests/DTidyCoreTests`, `Tests/DSortIOTests` → `Tests/DTidyIOTests`. Verify that `git status` shows them as renames.
- [x] 1.2 Update `Package.swift` (package name, product, executable target and dependencies, test targets, header comment) to the `dtidy`/`DTidy*` names. Verify with `swift package describe` that it lists product `dtidy` and targets `DTidyCore`, `DTidyIO`, `dtidy`, `DTidyCoreTests` and `DTidyIOTests`.

## 2. Code and tests

- [x] 2.1 In `Sources/` and `Tests/`, replace `DSort` with `DTidy` (modules, `DTidyError`, `DTidyExit`, `DTidyVersion`, the `@main` struct). Rename the file `DSort.swift` to `DTidy.swift`. Verify that `grep -rn DSort Sources Tests` is empty.
- [x] 2.2 In `Sources/` and `Tests/`, replace lowercase `dsort` with `dtidy`: `commandName`, the paths in `Paths.swift` and their doc comments, the `--config` help text, every "Run `dtidy …`" message, the `Scanner` binary fallback and the `dtidy-test-` temp prefix. Verify that `grep -rn -e dsort -e Dsort Sources Tests` is empty.
- [x] 2.3 Leave `interruptedSortRuns` unchanged: it matches a case-insensitive `dsort` search but is not the tool name. Verify that `grep -rn interruptedSortRuns Sources Tests` still finds its 8 uses and that `grep -rn 'interruptesortRuns\|dTidyRuns' Sources Tests` is empty.
- [x] 2.4 Run `swift package clean && swift build && swift test`. Verify that the build and every test pass, including the path assertions in `ConfigTests` and `LedgerTests` and the message assertions (`dtidy recover`, `the dtidy binary at`).
- [x] 2.5 Smoke-test against a scratch folder, with `XDG_DATA_HOME` and `XDG_CONFIG_HOME` set to scratch directories. Verify that `.build/debug/dtidy --help` shows `dtidy` and that `dtidy config path` reports `<XDG_CONFIG_HOME>/dtidy/config.json`. Then run `dtidy run --root <scratch>` and verify that it writes its ledger under `<XDG_DATA_HOME>/dtidy/history/` and that `dtidy undo` reverses it.

## 3. Specs, docs and examples

- [x] 3.1 Edit the `## Purpose` paragraphs of `openspec/specs/platform-macos/spec.md` and `openspec/specs/sort-configuration/spec.md` directly, replacing `dsort` with `dtidy`. Deltas cannot change a Purpose, so this edit is needed. Verify that `grep -n -e dsort -e Dsort` on those two Purpose sections is empty.
- [x] 3.2 `git mv examples/local.dsort.plist examples/local.dtidy.plist`, then set the label to `local.dtidy`, the program to `/usr/local/bin/dtidy` and the logs to `/tmp/dtidy.log`. Verify with `plutil -lint examples/local.dtidy.plist`.
- [x] 3.3 Update `README.md` throughout: the title, the commands, the paths, and the launchd section with the new plist name. Add one line telling anyone who loaded the old agent to `launchctl bootout gui/$(id -u)/local.dsort` first. Verify that `grep -n -e dsort -e Dsort -e DSort README.md` returns only that bootout line.
- [x] 3.4 Update `AGENTS.md` and `docs/architecture.md`, `docs/ledger-format.md`, `docs/platform-macos.md` and `docs/porting.md`: the tool name, the paths and the module names in the code layout tables. Verify that `grep -rn -e dsort -e Dsort -e DSort AGENTS.md docs` is empty and that `swift test` still passes `LedgerDocTests`.
- [x] 3.5 Run `openspec validate rename-cli --strict`. Verify that it passes.

## 4. Integration check

- [x] 4.1 Run `grep -rn -e dsort -e Dsort -e DSort Sources Tests Package.swift docs examples AGENTS.md`. Verify that it is empty and that the README contains only the intended bootout line. The main specs are checked after archive; see the follow-up below.

## Workflow follow-up

- Optionally, while no dsort process is running, move the scratch history: `mv ~/Library/Application\ Support/dsort ~/Library/Application\ Support/dtidy`.
- Archive the change with `/opsx:archive`. Then verify that `grep -rn -e dsort -e Dsort -e DSort openspec/specs` is empty.
- Next changes: `add-shell-completion-and-help`, then `add-homebrew-distribution`.
