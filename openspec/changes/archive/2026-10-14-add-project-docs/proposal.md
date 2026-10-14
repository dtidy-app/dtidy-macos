# Proposal

## Why

dsort's knowledge is scattered: behaviour lives in specs that mix guarantees with macOS mechanisms, design reasons and kernel behaviour verified by experiment live only in an archived design document, and the code comments describe single functions. A planned port to other operating systems (starting with Windows, possibly built by an AI agent) needs one place that says what must hold on every platform, why, and how macOS achieves it, without reading Swift code.

## What Changes

- Add a `docs/` folder for maintainers and porters:
  - `architecture.md`: pipeline, module boundaries, invariants, key decisions with reasons, and a glossary of the platform-neutral terms the specs use.
  - `ledger-format.md`: the ledger record schema and the rules for deriving run state, as a contract.
  - `platform-macos.md`: every platform-neutral guarantee mapped to the macOS mechanism behind it, plus the kernel behaviours verified during development.
  - `porting.md`: how to bring dsort to a new platform, a binding-table template, and unverified Windows candidates to spike first.
- Add `AGENTS.md` at the repository root: a short map telling coding agents where behaviour, invariants, and platform facts live. Add a one-line `CLAUDE.md` that imports it, because Claude Code reads `CLAUDE.md` rather than `AGENTS.md`.
- Link the new documents from `README.md`, which stays user-facing.
- Rewrite the requirements that name macOS mechanisms so they state platform-neutral guarantees, and move each macOS mechanism into a new `platform-macos` capability. Behaviour on macOS is unchanged.
- Align the specs with four behaviours that shipped but were not specified:
  - a bucket folder holding only the platform's folder-metadata file counts as empty;
  - a run with nothing to move writes no ledger;
  - the `failed` undo outcome;
  - the full set of run states.
- Add a test that fails when `docs/ledger-format.md` stops listing every ledger record type, so the contract document cannot silently drift from the code.
- Code comments stay in the code. No function-level reference documentation is added.

## Capabilities

### New Capabilities
- `platform-macos`: The macOS bindings of the platform-neutral guarantees. Covers default locations, the screenshot marker and default screenshot names, packages, type identifiers, document tracking, Trash locations, the folder-metadata file, privacy-permission messages, the hidden-item rule, and the absence of Apple Events.

### Modified Capabilities
- `item-classification`: Scanning default, packages, screenshot detection, and type detection restated in platform-neutral terms.
- `run-ledger`: Ledger location and recorded identity restated neutrally. History lists every run state. Runs with nothing to move write no ledger.
- `run-undo`: Identity matching, file lookup, Trash, and tracking restated neutrally. Folder removal covers folder-metadata files. Undo outcomes include `failed`.
- `sort-configuration`: Config location and built-in defaults restated neutrally, including the shipped `Documents` bucket.
- `sort-execution`: Collision naming, tracking, permission failures, and the no-scripting rule restated neutrally.

## Impact

- New files: `AGENTS.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/ledger-format.md`, `docs/platform-macos.md`, `docs/porting.md`, and one new test file in `Tests/DSortCoreTests`.
- Edited: `README.md` (links to the new documents), and main specs under `openspec/specs/` when the change is archived.
- No change to dsort's runtime behaviour, CLI, ledger format, or configuration format.
