# Spec Delta

## MODIFIED Requirements

### Requirement: Default undo target
`dtidy undo` without arguments SHALL target the most recent sort run that is committed or recovered and not fully reverted. `dtidy undo RUN_ID` SHALL target that sort run. Undo and recover runs SHALL NOT be undo targets.

#### Scenario: Undo after two sorts
- **WHEN** runs A then B were sorted and the user runs `dtidy undo`
- **THEN** run B is reversed and run A is untouched

#### Scenario: Nothing to undo
- **WHEN** every sort run is already reverted
- **THEN** dtidy reports that there is nothing to undo and exits 0

### Requirement: Replaced files require explicit consent
When a file exists at the recorded destination but does not match the recorded identity and the recorded file cannot be found elsewhere, the system SHALL report the entry as `replaced` and leave it in place, unless `--by-path` is given, in which case it SHALL restore whatever file is at the recorded destination.

#### Scenario: Default refuses to guess
- **WHEN** the file at the recorded destination has a different identity
- **THEN** it stays in place and is reported as `replaced`

#### Scenario: User opts into path-based restore
- **WHEN** the same situation occurs and the user runs `dtidy undo --by-path`
- **THEN** the file at the recorded destination is restored to the Desktop

### Requirement: Partial undo can be retried
An undo that leaves entries unresolved SHALL mark the target run as partially reverted, and a later `dtidy undo RUN_ID` SHALL retry only the unresolved entries.

#### Scenario: Retry after granting access
- **WHEN** one entry was `inaccessible` and the user grants access and runs `dtidy undo RUN_ID` again
- **THEN** that entry is restored and the run becomes fully reverted

### Requirement: Tracked flag is left in place
Undo SHALL NOT turn off document tracking that dtidy enabled on a file.

#### Scenario: Flag survives undo
- **WHEN** a file for which dtidy enabled document tracking is restored
- **THEN** document tracking is still enabled for it

### Requirement: Undo dry run
`dtidy undo --dry-run` SHALL print, for each entry, where the file was found and what would happen, without changing any file, folder, or ledger.

#### Scenario: Preview an undo
- **WHEN** the user runs `dtidy undo --dry-run`
- **THEN** each entry shows its planned outcome and the filesystem is unchanged

### Requirement: Undo outcome and exit code
Undo SHALL report counts per outcome: `restored`, `restored-renamed`, `already-restored`, `in-trash`, `missing`, `inaccessible`, `replaced`, `skipped-conflict`, `failed`. It SHALL exit 0 only when every entry was restored or already restored, otherwise 1.

#### Scenario: One file missing
- **WHEN** 19 entries are restored and one is `missing`
- **THEN** dtidy exits 1 and lists the missing entry

#### Scenario: Rename fails for another reason
- **WHEN** restoring an entry fails with an error other than a name conflict
- **THEN** the entry is reported as `failed` with the error and dtidy exits 1
