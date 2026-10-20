---
description: Running Perpetua on several projects from one account, and how they share the machine and the subscription.
---

# Multiple projects

One Perpetua installation drives any number of projects. Each one is registered separately and gets its own configuration, directive, timer, lock and state. What they share is the machine, your Claude Code login and its usage quota, and the presence gate.

## Registering several projects

```bash
perpetua init ~/src/acme-api
perpetua init ~/src/acme-web
perpetua init ~/src/infra --name acme-infra

perpetua enable acme-api   --interval 15min
perpetua enable acme-web   --interval 20min
perpetua enable acme-infra --interval 1h
```

```bash
perpetua list
```

```text
acme-api                 /home/dev/src/acme-api
acme-infra               /home/dev/src/infra
acme-web                 /home/dev/src/acme-web
```

`perpetua status` without a name shows every project, one block each.

## What is per project, what is shared

| | Per project | Shared |
| --- | --- | --- |
| Configuration and directive | `NAME.env`, `.perpetua/directive.md` | |
| Timer and interval | `perpetua@NAME.timer` and its drop-in | Unit templates `perpetua@.service`, `perpetua@.timer` |
| Lock | `state/NAME/lock` | |
| Pause, `STOP`, back-off, attention | each project's own files | |
| History, summaries, journals | `state/NAME/` | |
| Presence detection | | All Claude Code transcripts in `~/.claude/projects/`, all `own-sessions` files |
| Claude login and usage quota | | `~/.claude/` |

## The presence gate is global

The presence gate looks at every Claude Code transcript on the machine, not only those of its own project. This is deliberate: when you sit down to work in Claude Code, on anything, every Perpetua project stands down. Your interactive work gets the machine and the quota, and you never find a background agent rewriting a repository you just opened.

To tell its own work apart from yours, every project records the session ids it launches in `state/NAME/own-sessions`, and the gate excludes the transcripts of the ids listed in **all** projects' files: the session transcript (`ID.jsonl`) and its subagents (`ID/subagents/agent-*.jsonl`). The runner registers an id as soon as Claude Code announces it, a few seconds into the session, not when the session ends.

!!! info "Projects run concurrently"
    A running session of `acme-web` is already listed in `acme-web/own-sessions`, so the presence gate of `acme-api` ignores it and `acme-api` starts at its own next wake-up. Several projects can work at the same time.

    What still stops all of them is **you**: as soon as you use Claude Code yourself, every project yields at its next wake-up, for `PRESENCE_WINDOW_MIN` minutes after your last interaction. Sessions already running are not interrupted.

    Concurrency has a cost on a single subscription: two agents in parallel draw on the same quota, so they reach the usage limit sooner. See [Sharing the subscription quota](#sharing-the-subscription-quota).

## Staggering intervals

Because each timer counts from the end of its own last run, projects drift apart naturally. Different intervals help them interleave rather than wake up together after a reboot (every timer has `OnBootSec=10min`):

| Project | Priority | Interval |
| --- | --- | --- |
| `acme-api` | main focus | `15min` |
| `acme-web` | secondary | `20min` |
| `acme-infra` | maintenance | `1h` |

Staggering does not serialise projects (each one runs whenever its own timer fires), but it spreads their starts, and so their draw on the quota, over time.

## Sharing the subscription quota

All projects draw from the same Claude account. Plan for it:

- **Back-off is per project.** When `acme-api` hits a usage limit, it backs off for `BACKOFF_SECONDS`. `acme-web` learns about the limit only by hitting it at its own next session, which then also ends `rate_limited` and backs off. The cost is one short failed session per project.
- **Prioritise with `MAX_SESSION` and intervals.** A maintenance project with `MAX_SESSION=1h` and `--interval 1h` leaves most of the quota to the main one.
- **Pick models per project.** `MODEL=sonnet` on routine projects, the default on the important one.
- **Pause what you do not need.** `perpetua pause acme-infra` for the week costs nothing.

Watch the balance across projects with:

```bash
for p in acme-api acme-web acme-infra; do
  printf '%-12s ' "$p"
  python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][-20:]; print(sum(x["duration_s"] for x in r)//3600, "h in the last", len(r), "sessions,", sum(x["outcome"]=="rate_limited" for x in r), "rate limited")' \
    ~/.local/state/perpetua/$p/history.jsonl
done
```

## Several repositories, one project

If a product spans several repositories that a single plan drives, register **one** Perpetua project whose `PROJECT_DIR` is the directory containing them (or the main repository), and let the plan and `CLAUDE.md` say where each task lives. One project means one lock, one plan, one question channel, and no two sessions editing related code at the same time.
