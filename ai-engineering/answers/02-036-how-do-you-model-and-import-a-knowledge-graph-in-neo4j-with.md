# How do you model and import a knowledge graph in Neo4j with Cypher?

**Category:** 02-rag-systems
**Question #:** 036
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Vector-only RAG drops cross-document relationships — for legal contracts, the answer to "which affiliate agreements touch parties in New York?" spans several documents and no single chunk holds it. The interviewer wants to see that you can design the graph layer behind GraphRAG: node/relationship modeling, idempotent import, and multi-hop queries that chunk search cannot express.

### Trigger phrases
- "Our contracts reference each other — how do you query across documents?"
- "How would you build a knowledge graph from PDFs?"
- "Walk me through modeling entities and relationships in Neo4j."

### What it tests
Ability to model a domain as a property graph, write idempotent Cypher imports, and express multi-hop traversals — not just name-drop Neo4j.

---

## Answer

### Concept
A legal-document knowledge graph models each contract as a `Contract` node linked to `Party` and `Location` nodes via typed relationships (`SIGNED_BY`, `LOCATED_IN`, `AFFILIATED_WITH`). Extraction (LlamaParse → contract-type classification → per-type LlamaExtract schema) produces one clean record per PDF; the graph import turns those records into nodes and edges. Once built, multi-hop questions become traversals instead of similarity searches — the graph answers "locations of all parties" by walking edges, not by hoping one chunk mentions everything.

### Mechanism

**1. Node/relationship design.** Three node labels cover the domain: `Contract` (type, effective date, governing law), `Party` (name, role), `Location` (city, state). Relationships carry the semantics: `(:Party)-[:SIGNED_BY]->(:Contract)`, `(:Party)-[:LOCATED_IN]->(:Location)`, `(:Contract)-[:AFFILIATED_WITH]->(:Contract)`. Keep node properties scalar and query-relevant; push clause text to a `text` property or a linked chunk id rather than the graph — Neo4j traverses structure, it is not a document store.

**2. MERGE, not CREATE — idempotent re-ingest.** The import loop appends one PDF at a time (the post's `KnowledgeGraphBuilder` pattern: parse → classify → extract → import, per document). Re-running the loop over the same PDF must never duplicate nodes, so every import uses `MERGE` on a stable business key (contract id, party name) instead of `CREATE`. `MERGE` matches-or-creates atomically per pattern; `CREATE` blindly appends a second node on every re-run and silently doubles traversal results.

**3. Import statements (post's shape).** Clean nulls before writing — `apoc.map.clean` with an explicit values-to-skip list strips null/empty extraction fields so optional schema fields don't become junk properties — and cast date strings to real temporal types so range filters work:

```cypher
MERGE (c:Contract {contractId: $record.contractId})
SET c += apoc.map.clean($record.contractProps, [], [null, ''])
SET c.effectiveDate = date($record.effectiveDate)

MERGE (p:Party {name: $record.partyName})
MERGE (p)-[:SIGNED_BY]->(c)

MERGE (l:Location {city: $record.city, state: $record.state})
MERGE (p)-[:LOCATED_IN]->(l)
```

`apoc.map.clean(properties, keysToSkip, valuesToSkip)` with `[]` keys to skip and `[null, '']` values to skip drops the null- and empty-valued keys that schema extraction leaves behind when a contract omits an optional field — the values list is what does the work; an empty `[]` there would be a no-op. `date()` casts `"2024-03-01"` to a temporal value — without it, `WHERE c.effectiveDate > "2024-01-01"` degrades to string comparison and mis-orders non-ISO formats.

**4. One-command append loop.** Each PDF flows through parse → classify contract type → select the matching Pydantic schema → extract → run the MERGE statements above. Because every write is keyed `MERGE`, the loop is safely re-runnable: new PDFs add nodes/edges, re-processed PDFs converge to the same graph.

### Example / Tradeoff

The post's two demo questions, as traversals chunk search cannot express:

```cypher
// Locations of all parties to a given contract
MATCH (p:Party)-[:SIGNED_BY]->(c:Contract {contractId: $id}),
      (p)-[:LOCATED_IN]->(l:Location)
RETURN p.name, l.city, l.state;

// Affiliate agreements touching parties in New York
MATCH (c:Contract)-[:AFFILIATED_WITH]->(aff:Contract),
      (p:Party)-[:SIGNED_BY]->(aff),
      (p)-[:LOCATED_IN]->(l:Location {state: 'NY'})
RETURN DISTINCT aff.contractId, p.name;
```

The first query is two hops (contract → parties → locations); the second is three (contract → affiliates → parties → location filter). A vector index can find "New York" mentions but cannot enforce the signed-by path — it returns contracts that merely mention New York. The tradeoff is write complexity: every new document type needs a schema plus import mapping, whereas dumping chunks into a vector store needs neither. For hosting, Neo4j AuraDB's free tier covers interview-scale graphs; production pays per-GB-memory pricing, so keep clause text out of node properties (see Mechanism step 1) to stay in the cheap tier.

---

## Verbal script

**Opening (30s):**
"I'd model this as a small property graph — Contract, Party, and Location nodes with typed relationships — built one PDF at a time through parse, classify, schema-bound extraction, and a Cypher import. The key design decision is that the import is idempotent: re-running the PDF loop never duplicates nodes."

**Core explanation (2–3 min):**
"I'd start with the node design. Each contract becomes a Contract node with its type, effective date, and governing law. Each counterparty becomes a Party node, each jurisdiction a Location node. The semantics live in the relationships: Party SIGNED_BY Contract, Party LOCATED_IN Location, Contract AFFILIATED_WITH Contract. I keep clause text out of the graph — Neo4j traverses structure, it's not a document store, and stuffing text into properties bloats the memory footprint that AuraDB bills on.

For the import, the critical choice is MERGE on a stable business key — contract id, party name — never CREATE. The pipeline appends PDFs one at a time, and reprocessing a document has to converge to the same graph, not double every node. CREATE would silently duplicate nodes and inflate every traversal count, which is the most common production bug here.

Two more details from the import statements: I clean nulls with apoc.map.clean passing [null, ''] as the values-to-skip list before SET, because schema extraction leaves optional fields null and those become junk properties. And I cast date strings with date() into real temporal types — otherwise effective-date range filters degrade to string comparison.

A concrete example is the two demo queries. 'Locations of all parties' is a two-hop traversal: contract to parties to locations. 'Affiliate agreements in New York' is three hops with a location filter. A vector index can find New York mentions but can't enforce the signed-by path — it returns contracts that merely mention New York. That's exactly the multi-hop gap GraphRAG exists to close."

**Tradeoff / production angle (1 min):**
"The tradeoff is write complexity versus query power. Every new document type needs a Pydantic schema plus an import mapping, where a vector store needs neither. I'd also call out the hosting cost: AuraDB's free tier is fine for a demo graph, but production pricing is per-GB-memory, which is another reason to keep full text out of node properties. And if the extraction schema drifts — a new contract type appears — the classifier must route to the right schema before extraction, otherwise MERGE keys collide across types."

**Wrap-up (30s):**
"The key insight is that MERGE keyed on business identity makes document-to-graph ingestion safely re-runnable, and typed relationships turn cross-document questions into traversals that similarity search fundamentally cannot express. Happy to go deeper on the extraction schemas, the APOC cleaning step, or hybrid vector-plus-traversal queries."

---

## Pitfalls

- **Mistake:** Using `CREATE` for the import because "it's faster" — **Better:** Use `MERGE` on a stable business key; `CREATE` duplicates every node on re-ingest and silently doubles traversal results, which is undetectable without count audits.
- **Mistake:** Writing extracted date strings as plain string properties — **Better:** Cast with `date()`/`datetime()` at import so range filters use temporal comparison; string comparison mis-orders anything outside strict ISO format.
- **Mistake:** Storing full clause text as node properties — **Better:** Keep node properties scalar and query-relevant, link out to chunk/text ids; bloated properties inflate the AuraDB memory footprint and slow traversals.
- **Mistake:** Skipping null-cleaning on schema-extraction output — **Better:** Run `apoc.map.clean` with `[null, '']` as the values-to-skip list before `SET` so optional fields absent from a contract don't become null-valued properties that pollute queries and indexes.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q16 (01): What is GraphRAG — how does it differ from standard RAG?](../answers/01-016-what-is-graph-rag-how-does-it-differ-from-standard-rag.md) | Prerequisite: conceptual GraphRAG framing this note implements in Cypher |
| [Q3: Design a GenAI document-processing pipeline for unstructured data](02-003-design-a-genai-document-processing-pipeline-for-unstructured.md) | Prerequisite: the parse → classify → extract pipeline that feeds the graph import |
| [Q11 (01): How do you ensure LLM outputs are consistent and accurate?](../answers/01-011-how-do-you-ensure-llm-outputs-are-consistent-and-accurate-in.md) | Same concept: per-doctype Pydantic schemas that produce the records MERGE consumes |

---

## One-liner recall

> Model contracts as Contract/Party/Location nodes with typed relationships, import with MERGE on business keys (never CREATE) plus apoc.map.clean with a [null, ''] skip list and date casts so the PDF loop is idempotent — then multi-hop questions become traversals that chunk search cannot express.
