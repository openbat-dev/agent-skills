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

# Detail (messages + per-message sentiments):
openbat conversations show <conversationId>

# Analytics:
openbat analytics overview
openbat analytics sentiment --days 30
```

## MCP

| Tool | Args |
|------|------|
| `openbat_list_conversations` | `{ page?, limit? }` |
| `openbat_get_conversation`   | `{ id: uuid }` |
| `openbat_analytics_overview` | `{}` |
| `openbat_analytics_sentiment` | `{ days?: 1-90 }` |

## Filter recipes

```bash
# Show only the highest-impact conversations of the last week
openbat conversations list --days 7 --limit 50 --json | jq '.[] | select(.message_count >= 10)'

# Pipe into an LLM prompt
openbat conversations show $CONV_ID --json | jq '.messages[] | {role, content}'
```

## Per-message analyses

`openbat conversations show` returns each message with its `user_sentiments`
array. For deeper per-analysis-type queries (intents, flags, outcomes,
issues), use the platform chat's tools — they expose dedicated query
endpoints scoped to a chatbot.

## Gotchas

- Conversations are sorted by `last_message_at` desc with NULL last.
- Messages within a conversation are sorted by `created_at` asc, then by
  role priority for same-second ties (user before assistant).
- The 200-row registry cap applies everywhere — paginate via `page` and
  `limit`.
