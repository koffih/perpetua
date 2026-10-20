# Contributing to Perpetua

Thank you for your interest in improving Perpetua. This guide explains how to set up a
development environment, the standards a change must meet, and how changes are reviewed
and released.

By participating in this project you agree to abide by its
[Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- **Bugs.** Open an issue with the bug report form, including the output of
  `perpetua doctor` and the relevant lines of the runner log.
- **Features.** Open an issue with the feature request form before writing code. Perpetua
  deliberately stays small, and agreeing on the design first saves everyone time.
  Significant decisions are recorded as architecture decision records in
  [`docs/adr/`](docs/adr/).
- **Security vulnerabilities.** Never open a public issue. Follow the
  [security policy](SECURITY.md).
- **Small fixes** (typos, broken links, obvious one-line bugs) can go straight to a pull
  request.

## Development environment

Perpetua is a Bash CLI, a Bash session runner, a Python recorder that uses the standard
library only, and systemd user units. You need:

| Tool | Version | Used for |
| --- | --- | --- |
| Bash | 4.4 or later | the CLI and the runner |
| GNU coreutils, findutils, util-linux | any recent | `timeout`, `find`, `flock` |
| Python | 3.8 or later | the recorder |
| [ShellCheck](https://www.shellcheck.net/) | 0.10 or later | static analysis of the shell code |
| Node.js | 18 or later | running [bats](https://github.com/bats-core/bats-core) through `npx` |
| [uv](https://docs.astral.sh/uv/) | any recent | Ruff and the documentation site |

systemd is not required to develop or run the test suite: the tests replace `systemctl`
and Claude Code with fakes.

Clone the repository and run the CLI straight from the working tree. It resolves its
`libexec` and `share` directories relative to itself, so no installation is needed:

```sh
git clone https://github.com/koffih/perpetua.git
cd perpetua
bin/perpetua help
```

To try it end to end on your machine, `make install` installs the working tree into
`~/.local` (override with `PREFIX=...`), and `make uninstall` removes it.

## Checks

Run all of the following before you open a pull request. Continuous integration runs the
same checks and must be green before a change is merged.

```sh
make lint                                  # version consistency, ShellCheck, Python compile
uvx ruff check --target-version py38 libexec
make test                                  # the bats suite: npx --yes bats@1.11.0 tests/
make docs                                  # strict documentation build
```

A single test file or test can be run directly:

```sh
npx --yes bats@1.11.0 tests/session.bats
npx --yes bats@1.11.0 --filter 'gate:presence' tests/session.bats
```

To preview the documentation while you edit it:

```sh
uvx --with mkdocs-material mkdocs serve    # or: make docs-serve
```

## Coding standards

### Shell

- Target Bash, with `#!/usr/bin/env bash` as the first line.
- Start every script with `set -uo pipefail`. The CLI also sets `-e`. The runner does not,
  because it must survive a failing session in order to record it.
- Indent with tabs. The [`.editorconfig`](.editorconfig) file configures most editors.
- Keep ShellCheck clean. A `# shellcheck disable=SCxxxx` directive is acceptable only on
  the line it concerns, with a comment that explains why.
- Quote every expansion unless word splitting is intended and commented. Prefer `[[ ]]`
  and `(( ))` to `[ ]`, and declare function variables `local`.
- Do not add runtime dependencies. The runtime is Bash, coreutils, findutils, util-linux,
  Python 3.8 standard library and systemd. Anything else needs an ADR.
- Preserve the exit status contracts. The CLI exits `0` on success, `1` on failure and `2`
  on a usage or configuration error. The runner exits `0` whenever a run was handled,
  including when a gate closed, so that the timer keeps its cadence.
- Keep messages and log lines short, lowercase after the prefix, and stable: operators
  parse `runner.log` with their own tools.

### Python

- Standard library only, compatible with Python 3.8.
- Four spaces, Ruff clean.
- Write state files atomically when other processes read them.

### Tests

- Every change in behaviour comes with a test in `tests/`.
- Every admission gate has tests for both the open and the closed case. A change to a gate
  also tests that `--force` bypasses only the presence and attention gates, never the stop
  flag, the lock or the back-off.
- Tests must not depend on the host: use the helpers in `tests/helpers.bash`, which
  isolate `HOME`, the XDG directories, `systemctl` and Claude Code.

### Documentation

- A user-visible change updates the relevant pages in `docs/` in the same pull request.
- A user-visible change adds a line under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md),
  in the section that fits: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` or
  `Security`.
- Write in a plain, exact tone. Do not use emoji.

## Commits and pull requests

### Conventional Commits

Commit messages and pull request titles follow
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<scope>): <summary in the imperative, lowercase, no final period>
```

| Type | Use for |
| --- | --- |
| `feat` | a new capability |
| `fix` | a bug fix |
| `docs` | documentation only |
| `test` | tests only |
| `refactor` | a change that neither fixes a bug nor adds a capability |
| `perf` | a performance improvement |
| `build` | `Makefile`, `install.sh`, packaging |
| `ci` | GitHub Actions workflows |
| `chore` | anything else, including releases |

Common scopes are `cli`, `session`, `record`, `systemd`, `wsl`, `install` and `docs`.
Mark a breaking change with `!` after the scope and a `BREAKING CHANGE:` footer that
explains the migration.

```text
fix(session): release the lock before running the post-session hook

The hook could start a new session through `perpetua run`, which then
found the lock held and exited without running.

Signed-off-by: Ada Lovelace <ada@example.com>
```

### Developer Certificate of Origin

Perpetua does not require a contributor licence agreement. Instead, every commit must
carry a `Signed-off-by` trailer certifying that you wrote the change or otherwise have the
right to submit it under the project's licence, as described in the
[Developer Certificate of Origin 1.1](https://developercertificate.org/).

Git adds the trailer for you with `-s`:

```sh
git commit -s -m "docs(guides): explain the attention gate"
```

To sign off commits you already made on your branch, run
`git rebase --signoff main` and force-push the branch. Pull requests with unsigned
commits are not merged.

### Review

- Keep pull requests focused on a single change. Unrelated refactoring belongs in its own
  pull request.
- Fill in the pull request template. A maintainer reviews within a few days; please be
  patient.
- Pull requests are squash-merged, so the pull request title becomes the commit message
  on `main`.

## Release process

Releases follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and are cut by
a maintainer from `main`.

1. Update the version in `bin/perpetua` (`VERSION`), `libexec/perpetua/session`
   (`PERPETUA_VERSION`) and `CITATION.cff` (`version` and `date-released`).
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, add a new
   empty `## [Unreleased]` section above it, and update the link references at the bottom.
3. Run `make lint test docs dist`.
4. Open a pull request titled `chore(release): vX.Y.Z` and merge it once it is green.
5. Tag the merge commit and push the tag:

   ```sh
   git tag -s vX.Y.Z -m "Perpetua X.Y.Z"
   git push origin vX.Y.Z
   ```

6. The [release workflow](.github/workflows/release.yml) checks that the tag matches every
   version string and has a dated changelog section, runs the checks, builds
   `perpetua-X.Y.Z.tar.gz` with `SHA256SUMS` and a build provenance attestation, and
   publishes the GitHub release with the changelog section as its notes.

A tag with a pre-release suffix, such as `v1.1.0-rc.1`, is published as a pre-release.

## Licence

Perpetua is licensed under the [Apache License 2.0](LICENSE). Contributions are accepted
under the same licence, as stated in section 5 of the licence.
