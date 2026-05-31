#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-system-design/gen-plan.sh <topic>
# Parses design-doc sections and injects answer tasks into plan.md

TOPIC="${1:?Usage: $0 <topic>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOPIC_DIR="$PREP_ROOT/system-design/$TOPIC"
DESIGN_DOC="$TOPIC_DIR/${TOPIC}-design-doc.md"
PLAN="$TOPIC_DIR/plan.md"

[[ -f "$DESIGN_DOC" ]] || { echo "Missing $DESIGN_DOC" >&2; exit 1; }
[[ -f "$PLAN" ]] || { echo "Missing $PLAN" >&2; exit 1; }

python3 - "$TOPIC" "$DESIGN_DOC" "$PLAN" <<'PY'
import re
import sys
from pathlib import Path

topic, design_path, plan_path = sys.argv[1:4]
design = Path(design_path).read_text(encoding="utf-8")
plan = Path(plan_path).read_text(encoding="utf-8")

sections = []
for m in re.finditer(r'^##\s+(\d+)\.\s+(.+)$', design, re.MULTILINE):
    num = m.group(1).zfill(2)
    title = m.group(2).strip()
    slug = re.sub(r'[^\w\s-]', '', title.lower())
    slug = re.sub(r'[\s_]+', '-', slug).strip('-')[:60]
    sections.append((num, slug, title))

if not sections:
    print("No sections found (expected ## N. Title)", file=sys.stderr)
    sys.exit(1)

answer_tasks = []
for num, slug, title in sections:
    fname = f"answers/{num}-{slug}.md"
    answer_tasks.append(f"- [ ] {fname} — section {num}: {title}")

# Rebuild Next block: answer tasks + remaining pipeline tasks
pipeline = [
    "- [ ] md-to-html — run: python3 ralph-system-design/scripts/md_to_html.py " + topic,
    f"- [ ] architecture-map — write {topic}-frontend-architecture.html",
    f"- [ ] interview-template — write {topic}-system-design-interview.html",
    "- [ ] index-html — write answers-html/index.html",
    f"- [ ] validate — run: bash ralph-system-design/validate.sh {topic}",
]

if "## Next" not in plan:
    print("plan.md missing ## Next", file=sys.stderr)
    sys.exit(1)

# Mark gen-plan done if present
plan = re.sub(
    r'- \[ \] gen-plan[^\n]*',
    '- [x] gen-plan — sections parsed from design doc',
    plan,
)

# Remove old answer tasks and rebuild Next
before, _, after_next = plan.partition("## Next\n")
# strip old next content until ## Done or EOF - we'll replace entire Next section
done_match = re.search(r'## Done\n(.*?)(?=\n## |\Z)', plan, re.DOTALL)
done_block = done_match.group(0) if done_match else "## Done\n"

if "- [ ] gen-plan" not in done_block and "- [x] gen-plan" not in done_block:
    done_block = done_block.rstrip() + "\n- [x] gen-plan — sections parsed from design doc\n"

new_plan = before.split("## Done")[0] + done_block + "\n## Next\n"
new_plan += "\n".join(answer_tasks + pipeline) + "\n"

Path(plan_path).write_text(new_plan, encoding="utf-8")
print(f"Injected {len(sections)} answer tasks into {plan_path}")
for t in answer_tasks:
    print(f"  {t}")
PY

echo "$(date +%Y-%m-%d) | gen-plan | $(grep -c 'answers/' "$PLAN" || true) answer tasks" >> "$TOPIC_DIR/progress.txt"
