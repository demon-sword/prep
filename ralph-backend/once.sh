#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-backend/once.sh [concept-id] [--model <slug>]
#
# concept-id (optional): generate a specific concept by id, e.g. 11-consensus-algorithms
#                        If omitted, picks the first unchecked item in plan.md.
#
# Examples:
#   ./ralph-backend/once.sh                             # next in queue
#   ./ralph-backend/once.sh 11-consensus-algorithms     # specific concept
#   ./ralph-backend/once.sh 19-indexing-storage-engines --model claude-sonnet-4

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PREP_ROOT"

MODEL="${RALPH_BACKEND_MODEL:-}"
AGENT_TIMEOUT_SEC="${RALPH_BACKEND_TIMEOUT:-3600}"
TARGET_CONCEPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model|-m) MODEL="$2"; shift 2 ;;
    --help|-h)
      sed -n '1,15p' "$0" >&2
      echo "" >&2
      echo "Available concept IDs:" >&2
      python3 -c "
import json, pathlib
concepts = json.loads(pathlib.Path('$SCRIPT_DIR/concepts.json').read_text())
for c in concepts:
    print(f\"  {c['id']:35s} {c['title']}\")
" >&2
      exit 0
      ;;
    -*)
      echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      # Positional = concept id
      TARGET_CONCEPT="$1"; shift ;;
  esac
done

PLAN="$SCRIPT_DIR/plan.md"
PROGRESS="$SCRIPT_DIR/progress.txt"
SPEC="$SCRIPT_DIR/spec.md"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
CONCEPTS_JSON="$SCRIPT_DIR/concepts.json"

[[ -f "$PLAN" ]] || {
  echo "Missing $PLAN — run ./ralph-backend/scaffold.sh first" >&2
  exit 1
}

# Validate target concept if specified
if [[ -n "$TARGET_CONCEPT" ]]; then
  CONCEPT_EXISTS=$(python3 -c "
import json, pathlib, sys
concepts = json.loads(pathlib.Path('$CONCEPTS_JSON').read_text())
ids = [c['id'] for c in concepts]
print('yes' if '$TARGET_CONCEPT' in ids else 'no')
")
  if [[ "$CONCEPT_EXISTS" != "yes" ]]; then
    echo "Unknown concept id: '$TARGET_CONCEPT'" >&2
    echo "" >&2
    echo "Available IDs:" >&2
    python3 -c "
import json, pathlib
concepts = json.loads(pathlib.Path('$CONCEPTS_JSON').read_text())
for c in concepts:
    print(f\"  {c['id']:35s} {c['title']}\")
" >&2
    exit 1
  fi
  # Check if already done
  HTML_PATH="$PREP_ROOT/backend/concepts/${TARGET_CONCEPT}.html"
  if [[ -f "$HTML_PATH" ]]; then
    echo "Note: $TARGET_CONCEPT already has a generated file at:"
    echo "  $HTML_PATH"
    echo "Regenerating (will overwrite)..."
  fi
fi

# Check if anything is left to do (only relevant when no specific target)
if [[ -z "$TARGET_CONCEPT" ]] && ! grep -q '^\- \[ \]' "$PLAN" 2>/dev/null; then
  echo "All concepts complete (no unchecked items in plan.md)."
  exit 0
fi

mkdir -p "$SCRIPT_DIR/.logs"
LOG_DIR="$SCRIPT_DIR/.logs"
LOG_FILE="$LOG_DIR/iter-$(date +%Y%m%d-%H%M%S).log"

# Resolve which concept will be worked on (for display)
if [[ -n "$TARGET_CONCEPT" ]]; then
  DISPLAY_CONCEPT="$TARGET_CONCEPT"
  TARGET_INSTRUCTION="Generate the concept with id: ${TARGET_CONCEPT}
The file should be at: $PREP_ROOT/backend/concepts/${TARGET_CONCEPT}.html
Mark it as done in ralph-backend/plan.md even if it was already checked."
else
  DISPLAY_CONCEPT="(next in queue)"
  TARGET_INSTRUCTION="Pick the FIRST unchecked item from the ## Next section of ralph-backend/plan.md."
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ralph Backend — concept: $DISPLAY_CONCEPT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Log: $LOG_FILE" >&2
echo "Timeout: ${AGENT_TIMEOUT_SEC}s" >&2

# Build prompt: inline all context. Per-concept source notes (ralph-backend/sources/<id>.md)
# are NOT inlined here — the agent reads the relevant one itself per prompt.md's instructions,
# based on the "source" field it sees in concepts.json below.
CONTEXT="$(cat "$SPEC" "$CONCEPTS_JSON" "$PLAN" "$PROGRESS" "$PROMPT_FILE" 2>/dev/null || true)"

TASK="You are generating interactive HTML concept files for Backend / Distributed Systems interview study.

WORKSPACE ROOT: $PREP_ROOT
OUTPUT DIR: $PREP_ROOT/backend/concepts/
SOURCE NOTES DIR (read the file named in a concept's 'source' field, if present): $PREP_ROOT/ralph-backend/sources/

${CONTEXT}

TASK: ${TARGET_INSTRUCTION}
If the chosen concept has a 'source' field, read that file FIRST and adapt it faithfully per spec.md.
Generate the HTML file. Validate it. Test it with Playwright MCP.
Fix any issues. Mark the plan item done. Append to progress.txt.
Emit <promise>COMPLETE</promise> ONLY if ALL plan items are now checked (entire plan done).
Otherwise just finish normally after completing the ONE item."

# Build claude command
CLAUDE_FLAGS=(-p --dangerously-skip-permissions --output-format stream-json --verbose)
[[ -n "$MODEL" ]] && CLAUDE_FLAGS+=(--model "$MODEL")

echo "Running Claude..." >&2

set +e
claude "${CLAUDE_FLAGS[@]}" "$TASK" &
AGENT_PID=$!

# Watchdog
(sleep "$AGENT_TIMEOUT_SEC" && kill -INT "$AGENT_PID" 2>/dev/null && sleep 60 && kill -KILL "$AGENT_PID" 2>/dev/null) &
WATCHDOG_PID=$!

wait "$AGENT_PID"
RC=$?

kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
set -e

if [[ "$RC" -eq 124 ]] || [[ "$RC" -eq 142 ]]; then
  echo "Agent killed after ${AGENT_TIMEOUT_SEC}s" >&2
  exit 124
fi

# Check if plan is fully done now
if ! grep -q '^\- \[ \]' "$PLAN" 2>/dev/null; then
  echo "All concepts complete!"
  bash "$SCRIPT_DIR/validate.sh" || true
  exit 0
fi

echo "Concept generated. Continue loop for next item."
exit 2
