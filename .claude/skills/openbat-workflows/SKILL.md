---
name: openbat-workflows
description: "Create OpenBat workflows from a built-in DSL — e.g. fire a webhook when a user message is flagged or an assistant outcome matches a value. Triggers on workflow / webhook / trigger / DSL / xyflow questions in an OpenBat context."
source: project
date_added: "2026-05-13"
---

# OpenBat — Workflows via DSL templates

Agents don't author xyflow graphs by hand. The CLI/MCP accept a thin
template input and compile it to the `(nodes, edges, trigger_type)` shape
the dashboard editor renders.

## Templates (v1)

| Template | Triggers when | Use for |
|----------|---------------|---------|
| `flag-to-webhook` | A user message gets a flag analysis of value X | Slack/Discord alerts on customer issues |
| `outcome-to-webhook` | An assistant message gets outcome value X | Notify on resolved / escalation outcomes |
| `sentiment-drop-to-webhook` | Org avg sentiment crosses threshold (number in [-1, 1]) | Account-health alerts |

## Prereq

You need a `webhook` row first:

```bash
openbat webhooks create --chatbot $CB --name slack-ops \
  --url https://hooks.slack.com/services/T.../B.../X --type slack
# stderr: signing secret (shown once)
# stdout: { id: "...", ... }
```

## Create

```bash
openbat workflows create --chatbot $CB \
  --name "billing flag → slack" \
  --template flag-to-webhook \
  --trigger-value billing_issue \
  --webhook $WEBHOOK_ID \
  --message "User flagged billing: user={{user.id}} conv={{conversation.id}}"
```

MCP: `openbat_create_workflow_from_template` with the same fields.

`messageTemplate` supports `{{user.id}}`, `{{conversation.id}}`,
`{{flag.value}}`, `{{org.avgSentiment}}` etc. — the workflow runtime
interpolates from the analysis context.

## Listing

```bash
openbat workflows list --chatbot $CB
```

## Power-user mode (raw nodes/edges)

The registry exposes `update_workflow` with raw xyflow JSON. The DSL
covers ~90% of use cases — drop to raw nodes only when you need
branching or non-webhook actions.

## Gotchas

- The webhook id passed to `--webhook` must exist on the same chatbot.
  Cross-chatbot references fail at runtime.
- `--trigger-value` must match the analysis-definition `name` (slug)
  for flags/outcomes, or a `[-1, 1]` float for sentiment.
- The compiled workflow starts **enabled**. To disable, edit via the
  dashboard or raw `update_workflow`.
