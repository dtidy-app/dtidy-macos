# Spec Delta

## MODIFIED Requirements

### Requirement: Default locations on macOS
On macOS the default root folder SHALL be `~/Desktop`. The platform data directory SHALL be `~/Library/Application Support/dtidy`, and the platform config file SHALL be `~/.config/dtidy/config.json`. Either one is overridden by its XDG variable when that variable is set and non-empty.

#### Scenario: Default ledger location
- **WHEN** `XDG_DATA_HOME` is unset and a run completes
- **THEN** its ledger exists under `~/Library/Application Support/dtidy/history/`

#### Scenario: Default config location
- **WHEN** `XDG_CONFIG_HOME` is unset and no `--config` is given
- **THEN** `dtidy config path` reports `~/.config/dtidy/config.json`

### Requirement: Document tracking on macOS
On macOS, enabling document tracking SHALL mean setting the `UF_TRACKED` flag. dtidy SHALL set it only on files that lack it, record `trackedByUs`, and never clear it, including during undo.

#### Scenario: Flag set before the move and kept after undo
- **WHEN** an untracked `notes.txt` is sorted and later restored by undo
- **THEN** it carries `UF_TRACKED` after both steps and the ledger records `trackedByUs: true`

### Requirement: Privacy permissions on macOS
When macOS privacy controls (TCC) deny access to the root folder, the message SHALL name the responsible app and how to grant access. The app is the terminal when `TERM_PROGRAM` identifies one, otherwise the dtidy binary. Access is granted under System Settings > Privacy & Security > Files and Folders or Full Disk Access, and the message SHALL include a command that opens that pane.

#### Scenario: Terminal lacks Desktop access
- **WHEN** reading `~/Desktop` from Terminal fails with `Operation not permitted`
- **THEN** dtidy exits 77 and the message names Terminal and the Privacy & Security pane

#### Scenario: launchd agent lacks access
- **WHEN** the same failure happens with no `TERM_PROGRAM` set
- **THEN** the message names the dtidy binary's path

### Requirement: No Apple Events on macOS
On macOS, dtidy SHALL NOT send Apple Events or run AppleScript, and SHALL NOT require Automation permission. Finder picks up renames by other processes without a refresh request.

#### Scenario: Run under launchd
- **WHEN** dtidy runs as a `launchd` agent
- **THEN** no Automation permission prompt or Apple Events error can occur
