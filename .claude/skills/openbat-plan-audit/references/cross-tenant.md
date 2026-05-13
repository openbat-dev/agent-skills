# Cross-tenant access (IDOR) — 31 findings, the dominant pattern

## TL;DR

Anywhere a `chatbotId`, `reportId`, `conversationId`, `workflowId`, etc. comes from a URL or client-supplied input and is used to read or write data, **the plan must ensure that resource belongs to the authenticated user's active organization**. RLS is OFF in this codebase — `lib/supabase/server.ts` returns `createAdminClient()` for all server-component reads. The application layer is the only defense, and the report shows it was forgotten in 31 places.

## The antipattern (one shape, many copies)

```ts
// app/platform/[chatbotId]/<anything>/page.tsx
const { chatbotId } = await params;
const chatbot = await getChatbot(chatbotId);
if (!chatbot) redirect("/platform");           // ← existence check, not ownership
const data = await getThing(chatbotId);        // ← attacker now reads other org's data
```

`getChatbot(id)` filters only by `.eq('id', id)`. `SELECT_CHATBOT_BASIC` does not include `organization_id`, so even if a downstream page wanted to compare, it can't. The parent layout `app/platform/[chatbotId]/layout.tsx` repeats the same shape, so every nested route inherits the bug.

## Why it fails in openbat specifically

- `lib/supabase/server.ts` returns `createAdminClient()` (RLS bypassed). Any DB query that runs without an explicit `.eq('organization_id', orgId)` will return ANY org's rows.
- `getChatbot(chatbotId)` (`lib/queries/chatbots.ts`) does NOT filter by org and does NOT return `organization_id`.
- Layouts run before pages but do not enforce ownership today.
- `validateChatbotOwnership()` exists in `lib/actions/_shared.ts` but is **only invoked from server actions**, never on the read path.
- Chatbot UUIDs leak via SDK referrers, exports, support tickets, server logs, screenshots — they are not auth tokens.

## Canonical fix patterns

### Pattern A — fix at the layout (preferred for new pages under `/platform/[chatbotId]/*`)

```ts
// app/platform/[chatbotId]/layout.tsx
const org = await getOrganizationForUser();
if (!org) redirect("/platform");

const admin = createAdminClient();
const { data: chatbot } = await admin
  .from("chatbots")
  .select("id, name, api_key_prefix, settings, created_at, organization_id")
  .eq("id", chatbotId)
  .eq("organization_id", org.id)   // ← THE missing filter
  .single();

if (!chatbot) notFound();           // ← notFound, NOT redirect — don't leak existence
```

`notFound()` is preferred over `redirect("/platform")` because a redirect signals "this id exists but you can't access it", giving the attacker an oracle.

### Pattern B — push the org filter into the query

```ts
// lib/queries/chatbots.ts
export async function getChatbot(id: string, orgId: string) {
  const admin = createAdminClient();
  const { data } = await admin
    .from("chatbots")
    .select(SELECT_CHATBOT_BASIC)
    .eq("id", id)
    .eq("organization_id", orgId)
    .single();
  return data;
}
```

Then every caller is forced to pass `org.id` — the type system makes the omission a compile error. Same idea for `getConversations({ chatbotId, orgId })`, analytics queries, etc. Where the table doesn't have `organization_id` directly (e.g., `messages`, `analyses`), join through `chatbots`:

```ts
// pseudo-code for a join-through-chatbots check
.eq("chatbot_id", chatbotId)
.eq("chatbots.organization_id", orgId)   // assumes the join is set up
```

### Pattern C — server-action calls (already correct in the codebase)

```ts
const { chatbot } = await validateChatbotOwnership(chatbotId);  // throws if not owned
```

Reuse this for every server action. Don't reimplement the check.

## Real examples from the report (file:line)

- `app/platform/[chatbotId]/layout.tsx:28-34` — root cause; layout never checks ownership, every nested route inherits.
- `app/platform/[chatbotId]/conversations/page.tsx:44,66` — passes `chatbotId` straight into `ConversationsData`.
- `app/platform/[chatbotId]/conversations/[id]/page.tsx:75-86` — only checks URL-internal consistency (`conversation.chatbot_id === chatbotId`).
- `app/platform/[chatbotId]/deep-search/page.tsx:82,118` — semantic search across any chatbot's messages.
- `app/platform/[chatbotId]/analysis-config/page.tsx:29-93` — reads analysis defs, calibration examples, metadata fields without org check.
- `app/platform/[chatbotId]/experiments/page.tsx:19-45` — experiments + tag aggregates leak.
- `app/platform/[chatbotId]/settings/page.tsx` — settings page exposes API key prefix, settings JSON.
- `lib/queries/conversations.ts:61,108,112,242,397,417,434` — every read path is `.eq('chatbot_id', chatbotId)` only.
- `lib/queries/analytics.ts` — 19 functions accept `chatbotId` with no org filter.
- `lib/queries/external-organizations.ts:42+`, `lib/queries/external-users.ts:18+`, `lib/queries/prompts.ts:74+`, `lib/queries/analysis-definitions.ts:44+`, `lib/queries/onboarding.ts:25+`, `lib/queries/templates.ts:20+` — same shape.
- `lib/queries/conversations.ts:getConversation(id)` — loads any conversation by id, no chatbot filter at all (worse than the others).

## Plan-review questions (yes/no — any "no" → BLOCK)

1. Does the plan add or modify a page/layout/route under `/platform/[chatbotId]/*`?
   - If yes: is there an explicit `chatbot.organization_id === user.org.id` check before any data fetch?
2. Does the plan add a function in `lib/queries/*` that takes `chatbotId`?
   - If yes: does the signature also require `orgId`, or does the function join through `chatbots` filtered by org?
3. Does the plan add a function in `lib/actions/*` that takes `chatbotId`?
   - If yes: is the first line `await validateChatbotOwnership(chatbotId)`?
4. Does the plan add a function that takes `conversationId`, `reportId`, `workflowId`, `experimentId`, etc.?
   - If yes: same question — is ownership of the parent chatbot validated against the user's org?
5. Does the plan return errors as `redirect("/platform")` rather than `notFound()`?
   - If yes: FLAG — the redirect leaks existence. `notFound()` is the canonical response for "you can't see this".

## False positives (don't flag these)

- The action already calls `validateChatbotOwnership()` — that single call is the org check; downstream code in that action is fine.
- The route is a SDK ingestion endpoint (`/api/v1/capture`) authenticated by `validateApiKey()` — the API key embeds the chatbot identity, so org check is implicit.
- The query is intentionally cross-org (e.g., system-default templates that should be visible to everyone) — verify with the user that cross-org exposure is intentional. Public templates must be guarded by an explicit `is_system_default = true` filter, not "any chatbot id works".
- The page is in the `(marketing)` route group — public by design.

## Suggested-fix snippet for the audit findings table

> "Add an org-ownership check at the layout level (`app/platform/[chatbotId]/layout.tsx`) using `.eq('organization_id', org.id)` on the `getChatbot` query, OR call `validateChatbotOwnership(chatbotId)` from `lib/actions/_shared.ts` from the page. Return `notFound()` (not redirect) on mismatch. Audit every nested page under `/platform/[chatbotId]/*` for the same pattern — this is a systemic shape, not a one-off."
