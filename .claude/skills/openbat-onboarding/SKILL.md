---
name: openbat-onboarding
description: "Create a new OpenBat chatbot and complete onboarding from the CLI or MCP. Triggers when user wants to spin up a new chatbot, mint its first ingest key, or get the onboarding URL."
source: project
date_added: "2026-05-13"
---

# OpenBat — Create + onboard a chatbot

Requires a **PAT** (`ob_pat_*`) — no other credential can create chatbots
(ingest/read/admin keys are pinned to one existing chatbot).

## CLI

```bash
openbat chatbots create \
  --name "Acme Support" \
  --website https://acme.com \
  --docs-url https://docs.acme.com \
  --mcp-url https://acme.com/mcp        # optional, for advanced configs
```

Output:
- **stderr**: the new ingest key (`ob_live_*`) inside a "shown ONCE" banner.
  Capture it immediately — there is no recovery path.
- **stdout** (JSON-pipeable): `{ chatbot: { id, name, created_at, organization_id, api_key_prefix }, dashboardUrl }`.

The `dashboardUrl` points to `/platform/<id>/onboarding` for the optional
brand-voice / pricing / competitor wizard. The agent-driven flow doesn't
require completing the wizard — `settings.onboarded` defaults to false but
nothing else blocks on it.

## MCP

```json
{
  "tool": "openbat_create_chatbot",
  "arguments": {
    "name": "Acme Support",
    "websiteUrl": "https://acme.com",
    "docsUrl": "https://docs.acme.com",
    "primaryLanguage": "en"
  }
}
```

Return shape matches the CLI's stdout — `chatbot`, `ingestApiKey` (plaintext,
once), `dashboardUrl`.

## After creation

The chatbot exists with an ingest key. To open the read / write surface
you need additional keys:

```bash
# Generate a read key for CLI / MCP reads:
openbat settings keys generate-read --chatbot $CB

# Generate an admin key for write operations (one chatbot):
openbat settings keys generate-admin --chatbot $CB --name "CI key" --expires-in-days 90
```

Then drop the new ingest key into the target app's `.env.local` and follow
the `openbat-sdk-install` skill.

## Gotchas

- The org auto-selected for a new chatbot is the PAT user's primary
  org (oldest membership). To create a chatbot in a different org, the
  agent must first switch the PAT's user to that org via the dashboard;
  there's no CLI flag for cross-org creation yet.
- The 5-call/hour AI extraction rate limit (`extractProductIntelligence`)
  applies if you pass `--website` — chatbot creation itself is rate-limited
  at 5/hour per PAT.
