#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-system-design/once.sh <topic> [--model <slug>] [iterations]
#
# Runs Cursor Agent headless for one system-design topic.
# Reference: pulse/ralph/once.sh

TOPIC="${1:?Usage: $0 <topic> [--model <slug>] [iterations]}"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$WORKSPACE"

MODEL="${CURSOR_MODEL:-}"
ITERATIONS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model|-m)
      [[ $# -ge 2 ]] || { echo "Usage: $0 <topic> [--model <slug>] [iterations]" >&2; exit 1; }
      MODEL="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '1,15p' "$0" >&2
      exit 0
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        ITERATIONS="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

TOPIC_DIR="$WORKSPACE/system-design/$TOPIC"
PLAN="$TOPIC_DIR/plan.md"
PROGRESS="$TOPIC_DIR/progress.txt"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
SPEC="$SCRIPT_DIR/spec.md"
README="$WORKSPACE/system-design/README.md"

[[ -f "$PLAN" ]] || { echo "Missing $PLAN — run ./ralph-system-design/scaffold.sh $TOPIC first" >&2; exit 1; }

mkdir -p "$SCRIPT_DIR/.logs"
LOG_DIR="$SCRIPT_DIR/.logs"

PROMPT_BODY="$(sed "s/{{TOPIC}}/$TOPIC/g" "$PROMPT_FILE")"

CURSOR_PROMPT="@${SPEC} @${README} @${PLAN} @${PROGRESS} @${PROMPT_FILE} \
Topic: $TOPIC. Workspace: system-design/$TOPIC/ \
${PROMPT_BODY} \
Follow ralph-system-design/prompt.md. Complete exactly ONE unchecked item in plan.md Next section. \
Use Task/subagent for research-heavy steps. \
End with normal assistant text; emit <promise>COMPLETE</promise> only when ALL plan items done."

OUTPUT_FORMAT="${CURSOR_AGENT_OUTPUT_FORMAT:-stream-json}"

AGENT_FLAGS=(
  --print
  --trust
  --force
  --approve-mcps
  --workspace "$WORKSPACE"
  --output-format "$OUTPUT_FORMAT"
)

if [[ "$OUTPUT_FORMAT" == "stream-json" ]] && [[ "${CURSOR_AGENT_STREAM:-1}" == "1" ]]; then
  AGENT_FLAGS+=(--stream-partial-output)
fi

if [[ -n "$MODEL" ]]; then
  AGENT_FLAGS+=(--model "$MODEL")
fi

CURSOR_AGENT_TIMEOUT_SEC="${CURSOR_AGENT_TIMEOUT_SEC:-2700}"

run_agent_with_timeout() {
  local -a cmd=(agent "${AGENT_FLAGS[@]}" "$CURSOR_PROMPT")
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=INT --kill-after=60 "${CURSOR_AGENT_TIMEOUT_SEC}" "${cmd[@]}"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout --signal=INT --kill-after=60 "${CURSOR_AGENT_TIMEOUT_SEC}" "${cmd[@]}"
  else
    perl -e 'alarm shift @ARGV if shift; exec @ARGV' "$CURSOR_AGENT_TIMEOUT_SEC" "${cmd[@]}"
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
  echo "Timeout: ${CURSOR_AGENT_TIMEOUT_SEC}s" >&2
  [[ -n "$MODEL" ]] && echo "Model: $MODEL" >&2

  set +e
  if [[ -t 1 ]]; then
    run_agent_with_timeout 2>&1 | tee "$LOG_FILE" /dev/tty
  else
    run_agent_with_timeout 2>&1 | tee "$LOG_FILE"
  fi
  agent_exit=$?
  set -e

  if [[ "$agent_exit" -eq 124 ]] || [[ "$agent_exit" -eq 142 ]]; then
    echo "Agent killed after ${CURSOR_AGENT_TIMEOUT_SEC}s" >&2
    exit 124
  fi

  promise_text=""
  if [[ "$OUTPUT_FORMAT" == "stream-json" ]]; then
    promise_text="$(extract_stream_json_result "$LOG_FILE")"
  else
    promise_text="$(<"$LOG_FILE")"
  fi

  if has_completion_promise "$promise_text"; then
    echo "Stopping: COMPLETE promise in agent result."
    bash "$SCRIPT_DIR/validate.sh" "$TOPIC" || true
    exit 0  # signal loop to stop
  fi

  # Auto-run gen-plan after design-doc appears
  if [[ -f "$TOPIC_DIR/${TOPIC}-design-doc.md" ]] && grep -q '\[ \] gen-plan' "$PLAN" 2>/dev/null; then
    echo "Auto-running gen-plan.sh..." >&2
    bash "$SCRIPT_DIR/gen-plan.sh" "$TOPIC" || true
  fi

  # Auto-run md-to-html when all answer md files exist and task is pending
  SECTION_COUNT=$(grep -cE '^## [0-9]+\.' "$TOPIC_DIR/${TOPIC}-design-doc.md" 2>/dev/null || echo 0)
  MD_COUNT=$(find "$TOPIC_DIR/answers" -maxdepth 1 -name '[0-9]*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$SECTION_COUNT" -gt 0 && "$MD_COUNT" -ge "$SECTION_COUNT" ]] && grep -q '\[ \] md-to-html' "$PLAN" 2>/dev/null; then
    echo "Auto-running md_to_html.py..." >&2
    python3 "$SCRIPT_DIR/scripts/md_to_html.py" "$TOPIC" || true
    sed -i '' 's/- \[ \] md-to-html.*/- [x] md-to-html — generated section HTML/' "$PLAN" 2>/dev/null || \
      sed -i 's/- \[ \] md-to-html.*/- [x] md-to-html — generated section HTML/' "$PLAN" || true
  fi
done

echo "Finished $ITERATIONS iteration(s) for $TOPIC (not complete — continue loop)."
exit 2
