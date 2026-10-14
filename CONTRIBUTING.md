# Contributing to dtidy

Thanks for helping. dtidy moves people's files, so changes are planned before they are coded and every guarantee is backed by a test. This page explains how that works here.

## Reporting a bug

Open an issue with:

- `dtidy --version` and your macOS version (`sw_vers -productVersion`);
- what you ran, what you expected, and what happened;
- the output of `dtidy doctor --json`;
- for a run or undo that went wrong, `dtidy show <run-id> --json` (see `dtidy history`). Remove any file names you'd rather not share.

If the bug could lose or overwrite files, or lets dtidy write outside the folder it sorts, report it privately instead: see [SECURITY.md](SECURITY.md).

## How changes are made

**The specs define what dtidy does.** They live in [`openspec/specs/`](openspec/specs/). The README is written for users, and the Swift code shows only one platform's mechanisms, so neither is the authority on behaviour.

Changes that alter behaviour, a mechanism, the ledger format, or a documented platform fact go through [OpenSpec](https://github.com/Fission-AI/OpenSpec):

1. **Propose:** `openspec new change <name>`, or `/opsx:propose` with a coding agent. Write the proposal, the spec deltas, the design (when there are real decisions to make) and the tasks.
2. **Apply:** implement the tasks, with the tests and docs each task calls for.
3. **Archive:** when it's merged, the spec deltas are synced into `openspec/specs/` and the change moves to `openspec/changes/archive/`.

`openspec list` shows the changes in flight. Small fixes that don't change behaviour, such as typos, refactors or a failing test, can skip this and go straight to a pull request.

Before writing code, read [AGENTS.md](AGENTS.md) for where everything lives, and [docs/architecture.md](docs/architecture.md) for the invariants that must never break.

## Building and testing

```sh
swift build          # debug build: .build/debug/dtidy
swift test           # unit and filesystem tests; they only use temporary folders
make check-man       # fails if docs/man/dtidy.1 is out of date
```

- Tests never touch your real Desktop. For a manual run, use a scratch folder: `dtidy plan --root <dir>`. Set `XDG_DATA_HOME` and `XDG_CONFIG_HOME` to scratch folders so your real history and config stay untouched.
- Changed a command's help text? Run `make man` and commit the regenerated `docs/man/dtidy.1`. `swift test` also fails if a command has no discussion or examples.
- A pull request should pass `swift test` and `make check-man`.

Releases are described in [docs/releasing.md](docs/releasing.md).

## License

dtidy is licensed under the GNU General Public License v3.0 or later ([LICENSE](LICENSE)). By contributing, you agree that your contributions are licensed under the same terms.
