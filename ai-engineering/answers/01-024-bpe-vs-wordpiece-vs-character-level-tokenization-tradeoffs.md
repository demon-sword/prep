# BPE vs WordPiece vs character-level tokenization — tradeoffs?

**Category:** 01-llm-fundamentals
**Question #:** 024
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Tokenization sits at the foundation of every LLM — it determines vocabulary size, context window efficiency, cost per call, and whether domain-specific terms get split into nonsense. Interviewers probe this to see whether candidates understand the latent assumptions baked into pre-trained models *before* they are applied to specialized domains (legal, medical, code), and whether they can reason about cost/context tradeoffs in production.

### Trigger phrases
- "Why does a frontier model struggle with arithmetic / rare words / legal terms?"
- "How does tokenization affect cost and context window usage?"
- "What tokenizer does BERT use vs GPT? Why does it matter?"
- "Our domain has lots of abbreviations — should we retrain the tokenizer?"

### What it tests
Understanding of subword tokenization algorithms and their downstream consequences for model behavior, cost efficiency, and domain adaptation.

---

## Answer

### Concept
Tokenization is the process of converting raw text into discrete integer IDs that a model can process. The core tension in tokenizer design is **vocabulary coverage vs sequence length**: a large vocabulary covers more words as single tokens (shorter sequences, lower cost) but requires more embedding parameters and risks data sparsity; a small vocabulary keeps embeddings compact but splits every rare word into many fragments (longer sequences, higher cost, potential semantic degradation). All three major approaches — BPE, WordPiece, and character-level — make different bets on this tradeoff.

### Mechanism

**Byte-Pair Encoding (BPE)** — used by GPT-2/3/4, LLaMA, Mistral, Falcon:
1. Start with a character-level vocabulary plus a special end-of-word marker.
2. Iteratively count the most frequent adjacent byte/character pair in the training corpus.
3. Merge that pair into a new token and repeat until vocabulary reaches the target size (typically 32K–128K).
4. At inference, greedily apply learned merge rules left-to-right.
- **Strength:** Frequency-driven merges naturally capture common morphemes and subwords. No OOV tokens — unknown characters fall back to byte-level.
- **Weakness:** Merge order is greedy; slightly different byte sequences can produce very different tokenizations (e.g., " cat" vs "cat" are different tokens in GPT models). Arithmetic digits are often single characters, so "1234" = 4 tokens.

**WordPiece** — used by BERT, DistilBERT, ALBERT, Electra:
1. Start from full words, then segment by maximizing the likelihood of the training data under a language-model objective (maximize P(word) = product of P(subword pieces)).
2. Unknown subwords are broken down greedily, with a `##` prefix marking continuation pieces (e.g., "tokenization" → "token", "##ization").
3. Vocabulary typically 30K tokens.
- **Strength:** Likelihood-maximizing objective tends to produce linguistically meaningful splits. The `##` convention makes it clear a piece is a suffix.
- **Weakness:** Requires full vocabulary pre-selection; rare byte sequences may produce `[UNK]` unlike BPE which can always fall back to bytes.

**Character-level tokenization** — used in some early models, character-level LMs:
1. Every character is a token; vocabulary ~256 (ASCII) to a few thousand (Unicode).
2. Sequence length grows proportionally — an average English sentence of 20 words ≈ 100 characters = 100 tokens (vs ~25 with BPE).
- **Strength:** No OOV problem, perfect for highly agglutinative languages (Finnish, Turkish), robustness to typos and code.
- **Weakness:** Context window fills up much faster; model must learn to compose meaning from characters, requiring much more capacity and data.

**SentencePiece (BPE or Unigram variant)** — used by T5, LLaMA 2/3, Mistral:
- Language-agnostic; treats input as a raw byte stream, enabling multilingual tokenization without pre-tokenization rules. Unigram variant selects subword pieces by probabilistic language model (vs greedy BPE frequency).

### Example / Tradeoff

| Algorithm | Vocab size | OOV handling | Sequence length (English) | Domain gap risk |
|-----------|-----------|--------------|--------------------------|-----------------|
| BPE (a frontier model, tiktoken) | 100K | Byte fallback — no UNK | ~1 token / 4 chars | Medium — arithmetic, medical codes |
| WordPiece (BERT) | 30K | `[UNK]` for truly unseen bytes | ~1 token / 4 chars | Higher — fixed vocab, no byte fallback |
| Character-level | 256–5K | None | ~1 token / 1 char | None — but 4–5× longer sequences |
| SentencePiece Unigram (T5, LLaMA) | 32K–64K | Byte fallback | ~1 token / 4 chars | Low — language-agnostic |

**Concrete production impact — medical domain:**
A frontier model's tiktoken (BPE, 100K vocab) splits "hepatosplenomegaly" into 6–7 tokens. A clinical NLP team found their average note consumed **28% more tokens** than expected, inflating API costs and sometimes truncating context. Options: (1) use a domain-retrained tokenizer (requires fine-tuning from scratch), (2) add a pre-processing step to expand abbreviations, (3) switch to a model whose tokenizer was trained on biomedical text (e.g., BioGPT, ClinicalBERT).

**Arithmetic failure root cause:** GPT tokenizers split digits individually only for multi-digit numbers in certain contexts. "8 + 7 = 15" might tokenize "15" as one token but "153" as two — the model has never seen "153" as a unit; it must learn carry rules from character patterns, which it struggles with compared to a calculator.

---

## Verbal script

**Opening (30s):**
"Tokenization is one of those things that feels like plumbing until it causes a production incident. The high-level tension is vocabulary size versus sequence length — more tokens in your vocabulary means shorter sequences and lower cost, but you pay with larger embeddings and risk data sparsity. I'll walk through BPE, WordPiece, and character-level, then hit the production implications."

**Core explanation (2–3 min):**
"BPE — used by GPT and LLaMA — starts with characters and iteratively merges the most frequent adjacent pair until you hit a target vocab size, usually 32K to 100K. The result is a greedy frequency-driven vocabulary that captures common morphemes well. Modern BPE implementations like tiktoken operate at the byte level, so there are no true unknowns — any input can be expressed as bytes.

WordPiece, used by BERT, is similar but instead of raw frequency it maximizes the language-model likelihood of the training corpus. The practical difference is small, but you get linguistically cleaner splits and the `##` convention makes continuation pieces explicit. The downside is that BERT's 30K vocabulary is fixed — rare byte sequences produce `[UNK]`.

Character-level goes all the way down to individual characters — vocabulary is maybe 256 to a few thousand. Zero OOV risk and great for typo robustness, but a 20-word sentence becomes 100 tokens instead of 25, which is a 4× context window hit. For most production use cases that's prohibitive.

SentencePiece wraps BPE or a probabilistic Unigram algorithm in a language-agnostic byte-stream interface — that's what T5 and LLaMA 2 use, which is why they handle multilingual inputs well without language-specific pre-tokenization."

**Tradeoff / production angle (1 min):**
"The place this bites hardest in production is domain-specific vocabulary. Medical terms, legal clause identifiers, or financial tickers can fragment into many tokens, which means: higher API cost, shorter effective context, and sometimes the model has never seen that exact token sequence during training so it hallucinates. The fix isn't always 'retrain the tokenizer' — that means retraining the whole model. Usually you pre-process: expand abbreviations, normalize IDs, or add a glossary to the system prompt. If the domain gap is severe enough, switching to a domain-adapted model (BioGPT, LegalBERT) is the right call. Arithmetic is another classic failure — BPE splits large numbers into per-digit tokens, so the model has to learn carry rules from character fragments, which it does poorly compared to a tool call to a calculator."

**Wrap-up (30s):**
"Bottom line: BPE is the industry default for good reason — byte-level fallback, no UNK, good compression. WordPiece is BERT's slightly different bet on the same idea. Character-level is the nuclear option for OOV robustness at a steep sequence-length cost. In production, the real question is 'does this tokenizer handle our domain vocabulary efficiently?' and the answer determines your cost, context, and model quality story. Happy to go deeper on any of these."

---

## Pitfalls

- **Mistake:** Describing tokenization as just "splitting text into words" without mentioning subword algorithms — **Better:** Explain that subword tokenization (BPE/WordPiece) is the industry standard precisely to handle rare words and morphological variants without exploding vocabulary size or producing unknowns.
- **Mistake:** Saying "GPT and BERT use the same tokenizer" — **Better:** GPT uses BPE (tiktoken, 100K vocab, byte-level); BERT uses WordPiece (30K vocab, fixed, `[UNK]` for unseen bytes) — the difference matters when BERT encounters out-of-vocabulary bytes.
- **Mistake:** Ignoring the cost/context implication — "tokenization doesn't affect cost much" — **Better:** Name the concrete impact: more tokens → higher API cost + shorter effective context window. E.g., a medical corpus can run 20–30% longer than general English due to fragmented terminology.
- **Mistake:** Saying character-level is always worse — **Better:** Character-level has real advantages for highly agglutinative languages, code (where identifier fragments matter), and typo robustness; the tradeoff is sequence length, not correctness.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: What is tokenization and how does it affect LLM performance?](01-003-what-is-tokenization-and-how-does-it-affect-llm-performance.md) | Foundation — this Q24 goes deeper on algorithm comparison |
| [Q37: Risks of general-purpose tokenizers on legal/medical domains](01-037-risks-of-general-purpose-tokenizers-on-legalmedical-domains.md) | Direct application of tokenizer tradeoffs to domain-specific costs |
| [Q39: What is tokenization, and why does it matter for cost and context windows?](01-039-what-is-tokenization-and-why-does-it-matter-for-cost-and-con.md) | Production cost angle — same concept, applied to billing and context budget |

---

## One-liner recall

> BPE (GPT) merges frequent byte pairs to build a vocabulary greedily with byte-level fallback; WordPiece (BERT) uses a likelihood objective with `[UNK]` risk; character-level has zero OOV but 4–5× longer sequences — choose by domain OOV rate and context/cost budget.
