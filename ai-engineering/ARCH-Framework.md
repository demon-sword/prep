# ARCH Framework for Agentic System Design

## Overview

ARCH is a structured framework for designing agentic systems in technical interviews. It helps you organize your thoughts and present a complete, well-reasoned design.

---

## A - Architecture (3-4 minutes)

### What to Mention

| Category | Details to Cover | Example (IRCTC) |
|----------|------------------|-----------------|
| **Components** | What pieces exist | Session Service, Memory Service, Agents |
| **Data Flow** | How data moves through the system | User → Router → Conversational Agent → Tools |
| **Agents** | Who does what | Conversational Agent (responds), Memory Agent (extracts facts) |
| **Services** | Supporting infrastructure | Vector DB, LLM API, Tool Registry |
| **State Management** | Where state lives | Working (RAM), Short-term (cache), Long-term (JSON) |

### Key Talking Points

- Break down the system into clear components
- Explain how data flows between them
- Identify which components are agents vs services

### Example Script

> "We have two agents: Conversational Agent handles the chat, Memory Agent extracts facts asynchronously. They communicate via a shared state object or message queue."

---

## R - Routing (2-3 minutes)

### What to Mention

| Category | Details to Cover | Example (IRCTC) |
|----------|------------------|-----------------|
| **Agent Orchestration** | How agents run | Sequential vs Parallel vs Hierarchical |
| **Communication Pattern** | How agents talk | Direct call, message queue, blackboard |
| **Decision Logic** | Who decides what | Router/intent classifier picks agent |

### Key Talking Points

- Sequential: Steps depend on previous output
- Parallel: Independent tasks run simultaneously
- Hierarchical: Master agent delegates to sub-agents

### Example Script

> "Conversational and Memory agents should run in parallel. User should not wait for fact extraction. Only Conversational Agent output is shown to the user."

---

## C - Constraints (2-3 minutes)

### What to Mention

| Category | Details to Cover | Example (IRCTC) |
|----------|------------------|-----------------|
| **Context Limit** | LLM has finite memory | Compress at 80%, summarize older turns |
| **LLM Failures** | External dependency | Continue chat, log error, retry async |
| **First Startup** | Empty state | Graceful init with empty memory JSON |
| **Contradictions** | Facts change | Prefer newer, log conflict, notify if critical |
| **Cost** | Cost per token | Smaller model for fact extraction, batch calls |

### Key Talking Points

- Always have a fallback for LLM failures
- Graceful handling of empty/null states
- Version facts for conflict detection

### Example Script

> "If LLM fails during fact extraction, we skip the update and continue the conversation — never block the user."

---

## H - Heuristics (1-2 minutes)

### What to Mention

| Category | Details to Cover | Example (IRCTC) |
|----------|------------------|-----------------|
| **Why This Architecture?** | Defend decisions | Parallel agents for latency, JSON for simplicity |
| **Why Not X?** | Show trade-offs | Redis would scale but JSON is faster to build |
| **Scaling Path** | What comes next | Redis for multi-user, separate DB for long-term |
| **Monitoring** | How to know it works | Log fact extraction accuracy, track context window usage |

### Key Talking Points

- Always justify your choices
- Show awareness of trade-offs
- Have a scaling plan ready

### Example Script

> "I chose JSON for long-term memory because it is simple and survives restarts. If we scale beyond single-user, we would migrate to Redis or a lightweight DB."

---

## ARCH in 30 Seconds (Opening Line)

> "I will design this using the ARCH framework: Architecture — the components and agents; Routing — how they communicate; Constraints — what can break and how we handle it; and Heuristics — why I chose this design."

---

## Time Allocation

| Phase | Time | Focus |
|-------|------|-------|
| **A** - Architecture | 3-4 min | Components, agents, data flow |
| **R** - Routing | 2-3 min | Sequential vs parallel, communication |
| **C** - Constraints | 2-3 min | Context limits, failures, edge cases |
| **H** - Heuristics | 1-2 min | Trade-offs, scaling, monitoring |

**Total: 8-12 minutes** (leaves time for their questions)

---

## Critical Gaps to Avoid

| Gap | ARCH Fix |
|-----|----------|
| Missing memory tiers | **A** - Explicitly name Working/Short-term/Long-term |
| No parallel execution | **R** - Say "agents run in parallel" |
| No failure handling | **C** - "skip update, continue chat" |
| No scaling plan | **H** - "simple now, Redis later" |

---

## Quick Reference Card

```
A - ArchitectureDIR (planning needed) - Components, Agents, Data Flow
R - Routing - Sequential, Parallel, Hierarchical
C - Constraints - Limits, Failures, Edge Cases
H - Heuristics - Trade-offs, Scaling, Why This Design
```

---

## Common Interview Questions by Category

### Architecture Questions
- What are the main components?
- How do agents communicate?
- Where does state live?

### Routing Questions
- Do agents run in parallel or sequentially?
- How do you handle agent failures?
- What if two agents need the same resource?

### Constraints Questions
- What if the LLM is down?
- How do you handle context window limits?
- What about multi-user isolation?

### Heuristics Questions
- Why did you choose X over Y?
- How would you scale this to 1M users?
- What would you do differently?

---

## Example: IRCTC Assistant Using ARCH

### A - Architecture
- **Session Service**: Manages conversation history
- **Memory Service**: Stores and retrieves user facts
- **Conversational Agent**: Handles user chat, calls tools
- **Memory Agent**: Extracts facts asynchronously
- **Tool Registry**: Booking, PNR, Refund tools

### R - Routing
- Conversational Agent and Memory Agent run **in parallel**
- Shared state via blackboard pattern
- Only Conversational Agent output shown to user

### C - Constraints
- Context window: Compress at 80% using summarization
- LLM failure: Skip fact extraction, continue chat
- First startup: Graceful init with empty JSON
- Contradictions: Prefer newer, log conflict

### H - Heuristics
- JSON for long-term memory (simple, survives restart)
- Parallel agents for low latency
- Smaller LLM for fact extraction (cost optimization)
- Future: Redis for multi-user, separate DB for scale

---

*Last updated: For Reliance Intelligence AI Engineer prep*
