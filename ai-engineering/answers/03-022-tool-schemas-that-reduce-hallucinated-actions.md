# Tool schemas that reduce hallucinated actions?

**Category:** 03-agents-tool-use
**Question #:** 022
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether the candidate understands that **tool schema design is the primary engineering lever for agent reliability** — not model choice or prompt verbosity. Interviewers at companies with production agents (Anthropic, OpenAI, enterprise AI teams) ask this to distinguish candidates who have debugged real hallucination failures from those who treat schemas as boilerplate. It's a direct follow-up to "how do agents decide which tool to use?" and goes deeper into the craft of schema authoring.

### Trigger phrases
- "How do you write tool schemas to reduce hallucinations?"
- "Your agent keeps calling tools with wrong arguments — what do you fix?"
- "What makes a good tool definition in a function-calling API?"
- "How do you prevent the model from inventing parameter values?"

### What it tests
Practical knowledge of JSON Schema semantics, function-calling API mechanics, and the specific schema patterns that constrain LLM output to valid tool invocations.

---

## Answer

### Concept
A tool schema is the **specification contract** between the orchestrator and the LLM: it tells the model what the tool does, when to use it, and exactly what arguments are legal. Hallucinated actions — wrong tool names, fabricated argument values, out-of-range parameters — almost always trace back to schemas that are too vague, too permissive, or semantically overlapping. The fix is schema engineering, not model tuning.

### Mechanism

**Five concrete schema patterns that eliminate most hallucinations:**

#### 1. Action-oriented, condition-scoped descriptions
The `description` field is the model's only signal for _when_ to call the tool. Vague descriptions produce ambiguous selection; overlapping descriptions cause thrashing between tools.

```json
// ❌ Vague — model can't distinguish this from other tools
{
  "name": "search",
  "description": "Search for information."
}

// ✅ Action-oriented + condition-scoped
{
  "name": "search_knowledge_base",
  "description": "Search internal support articles for policy, product feature, or troubleshooting information. Use ONLY when the user asks about how something works, what a policy is, or how to fix a problem. Do NOT use for order lookups or account changes."
}
```

The `DO NOT use when` clause is especially powerful — it disambiguates from sibling tools without requiring the model to read all schemas simultaneously.

#### 2. Constrained enums over free-form strings
Free-form string parameters invite hallucination. Replace them with `enum` wherever the value space is finite.

```json
// ❌ Model invents values: "urgent", "URGENT", "high-priority", "escalate"
"priority": {"type": "string"}

// ✅ Model must pick from the legal set
"priority": {
  "type": "string",
  "enum": ["low", "medium", "high", "critical"],
  "description": "Ticket priority. Use 'critical' only for data loss or complete service outages."
}
```

#### 3. Regex patterns for structured identifiers
Order IDs, user IDs, account numbers — all should carry `pattern` constraints. The model follows JSON Schema patterns reliably at T=0 and the orchestrator can validate before execution.

```json
"order_id": {
  "type": "string",
  "pattern": "^ORD-[0-9]{6}$",
  "description": "Order identifier in format ORD-NNNNNN, e.g. ORD-483201. Extract from user message."
}
```

#### 4. `required` vs optional separation + explicit defaults
Mark as `required` only what is truly necessary. Optional parameters should include a `default` and a description of when to omit them. This prevents the model from hallucinating values for fields it doesn't need.

```json
{
  "name": "get_orders",
  "parameters": {
    "required": ["customer_id"],
    "properties": {
      "customer_id": {"type": "string", "description": "Customer UUID from user account"},
      "status_filter": {
        "type": "string",
        "enum": ["all", "open", "shipped", "cancelled"],
        "default": "all",
        "description": "Filter orders by status. Omit to return all orders."
      },
      "limit": {
        "type": "integer",
        "minimum": 1,
        "maximum": 50,
        "default": 10,
        "description": "Max orders to return. Default 10. Only increase if user asks for 'all orders'."
      }
    }
  }
}
```

#### 5. Inline examples in parameter descriptions
LLMs are few-shot learners. Adding `e.g.` examples in the description dramatically reduces argument format errors.

```json
"date_range": {
  "type": "string",
  "description": "ISO 8601 date range in format YYYY-MM-DD/YYYY-MM-DD, e.g. '2024-01-01/2024-03-31'. Extract from user's natural language date references."
}
```

**Orchestrator-side enforcement (the other half):**

Schema design alone isn't enough — the orchestrator must validate every tool call against the schema in code before dispatching:

```python
import jsonschema

def dispatch_tool(tool_call, tool_schemas):
    schema = tool_schemas[tool_call["name"]]
    try:
        jsonschema.validate(tool_call["arguments"], schema)
    except jsonschema.ValidationError as e:
        # Return structured error back to LLM for self-correction
        return {"error": f"Invalid arguments: {e.message}. Required: {schema['required']}"}
    return execute_tool(tool_call)
```

The structured error message (not a Python traceback) lets the LLM self-correct in the next turn — typically succeeds within 1–2 retries.

### Example / Tradeoff

**Before / after on a billing agent (production pattern):**

| Metric | Vague schemas | Engineered schemas |
|--------|--------------|-------------------|
| Tool selection accuracy | ~72% | ~96% |
| Argument hallucination rate | ~18% of calls | ~2% of calls |
| Avg turns to task completion | 6.2 | 3.8 |
| Cost per resolved ticket | $0.042 | $0.027 |

The biggest gain typically comes from: (1) adding condition-scoped descriptions that tell the model when NOT to use a tool, and (2) converting free-form string parameters to enums.

**Tradeoff:** Overly-constrained schemas reduce model flexibility — if a user request doesn't fit any enum value or the pattern doesn't match, the agent can't complete the task at all (it will keep returning validation errors). The right balance is: constrain what the system owns (IDs, statuses, categories), leave natural-language fields (`query`, `message`) as free-form strings.

---

## Verbal script

**Opening (30s):**
"Schema engineering is the highest-leverage intervention for reducing agent hallucinations — more than model choice or prompt verbosity. The model treats each tool schema as a zero-shot specification, so how you write descriptions and constrain parameters directly controls what the model can and can't output. Let me walk through the five patterns that eliminate most hallucinated tool calls in production."

**Core explanation (2–3 min):**
"The first and most impactful pattern is condition-scoped descriptions. Instead of 'search for information', you write 'search internal support articles — use ONLY when the user asks about policies, features, or troubleshooting steps; do NOT use for order lookups.' The explicit exclusion clause is what prevents the model from defaulting to a catch-all tool when it's uncertain.

The second pattern is constrained enums. Any parameter with a finite value space — status codes, categories, priority levels — should be an `enum`. A free-form string parameter is an invitation for the model to invent values like 'urgent' or 'URGENT' or 'high-priority' when the system only accepts 'high'. Enum constraints are respected reliably at temperature=0.

Third: regex patterns on structured IDs. If an order ID is always `ORD-NNNNNN`, add a `pattern` field. This catches both model errors and malformed user input early.

Fourth: mark only truly required fields as `required`, and give optional fields a default plus a description of when to omit them. This prevents the model from guessing values for fields it doesn't need.

Fifth: inline examples in descriptions. LLMs are few-shot learners even in schema context. Adding 'e.g. 2024-01-01/2024-03-31' to a date-range field reduces format errors dramatically.

But schema design is only half the story. The orchestrator must validate every tool call against the schema in code — using something like Python's `jsonschema` library — before dispatching the tool. When validation fails, you return a structured error message back to the LLM, not a raw traceback. With a well-written error, the model self-corrects in one or two retries."

**Tradeoff / production angle (1 min):**
"The failure mode I watch for with tight schemas is over-constraint. If you lock down a parameter so tightly that a valid user request doesn't fit — say a date format that doesn't handle 'last quarter' or a category enum that doesn't include the user's edge-case scenario — the agent loops forever on validation errors. The rule I follow: constrain what the system owns (IDs, statuses, enumerations), leave what the user provides as natural language (queries, messages) as free-form strings.

I also benchmark on a golden task set — 50 representative tasks with known correct tool calls — after every schema change. If tool-selection accuracy or argument accuracy drops more than 3 points, the schema change ships with fixes."

**Wrap-up (30s):**
"So: tool schema quality is the primary lever for reliable agents. The five patterns — condition-scoped descriptions, constrained enums, regex patterns on IDs, required vs optional separation, and inline examples — together drive hallucinated actions from ~18% down to ~2% of calls. Pair that with orchestrator-side JSON schema validation that returns structured errors for self-correction, and you have a robust tool layer."

---

## Pitfalls

- **Mistake:** Writing descriptions as one-line noun phrases ("Order lookup tool", "KB search") and then blaming the model for wrong tool selection — **Better:** Write descriptions in imperative/conditional form that state the exact condition for use AND explicit exclusions ("Use ONLY when the user references an order ID — do NOT use for policy questions"); treat description authoring as classifier label design.
- **Mistake:** Using free-form string parameters for everything ("the model is smart enough to know what format to use") — **Better:** Apply `enum` for any finite value space (statuses, categories, priorities), `pattern` for structured identifiers (IDs, dates), and `minimum`/`maximum` for integers; hallucination of argument values drops from ~18% to ~2% with proper constraints.
- **Mistake:** Relying on the LLM to self-validate its own tool arguments without orchestrator enforcement — **Better:** Parse every tool call against the JSON schema with `jsonschema.validate()` before execution; on failure, return a structured natural-language error ("order_id must match format ORD-NNNNNN, you provided 'order12345'") so the model can self-correct in the next turn.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q21: How agents decide which tool to use](03-021-how-agents-decide-which-tool-to-use.md) | Prerequisite — selection mechanism; this note goes deeper on schema engineering |
| [Q24: Tool failures, retries, idempotency](03-024-tool-failures-retries-idempotency.md) | Follow-up — what happens after a schema validation failure triggers a retry |
| [Q9: What logic belongs in orchestrator vs LLM](03-009-what-logic-belongs-in-orchestrator-vs-llm.md) | Context — orchestrator owns schema validation enforcement |

---

## One-liner recall

> Hallucinated tool actions trace to vague schemas: fix them with condition-scoped descriptions (with explicit DO NOT use clauses), enum-constrained parameters, regex patterns on IDs, required/optional separation with defaults, and inline examples — then enforce every call with orchestrator-side JSON schema validation that returns structured errors for self-correction.
