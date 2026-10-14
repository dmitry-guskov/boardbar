#!/usr/bin/env python3
"""Validate a menu-bar board snapshot (format v1) and optionally publish it atomically.

Usage:
  python3 validate_board.py board.tmp.json
  python3 validate_board.py board.tmp.json --publish board.json

Exit code 0 = valid (and published if requested); 1 = invalid, target left untouched.
Format spec: FORMAT.md
"""
import json
import os
import sys
from datetime import date, datetime

TASK_STATES = {"todo", "doing", "waiting", "done", "deferred", "cancelled", "unknown"}
PROJECT_STATES = {"active", "parked", "completed", "unknown"}
BASES = {"confirmed", "recommendation", "inference"}
COVERAGE = {"checked", "partial", "unavailable", "not_configured"}
CONFIDENCE = {"high", "medium", "low"}
DATE_FIELDS = ("due", "event_at", "since", "open_since", "status_as_of")
# Comma-separated note-path prefixes that must never appear on the board, e.g. "Private/,Journal/"
PRIVATE_PREFIXES = tuple(p for p in os.environ.get("BOARD_PRIVATE_PREFIXES", "").split(",") if p)


def is_date(value):
    if not isinstance(value, str):
        return False
    try:
        if len(value) == 10:
            date.fromisoformat(value)
        else:
            datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def validate(board, allow_fixture=False):
    errors = []
    err = errors.append
    if board.get("version") != 1:
        err("version must be 1")
    if board.get("fixture") and not allow_fixture:
        err("fixture snapshot must not be published")
    for key in ("generated_at", "next_refresh_at"):
        if key in board and not is_date(board[key]):
            err(f"{key} is not an ISO date-time")
    if "generated_at" not in board:
        err("generated_at is required")
    for i, c in enumerate(board.get("coverage", [])):
        if c.get("status") not in COVERAGE:
            err(f"coverage[{i}].status must be one of {sorted(COVERAGE)}")
    areas = board.get("areas", {})
    tasks = board.get("tasks")
    if not isinstance(tasks, list):
        err("tasks must be a list")
        tasks = []
    ids = set()
    for i, t in enumerate(tasks):
        where = f"tasks[{i}] ({t.get('id', '?')})"
        if not t.get("id") or not t.get("title"):
            err(f"{where}: id and title are required")
        if t.get("id") in ids:
            err(f"{where}: duplicate id")
        ids.add(t.get("id"))
        if t.get("state") not in TASK_STATES:
            err(f"{where}: state must be one of {sorted(TASK_STATES)}")
        if "basis" in t and t["basis"] not in BASES:
            err(f"{where}: basis must be one of {sorted(BASES)}")
        if areas and t.get("area") not in areas:
            err(f"{where}: area '{t.get('area')}' not in areas")
        for f in DATE_FIELDS:
            if f in t and not is_date(t[f]):
                err(f"{where}: {f} is not an ISO date")
        for s in t.get("sources", []):
            if "confidence" in s and s["confidence"] not in CONFIDENCE:
                err(f"{where}: source confidence must be high|medium|low")
        if PRIVATE_PREFIXES and str(t.get("note_path", "")).startswith(PRIVATE_PREFIXES):
            err(f"{where}: note_path points into a private prefix")
    top = board.get("top_ids", [])
    if len(top) > 3:
        err("top_ids has more than 3 entries")
    for tid in top:
        if tid not in ids:
            err(f"top_ids references unknown task '{tid}'")
    pids = set()
    for i, p in enumerate(board.get("projects", [])):
        where = f"projects[{i}] ({p.get('id', '?')})"
        if not p.get("id") or not p.get("name"):
            err(f"{where}: id and name are required")
        if p.get("id") in pids:
            err(f"{where}: duplicate id")
        pids.add(p.get("id"))
        if p.get("state") not in PROJECT_STATES:
            err(f"{where}: state must be one of {sorted(PROJECT_STATES)}")
        lw = p.get("last_evidenced_work")
        if lw is not None and not (is_date(lw.get("date")) and lw.get("source")):
            err(f"{where}: last_evidenced_work needs date and source")
        if PRIVATE_PREFIXES and str(p.get("note_path", "")).startswith(PRIVATE_PREFIXES):
            err(f"{where}: note_path points into a private prefix")
    return errors


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    src = argv[0]
    target = argv[argv.index("--publish") + 1] if "--publish" in argv else None
    try:
        with open(src, encoding="utf-8") as fh:
            board = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"INVALID: cannot read JSON: {exc}")
        return 1
    errors = validate(board, allow_fixture=target is None)
    if errors:
        print(f"INVALID: {len(errors)} problem(s)")
        for e in errors:
            print(" -", e)
        return 1
    if target:
        os.replace(src, target)
        print(f"OK: published {target}")
    else:
        print("OK: valid")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
