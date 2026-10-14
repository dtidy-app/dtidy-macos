# Tasks

## 1. Architecture and agent entry point

- [x] 1.1 Write `docs/architecture.md`. It covers:
  - the pipeline and module boundaries (DSortCore pure, DSortIO filesystem, `dsort` CLI);
  - the invariants (exclusive rename only; plan durable before the first move; only "does not exist" means missing; one run at a time);
  - the key decisions with their reasons (sequential execution, plan-as-intent ledger, barrier flushes, config replaces defaults, no file-manager scripting);
  - the glossary of platform-neutral terms from design D3.

  Verify that every glossary term appears in at least one spec under `openspec/changes/add-project-docs/specs/`, and that every module named in the document exists under `Sources/`.
- [x] 1.2 Write `AGENTS.md`. It contains the map of where behaviour, invariants, the ledger contract, platform facts, and usage live; the rule never to infer behaviour from the README or code alone; the build and test commands; and the rule to update the matching document in the same change. Verify that it fits on one screen (60 lines or fewer) and that every path it names exists.
- [x] 1.3 Add `CLAUDE.md` containing only `@AGENTS.md`. Verify that `git check-ignore CLAUDE.md` reports it as not ignored.

## 2. Ledger contract

- [x] 2.1 Write `docs/ledger-format.md`. It covers:
  - the file naming, location, and permissions;
  - the line format and truncation rule;
  - one `` ### `<type>` `` section per record type (run, mkdir, move, sealed, tracked, retarget, done, fail, restore, undone, rmdir, state, commit), each with its fields, when it is written, and whether it is flushed;
  - the rules for deriving run state (committed, interrupted, recovered, partially-reverted, reverted);
  - a worked example of a sort ledger and its undo ledger.

  Verify the example lines by decoding them with `LedgerCodec` in the test from 2.2.
- [x] 2.2 Add `Tests/DSortCoreTests/LedgerDocTests.swift`. It builds one sample of every `LedgerRecord` case through an exhaustive `switch` helper and asserts that `docs/ledger-format.md` (located via `#filePath`) has a `` ### `<t>` `` heading for each encoded `t`. It also asserts that every JSON line in the document's example blocks decodes. Verify that `swift test --filter LedgerDocTests` passes, and that temporarily deleting one heading makes it fail.

## 3. macOS platform document

- [x] 3.1 Write the binding table in `docs/platform-macos.md`. Each row maps a guarantee (named by its spec requirement) to the macOS mechanism behind it, with notes; mechanisms include `renamex_np`/`RENAME_EXCL`, `fsgetpath`, `UF_TRACKED` with `documentIdentifierKey`, `getxattr` of the screen-capture attribute, UTType, `F_BARRIERFSYNC`, `flock`, `realpath`, the TCC message, `.DS_Store`, and the Trash paths. Verify that every requirement in `openspec/changes/add-project-docs/specs/platform-macos/spec.md` appears in at least one row, and that each mechanism named exists in `Sources/` (grep).
- [x] 3.2 Write the "Verified behaviour" section of `docs/platform-macos.md`. Each kernel fact found during development gets how it was tested and what dsort does about it:
  - safe saves change the inode, and Foundation keeps the birth time;
  - document IDs exist only with `UF_TRACKED`, survive safe saves, and follow the original path;
  - `fsgetpath` returns `ENOENT`/`EACCES` and `/private` paths;
  - inode numbers are not reused;
  - `RENAME_EXCL` refuses case variants;
  - Finder refreshes on its own.

  Verify against the archived design.md that no fact recorded there is missing.

## 4. Porting guide

- [x] 4.1 Write `docs/porting.md`. It covers:
  - the procedure for a new platform: copy the core specs, write `platform-<os>` bindings, spike unverified mechanisms, implement against the specs, reuse the ledger and config formats;
  - a blank binding-table template with one row per glossary term and per platform-macos requirement;
  - the Windows candidate table from design D7, every row marked unverified;
  - a note on moving the core specs into a shared OpenSpec store once a second implementation exists.

  Verify that the template has a row for every glossary term in `docs/architecture.md`.

## 5. README

- [x] 5.1 Add a short "Documentation" section to `README.md` linking `docs/architecture.md`, `docs/ledger-format.md`, `docs/platform-macos.md`, `docs/porting.md`, and `AGENTS.md`. Shorten the README's ledger section to user-level facts plus a link to `docs/ledger-format.md`. Verify that the README's commands and exit-code table are unchanged.

## 6. Integration checks

- [x] 6.1 Check every relative Markdown link in `README.md`, `AGENTS.md`, and `docs/*.md` resolves to an existing file or heading (script over `](` targets), and verify none point to the archived change directory
- [x] 6.2 Run `swift test` and `openspec validate add-project-docs --strict`, and verify that both pass with no source file under `Sources/` changed (`git diff --stat -- Sources` is empty)
