#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-concepts/validate.sh [concept-id]
# Without argument: validates all generated concepts.
# With argument: validates one concept (e.g. 01-self-supervision).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONCEPTS_DIR="$PREP_ROOT/ai-engineering/concepts"
CONCEPTS_JSON="$SCRIPT_DIR/concepts.json"

TARGET="${1:-all}"

python3 - "$TARGET" "$CONCEPTS_DIR" "$CONCEPTS_JSON" <<'PY'
import json
import re
import sys
from pathlib import Path

target, concepts_dir_str, concepts_json_path = sys.argv[1:4]
concepts_dir = Path(concepts_dir_str)
concepts = json.loads(Path(concepts_json_path).read_text())

if target != "all":
    concepts = [c for c in concepts if c["id"] == target or c["slug"] == target]
    if not concepts:
        print(f"Unknown concept: {target}", file=sys.stderr)
        sys.exit(1)

REQUIRED_SECTIONS = [
    '<section id="theory">',
    '<section id="visualization">',
    '<section id="takeaways">',
    'class="concept-nav"',
]

PLACEHOLDER_PATTERNS = [
    r'\bTODO\b',
    r'\bPLACEHOLDER\b',
    r'Lorem ipsum',
    r'coming soon',
    r'<!-- [A-Z]',  # leftover HTML comments with caps (template stubs)
]

errors = []
ok = []
skipped = []

for c in concepts:
    filename = f"{c['id']}.html"
    path = concepts_dir / filename

    if not path.exists():
        skipped.append(f"SKIP  {filename} (not yet generated)")
        continue

    html = path.read_text(encoding="utf-8")

    concept_errors = []

    # Required sections
    for section in REQUIRED_SECTIONS:
        if section not in html:
            concept_errors.append(f"missing required element: {section!r}")

    # Header element
    if "<header" not in html:
        concept_errors.append("missing <header> element")

    # Event listener or animation (at least one interactive element)
    has_interaction = (
        "addEventListener" in html
        or "requestAnimationFrame" in html
        or "onclick" in html
        or "oninput" in html
    )
    if not has_interaction:
        concept_errors.append("no event listener or animation loop found — viz not interactive")

    # Placeholder check
    for pattern in PLACEHOLDER_PATTERNS:
        if re.search(pattern, html):
            concept_errors.append(f"placeholder text found matching: {pattern!r}")

    # Self-contained check (no local src= or href= to local files)
    local_refs = re.findall(r'(?:src|href)=["\'](?!https?://|//|data:|#|mailto:)([^"\']+)["\']', html)
    # Allow Google Fonts
    non_font_local = [r for r in local_refs if "fonts.googleapis.com" not in r and "fonts.gstatic.com" not in r]
    if non_font_local:
        concept_errors.append(f"local file references found (not self-contained): {non_font_local}")

    # Theory length (rough check: count text between theory tags)
    theory_match = re.search(r'<section id="theory">(.*?)</section>', html, re.DOTALL)
    if theory_match:
        # Strip tags to count text content approximately
        text_only = re.sub(r'<[^>]+>', '', theory_match.group(1))
        word_count = len(text_only.split())
        if word_count < 150:  # roughly 400 chars → 150 words
            concept_errors.append(f"theory section too short ({word_count} words) — need ≥150 words of content")

    if concept_errors:
        errors.extend([f"FAIL  {filename}: {e}" for e in concept_errors])
    else:
        ok.append(f"OK    {filename}")

# Report
print(f"\nValidation report — ralph-concepts")
print(f"  Checked: {len(ok) + len(errors)} | Passed: {len(ok)} | Failed: {len(errors)} | Skipped: {len(skipped)}")
print()

for msg in ok:
    print(f"  {msg}")

for msg in skipped:
    print(f"  {msg}")

if errors:
    print()
    for msg in errors:
        print(f"  {msg}", file=sys.stderr)
    sys.exit(1)
else:
    if len(skipped) == len(concepts):
        print("  No concepts generated yet — run the loop first.")
    else:
        print(f"\nAll generated concepts pass validation.")
    sys.exit(0)
PY
