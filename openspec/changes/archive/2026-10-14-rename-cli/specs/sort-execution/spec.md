# Spec Delta

## MODIFIED Requirements

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
