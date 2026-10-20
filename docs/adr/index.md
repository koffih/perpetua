---
description: The architecture decision records of Perpetua, what they are and how they are maintained.
---

# Architecture decision records

An architecture decision record (ADR) captures one significant design decision: the forces at play when it was made, the choice, its consequences and the alternatives that were rejected. Perpetua's records follow the format proposed by Michael Nygard.

Perpetua was extracted from a loop that has run unattended since October 2026 on a large private multi-repository codebase. Most of these decisions were first made there, under production conditions, and written down when the tool was extracted. They explain why Perpetua is shaped the way it is, and they are the place to start before proposing a change to its architecture.

## Records

| ADR | Title | Status | Date |
| --- | --- | --- | --- |
| [0001](0001-fresh-context-per-session.md) | A fresh context for every session | Accepted | 2026-10-16 |
| [0002](0002-systemd-user-timers.md) | systemd user timers as the scheduler | Accepted | 2026-10-16 |
| [0003](0003-subscription-auth.md) | Run on the Claude subscription login, not an API key | Accepted | 2026-10-17 |
| [0004](0004-operator-presence-yield.md) | Yield to the operator by detecting recent Claude Code transcripts | Accepted | 2026-10-18 |
| [0005](0005-directive-as-system-prompt.md) | Deliver the directive as an appended system prompt | Accepted | 2026-10-19 |
| [0006](0006-fail-closed-gates.md) | Fail-closed gates, and the project's own CI as the judge | Accepted | 2026-10-20 |

## Statuses

Proposed
:   Under discussion in a pull request.

Accepted
:   In force. The code follows it.

Superseded
:   Replaced by a later record, which links back to it.

Deprecated
:   No longer applies, without a replacement.

## Proposing a decision

Records are immutable once accepted, apart from status changes and links. To change a decision, open a pull request that adds a new record with the next number, states which record it supersedes, and updates the status of the old one. Each record has the sections Status, Date, Context, Decision, Consequences and Alternatives considered.
