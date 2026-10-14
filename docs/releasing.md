# Releasing dtidy for macOS

A release is an annotated Git tag `vX.Y.Z` on `main` in [dtidy-app/dtidy-macos](https://github.com/dtidy-app/dtidy-macos). Homebrew users get it through the formula in [dtidy-app/homebrew-tap](https://github.com/dtidy-app/homebrew-tap). The binary built from the tag must report the same version (`platform-macos` › Released versions match their tags), and `make release-check` enforces that before anything is tagged.

## Steps

1. **Bump the version.** Set `DTidyVersion.current` in `Sources/DTidyCore/Version.swift` to `X.Y.Z`. This is the version `dtidy --version` prints and the ledgers record. Use a patch release for fixes, minor for new behaviour, and major for breaking changes to the CLI, config or ledger format.
2. **Regenerate the man page:** `make man`. This picks up any help-text changes and stamps the page with today's date.
3. **Commit** the bump and the man page: `git commit -am "Release X.Y.Z"`.
4. **Check:** `make release-check VERSION=X.Y.Z`. It refuses a version mismatch, a dirty working tree, failing tests, a stale man page, or a tag that already exists.
5. **Tag:** `git tag -a vX.Y.Z -m "dtidy X.Y.Z"`. Use `-s` instead of `-a` once a signing key is set up.
6. **Push:** `git push origin main vX.Y.Z`.
7. **Publish the GitHub Release** for `vX.Y.Z`: on GitHub, Releases → Draft a new release → choose the tag. Write short notes listing what changed for users. With the `gh` CLI: `gh release create vX.Y.Z --title "dtidy X.Y.Z" --notes-file <notes>`.
8. **Get the tarball checksum**, which the formula needs:

   ```sh
   curl -fL https://github.com/dtidy-app/dtidy-macos/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
   ```
9. **Bump the formula.** The tap's scheduled `autobump` workflow notices the new tag and opens a pull request by itself. To do it now instead:

   ```sh
   brew bump-formula-pr --url https://github.com/dtidy-app/dtidy-macos/archive/refs/tags/vX.Y.Z.tar.gz \
     --sha256 <checksum> dtidy-app/tap/dtidy
   ```

   This needs `HOMEBREW_GITHUB_API_TOKEN` set to a GitHub token that can open pull requests on the tap.
10. **Publish bottles.** Wait for the pull request's `tests` checks to pass, then add the `pr-pull` label. The `publish` workflow uploads the bottles, adds the `bottle do` block, and merges.
11. **Verify:** `brew update && brew upgrade dtidy && dtidy --version`.

## Rules

- **Never move or delete a published tag.** Homebrew pins the tarball's checksum, so moving a tag breaks installs for everyone. Fix a bad release with a new patch version.
- Release from `main` only, with a clean working tree. `make release-check` checks the tree, not the branch.
- The formula and the man page come from the tag. Anything they need, such as `docs/man/dtidy.1`, must be committed before tagging.

## Maintainer setup

- Two-factor authentication must stay on for every owner of the `dtidy-app` organization.
- Add a second organization owner you trust, so the project is never locked behind a single account.
