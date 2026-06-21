#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-ai-engineering/validate.sh <category-slug>
# Example: ./ralph-ai-engineering/validate.sh 02-rag-systems

CATEGORY="${1:?Usage: $0 <category-slug>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AI_ENG="$PREP_ROOT/ai-engineering"

python3 - "$CATEGORY" "$AI_ENG" "$SCRIPT_DIR/scripts" <<'PY'
import re
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[3])
from question_data import get_category  # noqa: E402

category_slug, ai_eng_root = sys.argv[1:3]
ai_eng = Path(ai_eng_root)
cat = get_category(category_slug)
errors: list[str] = []
ok: list[str] = []

CATEGORY_SECTIONS = [
    "## Interview signals",
    "## Mental model",
    "## Sub-topics",
    "## Decision framework",
    "## Common mistakes",
    "## Question checklist",
    "## One-page summary",
]

ANSWER_SECTIONS = [
    "## Framing",
    "## Answer",
    "## Verbal script",
    "## Pitfalls",
    "## Related questions",
    "## One-liner recall",
]


def fail(msg: str) -> None:
    errors.append(msg)


def pass_(msg: str) -> None:
    ok.append(msg)


def check_sections(path: Path, required: list[str], label: str) -> None:
    if not path.exists():
        fail(f"missing {label}: {path.relative_to(ai_eng)}")
        return
    text = path.read_text(encoding="utf-8")
    for sec in required:
        if sec not in text:
            fail(f"{path.name} missing section: {sec!r}")
    # Unfilled template placeholder detection
    if "<!-- " in text and "Question Text" in text:
        fail(f"{path.name} still contains template placeholders")
    pass_(f"{path.relative_to(ai_eng)} sections OK")


def check_related_questions(path: Path) -> None:
    """Require ≥2 markdown links in the ## Related questions section."""
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    rq_match = re.search(r"## Related questions(.+?)(?=\n## |\Z)", text, re.DOTALL)
    if not rq_match:
        fail(f"{path.name} ## Related questions section is empty")
        return
    links = re.findall(r"\[.+?\]\(.+?\)", rq_match.group(1))
    if len(links) < 2:
        fail(f"{path.name} has {len(links)} related link(s) — need ≥2")


# Check category overview doc
cat_path = ai_eng / cat.category_file
check_sections(cat_path, CATEGORY_SECTIONS, "category doc")

# Check all answer notes
for q in cat.questions:
    ans_path = ai_eng / q.file
    check_sections(ans_path, ANSWER_SECTIONS, f"answer Q{q.num}")
    check_related_questions(ans_path)

# Report
if not errors:
    print(f"validate: ALL PASSED for {category_slug} ({cat.name})")
    for msg in ok:
        print(f"  OK: {msg}")
    sys.exit(0)

print(f"validate: FAILED for {category_slug} ({cat.name})", file=sys.stderr)
for msg in errors:
    print(f"  FAIL: {msg}", file=sys.stderr)
sys.exit(1)
PY
