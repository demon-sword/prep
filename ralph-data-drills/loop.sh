#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-data-drills/loop.sh <group-slug> [max_iterations] [--agent cursor|claude] [--model <slug>]
# Example: ./ralph-data-drills/loop.sh sql-01-window-functions 12 --agent claude
#
# Runs once.sh until a verified COMPLETE promise or max iterations.

GROUP="${1:?Usage: $0 <group-slug> [max_iterations] [--agent cursor|claude] [--model <slug>]}"
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
# RALPH_DD_OUT / RALPH_DD_PROBLEMS are honoured here as well as in
# validate.sh. They were read only by the validator, so setting one pointed
# it at a directory the generator never wrote to.
DRILLS="${RALPH_DD_OUT:-$PREP_ROOT/data-drills}"
PROBLEMS="${RALPH_DD_PROBLEMS:-$SCRIPT_DIR/problems.json}"

# shellcheck source=../ralph-common.sh
. "$PREP_ROOT/ralph-common.sh"

# Dirs whose new files count as progress for the stall guard.
LOOP_WATCH=("$DRILLS/sql" "$DRILLS/stats")
# One id for this whole run. The rejection budget in once.sh is keyed by it, so
# a 3-strike cap survives the fact that loop.sh starts a fresh once.sh process
# every iteration — without this the cap could never reach 2.
export RALPH_RUN_ID="loop-$$-$(date +%s)"
ralph_rejects_clear "$SCRIPT_DIR/.state" "${GROUP}"
STALLS=0

[[ -f "$PROBLEMS" ]] || { echo "Missing $PROBLEMS" >&2; exit 1; }

# One task per problem, plus the final validate task.
TASK_COUNT="$(python3 - "$PROBLEMS" "$GROUP" <<'PY'
import json, sys
from pathlib import Path
problems = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
n = sum(1 for p in problems if p.get("group") == sys.argv[2])
if n == 0:
    sys.exit(f"Unknown group: {sys.argv[2]}")
print(n + 1)
PY
)"

if [[ "$MAX" -lt "$TASK_COUNT" ]]; then
  echo "Note: group has ~$TASK_COUNT tasks; max iterations ($MAX) may be too low." >&2
fi

echo "Starting Ralph Data Drills loop for $GROUP (max $MAX iterations, agent: $AGENT_BACKEND)"

for ((i = 1; i <= MAX; i++)); do
  echo ""
  echo "========== Loop $i / $MAX =========="
  ITER_MARKER="$(mktemp)"
  set +e
  ONCE_ARGS=("$GROUP" --agent "$AGENT_BACKEND")
  [[ -n "$MODEL" ]] && ONCE_ARGS+=(--model "$MODEL")
  ONCE_ARGS+=(1)
  bash "$SCRIPT_DIR/once.sh" "${ONCE_ARGS[@]}"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    # Completeness backstop, GROUP-SCOPED. `validate.sh <group>` reports
    # `0 OK, 6 SKIP, 0 FAIL` and returns 0 on a group where nothing was
    # generated, so without this the loop exits clean having produced nothing.
    # The generic ralph_require_complete cannot serve here: drills are queued as
    # file paths, not `<id>.<ext>`, so its id branch matches nothing and its
    # non-empty fallback would pass on a drill from another group.
    CRC=0
    ralph_require_group_complete "$PROBLEMS" "$GROUP" "$DRILLS" || CRC=$?
    if [[ "$CRC" -ne 0 ]]; then
      echo "The loop reports $GROUP finished, but the group is empty or incomplete." >&2
      exit 1
    fi
    echo "Loop complete (COMPLETE promise verified)."
    echo ""
    echo "Next group: run ./ralph-data-drills/scaffold.sh <next-slug> then loop again."
    exit 0
  fi

  if [[ "$rc" -eq 124 ]]; then
    echo "Timeout — stopping loop."
    exit 124
  fi

  if [[ "$rc" -eq 4 ]]; then
    echo "Environment cannot validate drills — stopping loop." >&2
    rm -f "$ITER_MARKER"
    exit 4
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

echo "Reached max iterations ($MAX). Check data-drills/plan.md and data-drills/progress.txt."
# Binding: whatever state the loop ran out of iterations in, the validator has
# the last word. Captured via `|| VRC=$?` — errexit-safe, and never `|| true`.
VRC=0
ralph_validate bash "$SCRIPT_DIR/validate.sh" "$GROUP" || VRC=$?
if [[ "$VRC" -eq 2 ]]; then
  echo "Environment cannot validate drills — see above." >&2
  exit 4
fi
# Same backstop behind the final gate: the validator returning 0 over six SKIPs
# is not evidence that the group was produced.
FCRC=0
ralph_require_group_complete "$PROBLEMS" "$GROUP" "$DRILLS" || FCRC=$?
if [[ "$FCRC" -ne 0 ]]; then
  echo "Ran out of iterations with $GROUP incomplete." >&2
  exit 1
fi
if [[ "$VRC" -ne 0 ]]; then
  echo "Validation still failing for $GROUP:" >&2
  [[ -n "$RALPH_FAIL_LINES" ]] && printf '%s\n' "$RALPH_FAIL_LINES" >&2
  exit 1
fi
exit 2
