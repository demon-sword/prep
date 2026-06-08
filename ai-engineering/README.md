# AI Engineer Interview Prep

Interview question bank and study notes for **Applied AI / LLM Engineer** roles (2026 focus).

## What changed in 2026

| Era | Interview focus |
|-----|-----------------|
| 2023 | CNNs, gradient descent, classical ML (~75%) |
| 2026 | GenAI / LLM apps (~60–75%), classical ML (~20–30%) |

**Highest-signal topics:** RAG pipeline design, evaluation, system design at scale, agents, cost/latency.

## Folder layout

```
ai-engineering/
├── README.md                 # this file
└── interview-questions.md    # full question bank (patterns + ranked + by category)
```

## How to study

1. **Start with top 15** in `interview-questions.md` — answer each out loud in 3–5 min.
2. **Master the RAG pattern** — 9-stage pipeline + failure modes + eval metrics.
3. **One system design cold** — "Design a RAG system for customer support at 1M users."
4. **Project deep dive** — prepare a 10-min walkthrough of one shipped AI project with metrics.
5. **Keep DSA going** — see [`../dsa/`](../dsa/) for FAANG-style coding rounds.

## Prep priority (80/20)

| Priority | Topic |
|----------|-------|
| 1 | RAG end-to-end (design + debug + evaluate) |
| 2 | Prompt vs RAG vs fine-tuning decision tree |
| 3 | Evaluation framework (golden set, faithfulness, regression) |
| 4 | System design: customer support RAG at scale |
| 5 | Transformers, tokenization, embeddings |
| 6 | Agents vs chains, tool use, when NOT to use agents |
| 7 | LeetCode medium (if targeting FAANG) |

## Related prep in this repo

- [DSA (NeetCode 150)](../dsa/README.md) — coding rounds
- [System design](../system-design/) — architecture interview format

## Sources

Questions compiled from 100+ real interview reports (2024–2026):

- [Adil Shamim — 100+ Real Interviews](https://adilshamim8.medium.com/every-ai-engineer-interview-question-you-need-to-know-in-2026-from-100-real-interviews-b5b7ae4b961a)
- [LockedIn AI — frequency heatmap](https://www.lockedinai.com/blog/ai-engineer-interview-questions)
- [IGotAnOffer / Glassdoor reports](https://igotanoffer.com/en/advice/ai-engineer-interview)
- [gitGood — RAG interview guide](https://gitgood.dev/blog/complete-guide-rag-interview-questions-2026)
- [Careery — 2026 AI interview trends](https://careery.pro/blog/ai-careers/ai-engineer-interview-questions)
