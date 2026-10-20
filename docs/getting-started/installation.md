---
description: Requirements, installation and host verification for Perpetua.
---

# Installation

Perpetua is three small programs (a bash CLI, a bash session runner, a Python recorder) and two systemd unit templates. It installs into your home directory, needs no root access, and has no dependencies beyond what a standard Linux distribution ships.

## Requirements

| Requirement | Why | Check |
| --- | --- | --- |
| Linux with a systemd **user** instance | The cadence is a `systemd --user` timer. WSL2 with systemd enabled works, see [Running on WSL](../guides/wsl.md). | `systemctl --user show-environment` |
| bash 4 or later | CLI and runner | `bash --version` |
| python3 3.8 or later | Session recorder, standard library only | `python3 --version` |
| `flock` (util-linux) | One session per project | `command -v flock` |
| `timeout` (coreutils) | Hard session limit | `command -v timeout` |
| `git` | Used by the installer to fetch the release (not needed when installing from a clone) | `git --version` |
| Claude Code, logged in | The agent itself. A Claude subscription or an API key both work. | `claude --version` |

!!! tip "Recommended: the `autonomous-mode` skill"
    The default `PROMPT` written by `perpetua init` is `/autonomous-mode follow the plan`. That slash command comes from the [`autonomous-mode` skill](https://github.com/koffih/claude-skill-autonomous-mode), which keeps a single session working through a plan for hours instead of stopping after the first task. Install it into `~/.claude/skills/autonomous-mode`, or change `PROMPT` in the project configuration to something that does not depend on it.

## Install

=== "Installer"

    ```bash
    curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash
    ```

    The installer checks for bash, python3, `flock` and `timeout`, clones the requested version into a temporary directory and writes into `~/.local` by default:

    | Path | Content |
    | --- | --- |
    | `~/.local/bin/perpetua` | The CLI |
    | `~/.local/libexec/perpetua/` | The session runner (`session`) and the recorder (`record.py`) |
    | `~/.local/share/perpetua/` | systemd unit templates and project templates |

    Options, passed after `bash -s --`:

    | Option | Effect |
    | --- | --- |
    | `--prefix DIR` | Install root (default `~/.local`, or `$PREFIX` if set) |
    | `--version REF` | Git tag or branch to install (default `main`) |
    | `--uninstall` | Disable every `perpetua@*.timer`, remove the unit templates, the per-project interval drop-ins and the installed files; project configuration and state are kept |
    | `-h`, `--help` | Show the help |

    ```bash
    # a pinned release, somewhere else
    curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash -s -- --prefix /opt/perpetua --version v1.0.0

    # remove the installed files
    curl -fsSL https://raw.githubusercontent.com/koffih/perpetua/main/install.sh | bash -s -- --uninstall
    ```

    The installer is idempotent: running it again upgrades in place. See [Upgrading](../guides/operating.md#upgrading) and [Uninstalling](../guides/operating.md#uninstalling).

=== "From a clone"

    ```bash
    git clone https://github.com/koffih/perpetua.git
    cd perpetua
    make install PREFIX=~/.local
    ```

    `make install` runs `./install.sh --prefix "$(PREFIX)"`, which installs the working tree of the clone instead of downloading. The installer does this only when it runs as a file named `install.sh` inside a clone and `--version` is not given; with `--version`, or when piped from `curl`, it always downloads. The resulting layout is the same. `make uninstall PREFIX=~/.local` removes it.

Make sure the `bin` directory of the prefix is on your `PATH` (for `~/.local`, most distributions already do this):

```bash
command -v perpetua || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

!!! note "How the CLI finds its files"
    `perpetua` resolves its own location and reads `../libexec/perpetua` and `../share/perpetua` relative to it, so a prefix install is self-contained. The environment variables `PERPETUA_LIBEXEC` and `PERPETUA_SHARE` override these paths; you should not need them.

## Verify the host

```bash
perpetua doctor
```

```text
==> Perpetua 1.0.0
  ✓ Claude Code 2.1.0 (Claude Code)
  ✓ Claude credentials present
  ✓ autonomous-mode skill installed
  ✓ python3 3.12.3
  ✓ flock
  ✓ timeout
  ✓ find
  ✓ systemd user instance
  ! lingering off: loginctl enable-linger dev
  ! units not installed yet (perpetua enable installs them)

==> Host ready
```

`doctor` exits non-zero and prints `the host is not ready` only for hard failures (`✗`): Claude Code missing from `PATH`, python3 older than 3.8, a missing tool, or no systemd user instance. Warnings (`!`) are advisory.

| Check | What it looks at |
| --- | --- |
| Claude Code | `claude` on `PATH`, and its version |
| Claude credentials | `~/.claude/.credentials.json` exists, or `ANTHROPIC_API_KEY` is set |
| autonomous-mode skill | `~/.claude/skills/autonomous-mode` exists |
| python3, flock, timeout, find | Present and, for python3, 3.8 or later |
| systemd user instance | `systemctl --user show-environment` succeeds |
| Lingering | `loginctl show-user $USER -p Linger` is `yes` |
| WSL keep-alive | On WSL only: a `sleep infinity` process is running |
| Units | `perpetua@.service` exists in `~/.config/systemd/user` |

### Enable lingering

Without lingering, your systemd user instance (and every timer in it) stops when you log out. For a machine that should work overnight, enable it once:

```bash
loginctl enable-linger "$USER"
```

On most distributions this needs no root privilege for your own user. If it is refused, run it with `sudo`.

## Credentials for unattended runs

Sessions run from systemd, not from your terminal, but they run as you and read the same `~/.claude/` directory. If `claude` works in your shell, it works under Perpetua.

- **Subscription**: log in once with `claude`, then `/login`. The credentials in `~/.claude/.credentials.json` are reused by every session.
- **API key**: `ANTHROPIC_API_KEY` must be visible to the systemd user instance, not only to your shell. Import it with `systemctl --user set-environment ANTHROPIC_API_KEY=...` or a drop-in on `perpetua@.service`. See [Security: threat model](../security/threat-model.md) before storing a key on disk.

!!! info "PATH under systemd"
    systemd starts the runner with a minimal `PATH`. The runner prepends `~/.local/bin`, `~/.npm-global/bin`, `~/.local/opt/node/bin` and `/usr/local/bin`, which covers the usual Claude Code install locations. If your `claude` lives elsewhere, set `CLAUDE_BIN` to its absolute path in the project configuration.

## Next

[Quickstart :octicons-arrow-right-24:](quickstart.md){ .md-button .md-button--primary }
