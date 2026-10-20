# ADR 0004: Yield to the operator by detecting recent Claude Code transcripts

## Status

Accepted

## Date

2026-10-18

## Context

The machine that runs Perpetua is often the operator's own workstation, and the subscription it uses is the operator's own ([ADR 0003](0003-subscription-auth.md)). When the operator is working with Claude Code, an autonomous session started at the same moment competes for the same usage allowance, may edit the same repository, and adds load to the machine. The operator must take precedence, without having to remember to pause anything.

Detecting "the operator is working" in general (keyboard idle time, open editors, logged-in sessions) is platform-specific, unreliable over SSH and inside WSL, and says nothing about whether the operator is using Claude. What matters is narrower: is the operator using Claude Code right now?

Claude Code writes every session's transcript as a JSON Lines file under `~/.claude/projects/<encoded path>/<session id>.jsonl`, updated as the session progresses. A recently modified transcript is direct evidence of Claude Code activity on the account. The difficulty is that Perpetua's own sessions write transcripts in the same place.

## Decision

Before starting a session, the runner looks for any `*.jsonl` file under `PRESENCE_DIR` (default `~/.claude/projects`) modified within the last `PRESENCE_WINDOW_MIN` minutes (default 10), using `find -mmin`. If one exists, the run ends with `gate:presence` and exit status `0`; the timer tries again one interval later.

Perpetua's own sessions are excluded by identity:

- While a session runs, the runner watches its stream-json journal and appends the Claude Code session id to the project's `own-sessions` file as soon as Claude Code announces it, normally within seconds. `record.py` appends it at the end if it was missed.
- The gate concatenates the `own-sessions` files of **all** projects in the state root and drops every recent transcript whose path contains `/<id>.jsonl` (the session) or `/<id>/` (its subagents, under `<id>/subagents/`).

`PRESENCE_WINDOW_MIN=0` disables the gate. `--force` (and `PERPETUA_FORCE=1`) skips it, for a supervised run started by the operator while at the keyboard. Timer-driven runs never skip it.

## Consequences

- The operator gets priority automatically, within one interval of starting to use Claude Code, with no configuration and no platform-specific code.
- The loop resumes by itself once the operator has been idle for the window, which typically means sessions run at night, at weekends and during long meetings.
- Detection is cheap and has no dependency: one `find`, one `grep`.
- Activity outside Claude Code (an editor, a terminal) is not detected. Operators who edit the same checkout by hand should use a separate clone or worktree ([threat T6](../security/threat-model.md#t6-concurrent-edits-with-the-operator)).
- Any Claude Code process on the account counts as the operator, including tools other than Perpetua that drive Claude Code.
- Session ids are registered while the session runs, so several projects on one host can run in parallel without mistaking each other for the operator. A first version recorded ids only at the end of a session, and projects then blocked each other for the whole length of a session. Print mode does not let the caller choose the id, which is why it is read from the output.
- If Claude Code has not announced its id within two minutes, the session is excluded only once it ends.
- An interactive session that is left open but idle stops writing, and stops counting after the window.
- `own-sessions` grows by one line per session and is never pruned. At tens of bytes per line this is negligible for years of operation.

## Alternatives considered

**Desktop idle time** (X11, Wayland, `loginctl` idle hints). Not available over SSH, on headless servers or reliably on WSL, and unrelated to Claude usage. Rejected.

**Process detection** (`pgrep claude`). Cannot distinguish the operator's process from Perpetua's without extra bookkeeping, counts idle sessions left open for days, and misses nothing more than transcripts already reveal. Rejected.

**A manual "I am working" switch.** Relies on the operator remembering, which is the failure mode this gate exists to remove. `pause` remains available for explicit control.

**Excluding Perpetua's transcripts by location**, for example by running sessions with a different `HOME`. Would also separate credentials, skills and settings from the operator's, and break the subscription login sharing. Rejected in favour of identifying sessions by id.
