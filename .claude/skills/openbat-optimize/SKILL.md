---
name: openbat-optimize
description: "Run the daily eval→fix loop on a chatbot: pull the OpenBat digest of recent failures (flags, issues, outcomes + reasonings), drill into representative conversations, map each problem cluster to the right lever (system prompt / tool logic / retrieval / new analysis / new alert), and apply fixes in the customer's repo with confirmation. Triggers on 'optimize my chatbot', 'what went wrong yesterday', 'fix my chatbot from the conversations', 'daily eval', 'why is my bot failing X'."
source: project
date_added: "2026-05-29"
---

# OpenBat — Optimize a chatbot from its conversations

The eval loop has two halves, and OpenBat now does both:
1. **Diagnose (passive):** OpenBat tells you **what went wrong** in REAL traffic
   (flags, issues, outcomes + the analysis *reasoning*), and you — running inside
   the chatbot's own repo — diagnose **why** against the actual source.
2. **Validate (active):** you **send synthetic test queries** to the chatbot
   (`openbat probe` / `openbat eval`), OpenBat analyzes them, and you read the
   verdict to confirm your fix actually worked — before and after, as a diff.

Synthetic (probe) traffic is captured as `kind=probe` and is **excluded from
organic `review`/analytics**, so testing never skews real metrics. OpenBat ships
no scheduler: wire `openbat optimize` / `openbat review` into your own cron /
scheduled agent / CI and feed the output to this skill. Fastest start:
`openbat optimize` (review + active prompt + analysis defs + a probe plan, in one
read-only call).

**This skill operates on exactly ONE chatbot per run.** The reasoning happens
here, client-side, because only this repo holds the system prompt, tools, and
retrieval config — OpenBat's server never sees your code.

## 0. Confirm scope (one chatbot)

```bash
openbat auth whoami        # shows the active chatbot
```

If `activeChatbot` is `(not pinned — N reachable)` and the key is a PAT
spanning multiple chatbots, **STOP** and pin one first:

```bash
openbat use <id-or-name>   # persists ~/.openbatrc.activeChatbotId
```

Every command below then targets that one chatbot. (A chatbot-scoped key
`ob_read_*` / `ob_admin_*` is single-chatbot by construction — nothing to pin.)

## 1. Pull the digest

```bash
openbat review --since 24h          # default; also 45m, 6h, 7d (max 30d)
openbat review --since 7d --json    # machine-readable for a script/agent
```

Returns headline aggregates (with deltas vs the prior equal-length window) +
clusters of top **issues / flags / intents** and **failed outcomes**, each
issue carrying representative conversation pointers with the analysis
`reasoning` and verification fields. MCP equivalent: `openbat_review { chatbotId, windowMinutes? }`.

## 2. Drill into the representatives

For each cluster's representative `conversationId`:

```bash
openbat conversations show <id> --json | jq '.messages[] | {role, content, analyses: {
  intents: .user_intents, flags: .user_flags,
  outcomes: .assistant_outcomes, issues: .assistant_issues }}'
```

Read the actual turns **and** the analysis `reasoning` + `answer_available` +
`verification_source` on the flagged message. That triplet tells you whether
the bot *could* have answered.

## 3. Locate the chatbot's source in the repo

- **System prompt:** grep `systemPrompt`, `system_prompt`, `role: "system"`,
  large template literals near `streamText` / `generateText` / `messages: [`;
  paths like `**/prompts/*.{ts,md}`, `system-prompt.*`, `*.prompt.*`.
- **Tools / functions:** `tools: {`, `tool(`, `functionDeclarations`,
  `zodFunction`; files `tools.*`, `functions.*`.
- **Retrieval / RAG:** `embed(`, `similaritySearch`, `vectorStore`, `pgvector`,
  `retriev`, `topK`; files `retrieval.*`, `rag.*`, `knowledge*`.
- Prefer the repo's own code-intelligence (e.g. GitNexus `gitnexus_query`)
  before grepping.

## 4. Map symptom → lever (the centerpiece)

`answer_available = true` ⇒ the bot **could** have answered ⇒ it's a delivery
failure (prompt / retrieval / tool), **not** a knowledge gap. `verification_source`
then narrows which:

| Cluster signal | `answer_available` | `verification_source` | Lever | Fix |
|---|---|---|---|---|
| Wrong/incomplete answer, info exists in docs | true | `docs` / `retrieval` | **Retrieval / docs** | Improve chunking/topK, add the doc, fix the index — *not* the prompt |
| Bot refused/hedged though it had the data | true | `reasoning` / `chatbot_data` | **System prompt** | Loosen/clarify the instruction that caused the refusal |
| Bot needed a tool but never called it | n/a | (tool gap) | **Tool logic / prompt** | Add tool-trigger guidance to the prompt, or fix the tool schema/description |
| Invented facts not in any source | false | `hallucination` | **Prompt + retrieval** | Add a "say you don't know" guardrail; fill the knowledge gap |
| Genuinely unanswerable (info doesn't exist) | false | `missing_knowledge` | **Docs / product** | Author the missing doc; or route to a human |
| Recurring spike, no single root cause | n/a | n/a | **New analysis + alert** | `openbat analysis add` to track it, `openbat workflows create` to alert |

## 5. Propose + apply fixes, grouped by lever

For each lever group, list the proposed edit + the **evidence** as conversation
links (`/platform/<chatbotId>/conversations/<id>`). Link — don't paste raw
conversation content (it may contain customer PII) into a public PR.

- **Shipping a system-prompt fix — two paths:**
  - *Chatbot fetches its prompt from OpenBat* (`GET /api/v1/prompts`): ship it
    live without a redeploy — `openbat prompts publish --file <prompt>` (goes
    live in ~60s). Roll back with `openbat prompts activate <prevVersionId>` or,
    in an emergency, `openbat prompts kill-switch --on`. Confirm with the user
    first — this changes the production prompt.
  - *Chatbot hardcodes its prompt*: edit it in the repo (publishing in OpenBat
    won't change runtime). See `openbat-prompts`/flow 11 in `using-openbat`.
- **Repo edits** (system prompt, tool code, retrieval config) require explicit
  user confirmation. Offer a **PR**; never auto-commit to the default branch.
- **OpenBat mutations** (`openbat analysis add`, `openbat workflows create`,
  settings writes): first run the **`openbat-plan-audit`** skill on the change,
  then follow **`openbat-safe-mutations`** (list-first, confirm, smallest scope).

## 6. Validate the fix by PROBING (closes the loop)

Don't ship a fix on faith — test it against the live chatbot with synthetic
queries and read OpenBat's verdict. Two complementary tools:

**A. Fresh synthetic queries (`probe` / `eval`) — the active loop.** Drive the
chatbot with new questions targeting the failure, let it capture as `kind=probe`,
and read the analysis. Declare an adapter once (`openbat.probe.json`: how to call
your chatbot), then:

```bash
openbat probe "the exact question that failed organically"   # one turn → verdict
# Or a whole suite, diffed before/after the fix to catch regressions:
openbat eval run --suite golden.json --out before.json
#   …apply the fix (repo edit, or a candidate prompt — see below)…
openbat eval run --suite golden.json --out after.json
openbat eval diff before.json after.json       # exit 1 if anything regressed
```

Test a candidate prompt **without shipping**: `openbat prompts create-draft
--file new-prompt.txt` → probe/eval against that version (your chatbot fetches it
via the SDK's `versionOverride`, fed a `{{candidate}}` adapter field) → only
`openbat prompts activate <versionId>` once the eval passes. MCP equivalents:
`openbat_probe`, `openbat_await_analysis`, `openbat_create_draft_prompt`,
`openbat_optimize_context`. (Under MCP you issue the chatbot call and loop
`openbat_probe` → `openbat_await_analysis` → `openbat_get_conversation` yourself
— OpenBat never calls your chatbot.) See the **`openbat-eval`** skill for the full
active loop.

**B. Replay historical flagged conversations (`backtests`).** Complements probing
when you want to re-test the SAME real conversations that failed:

```bash
openbat backtests create --name "fix v2" --candidate-prompt <versionId> \
  --flags <flag1,flag2> --sample-size 50      # requires a PAT key
openbat backtests status <backtestId>          # still_flagged / resolved / new_flag / unchanged_clean
```

Ship only if the verdict is clean (probe issues resolved / `resolved` dominates,
`new_flag` ~0) — via `openbat prompts publish --wait` (fetch-endpoint chatbots),
`openbat prompts activate <draftId>`, or a repo PR.

## Wire into your own daily workflow

OpenBat doesn't schedule anything. To run this every morning, the customer
adds a step to *their* automation (cron, a scheduled Claude Code agent, or a CI
job) that:

1. runs `openbat review --since 24h --json` (with a chatbot-scoped `ob_read_*`
   key, or `OPENBAT_CHATBOT_ID` set), and
2. hands the output to an agent with this skill, which opens a "here's what to
   fix from yesterday" PR for a human to review.

## Gotchas / safety rails

- One chatbot per run — confirm scope (step 0) before anything else.
- `answer_available` is the load-bearing field — never edit the prompt for a
  `missing_knowledge` cluster.
- Repo edits need confirmation; never commit to the default branch.
- The digest is sampled + 200-row capped like every OpenBat read — for the full
  picture of a cluster, drill into more representatives via `conversations show`.
