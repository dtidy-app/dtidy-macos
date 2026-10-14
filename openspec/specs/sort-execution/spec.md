# sort-execution Specification

## Purpose

Turns classification results into a plan and carries it out with atomic, non-destructive moves, so that a sort run can never overwrite, delete, or duplicate a user's file.

## Requirements

### Requirement: Dry run shows the plan without side effects
`dtidy plan` and `dtidy run --dry-run` SHALL print every planned move, every folder to be created, and every skipped item with its reason, and SHALL NOT create, move, or modify any file, folder, flag, ledger, or lock.

#### Scenario: Plan leaves the Desktop untouched
- **WHEN** the user runs `dtidy plan` on a Desktop with 20 eligible files
- **THEN** 20 moves are listed and the Desktop, bucket folders, and data directory are unchanged

### Requirement: Machine-readable output
The `run`, `plan`, `undo`, `history`, and `show` commands SHALL accept `--json` and then write a single JSON document describing the result to standard output, with human-readable messages going to standard error.

#### Scenario: JSON plan is parseable
- **WHEN** the user runs `dtidy plan --json`
- **THEN** standard output parses as JSON containing the planned moves and skips

### Requirement: Moves never overwrite
The system SHALL move items only with an atomic rename that fails if the destination name exists, including names that differ only by letter case on case-insensitive volumes. It SHALL NOT overwrite, delete, or copy user files.

#### Scenario: Case-variant destination is not replaced
- **WHEN** `Doc.pdf` is to be moved into `PDFs/` and `PDFs/doc.PDF` already exists
- **THEN** `PDFs/doc.PDF` is unchanged and `Doc.pdf` is moved under a suffixed name

### Requirement: Collisions get numbered suffixes
When a destination name is taken, the system SHALL try `name (1).ext`, `name (2).ext`, and so on. It SHALL keep known compound extensions (such as `.tar.gz`) and package extensions intact. It SHALL keep the resulting name within 255 bytes of UTF-8 by shortening the base name.

#### Scenario: Compound extension is preserved
- **WHEN** `backup.tar.gz` collides in `Archives/`
- **THEN** it is moved as `Archives/backup (1).tar.gz`

#### Scenario: Name taken between planning and moving
- **WHEN** another process creates the planned destination name after the plan is made
- **THEN** the move uses the next free suffix and the actual name is recorded in the ledger

### Requirement: Cross-volume moves are refused
The system SHALL NOT move an item when the destination is on a different volume, and SHALL report that item as failed with reason `cross-volume`.

#### Scenario: Bucket on another volume
- **WHEN** a destination folder resolves to a mounted external volume
- **THEN** the item stays in place and is reported as failed with reason `cross-volume`

### Requirement: Bucket folders are created on demand
The system SHALL create a bucket folder, including intermediate folders, only when at least one item is moved into it, and SHALL record each folder it created.

#### Scenario: No screenshots, no screenshot folder
- **WHEN** a run moves no screenshots
- **THEN** `Images/_Screenshots/` is not created

### Requirement: Moved files are marked as tracked
Some platforms keep a document identity across later safe saves only when tracking is turned on for the file. On those platforms the system SHALL turn tracking on before moving each file, if it is not already on, and SHALL record whether dtidy did so. If turning tracking on fails, the file SHALL still be moved and recorded with document identity 0.

#### Scenario: Untracked file gains a document identity
- **WHEN** an untracked `notes.txt` is moved on a platform with opt-in document tracking
- **THEN** after the move it has a non-zero document identity, and the ledger records `trackedByUs: true`

#### Scenario: Tracking unavailable
- **WHEN** tracking cannot be enabled for a file
- **THEN** the file is moved and its ledger entry records document identity 0 and `trackedByUs: false`

### Requirement: Single concurrent run
The system SHALL hold an exclusive lock for the duration of any `run`, `undo`, or `recover`. If another dtidy process holds the lock, the command SHALL exit with code 75 without changing anything.

#### Scenario: Overlapping launchd and manual run
- **WHEN** a `launchd` run is in progress and the user starts `dtidy run`
- **THEN** the second command exits with code 75 and the Desktop is unchanged by it

### Requirement: Permission failures are explained
When the operating system's access controls deny access to the root folder, the system SHALL exit with code 77. It SHALL print which app or binary needs permission and where the user grants it.

#### Scenario: Terminal lacks Desktop access
- **WHEN** reading the root folder from a terminal fails because the operating system denies access
- **THEN** dtidy exits 77 and names the app or binary that needs access and where to grant it

### Requirement: Exit codes report outcome
The system SHALL exit 0 when every planned action succeeded, 1 when some items failed or were left unresolved, 64 for usage or configuration errors, 75 when the lock is held, and 77 for permission errors.

#### Scenario: One file fails
- **WHEN** 9 of 10 planned moves succeed and one fails
- **THEN** dtidy exits 1 and reports the failed item and its reason

### Requirement: Environment diagnostics
`dtidy doctor` SHALL report, without changing anything, whether the root folder is readable, whether its volume supports exclusive rename and path lookup by file ID, whether the lock is held, where the config and data directories are, and whether the config is valid.

#### Scenario: Doctor on a healthy setup
- **WHEN** the user runs `dtidy doctor` with Desktop access granted
- **THEN** every check is reported as passing and the exit code is 0

### Requirement: No file-manager scripting
The system SHALL NOT script or automate the platform's file manager or desktop shell, and SHALL NOT require automation permissions. The file manager is expected to notice moves on its own.

#### Scenario: Run under launchd
- **WHEN** dtidy runs from the platform's scheduler (such as `launchd` on macOS) with no user interaction
- **THEN** no automation permission prompt or scripting error can occur
