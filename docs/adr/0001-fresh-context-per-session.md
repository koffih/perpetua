# ADR 0001: A fresh context for every session

## Status

Accepted

## Date

2026-10-16

## Context

An unattended agent must keep working on a project for days or weeks. Two shapes are possible: one long-lived conversation that is continued (`claude --continue`, `--resume`) or kept open, or a series of independent sessions, each starting from an empty context.

A long-lived conversation accumulates context until the model's window is full. Claude Code then compacts it, replacing the history with a summary. Over many compactions, the summary drifts: decisions made early are lost or distorted, mistaken beliefs about the repository persist, and nothing outside the conversation records what the agent knows. When the conversation is corrupted (a crash in the middle of a tool call, an expired login, a killed process), resuming it is unreliable.

In production, the loop Perpetua was extracted from ran one `claude -p` per wake-up from the start. The projects it works on already keep their own durable memory: a plan with checkboxes, progress notes, pull requests, commit history. The agent can rebuild its working context from them in a few minutes.

## Decision

Every session starts with a fresh context: the runner invokes `claude -p PROMPT` without `--continue` or `--resume`, from the project directory, and the session ends when Claude Code exits.

Continuity between sessions is carried entirely by the repository and by Perpetua's state:

- the project's plan, progress notes and instructions files, which the directive tells the agent to read first;
- git: branches, uncommitted work, open pull requests, which the directive tells the agent to inspect and finish first;
- the directive itself, identical for every session;
- the closing report of each session, kept in `summaries.md` for the operator.

The default directive requires the agent to stop cleanly, with everything committed and documented, before starting a task it could not finish.

## Consequences

- No state hides in a conversation. Everything the next session knows is in files the operator can read, review and correct.
- A crashed, killed or timed-out session costs at most its own uncommitted work. The next one starts clean; nothing needs repairing.
- The `MAX_SESSION` ceiling and `timeout` are safe to enforce, since nothing is lost by ending a session beyond its uncommitted changes.
- Each session spends its first minutes re-reading the project. This is overhead, paid once per session, and the reason sessions are long (hours, with `/autonomous-mode`) rather than one task each.
- Projects must externalise their state: a plan file and progress notes are effectively required. A project without them gives the agent nothing to resume from.
- A prompt injection that succeeded in one session does not persist through conversation memory, only through files it caused to be written ([threat T1](../security/threat-model.md#t1-prompt-injection-through-repository-content)).

## Alternatives considered

**Resume the previous conversation** (`claude --continue` or `--resume <id>`). Saves the re-reading cost. Rejected: compaction drift over many sessions, fragile after crashes, and the memory it relies on is opaque to the operator.

**One conversation kept running indefinitely**, fed new prompts. Rejected for the same reasons, amplified, and because a single process running for weeks conflicts with the time ceiling and the stop controls.

**A memory file maintained by Perpetua** (for example, summaries injected into the next prompt). Rejected: it duplicates what the project's own notes already do, and it gives Perpetua opinions about the project's content. The closing reports are kept for humans and deliberately not fed back to the agent.
