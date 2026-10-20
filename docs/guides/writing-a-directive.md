---
description: How to write the standing order every Perpetua session receives, with the shipped template explained line by line.
---

# Writing a directive

The directive is the standing order of your project. Its full text is appended to the system prompt of every session, so it applies with system prompt weight to everything the agent does, on every wake-up, without depending on the agent remembering anything.

By default it lives at `PROJECT_DIR/.perpetua/directive.md` (`DIRECTIVE_FILE`, relative to `PROJECT_DIR` unless absolute). `perpetua init` copies the shipped template there unless a directive already exists. Commit it: a change to the directive changes how your project is worked on, and deserves review like any other change.

## Prompt, directive, project instructions

Four texts shape every session. Each has one job:

| Text | Where | Job | Changes |
| --- | --- | --- | --- |
| `PROMPT` | `NAME.env` | **What to do now.** The user turn of the session. | Rarely |
| Directive | `.perpetua/directive.md` | **How to behave when nobody is watching.** Unattended-specific rules. | Occasionally |
| `CLAUDE.md` / `AGENTS.md` | repository | **How this project works.** Build, test, conventions. Shared with interactive sessions. | Often |
| `PLAN.md` and progress notes | repository | **Where we are.** The state the next session continues from. | Every session |

Keep project conventions in `CLAUDE.md`, where your interactive sessions benefit from them too. Keep the directive about autonomy: what to pick, when to stop, what is forbidden, where to leave questions.

## Anatomy of the shipped template

```markdown title=".perpetua/directive.md"
--8<-- "share/perpetua/templates/directive.md"
```

**Preamble.** *Unattended session started by Perpetua. Nobody reads this session live: never ask a question in the conversation, nobody will answer it.*
Sets the frame. Without it, a model trained for interactive use will sometimes stop and ask for confirmation, which in `claude -p` ends the session with nothing done.

**1. Orientation.** *Read the project instructions, `PLAN.md` and the latest progress notes, then follow them.*
Every session starts with a fresh context. This line makes rebuilding context the first action, from the files the operator controls.

**2. Repository state first.** *Current branch, open pull requests, uncommitted work left by a previous session. Finish what was started first.*
The previous session may have been cut by `MAX_SESSION` or a usage limit in the middle of a task. Resuming it before taking new work prevents half-finished branches from piling up.

**3. One task, carried through.** *Next task whose dependencies are done, in plan order: dedicated branch, code, tests, pull request. Tick the task, update the notes.*
Defines the unit of work and the definition of done. The plan order is the operator's prioritisation; "dependencies are done" stops the agent from building on unmerged foundations.

**4. Chain, then stop cleanly.** *Chain tasks while the session allows. Stop cleanly, with everything committed and documented, before starting a task you could not finish.*
Uses the session well without leaving debris. "Committed and documented" is what makes the next fresh session productive.

**5. The question protocol.** *Write it in `PLAN.md` on the line `Pending question:` with context, options and your recommendation, then continue with the tasks that do not depend on it. If none remain, end the session.*
The only channel from the agent to you. It is wired to the [attention gate](../concepts/guardrails.md#gate-5-attention): a pending question throttles sessions to one per `QUESTION_THROTTLE_SECONDS` until you answer.

**6. Forbidden actions.** Purchases and sign-ups, publishing outside the project's repositories, pushing to the default branch or force-pushing, merging with a failing check, deleting real data, writing secrets, editing `.perpetua/`.
The irreversible or externally visible actions. Each one is either impossible to undo or visible to people outside the project. The last item keeps the loop under human control: the agent cannot rewrite its own rules.

**7. The report.** *At most five lines: tasks done, pull requests, progress, pending question if any.*
This text becomes the final `result` of the session, which `record.py` writes to `summaries.md`. Five lines is what you can read for ten sessions over a coffee.

## The pending question convention

The attention gate and the directive must agree on one line format. With the defaults (`QUESTION_FILE=PLAN.md`, `QUESTION_PATTERN='Pending question[*_ ]*:'`):

```markdown title="PLAN.md"
# Plan

**Pending question:** none
```

When the agent needs you, it rewrites that line:

```markdown title="PLAN.md"
**Pending question:** Which payment provider? Context: task 7 needs card payments in EUR
and USD. Options: Stripe (best API, 1.5% + 0.25 EUR), Adyen (cheaper above 1M EUR/year,
heavier onboarding). Recommendation: Stripe now, revisit at scale. Tasks 7 and 8 wait;
tasks 9 to 12 do not depend on it.
```

Rules that keep the gate reliable:

- The gate reads the **first** line matching `QUESTION_PATTERN`. The default pattern requires a colon right after "Pending question" (Markdown emphasis such as `**` may sit in between), so a heading like `## Pending questions` or a sentence mentioning pending questions does not match. Keep a single `Pending question:` line, near the top of the file.
- The match is case-sensitive: `pending question:` in lower case does not count.
- The value is whatever follows the **first colon** on that line. Leading `*` and `_` are ignored, so `**Pending question:**` works.
- "No question" is an empty value, `none`, `n/a`, `na`, `-` or `aucune`, in any case, optionally followed by a period (`QUESTION_NONE`).
- Write the whole question on that one line, or at least its first sentence. Continuation lines are fine for humans; the gate only needs the first.
- When you answer, write the answer where the agent will find it (in the plan, next to the task) and reset the line to `none`.

If your plan uses another convention, change `QUESTION_FILE`, `QUESTION_PATTERN` and `QUESTION_NONE` in the project configuration, and the directive line that describes it, together.

## Patterns

**State the definition of done.** "Tests pass locally and in CI, the pull request description explains the change" is checkable. "Do a good job" is not.

**Name the files.** "`PLAN.md`", "`docs/progress.md`", "`CHANGELOG.md` under Unreleased". Precise paths make behaviour reproducible across fresh sessions.

**Forbid by category, then by example.** "Never publish outside the project's repositories (no package release, no blog post, no comment on third-party issues)".

**Say what to do instead.** Every prohibition that might block progress should come with the alternative: "if a migration is needed on production data, write it and the rollback, open the pull request, and ask in `Pending question:`".

**Bound the blast radius.** "Touch only `services/billing/` and its tests" is a valid directive line for a focused campaign.

**Keep it short.** The shipped template is 21 lines. Every line is read on every wake-up, and every line competes for attention with the task.

## Anti-patterns

!!! failure "Asking for confirmation"
    "Confirm with the user before deleting files." Nobody is there; the session either stops or ignores the rule. Write a decision rule instead: "never delete files outside the task's scope".

!!! failure "Project documentation in the directive"
    Build commands, architecture notes and style guides belong in `CLAUDE.md`. In the directive they bloat every session and drift from the version your interactive sessions use.

!!! failure "Unbounded goals"
    "Improve the codebase." With no plan to anchor it, a fresh session every 15 minutes will produce a stream of unrelated refactors. Point the agent at a plan.

!!! failure "Rules that depend on memory"
    "Continue where you left off." The session has no memory of the previous one. "Read the progress notes, then continue" works.

!!! failure "Letting the agent edit the directive"
    If the agent may rewrite its own rules, they are not rules. Keep the `.perpetua/` prohibition.

## Testing a directive

Change the directive, then run one supervised session and read it:

```bash
perpetua run acme-api --force
perpetua summaries acme-api -n 1
```

For a closer look at what the agent did and why, read the journal of the last session. Each line is a stream-json message:

```bash
jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' \
  "$(jq -r .journal ~/.local/state/perpetua/acme-api/last-session.json)"
```
