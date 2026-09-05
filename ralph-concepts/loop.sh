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
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAN="$SCRIPT_DIR/plan.md"
OUTPUT_DIR="$PREP_ROOT/ai-engineering/concepts"
OUTPUT_EXT="html"

# shellcheck source=../ralph-common.sh
. "$PREP_ROOT/ralph-common.sh"

# Dirs whose new files count as progress for the stall guard.
LOOP_WATCH=("$OUTPUT_DIR")
# One id for this whole run, so counters that must survive across the separate
# once.sh processes can tell "this run" from a previous one.
export RALPH_RUN_ID="loop-$$-$(date +%s)"
STALLS=0

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

  ITER_MARKER="$(mktemp)"
  set +e
  bash "$SCRIPT_DIR/once.sh" ${ONCE_ARGS[@]+"${ONCE_ARGS[@]}"}
  RC=$?
  set -e

  if [[ "$RC" -eq 0 ]]; then
    echo ""
    # once.sh already gated on validation; re-run as the final word and honour it.
    set +e
    if [[ -n "$TARGET_CONCEPT" ]]; then
      bash "$SCRIPT_DIR/validate.sh" "$TARGET_CONCEPT"
    else
      bash "$SCRIPT_DIR/validate.sh"
    fi
    VRC=$?
    set -e
    if [[ "$VRC" -ne 0 ]]; then
      echo "Validation FAILED on the final check — not reporting success." >&2
      exit 1
    fi
    if [[ -z "$TARGET_CONCEPT" ]]; then
      # Reporting success over a corpus that was never generated is the failure
      # mode a per-file validator cannot see — it passes on zero files.
      CRC=0
      ralph_require_complete "$PLAN" "$OUTPUT_DIR" "$OUTPUT_EXT" || CRC=$?
      if [[ "$CRC" -ne 0 ]]; then
        echo "The loop reports it finished, but the corpus is empty or incomplete." >&2
        exit 1
      fi
      # The corpus gate is the last word, here as well as in once.sh — this is
      # the path a re-run over an already-finished track takes.
      DRC=0
      ralph_validate bash "$PREP_ROOT/validate-corpus.sh" --final "concepts" || DRC=$?
      if [[ "$DRC" -ne 0 ]]; then
        echo "Corpus-level validation FAILED on the final check." >&2
        exit 1
      fi
    fi
    if [[ -n "$TARGET_CONCEPT" ]]; then
      echo "Done — $TARGET_CONCEPT generated and validated."
    else
      echo "Loop complete — all concepts generated and validated!"
    fi
    exit 0
  fi

  if [[ "$RC" -eq 124 ]]; then
    echo "Timeout — stopping loop."
    exit 124
  fi

  if [[ "$RC" -eq 3 ]]; then
    echo "Item could not be made to pass validation — stopping loop." >&2
    exit 3
  fi

  if [[ "$RC" -ne 2 ]]; then
    # Anything that is not "one item done, more remain" is a failure. RC=1 used
    # to match no branch at all and fall through to the next iteration, and with
    # nothing sleeping the loop re-invoked the agent immediately — measured at 80
    # real agent invocations in 8.95 seconds against an agent that exits at once.
    echo "once.sh exited $RC — stopping loop rather than re-invoking the agent." >&2
    rm -f "$ITER_MARKER"
    exit "$RC"
  fi

  # Progress guard. An iteration that says "more remain" but wrote nothing is
  # what a broken agent looks like, and the exit code alone cannot tell it apart
  # from real work.
  if [[ -z "$(ralph_newest_since "$ITER_MARKER" ${LOOP_WATCH[@]+"${LOOP_WATCH[@]}"})" ]]; then
    STALLS=$((STALLS + 1))
    echo "  no new content this iteration ($STALLS/$RALPH_MAX_STALLS)" >&2
    if [[ "$STALLS" -ge "$RALPH_MAX_STALLS" ]]; then
      echo "Stopping: $STALLS consecutive iterations produced nothing." >&2
      rm -f "$ITER_MARKER"
      exit 5
    fi
  else
    STALLS=0
  fi
  rm -f "$ITER_MARKER"

  ralph_loop_pause "$i" "$MAX"
done

echo ""
echo "Reached max iterations ($MAX). Check ralph-concepts/plan.md."
set +e
bash "$SCRIPT_DIR/validate.sh"
VRC=$?
set -e
[[ "$VRC" -ne 0 ]] && exit 1
exit 2
