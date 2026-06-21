#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-ai-engineering/scaffold.sh <category-slug>
# Example: ./ralph-ai-engineering/scaffold.sh 02-rag-systems
#
# Creates ai-engineering/plan.md queue for ONE category. When moving to the
# next category, run scaffold again — validate the previous category first.

CATEGORY="${1:?Usage: $0 <category-slug>  e.g. 02-rag-systems}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AI_ENG="$PREP_ROOT/ai-engineering"
PLAN="$AI_ENG/plan.md"
PROGRESS="$AI_ENG/progress.txt"

mkdir -p "$AI_ENG/categories" "$AI_ENG/answers" "$SCRIPT_DIR/.logs"

python3 - "$CATEGORY" "$PLAN" "$PROGRESS" "$SCRIPT_DIR/scripts" <<'PY'
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, sys.argv[4])
from question_data import get_category  # noqa: E402

category_slug, plan_path, progress_path = sys.argv[1:4]
cat = get_category(category_slug)
today = date.today().isoformat()

plan_file = Path(plan_path)
progress_file = Path(progress_path)

# Preserve "Categories completed" from any existing plan
categories_completed: list[str] = []
if plan_file.exists():
    text = plan_file.read_text(encoding="utf-8")
    in_section = False
    for line in text.splitlines():
        if line.strip() == "## Categories completed":
            in_section = True
            continue
        if in_section:
            if line.startswith("## "):
                break
            stripped = line.strip()
            if stripped and stripped != "_none yet_":
                categories_completed.append(stripped)

    # If switching categories, record the previous active one
    m = re.search(r"current_category:\s*(\S+)", text)
    if m and m.group(1) != category_slug:
        prev = m.group(1)
        entry = f"- {prev} (switched on {today})"
        if entry not in categories_completed:
            categories_completed.append(entry)

# Build task list
tasks: list[str] = []
tasks.append(
    f"- [ ] {cat.category_file} — category overview: {cat.name} ({len(cat.questions)} questions)"
)
for q in cat.questions:
    tasks.append(f"- [ ] {q.file} — Q{q.num}: {q.text[:80]}")
tasks.append(f"- [ ] validate — run: bash ralph-ai-engineering/validate.sh {cat.slug}")

done_block = "## Done\n- [x] 0 scaffold — category queue created\n"

completed_block = "## Categories completed\n"
if categories_completed:
    completed_block += "\n".join(categories_completed) + "\n"
else:
    completed_block += "_none yet_\n"

first_q_num = cat.questions[0].num if cat.questions else 1
last_q_num  = cat.questions[-1].num if cat.questions else 1

plan = f"""# Plan: AI Engineering Interview Prep

## Meta
current_category: {cat.slug}
category_name: {cat.name}
category_num: {cat.num}
question_range: {first_q_num}–{last_q_num}
task_count: {len(tasks)}
created: {today}

{done_block}
{completed_block}
## Next
{chr(10).join(tasks)}
"""

plan_file.write_text(plan, encoding="utf-8")
progress_file.touch(exist_ok=True)
with progress_file.open("a", encoding="utf-8") as f:
    f.write(f"{today} | scaffold | queued {cat.slug} ({len(tasks)} tasks)\n")

print(f"Scaffolded category: {cat.slug} ({cat.name})")
print(f"  Category doc: {cat.category_file}")
print(f"  Questions: {len(cat.questions)}")
print(f"  Total tasks: {len(tasks)}")
print(f"  Plan: {plan_path}")
print("")
print("Next:")
print(f"  ./ralph-ai-engineering/once.sh {cat.slug}")
print(f"  ./ralph-ai-engineering/loop.sh {cat.slug} {len(tasks) + 5}")
PY
