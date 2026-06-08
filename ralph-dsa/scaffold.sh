#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-dsa/scaffold.sh <category-slug>
# Example: ./ralph-dsa/scaffold.sh 01-arrays-hashing
#
# Creates dsa/plan.md queue for ONE category. When moving to the next category,
# run scaffold again — previous category should be validated complete first.

CATEGORY="${1:?Usage: $0 <category-slug>  e.g. 01-arrays-hashing}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DSA="$PREP_ROOT/dsa"
PLAN="$DSA/plan.md"
PROGRESS="$DSA/progress.txt"

mkdir -p "$DSA/problems" "$DSA/patterns" "$SCRIPT_DIR/.logs"

python3 - "$CATEGORY" "$PLAN" "$PROGRESS" "$SCRIPT_DIR/scripts" <<'PY'
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, sys.argv[4])
from category_data import get_category  # noqa: E402

category_slug, plan_path, progress_path = sys.argv[1:4]
cat = get_category(category_slug)
today = date.today().isoformat()

plan_file = Path(plan_path)
progress_file = Path(progress_path)

categories_completed = []
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
            m = line.strip().lstrip("- ").split(" ", 1)
            if m and m[0].startswith("0") or m[0].startswith("1"):
                categories_completed.append(line.strip())

# Preserve completed categories; append previous active if switching
prev_meta = ""
if plan_file.exists() and "## Meta" in plan_file.read_text(encoding="utf-8"):
    import re
    m = re.search(r"current_category:\s*(\S+)", plan_file.read_text(encoding="utf-8"))
    if m and m.group(1) != category_slug:
        prev = m.group(1)
        entry = f"- {prev} (switched on {today})"
        if entry not in categories_completed:
            categories_completed.append(entry)

tasks = []
tasks.append(f"- [ ] {cat.pattern_file} — pattern doc: {cat.name} ({len(cat.problems)} problems)")
for p in cat.problems:
    tasks.append(
        f"- [ ] {p.file} — #{p.num} {p.name} ({p.difficulty})"
    )
tasks.append(f"- [ ] validate — run: bash ralph-dsa/validate.sh {cat.slug}")

done_block = """## Done
- [x] 0 scaffold — category queue created
"""

completed_block = "## Categories completed\n"
if categories_completed:
    completed_block += "\n".join(categories_completed) + "\n"
else:
    completed_block += "_none yet_\n"

plan = f"""# Plan: NeetCode 150

## Meta
current_category: {cat.slug}
category_name: {cat.name}
category_num: {cat.num}
problem_range: {cat.problems[0].num}–{cat.problems[-1].num}
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
print(f"  Pattern: {cat.pattern_file}")
print(f"  Problems: {len(cat.problems)}")
print(f"  Plan: {plan_path}")
print("")
print("Next:")
print(f"  ./ralph-dsa/once.sh {cat.slug}")
print(f"  ./ralph-dsa/loop.sh {cat.slug} 15")
PY
