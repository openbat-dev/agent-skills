# SSRF — 7 findings

## TL;DR

Anywhere the codebase accepts a URL from a user (mcpUrl, webhook URL, website URL, redirect target) and later fetches it, the URL must be validated against:
1. **Scheme allowlist** (`http`/`https` only — no `file:`, `gopher:`, etc.)
2. **Hostname not in private/loopback/link-local ranges** (`10.*`, `172.16-31.*`, `192.168.*`, `127.*`, `169.254.*`, `::1`, `fc00::/7`)
3. **DNS-resolved IP not in those ranges either** (DNS rebinding bypasses hostname-only checks)
4. **Both at write time AND at read/use time** (DNS records can change between when the URL was stored and when it's fetched)
5. **Redirect handling: `redirect: 'manual'` and re-validate every Location header** before following

The `isPrivateHostname` helper exists but is applied only at some sites and only on the literal hostname.

## The antipatterns

### A1 — no validation at all

```ts
// lib/actions/onboarding.ts:62
const client = await createMCPClient({
  transport: new StdioClientTransport({ url: input.mcpUrl }),  // ← user-supplied
});
```

A user submits `http://169.254.169.254/latest/meta-data/iam/security-credentials/` (AWS instance metadata) and the server happily fetches it from the trusted internal network.

### A2 — hostname-only check (DNS rebinding bypass)

```ts
const url = new URL(input.mcpUrl);
if (isPrivateHostname(url.hostname)) {
  throw new Error("Private hostname blocked");
}
const res = await fetch(input.mcpUrl);  // ← DNS may resolve to a private IP
```

The attacker controls a domain (`evil.com`) with DNS A record pointing to `1.2.3.4` (TTL: 0). When `isPrivateHostname` resolves at validation time, it gets `1.2.3.4` (public). At fetch time, the DNS server returns `127.0.0.1`. The server connects to itself.

### A3 — write-time validation only

```ts
// At write: validates webhook.url
await admin.from("webhooks").insert({ url: input.url });

// Later, at fire time:
await fetch(webhook.url);   // ← no re-validation; URL was validated days ago
```

If the DNS for `webhook.url` changes after it's stored, the validation is stale.

### A4 — `fetch` follows redirects to private IPs

```ts
const res = await fetch(webhook.url);
// fetch defaults to redirect: 'follow' — a 302 to http://169.254.169.254/ is followed silently
```

### A5 — port-scanning oracle in the response

```ts
try {
  const res = await fetch(input.mcpUrl, { signal: AbortSignal.timeout(2000) });
  return { ok: true, status: res.status };
} catch (err) {
  return { ok: false, error: err.message };  // ← timeout vs. ECONNREFUSED leaks port state
}
```

Even if the fetch is blocked from sending data, the *response timing and error type* tell the attacker which internal hosts/ports are open. Useful for mapping the internal network.

## Why it fails in openbat specifically

- `lib/actions/onboarding.ts:isPrivateHostname` exists but is hostname-only and not consistently applied.
- Several MCP/webhook fetch sites are in `"use server"` files or workflow steps where the URL was validated at write time only, never at use time.
- Workflow steps run with the admin client and full network access — they're the most attractive SSRF targets.

## Canonical fix patterns

### Pattern A — single hoisted validator

Create one helper and use it everywhere:

```ts
// lib/utils/url-safety.ts
import { lookup } from "node:dns/promises";

const PRIVATE_RANGES = [
  /^127\./, /^10\./, /^192\.168\./, /^169\.254\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^::1$/, /^fc[0-9a-f]{2}:/, /^fe80:/,
];

export async function assertPublicHttpUrl(input: string): Promise<URL> {
  const url = new URL(input);
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("Only http/https URLs are allowed");
  }
  // Resolve and check IP, not just hostname (defeats DNS rebinding for the moment)
  const { address } = await lookup(url.hostname);
  if (PRIVATE_RANGES.some((r) => r.test(address))) {
    throw new Error("URL resolves to a private network address");
  }
  return url;
}
```

Call it at write time (`createWebhook`, `updateChatbotData`, `extractProductIntelligence`, `testMcpConnection`) AND at use time (`postWebhook`, `verifyFactsStep`, `extractWithMcp`).

### Pattern B — manual redirects with re-validation

```ts
let target = await assertPublicHttpUrl(webhook.url);
let res: Response;
for (let i = 0; i < 3; i++) {
  res = await fetch(target, { redirect: "manual", signal: AbortSignal.timeout(5000) });
  if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
    target = await assertPublicHttpUrl(res.headers.get("location")!);
    continue;
  }
  break;
}
```

Cap redirects (3 hops max), re-validate every Location.

### Pattern C — pin to resolved IP (defeats post-validation rebinding)

For maximum paranoia (worth it for webhooks that fire repeatedly):

```ts
const url = new URL(input.url);
const { address } = await lookup(url.hostname);
if (PRIVATE_RANGES.some((r) => r.test(address))) throw new Error("private");
// Fetch by IP, set Host header to original hostname
const res = await fetch(`${url.protocol}//${address}${url.pathname}${url.search}`, {
  headers: { Host: url.hostname },
  redirect: "manual",
});
```

The DNS resolution happens once, in our control; the fetch goes to that exact IP.

### Pattern D — generic error response

```ts
try {
  const res = await fetch(target, ...);
  return { ok: res.ok };  // ← no status code, no error text
} catch {
  return { ok: false, error: "Could not reach the URL" };  // ← generic message
}
```

No status leak, no `ECONNREFUSED` vs. `timeout` distinction.

## Real examples from the report (file:line)

- `lib/actions/onboarding.ts:62,110-116` — `extractProductIntelligence` calls `createMCPClient` with user-supplied `mcpUrl`, no validation.
- `lib/actions/onboarding.ts:325-338` — `testMcpConnection` checks `isPrivateHostname` (hostname-only) and returns status code + error text (port-scan oracle).
- `lib/workflows/v3/verify-facts.ts:189-191` — `verifyFactsStep` calls `createMCPClient` with stored `mcp_url`, no re-validation.
- `lib/actions/webhooks.ts:17,49` — `createWebhook`/`updateWebhook` only validate `new URL(url)` (parses but doesn't check scheme/IP).
- `lib/workflows/execute-workflow.ts:100` — `postWebhook` calls `fetch(webhook.url)` with default `redirect: 'follow'`, no re-validation.
- `lib/org-health/dispatch.ts:85-102` — same as above for org-health webhooks.
- `app/api/v1/capture/route.ts` — `capture` derives base URL from incoming `Host` header (Host-header SSRF/cache-poisoning).

## Plan-review questions (any "no" → BLOCK on URL-fetch features)

1. Does the plan accept a URL from user input, store it, or fetch a URL stored from earlier user input?
   - If yes: is there an `assertPublicHttpUrl` (or equivalent scheme + IP-resolution check) at BOTH write time AND read/use time?
2. Does the plan call `fetch()` on a URL that came from user input?
   - If yes: is `redirect: "manual"` set, and does each Location redirect get re-validated through the same helper?
3. Does the plan return the upstream HTTP status code or the raw error message to the client?
   - If yes: FLAG — this becomes a port-scanning oracle. Return generic `{ ok: false, error: "Could not reach the URL" }`.
4. Does the plan derive a base URL from `request.url` or the `Host` header for outbound calls?
   - If yes: BLOCK — Host header is attacker-controlled. Use a constant base URL from env.
5. Does the plan introduce a new MCP client (`createMCPClient`)?
   - If yes: same scheme + IP check; remember MCP clients open arbitrary network connections, not just HTTP.

## False positives (don't flag these)

- The URL is a constant or comes from an env var (`process.env.RESEND_API_BASE`) — server-controlled, not user-supplied.
- The URL is normalized through a known-safe API like `@/lib/discord-webhook` (after that helper is itself fixed — see `secrets-and-error-leaks.md`).
- The fetch target is on the same Vercel deployment via `https://${process.env.VERCEL_URL}` — same-origin internal calls don't pose SSRF risk in the typical sense, but watch for self-DoS amplification.

## Suggested-fix snippet for the audit findings table

> "Add `assertPublicHttpUrl(url)` from `lib/utils/url-safety.ts` (create if it doesn't exist — see ssrf.md Pattern A). Call it at BOTH write time (when storing the URL) AND read time (immediately before `fetch`/`createMCPClient`). Set `redirect: 'manual'` and re-validate Location headers. Return generic error strings to the client; never leak status codes or `ECONNREFUSED` vs. `timeout` differences."
