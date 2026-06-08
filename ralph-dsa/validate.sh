#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-dsa/validate.sh <category-slug>
# Example: ./ralph-dsa/validate.sh 01-arrays-hashing

CATEGORY="${1:?Usage: $0 <category-slug>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DSA="$PREP_ROOT/dsa"

python3 - "$CATEGORY" "$DSA" "$SCRIPT_DIR/scripts" <<'PY'
import re
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[3])
from category_data import get_category  # noqa: E402

category_slug, dsa_root = sys.argv[1:3]
dsa = Path(dsa_root)
cat = get_category(category_slug)
errors: list[str] = []
ok: list[str] = []

PATTERN_SECTIONS = ["## Recognition", "## Sub-patterns", "## Templates", "## Anti-patterns", "One-page summary"]
PROBLEM_SECTIONS = ["## Framing", "## Approach", "Pseudocode skeleton", "## Tradeoffs", "One-liner recall"]


def fail(msg: str) -> None:
    errors.append(msg)


def pass_(msg: str) -> None:
    ok.append(msg)


def check_sections(path: Path, required: list[str], label: str) -> None:
    if not path.exists():
        fail(f"missing {label}: {path.relative_to(dsa)}")
        return
    text = path.read_text(encoding="utf-8")
    for sec in required:
        if sec not in text:
            fail(f"{path.name} missing section: {sec}")
    # Reject unfilled template placeholders
    if "<!--" in text and "Problem Title" in text:
        fail(f"{path.name} still contains template placeholders")
    pass_(f"{path.relative_to(dsa)} sections OK")


def check_pseudocode(path: Path) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    blocks = re.findall(r"```\n(.*?)```", text, re.DOTALL)
    skeleton_blocks = [b for b in blocks if "function " in b or "for each" in b or "←" in b]
    if not skeleton_blocks:
        fail(f"{path.name} missing pseudocode block")
        return
    best = max(skeleton_blocks, key=len)
    lines = [ln for ln in best.strip().splitlines() if ln.strip() and not ln.strip().startswith("//")]
    if len(lines) < 4:
        fail(f"{path.name} pseudocode too short (template stub?)")


pattern_path = dsa / cat.pattern_file
check_sections(pattern_path, PATTERN_SECTIONS, "pattern doc")
check_pseudocode(pattern_path)

for p in cat.problems:
    prob_path = dsa / p.file
    check_sections(prob_path, PROBLEM_SECTIONS, f"problem #{p.num}")
    check_pseudocode(prob_path)
    if prob_path.exists():
        text = prob_path.read_text(encoding="utf-8")
        if "**LC:**" not in text or "leetcode.com" not in text:
            fail(f"{prob_path.name} missing LeetCode URL")

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
