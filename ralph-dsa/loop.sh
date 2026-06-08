#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-dsa/loop.sh <category-slug> [max_iterations] [--model <slug>]
# Example: ./ralph-dsa/loop.sh 01-arrays-hashing 15
#
# Runs once.sh until COMPLETE promise or max iterations.

CATEGORY="${1:?Usage: $0 <category-slug> [max_iterations] [--model <slug>]}"
shift

MAX=15
MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model|-m) MODEL="$2"; shift 2 ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then MAX="$1"; shift
      else echo "Unknown: $1" >&2; exit 1; fi
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TASK_COUNT="$(python3 -c "
import sys
sys.path.insert(0, '${SCRIPT_DIR}/scripts')
from category_data import get_category
cat = get_category('${CATEGORY}')
print(len(cat.problems) + 2)
")"

if [[ "$MAX" -lt "$TASK_COUNT" ]]; then
  echo "Note: category has ~$TASK_COUNT tasks; max iterations ($MAX) may be too low." >&2
fi

echo "Starting Ralph DSA loop for $CATEGORY (max $MAX iterations)"

for ((i = 1; i <= MAX; i++)); do
  echo ""
  echo "========== Loop $i / $MAX =========="
  set +e
  if [[ -n "$MODEL" ]]; then
    bash "$SCRIPT_DIR/once.sh" "$CATEGORY" --model "$MODEL" 1
  else
    bash "$SCRIPT_DIR/once.sh" "$CATEGORY" 1
  fi
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "Loop complete (COMPLETE promise received)."
    echo ""
    echo "Next category: run ./ralph-dsa/scaffold.sh <next-slug> then loop again."
    exit 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "Timeout — stopping loop."
    exit 124
  fi
done

echo "Reached max iterations ($MAX). Check dsa/plan.md and dsa/progress.txt."
bash "$SCRIPT_DIR/validate.sh" "$CATEGORY" || true
exit 2
