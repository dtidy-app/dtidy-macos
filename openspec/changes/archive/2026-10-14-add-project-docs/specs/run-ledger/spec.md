# Spec Delta

## MODIFIED Requirements

### Requirement: Ledger location
The system SHALL store run ledgers in `<data directory>/history/`, with one file per run named by its run ID. The data directory is `$XDG_DATA_HOME/dsort` when `XDG_DATA_HOME` is set and non-empty, otherwise the platform's per-user application data location for dsort.

#### Scenario: Default location
- **WHEN** `XDG_DATA_HOME` is unset and a run completes
- **THEN** its ledger exists under the platform's data directory for dsort, in `history/`

#### Scenario: XDG override
- **WHEN** `XDG_DATA_HOME=/tmp/x` and a run completes
- **THEN** its ledger exists under `/tmp/x/dsort/history/`

### Requirement: Each move records file identity
For each move the ledger SHALL record:
- the source path and the planned destination path;
- the file identity: volume identifier, file identifier, and creation time;
- the file's document identity (0 when the platform or file has none);
- whether dsort enabled document tracking for the file.

#### Scenario: Identity fields present
- **WHEN** a run moves `invoice.pdf`
- **THEN** its ledger entry contains the source, destination, volume identifier, file identifier, creation time, document identity, and `trackedByUs`

### Requirement: Run history listing
`dsort history` SHALL list runs newest first and accept `--limit N`. Each run shows its run ID, kind (sort, undo, recover), start time, and counts. It also shows its state: `committed`, `interrupted`, `recovered`, `partially-reverted`, or `reverted`.

#### Scenario: Reverted run is marked
- **WHEN** a sort run was later undone
- **THEN** `dsort history` shows that sort run with state `reverted`

#### Scenario: Recovered run is marked
- **WHEN** an interrupted sort run was reconciled with `dsort recover`
- **THEN** `dsort history` shows it with state `recovered` until it is undone

## ADDED Requirements

### Requirement: Runs without moves write no ledger
A run whose plan contains no moves SHALL NOT create a ledger file. A schedule that finds nothing to sort therefore leaves the history unchanged.

#### Scenario: Nothing to sort
- **WHEN** `dsort run` finds only skipped items
- **THEN** it reports that there is nothing to sort and no new ledger file exists
