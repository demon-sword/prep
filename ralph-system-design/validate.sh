#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-system-design/validate.sh <topic>
TOPIC="${1:?Usage: $0 <topic>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIR="$PREP_ROOT/system-design/$TOPIC"
ERR=0

fail() { echo "FAIL: $1" >&2; ERR=1; }
pass() { echo "OK: $1"; }

[[ -d "$DIR" ]] || { fail "missing $DIR"; exit 1; }

DESIGN="$DIR/${TOPIC}-design-doc.md"
[[ -f "$DESIGN" ]] || fail "missing $DESIGN"
[[ -f "$DESIGN" ]] && pass "design doc exists"

ARCH="$DIR/${TOPIC}-frontend-architecture.html"
[[ -f "$ARCH" ]] || fail "missing $ARCH"
[[ -f "$ARCH" ]] && pass "architecture map exists"

INTERVIEW="$DIR/${TOPIC}-system-design-interview.html"
[[ -f "$INTERVIEW" ]] || fail "missing $INTERVIEW"
[[ -f "$INTERVIEW" ]] && pass "interview template exists"

INDEX="$DIR/answers-html/index.html"
[[ -f "$INDEX" ]] || fail "missing $INDEX"
[[ -f "$INDEX" ]] && pass "index exists"

[[ -f "$DIR/answers-html/assets/interactive.js" ]] || fail "missing interactive.js"
[[ -f "$DIR/answers-html/assets/interactive.css" ]] || fail "missing interactive.css"
pass "shared assets present"

# Section count from design doc
SECTION_COUNT=$(grep -cE '^## [0-9]+\.' "$DESIGN" 2>/dev/null || echo 0)
# find exits 1 on a path that does not exist, pipefail makes that the whole
# pipeline's status, and errexit then kills the script — so a missing answers/
# dir crashed the validator instead of producing the FAIL: line written for it.
MD_COUNT=0
HTML_COUNT=0
[[ -d "$DIR/answers" ]] && MD_COUNT=$(find "$DIR/answers" -maxdepth 1 -name '[0-9]*.md' | wc -l | tr -d ' ')
[[ -d "$DIR/answers-html" ]] && HTML_COUNT=$(find "$DIR/answers-html" -maxdepth 1 -name '[0-9]*.html' | wc -l | tr -d ' ')

if [[ "$SECTION_COUNT" -gt 0 && "$MD_COUNT" -ge "$SECTION_COUNT" ]]; then
  pass "answers md count ($MD_COUNT) >= sections ($SECTION_COUNT)"
else
  fail "answers md count ($MD_COUNT) < sections ($SECTION_COUNT)"
fi

if [[ "$HTML_COUNT" -ge "$MD_COUNT" && "$MD_COUNT" -gt 0 ]]; then
  pass "html count ($HTML_COUNT) >= md count ($MD_COUNT)"
else
  fail "html/md parity ($HTML_COUNT html vs $MD_COUNT md)"
fi

# Problem framing in all answer files
for md in "$DIR"/answers/[0-9]*.md; do
  [[ -f "$md" ]] || continue
  if ! grep -qE "Problem framing" "$md"; then
    fail "$(basename "$md") missing Problem framing"
  fi
done
pass "all answer files have Problem framing"

if [[ "$ERR" -eq 0 ]]; then
  echo "validate: ALL PASSED for $TOPIC"
  exit 0
else
  echo "validate: FAILED for $TOPIC"
  exit 1
fi
