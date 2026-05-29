---
name: openbat-settings
description: "Manage OpenBat chatbot settings, API keys (ingest/read/admin), webhooks, and custom metadata fields from the CLI or MCP."
source: project
date_added: "2026-05-13"
---

# OpenBat — Settings + keys + webhooks

## Keys

```bash
# Rotate the ingest (SDK) key — immediately invalidates the previous one:
openbat settings keys rotate-ingest --chatbot $CB

# Generate or rotate the read key (one per chatbot):
openbat settings keys generate-read --chatbot $CB

# Mint a fresh admin key (N admin keys per chatbot allowed):
openbat settings keys generate-admin --chatbot $CB --name "CI key" --expires-in-days 30

# List admin keys for a chatbot:
openbat settings keys list-admin --chatbot $CB

# Revoke an admin key:
openbat settings keys revoke-admin --chatbot $CB --key $KEY_ID
```

All mint commands print plaintext to **stderr** with a shown-once banner.
Pipe to a password manager immediately.

**Permission matrix:**
- Mint admin: PAT required
- Generate read / rotate ingest: admin or PAT
- List admin keys: admin or PAT
- Revoke admin: PAT required

## Scoping a key to one chatbot

`ob_read_*` and `ob_admin_*` keys are **scoped to one chatbot server-side** —
the simplest, safest credential for working on a single chatbot (and for the
daily-eval / `openbat-optimize` loop). With one of these, the CLI/MCP can only
ever see that chatbot; nothing to pin.

A `ob_pat_*` spans many chatbots. To keep it locked to one, pin an active
chatbot — `openbat use <id>` (CLI) or `OPENBAT_CHATBOT_ID` (MCP env). The MCP
then hard-locks to that chatbot (see `using-openbat` → "Pin to one chatbot").

## Webhooks

```bash
openbat webhooks list --chatbot $CB
openbat webhooks create --chatbot $CB --name slack-on-flag \
  --url https://hooks.slack.com/services/T.../B.../X --type slack
openbat webhooks delete --chatbot $CB --webhook $WH
```

Types: `discord`, `slack`, `custom`. Each is host-allowlisted at write time
(SSRF defence). The signing secret returned at create time is shown ONCE.

## Chatbot settings

```bash
openbat settings update --chatbot $CB \
  --description "Help desk for Acme support" \
  --website-url https://acme.com \
  --language en
```

The allowlist of settable keys is enforced server-side
(`settingsUpdateSchema` in `lib/actions/chatbots.ts`). Unknown keys are
rejected to prevent property-level authorization issues.

## Custom metadata fields

Metadata fields are auto-discovered from SDK capture payloads. They start
as `pending` and can be accepted or denied:

```bash
# CLI command not yet exposed — use the dashboard or MCP for now.
```

MCP tools `openbat_list_metadata_fields` and `openbat_update_metadata_field`
support both flows.

## Gotchas

- The read key has at most ONE active version per chatbot — generating
  a new read key implicitly rotates.
- Admin keys support multiple-active for safe rotation; revoke explicitly.
- Webhook signing secrets are not re-revealable. If you lose one, delete
  and recreate the webhook.
- `delete_webhook` is irreversible — workflow nodes that reference the
  webhook will be invalidated at runtime.
