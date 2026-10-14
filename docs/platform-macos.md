# dsort on macOS

How the macOS implementation provides each platform-neutral guarantee, and what was verified about macOS along the way.

- **What must hold:** the core specs and `platform-macos` in [`openspec/specs/`](../openspec/specs/).
- **Why the design looks like this:** [architecture.md](architecture.md).
- **Doing the same for another OS:** [porting.md](porting.md).

Verified on macOS 26.6, APFS, Swift 6.4. The minimum supported version is macOS 14; behaviour there has not been verified by hand yet.

## Bindings

Each row names a guarantee by its spec requirement, then the mechanism behind it. Source file paths are under `Sources/`.

### Locations and identity

| Guarantee (spec › requirement) | macOS mechanism | Where | Notes |
|---|---|---|---|
| platform-macos › Default locations on macOS; run-ledger › Ledger location; sort-configuration › Config file location | `~/Desktop`; `~/Library/Application Support/dsort`; `~/.config/dsort/config.json`; `XDG_DATA_HOME` / `XDG_CONFIG_HOME` override | `DSortCore/Paths.swift`, `DSortCore/Config.swift` | The root is resolved with `realpath`, so it matches the `/private/...` paths the kernel reports. |
| platform-macos › File identity on macOS; run-ledger › Each move records file identity | `statfs` → `f_fsid` (two `Int32`s); `lstat` → `st_ino`, `st_birthtimespec` | `DSortIO/FileOps.swift` (`lstat`, `fsid`) | Birth time is stored as seconds since 1970 (double) and compared with 1 µs tolerance. |
| platform-macos › Document tracking on macOS; sort-execution › Moved files are marked as tracked; run-undo › Tracked flag is left in place | `lchflags(path, flags \| UF_TRACKED)`; document ID read with `URLResourceKey.documentIdentifierKey` | `DSortIO/FileOps.swift` (`addTrackedFlag`, `documentID`), `DSortIO/Executor.swift` | A tracking failure does not block the move; the entry is recorded with `docid` 0. |
| run-undo › Locating moved files (path by file ID) | `fsgetpath(buf, len, &fsid, ino)` | `DSortIO/FileOps.swift` (`pathForFile`) | `ENOENT` means gone. Any other error means `inaccessible`. |
| run-undo › Locating moved files (by document identity) | `FileManager.enumerator` prefetching `documentIdentifierKey`, limited to the run's top-level bucket folders | `DSortIO/FileOps.swift` (`findDocument`), `DSortIO/UndoService.swift` | |
| platform-macos › Trash locations on macOS; run-undo › Trashed files are not restored | Path contains `/.Trash/` or `/.Trashes/` | `DSortCore/Reconciler.swift` (`isInTrash`) | |

### Moves and the ledger

| Guarantee (spec › requirement) | macOS mechanism | Where | Notes |
|---|---|---|---|
| sort-execution › Moves never overwrite; run-undo › Restores never overwrite | `renamex_np(from, to, RENAME_EXCL)` | `DSortIO/FileOps.swift` (`renameExclusive`) | `EEXIST` → next collision suffix. `EXDEV` → `cross-volume`. `doctor` checks `VOL_CAP_INT_RENAME_EXCL`. |
| sort-execution › Cross-volume moves are refused | `st_dev` of the bucket folder compared with the root's before each move; `EXDEV` from the rename as a backstop | `DSortIO/Executor.swift` | |
| run-ledger › Plan is durable before any move; run-ledger › Actual destinations are recorded | `fcntl(fd, F_BARRIERFSYNC)`, falling back to `fsync` | `DSortIO/Ledger.swift` (`barrier`) | An ordering barrier, not `F_FULLFSYNC`; see [architecture.md](architecture.md#key-decisions). |
| run-ledger › Ledgers are append-only | `open(O_WRONLY \| O_CREAT \| O_EXCL \| O_APPEND, 0600)`; one `write` per line | `DSortIO/Ledger.swift` | |
| sort-execution › Single concurrent run | `flock(fd, LOCK_EX \| LOCK_NB)` on `<data directory>/lock` | `DSortIO/RunLock.swift` | The kernel releases the lock when the process dies, so a stale lock is impossible. |

### Classification

| Guarantee (spec › requirement) | macOS mechanism | Where | Notes |
|---|---|---|---|
| platform-macos › Screen-capture marker on macOS; item-classification › Screenshots are detected by system metadata | `getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", …, XATTR_NOFOLLOW)`, then `PropertyListSerialization` → `Bool(true)` | `DSortIO/FileOps.swift` (`isScreenCapture`) | No Spotlight query and no file contents read. |
| platform-macos › Default screenshot names on macOS; item-classification › Screenshots are detected by localized name as a fallback | Swift `Regex` on the NFC-normalized name: `Config.screenshotPattern` | `DSortCore/Config.swift`, `DSortCore/Classifier.swift` | |
| platform-macos › Packages on macOS; item-classification › Plain folders are skipped by default | `URLResourceKey.isPackageKey` for directories | `DSortIO/FileOps.swift` (`isPackage`), `DSortIO/Scanner.swift` | |
| platform-macos › Type identifiers on macOS; item-classification › System type conformance decides categories | `UTType(filenameExtension:conformingTo:)` with `.package` for packages and `.data` otherwise, then `conforms(to:)`. Config identifiers are validated with `UTType(_:)?.isDeclared` | `DSortCore/Classifier.swift`, `DSortCore/ConfigValidation.swift` | See the type quirks below. |
| platform-macos › Hidden items on macOS; item-classification › Hidden items are skipped | Name starts with `.` | `DSortCore/Classifier.swift` | `UF_HIDDEN` is deliberately ignored. |

### Undo, permissions, and the file manager

| Guarantee (spec › requirement) | macOS mechanism | Where | Notes |
|---|---|---|---|
| platform-macos › Folder-metadata file on macOS; run-undo › Empty bucket folders are removed | `unlink` of a lone `.DS_Store`, then `rmdir` | `DSortIO/UndoService.swift` (`removeEmptyFolders`) | |
| platform-macos › Privacy permissions on macOS; sort-execution › Permission failures are explained | `opendir` failing with `EPERM`/`EACCES` → exit 77. Names the app from `TERM_PROGRAM`, or the binary path; prints `open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"` | `DSortIO/Scanner.swift` (`PermissionHelp`) | Under `launchd`, TCC checks the binary itself. An ad-hoc-signed binary loses its grant on every rebuild. |
| platform-macos › No Apple Events on macOS; sort-execution › No file-manager scripting | Nothing: no `NSAppleScript`, `osascript`, or Apple Events anywhere | — | Finder updates on its own (verified below). |
| sort-execution › Environment diagnostics | `getattrlist(ATTR_VOL_CAPABILITIES)` → `VOL_CAP_INT_RENAME_EXCL`, `VOL_CAP_FMT_PATH_FROM_ID`, `VOL_CAP_FMT_CASE_SENSITIVE` | `DSortIO/FileOps.swift` (`volumeCapabilities`), `DSortIO/Doctor.swift` | Case sensitivity also decides whether the planner treats `Doc.pdf` and `doc.pdf` as the same name. |

## Verified behaviour

Each fact below was established by experiment, either during exploration or with a throwaway test program in a scratch folder. Many are now covered by tests in `Tests/DSortIOTests`. If a future macOS version changes one of them, the listed test or check is where it will show.

### Files and identity

**Safe saves change the inode.**
- *Tested:* temp file + `rename`, `Data.write(.atomic)`, `FileManager.replaceItemAt`, and `NSDocument.writeSafely` all left a new inode at the path. An in-place write kept it. `FileManager.replaceItemAt` and `NSDocument.writeSafely` (the path TextEdit and Preview use) kept the birth time; the other two did not.
- *Consequence:* inode plus birth time cannot follow an edited file, and birth time cannot detect a replacement. dsort turns on document tracking so the document ID can.
- *Test:* `trackedFileKeepsDocumentIDAcrossSafeSave`.

**Document IDs exist only with `UF_TRACKED`, and survive safe saves and renames.**
- *Tested:* an untracked file had no ID. After `chflags` set `UF_TRACKED`, the same ID survived `replaceItemAt`, a rename into another folder, a second replace, and `Data.write(.atomic)`. The flag carried over each time.
- *Also found:* reading `ATTR_CMN_DOCUMENT_ID` with raw `getattrlist` returned `EINVAL` in the experiment, while `URLResourceKey.documentIdentifierKey` worked; dsort uses the latter. Apps such as Preview and TextEdit set `UF_TRACKED` on files they open: 4 of 65 items on a real Desktop already had it.
- *Tooling note:* `ls -lO` does not display the flag. Check bit `0x40` in `stat -f %f` instead.

**Document IDs follow the original path.**
- *Tested:*
  - A tracked file deleted and recreated at the same path inherited the ID, even 3 s later.
  - After a tracked file was renamed into another folder, any new file created at its old path took the ID, and the moved file lost it. This held 5 s later as well.
  - Once the moved file had been safe-saved at its new path, a new file at the old path no longer took the ID.
- *Consequence:* the reconciler checks the recorded destination by inode before anything else, so a file that was only moved is always found correctly. For tracked files, a file replaced at the same path counts as the same document, so `replaced` effectively applies only to untracked files.
- *Known misreport (no data loss):* a sorted file that is safe-saved *and* whose original Desktop name is later reused can be reported `already-restored` while it stays in its bucket.
- *Tests:* `trackedFileRecreatedAtSamePathCountsAsTheSameDocument`, `replacedFileNeedsByPath`.

**`fsgetpath` finds files by inode without special privileges.**
- *Tested:* it returned the new path after a move and rename, a path inside `~/.Trash` after `FileManager.trashItem` (Terminal had no Full Disk Access), and the surviving name of a hard link whose first name was removed. It returned `ENOENT` for a deleted file and `EACCES` when a parent folder was `chmod 000`.
- *Paths:* it returns kernel paths, for example `/private/var/...` and `/private/tmp/...`. Foundation's `resolvingSymlinksInPath` strips `/private`, which would break path comparisons; dsort canonicalizes with `realpath`.
- *Not yet verified:* the error for a folder blocked by TCC rather than Unix permissions. Any non-`ENOENT` error is reported as `inaccessible`, so the behaviour is safe either way.
- *Tests:* `pathForFileFollowsRenamesAndReportsDeletion`, `pathForFileReportsPermissionDenied`, `fileInUnreadableFolderIsInaccessibleNotMissing`.

**Inode numbers are not reused quickly.**
- *Tested:* across 3,000 file creations after 500 deletions, inode numbers only increased and none repeated.
- *Consequence:* the birth-time check against a reused inode is cheap insurance, not a hot path.

**`RENAME_EXCL` refuses case variants.**
- *Tested:* on the default case-insensitive APFS volume, renaming `Doc.pdf` onto an existing `doc.PDF` failed with `EEXIST` and left both files intact. A rename that only changes the case of a file's own name succeeds.
- *Test:* `exclusiveRenameRefusesCaseVariant`.

### Volume and toolchain

**The Desktop's volume supports everything dsort needs.**
- *Tested:* `getattrlist(ATTR_VOL_CAPABILITIES)` on the APFS Data volume (which holds `~/Desktop`, `/private/tmp`, and `~/.Trash`) reported `RENAME_EXCL`, `RENAME_SWAP`, and path-from-ID as supported, and the volume as case-insensitive. All of these share one `f_fsid`.
- *Consequence:* `dsort doctor` checks the first two capabilities dsort depends on and reports a failure on volumes without them.

**No C shims are needed.**
- *Tested:* `fsgetpath`, `renamex_np`, `RENAME_EXCL`, `chflags`/`lchflags`, `getattrlist`, and `UF_TRACKED` import directly from Swift's `Darwin` module.
- *Consequence:* the package has no C target, and the binary links only system libraries.

### Screenshots

**Screenshots carry a language-independent marker.**
- *Tested:* every screenshot on a real Desktop, and one three years old in `~/Pictures`, had `com.apple.metadata:kMDItemIsScreenCapture`. It was a 42-byte binary property list holding `true`, alongside `kMDItemScreenCaptureType` and `kMDItemScreenCaptureGlobalRect`. A screenshot exported to JPEG lost the attribute but kept the `Screenshot …` name and an EXIF comment.
- *Consequence:* the attribute is the primary signal and the localized name pattern is the fallback; EXIF is not read.
- *Tooling note:* `xattr -l` output looks empty if piped through text tools, because the value is binary. Use `xattr -px <name> <file>`.

### Finder and the type system

**Finder refreshes on its own.**
- *Tested:* renames by another process (`mv`, and dsort itself) made Desktop icons vanish and reappear without any interaction. This held with View › Use Stacks both off and on.
- *Consequence:* no AppleScript, no Apple Events, and no Automation permission.

**UTType quirks that shape the default config.**
- *Tested:* `UTType(filenameExtension:)` conformance for common extensions:
  - `.ts` is an MPEG-2 transport stream, so a movie.
  - `.odt` conforms to both composite content and `public.archive`.
  - `.json` and `.yml` conform only to `public.text`, not to source code.
  - `.kt`, `.tex`, `.apk`, and `.kdbx` have no declared type.
  - `.svg` is both image and text.
  - `.app` resolves to `com.apple.application-bundle` only when looked up as a package.
- *Consequence:* the default config maps `.ts`, `.json`, `.yml` and similar to `Code` by extension, and lists `Documents` before `Archives`.
- *Tests:* `defaultCategories` in `ClassifierTests`.
