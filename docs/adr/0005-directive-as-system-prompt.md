# ADR 0005: Deliver the directive as an appended system prompt

## Status

Accepted

## Date

2026-10-19

## Context

An unattended session needs standing rules that an interactive session does not: nobody will answer a question asked in the conversation; the plan must be followed in order; unfinished work from a previous session comes first; certain actions are forbidden (purchases, pushes to the default branch, merges with failing checks, writing secrets, editing Perpetua's own files); the session ends with a short report. Perpetua calls this text the directive.

There are three places to put it:

1. **In the prompt** passed to `claude -p`.
2. **In the project's `CLAUDE.md`**, which Claude Code loads automatically.
3. **In the system prompt**, through `--append-system-prompt`.

The prompt is also needed for something else. In production, the most effective prompt was a skill invocation, `/autonomous-mode`, which keeps a single session working through a plan for hours instead of stopping after one task. A slash command must be the prompt itself; it cannot be combined with several paragraphs of rules without changing how it is interpreted.

`CLAUDE.md` is shared with the operator's interactive sessions and with other contributors. Rules such as "never ask a question, nobody will answer" are wrong in an interactive session. It is also a file the agent edits as part of its normal work.

## Decision

The directive lives in its own file, `DIRECTIVE_FILE`, by default `.perpetua/directive.md` in the project, and the runner passes its content to Claude Code with `--append-system-prompt`, read afresh at every session. The prompt (`PROMPT`, default `/autonomous-mode`, template `/autonomous-mode follow the plan`) stays free for the instruction that drives the work.

The full command line is:

```text
claude -p PROMPT --output-format stream-json --verbose CLAUDE_ARGS... [--model MODEL] --append-system-prompt "<directive>"
```

A missing directive does not prevent the session: the runner logs `warning: no directive at <path>, the session runs on its prompt alone`.

`perpetua init` scaffolds a default directive and never overwrites an existing one.

## Consequences

- The directive applies only to Perpetua's sessions. Interactive sessions in the same repository are unaffected.
- The prompt can be a skill invocation, a slash command or plain text, independently of the rules. `/autonomous-mode` works unchanged.
- Appended to the system prompt, the rules sit above the conversation and above any text the agent reads in files. This raises the bar for prompt injection but does not remove it ([threat T1](../security/threat-model.md#t1-prompt-injection-through-repository-content)).
- Claude Code's default system prompt and the project's `CLAUDE.md` remain in effect; the directive adds to them rather than replacing them. Conflicts between the directive and `CLAUDE.md` are resolved by the model, so keep them consistent.
- The directive is a file in the repository by default, versioned and reviewed like code. A project that does not want contributors to change it through pull requests can point `DIRECTIVE_FILE` at an absolute path outside the repository.
- The content travels as one command-line argument, limited by Linux to 128 KiB. Directives are a page long; the limit is far away.

## Alternatives considered

**Rules in the prompt.** Incompatible with a slash-command prompt, and gives the rules the same standing as any other user message. Rejected.

**Rules in `CLAUDE.md`.** Leaks unattended-only rules into interactive sessions, mixes the operator's standing order with the project's general instructions, and exposes it to the agent's routine edits. Rejected.

**`--system-prompt` (replacing the system prompt).** Would discard Claude Code's own system prompt, which carries tool usage conventions the agent needs. Rejected in favour of appending.

**An output style or a settings file.** Applies to every session in the project, including interactive ones, unless managed per invocation, which brings back the same mechanism with more moving parts. Rejected.
