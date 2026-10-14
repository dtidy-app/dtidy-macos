# dtidy

`dtidy` is a small command-line tool for macOS that tidies the top level of your Desktop into category folders, and can put everything back with `dtidy undo`.

- **Native and fast.** A single Swift binary, no runtime dependencies, no shell scripts, no AppleScript.
- **Non-destructive.** Files are only ever renamed with an exclusive, atomic rename. dtidy never overwrites, deletes, or copies your files.
- **Reversible.** Every run is recorded in a ledger before anything moves, and `dtidy undo` finds files even after you moved, renamed, or edited them.

Requires macOS 14 (Sonoma) or later.

## Install

With [Homebrew](https://brew.sh):

```sh
brew install dtidy-app/tap/dtidy
```

This installs the binary, the man page, and the zsh, bash and fish completions. `brew upgrade dtidy` keeps them current, and `brew uninstall dtidy` removes them but leaves your config and run history in place. Homebrew installs a prebuilt bottle when one exists for your Mac. Otherwise it builds dtidy from source, which needs Xcode 16 or later.

### Build from source

The source is at [github.com/dtidy-app/dtidy-macos](https://github.com/dtidy-app/dtidy-macos).

```sh
git clone https://github.com/dtidy-app/dtidy-macos.git
cd dtidy-macos
make                  # release build plus zsh, bash and fish completion scripts
sudo make install     # binary, man page and completions under /usr/local
```

`make install` puts five files under `PREFIX` (default `/usr/local`): `bin/dtidy`, `share/man/man1/dtidy.1`, and the completion scripts in `share/zsh/site-functions/`, `share/bash-completion/completions/` and `share/fish/vendor_completions.d/`. Install somewhere else with `make install PREFIX=~/.local`. `sudo make uninstall` (with the same `PREFIX`) removes exactly those files.

Run the tests with `swift test`.

## Shell completion and help

Once dtidy is installed, Tab completes subcommands, options, `--on-conflict` values, folders for `--root`, `.json` files for `--config`, and run IDs: `dtidy undo <Tab>` offers the runs that can be undone, and `dtidy show <Tab>` offers every run. Completing never changes anything and never waits for a running dtidy.

- **zsh** (the macOS default): Homebrew's `share/zsh/site-functions` is on zsh's search path once `eval "$(brew shellenv)"` runs (Homebrew's installer adds it to `~/.zprofile`), and `/usr/local/share/zsh/site-functions` always is. Make sure completion is turned on in `~/.zshrc`:

  ```sh
  autoload -Uz compinit && compinit
  ```

  For another `PREFIX`, add `fpath=(<PREFIX>/share/zsh/site-functions $fpath)` before that line. After installing a new version, run `rm -f ~/.zcompdump && compinit` to refresh zsh's cache.
- **bash**: load the script from `~/.bash_profile`. This works with the macOS bash 3.2 and with newer versions:

  ```sh
  source "$(brew --prefix)/etc/bash_completion.d/dtidy"         # Homebrew install
  source /usr/local/share/bash-completion/completions/dtidy    # make install
  ```

  With Homebrew's `bash-completion@2` (`brew install bash-completion@2`, then add `[[ -r "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]] && . "$(brew --prefix)/etc/profile.d/bash_completion.sh"` to `~/.bash_profile`), Homebrew-installed scripts load automatically, and so do scripts in `share/bash-completion/completions/` on its search path.
- **fish**: nothing to do; fish reads `share/fish/vendor_completions.d/` under Homebrew's prefix and `/usr/local`.

If you copied only the binary, generate a script yourself, for example for zsh:

```sh
mkdir -p ~/.zsh/completions
dtidy --generate-completion-script zsh > ~/.zsh/completions/_dtidy
# in ~/.zshrc, before compinit:
fpath=(~/.zsh/completions $fpath)
```

`bash` and `fish` work the same way: `dtidy --generate-completion-script bash` or `fish`.

Every command explains itself with examples: `dtidy --help`, `dtidy help undo`, or `dtidy config init --help`. The top-level help also lists the exit codes and where the config and history live. The same text is in the manual: `man dtidy`.

## Sort the Desktop

```sh
dtidy            # same as `dtidy run`
dtidy run --json
dtidy run --root ~/Downloads
```

dtidy looks only at the top level of the root folder and moves each eligible item into a bucket folder inside it, such as `Images/`, `Images/_Screenshots/`, `PDFs/`, `Documents/`, `Code/`, `Archives/`, or `Other/`. Folders are created only when something goes into them.

What dtidy guarantees:

- **Nothing is overwritten.** Every move is an atomic rename that fails if the target name exists, including names that differ only by case. A taken name gets a Finder-style suffix: `invoice (1).pdf`, `backup (1).tar.gz`.
- **Nothing is deleted or copied.** A bucket on a different volume is refused (`cross-volume`) instead of copying.
- **Nothing runs twice at once.** A lock in the data directory makes a second dtidy process exit with code 75.
- **After a crash, sorting waits.** If a run was interrupted, `dtidy run` refuses to start until you run `dtidy recover`.

**Side effect: the tracked flag.** Before moving a file, dtidy sets the file's `UF_TRACKED` flag (the same flag Preview and TextEdit set). The kernel then gives the file a document ID that survives "safe saves" by apps, so `dtidy undo` can find the file even after you edit it. Undo leaves the flag in place. The ledger records which files dtidy flagged.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Every planned action succeeded. |
| 1 | Some items failed or were left unresolved, or an interrupted run needs `dtidy recover`. |
| 64 | Usage or configuration error. |
| 75 | Another dtidy process holds the lock. |
| 77 | macOS denied access to the folder (see below). |

### Permissions

The Desktop is protected by macOS privacy controls. On the first run, macOS asks whether your terminal app may access the Desktop folder. If access is denied, dtidy exits with code 77 and says which app needs permission. Grant it in **System Settings > Privacy & Security > Files and Folders** (Desktop Folder) or **Full Disk Access**:

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
```

Under `launchd` there is no terminal, so macOS checks the `dtidy` binary itself. Add the binary to Full Disk Access. A locally built binary is ad-hoc signed, and macOS ties the grant to that exact build: **after every rebuild you must grant access again**, or sign the binary with a stable identity.

dtidy never uses AppleScript or Apple Events, so it never needs Automation permission. Finder picks up the moves on its own.

## Undo

```sh
dtidy undo                  # reverse the most recent run that is not fully reverted
dtidy undo <run-id>         # reverse a specific sort run
dtidy undo --dry-run        # show what would happen, change nothing
dtidy undo --json
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

dtidy follows macOS's document identity. A tracked file that you delete and recreate at the same path counts as the same document, so it is restored rather than reported as `replaced`.

Undo exits 0 only when every entry is restored or already restored, otherwise 1. A run with unresolved entries becomes `partially-reverted`. Fix the cause, for example by granting folder access, then run `dtidy undo <run-id>` again: only the unresolved entries are retried.

## After a crash

If dtidy is killed, or the Mac loses power, in the middle of a run, the ledger already holds the complete plan. Every rename is atomic, so each file is either still in its original place or fully moved.

1. `dtidy history` shows the run as `interrupted`, and `dtidy run` refuses to start (exit code 1) until it is reconciled.
2. `dtidy recover` checks every planned move by file identity and records which files moved. The run becomes `recovered`.
3. `dtidy undo` can now reverse the moves that happened, like any other run.

```sh
dtidy recover
dtidy undo
```

## Check your setup

```sh
dtidy doctor
```

`doctor` changes nothing. It reports whether:

- the root folder is readable (and which app needs permission if it is not);
- the volume supports exclusive renames and lookup by file ID;
- the lock is free;
- any run is interrupted;
- the config is valid.

It also shows where the config and data directories are. It exits 0 when every check passes.

## Run on a schedule with launchd

[`examples/local.dtidy.plist`](examples/local.dtidy.plist) runs `dtidy run` once an hour:

```sh
cp examples/local.dtidy.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.dtidy.plist
```

Edit the binary path in the plist if `dtidy` is not in `/usr/local/bin`. Output goes to `/tmp/dtidy.log`. To stop the schedule, run `launchctl bootout gui/$(id -u)/local.dtidy`.

If you loaded the agent under its earlier name, stop it first with `launchctl bootout gui/$(id -u)/local.dsort`.

Under launchd, macOS checks the `dtidy` binary itself for Desktop access, not your terminal. Add the binary to **System Settings > Privacy & Security > Full Disk Access** before the first scheduled run, and again after every rebuild (see [Permissions](#permissions)). A denied run exits with code 77 and logs which binary needs access. Files modified in the last 10 seconds are skipped, so half-written screenshots and downloads wait for the next run.

## Preview a run

`dtidy plan` (or `dtidy run --dry-run`) prints exactly what a run would do, and changes nothing: no files, folders, flags, ledger, or lock.

```sh
dtidy plan                      # sort ~/Desktop (or the configured root)
dtidy plan --root ~/Downloads   # preview another folder
dtidy plan --json               # machine-readable plan on stdout
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

- `$XDG_DATA_HOME/dtidy/history/` when `XDG_DATA_HOME` is set, otherwise
- `~/Library/Application Support/dtidy/history/`

Each run has one file, `<run-id>.jsonl`, named by a run ID such as `20261014T190912Z-3f9a0c1d2e4b` (UTC start time plus a random suffix). Ledgers are plain text, one JSON record per line, and are never edited after the fact: undo and recovery write their own ledgers. The record format is documented in [docs/ledger-format.md](docs/ledger-format.md).

```sh
dtidy history              # newest first: run ID, kind, start time, state, counts
dtidy history --limit 5
dtidy show <run-id>        # every move of one run, with outcome and actual destination
```

A run's state is one of `committed`, `interrupted` (it stopped before finishing; run `dtidy recover`), `recovered`, `partially-reverted`, or `reverted`. Both commands accept `--json`.

A run with nothing to move does not write a ledger, so a `launchd` schedule does not fill the history with empty runs.

## Configuration

dtidy works without any configuration. To customize it, create a config file:

```sh
dtidy config init       # writes the built-in defaults, never overwrites
dtidy config path       # shows which file is in effect
dtidy config validate   # checks it without touching the Desktop
```

The config file is read from `--config PATH`, otherwise `$XDG_CONFIG_HOME/dtidy/config.json`, otherwise `~/.config/dtidy/config.json`.

**A config file replaces the built-in rules.** Fields you leave out take the defaults below, but the rule lists `triage` and `categories` are empty unless you write them. The easiest start is `dtidy config init`, then edit the result.

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

This README is for people using dtidy. For maintainers and anyone porting it:

- [docs/architecture.md](docs/architecture.md): how dtidy is built, the invariants it never breaks, and why.
- [docs/ledger-format.md](docs/ledger-format.md): the run ledger format and how run state is derived.
- [docs/platform-macos.md](docs/platform-macos.md): which macOS mechanism provides each guarantee, and what was verified about macOS.
- [docs/porting.md](docs/porting.md): how to bring dtidy to another operating system.
- [AGENTS.md](AGENTS.md): a short map for coding agents.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to report bugs and propose changes.
- [SECURITY.md](SECURITY.md): how to report a problem that could put files at risk.
- [docs/releasing.md](docs/releasing.md): how a release is made.
- [`openspec/specs/`](openspec/specs/): the behaviour specification.

## License

dtidy is free software, released under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
