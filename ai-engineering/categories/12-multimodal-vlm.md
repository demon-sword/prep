# 12. Multimodal & VLMs — AI Engineering Interview Category

Vision-language models (VLMs) connect images and video to frozen LLMs via a vision encoder plus a lightweight adapter, trained with multi-stage recipes (align → multitask → SFT/DPO). Interviewers probe whether you can pick an adapter, budget visual tokens, and recount a concrete recipe — not whether you can name every open model.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "walk me through how you'd add image input to our chatbot" | VLM architecture + adapter choice |
| "how would you train a model that understands screenshots / PDFs / video?" | Training recipe + token budget |
| "compare LLaVA and Qwen-VL" (or any two open VLMs) | Recipe numbers + design tradeoffs |
| "our VLM forgets how to follow text instructions after vision tuning" | Text-ability preservation |
| "how do you keep inference cost down when each image is 1,000+ tokens?" | Visual token budget / dynamic resolution |
| "CLIP vs SigLIP — which encoder and why?" | Vision-encoder pretraining objectives |

---

## Mental model

Strong candidates treat a VLM as three separable decisions — **encoder** (what visual representation, e.g. CLIP-style contrastive vs SigLIP pairwise-sigmoid vs captioning-pretrained), **adapter** (how visual features enter the LLM: MLP projection, query transformer, or cross-attention mid-fusion), and **recipe** (which stages unfreeze what, in what data order) — and can attach numbers to each: pretraining pair counts, instruction-tuning sample counts, queries-per-image at a given resolution. They know visual tokens obey the same quadratic attention cost as text tokens, so resolution and frame count are budget decisions, not free quality. Weak candidates say "just attach a vision encoder to the LLM" with no stage order, no frozen/unfrozen distinction, and no token math.

---

## Sub-topics

### 1. VLM architectures and vision-language adapters
**When:** "How do VLMs feed images into an LLM?" or "compare early fusion vs cross-attention"
**What:** The adapter taxonomy — MLP projection (LLaVA-style early fusion), Q-Former query transformers (BLIP-2, two-stage with ITC/ITM/ITG objectives), Flamingo-style perceiver resampler plus gated cross-attention, and LLaMA-3.2-style cross-attention every few blocks evolving toward LLaMA-4 early fusion — combined with dynamic resolution (NaViT native resolution, tiling, Qwen's 256→1024 queries at 448px) and the Chameleon discrete-token early-fusion exception.
**Key questions:**
- [Q1: Walk me through the LLaVA training recipe?](../answers/12-001-llava-two-stage-recipe-synthetic-captions.md)
- [Q4: How do you budget visual tokens for images and video?](../answers/12-004-video-token-budget-frame-sampling-compression.md)

### 2. Multi-stage training recipes and alignment
**When:** "How was this VLM actually trained?" or "why does vision tuning hurt text ability?"
**What:** The align → multitask → SFT/DPO stage progression with less-data/higher-quality data at each step, all-parameters joint training vs frozen-encoder variants, and text-ability preservation via mixed text data — instantiated concretely by LLaVA (595K instruction samples on CC3M-pretrained projection with GPT-4-from-caption synthetic data), Qwen-VL (5B pretraining pairs → 76.8M multitask → 350K instructions, Qwen2.5 long-context plus DPO), and DeepSeek-VL / Kimi-VL / MoonViT (SigLIP plus captioning pretraining, joint all-params training).
**Key questions:**
- [Q1: Walk me through the LLaVA training recipe?](../answers/12-001-llava-two-stage-recipe-synthetic-captions.md)
- [Q2: Walk me through the Qwen-VL training recipe?](../answers/12-002-qwen-vl-scale-recipe-dpo-long-context.md)
- [Q3: How do DeepSeek-VL, Kimi-VL, and MoonViT differ from LLaVA-style recipes?](../answers/12-003-deepseek-vl-kimi-vl-moonvit-joint-training.md)

### 3. Terminology, open-model landscape, and evaluation
**When:** "What's the difference between an LLM, a VLM, and an MLLM?" or "which open VLM would you start from?"
**What:** LLM (text-only) vs VLM (vision + language, usually image+text) vs MLLM (three or more modalities, e.g. adding video/audio); the open-model landscape (PaliGemma, DeepSeek-VL, Qwen-VL, Kimi-VL, GLM-family vision variants) mapped to their encoder/adapter/recipe choices; and evaluation by capability slice (vision QA, OCR-heavy document understanding, grounding/referring) rather than a single score.
**Key questions:**
- [Q2: Walk me through the Qwen-VL training recipe?](../answers/12-002-qwen-vl-scale-recipe-dpo-long-context.md)
- [Q3: How do DeepSeek-VL, Kimi-VL, and MoonViT differ from LLaVA-style recipes?](../answers/12-003-deepseek-vl-kimi-vl-moonvit-joint-training.md)
- [Q4: How do you budget visual tokens for images and video?](../answers/12-004-video-token-budget-frame-sampling-compression.md)

---

## Decision framework

```
Choosing a VLM adapter:
  If you need the cheapest path to a working image+text model:
    → MLP projection (LLaVA-style early fusion)  because one trainable matrix maps
       encoder features into LLM token space; stage-1 trains only the projector
  If the encoder output is long and you must compress before the LLM:
    → Query transformer (BLIP-2 Q-Former, ITC/ITG/ITM two-stage)  because a fixed
       set of learned queries distills variable-length visual features to N tokens
  If you must preserve the frozen LLM exactly and fuse deeply:
    → Gated cross-attention mid-fusion (Flamingo perceiver resampler; LLaMA-3.2
       cross-attention every 4th block)  because tanh-gated layers start as identity
       and add vision capacity without disturbing text behavior
  If the task needs generation in pixel space (not just understanding):
    → Discrete-token early fusion (Chameleon VQ-VAE tokens)  because the same
       autoregressive loss then covers both modalities

Choosing a training recipe:
  If starting from scratch with a modest budget:
    → LLaVA-style two-stage (projector pretrain on CC3M-scale pairs, then joint
       instruction finetune on ~595K samples incl. GPT-4-from-caption synthetic)
  If operating at frontier scale with long documents/video:
    → Qwen-VL-style three-stage (5B-pair pretrain → 76.8M multitask → 350K
       instructions) plus long-context extension and DPO on top
  If you can afford full joint optimization and want max quality:
    → All-params joint training (DeepSeek-VL / Kimi-VL / MoonViT style, SigLIP
       plus captioning encoder)  because unfreezing the encoder lets visual
       features co-adapt with the LLM

Budgeting visual tokens:
  If single image, detail matters (documents, screenshots):
    → Dynamic resolution / tiling (NaViT-style; Qwen uses up to 1024 queries at
       448px)  because fixed low-res downsampling destroys OCR-relevant detail
  If video:
    → 1 FPS sampling + spatial compression first  because naive frame
       concatenation multiplies the token bill by frame count (see Q4 math)
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| Saying "concatenate the image tokens" with no count — ignoring that a 448px tiled image can cost 1,000+ tokens and video multiplies that per frame | "At Qwen's dynamic resolution an image can produce up to 1024 visual queries at 448px, so each image is roughly a thousand-token prompt prefix. For video I sample at 1 FPS and compress spatially first, otherwise 60 seconds of video is tens of thousands of tokens before any text." |
| Describing VLM training as single-stage fine-tuning ("just train on image-text pairs") | "It's staged: align the projector on large-scale pairs first with everything else frozen, then multitask pretrain, then instruction-tune on a smaller high-quality mix, then DPO. Each stage uses less data of higher quality, and text-only data stays in the mix so the model doesn't lose text ability." |
| Claiming the vision encoder choice doesn't matter because "the LLM does the reasoning" | "The encoder sets the ceiling: contrastive (CLIP), pairwise-sigmoid (SigLIP), and captioning-pretrained (CapPa/CoCa-style) encoders produce different feature geometry, and recipes like MoonViT deliberately combine SigLIP with captioning. I'd pick the encoder the recipe was co-designed with." |
| Treating "VLM" and "MLLM" as synonyms | "VLM usually means vision+language specifically; MLLM means three or more modalities — e.g. a model handling image, video, and audio alongside text. The distinction matters because each added modality needs its own encoder, adapter, and token budget." |
| Evaluating a VLM with a single accuracy number | "I slice by capability: general vision QA, OCR-heavy document understanding, and grounding/referring expression. A model can top vision QA while failing document OCR if its pretraining resolution was too low — one number hides that." |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | Walk me through the LLaVA training recipe? | M | `review` |
| 2 | Walk me through the Qwen-VL training recipe? | M | `review` |
| 3 | How do DeepSeek-VL, Kimi-VL, and MoonViT differ from LLaVA-style recipes? | S | `review` |
| 4 | How do you budget visual tokens for images and video? | M | `review` |

---

## One-page summary

- **Three decisions**: encoder (CLIP contrastive / SigLIP sigmoid / captioning-pretrained) → adapter (MLP early fusion / Q-Former queries / gated cross-attention mid-fusion / Chameleon discrete tokens) → staged recipe (align → multitask → SFT/DPO, shrinking data volume and rising quality per stage).
- **LLaVA numbers**: projector pretrain on CC3M-scale pairs, then joint instruction finetune on ~595K samples including GPT-4-from-caption synthetic data.
- **Qwen-VL numbers**: 5B pretraining pairs → 76.8M multitask → 350K instructions; Qwen2.5 adds long-context extension plus DPO.
- **Joint-training variant**: DeepSeek-VL / Kimi-VL / MoonViT unfreeze everything (all-params joint training) on SigLIP-plus-captioning encoders instead of freezing the encoder.
- **Token budget**: dynamic resolution up to ~1024 queries per image at 448px; video sampled at ~1 FPS with spatial compression, because frame concatenation multiplies cost per frame under quadratic attention.
