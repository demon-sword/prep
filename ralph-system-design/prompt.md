# Ralph — System Design Topic Generator

## Inputs (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-system-design/spec.md` |
| Plan | `system-design/{{TOPIC}}/plan.md` |
| Reference | `system-design/claude/` (structure only) |
| Format | `system-design/README.md` |

Topic: **{{TOPIC}}**

## Rules

1. Read `plan.md` — complete **exactly ONE** unchecked item from **Next** (first item only).
2. Use **Task/subagent** (`subagent_type=generalPurpose` or `explore`) when the task spans research + writing (e.g. answer sections, architecture nodes).
3. Do **not** add interactive demo widgets (`data-demo`) to HTML.
4. Do **not** start the next plan item — one task per run.
5. After completing the task:
   - Check off the item in `plan.md` (move to Done, update Next)
   - Append one line to `system-design/{{TOPIC}}/progress.txt` with date + what you did
6. If **all** plan items are done and `ralph-system-design/validate.sh {{TOPIC}}` would pass, output `<promise>COMPLETE</promise>`.

## Task-specific guidance

### design-doc
Research {{TOPIC}} frontend system design. Write `<topic>-design-doc.md` with 6–10 themed sections. Each section: brief intro, ### Core (5+ questions), ### Deep (3+ questions). Match `claude/Claude-design-doc.md` structure.

### answers/NN-*.md
Read the matching section in design-doc. Write interview-depth answers for **every** question. Each answer: Problem framing → Approach → Tradeoffs. Use subagent if helpful for research.

### architecture-map
Build `<topic>-frontend-architecture.html` — interactive diagram (layers, nodes tagged to sections, flow walkthroughs, click-for-detail). Reference `claude/claude-frontend-architecture.html` for structure. Use subagents to research section mappings.

### interview-template
Build `<topic>-system-design-interview.html` — full 45–60m answer per README interview format. Link to architecture map and section pages.

### index-html
Build `answers-html/index.html` — list all sections from design doc, link to architecture + interview templates.

### md-to-html
Run: `python3 ralph-system-design/scripts/md_to_html.py {{TOPIC}}` — do not hand-write section HTML unless script fails.

## Verification

After substantive edits, run narrowest check:
- `bash ralph-system-design/validate.sh {{TOPIC}}` (note failures in progress.txt if blocked)
- For md-to-html task: confirm 1:1 md/html parity

## Commit

One commit per plan item: `feat({{TOPIC}}): <short description>`

Do not push unless asked.

## Fact-check gate (runs after you finish — you cannot bypass it)

Once you finish, a **separate agent** is given your finished file and nothing
else. It is told it did not write the file, and asked to find any incorrect
formula, wrong mechanism description, or false factual claim. Its verdict is
required before this item is accepted, and it does not see your reasoning — so a
claim that only looks right in context will be caught.

Write for that reviewer:

- Every formula must be correct as written, including scaling factors,
  normalisation terms and exponents. If you write softmax(QKᵀ/√d_k)V, the √d_k
  must be there and must be in the denominator.
- Every number must be real. Do not invent benchmark figures, parameter counts,
  latencies or costs to make a sentence land. If you are not sure of a number,
  describe the magnitude qualitatively instead.
- Attribute papers, tools and techniques correctly, or not at all.
- Do not pad to hit a word count with claims you cannot stand behind. A shorter
  section that is true beats a longer one that is not — the word floor is a
  minimum for *real* content, not a licence to speculate.
- Keep the visualization's numbers consistent with the prose. If the text says
  the ring has 128 virtual nodes, the JS must not use 64.

If this item comes back rejected, you will be shown the exact FAIL lines. Fix the
underlying fact — do not reword around it.
