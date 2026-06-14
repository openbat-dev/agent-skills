---
name: openbat-eval
description: "Run the ACTIVE eval loop on a chatbot: send synthetic test queries (`openbat probe` / `openbat eval`), let OpenBat analyze them, read the verdict, and validate fixes with a before/after regression diff — all isolated from organic analytics. Use when the user wants to 'test my chatbot', 'send test queries', 'probe my bot', 'run an eval suite', 'check my chatbot before shipping', 'did my prompt fix work', 'regression test the chatbot', or to validate a fix surfaced by openbat-optimize. Pairs with openbat-optimize (diagnose) — this is the validate half."
source: project
date_added: "2026-06-01"
---

# OpenBat — Active eval loop (probe → analyze → verdict)

OpenBat is a passive observability layer over your REAL traffic. This skill adds
the **active** half: you drive the chatbot with synthetic test queries, OpenBat
captures + analyzes them, and you read the verdict — to validate a fix *before*
shipping, or to regression-test a suite.

**Architecture (important):** OpenBat never calls your chatbot — it can't reach
it. YOU (the agent, in the repo) issue the chatbot call; OpenBat owns the eval
leg: synthetic isolation, deterministic await, and the verdict. The chatbot's own
`@openbat/sdk` integration captures the turn.

## 0. Scope + adapter

```bash
openbat auth whoami        # confirm ONE active chatbot (pin with `openbat use <id>` if a PAT spans many)
```

To let the CLI drive your chatbot, declare an adapter once at the repo root —
`openbat.probe.json` (how to call your chatbot; `{{conversationId}}` and
`{{message}}` are substituted):

```json
{
  "url": "http://localhost:3000/api/chat",
  "method": "POST",
  "headers": { "content-type": "application/json" },
  "body": {
    "conversationId": "{{conversationId}}",
    "messages": [{ "role": "user", "content": "{{message}}" }]
  }
}
```

No adapter? `openbat probe "..."` still mints the correlated id and prints the
exact call for YOU to issue, then you `openbat conversations await <id>`.

## 1. Single probe

```bash
openbat probe "how do I get a refund?"          # drive → await → verdict
openbat probe "..." --no-wait                    # just send; await later
openbat conversations await <obprobe_id|uuid>    # block until fully analyzed
```

`probe` generates a reserved `obprobe_<uuid>` conversationId → the server
classifies the conversation as `kind=probe` (excluded from organic
analytics/review) → it awaits analysis → prints the verdict (intents, flags,
outcome, issues, `answer_available`). Map the verdict to a lever exactly as in
the **`openbat-optimize`** skill (the `answer_available` × `verification_source`
table).

## 2. Eval suite + regression diff

A suite is `.json` (`{ "items": [{ "id", "question", "expect"? }] }`, max 100) or
one-question-per-line `.txt`. `expect` assertions (all must hold to pass):
`intent`, `outcome` (e.g. `resolved`), `no_flags: [...]`.

```bash
openbat eval run --suite golden.json --out before.json
#   …apply your fix (prompt / tools / retrieval)…
openbat eval run --suite golden.json --out after.json
openbat eval diff before.json after.json    # surfaces regressions + fixes; exit 1 on regression
```

## 3. Test a candidate prompt WITHOUT shipping

```bash
openbat prompts render --file new-prompt.txt --var company=Acme  # local variable preview
openbat prompts stage --file new-prompt.txt                      # creates a version, NOT live
openbat eval run --suite golden.json --candidate <versionId>     # chatbot runs staged version
openbat prompts activate <versionId>                             # ship only once eval is clean
```

`render` detects `{{variable}}` placeholders, supports names with dots/hyphens
(`{{user.name}}`, `{{plan-tier}}`), and reports missing values before the eval
burns tokens. `create-draft` is the legacy alias for `stage`; prefer `stage` in
new agent output.

The chatbot must fetch the candidate via the SDK's
`client.prompts.getSystem({ versionOverride })` — forward the `{{candidate}}`
adapter field as a header your
route reads. Repo-hardcoded prompts: just edit the prompt locally and probe.

## 4. MCP equivalents

`openbat_probe` (returns a probe id + next steps) → send to your chatbot →
`openbat_await_analysis { conversationId }` (poll until `allComplete`; accepts the
`obprobe_` id) → `openbat_get_conversation` (read the verdict). `eval` itself is
client-orchestrated (file I/O + loop), so under MCP you compose it from those
tools. Use `openbat_render_prompt_template` for the same local variable preview
when operating through MCP. `openbat_optimize_context` bootstraps the loop in
one call.

## Gotchas / safety rails

- **Synthetic isolation is the point** — probes are `kind=probe`, hidden from
  `review`/analytics. Inspect them with `openbat conversations list --synthetic`.
  Never assert prod metrics changed because of a probe run.
- **`answer_available`** is load-bearing — never "fix the prompt" for a
  `missing_knowledge` verdict (author the doc instead). See `openbat-optimize`.
- **Suite cap is 100** — an eval run amplifies LLM cost (each item = a chatbot
  turn + analysis). Keep suites focused on the failures you're fixing.
- **The chatbot must forward `conversationId`** to `recordMessages` for the probe
  prefix to classify it; apps that mint ids server-side should pass
  `kind: "probe"` explicitly to the SDK.
- **Confirm before shipping** — `prompts activate` / `publish` change the live
  prompt; repo edits go through a PR. Ship only on a clean eval/diff.
