---
name: openbat-skills-store
description: "Use when creating, versioning, reading, or updating an OpenBat chatbot's managed skills (reusable instruction/policy blocks the SDK fetches at runtime via skills.get) — over the MCP openbat_*_skill tools, the /chatbots/:id/skills REST routes, or the SDK."
source: project
date_added: "2026-06-14"
---

# OpenBat — Managed skills store

## Overview

A **managed skill** is a named, reusable instruction/policy block stored on a
chatbot (e.g. `refunds`, `tone`, `escalation-policy`). Your app fetches the
active body at runtime and injects it into the model context, so you can edit
behaviour without redeploying. Skills are **chatbot-scoped** (like prompts) and
**immutably versioned**: every write creates a new version; the highest version
is the active one ("restore = republish as new"). Bundled files travel with a
version.

This is distinct from the agent-skills you're reading now (those teach an agent
to drive OpenBat). Managed skills live in the product and serve the chatbot.

## Tools (MCP — chatbot-scoped)

| Tool | Args | Kind | Does |
|---|---|---|---|
| `openbat_list_skills` | `{chatbotId}` | read | Latest version per skill name (`{name, version, updatedAt}`) |
| `openbat_get_skill` | `{chatbotId, name, version?}` | read | Full body of the latest (or pinned `version`): `{id, name, version, body, files, createdAt}` |
| `openbat_create_skill` | `{chatbotId, name, body}` | admin | Create version 1. Fails (409) if `name` exists — use update instead. `name` ∈ `^[A-Za-z0-9_-]{1,64}$` |
| `openbat_update_skill` | `{chatbotId, name, base_version, body}` | admin | Publish a new immutable version |

Equivalent REST: `GET|POST /api/v1/chatbots/:id/skills`, `GET|PATCH /api/v1/chatbots/:id/skills/:name`.

## Optimistic concurrency — ALWAYS read before you write

Updates require `base_version` so concurrent edits never clobber each other:

1. `openbat_get_skill { chatbotId, name }` → note the returned `version`.
2. `openbat_update_skill { chatbotId, name, base_version: <that version>, body: <new> }`.
3. A **stale `base_version` → 409 CONFLICT** (someone else published first).
   Re-fetch with `openbat_get_skill` and re-apply your change on top.

Never guess `base_version`. Never reuse a version number across edits.

## Reading a skill at runtime (the SDK)

The chatbot app reads the active body — it does NOT need an admin key, just the
ingest key (`ob_live_*`):

```ts
const skill = await client.skills.get("refunds", {
  fallback: "Be concise and cite the refund policy.", // used if OpenBat is unreachable
  // version: 3,  // optional: pin an immutable version for a probe/eval
});
// skill.body is ready to inject; skill.source is "remote" | "fallback"
```

`skills.get` never throws — on any failure it returns your `fallback` so the
chatbot keeps running. Pin `version` to evaluate a candidate before promoting it.

## Common mistakes

- **Updating without `get` first** → you'll send a stale `base_version` and get a
  409. Read → note version → update.
- **`create` on an existing name** → 409. Use `openbat_update_skill`.
- **Using an `ob_live_*` ingest key for the MCP authoring tools** — those need a
  read/admin key; the ingest key is only for the SDK `skills.get` runtime read.
- **Treating a skill like the system prompt** — managed skills are reusable
  blocks *alongside* the base prompt (see `openbat-optimize` for the prompt loop).

## Safety

`create_skill`/`update_skill` are writes (admin). Follow `openbat-safe-mutations`:
list/get the current state first, and use `--dry-run` (CLI) / inspect args before
publishing a version that the live chatbot will start serving.
