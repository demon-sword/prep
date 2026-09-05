#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-ai-engineering/once.sh <category-slug> [--agent cursor|claude] [--model <slug>] [iterations]
#
# Runs one AI engineering category plan item via Cursor Agent or Claude Code.
#   --agent cursor  (default) — uses Cursor's headless `agent` CLI
#   --agent claude            — uses Claude Code's `claude -p` CLI

CATEGORY="${1:?Usage: $0 <category-slug> [--agent cursor|claude] [--model <slug>] [iterations]  e.g. 02-rag-systems}"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$WORKSPACE"

MODEL="${CURSOR_MODEL:-}"
ITERATIONS=1
AGENT_BACKEND="${RALPH_AGENT:-claude}"   # override via env or --agent flag

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
      sed -n '1,14p' "$0" >&2; exit 0
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

PLAN="$WORKSPACE/ai-engineering/plan.md"
PROGRESS="$WORKSPACE/ai-engineering/progress.txt"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
SPEC="$SCRIPT_DIR/spec.md"
README="$WORKSPACE/ai-engineering/README.md"
QUESTIONS="$WORKSPACE/ai-engineering/interview-questions.md"
CAT_TEMPLATE="$WORKSPACE/ai-engineering/categories/_template.md"
ANS_TEMPLATE="$WORKSPACE/ai-engineering/answers/_template.md"

[[ -f "$PLAN" ]] || { echo "Missing $PLAN — run ./ralph-ai-engineering/scaffold.sh $CATEGORY first" >&2; exit 1; }

CATEGORY_NAME="$(python3 -c "
import sys
sys.path.insert(0, '${SCRIPT_DIR}/scripts')
from question_data import get_category
print(get_category('${CATEGORY}').name)
")"

mkdir -p "$SCRIPT_DIR/.logs"
LOG_DIR="$SCRIPT_DIR/.logs"

# shellcheck source=../ralph-common.sh
. "$(cd "$SCRIPT_DIR/.." && pwd)/ralph-common.sh"

# Correction text appended to the next iteration's prompt after a rejection.
FEEDBACK=""
# Rejection budget. It lives on disk, not in this variable, because loop.sh
# runs this script once per iteration: a counter initialised here resets every
# iteration and the cap never binds. See ralph_rejects_bump in ralph-common.sh.
REJECT_STATE_DIR="$SCRIPT_DIR/.state"
CORPUS_TRACK="ai-engineering"
REJECTS=0

PROMPT_BODY="$(sed \
  -e "s/{{CATEGORY}}/$CATEGORY/g" \
  -e "s/{{CATEGORY_NAME}}/$CATEGORY_NAME/g" \
  "$PROMPT_FILE")"

TASK_INSTRUCTIONS="Category: $CATEGORY ($CATEGORY_NAME). Workspace: ai-engineering/
${PROMPT_BODY}
Follow ralph-ai-engineering/prompt.md. Complete exactly ONE unchecked item in ai-engineering/plan.md Next section.
End with normal assistant text; emit <promise>COMPLETE</promise> only when ALL plan items done and validate passes."

# This governs BOTH backends, so it has a backend-neutral name. The old
# CURSOR_-prefixed spelling still works — it reads as cursor-only and cost
# a real debugging session when a claude-backend timeout probe silently
# used the 2700s default instead.
AGENT_TIMEOUT_SEC="${RALPH_AGENT_TIMEOUT_SEC:-${CURSOR_AGENT_TIMEOUT_SEC:-2700}}"

# ── Cursor backend ────────────────────────────────────────────────────────────
build_cursor_cmd() {
  local output_fmt="${CURSOR_AGENT_OUTPUT_FORMAT:-stream-json}"
  local prompt="@${SPEC} @${README} @${QUESTIONS} @${CAT_TEMPLATE} @${ANS_TEMPLATE} @${PLAN} @${PROGRESS} @${PROMPT_FILE} ${TASK_INSTRUCTIONS}${FEEDBACK}"
  local -a flags=(--print --trust --force --approve-mcps --workspace "$WORKSPACE" --output-format "$output_fmt")
  if [[ "$output_fmt" == "stream-json" ]] && [[ "${CURSOR_AGENT_STREAM:-1}" == "1" ]]; then
    flags+=(--stream-partial-output)
  fi
  [[ -n "$MODEL" ]] && flags+=(--model "$MODEL")
  BUILT_CMD=(agent "${flags[@]}" "$prompt")
}

# ── Claude Code backend ───────────────────────────────────────────────────────
build_claude_cmd() {
  # Inline all context files into the prompt and pass as a positional argument.
  # Positional arg is required — `timeout` breaks claude's stdin pipe.
  local context
  context="$(cat "$SPEC" "$README" "$QUESTIONS" "$CAT_TEMPLATE" "$ANS_TEMPLATE" "$PLAN" "$PROGRESS" "$PROMPT_FILE" 2>/dev/null || true)"
  BUILT_PROMPT="${context}

${TASK_INSTRUCTIONS}${FEEDBACK}"
  local -a flags=(-p --dangerously-skip-permissions --output-format stream-json --verbose)
  [[ -n "$MODEL" ]] && flags+=(--model "$MODEL")
  BUILT_CMD=(claude "${flags[@]}")
}

run_agent_with_timeout() {
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    # Run claude in background with prompt as positional arg, then enforce timeout via wait.
    # Cannot use the `timeout` command — it breaks claude's process setup and yields empty output.
    "${BUILT_CMD[@]}" "$BUILT_PROMPT" &
    local agent_pid=$!
    # Marker first, then SIGTERM: a background job in a script IGNORES SIGINT
    # (job control is off), so INT alone never stopped anything and the eventual
    # SIGKILL reported 137 — see ralph_agent_timed_out.
    (sleep "$AGENT_TIMEOUT_SEC"; : > "$TIMEOUT_MARKER"; ralph_kill_tree "$agent_pid" TERM; sleep 30; ralph_kill_tree "$agent_pid" KILL) &
    local watchdog_pid=$!
    wait "$agent_pid"
    local rc=$?
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    return $rc
  else
    # Cursor: timeout command works fine
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

extract_stream_json_result() {
  local log_file="$1"
  python3 - "$log_file" <<'PY'
import json, sys
path = sys.argv[1]
final = ""
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "result":
            final = event.get("result") or ""
print(final, end="")
PY
}

has_completion_promise() {
  local text="$1"
  [[ "$text" == *"<promise>COMPLETE</promise>"* ]]
}

for ((i = 1; i <= ITERATIONS; i++)); do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Ralph AI Engineering $CATEGORY — iteration $i / $ITERATIONS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  LOG_FILE="$LOG_DIR/${CATEGORY}-iter-${i}-$(date +%Y%m%d-%H%M%S).log"
  echo "Log: $LOG_FILE" >&2
  echo "Timeout: ${AGENT_TIMEOUT_SEC}s" >&2
  echo "Agent: $AGENT_BACKEND" >&2
  [[ -n "$MODEL" ]] && echo "Model: $MODEL" >&2

  # Build the command for this backend
  ITER_MARKER="$(mktemp)"

  BUILT_CMD=(); BUILT_PROMPT=""
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    build_claude_cmd
  else
    build_cursor_cmd
  fi

  TIMEOUT_MARKER="${LOG_FILE}.timeout"
  rm -f "$TIMEOUT_MARKER"
  set +e
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    # For claude: redirect directly to log (no pipe) so the background job + wait
    # inside run_agent_with_timeout works correctly. Pipe would create a subshell
    # that can't wait for background jobs, causing an indefinite hang.
    run_agent_with_timeout > "$LOG_FILE" 2>&1
    agent_exit=$?
    # Stream log to terminal so user sees progress
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
    echo "Agent killed after ${AGENT_TIMEOUT_SEC}s (exit $agent_exit)" >&2
    rm -f "$TIMEOUT_MARKER"
    exit 124
  fi
  rm -f "$TIMEOUT_MARKER"

  # Both backends emit stream-json; extract the final result text
  promise_text="$(extract_stream_json_result "$LOG_FILE")"

  # Adversarial fact-check of whatever this iteration actually wrote.
  PRODUCED="$(ralph_newest_since "$ITER_MARKER" "$WORKSPACE/ai-engineering/answers" "$WORKSPACE/ai-engineering/categories")"
  rm -f "$ITER_MARKER"
  FACT_NOTES=""
  if [[ -n "$PRODUCED" ]]; then
    FACT_RC=0
    ralph_factcheck "$PRODUCED" "an AI-engineering interview answer note" "$MODEL" || FACT_RC=$?
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
    VALIDATE_RC=0
    ralph_validate bash "$SCRIPT_DIR/validate.sh" "$CATEGORY" || VALIDATE_RC=$?
    VALIDATE_FAILS="$RALPH_FAIL_LINES"

    # An empty corpus is invisible to a per-file validator — it checks the files
    # that exist, so on zero files it reports a clean pass. COMPLETE has to
    # answer the other question: did this run actually produce anything?
    CORPUS_RC=0
    ralph_require_complete "$PLAN" "$WORKSPACE/ai-engineering/answers" md "$WORKSPACE/ai-engineering/categories" || CORPUS_RC=$?
    RALPH_FAIL_LINES="${VALIDATE_FAILS}${RALPH_FAIL_LINES}"

    # The corpus-level gate: cross-file redundancy, plus a non-empty check.
    # Three specs called it binding under "Enforcement" while no script anywhere
    # actually invoked it. It does now.
    DEDUP_RC=0
    ralph_validate bash "$WORKSPACE/validate-corpus.sh" --final "$CORPUS_TRACK" || DEDUP_RC=$?
    RALPH_FAIL_LINES="${VALIDATE_FAILS}${RALPH_FAIL_LINES}"

    if [[ "$VALIDATE_RC" -eq 0 && "$CORPUS_RC" -eq 0 && "$DEDUP_RC" -eq 0 && -z "$FACT_NOTES" ]]; then
      ralph_rejects_clear "$REJECT_STATE_DIR" "${CATEGORY}"
      echo "Stopping: COMPLETE promise verified."
      exit 0
    fi

    REJECTS="$(ralph_rejects_bump "$REJECT_STATE_DIR" "${CATEGORY}")"
    echo "COMPLETE rejected ($REJECTS/$RALPH_MAX_ATTEMPTS) — validation or fact-check failed." >&2
    if [[ "$REJECTS" -ge "$RALPH_MAX_ATTEMPTS" ]]; then
      echo "" >&2
      echo "ERROR: $CATEGORY claimed COMPLETE $REJECTS times without passing." >&2
      echo "Giving up rather than accepting unverified content. Last failures:" >&2
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

echo "Finished $ITERATIONS iteration(s) for $CATEGORY (not complete — continue loop)."
exit 2
