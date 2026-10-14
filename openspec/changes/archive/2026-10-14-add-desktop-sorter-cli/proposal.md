# Proposal

## Why

Loose files pile up on `~/Desktop` (screenshots, downloads, camera imports, PDFs), and existing organizers either depend on GUI apps, shell scripts, or AppleScript, or move files without a reliable way to put them back. We want a fast, headless, dependency-free macOS CLI that sorts the Desktop into category folders and can always reverse a run, so users can run it from a terminal or `launchd` without fear of losing or misplacing files.

## What Changes

- New Swift Package Manager project producing a single native executable, `dsort` (working name), for macOS 14+, published under GPL-3.0.
- Scan only the top level of `~/Desktop`; skip hidden files, in-progress downloads, plain folders, symlinks, very recent files, user "never move" patterns, and dsort's own bucket folders.
- Classify items into buckets created inside `~/Desktop`: screenshots (by the system screen-capture metadata, falling back to localized file names), camera imports, then user extension overrides, then system type (UTType) conformance, then a fallback bucket.
- Plan before acting: `dsort plan` / `--dry-run` prints the exact moves (text or JSON) without touching the filesystem.
- Move items with exclusive, atomic renames only; never overwrite, delete, or copy. Name collisions get Finder-style ` (n)` suffixes. Cross-volume destinations are refused.
- Mark every moved file as kernel-tracked so its document identity survives later app "safe saves".
- Record every run in an append-only ledger under `~/Library/Application Support/dsort/` (or `$XDG_DATA_HOME/dsort/`), durable before any move happens.
- `dsort undo` restores the most recent unreverted run (or a named run), locating files that were since moved, renamed, or re-saved, and never overwriting what now occupies the original name. `dsort recover` finishes or reconciles an interrupted run.
- `dsort history` / `dsort show` inspect past runs; `dsort doctor` checks Desktop access permissions, volume capabilities, lock state, and config.
- Optional JSON configuration (`~/.config/dsort/config.json` or `$XDG_CONFIG_HOME`), with `dsort config init|path|validate`.
- No AppleScript or Apple Events: verified that Finder updates the Desktop on its own after renames.

## Capabilities

### New Capabilities
- `item-classification`: Which Desktop items are eligible for sorting and which bucket each one belongs in (skip rules, screenshot/camera triage, extension and type categories, fallback).
- `sort-execution`: Planning, dry-run output, collision-safe atomic moves, file tracking, run locking, permission handling, and the `run`/`plan`/`doctor` commands and exit codes.
- `run-ledger`: The durable per-run record of intended and completed moves, its location and crash-safety guarantees, and the `history`/`show`/`recover` commands.
- `run-undo`: Reversing a recorded run: locating each moved file, restoring it without overwriting anything, reporting files that are gone, trashed, or inaccessible, and removing emptied bucket folders.
- `sort-configuration`: The user configuration file, its defaults, validation rules, and the `config` commands.

### Modified Capabilities

None. This is the first change in the project.

## Impact

- New code: Swift package with a core library, a filesystem layer, and the `dsort` executable target; unit and integration test targets.
- New build-time dependency: `swift-argument-parser` (Apache-2.0, GPL-3.0 compatible), statically linked; no runtime dependencies beyond macOS system frameworks.
- Files written on the user's machine: bucket folders inside `~/Desktop`, ledger files and a lock file in the data directory, and an optional config file. Moved files gain the `UF_TRACKED` flag.
- Permissions: needs macOS Desktop folder access (TCC) for the terminal app or, under `launchd`, for the binary itself. No Automation (Apple Events) permission is needed.
- Repository: GPL-3.0 `LICENSE`, README with install, permission, and `launchd` guidance.
