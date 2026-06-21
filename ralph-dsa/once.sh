#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-dsa/once.sh <category-slug> [--agent cursor|claude] [--model <slug>] [iterations]
#
# Runs one DSA category plan item via Cursor Agent or Claude Code.
#   --agent cursor  (default) — uses Cursor's headless `agent` CLI
#   --agent claude            — uses Claude Code's `claude -p` CLI

CATEGORY="${1:?Usage: $0 <category-slug> [--agent cursor|claude] [--model <slug>] [iterations]  e.g. 01-arrays-hashing}"
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

PLAN="$WORKSPACE/dsa/plan.md"
PROGRESS="$WORKSPACE/dsa/progress.txt"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
SPEC="$SCRIPT_DIR/spec.md"
README="$WORKSPACE/dsa/README.md"
LIST="$WORKSPACE/dsa/neetcode-150-list.md"
RECOGNITION="$WORKSPACE/dsa/patterns/recognition-guide.md"
PROB_TEMPLATE="$WORKSPACE/dsa/problems/_template.md"
PAT_TEMPLATE="$WORKSPACE/dsa/patterns/_template.md"

[[ -f "$PLAN" ]] || { echo "Missing $PLAN — run ./ralph-dsa/scaffold.sh $CATEGORY first" >&2; exit 1; }

CATEGORY_NAME="$(python3 -c "
import sys
sys.path.insert(0, '${SCRIPT_DIR}/scripts')
from category_data import get_category
print(get_category('${CATEGORY}').name)
")"

mkdir -p "$SCRIPT_DIR/.logs"
LOG_DIR="$SCRIPT_DIR/.logs"

PROMPT_BODY="$(sed -e "s/{{CATEGORY}}/$CATEGORY/g" -e "s/{{CATEGORY_NAME}}/$CATEGORY_NAME/g" "$PROMPT_FILE")"

TASK_INSTRUCTIONS="Category: $CATEGORY ($CATEGORY_NAME). Workspace: dsa/
${PROMPT_BODY}
Follow ralph-dsa/prompt.md. Complete exactly ONE unchecked item in dsa/plan.md Next section.
End with normal assistant text; emit <promise>COMPLETE</promise> only when ALL plan items done and validate passes."

AGENT_TIMEOUT_SEC="${CURSOR_AGENT_TIMEOUT_SEC:-2700}"

# ── Cursor backend ────────────────────────────────────────────────────────────
build_cursor_cmd() {
  local output_fmt="${CURSOR_AGENT_OUTPUT_FORMAT:-stream-json}"
  local prompt="@${SPEC} @${README} @${LIST} @${RECOGNITION} @${PROB_TEMPLATE} @${PAT_TEMPLATE} @${PLAN} @${PROGRESS} @${PROMPT_FILE} ${TASK_INSTRUCTIONS}"
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
  context="$(cat "$SPEC" "$README" "$LIST" "$RECOGNITION" "$PROB_TEMPLATE" "$PAT_TEMPLATE" "$PLAN" "$PROGRESS" "$PROMPT_FILE" 2>/dev/null || true)"
  BUILT_PROMPT="${context}

${TASK_INSTRUCTIONS}"
  local -a flags=(-p --dangerously-skip-permissions --output-format stream-json --verbose)
  [[ -n "$MODEL" ]] && flags+=(--model "$MODEL")
  BUILT_CMD=(claude "${flags[@]}")
}

run_agent_with_timeout() {
  if [[ "$AGENT_BACKEND" == "claude" ]]; then
    # Pass prompt as positional arg — `timeout` breaks claude and yields empty output.
    "${BUILT_CMD[@]}" "$BUILT_PROMPT" &
    local agent_pid=$!
    (sleep "$AGENT_TIMEOUT_SEC" && kill -INT "$agent_pid" 2>/dev/null && sleep 60 && kill -KILL "$agent_pid" 2>/dev/null) &
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
  echo "Ralph DSA $CATEGORY — iteration $i / $ITERATIONS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  LOG_FILE="$LOG_DIR/${CATEGORY}-iter-${i}-$(date +%Y%m%d-%H%M%S).log"
  echo "Log: $LOG_FILE" >&2
  echo "Timeout: ${AGENT_TIMEOUT_SEC}s" >&2
  echo "Agent: $AGENT_BACKEND" >&2
  [[ -n "$MODEL" ]] && echo "Model: $MODEL" >&2

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

  if [[ "$agent_exit" -eq 124 ]] || [[ "$agent_exit" -eq 142 ]]; then
    echo "Agent killed after ${AGENT_TIMEOUT_SEC}s" >&2
    exit 124
  fi

  promise_text="$(extract_stream_json_result "$LOG_FILE")"

  if has_completion_promise "$promise_text"; then
    echo "Stopping: COMPLETE promise in agent result."
    bash "$SCRIPT_DIR/validate.sh" "$CATEGORY" || true
    exit 0
  fi
done

echo "Finished $ITERATIONS iteration(s) for $CATEGORY (not complete — continue loop)."
exit 2
