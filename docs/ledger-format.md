# Ledger format

Every run that changes something leaves one ledger file. Ledgers are the only record of what dtidy did, and the only input for `history`, `show`, `recover`, and `undo`. This document is the contract for that format. `swift test` fails if a record type exists in the code but not here.

The behaviour these records support is specified in the `run-ledger` and `run-undo` specs under [`openspec/specs/`](../openspec/specs/). The reasons for the format are in [architecture.md](architecture.md#key-decisions).

## Files

- **Location:** `<data directory>/history/<run-id>.jsonl`. The data directory is `$XDG_DATA_HOME/dtidy` when that variable is set and non-empty, otherwise the platform location (`~/Library/Application Support/dtidy` on macOS).
- **Permissions:** the history folder is created with mode `0700`; each ledger file with mode `0600`.
- **Creation:** a ledger file is created exclusively, so dtidy fails rather than reuse an existing file, and opened append-only. It is never rewritten or truncated.
- **Run ID:** `YYYYMMDDTHHMMSSZ-` (UTC start time) followed by 12 lowercase hex digits, for example `20261014T190912Z-3f9a0c1d2e4b`.
- **Empty runs:** a run whose plan has no moves writes no ledger.

## Lines

- One JSON object per line, terminated by `\n`, written with a single `write` call.
- Field `t` names the record type. Other fields depend on the type; field order does not matter.
- The first line is always a `run` record. A file whose first readable line is not one is ignored.
- **Truncation:** if the file does not end with `\n`, its last line is treated as cut off by a crash and ignored, even if it happens to parse.
- **Corruption:** a line that cannot be decoded anywhere else (including an unknown `t`) is skipped, and the ledger is marked corrupt.

"Flushed" below means dtidy issues an ordering flush (`F_BARRIERFSYNC` on macOS) after writing the record and before the next change on disk. Records that are not flushed reach disk with the next flush.

## Record types

### `run`

The header: first line of every ledger.

| Field | Type | Meaning |
|---|---|---|
| `v` | int | Format version, currently `1`. |
| `run` | string | This run's ID. |
| `kind` | string | `sort`, `undo`, or `recover`. |
| `ts` | string | Start time, ISO 8601 UTC with milliseconds. |
| `root` | string | Absolute path of the root folder, symlinks resolved. |
| `tool` | string | dtidy version that wrote the ledger. |
| `reverts` | string? | Undo ledgers only: the sort run being reversed. |
| `recovers` | string? | Recover ledgers only: the interrupted sort run being reconciled. |

Written first. In sort ledgers it is flushed together with the plan, at `sealed`; undo and recover ledgers flush it immediately.

### `mkdir`

A bucket folder the run will create. Field: `path` (absolute). One record per folder, parents before children, written before `sealed`. Undo removes these folders when they end up empty.

### `move`

One planned move.

| Field | Type | Meaning |
|---|---|---|
| `seq` | int | Entry number within the run, starting at 1, in name order. |
| `src` | string | Absolute source path. |
| `dst` | string | Planned absolute destination, collision suffix already applied. |
| `rule` | string | The rule that matched: a triage rule's name, `extension`, `type`, or `fallback`. |
| `id` | object | File identity: `fsid` (two 32-bit integers identifying the volume), `ino` (file identifier), `birth` (creation time, seconds since 1970). |

Written before `sealed`.

### `sealed`

The plan is complete. Field: `moves` (number of `move` records). **Flushed.** No folder is created and no file is moved before this record is on disk.

### `tracked`

Document tracking for one entry, written just before its rename. Fields: `seq`; `docid` (document identity, `0` when none); `byUs` (`true` if dtidy turned tracking on, `false` if it was already on or could not be turned on). Not flushed.

### `retarget`

The planned destination was taken at move time, so the entry moves to a new name. Fields: `seq`, `dst` (the new absolute destination). **Flushed** before the rename is attempted. An entry can have several `retarget` records; the last one is its destination.

### `done`

The rename for `seq` succeeded. Field: `seq`. Not flushed; if it is lost in a crash, `recover` recomputes it from file identity.

### `fail`

The entry was not moved. Fields:
- `seq`;
- `errno` (the system error number, or absent when there is none, as for `changed`);
- `reason`, one of:
  - `cross-volume`;
  - `bucket-unavailable` (the bucket path is not a folder);
  - `vanished` (the source no longer exists);
  - `changed` (a different file now has the source name);
  - `no free name`;
  - or the system error text.

Not flushed.

### `restore`

Undo intent: about to rename `from` back to `to`. Fields: `seq` (the entry in the target sort run), `from`, `to`. **Flushed** before the rename. One record per name attempt, so a conflict that leads to `name (restored).ext` produces two records.

### `undone`

The outcome of undoing one entry. Fields:
- `seq`;
- `outcome`: `restored`, `restored-renamed`, `already-restored`, `in-trash`, `missing`, `inaccessible`, `replaced`, `skipped-conflict`, or `failed`;
- `from`: where the file was found, when it was found;
- `to`: where it was restored;
- `detail`: a hint or the error text.

Not flushed.

### `rmdir`

Undo removed an empty folder that the target run had created. Field: `path`. Not flushed.

### `state`

Recover's finding for one planned move. Fields:
- `seq`;
- `state`, one of:
  - `moved`: found at its destination, or anywhere other than its source;
  - `not-moved`: still at its source;
  - `lost`: found nowhere; undo will look for it again;
- `at`: where it was found.

Not flushed.

### `commit`

The run finished. Its other fields are counts and depend on the kind:
- sort: `done`, `failed`;
- undo: one count per outcome that occurred;
- recover: `moved`, `not-moved`, `lost`.

**Flushed.** A sort ledger without `commit` belongs to an interrupted run.

## Deriving run state

State is never stored; it is computed from all ledgers together.

**Order.** Runs are listed newest first by `ts`, then by run ID.

**Sort runs:**

1. **Finished?**
   - Committed if its own ledger has a `commit`.
   - Otherwise recovered if a recover ledger with `recovers` = this run has a `commit`.
   - Otherwise interrupted.
2. **Entries to undo.**
   - For a recovered run: every `seq` whose `state` is `moved` or `lost`.
   - Otherwise: every `seq` with a `done` record.
3. **Resolved entries.** Every `seq` with an `undone` record whose outcome is `restored`, `restored-renamed`, or `already-restored`, in any undo ledger with `reverts` = this run. Later ledgers override earlier ones for the latest outcome.
4. **State:**
   - `interrupted` if not finished.
   - `reverted` if there is at least one entry to undo and every one is resolved.
   - `partially-reverted` if any undo ledger references the run but some entries are unresolved.
   - Otherwise `committed` or `recovered`.

**Undo and recover runs:** `committed` if their ledger has a `commit`, otherwise `interrupted`. They are never undo targets.

**Default undo target:** the newest sort run that is finished, not `reverted`, and has at least one entry to undo.

**Destination of an entry:** its last `retarget` `dst`, otherwise its `move` `dst`.

**Paths an entry was restored to:** every `to` of its `restore` records, plus every `to` of resolving `undone` records. Undo treats a file found at one of these, or at the original `src`, as `already-restored`.

## Example

A sort run that moved two files, one of which collided at move time:

```jsonl
{"t":"run","v":1,"run":"20261014T190912Z-3f9a0c1d2e4b","kind":"sort","ts":"2026-10-14T19:09:12.123Z","root":"/Users/you/Desktop","tool":"0.1.0"}
{"t":"mkdir","path":"/Users/you/Desktop/PDFs"}
{"t":"move","seq":1,"src":"/Users/you/Desktop/invoice.pdf","dst":"/Users/you/Desktop/PDFs/invoice.pdf","rule":"type","id":{"fsid":[16777230,26],"ino":123456,"birth":1767225600.25}}
{"t":"move","seq":2,"src":"/Users/you/Desktop/report.pdf","dst":"/Users/you/Desktop/PDFs/report.pdf","rule":"type","id":{"fsid":[16777230,26],"ino":123457,"birth":1767225601.5}}
{"t":"sealed","moves":2}
{"t":"tracked","seq":1,"docid":296,"byUs":true}
{"t":"done","seq":1}
{"t":"tracked","seq":2,"docid":297,"byUs":true}
{"t":"retarget","seq":2,"dst":"/Users/you/Desktop/PDFs/report (1).pdf"}
{"t":"done","seq":2}
{"t":"commit","done":2,"failed":0}
```

Its undo, after the user had put a new `invoice.pdf` on the Desktop:

```jsonl
{"t":"run","v":1,"run":"20261015T080000Z-0a1b2c3d4e5f","kind":"undo","ts":"2026-10-15T08:00:00.000Z","root":"/Users/you/Desktop","tool":"0.1.0","reverts":"20261014T190912Z-3f9a0c1d2e4b"}
{"t":"restore","seq":1,"from":"/Users/you/Desktop/PDFs/invoice.pdf","to":"/Users/you/Desktop/invoice.pdf"}
{"t":"restore","seq":1,"from":"/Users/you/Desktop/PDFs/invoice.pdf","to":"/Users/you/Desktop/invoice (restored).pdf"}
{"t":"undone","seq":1,"outcome":"restored-renamed","from":"/Users/you/Desktop/PDFs/invoice.pdf","to":"/Users/you/Desktop/invoice (restored).pdf"}
{"t":"restore","seq":2,"from":"/Users/you/Desktop/PDFs/report (1).pdf","to":"/Users/you/Desktop/report.pdf"}
{"t":"undone","seq":2,"outcome":"restored","from":"/Users/you/Desktop/PDFs/report (1).pdf","to":"/Users/you/Desktop/report.pdf"}
{"t":"rmdir","path":"/Users/you/Desktop/PDFs"}
{"t":"commit","restored":1,"restored-renamed":1}
```

After this undo, the sort run's state is `reverted`.
