# Spec Delta

## MODIFIED Requirements

### Requirement: Config file location
The system SHALL read configuration from the first of these that applies:
1. the path given by `--config`;
2. `$XDG_CONFIG_HOME/dsort/config.json`, when `XDG_CONFIG_HOME` is set and non-empty;
3. the platform's per-user config file for dsort.

#### Scenario: Explicit path wins
- **WHEN** the user runs `dsort plan --config ./alt.json`
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
- **WHEN** no config file exists and the user runs `dsort plan`
- **THEN** the plan uses the default buckets and no error is reported

#### Scenario: Office document has a default bucket
- **WHEN** no config file exists and `~/Desktop/report.docx` is sorted
- **THEN** it is routed to `Documents`

### Requirement: Config file format
The config SHALL be a JSON object with a required integer `version` (currently `1`). Its other fields are `root`, `minAgeSeconds`, `sortFolders`, `skipGlobs`, `neverMove`, `triage`, `categories`, and `fallback`:
- `triage` is an ordered list of rules, each with a name, a match (the screen-capture marker or a regular expression), and a destination.
- `categories` is an ordered list, each with a destination and extensions and/or platform type identifiers.

#### Scenario: Minimal valid file
- **WHEN** the config file is `{"version": 1}`
- **THEN** it is valid, and every other field takes its documented default except rule lists, which are empty
