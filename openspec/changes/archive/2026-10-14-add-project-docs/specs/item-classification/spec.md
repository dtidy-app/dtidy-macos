# Spec Delta

## MODIFIED Requirements

### Requirement: Top-level scanning only
The system SHALL consider only the direct children of the configured root folder (default: the user's Desktop folder, located as the platform defines) and SHALL NOT descend into subfolders.

#### Scenario: Nested file is ignored
- **WHEN** `~/Desktop/Project/report.pdf` exists and the Desktop is sorted
- **THEN** `report.pdf` is neither classified nor moved

### Requirement: Plain folders are skipped by default
The system SHALL skip directories unless the configuration enables folder sorting. A directory that the platform presents as a single document (a package or bundle) SHALL be treated as a file. Whether it is one SHALL be decided by the platform, never by the presence of a dot in the name.

#### Scenario: User folder stays in place
- **WHEN** `~/Desktop/toolkit-0.12.0-beta/` is a plain directory and folder sorting is not enabled
- **THEN** it is skipped with reason `folder`

#### Scenario: Application bundle is sorted as a file
- **WHEN** a directory on the Desktop is one the platform reports as a package, such as an application bundle
- **THEN** it is classified like any other file

### Requirement: Screenshots are detected by system metadata
When the platform provides a screen-capture marker (file metadata its screenshot tool attaches), the system SHALL classify an item carrying that marker as a screenshot, whatever its file name or language. The item SHALL go to the screenshot triage bucket (default `Images/_Screenshots`).

#### Scenario: Renamed screenshot is still detected
- **WHEN** a screenshot carrying the platform's screen-capture marker was renamed to `diagram.png`
- **THEN** it is routed to `Images/_Screenshots`

### Requirement: Screenshots are detected by localized name as a fallback
The system SHALL classify an item without the screen-capture marker as a screenshot when its Unicode-NFC-normalized name matches a configured screenshot name pattern. The defaults SHALL cover the platform's default screenshot names in at least English, Turkish, German, and French.

#### Scenario: Exported screenshot copy is detected by name
- **WHEN** `Screenshot 2026-08-24 at 22.11.28.jpg` has no screen-capture marker
- **THEN** it is routed to `Images/_Screenshots`

#### Scenario: Decomposed accented name still matches
- **WHEN** a file named `Capture d’écran 2026-01-02 à 10.00.00.png` is stored with a decomposed `é`
- **THEN** it matches the French screenshot pattern

### Requirement: System type conformance decides categories
The system SHALL get an item's type from the platform's file type system, using only the file name extension and never the contents. It SHALL route the item to the first configured category containing a type the item's type belongs to (directly or through the platform's type hierarchy).

#### Scenario: PDF is routed by type
- **WHEN** `~/Desktop/invoice.pdf` exists and a category lists the platform's PDF type for `PDFs`
- **THEN** it is routed to `PDFs`

#### Scenario: Contents are not read
- **WHEN** a file named `photo.png` contains PDF data
- **THEN** it is classified as an image by its extension
