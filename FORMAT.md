# board.json — format v1

One JSON object, written by your morning agent and read by BoardBar. Leave out any optional field you don't know rather than guessing. See [`example/board.json`](example/board.json) for a complete sample.

## Top level

| Field | Required | Meaning |
|---|---|---|
| `version` | yes | Always `1`. |
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

Projects with neither `active` state nor `last_evidenced_work` are folded into a collapsed group in the heartbeat.
