# The reliability eval loop — measure it, and trust the measurement

Distilled from multiple chatbot-reliability programs that each used a conversation-analysis layer as the eval oracle. The throughline: a tight **run → analyze → fix → re-run** loop turns "the bot feels off" into a ranked, shrinking list of root causes — *but only if the oracle sees what the model saw.* Half of these programs' late-stage effort was spent discovering that the measurement, not the chatbot, was the bug.

## Table of contents

- [The loop](#loop)
- [The oracle's blind spots (read this first)](#oracle)
- [Real-bug vs. false-positive triage](#triage)
- [Harness pitfalls that fake your score](#harness)
- [Knowing when to stop (out-running the oracle)](#stop)
- [What good analyzer output gives you](#analyzer-output)

---

<a name="loop"></a>
## The loop

```
fire N diverse, categorized queries
   → analyze each captured turn (issues + outcomes), async
   → read every conversation's flags
   → bucket genuine issues by root cause + category
   → fix the top root cause
   → re-run the SAME N
   → compare the distribution
```

- **Keep N and the query set fixed across campaigns.** The bot is non-deterministic, so the per-category mix shifts run to run (a query clean in one run flags in the next). The **aggregate trend** is the signal, not any single cell.
- **Categorize the queries** (aggregates, drill-downs, trends, out-of-scope declines, grounding traps, multi-step…) so you can see *which kind* of question fails.
- **Fix the top cause, then re-run** — don't fix ten things at once, or you can't attribute the delta. One structural fix (e.g. a single digest) is often worth more than all the prompt tweaks combined.
- **A fast smoke loop** (a handful of probes) is for quick iteration between full campaigns.
- **Isolate eval traffic** from organic analytics (a probe prefix / synthetic flag) so test runs don't pollute the dashboards, `review`, or real metrics.

What you're buying: the loop converts vibes into a measured, shrinking, ranked list — and *proves* the fix worked, instead of asserting it.

<a name="oracle"></a>
## The oracle's blind spots (read this first if you're building the audit)

**The single biggest source of false positives is the analyzer not seeing what the model saw.** Two concrete, recurring cases:

1. **System-prompt variables / registry.** Before the analyzer receives the chatbot's configured entities (competitors, personas, brands, plans), it flags *real, configured* entities as hallucinations. Feeding it the rendered variables/registry takes entity/persona false-positives to zero. Pass entity **names** plus a compact registry as first-class grounding — not just the unrendered template with scalar variables.
2. **Tool outputs, not just tool names.** A bot that correctly answers from a knowledge tool is still flagged "misinformation" if the analyzer sees the tool *call* but never the tool **output** — it judges a grounded fact against nothing. Verify each claim against the tool output the model actually cited.

**Prerequisite for a trustworthy audit:** ingest and ground against (a) the rendered system prompt + its variables and (b) tool **outputs**. Otherwise the audit punishes the exact correct behavior it should reward (routing to a tool instead of inventing), inflates the count, and buries real bugs.

Corollary self-checks for the analyzer:
- If the rationale **affirms** the claim ("accurate to the tool data") yet still emits an issue → suppress it (self-contradiction). A second pass — "does your reasoning actually contradict the claim?" — catches these.
- Don't score a correct, grounded, explanatory answer as a `failed` outcome just because it has no numeric "success" target. Add an `informational`/`answered` outcome.
- Populate the correct value (`answer_available`) on `contradicts` findings so fix→re-run loops can **auto-grade** before/after instead of re-reading prose.
- Surface `nature` (contradicts vs. fabricates) in the digest — it's the most useful root-causing signal: *contradicts* → mis-transcription → fix the digest; *fabricates* → invention → fix the prompt/registry.

<a name="triage"></a>
## Real-bug vs. false-positive triage

**Classify before you fix.** An "issue rate" is meaningless until split into real-bug vs. false-positive. In one program the ratio was about **1 real bug : 40 false positives** — almost all the optimization energy of several phases had been spent fighting ghosts.

Common false-positive classes to recognize (and *not* chase to zero):
- **Inapplicable rubrics.** Support-bot analyses (upsell, brand voice, over-apologizing, "yes-man") fire meaninglessly on an internal analytics assistant. Disable them on that chatbot's analysis definitions.
- **Rendered UI judged as prose.** Fenced chart/table markup the user sees as a rendered chart gets flagged "robotic" or "raw pseudo-code." Teach the analyzer that those blocks are legitimate rendered UI.
- **"The bot wrongly said X" vs. "X is true."** When the bot's *job* is to surface another bot's failures, the analyzer can't tell a correct quote-of-a-bad-answer from the bot itself being wrong. Have the bot **characterize, don't reproduce** — and track these as FPs.
- **Correct, grounded answers flagged because the oracle was blind** (see above).

Track the real-vs-FP split over time; the *composition* of the issue rate matters more than the number.

<a name="harness"></a>
## Harness pitfalls that fake your score

These silently corrupt the measurement — check them before trusting any number:

- **A missing/failed capture must be an ERROR, never a PASS.** A runner that counts requests with no captured conversation as "clean" will score a fully broken bot (returning 500s) as **100% clean**. This is the most dangerous harness bug.
- **Capture truncation hides grounding from the verifier.** If you truncate tool outputs to fit a capture endpoint's size caps, the verifier never sees the values the model legitimately cited and flags **grounded answers as hallucinations**. In one case ~two-thirds of "hallucinations" were this. Send full tool context; raise the caps instead of truncating.
- **Capture loss looks like concurrency but is often caps.** Silent drops were field-size limits (oversized tools/reasoning/content blobs rejected), plus fire-and-forget writes dropped under load. Bound the fields deterministically *and* await the write.
- **Corrupt/inconsistent seed data manufactures phantom hallucinations.** If one entity id carries several different names, the analyzer's reference differs from the tool the model used, and you get unlimited fake "hallucinations." Run a `count(distinct name) per id` sanity check on your test data *first*.
- **Measure the live prompt, not a stale one.** If prompt propagation is callback/capture-driven, a campaign can silently measure the old prompt. Warm up until the live version matches the published one before counting.
- **Apply the fix to the tool the model actually uses** — confirm which tool answered, or a correct fix lands on the wrong surface and the bug persists.

<a name="stop"></a>
## Knowing when to stop (out-running the oracle)

Every one of these programs converged on the same endpoint: **the chatbot's true error rate drops below the analyzer's own false-positive rate.** By the final pass, roughly *half* the analyzer's flags were false positives on *correct* answers, and the genuine residual was a handful of minor, scattered issues with **no cluster** — a counting slip, one near-tied ranking, a lone fabricated string, a couple of style nits.

When you reach that state:
- Further prompt rules are low-ROI — you're chasing a non-deterministic noise floor.
- The next leverage is the **analyzer**, not the chatbot (better grounding inputs, severity calibration, disabling inapplicable rubrics).
- Recognize it explicitly so you stop grinding the bot against ghosts.

A healthy trajectory looks like: a dominant cluster (one root cause producing most issues) → fix it structurally → the cluster collapses → the residual is a scattered tail → the remaining flags are mostly FPs. Clusters mean a structural bug; a scattered tail means you're basically done.

<a name="analyzer-output"></a>
## What good analyzer output gives you (so triage is cheap)

To make the loop auto-gradable and the triage fast, the analysis layer should provide:
- **`nature`** (contradicts vs. fabricates) surfaced in the aggregate digest, not just per-conversation — it routes the fix.
- **`answer_available`** (the correct value) populated on `contradicts` findings, so before/after can be auto-graded.
- **Severity/impact calibration** — an off-by-one on a minor source is not a wholesale fabrication; if everything returns `high`, triage is impossible.
- **An outcome rubric** that includes `informational`/`answered`, so a correct explanatory answer with no numeric target isn't scored `failed`.
- **Tool calls + outputs exposed** on conversation reads, so you can confirm grounding from the CLI instead of inferring it from the answer text.

The endgame for the numbers themselves is **proof-carrying values** (a model-emitted reference bound to a tool output, resolved fail-closed) — but note the binding must be **number → entity**; naive number-presence matching is too weak to catch the real fabrications.
