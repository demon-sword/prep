# Walk me through the LLaVA training recipe?

**Category:** 12-multimodal-vlm
**Question #:** 001
**Source section:** §TBD — no VLM bank section in interview-questions.md yet; stems land with File AU (C21)
**Status:** `review`
**Generated:** paper-build-vlm-cat

---

## Framing

### Why this question is asked
LLaVA is the reference "cheap path to a working VLM" recipe: a frozen CLIP-style encoder, a frozen LLM, and a two-stage procedure where only a projection matrix is trained first. Interviewers ask this to check whether you understand staged multimodal alignment — what is frozen when, why the stages are ordered, and where the instruction-following data actually comes from — rather than a vague "train on image-text pairs."

### Trigger phrases
- "How would you add image input to an LLM on a budget?"
- "Walk me through LLaVA — why two stages?"
- "Where does VLM instruction-tuning data come from?"

### What it tests
Understanding of staged adapter alignment, frozen/unfrozen parameter choices per stage, and synthetic instruction-data construction.

---

## Answer

### Concept
**LLaVA (Large Language-and-Vision Assistant)** turns a frozen vision encoder plus a frozen LLM into a visual chatbot by training a single **MLP projection layer** that maps visual features into the LLM's token embedding space. Training runs in two stages: stage 1 aligns the projector on 558K image-text pairs (LCS-558K) with everything else frozen; stage 2 jointly finetunes the projector and the LLM on visual instruction samples — 158K GPT-4-from-caption synthetic samples in v1, expanded to a 665K-sample mix in LLaVA-1.5.

### Mechanism

**Stage 1 — feature alignment pretraining:**
- Vision encoder (CLIP-style) and LLM are both **frozen**. Only the projection matrix W (visual-dim → LLM-embed-dim) trains.
- Data: LCS-558K — 558K image-text pairs (LAION/CC/SBU subset re-captioned by BLIP), i.e. hundreds of thousands of noisy but plentiful pairs.
- Objective: standard next-token prediction on the caption conditioned on projected visual features. This teaches W one thing: "put this image patch roughly where its words live in embedding space."
- Cheap by design: gradients flow through one matrix, so this stage runs in hours on a small cluster.

**Stage 2 — visual instruction finetuning:**
- **Unfreeze the LLM** (or train it with LoRA/PEFT); keep the vision encoder frozen. Train projector + LLM jointly.
- Data: v1 uses LLaVA-Instruct-158K (158K instruction-following samples mixing multitask academic VQA reformatted as instructions, caption-grounded conversation, and complex-reasoning examples); LLaVA-1.5 expands the mix to ~665K samples by adding academic-VQA data.
- The key trick is **GPT-4-from-caption synthesis**: take a COCO image's human captions and bounding boxes (text only, no pixels), prompt GPT-4 to invent a conversation / detailed description / multi-step reasoning QA about the image, and keep the pairs that survive filtering. This converts a strong text-only teacher into vision supervision without human labeling of 158K conversations.

**Why this order matters:**
- If you skip stage 1, the randomly initialized projector emits garbage embeddings that corrupt the LLM's representations on the first gradient steps — stage 1 puts W in a sane neighborhood first.
- If you skip stage 2, you get a captioner, not an assistant: the model describes but cannot follow instructions, refuse, or reason.

### Example / Tradeoff
- **Concrete system:** LLaVA-1.5 upgraded the recipe with an MLP (two-layer, not linear) projector and academic-VQA data in the stage-2 mix, reaching then-SOTA on 11 vision benchmarks with ~1 day of 8×A100 training — the canonical "grad-student budget VLM" result.
- **Tradeoff — frozen encoder:** Freezing the encoder keeps stage 1 cheap and preserves CLIP's zero-shot geometry, but caps visual detail: the LLM can never ask the encoder for finer features than CLIP was trained to emit. All-params recipes (DeepSeek-VL/Kimi-VL style, see Q3) remove this ceiling at full-training cost.
- **Tradeoff — synthetic data:** GPT-4-from-caption data inherits caption blind spots (captions omit small text, counts, spatial relations), so synthetic conversations hallucinate details the caption never mentioned. Production recipes filter with a second model or mix in human-verified grounding data.

---

## Verbal script

**Opening (30s):**
"I'd start by saying LLaVA's insight is that you don't need to train a vision model and a language model jointly from scratch — you align a tiny projector first, then teach instruction-following. Two stages, different frozen sets, different data."

**Core explanation (2–3 min):**
"Stage 1 freezes both the CLIP-style encoder and the LLM and trains only the projection matrix on 558K image-text pairs (LCS-558K) — that puts visual features into the LLM's embedding space without disturbing either pretrained model. Stage 2 unfreezes the LLM and finetunes projector plus LLM on instruction samples: 158K in v1, a ~665K mix in LLaVA-1.5. A large share is synthetic: they feed COCO captions and boxes — text only — to GPT-4 and have it invent conversations and reasoning questions about the image. The order matters: skip stage 1 and a random projector corrupts the LLM on step one; skip stage 2 and you have a captioner, not an assistant."

**Tradeoff / production angle (1 min):**
"The frozen encoder is the ceiling — the LLM only ever sees what CLIP emits, so fine OCR or small text in screenshots suffers, which is why later recipes unfreeze everything. And synthetic data inherits caption blind spots, so I'd budget for a filtering pass or human-verified grounding data before trusting it in production."

**Wrap-up (30s):**
"So: align the projector cheaply on pairs, then instruction-tune jointly on a smaller high-quality mix that's heavily synthetic. That's the template every later recipe varies."

---

## Pitfalls

- **Mistake:** "LLaVA trains the vision encoder and LLM together on image-text pairs" — **Better:** "Stage 1 freezes both and trains only the projector on 558K pairs (LCS-558K); the LLM unfreezes only in stage 2 on the instruction mix (158K v1 / ~665K in 1.5)."
- **Mistake:** "The instruction samples are human-labeled conversations" — **Better:** "Much of it is GPT-4-from-caption synthetic — GPT-4 invents conversations from COCO captions and boxes without seeing pixels — which is why filtering and grounding data matter."
- **Mistake:** "Freezing the encoder is pure win (cheaper, no forgetting)" — **Better:** "It's a ceiling tradeoff: cheap and stable, but the LLM can never extract finer visual detail than the frozen encoder emits."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Walk me through the Qwen-VL training recipe?](12-002-qwen-vl-scale-recipe-dpo-long-context.md) | Follow-up — same staged template at frontier scale |
| [How do DeepSeek-VL, Kimi-VL, and MoonViT differ from LLaVA-style recipes?](12-003-deepseek-vl-kimi-vl-moonvit-joint-training.md) | Same concept — removes the frozen-encoder ceiling |
| [What is PEFT/LoRA and when use it?](04-002-what-is-peftlora-and-when-use-it.md) | Prerequisite — stage-2 LLM updates are often LoRA |

---

## One-liner recall

> LLaVA = freeze encoder+LLM, train only the projector on 558K pairs LCS-558K (stage 1), then unfreeze the LLM and instruction-tune jointly — 158K GPT-4-from-caption synthetic samples in v1, ~665K-sample mix in LLaVA-1.5 (stage 2).
