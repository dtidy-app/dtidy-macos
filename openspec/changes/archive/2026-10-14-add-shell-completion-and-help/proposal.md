# Proposal

## Why

dtidy is used from the terminal, and most of its commands are run rarely: `undo RUN_ID`, `show RUN_ID`, `recover`, `config init`. Users have to remember the subcommands and options and copy run IDs out of `dtidy history` by hand. The built-in `--help` has one-line summaries and almost no examples, and there is no `man dtidy`. This change adds Tab completion for zsh, bash and fish, including live run IDs; richer help with examples and exit codes; and a man page. These are the user-facing parts that the planned Homebrew formula (`add-homebrew-distribution`) will install.

## What Changes

- **Completion scripts.** dtidy prints completion scripts for zsh, bash and fish. The swift-argument-parser flag `--generate-completion-script <shell>` already exists; this change makes it part of the contract and covers it with tests.
- **Completion of commands and options.**
  - Subcommands and options complete everywhere.
  - Enumerated values complete: `--on-conflict` offers `suffix` and `skip`.
  - Path options complete paths: `--root` offers directories and `--config` offers `.json` files and directories.
- **Live run-ID completion.**
  - `dtidy undo <Tab>` offers the sort runs that can be undone, newest first.
  - `dtidy show <Tab>` offers every recorded run.

  Completion only reads history. It never writes anything, takes the lock, reads the config, or touches the root folder, and it degrades to no suggestions instead of failing.
- **Richer help.**
  - Every command's help gets a discussion and at least one example.
  - The top-level help adds the exit codes and the config and data locations.
  - `dtidy help <command>`, `-h` and `--help` keep working for every command and subcommand.
- **Man page.**
  - `docs/man/dtidy.1` is generated from the same help text with argument-parser's `generate-manual` plugin and committed.
  - It is regenerated with `make man`, and `make check-man` reports when it is stale.
- **Manual install.** A new `Makefile` installs the binary, the man page and the three completion scripts under `PREFIX` (default `/usr/local`), and uninstalls them. The README documents both this path and the per-shell setup.

## Capabilities

### New Capabilities

- `shell-completion`: completion scripts for supported shells, which arguments complete to what (subcommands, options, values, paths, run IDs), and the guarantee that completing never has side effects or fails loudly.
- `command-help`: what every command's help must contain (summary, discussion, examples), the top-level exit-code and location summary, the help entry points, and the man page that mirrors them.

### Modified Capabilities

None. The behaviour of `run`, `plan`, `undo`, `recover`, `history`, `show`, `doctor` and `config` is unchanged. Only their help text grows.

## Impact

- **Code:**
  - `Sources/dtidy/*Command(s).swift`: discussions, examples, and `completion:` kinds on arguments and options.
  - `Sources/DTidyCore/History.swift`: a pure function that picks completion candidates.
- **Tests:**
  - `DTidyCoreTests`: candidate selection.
  - New `DTidyCLITests` target: help content, completion-script content, and a regression test that every command has a discussion and an example.
- **Build and docs:**
  - new `Makefile` and `docs/man/dtidy.1`
  - `README.md` (install, completion setup, `man dtidy`)
  - `AGENTS.md` (regenerate the man page when help changes)
  - `docs/architecture.md` (the completion path)
- **Dependencies:** none new. The `generate-manual` plugin ships with the existing swift-argument-parser 1.8.2 dependency.
- **Out of scope:** the Homebrew formula and tap, release tagging, and localized help.
