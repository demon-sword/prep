#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-concepts/loop.sh [concept-id] [max_iterations] [--model <slug>]
#
# concept-id (optional): run loop on a single concept id (regenerates it each iteration
#                        until it passes validation). Useful for retrying a failed concept.
#                        Omit to run sequentially through all remaining concepts.
#
# Examples:
#   ./ralph-concepts/loop.sh                        # run all remaining (default max=50)
#   ./ralph-concepts/loop.sh 40                     # run all remaining, max 40 iterations
#   ./ralph-concepts/loop.sh 06-qkv-attention       # retry one specific concept
#   ./ralph-concepts/loop.sh 16-lora --model claude-sonnet-4

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MAX=50
MODEL=""
TARGET_CONCEPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model|-m) MODEL="$2"; shift 2 ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then MAX="$1"; shift
      elif [[ "$1" =~ ^[0-9]{2}- ]]; then TARGET_CONCEPT="$1"; shift  # looks like a concept id
      else echo "Unknown argument: $1" >&2; exit 1; fi
      ;;
  esac
done

if [[ -n "$TARGET_CONCEPT" ]]; then
  echo "Starting Ralph Concepts loop — concept: $TARGET_CONCEPT (max $MAX retries)"
else
  echo "Starting Ralph Concepts loop — all remaining (max $MAX iterations)"
fi
echo "Concepts dir: $SCRIPT_DIR/../ai-engineering/concepts/"
echo ""

for ((i = 1; i <= MAX; i++)); do
  echo ""
  echo "========== Iteration $i / $MAX =========="

  ONCE_ARGS=()
  [[ -n "$TARGET_CONCEPT" ]] && ONCE_ARGS+=("$TARGET_CONCEPT")
  [[ -n "$MODEL" ]] && ONCE_ARGS+=(--model "$MODEL")

  set +e
  bash "$SCRIPT_DIR/once.sh" ${ONCE_ARGS[@]+"${ONCE_ARGS[@]}"}
  RC=$?
  set -e

  if [[ "$RC" -eq 0 ]]; then
    echo ""
    if [[ -n "$TARGET_CONCEPT" ]]; then
      echo "Done — $TARGET_CONCEPT generated and validated."
      bash "$SCRIPT_DIR/validate.sh" "$TARGET_CONCEPT" || true
    else
      echo "Loop complete — all concepts generated!"
      bash "$SCRIPT_DIR/validate.sh" || true
    fi
    exit 0
  fi

  if [[ "$RC" -eq 124 ]]; then
    echo "Timeout — stopping loop."
    exit 124
  fi

  # RC=2 means "one item done, more remain" — continue
done

echo ""
echo "Reached max iterations ($MAX). Check ralph-concepts/plan.md."
bash "$SCRIPT_DIR/validate.sh" || true
exit 2
