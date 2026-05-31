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
