---
description: Complete reference of the perpetua command line, its commands, options, output and exit statuses.
---

# Command line reference

`perpetua` is a single Bash program installed at `~/.local/bin/perpetua` by default. It manages project registrations, the systemd user units that drive the cadence, and the state each project accumulates. The session itself is executed by a separate program, the runner, at `~/.local/libexec/perpetua/session`; `perpetua run` hands over to it.

## Synopsis

```text
perpetua <command> [arguments]
```

| Command | Aliases | Purpose |
| --- | --- | --- |
| [`init`](#init) | | Register a project and scaffold `.perpetua/` |
| [`enable`](#enable) | | Install the systemd units and start the cadence |
| [`disable`](#disable) | | Stop the cadence; a running session finishes |
| [`remove`](#remove) | | Unregister a project; optionally delete its state |
| [`run`](#run) | | Run one session now, in the foreground |
| [`pause`](#pause) | | Raise the stop flag |
| [`resume`](#resume) | | Clear the stop flag and any back-off |
| [`status`](#status) | | Cadence, gates and last outcome |
| [`list`](#list) | `ls` | Registered projects |
| [`logs`](#logs) | `log` | Runner log, one line per wake-up |
| [`summaries`](#summaries) | `summary` | The agents' closing reports |
| [`doctor`](#doctor) | | Check the host and the installation |
| [`version`](#version) | `--version`, `-V` | Print the version |
| [`help`](#help) | `--help`, `-h` | Print the usage summary |

Invoked without a command, `perpetua` prints the usage summary and exits with status `0`. An unknown command prints the usage summary on standard error and exits with status `2`.

## Conventions

Project names
:   A project name matches `^[a-z0-9][a-z0-9_-]{0,62}$`: lowercase letters, digits, `-` and `_`, starting with a letter or a digit, at most 63 characters. The name identifies the configuration file (`~/.config/perpetua/projects/NAME.env`), the state directory (`~/.local/state/perpetua/NAME/`) and the systemd instance (`perpetua@NAME.timer`, `perpetua@NAME.service`).

Argument order
:   Every command that operates on a project takes the name as its first argument. Options follow the name (`perpetua run demo --force`, not `perpetua run --force demo`).

Output
:   Progress lines start with `==>`, checks with `✓`, `!` (warning) or `✗` (failure). Colour is used only when standard output is a terminal and `NO_COLOR` is unset or empty.

Errors
:   Errors are printed on standard error with the prefix `perpetua:`.

### Exit statuses

| Status | Meaning |
| --- | --- |
| `0` | Success. For `run`, the run was handled: a session ran, or a gate closed. |
| `1` | Runtime failure: systemd user instance unavailable, no log or summary yet, host not ready (`doctor`). |
| `2` | Usage or configuration error: unknown command or option, option without its value, missing or unknown project, invalid name or interval, project already registered, directory not found. |
| `3` | `run` only: the project directory configured in `PROJECT_DIR` does not exist. |

### Environment

| Variable | Default | Effect |
| --- | --- | --- |
| `XDG_CONFIG_HOME` | `~/.config` | Parent of `perpetua/projects/` and, unless `PERPETUA_UNIT_DIR` is set, of `systemd/user/`. |
| `XDG_STATE_HOME` | `~/.local/state` | Parent of `perpetua/<project>/`, the state directories. |
| `PERPETUA_LIBEXEC` | `<prefix>/libexec/perpetua` | Location of the runner (`session`) and `record.py`. The rendered service unit points here. |
| `PERPETUA_SHARE` | `<prefix>/share/perpetua` | Location of the unit and project templates. |
| `PERPETUA_UNIT_DIR` | `$XDG_CONFIG_HOME/systemd/user` | Where `enable` renders the units. |
| `PERPETUA_SYSTEMCTL` | `systemctl` | The `systemctl` binary. The test suite sets it to `false` to simulate a host without systemd. |
| `NO_COLOR` | unset | Any non-empty value disables colour. |
| `PERPETUA_FORCE` | `0` | Read by the runner: `1` is equivalent to `--force`. |

`<prefix>` is the directory two levels above the resolved `perpetua` executable, `~/.local` for a default installation. Symbolic links to the executable are resolved first.

---

## init

Register a project and scaffold its `.perpetua/` directory.

```text
perpetua init [DIR] [--name NAME]
```

`DIR`
:   The project repository. Defaults to the current directory. It must exist; it is resolved to an absolute path.

`--name NAME`
:   The project name. When omitted, it is derived from the basename of `DIR`: lowercased, every run of characters outside `a-z0-9_-` replaced with `-`, leading `-` and `_` and trailing `-` removed. `My App` becomes `my-app`.

**Behaviour**

1. Writes `~/.config/perpetua/projects/NAME.env` from the template `share/perpetua/templates/project.env`, with `@NAME@` replaced by the name and `@PROJECT_DIR@` by the absolute directory, shell-quoted with `printf %q`.
2. Creates `DIR/.perpetua/` and copies the default directive to `DIR/.perpetua/directive.md`, unless that file already exists. An existing directive is never overwritten.
3. Creates `DIR/.perpetua/.gitignore` containing `STOP`, unless it already exists, so the stop flag is never committed while the directive is.
4. Prints the paths it used and the next steps.

`init` does not create the state directory (the runner does, on its first wake-up) and does not touch systemd.

**Errors** (status `2`): unknown option, `option --name needs a value`, `no such directory`, `invalid name` (use `--name`), `project 'NAME' is already registered`.

```console
$ perpetua init ~/src/shop --name shop
==> Registered shop
  ✓ configuration   /home/alex/.config/perpetua/projects/shop.env
  ✓ directive       /home/alex/src/shop/.perpetua/directive.md
  ✓ state           /home/alex/.local/state/perpetua/shop/

Next
  1. Review the directive: it is the standing order every session receives.
  2. Run one supervised session:   perpetua run shop --force
  3. Start the cadence:            perpetua enable shop
```

!!! note "Registering the same repository twice"
    The registration is keyed by name, not by directory. Two names may point at the same directory; they then share `.perpetua/` (directive and `STOP`) but have separate locks, so their sessions can run concurrently in the same working tree. Avoid it.

## enable

Install the systemd units and start the cadence.

```text
perpetua enable NAME [--interval INTERVAL]
```

`--interval INTERVAL`
:   Delay between the end of one run and the next wake-up. Accepted forms match `^[0-9]+(s|min|h)?$`: `900` (seconds), `900s`, `15min`, `2h`. Other systemd time spans (`90m`, `1h 30min`) are rejected with status `2`, as is `--interval` without a value (`option --interval needs a value`). Without the option the timer template's `15min` applies.

**Behaviour**

1. Fails with status `1` if the systemd user instance is not reachable (`systemctl --user show-environment` fails).
2. Renders `perpetua@.service` into the unit directory, replacing `@LIBEXECDIR@` with the absolute runner directory, and copies `perpetua@.timer`. Both are overwritten on every `enable`: customise through drop-ins, never by editing the rendered files.
3. With `--interval`, writes the drop-in `perpetua@NAME.timer.d/10-interval.conf` (see [systemd units](systemd.md#interval-drop-in)).
4. Runs `systemctl --user daemon-reload`, then `systemctl --user enable --now perpetua@NAME.timer`.
5. Warns when lingering is off for the user, since the user manager, and the cadence with it, stops at logout.

Starting the timer makes the first wake-up happen immediately when the host has been up for more than 10 minutes (see [first wake-up](systemd.md#first-wake-up)).

```console
$ perpetua enable shop --interval 30min
==> Cadence enabled for shop
  ✓ timer perpetua@shop.timer, next session 30min after each run ends
```

The reported interval is the effective one: the value of an existing interval drop-in, otherwise `15min`.

!!! note "Changing back to the default interval"
    `enable NAME` without `--interval` keeps an existing interval drop-in. To return to the default, pass `--interval 15min`, or delete `~/.config/systemd/user/perpetua@NAME.timer.d/10-interval.conf` and run `perpetua enable NAME` again.

## disable

Stop the cadence.

```text
perpetua disable NAME
```

Runs `systemctl --user disable --now perpetua@NAME.timer`. Only the timer is stopped: a session in progress (`perpetua@NAME.service`) runs to completion. The rendered units and any interval drop-in stay in place, so `enable` restores the same cadence. Fails with status `1` if the systemd user instance is unavailable. Extra arguments are ignored.

To interrupt a running session, see [Stopping a running session](systemd.md#stopping-a-running-session).

## remove

Unregister a project.

```text
perpetua remove NAME [--purge]
```

`--purge`
:   Also delete the state directory `~/.local/state/perpetua/NAME/` (logs, journals, history, summaries). It must be the second argument; any other argument is ignored.

**Behaviour**: when systemd is reachable, disables and stops the timer, deletes the interval drop-in and reloads the manager. Then deletes the project file. The shared template units `perpetua@.service` and `perpetua@.timer` are kept, as is the project's `.perpetua/` directory, which belongs to the repository. Without `--purge` the state directory is kept, and the session ids it recorded in `own-sessions` keep being excluded by the presence gate of other projects.

```console
$ perpetua remove shop --purge
==> Removed shop and its state
```

## run

Run one session now, in the foreground.

```text
perpetua run NAME [--force]
```

`--force`
:   Skip the presence gate and the attention gate. It never bypasses the stop flag, the lock or the back-off (see [ADR 0006](../adr/0006-fail-closed-gates.md)). Setting `PERPETUA_FORCE=1` in the environment has the same effect.

`run` replaces itself (`exec`) with the runner, `libexec/perpetua/session NAME [--force]`, which is exactly what the systemd service executes. Gates are evaluated, the session runs, the outcome is recorded. The runner's log lines are echoed on standard error as `[NAME] <message>`; the agent's own output goes to the session journal, not to the terminal.

Pressing Ctrl-C interrupts the session cleanly: the runner forwards `SIGTERM` to Claude Code, waits for it to exit, and records the session with outcome `interrupted` and exit code `130`.

**Exit statuses**: the runner's. `0` when the run was handled (a session ran, whatever its outcome, including `interrupted`, or a gate closed), `2` for a usage error, an unknown project, an invalid name or a `CLAUDE_BIN` not found in `PATH`, `3` when `PROJECT_DIR` does not exist. Any other runner argument than `--force` prints `usage: session <project> [--force]` and exits `2`.

```console
$ perpetua run shop --force
[shop] session:start 20261020T091502 (limit 4h)
[shop] session:end 20261020T091502 outcome=ok exit=0 duration=47min
```

!!! tip "Why the first run needs `--force`"
    When you type `perpetua run` from a terminal where you have just used Claude Code, the presence gate sees your own transcript and yields. `--force` is the supervised way to start a session while you are at the keyboard.

!!! note "Differences with a timer-driven run"
    A foreground run inherits your shell's environment, current directory and resource limits, not the user manager's. In particular, an `ANTHROPIC_API_KEY` exported in your shell reaches Claude Code and may switch it to metered API billing. Background processes the agent leaves behind are not reaped as they are under systemd; they do not hold the project lock, since the runner closes the lock descriptor for Claude Code and its children.

## pause

Raise the operator stop flag.

```text
perpetua pause NAME
```

Writes the current date (`%F %T`) to `~/.local/state/perpetua/NAME/paused`. Every subsequent wake-up ends at the stop gate (`gate:stop`). A running session is not interrupted. The timer keeps firing, which is cheap and keeps `perpetua status` informative.

The project-side equivalent is the file `PROJECT_DIR/.perpetua/STOP`, which anyone with access to the repository can create. Both are checked by the same gate.

## resume

Clear the stop flag and any back-off.

```text
perpetua resume NAME
```

Deletes `paused` and `backoff-until` from the state directory, so the next wake-up can run a session even if a usage-limit back-off was in progress. Warns (`the project still holds .perpetua/STOP`) when the project-side stop file exists, since `resume` does not delete it. Always exits `0` for a registered project.

## status

Show cadence, gates and last outcome.

```text
perpetua status [NAME]
```

Without a name, prints a block for every registered project, separated by blank lines.

```console
$ perpetua status shop
shop
  project        /home/alex/src/shop
  cadence        enabled, next Mon 2026-10-20 10:17:41
  state          ready
  last session   ok (2026-10-20T09:15:02-04:00)
  last wake-up   2026-10-20 10:02:40 gate:presence operator active in Claude Code within 10 min, yielding
```

| Field | Source |
| --- | --- |
| `project` | `PROJECT_DIR` from the project file. |
| `cadence` | `enabled` when `perpetua@NAME.timer` is enabled, with the next elapse from `systemctl --user list-timers`; otherwise `disabled`. Always `disabled` without a systemd user instance. |
| `state` | The first that applies, in this order of precedence: `backing off until <time>` (unexpired `backoff-until`), `paused` (`paused` or `.perpetua/STOP` exists), `session running` (`ActiveState` of the service is `activating` or `active`), `ready`. |
| `last session` | `outcome` and `started_at` from `last-session.json`, or `none yet`. |
| `last wake-up` | The last line of `runner.log`; omitted when there is none. |

Because the post-session hook's output is appended to `runner.log` without a timestamp, `last wake-up` can show a line of hook output.

## list

List registered projects.

```text
perpetua list
perpetua ls
```

Prints one line per project file in `~/.config/perpetua/projects/`: the name, left-aligned on 24 columns, and `PROJECT_DIR`. With no project, prints `No project registered. Start with: perpetua init /path/to/project`.

## logs

Print the runner log.

```text
perpetua logs NAME [-f]
perpetua log NAME [-f]
```

Prints the last 40 lines of `runner.log`. With `-f` (second argument only), keeps following the file. Fails with status `1` (`no log yet for 'NAME'`) before the first wake-up. Every line is documented in the [runner log reference](runner-log.md).

## summaries

Print the agents' closing reports.

```text
perpetua summaries NAME [-n N]
perpetua summary NAME [-n N]
```

`-n N`
:   Number of reports, most recent last. Default `3`.

Reads `summaries.md`, where each session appends a section starting with `## ` (see [format](state-and-files.md#summariesmd)), and prints the last `N` sections. Fails with status `1` (`no session summary yet for 'NAME'`) before the first recorded session.

!!! note
    Sections are delimited by lines starting with `## `. A closing report that itself contains such a line counts as several sections, so `-n` may return fewer sessions than requested.

## doctor

Check the host and the installation.

```text
perpetua doctor
```

| Check | Result when it fails |
| --- | --- |
| `claude` found in `PATH`, with its version | failure |
| Credentials: `~/.claude/.credentials.json` exists or `ANTHROPIC_API_KEY` is set | warning |
| Skill `~/.claude/skills/autonomous-mode` installed (the default `PROMPT` uses it) | warning |
| `python3` 3.8 or later | failure |
| `flock`, `timeout`, `find` available | failure |
| systemd user instance reachable | failure |
| Lingering enabled for `$USER` (only when `loginctl` exists) | warning |
| On WSL (`/proc/version` mentions Microsoft): a keep-alive process matching `sleep infinity` | warning |
| Units installed in the unit directory | warning |

Exits `0` with `Host ready` when no check failed; otherwise exits `1` with `perpetua: the host is not ready`. Warnings never change the exit status.

`doctor` checks the interactive environment. The runner prepends `~/.local/bin`, `~/.npm-global/bin`, `~/.local/opt/node/bin` and `/usr/local/bin` to `PATH`, so a `claude` found there by the runner is found even under the minimal environment of the user manager; a `claude` installed elsewhere must be set through `CLAUDE_BIN`.

## version

```text
perpetua version
perpetua --version
perpetua -V
```

Prints `perpetua 1.0.0`.

## help

```text
perpetua help
perpetua --help
perpetua -h
```

Prints the usage summary on standard output and exits `0`.

---

## Known limitations

- Options are positional where noted: `remove` recognises `--purge` only as the second argument, `logs` recognises `-f` only as the second argument, `summaries` recognises `-n` only as the second argument.
- `perpetua` reads the project file by sourcing it as shell code, for `status`, `list` and `resume` as well as for the runner. See [Configuration: security](configuration.md#the-project-file-is-shell-code).
