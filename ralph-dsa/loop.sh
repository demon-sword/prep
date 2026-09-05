#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-dsa/loop.sh <category-slug> [max_iterations] [--agent cursor|claude] [--model <slug>]
# Example: ./ralph-dsa/loop.sh 01-arrays-hashing 15 --agent claude
#
# Runs once.sh until COMPLETE promise or max iterations.

CATEGORY="${1:?Usage: $0 <category-slug> [max_iterations] [--agent cursor|claude] [--model <slug>]}"
shift

MAX=15
MODEL=""
AGENT_BACKEND="${RALPH_AGENT:-claude}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent|-a) AGENT_BACKEND="$2"; shift 2 ;;
    --model|-m) MODEL="$2"; shift 2 ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then MAX="$1"; shift
      else echo "Unknown: $1" >&2; exit 1; fi
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../ralph-common.sh
. "$PREP_ROOT/ralph-common.sh"

# Dirs whose new files count as progress for the stall guard.
LOOP_WATCH=("$PREP_ROOT/dsa/problems" "$PREP_ROOT/dsa/patterns")
# One id for this whole run. The rejection budget in once.sh is keyed by it, so
# a 3-strike cap survives the fact that loop.sh starts a fresh once.sh process
# every iteration — without this the cap could never reach 2.
export RALPH_RUN_ID="loop-$$-$(date +%s)"
ralph_rejects_clear "$SCRIPT_DIR/.state" "${CATEGORY}"
STALLS=0

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

echo "Starting Ralph DSA loop for $CATEGORY (max $MAX iterations, agent: $AGENT_BACKEND)"

for ((i = 1; i <= MAX; i++)); do
  echo ""
  echo "========== Loop $i / $MAX =========="
  ITER_MARKER="$(mktemp)"
  set +e
  ONCE_ARGS=("$CATEGORY" --agent "$AGENT_BACKEND")
  [[ -n "$MODEL" ]] && ONCE_ARGS+=(--model "$MODEL")
  ONCE_ARGS+=(1)
  bash "$SCRIPT_DIR/once.sh" "${ONCE_ARGS[@]}"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    # Completeness backstop. once.sh's COMPLETE promise is only as good as the
    # per-file validator behind it, and that validator SKIPs what was never
    # generated and returns 0 — so a run that produced nothing arrives here
    # looking identical to one that produced everything.
    CRC=0
    ralph_require_complete "$PREP_ROOT/dsa/plan.md" "$PREP_ROOT/dsa/problems" md "$PREP_ROOT/dsa/patterns" || CRC=$?
    if [[ "$CRC" -ne 0 ]]; then
      echo "The loop reports it finished, but the corpus is empty or incomplete." >&2
      exit 1
    fi
    echo "Loop complete (COMPLETE promise received)."
    echo ""
    echo "Next category: run ./ralph-dsa/scaffold.sh <next-slug> then loop again."
    exit 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "Timeout — stopping loop."
    exit 124
  fi

  if [[ "$rc" -eq 3 ]]; then
    echo "Could not reach a validated state — stopping loop." >&2
    exit 3
  fi

  if [[ "$rc" -ne 2 ]]; then
    # Anything that is not "iterations done, not complete" is a failure. rc=1
    # used to match no branch at all and fall through to the next iteration, and
    # with nothing sleeping the loop re-invoked the agent immediately — measured
    # at 80 real agent invocations in 8.95 seconds against an agent that exits
    # at once.
    echo "once.sh exited $rc — stopping loop rather than re-invoking the agent." >&2
    rm -f "$ITER_MARKER"
    exit "$rc"
  fi

  # Progress guard. An iteration that reports "not complete" but wrote nothing
  # is what a broken agent looks like, and the exit code alone cannot tell it
  # apart from real work.
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

echo "Reached max iterations ($MAX). Check dsa/plan.md and dsa/progress.txt."
set +e
bash "$SCRIPT_DIR/validate.sh" "$CATEGORY"
VRC=$?
set -e
[[ "$VRC" -ne 0 ]] && exit 1
exit 2
