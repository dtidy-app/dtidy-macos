# Porting dsort to another platform

This guide is for building dsort for another operating system, by hand or with a coding agent. The macOS version is the reference implementation, but **the specs, not the Swift code, define what a port must do.**

## What carries over unchanged

- **Behaviour:** the core capability specs in [`openspec/specs/`](../openspec/specs/): `item-classification`, `sort-execution`, `run-ledger`, `run-undo`, `sort-configuration`. They are written in platform-neutral terms; the glossary in [architecture.md](architecture.md#glossary) defines each term.
- **Invariants and design decisions:** [architecture.md](architecture.md). The pure core (classifier, planner, suffix naming, ledger codec, run-state derivation, undo decision table) translates almost line by line.
- **Formats:** the ledger ([ledger-format.md](ledger-format.md)) and the config file (`sort-configuration` spec). Keep both identical so the docs, tooling, and users' knowledge carry over. Only config `types` entries are platform-specific, because they name the platform's type identifiers.
- **CLI:** commands, flags, JSON output, and exit codes.

What does *not* carry over is everything in `openspec/specs/platform-macos/` and [platform-macos.md](platform-macos.md). Those show what a platform binding looks like, not what the new one must contain.

## Procedure

1. **Copy the core specs** into the new project unchanged. If a core requirement cannot hold on the new platform, change the core spec through an OpenSpec change rather than quietly diverging, because it affects every platform.
2. **Fill in the binding table** below for the new platform: one mechanism per row.
3. **Spike every unverified row before writing product code.** Write throwaway programs in a scratch folder and record what actually happens. On macOS this step found three things the design then had to accommodate: safe saves change the inode, document IDs follow the original path, and kernel paths start with `/private`.
4. **Write `platform-<os>` as a capability spec** with one requirement per binding, each with a testable scenario. Use `platform-macos` as the model.
5. **Write `docs/platform-<os>.md`** with the binding table, the mechanisms, and a "Verified behaviour" section for what the spikes found.
6. **Implement against the specs.** Keep the split between a pure core and a single filesystem-operations interface that tests can fault-inject. That interface is `FileOps` on macOS.
7. **Port the tests.** The test suites under `Tests/` mirror the spec scenarios. Most core tests translate directly; filesystem tests need the new platform's temp folders and fault injection.

## Binding table template

Copy this table into `docs/platform-<os>.md` and fill in the last two columns. The rows cover every glossary term and every kind of binding that `platform-macos` needed.

| Need | Used by (spec › requirement) | macOS answer | New platform: mechanism | Verified? |
|---|---|---|---|---|
| root folder (default location) | item-classification › Top-level scanning only | `~/Desktop` | | |
| file identity | run-undo › File identity matching | `f_fsid` + inode + birth time | | |
| document identity | run-undo › File identity matching | kernel document ID | | |
| document tracking | sort-execution › Moved files are marked as tracked | `UF_TRACKED` flag | | |
| screen-capture marker | item-classification › Screenshots are detected by system metadata | `kMDItemIsScreenCapture` xattr | | |
| default screenshot names | item-classification › Screenshots are detected by localized name as a fallback | `Screenshot YYYY-MM-DD …` and translations | | |
| platform type system | item-classification › System type conformance decides categories | UTType conformance | | |
| packages | item-classification › Plain folders are skipped by default | `isPackageKey` | | |
| hidden items | item-classification › Hidden items are skipped | leading `.` only | | |
| links to skip | item-classification › Symbolic links are skipped | symlinks | | |
| platform trash | run-undo › Trashed files are not restored | `/.Trash/`, `/.Trashes/` | | |
| folder-metadata file | run-undo › Empty bucket folders are removed | `.DS_Store` | | |
| data directory | run-ledger › Ledger location | `~/Library/Application Support/dsort` | | |
| config file | sort-configuration › Config file location | `~/.config/dsort/config.json` | | |
| exclusive atomic rename | sort-execution › Moves never overwrite | `renamex_np` + `RENAME_EXCL` | | |
| case-insensitive names | sort-execution › Moves never overwrite | volume capability flag | | |
| current path by file identifier | run-undo › Locating moved files | `fsgetpath` | | |
| ordering flush | run-ledger › Plan is durable before any move | `F_BARRIERFSYNC` | | |
| single-run lock | sort-execution › Single concurrent run | `flock` | | |
| permission denial and its message | sort-execution › Permission failures are explained | TCC, exit 77, System Settings pane | | |
| file manager refresh | sort-execution › No file-manager scripting | none needed (Finder) | | |
| scheduler | README (usage) | `launchd` agent | | |

## Windows: candidates to spike

**Nothing in this table has been verified.** It lists where to start looking, from general knowledge of the Win32 and NTFS APIs. Treat every row as a hypothesis for step 3.

### Locations and identity

| Need | Candidate mechanism | Watch out for |
|---|---|---|
| root folder | Known folder `FOLDERID_Desktop` via `SHGetKnownFolderPath` | OneDrive "Known Folder Move" can redirect the Desktop into OneDrive, where files may be cloud placeholders. Never read contents. |
| file identity | `GetFileInformationByHandleEx(FileIdInfo)`: volume serial number + 128-bit file ID; creation time from `GetFileInformationByHandle` | NTFS "tunneling" can give a file recreated under a recently deleted name the old creation time. Check that the creation-time guard still works. |
| current path by file identifier | `OpenFileById` + `GetFinalPathNameByHandleW` | Path prefixes (`\\?\`) must be normalized before comparing with recorded paths, much as macOS needs `realpath`. |
| document identity / tracking | NTFS object IDs (`FSCTL_CREATE_OR_GET_OBJECT_ID`) and the Distributed Link Tracking service | Unknown whether IDs survive common safe-save patterns (`ReplaceFileW`, write-temp-then-rename). This is the most important spike. |
| data directory | `%LOCALAPPDATA%\dsort` | |
| config file | `%APPDATA%\dsort\config.json` | |

### Moves and the ledger

| Need | Candidate mechanism | Watch out for |
|---|---|---|
| exclusive atomic rename | `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING`, or `SetFileInformationByHandle(FileRenameInfo)` with `ReplaceIfExists = FALSE` | Confirm atomicity and that the error for a taken name is distinct (`ERROR_ALREADY_EXISTS` / `ERROR_FILE_EXISTS`). Cross-volume moves need `MOVEFILE_COPY_ALLOWED`; never pass it. |
| case-insensitive names | NTFS is case-insensitive by default; per-directory case sensitivity exists | NTFS does not normalize Unicode: precomposed and decomposed names are different files. Name matching must still normalize to NFC. |
| name length | 255 UTF-16 code units per name on NTFS | The spec's limit is 255 bytes of UTF-8. Decide whether the core spec should state the limit per platform. |
| ordering flush | `FlushFileBuffers` | It is a full flush with no cheaper barrier: two per run, which is acceptable. |
| single-run lock | `LockFileEx` on `<data directory>\lock`, or a named mutex | Must be released automatically when the process dies. |

### Classification and permissions

| Need | Candidate mechanism | Watch out for |
|---|---|---|
| screen-capture marker | None known | Snipping Tool and Win+PrtScn save to `Pictures\Screenshots`; their names (for example `Screenshot 2026-10-14 191312.png`) differ from macOS. Rely on name patterns; check the exact formats per language. |
| platform type system | Extension → `PerceivedType` (image, video, audio, text, compressed, document) via `AssocQueryStringW` | There is no conformance hierarchy like UTType. Config `types` would name perceived types or registered ProgIDs; decide which. |
| packages | Probably none | Folders are folders. `.lnk` shortcuts are ordinary files. |
| hidden items | `FILE_ATTRIBUTE_HIDDEN` and `FILE_ATTRIBUTE_SYSTEM`, plus a leading `.` | `desktop.ini` has no leading dot, so the attribute rule is required. |
| links to skip | Reparse points: symlinks and junctions | Check `FILE_ATTRIBUTE_REPARSE_POINT`; OneDrive placeholders are reparse points too, and must *not* be skipped as links. |
| platform trash | `\$Recycle.Bin\<SID>\` on each volume | |
| folder-metadata file | `desktop.ini`, `Thumbs.db` | |
| permission denial | Defender "Controlled folder access" can block writes to the Desktop (`ERROR_ACCESS_DENIED`) | The message should name the app to allow and where (Windows Security › Ransomware protection). Map it to exit 77. |
| file manager refresh | Explorer watches folders itself | Verify that the Desktop updates after a rename from another process, with no `SHChangeNotify` needed. |
| scheduler | Task Scheduler | |

## Sharing specs between platforms

While there is one implementation, the specs live in this repository. Once a second platform exists, move the core specs into a shared OpenSpec repository (a "store"), and have each implementation point at it. Each platform keeps only its `platform-<os>` spec and docs locally, so a spec change is made once and reviewed for every platform. See `openspec store --help` for how projects reference a store; this has not been set up for dsort yet.

An agent working on a port then needs only:
- the new project's `AGENTS.md`;
- the shared core specs (`openspec show <spec-id> --type spec` returns one compactly);
- its own platform document.

It never needs another platform's code.
