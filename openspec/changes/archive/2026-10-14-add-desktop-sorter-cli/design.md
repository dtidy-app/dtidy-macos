# Design

## Context

Greenfield repository: only OpenSpec scaffolding exists. See proposal.md for motivation and the five capability specs for required behavior.

Platform facts this design relies on, verified on macOS 26.6 (APFS Data volume, Swift 6.4) during exploration:

- **Finder:** it picks up renames made by other processes on its own; Desktop icons vanished and reappeared with no refresh call.
- **Screenshot metadata:** screenshots carry the extended attribute `com.apple.metadata:kMDItemIsScreenCapture`. Its value is a binary property list holding `true`. Exported copies lose it but keep the localized "Screenshot …" name.
- **Safe saves change the inode:** every safe-save strategy tested gives the file a new inode (temp file + rename, `Data.write(.atomic)`, `FileManager.replaceItemAt`, `NSDocument.writeSafely`). Only the two Foundation replace paths keep the birth time.
- **Document identifiers:** a document ID exists only on files flagged `UF_TRACKED`. It survives all of the save strategies above and renames. It reads through `URLResourceKey.documentIdentifierKey`. Some Desktop files are already tracked because apps set the flag.
- **`fsgetpath(fsid, inode)`:**
  - works without special privileges and returns user-visible `/Users/...` paths;
  - finds files that were moved or trashed;
  - returns `ENOENT` for deleted files and `EACCES` behind an unreadable folder;
  - after a hard link's first name is removed, returns the surviving name.
- **Volume capabilities:** the volume supports `RENAME_EXCL`, `RENAME_SWAP`, and path-from-ID, and is case-insensitive.
- **Exclusive rename on case-insensitive volumes:** `renamex_np(RENAME_EXCL)` returns `EEXIST` for a destination that differs only in letter case.
- **Inode numbers:** across 3,000 creations after 500 deletions they only increased, and none was reused.
- **Swift imports:** `fsgetpath`, `renamex_np`, `chflags`, and `getattrlist` import directly from Swift's `Darwin` module; no C target is needed.

## Goals / Non-Goals

**Goals:**
- Pure, filesystem-free classification and planning so every rule and collision case is unit-testable.
- Runs that are crash-safe and reversible, with no more than one flush before the moves start and one at commit on the normal path.
- A single statically linked binary with no runtime dependencies beyond system frameworks.
- Well under 100 ms end-to-end for a few hundred Desktop items. Startup cost dominates; per-item cost is microseconds.

**Non-Goals:**
- Recursing into subfolders, sorting plain folders by default, or watching the Desktop continuously. Scheduling is left to `launchd`.
- Restoring Desktop icon positions, which would require AppleScript.
- Redo, meaning undoing an undo run.
- Cross-volume moves (copy + delete).
- Reading file contents (EXIF, magic bytes) for classification.
- Distribution packaging (Homebrew tap, notarized releases).

## Decisions

### D1. Package layout: pure core, thin I/O layer

```
Package.swift                     swift-tools-version 6.x, macOS 14, Swift 6 language mode
Sources/DSortCore/   Model, Config (Codable + validation), Classifier, Planner,
                     SuffixNamer, LedgerRecord codec, Reconciler decision table  -- no I/O
Sources/DSortIO/     Scanner, Executor, LedgerWriter/Reader, RunLock, Paths,
                     Darwin shims (renamex_np, fsgetpath, chflags, xattr, docID)
Sources/dsort/       swift-argument-parser commands: run, plan, undo, recover,
                     history, show, doctor, config {init,path,validate}
Tests/DSortCoreTests/  Swift Testing, no filesystem
Tests/DSortIOTests/    Swift Testing, temp directories only
```

The Executor and Reconciler talk to the filesystem through a small `FileOps` protocol, so the I/O tests can inject faults: `EEXIST` races, `EXDEV`, `EACCES`, and a kill after N moves.

*Alternative:* a single module. Rejected because it lets I/O leak into the classifier and weakens the pure tests.

### D2. Pipeline

```
 Scanner -> [Entry] -> Classifier -> [Decision] -> Planner -> Plan --(dry-run: render, stop)
   |                                                            |
   | lstat + one getxattr + package/type resource values        v
   v                                              Ledger: header, mkdir*, move* , SEALED  (flush)
 Entry{name, dev, ino, birth, mtime, kind, isScreenCapture}     |
                                                                v
                                       Executor, per move: chflags +UF_TRACKED -> read docID
                                         -> renamex_np(src, dst, RENAME_EXCL)
                                            EEXIST -> next suffix -> RETARGET (flush) -> retry
                                         -> DONE / FAIL line (no flush)
                                                                |
                                                                v
                                                    COMMIT (flush), release lock
```

Execution is sequential. Moves into the same directory serialize on the directory lock anyway, and a few hundred renames take about a millisecond. Swift 6 strict concurrency is still enabled for compile-time safety.

*Alternative:* a TaskGroup fan-out. Rejected because it adds no throughput and makes the ledger order nondeterministic.

### D3. Exclusive rename everywhere

All moves and restores use `renamex_np(..., RENAME_EXCL)`; `FileManager.moveItem` is never used. Its check-then-move is racy and it has no exclusive flag.

`EXDEV` maps to the failure reason `cross-volume`. The bucket's device ID is compared with the root's before the first move, so a misconfigured bucket fails fast.

### D4. Ledger format: JSON Lines, plan-as-intent

One file per run, `<runId>.jsonl`, in the data directory resolved by the `run-ledger` spec. Records:

```jsonl
{"t":"run","v":1,"run":"20261014T190912Z-3f9a","kind":"sort","ts":"2026-10-14T19:09:12Z","root":"/Users/you/Desktop","tool":"0.1.0"}
{"t":"mkdir","path":"/Users/you/Desktop/Images/_Screenshots"}
{"t":"move","seq":1,"src":"…","dst":"…","rule":"screenshot",
 "id":{"fsid":[16777230,26],"ino":123456,"birth":1767225600.25}}
{"t":"sealed","moves":42}
{"t":"tracked","seq":1,"docid":296,"byUs":true}
{"t":"retarget","seq":7,"dst":"…/report (1).pdf"}
{"t":"done","seq":1}
{"t":"fail","seq":9,"errno":18,"reason":"cross-volume"}
{"t":"commit","done":41,"failed":1}
```

- Undo ledgers add `"reverts":"<runId>"` to the header. Their entries include `"outcome"`, with values from the `run-undo` spec, and `"from"`/`"to"` paths.
- Recover ledgers add `"recovers":"<runId>"` and one `"state"` record per entry.
- Run state (committed, interrupted, reverted, partially reverted) is computed by reading the ledgers and is never stored by rewriting a file.

**The identity is split across two records.** The document ID is recorded in a `tracked` line after `chflags`, not in the plan. A file gets a document ID only once it is tracked, and tracking happens just before its move. Tracking every file before sealing would add a second pass over the files and leave flags behind on a dry plan.

**Flushing:**
- `sealed` and `retarget` are flushed with `fcntl(F_BARRIERFSYNC)` before any rename that depends on them. This guarantees the ledger writes reach disk before the renames, and is far cheaper than `F_FULLFSYNC`.
- `commit` gets one more barrier.
- `done`/`fail` lines are not flushed individually. If one is lost, recovery recomputes it from file identity, because each rename is atomic: the file is always at either its source or its destination.

**Reading:** the reader ignores a trailing partial line.

*Alternatives:*
- A single JSON document: it cannot be appended to safely after a crash.
- Binary plist: not human-inspectable, and gains nothing at this size.
- A flush per move: 2N flushes buy nothing, since recovery can work out every move's outcome from identity.

### D5. File identity and the reconciler

The matching rule is fixed by the `run-undo` spec. Lookup order and the resulting outcomes:

```
 recorded dst exists?
   |-- identity matches (ino+birth, or docID) ----------------------> FOUND(dst)
   |-- exists, no match, keep as candidate for --by-path
   v
 fsgetpath(fsid, ino)
   |-- path P, lstat(P) matches ino+birth --------------------------> FOUND(P)
   |-- path P, birth differs (inode reused) ------------------------> continue
   |-- ENOENT ------------------------------------------------------> continue
   |-- other errno (EACCES, EPERM, ...) ----------------------------> INACCESSIBLE (stop)
   v
 docID != 0 ? scan the run's bucket folders recursively (getattrlistbulk or
              FileManager enumerator reading documentIdentifierKey) -> FOUND(P) / continue
   v
 dst candidate exists ? REPLACED (or restore it with --by-path) : MISSING

 FOUND(P): P under a Trash folder -> IN-TRASH
           P == original src      -> ALREADY-RESTORED
           else restore with RENAME_EXCL, "(restored n)" suffix on EEXIST
```

The decision table is a pure function in DSortCore. It takes the observations (stat results, fsgetpath result or error, scan result) and returns an outcome. Only the observation gathering is I/O, so every row is unit-tested.

The document-ID scan is limited to the run's bucket folders, so it stays bounded and never walks the whole home directory.

`recover` uses the same lookups for each planned move. If the file is found at its source, the entry is recorded as not moved; if found at its destination, as moved.

### D6. Tracking flag

`chflags(path, flags | UF_TRACKED)` is set just before each move, only if the flag is not already set, and `byUs` records whether dsort set it. The document ID is then read via `URLResourceKey.documentIdentifierKey`, after calling `removeAllCachedResourceValues()` because Foundation caches it.

A `chflags` failure, such as on a volume that does not support tracking, does not block the move. The entry is recorded with `docid: 0`, and that file falls back to inode + birth-time matching.

*Alternative:* skip tracking and accept that safe-saved files undo as `replaced`. The user rejected this during exploration.

### D7. Classification details

- **File kind** comes from `lstat` (symlinks are detected without following them) plus `URLResourceKey.isPackageKey` for directories.
- **Screenshot attribute:** `getxattr` reads `com.apple.metadata:kMDItemIsScreenCapture`, and the value is decoded with `PropertyListSerialization`; it counts only if it decodes to `Bool(true)`. A missing attribute or decode failure means no.
- **Name matching:** names are normalized to NFC (`precomposedStringWithCanonicalMapping`) before regex matching. Regexes are compiled once at config load as Swift `Regex<AnyRegexOutput>`.
- **Default screenshot pattern:** `^(Screenshot|Screen Shot|Ekran Resmi|Bildschirmfoto|Capture d’écran) \d{4}-\d{2}-\d{2}`, with both the straight and curly apostrophe accepted for French.
- **File type:** `UTType(filenameExtension:)` followed by `conforms(to:)` against each category's identifiers, in order. Nothing is read from file contents.

### D8. Collision naming

The suffix is applied to the "stem" of the name:
- A known compound extension (`.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`) stays together, giving `backup (1).tar.gz`.
- Otherwise the last extension is kept, giving `doc (1).pdf`, `Tool (1).app`.
- A name with no extension gets the suffix appended.

If the result exceeds 255 UTF-8 bytes, the stem is trimmed on a grapheme boundary. Undo uses the same namer with the ` (restored)` / ` (restored n)` suffix.

### D9. Configuration

- **Decoding:** `JSONDecoder` into Codable structs.
- **Unknown fields:** rejected by first decoding into `[String: Any]` via `JSONSerialization` and comparing keys against the known set at every level, because Codable silently ignores extras.
- **Defaults:** live in code as a `Config.default` value. `config init` writes them with `JSONEncoder` (`.prettyPrinted`, `.sortedKeys`, `.withoutEscapingSlashes`), so the written file and the built-ins cannot drift apart.
- **Type identifiers:** validation requires `UTType(identifier)?.isDeclared == true`.

*Alternative:* property list. Rejected because JSON is easier to read and edit on GitHub and in an editor; both are free in Foundation.

### D10. Paths, lock, permissions

- **Data directory:** `$XDG_DATA_HOME/dsort`, otherwise `~/Library/Application Support/dsort`. Config follows the `sort-configuration` spec.
- **Lock:** `flock(LOCK_EX | LOCK_NB)` on `<data>/lock`, held for the life of the process and released by the kernel on crash. No PID-file staleness logic is needed.
- **Permission errors:** `EPERM` from `opendir`/`contentsOfDirectory` on the root exits 77 with a message that:
  - names the responsible app (`TERM_PROGRAM` when present, otherwise "the dsort binary at <path>");
  - points to System Settings → Privacy & Security → Files and Folders / Full Disk Access.
- **`doctor`** runs the same checks read-only and reports the volume capabilities through `getattrlist(ATTR_VOL_CAPABILITIES)`.

### D11. Exit codes and output

The exit codes come from sysexits and are defined in the `sort-execution` spec.

- **Text output** goes to stdout: one line per action, plus a summary.
- **`--json`** emits a single document on stdout, and diagnostics go to stderr.
- **JSON schema:** the JSON models are the same Codable types as the plan and undo report, so the CLI and tests share them.

## Risks / Trade-offs

- **[TCC grants for an ad-hoc-signed binary reset on rebuild under `launchd`]** → Document it in the README. `doctor` detects the failure, and exit code 77 explains it.
- **[`chflags` changes metadata on user files (ctime, and a flag visible to `stat`)]** → Accepted by the user. It is recorded per file as `byUs` for auditability, and some files on the Desktop already carry it.
- **[Document-ID behavior on non-APFS or network volumes is untested]** → The root and buckets are on one volume by design (D3). If tracking fails, matching falls back to inode + birth time (D6).
- **[The privacy-protected (TCC) failure of `fsgetpath` could not be reproduced (Terminal lacks Full Disk Access, so no protected file inode was reachable)]** → The rule "only `ENOENT` means missing" makes every other error report `inaccessible`, so the behavior is safe whatever error code appears.
- **[Document IDs stay with the file's *original* path (found during implementation)]** In the kernel tests:
  - A tracked file deleted and recreated at the same path inherits the ID.
  - Once a tracked file has been renamed away, a new file created at its old path takes the ID, and the renamed file loses it. This held across folders and five seconds later.
  - Once the moved file has itself been safe-saved, its new path becomes the sticky one.

  → The reconciler checks the recorded destination by inode first, so a file that was only moved is always found correctly. A tracked file "replaced" at the same path counts as the same document, so the `replaced` outcome effectively applies to untracked files.

  One misreport remains, and it loses no data. If a sorted file is safe-saved *and* a same-named file later appears at its original Desktop path, undo can report the entry `already-restored` while the edited file stays in its bucket.
- **[`done` lines are unflushed, so after a crash the ledger can under-report completed moves]** → `recover` recomputes every entry from identity, and new runs are blocked until it is run.
- **[The default screenshot name patterns cover only a few languages]** → The metadata attribute is the primary signal and works in every language. The name patterns are configurable.
- **[Finder's automatic refresh was verified on one macOS version and in the default view mode]** → Release checklist: re-check with "Use Stacks" on and on macOS 14. No code depends on Finder.
- **[The Swift `Regex` runtime is slower than `NSRegularExpression`]** → It matches a few hundred short names per run, which is negligible. Swap the engine behind the matcher type if profiling disagrees.

## Migration Plan

Not applicable: this is a new tool with no prior state. A run's rollback is `dsort undo`. Uninstalling means deleting the binary, the data directory, and the optional config file. Bucket folders and the `UF_TRACKED` flags stay on the user's files.
