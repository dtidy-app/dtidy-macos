# Spec Delta

## Purpose

Lets users complete dtidy's commands, options, values, paths and run IDs with Tab in zsh, bash and fish, without completion ever changing state or printing errors.

## ADDED Requirements

### Requirement: Completion scripts for supported shells
`dtidy --generate-completion-script SHELL` SHALL print a completion script for SHELL on stdout and exit 0, for SHELL `zsh`, `bash` and `fish`. Any other value SHALL exit 64 with a message naming the supported shells.

#### Scenario: zsh script
- **WHEN** the user runs `dtidy --generate-completion-script zsh`
- **THEN** a zsh completion script for `dtidy` is printed on stdout and the exit code is 0

#### Scenario: Unsupported shell
- **WHEN** the user runs `dtidy --generate-completion-script tcsh`
- **THEN** nothing is printed on stdout, dtidy exits 64, and the message names `zsh`, `bash` and `fish`

### Requirement: Commands, options and values complete
With a completion script installed, Tab SHALL complete the subcommands at every level, the options of the command being typed, and the allowed values of options that take a fixed set of values.

#### Scenario: Subcommands
- **WHEN** the user types `dtidy ` and presses Tab
- **THEN** `run`, `plan`, `undo`, `recover`, `history`, `show`, `doctor`, `config` and `help` are offered

#### Scenario: Nested subcommands
- **WHEN** the user types `dtidy config ` and presses Tab
- **THEN** `init`, `path` and `validate` are offered

#### Scenario: Enumerated option value
- **WHEN** the user types `dtidy undo --on-conflict ` and presses Tab
- **THEN** `suffix` and `skip` are offered

### Requirement: Path options complete paths
`--root` SHALL complete directory names, and `--config` SHALL complete files ending in `.json` and directories.

#### Scenario: Root folder
- **WHEN** the user types `dtidy plan --root ~/Dow` and presses Tab
- **THEN** directories such as `~/Downloads/` are offered and regular files are not

#### Scenario: Config file
- **WHEN** the user types `dtidy config validate --config ./` and presses Tab in a folder that contains `alt.json` and `notes.txt`
- **THEN** `alt.json` is offered and `notes.txt` is not

### Requirement: Undo completes undoable run IDs
The run-ID argument of `undo` SHALL complete to the IDs of sort runs that moved at least one file and whose state is `committed`, `recovered` or `partially-reverted`, newest first. These are the same runs `dtidy undo` can choose as its default target. Interrupted and fully reverted runs, and undo and recover runs, SHALL NOT be offered.

#### Scenario: Only undoable runs are offered
- **WHEN** history holds sort run A (`reverted`), sort run B (`committed`), sort run C (`interrupted`), and the undo run that reverted A, and the user types `dtidy undo ` and presses Tab
- **THEN** only B's run ID is offered

#### Scenario: Empty history
- **WHEN** no ledger exists and the user types `dtidy undo ` and presses Tab
- **THEN** no run ID is offered and no error is shown

### Requirement: Show completes every run ID
The run-ID argument of `show` SHALL complete to the IDs of every run in history, of every kind and state, newest first.

#### Scenario: All runs are offered
- **WHEN** history holds a sort run, an undo run and a recover run, and the user types `dtidy show ` and presses Tab
- **THEN** all three run IDs are offered, newest first

### Requirement: Completion has no side effects
Producing completions SHALL NOT create, modify or delete any file, folder, ledger or lock, and SHALL NOT read the config file or the root folder. It reads only the history in the data directory in effect, including an `XDG_DATA_HOME` override. If history cannot be read, it SHALL offer nothing, print nothing on stderr, and exit 0.

#### Scenario: Missing data directory
- **WHEN** the data directory does not exist and run-ID completions are requested
- **THEN** no candidates are returned, the data directory is still absent afterwards, and the exit code is 0

#### Scenario: Unreadable or corrupt ledger
- **WHEN** one ledger file is unreadable or corrupt and run-ID completions are requested
- **THEN** the run IDs from the readable ledgers are offered and nothing is printed on stderr

#### Scenario: Run in progress
- **WHEN** another dtidy process holds the lock and run-ID completions are requested
- **THEN** completions are returned without waiting for the lock
