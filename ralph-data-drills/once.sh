#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-data-drills/once.sh <group-slug> [--agent cursor|claude] [--model <slug>] [iterations]
#
# Runs one data-drills plan item (one SQL or stats drill) via Cursor Agent or
# Claude Code.
#   --agent claude  (default) — uses Claude Code's `claude -p` CLI
#   --agent cursor            — uses Cursor's headless `agent` CLI
#
# The unit of work is a GROUP (one of the 12 slugs in problems.json), the way a
# category is the unit of work in ralph-dsa.

GROUP="${1:?Usage: $0 <group-slug> [--agent cursor|claude] [--model <slug>] [iterations]  e.g. sql-01-window-functions}"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$WORKSPACE"

MODEL="${CURSOR_MODEL:-}"
ITERATIONS=1
AGENT_BACKEND="${RALPH_AGENT:-claude}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent|-a)
      [[ $# -ge 2 ]] || { echo "--agent requires cursor|claude" >&2; exit 1; }
      AGENT_BACKEND="$2"; shift 2
      ;;
    --model|-m)
      [[ $# -ge 2 ]] || { echo "--model requires a value" >&2; exit 1; }
      MODEL="$2"; shift 2
      ;;
    --help|-h)
      sed -n '1,17p' "$0" >&2; exit 0
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        ITERATIONS="$1"; shift
      else
        echo "Unknown argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

case "$AGENT_BACKEND" in
  cursor|claude) ;;
  *) echo "Unknown --agent value: $AGENT_BACKEND (expected cursor or claude)" >&2; exit 1 ;;
esac

# RALPH_DD_OUT / RALPH_DD_PROBLEMS are honoured here as well as in
# validate.sh. They were read only by the validator, so setting one pointed
# it at a directory the generator never wrote to.
DRILLS="${RALPH_DD_OUT:-$WORKSPACE/data-drills}"
PLAN="$DRILLS/plan.md"
PROGRESS="$DRILLS/progress.txt"
README="$DRILLS/README.md"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
SPEC="$SCRIPT_DIR/spec.md"
PROBLEMS="${RALPH_DD_PROBLEMS:-$SCRIPT_DIR/problems.json}"

[[ -f "$PLAN" ]] || { echo "Missing $PLAN — run ./ralph-data-drills/scaffold.sh $GROUP first" >&2; exit 1; }
[[ -f "$PROBLEMS" ]] || { echo "Missing $PROBLEMS" >&2; exit 1; }
[[ -f "$SPEC" ]] || { echo "Missing $SPEC" >&2; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { echo "Missing $PROMPT_FILE" >&2; exit 1; }

# The plan's Meta block is written by scaffold.sh and is the single source of
# truth for which group is active (ralph-dsa gets this from category_data.py;
# we have no such module, so the plan carries it).
PLAN_GROUP="$(sed -n 's/^current_group:[[:space:]]*//p' "$PLAN" | head -1)"
FAMILY="$(sed -n 's/^family:[[:space:]]*//p' "$PLAN" | head -1)"
GROUP_NAME="$(sed -n 's/^group_name:[[:space:]]*//p' "$PLAN" | head -1)"

if [[ "$PLAN_GROUP" != "$GROUP" ]]; then
  echo "Plan is scaffolded for '$PLAN_GROUP' but you asked for '$GROUP'." >&2
  echo "Run: bash ralph-data-drills/scaffold.sh $GROUP" >&2
  exit 1
fi

case "$FAMILY" in
  sql|stats) ;;
  *) echo "Unknown family '$FAMILY' in $PLAN Meta (expected sql or stats)" >&2; exit 1 ;;
esac

TEMPLATE="$DRILLS/$FAMILY/_template.md"

# The group's problem list, straight out of problems.json — metadata only, so
# the agent still has to derive every schema, query, answer and solution.
PROBLEM_LIST="$(python3 - "$PROBLEMS" "$GROUP" <<'PY'
import json, sys
from pathlib import Path

problems = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
group = [p for p in problems if p.get("group") == sys.argv[2]]
if not group:
    sys.exit(f"No problems in problems.json for group {sys.argv[2]}")
group.sort(key=lambda p: p.get("id", ""))
for p in group:
    print(f"{p['id']}  {p['title']}  [{p.get('difficulty','?')}]  -> {p['file']}")
    print(f"    topics: {', '.join(p.get('topics', []))}")
    print(f"    focus: {p.get('focus','')}")
    dialect = p.get("dialect")
    if dialect:
        print(f"    dialect: {dialect}  (skip_exec_reason: {p.get('skip_exec_reason','MISSING')})")
    if p.get("mc"):
        print(f"    monte carlo: required, tolerance {p.get('mc_tolerance')} ({p.get('mc_tolerance_kind')})")
    elif p.get("family") == "stats":
        print("    monte carlo: not required")
PY
)"

mkdir -p "$SCRIPT_DIR/.logs"
LOG_DIR="$SCRIPT_DIR/.logs"

# shellcheck source=../ralph-common.sh
. "$WORKSPACE/ralph-common.sh"

# Correction text appended to the next iteration's prompt after a rejection.
FEEDBACK=""
# Rejection budget. It lives on disk, not in this variable, because loop.sh
# runs this script once per iteration: a counter initialised here resets every
# iteration and the cap never binds. See ralph_rejects_bump in ralph-common.sh.
REJECT_STATE_DIR="$SCRIPT_DIR/.state"
CORPUS_TRACK="data-drills"
REJECTS=0

PROMPT_BODY="$(sed -e "s/{{GROUP}}/$GROUP/g" -e "s/{{GROUP_NAME}}/$GROUP_NAME/g" "$PROMPT_FILE")"

TASK_INSTRUCTIONS="Group: $GROUP ($GROUP_NAME). Family: $FAMILY. Workspace: data-drills/
${PROMPT_BODY}

Problems in this group (metadata only — derive everything else yourself):
${PROBLEM_LIST}

Follow ralph-data-drills/prompt.md. Complete exactly ONE unchecked item in data-drills/plan.md Next section.
Every fenced block id required by ralph-data-drills/spec.md must be present and must actually run:
\`bash ralph-data-drills/validate.sh $GROUP\` is the judge, not your own reading of the file.
End with normal assistant text; emit <promise>COMPLETE</promise> only when ALL plan items are done and validate passes."

# Subject handed to the adversarial fact-checker — it sees the file and this
# line only, so it has to say what the file is meant to be.
if [[ "$FAMILY" == "sql" ]]; then
  FACT_SUBJECT="a SQL interview drill with an executable schema, a reference solution query, its expected result set, and a deliberately wrong query"
else
  FACT_SUBJECT="a probability/statistics interview drill with a worked solution, a single numeric answer, and a Monte Carlo check"
fi

# This governs BOTH backends, so it has a backend-neutral name. The old
# CURSOR_-prefixed spelling still works — it reads as cursor-only and cost
# a real debugging session when a claude-backend timeout probe silently
# used the 2700s default instead.
AGENT_TIMEOUT_SEC="${RALPH_AGENT_TIMEOUT_SEC:-${CURSOR_AGENT_TIMEOUT_SEC:-2700}}"

# ── Cursor backend ────────────────────────────────────────────────────────────
build_cursor_cmd() {
  local output_fmt="${CURSOR_AGENT_OUTPUT_FORMAT:-stream-json}"
  # prompt.md is deliberately NOT @-referenced: TASK_INSTRUCTIONS already carries
  # it with {{GROUP}}/{{GROUP_NAME}} substituted, and handing the agent the raw
  # copy as well would put literal {{GROUP}} placeholders back in the context.
  local prompt="@${SPEC} @${README} @${TEMPLATE} @${PLAN} @${PROGRESS} ${TASK_INSTRUCTIONS}${FEEDBACK}"
  local -a flags=(--print --trust --force --approve-mcps --workspace "$WORKSPACE" --output-format "$output_fmt")
  if [[ "$output_fmt" == "stream-json" ]] && [[ "${CURSOR_AGENT_STREAM:-1}" == "1" ]]; then
    flags+=(--stream-partial-output)
  fi
  [[ -n "$MODEL" ]] && flags+=(--model "$MODEL")
  BUILT_CMD=(agent "${flags[@]}" "$prompt")
}

# ── Claude Code backend ───────────────────────────────────────────────────────
build_claude_cmd() {
  local context
  # Same reason as build_cursor_cmd: the substituted prompt body is in
  # TASK_INSTRUCTIONS, so the raw prompt.md is left out of the context.
  context="$(cat "$SPEC" "$README" "$TEMPLATE" "$PLAN" "$PROGRESS" 2>/dev/null || true)"
  BUILT_PROMPT="${context}

${TASK_INSTRUCTIONS}${FEEDBACK}"
  local -a flags=(-p --dangerously-skip-permissions --output-format stream-json --verbose)
  [[ -n "$MODEL" ]] && flags+=(--model "$MODEL")
  BUILT_CMD=(claude "${flags[@]}")
}

# Set by run_agent_with_timeout's watchdog; see the note at the call site.
TIMEOUT_MARKER=""

run_agent_with_timeout() {
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    # Pass prompt as positional arg — `timeout` breaks claude and yields empty output.
    "${BUILT_CMD[@]}" "$BUILT_PROMPT" &
    local agent_pid=$!
    # The watchdog leaves a marker when it actually fires. A SIGINT-killed
    # claude exits 130, not 124, so the exit code alone cannot tell a timeout
    # apart from an ordinary failure — without the marker a timed-out run gets
    # misreported as "not complete" (exit 2).
    (sleep "$AGENT_TIMEOUT_SEC"; : > "$TIMEOUT_MARKER"; ralph_kill_tree "$agent_pid" TERM; sleep 30; ralph_kill_tree "$agent_pid" KILL) &
    local watchdog_pid=$!
    wait "$agent_pid"
    local rc=$?
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    return $rc
  else
    local -a timed_cmd
    if command -v timeout >/dev/null 2>&1; then
      timed_cmd=(timeout --signal=INT --kill-after=60 "$AGENT_TIMEOUT_SEC")
    elif command -v gtimeout >/dev/null 2>&1; then
      timed_cmd=(gtimeout --signal=INT --kill-after=60 "$AGENT_TIMEOUT_SEC")
    else
      timed_cmd=(perl -e 'alarm shift @ARGV if shift; exec @ARGV' "$AGENT_TIMEOUT_SEC")
    fi
    "${timed_cmd[@]}" "${BUILT_CMD[@]}"
  fi
}

has_completion_promise() {
  local text="$1"
  [[ "$text" == *"<promise>COMPLETE</promise>"* ]]
}

for ((i = 1; i <= ITERATIONS; i++)); do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Ralph Data Drills $GROUP — iteration $i / $ITERATIONS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  LOG_FILE="$LOG_DIR/${GROUP}-iter-${i}-$(date +%Y%m%d-%H%M%S).log"
  echo "Log: $LOG_FILE" >&2
  echo "Timeout: ${AGENT_TIMEOUT_SEC}s" >&2
  echo "Agent: $AGENT_BACKEND" >&2
  [[ -n "$MODEL" ]] && echo "Model: $MODEL" >&2

  ITER_MARKER="$(mktemp)"
  TIMEOUT_MARKER="${LOG_FILE}.timeout"
  rm -f "$TIMEOUT_MARKER"

  BUILT_CMD=(); BUILT_PROMPT=""
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    build_claude_cmd
  else
    build_cursor_cmd
  fi

  set +e
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    run_agent_with_timeout > "$LOG_FILE" 2>&1
    agent_exit=$?
    cat "$LOG_FILE"
  elif [[ -t 1 ]]; then
    run_agent_with_timeout 2>&1 | tee "$LOG_FILE" /dev/tty
    agent_exit=${PIPESTATUS[0]}
  else
    run_agent_with_timeout 2>&1 | tee "$LOG_FILE"
    agent_exit=${PIPESTATUS[0]}
  fi
  set -e

  ralph_agent_record "$LOG_FILE" "$agent_exit" "${#BUILT_PROMPT}" "${BUILT_CMD[*]}" || true

  if ralph_agent_timed_out "$TIMEOUT_MARKER" "$agent_exit"; then
    echo "Agent killed after ${AGENT_TIMEOUT_SEC}s" >&2
    rm -f "$ITER_MARKER" "$TIMEOUT_MARKER"
    exit 124
  fi
  rm -f "$TIMEOUT_MARKER"

  promise_text="$(ralph_stream_json_result "$LOG_FILE")"

  # Adversarial fact-check of whatever drill this iteration actually wrote.
  PRODUCED="$(ralph_newest_since "$ITER_MARKER" "$DRILLS/sql" "$DRILLS/stats")"
  rm -f "$ITER_MARKER"
  FACT_NOTES=""
  if [[ -n "$PRODUCED" ]]; then
    # Capture the status in an `||` list — the calling convention documented in
    # ralph-common.sh, and errexit-safe without touching the shell's options.
    # This is NOT `|| true`: the code is kept and acted on below.
    FACT_RC=0
    ralph_factcheck "$PRODUCED" "$FACT_SUBJECT" "$MODEL" || FACT_RC=$?
    [[ "$FACT_RC" -ne 0 ]] && FACT_NOTES="$RALPH_FACTCHECK_NOTES"
    # Harness-written evidence that the adversarial pass ran, and with what
    # verdict — SKIPPED included, so a skipped run is visible as such.
    printf '%s | %s | gate | factcheck=%s\n' "$(date +%Y-%m-%d)" \
      "$(basename "$PRODUCED")" "${RALPH_FACTCHECK_VERDICT:-NOT-RUN}" \
      >> "$PROGRESS" 2>/dev/null || true
  fi

  # FACT_RC=2 means the fact-check HARNESS failed — no verdict was produced at
  # all. Regenerating cannot fix that, and three more generations at ~$4 and
  # ~9 minutes each buys nothing. Fail fast, like the environment cases.
  if [[ "$FACT_RC" -eq 2 ]]; then
    echo "" >&2
    echo "Fact-check could not run — infrastructure failure, not a content failure." >&2
    printf '%s\n' "$FACT_NOTES" >&2
    echo "Fix it and re-run. Not spending the retry budget on it." >&2
    exit 4
  fi

  if has_completion_promise "$promise_text"; then
    echo "COMPLETE promise received — verifying before accepting it."
    # Same errexit caveat as the fact-check above. The exit code is binding —
    # a non-zero validate can never be swallowed into a success here.
    VALIDATE_RC=0
    ralph_validate bash "$SCRIPT_DIR/validate.sh" "$GROUP" || VALIDATE_RC=$?

    # validate.sh exit 2 = the sandbox launcher is missing. Its own header calls
    # that an environment fault "not something the agent can fix by
    # regenerating" — so it must not be charged to the rejection budget, which
    # would spend RALPH_MAX_ATTEMPTS full agent cycles on an unfixable
    # condition and then blame the content. Reported as 4, like ml-coding.
    if [[ "$VALIDATE_RC" -eq 2 ]]; then
      echo "" >&2
      echo "Cannot validate drills — see the message above. Fix the environment, then re-run." >&2
      exit 4
    fi
    VALIDATE_FAILS="$RALPH_FAIL_LINES"

    # An empty corpus is invisible to a per-file validator — it checks the files
    # that exist, so on zero files it reports a clean pass. COMPLETE has to
    # answer the other question: did this run actually produce anything?
    CORPUS_RC=0
    ralph_require_group_complete "$PROBLEMS" "$GROUP" "$DRILLS" || CORPUS_RC=$?
    RALPH_FAIL_LINES="${VALIDATE_FAILS}${RALPH_FAIL_LINES}"

    # The corpus-level gate: cross-file redundancy, plus a non-empty check.
    # Three specs called it binding under "Enforcement" while no script anywhere
    # actually invoked it. It does now.
    DEDUP_RC=0
    ralph_validate bash "$WORKSPACE/validate-corpus.sh" --final "$CORPUS_TRACK" || DEDUP_RC=$?
    RALPH_FAIL_LINES="${VALIDATE_FAILS}${RALPH_FAIL_LINES}"

    if [[ "$VALIDATE_RC" -eq 0 && "$CORPUS_RC" -eq 0 && "$DEDUP_RC" -eq 0 && -z "$FACT_NOTES" ]]; then
      ralph_rejects_clear "$REJECT_STATE_DIR" "${GROUP}"
      echo "Stopping: COMPLETE promise verified."
      exit 0
    fi

    REJECTS="$(ralph_rejects_bump "$REJECT_STATE_DIR" "${GROUP}")"
    echo "COMPLETE rejected ($REJECTS/$RALPH_MAX_ATTEMPTS) — validation or fact-check failed." >&2
    if [[ "$REJECTS" -ge "$RALPH_MAX_ATTEMPTS" ]]; then
      echo "" >&2
      echo "ERROR: $GROUP claimed COMPLETE $REJECTS times without passing." >&2
      echo "Giving up rather than accepting unverified drills. Last failures:" >&2
      [[ -n "$RALPH_FAIL_LINES" ]] && printf '%s\n' "$RALPH_FAIL_LINES" >&2
      [[ -n "$FACT_NOTES" ]] && printf '%s\n' "$FACT_NOTES" >&2
      exit 3
    fi
    FEEDBACK="
$(ralph_feedback "$REJECTS" "$RALPH_MAX_ATTEMPTS" "$RALPH_FAIL_LINES" "$FACT_NOTES")"
    continue
  fi

  if [[ -n "$FACT_NOTES" ]]; then
    FEEDBACK="
$(ralph_feedback "$((REJECTS + 1))" "$RALPH_MAX_ATTEMPTS" "" "$FACT_NOTES")
The file with the incorrect claims is: $PRODUCED
Fix it before starting any new plan item."
  else
    FEEDBACK=""
  fi
done

echo "Finished $ITERATIONS iteration(s) for $GROUP (not complete — continue loop)."
exit 2
