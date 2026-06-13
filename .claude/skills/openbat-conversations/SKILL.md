---
name: openbat-conversations
description: "Query OpenBat conversations and their analyses, time-filtered (default last 7 days). Triggers on conversation history, sentiment over time, message search, or analysis result questions."
source: project
date_added: "2026-05-13"
---

# OpenBat — Conversations + analyses

Conversation reads work with **any read-capable credential** (`ob_read_*`,
`ob_admin_*`, `ob_pat_*`). The default time window is 7 days when neither
`--from` nor `--to` is supplied.

## CLI

```bash
# Last 7 days, newest first:
openbat conversations list --days 7 --limit 50

# Custom window:
openbat conversations list --from 2026-05-01T00:00:00Z --to 2026-05-13T00:00:00Z

# Detail (messages + ALL per-message analyses: sentiments, intents, flags,
# assistant outcomes, assistant issues — each with reasoning + verification):
openbat conversations show <conversationId>

# Wait until a conversation's messages are fully analyzed (analysis is async).
# Accepts an internal id OR a probe's obprobe_ id. Exit 0 done, 2 on timeout:
openbat conversations await <conversationId> --timeout 90

# Synthetic-traffic filter (probe/eval conversations are hidden by default):
openbat conversations list --synthetic          # ONLY probe/eval conversations
openbat conversations list --include-synthetic   # organic + synthetic

# Analytics:
openbat analytics overview
openbat analytics sentiment --days 30

# Daily eval digest (aggregate "what went wrong" — see openbat-optimize):
openbat review --since 24h          # also 45m, 6h, 7d (max 30d)
```

## MCP

| Tool | Args |
|------|------|
| `openbat_list_conversations` | `{ chatbotId: uuid, page?, limit?, from?, to?, kind?: organic\|probe\|all }` (chatbotId optional only when the server is pinned) |
| `openbat_get_conversation`   | `{ chatbotId: uuid, id: uuid }` |
| `openbat_await_analysis`     | `{ conversationId: uuid \| obprobe_… }` — poll until analyzed |
| `openbat_analytics_overview` | `{ chatbotId: uuid }` |
| `openbat_analytics_sentiment` | `{ chatbotId: uuid, days?: 1-90 }` |
| `openbat_review`             | `{ chatbotId: uuid, windowMinutes?: 1-43200 }` |

If the MCP server is pinned with `OPENBAT_CHATBOT_ID`, per-chatbot tools can omit `chatbotId`; otherwise pass the id returned by `openbat_list_chatbots`.

## Filter recipes

```bash
# Show only the highest-impact conversations of the last week
openbat conversations list --days 7 --limit 50 --json | jq '.[] | select(.message_count >= 10)'

# Pipe into an LLM prompt
openbat conversations show $CONV_ID --json | jq '.messages[] | {role, content}'
```

## Per-message analyses

`openbat conversations show` returns each message with **all** of its analyses:
`user_sentiments`, `user_intents`, `user_flags`, `assistant_outcomes`, and
`assistant_issues` — each carrying its `reasoning` plus verification fields
(`verification_source`, `answer_available`, `verification_type`, `severity`).
This is how you read **why** a message was flagged.

For the aggregate "what went wrong over a window" view (top issues / flags /
outcomes with deltas + representative pointers), use `openbat review` and the
**`openbat-optimize`** skill.

## Gotchas

- Conversations are sorted by `last_message_at` desc with NULL last.
- Messages within a conversation are sorted by `created_at` asc, then by
  role priority for same-second ties (user before assistant).
- The 200-row registry cap applies everywhere — paginate via `page` and
  `limit`.
