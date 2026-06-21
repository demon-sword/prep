#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-ai-engineering/run-all.sh [--agent cursor|claude] [--model <slug>] [--from <slug>]
#
# Generates all 10 AI engineering categories in order (fewest tasks first).
# Each category is scaffolded, looped until complete, then validated before
# moving to the next. Progress is logged to ai-engineering/progress.txt.
#
# Options:
#   --agent cursor|claude   Agent backend (default: claude)
#   --model <slug>          Model override (e.g. sonnet, opus)
#   --from <slug>           Skip categories before this slug (resume from here)
#   --dry-run               Print what would run without executing

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENT_BACKEND="${RALPH_AGENT:-claude}"
MODEL=""
FROM_SLUG=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent|-a)   AGENT_BACKEND="$2"; shift 2 ;;
    --model|-m)   MODEL="$2"; shift 2 ;;
    --from|-f)    FROM_SLUG="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --help|-h)
      sed -n '1,15p' "$0" >&2; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Categories in order: fewest tasks first → largest last
declare -a CATEGORIES=(
  "08-safety-guardrails:16"
  "04-fine-tuning-training:18"
  "07-cost-latency:22"
  "05-evaluation-metrics:30"
  "06-ml-fundamentals:34"
  "02-rag-systems:42"
  "03-agents-tool-use:46"
  "01-llm-fundamentals:56"
  "09-system-design-ai:63"
  "10-behavioral:80"
)

# ── Helpers ───────────────────────────────────────────────────────────────────

log() { echo "[run-all] $*"; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  DRY-RUN: $*"
  else
    "$@"
  fi
}

# ── Skip-to logic ─────────────────────────────────────────────────────────────

ACTIVE=1
if [[ -n "$FROM_SLUG" ]]; then
  ACTIVE=0
  log "Skipping categories before '$FROM_SLUG'"
fi

# ── Main loop ─────────────────────────────────────────────────────────────────

TOTAL=${#CATEGORIES[@]}
DONE=0
FAILED=()

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Ralph AI Engineering — run-all"
echo "  Agent: $AGENT_BACKEND${MODEL:+  Model: $MODEL}${FROM_SLUG:+  From: $FROM_SLUG}"
echo "  Categories: $TOTAL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for entry in "${CATEGORIES[@]}"; do
  SLUG="${entry%%:*}"
  MAX="${entry##*:}"

  # --from: activate once we hit the target slug
  if [[ "$ACTIVE" -eq 0 ]]; then
    if [[ "$SLUG" == "$FROM_SLUG" ]]; then
      ACTIVE=1
    else
      log "Skipping $SLUG"
      continue
    fi
  fi

  DONE=$((DONE + 1))
  echo ""
  echo "══════════════════════════════════════════════════════════════════════"
  echo "  Category $DONE / $TOTAL: $SLUG (max $MAX iterations)"
  echo "══════════════════════════════════════════════════════════════════════"

  # 1. Scaffold
  log "Scaffolding $SLUG..."
  run bash "$SCRIPT_DIR/scaffold.sh" "$SLUG"

  # 2. Loop
  LOOP_ARGS=("$SLUG" "$MAX" --agent "$AGENT_BACKEND")
  [[ -n "$MODEL" ]] && LOOP_ARGS+=(--model "$MODEL")

  log "Running loop for $SLUG (max $MAX)..."
  set +e
  run bash "$SCRIPT_DIR/loop.sh" "${LOOP_ARGS[@]}"
  loop_rc=$?
  set -e

  if [[ "$loop_rc" -eq 0 ]]; then
    log "✓ $SLUG — loop reported COMPLETE"
  elif [[ "$loop_rc" -eq 124 ]]; then
    log "✗ $SLUG — timed out; continuing to next category"
    FAILED+=("$SLUG (timeout)")
    continue
  else
    log "! $SLUG — loop ended without COMPLETE (rc=$loop_rc); running validate to check"
  fi

  # 3. Validate
  log "Validating $SLUG..."
  set +e
  run bash "$SCRIPT_DIR/validate.sh" "$SLUG"
  val_rc=$?
  set -e

  if [[ "$val_rc" -eq 0 ]]; then
    log "✓ $SLUG — validated OK"
  else
    log "✗ $SLUG — validation failed; logged and continuing"
    FAILED+=("$SLUG (validate failed)")
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  run-all complete"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "  All categories passed ✓"
else
  echo "  Failed / incomplete categories:"
  for f in "${FAILED[@]}"; do
    echo "    • $f"
  done
  echo ""
  echo "  Re-run individual categories with:"
  echo "    ./ralph-ai-engineering/scaffold.sh <slug>"
  echo "    ./ralph-ai-engineering/loop.sh <slug> <max>"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
