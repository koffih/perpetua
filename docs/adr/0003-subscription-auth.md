# ADR 0003: Run on the Claude subscription login, not an API key

## Status

Accepted

## Date

2026-10-17

## Context

Claude Code authenticates either with a Claude subscription login (an OAuth credential stored in `~/.claude/` by `/login`) or with an API key (`ANTHROPIC_API_KEY`), billed per token.

An unattended loop runs many hours a day. Under per-token billing, the cost of a day of autonomous work is open-ended and depends on how much context the agent reads, which is not under the operator's control. Under a subscription, cost is fixed and the constraint becomes the subscription's usage limits, which the agent shares with the operator's interactive use.

Anthropic publishes an autonomous-coding quickstart that runs an agent in a loop through the Agent SDK. It was evaluated as the base for this tool and rejected, for three reasons:

1. It requires a metered API key, so the cost model above applies.
2. It restricts the agent to a short command allowlist. That is a sound default for a demonstration, but real stacks need many tools (package managers, build systems, database clients, container tooling, `gh`), and an allowlist that tight stops sessions on every project the loop was meant for.
3. It generates its own feature list from a specification and works through that list, whereas the projects in question already have a plan, written and maintained with the operator, that the agent must follow.

## Decision

Perpetua invokes the `claude` CLI, unmodified, in print mode (`claude -p`) under the user's account, and relies on whatever authentication that account's Claude Code uses. The supported and documented setup is the subscription login.

- Perpetua stores no credential and reads none. `perpetua doctor` only checks that `~/.claude/.credentials.json` exists or that `ANTHROPIC_API_KEY` is set, and warns otherwise.
- Usage limits are an expected event, not a failure: the runner detects them in the session journal (`LIMIT_PATTERN`), records the outcome `rate_limited` and pauses the project for `BACKOFF_SECONDS`.
- The presence gate gives the operator priority on the shared allowance ([ADR 0004](0004-operator-presence-yield.md)).
- The tools available to the agent are those of Claude Code, configured per project, with permissions either skipped or allowlisted in the project's settings.
- The work to do comes from the project's own plan, through the directive and the prompt.

## Consequences

- The cost of running Perpetua is the subscription the operator already pays. There is no per-token bill to watch.
- Throughput is bounded by usage limits. The loop slows down instead of spending more, and the back-off prevents it from repeatedly hitting the limit.
- The agent and the operator draw on the same allowance. Long autonomous sessions can leave less for interactive work; the presence gate mitigates this but does not reserve capacity.
- Authentication is renewed by Claude Code. When the login expires or is revoked, sessions end as `error` until the operator runs `/login` again as the same user.
- An `ANTHROPIC_API_KEY` present in the runner's environment reaches Claude Code and may take precedence over the login, silently switching to metered billing. Keep it out of the user manager's environment, and out of your shell when using `perpetua run`.
- `cost_usd` in session records is Claude Code's estimate from token usage. Under a subscription it is informative, not billed.
- Operators remain bound by the terms of their subscription for automated use; Perpetua does not change them.

## Alternatives considered

**Anthropic's autonomous-coding quickstart.** Rejected for the three reasons stated in the context: metered API key, command allowlist too narrow for real stacks, and a self-generated feature list in place of the project's plan.

**Agent SDK with an API key, written for Perpetua.** Same cost model, plus the need to reimplement what Claude Code already provides: tools, permissions, skills, project instructions, transcripts. Rejected.

**Support both, selected per project.** Perpetua does not prevent it: an API key in the environment works. Making it a first-class option would add credential handling to Perpetua, which it deliberately has none of.
