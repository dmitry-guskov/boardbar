#!/usr/bin/env python3
"""Validate a BoardBar snapshot (format v1, revision 1.1) and optionally publish it atomically.

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
from urllib.parse import urlparse

TASK_STATES = {"todo", "doing", "waiting", "done", "deferred", "cancelled", "unknown"}
PROJECT_STATES = {"active", "parked", "completed", "unknown"}
MILESTONE_STATES = {"planned", "achieved", "cancelled", "unknown"}
BASES = {"confirmed", "recommendation", "inference"}
COVERAGE = {"checked", "partial", "unavailable", "not_configured"}
CONFIDENCE = {"high", "medium", "low"}
EFFORTS = {"15m", "1h", "half-day", "multi-day"}
EFFORT_BASES = {"user", "source", "estimate"}
REVISIONS = {"1.0", "1.1"}
RECEIPT_STATES = {"applied", "acknowledged", "conflict", "rejected"}
DATE_FIELDS = ("due", "event_at", "since", "open_since", "status_as_of")
MAX_DECISIONS, MAX_READING = 5, 3
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


def is_text(value):
    return isinstance(value, str) and value.strip() != ""


def is_link(value, schemes):
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme in schemes and (parsed.netloc or parsed.scheme == "zotero")


class Checker:
    def __init__(self):
        self.errors = []

    def err(self, msg):
        self.errors.append(msg)

    def enum(self, where, obj, key, allowed, required=False):
        if key not in obj:
            if required:
                self.err(f"{where}: {key} is required")
            return
        if obj[key] not in allowed:
            self.err(f"{where}: {key} must be one of {sorted(allowed)}")

    def dates(self, where, obj, keys):
        for k in keys:
            if k in obj and obj[k] is not None and not is_date(obj[k]):
                self.err(f"{where}: {k} is not an ISO date")

    def sources(self, where, obj):
        srcs = obj.get("sources", [])
        if not isinstance(srcs, list):
            self.err(f"{where}: sources must be a list")
            return
        for s in srcs:
            if not isinstance(s, dict) or not is_text(s.get("ref")):
                self.err(f"{where}: each source needs a ref")
                continue
            self.dates(where + " source", s, ("date",))
            self.enum(where + " source", s, "confidence", CONFIDENCE)

    def note_path(self, where, obj):
        np = obj.get("note_path")
        if np is None:
            return
        if not isinstance(np, str) or np.startswith("/") or ".." in np.split("/"):
            self.err(f"{where}: note_path must be a relative path inside the vault")
        elif PRIVATE_PREFIXES and np.startswith(PRIVATE_PREFIXES):
            self.err(f"{where}: note_path points into a private prefix")

    def unique(self, where, seen, ident):
        if not is_text(ident):
            self.err(f"{where}: id is required")
        elif ident in seen:
            self.err(f"{where}: duplicate id")
        seen.add(ident)


def validate(board, allow_fixture=False):
    c = Checker()
    err = c.err
    if not isinstance(board, dict):
        return ["top level must be an object"]
    if board.get("version") != 1:
        err("version must be 1")
    if "schema_revision" in board and board["schema_revision"] not in REVISIONS:
        err(f"schema_revision must be one of {sorted(REVISIONS)}")
    if board.get("fixture") and not allow_fixture:
        err("fixture snapshot must not be published")
    if "generated_at" not in board:
        err("generated_at is required")
    c.dates("board", board, ("generated_at", "next_refresh_at"))
    for i, cov in enumerate(board.get("coverage", [])):
        c.enum(f"coverage[{i}]", cov, "status", COVERAGE, required=True)

    areas = board.get("areas", {})
    tasks = board.get("tasks")
    if not isinstance(tasks, list):
        err("tasks must be a list")
        tasks = []
    task_ids = set()
    for i, t in enumerate(tasks):
        where = f"tasks[{i}] ({t.get('id', '?')})"
        c.unique(where, task_ids, t.get("id"))
        if not is_text(t.get("title")):
            err(f"{where}: title is required")
        c.enum(where, t, "state", TASK_STATES, required=True)
        c.enum(where, t, "basis", BASES)
        if areas and t.get("area") not in areas:
            err(f"{where}: area '{t.get('area')}' not in areas")
        c.dates(where, t, DATE_FIELDS)
        c.sources(where, t)
        c.note_path(where, t)
        if "effort" in t:
            c.enum(where, t, "effort", EFFORTS)
            c.enum(where, t, "effort_basis", EFFORT_BASES, required=True)

    top = board.get("top_ids", [])
    if len(top) > 3:
        err("top_ids has more than 3 entries")
    for tid in top:
        if tid not in task_ids:
            err(f"top_ids references unknown task '{tid}'")

    projects = board.get("projects", [])
    project_ids = set()
    for i, p in enumerate(projects):
        project_ids.add(p.get("id"))
    seen_projects = set()
    for i, p in enumerate(projects):
        where = f"projects[{i}] ({p.get('id', '?')})"
        c.unique(where, seen_projects, p.get("id"))
        if not is_text(p.get("name")):
            err(f"{where}: name is required")
        c.enum(where, p, "state", PROJECT_STATES, required=True)
        lw = p.get("last_evidenced_work")
        if lw is not None and not (isinstance(lw, dict) and is_date(lw.get("date")) and is_text(lw.get("source"))):
            err(f"{where}: last_evidenced_work needs date and source")
        if "parent_id" in p and (p["parent_id"] not in project_ids or p["parent_id"] == p.get("id")):
            err(f"{where}: parent_id must reference another project")
        c.note_path(where, p)
        ms_ids = set()
        for j, m in enumerate(p.get("milestones", [])):
            mw = f"{where} milestones[{j}]"
            c.unique(mw, ms_ids, m.get("id"))
            if not is_text(m.get("title")):
                err(f"{mw}: title is required")
            if not is_date(m.get("date")):
                err(f"{mw}: date (target or event date) is required")
            c.enum(mw, m, "state", MILESTONE_STATES, required=True)
            c.enum(mw, m, "basis", BASES)
            c.dates(mw, m, ("achieved_at", "status_as_of"))
            if m.get("achieved_at") and m.get("state") != "achieved":
                err(f"{mw}: achieved_at is only allowed when state is achieved")
            c.sources(mw, m)

    decisions = board.get("decisions", [])
    decision_ids = set()
    if not isinstance(decisions, list):
        err("decisions must be a list")
        decisions = []
    if len(decisions) > MAX_DECISIONS:
        err(f"decisions has more than {MAX_DECISIONS} entries")
    for i, d in enumerate(decisions):
        where = f"decisions[{i}] ({d.get('id', '?')})"
        c.unique(where, decision_ids, d.get("id"))
        for k in ("question", "why"):
            if not is_text(d.get(k)):
                err(f"{where}: {k} is required")
        opts = d.get("options", [])
        if not isinstance(opts, list) or not all(is_text(o) for o in opts):
            err(f"{where}: options must be a list of strings")
        if "task_id" in d and d["task_id"] not in task_ids:
            err(f"{where}: task_id references unknown task")
        c.enum(where, d, "basis", BASES)
        c.dates(where, d, ("due", "status_as_of"))
        c.sources(where, d)

    q = board.get("question")
    if q is not None:
        if not isinstance(q, dict) or not is_text(q.get("text")):
            err("question must be null or an object with text")
        else:
            if "task_id" in q and q["task_id"] not in task_ids:
                err("question: task_id references unknown task")
            if "decision_id" in q and q["decision_id"] not in decision_ids:
                err("question: decision_id references unknown decision")
            c.enum("question", q, "basis", BASES)
            c.sources("question", q)

    reading = board.get("reading", [])
    if not isinstance(reading, list):
        err("reading must be a list")
        reading = []
    if len(reading) > MAX_READING:
        err(f"reading has more than {MAX_READING} entries")
    reading_ids = set()
    for i, r in enumerate(reading):
        where = f"reading[{i}] ({r.get('id', '?')})"
        c.unique(where, reading_ids, r.get("id"))
        if not is_text(r.get("title")):
            err(f"{where}: title is required")
        authors = r.get("authors", [])
        if not isinstance(authors, list) or not all(is_text(a) for a in authors):
            err(f"{where}: authors must be a list of strings")
        if "url" in r and not is_link(r["url"], {"http", "https"}):
            err(f"{where}: url must be http(s)")
        if "zotero_url" in r and not is_link(r["zotero_url"], {"zotero", "https"}):
            err(f"{where}: zotero_url must be zotero:// or https")
        c.dates(where, r, ("published", "recommended_at"))
        for k in ("collections", "tags"):
            if k in r and (not isinstance(r[k], list) or not all(isinstance(x, str) for x in r[k])):
                err(f"{where}: {k} must be a list of strings")
        c.sources(where, r)

    receipts = board.get("feedback_receipts", {})
    if not isinstance(receipts, dict):
        err("feedback_receipts must be an object keyed by event_id")
        receipts = {}
    for eid, rc in receipts.items():
        where = f"feedback_receipts[{eid}]"
        if not isinstance(rc, dict):
            err(f"{where}: must be an object")
            continue
        c.enum(where, rc, "status", RECEIPT_STATES, required=True)
        if not is_date(rc.get("processed_at")):
            err(f"{where}: processed_at is required")
        if rc.get("status") in ("conflict", "rejected") and not is_text(rc.get("reason")):
            err(f"{where}: reason is required for conflict or rejected")
        if "reply" in rc and not isinstance(rc["reply"], str):
            err(f"{where}: reply must be text")

    return c.errors


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
