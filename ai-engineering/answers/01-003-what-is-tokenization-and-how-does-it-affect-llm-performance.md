# What is tokenization and how does it affect LLM performance?

**Category:** 01-llm-fundamentals
**Question #:** 003
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Tokenization is a surprisingly deep topic that separates candidates who have read documentation from those who've dealt with real production LLM systems. The interviewer is checking whether you understand the cost implications (tokens = billing), context window consumption, vocabulary coverage failures in specialized domains (medical, legal, code), and how tokenization quirks cause model failures (e.g., failing to count letters, arithmetic errors). Mid-level candidates hit the "BPE splits words into subwords" answer; senior candidates explain *why* this matters for your specific deployment.

### Trigger phrases
- "What is tokenization and why does it matter?"
- "How does tokenization affect cost and context windows?"
- "Why do LLMs sometimes fail on simple string operations?"
- "What are the risks of using a general-purpose tokenizer on medical/legal text?"

### What it tests
Understanding of the text preprocessing pipeline before LLM inference, and the downstream effects on cost, context utilization, model capability, and domain adaptation.

---

## Answer

### Concept
Tokenization is the process of converting raw text into a sequence of integer IDs (tokens) that the model can process. Rather than operating on characters or words, modern LLMs use **subword tokenization** — algorithms like BPE (Byte-Pair Encoding) or WordPiece that split text into frequently-occurring subword units. A "token" is typically 3–4 characters of English text on average, meaning 1K words ≈ 750 tokens. The entire LLM — from context windows to pricing to inference speed — is measured in tokens, making tokenization the foundational unit of LLM engineering.

### Mechanism
**Byte-Pair Encoding (BPE) — used by the GPT and Llama families:**
1. Start with a character-level vocabulary.
2. Iteratively merge the most frequent adjacent pair of tokens into a single new token.
3. Repeat until vocabulary size target is reached (e.g., 50K for GPT-2; ~100K–128K for modern frontier and open-weight models).
4. At inference: apply the learned merge rules to split input text into the longest matching tokens.

**WordPiece — used by BERT, embedding models:**
- Similar to BPE but chooses merges that maximize language model likelihood, not just frequency.
- Marks subword continuations with `##` (e.g., "unbelievable" → ["un", "##believ", "##able"]).

**SentencePiece — used by T5, multilingual models:**
- Language-agnostic, operates on raw Unicode bytes. No whitespace assumptions, works for any language.
- Used by models that serve many languages (mT5, NLLB).

**How tokenization affects performance:**

| Effect | Mechanism | Impact |
|--------|-----------|--------|
| **Cost** | APIs charge per token. English ≈ 4 chars/token; code, math, non-Latin scripts can be 1–2 chars/token | Legal/code prompts cost 2–4× more than equivalent English prose |
| **Context window consumption** | Tokens, not characters, fill context. "1M token" context ≠ "1M words" | Context budget planning requires token-aware chunking |
| **Arithmetic errors** | Numbers are often split oddly: "1,234,567" → ["1", ",", "234", ",", "567"] — model must reason across split digits | Root cause of LLM arithmetic failures; solved by tool use (calculator) |
| **String operation failures** | "strawberry" tokenized as ["straw", "berry"] — model never sees individual letters | Why "how many r's in strawberry?" fails — the model sees tokens, not characters |
| **Domain vocabulary coverage** | Medical terms like "acetylcholinesterase" split into many rare subwords → high perplexity, worse generation | General tokenizers disadvantage specialized domains; domain-specific tokenizers (BioMedBERT, ClinicalBERT) help |
| **Multilingual inequity** | Non-Latin scripts (Japanese, Arabic, Chinese) often have fewer merged tokens → much longer token sequences for same information content | Japanese text can use 2–4× more tokens than English for equivalent content, increasing cost and reducing effective context |

### Example / Tradeoff
**Real cost example:** A customer support pipeline processes 10K queries/day in English. Average query = 500 tokens in/200 tokens out. Switching to a legal domain with Latin terms and citations pushes this to 900 tokens in/400 tokens out — a 1.8× cost increase *purely from tokenization density*, before any model capability considerations.

**Llama-3 tokenizer improvement:** Llama-3 expanded vocabulary from 32K (Llama-2) to 128K tokens. This makes common English words single tokens, reduces token count by ~15–25% for English text, and improves non-Latin language coverage significantly. The tradeoff: embedding table grows from 32K × 4096 = 500MB to 128K × 4096 = 2GB, adding to model memory footprint.

---

## Verbal script

**Opening (30s):**
"Tokenization is how raw text gets converted into the integer sequences that LLMs actually process. I think of it as the hidden variable that drives almost every engineering tradeoff — cost, context window consumption, model capability on specialized text. Let me walk through the mechanics and then hit the practical implications."

**Core explanation (2–3 min):**
"Modern LLMs use subword tokenization, most commonly BPE — Byte-Pair Encoding. The idea is: start with individual characters, then iteratively merge the most frequent adjacent pairs into a single token. You repeat this until you hit your vocabulary size target — modern models land in the 100K–128K range. The result is a vocabulary where common English words like 'the' or 'running' are single tokens, but rare or compound words get split: 'acetylcholinesterase' might become 8 or 10 tokens.

At inference time, the tokenizer applies those learned merge rules to your input, producing a sequence of integer IDs. The model operates entirely on these IDs — it never sees individual characters.

This creates a few important failure modes. Arithmetic fails because numbers get split oddly — '1,234,567' becomes individual digit chunks, and the model has to reason across token boundaries. The famous 'how many r's in strawberry?' failure happens because 'strawberry' tokenizes as ['straw', 'berry'] — the model literally never sees the 'r' characters. These aren't knowledge failures; they're tokenization artifacts.

Domain tokenization is a major issue. Medical and legal text contain long Latin-derived compound terms that general tokenizers haven't learned to merge efficiently — they split into many subword tokens. This means: more tokens per document (higher cost), more context consumed per chunk (worse RAG retrieval density), and higher model perplexity on these terms (worse generation quality)."

**Tradeoff / production angle (1 min):**
"The cost dimension is underappreciated. English averages ~4 characters per token. Code, math, and non-Latin scripts can be 1–2 characters per token. If you're building a multilingual product serving Japanese and Arabic users, those users' requests consume 2–3× more tokens than equivalent English requests — your cost model breaks if you didn't account for this.

Context window is also measured in tokens. A '128K token context' holds far less information than 128K English words — documents need to be chunked and counted in token units, not word units. I always tokenize representative samples before sizing RAG chunk boundaries."

**Wrap-up (30s):**
"So tokenization is the bridge from text to model input, and it's the root cause of several real failure modes — arithmetic errors, string operation failures, domain vocabulary gaps, and multilingual cost inequity. In production, token-aware design means: budget context in tokens not words, tokenize before chunking, use domain-specific models for medical/legal, and add tool use for any task requiring character-level precision."

---

## Pitfalls

- **Mistake:** Saying "tokenization just splits text into words" — **Better:** Explain BPE/subword tokenization specifically: common words become single tokens, rare/compound words are split into subword pieces, and the vocabulary is learned from corpus statistics rather than a dictionary — which is why "strawberry" → ["straw", "berry"] and arithmetic on split numbers fails.
- **Mistake:** Not connecting tokenization to cost and context windows — **Better:** Explicitly state that APIs charge per token, non-English text uses more tokens per character than English, and context window limits are in tokens not words — all of which are directly engineered tradeoffs in production system design.
- **Mistake:** Missing the domain-specificity problem — saying "tokenization is just a preprocessing step" — **Better:** Explain that general-purpose tokenizers (frontier and open-weight alike) are trained on web text, so specialized vocabulary in medical, legal, or code domains is often poorly covered — resulting in more tokens per concept, worse generation quality, and higher perplexity, which is why domain-specific models (BioMedBERT, ClinicalBERT, CodeLlama) use domain-adapted tokenizers.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q39: What is tokenization, and why does it matter for cost and context windows?](01-039-what-is-tokenization-and-why-does-it-matter-for-cost-and-con.md) | Near-duplicate with production/cost focus; this Q covers mechanics more broadly |
| [Q24: BPE vs WordPiece vs character-level tokenization — tradeoffs?](01-024-bpe-vs-wordpiece-vs-character-level-tokenization-tradeoffs.md) | Deep dive on the different tokenization algorithms introduced here |
| [Q37: Risks of general-purpose tokenizers on legal/medical domains?](01-037-risks-of-general-purpose-tokenizers-on-legalmedical-domains.md) | Expands on the domain coverage problem raised in this answer |

---

## One-liner recall

> Tokenization (BPE/subword) converts text to integer token sequences — averaging ~4 chars/token in English — and directly drives LLM cost, context window consumption, arithmetic/string failures, and domain vocabulary coverage gaps.
