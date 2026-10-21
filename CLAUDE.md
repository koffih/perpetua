# Working on Perpetua

Perpetua keeps a software project moving with nobody at the keyboard: a systemd user timer starts a guarded runner, the runner starts one unattended Claude Code session on the project, records what happened, and the timer waits before the next one. This file is the brief for any Claude Code session that develops Perpetua itself.

## Map

| Path | Role |
| --- | --- |
| `bin/perpetua` | CLI (bash): init, enable, disable, remove, run, pause, resume, status, list, logs, summaries, doctor |
| `libexec/perpetua/session` | Runner (bash): five admission gates, then one `claude -p` session under `timeout` |
| `libexec/perpetua/record.py` | Recorder (Python 3.8+, standard library only): last-session.json, history.jsonl, summaries.md |
| `share/perpetua/systemd/` | `perpetua@.service` and `perpetua@.timer` templates |
| `share/perpetua/templates/` | Project configuration and directive templates written by `perpetua init` |
| `share/perpetua/skills/autonomous-mode/` | Bundled skill behind the default `PROMPT` |
| `platform/vps/bootstrap.sh` | Fresh server to Perpetua host, as root, idempotent |
| `platform/wsl/` | Windows-side keep-alive for WSL2 |
| `tests/` | bats suite with a fake `claude` and a fake `systemctl`; never consumes a real session |
| `docs/` | Material for MkDocs site; `docs/adr/` holds the architecture decisions |

Read `docs/concepts/architecture.md`, `docs/concepts/guardrails.md` and the ADRs before changing behaviour.

## Invariants

- Gates run in this order: stop, lock, back-off, presence, attention. A closed gate exits 0 so the timer keeps its cadence. `--force` skips presence and attention only, never the first three.
- Gates fail closed: when in doubt, do not start a session (ADR 0006).
- One session per project per host (`flock`); sessions never overlap (`OnUnitInactiveSec`).
- No daemon, no database, no network service of Perpetua's own. State is plain files under `$XDG_STATE_HOME/perpetua/`.
- Secrets are never printed, logged, committed or passed on a command line. The Claude token lives in `$XDG_CONFIG_HOME/perpetua/environment`, mode 600.
- Runtime dependencies stay at what a minimal Linux ships: bash 4, python3 3.8 standard library, util-linux, coreutils, systemd.
- No root at runtime. Only `platform/vps/bootstrap.sh` runs as root, and only once per server.

## Commands

```bash
make test      # bats suite (npx bats@1.11.0), no Claude session consumed
make lint      # shellcheck on every shell file listed in SHELLS, version check, python compile
make docs      # strict MkDocs build; a broken link fails it
make dist      # release tarball in dist/
./platform/vps/bootstrap.sh --dry-run --no-packages   # print the server setup without changing anything
```

shellcheck missing locally: `uvx --from shellcheck-py shellcheck -x <files>`.

## Definition of done for a change

1. Tests added or updated in `tests/` (one behaviour per `@test`), `make test` and `make lint` green.
2. Every user-visible change documented in the same change: the matching page under `docs/`, `README.md` and `README.fr.md` when the quickstart or the feature list moves, an entry under `[Unreleased]` in `CHANGELOG.md`.
3. A structural choice gets an ADR in `docs/adr/` and a line in `docs/adr/index.md`.
4. New shell files are added to `SHELLS` in the Makefile.
5. Releases bump `VERSION` in `bin/perpetua` and `PERPETUA_VERSION` in `libexec/perpetua/session` together (`make version-check`).
6. Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`). Work on a branch; nothing is pushed or released without the maintainer.

## Roadmap: running a fleet of VPS

The 1.1 bootstrap gets one server running. Candidate next steps, roughly in order of value:

1. **Remote status**: `perpetua status --json` and a `POST_SESSION_HOOK` recipe that posts each outcome to a chat webhook, so a fleet can be watched from one place.
2. **Fleet inventory**: a small `fleet` command or script that runs `perpetua status --json` over SSH on a list of hosts and prints one table.
3. **Token expiry**: detect an authentication failure in the session journal, classify it as outcome `auth_error`, pause the project and say so in `status` and `doctor`.
4. **Disk hygiene**: cap the size of `sessions/` in addition to `SESSION_RETENTION`, and warn in `doctor` when the disk is nearly full.
5. **Bootstrap from a URL**: `curl ... | sudo bash -s -- --version vX.Y.Z ...` without first copying an archive.
6. **cloud-init example**: `platform/vps/cloud-init.yaml` that runs the bootstrap at first boot.
7. **Resource limits**: optional `MemoryMax=` and `CPUQuota=` in the service through `perpetua enable` options, so a runaway build cannot starve the host.
8. **Hardening**: optional systemd sandboxing (`ProtectSystem=strict`, `ReadWritePaths=` the project) documented in the threat model.

Keep each item small, tested and documented; open it as its own pull request.
