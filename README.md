# OpenBat agent skills

[![skills.sh](https://skills.sh/b/openbat-dev/agent-skills)](https://skills.sh/openbat-dev/agent-skills)

Procedural knowledge for AI agents working with [OpenBat](https://openbat.dev) —
distillable into Claude Code, Cursor, Copilot, Gemini, and any
Claude-compatible MCP client via the [skills.sh](https://skills.sh)
distribution mechanism.

These skills teach an agent how to use the OpenBat CLI
([`@openbat/cli`](https://www.npmjs.com/package/@openbat/cli)), the
OpenBat MCP server ([`@openbat/mcp`](https://www.npmjs.com/package/@openbat/mcp)),
and the OpenBat SDK ([`@openbat/sdk`](https://www.npmjs.com/package/@openbat/sdk))
end-to-end — read analytics, manage settings and webhooks, build
workflows, mint credentials, run experiments, install the SDK in a
target app.

## Install

```bash
npx skills add openbat-dev/agent-skills
```

By default this drops the skill files into `.claude/skills/` in your
current project. Target a different agent platform with `-a`:

```bash
npx skills add openbat-dev/agent-skills -a cursor
npx skills add openbat-dev/agent-skills -a copilot
```

Install one specific skill only:

```bash
npx skills add openbat-dev/agent-skills --skill using-openbat
```

Pin a specific version (recommended for reproducibility):

```bash
npx skills add openbat-dev/agent-skills@v0.1.0
```

## What's included

| Skill | Purpose |
|---|---|
| [`using-openbat`](.claude/skills/using-openbat) | **Start here.** Comprehensive reference — auth model, 10 user flows, MCP + CLI command pairs, safety rails, failure-mode recovery. |
| [`openbat-onboarding`](.claude/skills/openbat-onboarding) | Create a new chatbot + capture the ingest key. |
| [`openbat-settings`](.claude/skills/openbat-settings) | Manage keys (ingest / read / admin / PAT), webhooks, custom metadata. |
| [`openbat-conversations`](.claude/skills/openbat-conversations) | Query conversations + analyses, time-filtered (default last 7 days). |
| [`openbat-optimize`](.claude/skills/openbat-optimize) | Daily eval → fix loop: pull the `openbat review` digest of recent failures, map each cluster to a lever (prompt / tools / retrieval / new analysis / alert), apply fixes in the chatbot's repo. |
| [`openbat-workflows`](.claude/skills/openbat-workflows) | Compile DSL templates (`flag-to-webhook`, `outcome-to-webhook`, `sentiment-drop-to-webhook`) into workflows. |
| [`openbat-sdk-install`](.claude/skills/openbat-sdk-install) | Install + verify `@openbat/sdk` in Node / Next.js / Vercel AI SDK apps. |
| [`openbat-safe-mutations`](.claude/skills/openbat-safe-mutations) | Cross-cutting safety rules — confirmation patterns, audit log review, key rotation hygiene. |
| [`openbat-plan-audit`](.claude/skills/openbat-plan-audit) | Audit implementation plans against recurring failure patterns (cross-tenant IDOR, missing rate limits, missing role checks, SSRF, race conditions, input validation). |

## Prereqs

Install at least one of the OpenBat surfaces first:

```bash
npm i -g @openbat/cli              # CLI
# or configure MCP in your client's mcp.json — see @openbat/mcp README
```

You'll also need an OpenBat API key. Sign up at https://openbat.dev to mint one.

## Why these are skills

`@openbat/cli` and `@openbat/mcp` are intentionally generic — they
expose 44 tools across 9 user flows. An agent confronted with all 44
tools and no procedural guidance will plausibly hallucinate inputs,
choose the wrong key kind, or call destructive operations without
confirmation.

The skills here distil the "how to use this safely" knowledge into the
agent's context window when it's loaded. They cover:

- The four-kind auth ladder (`ob_read_*` < `ob_admin_*` < `ob_pat_*`).
- Plaintext-shown-once-to-stderr conventions for mint commands.
- The `dryRun` safety pattern for destructive operations.
- The org-private nature of AI reports (no public sharing).
- Audit log + rate-limit recovery patterns.

## Format

Each skill is a single `SKILL.md` file with YAML frontmatter, following
the [agent-skills](https://github.com/vercel-labs/skills) spec:

```yaml
---
name: skill-name
description: One-paragraph triggers + scope summary
---

# Skill body...
```

## Versioning

Tagged releases (`v0.1.0`, `v0.2.0`, …) track the published versions of
`@openbat/cli` and `@openbat/mcp` they're written against. Bumping the
tools without bumping the skills is fine — the skills are deliberately
not coupled to specific tool signatures, just to the patterns
(`requireWrite`, BOLA filter, etc.). But if the auth ladder changes
shape, the skills bump too.

## Contributing

These skills are maintained as a thin export from the
[`openbat/openbat`](https://openbat.dev) monorepo's `.claude/skills/`
directory. Bug reports + suggestions:
[issues](https://github.com/openbat-dev/agent-skills/issues).

PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

## See also

- **OpenBat product** — https://openbat.dev
- **OpenBat docs** — https://openbat.dev/docs
- **`@openbat/cli`** — https://www.npmjs.com/package/@openbat/cli
- **`@openbat/mcp`** — https://www.npmjs.com/package/@openbat/mcp
- **`@openbat/sdk`** — https://www.npmjs.com/package/@openbat/sdk
- **skills.sh directory** — https://skills.sh
- **agent-skills CLI** — https://github.com/vercel-labs/skills
