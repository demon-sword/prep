# What is graph RAG? How does it differ from standard RAG?

**Category:** 01-llm-fundamentals
**Question #:** 016
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the structural limitations of flat vector search — and when relationships between entities matter more than semantic similarity. Graph RAG is a 2024–2025 pattern that appears in enterprise knowledge management, legal/medical domain Q&A, and multi-hop reasoning systems. The question tests architectural thinking beyond the vanilla pipeline.

### Trigger phrases
- "How would you handle queries that require connecting multiple documents?"
- "What is graph RAG and when would you use it?"
- "Standard RAG struggles with multi-hop questions — what's the fix?"
- "How do you model relationships between entities in a knowledge base?"

### What it tests
Whether the candidate can articulate the structural gap in vector-only retrieval and knows when a knowledge graph adds signal that embeddings can't capture.

---

## Answer

### Concept
Graph RAG augments the standard RAG pipeline by replacing (or supplementing) the flat vector index with a **knowledge graph** — nodes represent entities (people, concepts, events, documents) and edges represent typed relationships between them. Instead of retrieving the top-k most similar text chunks, retrieval now traverses the graph to collect a subgraph of related entities, then passes that structured context to the LLM. Microsoft Research's GraphRAG (2024) is the canonical open-source implementation.

### Mechanism

**Standard RAG flow:**
1. Chunk documents → embed chunks → store in vector index (FAISS / Pinecone)
2. Query → embed query → ANN search → top-k chunks → LLM generates answer

**Graph RAG flow:**
1. **Offline graph construction:** An LLM extracts entities and relationships from source documents → build a knowledge graph (Neo4j, Kuzu, or in-memory NetworkX). Optionally cluster into "communities" (Leiden algorithm) and pre-generate community summaries.
2. **Retrieval:** Given a query, identify anchor entities (NER or embedding match) → traverse the graph (BFS/DFS/shortest-path) to collect a relevant subgraph or community summary.
3. **Context assembly:** Serialize the subgraph (triples or natural-language summary) + optionally augment with raw chunks → pass to LLM.
4. **Generation:** LLM answers using relational context it couldn't get from flat retrieval.

**Key variants:**
- **Local search** (GraphRAG): expands from anchor entities outward — best for entity-specific queries
- **Global search** (GraphRAG): uses pre-built community summaries — best for holistic "what are the main themes?" queries
- **Hybrid graph + vector**: Neo4j vector index lets you do semantic ANN search *and* graph traversal in a single query

### Example / Tradeoff

**When Graph RAG wins:** A legal knowledge base with 10,000 contracts. A query like *"Which suppliers have disputes with clients who also appear in contract amendments from 2023?"* requires linking supplier → contract → client → amendment — three hops. Flat RAG retrieves individual chunks about each entity but misses the connections. Graph RAG traverses those relationships explicitly.

**Microsoft GraphRAG (2024) benchmark:** On the "Poverty Map" dataset (a large community-oriented corpus), global GraphRAG answered community-summarization questions that standard RAG failed on, but at ~3–5× higher cost (graph construction is LLM-intensive).

**Concrete tradeoffs:**

| Dimension | Standard RAG | Graph RAG |
|-----------|-------------|-----------|
| Setup cost | Low (embed + index) | High (LLM-driven entity extraction + graph build) |
| Multi-hop queries | Poor | Strong |
| Simple factual Q&A | Strong | Marginal improvement |
| Latency | Fast (ANN ~5ms) | Slower (graph traversal + possibly community summary fetch) |
| Maintenance | Re-embed on update | Re-extract entities + rebuild edges on update |
| Tooling | FAISS, Pinecone, Weaviate | Neo4j, Kuzu, Microsoft GraphRAG, LlamaIndex PropertyGraph |

**When NOT to use Graph RAG:** High document-churn corpora (news, real-time data) — graph construction is expensive and stale graphs are worse than no graph. Also avoid for simple single-document Q&A where flat retrieval is sufficient.

---

## Verbal script

**Opening (30s):**
"Graph RAG addresses a structural gap in standard vector RAG: flat chunk retrieval is excellent at finding semantically similar text, but it can't reason about *relationships* between entities across documents. Graph RAG builds a knowledge graph on top of the corpus, so retrieval can traverse connections — not just rank similarity."

**Core explanation (2–3 min):**
"In standard RAG, I embed chunks and retrieve top-k by cosine similarity. That works well for self-contained factual questions. But consider a query like 'Which of our supplier contracts have penalty clauses linked to clients who also appear in 2023 amendments?' — that's a three-hop question. No single chunk contains all three relationships. Flat retrieval fails here.

Graph RAG fixes this in two phases. First, offline: I run an LLM over the corpus to extract entities and typed relationships — supplier, contract, client, clause type — and store them as a graph, say in Neo4j or with Microsoft's GraphRAG library using Leiden community clustering. Second, at query time: I identify anchor entities from the query using NER or a small ANN search, then traverse the graph — BFS, shortest-path, or community-summary lookup — to collect a relevant subgraph. I serialize those triples or the community summary into natural language and pass it as context to the generation LLM.

Microsoft's 2024 GraphRAG paper showed this works especially well for 'global' queries — 'what are the main themes in this corpus?' — where community-level pre-summaries surface patterns no single chunk reveals."

**Tradeoff / production angle (1 min):**
"The key tradeoff is construction cost versus query quality. Graph construction is LLM-intensive — you're running extraction over every document, which can be 5–10× the embedding cost. That's fine for a stable legal or medical corpus, but expensive for high-churn corpora like news feeds. For those, I'd stick with hybrid dense+sparse vector search. I also keep vector search in parallel because Graph RAG alone can miss purely semantic matches — the hybrid wins on both axes.

A practical middle ground: use LlamaIndex's PropertyGraph or Neo4j's vector index to do ANN search *and* graph traversal in a single query, so you don't have to choose."

**Wrap-up (30s):**
"So: Graph RAG = knowledge graph on top of the corpus, entity traversal at retrieval time, best for multi-hop relational queries. Standard RAG = flat vector search, best for single-hop factual or semantic similarity tasks. The decision comes down to whether relationships between entities are load-bearing for the queries you're answering. Happy to go deeper on the construction pipeline or community summarization."

---

## Pitfalls

- **Mistake:** Saying "Graph RAG is just RAG with a graph database" without explaining what changes in the retrieval step — **Better:** Explain that the retrieval mechanism shifts from ANN similarity search to entity-anchored graph traversal, and that graph construction requires an LLM extraction pass that standard RAG doesn't need.
- **Mistake:** Recommending Graph RAG for every use case because it "handles relationships" — **Better:** Acknowledge the high construction and maintenance cost; flag that for simple factual Q&A or high-churn corpora, standard RAG is cheaper and often just as accurate. Only reach for Graph RAG when multi-hop relational queries are a documented failure mode.
- **Mistake:** Not mentioning the community summarization variant (global search) — **Better:** Distinguish local search (entity-anchored traversal) from global search (pre-built community summaries for thematic/holistic questions), as the interviewer may ask about the Microsoft GraphRAG paper specifically.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: What's an RAG model? Explain the complete process.](01-012-whats-an-rag-model-explain-the-complete-process.md) | Prerequisite — standard RAG pipeline to contrast against |
| [Q13: What are embeddings?](01-013-what-are-embeddings.md) | Prerequisite — embedding-based retrieval that Graph RAG augments |
| [Q14: How does chunking happen?](01-014-how-does-chunking-happen.md) | Related — Graph RAG's entity extraction depends on chunking strategy upstream |

---

## One-liner recall

> Graph RAG replaces flat vector retrieval with a knowledge-graph traversal — extracting entities and typed relationships offline, then traversing them at query time to answer multi-hop relational questions that standard top-k chunk retrieval cannot.
