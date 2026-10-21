# Changelog

All notable changes to Perpetua are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-10-20

### Added

- `platform/vps/bootstrap.sh`: turns a fresh Debian, Ubuntu or Fedora-family server into
  a Perpetua host as root, idempotently: system packages, a dedicated account with
  lingering, SSH access, a deploy key, a git identity, Claude Code, Perpetua, the stored
  Claude token, and optionally a cloned, registered and enabled project. `--dry-run`
  prints every command and never prints the token.
- Host environment file `$XDG_CONFIG_HOME/perpetua/environment`, exported to every
  session by the runner. It carries `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`
  on servers without a browser.
- `perpetua doctor` accepts credentials from the environment file and warns when the file
  is readable by others.
- The `autonomous-mode` skill is bundled in `share/perpetua/skills/` and installed into
  `~/.claude/skills/` when absent (`install.sh --no-skill` opts out).
- Guide: Running on a VPS.
- `CLAUDE.md`: working brief for Claude Code sessions that develop Perpetua itself.

## [1.0.0] - 2026-10-20

First public release.

### Added

#### Command line

- `perpetua` CLI with the lifecycle commands `init`, `enable`, `disable` and `remove`,
  the operation commands `run`, `pause`, `resume`, `status`, `list`, `logs` and
  `summaries`, and `doctor`, `version` and `help`.
- `perpetua init [DIR] [--name NAME]` registers a project in
  `$XDG_CONFIG_HOME/perpetua/projects/NAME.env`, derives a valid name from the directory
  when none is given, and scaffolds `.perpetua/directive.md` and `.perpetua/.gitignore`
  without overwriting an existing directive.
- `perpetua run NAME [--force]` runs one session in the foreground.
- `perpetua pause` and `perpetua resume` raise and clear the operator stop flag; `resume`
  also clears an active back-off and warns when `.perpetua/STOP` is still present.
- `perpetua status [NAME]` reports the cadence, the next wake-up, the gate state
  (running, paused, backing off), the last outcome and the last runner log line.
- `perpetua logs NAME [-f]` and `perpetua summaries NAME [-n N]` show the runner log and
  the agents' closing reports.
- `perpetua remove NAME [--purge]` unregisters a project and, with `--purge`, deletes its
  state.
- `perpetua doctor` checks Claude Code, credentials, the `autonomous-mode` skill,
  Python 3.8 or later, `flock`, `timeout`, `find`, the systemd user instance, lingering,
  the WSL keep-alive and the installed units.
- Colour output that honours `NO_COLOR` and is disabled when stdout is not a terminal.
- Exit statuses: `0` success, `1` failure, `2` usage or configuration error.

#### Session runner

- `libexec/perpetua/session`, which runs one guarded `claude -p` session with
  `--output-format stream-json`, the project prompt, an optional model and the project
  directive appended to the system prompt.
- Five admission gates, evaluated in order, each closing with exit status `0` so the
  timer keeps its cadence:
  1. stop flag: `$XDG_STATE_HOME/perpetua/NAME/paused` or `.perpetua/STOP` in the project;
  2. exclusivity: a single session per project, enforced with `flock`;
  3. back-off: no session for `BACKOFF_SECONDS` after a usage limit is detected;
  4. operator presence: yield while a Claude Code transcript was written within
     `PRESENCE_WINDOW_MIN` minutes, ignoring transcripts (and subagent transcripts) of
     sessions Perpetua launched;
  5. attention: while a question for the operator is pending in `QUESTION_FILE`, at most
     one session per `QUESTION_THROTTLE_SECONDS`.
- `--force` and `PERPETUA_FORCE=1` skip the presence and attention gates, never the first
  three.
- A hard session ceiling, `MAX_SESSION`, enforced with `timeout(1)` and a 60 second kill
  grace period.
- Outcome classification: `ok`, `error`, `timeout`, `rate_limited` and `interrupted`.
  Usage limits are detected with `LIMIT_PATTERN` in what Claude Code itself reports
  (error events, results flagged as errors, stderr), never in tool output or in the
  agent's closing report.
- The project lock is never inherited by the session or the post-session hook, so a
  stray background process cannot keep a project locked.
- Graceful interruption: `TERM`, `INT` or `HUP` sent to the runner is forwarded to the
  session, which is still recorded with the outcome `interrupted`.
- Live session registration: the Claude Code session id is recorded as soon as it is
  announced, so the presence gate of every project ignores a running Perpetua session
  and its subagents, and several projects can run concurrently.
- A `PATH` extended with the usual user locations, so sessions started by systemd find
  `claude`.
- Runner exit statuses: `0` handled, `2` usage or configuration error, `3` project
  directory missing.

#### Configuration

- Per-project configuration file with the keys `PROJECT_DIR`, `PROMPT`, `DIRECTIVE_FILE`,
  `MAX_SESSION`, `PRESENCE_WINDOW_MIN`, `PRESENCE_DIR`, `BACKOFF_SECONDS`, `LIMIT_PATTERN`,
  `QUESTION_FILE`, `QUESTION_PATTERN`, `QUESTION_NONE`, `QUESTION_THROTTLE_SECONDS`,
  `CLAUDE_BIN`, `CLAUDE_ARGS`, `MODEL`, `SESSION_RETENTION` and `POST_SESSION_HOOK`.
- A default directive, the standing order every session receives, covering plan
  discipline, how to raise a pending question and the actions an unattended session must
  never take.

#### Session recording

- `libexec/perpetua/record.py`, standard library only, which parses the stream-json
  journal and writes `last-session.json` (atomically), appends to `history.jsonl` and
  `summaries.md`, and records Claude Code session ids in `own-sessions` for the presence
  gate.
- Each record holds the project, outcome, exit code, start and end times, duration,
  session id, model, turns, cost in USD, journal path and Perpetua version.
- A session that exits `0` without a successful result is recorded as `error`.
- `runner.log`, with one line per wake-up: the gate that closed, or the start and end of
  a session.

#### Retention and hooks

- Journal retention: only the `SESSION_RETENTION` most recent session journals are kept.
- `POST_SESSION_HOOK`, a shell command run after every session with a 120 second limit,
  receiving `PERPETUA_PROJECT`, `PERPETUA_OUTCOME`, `PERPETUA_EXIT_CODE`,
  `PERPETUA_JOURNAL`, `PERPETUA_STATE_DIR` and `PERPETUA_PROJECT_DIR`.

#### systemd integration

- Template units `perpetua@.service` (oneshot, no start timeout, lowered CPU and I/O
  priority) and `perpetua@.timer` (first run 10 minutes after boot, then 15 minutes after
  the previous run ends), rendered into the user unit directory by `perpetua enable`.
- `perpetua enable NAME --interval DURATION` writes a per-project drop-in,
  `perpetua@NAME.timer.d/10-interval.conf`, that overrides the cadence.
- A warning when lingering is disabled, since sessions would then stop at logout.

#### Platforms

- WSL 2 support: `platform/wsl/keepalive.ps1` holds one WSL client open so the
  distribution, and its timers, keep running; `platform/wsl/install-keepalive.ps1`
  registers it at Windows logon without administrator rights, and removes it with
  `-Uninstall`.

#### Installation

- `install.sh`, which installs a tagged release or a working tree into a prefix
  (`~/.local` by default) and uninstalls it without touching projects or state.
- `make` targets for installation, tests, lint, documentation and release archives.

#### Quality

- A bats test suite covering the CLI, every admission gate, outcome recording, retention,
  the post-session hook, the systemd units and the installer, run against a fake Claude
  Code.
- Continuous integration with ShellCheck, Ruff, the test suite on Ubuntu 22.04 and 24.04,
  and a strict documentation build.
- Release automation that verifies version strings, publishes a tarball with
  `SHA256SUMS` and a build provenance attestation.

#### Documentation

- A documentation site at <https://koffih.github.io/perpetua/> covering installation,
  quickstart, architecture, the session lifecycle, guardrails, operating guides, WSL,
  the CLI and configuration reference, state files, the runner log, systemd, the threat
  model and the architecture decision records.

[Unreleased]: https://github.com/koffih/perpetua/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/koffih/perpetua/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/koffih/perpetua/releases/tag/v1.0.0
