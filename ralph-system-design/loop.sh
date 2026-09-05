#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-system-design/loop.sh <topic> [max_iterations] [--agent cursor|claude] [--model <slug>]
# Runs once.sh until COMPLETE promise or max iterations.

TOPIC="${1:?Usage: $0 <topic> [max_iterations] [--agent cursor|claude] [--model <slug>]}"
shift

MAX=25
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
LOOP_WATCH=("$PREP_ROOT/system-design/$TOPIC")
# One id for this whole run. The rejection budget in once.sh is keyed by it, so
# a 3-strike cap survives the fact that loop.sh starts a fresh once.sh process
# every iteration — without this the cap could never reach 2.
export RALPH_RUN_ID="loop-$$-$(date +%s)"
ralph_rejects_clear "$SCRIPT_DIR/.state" "${TOPIC}"
STALLS=0

echo "Starting Ralph loop for $TOPIC (max $MAX iterations, agent: $AGENT_BACKEND)"

for ((i = 1; i <= MAX; i++)); do
  echo ""
  echo "========== Loop $i / $MAX =========="
  ITER_MARKER="$(mktemp)"
  set +e
  ONCE_ARGS=("$TOPIC" --agent "$AGENT_BACKEND")
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
    ralph_require_complete "$PREP_ROOT/system-design/$TOPIC/plan.md" "$PREP_ROOT/system-design/$TOPIC/answers" md "$PREP_ROOT/system-design/$TOPIC" || CRC=$?
    if [[ "$CRC" -ne 0 ]]; then
      echo "The loop reports it finished, but the corpus is empty or incomplete." >&2
      exit 1
    fi
    echo "Loop complete (COMPLETE promise received)."
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

echo "Reached max iterations ($MAX). Check plan.md and progress.txt."
set +e
bash "$SCRIPT_DIR/validate.sh" "$TOPIC"
VRC=$?
set -e
[[ "$VRC" -ne 0 ]] && exit 1
# Explicit: without this the script falls off the end and bash returns the status
# of the `[[ ]]` test — which is 1 exactly when validation PASSED. Every sibling
# loop.sh ends this block with `exit 2` ("budget exhausted, not complete").
exit 2
