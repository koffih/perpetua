# Governance

This document describes how decisions are made in the Perpetua project.

## Roles

**Users** run Perpetua. They help the project by reporting bugs, proposing improvements
and answering other users' questions.

**Contributors** submit pull requests, review changes and improve the documentation.
Anyone can become a contributor by following [CONTRIBUTING.md](CONTRIBUTING.md).

**Maintainers** review and merge pull requests, triage issues, cut releases and handle
security reports. They are listed in [`.github/CODEOWNERS`](.github/CODEOWNERS).
The current maintainer is [@koffih](https://github.com/koffih), who founded the project
and acts as its lead maintainer.

## Decision process

Day-to-day decisions, such as merging a bug fix or a documentation change, are taken by
lazy consensus: a maintainer approves the pull request, and it is merged once checks pass
and no objection is outstanding.

Significant decisions are recorded as architecture decision records (ADRs) in
[`docs/adr/`](docs/adr/), published in the
[documentation](https://koffih.github.io/perpetua/adr/). A decision is significant when it
changes the security model or a guardrail, adds a runtime dependency or a supported
platform, changes a stable interface (CLI commands and options, configuration keys, state
file formats, exit statuses or runner log lines), or reverses an earlier ADR.

To propose one:

1. Open an issue describing the problem and the options.
2. Open a pull request adding an ADR in `docs/adr/` with the status `Proposed`, following
   the structure of the existing records: context, decision, consequences.
3. Discussion takes place on the pull request for at least seven days, so that users can
   weigh in.
4. The lead maintainer accepts or rejects the ADR, explaining the reasoning on the pull
   request. An accepted ADR is merged with the status `Accepted` before or with the
   implementation.

ADRs are never deleted. A decision that no longer holds is marked `Superseded` and links
to the record that replaces it.

## Becoming a maintainer

A contributor who has made sustained, high-quality contributions and reviews over several
months may be invited to become a maintainer by the existing maintainers. Maintainers who
are no longer active may step down, or be moved to emeritus status after a year of
inactivity.

## Changes to this document

Changes to this governance follow the process for significant decisions.
