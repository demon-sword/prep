# Ralph Concepts — Interactive HTML Generator

Generates **self-contained interactive HTML files** for every AI Engineering concept — one file per concept, theory + live visualization.

## Quick start

```bash
# 1. Scaffold the plan
./ralph-concepts/scaffold.sh

# 2a. Generate one concept — next in queue
./ralph-concepts/once.sh

# 2b. Generate a specific concept by id
./ralph-concepts/once.sh 06-qkv-attention

# 3a. Run the full loop (all 36)
./ralph-concepts/loop.sh

# 3b. Run a specific concept (useful to retry a failed one)
./ralph-concepts/loop.sh 16-lora

# 4. Validate all generated files
./ralph-concepts/validate.sh

# 4b. Validate a single concept
./ralph-concepts/validate.sh 06-qkv-attention
```

## See available concept IDs

```bash
./ralph-concepts/once.sh --help
```

## What it generates

For each of the 36 concepts in `concepts.json`, one HTML file at:
```
ai-engineering/concepts/<id>-<slug>.html
```

Each file is **fully self-contained** — open directly in a browser, no server needed.

### HTML structure
| Section | Content |
|---------|---------|
| `<header>` | Title, group badge, one-sentence description |
| `#theory` | Deep theory: mechanism, tradeoffs, real numbers, production context |
| `#visualization` | Interactive JS viz (vanilla JS + Canvas/SVG, no CDN) |
| `#takeaways` | 4–6 senior-level insights |
| `.concept-nav` | Prev/next navigation between concepts |

## Concepts (36 total)

| Group | Concepts |
|-------|---------|
| **Foundations** | Self-Supervision, Seq2Seq, RNN, RWKV, Chinchilla Scaling, Bottlenecks, Open Weight vs Open Source |
| **Transformers** | Overview, Prefill & Decode, QKV Attention |
| **Training** | Post-Training, RLHF, DPO, Best-of-N, Memory Bottlenecks, Loss Functions, Dataset Engineering |
| **Fine-tuning** | Overview & Decision, Types (Full/Partial/PEFT), LoRA, Distillation, Multi-task, Hyperparams |
| **Inference** | Token Sampling, Prompt Engineering, Prompt Attacks, Inference Optimization, Speculative Decoding, Model Parallelism |
| **RAG** | RAG Overview, Vector Search |
| **Agents** | Agent Overview, Agent Memory |
| **Evaluation** | Evaluation Metrics, Evaluation Pipeline, Loss Functions, Model Evaluation Workflow |

## Scripts

| Script | Purpose |
|--------|---------|
| `scaffold.sh` | Build/refresh `plan.md` from `concepts.json` |
| `once.sh [--model slug]` | Generate ONE concept (pick from plan.md) |
| `loop.sh [max] [--model slug]` | Loop until all concepts done |
| `validate.sh [concept-id]` | Structural validation of generated HTML files |

## Design system

All files match the dark terminal theme from the existing AI Engineering HTML suite:
- Background: `#0d0f17`
- Accent: `#00d4ff` (cyan)
- Fonts: Inter + JetBrains Mono (Google Fonts CDN)
- No other external dependencies

## Testing

Each concept is tested by the generating agent via **Playwright MCP**:
1. Navigate to the file URL
2. Screenshot to confirm render
3. Check console for JS errors
4. Fix and re-test if needed

## Environment variables

| Var | Default | Description |
|-----|---------|-------------|
| `RALPH_CONCEPTS_MODEL` | (claude default) | Model slug to use |
| `RALPH_CONCEPTS_TIMEOUT` | `3600` | Agent timeout in seconds |

## Shared environment

| Var | Default | Effect |
|---|---|---|
| `RALPH_MAX_ATTEMPTS` | 3 | Rejections before the run gives up |
| `RALPH_SKIP_FACTCHECK` | 0 | `1` skips the adversarial fact-check pass |
| `RALPH_FACTCHECK_TIMEOUT` | 900 | Seconds for the fact-check pass |
| `RALPH_LOOP_SLEEP` | 5 | Seconds `loop.sh` pauses between iterations |
| `RALPH_MAX_STALLS` | 3 | Consecutive no-output iterations before the loop stops |
| `RALPH_CORPUS_FINAL` | — | `1` makes `validate-corpus.sh` apply its completeness gate |
