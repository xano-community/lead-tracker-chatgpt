# Lead Tracker ChatGPT Plugin

A ChatGPT plugin (plug-in) for tracking sales leads, with an interactive panel inside the chat and everything behind it on Xano: the `lead` table, the tool logic, the MCP server ChatGPT connects to, and the REST API a web board uses. Add and move leads by chatting, or move them through New → Qualified → Proposal → Won on a live board. Use it as a working starting point for building your own ChatGPT plugin on Xano.

## Why this exists

ChatGPT plugins can now show app-like interactive panels next to the conversation, not just return text. Building one with your own data usually means standing up an MCP server, a database, a hosted UI for the panel, and glue code to keep them in sync. For something as simple as a lead list, that's a lot of moving parts before anyone can say "add Maya from Northwind, $4,800."

This template collapses it into one Xano workspace. The `lead` table holds the data, four AI tools (`open_lead_tracker`, `list_leads`, `add_lead`, `update_lead_stage`) do the work, and a Xano MCP server exposes them to ChatGPT as a plugin, along with an interactive board panel. The same functions back a REST API and a single-file web board, so the chat and the browser always show the same leads. Fork it as a working example of a ChatGPT plugin with a real backend, then swap the lead model for your own.

## How it works

```
ChatGPT ──MCP──▶ Xano MCP server "Lead Tracker"
                   ├─ open_lead_tracker   → opens the board panel in the chat
                   ├─ list_leads          → read the board (the panel polls this)
                   ├─ add_lead            → insert a lead
                   ├─ update_lead_stage   → move a lead (matched by name or id)
                   └─ lead_tracker_panel  → resource: the panel HTML
Browser ──REST──▶ api:LeadTracker  (GET/POST /leads, PATCH /leads/{id}/stage, POST /seed)
                        both call the same functions ─▶ function/leads/* ─▶ table lead
```

- **One code path.** The tools and the REST endpoints are thin wrappers over `leads/list`, `leads/add`, and `leads/move_stage`, so validation and error messages are identical wherever a lead is written.
- **Interactive panel.** `open_lead_tracker` carries an output template, so ChatGPT renders the board inline as the plugin's interactive panel. Use ChatGPT's "open in tab" control to show it next to the chat; the panel switches to a full-height layout in fullscreen.
- **Live sync.** The panel re-reads `list_leads` every 2 seconds while visible, and the web board re-reads `GET /leads` every 5 seconds. A lead added or moved from either side shows up on the other, marked "Saved to Xano".
- **Text-only writes.** `add_lead` and `update_lead_stage` have no output template, so ChatGPT replies in a sentence and the open panel updates itself.
- **Panel hosting.** The `lead_tracker_panel` resource fetches `frontend/panel.html` from `PANEL_URL`. If you don't set it, it uses this repository's public copy on GitHub.

## Common use cases

- **A founder or small sales team** tracking a handful of deals by talking to ChatGPT ("move Leo to Qualified", "what's in Proposal?") instead of opening a CRM.
- **A developer learning how to build a ChatGPT plugin** who wants a complete, working MCP server, AI tools, and interactive panel on Xano to read and extend.
- **An agency building a client-facing ChatGPT plugin** that needs a real database and REST API behind the chat, starting from a pattern that already keeps the two in sync.

## Quick start

1. **Push the backend** to a Xano workspace:
   ```sh
   xano workspace push -d ./backend -w <your-workspace-id>
   ```
   Your instance needs MCP resource support (`type: "resource"` and `tool_meta` on MCP server tools). If the push rejects `backend/ai/mcp_server/lead_tracker.xs` with "Invalid block", your instance is on an older release.
2. **Load the demo leads** (six leads across every stage; safe to run twice):
   ```sh
   curl -X POST "https://<your-instance>.xano.io/api:<leadtracker-group>/seed"
   ```
   The group slug is the part after `api:` in the LeadTracker API group's base URL in Xano.
3. **Open the web board.** Open `frontend/index.html` in a browser, enter your instance URL (and the LeadTracker group slug if asked). Or skip step 2 and press **Load demo data** there.
4. **Add the plugin to ChatGPT.**
   1. In ChatGPT, turn on developer mode, go to **Settings → Plugins**, and add a plugin that points at your MCP server's stream URL (find it on the **Lead Tracker** MCP server in Xano), with no authentication.
   2. Ask "open my lead tracker". After any change to tools or the panel, open the plugin's settings and click **Refresh tools**.
   3. ChatGPT caches the panel by its resource URI (`ui://lead-tracker/panel-v1.html`). If an old panel keeps showing after you change it, bump the version in both `lead_tracker.xs` and `lead_tracker_panel.xs`.
5. **Optional: host the panel yourself.** If you edit the panel, rebuild it (`cd panel && npm install && npm run build`, which writes `frontend/panel.html`), publish that file anywhere public (Xano static hosting works), and set the workspace environment variable `PANEL_URL` to its URL.

**Before you store real customer data:** neither the MCP server nor the REST API requires authentication, so anyone with the URLs can read and change leads. Add an `auth` table to the MCP server's tool entries and `auth` to the endpoints first.

## API surface

**REST — API group `LeadTracker`**

| Method | Path | What it does |
| --- | --- | --- |
| `GET` | `/leads` | Every lead (oldest first) plus a per-stage summary: counts, dollar totals, open vs won value. |
| `POST` | `/leads` | Add a lead: `name` (required), `company`, `deal_value`, `stage` (defaults to New). |
| `PATCH` | `/leads/{lead_id}/stage` | Move a lead to `New`, `Qualified`, `Proposal`, or `Won`. Returns the lead and its previous stage. |
| `POST` | `/seed` | Load the six demo leads. Idempotent. |

**MCP server `Lead Tracker` — AI tools**

| Tool | What it does |
| --- | --- |
| `open_lead_tracker` | Returns the board and tells ChatGPT to render the panel. |
| `list_leads` | Returns the board (leads + summary). |
| `add_lead` | Adds a lead; returns `saved: true` and the updated board. |
| `update_lead_stage` | Moves a lead found by (part of) its name, or by id. |
| `lead_tracker_panel` | MCP resource: the panel HTML, fetched from `PANEL_URL`. |

**Functions:** `leads/list`, `leads/add`, `leads/move_stage`, and `leads/pipeline_summary` (the pure per-stage rollup).

## Database Tables

| Table | Purpose |
| --- | --- |
| `lead` | One sales lead: `name`, `company`, `deal_value` (USD), `stage` (New / Qualified / Proposal / Won), `updated_at`. |

## Testing

The tests ship in `backend/` and run against any workspace you push to:

```sh
xano unit_test run_all -w <your-workspace-id>
xano workflow_test run_all -w <your-workspace-id>
```

- **Unit tests** (in `backend/function/leads/`): the pipeline rollup math, the add-lead defaults and validation (blank name, negative value), and move-stage errors (no lead given, unknown lead).
- **Workflow tests** (in `backend/workflow_test/`):
  - `lead_tracker_chatgpt_seeded_board`: seeding twice gives one populated board with every stage represented and correct totals.
  - `lead_tracker_chatgpt_chat_flow`: the ChatGPT path through the real tools: `add_lead` → `update_lead_stage` by partial name → `list_leads`.
  - `lead_tracker_chatgpt_rest_flow`: the web-board path: `POST /leads` → move by id → a move for an unknown lead is rejected.

These prove the backend: the tools, functions, endpoints, and seed. They call the tools directly rather than through ChatGPT, so connecting the app and rendering the panel in a chat is something you check by hand after step 4.

## Environment variables

| Variable | Required | What it's for |
| --- | --- | --- |
| `PANEL_URL` | No | Public URL of the built `frontend/panel.html` that the `lead_tracker_panel` resource serves to ChatGPT. Unset, it uses this repository's copy on GitHub. Set it after you edit and re-host the panel. |

## Seed data

`POST /seed` adds six leads: Sam Okafor (Harbor Labs, New), Priya Shah (Cedar & Pine Interiors, New), Leo Park (Brightline Dental, Qualified), Maya Chen (Northwind Analytics, Proposal), Tom Becker (Fieldstone Logistics, Proposal), and Ana Ruiz (Kiln & Co, Won), totalling $27,600. Each is matched by name, so running the seed again adds nothing.

## Frontend

- `frontend/index.html` is the web board: a single file with no dependencies that reads and writes through the LeadTracker REST API.
- `frontend/panel.html` is the built ChatGPT panel, served to ChatGPT through the `lead_tracker_panel` resource.
- `panel/` holds the panel source (dependency-free TypeScript and CSS) and its esbuild script.
