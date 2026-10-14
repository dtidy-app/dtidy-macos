# Security policy

dtidy moves files in your home folder, so bugs that put data at risk are treated as security issues.

## Reporting a vulnerability

Report privately through GitHub: on [dtidy-app/dtidy-macos](https://github.com/dtidy-app/dtidy-macos), open **Security → Report a vulnerability**. Please don't open a public issue for these.

Include the dtidy version (`dtidy --version`), your macOS version, the steps to reproduce, and what was affected. Reports are answered as soon as possible, and a fix is released as a new patch version once it is ready.

## What counts

Report it privately if dtidy can be made to:

- lose a file, or leave it where neither `undo` nor `recover` can find it;
- overwrite, truncate or delete a user file;
- write, move or create anything outside the root folder it sorts, its config file, or its data directory;
- follow a symbolic link or a crafted name into another location;
- misreport what it did in a way that makes `undo` move the wrong file.

Ordinary bugs, such as a file sorted into the wrong bucket, belong in a public issue: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Supported versions

Only the latest release gets fixes. Update with `brew upgrade dtidy`, or rebuild from the latest tag.
