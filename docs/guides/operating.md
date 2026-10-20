---
description: Day-2 operations for Perpetua, from the morning review to upgrades and uninstalling.
---

# Operating Perpetua

Once the cadence is enabled, Perpetua needs a few minutes of attention a day. This guide covers the routine and the occasional.

## The morning review

A five-minute review, in this order:

```bash
perpetua status # (1)!
perpetua summaries acme-api -n 10 # (2)!
perpetua logs acme-api # (3)!
gh pr list --author @me # (4)!
grep -nE 'Pending question[*_ ]*:' ~/src/acme-api/PLAN.md # (5)!
```

1. Every project at a glance: cadence and next wake-up, `ready`, `paused`, `session running` or `backing off until ...`, and the last outcome.
2. The closing reports of the night, oldest first. Anything that is not `| ok` in a heading deserves a look.
3. The last 40 runner log lines: when sessions started and ended, and why wake-ups were skipped.
4. The work itself. Review and merge as you would for a colleague.
5. The same pattern as the attention gate's default `QUESTION_PATTERN`. A question waiting for you throttles the project to one session per six hours until you answer it.

Look for these signals:

| Signal | Likely cause | Action |
| --- | --- | --- |
| Many `gate:presence` lines at night | A Claude Code session left open, or a scheduled job of your own that runs Claude Code | Close idle sessions; see [Guardrails](../concepts/guardrails.md#gate-4-operator-presence) |
| Repeated `outcome=timeout` | Tasks too large for `MAX_SESSION`, or a hanging command | Split tasks in the plan, or raise `MAX_SESSION` |
| Repeated `outcome=error` with short durations | Claude Code cannot start: login expired, binary moved | `perpetua doctor`, then `perpetua run NAME --force` to see the error |
| `outcome=rate_limited` every night | The subscription quota is exhausted | Longer `--interval`, fewer projects, or a smaller model via `MODEL` |
| `_No closing report was produced._` | Session killed or crashed before its final message | Read the journal |

## Pausing and resuming

=== "pause / resume"

    ```bash
    perpetua pause acme-api
    perpetua resume acme-api
    ```

    `pause` writes the current date into `~/.local/state/perpetua/acme-api/paused`. The timer keeps firing; every wake-up closes at the stop gate with `gate:stop paused by operator`. `resume` removes the flag **and** any pending back-off, and warns if the project still contains a `STOP` file.

=== "STOP file"

    ```bash
    touch ~/src/acme-api/.perpetua/STOP
    rm ~/src/acme-api/.perpetua/STOP
    ```

    Same effect as `pause`, but the switch lives in the working tree, so you can flip it from anywhere you can reach the files: an editor, a file manager, an SSH session, a script, without the `perpetua` CLI. It is ignored by git through `.perpetua/.gitignore`.

=== "disable / enable"

    ```bash
    perpetua disable acme-api
    perpetua enable acme-api
    ```

    Stops the timer itself. No wake-up happens at all, so nothing is logged. Use it for long breaks; use `pause` for short ones, because `status` then shows the project as `paused` instead of simply `disabled`.

None of these interrupt a session that is already running: it finishes normally (or at `MAX_SESSION`).

### Stopping a running session

To stop the session in progress immediately:

```bash
perpetua pause acme-api # (1)!
systemctl --user stop perpetua@acme-api.service # (2)!
```

1. First, so that the next wake-up does not start a new session.
2. systemd sends `SIGTERM` to the runner (`KillMode=mixed`). The runner forwards `SIGTERM` to the Claude Code session, waits for it to exit, and records it.

For a supervised `perpetua run`, `Ctrl-C` (or closing the terminal) does the same. The session is recorded with outcome `interrupted` and exit status 130, like any other session:

```text
2026-10-21 08:02:13 session:end 20261021T064010 outcome=interrupted exit=130 duration=82min
```

It appears in `last-session.json`, `history.jsonl` and `summaries.md`, and the post-session hook runs with `PERPETUA_OUTCOME=interrupted`.

!!! note "When nothing is recorded"
    systemd allows a stopping unit 90 seconds by default before it sends `SIGKILL` to every remaining process. A session that takes longer to exit, or a slow hook, is cut at that point. A machine crash or a power loss also leaves no record. In those cases the partial journal stays in `sessions/`, with no `session:end` line.

The next session will find the interrupted work in the repository; the shipped directive tells it to finish that first.

## Logs

Perpetua writes each decision to two places.

**The runner log**, `~/.local/state/perpetua/NAME/runner.log`, one timestamped line per event, read with `perpetua logs NAME` (last 40 lines) or `perpetua logs NAME -f` to follow. Post-session hook output is appended to it as well. See [Runner log](../reference/runner-log.md) for every line format.

**journald**, for timer runs. The runner also writes each line to standard error, prefixed with the project name, which systemd captures:

```bash
journalctl --user -u perpetua@acme-api                 # everything
journalctl --user -u perpetua@acme-api --since today   # today
journalctl --user -u perpetua@acme-api -f              # follow
journalctl --user -u 'perpetua@*' --since -12h         # every project, last 12 hours
```

```text
Oct 21 03:03:26 devbox session[48211]: [acme-api] session:start 20261021T030326 (limit 4h)
Oct 21 05:31:02 devbox session[48211]: [acme-api] session:end 20261021T030326 outcome=rate_limited exit=1 duration=147min
Oct 21 05:31:02 devbox session[48211]: [acme-api] backoff: usage limit reached, pausing 60 min
Oct 21 05:31:02 devbox systemd[1342]: perpetua@acme-api.service: Deactivated successfully.
```

journald also shows what the runner log cannot: systemd's own view, such as a unit failing with status 2 or 3 because of a configuration error.

**The session journal**, `sessions/YYYYMMDDTHHMMSS.jsonl`, is Claude Code's complete stream-json output: every message, tool call and tool result. It is the ground truth when a summary is not enough.

```bash
# the final report of the last session
jq -r 'select(.type == "result") | .result' \
  "$(jq -r .journal ~/.local/state/perpetua/acme-api/last-session.json)"

# every shell command the last session ran
jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Bash") | .input.command' \
  "$(jq -r .journal ~/.local/state/perpetua/acme-api/last-session.json)"
```

## Reading history

`history.jsonl` holds one JSON record per session, never truncated:

```json
{"project": "acme-api", "outcome": "ok", "exit_code": 0, "started_at": "2026-10-20T23:18:10+02:00", "ended_at": "2026-10-21T02:47:55+02:00", "duration_s": 12585, "session_id": "5b0e6c1e-8f0a-4d38-9a51-2f7f3f1d2c11", "model": "claude-opus-4-5", "turns": 214, "cost_usd": 18.42, "journal": "/home/dev/.local/state/perpetua/acme-api/sessions/20261020T231810.jsonl", "perpetua_version": "1.0.0"}
```

Useful queries:

```bash
cd ~/.local/state/perpetua/acme-api

# the last 15 sessions as a table
jq -r '[.started_at[:16], .outcome, "\(.duration_s / 60 | floor)min", (.turns // "-")] | @tsv' history.jsonl | tail -n 15

# sessions per outcome
jq -s 'group_by(.outcome) | map({outcome: .[0].outcome, sessions: length})' history.jsonl

# hours of agent work per day
jq -rs 'group_by(.started_at[:10]) | .[] | "\(.[0].started_at[:10])  \(map(.duration_s) | add / 3600 * 10 | floor / 10) h"' history.jsonl

# the sessions that did not end ok, with their journal
jq -r 'select(.outcome != "ok") | "\(.started_at)  \(.outcome)  \(.journal)"' history.jsonl
```

!!! note "About `cost_usd`"
    `cost_usd` is the `total_cost_usd` that Claude Code reports at the end of a session. On a subscription it is an estimate of API-equivalent usage, not an amount billed to you. Old journals are pruned to `SESSION_RETENTION`, but `history.jsonl` keeps every record, so a `journal` path may point to a file that no longer exists.

## Changing configuration

Edit `~/.config/perpetua/projects/NAME.env`. The runner sources it on every wake-up, so changes apply from the next session without any reload. The exception is the interval, which lives in systemd:

```bash
perpetua enable acme-api --interval 30min
```

## Upgrading

Upgrade between sessions, so that no session is running while its runner is replaced:

```bash
perpetua pause acme-api                                   # repeat for each project
systemctl --user is-active perpetua@acme-api.service      # wait for "inactive"
curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash
perpetua version
perpetua resume acme-api
```

The installer replaces `bin/perpetua`, `libexec/perpetua/` and `share/perpetua/` in the prefix and, when the unit templates are already installed, re-renders `perpetua@.service` and `perpetua@.timer` and reloads systemd. Per-project interval drop-ins are left as they are. To install a specific release or branch instead of `main`, pass `--version`:

```bash
curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash -s -- --version v1.0.0
```

From a clone, `git pull && make install PREFIX=~/.local` does the same with the working tree (the installer uses the working tree only when run as a file from the clone without `--version`).

Project configuration files and directives are never overwritten by an upgrade. Read the [changelog](../changelog.md) for new configuration keys; any key missing from your file takes its built-in default.

## Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash -s -- --uninstall
```

`--uninstall` (or `make uninstall` from a clone) disables every `perpetua@*.timer`, removes the unit templates `perpetua@.service` and `perpetua@.timer` and every per-project interval drop-in (`perpetua@*.timer.d/`), and deletes `bin/perpetua`, `libexec/perpetua/` and `share/perpetua/` from the prefix. Pass the same `--prefix` you installed with. It deliberately **keeps** project configuration (`~/.config/perpetua/`) and state (`~/.local/state/perpetua/`), so a later reinstall picks up where you left off.

For a complete removal, unregister the projects first, while the CLI is still installed:

```bash
# every project: stop the timer, delete its interval drop-in, configuration and state
for f in ~/.config/perpetua/projects/*.env; do [ -e "$f" ] && perpetua remove "$(basename "$f" .env)" --purge; done

curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash -s -- --uninstall
```

`remove` stops and disables the timer, deletes the interval drop-in and the project configuration; `--purge` also deletes the state directory (logs, history, journals). Without `--purge`, the state stays in `~/.local/state/perpetua/NAME/` for later reading. Neither touches the repository: delete `.perpetua/` from each project yourself if you no longer want the directive.
