---
name: openbat-sdk-install
description: "Install and verify the @openbat/sdk in a target Node.js / Next.js / Vercel AI SDK app, capturing conversations to an OpenBat chatbot."
source: project
date_added: "2026-05-13"
---

# OpenBat — Install the SDK in production

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

## Wire-up — Vercel AI SDK

```ts
import { OpenBat, withOpenBat } from "@openbat/sdk";
import { streamText } from "ai";

const openbat = new OpenBat({ apiKey: process.env.OPENBAT_API_KEY! });

const result = await withOpenBat(openbat, { conversationId }, () =>
  streamText({ model, system, messages }),
);
```

`withOpenBat` auto-captures the streamed messages — no manual
`recordMessages` call needed.

## Verify

```bash
openbat sdk verify --chatbot $CB --timeout 60
# Polls /api/v1/conversations until total > 0 or timeout.
# Exit 0 on success; exit 2 on timeout.
```

The CLI runs against a **read** or **admin** key (not the ingest key
used by the SDK — keep those separate).

## Optional — server-managed system prompts

```ts
const { template, source } = await openbat.getSystemPrompt({
  fallback: HARDCODED_PROMPT,
  conversationId,
  // mode: "instant_fallback" returns fallback immediately, fetches in BG
});
```

This lets you publish prompt versions from the dashboard's experiments
flow without redeploying the app.

## Gotchas

- The SDK uses ONLY the ingest key. Never paste `ob_read_*` /
  `ob_admin_*` / `ob_pat_*` into the SDK config.
- `recordMessages` retries: zero. If you need durability, pair with
  Vercel Workflow DevKit or a queue.
- Custom metadata (user / organization / session / custom maps) auto-
  populates discovered metadata fields — accept them in the dashboard
  for analysis to start using them.
