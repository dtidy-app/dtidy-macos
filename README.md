# dsort

`dsort` is a small command-line tool for macOS that tidies the top level of your Desktop into category folders, and can put everything back with `dsort undo`.

- **Native and fast.** A single Swift binary, no runtime dependencies, no shell scripts, no AppleScript.
- **Non-destructive.** Files are only ever renamed with an exclusive, atomic rename. dsort never overwrites, deletes, or copies your files.
- **Reversible.** Every run is recorded in a ledger before anything moves, and `dsort undo` finds files even after you moved, renamed, or edited them.

Requires macOS 14 (Sonoma) or later.

## Build and install

```sh
swift build -c release
cp .build/release/dsort /usr/local/bin/   # or anywhere on your PATH
```

Run the tests with `swift test`.

## Sort the Desktop

```sh
dsort            # same as `dsort run`
dsort run --json
dsort run --root ~/Downloads
```

dsort looks only at the top level of the root folder and moves each eligible item into a bucket folder inside it, such as `Images/`, `Images/_Screenshots/`, `PDFs/`, `Documents/`, `Code/`, `Archives/`, or `Other/`. Folders are created only when something goes into them.

What dsort guarantees:

- **Nothing is overwritten.** Every move is an atomic rename that fails if the target name exists, including names that differ only by case. A taken name gets a Finder-style suffix: `invoice (1).pdf`, `backup (1).tar.gz`.
- **Nothing is deleted or copied.** A bucket on a different volume is refused (`cross-volume`) instead of copying.
- **Nothing runs twice at once.** A lock in the data directory makes a second dsort process exit with code 75.
- **After a crash, sorting waits.** If a run was interrupted, `dsort run` refuses to start until you run `dsort recover`.

**Side effect: the tracked flag.** Before moving a file, dsort sets the file's `UF_TRACKED` flag (the same flag Preview and TextEdit set). The kernel then gives the file a document ID that survives "safe saves" by apps, so `dsort undo` can find the file even after you edit it. Undo leaves the flag in place. The ledger records which files dsort flagged.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Every planned action succeeded. |
| 1 | Some items failed or were left unresolved, or an interrupted run needs `dsort recover`. |
| 64 | Usage or configuration error. |
| 75 | Another dsort process holds the lock. |
| 77 | macOS denied access to the folder (see below). |

### Permissions

The Desktop is protected by macOS privacy controls. On the first run, macOS asks whether your terminal app may access the Desktop folder. If access is denied, dsort exits with code 77 and says which app needs permission. Grant it in **System Settings > Privacy & Security > Files and Folders** (Desktop Folder) or **Full Disk Access**:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
```

Under `launchd` there is no terminal, so macOS checks the `dsort` binary itself. Add the binary to Full Disk Access. A locally built binary is ad-hoc signed, and macOS ties the grant to that exact build: **after every rebuild you must grant access again**, or sign the binary with a stable identity.

dsort never uses AppleScript or Apple Events, so it never needs Automation permission. Finder picks up the moves on its own.

## Undo

```sh
dsort undo                  # reverse the most recent run that is not fully reverted
dsort undo <run-id>         # reverse a specific sort run
dsort undo --dry-run        # show what would happen, change nothing
dsort undo --json
```

For each moved file, undo looks:

1. at the recorded destination;
2. at wherever the file's inode is now, so it finds files you moved or renamed after sorting;
3. by document ID inside the run's bucket folders, so it finds files an app re-saved after you moved them.

Files go back with an exclusive rename. If the original Desktop name is taken, the file comes back as `name (restored).ext` (then `name (restored 2).ext`, …). Pass `--on-conflict skip` to leave such files where they are instead. Bucket folders the run created are removed once they are empty; a folder holding only Finder's `.DS_Store` counts as empty.

Each entry ends with one of these outcomes:

| Outcome | Meaning |
|---|---|
| `restored` | Put back under its original name. |
| `restored-renamed` | Put back as `name (restored).ext` because the original name was taken. |
| `already-restored` | Already back at its original path; nothing to do. |
| `in-trash` | Found in the Trash. Left there; put it back from the Trash if you want it. |
| `missing` | The file no longer exists. Nothing is recreated. |
| `inaccessible` | A lookup failed for a reason other than "does not exist", such as a folder the app cannot read. The file is not assumed gone. |
| `replaced` | A different file is at the recorded destination, and the original was not found. Pass `--by-path` to restore whatever is at that path. |
| `skipped-conflict` | The original name was taken and `--on-conflict skip` was given. |
| `failed` | The rename failed for another reason; the detail says why. |

dsort follows macOS's document identity. A tracked file that you delete and recreate at the same path counts as the same document, so it is restored rather than reported as `replaced`.

Undo exits 0 only when every entry is restored or already restored, otherwise 1. A run with unresolved entries becomes `partially-reverted`. Fix the cause, for example by granting folder access, then run `dsort undo <run-id>` again: only the unresolved entries are retried.

## After a crash

If dsort is killed, or the Mac loses power, in the middle of a run, the ledger already holds the complete plan. Every rename is atomic, so each file is either still in its original place or fully moved.

1. `dsort history` shows the run as `interrupted`, and `dsort run` refuses to start (exit code 1) until it is reconciled.
2. `dsort recover` checks every planned move by file identity and records which files moved. The run becomes `recovered`.
3. `dsort undo` can now reverse the moves that happened, like any other run.

```sh
dsort recover
dsort undo
```

## Check your setup

```sh
dsort doctor
```

`doctor` changes nothing. It reports whether:

- the root folder is readable (and which app needs permission if it is not);
- the volume supports exclusive renames and lookup by file ID;
- the lock is free;
- any run is interrupted;
- the config is valid.

It also shows where the config and data directories are. It exits 0 when every check passes.

## Run on a schedule with launchd

[`examples/local.dsort.plist`](examples/local.dsort.plist) runs `dsort run` once an hour:

```sh
cp examples/local.dsort.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.dsort.plist
```

Edit the binary path in the plist if `dsort` is not in `/usr/local/bin`. Output goes to `/tmp/dsort.log`. To stop the schedule, run `launchctl bootout gui/$(id -u)/local.dsort`.

Under launchd, macOS checks the `dsort` binary itself for Desktop access, not your terminal. Add the binary to **System Settings > Privacy & Security > Full Disk Access** before the first scheduled run, and again after every rebuild (see [Permissions](#permissions)). A denied run exits with code 77 and logs which binary needs access. Files modified in the last 10 seconds are skipped, so half-written screenshots and downloads wait for the next run.

## Preview a run

`dsort plan` (or `dsort run --dry-run`) prints exactly what a run would do, and changes nothing: no files, folders, flags, ledger, or lock.

```sh
dsort plan                      # sort ~/Desktop (or the configured root)
dsort plan --root ~/Downloads   # preview another folder
dsort plan --json               # machine-readable plan on stdout
```

```
Plan for /Users/you/Desktop (dry run, nothing changed):
  mkdir   Images/_Screenshots
  move    Screenshot 2026-10-14 at 16.48.54.png -> Images/_Screenshots/Screenshot 2026-10-14 at 16.48.54.png  [screenshot]
  move    invoice.pdf -> PDFs/invoice.pdf  [type]
  skip    .DS_Store  (hidden)
  skip    Projects  (folder)
2 to move, 1 folder to create, 2 skipped.
```

Each move shows the rule that matched: a triage rule's name, `extension`, `type`, or `fallback`. Skip reasons are `hidden`, `bucket`, `symlink`, `special`, `folder`, `skip-glob`, `never-move`, and `too-recent`.

## History and the run ledger

Every run that moves something writes a ledger before the first move happens. Ledgers live in:

- `$XDG_DATA_HOME/dsort/history/` when `XDG_DATA_HOME` is set, otherwise
- `~/Library/Application Support/dsort/history/`

Each run has one file, `<run-id>.jsonl`, named by a run ID such as `20261014T190912Z-3f9a0c1d2e4b` (UTC start time plus a random suffix). Ledgers are plain text, one JSON record per line, and are never edited after the fact: undo and recovery write their own ledgers. The record format is documented in [docs/ledger-format.md](docs/ledger-format.md).

```sh
dsort history              # newest first: run ID, kind, start time, state, counts
dsort history --limit 5
dsort show <run-id>        # every move of one run, with outcome and actual destination
```

A run's state is one of `committed`, `interrupted` (it stopped before finishing; run `dsort recover`), `recovered`, `partially-reverted`, or `reverted`. Both commands accept `--json`.

A run with nothing to move does not write a ledger, so a `launchd` schedule does not fill the history with empty runs.

## Configuration

dsort works without any configuration. To customize it, create a config file:

```sh
dsort config init       # writes the built-in defaults, never overwrites
dsort config path       # shows which file is in effect
dsort config validate   # checks it without touching the Desktop
```

The config file is read from `--config PATH`, otherwise `$XDG_CONFIG_HOME/dsort/config.json`, otherwise `~/.config/dsort/config.json`.

**A config file replaces the built-in rules.** Fields you leave out take the defaults below, but the rule lists `triage` and `categories` are empty unless you write them. The easiest start is `dsort config init`, then edit the result.

| Field | Default | Meaning |
|---|---|---|
| `version` | required | Always `1`. |
| `root` | `"~/Desktop"` | Folder to sort. Only its top level is scanned. |
| `minAgeSeconds` | `10` | Skip files modified more recently than this, so half-written files wait. |
| `sortFolders` | `false` | Plain folders are left alone. Packages such as `.app` are always treated as files. |
| `skipGlobs` | `["*.download", "*.crdownload", "*.part"]` | Names to skip (in-progress downloads). |
| `neverMove` | `[]` | Names that must never move, for example `"*.kdbx"`. |
| `triage` | `[]` | Ordered rules: `screenCapture: true` (macOS screenshot metadata) or `regex` (matched against the file name). |
| `categories` | `[]` | Ordered rules: `extensions` (checked first, across all categories) and/or system `types` (checked in order). |
| `fallback` | `"Other"` | Where everything else goes. |

Every destination (`to`, `fallback`) is a folder path relative to `root`, created on demand. Hidden files, symlinks, and the bucket folders themselves are never moved.

A small example:

```json
{
  "version": 1,
  "neverMove": ["*.kdbx"],
  "triage": [
    { "name": "screenshot", "screenCapture": true, "to": "Images/_Screenshots" },
    { "name": "screenshot-name", "regex": "^(Screenshot|Ekran Resmi) \\d{4}-\\d{2}-\\d{2}", "to": "Images/_Screenshots" }
  ],
  "categories": [
    { "to": "Code", "extensions": ["ts", "json"], "types": ["public.source-code"] },
    { "to": "Images", "types": ["public.image"] },
    { "to": "PDFs", "types": ["com.adobe.pdf"] }
  ],
  "fallback": "Other"
}
```

Validation rejects unknown fields, regular expressions that do not compile, unknown type identifiers, and destinations that are absolute or contain `.` or `..`. Errors name the field, for example `categories[0].to`, and exit with code 64.

## Tested platforms

- **macOS 26.6 (APFS):** sorting and undoing on the real Desktop. Finder updates the icons on its own, with "Use Stacks" both off and on.
- **macOS 14 and 15:** not yet tested by hand. The minimum supported version is macOS 14.

## Documentation

This README is for people using dsort. For maintainers and anyone porting it:

- [docs/architecture.md](docs/architecture.md): how dsort is built, the invariants it never breaks, and why.
- [docs/ledger-format.md](docs/ledger-format.md): the run ledger format and how run state is derived.
- [docs/platform-macos.md](docs/platform-macos.md): which macOS mechanism provides each guarantee, and what was verified about macOS.
- [docs/porting.md](docs/porting.md): how to bring dsort to another operating system.
- [AGENTS.md](AGENTS.md): a short map for coding agents.
- [`openspec/specs/`](openspec/specs/): the behaviour specification.

## License

dsort is free software, released under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
