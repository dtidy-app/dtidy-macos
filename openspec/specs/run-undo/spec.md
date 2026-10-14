# run-undo Specification

## Purpose

Reverses a recorded sort run by finding each moved file wherever it is now and putting it back on the Desktop, without overwriting anything and without guessing about files it cannot find.

## Requirements

### Requirement: Default undo target
`dsort undo` without arguments SHALL target the most recent sort run that is committed or recovered and not fully reverted. `dsort undo RUN_ID` SHALL target that sort run. Undo and recover runs SHALL NOT be undo targets.

#### Scenario: Undo after two sorts
- **WHEN** runs A then B were sorted and the user runs `dsort undo`
- **THEN** run B is reversed and run A is untouched

#### Scenario: Nothing to undo
- **WHEN** every sort run is already reverted
- **THEN** dsort reports that there is nothing to undo and exits 0

### Requirement: File identity matching
A file SHALL be considered the recorded file if its volume ID, inode number, and birth time all equal the recorded values, or if its document identifier is non-zero and equals the recorded one.

#### Scenario: Safe-saved file still matches
- **WHEN** an app safe-saved a moved file, giving it a new inode but the same document identifier
- **THEN** undo treats it as the recorded file

#### Scenario: Reused inode does not match
- **WHEN** the inode at a path equals the recorded inode but the birth time and document ID differ
- **THEN** undo does not treat it as the recorded file

### Requirement: Locating moved files
For each entry, the system SHALL look for the recorded file first at its recorded destination, then at the current path the kernel reports for its inode, then by document identifier among the bucket folders created or used by the run.

#### Scenario: User renamed the file after sorting
- **WHEN** `PDFs/invoice.pdf` was renamed by the user to `PDFs/paid/invoice-2026.pdf`
- **THEN** undo moves `PDFs/paid/invoice-2026.pdf` back to `~/Desktop/invoice.pdf`

#### Scenario: User moved and then edited the file
- **WHEN** a sorted file was moved within the bucket folders and later safe-saved
- **THEN** undo finds it by document identifier and restores it

### Requirement: Restores never overwrite
The system SHALL restore files only with an atomic rename that fails if the target name exists. If the original name is taken, it SHALL restore as `name (restored).ext`, then `name (restored 2).ext`, and so on, unless `--on-conflict skip` is given, in which case the entry is left in place and reported.

#### Scenario: Original name reused
- **WHEN** a new `~/Desktop/report.pdf` exists and the sorted `report.pdf` is undone
- **THEN** the new file is unchanged and the sorted one returns as `~/Desktop/report (restored).pdf`

### Requirement: Trashed files are not restored
When the recorded file is found inside a Trash folder, the system SHALL leave it in place and report it as `in-trash` with its current path.

#### Scenario: User trashed a sorted file
- **WHEN** a sorted file is now at `~/.Trash/old.pdf`
- **THEN** it stays there and undo reports `in-trash` with that path

### Requirement: Only proven absence counts as missing
The system SHALL report an entry as `missing` only when every lookup positively reports that the file does not exist. Any other lookup failure, such as permission denied, SHALL be reported as `inaccessible` with a hint about folder access, and SHALL NOT be treated as deletion.

#### Scenario: Deleted file
- **WHEN** the sorted file was permanently deleted
- **THEN** undo reports it as `missing` and does not create anything in its place

#### Scenario: File moved into a protected folder
- **WHEN** the path lookup for a sorted file fails with permission denied
- **THEN** undo reports it as `inaccessible`, not `missing`, and suggests granting folder access

### Requirement: Replaced files require explicit consent
When a file exists at the recorded destination but does not match the recorded identity and the recorded file cannot be found elsewhere, the system SHALL report the entry as `replaced` and leave it in place, unless `--by-path` is given, in which case it SHALL restore whatever file is at the recorded destination.

#### Scenario: Default refuses to guess
- **WHEN** the file at the recorded destination has a different identity
- **THEN** it stays in place and is reported as `replaced`

#### Scenario: User opts into path-based restore
- **WHEN** the same situation occurs and the user runs `dsort undo --by-path`
- **THEN** the file at the recorded destination is restored to the Desktop

### Requirement: Already-restored entries are skipped
The system SHALL treat an entry whose recorded file is already at its original Desktop path as complete without moving anything.

#### Scenario: Undo after a crash during undo
- **WHEN** an undo was interrupted and is run again
- **THEN** entries already back on the Desktop are left alone and the rest are restored

### Requirement: Partial undo can be retried
An undo that leaves entries unresolved SHALL mark the target run as partially reverted, and a later `dsort undo RUN_ID` SHALL retry only the unresolved entries.

#### Scenario: Retry after granting access
- **WHEN** one entry was `inaccessible` and the user grants access and runs `dsort undo RUN_ID` again
- **THEN** that entry is restored and the run becomes fully reverted

### Requirement: Empty bucket folders are removed
After restoring files, the system SHALL remove folders that the target run created, deepest first, only if they are empty, and SHALL leave non-empty folders in place.

#### Scenario: Folder still holds a user file
- **WHEN** the user saved a new file into `Images/` after the sort and the run is undone
- **THEN** `Images/` and the new file remain

### Requirement: Tracked flag is left in place
Undo SHALL NOT clear the `UF_TRACKED` flag on restored files.

#### Scenario: Flag survives undo
- **WHEN** a file that dsort marked as tracked is restored
- **THEN** it still carries `UF_TRACKED`

### Requirement: Undo dry run
`dsort undo --dry-run` SHALL print, for each entry, where the file was found and what would happen, without changing any file, folder, or ledger.

#### Scenario: Preview an undo
- **WHEN** the user runs `dsort undo --dry-run`
- **THEN** each entry shows its planned outcome and the filesystem is unchanged

### Requirement: Undo outcome and exit code
Undo SHALL report counts per outcome (restored, restored-renamed, already-restored, in-trash, missing, inaccessible, replaced, skipped-conflict) and exit 0 only when every entry was restored or already restored, otherwise 1.

#### Scenario: One file missing
- **WHEN** 19 entries are restored and one is `missing`
- **THEN** dsort exits 1 and lists the missing entry
