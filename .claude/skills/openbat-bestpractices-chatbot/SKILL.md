---
name: openbat-bestpractices-chatbot
description: Field-tested best practices and fundamental truths for making data/analytics LLM chatbots and agents over SQL, tools, or structured data reliable and hallucination-resistant. Reach for it when building, debugging, reviewing, or hardening such a bot whose answers can't be trusted — it makes up numbers (amounts, counts, percentages, averages, growth rates), invents competitors/entities/plans/terms not in the data, gets rankings backwards, pins a real number to the wrong entity or metric, returns empty answers, or leaks tool names — even if the user never says "hallucination" (they may just say it "makes stuff up" or "feels off"). Also use for design calls — how to shape what a tool or digest returns to the model, compute math in code vs. in the model, prompt rule vs. structural fix, grounding to real entities, or standing up an eval loop to prove reliability. Durable grounding guidance — pairs with openbat-optimize (live diagnosis) and openbat-plan-audit (security).
metadata:
  tags: chatbot, reliability, hallucination, grounding, tool-design, eval, best-practices, analytics, agents
---

# openbat-bestpractices-chatbot

A distilled, vendor-neutral reference for making LLM chatbots and agents that answer **over tools and structured data** reliable. These are durable engineering principles, each with the *why* behind it, so you can apply them to a tool/digest/prompt you've never seen before — not a checklist to follow blindly.

The patterns here were compiled from multiple real chatbot-reliability programs that each drove a hallucination-prone analytics assistant down to a small, scattered residual using a conversation-analysis eval loop. The striking finding across all of them: **every data chatbot fails in the same handful of ways, and the same handful of fixes work.**

## The one truth everything else follows from

> **Hallucination over structured data is a *grounding* problem, not a *model* problem.**

A capable model invents a number, an entity, or a positioning statement when the thing it needs *isn't in front of it* — the field was hidden, the source didn't exist, the arithmetic was left to it, or the label was ambiguous. The fix is almost never "a better model" or "one more prompt rule." It is **changing what the model sees** so the truth is the path of least resistance. When a digest hides a field, the model fills the gap with a plausible guess.

The corollary, equally important:

> **Your eval oracle must see the same grounding the model saw** — the rendered system prompt + its variables/registry *and* the tool **outputs** (not just the tool names). Otherwise it flags truthful, grounded answers as hallucinations, inflates your issue count, and buries the real bugs.

## When to invoke

Use this skill when the user is:

- Building, designing, or reviewing a chatbot/agent that answers over tools, SQL, analytics, documents, or any structured data.
- Debugging symptoms like: invented or miscomputed numbers, fabricated entities/competitors/plans/terms, sentiment or ranking that's wrong in a *systematic* way, the bot quoting the wrong field, empty/silent replies, the bot telling users to "call `getFooBar`," or unsolicited charts.
- Deciding a tool's **return shape** or a **digest** the model will read, or whether to compute something **in code vs. let the model derive it**.
- Weighing a **system-prompt rule vs. a structural fix**.
- Standing up an **eval loop** to measure and prove chatbot reliability.

Even if the user doesn't say "hallucination" — if they say the bot "makes stuff up," "gets numbers wrong," "feels off," or "isn't trustworthy," this is the skill.

This is the *reliability/grounding* reference. For diagnosing a specific live chatbot from its captured conversations, pair with **openbat-optimize**. For security review of an implementation plan, use **openbat-plan-audit**.

## How to use this skill

1. Read the **fundamental truths** below — they're the principles you'll reason from.
2. When you have a concrete symptom or a tool/digest in hand, open the matching reference for the detailed catalog:

   | You're dealing with… | Read |
   |---|---|
   | A specific failure symptom (wrong number, invented entity, bad ranking, empty answer, leaked tool name, forced chart…) and want symptom → root cause → durable fix | `references/failure-patterns.md` |
   | Setting up or fixing the measurement: run→analyze→fix→re-run, what the oracle must see, real-bug vs. false-positive triage, harness pitfalls | `references/eval-loop.md` |

3. Apply the **design checklist** at the end before shipping a tool, digest, or prompt change.

---

## The fundamental truths

Grouped by where the leverage is. Within each group, the highest-leverage principle comes first.

### A. Ground by construction (the model never derives what it can be handed)

**1. Compute in code, never in the model.** Any total, count, average, ratio, percentage, delta, rollup, or forecast must come from **one quotable tool field** computed deterministically (SQL or closed-form), not from the model's mental math over context. The model *selects* a metric and *narrates* it; it does not do arithmetic. This is the single highest-leverage move for any numeric agent — LLMs are unreliable at arithmetic and extrapolation over tabular context, and they fail *confidently*.

**2. Surface the authoritative field; don't make the model reconstruct it.** If a digest shows `pos X / neg Y` but hides the neutral bucket and the precomputed ratio, the model will invent the percentage (typically `pos/(pos+neg)`, silently dropping neutrals) and assume "all positive." Surface the computed value verbatim — the ratio, the neutral count, the total — with an explicit "cite this, don't recompute" note. Repeatedly, one incomplete digest is the *single largest* source of a chatbot's numeric errors; fixing it is the highest-ROI change available.

**3. Conventions must live in the shape of the data the tool returns — not in the prompt.** Prompt rules decay and the model drifts, especially on near-tied or adversarial cases. Every durable fix moves a convention *out of the prose and into the return shape*: a rollup row instead of "sum the leaves yourself," a sign-explicit field name (`netInflowCents`) instead of a prose rule about sign, a server-computed rank `(#k/N)` instead of "order these by value." **Don't instruct the model to compare — compute the comparison and have it read the result.** The prompt should then only have to say *which* tool to call.

**4. When you truncate, attach full-set aggregates.** Digests cap rows (say, 10 of N) for context economy. If you show a subset without exact full-set `count/mean/min/max/sum`, the model averages the *visible* rows and reports it as the whole. Append the complete-set aggregates (computed pre-truncation) to every truncated digest, and make the bot prefer them.

**5. Abstain below a threshold; never silently project.** A forecast/projection tool should self-fetch a clean series, do the date math in code (never trust the model's date arithmetic), fit a closed-form model, return scalars + confidence interval + a confidence score, and **abstain** below a data threshold. Forbid stating any projected number that didn't come from the tool.

### B. Tool & digest design (give the questions their dimensions)

**6. Add the dimensions the questions need; don't make the model derive them.** If users ask "spend at merchant X over €50 this year," the tool needs merchant/date/amount/direction filters — otherwise the model flails until it hits the step cap and answers nothing. Add **dimensions to one aggregate tool** (parent-category rollups, a transfers-only flag, a direction-in-the-user's-frame field) rather than sprouting a tool per question. Tool sprawl tempts flailing.

**7. Keep the tool surface small and purpose-built.** A model facing dozens of overlapping raw-row tools synthesizes across them and invents entities in the seams. A handful of **report tools** that each return the *whole* pre-joined, pre-aggregated answer for one intent (so the model narrates fields verbatim, no synthesis) plus one deterministic `calc()` tool beats a large registry. Prune aggressively.

**8. A smaller prompt grounds better than a bigger one.** Piling on grounding rules dilutes attention and does **not** close *structural* hallucination — if the model must synthesize to answer, no rule stops it. With the tools doing the grounding, a lean prompt (one clear rule + an answer shape) grounds better, faster, and cheaper than a sprawling one.

**9. Decoding helps at the margin; it is not the cure.** Low temperature and bounded thinking measurably reduce fabrication, but on structured-data hallucination they only move the needle — the cure is architectural (the tools above). Use decoding as a complement, never as the fix.

**10. Never sum across incompatible units.** Blindly adding amounts in different currencies (or any incompatible unit) produces a confident bogus total. Group every aggregate by unit in code; emit a single total only when one unit is present; surface "unknown unit" honestly.

**11. Fail loudly, not silently.** Distinguish "the fetch failed" from "there is no data" — error-masking gives the model false confidence in an absence. Paginate to completion rather than silently under-counting past a page limit. Add a test asserting every digest key exists in its data source's columns, so a casing/naming drift can't feed the model `NaN` it then reasons over.

### C. Entity & claim discipline

**12. Registry-only naming.** Never name a brand/competitor/provider/program/plan, or quote a tracked string, unless it appears verbatim in a tool result or an entity registry. Otherwise describe it generically. This kills invented competitors, fake program names, coined "platform terms," and quoted queries that don't exist.

**13. Ground entities by ID, not by value.** Two rows with the same amount are swappable if you key claims off the amount; key list/identity claims off the row **id**.

**14. Bind each value to its entity and metric, on the same line.** Cross-field confusion (a *real* number attached to the wrong metric or entity — "16 mentions" when citations were 2; theme A's size quoted for theme B) is invisible to "is this number anywhere in the output?" checks, because the number *is* real. Relabel digests so each count states exactly what it is, bind value to entity inline (`theme="X" size=N`), and add "do not conflate" notes (`citations ≠ mentions`, `ratio ≠ count breakdown`).

**15. Forbid invented relationships and causation.** "This deposit is a round-up tied to that purchase" / "X triggered Y" is a category error — an inference smuggled in as a fact. Report co-occurrence, never causation, unless a tool returned an explicit link.

**16. Respect metric direction in any ranking.** Don't claim "highest/best in the set" unless the other entities' values are present *this turn*; honor whether higher-is-better or rank-lower-is-better; and prefer a **server-computed rank** so the model reads its position rather than ordering near-tied values by hand (which it inverts).

**17. Keep the knowledge base synced to the source of truth, and route to it.** Stale platform facts (model lists, plan names, definitions, counts) produce confident wrong answers. Sync the knowledge tool to config, route "what does metric X mean / what plans exist" to it, and forbid answering such questions from training data.

### D. Conversation behavior

**18. Never let a turn be silent.** An empty/silent reply is the worst failure class (high-severity "premature closure"). Guarantee a non-empty answer with a deterministic fallback, and tell the model to conclude "I don't see any X" the moment a search returns nothing.

**19. Converge — stop when you can answer.** More tools tempt more flailing; expanding the toolset can *raise* empty-answer rates. Add the discipline "one call is enough; don't re-query to double-check; conclude on an empty result." When the provider ignores the SDK's per-step tool-choice controls, enforce the invariant one layer down — a **tool-call budget** at the tool boundary, which every provider must honor (after N calls, return "limit reached — write your answer now"). And when you force an answer, force it *honestly*: "write from only the data you received; if it's incomplete, say what's missing — never invent." But beware the opposite failure: pushed too hard, convergence makes the model *under*-tool and drop a needed fact — it answered MRR and conversation count but omitted the health score because it stopped at one tool. Don't fix that with a stricter prompt; fix it structurally per #3 — put every field a common intent needs into **one** tool's return shape, so a single call is both minimal *and* complete. And **size the budget N to your most complex *legitimate* request, not the median**: well-behaved answers can have a p90 of 2 tool calls while a valid multi-entity comparison or executive briefing legitimately needs 6–8. Too low a cap clips correct complex answers — the budget is a runaway guard, not an efficiency lever; efficiency comes from convergence, not from a low ceiling.

**20. Tools are internal — never leak their names to the user.** Telling a user to "use `getMetrics` with `filter='internal'`" exposes a function they can't call. Call tools yourself; describe results in plain language. (This one is even regex-detectable.)

**21. Don't fabricate or force structure the user didn't ask for.** Prose-first. Include a chart/table inline only when it fits the request; never announce or defer to a render the user didn't ask for. And every value/label/name in a chart must be copied **exactly** from a tool result — chart cells hallucinate just like prose.

**22. Characterize, don't reproduce** (when the bot's job is to analyze *other* content). Summarize a bad or unsafe quote — "the bot gave credential-sharing advice" — rather than reproducing "email your API key." It's better analytics output *and* it avoids tripping safety/quality filters on the verbatim quote.

**23. Counting and self-consistency need a source, not a vibe.** Count entities from the registry/tool, and make the announced quantity equal the length of the list the model then produces ("three actions:" must be followed by three). Prompt rules reduce the slip rate on a generative model; they don't guarantee zero — treat an occasional off-by-one as a noise floor, not a systematic bug.

### E. Measure it, and trust the measurement

**24. Run a loop: fire N diverse queries → analyze each turn → bucket genuine issues by root cause → fix the top cause → re-run the same N → compare.** This turns "the bot feels off" into a ranked, shrinking list of root causes and *proves* a fix worked. Keep the query set fixed across campaigns so the trend is the signal (the bot is non-deterministic, so the per-category mix shifts run to run).

**25. The oracle has blind spots — close them before trusting it.** The biggest source of false positives is the analyzer not seeing what the model saw (truth #0's corollary). Feed it the system-prompt variables/registry and the tool **outputs**. A missing or failed capture must count as an **error, never a pass** — a bot returning 500s with no captured turns will otherwise score 100% clean.

**26. Apply each fix to the tool the model actually uses.** A correct fix on the wrong tool leaves the bug live. Confirm which tool answered before annotating one.

**27. Classify real-bug vs. false-positive before you fix anything.** An issue rate is meaningless until split — in one case the ratio of real bugs to analyzer false-positives was about 1:40. Don't chase false positives to zero: rubrics built for a customer-support bot (upsell, brand voice) misfire on an internal analytics assistant, and an analyzer may flag rendered chart markup as "robotic."

**28. Test on consistent data, or you measure the data's bugs.** If one entity id carries several different names in your seed/test data, the analyzer's "truth" differs from the tool the model used, and you manufacture unlimited phantom "hallucinations." A 30-second `count(distinct name) per id` check can save days.

**29. You will eventually out-run your own oracle.** Every one of these programs reached the point where the chatbot's true error rate dropped *below* the analyzer's false-positive rate — half the remaining flags were on *correct* answers. When you get there, the next leverage is the analyzer, not the chatbot. Recognize it so you stop grinding the bot.

**30. Proof-carrying numbers are the endgame, but only with entity binding.** The strongest guarantee: the model emits a value *reference* bound to a tool output, and a resolver substitutes the real value fail-closed, so a number *cannot* drift from its source. Note the trap: naive number-presence matching is too weak (with many ground-truth numbers, coincidental matches abound) — the check must bind **number → entity**, which is real work. Avoid an LLM self-verification pass on the streaming hot path (it re-guesses and multiplies latency); prefer an offline deterministic gate, or a gated re-ask only on suspicious turns. Make the binder **layout-aware**: when the bot answers in a markdown table or a generative-UI spec (a chart/table DSL), the value and its entity share a *row/cell*, not prose proximity — a linear-distance binder false-*negatives* correct tabular answers (a fully-correct org comparison scored 0/4 until the check split on row boundaries). Bind within the row/segment, not by character distance.

---

## Design checklist (run before shipping a tool, digest, or prompt change)

- **Numbers:** Is every number the user could ask for a single quotable tool field? Any place the model would have to add/divide/average/project in its head? → move it into the tool.
- **Digests:** Does each digest surface the authoritative computed field (ratio, total, neutral bucket, rank)? Are truncated lists accompanied by full-set aggregates? Does every value name its metric and bind to its entity inline?
- **Sources:** Is there a grounded, cited source for every claim the bot will make (including "what we are / what we do / what this metric means")? Does it **abstain** when the source is empty rather than reconstruct?
- **Entities:** Registry-only naming in force? Claims keyed by id, not value? Causation forbidden unless a tool returned the link?
- **Behavior:** Can a turn ever be silent? Is there a convergence/tool-budget guard? Are tool names kept internal? Are charts faithful and unforced?
- **Units & failures:** Aggregates grouped by unit? Fetch-failure distinguished from no-data? A test that digest keys ⊆ source columns?
- **Rule vs. structure:** For each prompt rule you're tempted to add — could this instead live in the tool's return shape? Prefer the structural fix; it won't decay.
- **Measurement:** Can you prove this change worked with a re-run on a fixed query set? Does your oracle see the same grounding the model saw?

When in doubt, prefer the fix that changes **what the model sees** over the fix that changes **what the model is told**.
