# Scalable efficient LLM training system — compute and data constraints

**Category:** 04-fine-tuning-training
**Question #:** 007
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing senior-level systems thinking: can you architect the full training stack from data pipeline to GPU cluster orchestration under real-world constraints? This is a design question, not a theory question — strong candidates name specific techniques (tensor parallelism, gradient checkpointing, BF16 mixed precision), quantify their impact, and explain what breaks at scale.

### Trigger phrases
- "Design a scalable LLM training system."
- "How would you train a large model under compute and data constraints?"
- "Walk me through how you'd set up distributed training for a fine-tuning run."

### What it tests
Ability to reason across the full training stack — parallelism strategies, memory optimization, data pipeline throughput, and fault tolerance — under realistic budget and hardware constraints.

---

## Answer

### Concept
Scalable LLM training requires co-designing three systems: a **parallelism strategy** that splits model + data across GPUs, a **memory optimization stack** that reduces per-GPU footprint, and a **data pipeline** that keeps GPUs fed without becoming the bottleneck. The core tension is GPU utilization vs memory pressure vs communication overhead — every technique involves a tradeoff between these three.

### Mechanism

**1. Parallelism strategies (choose by model size and cluster topology)**

| Strategy | What it splits | When to use | Overhead |
|----------|---------------|-------------|----------|
| **Data parallelism (DDP)** | Batch across GPUs; each GPU holds full model | Model fits in 1 GPU's VRAM | AllReduce gradient sync (NVLink: low, cross-node: high) |
| **Tensor parallelism (TP)** | Individual weight matrices split column/row across GPUs | Large weight matrices; same node (NVLink) | All-reduce per layer forward/backward |
| **Pipeline parallelism (PP)** | Layers split across GPUs/nodes | Model too large for tensor parallelism alone; multi-node | Bubble time (idle GPU cycles between micro-batches) |
| **ZeRO (DeepSpeed)** | Optimizer state / gradients / parameters sharded across GPUs | Single-machine or small cluster; maximizes utilization | Gather/scatter communication on backward pass |

Production default for SFT fine-tuning at 7B–70B scale: **DDP + ZeRO Stage 2** (optimizer state + gradient sharding) via DeepSpeed or FSDP (PyTorch native). For pre-training at 100B+: **3D parallelism** (TP + PP + DP), as used in Megatron-LM (GPT-3, Llama).

**2. Memory optimization stack**

- **Mixed precision (BF16):** Store weights in BF16 (half the memory of FP32), keep a FP32 master copy for optimizer updates. BF16 preferred over FP16 for training stability (larger dynamic range). On H100s, FP8 is available via Transformer Engine.
- **Gradient checkpointing:** Recompute activations on the backward pass instead of storing them. Saves ~60–70% activation memory at the cost of ~33% extra compute (one additional forward pass). Essential for long-sequence or large-batch runs.
- **ZeRO-Offload:** Offload optimizer state to CPU RAM (Stage 3 + offload). Enables 30B+ training on a single 8×A100 node at the cost of CPU↔GPU PCIe bandwidth becoming a bottleneck.
- **Flash Attention 2:** Tiling reduces attention activation memory from O(n²) to O(n), enabling long-context training without OOM.

**3. Data pipeline (don't let the GPU starve)**

- Pre-tokenize and shard the dataset offline into `n_shards` HuggingFace Arrow datasets or WebDataset `.tar` shards. Streaming from object storage (S3/GCS) during training avoids local disk limits.
- Multi-worker `DataLoader` with `prefetch_factor=4` to overlap CPU tokenization with GPU forward pass.
- **Data quality at scale:** Deduplication (MinHash LSH, MassiveText approach), quality classifiers (fastText trained on curated vs. web text), and domain weighting (upweight code, math, scientific papers). Chinchilla scaling laws (20 tokens/param optimal) dictate the data budget: a 7B model needs ~140B high-quality tokens.
- **Curriculum learning:** Start with easier / shorter sequences, introduce harder data later. Reduces instability in early training and improves final loss at the same compute budget.

**4. Fault tolerance**

- Checkpoint every N steps (N = 100–500 depending on cluster reliability). Use async checkpointing (Torch Distributed Checkpoint) to avoid blocking the training process.
- Detect GPU failures via heartbeat and auto-restart from latest checkpoint (SLURM `--requeue` or Kubernetes with `restartPolicy: OnFailure`).
- Track training metrics (grad norm, loss, learning rate) in real time (W&B or TensorBoard) with alerts on loss spikes or NaN gradients.

### Example / Tradeoff

**A 70B-class open-weight model, SFT on 32× H100s:**
- Parallelism: DDP + ZeRO Stage 2 (DeepSpeed) per node; 4-node cluster; NVLink within node.
- Precision: BF16 forward/backward, FP32 optimizer (AdamW), gradient clipping at 1.0.
- Gradient checkpointing: enabled; ~33% compute overhead recovered by 2× batch size increase.
- Batch: global batch size 512 (8 GPUs/node × 4 nodes × per-GPU batch 16).
- Data: 1B token SFT dataset streamed from S3; 16 DataLoader workers per node.
- Result: ~2.1 tokens/second/GPU; full run ≈ 48 hours.

**Key tradeoff — ZeRO Stage 2 vs 3:**
- Stage 2 (optimizer + gradient sharding): low communication overhead, model weights still replicated. Good for models that fit per-GPU in BF16.
- Stage 3 (parameter sharding too): enables training models that don't fit per GPU, but adds gather/scatter on every layer during the forward pass — can drop GPU utilization from 55 to 38% MFU if communication bandwidth is the bottleneck.

---

## Verbal script

**Opening (30s):**
"I'd approach this as three co-designed subsystems: the parallelism strategy that maps model and data to GPUs, the memory optimization stack that determines what fits, and the data pipeline that keeps GPUs fed. The core constraint is always the same — you're trying to maximize GPU utilization while staying within VRAM budget and communication bandwidth limits."

**Core explanation (2–3 min):**
"Starting with parallelism: for a 7B–70B fine-tuning run, I'd default to DDP with ZeRO Stage 2 via DeepSpeed or FSDP. That shards optimizer state and gradients across GPUs — typically 4–8× memory reduction vs vanilla DDP — without the communication overhead of full parameter sharding. For pre-training at 100B+ you need 3D parallelism: tensor parallelism within a node over NVLink, pipeline parallelism across nodes, data parallelism across pipeline replicas. That's what Megatron-LM uses.

On memory: I always enable BF16 mixed precision — it halves weight memory vs FP32 and is more numerically stable than FP16. Gradient checkpointing is almost always worth it — costs about 33% extra compute but saves 60–70% of activation memory, which lets you double your batch size or train on longer sequences. For long-context work, FlashAttention 2 is mandatory — it keeps attention memory linear instead of quadratic.

Data pipeline is often the silent bottleneck. I pre-tokenize and shard the dataset offline into Arrow shards or WebDataset tars, stream from object storage, and use 16 DataLoader workers per node with prefetch. For data quality at this scale, you need deduplication with MinHash LSH and quality classifiers — raw web data is too noisy to train on directly. Chinchilla tells us we need roughly 20 tokens per parameter of high-quality data, so a 7B model needs ~140B tokens."

**Tradeoff / production angle (1 min):**
"The main failure modes I watch for are: NaN gradients from FP16 overflow — BF16 largely solves this but I still clip gradients at 1.0; GPU starvation from a slow data pipeline — profiler shows it as GPU utilization dropping below 80%; and ZeRO Stage 3 communication overhead if inter-node bandwidth is the bottleneck — sometimes Stage 2 with more nodes is faster than Stage 3 with fewer. I checkpoint every 200 steps with async checkpointing so a node failure costs at most 10 minutes, not hours."

**Wrap-up (30s):**
"So the summary is: DDP + ZeRO Stage 2 as the default for SFT, 3D parallelism for pre-training at scale, BF16 + gradient checkpointing + FlashAttention for memory, and a pre-tokenized streaming data pipeline with quality filtering. Happy to go deeper on any layer — parallelism, data, or fault tolerance."

---

## Pitfalls

- **Mistake:** Saying "just use multi-GPU training" without specifying the parallelism strategy (DDP vs tensor vs pipeline vs ZeRO) or explaining why one is chosen over another — **Better:** Name ZeRO Stage 2/FSDP as the production default for fine-tuning, explain that tensor parallelism requires NVLink bandwidth and is mainly for pre-training at 100B+ scale, and note that ZeRO Stage 3 can hurt utilization if cross-node bandwidth is a bottleneck.
- **Mistake:** Ignoring the data pipeline ("just feed the data in") without mentioning pre-tokenization, streaming from object storage, DataLoader workers, or data quality (deduplication, quality classifiers) — **Better:** Explain that at 140B token scale, the data pipeline must be pre-tokenized offline, streamed from S3/GCS shards, and quality-filtered; otherwise the CPU becomes the bottleneck and GPU utilization drops below 50%.
- **Mistake:** Treating gradient checkpointing as "free" — **Better:** State the tradeoff explicitly: ~33% extra compute (one recomputed forward pass per layer) in exchange for 60–70% activation memory savings, and explain that this usually enables a 1.5–2× batch size increase that more than offsets the compute cost.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q6: Design a model for math problems — data, SFT, post-training, eval](04-006-design-a-model-for-math-problems-data-sft-post-training-eval.md) | Concrete end-to-end training design example using this infrastructure |
| [Q2: What is PEFT/LoRA and when use it?](04-002-what-is-peftlora-and-when-use-it.md) | LoRA dramatically reduces compute and memory requirements for fine-tuning — the complement to full training system design |
| [Q10: Speculative decoding — speed up inference?](04-010-speculative-decoding-speed-up-inference.md) | Inference-side efficiency; same GPU/memory reasoning applied to serving instead of training |

---

## One-liner recall

> Scale LLM training with ZeRO Stage 2 / FSDP for parallelism, BF16 + gradient checkpointing + FlashAttention for memory, and a pre-tokenized streaming data pipeline with MinHash dedup and Chinchilla-calibrated data volume.
