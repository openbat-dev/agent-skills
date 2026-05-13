# One-shot criticals — patterns that surfaced once but are subtle

These are HIGH-severity issues that each appeared in only one or two findings, but each is the kind of thing that's easy to repeat in a new feature without a checklist. Skim them all when auditing any plan that touches caches, public-facing forms, GET endpoints with side effects, header trust, or stored-then-fetched URLs.

---

## 1. Global cache poisoning across tenants

**Antipattern.** A cache keyed by `(key_type, value)` shared across all tenants, where `value` is user-controllable. First tenant to look up `name = "Vercel" + email = "evil@evil.com"` writes a 30-day cache entry; every other tenant who later looks up `name = "Vercel"` sees the attacker's cached payload (logo, metadata, whatever).

**Real example.** `lib/logos/resolve.ts:183` — global `logo_lookups` table cached cross-tenant by `(key_type, key)` with no `organization_id` scoping.

**Fix.**
- Scope the cache by `organization_id` or `chatbot_id`. Cross-tenant caching is fine *only* for data that is genuinely public/safe across tenants (e.g., a public domain → logo mapping where `name` is restricted to a curated allowlist).
- If global cache is necessary for performance, only use it for *allowlist-derived* keys (e.g., a hardcoded `DOMAIN_MAP`), not user-supplied names.

**Plan-review question.** Does the plan introduce or use a cache (DB table, KV, in-memory) keyed partly by user input? If yes, is the cache scoped per-tenant, OR are the cached values guaranteed to be safe across tenants?

---

## 2. Clickjacking / auto-action on page load

**Antipattern.** Membership change, permission grant, subscription, or other state-changing action runs in a `useEffect` or server-component side effect on page load — no explicit confirmation button.

```tsx
// app/platform/invitations/accept/page.tsx (the BUG shape)
"use client";
useEffect(() => {
  acceptInvitation(token);   // ← runs on every visit, including link prefetch
}, []);
```

Effect: any link to `/platform/invitations/accept?token=...` accepts the invitation. Browser link previews, Slack unfurls, prefetch, or a malicious page that frames the URL all silently accept.

**Real example.** `app/platform/invitations/accept/page.tsx` — invitation auto-accepted in `useEffect` with no UI confirmation.

**Fix.** Show a confirmation page with the org name + role + "Accept" button. The membership change happens only on explicit click, ideally via a server action submitted from a `<form action={...}>` (POST, not idempotent GET).

**Plan-review question.** Does the plan add a flow where visiting a URL triggers a state change (membership, permission, billing, deletion, role grant)? If yes, is there an explicit confirmation step requiring a POST/server-action click?

---

## 3. Code injection into stored content

**Antipattern.** User-supplied field (e.g., `target_value`) flows into stored code/template that is later rendered. Escape function exists but only handles the obvious case (e.g., quotes) and misses newlines or other delimiters.

**Real example.** `lib/ai-reports/widgets/actions.ts:pinExperimentToReport` — unescaped `target_value` flows into stored openui-lang code; the existing name escape handles quotes but misses newlines, allowing the value to break out of the surrounding token.

**Fix.**
- Don't store user input as code-shaped strings. Store as data; render via a renderer that knows how to escape per-context.
- If the data must be embedded in code-shape strings, validate against a strict allowlist (alphanumeric + a few safe punctuation chars, no newlines, no quote-style chars) AND length-cap it.

**Plan-review question.** Does the plan flow user-controlled input into a stored code/template/markup string? If yes, is there a context-aware renderer or a strict allowlist (no newlines, no quotes, no delimiters of the embedding format)?

---

## 4. Spoofable forwarded headers treated as ground truth

**Antipattern.** Reading `x-forwarded-for`, `x-real-ip`, `x-forwarded-host`, or `User-Agent` from the request and using them for security decisions, rate-limit keys, or audit logs as if they were authoritative.

```ts
// the BUG shape
const ip = req.headers.get("x-forwarded-for") ?? "unknown";
checkRateLimit(`api:${ip}`, ...);
```

A client can send any value. On Vercel, the trustworthy header is `x-vercel-forwarded-for`; the platform sets it after stripping client-supplied versions.

**Real example.** Capture pipeline in `/api/v1/capture` accepts spoofable `x-real-ip`/`User-Agent` headers and stores them in analytics.

**Fix.** On Vercel, use `x-vercel-forwarded-for`. For audit logs, pair the spoofable headers with the authenticated `user_id` so the log is still useful even if headers lie. Never use spoofable headers as a rate-limit key for unauthenticated endpoints — the attacker can rotate the header value to bypass the limit.

**Plan-review question.** Does the plan read `x-forwarded-for`, `x-real-ip`, `User-Agent`, or any forwarded header for auth/rate-limit/audit decisions? If yes, is the source restricted to platform-set headers (`x-vercel-forwarded-for`) and is the value treated as untrusted metadata, not ground truth?

---

## 5. Webhook redirect-following bypasses URL validation

**Antipattern.** SSRF check at write time, but `fetch()` defaults to `redirect: 'follow'`, so a 302 to a private IP after the validated public URL is followed silently.

**Real example.** `lib/workflows/execute-workflow.ts:100` — `postWebhook` calls `fetch(webhook.url)` with default redirect handling.

**Fix.** Set `redirect: "manual"`, follow at most N hops manually, re-validate every Location through the SSRF helper. See `references/ssrf.md` Pattern B.

**Plan-review question.** Does the plan call `fetch()` on a URL that came from user input? If yes, is `redirect: "manual"` set?

---

## 6. TOCTOU on idempotency markers

**Antipattern.** Read marker → if not set, do expensive op → set marker. Concurrent requests both pass the check, both do the expensive op. See `references/race-conditions.md` Pattern C.

**Real example.** `app/api/v1/capture/route.ts:521-538` — `intentsGeneratedAt` race.

**Plan-review question.** Does the plan check a marker, do an expensive op, then set the marker? If yes, flip the marker first via atomic SQL (claim semantics) and only proceed if the flip succeeded.

---

## 7. Cross-tenant client cache pollution

**Antipattern.** Client-side cache (SWR, React Query, in-memory store, localStorage) keyed without including a tenant scope. After a user switches orgs (or signs in as a different user without a hard reload), the cache returns the previous tenant's data.

**Real example.** From the report: an SWR fetcher cached on a key like `chatbots-list` without including `org.id`, so switching orgs displayed the wrong list briefly.

**Fix.** Include `org.id` (or `chatbot.id`) in every client-cache key. On org switch, call SWR's `mutate()` with the cache-clear pattern `() => true`. On sign-out, clear all cached state.

**Plan-review question.** Does the plan add a client-side cache (SWR `useSWR`, React Query, Zustand, localStorage)? If yes, does the cache key include the tenant scope (org id, chatbot id)?

---

## 8. Unfiltered URL-controlled error text rendered to user

**Antipattern.** Auth error page reads `?error=...` from the URL and renders it as page content. Attacker crafts a phishing URL with an error message like "Your password has been compromised. Call support at +1-800-evil to verify."

**Real example.** Auth error page rendered URL-controlled error text without normalization, enabling phishing/social engineering.

**Fix.** Map the `?error=...` parameter to a known set of message keys; render only the message looked up from the map. Unknown keys fall back to a generic "Something went wrong."

**Plan-review question.** Does the plan render a string from a URL query param into the page UI? If yes, is the value mapped through an allowlist of known keys, or HTML-escaped at minimum?

---

## 9. Broken redirect after success (HIGH_BUG)

**Antipattern.** After a sensitive flow (password reset, email verification, signup), redirect to a hardcoded path that doesn't exist (404). User sees a broken page and assumes the action failed; trust erodes.

**Real example.** `components/update-password-form.tsx:42` redirects to `/protected` after password reset — `/protected` is not a real route.

**Fix.** Redirect to a known-good page (`/platform`, or `/auth/login?reset=success` if not yet authenticated). Add an explicit success message.

**Plan-review question.** Does the plan add a redirect after a sensitive flow (password change, signup, email verification, payment)? If yes, does the destination route actually exist and convey success?

---

## 10. Robots.txt misconfiguration

**Antipattern.** Robots.txt disallows non-existent paths and forgets to disallow the actual sensitive paths. AI crawlers and scrapers follow the rules; if `/platform/*` isn't disallowed, they crawl through the auth gate's redirect URLs and may index information leaks.

**Real example.** `app/robots.ts` disallows `/product/` (not a real path) but doesn't disallow `/platform/*`.

**Fix.** Audit the route table and disallow every route group that auth-gates content. Add explicit AI-crawler directives (User-agent: GPTBot, ClaudeBot, etc.).

**Plan-review question.** Does the plan add a new route group with auth-gated content? If yes, is `app/robots.ts` updated to disallow that path?

---

## How to use this file

When a plan touches one of the topics above (caches, GET-side state changes, header trust, stored URLs, error rendering, redirects, robots), spot-check the matching section. If the plan repeats the antipattern shape, BLOCK or FLAG with a citation back to the canonical example in the report.

If a plan does *not* touch any of these topics, this file is short enough to skim once anyway as a final sanity check before printing the audit findings.
