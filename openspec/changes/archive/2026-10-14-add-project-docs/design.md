# Design

## Context

See proposal.md for motivation. Current state:

- **`README.md`:** user-facing, covering install, usage, undo, configuration, permissions, and `launchd`.
- **`openspec/specs/`:** five capability specs. Their requirement text names macOS mechanisms in about 20 places.
- **Source code:** about 240 comment lines in 2,900 lines, almost all `///` doc comments on types and functions.
- **Verified platform facts:** kept in `openspec/changes/archive/2026-10-14-add-desktop-sorter-cli/design.md`, where they are hard to find. They cover how the kernel handles safe saves, document IDs, `fsgetpath` errors, and inode reuse.
- **No agent entry point:** the repository has no `AGENTS.md` or `CLAUDE.md`.

## Goals / Non-Goals

**Goals:**
- Give maintainers, and agents porting dsort, one document per question: what must hold (specs), why and how it fits together (architecture), what the ledger looks like (ledger format), how macOS does it (platform doc), and how to start a new platform (porting guide).
- Keep every fact in exactly one place, and make the most-shared contract (the ledger format) checked by a test.

**Non-Goals:**
- A documentation website or generated API reference. DocC can be added later from the existing `///` comments.
- Moving or rewriting code comments.
- Extracting the specs into a shared OpenSpec store. That waits until a second platform exists.
- Any change to runtime behaviour.

## Decisions

### D1. Markdown in the repository, not a website
The docs live in `docs/` next to the code they describe, so they are reviewed and changed in the same commits. GitHub renders them directly, and a site generator can be pointed at `docs/` later without moving anything. The README stays the user's front door and links to `docs/` for maintainers.

*Alternative:* a separate documentation site. Rejected for now: it adds publishing work, and it drifts from the code because it is not changed alongside it.

### D2. Each kind of knowledge has one home

| Knowledge | Home |
|---|---|
| What a function or type promises | `///` comment on it (unchanged) |
| Externally observable behaviour | `openspec/specs/` |
| Pipeline, invariants, decisions and their reasons, glossary | `docs/architecture.md` |
| Ledger records and state derivation | `docs/ledger-format.md` |
| Guarantee → macOS mechanism, verified kernel facts | `docs/platform-macos.md` |
| How to add a platform, unverified candidates | `docs/porting.md` |
| Usage | `README.md` |

Documents link to each other instead of repeating content. For example, `platform-macos.md` cites spec requirements by name rather than copying them.

### D3. Specs split into platform-neutral core plus one platform capability
Core capabilities state guarantees using a fixed vocabulary, defined once in the glossary in `docs/architecture.md`:

| Term | Meaning |
|---|---|
| root folder | the folder being sorted; by default the user's Desktop |
| file identity | volume identifier + file identifier + creation time |
| document identity | an ID that survives safe saves; 0 when unavailable |
| document tracking | opting a file into document identity |
| screen-capture marker | metadata a platform's screenshot tool attaches |
| platform type system | how a file's type is derived from its extension |
| platform trash | the trash or recycle bin folders |
| folder-metadata file | e.g. `.DS_Store` |
| data directory | per-user application data location for dsort |
| config file | per-user config location for dsort |

`platform-macos` binds each term to macOS and holds the macOS-only rules: no Apple Events, the TCC message, and the hidden-item rule.

Two details of the split:
- **Example paths stay.** Scenario example paths such as `~/Desktop/invoice.pdf` remain as illustrations; requirement text carries the guarantee.
- **Scenario names stay.** OpenSpec refuses MODIFIED blocks that drop a scenario name, so existing names are kept even where they mention a macOS term (for example "Run under launchd"), and their bodies are made neutral.

*Alternative:* leave the specs macOS-specific and put a mapping table only in the docs. Rejected (user decision): a port would then have to separate guarantees from mechanisms itself.

### D4. `AGENTS.md` as the agent entry point, imported by `CLAUDE.md`
`AGENTS.md` is a short map (well under one screen):
- where behaviour, invariants, the ledger contract, and platform facts live;
- the rule that behaviour is never inferred from the README or the Swift code alone;
- how to build and test;
- the rule to update the matching document in the same change.

`CLAUDE.md` contains only `@AGENTS.md`, so Claude Code loads the same text and the two never diverge. `CLAUDE.local.md` stays ignored for personal notes.

### D5. Ledger contract guarded by a test
`docs/ledger-format.md` gives each record type a heading of the form `` ### `<type>` ``, followed by its fields, when it is written, and whether it is flushed. It then gives the state-derivation rules: committed, interrupted, recovered, partially-reverted, reverted.

A new test in `DSortCoreTests` checks the document against the code:
- It builds one sample of every `LedgerRecord` case. An exhaustive `switch` helper makes the compiler flag a new case.
- It encodes each sample and reads its `t` value.
- It asserts that `docs/ledger-format.md`, found via `#filePath`, contains the matching heading.

Adding a record type without documenting it fails the test suite.

*Alternative:* generate the document from code. Rejected as heavier than the problem: the schema is small and changes rarely.

### D6. `platform-macos.md` holds the verified facts
It has two parts:
1. A table: guarantee (named by spec requirement) → macOS mechanism (API or syscall) → notes. Mechanisms belong here, not in specs, because they are implementation details: `renamex_np` + `RENAME_EXCL`, `fsgetpath`, `chflags(UF_TRACKED)`, `F_BARRIERFSYNC`, `flock`, `getxattr`.
2. "Verified behaviour": each kernel fact found by experiment, with how it was tested and what dsort does about it. This replaces the archived design.md as the place to look these up. The facts are:
   - safe saves change the inode;
   - Foundation keeps the birth time across safe saves;
   - document IDs exist only with `UF_TRACKED` and follow the original path;
   - `fsgetpath` returns `EACCES`/`ENOENT` and paths under `/private`;
   - inode numbers are not reused;
   - `RENAME_EXCL` refuses case variants;
   - Finder refreshes on its own.

### D7. `porting.md` is a procedure, not a promise
It covers:
- the order of work for a new platform: copy the core specs, write `platform-<os>` bindings, spike the unverified mechanisms first, then implement against the specs;
- a blank binding-table template;
- the Windows candidates, each explicitly marked unverified:

| Need | Windows candidate |
|---|---|
| Exclusive move | `MoveFileExW` without `MOVEFILE_REPLACE_EXISTING` |
| File identity | NTFS file ID via `GetFileInformationByHandleEx` |
| Lookup by file ID | `OpenFileById` + `GetFinalPathNameByHandleW` |
| Identity across safe saves | NTFS object IDs / link tracking |
| Screen-capture marker | none known |
| Lock | `LockFileEx` |
| Data directory | `%LOCALAPPDATA%` |

It also describes the future option of moving the core specs into a shared OpenSpec store once a second implementation exists.

## Risks / Trade-offs

- **[Docs drift from code]** → Each fact has one home (D2). `AGENTS.md` tells agents to update the matching document in the same change. The ledger contract is test-checked (D5). Behaviour remains test-covered by the specs.
- **[Neutral specs are harder to test on macOS]** → Every neutral term is bound to a concrete, testable rule in `platform-macos`. Together the core specs and the platform spec say everything the old specs said.
- **[Windows candidates turn out wrong]** → They are labelled unverified and presented as spike targets, not decisions.
- **[Scenario names keep macOS words]** → Accepted. Names are labels; requirement text and scenario bodies carry the meaning.
