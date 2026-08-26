#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-machine-learning/scaffold.sh
# Builds ralph-machine-learning/plan.md from concepts.json.
# Re-run to reset the plan (preserves already-generated HTML files).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONCEPTS_JSON="$SCRIPT_DIR/concepts.json"
PLAN="$SCRIPT_DIR/plan.md"
PROGRESS="$SCRIPT_DIR/progress.txt"
CONCEPTS_DIR="$PREP_ROOT/machine_learning/concepts"

mkdir -p "$CONCEPTS_DIR" "$SCRIPT_DIR/.logs"
touch "$PROGRESS"

python3 - "$CONCEPTS_JSON" "$PLAN" "$PROGRESS" "$CONCEPTS_DIR" <<'PY'
import json
import sys
from datetime import date
from pathlib import Path

concepts_path, plan_path, progress_path, concepts_dir = sys.argv[1:5]

concepts = json.loads(Path(concepts_path).read_text())
today = date.today().isoformat()
plan_file = Path(plan_path)

# Preserve existing done items (concepts already generated)
done_ids = set()
if plan_file.exists():
    for line in plan_file.read_text().splitlines():
        if line.strip().startswith("- [x]"):
            # Extract id from line like "- [x] 01-bias-variance-tradeoff — ..."
            parts = line.strip().removeprefix("- [x]").strip().split(" — ")
            if parts:
                done_ids.add(parts[0].strip())

# Build next list
next_tasks = []
done_tasks = ["- [x] scaffold — plan created"]
for c in concepts:
    cid = c["id"]
    label = f"{cid} — {c['title']}"
    filename = f"{cid}.html"
    html_path = Path(concepts_dir) / filename
    if cid in done_ids or html_path.exists():
        done_tasks.append(f"- [x] {label}")
    else:
        next_tasks.append(f"- [ ] {label}")

total = len(concepts)
done_count = len(done_tasks) - 1  # subtract scaffold line
remaining = len(next_tasks)

plan = f"""# Plan: Machine Learning Concepts

## Meta
total_concepts: {total}
done: {done_count}
remaining: {remaining}
created: {today}

## Done
{chr(10).join(done_tasks)}

## Next
{chr(10).join(next_tasks) if next_tasks else "_all done_"}
"""

plan_file.write_text(plan.strip() + "\n", encoding="utf-8")

with open(progress_path, "a", encoding="utf-8") as f:
    f.write(f"{today} | scaffold | {done_count} done, {remaining} remaining\n")

print(f"Scaffolded ralph-machine-learning plan")
print(f"  Total concepts: {total}")
print(f"  Already done:   {done_count}")
print(f"  Remaining:      {remaining}")
print(f"  Plan: {plan_path}")
print("")
if remaining > 0:
    print("Next:")
    print(f"  ./ralph-machine-learning/once.sh")
    print(f"  ./ralph-machine-learning/loop.sh {remaining + 5}")
else:
    print("All concepts done!")
PY
