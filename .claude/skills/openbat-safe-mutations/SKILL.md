---
name: openbat-safe-mutations
description: "Cross-cutting safety rules for any OpenBat mutation — confirmation patterns, audit log review, key rotation hygiene, scoping discipline."
source: project
date_added: "2026-05-13"
---

# OpenBat — Safe mutations

This is the cross-cutting reference for **anything that writes**. Read it
before invoking `delete_*`, `revoke_*`, or `rotate_*` tools.

## Confirmation discipline

Destructive operations don't get an automatic "undo". The recovery path
is usually a fresh mint (key) or recreation (webhook / workflow). Before
firing one:

1. **List first.** Get the current state so you can confirm what you're
   about to remove is the right thing.
   ```bash
   openbat settings keys list-admin --chatbot $CB
   openbat webhooks list --chatbot $CB
   openbat workflows list --chatbot $CB
   ```
2. **Type the id explicitly.** Don't construct it from a search; pass
   the exact uuid you got from step 1.
3. **For chatbot deletion, type the chatbot name as `--confirm`.** The
   tool requires the literal name match to fire.

## Key hygiene

| Action | Frequency | How to recover |
|--------|-----------|----------------|
| Rotate ingest key | When you suspect leak | Old key dies immediately; deploy new one to SDK env |
| Generate new read key | When you need it; old read auto-revokes | New plaintext, one slot per chatbot |
| Mint admin key | One per environment (CI, dev, prod) | Mint a new one; old keeps working until revoked |
| Revoke admin key | Immediately on suspected leak / on departure | None — must mint fresh |
| Rotate PAT | Every 90 days by default | Mint via dashboard; old expires per `expires_at` |

**Set `expires_at` on every admin key.** The CLI accepts
`--expires-in-days N` — use it. 30-90 days is reasonable for CI.

## Audit log

Every authenticated request lands in `api_audit_log`:

```sql
select occurred_at, actor_kind, tool_name, outcome, ip
from api_audit_log
where user_id = 'user_xxx'
  and occurred_at > now() - interval '7 days'
order by occurred_at desc
limit 50;
```

`actor_kind` covers `pat`, `admin`, `read`, `ingest`, `session`,
`internal`. `actor_id` is the credential's table id (PAT id, admin key
id, user id for sessions) — never plaintext, never hash.

`outcome` enum: `ok` | `forbidden` | `rate_limited` | `error` | `invalid`.
Filter by `outcome != 'ok'` to surface every rejection.

## Scoping discipline

- **Read PAT for CI dashboards.** No write authority, blast radius zero.
- **Admin key per environment.** Pin to one chatbot, named with the env
  (`"CI key"`, `"prod key"`).
- **Full PAT only for chatbot creation + org admin.** Treat like an SSH
  key — single user, no sharing.
- **Never use ingest keys in CLI or MCP.** Those are SDK-only.

## Common failure modes (and recovery)

- **Lost webhook signing secret**: delete the webhook + recreate. No
  rotation endpoint exists yet.
- **Accidentally rotated ingest key**: the SDK starts failing 401s
  immediately. Roll forward — deploy the new key to your SDK env.
- **Read-scope PAT trying to mutate**: 403 with "permission read".
  Mint a new admin-scope PAT.
- **`delete_org` cascades everything**: the org and all chatbots /
  conversations / messages / analyses go. There is no soft-delete.
  Confirm the org name twice.

## Always-true invariants

- `chatbot_id` filtering is enforced server-side in every handler. A
  leaked admin key for chatbot A cannot touch chatbot B.
- Plaintext credentials are never logged, never stored, never echoed.
- Every list-returning tool caps at 200 rows. Pagination is mandatory.
- Rate-limit responses include `Retry-After`. Respect it.
