# Ralph — DSA Notes Generator

## Inputs (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-dsa/spec.md` |
| Plan | `dsa/plan.md` |
| Problem list | `dsa/neetcode-150-list.md` |
| Recognition guide | `dsa/patterns/recognition-guide.md` |
| Conventions | `dsa/README.md` |
| Problem template | `dsa/problems/_template.md` |
| Pattern template | `dsa/patterns/_template.md` |

**Category:** {{CATEGORY}} ({{CATEGORY_NAME}})

## Rules

1. Read `dsa/plan.md` — complete **exactly ONE** unchecked item from **Next** (first item only).
2. Use **Task/subagent** when research helps (LC problem statement, pattern variants).
3. **One task per run** — do not start the next plan item.
4. After completing the task:
   - Check off the item in `plan.md` (move to Done, remove from Next)
   - Append one line to `dsa/progress.txt` with date + category + what you did
   - For problem notes: add a row to the **Problem notes index** at the bottom of `dsa/progress.md` if missing
5. If **all** plan items are done and `bash ralph-dsa/validate.sh {{CATEGORY}}` passes, output `<promise>COMPLETE</promise>`.

## Task-specific guidance

### patterns/NN-*.md

- Copy structure from `dsa/patterns/_template.md` and reference example `dsa/patterns/03-sliding-window.md`
- Read all problems in this category from `neetcode-150-list.md`
- Define 2–4 **sub-patterns** specific to this category
- Include **pseudocode templates** only (no Python/Java)
- Populate the NeetCode checklist table with every problem in the category
- Add anti-patterns: common wrong approaches for this topic

### problems/NNN-*.md

- Copy `dsa/problems/_template.md` and fill every section — no HTML comments left as placeholders
- Set `**Status:**` `review` and `**Generated:**` ralph-dsa
- Set `**LC:**` from `neetcode-150-list.md`
- Read the category pattern doc if it exists (`dsa/patterns/{{CATEGORY}}.md`)
- **Pseudocode skeleton** must be problem-specific (~10–20 lines), not the empty template stub
- **Similar problems:** link 2–3 others from the same category
- **Pitfalls:** at least 2 concrete mistakes

### validate

- Run: `bash ralph-dsa/validate.sh {{CATEGORY}}`
- Fix any failures if validate is the current task and files are incomplete
- If validate passes, emit COMPLETE promise

## Verification

After substantive edits:

```bash
bash ralph-dsa/validate.sh {{CATEGORY}}
```

Report failures in `progress.txt` if blocked.

## Commit

One commit per plan item: `feat(dsa): {{CATEGORY}} — <short description>`

Do not push unless asked.
