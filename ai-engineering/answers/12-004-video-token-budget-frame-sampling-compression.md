# How do you budget visual tokens for images and video?

**Category:** 12-multimodal-vlm
**Question #:** 004
**Source section:** §23 in interview-questions.md
**Status:** `review`
**Generated:** paper-build-vlm-cat

---

## Framing

### Why this question is asked
Every image in a VLM is a prompt prefix of hundreds to thousands of tokens, and video multiplies that per frame — under quadratic attention, naive frame concatenation explodes both context and cost. Interviewers ask this to test whether you do token math before designing: sampling rates, spatial compression, and the resulting context budget, not just "feed frames to the model."

### Trigger phrases
- "How would you build a VLM over hour-long videos?"
- "Each image costs how many tokens in your design?"
- "Our multimodal inference bill exploded — what do you check?"

### What it tests
Quantitative visual-token budgeting: per-image query counts, frame-sampling arithmetic, compression options, and the attention-cost consequence.

---

## Answer

### Concept
**Visual-token budgeting** treats every image as a token bill — a dynamic-resolution image costs 256 to ~1024 visual queries at 448px — and every video as that bill times frame count, so production designs sample sparsely (**~1 FPS**), compress spatially (**Conv3D 3D patches**, perceiver-style resampling), and compress temporally (**run-length tokenization** of static spans) before anything reaches the LLM.

### Mechanism

**Per-image math (the unit cost):**
- A fixed 224px ViT/16 encoder emits 196 tokens; 336px emits 441. Dynamic-resolution designs (NaViT tiling, Qwen-style) emit 256 for small images up to ~1024 visual queries at 448px for detail-heavy inputs.
- Under standard attention, 1024 visual tokens cost the same as 1024 text tokens *plus* their quadratic interaction with the rest of the context: attention FLOPs scale with (visual + text)², so a 1K-token image inside a 4K context roughly doubles attention work versus the 3K text tokens alone.

**Naive video math (why it breaks):**
- Frame concatenation at 30 FPS × 60 seconds = 1800 frames. Even at a lean 256 tokens/frame that is ~460K tokens — before any text, and far past most context windows. At 1024 queries/frame it exceeds 1.8M tokens. Naive concatenation is never the design.

**The three compression levers, in order:**
1. **Temporal sampling — ~1 FPS:** Sample one frame per second (1800 → 60 frames for a minute of video). Assumption: most video semantics change at second granularity, not frame granularity. Fast-action content (sports, inspection) needs adaptive sampling, not blind 1 FPS.
2. **Spatial compression — Conv3D patches / resampling:** Instead of per-frame 2D patches, 3D convolution over space+time emits tubelet tokens spanning multiple frames, cutting per-frame tokens several-fold. Alternatively a perceiver-style resampler distills each frame (or frame group) to a fixed small query set, exactly the Flamingo/Q-Former idea applied temporally.
3. **Temporal compression — run-length tokenization:** Static spans (slides, talking heads, parked scenes) repeat near-identical frames; run-length schemes emit one token span plus a count/duration instead of N copies. This is where hour-long videos become feasible: real content has enormous static redundancy.

**Worked budget:** 60s video → 1 FPS = 60 frames → Conv3D/resample to ~64 tokens/frame = ~3.8K visual tokens → run-length on static spans halves it to ~2K. That fits comfortably in a 32K window with room for text — versus 460K+ naive.

### Example / Tradeoff
- **Concrete system:** Document/screenshot QA uses the opposite corner from video: single image, full 1024-query dynamic resolution, no temporal lever available — so the budget goes to tiling (process regions) rather than sampling. Same framework, different lever.
- **Tradeoff — 1 FPS sampling:** Misses sub-second events (a defect flashing past on a production line, a foul in sports). Fix is content-adaptive sampling (motion-gated densification), at the cost of variable token counts that complicate batching.
- **Tradeoff — aggressive spatial compression:** 64 tokens/frame destroys small-text legibility. If the task is OCR-over-video (read every slide), compress temporally first and keep spatial resolution — lever choice follows the task's information location.

---

## Verbal script

**Opening (30s):**
"I'd start with the unit cost: one detail-heavy image is up to about a thousand visual tokens, and video multiplies that by frame count — so naive concatenation of a minute of video is half a million tokens. Budgeting means three levers."

**Core explanation (2–3 min):**
"First lever is temporal sampling: 1 frame per second takes 1800 frames down to 60 for a minute. Second is spatial: 3D-conv tubelets or a perceiver-style resampler cut each frame from hundreds of tokens to tens. Third is temporal compression: run-length tokenization collapses static spans into one span plus a duration. Worked out, 60 seconds goes from ~460K tokens naive to roughly 2–4K — fits in a normal context window. And the per-image math matters too: dynamic resolution means a document screenshot can legitimately cost 1024 queries at 448px, roughly doubling attention work inside a 4K context."

**Tradeoff / production angle (1 min):**
"Lever choice follows the task: OCR-over-video keeps spatial resolution and compresses time; action detection keeps frame rate and compresses space. And adaptive sampling gives variable token counts, so I'd plan the batching and KV-cache padding story before promising it."

**Wrap-up (30s):**
"Sample at 1 FPS, compress spatially, run-length the static spans — and always show the arithmetic before proposing the architecture."

---

## Pitfalls

- **Mistake:** "Feed all frames through the encoder and concatenate" — **Better:** "30 FPS × 60s × 256 tokens is ~460K tokens before any text. Sample at ~1 FPS, then spatial and run-length compression — show the budget first."
- **Mistake:** Treating visual tokens as cheaper than text tokens in attention math — **Better:** "Attention is quadratic in total sequence length; 1K visual tokens inside a 4K context roughly doubles attention FLOPs versus the 3K text tokens alone. Resolution is a cost decision."
- **Mistake:** "Compress everything uniformly" — **Better:** "Match the lever to the information: keep spatial detail for OCR-over-video, keep frame rate for action detection. Uniform compression destroys exactly what the task needs."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Walk me through the LLaVA training recipe?](12-001-llava-two-stage-recipe-synthetic-captions.md) | Prerequisite — where the visual tokens being budgeted come from |
| [How do DeepSeek-VL, Kimi-VL, and MoonViT differ from LLaVA-style recipes?](12-003-deepseek-vl-kimi-vl-moonvit-joint-training.md) | Same concept — joint recipes pay identical token costs |
| [How to reduce token costs at scale?](07-002-how-reduce-token-costs-at-scale.md) | Same concept — text-side cost discipline applied to visual tokens |

---

## One-liner recall

> Video token budget = 1 FPS sampling → Conv3D/resampler spatial compression → run-length on static spans turns ~460K naive tokens per minute into ~2–4K; single images cost 256–1024 queries by resolution, and attention bills all of it quadratically.
