# Secrets exposure + error message leaks + info disclosure — 9 findings

## TL;DR

- **No hardcoded secrets** in source — even `lib/utils/discord-webhook.ts` had a real webhook URL with token in code.
- **Distinct keys per environment** — `.env.local` and `.env.production.local` should never share the same Gemini API key.
- **Don't pull production service-role JWTs to dev machines.** A 10-year service_role token with full RLS bypass on a developer laptop is a single-machine compromise = full data breach.
- **API keys never travel via URL query params.** Logs, browser history, Referer headers, screen shares all preserve them.
- **Error responses to clients must be generic.** Raw `error.message` from Supabase exposes table/column/constraint names; including env var names in error text gives attackers a direct list of what to compromise next.
- **Use 4xx/5xx status codes.** Returning `200 { ok: false, error: "..." }` confuses clients and obscures monitoring.

## The antipatterns

### A1 — secret in source

```ts
// lib/utils/discord-webhook.ts:4 (the BUG)
const DISCORD_URL = "https://discord.com/api/webhooks/.../...";
```

Anyone with read access to the repo can post to the operator's Discord. Even if the webhook is rotated, the next clone of the repo replants it.

### A2 — same key, two environments

```bash
# .env.local
GEMINI_API_KEY=AIzaSy...XYZ

# .env.production.local
GEMINI_API_KEY=AIzaSy...XYZ   # ← same key
```

Compromise of either side compromises both. Defeats the point of having separate environments.

### A3 — production service_role on a developer laptop

```bash
# .env.production.local (real entry from the report)
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...  # iat 2026-03, exp 2036-02
```

10-year JWT with full bypass-RLS access. Local-machine compromise = full prod data breach for a decade.

### A4 — newly minted API key in URL

```ts
// app/platform/(org)/_components/create-chatbot-dialog.tsx:37 (the BUG)
router.push(`/platform/${id}/onboarding?key=${apiKey}`);
```

The key now lives in:
- Browser history
- Server access logs
- `Referer` header on outbound requests from the onboarding page
- Vercel runtime logs
- Any analytics tool that captures `window.location.href`

Even if the user closes the tab, the key is recoverable.

### A5 — raw Supabase error returned to client

```ts
// app/api/ai-reports/[reportId]/thread/delete/[threadId]/route.ts:35-38
const { error } = await admin.from("ai_report_threads").delete().eq("id", threadId);
if (error) {
  return NextResponse.json({ error: error.message }, { status: 200 });
  //                                  ^^^^^^^^^^^^^^^^                   ^^^
  //                                  table+constraint names              wrong status
}
```

`error.message` from Supabase often contains: table name, column name, constraint name, full SQL fragment. Returning HTTP 200 makes the client treat the error as success.

### A6 — env var names in error text

```ts
// app/api/ai-reports/[reportId]/chat/route.ts:151-161 (the BUG shape)
catch (err) {
  return NextResponse.json({
    ok: false,
    error: `Configuration error. Verify GEMINI_API_KEY and LLM_MODEL are set.`,
  }, { status: 200 });
}
```

Tells the attacker exactly which env vars exist on the server.

## Why it fails in openbat specifically

- `.gitignore` already excludes `.env*.local`, but file is still on disk in plain text — local exposure is the threat vector.
- Multiple endpoints catch errors and return them as 200 with the message. Some of those messages reference Better Auth / Supabase / Gemini error shapes verbatim.
- The new-API-key flow (creation → onboarding) uses `router.push` instead of an in-memory hand-off; the URL is the simplest path but the worst place to put a key.
- `lib/utils/discord-webhook.ts` was a one-off internal alerting helper that landed with the URL hardcoded.

## Canonical fix patterns

### Pattern A — env-only secrets, validated at boot

```ts
// lib/env.ts
import { z } from "zod";
const Env = z.object({
  GEMINI_API_KEY: z.string().min(1),
  DISCORD_WEBHOOK_URL: z.string().url().optional(),
  // ... every required secret
});
export const env = Env.parse(process.env);
```

Then everywhere uses `env.GEMINI_API_KEY` — no `process.env.<KEY>` at the call sites, and a missing or malformed key fails loud at boot.

### Pattern B — distinct keys per env, rotated

- Create separate Gemini API keys: `prod-XXX`, `dev-YYY`. Set restrictive billing caps on `dev-*`.
- For Supabase: use the local-emulator service_role key (`npx supabase start` provides a dev-only key) for `.env.local`. Reserve the production service_role for Vercel env config + 1Password.
- Rotate quarterly; tighten the `exp` field on Supabase tokens if Supabase supports custom expirations.

### Pattern C — API key handoff via session storage, not URL

```ts
// On creation:
sessionStorage.setItem(`onboarding-key-${id}`, apiKey);
router.push(`/platform/${id}/onboarding`);

// In the onboarding page:
const apiKey = sessionStorage.getItem(`onboarding-key-${id}`);
sessionStorage.removeItem(`onboarding-key-${id}`);   // one-shot
if (!apiKey) {
  // user navigated here directly — show a "rotate key" CTA
}
```

Or use a one-time reveal token: server stores `{ token, key, expiresAt }`, client exchanges token → key on the onboarding page, server deletes the row.

### Pattern D — generic error responses + correct HTTP codes

```ts
try {
  await someOperation();
  return NextResponse.json({ ok: true });
} catch (err) {
  log.error("operation failed", { err });   // ← detailed log, server-only
  return NextResponse.json(
    { ok: false, error: "Could not complete the request. Please try again." },
    { status: 500 }   // ← not 200
  );
}
```

For client-input errors (validation, ownership): `{ status: 400 }` or `{ status: 403 }`. Never `200` for an error.

### Pattern E — pre-commit secret scanner

Add `gitleaks` or `trufflehog` as a pre-commit hook to catch JWTs / `re_*` / `AIzaSy*` / `sk_live_*` patterns even if `.gitignore` is misconfigured. The repo's `proxy.ts` already establishes the local hooks pattern; adding one more is straightforward.

## Real examples from the report (file:line)

- `.env.production.local:6` — production Supabase service_role JWT (10-year token).
- `.env.production.local:2` — production Gemini API key (also identical to `.env.local`).
- `.env.production.local:24` — Vercel OIDC token cached on disk.
- `lib/utils/discord-webhook.ts:4` — hardcoded Discord webhook URL with token.
- `app/platform/(org)/_components/create-chatbot-dialog.tsx:37` — newly minted API key in URL query param.
- `app/api/ai-reports/[reportId]/chat/route.ts:151-161` — env var names in error response.
- `app/api/ai-reports/[reportId]/thread/delete/[threadId]/route.ts:35-38` — raw Supabase error returned with HTTP 200.
- `app/api/ai-reports/[reportId]/thread/update/[threadId]/route.ts:48-51` — same shape on PATCH.
- `lib/queries/onboarding.ts:25` — `select("*")` over-fetches and amplifies any IDOR (separate finding, but same "info disclosure" theme).

## Plan-review questions

### Secrets

1. Does the plan introduce any constant in source that looks like an API key, webhook URL, signing secret, JWT, or bearer token?
   - If yes: BLOCK. Move to env var; validate via `lib/env.ts`.
2. Does the plan reuse the same secret across environments?
   - If yes: BLOCK. Generate a separate dev-scope key (with billing caps) for `.env.local`.
3. Does the plan transmit a newly minted API key (or any secret) via URL query param or path segment?
   - If yes: BLOCK. Use sessionStorage handoff or a one-time reveal token.
4. Does the plan introduce a flow that pulls a production credential to a developer machine (e.g., `vercel env pull --environment=production`)?
   - If yes: FLAG and add documentation: chmod 600, no cloud-sync folders, delete after use.
5. Does the plan introduce a long-lived token (`exp` more than ~1 year out) that bypasses RLS or otherwise has god-mode access?
   - If yes: FLAG — tighten the expiration if supported.

### Error responses

6. Does the plan return `error.message` from Supabase / Better Auth / Gemini directly to the client?
   - If yes: BLOCK. Log the detail server-side; return a generic user-facing string.
7. Does the plan return `200 { ok: false, error: ... }` for any failure path?
   - If yes: FLAG — change to 4xx/5xx so monitoring and clients can distinguish success from failure.
8. Does any error message reference an environment variable name (`GEMINI_API_KEY`, `RESEND_API_KEY`, etc.)?
   - If yes: BLOCK. The error text becomes a recon list.

### Info disclosure

9. Does the plan add a `.select("*")` query?
   - If yes: FLAG — replace with explicit column lists. `select("*")` amplifies the impact of any IDOR; the report flagged this on `getOnboardingData`.
10. Does the plan log secret material via `log.info` / `log.error`?
    - If yes: redact before logging (the `llm_calls` log encryption pattern is the model — see `lib/llm/call-llm.ts`).

## False positives (don't flag these)

- Generic error strings that don't reveal infrastructure: `"Invalid input"`, `"Forbidden"`, `"Not found"` — these are fine to return verbatim.
- Test fixtures that intentionally include placeholder secrets like `sk_test_PLACEHOLDER` — confirm they're placeholders, not real test-environment secrets.
- Local-only seed scripts that read from `.env.local` and only run in `NODE_ENV=development`.

## Suggested-fix snippets for the audit findings table

> Hardcoded secret: "Move `<secret-name>` to an environment variable; add to `lib/env.ts` schema and validate at boot. Rotate the leaked value before merging."

> Secret in URL: "Replace `router.push('?key=${apiKey}')` with a sessionStorage handoff: `sessionStorage.setItem(<scoped-key>, apiKey)` before navigation; read and remove on the destination page. Surface a 'rotate key' CTA if the storage is missing."

> Raw error to client: "Log `error.message` server-side via `log.error(...)`; return a generic string `{ ok: false, error: 'Could not complete the request' }` to the client with HTTP 500 (server error) or 4xx (client error). Never HTTP 200 for a failure."
