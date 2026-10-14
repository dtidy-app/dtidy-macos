# Spec Delta

## Purpose

Makes dtidy self-documenting: every command explains itself with a summary, a discussion and examples, the top-level help summarizes exit codes and file locations, and the man page carries the same text.

## ADDED Requirements

### Requirement: Help entry points
`dtidy --help`, `dtidy -h`, `dtidy help [COMMAND [SUBCOMMAND]]` and `--help` or `-h` after any command or subcommand SHALL print that command's help on stdout and exit 0. Showing help SHALL NOT read the config file or the root folder, or create, modify or delete any file, folder, ledger or lock.

#### Scenario: Help for a nested subcommand
- **WHEN** the user runs `dtidy help config init`
- **THEN** the help for `config init` is printed on stdout and the exit code is 0

#### Scenario: Help without access to the Desktop
- **WHEN** the terminal lacks Desktop access and the user runs `dtidy run --help`
- **THEN** the help is printed, the exit code is 0, and no permission error is reported

### Requirement: Every command documents itself
The help of every command and subcommand SHALL include a one-line summary, a discussion of what it does and when to use it, and at least one example command line with a short explanation.

#### Scenario: Undo help shows examples
- **WHEN** the user runs `dtidy undo --help`
- **THEN** the output includes a discussion of how files are found and put back, and examples of undoing the latest run, a specific run ID, and a dry run

#### Scenario: A command without examples is caught
- **WHEN** a command is added without a discussion or an example
- **THEN** the test suite fails, naming that command

### Requirement: Top-level help summarizes outcomes and locations
The top-level help SHALL list every exit code with its meaning: 0, 1, 64, 75 and 77. It SHALL also name the config file and data directory locations, including their XDG overrides, and point to `dtidy doctor` to show the locations in effect.

#### Scenario: Exit codes in the overview
- **WHEN** the user runs `dtidy --help`
- **THEN** the output lists exit codes 0, 1, 64, 75 and 77 with their meanings, and names `~/.config/dtidy/config.json` and `~/Library/Application Support/dtidy`

### Requirement: Man page mirrors the help
A man page in section 1, `dtidy.1`, SHALL document every command, subcommand, argument and option with the same summaries, discussions and examples as the help output. The man page that is shipped SHALL match the help of the build it ships with.

#### Scenario: Reading the manual
- **WHEN** dtidy and its man page are installed and the user runs `man dtidy`
- **THEN** the page shows the top-level overview with exit codes, and a section for every command including `config init`, `config path` and `config validate`

#### Scenario: Stale man page is detected
- **WHEN** a command's help text changes and the man page is not regenerated
- **THEN** the man page staleness check fails and names the difference
