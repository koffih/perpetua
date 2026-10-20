---
description: From an empty registration to an overnight cadence and a morning review.
---

# Quickstart

This walkthrough takes a repository from zero to an overnight cadence in about ten minutes, plus the length of one supervised session. It assumes Perpetua is [installed](installation.md) and `perpetua doctor` reports `Host ready`.

!!! warning "Before you start"
    Sessions run with `--dangerously-skip-permissions` by default, because nobody is there at night to answer a permission prompt. The agent can run any command your user can. Start on a repository that has a remote, branch protection on the default branch, and CI. Read [Guardrails](../concepts/guardrails.md) for what Perpetua enforces and what it does not.

## 1. Give the project a plan

Perpetua does not invent work. Each session starts with a fresh context and rebuilds its picture from files in the repository, so those files must exist. The shipped directive expects:

- `PLAN.md`: an ordered task list with checkboxes, and a `Pending question:` line.
- Progress notes: any file the plan points to (for example `docs/progress.md`) where each session leaves a dated entry.
- `CLAUDE.md` or `AGENTS.md`: project conventions, how to build and test.

A minimal `PLAN.md`:

```markdown
# Plan

Pending question: none

## Tasks

- [x] 1. Set up the HTTP server skeleton
- [ ] 2. Add the /health endpoint with a test
- [ ] 3. Add request logging (depends on 2)
- [ ] 4. Document the API in README.md

Progress notes: docs/progress.md
```

## 2. Register the project

```bash
cd ~/src/acme-api
perpetua init
```

```text
==> Registered acme-api
  ✓ configuration   /home/dev/.config/perpetua/projects/acme-api.env
  ✓ directive       /home/dev/src/acme-api/.perpetua/directive.md
  ✓ state           /home/dev/.local/state/perpetua/acme-api/

Next
  1. Review the directive: it is the standing order every session receives.
  2. Run one supervised session:   perpetua run acme-api --force
  3. Start the cadence:            perpetua enable acme-api
```

The project name is derived from the directory name (lowercased, anything outside `a-z 0-9 _ -` replaced by `-`). Choose it explicitly with `perpetua init DIR --name NAME`. `init` creates three things:

| File | Purpose |
| --- | --- |
| `~/.config/perpetua/projects/NAME.env` | The project configuration, a shell file of `KEY=value` lines. See [Configuration](../reference/configuration.md). |
| `.perpetua/directive.md` | The standing order appended to the system prompt of every session. Kept if it already exists. |
| `.perpetua/.gitignore` | Ignores `.perpetua/STOP`, so the stop switch never gets committed. |

Commit `.perpetua/directive.md`: it is part of how the project is run, and reviewing changes to it matters.

## 3. Review the directive and the configuration

Open `.perpetua/directive.md`. The shipped template is a sound default for plan-driven work: read the plan, finish unfinished work first, one branch and pull request per task, ask questions in `PLAN.md` instead of in the conversation, and a list of forbidden actions. Adapt it to your project; [Writing a directive](../guides/writing-a-directive.md) explains each line.

Then look at the configuration:

```bash
${EDITOR:-vi} ~/.config/perpetua/projects/acme-api.env
```

The values to check on day one:

```bash
PROMPT='/autonomous-mode follow the plan' # (1)!
MAX_SESSION=4h # (2)!
QUESTION_FILE=PLAN.md # (3)!
MODEL= # (4)!
```

1. What each session is asked to do. Requires the `autonomous-mode` skill; replace it with a plain instruction if you do not use the skill.
2. Hard ceiling of one session, in `timeout(1)` syntax. A session that reaches it is killed and recorded as `timeout`.
3. The file the attention gate reads for a `Pending question:` line. Empty disables the gate.
4. Empty means the Claude Code default. Set `opus`, `sonnet` or a full model id to pin it.

## 4. Run one supervised session

```bash
perpetua run acme-api --force
```

`run` executes one session in the foreground, exactly as the timer would. `--force` skips the presence gate (you are, after all, at the keyboard and probably just used Claude Code) and the attention gate. It never skips the stop flag, the lock or the back-off.

The runner prints its log lines to your terminal while the session works:

```text
[acme-api] session:start 20261020T183012 (limit 4h)
[acme-api] session:end 20261020T183012 outcome=ok exit=0 duration=41min
```

Watch what the agent does in a second terminal, either through `git log` and the pull requests it opens, or by following the raw journal:

```bash
tail -f ~/.local/state/perpetua/acme-api/sessions/*.jsonl
```

When it ends, read its closing report:

```bash
perpetua summaries acme-api -n 1
```

```markdown
## 2026-10-20 18:30 | ok

Duration 41 min, 63 turns, exit 0.

Tasks done: 2 (/health endpoint with test).
Pull requests: #14 (feat/health-endpoint), CI green.
Progress: 2/4, notes updated in docs/progress.md.
Pending question: none.
```

If the session did something you did not want, fix the directive before going further. This is the cheapest moment to do it.

## 5. Start the cadence

```bash
perpetua enable acme-api --interval 15min
```

```text
==> Cadence enabled for acme-api
  ✓ timer perpetua@acme-api.timer, next session 15min after each run ends
```

`enable` installs `perpetua@.service` and `perpetua@.timer` into `~/.config/systemd/user/`, writes the interval as a per-project drop-in, reloads systemd, starts the timer, and prints the effective interval. Without `--interval`, a project keeps the interval it was given before, or 15 minutes if it never had one. The interval is measured from the moment the previous run **ended**, so a four-hour session followed by a 15-minute interval means the next wake-up comes four hours and fifteen minutes after the first one started. Accepted forms: `900` (seconds), `90s`, `15min`, `1h`.

Check when the next wake-up is due:

```bash
perpetua status acme-api
```

!!! tip "Going to bed"
    The presence gate yields while you have used Claude Code in the last `PRESENCE_WINDOW_MIN` minutes (10 by default). Once you stop, the next wake-up after that window starts a session. There is nothing to arm.

## 6. Review in the morning

=== "Status"

    ```bash
    perpetua status acme-api
    ```

    Cadence, next wake-up, whether the project is paused or backing off, the outcome of the last session and the last runner log line.

=== "Summaries"

    ```bash
    perpetua summaries acme-api -n 5
    ```

    The closing reports of the last five sessions, oldest first. Each heading carries the start time and the outcome.

=== "Runner log"

    ```bash
    perpetua logs acme-api
    ```

    The last 40 lines of the runner log: one line per gate decision, two per session (`session:start`, `session:end`). A night with a long session and a few yields looks like this:

    ```text
    2026-10-20 23:02:41 gate:presence operator active in Claude Code within 10 min, yielding
    2026-10-20 23:18:10 session:start 20261020T231810 (limit 4h)
    2026-10-21 02:47:55 session:end 20261020T231810 outcome=ok exit=0 duration=209min
    2026-10-21 03:03:26 session:start 20261021T030326 (limit 4h)
    2026-10-21 05:31:02 session:end 20261021T030326 outcome=rate_limited exit=1 duration=147min
    2026-10-21 05:31:02 backoff: usage limit reached, pausing 60 min
    2026-10-21 05:46:33 gate:backoff usage limit, waiting until 2026-10-21 06:31:02
    ```

=== "The work itself"

    ```bash
    gh pr list --author @me
    git -C ~/src/acme-api log --oneline -20
    ```

    Perpetua records sessions; the work lives in branches and pull requests. Review and merge them as you would a colleague's.

If the agent wrote a question for you, it sits on the `Pending question:` line of `PLAN.md`. Answer it in the plan (and reset the line to `Pending question: none`), and the attention gate reopens on the next wake-up.

## Where to go next

- [Operating Perpetua](../guides/operating.md): pausing, stopping, journald, history, upgrades.
- [Notifications](../guides/notifications.md): be told when a session does not end `ok`.
- [Session lifecycle](../concepts/session-lifecycle.md): exactly what happens on each wake-up.
