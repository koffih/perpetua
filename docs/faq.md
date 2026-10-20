---
description: Frequently asked questions about Perpetua.
---

# FAQ

## General

??? question "What is Perpetua, in one sentence?"
    A systemd user timer, a guarded session runner and a recorder that together run `claude -p` on your project again and again, each time with a fresh context, your standing directive and a hard time limit, and write down what happened.

??? question "Is this an official Anthropic project?"
    No. Perpetua is an independent open-source project under the Apache-2.0 license. It drives the Claude Code CLI as documented and does not modify it.

??? question "Why not just run `/loop` or keep one long Claude Code session open?"
    A single long session accumulates context until its earliest instructions and decisions are compressed or forgotten. Perpetua starts every session clean and makes the plan, the progress notes and git the only memory, which the operator can read and correct. It also survives reboots, usage limits and crashes without anyone restarting it, and it stands down when you start working. See [ADR 0001](adr/0001-fresh-context-per-session.md).

??? question "Does it need an API key?"
    No. It uses whatever login your `claude` command uses. A Claude subscription works, and usage limits are handled with an automatic back-off. An API key in `ANTHROPIC_API_KEY` works too. See [ADR 0003](adr/0003-subscription-auth.md).

??? question "Does it work on macOS?"
    Not as shipped. The cadence relies on a systemd user instance, which macOS does not have. The runner also uses GNU `date`, `find` and `flock`. Porting is possible (a launchd agent calling the runner, GNU tools from Homebrew) but it is not supported or tested.

??? question "Does it work on WSL?"
    Yes, WSL2 with systemd enabled. Follow [Running on WSL](guides/wsl.md) to keep the distribution alive overnight.

## Sessions

??? question "Why is nothing happening?"
    Read the last runner log lines, they say why:

    ```bash
    perpetua status NAME
    perpetua logs NAME
    ```

    The most common reasons are `gate:presence` (you used Claude Code in the last 10 minutes, or a Claude Code session is still open), `gate:stop` (paused, or a `.perpetua/STOP` file), `gate:backoff` (a usage limit), `gate:attention` (a question waits for you in `PLAN.md`), or `cadence disabled` in `status` (run `perpetua enable NAME`). If `runner.log` does not exist at all, the timer never ran: check `systemctl --user list-timers 'perpetua@*'`.

??? question "How do I start a session right now?"
    `perpetua run NAME --force`. It runs in the foreground and skips the presence and attention gates. It never skips a pause, a running session or a back-off.

??? question "How long does a session last?"
    As long as the agent works, up to `MAX_SESSION` (4 hours by default). With the `autonomous-mode` skill a session chains tasks until the plan is done, the limit is reached or a usage limit stops it.

??? question "What happens when I hit my usage limit?"
    The session is classified `rate_limited` and the project backs off for `BACKOFF_SECONDS` (one hour by default). Wake-ups during the back-off close at the back-off gate. `perpetua resume NAME` clears it early.

??? question "What happens if my machine reboots during a session?"
    On a clean shutdown or reboot, systemd stops the service, the runner forwards `SIGTERM` to the session, and it is recorded as `interrupted` (provided it exits within systemd's stop timeout). A crash or a power loss kills it without a record; its partial journal stays in `sessions/`. After boot, the timer fires 10 minutes in, and the next session finds the interrupted work in the repository. The shipped directive tells it to finish that work first.

??? question "Can two sessions run on the same project at once?"
    No. A per-project `flock` makes the second one exit with `gate:lock`, and `--force` does not override it.

??? question "Can it run several projects?"
    Yes, any number, and they run concurrently: each Perpetua session registers its own id while it runs, so projects never mistake each other for the operator. They still share your usage quota, and your own Claude Code activity pauses all of them. See [Multiple projects](guides/multiple-projects.md).

## Safety

??? question "Is it safe to run with `--dangerously-skip-permissions`?"
    It is as safe as the environment you run it in. With that flag the agent can run any command your user can. Perpetua bounds when and how long sessions run, and the directive tells the agent what not to do, but neither is a sandbox. Protect the default branch, require CI, scope your git credentials, and consider a dedicated user or VM. Read [Guardrails](concepts/guardrails.md) and the [threat model](security/threat-model.md).

??? question "Can the agent change its own rules?"
    The configuration lives in `~/.config/perpetua/`, outside the repository. The directive lives in `.perpetua/` inside it, and the shipped directive forbids editing that directory. That prohibition is an instruction, not a permission boundary: review changes to `.perpetua/` in pull requests like any other change, or keep the directive outside the repository by setting `DIRECTIVE_FILE` to an absolute path.

??? question "Will it push to my main branch?"
    The directive forbids pushing to the default branch, force-pushing and merging with a failing check. Make it impossible as well with branch protection on your git host.

??? question "Does Perpetua send data anywhere?"
    Perpetua itself makes no network calls. Claude Code talks to Anthropic as it always does, and your `POST_SESSION_HOOK` does whatever you write in it.

## Operation

??? question "How do I stop everything immediately?"
    ```bash
    perpetua pause NAME
    systemctl --user stop perpetua@NAME.service
    ```

    The first line prevents new sessions, the second stops the running one, which is recorded with outcome `interrupted`. See [Operating](guides/operating.md#stopping-a-running-session).

??? question "Where are the logs?"
    `~/.local/state/perpetua/NAME/runner.log` (also `perpetua logs NAME`), journald (`journalctl --user -u perpetua@NAME`), and the full session journals in `~/.local/state/perpetua/NAME/sessions/`.

??? question "How much disk does it use?"
    Mostly session journals: at most `SESSION_RETENTION` of them (200 by default) per project. A long session's stream-json journal is typically a few megabytes. `history.jsonl` and `summaries.md` grow by a few hundred bytes per session and are never truncated.

??? question "How do I change the interval?"
    `perpetua enable NAME --interval 30min`. The interval counts from the end of the previous run. Accepted forms: a number of seconds, or a number followed by `s`, `min` or `h`.

??? question "Do configuration changes need a restart?"
    No. The runner reads the project configuration at every wake-up. Only the interval lives in systemd and needs `perpetua enable --interval`.

??? question "What does the agent's question look like, and how do I answer?"
    It rewrites the `Pending question:` line of `PLAN.md` with context, options and a recommendation. Answer in the plan, then set the line back to `Pending question: none`. Until then, the project runs at most one session per six hours. See [Writing a directive](guides/writing-a-directive.md#the-pending-question-convention).
