---
description: Every file Perpetua reads or writes, who owns it, its format and its lifecycle, with the schema of the session record.
---

# State and files

Perpetua keeps its files in four places: the installation, the user configuration, the project repository and the state directory. Nothing is written anywhere else, apart from what Claude Code itself writes under `~/.claude/`.

## Filesystem map

```text
~/.local/                                   installation prefix (default)
├── bin/perpetua                            the CLI
├── libexec/perpetua/
│   ├── session                             the runner, one session per invocation
│   └── record.py                           writes the session record
└── share/perpetua/
    ├── systemd/perpetua@.service           unit template (@LIBEXECDIR@ placeholder)
    ├── systemd/perpetua@.timer             timer template
    └── templates/project.env, directive.md

~/.config/
├── perpetua/projects/<name>.env            project configuration (one per project)
└── systemd/user/
    ├── perpetua@.service                   rendered by `perpetua enable`
    ├── perpetua@.timer                     copied by `perpetua enable`
    └── perpetua@<name>.timer.d/10-interval.conf   written by `enable --interval`

<PROJECT_DIR>/.perpetua/
├── directive.md                            standing order, appended to the system prompt
├── .gitignore                              contains `STOP`
└── STOP                                    project-side stop flag (optional)

~/.local/state/perpetua/<name>/             state directory
├── runner.log                              one line per event, see the runner log reference
├── lock                                    flock target, one session at a time
├── paused                                  operator stop flag (optional)
├── backoff-until                           end of a usage-limit back-off (optional)
├── last-question-run                       attention gate throttle (optional)
├── own-sessions                            Claude Code session ids launched by Perpetua
├── last-session.json                       record of the last session
├── history.jsonl                           one record per session
├── summaries.md                            closing reports, for humans
└── sessions/<YYYYMMDDTHHMMSS>.jsonl        raw stream-json journal of each session
```

`~/.config` and `~/.local/state` follow `XDG_CONFIG_HOME` and `XDG_STATE_HOME`. The unit directory follows `PERPETUA_UNIT_DIR`.

## Configuration and units

| Path | Written by | Read by | Format | Lifecycle |
| --- | --- | --- | --- | --- |
| `~/.config/perpetua/projects/<name>.env` | `init`, then the operator | runner at every wake-up; CLI (`status`, `list`, `resume`, existence checks) | Bash fragment, sourced. See [configuration](configuration.md). | Deleted by `remove`. |
| `~/.config/systemd/user/perpetua@.service` | `enable` | systemd | Unit file | Overwritten by every `enable`. Never deleted by Perpetua. |
| `~/.config/systemd/user/perpetua@.timer` | `enable` | systemd | Unit file | Same. |
| `~/.config/systemd/user/perpetua@<name>.timer.d/10-interval.conf` | `enable --interval` | systemd | Drop-in | Rewritten by `enable --interval`; kept by `enable` without the option and by `disable`; deleted by `remove` and `install.sh --uninstall`. |

## Project directory

| Path | Written by | Read by | Lifecycle |
| --- | --- | --- | --- |
| `.perpetua/directive.md` | `init` (only if absent), then the operator | runner, at every session | Versioned with the repository. Never overwritten or deleted by Perpetua. |
| `.perpetua/.gitignore` | `init` (only if absent) | git | Contains `STOP`. |
| `.perpetua/STOP` | the operator, or anyone with write access to the working tree | runner (gate 1), `status`, `resume` | Its existence is the flag; content ignored. Never deleted by Perpetua. |

The directive is meant to be committed: it documents how the project is run. The default directive forbids the agent from editing `.perpetua/`. The path is configurable through `DIRECTIVE_FILE`, which may also point outside the repository.

## State directory

The runner creates `~/.local/state/perpetua/<name>/` and its `sessions/` subdirectory at every wake-up, before any gate. `remove --purge` deletes it.

### runner.log

| | |
| --- | --- |
| Written by | Runner, append-only: one line per event, `YYYY-MM-DD HH:MM:SS <message>`. The post-session hook's output is appended as is, without timestamp. |
| Read by | `perpetua logs`, `perpetua status` (last line) |
| Lifecycle | Never rotated or truncated by Perpetua. At a 15-minute cadence it grows by roughly 100 lines per day. Rotate it with `logrotate` (`copytruncate`) if needed. |

Every message is documented in the [runner log reference](runner-log.md). The same messages go to standard error, prefixed with `[<name>]`, and therefore to the journal under systemd.

### lock

An empty file. The runner opens it on file descriptor 9 and takes an exclusive, non-blocking `flock` after the stop gate. Only the runner holds it: the descriptor is closed for Claude Code and for the post-session hook, so processes they leave behind cannot keep the project locked. The lock is released when the runner exits. Deleting the file while a session runs breaks mutual exclusion; leave it alone.

### paused

| | |
| --- | --- |
| Written by | `perpetua pause`, content `YYYY-MM-DD HH:MM:SS` |
| Read by | Runner (gate 1, existence only), `status` |
| Deleted by | `perpetua resume` |

### backoff-until

| | |
| --- | --- |
| Written by | Runner, after a session classified `rate_limited`: one integer, the epoch second at which the back-off ends (`ended + BACKOFF_SECONDS`) |
| Read by | Runner (gate 3), `status` |
| Deleted by | Runner, at the first wake-up after it expires or when its content is not an integer; `perpetua resume` |

### last-question-run

| | |
| --- | --- |
| Written by | Runner (gate 5): the epoch second of the last wake-up that let a session start while a question was pending |
| Read by | Runner (gate 5) |
| Lifecycle | Overwritten, never deleted. It is only consulted while a question is pending. |

### own-sessions

| | |
| --- | --- |
| Written by | Runner, append-only, while the session runs: as soon as the first `"session_id"` appears in the journal (polled every half second for up to two minutes), one id per line. `record.py` appends it at the end of the session if it is not already listed. |
| Read by | Runner (gate 4): the `own-sessions` files of **all** projects in the state root are concatenated, so a project never mistakes another project's sessions, running or finished, for operator activity |
| Lifecycle | Never pruned. About 37 bytes per session. |

For each id the gate ignores both the main transcript (`.../<id>.jsonl`) and the transcripts of its subagents (`.../<id>/subagents/agent-*.jsonl`). Because the id is registered within seconds of the session start, sessions of several projects on one host do not block each other through the presence gate.

### last-session.json

The record of the most recent session, pretty-printed JSON, replaced atomically (temporary file in the same directory, then `rename`). File mode `0600`. Read by `perpetua status` and by the runner itself, which takes the final outcome from it for the `session:end` line. [Schema](#session-record-schema) below.

### history.jsonl

The same record, one compact JSON object per line, appended after each session. Never pruned or rewritten by Perpetua. Suitable for `jq`:

```bash
# Outcomes over the last 50 sessions
tail -n 50 ~/.local/state/perpetua/shop/history.jsonl | jq -r .outcome | sort | uniq -c

# Total working hours recorded
jq -s 'map(.duration_s) | add / 3600' ~/.local/state/perpetua/shop/history.jsonl
```

### summaries.md

Human-readable closing reports, appended by `record.py`. Each session adds:

```markdown

## 2026-10-20 09:15 | ok

Duration 47 min, 31 turns, exit 0.

Finished task 4.2 (pagination of the orders API), PR #118 open, CI green.
Started task 4.3, branch feat/order-export pushed, tests pending.
No pending question.
```

The heading carries the local start time and the outcome. `turns` reads `n/a` when unknown. The body is the `result` text of the session's final `result` message, stripped, or `_No closing report was produced._` when there is none. `perpetua summaries` prints the last sections. Never pruned.

### sessions/

One file per session, named after the local start time: `YYYYMMDDTHHMMSS.jsonl`. It holds the standard output and standard error of `claude -p --output-format stream-json --verbose`, so mostly one JSON event per line, interleaved with any non-JSON output. The runner reads the session id from it while the session runs and searches Claude Code's own reports in it for `LIMIT_PATTERN` afterwards; `record.py` parses it.

| | |
| --- | --- |
| Lifecycle | Pruned after every session to the newest `SESSION_RETENTION` files (default 200), by file name. |
| Sensitivity | Contains the whole session: prompts, the directive, file contents read by the agent, command output. If a secret passed through the session, it is in the journal. See the [threat model](../security/threat-model.md#t3-credential-exposure-in-journals). |

Two sessions started within the same second would share a file name; the second overwrites the first. This only happens with sessions that end immediately and are restarted by hand.

## Session record schema

`last-session.json` and each line of `history.jsonl` hold the same object.

| Field | Type | Source | Description |
| --- | --- | --- | --- |
| `project` | string | runner | Project name. |
| `outcome` | string | runner, then `record.py` | `ok`, `error`, `timeout`, `rate_limited` or `interrupted`. See [classification](runner-log.md#outcomes). |
| `exit_code` | integer | runner | Exit status of `timeout` running Claude Code: Claude Code's own status, `124` on timeout, `137` when killed after the grace period, always `130` for an interrupted session. |
| `started_at` | string | runner | ISO 8601 local time with offset, second precision. |
| `ended_at` | string | runner | Same format. |
| `duration_s` | integer | runner | `ended - started`, in seconds. |
| `session_id` | string or null | journal | The first `session_id` found in any JSON event. Null when Claude Code produced no event. |
| `model` | string or null | journal | `model` of the `system` event with subtype `init`. |
| `turns` | integer or null | journal | `num_turns` of the final `result` event. |
| `cost_usd` | number or null | journal | `total_cost_usd` of the final `result` event: Claude Code's own estimate from token usage, not an invoice. Under subscription authentication nothing is billed per token. |
| `journal` | string | runner | Absolute path of the session journal. It may have been pruned since. |
| `perpetua_version` | string | runner | Version of the runner that recorded the session. |

When the journal holds several `result` events, the last one is used.

```json
{
  "project": "shop",
  "outcome": "ok",
  "exit_code": 0,
  "started_at": "2026-10-20T09:15:02-04:00",
  "ended_at": "2026-10-20T10:02:11-04:00",
  "duration_s": 2829,
  "session_id": "5f0c2a8e-61d4-4b8a-9b0e-2d7f3c1a9e44",
  "model": "claude-opus-4-1",
  "turns": 31,
  "cost_usd": 6.84,
  "journal": "/home/alex/.local/state/perpetua/shop/sessions/20261020T091502.jsonl",
  "perpetua_version": "1.0.0"
}
```

No record is written when a gate closes, when the runner fails before the session (missing directory, `CLAUDE_BIN` not found), or when the runner itself is killed with `SIGKILL` during the session (out-of-memory killer, power loss, a stop that exceeds systemd's stop timeout). A `SIGTERM`, `SIGINT` or `SIGHUP` to the runner (`systemctl --user stop`, Ctrl-C under `perpetua run`) is forwarded to Claude Code, and the session is recorded with outcome `interrupted`.

## Backing up and moving

- To move a project, edit `PROJECT_DIR` in its file. State is keyed by name and needs no change.
- To rename a project, `remove` it (without `--purge`), `init` it under the new name, and move the old state directory to the new name if you want to keep its history.
- What is worth backing up: the project files and `history.jsonl`. Everything else is either regenerated or disposable.
