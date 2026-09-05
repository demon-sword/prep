#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-data-drills/scaffold.sh <group-slug>
# Example: ./ralph-data-drills/scaffold.sh sql-01-window-functions
#
# Creates the data-drills/plan.md queue for ONE group. When moving to the next
# group, run scaffold again — the previous group should be validated complete
# first (bash ralph-data-drills/validate.sh <group>).

GROUP="${1:?Usage: $0 <group-slug>  e.g. sql-01-window-functions}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# RALPH_DD_OUT / RALPH_DD_PROBLEMS are honoured here as well as in
# validate.sh. They were read only by the validator, so setting one pointed
# it at a directory the generator never wrote to.
DRILLS="${RALPH_DD_OUT:-$PREP_ROOT/data-drills}"
PLAN="$DRILLS/plan.md"
PROGRESS="$DRILLS/progress.txt"
PROBLEMS="${RALPH_DD_PROBLEMS:-$SCRIPT_DIR/problems.json}"

[[ -f "$PROBLEMS" ]] || { echo "Missing $PROBLEMS" >&2; exit 1; }

mkdir -p "$DRILLS/sql" "$DRILLS/stats" "$SCRIPT_DIR/.logs"

python3 - "$GROUP" "$PLAN" "$PROGRESS" "$PROBLEMS" <<'PY'
import json
import re
import sys
from datetime import date
from pathlib import Path

group_slug, plan_path, progress_path, problems_path = sys.argv[1:5]

# Canonical group order + display names (the 12 slugs from the contract).
# This is the ONE place a group's human name is defined; once.sh reads it back
# out of the plan Meta block rather than duplicating the table.
GROUP_NAMES = {
    "sql-01-window-functions": "Window Functions",
    "sql-02-joins-and-nulls": "Joins and NULLs",
    "sql-03-aggregation-grouping": "Aggregation and Grouping",
    "sql-04-ctes-and-recursion": "CTEs and Recursion",
    "sql-05-time-and-cohorts": "Time and Cohorts",
    "sql-06-modeling-and-performance": "Modeling and Performance",
    "stats-01-probability-puzzles": "Probability Puzzles",
    "stats-02-expectation-and-counting": "Expectation and Counting",
    "stats-03-markov-and-processes": "Markov Chains and Processes",
    "stats-04-distributions-and-estimation": "Distributions and Estimation",
    "stats-05-inference-and-testing": "Inference and Testing",
    "stats-06-bias-and-reasoning": "Bias and Reasoning",
}

problems = json.loads(Path(problems_path).read_text(encoding="utf-8"))
if not isinstance(problems, list):
    sys.exit(f"{problems_path}: top level must be a JSON array")

# Valid slugs = the groups problems.json actually carries, in canonical order.
order = list(GROUP_NAMES)
present = {p.get("group") for p in problems}
valid = [g for g in order if g in present] + sorted(present - set(order))

if group_slug not in present:
    print(f"Unknown group: {group_slug}", file=sys.stderr)
    print("Valid group slugs:", file=sys.stderr)
    for g in valid:
        n = sum(1 for p in problems if p.get("group") == g)
        print(f"  {g}  ({GROUP_NAMES.get(g, g)}, {n} problems)", file=sys.stderr)
    sys.exit(1)

group = [p for p in problems if p.get("group") == group_slug]
group.sort(key=lambda p: p.get("id", ""))
family = group[0].get("family", "")
group_name = GROUP_NAMES.get(group_slug, group_slug)
today = date.today().isoformat()

plan_file = Path(plan_path)
progress_file = Path(progress_path)
old = plan_file.read_text(encoding="utf-8") if plan_file.exists() else ""

# Preserve every previously completed group verbatim.
groups_completed = []
in_section = False
for line in old.splitlines():
    if line.strip() == "## Groups completed":
        in_section = True
        continue
    if in_section:
        if line.startswith("## "):
            break
        entry = line.strip()
        if entry.startswith("- ") and entry != "_none yet_":
            groups_completed.append(entry)

# Append the previously active group when switching to a different one.
m = re.search(r"^current_group:\s*(\S+)", old, re.M)
if m and m.group(1) != group_slug:
    prev = m.group(1)
    if not any(e.startswith(f"- {prev} ") or e == f"- {prev}" for e in groups_completed):
        groups_completed.append(f"- {prev} (switched on {today})")

def annotate(p):
    bits = [p.get("difficulty", "?")]
    dialect = p.get("dialect")
    if dialect and dialect != "sqlite":
        bits.append(f"dialect={dialect}, no-exec")
    if p.get("mc"):
        bits.append(f"monte-carlo tol={p.get('mc_tolerance')} {p.get('mc_tolerance_kind')}")
    return ", ".join(str(b) for b in bits)

tasks = [
    f"- [ ] {p.get('file')} — {p.get('id')} {p.get('title')} ({annotate(p)})"
    for p in group
]
tasks.append(f"- [ ] validate — run: bash ralph-data-drills/validate.sh {group_slug}")

done_block = """## Done
- [x] 0 scaffold — group queue created
"""

completed_block = "## Groups completed\n"
completed_block += ("\n".join(groups_completed) + "\n") if groups_completed else "_none yet_\n"

plan = f"""# Plan: Data Drills — SQL & Statistics

## Meta
current_group: {group_slug}
family: {family}
group_name: {group_name}
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
    f.write(f"{today} | scaffold | queued {group_slug} ({len(tasks)} tasks)\n")

print(f"Scaffolded group: {group_slug} ({group_name})")
print(f"  Family: {family}")
print(f"  Problems: {len(group)}")
print(f"  Plan: {plan_path}")
print("")
print("Next:")
print(f"  ./ralph-data-drills/once.sh {group_slug}")
print(f"  ./ralph-data-drills/loop.sh {group_slug} {len(tasks) + 2}")
PY
