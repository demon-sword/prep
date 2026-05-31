#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-system-design/loop.sh <topic> [max_iterations] [--model <slug>]
# Runs once.sh until COMPLETE promise or max iterations.

TOPIC="${1:?Usage: $0 <topic> [max_iterations] [--model <slug>]}"
shift

MAX=25
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

echo "Starting Ralph loop for $TOPIC (max $MAX iterations)"

for ((i = 1; i <= MAX; i++)); do
  echo ""
  echo "========== Loop $i / $MAX =========="
  set +e
  if [[ -n "$MODEL" ]]; then
    bash "$SCRIPT_DIR/once.sh" "$TOPIC" --model "$MODEL" 1
  else
    bash "$SCRIPT_DIR/once.sh" "$TOPIC" 1
  fi
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "Loop complete (COMPLETE promise received)."
    exit 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "Timeout — stopping loop."
    exit 124
  fi
done

echo "Reached max iterations ($MAX). Check plan.md and progress.txt."
bash "$SCRIPT_DIR/validate.sh" "$TOPIC" || true
