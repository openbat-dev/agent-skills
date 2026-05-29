---
name: openbat-optimize
description: "Run the daily eval→fix loop on a chatbot: pull the OpenBat digest of recent failures (flags, issues, outcomes + reasonings), drill into representative conversations, map each problem cluster to the right lever (system prompt / tool logic / retrieval / new analysis / new alert), and apply fixes in the customer's repo with confirmation. Triggers on 'optimize my chatbot', 'what went wrong yesterday', 'fix my chatbot from the conversations', 'daily eval', 'why is my bot failing X'."
source: project
date_added: "2026-05-29"
---

# OpenBat — Optimize a chatbot from its conversations

The daily eval loop: OpenBat tells you **what went wrong** (flags, issues,
outcomes, and the analysis *reasoning* behind each), and you — running inside
the chatbot's own repo — diagnose **why** against the actual source and apply
the fix. OpenBat ships no scheduler: a customer wires `openbat review` into
their own cron / scheduled agent / CI and feeds the output to this skill.

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
`reasoning` and verification fields. MCP equivalent: `openbat_review { windowMinutes? }`.

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

- **Repo edits** (system prompt, tool code, retrieval config) require explicit
  user confirmation. Offer a **PR**; never auto-commit to the default branch.
- **OpenBat mutations** (`openbat analysis add`, `openbat workflows create`,
  settings writes): first run the **`openbat-plan-audit`** skill on the change,
  then follow **`openbat-safe-mutations`** (list-first, confirm, smallest scope).

## 6. (Phase 2) Validate the fix with a backtest

Once exposed, replay the flagged conversations against the candidate prompt and
read the verdict (resolved / still-flagged / new-flags) before shipping — see
the `openbat-experiments` skill. Closes the eval loop.

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
