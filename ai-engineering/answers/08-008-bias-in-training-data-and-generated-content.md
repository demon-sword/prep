# Bias in training data and generated content?

**Category:** 08-safety-guardrails
**Question #:** 008
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Bias questions are where candidates most often retreat into generalities — "we'd make sure the training data is diverse," "we'd audit for fairness." The interviewer is looking for the opposite: a **measurement plan**. Can you name the specific places bias enters an LLM application (four of them, and only one is the pretraining corpus)? Can you describe a test you would actually run this week? Do you know that a published benchmark score for a model does not transfer to your task? And — the senior-level discriminator — do you understand that an LLM making or influencing a *consequential decision* about a person is a legally different object than an LLM writing marketing copy, with a different obligation set attached?

### Trigger phrases
- "How do you handle bias in the model?"
- "How would you audit an LLM for fairness?"
- "We're using an LLM to screen résumés — what are your concerns?"
- "The model gives different answers depending on the name in the prompt. What now?"
- "Isn't bias a pretraining problem you can't do anything about?"

### What it tests
Whether you can turn "bias" into a measurable, task-specific evaluation with named metrics and a mitigation at each layer of the stack — and whether you recognize when the deployment crosses into regulated-decision territory.

---

## Answer

### Concept
Bias in an LLM system is a **systematic difference in output quality or outcome that correlates with a protected or sensitive attribute** — gender, race, age, disability, national origin, dialect, and in practice also things like non-native-speaker phrasing. It is not one thing that lives in the weights. It enters at four separable points, and each has a different owner and a different fix. The engineering consequence: you cannot inherit a bias assessment from the model provider, because **bias is a property of your task, your prompts, your retrieval corpus, and your user segments — not of the base model alone.**

### Mechanism

**Four sources, four different fixes:**

| Source | What it looks like | Who can fix it | Your lever |
|--------|-------------------|----------------|------------|
| **Pretraining corpus skew** | Occupational stereotypes, dialect quality gaps, Western/English-centric defaults, thin coverage of minority-language and low-resource contexts | The lab, not you | Model selection; measure candidates on *your* probes before choosing |
| **Alignment / RLHF annotator pool** | Preferences of a narrow demographic and geographic slice of annotators baked into "helpfulness"; politeness and register norms; sycophancy toward confident-sounding users | The lab (or you, if you fine-tune) | If you fine-tune or run preference optimization, audit your own annotator pool and label guidelines |
| **Retrieval corpus** | Your own KB under-covers a product line, region, or language, so RAG answers are systematically thinner for those users | **You** | Coverage audit by segment; targeted content backfill |
| **Prompt framing & few-shot exemplars** | Exemplars all show one demographic pattern; the system prompt encodes an assumption ("the customer, he…"); the schema forces a binary where reality isn't | **You** | Balanced exemplars, neutral framing, schema review |

Two more that show up specifically in application layers: **the schema itself** (a required "gender: M/F" field is a design bias), and **the threshold** (one global cutoff on a score that is calibrated differently across segments produces disparate outcomes even from an unbiased model).

**Measurement — this is the substance of the answer.**

**1. Counterfactual / perturbation testing.** The single highest-value test, and cheap. Take N real production inputs, hold everything constant except one demographic signal, and diff the outputs. Swap:
- names (given names with strong demographic association, plus surnames)
- pronouns (he/she/they)
- explicit attributes (age, "single mother of two", disability disclosure, university, ZIP code)
- dialect and register (AAVE, Indian English, non-native phrasing, code-switching)
- language (the same question in Spanish, Hindi, Arabic)

Then measure the delta on whatever the model actually produces: for a scored decision, mean score shift and selection-rate shift; for free text, sentiment/tone deltas, length deltas (systematically shorter answers to one group is a real and common harm), refusal-rate deltas, and hedging-language frequency. **Refusal-rate asymmetry is the most under-tested and most common LLM bias in practice** — the model declining more often on questions about one group, or on inputs written in a particular dialect.

Do this with N ≥ 200 base cases × the number of variants and bootstrap a confidence interval, because LLM sampling noise will happily manufacture a 3-point "gap" that vanishes on reseed. Run at temperature 0 for the decision path, and report the CI, not a point estimate.

**2. Subgroup performance gaps.** Slice your *existing* task metrics — accuracy, groundedness, citation correctness, task completion, CSAT, escalation rate, latency — by segment and look for gaps, not absolute values. Aggregate accuracy of 91% can hide 94% for one segment and 78% for another. This requires you to have segment labels, which is itself a privacy and consent question: you often cannot store race, so real programs use consented self-ID on a sample, proxy variables (language, region) with explicit caveats, or an offline audit set. Say this — it shows you've had to actually operationalize it.

**3. Disparate impact ratio on downstream decisions.** When the LLM feeds a decision (advance/reject, approve/deny, prioritize/deprioritize), compute the **impact ratio**: selection rate of the lowest-selected group ÷ selection rate of the highest. The **four-fifths rule** from the EEOC Uniform Guidelines flags anything **below 0.80** as evidence of adverse impact. This is the exact statistic NYC's Local Law 144 requires in the annual independent bias audit of automated employment decision tools, computed by sex, by race/ethnicity, and by their intersection. Report intersectional cells too — a system can look clean on sex alone and on race alone and still fail badly on the intersection.

**4. Published probes as *smoke tests only*.** **BBQ** (Bias Benchmark for QA — ambiguous vs disambiguated contexts across nine social dimensions), **WinoBias** and **Winogender** (coreference against occupational stereotypes), **StereoSet**, **HolisticBias**, **BOLD** for open-ended generation, and the fairness modules inside evaluation harnesses. These are useful for comparing candidate models before you commit and for catching a gross regression on a model upgrade. They are **not** an audit of your system. A model can score well on WinoBias and still be badly biased on your résumé-screening prompt, because your prompt, your exemplars, and your retrieval corpus are not in the benchmark. Say this explicitly — "a published bias benchmark score does not transfer to my task" is a high-signal sentence.

**Mitigation, layer by layer:**

| Layer | Mitigation | Realistic effect |
|-------|-----------|------------------|
| Model selection | Run your own counterfactual suite across 2–3 candidate models before committing | Sometimes the single biggest lever; costs a day |
| Retrieval corpus | Coverage audit by segment; backfill thin areas; check the retriever isn't systematically ranking one language's docs lower | Fixes the gaps *you* created — often the largest real-world gap |
| Prompt / exemplars | Balance few-shot exemplars across demographics; strip assumption-laden framing; instruct explicitly that protected attributes are irrelevant to the judgment | Moderate; cheap; verify, don't assume — instructions alone frequently fail |
| Input scrubbing | Strip names, pronouns, photos, schools, ZIP, graduation year before the decision call | Strong for decisions; **beware proxies** — ZIP, school, and hobbies leak the attribute you just removed |
| Structured output | Force the model to emit its rationale against fixed named criteria rather than a free-form judgment | Makes the decision auditable and is often required for the "explanation of factors" duty |
| Output calibration | Per-segment calibration or threshold adjustment on the downstream score | Effective — but legally fraught: explicit per-group thresholds can themselves be unlawful disparate treatment in US employment; get counsel before shipping it |
| Human review | Route the consequential decision to a human with the model as advisory input only | The default posture in regulated settings |
| Monitoring | The counterfactual suite runs in CI on every prompt/model change; impact ratio tracked on live decisions | Bias regressions ship in prompt diffs, not just model swaps |

**The regulated-decision angle — say this unprompted.** An LLM writing product descriptions and an LLM ranking job applicants are the same technology and completely different legal objects. Once the system makes or materially influences a **consequential decision** about a person — employment, credit, housing, insurance, education, or access to essential services — a whole obligation set attaches:

- **NYC Local Law 144** (in force since July 2023): annual **independent** bias audit of automated employment decision tools, published selection rates and impact ratios, candidate notice. Note that a 2026 audit of the law's real-world effect found weak compliance and rising employer risk — meaning enforcement attention is increasing, not decreasing.
- **EEOC / Title VII / ADA** in the US: disparate impact liability attaches to the employer using the tool, not the vendor who built it. "The vendor said it was fair" is not a defense.
- **ECOA / Regulation B** for credit: adverse action notices must state **specific principal reasons** for denial. A model that cannot produce reasons cannot lawfully make that decision — which is a *design* constraint on your output schema, not a compliance afterthought.
- **Colorado**: SB 26-189 (signed May 2026, replacing the earlier SB 24-205) takes effect **1 January 2027**, imposing deployer obligations including impact assessments for consequential decisions.
- **EU AI Act**: employment and creditworthiness systems are Annex III high-risk. Under the Digital Omnibus revision, the Annex III high-risk regime — risk management, data governance, logging, human oversight, conformity assessment — now applies from **2 December 2027** (Annex I product-embedded: 2 August 2028), while general application and the Article 50 transparency duties land **2 August 2026**. Being current on that shift is a nice signal; the point is the obligations are dated, and "we'll deal with it later" has a deadline attached.
- **NIST AI RMF 1.0** plus **NIST SP 1270** (*Towards a Standard for Identifying and Managing Bias in AI*) give you the vocabulary — systemic, computational/statistical, and human-cognitive bias — and the MEASURE/MANAGE functions to structure the program. Useful for making your work legible to a risk committee.

The engineering translation of all this: in the regulated case you need **decision logs retained** (input, retrieved context, model version, prompt version, output, human override), a **reason code** on every decision, a **human-in-the-loop** for adverse outcomes, and a **repeatable audit** an outside party can rerun. In the unregulated case you need the counterfactual suite in CI and segment-sliced quality metrics — a much lighter program, and it's fine to say so. Matching the weight of the program to the stakes *is* the senior answer.

### Example / Tradeoff

**Résumé-screening assistant (the canonical hard case).** An LLM summarizes candidates and produces a 1–5 fit score against a job description; recruiters see the summary and the score.

What the counterfactual suite found on a 300-résumé base set, each rendered in 6 variants (name swap ×2, pronoun swap, "career gap for childcare" added, non-native phrasing, degree from a less-selective school):
- Mean fit score shifted **0.3–0.4 points** on identical content when only the name changed — enough to move candidates across the recruiter's mental 3.5 cutoff.
- Résumés with a career gap were penalized in the *summary language* ("limited recent experience") even when the score was unchanged, which is a harm the score metric alone would have missed entirely. **Measure the text, not just the number.**
- Non-native phrasing produced systematically shorter summaries — less advocacy for the candidate, from identical qualifications.

Mitigation stack that got the impact ratio from **0.71 to 0.94** on the audit set:
1. Strip names, pronouns, photos, addresses, graduation years, and school names before the model call — and audit for proxies afterward, because ZIP codes and hobbies leak.
2. Force structured output: score each of five named job-relevant criteria separately with a quoted evidence span from the résumé for each, rather than a holistic free-text judgment. This both reduced the gap and produced the reason codes the process needed.
3. Balance few-shot exemplars across demographics and across résumé formats.
4. Keep the human decision-maker; the model output is explicitly advisory, and rejections require a human reason code.
5. Ship the counterfactual suite into CI: any prompt change that moves the impact ratio below 0.85 fails the build.

**Tradeoffs, stated honestly:**

- **Fairness metrics are mathematically incompatible.** Demographic parity (equal selection rates), equalized odds (equal TPR/FPR), and calibration within groups cannot generally be satisfied at once when base rates differ — this is the standard impossibility result, and it means "make it fair" is under-specified until someone chooses the criterion. That choice is a policy decision with legal input, not an engineering one. Push it to the right people and document the choice; pretending it's a tuning knob is the wrong answer.
- **Blinding costs accuracy and can be defeated by proxies.** Removing the attribute doesn't remove correlated signal; sometimes you need the attribute *visible for measurement* even while it's blinded to the decision — which is awkward and needs an explicit data-handling design.
- **Per-segment thresholds work and may be illegal.** Effective statistically, potentially unlawful disparate treatment in US employment contexts. Counsel first.
- **Measurement requires the attribute you're not allowed to store.** Real programs use consented self-ID on a sample, or an offline audit set with synthetic/labeled variants — which is precisely why the counterfactual approach is so valuable: it needs **no demographic data about real users at all**, because you generate the variants yourself.
- **Cost:** the counterfactual suite is 300 × 6 = 1,800 model calls per run. That is cheap enough to run on every prompt PR, which is the whole point — bias regressions arrive in prompt diffs far more often than in model upgrades.

---

## Verbal script

**Opening (30s):**
"I'd want to make this concrete fast, because 'bias' can drift into abstraction. My framing is: bias enters at four points — the pretraining corpus, the alignment annotator pool, my retrieval corpus, and my prompt and exemplars — and I only control the last two. So my job is a measurement plan on *my* task, not an opinion about the base model. And the first thing I'd establish is the stakes, because an LLM writing marketing copy and an LLM ranking job applicants are the same technology and completely different legal objects."

**Core explanation (2–3 min):**
"The measurement I'd run first is counterfactual perturbation testing, because it's cheap and it finds real things. Take a couple hundred real production inputs, hold everything constant, and change exactly one demographic signal — swap the name, swap pronouns, add a career gap, rewrite in a different dialect or a different language — then diff the outputs. For a scored decision I measure the score shift and the selection-rate shift. For free text I measure sentiment delta, refusal-rate delta, and length delta. Refusal asymmetry and length asymmetry are the two most under-tested LLM biases I've seen: the model quietly writing shorter, less enthusiastic summaries for one group, from identical underlying content. A score-only metric misses that completely.

I'd bootstrap confidence intervals over at least a couple hundred base cases, because sampling noise will manufacture a three-point gap that disappears on reseed, and I don't want to chase ghosts or, worse, declare victory on noise.

Second, subgroup performance gaps — slice the metrics I already have, accuracy, groundedness, task completion, escalation rate, by segment and look at the gap rather than the absolute. Aggregate 91 percent can hide 94 and 78. The practical wrinkle is that this needs segment labels I often can't legally store, so it's consented self-ID on a sample or an offline audit set — which is exactly why I like counterfactual testing, it needs no demographic data about real users at all because I generate the variants myself.

Third, if the model feeds a decision, the impact ratio: selection rate of the lowest group over the highest, and the four-fifths rule flags anything under 0.80. That's the same statistic NYC Local Law 144 requires in the annual independent audit for automated employment decision tools, computed by sex, by race, and by the intersection — and I'd always report intersectional cells, because a system can look clean on each axis alone and fail on the combination.

On published benchmarks — BBQ, WinoBias, StereoSet, BOLD — I use them as smoke tests for comparing candidate models, and I'd say clearly that a published bias score does not transfer to my task. My prompt, my few-shot exemplars, and my retrieval corpus aren't in the benchmark, and they're where most of the bias I can actually fix lives.

For mitigation I'd go layer by layer. Model choice, evaluated on my own probes. Retrieval corpus coverage by segment — if the KB is thin on one product line or one language, RAG answers are systematically worse for those users, and that's a gap I created and can close. Balanced exemplars and neutral framing. Input scrubbing for decisions, with a proxy audit afterward, because ZIP code and school leak exactly what you just removed. Structured output with per-criterion scores and quoted evidence rather than a holistic judgment. And human review on the consequential decision."

**Tradeoff / production angle (1 min):**
"Three things I'd be honest about. First, the fairness criteria are mathematically incompatible — demographic parity, equalized odds, and calibration within groups can't all hold when base rates differ. So 'make it fair' is under-specified until someone picks the criterion, and that's a policy call with legal input that I'd document, not a knob I'd quietly turn. Second, per-segment thresholds are statistically effective and potentially unlawful disparate treatment in US employment contexts, so counsel before shipping. Third, the regulated case demands things that are design constraints, not afterthoughts — ECOA requires specific principal reasons on an adverse action notice, so a model that can't produce reason codes can't lawfully make that decision. That changes my output schema on day one.

On a résumé-screening system, the concrete version: 300 résumés times 6 variants, and identical content scored 0.3 to 0.4 points differently on a name swap alone — enough to cross a recruiter's mental cutoff. Stripping identifiers plus forcing per-criterion structured scoring with quoted evidence moved the impact ratio from 0.71 to 0.94. And then the important part: that suite runs in CI, and any prompt change that drops the ratio below 0.85 fails the build. Bias regressions show up in prompt diffs far more often than in model upgrades, and 1,800 calls is cheap enough to run on every PR."

**Wrap-up (30s):**
"So the short version: four sources, I control two of them; measure with counterfactual perturbation plus subgroup gaps plus impact ratio on my own task and my own segments; treat published benchmarks as smoke tests that don't transfer; mitigate at model, corpus, prompt, scrubbing, schema, and threshold layers; and scale the program to the stakes — CI checks for a chatbot, full audit trail with reason codes and human review for anything touching employment, credit, or housing. Happy to go deeper on the counterfactual harness or the fairness-metric tradeoff."

---

## Pitfalls

- **Mistake:** "We use a model that scores well on standard bias benchmarks, so we're covered." — **Better:** Benchmark scores are properties of the base model on the benchmark's task; your prompt, few-shot exemplars, retrieval corpus, and output schema are not in the benchmark and are where most fixable bias lives. Use BBQ/WinoBias as a smoke test for model selection, then build a counterfactual suite on your own inputs and your own segments — and put it in CI, because prompt changes introduce bias regressions too.

- **Mistake:** "Bias comes from the training data, and we can't retrain a foundation model, so there's nothing we can do." — **Better:** Pretraining is one of four sources; the retrieval corpus, the prompt framing and exemplars, and the decision threshold are all yours. Naming a concrete fix at each layer — segment coverage audit on the KB, balanced exemplars, identifier scrubbing with a proxy audit, per-criterion structured output — turns a fatalistic answer into an engineering plan.

- **Mistake:** Measuring only the score or the label and never the generated text — and quoting a gap with no confidence interval. — **Better:** Bias in generative systems shows up as tone, length, hedging, and refusal-rate asymmetry, not just score deltas; systematically shorter, less enthusiastic summaries for one group is a real harm a score metric never sees. And bootstrap a CI over 200+ base cases at temperature 0, because LLM sampling noise routinely produces apparent gaps that vanish on reseed.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: Bias/fairness tradeoffs — example](05-014-biasfairness-tradeoffs-example.md) | same concept — the fairness-metric incompatibility in detail |
| [Q9: Red-team an LLM system?](08-009-red-team-an-llm-system.md) | adjacent — counterfactual bias probes are a taxonomy node in the red-team suite |
| [Q31: Agents in regulated domains (financial, healthcare)](03-031-agents-in-regulated-domains-financial-healthcare.md) | follow-up — the audit-trail and human-review obligations for consequential decisions |

---

## One-liner recall

> Bias enters at four points — pretraining corpus, RLHF annotator pool, *your* retrieval corpus, and *your* prompt/exemplars — and you only control the last two, so the answer is a measurement plan on your own task: counterfactual perturbation testing (swap names, pronouns, dialect; measure score, refusal-rate, tone and *length* deltas with bootstrapped CIs), subgroup performance gaps, and the four-fifths impact ratio (<0.80 flags adverse impact, the LL144 statistic) — mitigate at model/corpus/prompt/scrubbing/schema/threshold layers, run the suite in CI on every prompt diff, and remember a published bias benchmark score does not transfer to your task and a consequential-decision deployment (hiring, credit, housing) carries reason-code, audit-log, and human-review obligations a chatbot does not.
