---
description: Every line the Perpetua runner writes to runner.log, what it means and what to do about it, and the exact rules that classify a session's outcome.
---

# Runner log reference

The runner writes one line per event to `~/.local/state/perpetua/<name>/runner.log`:

```text
2026-10-20 09:15:02 session:start 20261020T091502 (limit 4h)
```

The timestamp is local time, `YYYY-MM-DD HH:MM:SS`. The same message goes to standard error as `[<name>] <message>`, so under systemd it is also in the journal:

```bash
journalctl --user -u perpetua@shop.service
```

Every wake-up produces at least one line. A wake-up ends either at a gate (one `gate:` line), in an error (one `error:` line), or with a session (`session:start`, then `session:end`, possibly preceded by a `warning:` and followed by `backoff:` and `warning:` lines). Read the log with `perpetua logs <name>`.

## Messages

Messages appear below in the order in which the runner can emit them.

### Gate lines

A closed gate ends the wake-up with exit status `0`: the service succeeds and the timer keeps its cadence. Gates are evaluated in this order, and the first one that closes ends the run.

| Message | Gate | Meaning | Operator action |
| --- | --- | --- | --- |
| `gate:stop paused by operator` | 1, stop | `state/paused` or `PROJECT_DIR/.perpetua/STOP` exists. | None if intended. `perpetua resume <name>` and delete `.perpetua/STOP` to restart. |
| `gate:lock a session is already running` | 2, exclusivity | Another process holds the lock: a session in progress (timer-driven or `perpetua run`). | None. Check with `perpetua status` (`session running`) or `systemctl --user status perpetua@<name>.service`. |
| `gate:backoff usage limit, waiting until <YYYY-MM-DD HH:MM:SS>` | 3, back-off | A previous session hit a usage limit; the pause has not expired. | None. `perpetua resume <name>` cancels it early. |
| `gate:presence operator active in Claude Code within <N> min, yielding` | 4, presence | A Claude Code transcript not launched by Perpetua was modified within `PRESENCE_WINDOW_MIN` minutes. | None: the loop resumes once you have been idle for the window. If it persists while you are away, see [below](#persistent-gatepresence). |
| `gate:attention question pending for the operator, next session after <YYYY-MM-DD HH:MM:SS>` | 5, attention | `QUESTION_FILE` holds an unanswered question and a session already ran within `QUESTION_THROTTLE_SECONDS`. | Answer the question in the plan (replace its value with `none`, or remove the line). |

Gates 4 and 5 are skipped with `--force` or `PERPETUA_FORCE=1`. Gates 1 to 3 never are.

#### Persistent gate:presence

The gate considers every `*.jsonl` file under `PRESENCE_DIR` (default `~/.claude/projects`) whose modification time is within the window, minus the ids listed in the `own-sessions` files of all projects. Common causes when nobody is at the keyboard:

- An interactive Claude Code session left open that keeps writing.
- A Claude Code process launched by another tool on the same account.
- A Perpetua session whose id could not be registered: the runner looks for it in the journal during the first two minutes only. Such a session is still registered by `record.py` when it ends.

To identify the file:

```bash
find ~/.claude/projects -name '*.jsonl' -mmin -10
```

### Session lines

`session:start <stamp> (limit <MAX_SESSION>)`
:   All gates are open; Claude Code is starting. `<stamp>` is `YYYYMMDDTHHMMSS`, also the journal's file name: `sessions/<stamp>.jsonl`.

`session:end <stamp> outcome=<outcome> exit=<code> duration=<minutes>min`
:   The session finished and was recorded. `outcome` is the final classification (see [Outcomes](#outcomes)), `exit` the exit status of `timeout` running Claude Code, `duration` whole minutes, rounded down.

A `session:start` without a matching `session:end` means the runner was killed with `SIGKILL` during the session: the out-of-memory killer, a power loss, or a stop during which Claude Code did not exit within systemd's stop timeout (90 seconds by default). No record was written. A regular stop (`systemctl --user stop`, a shutdown, a logout without lingering, Ctrl-C) produces `session:end ... outcome=interrupted exit=130` instead.

`backoff: usage limit reached, pausing <N> min`
:   Follows a `session:end` with `outcome=rate_limited`. `<N>` is `BACKOFF_SECONDS / 60`, rounded down. The next wake-ups log `gate:backoff`.

### Warnings

`warning: no directive at <path>, the session runs on its prompt alone`
:   `DIRECTIVE_FILE` does not resolve to a readable file. The session runs without the standing order. **Action**: restore the file, or fix `DIRECTIVE_FILE`. Treat this as urgent: the directive carries the forbidden actions.

`warning: could not record the session summary`
:   `record.py` failed: Python missing, state directory not writable, disk full. **Action**: run `perpetua doctor`; check free space. The runner then keeps its own provisional outcome for the `session:end` line and the hook, without the recorder's `ok` to `error` refinement; `last-session.json`, `history.jsonl` and `summaries.md` lack this session.

`warning: post-session hook failed`
:   `POST_SESSION_HOOK` exited non-zero or exceeded 120 seconds. Its output, if any, is in the lines just above, without timestamps. **Action**: fix the hook; the session itself is unaffected.

### Errors

Errors end the wake-up without running a session and with a non-zero exit status, so the service is marked failed. The timer keeps its cadence regardless.

`error: project directory '<path>' not found`
:   `PROJECT_DIR` is empty or not a directory. Exit status `3`. **Action**: fix `PROJECT_DIR`, or `perpetua disable <name>`. Logged before any gate.

`error: '<CLAUDE_BIN>' not found in PATH`
:   Claude Code cannot be found with the runner's `PATH`. Exit status `2`. Logged after the gates. **Action**: set `CLAUDE_BIN` to an absolute path (`command -v claude` in your shell).

Earlier failures are not logged to `runner.log`, because they happen before the state directory is known. They appear only on standard error, hence in the journal: `usage: session <project> [--force]`, `perpetua: invalid project name '<name>'` and `perpetua: unknown project '<name>' (no <path>)`, all with exit status `2`.

### Hook output

Anything `POST_SESSION_HOOK` prints is appended to `runner.log` verbatim, without timestamp. Keep hooks quiet, or redirect their output elsewhere, so that the log, and the `last wake-up` line of `perpetua status`, stay readable.

## Outcomes

Each session that ran receives exactly one outcome. The runner classifies it first; `record.py` may then downgrade `ok` to `error`. The rules are applied in this order, and the first that matches wins:

| Order | Outcome | Rule | Applied by |
| --- | --- | --- | --- |
| 1 | `interrupted` | The runner received `SIGTERM`, `SIGINT` or `SIGHUP` during the session. It forwarded `SIGTERM` to Claude Code and waited for it. The exit code is recorded as `130`. | runner |
| 2 | `rate_limited` | A line of the journal in which Claude Code reports a condition matches `LIMIT_PATTERN` (`grep -iE`), whatever the exit status. Those lines are the non-JSON lines (standard error), the events starting with `{"type":"error"` or `{"type":"rate_limit"`, and `result` events flagged `"is_error":true`. Tool output and successful `result` events are never searched. Starts the back-off. | runner |
| 3 | `timeout` | Exit status `124` (`timeout` sent `SIGTERM` at `MAX_SESSION`) or `137` (process killed by `SIGKILL`, normally 60 seconds after the deadline). | runner |
| 4 | `error` | Any other non-zero exit status. | runner |
| 5 | `error` | Exit status `0`, but the journal holds no `result` event, or the last one has `"is_error": true`. | `record.py` |
| 6 | `ok` | Exit status `0` and a final `result` event that is not an error. | |

The final outcome is the one in `last-session.json`, `history.jsonl`, `summaries.md`, the `session:end` line, `PERPETUA_OUTCOME` and `perpetua status`.

!!! note "Reading the outcome correctly"
    `ok` means the Claude Code process completed normally. It says nothing about the quality of the work: that judgement belongs to the project's CI and review process ([ADR 0006](../adr/0006-fail-closed-gates.md)). Read the closing report (`perpetua summaries`) and the pull requests.

!!! warning "Classification edge cases"
    - A `137` caused by something other than the timeout, such as the kernel's out-of-memory killer, is reported as `timeout`.
    - A failed `result` event still carries text written by the agent; if that text matches the pattern, the session is classified `rate_limited`. A successful session is never classified `rate_limited` because of its closing report. See [`LIMIT_PATTERN`](configuration.md#limit_pattern).
    - An interrupted session is never `rate_limited`, even when it was interrupted because of a limit, so no back-off starts.

### What to do per outcome

| Outcome | Typical causes | Action |
| --- | --- | --- |
| `ok` | Normal end. | Read the summary. |
| `error` | Claude Code crashed, refused to start (authentication expired, invalid `CLAUDE_ARGS` or `MODEL`), or ended with an error result. | Inspect the end of the journal: `tail -n 5 "$(jq -r .journal ~/.local/state/perpetua/<name>/last-session.json)"`. After an expired login, run `claude` and `/login` as the same user. |
| `timeout` | The session reached `MAX_SESSION`. Frequent with `/autonomous-mode` on a long plan, and harmless if the agent commits as it goes. | If work is lost at each cut, lower the size of tasks in the plan, or raise `MAX_SESSION`. |
| `rate_limited` | The subscription's usage limit was reached. | None: the back-off handles it. If it recurs every window, lengthen the interval or `BACKOFF_SECONDS`. |
| `interrupted` | `systemctl --user stop`, shutdown, logout without lingering, Ctrl-C under `perpetua run`. | None if intended. Uncommitted work stays in the working tree; the next session is told to finish it first. To prevent the next wake-up, `perpetua pause` as well. |

## Example: a typical day

```text
2026-10-20 06:40:12 session:start 20261020T064012 (limit 4h)
2026-10-20 08:52:47 session:end 20261020T064012 outcome=ok exit=0 duration=132min
2026-10-20 09:07:48 gate:presence operator active in Claude Code within 10 min, yielding
2026-10-20 09:22:49 gate:presence operator active in Claude Code within 10 min, yielding
2026-10-20 09:37:50 session:start 20261020T093750 (limit 4h)
2026-10-20 11:19:24 session:end 20261020T093750 outcome=rate_limited exit=1 duration=101min
2026-10-20 11:19:24 backoff: usage limit reached, pausing 60 min
2026-10-20 11:34:25 gate:backoff usage limit, waiting until 2026-10-20 12:19:24
2026-10-20 11:49:26 gate:backoff usage limit, waiting until 2026-10-20 12:19:24
2026-10-20 12:04:27 gate:backoff usage limit, waiting until 2026-10-20 12:19:24
2026-10-20 12:19:28 session:start 20261020T121928 (limit 4h)
```
