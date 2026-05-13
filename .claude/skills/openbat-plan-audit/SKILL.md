---
name: openbat-plan-audit
description: Audit an openbat implementation plan against the recurring failure patterns surfaced by the deepsec security scan (118 findings, dominated by cross-tenant IDOR, missing rate limits, missing role checks, SSRF, race conditions, and input-validation gaps). Use this skill BEFORE executing any /gsd-plan-phase, /gsd-execute-phase, or hand-written plan that touches /platform/[chatbotId]/* routes, lib/queries/*, lib/actions/*, app/api/*, server actions, LLM calls, webhooks, or anything reading/writing chatbot-scoped data. Pass the plan path as an argument. Always invoke this whenever the user mentions "audit the plan", "review my plan", "check this plan", "is this plan safe", "before I implement", or whenever a non-trivial plan is about to be executed.
metadata:
  tags: security, audit, plan-review, openbat, multi-tenant, rate-limiting, idor
---

# openbat-plan-audit

Audit an openbat implementation plan against the recurring failure patterns the deepsec scanner surfaced (118 findings, see `.deepsec/data/openbat/reports/report.md`). The same antipatterns landed on the same surfaces over and over because plans got executed without a pre-flight check against this codebase's actual conventions. This skill is that pre-flight.

## When to invoke

- The user passes a plan path or says "audit this plan", "review my plan", "is this safe to ship", "check this before I implement".
- About to start `/gsd-execute-phase` or hand-implement a plan that touches any of:
  - Pages or layouts under `app/platform/[chatbotId]/*`
  - Anything in `lib/queries/*`, `lib/actions/*`, `app/api/*`
  - Files with the `"use server"` directive
  - LLM invocations (`callLLM`, `streamText`, `embed*`, agents with `thinking: true`)
  - Webhooks, MCP URLs, or any user-supplied URL stored or fetched
  - Counters, JSON merges, or workflow state writes
  - `chatbot.settings`, system prompts, or admin client (`lib/supabase/admin.ts`) usage

If unsure whether the plan touches a sensitive surface, run the audit anyway — false positives are cheap, missed findings are not.

## Inputs

- **Required:** path to the plan file (e.g. `~/.claude/plans/<name>.md`, `.planning/<phase>/PLAN.md`, or any markdown plan).
- If the user did not provide a path, ask once: "Which plan file should I audit?"
- If the user wants to audit plan content already in the conversation (no file), proceed using that content as the plan body.

## Workflow (follow in order)

1. **Read the plan in full.** Don't skim — every BLOCK-level finding in the deepsec report came from one missed line.
2. **Tag the surfaces the plan touches.** Build a quick mental list: route handler? server action? page/layout? query? workflow? SDK? LLM call? URL fetch? counter increment? settings JSON write? auth/role boundary?
3. **Load only the matching reference files** (progressive disclosure — don't load all of them):

   | Plan touches… | Read reference file |
   |---|---|
   | `app/platform/[chatbotId]/*`, `lib/queries/*`, any read of chatbot-scoped data | `references/cross-tenant.md` |
   | `callLLM`, `streamText`, `embed*`, agent invocation, expensive aggregation queries | `references/expensive-api-and-rate-limit.md` |
   | Files with `"use server"`, destructive ops (`delete*`/`archive*`/`rotate*`/`approve*`/`import*`), settings writes, role-gated UI | `references/acl-and-server-actions.md` |
   | Stores or fetches a user-supplied URL (mcpUrl, webhook.url, website_url, redirect target) | `references/ssrf.md` |
   | Counters (e.g., `message_count`), JSON merges, parallel workflows, idempotency markers | `references/race-conditions.md` |
   | New API endpoint, server action, schema validation, search filters, prompt construction, HTML/email rendering | `references/input-validation-and-injection.md` |
   | API keys, env vars, error responses to clients, hardcoded secrets, webhook URLs | `references/secrets-and-error-leaks.md` |
   | Caches keyed by user input, GET-side state changes, `dangerouslySetInnerHTML`, forwarded headers, `fetch` redirects | `references/one-shot-criticals.md` |

4. **Run the top-5 inline checklist** below regardless of which references you load — these dominate the report and are cheap to check.
5. **Record one row per check.** Verdict: `BLOCK` (must fix), `FLAG` (should fix; raise to user), `PASS`. Cite the plan section/line, name the missing helper, propose the canonical openbat fix.
6. **Output the report** in the structured template below. Ask the user: "Append findings to the plan file under `## Audit findings (openbat-plan-audit)`, or print here only?"

## Top-5 inline checklist (run for every plan)

These cover ~70% of historical findings. If the plan can't satisfy each one, it gets a `BLOCK` or `FLAG`.

1. **Cross-tenant ownership.** Does every URL-supplied `chatbotId` / `reportId` / `conversationId` get bound to `user.org.id` before any data access?
   - **Canonical helper:** `validateChatbotOwnership(chatbotId)` from `lib/actions/_shared.ts` — for read paths, replicate at the layout level (`app/platform/[chatbotId]/layout.tsx`) so all children inherit. RLS is OFF (admin client everywhere); the app layer is the only defense.
2. **LLM rate limits.** Does every `callLLM` / `streamText` / `embed*` / agent invocation have `checkRateLimit(...)` from `lib/api/rate-limit.ts` immediately before it, with a per-user-or-per-chatbot key?
   - **Canonical example:** `app/api/v1/system-prompts/suggest/route.ts:78` — `checkRateLimit(\`suggest:${session.user.id}:${body.chatbotId}\`, { limit, windowMs })`. Combine with `.max()` on prompt fields.
3. **Role checks.** Does every destructive op (`delete*`, `archive*`, `rotate*`, `approve*`, `import*`, settings write) call `authorize(role, "<permission>")` from `@/lib/rbac` after `getActiveOrgContext()`?
   - **Permission slugs:** `manage_chatbot_settings`, `manage_chatbot_members`, `delete_chatbot` (owner-only), `invite_member`, `remove_member`, `update_member_role`, `update_org_name`, `delete_org`. Any new op needs to map to one of these.
4. **Atomic writes.** Does every counter / array / JSON update use a single SQL operation (`UPDATE ... SET counter = counter + $1` or `data || $1::jsonb`) instead of `select → mutate-in-JS → write`?
   - **Why:** the capture pipeline, import flows, and parallel workflows all lose updates today because of read-modify-write.
5. **Input validation.** Does every API/server-action input flow through a Zod `.strict()` schema with `.max()` length caps, before reaching the DB or an LLM?
   - **Mass-assignment:** `Record<string, unknown>` parameters or unchecked `nodes`/`edges`/`updates` JSON columns are red flags.

## Output template

Append (or print) a single section using this exact format. Keep findings scannable — the goal is for the user to walk down the table and decide go/no-go.

```markdown
## Audit findings (openbat-plan-audit)

| # | Severity | Category | Plan section | Issue | Required helper / pattern |
|---|---|---|---|---|---|
| 1 | BLOCK | cross-tenant-id | "Add /platform/[chatbotId]/foo" | Plan calls `getChatbot(chatbotId)` but never asserts `chatbot.organization_id === org.id` | Use `validateChatbotOwnership(chatbotId)` from `lib/actions/_shared.ts`; OR add `.eq('organization_id', orgId)` to the query and compare in the layout |
| 2 | FLAG | rate-limit-bypass | "POST /api/v1/foo" | New endpoint calls `callLLM` with no `checkRateLimit` before it | Add `checkRateLimit(\`foo:${userId}:${chatbotId}\`, { limit: 30, windowMs: 60_000 })` per pattern at `app/api/v1/system-prompts/suggest/route.ts:78` |
| ... |

### Summary
- BLOCK: N (must fix before execution)
- FLAG:  N (should fix; raise to user)
- PASS:  N (checked, no concerns)

### Surfaces touched
- [list of surfaces, e.g. "page under /platform/[chatbotId]/*", "server action with LLM call"]

### Reference files consulted
- [list of references/*.md files read during this audit]
```

## Severity guide

- **BLOCK** — Direct match to a CRITICAL/HIGH pattern from the report (cross-tenant read without org check, LLM call with no rate limit, destructive op with no role check, user URL fetched without SSRF guard, secret in URL/source). Don't execute the plan until fixed.
- **FLAG** — Pattern is risky but not certain to be exploitable, OR mitigations exist elsewhere (e.g., proxy gates the route). Raise to the user; let them decide.
- **PASS** — Plan explicitly handles the concern, OR the surface isn't relevant (e.g., SDK-only changes don't need cross-tenant checks).

## Canonical openbat helpers (reuse, do not invent)

| Helper | Location | Use for |
|---|---|---|
| `validateChatbotOwnership(chatbotId)` | `lib/actions/_shared.ts:9` | Org-scoped chatbot fetch; throws if not owned |
| `getActiveOrgContext()` | `lib/org.ts:193` | `{ user, org, role, memberId }` for server actions |
| `requireUserAndOrg()` | `lib/api/auth.ts` | Same shape but returns `NextResponse` on failure (for API routes) |
| `validateApiKey(request)` | `lib/api/auth.ts` | SDK-key auth for `/api/v1/capture` style endpoints |
| `checkRateLimit(key, opts)` | `lib/api/rate-limit.ts:65` | Token-bucket rate limiting |
| `authorize(role, action)` | `lib/rbac.ts:38` | Throws if role lacks permission slug; use after `getActiveOrgContext()` |
| `can(role, action)` | `lib/rbac.ts:33` | Boolean variant of `authorize` |

## False-positive guidance

- **Cross-tenant on server actions:** if the action already calls `validateChatbotOwnership(chatbotId)`, that's the read-path AND ownership check in one — don't double-flag.
- **Rate limit on internal helpers:** internal-only functions imported by other server modules (no `"use server"` directive, no API route export) don't need their own rate limit — the calling endpoint should.
- **Atomic writes on single-writer paths:** if the table is written only by one path that already serializes (e.g., a workflow with a leadership lock), atomic SQL is nice-to-have, not a BLOCK.
- **Input validation on internal-shaped types:** TypeScript-typed inputs from server-only modules don't need Zod parsing — only public surfaces (API routes, server actions, capture endpoint) do.
- **Scanner-flagged "weak cipher" hits on `description`-style English words:** ignore. See `.deepsec/data/openbat/reports/FALSE-POSITIVES.md` for confirmed false positives.

## Self-check before reporting

Before printing the findings:
- Re-read the plan once more — did you miss a sub-feature buried in a "and also…" bullet?
- For every BLOCK, can you cite the canonical fix with a real file path? If not, downgrade to FLAG.
- Did you check the top-5 inline list, even for the categories you didn't load a reference for?
