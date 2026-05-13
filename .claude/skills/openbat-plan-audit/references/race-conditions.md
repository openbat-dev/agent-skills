# Race conditions / TOCTOU — 8 findings

## TL;DR

Read-modify-write on shared state without atomicity is the recurring shape: SELECT a counter or JSON column, mutate it in JavaScript, write it back. Two concurrent requests both read the old value, both compute "old + N", both write the same new value — one update is lost. Same problem for JSON merges and idempotency markers.

The fix is always to do the mutation in a single SQL statement, or use SECURITY DEFINER RPC, or use optimistic concurrency on `updated_at`.

## The antipatterns

### A1 — counter increment via read-modify-write

```ts
// app/api/v1/capture/route.ts:487-500 (the BUG shape)
const { data: cb } = await admin
  .from("chatbots")
  .select("message_count")
  .eq("id", chatbotId)
  .single();

await admin
  .from("chatbots")
  .update({ message_count: (cb.message_count ?? 0) + insertedMessages.length })
  .eq("id", chatbotId);
```

Two concurrent capture requests with `insertedMessages.length = 5` each: both read `100`, both write `105`. Real total should be `110`. The SDK regularly batches captures, so this is hit constantly.

### A2 — JSON merge via spread + write back

```ts
const { data: row } = await admin.from("widgets").select("data").eq("id", reportId).single();
const newData = { ...row.data, ...patch };  // ← in-JS merge
await admin.from("widgets").update({ data: newData }).eq("id", reportId);
```

Same problem: concurrent edits clobber each other's keys.

### A3 — TOCTOU on idempotency marker

```ts
// app/api/v1/capture/route.ts:521-538 (the BUG shape)
const { data: cb } = await admin.from("chatbots").select("intentsGeneratedAt").eq("id", chatbotId).single();
if (!cb.intentsGeneratedAt && messageCount >= 100) {
  await generateIntents(chatbotId);                                 // ← expensive LLM call
  await admin.from("chatbots").update({ intentsGeneratedAt: now }).eq("id", chatbotId);
}
```

Two concurrent requests both pass the check, both fire the LLM call, both write the marker. The expensive operation runs twice (extra cost, possibly conflicting writes downstream).

### A4 — parallel workflow steps reading shared counter

```ts
// lib/workflows/v3/generate-calibration-examples.ts:78-100
const { data: state } = await admin.from("calibration_state").select("step").eq("id", id).single();
const next = state.step + 1;
await admin.from("calibration_state").update({ step: next }).eq("id", id);
```

Workflows fan out: 6 parallel branches, each running this loop. Most steps get clobbered.

### A5 — race in dedup-then-insert

```ts
const { data: existing } = await admin.from("conversations").select("id").eq("external_id", extId);
if (!existing.length) {
  await admin.from("conversations").insert({ external_id: extId, ... });  // ← duplicate row possible
}
```

Two concurrent imports both see "no existing row" and both insert. Need a `UNIQUE` constraint + `upsert` instead.

## Why it fails in openbat specifically

- Capture pipeline (`/api/v1/capture`) is high-fanout: SDK clients batch and ship concurrently.
- Workflow DevKit fans out (`Promise.all` on parallel steps); each step runs the same JS code; shared counters are common.
- Several JSON columns (`chatbots.settings`, `widgets.data`, workflow state) are routinely merged in JS instead of with `||`.
- Idempotency markers are checked-then-written across multiple statements without a transaction.

## Canonical fix patterns

### Pattern A — atomic counter via SQL

For Postgres via Supabase, use a SECURITY DEFINER RPC:

```sql
-- supabase/migrations/00X_increment_message_count.sql
create or replace function increment_message_count(p_chatbot_id uuid, p_n int)
returns int
language sql
security definer
set search_path = public
as $$
  update chatbots
     set message_count = coalesce(message_count, 0) + p_n
   where id = p_chatbot_id
  returning message_count;
$$;
```

```ts
// app/api/v1/capture/route.ts (the FIX shape)
const { data: newCount } = await admin.rpc("increment_message_count", {
  p_chatbot_id: chatbotId,
  p_n: insertedMessages.length,
});
```

The increment runs as a single SQL operation under a row-level lock — no read-modify-write race.

### Pattern B — JSONB merge with `||`

```sql
-- atomic JSONB merge
update widgets
   set data = data || $1::jsonb,
       updated_at = now()
 where id = $2;
```

```ts
const { error } = await admin.rpc("merge_widget_data", { p_id: id, p_patch: patch });
```

The `||` operator is shallow — for deep merge, write a recursive PL/pgSQL function or restrict the patch shape so shallow merge is sufficient.

### Pattern C — atomic idempotency flip

Move the marker flip to the start, not the end:

```sql
create or replace function try_claim_intent_generation(p_chatbot_id uuid, p_threshold int)
returns boolean
language plpgsql
security definer
as $$
declare
  claimed boolean;
begin
  update chatbots
     set intents_generated_at = now()
   where id = p_chatbot_id
     and intents_generated_at is null
     and message_count >= p_threshold
  returning true into claimed;
  return coalesce(claimed, false);
end;
$$;
```

```ts
const { data: shouldGenerate } = await admin.rpc("try_claim_intent_generation", {
  p_chatbot_id: chatbotId,
  p_threshold: 100,
});
if (shouldGenerate) {
  await generateIntents(chatbotId);  // ← runs at most once
}
```

The flip happens atomically; only the request that wins the race sees `true`.

### Pattern D — optimistic concurrency on `updated_at`

For more general read-modify-write where atomic SQL is awkward:

```ts
const { data: row } = await admin.from("widgets").select("data, updated_at").eq("id", id).single();
const newData = mergeInJs(row.data, patch);

const { data: updated, error } = await admin
  .from("widgets")
  .update({ data: newData, updated_at: new Date().toISOString() })
  .eq("id", id)
  .eq("updated_at", row.updated_at)            // ← optimistic check
  .select();

if (!updated?.length) {
  // Lost the race — retry once with fresh data, or surface a conflict to the user
}
```

### Pattern E — UNIQUE + upsert for dedup-then-insert

```sql
alter table conversations
  add constraint conversations_external_id_chatbot_id_key unique (external_id, chatbot_id);
```

```ts
await admin
  .from("conversations")
  .upsert({ external_id: extId, chatbot_id: chatbotId, ... },
          { onConflict: "external_id,chatbot_id", ignoreDuplicates: true });
```

The DB enforces uniqueness; concurrent inserts can't both succeed.

## Real examples from the report (file:line)

- `app/api/v1/capture/route.ts:487-500` — `message_count` read-modify-write.
- `app/api/v1/capture/route.ts:521-538` — TOCTOU on `intentsGeneratedAt` marker.
- `lib/actions/import-full-export.ts:230-244` — `message_count` read-modify-write during bulk import.
- `lib/actions/import-conversations.ts:104+` — dedup-then-insert + counter increment, both racy.
- `lib/workflows/v3/generate-calibration-examples.ts:78-100` — parallel workflow reading shared step counter.
- `lib/ai-reports/widgets/actions.ts:15-45` — load widgets array, mutate, write back; affects `addWidget`, `deleteWidget`, etc.
- `lib/utils/definition-promotion.ts:19-47` — read max sort_order + colors, compute next, write — concurrent promotions collide.

## Plan-review questions (any "no" → BLOCK or FLAG depending on concurrency)

1. Does the plan increment a counter or compute "old value + delta" then write back?
   - If yes: BLOCK unless the operation is wrapped in a SECURITY DEFINER RPC or a single SQL `UPDATE counter = counter + N`.
2. Does the plan merge a partial patch into a JSON column?
   - If yes: BLOCK unless using `||` in SQL or a recursive merge RPC.
3. Does the plan check a flag/marker, do an expensive op, then set the flag?
   - If yes: BLOCK — flip the flag atomically first (claim semantics), then run the expensive op only if the flip succeeded.
4. Does the plan dedup-by-select-then-insert?
   - If yes: FLAG — add a UNIQUE constraint and use upsert.
5. Does the plan run the same mutation across multiple parallel workflow steps or `Promise.all` branches?
   - If yes: enumerate the shared state — every counter, every accumulator, every marker — and verify each is updated atomically.
6. Does the plan claim "writes are rare so we don't need locks"?
   - If yes: FLAG. The capture pipeline runs at SDK speed; "rare" usually isn't.

## False positives (don't flag these)

- Single-row `INSERT` with no read step — no race possible.
- Single-row `UPDATE x SET col = $1 WHERE id = $2` (full replacement, not relative) — write order is the only race, and the last write wins, which is usually fine.
- Operations on rows owned by a single user where concurrent writes are physically impossible (e.g., a personal note edited only via the user's own UI).
- Workflow steps that already use Workflow DevKit's idempotent retry semantics (declared in the workflow harness) — but the harness only protects the step boundary, not arbitrary downstream JS reads/writes.

## Suggested-fix snippet for the audit findings table

> "Replace the read-modify-write block (`select <col>; update <col> = <jsValue>`) with an atomic SQL operation: either an `UPDATE x SET <col> = <col> + $1 WHERE id = $2` statement, or a SECURITY DEFINER RPC that wraps the whole sequence in one statement. For JSON merges, use `data = data || $1::jsonb`. For idempotency markers, flip the marker first and only proceed if the flip succeeded."
