---
name: openbat-replay
description: "Replay a labeled set of real conversations against other models/prompts (OpenRouter BYOK), grade them with the chatbot's own analysis, and pick a winner on one objective (flags / outcome / issues). Triggers on 'replay experiment', 'replay these conversations', 'compare models on real traffic', 'optimize-for', 'frozen tools', openbat replay, or openbat_replay_*."
source: project
date_added: "2026-08-19"
---

# OpenBat — Replay experiments

Replay batch-tests **history**. Prompt A/B under Chatbot Management splits
**future** traffic. Use this when the user wants to know whether a different
model or prompt would have judged better on the **same** real user turns.

Requires `@openbat/cli` / `@openbat/mcp` **1.0.3** or later. Dashboard:
`/platform/[chatbotId]/experiments` (not the Chatbot Management Experiments tab).

## When to use this vs probe / backtest

| Tool | What it re-runs | Isolation |
|---|---|---|
| **Replay** (`openbat replay`) | Real labeled conversations, one assistant turn, frozen history | `traffic_kind='replay'` — never in organic analytics |
| **Probe / eval** (`openbat-eval`) | Fresh synthetic questions you send to the live chatbot | `kind=probe` |
| **Backtest** (`openbat backtests`) | Flagged conversations under a candidate **prompt** | PAT-only; flag tally |

Use replay to **measure a model/prompt change on the failures you already have**.
Use probe/eval to **validate a fix against new questions**. Use backtest when
you only need "would this prompt clear these flags?"

## 0. Prereqs

```bash
openbat use <id>                 # pin one chatbot
openbat auth whoami
```

- An **OpenRouter key** on the chatbot (Settings → Providers). Generation
  bills that key. Judging is free.
- A **label** with the conversations to replay (max 200 at snapshot).
- `run` needs an **admin or PAT** key. `list` / `status` / `results` / `diff`
  work with any read-capable key.

## 1. Curate the set

```bash
openbat labels create refunds-week16
openbat labels add <conversationId…> --label refunds-week16
openbat labels list
```

MCP: `openbat_list_labels` (read); `openbat_{create,archive,assign,unassign}_label`
(admin). On a conversation, **Replay from this turn** (user message) pins the
start turn for every label on that thread.

Fidelity badges on Chatbot Management → Labels (prompt / tools / model ✓/✗)
count how often those fields were **captured**. They do not change generation.

## 2. Launch

```bash
openbat replay run --label refunds-week16 \
  --model openai/gpt-4o --model anthropic/claude-sonnet-4 \
  --optimize-for flags --wait
```

`--model` is repeatable (1–7 variants + server-created baseline).
`--optimize-for` is `flags` (default), `outcome`, or `issues` — the **one**
objective used to color cells and award Best. `--wait` polls to completion.

MCP: `openbat_replay_run` (`optimizeFor`, same enums) → poll
`openbat_replay_status` → read `openbat_replay_results`.

One running experiment per chatbot. Baseline is the **original** captured
assistant (no regen, no OpenRouter spend).

## 3. Read results

```bash
openbat replay list
openbat replay status <experimentId>
openbat replay results <experimentId>          # grid + rates
openbat replay diff <experimentId>             # grep-friendly flag/outcome deltas
```

Best is awarded only when a non-baseline variant actually improved on the
chosen objective. Click a cell in the dashboard to open the judged assistant
turn (replay transcript banner; labels stay on the source conversation).

## What replay actually uses (v1)

Replay regenerates **one** assistant turn. It does **not** reconstruct the
original production combo unless you put those levers on the variant.

| Lever | What the variant run uses | If capture is missing |
|---|---|---|
| User query + prior turns | Frozen history up to the target user message | Always present |
| System prompt | The **variant** prompt (active / candidate / inline) | Empty system string |
| Model + sampling | The **variant** OpenRouter model + optional params | Required on each non-baseline |
| Tools | **Frozen, not live.** Prior assistant `context.tools` may be inlined as `[Original tool result] name(input) -> output`. `generateText` is called with **no tools** | First-turn threads, or empty `context.tools`, give the model chat text only |

A replay that says it cannot access data — judged **Correctly Refused** — is
expected when there are no live tools and nothing to inline. That is **not**
proof the production bot lacked tools. The original answer lives on the
**source** conversation / baseline column.

## SDK (no customer replay API)

`@openbat/sdk` **1.1.0** does not launch experiments. Keep sending
`kind: "organic"` or `"probe"`. Ingest **rejects** `kind: "replay"` on SDK
keys (400). Capture `model`, `params`, `tools`, and `toolDefinitions` on
organic traffic so labeled sets stay faithful. See `openbat-sdk-install`.

## Gotchas

- Replay conversations never appear in dashboards / Tinybird / metering.
- Do not treat Chatbot Management → Experiments (live A/B) as this feature.
- Do not tell the user to "load tools" on a replay transcript — v1 cannot.
- Confirm OpenRouter spend before a large `--wait` run (estimate is 1,500 in /
  400 out tokens per item; real spend shows on the detail page).
