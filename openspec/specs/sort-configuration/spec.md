# sort-configuration Specification

## Purpose

Lets users customize what dsort sorts and where items go through a single, validated JSON file, while working out of the box with built-in defaults when no file exists.

## Requirements

### Requirement: Config file location
The system SHALL read configuration from the path given by `--config`, otherwise from `$XDG_CONFIG_HOME/dsort/config.json` when `XDG_CONFIG_HOME` is set and non-empty, otherwise from `~/.config/dsort/config.json`.

#### Scenario: Explicit path wins
- **WHEN** the user runs `dsort plan --config ./alt.json`
- **THEN** rules from `./alt.json` are used even if `~/.config/dsort/config.json` exists

### Requirement: Built-in defaults without a file
When no config file exists, the system SHALL use built-in defaults, which SHALL include: root `~/Desktop`; minimum age 10 seconds; folder sorting off; skip globs for in-progress downloads; screenshot triage to `Images/_Screenshots`; camera triage to `Images/_Inbox`; categories for images, movies, audio, PDFs, archives and disk images, and source code; and fallback `Other`.

#### Scenario: First run without config
- **WHEN** no config file exists and the user runs `dsort plan`
- **THEN** the plan uses the default buckets and no error is reported

### Requirement: A config file replaces the defaults
When a config file exists, it SHALL be the complete configuration. Omitted optional fields SHALL take their documented default value, but rule lists SHALL NOT be merged with the built-in lists.

#### Scenario: User removes the camera rule
- **WHEN** the config file's triage list contains only a screenshot rule
- **THEN** files named `IMG_1234.jpg` are classified by type, not routed to `Images/_Inbox`

### Requirement: Config file format
The config SHALL be a JSON object with a required integer `version` (currently `1`) and the fields `root`, `minAgeSeconds`, `sortFolders`, `skipGlobs`, `neverMove`, `triage` (ordered rules with a name, a match by screen-capture metadata or by regular expression, and a destination), `categories` (ordered, each with a destination and extensions and/or type identifiers), and `fallback`.

#### Scenario: Minimal valid file
- **WHEN** the config file is `{"version": 1}`
- **THEN** it is valid, and every other field takes its documented default except rule lists, which are empty

### Requirement: Validation before any action
The system SHALL validate the config before scanning and, on any error, exit 64 with the field path and reason, changing nothing. Validation SHALL reject: unknown `version`; unknown fields; regular expressions that do not compile; unrecognized type identifiers; destinations that are absolute, empty, or contain `.` or `..` components; and a root that does not exist.

#### Scenario: Path escape is rejected
- **WHEN** a category destination is `../Documents`
- **THEN** dsort exits 64 naming that category's destination as invalid

#### Scenario: Bad regular expression
- **WHEN** a triage rule's pattern is `^(Screenshot`
- **THEN** dsort exits 64 naming that rule and the compile error

### Requirement: Home directory expansion
A leading `~` in `root` SHALL expand to the user's home directory.

#### Scenario: Tilde root
- **WHEN** `root` is `~/Desktop`
- **THEN** the scanned folder is the user's Desktop

### Requirement: Config commands
`dsort config path` SHALL print the config path in effect and whether the file exists. `dsort config init` SHALL write the built-in defaults as a config file and SHALL refuse to overwrite an existing file. `dsort config validate` SHALL report validation results without scanning.

#### Scenario: Init does not overwrite
- **WHEN** a config file already exists and the user runs `dsort config init`
- **THEN** the existing file is unchanged and dsort exits 64 with a message that the file exists

#### Scenario: Init output is valid
- **WHEN** the user runs `dsort config init` with no existing file and then `dsort config validate`
- **THEN** validation passes
