# Tasks

## 1. Project scaffolding

- [x] 1.1 Create `Package.swift` (swift-tools-version 6.x, platform macOS 14, Swift 6 language mode) with library targets `DSortCore` and `DSortIO`, executable target `dsort`, test targets `DSortCoreTests` and `DSortIOTests`, and a pinned `swift-argument-parser` dependency; verify `swift build` succeeds
- [x] 1.2 Add the `dsort` root command with empty subcommands `run` (default), `plan`, `undo`, `recover`, `history`, `show`, `doctor`, `config {init,path,validate}` and `--version`; verify `swift run dsort --help` lists every subcommand
- [x] 1.3 Add GPL-3.0 `LICENSE`, a `.gitignore` for `.build/` and `.swiftpm/`, and a README skeleton (purpose, build, license); verify `swift build -c release` produces a binary whose `otool -L` lists only system libraries
- [x] 1.4 Add a shared exit-code enum (0, 1, 64, 75, 77) used by all commands; verify `swift run dsort show` without arguments exits 64

## 2. Configuration (`sort-configuration` spec)

- [x] 2.1 Implement the Codable config model (version, root, minAgeSeconds, sortFolders, skipGlobs, neverMove, triage, categories, fallback) with documented per-field defaults and `Config.default` holding the built-in rules from design D7; verify unit tests decode `{"version": 1}` with empty rule lists and decode the encoded `Config.default` back to an equal value
- [x] 2.2 Implement validation (unknown version, unknown fields at any level, regexes that do not compile, undeclared type identifiers, absolute/empty/`.`/`..` destinations, missing root) with field-path error messages; verify one unit test per rejection rule from the spec
- [x] 2.3 Implement config path resolution (`--config`, `$XDG_CONFIG_HOME`, `~/.config`) and `~` expansion for `root`; verify unit tests with injected environment values
- [x] 2.4 Wire `dsort config path|init|validate` (init refuses to overwrite and exits 64; validate exits 64 on errors); verify with a temp `XDG_CONFIG_HOME` that `config init` followed by `config validate` exits 0 and a second `config init` exits 64 and leaves the file unchanged
- [x] 2.5 Document the config file format, defaults, and the "a file replaces the defaults" rule in the README; verify the README example passes `dsort config validate`

## 3. Classification (`item-classification` spec)

- [x] 3.1 Define the `Entry` model (name, dev, ino, birth, mtime, kind file/package/folder/symlink, isScreenCapture) and the `Decision` result (skip with reason, or bucket with rule name); verify it compiles under strict concurrency as `Sendable`
- [x] 3.2 Implement the pure classifier with the spec's rule order (hidden, skip globs, folder, symlink, too-recent, never-move, bucket names, screenshot metadata, triage regexes on NFC names, extension overrides, UTType categories, fallback); verify one unit test per spec scenario, including decomposed `é`, `.ts` override, `toolkit-0.12.0-beta` folder, and `Tool.app` package
- [x] 3.3 Verify the default screenshot pattern against real macOS names (`Screenshot 2026-10-14 at 16.48.54.png`, `Ekran Resmi …`, `Bildschirmfoto …`, `Capture d’écran …` with both apostrophes) and the camera patterns (`IMG_4821.HEIC`, `DSC_0001.JPG`, `DSCF1234.RAF`, `PXL_20260101_123456.jpg`) in unit tests

## 4. Planning and dry run (`sort-execution` spec)

- [x] 4.1 Implement the suffix namer (` (n)` and ` (restored n)` variants, compound extensions, packages, no-extension names, 255-byte grapheme-safe trimming); verify unit tests for `backup.tar.gz`, `Tool.app`, `README`, and a 250-byte name
- [x] 4.2 Implement the pure planner: decisions plus existing destination names (case-insensitive) produce a plan of mkdirs (only for buckets receiving items) and moves with pre-resolved suffixes; verify unit tests for the case-variant collision, two Desktop files planned into one name, and "no screenshots, no screenshot folder"
- [x] 4.3 Implement text and `--json` rendering of a plan (moves, mkdirs, skips with reasons; JSON on stdout, messages on stderr); verify a snapshot test of both renderings
- [x] 4.4 Document `dsort plan` / `run --dry-run` in the README; verify the documented command runs against a temp root

## 5. Scanner and Darwin shims

- [x] 5.1 Implement Darwin shims: `renamex_np` with `RENAME_EXCL`, `fsgetpath`, `chflags` add `UF_TRACKED`, a `getxattr` read of the screen-capture attribute with binary-plist decoding, a document-ID read via `documentIdentifierKey` with cache invalidation, `F_BARRIERFSYNC`, and volume capabilities via `getattrlist`; verify `DSortIOTests` in temp dirs (exclusive rename returns `EEXIST` on a case-variant name; a tracked file reports a non-zero document ID that survives `FileManager.replaceItemAt`)
- [x] 5.2 Implement the scanner for the top level of the root using `lstat` and the package resource key, never following symlinks; verify in a temp dir with a hidden file, a plain folder, a dotted folder name, a fake `.app` package, a symlink, and a file carrying a test-set screen-capture xattr
- [x] 5.3 Map `EPERM` on reading the root to exit 77 with a message naming `TERM_PROGRAM` or the binary path and the System Settings pane; verify with a test using an injected `FileOps` that throws `EPERM`

## 6. Ledger (`run-ledger` spec)

- [x] 6.1 Implement data-directory resolution (`$XDG_DATA_HOME/dsort`, otherwise `~/Library/Application Support/dsort`) and run-ID generation (`YYYYMMDDTHHMMSSZ-<random>`); verify unit tests for both env cases and uniqueness of 1,000 IDs generated in one second
- [x] 6.2 Implement the ledger record codec and append-only writer for the record types in design D4 (run, mkdir, move, sealed, tracked, retarget, done, fail, commit, plus undo/recover variants) with barrier flush on sealed, retarget, and commit; verify a round-trip unit test and that the writer opens files append-only
- [x] 6.3 Implement the ledger reader that tolerates a truncated last line and computes run state (committed, interrupted, reverted, partially reverted) across sort, undo, and recover ledgers; verify unit tests with a half-written final line and with an undo ledger referencing a sort run
- [x] 6.4 Implement `dsort history [--limit N] [--json]` and `dsort show RUN_ID [--json]` (unknown ID exits 64); verify against fixture ledgers in a temp data dir
- [x] 6.5 Document the ledger location, format, and `history`/`show` in the README; verify the documented paths match `dsort doctor` output

## 7. Executing a sort (`sort-execution` spec)

- [x] 7.1 Implement the run lock (`flock` with `LOCK_EX | LOCK_NB` on `<data>/lock`); verify a test where a second process gets exit 75 while the first holds the lock
- [x] 7.2 Implement the executor: write and seal the plan, create bucket folders, and for each move set `UF_TRACKED` if absent, record the document ID and `byUs`, rename with `RENAME_EXCL`, retarget with a flushed record on `EEXIST`, map `EXDEV` to `cross-volume`, then commit; verify `DSortIOTests` in a temp root for the normal path, an injected `EEXIST` race, injected `EXDEV`, and no tracked-flag changes on already-tracked files
- [x] 7.3 Refuse `run` while an interrupted run exists (exit 1, message names `dsort recover`); verify with a fixture interrupted ledger
- [x] 7.4 Wire `dsort run [--dry-run] [--json] [--config] [--root]` with exit codes 0/1/64/75/77; verify an end-to-end test against a temp root containing every item kind from 5.2 produces the expected bucket layout and exit 0
- [x] 7.5 Document `dsort run`, exit codes, the tracked-flag side effect, and Desktop/Full Disk Access permission setup (including the ad-hoc-signing re-grant caveat for `launchd`) in the README; verify the README states every exit code from the spec

## 8. Undo (`run-undo` spec)

- [x] 8.1 Implement the pure reconciler decision table from design D5 (identity matching by inode + birth or document ID, found / in-trash / already-restored / replaced / missing / inaccessible); verify one unit test per row, including "reused inode does not match" and "non-ENOENT error is inaccessible"
- [x] 8.2 Implement observation gathering: stat of the recorded destination, `fsgetpath` with errno capture, and the document-ID scan limited to the run's bucket folders; verify in temp dirs that a file renamed into a subfolder, a safe-saved file, and a renamed-then-safe-saved file are all found
- [x] 8.3 Implement the undo executor: restore with `RENAME_EXCL`, use ` (restored n)` on conflict or skip with `--on-conflict skip`, honor `--by-path` for `replaced`, remove the run's created folders deepest-first only if empty, leave `UF_TRACKED` set, and write an undo ledger; verify temp-dir tests for every `run-undo` spec scenario, including a parent folder chmod'ed to 000 giving `inaccessible` and a trashed file left in place
- [x] 8.4 Implement undo target selection (latest committed or recovered unreverted sort run, or an explicit `RUN_ID`, rejecting undo/recover runs) and retry of only unresolved entries on a partially reverted run; verify with a sort, a partial undo, a fix, and a second undo reaching fully reverted
- [x] 8.5 Wire `dsort undo [RUN_ID] [--dry-run] [--json] [--on-conflict suffix|skip] [--by-path]` with the outcome counts and exit 0/1 rule; verify that the dry run leaves the filesystem and ledgers byte-identical
- [x] 8.6 Document undo outcomes and options in the README; verify each outcome name in the README matches the JSON output

## 9. Recovery (`run-ledger` spec)

- [x] 9.1 Implement `dsort recover`, which reconciles each planned move of an interrupted run as moved or not moved by identity and writes a recover ledger; verify a test that kills the executor (injected fault) after 12 of 30 moves, then recover reports 12 moved and 18 not moved and `undo` restores exactly those 12
- [x] 9.2 Document crash recovery in the README; verify the documented sequence (interrupted, recover, undo) works against a temp root

## 10. Diagnostics

- [x] 10.1 Implement `dsort doctor` (root readable, `RENAME_EXCL` and path-from-ID support, lock state, config and data paths, config validity), read-only, exit 0 when everything passes; verify on a temp root and that a missing root fails the root check with a nonzero exit
- [x] 10.2 Add a `launchd` agent example (`StartInterval`) and its permission notes to the README; verify the plist passes `plutil -lint`

## 11. Integration checks

- [x] 11.1 Run the full sort, history, undo cycle against a temp root of 300 mixed items and verify the restored tree is identical to the original (names, inodes or document IDs, contents)
- [x] 11.2 Measure `dsort plan` and `dsort run` on that 300-item root with a release build and verify each completes in under 100 ms on this machine
- [x] 11.3 Manually sort and undo a few scratch files on the real Desktop and verify that Finder updates icons without interaction, including with "Use Stacks" on; record the result in the README's tested-platforms note
