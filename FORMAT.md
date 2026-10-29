# board.json — format v1 (revision 1.1)

One JSON object, written by your morning agent and read by BoardBar. Leave out any optional field you don't know rather than guessing. See [`example/board.json`](example/board.json) for a complete sample.

## Top level

| Field | Required | Meaning |
|---|---|---|
| `version` | yes | Always `1`. Revision 1.1 only adds optional fields. |
| `schema_revision` | | `"1.0"` or `"1.1"`. |
| `generated_at` | yes | ISO date-time when the agent wrote the file. |
| `generated_by` | | Who wrote it, e.g. `"chief"`. |
| `timezone` | | IANA name, e.g. `"America/Toronto"`. |
| `next_refresh_at` | | When the next run is expected. The app calls the board late 3h after this. Without it, the board is late after 36h. |
| `brief` | | One or two sentences about the day. |
| `coverage` | | List of sources and whether they were actually checked (see below). |
| `areas` | | `{ "id": {"label": "…"} }`. Order sets the colors and timeline lanes. |
| `top_ids` | | 0–3 task IDs in priority order. The app never re-ranks them. |
| `tasks` | yes | List of tasks (see below). |
| `projects` | | List of projects for the heartbeat (see below). |
| `decisions` | | 1.1. At most 5 open choices that need the user's judgment (see below). |
| `question` | | 1.1. Zero or one clarifying question, or `null`. |
| `reading` | | 1.1. At most 3 reading recommendations (see below). |
| `feedback_receipts` | | 1.1. Results of applying the user's status updates (see the feedback section). |
| `fixture` | | `true` for example or test data. Shows a banner, skips the late check, and the validator refuses to publish it. |

## coverage item

`source`, `status` (`checked` · `partial` · `unavailable` · `not_configured`), `checked_at`, `note`.

## task

| Field | Meaning |
|---|---|
| `id`, `title` | Required. Keep `id` the same from day to day. |
| `short` | Optional short label for the timeline. |
| `area`, `project_id` | Which area lane, and which project it belongs to. |
| `state` | `todo` · `doing` · `waiting` · `done` · `deferred` · `cancelled` · `unknown` |
| `basis` | `confirmed` · `recommendation` (shown as "suggested") · `inference` (shown as "inferred") |
| `status_as_of` | Date the state was last known to be true. |
| `due` | A verified deadline (date or date-time). |
| `event_at` | An event date, as opposed to a deadline. |
| `since`, `waiting_on` | For waiting items. |
| `open_since` | When the item was first captured. |
| `priority` | `"high"` shows a tag. |
| `why` | One line shown under top items and on hover. |
| `note_path` | Note path relative to the vault. Clicking opens it in Obsidian. |
| `sources` | `[{ "ref", "date", "confidence": "high"/"medium"/"low" }]`, shown on hover. |
| `effort`, `effort_basis` | Experimental. `15m` · `1h` · `half-day` · `multi-day`: active personal time, not counting waiting or compute time. `effort_basis` (`user` · `source` · `estimate`) is required when `effort` is set. Leave it out when unknown. |

A task with `basis: "recommendation"` is a **suggestion, not a commitment**. The app lists suggestions separately and doesn't count them as open work.

## project

| Field | Meaning |
|---|---|
| `id`, `name` | Required. |
| `area` | Area id. |
| `state` | `active` · `parked` · `completed` · `unknown` |
| `state_note` | Short explanation, shown on hover. |
| `last_evidenced_work` | `{ "date", "source" }`. Actual work, not just a note edit. Leave it out if unknown. |
| `next` | `{ "text", "basis" }` |
| `note_path` | As for tasks. |
| `parent_id` | 1.1. ID of a parent project. The app nests children under their parent. |
| `milestones` | 1.1. Only real, sourced, dated deliverables or events (see below). |

Projects with neither `active` state nor `last_evidenced_work` are folded into a collapsed group in the heartbeat.

## milestone (1.1)

| Field | Meaning |
|---|---|
| `id`, `title`, `date` | Required. `date` is the target or event date. A verified date doesn't mean the milestone was achieved. |
| `state` | Required. `planned` (an adopted milestone, not just a suggestion) · `achieved` · `cancelled` · `unknown` |
| `achieved_at` | Only when `state` is `achieved`. |
| `basis`, `status_as_of`, `sources` | As for tasks. |

Don't invent milestones, durations or overdue states just to fill a project's lane.

## decision (1.1)

`id`, `question` and `why` are required. Optional: `options` (strings, never invented), `due` (a verified date), `task_id`, `basis` (whether the user asked for this choice or you're recommending it), `status_as_of`, `sources`. Unknown task statuses are not decisions.

## question (1.1)

`{ "text", "why", "task_id", "decision_id", "basis", "sources" }`, with only `text` required. If it repeats a decision, set `decision_id` and the app shows it only once. Use `null` or leave it out when there's none; never send the text "None".

## reading item (1.1)

`id` and `title` are required. Optional: `authors` (a list of strings), `published`, `url` (http or https), `zotero_url` (`zotero://` or https), `why`, `recommended_at` (keep the original date when carrying an item forward), `collections`, `tags`, `sources`. An empty list means nothing was recommended, not that the library was checked.

## Feedback log and receipts (1.1)

When feedback is on (the default; turn it off with `defaults write local.boardbar feedbackEnabled -bool false`), the expanded view's "Set status…" menu adds one JSON line to `board-feedback.jsonl` next to `board.json`. You can change the path with the `feedbackPath` default. The app only ever adds lines. It never edits or deletes them.

```json
{"action":"done","actor":"sam","event_id":"<uuid>","note":"","previous_state":"unknown","recorded_at":"2026-10-28T12:31:05-04:00","snapshot_generated_at":"2026-10-28T07:11:00-04:00","task_id":"tqc-reimbursement","via":"BoardBar"}
```

`action` is one of `done` · `todo` · `doing` · `waiting` · `cancelled` · `comment`. "Cancel task" means `cancelled`, not deleted.

A **`comment`** event carries the user's text in `note` (required, at most 4000 characters) and changes no status. The curator reads every unreviewed comment at its next run and acknowledges it with a receipt. It may then act on what the comment says (for example, add a `waiting_on` or change a date) through its normal evidence rules, treating the comment as a dated statement from the user.

Rules for the curator:
- Replay the whole log on every run and overlay valid events on the inventory built from your sources. Use `event_id` to avoid applying an event twice.
- The latest valid event for a task wins over older evidence and over your own inferences, for that task only. It proves nothing beyond that task's status.
- If newer evidence contradicts an event, report a `conflict`; don't silently reopen the task.
- Report malformed lines and unknown task IDs as `rejected`, and never create tasks from them.
- Publish a receipt for each event, in the same atomic write as the task states. Use `acknowledged` for comments. `reason` is required for `conflict` and `rejected`. `reply` is an optional short answer, which the app shows under the user's comment:

```json
"feedback_receipts": { "<event_id>": { "status": "applied" | "acknowledged" | "conflict" | "rejected", "processed_at": "<ISO date-time>", "reason": "…", "reply": "…" } }
```

For status updates, the app shows "pending" until a receipt appears, then "conflict" or "not applied" with the reason. For comments, it shows "for review" with the next run time, then "reviewed" plus your reply. A receipt only covers the board; it doesn't mean any note was updated.
