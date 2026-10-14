# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Collisions get Finder-style suffixes`
- TO: `### Requirement: Collisions get numbered suffixes`

- FROM: `### Requirement: No Finder scripting`
- TO: `### Requirement: No file-manager scripting`

## MODIFIED Requirements

### Requirement: Collisions get numbered suffixes
When a destination name is taken, the system SHALL try `name (1).ext`, `name (2).ext`, and so on. It SHALL keep known compound extensions (such as `.tar.gz`) and package extensions intact. It SHALL keep the resulting name within 255 bytes of UTF-8 by shortening the base name.

#### Scenario: Compound extension is preserved
- **WHEN** `backup.tar.gz` collides in `Archives/`
- **THEN** it is moved as `Archives/backup (1).tar.gz`

#### Scenario: Name taken between planning and moving
- **WHEN** another process creates the planned destination name after the plan is made
- **THEN** the move uses the next free suffix and the actual name is recorded in the ledger

### Requirement: Moved files are marked as tracked
Some platforms keep a document identity across later safe saves only when tracking is turned on for the file. On those platforms the system SHALL turn tracking on before moving each file, if it is not already on, and SHALL record whether dsort did so. If turning tracking on fails, the file SHALL still be moved and recorded with document identity 0.

#### Scenario: Untracked file gains a document identity
- **WHEN** an untracked `notes.txt` is moved on a platform with opt-in document tracking
- **THEN** after the move it has a non-zero document identity, and the ledger records `trackedByUs: true`

#### Scenario: Tracking unavailable
- **WHEN** tracking cannot be enabled for a file
- **THEN** the file is moved and its ledger entry records document identity 0 and `trackedByUs: false`

### Requirement: Permission failures are explained
When the operating system's access controls deny access to the root folder, the system SHALL exit with code 77. It SHALL print which app or binary needs permission and where the user grants it.

#### Scenario: Terminal lacks Desktop access
- **WHEN** reading the root folder from a terminal fails because the operating system denies access
- **THEN** dsort exits 77 and names the app or binary that needs access and where to grant it

### Requirement: No file-manager scripting
The system SHALL NOT script or automate the platform's file manager or desktop shell, and SHALL NOT require automation permissions. The file manager is expected to notice moves on its own.

#### Scenario: Run under launchd
- **WHEN** dsort runs from the platform's scheduler (such as `launchd` on macOS) with no user interaction
- **THEN** no automation permission prompt or scripting error can occur
