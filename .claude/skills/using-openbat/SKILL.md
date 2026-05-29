---
name: using-openbat
description: "Use the OpenBat CLI + MCP to manage chatbots, conversations, analyses, workflows, reports, and experiments end-to-end. Triggers on any mention of OpenBat, chatbot analytics, conversation sentiment, ingest/read/admin/PAT keys, or @openbat/sdk integration."
source: project
date_added: "2026-05-13"
---

# Using OpenBat (CLI + MCP)

OpenBat lets agents create chatbots, capture conversations from an external
application, run AI-driven analyses, ship workflows that fire webhooks, build
AI-native reports, and run prompt experiments — all through a CLI
(`@openbat/cli`) and an MCP server (`@openbat/mcp`) that share a single
v1 HTTP surface.

This is the **single comprehensive reference**. Per-flow skills exist for
deeper guidance:
- `openbat-onboarding` — create + onboard a chatbot (flow 0)
- `openbat-settings` — keys, webhooks, metadata (flow 1)
- `openbat-org-admin` — org rename + members + invitations
- `openbat-analysis` — analysis definitions (flow 2)
- `openbat-conversations` — time-windowed reads (flow 3)
- `openbat-users-orgs` — external users + orgs health (flow 4)
- `openbat-workflows` — workflow DSL → webhook (flow 5)
- `openbat-reports` — create + chat with AI reports (flow 6)
- `openbat-experiments` — backtests + prompt publishing (7+8)
- `openbat-sdk-install` — install + verify SDK in a target project (flow 9)
- `openbat-optimize` — daily eval → fix loop: `openbat review` + apply fixes (flow 10)
- `openbat-safe-mutations` — confirmation patterns, audit log, key hygiene

## When to use this skill

- Any user request mentioning OpenBat, ob_live_*, ob_read_*, ob_admin_*, ob_pat_*
- Building a chatbot + observability pipeline end-to-end
- Pulling conversation analytics, sentiment, flags, or outcomes
- Creating workflows that fire Slack/Discord/custom webhooks
- Running prompt experiments and publishing prompt versions
- Adding @openbat/sdk to a Next.js / Node / AI SDK project

## The four key kinds

Stripe-style key kinds, each with a disjoint prefix. Pick the **smallest scope
that works**:

| Prefix | Kind | Scope | Use for |
|--------|------|-------|---------|
| `ob_live_*` | ingest | one chatbot, **write-only** | SDK capture (`OpenBat.recordMessages`) — never paste into CLI/MCP |
| `ob_read_*` | read | one chatbot, **read-only** | Per-chatbot read tools (CLI/MCP listing, analytics) |
| `ob_admin_*` | admin | one chatbot, **read+write** | Webhooks, workflows, reports, settings for one chatbot |
| `ob_pat_*` | PAT | one user across multiple chatbots and orgs | Creating chatbots, org-level operations, CI |

PATs also carry a sub-scope column (`read` or `admin`). A read-scope PAT
**cannot mutate** — the resolver gates writes on `permission === "write"`.

## Setup

```bash
npm install -g @openbat/cli
echo "ob_pat_…" | openbat config set-key --from-stdin   # recommended (stdin)
# or for one-off testing: openbat --api-key ob_pat_… <cmd>
openbat auth whoami                                     # confirm scope resolved
```

For MCP (Claude Desktop / Cursor / any MCP client):

```jsonc
{
  "mcpServers": {
    "openbat": {
      "command": "npx",
      "args": ["-y", "@openbat/mcp"],
      "env": { "OPENBAT_API_KEY": "ob_pat_…" }
    }
  }
}
```

The MCP server **filters its tool list by key kind**. With `ob_read_*` you see
only read tools; `ob_admin_*` lights up writes for one chatbot; `ob_pat_*`
adds `openbat_create_chatbot` and the org tools.

### Pin to one chatbot (hard lock)

Both the CLI and the MCP can lock to a single **active chatbot** so a key that
can reach many (a PAT) never wanders out of the one you're working on:

```bash
openbat use <id-or-name>     # persists ~/.openbatrc.activeChatbotId
openbat use                  # no arg → shows current pin + reachable options
```

For the MCP, set `OPENBAT_CHATBOT_ID` in the server env (or rely on the
`openbat use` value in `~/.openbatrc`). When pinned, the MCP **hard-locks**:
every per-chatbot tool defaults to the pin and rejects a different `chatbotId`,
`openbat_list_chatbots` returns only the pinned chatbot, and cross-chatbot/org
tools (`create_chatbot`, `list_orgs`, members) are hidden. To switch, run
`openbat use <other>` or restart the MCP with a different `OPENBAT_CHATBOT_ID`.

**Simplest single-chatbot setup:** use a chatbot-scoped `ob_read_*` / `ob_admin_*`
key — it's already one chatbot server-side, so the pin is automatic. The
`OPENBAT_CHATBOT_ID` pin is the safety net for PAT users. Every data command
prints a `→ chatbot: <name> (<id>)` banner to stderr so the scope is never in
doubt.

## The 11 flows (mapped to commands + tools)

### Flow 0 — Create a chatbot + onboard

```bash
openbat chatbots create \
  --name "Acme Support" \
  --website https://acme.com \
  --docs-url https://docs.acme.com
# stderr: "Ingest API key (ob_live_*) — shown ONCE — store this now: ob_live_…"
# stdout: { chatbot, dashboardUrl }
```

MCP: `openbat_create_chatbot { name, websiteUrl?, docsUrl?, mcpUrl?, primaryLanguage? }`.
Both require a PAT. Capture the ingest key immediately — it's the only
credential for the SDK in flow 9.

### Flow 1 — Settings: keys, webhooks, custom metadata

```bash
# Mint an admin key for CI:
openbat settings keys generate-admin --chatbot $CB --name "CI key" --expires-in-days 30

# Rotate the ingest key (immediately invalidates the old one):
openbat settings keys rotate-ingest --chatbot $CB

# Webhook CRUD:
openbat webhooks create --chatbot $CB --name slack-on-flag \
  --url https://hooks.slack.com/services/T.../B.../X --type slack
```

Each mint command prints plaintext to **stderr** with a shown-once banner.
Capture it before continuing.

### Flow 2 — Analysis definitions (user + assistant)

```bash
openbat analysis list --chatbot $CB --type intent
openbat analysis list --chatbot $CB --pending
openbat analysis add --chatbot $CB --type flag --name billing_issue \
  --display-name "Billing Issue" --description "Customer raises a billing concern"
```

Slugs must be lowercase snake_case (`[a-z0-9_]+`). Built-in types: `intent`,
`flag`, `assistant_outcome`, `assistant_issue`.

### Flow 3 — Conversations (time-filtered, default 7d)

```bash
openbat conversations list --days 7 --limit 50      # last week
openbat conversations show <conversationId>
```

MCP: `openbat_list_conversations { page, limit }`. For deeper time-window
queries, prefer the v1 routes directly.

### Flow 4 — Users / Orgs (external customer health)

```bash
openbat users list --chatbot $CB --days 30          # 30-day health window
openbat users list --chatbot $CB --search acme.com
```

Health metrics are computed by Postgres RPCs (`users_with_health`,
`orgs_with_health`) scoped to the date window.

### Flow 5 — Workflow (flag → webhook) via DSL

```bash
# 1. List webhooks to pick one
openbat webhooks list --chatbot $CB

# 2. Compile a built-in template into the workflow:
openbat workflows create --chatbot $CB \
  --name "billing → slack" \
  --template flag-to-webhook \
  --trigger-value billing_issue \
  --webhook $WEBHOOK_ID \
  --message "User flagged billing: {{user.id}} / {{conversation.id}}"
```

Templates: `flag-to-webhook`, `outcome-to-webhook`,
`sentiment-drop-to-webhook`. Power users can author raw xyflow nodes/edges
via `update_workflow`.

### Flow 6 — AI Reports

```bash
openbat reports create --chatbot $CB --name "Q3 retention"
# stderr: "Created report. View it (org members only): /platform/.../reports/..."
```

Reports are **org-private** — only members of the chatbot's org can open the
URL. No public sharing.

### Flow 7+8 — Experiments (backtests + prompt publishing)

Experiments / backtests are still primarily a dashboard wizard; the v1
surface exposes status checks today. Create + chat with reports for
qualitative comparison, then publish from the dashboard.

### Flow 9 — Add @openbat/sdk to a production app

```bash
openbat sdk install-instructions --framework next --chatbot $CB
# Prints copy-pasteable markdown — install, env var, recordMessages snippet.
openbat sdk verify --chatbot $CB --timeout 60
# Polls until the first event arrives; exits 2 on timeout.
```

The SDK uses the **ingest** key (`ob_live_*`), never the CLI/MCP credentials.

### Flow 10 — Daily eval → fix the chatbot

```bash
openbat use <chatbot>               # pin one chatbot (see "Pin to one chatbot")
openbat review --since 24h          # digest: flags, issues, outcomes + reasonings
openbat review --since 7d --json    # machine-readable for your own daily workflow
```

`openbat review` returns headline aggregates (with deltas vs the prior window)
plus clusters of the top issues / flags / intents and failed outcomes — each
issue cluster carrying representative conversation pointers with the analysis
`reasoning` + verification fields. Drill into a representative with
`openbat conversations show <id>` (now returns ALL analyses), then map the
symptom to a fix. The **`openbat-optimize`** skill orchestrates the full loop
(diagnose against the repo's system prompt / tools / retrieval → apply a PR).
MCP: `openbat_review { windowMinutes? }`. OpenBat ships no scheduler — wire
`openbat review` into your own cron / scheduled agent / CI for a daily cadence.

### Flow 11 — Publish the system prompt (live, remote)

For chatbots that **fetch their prompt from OpenBat at runtime** (`GET /api/v1/prompts`),
the active prompt can be managed remotely — no redeploy:

```bash
openbat prompts list                       # versions + which is active + kill-switch state
openbat prompts publish --file prompt.txt  # create a version from the file + set it LIVE
openbat prompts publish --text "You are…"  # inline (prefer --file for long prompts)
openbat prompts activate <versionId>       # roll back/forward to a known version
openbat prompts kill-switch --on           # emergency: SDK falls back to its hardcoded prompt
openbat prompts kill-switch --off          # resume serving the active published prompt
```

Writes need an **admin or PAT (write)** key. Changes go live within **~60s** (SDK
cache TTL). MCP: `openbat_list_prompt_versions`, `openbat_publish_prompt`,
`openbat_activate_prompt_version`, `openbat_set_prompt_kill_switch`.

**Caveat:** this only changes the running bot if your app fetches its prompt
from OpenBat. If you hardcode the prompt (and send `systemPromptTemplate` only
for versioning), publishing here records a version but does NOT change runtime —
deploy via your own repo instead (see `openbat-optimize`). This closes the
eval→fix loop for fetch-endpoint chatbots: `openbat review` → edit → `openbat
prompts publish` → live, with a kill switch to roll back.

## Safety rails (always apply these)

1. **Use the smallest scope that works.** Read-scope PAT for CI dashboards;
   admin key for one-chatbot ops; full PAT only for chatbot creation and
   org admin.
2. **Never paste plaintext keys into chat.** Use `echo "$KEY" | openbat config set-key --from-stdin`
   or set `OPENBAT_API_KEY` in `.env.local` (chmod 600).
3. **Capture plaintext once.** Every mint command prints to stderr with a
   "shown once" banner — pipe to a password manager immediately.
4. **Confirm before destructive ops.** `delete_chatbot`, `revoke_admin_key`,
   `delete_webhook` are irreversible. Prefer a dry inventory first
   (`openbat chatbots list`, `openbat settings keys list-admin`).
5. **Set `--expires-in-days` on admin keys** unless you have a strong reason.
   90 days max is a good default.
6. **Don't run the MCP with an ingest key** — the server refuses on startup.
   Ingest keys are SDK-only.

## Failure modes you'll see

| HTTP / Tool error                           | What it means                                  | Fix |
|---------------------------------------------|------------------------------------------------|-----|
| `401 Unauthorized`                          | Key invalid / wrong kind / revoked / expired   | `openbat auth whoami`; rotate key |
| `403 Forbidden`                             | Key valid but lacks permission (read PAT trying to mutate; member acting as owner) | Use a higher-scope credential |
| `404 Not Found` (chatbot id, conversation)  | Object exists in another org/chatbot — 404 not 403 by design (no enumeration) | Pass the right id |
| `429 Rate limited` + `Retry-After` header   | Per-PAT/admin/chatbot/IP bucket exceeded       | Wait and retry; see `lib/api/tool-rate-limit.ts` for limits |
| `Tool X requires a Y key or higher`         | MCP tool gating — your key kind is too low     | Set `OPENBAT_API_KEY` to a higher-scope key |

## Architecture (for debugging the surface)

```
Agent → CLI (HTTPS) ──┐
                      ├── v1 routes ── dispatchTool ── handler → Supabase
Agent → MCP (stdio) ──┘                    │
                                           ├── recordAudit() (api_audit_log)
                                           └── checkToolRateLimit() (per-tool bucket)
```

Every authenticated request appears as a row in `api_audit_log`
(success + failure both). To investigate "who did what when," query that
table in Supabase Studio. For a full inventory of tools, see
[lib/openbat-tools/registry.ts](../../lib/openbat-tools/registry.ts).
