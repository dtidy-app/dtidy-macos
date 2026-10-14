# Architecture

This document explains how dtidy is put together and why. It is written for maintainers and for anyone porting dtidy to another platform.

- **What dtidy must do** is defined by the specs in [`openspec/specs/`](../openspec/specs/).
- **How macOS provides each guarantee** is in [platform-macos.md](platform-macos.md).
- **How to start a new platform** is in [porting.md](porting.md).

## Pipeline

A sort run is a straight pipeline. Only the edges touch the filesystem.

```
            +-----------+   +------------+   +---------+   +----------+   +----------+
 root  ---> |  Scanner  |-->| Classifier |-->| Planner |-->| Executor |-->|  ledger  |
 folder     | (I/O)     |   | (pure)     |   | (pure)  |   | (I/O)    |   |  file    |
            +-----------+   +------------+   +---------+   +----------+   +----------+
             entries         decisions        plan          renames        records
                                                 |
                                       dry run stops here and prints the plan

 undo:     ledgers --> History (pure) --> Reconciler (pure decision table) --> UndoService (I/O)
 recover:  ledgers --> History (pure) --> RecoverService (I/O) --> recover ledger
```

1. **Scanner:** lists the top level of the root folder. It records each item's name, kind (file, package, folder, symlink, special), file identity, modification time, and whether it carries the screen-capture marker. It never reads file contents and never follows symlinks.
2. **Classifier:** turns each entry into a decision: skip (with a reason) or move to a bucket (with the name of the rule that matched). The rules apply in a fixed order; see the `item-classification` spec.
3. **Planner:** turns the decisions into a plan: which folders to create (parents first), and the moves with their collision suffixes already worked out against what exists in each bucket. Moves are numbered (`seq`) in name order.
4. **Executor:** writes the whole plan to a new ledger and flushes it, creates the folders, then performs each move and records the outcome.
5. **Undo and recover** rebuild each run's state from all the ledgers, decide what to do for each entry with a pure decision table, and only then touch files.

## Modules

| Module | Role | Filesystem access |
|---|---|---|
| `Sources/DTidyCore` | Models, configuration parsing and validation, classifier, planner, suffix naming, ledger codec, run-state derivation (`History`), undo decision table (`Reconciler`), text and JSON rendering | None. Every observation arrives as a value, so all rules are unit-tested without a disk. |
| `Sources/DTidyIO` | `FileOps` (every system call, behind a protocol), `Scanner`, `Executor`, `SortService`, `UndoService`, `RecoverService`, `Doctor`, ledger writer/store, run lock, config loader | Yes. Every operation on user files (listing, identity, renames, folder creation and removal, lookups) goes through `FileOps`, and tests swap in a fault-injecting one. Ledger, lock, and config files are read and written directly, and so is the `.DS_Store` deletion during undo. |
| `Sources/dtidy` | The command-line interface (swift-argument-parser): parses arguments, calls a service, prints the report, maps errors to exit codes | Only through the services |

A port keeps this split: the pure core can be translated almost line by line, and only the I/O layer is truly platform-specific.

## Invariants

These hold on every platform. Breaking any of them is a bug.

1. **Rename only, never replace.** Files are moved with an atomic rename that fails if the target name exists. dtidy never overwrites, deletes, or copies a user file. The one exception: undo deletes the platform's folder-metadata file so it can remove an otherwise empty bucket folder.
2. **The plan is durable before anything moves.** Every planned move and folder is written to the ledger and flushed before the first change on disk. After a crash, every file is therefore either at its source or at its recorded destination.
3. **Only "does not exist" means missing.** A lookup that fails for any other reason (permission denied, I/O error) is reported as `inaccessible`, never treated as deletion.
4. **One run at a time.** `run`, `undo`, and `recover` hold an exclusive, non-blocking lock. A second process exits with code 75.
5. **Ledgers are append-only.** Undo and recover write their own ledgers that point at the run they act on. A run's state is always derived by reading ledgers, never stored by editing one.
6. **Dry runs change nothing.** No files, folders, flags, ledgers, or lock files.

## Key decisions

| Decision | Why | Rejected alternative |
|---|---|---|
| Sequential execution | Renames into the same folder serialize in the kernel anyway; a few hundred renames take about a millisecond. Sequential order keeps the ledger deterministic. | Parallel moves: no throughput gain, nondeterministic ledger. |
| Plan-as-intent ledger with two flush points | The flush after the plan and the one at commit are enough. Lost per-move `done` lines can be recomputed from file identity, because each rename is atomic. | A flush before every move: twice as many flushes for no added safety. |
| Ordering flushes (barriers) instead of full device flushes | dtidy needs the ledger to reach disk before the renames that follow, not a guarantee against power loss of the disk cache. Losing the ledger never loses user data. | Full device flush per record: much slower, no extra protection for files. |
| JSON Lines ledger | Appending a line is crash-safe; a half-written last line is detected and ignored. | One JSON document: cannot be appended safely. Binary: not inspectable. |
| A config file replaces the built-in rules | No merge rules to explain or debug. `dtidy config init` writes the defaults as a starting point, so the file and the built-ins never drift. | Merging user rules into defaults: ambiguous ordering and removal. |
| No file-manager scripting | The file manager notices renames on its own, so scripting it would only add a permission prompt and a failure mode. | Asking the file manager to refresh after each run. |
| Top-level only, plain folders skipped by default | The Desktop's top level is where clutter accumulates; folders are usually deliberate. | Recursive sorting: surprising and hard to undo mentally. |
| Document tracking turned on before moving | Without it, an app's safe save gives a file a new file identifier, and undo would lose track of it. | Accept `replaced` for safe-saved files. |

## Glossary

The specs use these platform-neutral terms. Each platform document defines how its platform provides them.

| Term | Meaning |
|---|---|
| root folder | The folder being sorted, by default the user's Desktop. Only its direct children are considered. |
| file identity | Volume identifier + file identifier + creation time. Stable across renames on one volume. The creation time guards against a reused file identifier. |
| document identity | An identifier that survives an app's safe save (when the app writes a new file and swaps it into place). 0 when the platform or file has none. |
| document tracking | Opting a file into document identity, on platforms where that is opt-in. |
| screen-capture marker | Metadata the platform's screenshot tool attaches to the files it creates. It identifies screenshots in any language. |
| platform type system | How a file's type is derived from its extension, including any hierarchy (for example "PNG is an image"). |
| platform trash | The folders holding deleted-but-recoverable files. |
| folder-metadata file | A file the file manager creates inside folders to store view settings. It is not user content. |
| data directory | The per-user application-data location for dtidy; ledgers live in its `history/` folder. |
| config file | The per-user location of dtidy's `config.json`. |

Other terms used throughout:

| Term | Meaning |
|---|---|
| bucket | A destination folder inside the root, such as `Images/_Screenshots` or `PDFs`. |
| run | One execution of `run`, `undo`, or `recover` that changed something, recorded in one ledger file. |
| entry | One planned move within a sort run, identified by its `seq`. |
| safe save | An app saving by writing a new file and renaming it over the old one. The file identifier changes. |
