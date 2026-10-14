# Proposal

## Why

dtidy can only be installed by cloning the source and running `make install`, and the repository is not public yet. Homebrew is how most macOS command-line users install tools. A Homebrew formula would also put the completion scripts and man page from `add-shell-completion-and-help` in place with no setup, and upgrade them with `brew upgrade`.

Windows and Linux versions are planned. The repository name and owner chosen now appear in every install command and in the formula's download URL, so they are settled in this change.

- **Layout:** one repository per operating system. This is the plan `docs/porting.md` already describes: each platform is its own implementation, and the core specs move to a shared OpenSpec store once a second platform exists.
- **Owner:** a GitHub organization, `dtidy-app`, owned by the author's account, so the project name stays the same across platforms. The name `dtidy` was unavailable on GitHub.

## What Changes

- **Publish the source.** The `dtidy-app` GitHub organization is created and owned by the author. This repository is published as `dtidy-app/dtidy-macos` with history whose commits are attributed to the author's GitHub account; they originally carried a hostname-derived email, so they were rewritten to the author's GitHub noreply address before the first push. Tags use the form `vX.Y.Z`.
- **Release process.**
  - A release is a `vX.Y.Z` tag whose version equals what `dtidy --version` prints.
  - It is published as a GitHub Release.
  - `make release-check VERSION=X.Y.Z` verifies the version, a clean working tree, the tests and the man page before tagging.
  - `docs/releasing.md` documents the steps.
- **Homebrew tap and formula.**
  - A tap repository, `dtidy-app/homebrew-tap`, is created with `brew tap-new`, which sets up GitHub Actions for tests and bottles.
  - Its `Formula/dtidy.rb` builds from the release tarball. It installs the binary, generates the zsh, bash and fish completions from it, and installs `docs/man/dtidy.1`.
  - Users install with `brew install dtidy-app/tap/dtidy`.
  - Bottles (prebuilt binaries) are published for the macOS versions the tap's CI runners provide. Other Macs build from source.
- **Community files.**
  - `CONTRIBUTING.md`: how changes are proposed through OpenSpec, how to build and test, the GPL-3.0-or-later licensing of contributions, and what a bug report needs.
  - `SECURITY.md`: how to report a vulnerability privately.
- **Docs.**
  - `README.md` leads with the Homebrew install and links to the repository.
  - `AGENTS.md` and `docs/porting.md` record the repository layout and naming for future ports.
- **Out of scope:**
  - submitting to homebrew-core;
  - a cask or notarized download;
  - the Windows and Linux ports, and setting up the shared spec store;
  - renaming the local checkout folder.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `platform-macos`: adds two requirements.
  - Installing with Homebrew provides the binary, completions and man page, and uninstalling removes them.
  - A released version's `--version` output matches its tag.

## Impact

- **This repository:**
  - `Makefile` (`release-check`)
  - new `CONTRIBUTING.md`, `SECURITY.md` and `docs/releasing.md`
  - `README.md`, `AGENTS.md`, `docs/porting.md`
  - rewritten commit authors before the first push
- **New external resources:**
  - the GitHub organization `dtidy-app`;
  - the repositories `dtidy-app/dtidy-macos` and `dtidy-app/homebrew-tap`;
  - the GitHub Release `v0.1.0`;
  - bottles stored as GitHub Release assets of the tap.
- **Accounts and tools:**
  - The author creates the organization in the GitHub web UI, because it must be done while signed in.
  - Pushing needs GitHub credentials on this machine.
  - The `gh` CLI is not installed. It is optional; the steps work in the web UI too.
- **Code:** no change to dtidy's behaviour. The version stays `0.1.0` for the first release.
