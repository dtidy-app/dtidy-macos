# Tasks

Steps marked **(you)** need the author's signed-in GitHub account. The apply workflow pauses at each one.

## 1. Accounts and commit identity

- [x] 1.1 **(you)** Turn on two-factor authentication for `t-ilk`, then create the free GitHub organization `dtidy-app` with the real address as its private contact email and no public email. Verify that https://github.com/dtidy-app loads and lists `t-ilk` as an owner. *Status 2026-10-14:* the organization is created (`dtidy` was unavailable), and the author confirmed two-factor authentication is on.
- [x] 1.2 **(you)** Choose the commit email: the GitHub noreply address `<id>+t-ilk@users.noreply.github.com` from Settings > Emails (recommended), or another address on the account. Then set it for this repository with `git config user.email`, and rewrite the unpublished commits with `git rebase --root --exec 'git commit --amend --no-edit --author="t-ilk <ADDRESS>"'`, which keeps the author dates. Verify that `git log --format='%an <%ae>'` shows only the chosen address, and that `git diff <old HEAD> HEAD` is empty (same tree). *Result 2026-10-14:* `50845773+t-ilk@users.noreply.github.com` (matching `t-ilk`'s account ID) is set globally. All 4 commits carry it with their original dates, and the tree is identical to the old `cb7681f`.
- [x] 1.3 **(you)** Create the empty public repository `dtidy-app/dtidy-macos`, with no README, license or .gitignore, and turn on Settings > Security > Private vulnerability reporting. Verify that the repository page shows the empty-repository instructions. *Status 2026-10-14:* `dtidy-app/dtidy-macos` exists (public, empty, default branch `main`, as checked through the API); the author confirmed private vulnerability reporting is on.

## 2. Repository files

- [x] 2.1 Add `CONTRIBUTING.md`:
  - the specs define behaviour, and changes go through OpenSpec (propose → apply → archive);
  - build and test with `swift test`, `make check-man` and `make man`;
  - contributions are licensed GPL-3.0-or-later;
  - what a bug report needs: `dtidy --version`, the macOS version and `dtidy doctor --json`;
  - links to `AGENTS.md`, `docs/` and `docs/releasing.md`.

  Add `SECURITY.md`: private vulnerability reporting, which bugs count (data loss, overwritten files, writes outside the root), and that the latest release is the supported version. Verify that every relative link in both files resolves to an existing file.
- [x] 2.2 Add `make release-check VERSION=X.Y.Z` to the `Makefile`. It fails, naming the reason, when:
  - `VERSION` is missing;
  - `.build/release/dtidy --version` differs from `VERSION` (naming both versions);
  - the working tree is not clean;
  - `swift test` or `make check-man` fails;
  - the tag `vX.Y.Z` already exists.

  Verify that it passes for `0.1.0` on a clean tree, fails for `0.2.0` naming `0.1.0` and `0.2.0`, and fails with an uncommitted change present.
- [x] 2.3 Write `docs/releasing.md`:
  1. bump `DTidyVersion`;
  2. `make man`;
  3. commit;
  4. `make release-check`;
  5. `git tag -a vX.Y.Z`;
  6. push `main` and the tag;
  7. create the GitHub Release;
  8. compute the tarball checksum;
  9. bump the formula (`brew bump-formula-pr --url … dtidy-app/tap/dtidy`, or the tap's autobump);
  10. label the tap pull request `pr-pull` to publish bottles;
  11. never move a published tag.

  Verify that every command it names exists (the Make targets, and the `brew` subcommands via `brew help <cmd>`).
- [x] 2.4 Update the docs:
  - `README.md`: Homebrew first (`brew install dtidy-app/tap/dtidy`), then building from source; a note that Macs without a bottle build from source and need Xcode 16 or later; the repository link; and pointers to `CONTRIBUTING.md` and `SECURITY.md` in the Documentation section.
  - `AGENTS.md`: the repository naming (`dtidy-app/dtidy-<os>`) and `docs/releasing.md` in the "Where the truth lives" table.
  - `docs/porting.md`: new ports live in `dtidy-app/dtidy-<os>`, and the shared store is `dtidy-app/spec`.

  Verify that `grep -n "dtidy-app/tap/dtidy" README.md` matches and that `swift test` passes.
- [x] 2.5 Run `swift test && make check-man && openspec validate add-homebrew-distribution --strict`, then commit the repository files. Verify that all three pass and that the working tree is clean.

## 3. Publish the source

- [ ] 3.1 Add `origin` (`https://github.com/dtidy-app/dtidy-macos.git`) and push `main`. **(you)** Authenticate when git asks, with a personal access token or the macOS keychain helper. Verify on GitHub that every commit shows the `t-ilk` avatar and links to the account.
- [ ] 3.2 Run `make release-check VERSION=0.1.0`, create the annotated tag `v0.1.0`, push it, and create the GitHub Release `v0.1.0` with short notes **(you, in the web UI, or with `gh` if installed)**. Verify that `curl -fL https://github.com/dtidy-app/dtidy-macos/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256` succeeds. Record the checksum in this task.

## 4. Tap and formula

- [ ] 4.1 **(you)** Create the empty public repository `dtidy-app/homebrew-tap`. Then run `brew tap-new dtidy-app/homebrew-tap` locally, add the remote, and push. Verify that the tap's Actions tab lists the `tests`, `publish` and `autobump` workflows.
- [ ] 4.2 Write `Formula/dtidy.rb` as in the design, with the recorded checksum. Verify that `brew style dtidy-app/tap` and `brew audit --strict --new --online dtidy-app/tap/dtidy` report no problems.
- [ ] 4.3 Run `brew install --build-from-source dtidy-app/tap/dtidy` and `brew test dtidy`. Then check the platform-macos scenarios:
  - `dtidy --version` prints `0.1.0`;
  - `man -w dtidy` resolves;
  - `_dtidy`, `dtidy` and `dtidy.fish` exist under `$(brew --prefix)/share/zsh/site-functions`, `etc/bash_completion.d` and `share/fish/vendor_completions.d`;
  - a zsh `dtidy undo <Tab>` offers undoable run IDs, using the `zpty` harness from the completion change against a scratch history;
  - `brew uninstall dtidy` removes those files and leaves `~/.config/dtidy` and `~/Library/Application Support/dtidy` unchanged (compare listings before and after).
- [ ] 4.4 Push the formula on a branch and open a pull request in the tap, so `tests.yml` builds bottles. **(you)** Once the checks pass, add the `pr-pull` label. Verify that the merged formula on `main` has a `bottle do` block, and that `brew uninstall dtidy && brew install dtidy-app/tap/dtidy` reports pouring a bottle.

## 5. Integration check

- [ ] 5.1 From a clean state (`brew uninstall dtidy`, `brew untap dtidy-app/tap`), follow the README's install section exactly as written, then run `dtidy --help` and `man dtidy`. Verify that each documented command works without changes, and record any macOS version that got no bottle.
- [ ] 5.2 Run `openspec validate add-homebrew-distribution --strict` and confirm that `main` on GitHub matches the local `main`. Verify both.

## Workflow follow-up

- Archive with `/opsx:archive`. This syncs the two new `platform-macos` requirements.
- After real-world use, consider homebrew-core. Then create `dtidy-app/spec` and the OpenSpec store when the second platform starts.
