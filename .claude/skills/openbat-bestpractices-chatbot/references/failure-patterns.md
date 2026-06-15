# Failure-pattern catalog (symptom → detection → root cause → durable fix)

A de-identified catalog of the recurring ways a data/analytics chatbot fails, compiled across multiple reliability programs. Each entry is structured so you can route a real symptom to its root cause and the *durable* fix (usually structural, not a prompt rule). Use alongside the fundamental truths in `SKILL.md`.

## Table of contents

- [P1 — Incomplete tool digest (model invents the hidden field)](#p1)
- [P2 — Cross-field / cross-entity number confusion](#p2)
- [P3 — Missing grounded source → fabrication](#p3)
- [P4 — In-context math / forecasting](#p4)
- [P5 — NaN / garbage digest (column-name drift)](#p5)
- [P6 — Stale knowledge base](#p6)
- [P7 — Invented entities / terminology / queries](#p7)
- [P8 — Tool-name leakage](#p8)
- [P9 — Unsupported or inverted ranking](#p9)
- [P10 — Counting / self-consistency slips](#p10)
- [P11 — Forced / premature UI render](#p11)
- [P12 — Empty / silent answer (premature closure)](#p12)
- [P13 — Summing across incompatible units](#p13)
- [P14 — Invented relationships / causation](#p14)
- [P15 — Averaging a truncated sample](#p15)
- [Quick routing table](#routing)

---

<a name="p1"></a>
## P1 — Incomplete tool digest (model invents the hidden field)

- **Symptom:** a reported percentage/count is wrong in a *systematic* way — e.g. "82% positive" when the true ratio is 40%, or "all positive, zero negative" when neutrals exist. A cluster of identical errors on one tool is the tell.
- **Detection:** the model's value equals a *derivable-but-wrong* combination of the visible fields (classically `pos/(pos+neg)` when neutrals were hidden). If many turns show the same wrong derivation on one tool, it's this.
- **Root cause:** the digest omitted the authoritative field (the ratio, the neutral bucket, the total), so the model reconstructed it from what it could see.
- **Durable fix:** surface the computed field verbatim and instruct "cite this, don't recompute; neutral ≠ positive." *When a digest hides a field, the model fills the gap with a guess.*
- **Why it matters:** this is repeatedly the single highest-leverage fix in an entire program — one digest correction has eliminated the large majority of a run's numeric errors.

<a name="p2"></a>
## P2 — Cross-field / cross-entity number confusion

- **Symptom:** the model reports a *real* number but attaches it to the wrong metric or entity ("16 total mentions" when citations = 2; theme A's size quoted for theme B).
- **Detection:** the model's number matches a *different* field/row in the same tool output. Flat "is this number anywhere in the output?" checks **miss this** — the number is real, just mis-attributed.
- **Root cause:** two adjacent metrics look interchangeable (citations vs. mentions), or a list lets a value detach from its label.
- **Durable fix:** relabel digests so each count states what it is and carries a "do not conflate" note; bind each value to its entity on the same line (`theme="X" size=N`); name the field the user asked for explicitly.

<a name="p3"></a>
## P3 — Missing grounded source → fabrication

- **Symptom:** confident claims about the primary subject (its positioning, value props, "what makes us different," a definition) with no backing data.
- **Detection:** fabrication recurs specifically on "describe / position / differentiate / define" intents.
- **Root cause:** no tool or field provides the answer, so the model reconstructs it from adjacent data plus priors. (A classic instance: the enrichment pipeline populated profiles for *comparison* entities but never for the subject's own — leaving "what we stand for" ungrounded.)
- **Durable fix:** give it a cited source tool that returns the profile as a tool output, and a rule to **abstain** when the source is empty (`hasProfile:false`). Often the invented claim turns out to be *true* — it was simply ungrounded; now it's stated from the real profile.

<a name="p4"></a>
## P4 — In-context math / forecasting

- **Symptom:** projections, averages, growth rates, or "by end of next year" numbers computed in the model's head over tabular context.
- **Detection:** forward-looking numbers; aggregates that don't match a compute tool; arithmetic over a truncated sample.
- **Root cause:** LLMs are unreliable at arithmetic/extrapolation over context, and a prompt that merely *says* "use a tool to forecast" is ignored.
- **Durable fix:** a deterministic compute/forecast tool — parses the horizon in code (never trusts model date math), fits a closed-form model, returns only `{low, high, ci, r², confidence}`, and **abstains** below a data threshold. Make the exact-compute path reachable on the first step. Forbid stating any computed/projected number that didn't come from a tool.

<a name="p5"></a>
## P5 — NaN / garbage digest (column-name drift)

- **Symptom:** answers derived from `NaN`/undefined; nonsense numbers on exactly one tool.
- **Detection:** `NaN`/null in the captured tool output; a tool whose digest keys don't match its data source's column names (a casing/naming drift like `score` vs `score_value`, or `weekNum` vs `week_number`).
- **Root cause:** the digest reads the wrong column names; the model reasons over `NaN`.
- **Durable fix:** correct the mapping, and add a **test asserting digest keys ⊆ the data source's output columns** so the class can't recur.

<a name="p6"></a>
## P6 — Stale knowledge base

- **Symptom:** confident platform facts that contradict the actual config — "7 monitored models" when there are 3; outdated model/plan names; wrong metric definitions.
- **Detection:** platform-fact claims that disagree with the system's own source of truth.
- **Root cause:** the knowledge tool's content drifted from config.
- **Durable fix:** sync the knowledge tool to the source of truth; add a dedicated topic the prompt routes to; forbid answering platform-fact questions from training data. (Where possible, inject the real values — plan names, model list — into the prompt as a ground-truth block so invention is impossible.)

<a name="p7"></a>
## P7 — Invented entities / terminology / queries

- **Symptom:** names a competitor/provider/program that doesn't exist, coins a "platform term," or quotes a tracked query/string that was never run.
- **Detection:** a proper noun or quoted string not present in any tool output or the entity registry.
- **Root cause:** padding a synthesis with plausible-sounding specifics.
- **Durable fix:** a **registry-only naming** rule — never name an entity or quote a string unless it appears verbatim in a tool result or the registry; otherwise describe generically.

<a name="p8"></a>
## P8 — Tool-name leakage

- **Symptom:** tells the user to "use `getMetrics`" or "set `filter='internal'`" — exposing internals they can't act on.
- **Detection:** function/parameter names in user-facing text (regex-detectable, no LLM needed).
- **Durable fix:** "tools are internal — call them yourself and describe results in plain language, never by function or parameter name."

<a name="p9"></a>
## P9 — Unsupported or inverted ranking

- **Symptom:** "highest in the set" without the set present; or a *direction inversion* — calling an entity "ahead" at 16.2% when a competitor is at 16.5%.
- **Detection:** superlative/ranking claims; a stated order that disagrees with the numeric order of the tool's values (especially on near-tied values, which the model inverts even while printing both numbers).
- **Durable fix, in order of strength:**
  1. Don't rank unless the other entities' values are present this turn.
  2. Respect metric direction (higher-is-better vs. rank-lower-is-better).
  3. **The decisive one:** put a **server-computed rank** `(#k/N)` in the digest so the model *reads* position instead of ordering by hand. A prose rule alone ("order by the values; lower = behind") only partially helps; the model keeps inverting near-ties.
- **Lesson:** don't instruct the model to compare — compute the comparison and have it read the result. And apply the rank to the tool the model *actually answers from* (annotating the wrong tool leaves the bug live).

<a name="p10"></a>
## P10 — Counting / self-consistency slips

- **Symptom:** "all four" when three exist; "three actions" then lists four.
- **Detection:** a stated count ≠ the registry/tool count, or ≠ the length of the list the model then produces (both checkable without an LLM).
- **Durable fix:** count entities from the registry; the announced quantity must equal the list length. Prompt rules reduce the rate but don't zero it on a generative model — treat an occasional off-by-one as a non-deterministic noise floor, not a systematic bug.

<a name="p11"></a>
## P11 — Forced / premature UI render

- **Symptom:** ends a turn by announcing or triggering a dashboard/chart the user didn't ask for.
- **Detection:** an unsolicited render announcement near the end of a turn; "verbose"/"premature closure" flags.
- **Durable fix:** include visuals inline only when they fit the request; never defer to or force a render the user didn't ask for. When you *do* render, every value/label/name in the chart must be copied exactly from a tool result.

<a name="p12"></a>
## P12 — Empty / silent answer (premature closure)

- **Symptom:** the turn returns success with **zero text** — the worst failure class.
- **Detection:** finish reason is "tool-calls" with a high tool count; the model looped tools to the step cap and never wrote prose.
- **Root cause:** a planning failure — the model keeps "deciding it needs more data," often because the tool lacks the filter/dimension it needs to actually answer (see P-dimensions below), or because more tools invited more flailing.
- **Durable fix:** (a) give the tool the missing dimensions so it *can* answer; (b) a deterministic **non-empty fallback** so a turn can never be silent; (c) a **tool-call budget** enforced at the tool boundary (provider-agnostic — per-step tool-choice overrides are ignored by some providers); (d) "stop when you can answer; conclude 'I don't see any X' on an empty result." When you force the answer, force it honestly ("write from only the data you have; say what's missing; never invent") — otherwise forcing exposes fresh fabrication.

<a name="p13"></a>
## P13 — Summing across incompatible units

- **Symptom:** a single bogus total that blends currencies/units (e.g. an unknown-currency row summed into an EUR total).
- **Detection:** a total that doesn't equal the sum of any single-unit subset.
- **Durable fix:** group every aggregate by unit in code; emit a single total only when one unit is present; surface "unknown unit" honestly rather than coercing it.

<a name="p14"></a>
## P14 — Invented relationships / causation

- **Symptom:** "this deposit is a round-up tied to that purchase," "X triggered Y" — an inference asserted as a fact.
- **Detection:** a causal/linking claim with no tool field expressing that link.
- **Durable fix:** report co-occurrence, never causation, unless a tool returned an explicit relationship. Ground list items by row **id**, not by a shared value (same-amount rows are otherwise swappable).

<a name="p15"></a>
## P15 — Averaging a truncated sample

- **Symptom:** "average across all rows" computed from the 10 rows shown, not all N.
- **Detection:** an aggregate that matches the visible subset rather than the full set.
- **Root cause:** digests truncate for context economy but carry no full-set aggregates.
- **Durable fix:** append exact `count/mean/min/max/sum` over the **complete** set (computed pre-truncation) to every truncated digest, with an anti-eyeballing note; make the exact-compute tool reachable early.

---

<a name="routing"></a>
## Quick routing table (analyzer signal → likely pattern)

| Signal | Likely pattern(s) |
|---|---|
| contradicts a NUMBER, systematic | P1 hidden field · P2 cross-field · P5 NaN |
| number matches a *different* field/row | P2 cross-field |
| fabricates an ENTITY / name / quoted string | P7 invented entity · P3 missing source |
| fabricates a NUMBER breakdown from a ratio | P1 ratio→counts · P4 in-context math |
| forward-looking / projected number | P4 forecasting |
| ranking / "highest / ahead of" claim | P9 ranking |
| stated count ≠ list length / registry | P10 counting |
| empty reply, finish reason = tool-calls | P12 silent answer |
| total blends units | P13 units |
| "caused / triggered / tied to" | P14 causation |
| aggregate matches visible subset | P15 truncation |
| tool/param name in user text | P8 leakage (regex-detectable) |
| unsolicited render near turn end | P11 forced render |
| misinformation on a definition/metric | P6 stale KB **or** an oracle false-positive (see `eval-loop.md`) |

**The deepest cross-cutting lesson:** for almost every pattern, the durable fix changes **what the model sees** (the tool's return shape, an added field, a registry, a budget) rather than **what the model is told** (a prose rule). Prompt rules decay; structure holds.
