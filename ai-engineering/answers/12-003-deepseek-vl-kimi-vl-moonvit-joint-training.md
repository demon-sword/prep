# How do DeepSeek-VL, Kimi-VL, and MoonViT differ from LLaVA-style recipes?

**Category:** 12-multimodal-vlm
**Question #:** 003
**Source section:** §TBD — no VLM bank section in interview-questions.md yet; stems land with File AU (C21)
**Status:** `review`
**Generated:** paper-build-vlm-cat

---

## Framing

### Why this question is asked
This is the "compare frontier recipes" question. LLaVA freezes the encoder; DeepSeek-VL, Kimi-VL, and the MoonViT encoder family represent the opposite bet — **joint all-params training** on stronger hybrid encoders (SigLIP plus captioning objectives). Interviewers want the axis of comparison (frozen vs joint, contrastive-only vs hybrid encoder), not a spec-sheet recital.

### Trigger phrases
- "Compare LLaVA and DeepSeek-VL."
- "When would you unfreeze the vision encoder?"
- "What is MoonViT / what encoder would you pick for a new VLM?"

### What it tests
Articulating the frozen-encoder ceiling, the cost/quality tradeoff of joint training, and why encoder pretraining objective (SigLIP vs captioning vs both) constrains the recipe.

---

## Answer

### Concept
**DeepSeek-VL and Kimi-VL** train vision encoder, adapter, and LLM **jointly (all parameters unfrozen)** through the alignment stages instead of freezing the encoder LLaVA-style, letting visual features co-adapt with the language model. Their encoders follow the hybrid pattern the Kimi-VL report calls **MoonViT**: a SigLIP-style pairwise-sigmoid contrastive objective **combined with captioning pretraining**, so one encoder carries both discriminative (retrieval/zero-shot) and generative (dense description) strengths into the joint recipe. (Architecture details below are as described in the DeepSeek-VL/Kimi-VL reports — cite them, don't present them as settled constants.)

### Mechanism

**The frozen-encoder ceiling (what these recipes remove):**
- In LLaVA, gradients stop at the projector: the LLM learns to *interpret* fixed CLIP features but can never request *better* features. Failure mode: fine-grained detail the encoder discarded (small text, dense charts, subtle grounding cues) is unrecoverable downstream no matter how much instruction data you add.
- Joint training lets stage-2/3 loss reshape encoder filters toward what the LLM actually consumes — e.g. preserving high-frequency text strokes useful for OCR that a pure contrastive objective would treat as noise.

**MoonViT-style hybrid encoder (why SigLIP + captioning):**
- **SigLIP half:** pairwise sigmoid loss over image-text pairs with a learnable bias, trained with chunked multi-device parallelization. Unlike CLIP's batch-softmax, each pair is an independent binary decision, which scales better to large noisy batches and small per-device batch sizes.
- **Captioning half (CapPa/CoCa-style):** an autoregressive decoder loss — predict the caption tokens conditioned on the image — forcing the encoder to retain compositional detail (attributes, relations, counts) that contrastive learning can discard once pairs are merely separable.
- Combined, the encoder enters joint VLM training already good at both matching (retrieval, zero-shot classification) and describing (dense captions) — so joint finetuning starts from a stronger point than a contrastive-only encoder.

**All-params joint training (how it differs operationally):**
- Optimizer states cover the full stack (no frozen-parameter memory savings), so batch sizes shrink or parallelism (FSDP/pipeline) grows versus LLaVA-style stages.
- Learning-rate discipline matters: the encoder typically trains at a fraction of the LLM/adapter rate (illustratively ~0.1–0.2×) to avoid destroying pretrained visual geometry in the first epochs — unfreezing without LR stratification causes the "vision collapse" where zero-shot accuracy craters before recovering.
- Text-only data must stay in every stage's mix; with the encoder moving, the forgetting pressure on language ability is strictly stronger than in frozen-encoder recipes.

### Example / Tradeoff
- **Concrete comparison:** LLaVA-1.5 aligns in ~1 day on 8×A100 with the encoder frozen; a DeepSeek-VL/Kimi-VL-style joint recipe needs the full pretraining-scale cluster for the alignment stages too — roughly an order of magnitude more encoder-side compute — in exchange for state-of-the-art document/chart grounding the frozen recipe cannot reach. (Treat both compute figures as order-of-magnitude, not measured constants.)
- **Tradeoff — when frozen wins:** Tight budget, standard natural-image QA, or a strong off-the-shelf encoder already matched to your domain → freeze (LLaVA-style). Unfreezing buys little when the encoder's pretraining distribution already covers your inputs.
- **Tradeoff — when joint wins:** OCR-heavy documents, screenshots, charts, fine-grained grounding — any domain where the generic encoder's pretraining never saw your visual distribution. That is exactly the Kimi-VL long-document and DeepSeek-VL chart/document strength story.

---

## Verbal script

**Opening (30s):**
"The one-line difference is frozen versus joint: LLaVA freezes the encoder and trains the projector, while DeepSeek-VL and Kimi-VL unfreeze everything so the encoder co-adapts with the LLM — built on hybrid MoonViT-style encoders that combine SigLIP with captioning."

**Core explanation (2–3 min):**
"A frozen encoder is a ceiling: if CLIP discarded small text or fine spatial detail during its own pretraining, no amount of instruction tuning gets it back, because gradients stop at the projector. Joint training lets stage loss reshape encoder filters toward what the LLM actually needs — preserving OCR-relevant detail, for example. The encoder side matters too: MoonViT-style means SigLIP's pairwise-sigmoid contrastive loss plus an autoregressive captioning loss, so the encoder is good at both matching and describing before joint training starts. Operationally, joint means full optimizer states, smaller batches or more parallelism, stratified learning rates — typically a tenth of the LLM rate for the encoder — and text data in every mix to hold language ability."

**Tradeoff / production angle (1 min):**
"I'd only pay for joint training when the domain demands it — documents, screenshots, charts, fine grounding. For natural-image QA on a budget, frozen-encoder LLaVA-style gets 90% of the quality at a fraction of the cost. The decision is really about whether your visual distribution was in the encoder's pretraining."

**Wrap-up (30s):**
"So: hybrid encoder for a stronger starting point, unfreeze everything with stratified LRs for max quality, and only when the domain justifies the compute."

---

## Pitfalls

- **Mistake:** "Joint training just means bigger batches / more epochs" — **Better:** "It means gradients reach the encoder, so you need stratified learning rates, full-stack optimizer memory, and text in every mix — it's an optimization-regime change, not a scale change."
- **Mistake:** "SigLIP and CLIP are interchangeable encoder choices" — **Better:** "SigLIP's pairwise-sigmoid formulation scales to noisy large batches differently than CLIP's batch-softmax, and MoonViT-style recipes add captioning on top — the encoder objective is part of the recipe decision."
- **Mistake:** "Unfreezing always helps" — **Better:** "It helps when the encoder's pretraining missed your visual distribution (documents, charts). On in-distribution natural images the frozen recipe is near-parity at far lower cost."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Walk me through the LLaVA training recipe?](12-001-llava-two-stage-recipe-synthetic-captions.md) | Prerequisite — the frozen-encoder baseline this family departs from |
| [Walk me through the Qwen-VL training recipe?](12-002-qwen-vl-scale-recipe-dpo-long-context.md) | Same concept — alternative frontier scaling path |
| [How do you budget visual tokens for images and video?](12-004-video-token-budget-frame-sampling-compression.md) | Follow-up — joint recipes still pay the same token costs |

---

## One-liner recall

> DeepSeek-VL/Kimi-VL = unfreeze everything (all-params joint training with stratified LRs) on MoonViT-style hybrid encoders (SigLIP sigmoid + captioning, per the Kimi-VL report) — removes LLaVA's frozen-encoder ceiling at roughly an order of magnitude more alignment compute, worth it for documents/charts/grounding.
