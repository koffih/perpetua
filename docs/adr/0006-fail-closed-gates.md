# ADR 0006: Fail-closed gates, and the project's own CI as the judge

## Status

Accepted

## Date

2026-10-20

## Context

Every wake-up must decide whether a session may start. The reasons not to start are varied: the operator paused the project, a session is already running, a usage limit was hit, the operator is at work, a question is waiting for an answer. These checks will sometimes fail in unforeseen ways, and when they do, the safe result is no session, not an unsupervised one.

Two more questions follow. How should a skipped run look to systemd? A non-zero exit marks the service failed; repeated failures look like an incident and train operators to ignore failed units. And who decides whether a session's work was good?

One design considered puts a judge in the runner: after each session, inspect the result (commits made, plan file updated, no test deleted, clean tree, the project's check command still passing) and stop the loop when anything looks wrong. In the production setting Perpetua comes from, this design does not work. The project spans several repositories: a session may change three of them, through branches and pull requests, and the runner, sitting in one directory, sees only part of it. The authoritative checks run in CI, on the hosting service, often minutes after the session ended, on infrastructure the runner cannot reproduce locally. A local judge would be both blind to most of the work and a weaker copy of checks that already exist.

## Decision

**Gates.** The runner evaluates five gates, in a fixed order: stop flag, exclusivity lock, usage-limit back-off, operator presence, pending question. The first gate that closes logs one `gate:` line and ends the run with exit status `0`. A session starts only when every gate is open.

**Fail closed.** Each gate is written so that an inconclusive check closes it or is harmless: the stop flag is the existence of a file; the lock is a non-blocking `flock` that refuses on contention; a back-off file that exists is honoured until it is provably expired; any recent transcript not proven to be Perpetua's counts as the operator.

**Exit status `0` for closed gates.** Skipping is the normal state of a well-behaved loop. The service stays successful, the timer keeps its cadence ([ADR 0002](0002-systemd-user-timers.md)), and `failed` is reserved for real configuration errors (status `2` and `3`).

**`--force` is limited.** `--force` and `PERPETUA_FORCE=1` skip only the presence and attention gates, which exist to protect the operator and can be waived by the operator. They never skip the stop flag, the lock or the back-off: those protect the project and the quota against the operator's own mistake too. To lift them, the operator uses `perpetua resume` and deletes `.perpetua/STOP`, deliberate actions that leave a trace.

**No judge in the runner.** Perpetua classifies how a session ended (`ok`, `error`, `timeout`, `rate_limited`, `interrupted`) and records it. It does not assess the work. The judge is the project's own CI and pull request process: the directive forbids pushing to the default branch and merging with a failing check, and branch protection on the hosting service enforces both regardless of what the agent does.

## Consequences

- A bug or an unexpected condition in a gate errs towards not running a session. The cost is lost time, never an unwanted session.
- `systemctl --user --failed` stays meaningful: a failed Perpetua unit is a configuration problem to fix, not a skipped run.
- The runner stays small and project-agnostic: it knows nothing about languages, test commands or repository layouts, and works the same on single-repository and multi-repository projects.
- Quality control is only as good as the project's CI and branch protection. A project without required checks and protected branches has no judge at all; the [hardening checklist](../security/threat-model.md#hardening-checklist) makes them the first items after account isolation.
- A session can produce poor work that never fails a check: an `ok` outcome is not a quality signal. Reviewing pull requests and closing reports remains the operator's job.
- `--force` cannot get the operator out of a back-off by accident; `perpetua resume` can, on purpose.

## Alternatives considered

**A judge in the runner** (check commits, plan file, deleted tests, working tree and a local check command after each session, and stop the loop on any anomaly). Rejected: blind to changes in other repositories and to CI, which runs remotely and later; duplicates checks the project already enforces, less well; and couples the runner to each project's layout and tooling.

**Non-zero exit for closed gates.** Rejected: floods the failed-unit list with normal events and hides real failures.

**`--force` bypassing every gate.** Convenient, and a reliable way to run a second session over a running one, or to burn through a usage limit. Rejected.

**Fail open** (start the session when a check cannot be evaluated). Rejected: the asymmetry between a missed session and an unwanted one is the point of having gates.
