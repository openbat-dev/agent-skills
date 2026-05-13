# Contributing

These skills are exported from the upstream
[`openbat/openbat`](https://openbat.dev) monorepo's
`.claude/skills/` directory. The canonical edits happen there; this
repo is the distribution surface.

## Reporting a problem

Open an issue at https://github.com/openbat-dev/agent-skills/issues
with:

- Which skill (`using-openbat` / `openbat-onboarding` / ...)
- What the agent did vs. what you expected
- Optional: the prompt that triggered it

## Proposing a change

Two paths:

### Path 1 — Open a PR here (best for small fixes)

```bash
git clone https://github.com/openbat-dev/agent-skills && cd agent-skills
# edit .claude/skills/<name>/SKILL.md
git checkout -b fix/<short-description>
git commit -am "<concise message>"
gh pr create
```

A maintainer will mirror the change back to the upstream monorepo.

### Path 2 — PR against the upstream monorepo (best for new skills)

Edit `.claude/skills/<name>/SKILL.md` in
[`openbat/openbat`](https://openbat.dev) and open a PR there. The skill
will land in this repo on the next sync.

## Skill format

Every skill is a single `SKILL.md` file with YAML frontmatter, per the
[agent-skills](https://github.com/vercel-labs/skills) spec.

```yaml
---
name: skill-name
description: |
  One-paragraph description that's specific about when this skill should
  trigger. The CLI uses this to surface the skill in search; agents use
  it to decide whether to load the full body into context.
---

# Skill Body

Sections, code blocks, and tables that teach an agent how to do the
thing. Cite the underlying CLI commands / MCP tools / v1 routes by
name. Don't include real API keys — use sentinels like
`ob_pat_EXAMPLE000…`.
```

### Required fields

- `name` — lowercase, hyphens allowed. Must match the directory name.
- `description` — what the skill does + when to use it.

### Optional fields

- `metadata.internal: true` — hide from the skills.sh leaderboard.
- `metadata.tags: tag1, tag2` — searchable tags.

### What NOT to put in a skill

- Real API keys (CI greps for `ob_(live|read|pat|admin)_[a-f0-9]{32}`).
- Customer data.
- One-off plans or to-do lists (those belong in PR descriptions, not skills).

## Versioning

Tagged releases (`v0.1.0`, `v0.2.0`, …) snapshot the skill set against
specific versions of `@openbat/cli` / `@openbat/mcp`. Bump when:

- A skill's recommended commands or tools change.
- A new skill is added.
- A skill is removed or renamed (major bump).

Patch bumps for typo fixes and clarifications.

## Local development

You can test a skill before publishing by symlinking it into a target
project's `.claude/skills/` directory:

```bash
ln -s /path/to/agent-skills/.claude/skills/using-openbat \
      /path/to/target-project/.claude/skills/using-openbat
```

Then start a Claude Code session in the target project and ask the
agent to do something OpenBat-related. The skill should auto-trigger
based on its `description`.

## Code of conduct

Be kind, be specific, and remember the audience is an LLM that will
load your words into its context window — so write for clarity, not
for cleverness.
