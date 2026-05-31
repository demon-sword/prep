#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-system-design/scaffold.sh <topic>
# Creates system-design/<topic>/ folder with shared assets and initial plan.

TOPIC="${1:?Usage: $0 <topic>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOPIC_DIR="$PREP_ROOT/system-design/$TOPIC"
REF_ASSETS="$PREP_ROOT/system-design/claude/answers-html/assets"

if [[ -d "$TOPIC_DIR" ]]; then
  echo "Topic dir exists: $TOPIC_DIR"
else
  mkdir -p "$TOPIC_DIR/answers" "$TOPIC_DIR/answers-html/assets" "$TOPIC_DIR/scripts"
fi

if [[ -d "$REF_ASSETS" ]]; then
  cp -f "$REF_ASSETS/interactive.css" "$TOPIC_DIR/answers-html/assets/"
  cp -f "$REF_ASSETS/interactive.js" "$TOPIC_DIR/answers-html/assets/"
  echo "Copied interactive assets from claude/"
fi

cat > "$TOPIC_DIR/plan.md" <<EOF
# Plan: $TOPIC

## Meta
topic: $TOPIC
created: $(date +%Y-%m-%d)

## Done
- [x] 0 scaffold

## Next
- [ ] design-doc — write ${TOPIC}-design-doc.md
- [ ] gen-plan — run: bash ralph-system-design/gen-plan.sh $TOPIC
- [ ] md-to-html — run: python3 ralph-system-design/scripts/md_to_html.py $TOPIC
- [ ] architecture-map — write ${TOPIC}-frontend-architecture.html
- [ ] interview-template — write ${TOPIC}-system-design-interview.html
- [ ] index-html — write answers-html/index.html
- [ ] validate — run: bash ralph-system-design/validate.sh $TOPIC
EOF

touch "$TOPIC_DIR/progress.txt"
echo "$(date +%Y-%m-%d) | scaffold | created $TOPIC_DIR" >> "$TOPIC_DIR/progress.txt"

echo "Scaffolded: $TOPIC_DIR"
ls -la "$TOPIC_DIR"
