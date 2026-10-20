#!/usr/bin/env python3
"""Record the outcome of one Perpetua session.

Reads the stream-json journal written by `claude -p --output-format stream-json`
and produces, in the project's state directory:

- last-session.json   the machine-readable record of this session (overwritten)
- history.jsonl       one record per session (appended)
- summaries.md        the agent's closing report, for humans (appended)
- own-sessions        Claude Code session ids launched by Perpetua (appended),
                      so the presence gate never mistakes them for the operator

Standard library only, Python 3.8+.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import tempfile
from pathlib import Path


def parse_journal(path: Path) -> dict:
    session_id = None
    result = None
    model = None
    for raw in path.read_text(errors="replace").splitlines():
        raw = raw.strip()
        if not raw.startswith("{"):
            continue
        try:
            message = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(message, dict):
            continue
        session_id = session_id or message.get("session_id")
        if message.get("type") == "system" and message.get("subtype") == "init":
            model = message.get("model") or model
        if message.get("type") == "result":
            result = message
    return {"session_id": session_id, "result": result, "model": model}


def atomic_write(path: Path, text: str) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
    with os.fdopen(fd, "w") as handle:
        handle.write(text)
    os.replace(tmp, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--project", required=True)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--journal", required=True, type=Path)
    parser.add_argument("--exit-code", required=True, type=int)
    parser.add_argument("--outcome", required=True)
    parser.add_argument("--started", required=True, type=int)
    parser.add_argument("--ended", required=True, type=int)
    parser.add_argument("--version", default="unknown")
    args = parser.parse_args()

    parsed = parse_journal(args.journal) if args.journal.exists() else {
        "session_id": None, "result": None, "model": None}
    result = parsed["result"] or {}
    outcome = args.outcome
    if outcome == "ok" and (not result or result.get("is_error")):
        outcome = "error"

    started = dt.datetime.fromtimestamp(args.started).astimezone()
    record = {
        "project": args.project,
        "outcome": outcome,
        "exit_code": args.exit_code,
        "started_at": started.isoformat(timespec="seconds"),
        "ended_at": dt.datetime.fromtimestamp(args.ended).astimezone().isoformat(timespec="seconds"),
        "duration_s": args.ended - args.started,
        "session_id": parsed["session_id"],
        "model": parsed["model"],
        "turns": result.get("num_turns"),
        "cost_usd": result.get("total_cost_usd"),
        "journal": str(args.journal),
        "perpetua_version": args.version,
    }

    state = args.state
    state.mkdir(parents=True, exist_ok=True)
    atomic_write(state / "last-session.json", json.dumps(record, indent=2) + "\n")
    with open(state / "history.jsonl", "a") as handle:
        handle.write(json.dumps(record) + "\n")
    own = state / "own-sessions"
    known = own.read_text().split() if own.exists() else []
    if parsed["session_id"] and parsed["session_id"] not in known:
        with open(own, "a") as handle:
            handle.write(parsed["session_id"] + "\n")

    minutes = record["duration_s"] // 60
    turns = record["turns"] if record["turns"] is not None else "n/a"
    report = (result.get("result") or "").strip() or "_No closing report was produced._"
    with open(state / "summaries.md", "a") as handle:
        handle.write(
            f"\n## {started:%Y-%m-%d %H:%M} | {outcome}\n\n"
            f"Duration {minutes} min, {turns} turns, exit {args.exit_code}.\n\n"
            f"{report}\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
