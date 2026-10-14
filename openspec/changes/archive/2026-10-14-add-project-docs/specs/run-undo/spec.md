# Spec Delta

## MODIFIED Requirements

### Requirement: File identity matching
A file SHALL be considered the recorded file in either of two cases:
- its volume identifier, file identifier, and creation time all equal the recorded values;
- its document identity is non-zero and equals the recorded one.

#### Scenario: Safe-saved file still matches
- **WHEN** an app safe-saved a moved file, giving it a new file identifier but the same document identity
- **THEN** undo treats it as the recorded file

#### Scenario: Reused inode does not match
- **WHEN** the file identifier at a path equals the recorded one but the creation time and document identity differ
- **THEN** undo does not treat it as the recorded file

### Requirement: Locating moved files
For each entry, the system SHALL look for the recorded file in this order:
1. at its recorded destination;
2. at the current path the platform reports for its file identifier, where the platform supports that lookup;
3. by document identity, among the bucket folders the run created or used.

#### Scenario: User renamed the file after sorting
- **WHEN** `PDFs/invoice.pdf` was renamed by the user to `PDFs/paid/invoice-2026.pdf`
- **THEN** undo moves `PDFs/paid/invoice-2026.pdf` back to `~/Desktop/invoice.pdf`

#### Scenario: User moved and then edited the file
- **WHEN** a sorted file was moved within the bucket folders and later safe-saved
- **THEN** undo finds it by document identity and restores it

### Requirement: Trashed files are not restored
When the recorded file is found inside the platform's trash, the system SHALL leave it in place and report it as `in-trash` with its current path.

#### Scenario: User trashed a sorted file
- **WHEN** a sorted file is now in the platform's trash
- **THEN** it stays there and undo reports `in-trash` with that path

### Requirement: Empty bucket folders are removed
After restoring files, the system SHALL remove folders that the target run created, deepest first, only if they are empty, and SHALL leave non-empty folders in place. A folder holding nothing but the platform's folder-metadata file counts as empty.

#### Scenario: Folder still holds a user file
- **WHEN** the user saved a new file into `Images/` after the sort and the run is undone
- **THEN** `Images/` and the new file remain

#### Scenario: Folder holds only metadata
- **WHEN** after restoring, a folder the run created contains only the platform's folder-metadata file
- **THEN** the folder is removed

### Requirement: Tracked flag is left in place
Undo SHALL NOT turn off document tracking that dsort enabled on a file.

#### Scenario: Flag survives undo
- **WHEN** a file for which dsort enabled document tracking is restored
- **THEN** document tracking is still enabled for it

### Requirement: Undo outcome and exit code
Undo SHALL report counts per outcome: `restored`, `restored-renamed`, `already-restored`, `in-trash`, `missing`, `inaccessible`, `replaced`, `skipped-conflict`, `failed`. It SHALL exit 0 only when every entry was restored or already restored, otherwise 1.

#### Scenario: One file missing
- **WHEN** 19 entries are restored and one is `missing`
- **THEN** dsort exits 1 and lists the missing entry

#### Scenario: Rename fails for another reason
- **WHEN** restoring an entry fails with an error other than a name conflict
- **THEN** the entry is reported as `failed` with the error and dsort exits 1
