---
name: openbat-sdk-install
description: "Install and verify the @openbat/sdk in a target Node.js / Next.js / Vercel AI SDK app, capturing conversations to an OpenBat chatbot."
source: project
date_added: "2026-05-13"
---

# OpenBat — Install the SDK in production

## Fastest path — `openbat init` / `openbat wizard`

Two CLI front doors automate the manual steps below:

- **`openbat init`** (alias of `openbat onboard`) — deterministic, no LLM.
  Resolves/creates a chatbot, enables analysis, prints the paste-ready SDK
  snippet, then polls for the first event. Add `--create "<name>"` to mint a
  fresh chatbot + ingest key in one shot.
- **`openbat wizard`** — drives the user's OWN installed coding agent
  (Claude Code / Codex / Gemini / Cursor / opencode / aider) to wire the SDK
  into the project. It **refuses (exit 1) if no agent is installed**,
  auto-launches `openbat login` if unauthenticated, writes
  `OPENBAT_API_KEY` to `.env.local` (mode 0600, never on the agent's argv),
  installs this skill bundle for the agent, then runs `openbat sdk verify`.
  Flags: `--agent <id>`, `--create <name>`, `--dir <path>`, `--stack <hint>`,
  `--no-verify`, `--dry-run`.

Prefer these for new integrations; the manual steps below are the fallback /
reference (and what the wizard's agent follows).

## Prereq

A chatbot must exist + you need its **ingest key** (`ob_live_*`).
Either capture it at create time (`openbat chatbots create`) or rotate
a fresh one via `openbat settings keys rotate-ingest --chatbot $CB`.

## Install

```bash
npm install @openbat/sdk
```

## Environment

Add the ingest key to the target app's `.env.local` (chmod 600):

```
OPENBAT_API_KEY=ob_live_…
```

## Wire-up — Next.js / Node.js

```ts
import { OpenBat } from "@openbat/sdk";

const openbat = new OpenBat({
  apiKey: process.env.OPENBAT_API_KEY!,
});

// After each LLM turn (server action, route handler, etc.):
await openbat.recordMessages({
  conversationId,         // your own stable id per conversation
  user: { id: userId },   // optional but recommended
  messages: [
    { role: "user", content: userText },
    { role: "assistant", content: assistantText },
  ],
});
```

`recordMessages` is fire-and-forget safe — network errors are swallowed
to the console, never thrown to your handler. Latency is dominated by
the response time of the OpenBat ingest endpoint.

To observe failures (e.g. alert on `401`/`429`) without breaking the
never-throw contract, pass `onError` to the constructor — it receives only
`{ phase, status?, code? }` (never the response body), and anything it throws
is caught:

```ts
const openbat = new OpenBat({
  apiKey: process.env.OPENBAT_API_KEY!,
  onError: ({ phase, status, code }) => {
    console.warn(`openbat capture failed: ${phase} ${status ?? ""} ${code ?? ""}`);
  },
});
```

## Wire-up — Vercel AI SDK

```ts
import { OpenBat, withOpenBat } from "@openbat/sdk";
import { streamText } from "ai";

const result = streamText({ model, system, messages });

return withOpenBat(result.toDataStreamResponse(), {
  apiKey: process.env.OPENBAT_API_KEY!,
  conversationId,
  messages,
});
```

`withOpenBat` auto-captures the streamed messages — no manual
`recordMessages` call needed.

For tool-using or skill-using chatbots, prefer an explicit `recordMessages`
call in the model's `onFinish` callback. The wrapper cannot see tool calls,
reasoning, loaded skills, or retrieved policy snippets.

## Verify

```bash
openbat sdk verify --chatbot $CB --timeout 60
# Polls /api/v1/conversations until total > 0 or timeout.
# Exit 0 on success; exit 2 on timeout.
```

The CLI runs against a **read** or **admin** key (not the ingest key
used by the SDK — keep those separate).

## Optional — OpenBat-managed system prompts

```ts
const promptVariables = {
  company: "Acme",
  "user.name": "Nina",
  "plan-tier": "pro",
};

const { text: system, template, missingVariables } =
  await openbat.prompts.getSystem({
    fallback: HARDCODED_PROMPT,
    variables: promptVariables,
    conversationId,
  });

if (missingVariables.length > 0) {
  throw new Error(`Missing prompt variables: ${missingVariables.join(", ")}`);
}

const result = streamText({
  model,
  system,
  messages,
  onFinish: async ({ text }) => {
    await openbat.recordMessages({
      conversationId,
      systemPromptTemplate: template,
      systemPromptVariables: promptVariables,
      messages: [
        { role: "user", content: userText },
        { role: "assistant", content: text },
      ],
    });
  },
});

return result.toUIMessageStreamResponse();
```

`client.prompts.getSystem()` returns rendered `text`, the unrendered `template`
that should be sent back as `systemPromptTemplate`, the `source` (`remote`,
`cache`, `fallback`, or `kill_switch`), and `missingVariables`. Variable names
may include dots and hyphens. Missing variables are reported and left as
`{{name}}` rather than silently blanked.

For production apps with a database, prefer the SDK's `onPromptStateChange`
callback pattern: OpenBat pushes dashboard prompt updates back through the
existing capture response, your app upserts the prompt into its own DB, and
future requests read locally. Use `prompts.getSystem()` when you need the
single-line runtime-fetch path or cannot host a prompt table.

## Optional — skill-aware verification

If the chatbot loads skills, policies, playbooks, or tool-fetched instructions,
capture them on assistant messages:

```ts
await openbat.recordMessages({
  conversationId,
  messages: [{
    role: "assistant",
    content: assistantText,
    tools,
    reasoning,
    skills: [{ source: "external", name: "refund-policy", version: "v3" }],
    behaviorEvidence: [{
      type: "external_skill_observed",
      source: "kb.search",
      name: "Refund policy",
      text: "Annual refunds require support approval.",
    }],
  }],
});
```

OpenBat also mines tool output and reasoning for policy-like evidence when
`skills`/`behaviorEvidence` are absent, but explicit fields improve root-cause
labels like ignored skill, stale skill, missing skill, or tool/data wrong.

## Gotchas

- The SDK uses ONLY the ingest key. Never paste `ob_read_*` /
  `ob_admin_*` / `ob_pat_*` into the SDK config.
- `recordMessages` retries: zero. If you need durability, pair with
  Vercel Workflow DevKit or a queue.
- Custom metadata (user / organization / session / custom maps) auto-
  populates discovered metadata fields — accept them in the dashboard
  for analysis to start using them.
