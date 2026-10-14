# Tasks

## 1. Undo eligibility and run-ID candidates (Core)

- [x] 1.1 Add `SortRun.isUndoable` (`isFinished && state != .reverted && !movedSeqs.isEmpty`) and switch `UndoService`'s default-target search to it. Verify that the existing `UndoTests` all pass unchanged.
- [x] 1.2 Add `History.undoableRunIds` and `History.allRunIds`, both newest first. Add `DTidyCoreTests` cases for the spec scenarios:
  - reverted, committed and interrupted sort runs plus an undo run → only the committed run;
  - a recovered run is included;
  - a partially reverted run is included;
  - a committed run with zero moved files is excluded;
  - `allRunIds` lists sort, undo and recover runs newest first.

  Verify with `swift test --filter DTidyCoreTests`.

## 2. Completion wiring (CLI)

- [x] 2.1 Add `completion: .custom` to `UndoCommand.runId` and `ShowCommand.runId`. Each closure calls `LedgerStore(environment: .current).load()`, takes the matching helper's IDs, and filters them by `prefix`. Add no lock, config or root access. Verify against a scratch history (`XDG_DATA_HOME` set) by running the exact `---completion` command line that the regenerated zsh script builds for `undo` and `show`: it prints only undoable IDs for `undo` and every ID for `show`.
- [x] 2.2 Set `completion: .directory` on `--root` and `.file(extensions: ["json"])` on `--config` in `Options.swift`. Verify in the regenerated zsh script that `--root` uses directory-only file completion and `--config` uses a `json` extension filter.
- [x] 2.3 Add a `DTidyIOTests` case for a history directory holding one readable, one unreadable (mode 000) and one corrupt ledger: the readable run IDs come back, nothing throws, and a missing data directory yields `[]` and is not created. Add a timing check over 1,000 synthetic ledgers that records the load time and fails above 100 ms in a release build (`swift test -c release`). Debug builds use a 1 s guard. *Note:* release measured about 61 ms (41 ms read, 20 ms run-state derivation), debug about 375 ms. `History.sortRun` scans every ledger for each run, which is quadratic; it's fast enough for now and left for a later change. Verify with `swift test --filter DTidyIOTests`.
- [x] 2.4 Manually check with a lock held: start a `dtidy run` against a large scratch root, request run-ID completions from a second shell, and confirm they return immediately. Record the result in the task note. *Result (2026-10-14):* the lock was held with `flock` on `<data>/lock` from a separate process instead of a long run, which is the same kernel lock. `dtidy run` exited 75, and `undo` completion returned its candidate in under 10 ms.

## 3. Help text

- [x] 3.1 Write the top-level `DTidy` discussion:
  - what dtidy does;
  - an `EXIT STATUS:` list of 0, 1, 64, 75 and 77 with their meanings (from the sort-execution spec);
  - `FILES:` for `~/.config/dtidy/config.json` and `~/Library/Application Support/dtidy`, with their XDG overrides;
  - a pointer to `dtidy doctor`;
  - an `EXAMPLES:` block.

  Verify with `.build/debug/dtidy --help`.
- [x] 3.2 Add a `discussion` that ends with an `EXAMPLES:` block to `run`, `plan`, `undo` (extending its existing text with examples for the latest run, a specific RUN_ID and `--dry-run`), `recover`, `history`, `show`, `doctor`, `config`, `config init`, `config path` and `config validate`. Base each discussion on the matching spec. Verify that `dtidy help <command>` shows each one.
- [x] 3.3 Add the `DTidyCLITests` test target to `Package.swift` (depending on `dtidy`), with tests that:
  - walk all subcommands and require an abstract, a discussion and `EXAMPLES:`, naming any command that lacks them;
  - check that the top-level help contains the five exit codes and both locations;
  - check that the zsh, bash and fish completion scripts each mention every subcommand and `---completion`.

  Verify with `swift test --filter DTidyCLITests`, then remove one command's discussion locally and confirm the test fails and names that command.

## 4. Man page and installation

- [x] 4.1 Add a `Makefile` with the targets `build`, `man` (runs `swift package generate-manual` and copies `dtidy.1` to `docs/man/`), `check-man` (regenerates into a temporary directory and diffs, ignoring `.Dd`), `completions`, `install` and `uninstall`, with `PREFIX ?= /usr/local` and `DESTDIR` support. Verify with `make install PREFIX=<scratch>`:
  - it installs exactly `bin/dtidy`, `share/man/man1/dtidy.1`, `share/zsh/site-functions/_dtidy`, `share/bash-completion/completions/dtidy` and `share/fish/vendor_completions.d/dtidy.fish`;
  - `make uninstall PREFIX=<scratch>` removes all five.
- [x] 4.2 Run `make man` and commit `docs/man/dtidy.1`. Verify that `man ./docs/man/dtidy.1` shows the overview with exit codes and a section for every command, including `config init`, `config path` and `config validate`. Then verify that `make check-man` passes, and that it fails after a local edit to any command's help.
- [x] 4.3 Check completion in each shell after `make install PREFIX=<scratch>`, with each shell pointed at that prefix and `XDG_DATA_HOME` pointing at a scratch history:
  - in zsh, `dtidy <Tab>`, `dtidy config <Tab>`, `dtidy undo --on-conflict <Tab>` and `dtidy undo <Tab>`;
  - in bash 5 with `bash-completion@2`, the same;
  - in fish, if it is installed.

  Note any shell that wasn't available in the task note.

  *Result (2026-10-14):* tested after `make install` into a scratch PREFIX, against a scratch history with one committed sort run, one reverted sort run and its undo run.
  - zsh 5.9: driven interactively through `zpty` with `compinit`. Subcommands, `config` subcommands, `suffix`/`skip`, only the committed run for `undo`, all three runs for `show`, and directories for `--root` were all offered.
  - bash 5.3 (Homebrew): identical results, calling the registered `_dtidy` function directly. `bash-completion@2` isn't installed here, so autoloading wasn't exercised. The macOS bash 3.2 also works when the script is sourced.
  - fish: not installed on this machine, so not tested. The fish script's content is covered by `CompletionScriptTests`.

## 5. Documentation

- [x] 5.1 Update `README.md`:
  - `make install` (with `sudo` for `/usr/local`) and `make uninstall`;
  - per-shell completion setup: `compinit` in `~/.zshrc`; `brew install bash-completion@2` and its profile line; fish needs nothing;
  - manual setup for users who copy only the binary (`dtidy --generate-completion-script zsh > ~/.zsh/completions/_dtidy` plus `fpath`);
  - `man dtidy`.

  Verify that every command in the new sections runs as written against a scratch `PREFIX`. *Result (2026-10-14):* the commands ran against a scratch `PREFIX` and `HOME`: `make`, `make install`, the binary-only zsh setup with `compinit`, sourcing the bash script, `man -w dtidy`, the three help commands, and `make uninstall`. Not run: `sudo make install` to `/usr/local` (the same targets were run without root) and the `bash-completion@2` profile line (that package isn't installed).
- [x] 5.2 Update `AGENTS.md` (add `make man` / `make check-man` to Build and test, and a rule that help-text changes regenerate the man page in the same change) and `docs/architecture.md` (the completion callback path, and the rule that completion and help never take the lock or read config or root). Verify that `grep -n "check-man" AGENTS.md` matches and that `swift test` passes.

## 6. Integration check

- [x] 6.1 Run `swift package clean && swift build && swift test && make check-man && openspec validate add-shell-completion-and-help --strict`. Verify that all of them pass.

## Workflow follow-up

- Archive with `/opsx:archive` after review.
- Next change: `add-homebrew-distribution`. Its formula uses `generate_completions_from_executable(bin/"dtidy", "--generate-completion-script")` and `man1.install "docs/man/dtidy.1"`.
