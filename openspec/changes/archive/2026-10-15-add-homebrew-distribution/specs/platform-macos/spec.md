# Spec Delta

## ADDED Requirements

### Requirement: Homebrew installation on macOS
On macOS, dtidy SHALL be installable with `brew install dtidy-app/tap/dtidy`. The installation SHALL provide the `dtidy` binary, the zsh, bash and fish completion scripts in Homebrew's completion directories, and the `dtidy(1)` man page, with no further setup beyond the shell's own completion initialization. `brew uninstall dtidy` SHALL remove all of them and SHALL NOT touch the user's config file or run history.

#### Scenario: Fresh install
- **WHEN** the user runs `brew install dtidy-app/tap/dtidy` on a supported Mac
- **THEN** `dtidy --version` prints the formula's version, `man dtidy` opens the manual, and `_dtidy`, `dtidy` and `dtidy.fish` exist under Homebrew's `share/zsh/site-functions`, `etc/bash_completion.d` and `share/fish/vendor_completions.d`

#### Scenario: Completion works after install
- **WHEN** dtidy was installed with Homebrew and the user's zsh runs `compinit` with Homebrew's `share/zsh/site-functions` on its `fpath`
- **THEN** typing `dtidy undo ` and pressing Tab offers the undoable run IDs

#### Scenario: Uninstall keeps user data
- **WHEN** the user runs `brew uninstall dtidy`
- **THEN** the binary, completions and man page are gone, and `~/.config/dtidy/` and `~/Library/Application Support/dtidy/` are unchanged

### Requirement: Released versions match their tags
Every macOS release SHALL be a Git tag `vX.Y.Z` in the dtidy-macos repository, and the binary built from that tag SHALL print `X.Y.Z` for `dtidy --version` and record `X.Y.Z` as the `tool` of the ledgers it writes.

#### Scenario: Version of a tagged build
- **WHEN** dtidy is built from tag `v0.1.0`
- **THEN** `dtidy --version` prints `0.1.0`

#### Scenario: Mismatched tag is refused
- **WHEN** the maintainer runs the release check for `0.2.0` while the source still declares `0.1.0`
- **THEN** the check fails and names both versions, before any tag is created
