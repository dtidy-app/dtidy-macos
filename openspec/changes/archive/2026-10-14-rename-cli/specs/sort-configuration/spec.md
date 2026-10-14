# Spec Delta

## MODIFIED Requirements

### Requirement: Config file location
The system SHALL read configuration from the first of these that applies:
1. the path given by `--config`;
2. `$XDG_CONFIG_HOME/dtidy/config.json`, when `XDG_CONFIG_HOME` is set and non-empty;
3. the platform's per-user config file for dtidy.

#### Scenario: Explicit path wins
- **WHEN** the user runs `dtidy plan --config ./alt.json`
- **THEN** rules from `./alt.json` are used even if the platform's default config file exists

### Requirement: Built-in defaults without a file
When no config file exists, the system SHALL use built-in defaults. They SHALL include:
- root: the user's Desktop folder;
- minimum age 10 seconds;
- folder sorting off;
- skip globs for in-progress downloads;
- screenshot triage to `Images/_Screenshots`, and camera triage to `Images/_Inbox`;
- categories for images, movies, audio, PDFs, source code, documents, and archives and disk images;
- fallback `Other`.

#### Scenario: First run without config
- **WHEN** no config file exists and the user runs `dtidy plan`
- **THEN** the plan uses the default buckets and no error is reported

#### Scenario: Office document has a default bucket
- **WHEN** no config file exists and `~/Desktop/report.docx` is sorted
- **THEN** it is routed to `Documents`

### Requirement: Validation before any action
The system SHALL validate the config before scanning and, on any error, exit 64 with the field path and reason, changing nothing. Validation SHALL reject: unknown `version`; unknown fields; regular expressions that do not compile; unrecognized type identifiers; destinations that are absolute, empty, or contain `.` or `..` components; and a root that does not exist.

#### Scenario: Path escape is rejected
- **WHEN** a category destination is `../Documents`
- **THEN** dtidy exits 64 naming that category's destination as invalid

#### Scenario: Bad regular expression
- **WHEN** a triage rule's pattern is `^(Screenshot`
- **THEN** dtidy exits 64 naming that rule and the compile error

### Requirement: Config commands
`dtidy config path` SHALL print the config path in effect and whether the file exists. `dtidy config init` SHALL write the built-in defaults as a config file and SHALL refuse to overwrite an existing file. `dtidy config validate` SHALL report validation results without scanning.

#### Scenario: Init does not overwrite
- **WHEN** a config file already exists and the user runs `dtidy config init`
- **THEN** the existing file is unchanged and dtidy exits 64 with a message that the file exists

#### Scenario: Init output is valid
- **WHEN** the user runs `dtidy config init` with no existing file and then `dtidy config validate`
- **THEN** validation passes
