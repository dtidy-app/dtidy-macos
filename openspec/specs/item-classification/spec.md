# item-classification Specification

## Purpose

Decides which items on the top level of the Desktop are eligible for sorting and which bucket folder each eligible item belongs in, without reading file contents.

## Requirements

### Requirement: Top-level scanning only
The system SHALL consider only the direct children of the configured root folder (default `~/Desktop`) and SHALL NOT descend into subfolders.

#### Scenario: Nested file is ignored
- **WHEN** `~/Desktop/Project/report.pdf` exists and the Desktop is sorted
- **THEN** `report.pdf` is neither classified nor moved

### Requirement: Hidden items are skipped
The system SHALL skip every item whose name begins with `.`.

#### Scenario: Hidden file stays in place
- **WHEN** `~/Desktop/.DS_Store` and `~/Desktop/.localized` exist
- **THEN** both are skipped with reason `hidden`

### Requirement: In-progress downloads are skipped
The system SHALL skip items matching the configured skip globs, which by default are `*.download`, `*.crdownload`, and `*.part`.

#### Scenario: Partial Chrome download stays in place
- **WHEN** `~/Desktop/installer.dmg.crdownload` exists
- **THEN** it is skipped with reason `skip-glob`

### Requirement: Plain folders are skipped by default
The system SHALL skip directories that are not packages unless the configuration enables folder sorting. Packages (such as `.app`, `.rtfd`, `.key`) SHALL be treated as single files, determined by the system package attribute rather than by the presence of a dot in the name.

#### Scenario: User folder stays in place
- **WHEN** `~/Desktop/toolkit-0.12.0-beta/` is a plain directory and folder sorting is not enabled
- **THEN** it is skipped with reason `folder`

#### Scenario: Application bundle is sorted as a file
- **WHEN** `~/Desktop/Tool.app` is an application package
- **THEN** it is classified like any other file

### Requirement: Symbolic links are skipped
The system SHALL skip symbolic links and SHALL NOT follow them.

#### Scenario: Symlink stays in place
- **WHEN** `~/Desktop/notes` is a symbolic link to another folder
- **THEN** it is skipped with reason `symlink` and its target is not inspected

### Requirement: Recently modified items are skipped
The system SHALL skip items whose modification time is newer than the configured minimum age (default 10 seconds), so files still being written are not moved.

#### Scenario: Fresh screenshot waits for the next run
- **WHEN** a screenshot was written 3 seconds before the run
- **THEN** it is skipped with reason `too-recent`

### Requirement: Never-move patterns are honored
The system SHALL skip items whose names match any configured never-move glob.

#### Scenario: Password database stays in place
- **WHEN** the configuration lists `*.kdbx` as never-move and `~/Desktop/vault.kdbx` exists
- **THEN** it is skipped with reason `never-move`

### Requirement: Bucket folders are never sorted
The system SHALL skip any top-level item whose name equals the first path component of a configured bucket destination or the fallback bucket.

#### Scenario: Existing bucket folder stays in place
- **WHEN** `~/Desktop/Images/` exists and `Images` is a configured bucket
- **THEN** it is skipped with reason `bucket`

### Requirement: Screenshots are detected by system metadata
The system SHALL classify an item as a screenshot when its `com.apple.metadata:kMDItemIsScreenCapture` extended attribute decodes to boolean true, regardless of its file name or language, and route it to the screenshot triage bucket (default `Images/_Screenshots`).

#### Scenario: Renamed screenshot is still detected
- **WHEN** a screenshot carrying the screen-capture attribute was renamed to `diagram.png`
- **THEN** it is routed to `Images/_Screenshots`

### Requirement: Screenshots are detected by localized name as a fallback
The system SHALL classify an item without the screen-capture attribute as a screenshot when its Unicode-NFC-normalized name matches a configured screenshot name pattern. The defaults SHALL cover at least English, Turkish, German, and French macOS screenshot names.

#### Scenario: Exported screenshot copy is detected by name
- **WHEN** `Screenshot 2026-08-24 at 22.11.28.jpg` has no screen-capture attribute
- **THEN** it is routed to `Images/_Screenshots`

#### Scenario: Decomposed accented name still matches
- **WHEN** a file named `Capture d’écran 2026-01-02 à 10.00.00.png` is stored with a decomposed `é`
- **THEN** it matches the French screenshot pattern

### Requirement: Camera imports are triaged
The system SHALL route items whose names match the configured camera patterns (defaults include `IMG_`, `DSC_`, `DSCF`, and `PXL_` followed by digits) to the camera triage bucket (default `Images/_Inbox`).

#### Scenario: Phone photo goes to the inbox
- **WHEN** `~/Desktop/IMG_4821.HEIC` exists
- **THEN** it is routed to `Images/_Inbox`

### Requirement: Extension overrides precede type detection
The system SHALL check user-configured extension mappings, compared case-insensitively, before system type conformance.

#### Scenario: TypeScript file is not treated as video
- **WHEN** `.ts` is mapped to `Code` in the configuration and `~/Desktop/app.ts` exists
- **THEN** it is routed to `Code`, not to the bucket for movies

### Requirement: System type conformance decides categories
The system SHALL determine an item's type from its file name extension without reading its contents, and route it to the first configured category whose type identifiers the item's type conforms to.

#### Scenario: PDF is routed by type
- **WHEN** `~/Desktop/invoice.pdf` exists and a category maps `com.adobe.pdf` to `PDFs`
- **THEN** it is routed to `PDFs`

### Requirement: Unmatched items go to the fallback bucket
The system SHALL route eligible items that match no triage rule, extension override, or category to the fallback bucket (default `Other`).

#### Scenario: Unknown extension falls back
- **WHEN** `~/Desktop/data.xyz123` exists and nothing maps its type
- **THEN** it is routed to `Other`

### Requirement: Rule order is deterministic
The system SHALL evaluate rules in this order and stop at the first match: skip rules, screenshot metadata, triage name rules in configured order, extension overrides, type categories in configured order, fallback.

#### Scenario: Screenshot beats generic image category
- **WHEN** a screenshot PNG matches both the screenshot rule and the `Images` category
- **THEN** it is routed to `Images/_Screenshots`
