# How agents decide which tool to use?

**Category:** 03-agents-tool-use
**Question #:** 021
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether the candidate understands the **mechanism and failure modes of tool selection** inside an agent loop — a critical production concern because a hallucinated or miscalibrated tool call is the most common source of agent errors. Interviewers want to know if you can both explain how tool selection works and how to engineer schemas, prompts, and orchestration to make it reliable.

### Trigger phrases
- "How does an agent know which tool to call?"
- "How do you design tool schemas for reliable selection?"
- "What happens when an agent picks the wrong tool?"

### What it tests
Deep understanding of the interplay between LLM function-calling mechanics, tool schema quality, and orchestrator-side validation — plus production intuition about failure modes.

---

## Answer

### Concept
Agents decide which tool to use through **LLM function-calling**: the model receives a set of JSON-schema tool definitions alongside the conversation context, and its next-token prediction head is fine-tuned to output a structured `tool_call` object that names the tool and its arguments. Tool selection is a **semantic match** between the current task context and each tool's description — which means schema quality is the primary lever for reliability.

### Mechanism

**Step-by-step flow (OpenAI / Anthropic function-calling pattern):**

1. **Schema injection** — the orchestrator prepends all available tool definitions (name, description, parameter schema with types and constraints) into the system prompt or `tools` array (OpenAI API `tools` param / Anthropic `tools` block).
2. **LLM reasoning (ReAct Thought step)** — the model generates a `Thought` explaining what it needs to do, then emits a `tool_call` JSON: `{"name": "search_kb", "arguments": {"query": "refund policy"}}`.
3. **Orchestrator validation** — the orchestrator (not the LLM) validates: tool name is in the allowlist, required parameters are present, types match the schema. Rejects malformed calls with a structured error the LLM can correct.
4. **Tool execution** — the validated call is dispatched; the result is injected as an `Observation` back into the context.
5. **Iteration** — the LLM reads the observation and selects the next tool (or terminates with `FINAL_ANSWER`).

**What drives the selection decision:**

| Factor | Effect on tool selection |
|--------|--------------------------|
| Tool `description` field | Primary signal — must be distinct and action-oriented ("Search the knowledge base for policy questions" not "KB search") |
| Parameter schema quality | Constrained enums and examples reduce hallucinated arg values |
| Number of tools | ≤10 tools → near-perfect selection; 20+ tools → accuracy degrades; 40+ → use tool retrieval |
| Context clarity | Ambiguous user intent → LLM falls back to asking for clarification or picks the "closest" tool incorrectly |
| Temperature | T=0 for tool-calling steps forces the highest-probability (most confident) tool selection |

**Tool retrieval for large tool sets (20+ tools):**  
When the tool library is large (e.g., 50-200 enterprise API tools), inject only a **retrieved subset** per turn: embed the current task description, embed all tool descriptions at startup, and retrieve the top-5–10 by cosine similarity (FAISS/Qdrant). This keeps the context window small and accuracy high.

### Example / Tradeoff

**Support-ticket agent with 5 tools — LangGraph + OpenAI function-calling:**

```python
tools = [
    {
        "name": "search_kb",
        "description": "Search the support knowledge base for policy or product information. Use when the user asks about policies, features, or troubleshooting steps.",
        "parameters": {
            "query": {"type": "string", "description": "Natural language search query"},
            "category": {"type": "string", "enum": ["billing", "shipping", "returns", "technical"], 
                         "description": "Filter by support category"}
        }
    },
    {
        "name": "get_order",
        "description": "Retrieve order details by order ID. Use when the user references a specific order number or asks about order status.",
        "parameters": {
            "order_id": {"type": "string", "pattern": "^ORD-[0-9]{6}$"}
        }
    },
    # ... escalate, send_email, create_ticket
]
```

**Selection accuracy in production:**
- 5 well-described tools → ~95%+ correct selection at T=0 with a small fast model
- Same 5 tools with generic descriptions ("Use this to search") → drops to ~70–75%
- Adding 20 poorly-described tools → drops to ~60%, hallucinated tool names appear

**Tradeoff:** More tools = richer agent capability but lower selection accuracy and higher input-token cost (each tool schema consumes tokens every turn). The production pattern is: start with ≤10 curated tools, add tool retrieval when the library grows, and benchmark selection accuracy on a golden task set after each tool addition.

---

## Verbal script

**Opening (30s):**
"Tool selection in agents runs through LLM function-calling — the model reads a set of JSON tool schemas alongside the task context and produces a structured tool-call object. The key insight is that selection accuracy is almost entirely driven by how well you write those schemas, not by anything magic in the model. Let me walk through the mechanism and the production failure modes."

**Core explanation (2–3 min):**
"The orchestrator injects tool definitions into every call — name, description, and a parameter JSON schema. The LLM then does a semantic match between what it needs to do right now and each tool's description, and emits a `tool_call` JSON naming the tool and its arguments. The orchestrator validates the output — confirming the tool name is on the allowlist, required params are present, types match — and rejects malformed calls with a structured error so the LLM can self-correct.

The description field is the primary lever. A description like 'Search the knowledge base for policy or product information — use when the user asks about policies, features, or troubleshooting steps' is dramatically better than 'KB search'. Similarly, constrained enum parameters prevent the model from hallucinating values — if `category` must be one of `['billing', 'shipping', 'returns', 'technical']`, it can't invent a new category.

Temperature matters here too: I always set T=0 for tool-calling turns to force the highest-confidence selection rather than creative sampling.

When the tool library grows past 10–15 tools, selection accuracy degrades and input token cost rises because you're sending every schema every turn. The fix is tool retrieval: embed all tool descriptions offline, then at runtime embed the current task and retrieve the top 5–10 tools by cosine similarity from FAISS or Qdrant before the LLM call."

**Tradeoff / production angle (1 min):**
"The failure mode I see most in production is teams adding tools without updating descriptions, so two tools end up with overlapping semantics and the model alternates between them. I benchmark selection accuracy on a golden task set — 50–100 representative tasks where the correct tool is labeled — after every tool change. If accuracy on that set drops more than 5 points, the new tool's description needs work or the schema needs better parameter constraints.

A second failure: tool selection is fine but argument generation is wrong. This is fixed with examples in the parameter description, constrained enums, and pattern fields in the JSON schema — the model will follow schema constraints reliably at T=0."

**Wrap-up (30s):**
"So: agents select tools via LLM function-calling driven by schema quality. The levers are tool description distinctiveness, parameter constraints, temperature=0, and tool retrieval for large libraries. The orchestrator validates every call in code — never trust the LLM to self-validate its own tool arguments."

---

## Pitfalls

- **Mistake:** Writing vague or overlapping tool descriptions ("Use this tool to get information") and then wondering why the agent picks the wrong tool — **Better:** Make each description action-oriented and explicitly state the condition under which to use it ("Use when the user references a specific order number"); treat descriptions as classifier training data — the model is doing zero-shot classification against them.
- **Mistake:** Expecting the LLM to validate its own tool arguments ("the model will use the right format") — **Better:** Enforce JSON schema validation in the orchestrator; reject malformed calls with a structured error response that names the violated constraint so the model can self-correct in the next turn.
- **Mistake:** Injecting 30+ tool schemas every turn and wondering why token costs exploded and selection accuracy dropped — **Better:** Embed tool descriptions at startup, retrieve the top 5–10 relevant tools per turn via cosine similarity, and benchmark selection accuracy on a golden task set as the library grows.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q22: Tool schemas that reduce hallucinated actions](03-022-tool-schemas-that-reduce-hallucinated-actions.md) | Follow-up — how to design schemas for reliable selection |
| [Q9: What logic belongs in orchestrator vs LLM](03-009-what-logic-belongs-in-orchestrator-vs-llm.md) | Prerequisite — orchestrator owns tool dispatch and validation |
| [Q6: Essential components of an agent beyond an LLM](03-006-essential-components-of-an-agent-beyond-an-llm.md) | Context — tool layer as one of the four agent components |

---

## One-liner recall

> Agents select tools via LLM function-calling — the model does a semantic match between task context and tool descriptions, so schema quality (distinct descriptions, constrained enums, T=0) is the primary accuracy lever, with tool retrieval (embed + cosine-retrieve top-K) for libraries of 15+ tools.
