#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-system-design/once.sh <topic> [--agent cursor|claude] [--model <slug>] [iterations]
#
# Runs one system-design topic plan item via Cursor Agent or Claude Code.
#   --agent cursor  (default) — uses Cursor's headless `agent` CLI
#   --agent claude            — uses Claude Code's `claude -p` CLI

TOPIC="${1:?Usage: $0 <topic> [--agent cursor|claude] [--model <slug>] [iterations]}"
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
      sed -n '1,15p' "$0" >&2; exit 0
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

TOPIC_DIR="$WORKSPACE/system-design/$TOPIC"
PLAN="$TOPIC_DIR/plan.md"
PROGRESS="$TOPIC_DIR/progress.txt"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
SPEC="$SCRIPT_DIR/spec.md"
README="$WORKSPACE/system-design/README.md"

[[ -f "$PLAN" ]] || { echo "Missing $PLAN — run ./ralph-system-design/scaffold.sh $TOPIC first" >&2; exit 1; }

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
CORPUS_TRACK="system-design"
REJECTS=0

PROMPT_BODY="$(sed "s/{{TOPIC}}/$TOPIC/g" "$PROMPT_FILE")"

TASK_INSTRUCTIONS="Topic: $TOPIC. Workspace: system-design/$TOPIC/
${PROMPT_BODY}
Follow ralph-system-design/prompt.md. Complete exactly ONE unchecked item in plan.md Next section.
Use Task/subagent for research-heavy steps.
End with normal assistant text; emit <promise>COMPLETE</promise> only when ALL plan items done."

# This governs BOTH backends, so it has a backend-neutral name. The old
# CURSOR_-prefixed spelling still works — it reads as cursor-only and cost
# a real debugging session when a claude-backend timeout probe silently
# used the 2700s default instead.
AGENT_TIMEOUT_SEC="${RALPH_AGENT_TIMEOUT_SEC:-${CURSOR_AGENT_TIMEOUT_SEC:-2700}}"

# ── Cursor backend ────────────────────────────────────────────────────────────
build_cursor_cmd() {
  local output_fmt="${CURSOR_AGENT_OUTPUT_FORMAT:-stream-json}"
  local prompt="@${SPEC} @${README} @${PLAN} @${PROGRESS} @${PROMPT_FILE} ${TASK_INSTRUCTIONS}${FEEDBACK}"
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
  context="$(cat "$SPEC" "$README" "$PLAN" "$PROGRESS" "$PROMPT_FILE" 2>/dev/null || true)"
  BUILT_PROMPT="${context}

${TASK_INSTRUCTIONS}${FEEDBACK}"
  local -a flags=(-p --dangerously-skip-permissions --output-format stream-json --verbose)
  [[ -n "$MODEL" ]] && flags+=(--model "$MODEL")
  BUILT_CMD=(claude "${flags[@]}")
}

run_agent_with_timeout() {
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    # Pass prompt as positional arg — `timeout` breaks claude and yields empty output.
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
  echo "Ralph $TOPIC — iteration $i / $ITERATIONS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  LOG_FILE="$LOG_DIR/${TOPIC}-iter-${i}-$(date +%Y%m%d-%H%M%S).log"
  echo "Log: $LOG_FILE" >&2
  echo "Timeout: ${AGENT_TIMEOUT_SEC}s" >&2
  echo "Agent: $AGENT_BACKEND" >&2
  [[ -n "$MODEL" ]] && echo "Model: $MODEL" >&2

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
    echo "Agent killed after ${AGENT_TIMEOUT_SEC}s (exit $agent_exit)" >&2
    rm -f "$TIMEOUT_MARKER"
    exit 124
  fi
  rm -f "$TIMEOUT_MARKER"

  promise_text="$(extract_stream_json_result "$LOG_FILE")"

  # Adversarial fact-check of whatever this iteration actually wrote.
  PRODUCED="$(ralph_newest_since "$ITER_MARKER" "$TOPIC_DIR/answers" "$TOPIC_DIR")"
  rm -f "$ITER_MARKER"
  FACT_NOTES=""
  if [[ -n "$PRODUCED" ]]; then
    FACT_RC=0
    ralph_factcheck "$PRODUCED" "a system-design answer section" "$MODEL" || FACT_RC=$?
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
    ralph_validate bash "$SCRIPT_DIR/validate.sh" "$TOPIC" || VALIDATE_RC=$?
    VALIDATE_FAILS="$RALPH_FAIL_LINES"

    # An empty corpus is invisible to a per-file validator — it checks the files
    # that exist, so on zero files it reports a clean pass. COMPLETE has to
    # answer the other question: did this run actually produce anything?
    CORPUS_RC=0
    ralph_require_complete "$PLAN" "$TOPIC_DIR/answers" md "$TOPIC_DIR" || CORPUS_RC=$?
    RALPH_FAIL_LINES="${VALIDATE_FAILS}${RALPH_FAIL_LINES}"

    # The corpus-level gate: cross-file redundancy, plus a non-empty check.
    # Three specs called it binding under "Enforcement" while no script anywhere
    # actually invoked it. It does now.
    DEDUP_RC=0
    ralph_validate bash "$WORKSPACE/validate-corpus.sh" --final "$CORPUS_TRACK" || DEDUP_RC=$?
    RALPH_FAIL_LINES="${VALIDATE_FAILS}${RALPH_FAIL_LINES}"

    if [[ "$VALIDATE_RC" -eq 0 && "$CORPUS_RC" -eq 0 && "$DEDUP_RC" -eq 0 && -z "$FACT_NOTES" ]]; then
      ralph_rejects_clear "$REJECT_STATE_DIR" "${TOPIC}"
      echo "Stopping: COMPLETE promise verified."
      exit 0
    fi

    REJECTS="$(ralph_rejects_bump "$REJECT_STATE_DIR" "${TOPIC}")"
    echo "COMPLETE rejected ($REJECTS/$RALPH_MAX_ATTEMPTS) — validation or fact-check failed." >&2
    if [[ "$REJECTS" -ge "$RALPH_MAX_ATTEMPTS" ]]; then
      echo "" >&2
      echo "ERROR: $TOPIC claimed COMPLETE $REJECTS times without passing." >&2
      echo "Giving up rather than accepting unverified content. Last failures:" >&2
      [[ -n "$RALPH_FAIL_LINES" ]] && printf '%s\n' "$RALPH_FAIL_LINES" >&2
      [[ -n "$FACT_NOTES" ]] && printf '%s\n' "$FACT_NOTES" >&2
      exit 3
    fi
    FEEDBACK="
$(ralph_feedback "$REJECTS" "$RALPH_MAX_ATTEMPTS" "$RALPH_FAIL_LINES" "$FACT_NOTES")"
    continue
  fi

  # Auto-run gen-plan after design-doc appears
  if [[ -f "$TOPIC_DIR/${TOPIC}-design-doc.md" ]] && grep -q '\[ \] gen-plan' "$PLAN" 2>/dev/null; then
    echo "Auto-running gen-plan.sh..." >&2
    bash "$SCRIPT_DIR/gen-plan.sh" "$TOPIC" || true
  fi

  # Auto-run md-to-html when all answer md files exist and task is pending
  SECTION_COUNT=$(grep -cE '^## [0-9]+\.' "$TOPIC_DIR/${TOPIC}-design-doc.md" 2>/dev/null || echo 0)
  # Guarded: find exits 1 on a missing path, and pipefail + errexit turn that
  # into a silent death of the iteration.
  MD_COUNT=0
  [[ -d "$TOPIC_DIR/answers" ]] && MD_COUNT=$(find "$TOPIC_DIR/answers" -maxdepth 1 -name '[0-9]*.md' | wc -l | tr -d ' ')
  if [[ "$SECTION_COUNT" -gt 0 && "$MD_COUNT" -ge "$SECTION_COUNT" ]] && grep -q '\[ \] md-to-html' "$PLAN" 2>/dev/null; then
    echo "Auto-running md_to_html.py..." >&2
    python3 "$SCRIPT_DIR/scripts/md_to_html.py" "$TOPIC" || true
    sed -i '' 's/- \[ \] md-to-html.*/- [x] md-to-html — generated section HTML/' "$PLAN" 2>/dev/null || \
      sed -i 's/- \[ \] md-to-html.*/- [x] md-to-html — generated section HTML/' "$PLAN" || true
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

echo "Finished $ITERATIONS iteration(s) for $TOPIC (not complete — continue loop)."
exit 2
