#!/usr/bin/env bash
# Shared helpers for the Ralph generators. Source from a once.sh/loop.sh:
#
#   . "$PREP_ROOT/ralph-common.sh"
#
# Nothing here runs an agent loop on its own.
#
# CALLING CONVENTION — read this before adding a helper or a call site.
#
# Nothing in this file may touch the caller's shell options. `set -e` is
# SHELL-GLOBAL, not function-scoped: a helper that flips it off, does its work
# and flips it back on before returning non-zero kills the CALLER at the point
# of the call. The line after it never runs. That is exactly how every retry,
# feedback and give-up path in nine of these generators was silently turned
# into dead code. Inside a helper, capture failures with `|| rc=$?` instead —
# an `||` list is already exempt from errexit and mutates nothing.
#
# Call the status-returning helpers (ralph_validate, ralph_factcheck,
# ralph_require_complete) like this, so the exit code survives errexit:
#
#   RC=0
#   ralph_validate bash validate.sh "$ID" || RC=$?
#
# NOT `set +e; ralph_validate ...; RC=$?; set -e`. That form depends on the
# caller's errexit state being what you assumed, and it is the shape the bug
# above hid in. This is NOT `|| true` — the code is kept and acted on.

# How many times a single unit (concept / category) may be regenerated before
# the run gives up and reports the failure instead of silently accepting it.
RALPH_MAX_ATTEMPTS="${RALPH_MAX_ATTEMPTS:-3}"
RALPH_FACTCHECK_TIMEOUT="${RALPH_FACTCHECK_TIMEOUT:-900}"
# Set RALPH_SKIP_FACTCHECK=1 to skip the adversarial pass (e.g. offline reruns).
RALPH_SKIP_FACTCHECK="${RALPH_SKIP_FACTCHECK:-0}"

# Seconds loop.sh waits between iterations. A loop with no pause and no failure
# handling is a token bonfire: with an agent binary that exits immediately,
# ralph-ai-engineering made 80 real agent invocations in 8.95 seconds.
RALPH_LOOP_SLEEP="${RALPH_LOOP_SLEEP:-5}"
# Consecutive iterations that produce no new content before loop.sh gives up.
RALPH_MAX_STALLS="${RALPH_MAX_STALLS:-3}"
# Identifies one whole loop.sh run, so per-run counters can survive across the
# separate once.sh processes that run belongs to. A once.sh started by hand gets
# its own id and therefore its own fresh budget.
RALPH_RUN_ID="${RALPH_RUN_ID:-}"

RALPH_FAIL_LINES=""
RALPH_FACTCHECK_NOTES=""
# PASS | FAIL | SKIPPED | NO-VERDICT | NO-CLI | MISSING-FILE — so callers can
# record in progress.txt WHICH of those happened. "no evidence the gate ran" was
# a real review finding; a verdict nobody writes down is indistinguishable from
# a gate that never fired.
RALPH_FACTCHECK_VERDICT=""

# ralph_stream_json_result <log-file>
# Final assistant text from a stream-json transcript.
ralph_stream_json_result() {
  python3 - "$1" <<'PY'
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

# ralph_validate <cmd...>
# Runs a validator, echoes its report, and leaves the FAIL: lines in
# RALPH_FAIL_LINES. Returns the validator's exit code — callers must honour it.
# Touches no shell option; call as `ralph_validate ... || RC=$?`.
ralph_validate() {
  local errfile rc=0
  errfile="$(mktemp)"
  "$@" 2>"$errfile" || rc=$?
  cat "$errfile" >&2
  RALPH_FAIL_LINES="$(grep -E '^[[:space:]]*FAIL[: ]' "$errfile" || true)"
  # A validator can reject without using the FAIL: prefix — "Unknown concept:
  # zz" is a rejection too. Falling through with nothing would hand the next
  # attempt a correction block that names no problem to correct.
  if [[ "$rc" -ne 0 && -z "$RALPH_FAIL_LINES" ]]; then
    RALPH_FAIL_LINES="$(grep -v '^[[:space:]]*$' "$errfile" | tail -5 || true)"
    [[ -z "$RALPH_FAIL_LINES" ]] && RALPH_FAIL_LINES="FAIL: validation exited $rc without explaining why"
  fi
  rm -f "$errfile"
  return "$rc"
}

# ralph_factcheck <file> <subject> [model]
# Adversarial second opinion on a finished file. The agent is handed the file
# and nothing else — no spec, no plan, no generation transcript — so it judges
# the content on its merits rather than re-reading its own intent.
#
# Returns:
#   0  PASS — no incorrect claim found
#   1  FAIL — the CONTENT is wrong. Retrying is the right response: the notes in
#      RALPH_FACTCHECK_NOTES go back into the next generation attempt.
#   2  the HARNESS broke — no verdict was produced at all. Regenerating cannot
#      fix this, so callers must fail fast instead of spending the retry budget.
#      A missing --dangerously-skip-permissions on this invocation caused exactly
#      that: headless, the reviewer could not use the tools it had been granted,
#      exited 1 before saying anything, and every concept then burned three full
#      generations (~$11.60 each) to produce nothing.
ralph_factcheck() {
  local target="$1" subject="$2" model="${3:-}"
  RALPH_FACTCHECK_NOTES=""
  RALPH_FACTCHECK_VERDICT=""

  if [[ "$RALPH_SKIP_FACTCHECK" == "1" ]]; then
    RALPH_FACTCHECK_VERDICT="SKIPPED"
    echo "Fact-check skipped (RALPH_SKIP_FACTCHECK=1)." >&2
    return 0
  fi
  if [[ ! -f "$target" ]]; then
    RALPH_FACTCHECK_NOTES="file not found: $target"
    RALPH_FACTCHECK_VERDICT="MISSING-FILE"
    return 1
  fi

  local prompt="You did NOT write this file. Someone else did, and you are the reviewer.

FILE TO AUDIT: $target
SUBJECT: $subject

Read that file — and ONLY that file. Do not read the spec, the plan, the concept
list, or any other page. You have no context about how or why it was written,
and you should not go looking for any. Judge only whether what it says is TRUE.

Hunt specifically for:
  1. Incorrect formulas — wrong terms, wrong exponents, wrong normalisation,
     a scaling factor that is missing or should not be there, a loss or update
     rule that does not match the method it claims to describe.
  2. Wrong mechanism descriptions — a claim about how something works that is
     backwards, garbled, or describes a different technique entirely.
  3. False factual claims — invented numbers, misattributed papers or tools,
     wrong complexity or cost figures, real-world claims that are not true.
  4. Numbers or behaviour in the JavaScript that contradict the prose.

Be adversarial but precise. Do not report style, wording, missing topics,
formatting, or things you merely would have written differently — only claims
that are actually WRONG. If a claim is a defensible simplification, it passes.

End your reply with exactly one verdict line:
  <factcheck>PASS</factcheck>   — you found no incorrect claim
  <factcheck>FAIL</factcheck>   — you found at least one

If FAIL, precede the verdict with one line per problem, each formatted:
  FAIL: <quote the wrong claim> -> <what is actually correct>

Do not edit the file. You are reviewing, not fixing."

  if ! command -v claude >/dev/null 2>&1; then
    RALPH_FACTCHECK_NOTES="the 'claude' CLI is not on PATH — the fact-check pass cannot run"
    RALPH_FACTCHECK_VERDICT="NO-CLI"
    return 2
  fi

  local log promptfile rc=0 result
  log="$(mktemp)"
  promptfile="$(mktemp)"
  printf '%s' "$prompt" > "$promptfile"
  # Same permission posture as the generation call — headless, a tool grant is
  # useless without it — but a deliberately narrow allowlist. This agent
  # reviews; it must never edit the file it is judging.
  #
  # --allowedTools is NOT last, and the prompt goes in on stdin. It is greedy:
  # with the prompt trailing it as a positional, the CLI read the prompt as
  # another tool name and died with "Input must be provided either through
  # stdin or as a prompt argument when using --print" — exit 1, before a single
  # token of review. The generation calls never hit this because their final
  # flag takes exactly one value. stdin cannot be swallowed by any flag.
  local -a flags=(-p --dangerously-skip-permissions --allowedTools "Read,Grep,Glob"
                  --output-format stream-json --verbose)
  [[ -n "$model" ]] && flags+=(--model "$model")

  echo "Fact-checking $(basename "$target") (adversarial pass)..." >&2

  claude "${flags[@]}" >"$log" 2>&1 <"$promptfile" &
  local pid=$!
  (sleep "$RALPH_FACTCHECK_TIMEOUT" && kill -INT "$pid" 2>/dev/null && sleep 30 && kill -KILL "$pid" 2>/dev/null) &
  local watchdog=$!
  wait "$pid" || rc=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true

  result="$(ralph_stream_json_result "$log")" || result=""
  rm -f "$log" "$promptfile"

  if [[ "$rc" -ne 0 && -z "$result" ]]; then
    RALPH_FACTCHECK_VERDICT="NO-VERDICT"
    RALPH_FACTCHECK_NOTES="fact-check agent failed to produce a verdict (exit $rc).
This is an infrastructure failure, not a content failure — the reviewer never
ran. Check the 'claude' CLI, its auth, and the flags in ralph_factcheck."
    return 2
  fi

  if [[ "$result" == *"<factcheck>PASS</factcheck>"* ]]; then
    RALPH_FACTCHECK_VERDICT="PASS"
    echo "Fact-check PASS." >&2
    return 0
  fi

  if [[ "$result" == *"<factcheck>FAIL</factcheck>"* ]]; then
    RALPH_FACTCHECK_NOTES="$(printf '%s\n' "$result" | grep -E '^[[:space:]]*FAIL[: ]' || printf '%s' "$result")"
    RALPH_FACTCHECK_VERDICT="FAIL"
    echo "Fact-check FAIL." >&2
    return 1
  fi

  # Output, but no verdict tag. The reviewer did not follow the protocol, which
  # regenerating the page cannot fix — so this is a harness failure, not a
  # content one, and it must not be charged to the retry budget.
  RALPH_FACTCHECK_NOTES="fact-check returned no verdict tag, so nothing was verified.
This is an infrastructure failure, not a content failure. Output was:
$result"
  RALPH_FACTCHECK_VERDICT="NO-VERDICT"
  echo "Fact-check produced no verdict." >&2
  return 2
}

# ralph_newest_since <marker-file> <dir>...
# The most recently modified .md/.html file under those dirs that is newer than
# the marker — i.e. what the iteration that just ran actually produced.
ralph_newest_since() {
  local marker="$1"; shift
  local dir newest=""
  for dir in "$@"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [[ -z "$newest" || "$f" -nt "$newest" ]]; then newest="$f"; fi
    done < <(find "$dir" -type f \( -name '*.md' -o -name '*.html' \) -newer "$marker" 2>/dev/null)
  done
  printf '%s' "$newest"
}

# ralph_quarantine_partial <target-file> [pristine-copy]
# Takes an unaccepted draft out of the corpus.
#
# mlops/concepts/11-evaluation-gates.html sat in the corpus for two days looking
# exactly like the ten accepted pages beside it: unticked in plan.md, absent from
# progress.txt, and the only one of the eleven that violated a spec rule. Every
# gate did its job — it was never accepted — but nothing removed it, so the next
# reader could not tell an accepted page from an abandoned one.
#
# If a previously accepted version was captured before the run, it is restored,
# because a failed REGENERATION must not degrade a page that was already good.
ralph_quarantine_partial() {
  local target="$1" pristine="${2:-}"
  [[ -n "$target" && -e "$target" ]] || return 0
  mv -f "$target" "${target}.partial" 2>/dev/null || return 0
  echo "Quarantined the unaccepted draft as ${target}.partial" >&2
  if [[ -n "$pristine" && -s "$pristine" ]]; then
    cp "$pristine" "$target"
    echo "Restored the previously accepted $target" >&2
  fi
}

# ralph_exit_reason <code>
# An agent exit status, in words. The raw number is not interpretable at 3am
# mid-run: 143 is the watchdog's own SIGTERM, 130 is what `claude` reports on
# interrupt (NOT 124 — the GNU-timeout convention only applies to the cursor
# backend, which really does go through `timeout`), and a bare 1 from `claude -p`
# is most often expired auth rather than anything about the prompt.
ralph_exit_reason() {
  local c="${1:-}"
  case "$c" in
    0)   printf '0 (clean exit)' ;;
    1)   printf '1 (general error — for `claude -p` most often expired auth/session, a rejected prompt, or a bad flag)' ;;
    2)   printf '2 (CLI usage error — a flag was malformed or swallowed its argument)' ;;
    124) printf '124 (timeout, GNU convention — only the cursor backend, which uses `timeout`, produces this)' ;;
    126) printf '126 (found but not executable)' ;;
    127) printf '127 (command not found — is `claude` on PATH?)' ;;
    130) printf '130 (SIGINT, 128+2 — what `claude` reports on interrupt)' ;;
    137) printf '137 (SIGKILL, 128+9 — the watchdog gave up waiting)' ;;
    143) printf '143 (SIGTERM, 128+15 — the watchdog stopped it at the timeout)' ;;
    *)
      if [[ "$c" =~ ^[0-9]+$ ]] && [[ "$c" -gt 128 ]]; then
        printf '%s (killed by signal %s)' "$c" "$((c - 128))"
      else
        printf '%s' "$c"
      fi
      ;;
  esac
}

# ralph_agent_record <log-file> <exit-code> <prompt-bytes> <cmd-description>
# Records what the agent run actually did — on EVERY run, not only failures.
#
# The four August data-drills failures left three 0-byte logs and one holding a
# bare `Terminated` line. stderr was already redirected into the transcript, so
# the agent genuinely emitted nothing on either stream — and an empty file is
# indistinguishable from a clean run that happened to print nothing. The exit
# code was the one fact that would have separated "expired auth" from "fine",
# and nothing wrote it down.
#
# So: a `.status` sidecar is written unconditionally (machine-readable, keeps the
# transcript valid stream-json), and a transcript with no result event also gets
# a human diagnostic naming the likely causes, commonest first.
ralph_agent_record() {
  local log="$1" rc="$2" bytes="$3"; shift 3
  local size reason results
  size="$(wc -c <"$log" 2>/dev/null | tr -d ' ')"; size="${size:-0}"
  reason="$(ralph_exit_reason "$rc")"
  results="$(grep -c '"type":"result"' "$log" 2>/dev/null || true)"; results="${results:-0}"

  {
    echo "exit=$rc"
    echo "exit_meaning=$reason"
    echo "transcript_bytes=$size"
    echo "prompt_bytes=$bytes"
    echo "result_events=$results"
    echo "finished=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "claude_path=$(command -v claude 2>/dev/null || echo '<NOT ON PATH>')"
    echo "command=$*"
  } > "${log}.status" 2>/dev/null || true

  [[ "$size" -gt 0 && "$results" -gt 0 ]] && return 0

  # Snapshot the transcript BEFORE the tee starts appending, or the diagnostic
  # quotes itself back and buries the agent's actual last words.
  local tail_txt
  tail_txt="$(tail -c 500 "$log" 2>/dev/null | sed 's/^/    | /')"
  {
    echo ""
    echo "=== ralph diagnostic: the agent produced no result event ==="
    echo "  exit code    : $reason"
    echo "  transcript   : ${size} bytes at $log"
    echo "  status file  : ${log}.status"
    echo "  prompt size  : $bytes bytes"
    echo "  command      : $*"
    echo "  claude onPATH: $(command -v claude 2>/dev/null || echo '<NOT ON PATH>')"
    echo "  last output  :"
    printf '%s\n' "${tail_txt:-    | <the agent wrote nothing on stdout or stderr>}"
    if [[ "$size" -eq 0 ]]; then
      echo "  likely causes, commonest first:"
      echo "    1. EXPIRED AUTH / SESSION — run \`claude\` once interactively and re-login."
      echo "       This is what the four 30 Aug data-drills failures turned out to be:"
      echo "       three 0-byte logs 5s apart, healthy again after a 3 Sep re-login."
      echo "    2. Rate limit or org policy refusing the call before the first token."
      echo "    3. A flag that swallowed the prompt — a greedy option consuming the"
      echo "       positional arg makes the CLI exit 1 before emitting anything."
      echo "    4. The \`claude\` on PATH is a stub or wrapper, not the real CLI."
    fi
    echo "=== end ralph diagnostic ==="
  } | tee -a "$log" >&2
  return 1
}

# ralph_kill_tree <pid> [signal]
# Signals a process AND every descendant, deepest first.
#
# The watchdog used to signal the agent pid alone. `claude` spawns children, and
# an orphan both survives the timeout — still working, still costing — and keeps
# the iteration's log file descriptor open, so anything reading that log blocks
# long after the agent was supposedly killed. Measured with a stub that forks:
# parent reaped in 1.0s, grandchild still running.
#
# Deepest-first so a child cannot be re-parented out of the walk mid-kill.
ralph_kill_tree() {
  local root="$1" sig="${2:-TERM}" child
  for child in $(pgrep -P "$root" 2>/dev/null || true); do
    ralph_kill_tree "$child" "$sig"
  done
  kill -"$sig" "$root" 2>/dev/null || true
}

# ralph_agent_timed_out <marker-file> <exit-status>
# Did the watchdog fire? The MARKER is the authority, not the exit status.
#
# A background job started with `&` in a script runs with job control off, and
# POSIX then makes it IGNORE SIGINT. Measured on this machine: `kill -INT` on
# such a job let a 10-second sleep run to completion and `wait` reported 0. So
# the watchdog's graceful kill was a no-op, only its follow-up SIGKILL landed,
# and that reports 137 — a number the old `-eq 124 || -eq 142` test never
# matched. A real timeout was therefore indistinguishable from an agent that
# simply finished without promising anything: the iteration was accepted as
# ordinary non-completion and the loop kept spending.
#
# The signal statuses are kept as a second signal for the cursor backend, which
# does go through `timeout` and can legitimately produce 124.
ralph_agent_timed_out() {
  [[ -f "$1" ]] && return 0
  case "${2:-0}" in
    124|130|137|142|143) return 0 ;;
  esac
  return 1
}

# ralph_reject_file <state-dir> <key>
# Path of the rejection-budget file for one category/topic/group.
ralph_reject_file() {
  local slug
  slug="$(printf '%s' "$2" | tr -c 'A-Za-z0-9._-' '_')"
  printf '%s/rejects-%s.txt' "$1" "$slug"
}

# ralph_rejects_bump <state-dir> <key>
# Increments and prints the consecutive-rejection count for this run.
#
# The count MUST live outside the process. loop.sh invokes once.sh once per
# iteration with an iteration budget of 1, and once.sh initialises its counter
# at process start — so a shell variable resets every iteration and a 3-strike
# cap silently becomes MAX strikes. Measured: driven through loop.sh,
# ai-engineering printed "COMPLETE rejected (1/3)" eighty times and gave up
# zero times, against a nominal cap of 3.
#
# Keyed by RALPH_RUN_ID so a fresh run starts a fresh budget, and a once.sh run
# by hand is never held to a previous run's strikes.
ralph_rejects_bump() {
  local dir="$1" key="$2" file run stored_run="" n=0
  run="${RALPH_RUN_ID:-standalone-$$}"
  mkdir -p "$dir" 2>/dev/null || true
  file="$(ralph_reject_file "$dir" "$key")"
  if [[ -f "$file" ]]; then
    stored_run="$(sed -n '1p' "$file" 2>/dev/null || true)"
    n="$(sed -n '2p' "$file" 2>/dev/null || true)"
    [[ "$stored_run" == "$run" ]] || n=0
  fi
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  printf '%s\n%s\n' "$run" "$n" > "$file" 2>/dev/null || true
  printf '%s' "$n"
}

# ralph_rejects_clear <state-dir> <key>
ralph_rejects_clear() {
  rm -f "$(ralph_reject_file "$1" "$2")" 2>/dev/null || true
}

# ralph_loop_pause <iteration> <max>
# The gap between loop iterations. Nothing slept before, so a transient failure
# spun at full speed.
ralph_loop_pause() {
  local secs="${RALPH_LOOP_SLEEP:-5}"
  case "$secs" in ''|*[!0-9]*) secs=5 ;; esac
  [[ "$secs" -gt 0 ]] || return 0
  [[ "${1:-0}" -lt "${2:-0}" ]] || return 0
  echo "  (pausing ${secs}s before the next iteration)"
  sleep "$secs"
}

# ralph_queue_file <plan-file>
# The generator's item queue, which lives beside the plan. Empty if there is
# none — the category-shaped tracks have no flat id queue.
ralph_queue_file() {
  local dir f
  dir="$(dirname "$1")"
  for f in concepts.json topics.json problems.json; do
    [[ -f "$dir/$f" ]] && { printf '%s' "$dir/$f"; return 0; }
  done
  printf ''
}

# ralph_queue_ids <queue-json>
# One id per line. Accepts both shapes in use here: a bare list, and a single
# key wrapping a list.
ralph_queue_ids() {
  python3 - "$1" <<'RALPH_PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    lists = [v for v in data.values() if isinstance(v, list)]
    data = lists[0] if len(lists) == 1 else []
for item in data or []:
    if isinstance(item, dict) and item.get("id"):
        print(item["id"])
RALPH_PY
}

# ralph_require_group_complete <problems-json> <group> <output-dir>
# The group-scoped completeness gate, for a track whose plan items are file
# PATHS rather than `<id>.<ext>`.
#
# data-drills queues items as `sql/sql-001-ranking-ties-three-ways.md`, so
# ralph_require_complete's id-shaped branch matches nothing and it falls through
# to its non-empty fallback — which would pass as soon as ANY drill exists, even
# one belonging to a different group. That is how data-drills kept exiting clean
# having produced nothing: `validate.sh <group>` reports `0 OK, 6 SKIP, 0 FAIL`
# and returns 0, and nothing behind it asked whether the group was actually done.
#
# Reads the queue read-only. Sets RALPH_FAIL_LINES. 0 = complete, 1 = not.
ralph_require_group_complete() {
  local problems="$1" group="$2" outdir="$3" out produced total missing
  out="$(python3 - "$problems" "$group" "$outdir" <<'RALPH_PY' 2>/dev/null || true
import json, sys
from pathlib import Path

def bail(msg):
    print("ERR|" + msg)
    raise SystemExit(0)

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    bail("could not read the drill queue: " + sys.argv[1])
if isinstance(data, dict):
    lists = [v for v in data.values() if isinstance(v, list)]
    data = lists[0] if len(lists) == 1 else []
group, outdir = sys.argv[2], Path(sys.argv[3])
items = [p for p in (data or []) if isinstance(p, dict) and p.get("group") == group]
if not items:
    bail("no queued items for group: " + group)
missing = []
for p in items:
    rel = p.get("file") or ""
    path = outdir / rel
    if not rel or not path.is_file() or path.stat().st_size == 0:
        missing.append(rel or p.get("id") or "?")
print("%d|%d|%s" % (len(items) - len(missing), len(items), ",".join(missing[:10])))
RALPH_PY
)"

  if [[ -z "$out" ]]; then
    RALPH_FAIL_LINES="FAIL: could not evaluate group completeness for $group
"
    printf '%s' "$RALPH_FAIL_LINES" >&2
    return 1
  fi
  if [[ "$out" == ERR\|* ]]; then
    RALPH_FAIL_LINES="FAIL: ${out#ERR|}
"
    printf '%s' "$RALPH_FAIL_LINES" >&2
    return 1
  fi

  produced="${out%%|*}"; out="${out#*|}"
  total="${out%%|*}";    missing="${out#*|}"

  if [[ "$produced" == "$total" ]]; then
    RALPH_FAIL_LINES=""
    echo "Completeness: $produced/$total drills present for $group." >&2
    return 0
  fi

  RALPH_FAIL_LINES=""
  local f
  for f in ${missing//,/ }; do
    [[ -n "$f" ]] && RALPH_FAIL_LINES="${RALPH_FAIL_LINES}FAIL: queued drill never produced: $outdir/$f
"
  done
  RALPH_FAIL_LINES="${RALPH_FAIL_LINES}FAIL: $group is incomplete — $produced of $total drills produced
"
  printf '%s' "$RALPH_FAIL_LINES" >&2
  return 1
}

# ralph_require_complete <plan-file> <output-dir> <extension> [extra-dir...]
#
# The end-of-run completeness gate — the thing a per-file validator structurally
# cannot check. Every validate.sh iterates over the files that exist; on an empty
# corpus it iterates over nothing, reports "0 checked, 0 failed" and exits 0. For
# a per-item run on an item nobody has generated yet that is the right answer, a
# legitimate skip. For the FINAL "the loop says it is finished" gate it is a lie:
# a run that produced nothing at all passes.
#
# So the final gate asks a different question — not "is what exists correct" but
# "does everything the plan promised exist". Ids come from the plan, because the
# plan is what the loop claims to have finished.
#
# Sets RALPH_FAIL_LINES. Returns 0 = complete, 1 = empty or partial.
ralph_require_complete() {
  local plan="$1" outdir="$2" ext="${3:-html}"
  local id fails="" n_planned=0 n_missing=0 n_shown=0 n_unqueued=0 found=0 dir queue
  shift 3 2>/dev/null || shift $#
  local -a dirs=("$outdir")
  [[ $# -gt 0 ]] && dirs+=("$@")
  queue="$(ralph_queue_file "$plan")"

  if [[ -f "$plan" ]]; then
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      n_planned=$((n_planned + 1))
      if [[ ! -s "$outdir/$id.$ext" ]]; then
        n_missing=$((n_missing + 1))
        if [[ "$n_shown" -lt 10 ]]; then
          fails="${fails}FAIL: planned item never produced: $outdir/$id.$ext
"
          n_shown=$((n_shown + 1))
        fi
      fi
    done < <(sed -n 's/^- \[[ xX]\] \([0-9][0-9]*-[a-z0-9][a-z0-9-]*\).*/\1/p' "$plan")
  fi

  # The plan is the loop's own record, and a plan that was never re-scaffolded is
  # a smaller universe than the queue it came from: ai-engineering/concepts has
  # 41 planned items against 51 in concepts.json, so "every plan item is checked"
  # was true while ten concepts had never been queued at all.
  if [[ -n "$queue" ]]; then
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      n_unqueued=$((n_unqueued + 1))
      if [[ "$n_unqueued" -le 10 ]]; then
        fails="${fails}FAIL: queued item never entered the plan: $id
"
      fi
    done < <(ralph_queue_ids "$queue" | grep -v -F -x -f <(
      sed -n 's/^- \[[ xX]\] \([0-9][0-9]*-[a-z0-9][a-z0-9-]*\).*/\1/p' "$plan" 2>/dev/null
    ) || true)
  fi

  if [[ "$n_planned" -gt 0 || "$n_unqueued" -gt 0 ]]; then
    if [[ "$n_missing" -eq 0 && "$n_unqueued" -eq 0 ]]; then
      RALPH_FAIL_LINES=""
      echo "Completeness: $n_planned/$n_planned planned items present." >&2
      return 0
    fi
    if [[ "$n_missing" -gt "$n_shown" ]]; then
      fails="${fails}FAIL: ... and $((n_missing - n_shown)) more missing
"
    fi
    if [[ "$n_unqueued" -gt 10 ]]; then
      fails="${fails}FAIL: ... and $((n_unqueued - 10)) more queued items missing from the plan
"
    fi
    fails="${fails}FAIL: corpus is incomplete — $((n_planned - n_missing)) of $((n_planned + n_unqueued)) items produced ($n_missing planned but missing, $n_unqueued never planned)
"
    RALPH_FAIL_LINES="$fails"
    printf '%s' "$fails" >&2
    return 1
  fi

  # No id-shaped plan items — a category-style track, where the plan lists tasks
  # rather than files. The weaker but still binding question: did this produce
  # anything at all?
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r id; do
      [[ -s "$id" ]] || continue
      found=1
      break
    done < <(find "$dir" -type f \( -name '*.md' -o -name '*.html' \) 2>/dev/null)
    [[ "$found" -eq 1 ]] && break
  done

  if [[ "$found" -eq 1 ]]; then
    RALPH_FAIL_LINES=""
    return 0
  fi

  RALPH_FAIL_LINES="FAIL: corpus is EMPTY — ${dirs[*]} produced no files, so there is nothing for validation to have checked
"
  printf '%s' "$RALPH_FAIL_LINES" >&2
  return 1
}

# ralph_feedback <attempt> <max> <validation-fails> <factcheck-notes>
# The correction block appended to the next attempt's prompt.
ralph_feedback() {
  local attempt="$1" max="$2" fails="$3" notes="$4"
  printf '\n%s\n' "━━━ PREVIOUS ATTEMPT REJECTED (attempt $attempt of $max) ━━━"
  printf '%s\n' "Your previous attempt at this item was NOT accepted. Fix exactly these"
  printf '%s\n' "problems and regenerate the file. Do not mark the plan item done, and do"
  printf '%s\n' "not emit a COMPLETE promise, until every one of them is resolved."
  if [[ -n "$fails" ]]; then
    printf '\n%s\n%s\n' "Automated validation failures:" "$fails"
  fi
  if [[ -n "$notes" ]]; then
    printf '\n%s\n%s\n' "An independent fact-check of the finished file found incorrect claims:" "$notes"
    printf '%s\n' "Correct the underlying facts — do not merely reword them."
  fi
  printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
