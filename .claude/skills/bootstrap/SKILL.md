---
name: bootstrap
description: First-run setup script Lilo follows on a fresh clone. Walks the operator through `.mcp.json`, the tools-bridge venv, `USER.md`, optional platform MCPs (`ios-simulator` on macOS), Telegram setup, the optional Notion pipeline dashboard, and an optional smoke-test project. Use when the operator says "bootstrap", "walk me through setup", "first-time setup", or anything clearly equivalent. Skip steps that are already done (e.g. if `USER.md` exists and looks complete, confirm it and move on).
---

# bootstrap

Follow this script the first time you are launched in a fresh clone of this repo. Run through the steps in order, one question at a time — do not dump all the questions at once. Keep it conversational.

Skip steps that are already done (e.g. if `USER.md` exists and looks filled in, just confirm it with the operator and move on).

---

## Step 0 — Local config files

Three gitignored templates the operator needs locally. Check and create if missing:

1. `.mcp.json` — Lilo is fully operational with zero project-local MCP servers, so an empty file (or none at all) is the supported **minimum**. The committed `.mcp.recommended.json` is the **recommended** starting point: it wires `lilo-tools` (so registered tools are callable) and `playwright` (headless browser fallback). Copy it on first clone:

   ```bash
   [ -f .mcp.json ] || cp .mcp.recommended.json .mcp.json
   ```

   Two integrations Lilo expects are NOT configurable here:
   - **Claude-in-Chrome extension** — enabled via the `--chrome` launch flag (Step 0.4 below).
   - **Account-level connectors** (Notion, Telegram, Gmail, Calendar, HubSpot, etc.) — configured in Claude Code app settings and inherited automatically by every session. Step 2 covers the ones worth suggesting.

   Then offer platform-specific additions:

   - **macOS**: ask "Want me to wire up the iOS simulator MCP? It needs Xcode + Facebook IDB on the host (see `docs/ios-simulator-setup.md`)." If yes, edit `.mcp.json` to add the `ios-simulator` server inside `mcpServers`:
     ```json
     "ios-simulator": {
       "command": "npx",
       "args": ["-y", "ios-simulator-mcp"]
     }
     ```
     Use the Edit tool — don't tell the operator to hand-edit. If they say no or are on non-macOS, skip.

   - **Any platform**: ask "Are there other MCPs you know you want upfront (Supabase, Notion, etc.)?" — most are account-level via Claude settings (covered in Step 2), but if the operator names one that's an in-repo server they want now, add it to `.mcp.json` for them.

2. `tools/registry.json` — the bridge will boot with zero tools if this is missing (fine for a fresh clone). If the operator wants starter scaffolding, copy the example:
   ```bash
   [ -f tools/registry.json ] || cp tools/registry.example.json tools/registry.json
   ```

3. Tools-bridge venv — run the setup script if `tools/mcp-bridge/.venv/` doesn't exist:
   ```bash
   [ -d tools/mcp-bridge/.venv ] || ./tools/mcp-bridge/setup.sh
   ```
   One-time; idempotent. Installs `fastmcp` + adapter deps into
   `tools/mcp-bridge/.venv/`.

4. **Chrome extension (optional)**: if the launch command included `--chrome`, mention the `claude-in-chrome` extension gives DOM-aware browser automation. If it's not installed, point the operator at the extension store — do NOT try to install it yourself. If the operator doesn't want browser automation, skip.

---

## Step 1 — Operator profile (`USER.md`)

1. If `USER.md` does not exist, copy it from the template:
   ```bash
   cp USER.md.example USER.md
   ```
2. Ask the operator these questions, one at a time, and fill the answers into `USER.md` as you go. Keep pace — do not demand all answers before writing anything.

   - **Name** — "What should I call you?"
   - **Telegram** — "Do you want me to be able to reach you proactively on Telegram when things need your attention? (If yes, we'll wire up the bot in Step 3 and I'll ask for your `chat_id` then.)"
   - **Terseness** — "Are you usually on your phone (prefer short replies) or at a terminal (verbose is fine)?"
   - **Primary channel** — "How do you expect to reach me most of the time — Telegram, terminal, or a mix?"
   - **Anything else** — "Anything else I should know about how you work? Quiet hours, things to always or never do, projects you own?"

3. Show the operator the final `USER.md` and confirm it reads right before moving on.

---

## Step 2 — MCP suggestions

Check what MCP servers are already wired (`claude mcp list`, and read `.mcp.json`). Suggest the three below if they're missing. Do **not** install without explicit permission.

### Notion (recommended)

Powers the optional pipeline dashboard in Step 5 — a live cross-project view that refreshes on the cron tick. Even without the dashboard, Notion is useful for any project that needs shared docs/tasks the operator already lives in.

Install pointer: account-level connector — the operator adds it through the Claude account settings, not in this repo. Point them to the install flow. If they decline, note that Step 5 will be skipped.

### Supabase

Useful for projects that need a hosted Postgres, auth, storage, or edge functions without standing up infra. If the operator works on web apps or anything with a backend, suggest it.

Install pointer: also account-level — same flow as Notion. Offer to continue once they confirm it's connected.

### Playwright

Already wired into this repo's `.mcp.json`. Mention that it's available for headless browser automation when the Chrome extension isn't the right fit — the operator does not need to do anything.

Also mention the `claude-in-chrome` extension (DOM-aware browser automation) and the custom `lilo-tools` bridge — both are covered elsewhere but worth a one-line callout so the operator knows what's on deck.

---

## Step 3 — Telegram (optional)

Only run this step if the operator said yes in Step 1. Otherwise skip.

The plugin's MCP server runs on **Bun**, and the plugin itself has to be installed inside the current Claude Code session before `/telegram:configure` and `/telegram:access` become available. Lilo cannot invoke `/plugin install` or `/reload-plugins` — the operator types them.

1. **Bun (host prereq).** Check with `command -v bun`. If missing, tell the operator to install it in another terminal:
   ```bash
   curl -fsSL https://bun.sh/install | bash
   ```
   Wait for confirmation before continuing. Re-check with `command -v bun` if unsure.

2. **Install the plugin.** Have the operator run these slash commands in this session, in order:
   ```
   /plugin install telegram@claude-plugins-official
   /reload-plugins
   ```
   After `/reload-plugins`, `/telegram:configure` and `/telegram:access` become callable.

3. **Create a bot.** Tell the operator to open Telegram, DM `@BotFather`, run `/newbot`, and follow the prompts. BotFather returns an HTTP API token (looks like `123456789:AAHfiqksKZ8...`). Have them copy it.

4. **Configure the bot.** Have the operator run `/telegram:configure <token>` in this session. That writes `TELEGRAM_BOT_TOKEN` to `~/.claude/channels/telegram/.env`.

5. **Relaunch with the channel flag.** The bot won't connect until the session is launched with `--channels plugin:telegram@claude-plugins-official` (already in `README.md`'s launch line). If the current session is missing the flag, the operator must exit and restart using the full launch command from the README.

6. **Pair.** Once relaunched, the operator DMs the bot. The bot replies with a 6-character pairing code. They run `/telegram:access pair <code>` in this session.

7. **Find the `chat_id`.** With pairing complete, ask the operator to send another message to the bot. When the inbound message arrives in this session, the `chat_id` is in the `<channel>` tag — write it into `USER.md` under "Telegram chat_id" so Lilo can DM proactively.

8. **Lock it down.** Pairing is for capturing IDs; once paired, switch the policy so strangers can't trigger pairing-code replies: `/telegram:access policy allowlist`.

---

## Step 4 — Tools framework

The `tools/` framework ships inside this repo (`./tools/`). The MCP bridge reads `tools/registry.json` at startup and exposes every registered action. On a fresh clone the registry is empty (`tools/registry.example.json` is the template).

- If the operator wants to register a custom tool, they can copy the example to `registry.json` and add entries, or use the `toolify` skill against an existing sibling project to scaffold everything automatically.
- No sibling repo needed — everything the bridge needs lives in-repo.

---

## Step 5 — Pipeline dashboard (optional, recommended)

A live cross-project Notion dashboard backed by the cron tick. Refreshes every 30 minutes — same `7,37 * * * *` schedule as the outbox sweep. Skip if the operator doesn't use Notion.

Prereq: the Notion MCP must be connected at the account level (Step 2). Verify by checking `.mcp.json` or `claude mcp list` shows a Notion entry — if not, point the operator at the install flow and skip.

1. **Copy the config template:**
   ```bash
   [ -f pipeline-config.json ] || cp .claude/skills/sync/pipeline-config.example.json pipeline-config.json
   ```

2. **Create the parent page.** Ask the operator: "Want me to create a top-level Notion page called 'Lilo Pipeline' for the dashboard, or drop it under an existing page?" Use `mcp__claude_ai_Notion__notion-create-pages`:
   - For a top-level page: omit `parent` (creates as workspace-level private page).
   - Under an existing page: pass `parent: {type: "page_id", page_id: <ID>}`.
   - `properties: {"title": "Lilo Pipeline"}`, brief placeholder `content`.
   Capture the returned page id.

3. **Create the Projects database** under the parent page via `mcp__claude_ai_Notion__notion-create-database`:
   - `parent: {type: "page_id", page_id: <id from step 2>}`
   - `title: "Projects"`
   - `schema`: `CREATE TABLE ("Name" TITLE, "Status" SELECT('active':blue, 'paused':yellow, 'blocked':red, 'done':green, 'solo':gray), "Phase" RICH_TEXT, "Updated" DATE, "Team" NUMBER, "Open tasks" NUMBER, "Outbox pending" NUMBER, "Outbox archived" NUMBER, "PM live" CHECKBOX, "Summary" RICH_TEXT, "Top tasks" RICH_TEXT)`
   Capture the returned database url AND the data-source UUID (from the `<data-source url="collection://...">` tag in the response).

4. **Add a "Live & recent" view** — table sorted by `PM live DESC, Updated DESC`. Use `notion-create-view` with `database_id` from step 3, `type: "table"`, and `configure: 'SORT BY "PM live" DESC, "Updated" DESC\nSHOW "Name", "PM live", "Status", "Updated", "Phase", "Open tasks", "Outbox pending", "Team", "Summary"'`.

5. **Wire the parent page** to embed the database inline — `notion-update-page` with `command: "replace_content"` and a callout + `<database url="<db_url>" inline="true">Projects</database>` block.

6. **Fill in `pipeline-config.json`** (at orchestrator root, NOT inside `.claude/`) with the captured ids:
   - `notion_page_id`: the parent page id
   - `notion_page_url`: the parent page url
   - `notion_database_url`: the database url
   - `data_source_id`: the data source uuid (NOT the database uuid)

7. **Verify.** Run `/sync` once. The skill renders `pipeline.md` + `pipeline.json` locally, then upserts each sibling project into the Projects database (creating rows on first run, caching their ids back into `pipeline-config.json` at the orchestrator root), and regenerates the parent page's Snapshot / What's next / Recent activity sections.

The cron tick takes over from there.

---

## Step 6 — Smoke test

Suggest running `new project: hello` to scaffold a throwaway project and verify the pipeline works end-to-end. Offer to nuke it afterwards.

---

## Step 7 — Wrap up

- Recap what was set up, what was skipped, and any next steps the operator still owes (e.g. install Notion or Supabase MCP in account settings).
- Mention two opt-ins they may want now that setup is done:
  - **`/advisor opus`** — enables a pooled opus-level reviewer that Lilo, every PM, and every specialist can consult on judgment calls. One-time user-level setting. `/advisor off` disables.
  - **`/poll on`** — registers the recurring `/sync` cron (sweep + dashboard refresh, twice an hour). Off by default; the operator opts in. `/poll off` removes it. Manual `/sync` works any time without the cron.
- Remind them that `USER.md` is gitignored — safe to commit the repo without leaking their profile.
- Stop. Wait for the operator's next instruction.
