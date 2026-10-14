# platform-macos Specification

## Purpose

Defines how dtidy binds the platform-neutral guarantees of the other capabilities to macOS: default locations, file metadata, document tracking, privacy permissions, and the interaction with Finder.

## Requirements

### Requirement: Default locations on macOS
On macOS the default root folder SHALL be `~/Desktop`. The platform data directory SHALL be `~/Library/Application Support/dtidy`, and the platform config file SHALL be `~/.config/dtidy/config.json`. Either one is overridden by its XDG variable when that variable is set and non-empty.

#### Scenario: Default ledger location
- **WHEN** `XDG_DATA_HOME` is unset and a run completes
- **THEN** its ledger exists under `~/Library/Application Support/dtidy/history/`

#### Scenario: Default config location
- **WHEN** `XDG_CONFIG_HOME` is unset and no `--config` is given
- **THEN** `dtidy config path` reports `~/.config/dtidy/config.json`

### Requirement: Screen-capture marker on macOS
On macOS the screen-capture marker SHALL be the extended attribute `com.apple.metadata:kMDItemIsScreenCapture`, counted only when its value decodes as a property list to boolean true.

#### Scenario: System screenshot carries the marker
- **WHEN** a file created by the macOS screenshot tool still has its `kMDItemIsScreenCapture` attribute set to true
- **THEN** it is classified by the screen-capture marker rule

#### Scenario: Exported copy has no marker
- **WHEN** a screenshot was exported to a new file without the attribute
- **THEN** only the name rules can classify it as a screenshot

### Requirement: Default screenshot names on macOS
On macOS the default screenshot name patterns SHALL match names that start with `Screenshot`, `Screen Shot`, `Ekran Resmi`, `Bildschirmfoto`, or `Capture d’écran` (straight or curly apostrophe) followed by a space and a `YYYY-MM-DD` date.

#### Scenario: Turkish screenshot name
- **WHEN** a file is named `Ekran Resmi 2026-10-14 16.48.54.png`
- **THEN** it matches the default screenshot name pattern

### Requirement: Packages on macOS
On macOS an item SHALL be treated as a single document when the system reports it as a package, such as `.app`, `.rtfd`, or `.key` bundles. A folder whose name merely contains a dot SHALL remain a folder.

#### Scenario: Application bundle is a file
- **WHEN** `~/Desktop/Tool.app` is an application bundle
- **THEN** it is classified like any other file

#### Scenario: Dotted folder name stays a folder
- **WHEN** `~/Desktop/toolkit-0.12.0-beta/` is a plain directory
- **THEN** it is treated as a folder

### Requirement: Type identifiers on macOS
On macOS the platform type system SHALL be Uniform Type Identifiers. An item's type comes from its extension; for a package, the extension is looked up as a package. The `types` entries in the configuration SHALL be declared UTType identifiers such as `public.image` or `com.adobe.pdf`.

#### Scenario: PDF type
- **WHEN** a category lists `com.adobe.pdf` and `~/Desktop/invoice.pdf` exists
- **THEN** the item matches that category

#### Scenario: Undeclared identifier is rejected
- **WHEN** a category lists `com.example.nope`
- **THEN** configuration validation fails for that entry

### Requirement: File identity on macOS
On macOS a file's identity SHALL be its volume's `f_fsid`, its inode number, and its birth time. Its document identity SHALL be the kernel document ID, which exists only while the file carries the `UF_TRACKED` flag.

#### Scenario: Identity recorded per move
- **WHEN** a run moves `invoice.pdf`
- **THEN** its ledger entry records the volume `fsid`, the inode, the birth time, and the document ID

### Requirement: Document tracking on macOS
On macOS, enabling document tracking SHALL mean setting the `UF_TRACKED` flag. dtidy SHALL set it only on files that lack it, record `trackedByUs`, and never clear it, including during undo.

#### Scenario: Flag set before the move and kept after undo
- **WHEN** an untracked `notes.txt` is sorted and later restored by undo
- **THEN** it carries `UF_TRACKED` after both steps and the ledger records `trackedByUs: true`

### Requirement: Trash locations on macOS
On macOS a path SHALL count as being in the trash when it contains a `/.Trash/` or `/.Trashes/` component.

#### Scenario: User trash
- **WHEN** a sorted file is found at `~/.Trash/old.pdf`
- **THEN** undo reports it as `in-trash`

### Requirement: Folder-metadata file on macOS
On macOS the folder-metadata file SHALL be Finder's `.DS_Store`. When a folder that would otherwise be empty holds only that file, undo deletes it so the folder can be removed.

#### Scenario: Folder opened in Finder
- **WHEN** a bucket folder created by the run contains only `.DS_Store` after its files are restored
- **THEN** undo removes the `.DS_Store` and the folder

### Requirement: Hidden items on macOS
On macOS an item SHALL be hidden exactly when its name begins with `.`. The `UF_HIDDEN` flag SHALL NOT make an item hidden.

#### Scenario: Flag-hidden file is sorted
- **WHEN** `~/Desktop/report.pdf` has the `UF_HIDDEN` flag but no leading dot
- **THEN** it is classified like any other file

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
