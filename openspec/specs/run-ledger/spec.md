# run-ledger Specification

## Purpose

Keeps a durable, append-only record of every run so that any completed or interrupted run can be inspected, reconciled, and reversed later.

## Requirements

### Requirement: Ledger location
The system SHALL store run ledgers in `$XDG_DATA_HOME/dsort/history/` when `XDG_DATA_HOME` is set and non-empty, otherwise in `~/Library/Application Support/dsort/history/`, with one file per run named by its run ID.

#### Scenario: Default location
- **WHEN** `XDG_DATA_HOME` is unset and a run completes
- **THEN** its ledger exists under `~/Library/Application Support/dsort/history/`

#### Scenario: XDG override
- **WHEN** `XDG_DATA_HOME=/tmp/x` and a run completes
- **THEN** its ledger exists under `/tmp/x/dsort/history/`

### Requirement: Run identifiers sort chronologically
Each run SHALL have a unique run ID that begins with its UTC start time in `YYYYMMDDTHHMMSSZ` form followed by a random suffix.

#### Scenario: Two runs in the same second
- **WHEN** two runs start within the same second
- **THEN** their run IDs differ and both ledgers exist

### Requirement: Plan is durable before any move
The system SHALL write every planned move and folder creation to the ledger and flush it to stable storage before performing the first move or folder creation of the run.

#### Scenario: Crash right after the first move
- **WHEN** the process is killed after moving the first of 30 files
- **THEN** the ledger lists all 30 planned moves with their source, destination, and file identity

### Requirement: Each move records file identity
For each move the ledger SHALL record the source path, planned destination path, the volume ID, inode number, birth time, document identifier, and whether dsort set the tracked flag.

#### Scenario: Identity fields present
- **WHEN** a run moves `invoice.pdf`
- **THEN** its ledger entry contains the source, destination, volume ID, inode, birth time, document ID, and `trackedByUs`

### Requirement: Actual destinations are recorded
When a move lands at a name different from the planned destination, the system SHALL record the actual destination and flush it to stable storage before attempting that move.

#### Scenario: Suffix chosen at move time
- **WHEN** `doc.pdf` is moved as `doc (1).pdf` because the planned name was taken
- **THEN** the ledger records `doc (1).pdf` as the destination for that entry

### Requirement: Outcomes and completion are recorded
The ledger SHALL record each move's outcome (done or failed with reason) and SHALL end with a commit record giving success and failure counts when the run finishes.

#### Scenario: Completed run
- **WHEN** a run finishes with 41 moves done and 1 failed
- **THEN** the ledger ends with a commit record showing 41 done and 1 failed

### Requirement: Ledgers are append-only
The system SHALL never rewrite or truncate an existing ledger. Undo and recovery SHALL record their effects in their own new ledgers that reference the run they act on.

#### Scenario: Undo leaves the original ledger intact
- **WHEN** a run is undone
- **THEN** the original ledger is byte-for-byte unchanged and a new undo ledger references it

### Requirement: Truncated records are tolerated
When reading a ledger, the system SHALL ignore an incomplete final record and treat the run as interrupted if no commit record follows its plan.

#### Scenario: Power loss mid-write
- **WHEN** a ledger ends with half a JSON record and no commit record
- **THEN** `dsort history` lists that run as `interrupted` and the readable records are used

### Requirement: Run history listing
`dsort history` SHALL list runs newest first with run ID, kind (sort, undo, recover), start time, counts, and state (committed, interrupted, reverted), and accept `--limit N`.

#### Scenario: Reverted run is marked
- **WHEN** a sort run was later undone
- **THEN** `dsort history` shows that sort run with state `reverted`

### Requirement: Single run details
`dsort show RUN_ID` SHALL print every recorded move of that run with its outcome and actual destination.

#### Scenario: Unknown run ID
- **WHEN** the user runs `dsort show nosuchrun`
- **THEN** dsort exits 64 and reports that the run was not found

### Requirement: Interrupted runs can be reconciled
`dsort recover` SHALL find interrupted runs, determine for each planned move whether the file is at its source or destination by checking file identity, and record the result so the run can be undone like a committed run.

#### Scenario: Recover after a crash
- **WHEN** a run was killed after 12 of 30 moves and the user runs `dsort recover`
- **THEN** 12 entries are recorded as moved, 18 as not moved, and the run becomes eligible for undo

### Requirement: Interrupted runs block new sorts
The system SHALL refuse to start a new `run` while an interrupted run exists, exit 1, and tell the user to run `dsort recover`.

#### Scenario: Sort after crash
- **WHEN** an interrupted run exists and the user runs `dsort run`
- **THEN** no moves are made and the message names `dsort recover`
