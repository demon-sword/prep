#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-ml-coding/once.sh [problem-id] [--model <slug>]
#
# problem-id (optional): generate a specific problem by id, e.g. 25-scaled-dot-product-attention
#                        If omitted, picks the first unchecked item in plan.md.
#
# Examples:
#   ./ralph-ml-coding/once.sh                        # next in queue
#   ./ralph-ml-coding/once.sh 25-scaled-dot-product-attention       # specific problem
#   ./ralph-ml-coding/once.sh 15-kmeans --model claude-sonnet-4

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../ralph-common.sh
. "$PREP_ROOT/ralph-common.sh"
cd "$PREP_ROOT"

MODEL="${RALPH_MLCODING_MODEL:-}"
AGENT_TIMEOUT_SEC="${RALPH_MLCODING_TIMEOUT:-3600}"
TARGET_PROBLEM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model|-m) MODEL="$2"; shift 2 ;;
    --help|-h)
      sed -n '1,15p' "$0" >&2
      echo "" >&2
      echo "Available problem IDs:" >&2
      python3 -c "
import json, pathlib
concepts = json.loads(pathlib.Path('$SCRIPT_DIR/problems.json').read_text())
for c in concepts:
    print(f\"  {c['id']:35s} {c['title']}\")
" >&2
      exit 0
      ;;
    -*)
      echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      # Positional = concept id
      TARGET_PROBLEM="$1"; shift ;;
  esac
done

PLAN="$SCRIPT_DIR/plan.md"
PROGRESS="$SCRIPT_DIR/progress.txt"
OUTPUT_DIR="$PREP_ROOT/ml-coding"
CORPUS_TRACK="ml-coding"
OUTPUT_EXT="md"
SPEC="$SCRIPT_DIR/spec.md"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
PROBLEMS_JSON="$SCRIPT_DIR/problems.json"

[[ -f "$PLAN" ]] || {
  echo "Missing $PLAN — run ./ralph-ml-coding/scaffold.sh first" >&2
  exit 1
}

# Validate target concept if specified
if [[ -n "$TARGET_PROBLEM" ]]; then
  CONCEPT_EXISTS=$(python3 -c "
import json, pathlib, sys
concepts = json.loads(pathlib.Path('$PROBLEMS_JSON').read_text())
ids = [c['id'] for c in concepts]
print('yes' if '$TARGET_PROBLEM' in ids else 'no')
")
  if [[ "$CONCEPT_EXISTS" != "yes" ]]; then
    echo "Unknown problem id: '$TARGET_PROBLEM'" >&2
    echo "" >&2
    echo "Available IDs:" >&2
    python3 -c "
import json, pathlib
concepts = json.loads(pathlib.Path('$PROBLEMS_JSON').read_text())
for c in concepts:
    print(f\"  {c['id']:35s} {c['title']}\")
" >&2
    exit 1
  fi
  # Check if already done
  PROBLEM_PATH="$PREP_ROOT/ml-coding/${TARGET_PROBLEM}.md"
  if [[ -f "$PROBLEM_PATH" ]]; then
    echo "Note: $TARGET_PROBLEM already has a generated file at:"
    echo "  $PROBLEM_PATH"
    echo "Regenerating (will overwrite)..."
  fi
fi

# Check if anything is left to do (only relevant when no specific target)
if [[ -z "${TARGET_PROBLEM}" ]] && ! grep -q '^\- \[ \]' "$PLAN" 2>/dev/null; then
  # "Nothing left to do" is a completion claim, so it answers to exactly the
  # gates the COMPLETE branch answers to. It used to `exit 0` outright, which
  # meant re-running the loop over an already-generated track reported success
  # without the corpus gate spec.md calls binding ever running.
  echo "All problems complete (no unchecked items in plan.md) — verifying before reporting it."
  SHORTCUT_RC=0
  ralph_validate bash "$SCRIPT_DIR/validate.sh" || SHORTCUT_RC=$?
  if [[ "$SHORTCUT_RC" -eq 2 ]]; then
    echo "" >&2
    echo "Cannot execute solutions — see the message above. Fix the interpreter, then re-run." >&2
    exit 4
  fi
  if [[ "$SHORTCUT_RC" -eq 0 ]]; then
    ralph_require_complete "$PLAN" "$OUTPUT_DIR" "$OUTPUT_EXT" || SHORTCUT_RC=$?
  fi
  if [[ "$SHORTCUT_RC" -eq 0 ]]; then
    ralph_validate bash "$PREP_ROOT/validate-corpus.sh" --final "$CORPUS_TRACK" || SHORTCUT_RC=$?
  fi
  if [[ "$SHORTCUT_RC" -ne 0 ]]; then
    echo "" >&2
    echo "Plan is fully checked but the corpus does not pass — not reporting complete." >&2
    exit 3
  fi
  echo "All problems complete (no unchecked items in plan.md)."
  exit 0
fi

mkdir -p "$SCRIPT_DIR/.logs"
LOG_DIR="$SCRIPT_DIR/.logs"
LOG_FILE="$LOG_DIR/iter-$(date +%Y%m%d-%H%M%S).log"

# Resolve which concept will be worked on (for display)
if [[ -n "$TARGET_PROBLEM" ]]; then
  DISPLAY_PROBLEM="$TARGET_PROBLEM"
  TARGET_INSTRUCTION="Generate the problem with id: ${TARGET_PROBLEM}
The file should be at: $PREP_ROOT/ml-coding/${TARGET_PROBLEM}.md
Mark it as done in ralph-ml-coding/plan.md even if it was already checked."
else
  DISPLAY_PROBLEM="(next in queue)"
  TARGET_INSTRUCTION="Pick the FIRST unchecked item from the ## Next section of ralph-ml-coding/plan.md."
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ralph ML Coding — problem: $DISPLAY_PROBLEM"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Log: $LOG_FILE" >&2
echo "Timeout: ${AGENT_TIMEOUT_SEC}s" >&2

# Build prompt: inline all context
CONTEXT="$(cat "$SPEC" "$PROBLEMS_JSON" "$PLAN" "$PROGRESS" "$PROMPT_FILE" 2>/dev/null || true)"

# Resolve which concept this run produces, so validation can be scoped to it.
# Empty (no id-shaped next item) means validate the whole corpus instead.
if [[ -n "$TARGET_PROBLEM" ]]; then
  RESOLVED_PROBLEM="$TARGET_PROBLEM"
else
  # One sed, no pipeline. `grep -m1 ... | sed` looks equivalent but exits 1 the
  # moment grep matches nothing, and under `set -o pipefail` that failure becomes
  # the assignment's, which errexit turns into a silent death of the whole run.
  RESOLVED_PROBLEM="$(sed -n 's/^- \[ \] \([0-9][0-9]*-[a-z0-9][a-z0-9-]*\).*/\1/p' "$PLAN" 2>/dev/null || true)"
  RESOLVED_PROBLEM="${RESOLVED_PROBLEM%%$'\n'*}"
fi
VALIDATE_ARGS=()
[[ -n "$RESOLVED_PROBLEM" ]] && VALIDATE_ARGS+=("$RESOLVED_PROBLEM")


# Build claude command
CLAUDE_FLAGS=(-p --dangerously-skip-permissions --output-format stream-json --verbose)
[[ -n "$MODEL" ]] && CLAUDE_FLAGS+=(--model "$MODEL")

# A failed run must not leave a half-written page sitting in the corpus, and a
# failed REGENERATION must not destroy the accepted page it was replacing.
TARGET_FILE=""
PRISTINE=""
if [[ -n "${RESOLVED_PROBLEM}" ]]; then
  TARGET_FILE="$OUTPUT_DIR/${RESOLVED_PROBLEM}.$OUTPUT_EXT"
  if [[ -s "$TARGET_FILE" ]]; then PRISTINE="$(mktemp)"; cp "$TARGET_FILE" "$PRISTINE"; fi
fi

FEEDBACK=""
FACT_NOTES=""
VERIFIED=0

for ((attempt = 1; attempt <= RALPH_MAX_ATTEMPTS; attempt++)); do
  echo ""
  echo "---------- attempt $attempt / $RALPH_MAX_ATTEMPTS ----------"

  TASK="You are generating runnable Python ML interview problems.

WORKSPACE ROOT: $PREP_ROOT
OUTPUT DIR: $PREP_ROOT/ml-coding/

${CONTEXT}

TASK: ${TARGET_INSTRUCTION}
Generate the HTML file. Validate it. Test it with Playwright MCP.
Fix any issues. Mark the plan item done. Append to progress.txt.

After you finish, ralph runs two gates you cannot bypass:
  1. bash ralph-ml-coding/validate.sh <id> — a hard gate. Its exit code is honoured.
  2. an independent fact-check agent that reads ONLY your finished file and
     hunts for wrong formulas, wrong mechanisms and false claims.
If either fails, this item is regenerated and you will be shown the failures.
So get the content factually right the first time — do not pad word counts with
claims you are not sure of.

Emit <promise>COMPLETE</promise> ONLY if ALL plan items are now checked (entire plan done).
Otherwise just finish normally after completing the ONE item.
${FEEDBACK}"

  echo "Running Claude..." >&2

  set +e
  # Redirect to the log this script has always ANNOUNCED but never wrote:
  # every plan-driven .logs/ was empty, which is why 11 generated mlops
  # pages left no evidence that any gate fired on them. Redirecting a
  # background job is safe; piping is not, because $! must stay the
  # agent for the watchdog to signal the right process tree.
  claude "${CLAUDE_FLAGS[@]}" "$TASK" >"$LOG_FILE" 2>&1 &
  AGENT_PID=$!

  # Watchdog. It stamps a marker BEFORE signalling, because the exit status
  # cannot be trusted: a background job in a script has job control off and
  # POSIX makes it IGNORE SIGINT, so the old graceful kill was a no-op and only
  # the SIGKILL 60s later landed — reporting 137, which the old 124/142 test
  # never matched. SIGTERM is NOT ignored, so it now does the graceful stop and
  # the timeout takes effect on time. See ralph_agent_timed_out.
  TIMEOUT_MARKER="${LOG_FILE}.timeout"
  rm -f "$TIMEOUT_MARKER"
  (sleep "$AGENT_TIMEOUT_SEC"; : > "$TIMEOUT_MARKER"; ralph_kill_tree "$AGENT_PID" TERM; sleep 30; ralph_kill_tree "$AGENT_PID" KILL) &
  WATCHDOG_PID=$!

  wait "$AGENT_PID"
  RC=$?

  kill "$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true
  cat "$LOG_FILE" 2>/dev/null || true
  ralph_agent_record "$LOG_FILE" "$RC" "${#TASK}" "claude ${CLAUDE_FLAGS[*]}" || true
  set -e

  if ralph_agent_timed_out "$TIMEOUT_MARKER" "$RC"; then
    echo "Agent killed after ${AGENT_TIMEOUT_SEC}s (exit $RC)" >&2
    rm -f "$TIMEOUT_MARKER"
    ralph_quarantine_partial "$TARGET_FILE" "$PRISTINE"

    exit 124
  fi
  rm -f "$TIMEOUT_MARKER"

  # Gate 1 — structural validation. Binding: the exit code decides.
  VALIDATE_RC=0
  ralph_validate bash "$SCRIPT_DIR/validate.sh" ${VALIDATE_ARGS[@]+"${VALIDATE_ARGS[@]}"} || VALIDATE_RC=$?

  # validate.sh exit 2 = no Python with numpy. That is an environment problem,
  # not something the agent can fix by regenerating — abort instead of burning
  # the retries. Re-mapped to 4 on the way out: this script's exit 2 already
  # means "item done, more remain", and overloading it made loop.sh stop after
  # its first SUCCESS and blame the environment for it.
  if [[ "$VALIDATE_RC" -eq 2 ]]; then
    echo "" >&2
    echo "Cannot execute solutions — see the message above. Fix the interpreter, then re-run." >&2
    exit 4
  fi

  # An item that was never generated is SKIPped by the validator, which then
  # exits 0 — correct for a validation sweep over a half-built corpus, and wrong
  # here, where this iteration was supposed to produce exactly that file. Without
  # this, an agent that wrote nothing passes gate 1.
  if [[ "$VALIDATE_RC" -eq 0 && -n "${RESOLVED_PROBLEM}" && ! -s "$OUTPUT_DIR/${RESOLVED_PROBLEM}.$OUTPUT_EXT" ]]; then
    VALIDATE_RC=1
    RALPH_FAIL_LINES="FAIL: ${RESOLVED_PROBLEM} — this iteration produced no file at $OUTPUT_DIR/${RESOLVED_PROBLEM}.$OUTPUT_EXT"
    printf '%s\n' "$RALPH_FAIL_LINES" >&2
  fi

  # Gate 2 — adversarial fact-check of the finished file, only worth spending
  # once the file is structurally sound.
  FACT_RC=0
  FACT_NOTES=""
  if [[ "$VALIDATE_RC" -eq 0 && -n "$RESOLVED_PROBLEM" ]]; then
    FACT_RC=0
    ralph_factcheck "$PREP_ROOT/ml-coding/${RESOLVED_PROBLEM}.md" "an ML coding problem with a runnable solution" "$MODEL" || FACT_RC=$?
    FACT_NOTES="$RALPH_FACTCHECK_NOTES"
  fi

  # FACT_RC=2 means the fact-check HARNESS failed — no verdict was produced at
  # all. Regenerating cannot fix that, and three more generations at ~$4 and
  # ~9 minutes each buys nothing. Fail fast, like the environment cases.
  if [[ "$FACT_RC" -eq 2 ]]; then
    echo "" >&2
    echo "Fact-check could not run — infrastructure failure, not a content failure." >&2
    printf '%s\n' "$FACT_NOTES" >&2
    echo "Fix it and re-run. Not spending the retry budget on it." >&2
    ralph_quarantine_partial "$TARGET_FILE" "$PRISTINE"

    exit 4
  fi

  if [[ "$VALIDATE_RC" -eq 0 && "$FACT_RC" -eq 0 ]]; then
    VERIFIED=1
    # Leave evidence that the gates actually ran on this item. The agent writes
    # its own progress line; this one is the HARNESS's, and it records which
    # verdict the adversarial pass returned — including SKIPPED, so a run made
    # with RALPH_SKIP_FACTCHECK=1 can never again be mistaken for a checked one.
    printf '%s | %s | gate | validate=PASS factcheck=%s attempts=%s\n' \
      "$(date +%Y-%m-%d)" "${RESOLVED_PROBLEM}" "${RALPH_FACTCHECK_VERDICT:-NOT-RUN}" "$attempt" \
      >> "$PROGRESS" 2>/dev/null || true
    rm -f "$PRISTINE" 2>/dev/null || true
    break
  fi

  FEEDBACK="$(ralph_feedback "$attempt" "$RALPH_MAX_ATTEMPTS" "$RALPH_FAIL_LINES" "$FACT_NOTES")"
  echo "Attempt $attempt rejected — feeding the specific failures into the next attempt." >&2
done

if [[ "$VERIFIED" -ne 1 ]]; then
  echo "" >&2
  echo "ERROR: ${RESOLVED_PROBLEM:-this item} still fails after $RALPH_MAX_ATTEMPTS attempts." >&2
  echo "Giving up rather than accepting unverified content. Last failures:" >&2
  [[ -n "$RALPH_FAIL_LINES" ]] && printf '%s\n' "$RALPH_FAIL_LINES" >&2
  [[ -n "$FACT_NOTES" ]] && printf '%s\n' "$FACT_NOTES" >&2
  ralph_quarantine_partial "$TARGET_FILE" "$PRISTINE"
  exit 3
fi

# Plan fully done? COMPLETE is only real if the whole corpus still validates.
if ! grep -q '^\- \[ \]' "$PLAN" 2>/dev/null; then
  FINAL_RC=0
  ralph_validate bash "$SCRIPT_DIR/validate.sh" || FINAL_RC=$?
  if [[ "$FINAL_RC" -eq 2 ]]; then
    echo "" >&2
    echo "Cannot execute solutions — see the message above. Fix the interpreter, then re-run." >&2
    exit 4
  fi
  if [[ "$FINAL_RC" -ne 0 ]]; then
    echo "" >&2
    echo "Plan is fully checked but corpus validation FAILED — refusing to report COMPLETE." >&2
    exit 3
  fi
  # A per-file validator iterates over the files that exist, so on an empty or
  # half-finished corpus it checks nothing and passes. Before believing
  # COMPLETE, confirm the plan was actually carried out.
  COMPLETE_RC=0
  ralph_require_complete "$PLAN" "$OUTPUT_DIR" "$OUTPUT_EXT" || COMPLETE_RC=$?
  if [[ "$COMPLETE_RC" -ne 0 ]]; then
    echo "" >&2
    echo "Plan is fully checked but the corpus is empty or incomplete — refusing to report COMPLETE." >&2
    exit 3
  fi
  # The corpus-level gate: cross-file redundancy, plus completeness against the
  # generator queue. Three specs called it binding under "Enforcement" while no
  # script anywhere actually invoked it. It does now.
  DEDUP_RC=0
  ralph_validate bash "$PREP_ROOT/validate-corpus.sh" --final "$CORPUS_TRACK" || DEDUP_RC=$?
  if [[ "$DEDUP_RC" -ne 0 ]]; then
    echo "" >&2
    echo "Corpus-level validation FAILED — refusing to report COMPLETE." >&2
    exit 3
  fi
  echo "All problems complete and validated!"
  exit 0
fi

echo "Problem generated and verified. Continue loop for next item."
exit 2
