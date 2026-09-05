#!/usr/bin/env bash
set -euo pipefail

# Usage: bash ralph-data-drills/validate.sh <group-slug>
# Example: bash ralph-data-drills/validate.sh sql-01-window-functions
#
# Reads ralph-data-drills/problems.json, filters to <group-slug>, and validates
# every problem in that group per ralph-data-drills' interface contract:
#   sections + hint ladder + placeholders + required fenced blocks, then
#   real EXECUTION -- sqlite3 for family=sql, a sandboxed Monte Carlo subprocess
#   for family=stats.
#
# Exit 0 only when there are zero FAILs. FAIL lines go to stderr in the shape
# ralph-common.sh's ralph_validate greps for: ^[[:space:]]*FAIL[: ]
#
# Test hooks (optional, default to the real repo paths):
#   RALPH_DD_PROBLEMS=<path to problems.json>
#   RALPH_DD_OUT=<path to the data-drills output dir>

GROUP="${1:?Usage: $0 <group-slug>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBLEMS="${RALPH_DD_PROBLEMS:-$SCRIPT_DIR/problems.json}"
DRILLS="${RALPH_DD_OUT:-$PREP_ROOT/data-drills}"
SANDBOX_LIB="$PREP_ROOT/ralph-lib"
MC_MEM_MB="${RALPH_DD_MEM_MB:-2048}"

# Monte Carlo simulations are model-written Python, so they run under the
# shared containment launcher that ralph-ml-coding also uses. One copy, so the
# two tracks cannot drift apart. Missing launcher = environment fault, and we
# stop rather than fall back to running untrusted code uncontained.
if [[ ! -f "$SANDBOX_LIB/ralph_sandbox.py" ]]; then
  echo "ERROR: ralph-lib/ralph_sandbox.py is missing — refusing to execute" >&2
  echo "model-written simulations without containment. Restore it and re-run." >&2
  exit 2
fi

python3 - "$GROUP" "$PROBLEMS" "$DRILLS" "$SANDBOX_LIB" "$MC_MEM_MB" <<'PY'
import csv
import io
import json
import math
import os
import re
import sqlite3
import sys
from pathlib import Path

group_slug, problems_path, drills_root, sandbox_lib, mc_mem_mb = sys.argv[1:6]
drills = Path(drills_root)
mc_mem_mb = int(mc_mem_mb)

sys.path.insert(0, sandbox_lib)
import ralph_sandbox

GROUPS = [
    "sql-01-window-functions",
    "sql-02-joins-and-nulls",
    "sql-03-aggregation-grouping",
    "sql-04-ctes-and-recursion",
    "sql-05-time-and-cohorts",
    "sql-06-modeling-and-performance",
    "stats-01-probability-puzzles",
    "stats-02-expectation-and-counting",
    "stats-03-markov-and-processes",
    "stats-04-distributions-and-estimation",
    "stats-05-inference-and-testing",
    "stats-06-bias-and-reasoning",
]

SQL_SECTIONS = [
    "## Schema", "## Question", "## Hints", "## Solution",
    "## Expected Result", "## Common Wrong Answer", "## Why It Is Wrong",
]
STATS_SECTIONS = ["## Question", "## Hints", "## Worked Solution", "## Answer"]

SQL_BLOCKS = ["schema", "solution", "expected", "wrong"]
STATS_BLOCKS = ["answer"]

FORBIDDEN_IMPORTS = ("numpy", "scipy", "pandas")
NUM_TOL = 1e-6
# Overridable like ml-coding's RALPH_ML_EXEC_TIMEOUT — same shared sandbox,
# same need (a correct simulation with more trials can legitimately be slow).
MC_TIMEOUT = int(os.environ.get("RALPH_DD_EXEC_TIMEOUT", "20"))

# Exact contract regexes for machine-extractable fenced blocks.
BLOCK_OPEN = re.compile(r"^```([a-z]+) id=([a-z_]+)\s*$")
BLOCK_CLOSE = re.compile(r"^```\s*$")

errors = []      # FAIL lines
ok = []          # OK lines
skips = []       # SKIP lines (missing .md)
skip_execs = []  # SKIP-EXEC lines (non-sqlite dialect)


def fail(msg):
    errors.append(msg)


def pass_(msg):
    ok.append(msg)


# ---------------------------------------------------------------- block parse

def extract_blocks(text):
    """Line-driven fence state machine.

    Returns (blocks, problems) where blocks maps id -> {"lang","body","line"}
    and problems is a list of structural complaints (duplicate id,
    unterminated fence). Anonymous fences (``` or ```lang with no id=) are
    consumed so their contents can never be mistaken for a block body.
    """
    blocks = {}
    issues = []
    open_id = None      # None when outside an id-tagged block
    open_lang = ""
    open_line = 0
    anon = False
    body = []
    for lineno, line in enumerate(text.splitlines(), 1):
        line = line.rstrip("\r")
        if open_id is None and not anon:
            m = BLOCK_OPEN.match(line)
            if m:
                open_lang, open_id = m.group(1), m.group(2)
                open_line = lineno
                body = []
                continue
            if line.startswith("```"):
                anon = True
                open_line = lineno
            continue
        if BLOCK_CLOSE.match(line):
            if anon:
                anon = False
            else:
                if open_id in blocks:
                    issues.append(
                        "duplicate block id=%s (lines %d and %d)"
                        % (open_id, blocks[open_id]["line"], open_line)
                    )
                else:
                    blocks[open_id] = {
                        "lang": open_lang,
                        "body": "\n".join(body),
                        "line": open_line,
                    }
                open_id = None
                body = []
            continue
        if open_id is not None:
            body.append(line)
    if open_id is not None:
        issues.append("unterminated fence for id=%s opened at line %d" % (open_id, open_line))
    elif anon:
        issues.append("unterminated code fence opened at line %d" % open_line)
    return blocks, issues


def require_blocks(pid, blocks, needed):
    """True iff every needed id is present and non-empty."""
    good = True
    for bid in needed:
        if bid not in blocks:
            fail("%s missing required block id=%s" % (pid, bid))
            good = False
        elif not blocks[bid]["body"].strip():
            fail("%s block id=%s is empty" % (pid, bid))
            good = False
    return good


# ------------------------------------------------------------ markdown checks

def check_sections(pid, text, required):
    for sec in required:
        if not re.search(r"^%s\s*$" % re.escape(sec), text, re.M):
            fail("%s missing section: %s" % (pid, sec))


def check_placeholders(pid, text):
    if "<!--" in text:
        m = re.search(r"<!--(.*?)-->", text, re.S) or re.search(r"<!--(.{0,60})", text, re.S)
        frag = " ".join(m.group(1).split())[:60] if m else ""
        fail("%s still contains an unfilled template placeholder: <!-- %s ... -->"
             % (pid, frag))


def check_hint_ladder(pid, text):
    m = re.search(r"^## Hints\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        return  # missing-section check already reported it
    ordered = re.findall(r"^\s{0,3}\d+[.)]\s+\S", m.group(1), re.M)
    if len(ordered) < 3:
        fail("%s hint ladder has %d ordered item(s), needs >= 3" % (pid, len(ordered)))


# ----------------------------------------------------------------- sql checks

def strip_sql_noise(sql):
    """Remove string literals and comments so ';' can be counted safely."""
    out = []
    i = 0
    n = len(sql)
    while i < n:
        c = sql[i]
        if c == "'":
            i += 1
            while i < n:
                if sql[i] == "'":
                    if i + 1 < n and sql[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue
        if c == '"':
            i += 1
            while i < n and sql[i] != '"':
                i += 1
            i += 1
            continue
        if c == "-" and sql[i:i + 2] == "--":
            while i < n and sql[i] != "\n":
                i += 1
            continue
        if c == "/" and sql[i:i + 2] == "/*":
            end = sql.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def single_statement(sql):
    return strip_sql_noise(sql).strip().rstrip(";").count(";") == 0


def as_number(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        s = value.strip()
        if not s:
            return None
        try:
            return float(s)
        except ValueError:
            return None
    return None


def cell_repr(value):
    if value is None:
        return "NULL"
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


def cells_match(expected, actual):
    """expected is a CSV string; actual is whatever sqlite returned."""
    exp = expected.strip()
    if actual is None:
        return exp == "" or exp.upper() == "NULL"
    en, an = as_number(exp), as_number(actual)
    if en is not None and an is not None:
        if math.isnan(en) or math.isnan(an):
            return math.isnan(en) and math.isnan(an)
        return abs(en - an) <= NUM_TOL or abs(en - an) <= NUM_TOL * max(abs(en), abs(an))
    return exp == cell_repr(actual).strip()


def parse_expected_csv(pid, body):
    try:
        rows = [r for r in csv.reader(io.StringIO(body.strip("\n")))]
    except csv.Error as exc:
        fail("%s id=expected is not parseable CSV: %s" % (pid, exc))
        return None, None
    rows = [r for r in rows if any(c.strip() for c in r) or len(r) > 1]
    if not rows:
        fail("%s id=expected has no header row" % pid)
        return None, None
    return [c.strip() for c in rows[0]], rows[1:]


def compare_result(desc, rows, exp_header, exp_rows):
    """Return a list of human-readable differences (empty == identical)."""
    diffs = []
    act_header = [d[0] for d in (desc or [])]
    if len(act_header) != len(exp_header):
        diffs.append("column count %d != expected %d (got %s, expected %s)"
                     % (len(act_header), len(exp_header),
                        ",".join(act_header) or "<none>", ",".join(exp_header)))
        return diffs
    for i, (a, e) in enumerate(zip(act_header, exp_header)):
        if a.strip().casefold() != e.strip().casefold():
            diffs.append("column %d named %r, expected %r" % (i + 1, a, e))
    if len(rows) != len(exp_rows):
        diffs.append("returned %d row(s), expected %d" % (len(rows), len(exp_rows)))
        return diffs
    for r, (arow, erow) in enumerate(zip(rows, exp_rows), 1):
        if len(erow) != len(exp_header):
            diffs.append("expected CSV row %d has %d field(s), header has %d"
                         % (r, len(erow), len(exp_header)))
            continue
        for c in range(len(exp_header)):
            if not cells_match(erow[c], arow[c]):
                diffs.append("row %d col %r: got %r, expected %r"
                             % (r, exp_header[c], cell_repr(arow[c]), erow[c].strip()))
    return diffs


def run_sql(pid, blocks):
    exp_header, exp_rows = parse_expected_csv(pid, blocks["expected"]["body"])
    if exp_header is None:
        return False
    for bid in ("solution", "wrong"):
        if not single_statement(blocks[bid]["body"]):
            fail("%s id=%s must be exactly ONE statement" % (pid, bid))
            return False
    conn = None
    try:
        conn = sqlite3.connect(":memory:")
        try:
            conn.executescript(blocks["schema"]["body"])
        except (sqlite3.Error, sqlite3.Warning) as exc:
            fail("%s schema failed to execute: %s" % (pid, exc))
            return False
        try:
            cur = conn.execute(blocks["solution"]["body"])
            sol_desc, sol_rows = cur.description, cur.fetchall()
        except (sqlite3.Error, sqlite3.Warning) as exc:
            fail("%s solution failed to execute: %s" % (pid, exc))
            return False
        diffs = compare_result(sol_desc, sol_rows, exp_header, exp_rows)
        if diffs:
            for d in diffs[:6]:
                fail("%s solution result != id=expected: %s" % (pid, d))
            if len(diffs) > 6:
                fail("%s solution result != id=expected: ...and %d more difference(s)"
                     % (pid, len(diffs) - 6))
            return False
        try:
            cur = conn.execute(blocks["wrong"]["body"])
            wrong_desc, wrong_rows = cur.description, cur.fetchall()
        except (sqlite3.Error, sqlite3.Warning) as exc:
            fail("%s wrong failed to execute: %s" % (pid, exc))
            return False
        if not compare_result(wrong_desc, wrong_rows, exp_header, exp_rows):
            fail("%s id=wrong returns the SAME result as id=expected -- "
                 "the 'common wrong answer' is not actually wrong" % pid)
            return False
    except MemoryError:
        raise
    except Exception as exc:  # never let sqlite surprise us with a traceback
        fail("%s SQL execution raised %s: %s" % (pid, type(exc).__name__, exc))
        return False
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass
    return True


# --------------------------------------------------------------- stats checks

def parse_answer(pid, body):
    text = body.strip()
    last = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not last:
        fail("%s id=answer is empty" % pid)
        return None
    try:
        value = float(last[-1])
    except ValueError:
        fail("%s id=answer %r does not parse as a bare number" % (pid, last[-1]))
        return None
    if not math.isfinite(value):
        fail("%s id=answer is not finite (%r)" % (pid, last[-1]))
        return None
    return value


def check_forbidden_imports(pid, code):
    hits = []
    for mod in FORBIDDEN_IMPORTS:
        # `import random, numpy as np` put the forbidden name after a comma, where
        # `^\s*import\s+numpy` never looked — it was caught only by the child
        # crashing on a machine that happens to lack numpy, which is luck, not a gate.
        if re.search(r"^[ \t]*import[ \t]+[\w.,\s]*\b%s\b" % mod, code, re.M) or \
           re.search(r"^[ \t]*from[ \t]+%s\b" % mod, code, re.M) or \
           re.search(r"import_module\(\s*['\"]%s" % mod, code) or \
           re.search(r"__import__\(\s*['\"]%s" % mod, code):
            hits.append(mod)
    if hits:
        fail("%s id=simulation imports forbidden module(s): %s (stdlib only)"
             % (pid, ", ".join(hits)))
        return False
    return True


def run_simulation(pid, code, label="Monte Carlo simulation"):
    """Run the sim under the shared containment launcher, hard 20s timeout.

    Simulations are written by a model, so they get the same treatment as the
    ml-coding track's solutions: isolated interpreter, allowlisted environment
    (the child cannot read this process's tokens), no network, no writes outside
    its own sandbox directory, a resident-memory cap, and a timeout that kills
    the process group rather than only the direct child. See
    ralph-lib/ralph_sandbox.py.
    """
    result = ralph_sandbox.run(sys.executable, code, MC_TIMEOUT,
                               filename="simulation.py", memory_mb=mc_mem_mb)
    if result.start_error:
        fail("%s could not start the simulation subprocess: %s"
             % (pid, result.start_error))
        return None
    if result.memory_exceeded:
        fail("%s %s exceeded the %d MB memory cap (peak RSS %s MB) and was killed"
             % (pid, label, mc_mem_mb, result.peak_rss_mb))
        return None
    if result.timed_out:
        fail("%s %s exceeded the %ds timeout and its whole process group was killed"
             % (pid, label, MC_TIMEOUT))
        return None
    if result.returncode != 0:
        tail = " | ".join(result.stderr.strip().splitlines()[-2:]) or "no stderr"
        fail("%s %s crashed (exit %s): %s" % (pid, label, result.returncode, tail))
        return None
    lines = [ln.strip() for ln in result.stdout.splitlines() if ln.strip()]
    if not lines:
        fail("%s %s printed nothing on stdout (last line must be the bare estimate)"
             % (pid, label))
        return None
    try:
        value = float(lines[-1])
    except ValueError:
        fail("%s %s last stdout line %r does not parse as a float"
             % (pid, label, lines[-1]))
        return None
    if not math.isfinite(value):
        fail("%s %s estimate is not finite (%r)" % (pid, label, lines[-1]))
        return None
    return value


# A simulation has to sample. `print(0.333333)` agreed with the analytic answer
# to six decimals and passed, because the check compared numbers and never asked
# where the number came from — the file contained no `random` at all.
SEEDS_RNG = re.compile(r'\brandom\s*\.\s*(?:seed|Random)\s*\(')
USES_RNG = re.compile(r'\brandom\s*\.\s*(?!seed\b|Random\b)\w+\s*\(')

# Re-seeding prelude for the second run. The simulation seeds itself for
# reproducibility, so to resample we intercept the seed it asks for rather than
# editing its source: same code, different stream.
RESEED_PRELUDE = """import random as _r
_ralph_seed, _ralph_Random = _r.seed, _r.Random
_RALPH_SALT = 0x5EED


def _ralph_reseed(a=None, *rest, **kw):
    return _ralph_seed((a ^ _RALPH_SALT) if isinstance(a, int) else a, *rest, **kw)


class _RalphRandom(_ralph_Random):
    def __init__(self, x=None):
        _ralph_Random.__init__(self, (x ^ _RALPH_SALT) if isinstance(x, int) else x)


_r.seed = _ralph_reseed
_r.Random = _RalphRandom
"""


def check_simulation_is_a_simulation(pid, code):
    """Static half of the method check: does this block sample at all?"""
    ok = True
    if not SEEDS_RNG.search(code):
        fail("%s id=simulation never calls random.seed(...) or random.Random(...) "
             "— a simulation must seed deterministically" % pid)
        ok = False
    if not USES_RNG.search(code):
        fail("%s id=simulation seeds a generator but never draws from it — "
             "there is no sampling here, only a printed constant" % pid)
        ok = False
    return ok


def check_monte_carlo(pid, prob, blocks, analytic):
    tol = prob.get("mc_tolerance")
    kind = prob.get("mc_tolerance_kind")
    bad = False
    if not isinstance(tol, (int, float)) or isinstance(tol, bool) or tol <= 0:
        fail("%s mc is true but mc_tolerance is missing or not a positive number (%r)"
             % (pid, tol))
        bad = True
    if kind not in ("abs", "rel"):
        fail("%s mc is true but mc_tolerance_kind must be 'abs' or 'rel' (got %r)"
             % (pid, kind))
        bad = True
    code = blocks["simulation"]["body"]
    if not check_forbidden_imports(pid, code):
        return False
    if bad:
        return False
    if analytic is None:
        return False
    if not check_simulation_is_a_simulation(pid, code):
        return False
    empirical = run_simulation(pid, code)
    if empirical is None:
        return False
    diff = abs(empirical - analytic)
    limit = tol if kind == "abs" else tol * abs(analytic)
    if diff > limit:
        fail("%s Monte Carlo %.6g vs analytic %.6g (|diff| %.6g > %s tol %.6g)"
             % (pid, empirical, analytic, diff, kind, limit))
        return False

    # Second run on a different stream. A real simulation moves — a little — and
    # still lands inside tolerance; a rigged one returns the identical number
    # because nothing it does depends on the seed. Both halves are required:
    # "differs" alone would pass a random number generator, "in tolerance" alone
    # is what let the constant through.
    resampled = run_simulation(pid, RESEED_PRELUDE + "\n" + code,
                               label="re-seeded Monte Carlo")
    if resampled is None:
        return False
    if resampled == empirical:
        fail("%s id=simulation returns the identical estimate %.6g under a "
             "different seed — it is not sampling, it is printing a constant "
             "(or ignoring its own seed)" % (pid, empirical))
        return False
    diff2 = abs(resampled - analytic)
    if diff2 > limit:
        fail("%s re-seeded Monte Carlo %.6g vs analytic %.6g (|diff| %.6g > %s "
             "tol %.6g) — the estimate agreed on one seed only, so the agreement "
             "was luck or tuning, not convergence"
             % (pid, resampled, analytic, diff2, kind, limit))
        return False

    pass_("%s Monte Carlo %.6g vs analytic %.6g (|diff| %.6g <= %s tol %.6g); "
          "re-seeded %.6g (|diff| %.6g)"
          % (pid, empirical, analytic, diff, kind, limit, resampled, diff2))
    return True


# ------------------------------------------------------------------ main loop

def load_problems():
    path = Path(problems_path)
    if not path.exists():
        print("validate: FAILED for %s" % group_slug, file=sys.stderr)
        print("  FAIL: problems.json not found at %s" % path, file=sys.stderr)
        sys.exit(1)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        print("validate: FAILED for %s" % group_slug, file=sys.stderr)
        print("  FAIL: problems.json is unreadable (%s): %s"
              % (type(exc).__name__, exc), file=sys.stderr)
        sys.exit(1)
    if not isinstance(data, list):
        print("validate: FAILED for %s" % group_slug, file=sys.stderr)
        print("  FAIL: problems.json top level must be a JSON array, got %s"
              % type(data).__name__, file=sys.stderr)
        sys.exit(1)
    return data


def validate_problem(prob):
    pid = prob.get("id") or "<no id>"
    family = prob.get("family")
    rel = prob.get("file")
    if family not in ("sql", "stats"):
        fail("%s has invalid family %r (must be 'sql' or 'stats')" % (pid, family))
        return
    if not isinstance(rel, str) or not rel.strip():
        fail("%s has a missing or non-string 'file' field" % pid)
        return
    path = drills / rel
    if not path.exists():
        skips.append("%s not generated yet (%s)" % (pid, rel))
        return
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        fail("%s cannot read %s: %s" % (pid, rel, exc))
        return

    check_sections(pid, text, SQL_SECTIONS if family == "sql" else STATS_SECTIONS)
    check_placeholders(pid, text)
    check_hint_ladder(pid, text)

    mc = bool(prob.get("mc")) if family == "stats" else False
    if family == "stats" and mc and not re.search(r"^## Simulation\s*$", text, re.M):
        fail("%s mc is true but the file has no '## Simulation' section" % pid)

    try:
        blocks, issues = extract_blocks(text)
    except Exception as exc:
        fail("%s could not be parsed for fenced blocks (%s): %s"
             % (pid, type(exc).__name__, exc))
        return
    for issue in issues:
        fail("%s %s" % (pid, issue))

    needed = list(SQL_BLOCKS) if family == "sql" else list(STATS_BLOCKS)
    if mc:
        needed.append("simulation")
    have_blocks = require_blocks(pid, blocks, needed)

    if family == "sql":
        dialect = prob.get("dialect") or "sqlite"
        if dialect != "sqlite":
            reason = prob.get("skip_exec_reason")
            if not isinstance(reason, str) or not reason.strip():
                fail("%s has dialect=%s but no non-empty skip_exec_reason" % (pid, dialect))
            else:
                skip_execs.append("SKIP-EXEC %s (dialect=%s): %s"
                                  % (pid, dialect, reason.strip()))
            return
        if not issues and have_blocks and run_sql(pid, blocks):
            pass_("%s SQL executes and matches id=expected; id=wrong really differs" % pid)
        return

    # family == stats
    analytic = parse_answer(pid, blocks["answer"]["body"]) if "answer" in blocks else None
    if not mc:
        if analytic is not None:
            pass_("%s analytic answer parses (%.6g)" % (pid, analytic))
        return
    if issues or not have_blocks:
        return
    check_monte_carlo(pid, prob, blocks, analytic)


def main():
    if group_slug not in GROUPS:
        print("validate: FAILED for %s" % group_slug, file=sys.stderr)
        print("  FAIL: unknown group slug %r (expected one of: %s)"
              % (group_slug, ", ".join(GROUPS)), file=sys.stderr)
        sys.exit(1)
    data = load_problems()
    selected = []
    for idx, prob in enumerate(data):
        if not isinstance(prob, dict):
            fail("problems.json entry #%d is %s, expected an object"
                 % (idx, type(prob).__name__))
            continue
        if prob.get("group") == group_slug:
            selected.append(prob)
    if not selected and not errors:
        print("validate: FAILED for %s" % group_slug, file=sys.stderr)
        print("  FAIL: no problems in problems.json for group %s" % group_slug,
              file=sys.stderr)
        sys.exit(1)

    for prob in selected:
        try:
            validate_problem(prob)
        except Exception as exc:  # a bad .md must never produce a traceback
            fail("%s validation raised %s: %s"
                 % (prob.get("id", "<no id>"), type(exc).__name__, exc))

    summary = "summary: %d OK, %d SKIP, %d SKIP-EXEC, %d FAIL" % (
        len(ok), len(skips), len(skip_execs), len(errors))

    for line in skip_execs:
        print("  " + line)

    if not errors:
        print("validate: ALL PASSED for %s" % group_slug)
        for msg in ok:
            print("  OK: %s" % msg)
        for msg in skips:
            print("  SKIP: %s" % msg)
        print(summary)
        sys.exit(0)

    for msg in ok:
        print("  OK: %s" % msg)
    for msg in skips:
        print("  SKIP: %s" % msg)
    print(summary)
    sys.stdout.flush()
    print("validate: FAILED for %s (%d FAIL)" % (group_slug, len(errors)), file=sys.stderr)
    for msg in errors:
        print("  FAIL: %s" % msg, file=sys.stderr)
    sys.exit(1)


main()
PY
