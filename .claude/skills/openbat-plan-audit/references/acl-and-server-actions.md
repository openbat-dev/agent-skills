# ACL / role checks + Server Action exposure — 9 findings

## TL;DR

Two related failure modes that often coexist:

1. **Membership ≠ role.** Destructive operations are gated only on org membership via `getActiveOrgContext()`, but the `role` field is never read. Any member can delete chatbots, rotate API keys, archive data, approve definitions, import data, etc.
2. **`"use server"` exports are public POST endpoints.** Internal helpers exported from a `"use server"` file become callable from any client component (and therefore by any logged-in user). Functions whose docstrings say "caller is responsible for auth" are routinely re-exposed to the world this way.

## The antipatterns

### A1 — destructive op gated only on membership

```ts
// lib/actions/chatbots.ts (the BUG shape, before fix)
"use server";
export async function deleteChatbot(chatbotId: string) {
  const { admin, orgId } = await validateChatbotOwnership(chatbotId);
  // ↑ ownership check — passes for ANY org member, including role: 'member'
  await admin.from("chatbots").delete().eq("id", chatbotId);
}
```

A regular org member can call this and delete every conversation/message/analysis the org has. The destructive consequence (cascade delete) is owner-only by policy but never enforced in code.

### A2 — internal helper exposed via `"use server"`

```ts
// lib/actions/backfill-embeddings.ts
"use server";   // ← every export becomes a public POST endpoint
export async function backfillEmbeddings(chatbotId: string) {
  // No auth at all. Loops 2000+ messages × Gemini embed.
  ...
}
```

Even if no client component imports it today, the `"use server"` directive registers the function as a callable Server Action — any logged-in user can hit it via the Server Action ID by inspecting the bundle.

### A3 — "internal" helper with comment "caller is responsible"

```ts
// lib/actions/generate-definitions.ts
"use server";
/** Internal: caller is responsible for auth. */
export async function generateIntentsAndFlagsInternal(...) {
  // Calls callLLM, mutates DB, no checks.
}
```

The comment doesn't bind the export. A future client-component import (or a direct call by Server Action ID) skips the auth.

## Why it fails in openbat specifically

- `getActiveOrgContext()` returns `{ user, org, role, memberId }` — the `role` field is *available* but routinely discarded.
- `lib/rbac.ts` exports `authorize(role, action)` and `can(role, action)`. Permission slugs are: `manage_chatbot_settings`, `manage_chatbot_members`, `delete_chatbot` (owner-only), `invite_member`, `remove_member` (owner-only), `update_member_role` (owner-only), `update_org_name` (owner-only), `delete_org` (owner-only).
- Many actions correctly use `validateChatbotOwnership` (the org check) but **skip** the role check. The two are different concerns.
- Client UI can hide the "Delete" button, but server actions don't see the UI — they see a POST.

## Canonical fix patterns

### Pattern A — destructive op, role check after ownership

```ts
// lib/actions/chatbots.ts (the FIX shape)
"use server";
import { authorize } from "@/lib/rbac";

export async function deleteChatbot(chatbotId: string) {
  const { role } = await getActiveOrgContext();
  authorize(role, "delete_chatbot");                       // ← throws if not owner
  const { admin } = await validateChatbotOwnership(chatbotId);
  await admin.from("chatbots").delete().eq("id", chatbotId);
}
```

Order matters: `authorize` first (cheapest reject) → then `validateChatbotOwnership` (DB round trip). Reverse order is ok if the ownership check is also instructive for logging.

### Pattern B — admin/owner ops

```ts
authorize(role, "manage_chatbot_settings");   // owner + admin
```

Operations that map to this slug today: settings updates, archiving, member management, API key rotation, custom-color edits, custom metadata field updates, member invites.

### Pattern C — owner-only ops

```ts
authorize(role, "delete_chatbot");   // owner only — no admin escalation
authorize(role, "remove_member");
authorize(role, "delete_org");
```

The slug map (`PERMISSIONS` in `lib/rbac.ts`) is the source of truth for which roles a slug allows.

### Pattern D — internal helper that should NOT be a Server Action

If a function is genuinely internal (only ever called from server-side code, never from a client component), put it in a non-`"use server"` module:

```ts
// lib/llm/intent-generation.ts   ← no "use server" directive
export async function generateIntentsAndFlagsInternal(...) {
  ...
}

// lib/actions/generate-definitions.ts
"use server";
import { generateIntentsAndFlagsInternal } from "@/lib/llm/intent-generation";

export async function generateIntents(chatbotId: string) {
  const { role } = await getActiveOrgContext();
  authorize(role, "manage_chatbot_settings");
  await validateChatbotOwnership(chatbotId);
  return generateIntentsAndFlagsInternal(chatbotId);
}
```

The `lib/llm/intent-generation.ts` module is now NOT a public POST surface. Only the wrapper in `lib/actions/` is, and the wrapper has full auth.

### Pattern E — gated dev-only helper

If the helper is a dev convenience that should never run in prod:

```ts
"use server";
export async function sendSeedBatch(...) {
  if (process.env.NODE_ENV !== "development") {
    throw new Error("Disabled in production");
  }
  ...
}
```

Combine with NODE_ENV-gated UI so the function is also hidden client-side.

## Real examples from the report (file:line)

### Missing role checks

- `app/api/v1/chatbots/[id]/rotate-key/route.ts:21-25` — any member can rotate the org's API key.
- `lib/actions/chatbots.ts:8,67,137,152,167` — `deleteChatbot`, `archiveChatbot`, `createChatbot`, settings update — all only check `getActiveOrgContext()` membership.
- `lib/actions/pending-definitions.ts:30,59,63` — `approvePendingDefinition`, `rejectPendingDefinition` skip role check.
- `lib/actions/import-full-export.ts:26` — calls `validateChatbotOwnership` but no `authorize(role, "manage_chatbot_settings")`.
- `app/api/platform/backfill-embeddings/route.ts:8-17` — any member can trigger the expensive backfill.

### Server Actions with no auth

- `lib/actions/backfill-embeddings.ts:1,12` — `backfillEmbeddings` exported, zero auth.
- `lib/actions/generate-definitions.ts:1,95,106` — `generateIntentsAndFlagsInternal` exported, "caller responsible" comment, no auth.
- `lib/actions/calibration-examples.ts:1,21` — `generateCalibrationExamplesInternal` exported, comment-only auth.
- `lib/actions/generate-seed-conversations.ts:5,6,24` — `sendSeedBatch` exported, zero auth, uses hardcoded `OPENBAT_API_KEY`.

## Plan-review questions

### Role checks (any "no" → BLOCK)

1. Does the plan add or modify a destructive operation (delete, archive, rotate, approve, reject, import, mass-update)?
   - If yes: does the action call `authorize(role, "<slug>")` from `@/lib/rbac` after `getActiveOrgContext()`?
2. Does the slug it uses map to the right role floor in `lib/rbac.ts`'s `PERMISSIONS` table?
   - Owner-only: deletion, member removal, role change, org rename/delete.
   - Admin+owner: settings, member invites, chatbot management.
3. Does the plan rely solely on conditional rendering of UI buttons for access control?
   - If yes: BLOCK — server actions don't see UI; the role check belongs in the action body.

### Server Action exposure

4. Does the plan add or modify a file with `"use server"` at the top?
   - If yes: does *every exported function* in that file have explicit auth (`getActiveOrgContext` + `authorize` + `validateChatbotOwnership` as appropriate)?
5. Does the plan add an "internal" helper exported from a `"use server"` file?
   - If yes: BLOCK — move the helper to a non-`"use server"` module, or add real auth.
6. Is the helper's comment "caller is responsible for auth"?
   - If yes: BLOCK — comments don't gate exports. Either add auth or relocate.
7. Is the helper a dev-only seed/backfill?
   - If yes: gate on `NODE_ENV !== "development"` AND add role check (so even in dev, only owners can run it).

## False positives (don't flag these)

- Read-only server actions that don't mutate state and don't fan out to expensive APIs — membership check is enough; role check is overkill.
- Internal modules with no `"use server"` directive — these are not Server Actions, just regular server modules; they only need auth if they're called from a public surface.
- API routes under `/api/cron/*` gated on `CRON_SECRET` — bearer token is the auth.
- API routes under `/api/auth/[...all]/*` — Better Auth handles its own auth model.

## Suggested-fix snippets for the audit findings table

> Missing role check: "After `getActiveOrgContext()`, add `authorize(role, '<permission_slug>')` from `@/lib/rbac`. The slug maps to roles per `lib/rbac.ts:PERMISSIONS`. Owner-only ops use `delete_chatbot`/`delete_org`/`remove_member`. Admin+owner ops use `manage_chatbot_settings`/`manage_chatbot_members`/`invite_member`."

> Internal helper in `"use server"` file: "Move `<functionName>` to a non-`use server` module (e.g., `lib/llm/<helper>.ts`) and add a thin wrapper in `lib/actions/` that performs `getActiveOrgContext` + `authorize` + `validateChatbotOwnership` before calling the internal helper."
