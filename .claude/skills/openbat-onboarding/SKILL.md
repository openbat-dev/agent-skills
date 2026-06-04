---
name: openbat-onboarding
description: "Create a new OpenBat chatbot and complete onboarding from the CLI or MCP. Triggers when user wants to register an account, spin up a new chatbot, mint its first ingest key, run full onboarding, or get the onboarding URL."
source: project
date_added: "2026-05-13"
---

# OpenBat — Register, create + onboard a chatbot

Everything from account signup through full product onboarding can be driven
from the terminal. Creating a chatbot still requires a **PAT** (`ob_pat_*`) —
no other credential can create chatbots (ingest/read/admin keys are pinned to
one existing chatbot).

## 0. Register an account (CLI)

```bash
openbat register                      # prompts email + password (masked)
openbat register --email you@co.com   # password via prompt/stdin
openbat register --browser            # open the web sign-up form instead
```

Honest reality: a freshly-registered account lands in a **pending** state — the
product owner approves new accounts out of band (you get an email). After
approval, run `openbat login` to mint a PAT on the device. `register` therefore
ends at "pending approval", it does **not** hand back a key. (Plaintext
passwords are only sent over HTTPS/localhost — a remote `--base-url http://…`
is refused.)

## 1. Create a chatbot

```bash
openbat chatbots create \
  --name "Acme Support" \
  --website https://acme.com \
  --docs-url https://docs.acme.com
```

Output:
- **stderr**: the new ingest key (`ob_live_*`) inside a "shown ONCE" banner.
  Capture it immediately — there is no recovery path.
- **stdout** (JSON-pipeable): `{ chatbot: { id, name, created_at, organization_id, api_key_prefix }, dashboardUrl }`.

## 2. Full onboarding (interactive, CLI)

`openbat onboard` runs the whole product-onboarding flow in the terminal —
no dashboard needed. It can create the chatbot for you, or onboard the active
one (`openbat use <id>` / `--chatbot`).

```bash
openbat onboard --create "Acme Support"   # create + onboard in one shot
openbat onboard                            # onboard the active chatbot
openbat onboard --yes --website https://acme.com --no-verify   # CI / headless
```

Sequence (each step = a v1 endpoint, also available as MCP tools):
1. resolve/create the chatbot (surfaces the ingest key once),
2. **extract** product intelligence from the website/docs (Gemini, ~30-120s; also seeds personas),
3. confirm/edit the extracted summary,
4. pick which of the **6 analysis categories** to enable (`sentiment`, `intent`, `flag`, `ai_literacy`, `assistant_outcome`, `assistant_issue`),
5. fire persona + calibration generation in the background,
6. print the SDK snippet and wait for the first captured event (skip with `--no-verify`),
7. **complete** — flips the analyze\* settings + `onboarded:true`, prints the dashboard URL.

`--yes` / `--non-interactive` accept the extracted defaults and enable all six
categories (for agents/CI). Deep persona editing still lives in the dashboard.

The `dashboardUrl` (`/platform/<id>/onboarding`) opens the same wizard visually
if you'd rather not use the terminal — completing either path sets
`settings.onboarded = true`.

## MCP

Create:

```json
{ "tool": "openbat_create_chatbot",
  "arguments": { "name": "Acme Support", "websiteUrl": "https://acme.com", "primaryLanguage": "en" } }
```

Onboarding tools (admin/PAT for writes, read for status):
`openbat_set_onboarding_data`, `openbat_extract_product_intelligence`,
`openbat_seed_personas`, `openbat_generate_calibration`,
`openbat_get_calibration_status`, `openbat_complete_onboarding`. Each maps 1:1
to a `/api/v1/chatbots/{id}/onboarding/*` route, so CLI and MCP share behavior.
Account registration is **not** an MCP tool (no token to mint while pending).

## After creation

The chatbot exists with an ingest key. To open the read / write surface
you need additional keys:

```bash
openbat settings keys generate-read --chatbot $CB                       # CLI/MCP reads
openbat settings keys generate-admin --chatbot $CB --name "CI key" --expires-in-days 90  # writes
```

Then drop the new ingest key into the target app's `.env.local` and follow
the `openbat-sdk-install` skill.

## Gotchas

- The org auto-selected for a new chatbot is the PAT user's primary
  org (oldest membership). There's no CLI flag for cross-org creation yet.
- AI extraction (`extract_product_intelligence`) is rate-limited 10/hour
  (registry) + 5/hour (per chatbot); `generate_calibration` is 5/hour. All
  user-supplied URLs are SSRF-validated (DNS-resolving) before any fetch.
- `register` cannot complete onboarding for you — it only creates the (pending)
  account. Run `openbat login` once approved, then `openbat onboard`.
