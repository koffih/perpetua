# ADR 0002: systemd user timers as the scheduler

## Status

Accepted

## Date

2026-10-16

## Context

Something must start the runner repeatedly, for weeks, on a developer workstation or a small server, and keep doing so across crashes, reboots and logouts. Requirements:

- a rest period between the end of one run and the start of the next, whatever the run's length (seconds for a closed gate, hours for a session);
- no overlap with a run still in progress;
- no long-lived Perpetua process whose own failure stops everything;
- logs, failure state and process cleanup without code of our own;
- no root privileges;
- one schedule per project, independently enabled.

## Decision

Each project is driven by two instances of template units in the systemd **user** manager: `perpetua@<name>.timer` and `perpetua@<name>.service`.

- The service is `Type=oneshot` and runs the runner once: gates, then at most one session.
- The timer uses `OnUnitInactiveSec=15min`, measured from the moment the service last became inactive, and `OnBootSec=10min` for the first run after boot.
- `TimeoutStartSec=infinity`, because the runner enforces `MAX_SESSION` itself; `KillMode=mixed`, so that the runner is asked to stop first and everything left in the unit is killed afterwards.
- The interval is changed per project by a drop-in that `perpetua enable --interval` writes.
- Lingering (`loginctl enable-linger`) keeps the user manager running without a login session.

See the [systemd reference](../reference/systemd.md) for the units, annotated.

## Consequences

- No Perpetua process exists between runs. A bug in the runner can fail one wake-up, never the schedule: a failed service still becomes inactive, and the timer fires again.
- Overlap is impossible by construction: a unit that is still running is not started again, and the runner's `flock` additionally covers manual runs.
- Logs go to journald for free, failed runs are visible in `systemctl --user --failed`, and stray processes of a session are reaped with its control group.
- Each project's cadence is managed with standard tools (`list-timers`, `status`, `cat`), which operators already know.
- Perpetua requires Linux with a systemd user instance. macOS, BSD and containers without systemd are not supported. WSL works with systemd enabled and a keep-alive, which `perpetua doctor` checks.
- Without lingering, sessions stop at logout. `enable` and `doctor` warn about it.
- Time spent suspended does not count towards the interval (monotonic clock), and missed runs are never caught up. Both are acceptable for a cadence whose only purpose is to keep work flowing.

## Alternatives considered

**A long-running daemon** with its own loop and sleep. Needs a supervisor anyway (systemd, in practice) to survive crashes and reboots, then reimplements what the timer gives: scheduling, logging, process cleanup. Its own memory leaks, hung sleeps and signal handling become failure modes of the whole loop. Rejected.

**cron.** Schedules by wall clock, not relative to the end of the previous run: a two-hour session under a 15-minute schedule produces eight start attempts, each needing an overlap check. No process cleanup, no failure state, output mailed or lost, a minimal and surprising environment. Rejected.

**A Python supervisor** (a script managing all projects, possibly with a library such as APScheduler). One process for every project means one failure for every project. It would also add a runtime dependency and a component that must itself be installed as a service. Rejected.

**`OnCalendar=` or `OnUnitActiveSec=` timers.** Both measure from the clock or from the start of the run, so a long session swallows elapses and the rest period after it is unpredictable. Rejected in favour of `OnUnitInactiveSec=`.
