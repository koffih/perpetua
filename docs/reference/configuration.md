---
description: Every key of the Perpetua project file, with type, default, semantics and examples.
---

# Configuration reference

Each registered project has one configuration file:

```text
~/.config/perpetua/projects/<name>.env
```

`perpetua init` writes it from the template `share/perpetua/templates/project.env`. The runner reads it at every wake-up, so a change applies from the next wake-up on, with no reload and no restart.

## File format

The project file is a Bash fragment. The runner first assigns its built-in defaults, then sources the file, so any key you set overrides the default and any key you omit keeps it.

```bash
# Values with spaces must be quoted. Single quotes keep regex metacharacters literal.
PROJECT_DIR=/home/alex/src/shop
PROMPT='/autonomous-mode follow the plan'
MAX_SESSION=3h
```

- One `KEY=value` per line, no spaces around `=`.
- Quote any value that contains spaces or shell metacharacters. Prefer single quotes, especially for regular expressions.
- Lines starting with `#` are comments.
- A key that appears several times takes its last value.

### The project file is shell code

!!! danger "Security implication"
    The file is executed with `.` (source) by the runner at every wake-up, and by `perpetua status`, `perpetua list` and `perpetua resume`. Any command it contains runs with your user's privileges, unattended. Treat it like a script in your `PATH`:

    - keep it owned by you and not writable by anyone else (`chmod 600` is appropriate);
    - never generate it from untrusted input;
    - never let the agent edit it: it lives outside the repository on purpose, and the default directive forbids editing `.perpetua/`.

    See the [threat model](../security/threat-model.md#t4-the-project-file-is-sourced-as-shell).

Because the file is sourced, values can refer to the environment (`PROJECT_DIR=$HOME/src/shop`) and to keys set earlier in the file.

## Keys

The default is the value the runner uses when the key is absent from the file. Where the template written by `init` sets a different value, both are given.

| Key | Type | Runner default | Template value |
| --- | --- | --- | --- |
| [`PROJECT_DIR`](#project_dir) | absolute path | empty (required) | the directory given to `init` |
| [`PROMPT`](#prompt) | string | `/autonomous-mode` | `/autonomous-mode follow the plan` |
| [`DIRECTIVE_FILE`](#directive_file) | path | `.perpetua/directive.md` | same |
| [`MAX_SESSION`](#max_session) | `timeout(1)` duration | `4h` | same |
| [`PRESENCE_WINDOW_MIN`](#presence_window_min) | integer, minutes | `10` | same |
| [`PRESENCE_DIR`](#presence_dir) | directory | `$HOME/.claude/projects` | not set |
| [`BACKOFF_SECONDS`](#backoff_seconds) | integer, seconds | `3600` | same |
| [`LIMIT_PATTERN`](#limit_pattern) | extended regex | see [below](#limit_pattern) | not set |
| [`QUESTION_FILE`](#question_file) | path | empty (gate disabled) | `PLAN.md` |
| [`QUESTION_PATTERN`](#question_pattern) | extended regex | `Pending question[*_ ]*:` | same |
| [`QUESTION_NONE`](#question_none) | extended regex | see [below](#question_none) | not set |
| [`QUESTION_THROTTLE_SECONDS`](#question_throttle_seconds) | integer, seconds | `21600` | same |
| [`CLAUDE_BIN`](#claude_bin) | command | `claude` | same |
| [`CLAUDE_ARGS`](#claude_args) | whitespace-separated words | `--dangerously-skip-permissions` | same |
| [`MODEL`](#model) | string | empty | empty |
| [`SESSION_RETENTION`](#session_retention) | integer | `200` | same |
| [`POST_SESSION_HOOK`](#post_session_hook) | shell command | empty | empty |

The two values that differ matter: a project file that omits `QUESTION_FILE` has no attention gate, and one that omits `PROMPT` sends `/autonomous-mode` without the argument.

---

### PROJECT_DIR

Absolute path of the repository the sessions work in. Required: there is no default.

The session's working directory is set to it, the stop file is looked up at `PROJECT_DIR/.perpetua/STOP`, and relative `DIRECTIVE_FILE` and `QUESTION_FILE` paths are resolved against it. When it is empty or not a directory, the runner logs `error: project directory '<value>' not found` and exits with status `3`; under systemd the service is marked failed and the cadence continues.

`init` writes the value shell-quoted (`printf %q`), so a directory with spaces appears as `/home/alex/My\ App`.

### PROMPT

The user prompt of every session, passed as a single argument to `claude -p`. It is not split or expanded by the runner.

The default runs the `autonomous-mode` skill, which keeps one session working through a plan for hours. Anything Claude Code accepts as a prompt works, including another slash command or plain text:

```bash
PROMPT='/autonomous-mode follow the plan'
PROMPT='Work through the next unchecked item of TODO.md, then stop.'
```

The standing rules belong in the directive, not in the prompt (see [ADR 0005](../adr/0005-directive-as-system-prompt.md)).

### DIRECTIVE_FILE

The file whose content is appended to the system prompt of every session with `--append-system-prompt`.

- A path starting with `/` is used as is.
- Any other path is resolved against `PROJECT_DIR`.

When the file is missing or unreadable, the runner logs `warning: no directive at <path>, the session runs on its prompt alone` and runs the session anyway.

The content is read at every wake-up and passed as one command-line argument. Linux limits a single argument to 128 KiB; keep the directive well below that size.

Use an absolute path to keep the directive outside the repository, out of the agent's reach:

```bash
DIRECTIVE_FILE=$HOME/.config/perpetua/directives/shop.md
```

### MAX_SESSION

Hard ceiling of one session, in `timeout(1)` syntax: a number with an optional suffix `s`, `m`, `h` or `d` (`90m`, `4h`, `1.5h`). The runner runs Claude Code under `timeout --kill-after=60 MAX_SESSION`: at the deadline, `SIGTERM`; 60 seconds later, `SIGKILL` if the process is still alive. The session is then recorded with outcome `timeout`.

systemd imposes no limit of its own (`TimeoutStartSec=infinity`), so this key is the only ceiling.

### PRESENCE_WINDOW_MIN

The presence gate yields when any Claude Code transcript (`*.jsonl`) under `PRESENCE_DIR` was modified within this many minutes, excluding transcripts of sessions Perpetua launched itself. `0` disables the gate. See [ADR 0004](../adr/0004-operator-presence-yield.md).

### PRESENCE_DIR

Directory searched recursively by the presence gate. When it does not exist, the gate is open. Default `$HOME/.claude/projects`, where Claude Code stores session transcripts.

### BACKOFF_SECONDS

Length of the pause after a session whose journal matched `LIMIT_PATTERN`. The runner writes `ended + BACKOFF_SECONDS` (epoch seconds) to `backoff-until`, and the back-off gate closes until that time. The reset time that Claude Code may print with the limit message is not used. `perpetua resume` clears an active back-off.

### LIMIT_PATTERN

Default:

```bash
LIMIT_PATTERN='usage limit|limit reached|rate_limit_error|"error":"rate_limit"'
```

Extended regular expression (`grep -E`), matched case-insensitively after the session ends against the lines of the journal in which Claude Code itself reports a condition:

- lines that do not start with `{`, which is Claude Code's standard error and any other non-JSON output;
- events that start with `{"type":"error"` or `{"type":"rate_limit`;
- `result` events flagged `"is_error":true`.

Tool calls, tool results (file contents the agent read, command output) and successful `result` events, which carry the agent's closing report, are never searched. Any match classifies the session as `rate_limited` and starts the back-off, whatever the exit status. An interrupted session is never classified `rate_limited`.

!!! warning "Residual false positives and negatives"
    A failed `result` event still carries text written by the agent, and standard error carries whatever Claude Code prints. A match in either classifies the session `rate_limited`. Conversely, if a future Claude Code version words its limit message differently, or emits events whose first key is not `type`, the limit goes undetected and the session is recorded as `error`. Adjust the pattern to the exact message your Claude Code version prints if either happens.

### QUESTION_FILE

File where the agent records a question for the operator. Empty disables the attention gate. The runner default is empty; the template sets `PLAN.md`, matching the default directive, which tells the agent to write its question on a `Pending question:` line of `PLAN.md`.

- A path starting with `/` is used as is.
- Any other path is resolved against `PROJECT_DIR`.

When the file does not exist or is not readable, the gate is open.

### QUESTION_PATTERN

Extended regular expression (`grep -E`, case-sensitive) selecting the question line. Only the first matching line of `QUESTION_FILE` is considered. The default, `Pending question[*_ ]*:`, requires the colon, optionally preceded by Markdown emphasis: it matches `Pending question:` and `**Pending question:**`, not a heading such as `## Pending questions`.

From that line the runner extracts the value: everything up to and including the first `:` and the following whitespace is removed, then leading `*` and `_` (Markdown emphasis) and whitespace, then trailing whitespace. `**Pending question:** none` yields `none`.

A custom pattern that can match a line without any `:` makes the whole line its value, which then counts as a pending question. Keep the colon in any custom pattern.

### QUESTION_NONE

Default:

```bash
QUESTION_NONE='^(none|n/?a|-|aucune)?[.]?$'
```

Extended regular expression matched against the extracted value, case-insensitively (Bash `nocasematch`). A match means "no question pending". The default accepts an empty value, `none`, `n/a`, `na`, `-` and `aucune`, each optionally followed by one period: `None.`, `N/A`, `NONE` all match.

### QUESTION_THROTTLE_SECONDS

While a question is pending, at most one session runs per this many seconds (default six hours). The time of the last such session is stored in `last-question-run`. Sessions keep running at a reduced rate rather than stopping, because the agent was told to continue with tasks that do not depend on the answer.

### CLAUDE_BIN

The Claude Code executable, looked up in the runner's `PATH`, which is the inherited `PATH` with `~/.local/bin`, `~/.npm-global/bin`, `~/.local/opt/node/bin` and `/usr/local/bin` prepended. When it cannot be found, the runner logs `error: '<value>' not found in PATH` and exits with status `2`. Use an absolute path for any other location.

### CLAUDE_ARGS

Additional arguments for Claude Code, inserted after the fixed ones. The full command line is:

```text
CLAUDE_BIN -p PROMPT --output-format stream-json --verbose CLAUDE_ARGS... [--model MODEL] [--append-system-prompt DIRECTIVE]
```

The value is split on whitespace with `read -r -a`. No quote removal, escaping or globbing takes place: an argument cannot contain a space, and quotes are passed literally. `--allowedTools "Bash(git commit:*)"` therefore does not work here.

The default, `--dangerously-skip-permissions`, exists because nobody can answer a permission prompt in an unattended session. A narrower setup is preferable when the project allows it: declare the permitted tools in the repository's `.claude/settings.json` (`permissions.allow`), where spaces are not a problem, and remove the flag:

```bash
CLAUDE_ARGS='--permission-mode acceptEdits'
```

Tools outside the allowlist are then refused rather than prompted. See the [hardening checklist](../security/threat-model.md#hardening-checklist).

### MODEL

When non-empty, passed as `--model MODEL`. Empty leaves the choice to Claude Code. The model actually used is recorded in `last-session.json`.

### SESSION_RETENTION

Number of session journals (`sessions/*.jsonl`) kept in the state directory. After each session the oldest, by file name, are deleted. `0` disables pruning. `history.jsonl` keeps the path of pruned journals.

### POST_SESSION_HOOK

Shell command run with `sh -c` after every session that actually ran (not after a closed gate or an early error). It runs under `timeout 120`; standard output and standard error are appended to `runner.log`. A non-zero status or a timeout logs `warning: post-session hook failed`. Its working directory is the runner's: your home directory under systemd, the current directory under `perpetua run`. The runner closes the lock descriptor for the hook, so a background process it starts does not keep the project locked.

| Variable | Value |
| --- | --- |
| `PERPETUA_PROJECT` | Project name |
| `PERPETUA_OUTCOME` | Final outcome: `ok`, `error`, `timeout`, `rate_limited` or `interrupted` |
| `PERPETUA_EXIT_CODE` | Exit status of `timeout` running Claude Code; `130` for an interrupted session |
| `PERPETUA_JOURNAL` | Path of the session journal |
| `PERPETUA_STATE_DIR` | The project's state directory |
| `PERPETUA_PROJECT_DIR` | `PROJECT_DIR` |

```bash
# Desktop notification on anything but success.
POST_SESSION_HOOK='[ "$PERPETUA_OUTCOME" = ok ] || notify-send "perpetua: $PERPETUA_PROJECT" "$PERPETUA_OUTCOME"'
```

Single quotes are required so that the variables are expanded when the hook runs, not when the file is sourced.

---

## Environment variables

The runner and the CLI read the following variables from their environment. Under systemd that is the user manager's environment (`systemctl --user show-environment`), not your shell's.

| Variable | Read by | Effect |
| --- | --- | --- |
| `HOME` | both | Base of every default path. |
| `XDG_CONFIG_HOME` | both | Project files in `$XDG_CONFIG_HOME/perpetua/projects/`; default `~/.config`. |
| `XDG_STATE_HOME` | both | State in `$XDG_STATE_HOME/perpetua/<name>/`; default `~/.local/state`. |
| `PERPETUA_FORCE` | runner | `1` skips the presence and attention gates, like `--force`. |
| `PERPETUA_LIBEXEC` | CLI | Runner directory used by `run` and rendered into the service unit. |
| `PERPETUA_SHARE` | CLI | Template directory. |
| `PERPETUA_UNIT_DIR` | CLI | Unit directory; default `$XDG_CONFIG_HOME/systemd/user`. |
| `PERPETUA_SYSTEMCTL` | CLI | `systemctl` binary. |
| `NO_COLOR` | CLI | Non-empty disables colour. |
| `PATH` | runner | Extended as described under [`CLAUDE_BIN`](#claude_bin). |

Claude Code reads its own environment variables. An `ANTHROPIC_API_KEY` present in the runner's environment reaches it and may take precedence over the subscription login (see [ADR 0003](../adr/0003-subscription-auth.md)).

## Complete example

```bash
# Perpetua project configuration: shop
PROJECT_DIR=/home/alex/src/shop
PROMPT='/autonomous-mode follow the plan'
DIRECTIVE_FILE=.perpetua/directive.md
MAX_SESSION=3h
PRESENCE_WINDOW_MIN=15
BACKOFF_SECONDS=5400
QUESTION_FILE=PLAN.md
QUESTION_PATTERN='Pending question[*_ ]*:'
QUESTION_THROTTLE_SECONDS=21600
CLAUDE_BIN=claude
CLAUDE_ARGS='--permission-mode acceptEdits'
MODEL=opus
SESSION_RETENTION=500
POST_SESSION_HOOK='[ "$PERPETUA_OUTCOME" = ok ] || logger -t perpetua "$PERPETUA_PROJECT: $PERPETUA_OUTCOME"'
```
