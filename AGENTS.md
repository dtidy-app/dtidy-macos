# AGENTS.md

dtidy is a macOS command-line tool that sorts the top level of the Desktop into bucket folders and can undo every run. Swift 6, Swift Package Manager, macOS 14+, GPL-3.0.

## Where the truth lives

| Question | Read |
|---|---|
| What must dtidy do? (behaviour, edge cases, exit codes) | `openspec/specs/*/spec.md` |
| What does a guarantee mean on macOS specifically? | `openspec/specs/platform-macos/spec.md` |
| How is it built, which invariants must never break, and why? | `docs/architecture.md` |
| What is in a ledger file, and how is run state derived? | `docs/ledger-format.md` |
| Which macOS API provides each guarantee, and what was verified about the kernel? | `docs/platform-macos.md` |
| How do I bring dtidy to another OS? | `docs/porting.md` |
| How do users run it? | `README.md` |

Rules:

- Take behaviour from the specs. Do not infer it from the README (which is written for users) or from the Swift code alone (which shows one platform's mechanisms).
- Planned work goes through OpenSpec: `openspec list` for changes in flight, `openspec list --specs` for capabilities. The project's workflow commands are in `.claude/commands/opsx/`.
- When a change alters behaviour, a mechanism, the ledger format, or a verified platform fact, update the matching document above in the same change. `swift test` fails if `docs/ledger-format.md` misses a ledger record type.
- Help text lives in each command's `abstract`, `discussion` (ending in an `EXAMPLES:` block) and `help:` strings. When you change any of them, run `make man` in the same change; `make check-man` fails otherwise. `swift test` fails if a command lacks a discussion or examples.

## Build and test

```sh
swift build                 # debug build: .build/debug/dtidy
swift test                  # all unit and filesystem tests (they use temp directories only)
swift build -c release      # release build: .build/release/dtidy
make man                    # regenerate docs/man/dtidy.1 from the help text
make check-man              # fail if docs/man/dtidy.1 is stale
make install PREFIX=<dir>   # binary, man page and completions (default PREFIX /usr/local)
```

Tests never touch the real Desktop. Manual runs against a scratch folder: `dtidy plan --root <dir>`; set `XDG_DATA_HOME` and `XDG_CONFIG_HOME` to scratch folders to keep the real history and config untouched.

## Code layout

- `Sources/DTidyCore`: pure logic, no filesystem access.
- `Sources/DTidyIO`: everything that touches the disk, behind the `FileOps` protocol.
- `Sources/dtidy`: the CLI.

`docs/architecture.md` has the details.
