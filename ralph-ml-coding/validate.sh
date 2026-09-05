#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-ml-coding/validate.sh [problem-id]
# Without argument: validates all generated problems.
# With argument: validates one problem (e.g. 15-kmeans).
#
# This validator EXECUTES the Python in each problem file. A solution that does
# not run, or whose self-test does not pass, fails the problem. That is the
# point of this track: plausible-looking ML code that does not run is worse than
# useless for interview prep.
#
# Exit 0 = pass
#      1 = at least one FAIL
#      2 = cannot execute (no Python with numpy) — an environment problem, not
#          a content problem. Callers must not retry the agent on this.
#
# Callers MUST honour the exit code — never `|| true` this script.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBLEMS_DIR="$PREP_ROOT/ml-coding"
PROBLEMS_JSON="$SCRIPT_DIR/problems.json"

TARGET="${1:-all}"
EXEC_TIMEOUT="${RALPH_ML_EXEC_TIMEOUT:-60}"
# Resident-memory ceiling for the code under test. See ralph-lib/ralph_sandbox.py.
EXEC_MEM_MB="${RALPH_ML_MEM_MB:-2048}"
SANDBOX_LIB="$PREP_ROOT/ralph-lib"

# This validator exists to execute code a model wrote, so it runs that code
# under the shared containment launcher rather than a bare subprocess. If the
# launcher is missing we stop: running untrusted code uncontained is worse than
# not validating it, and a missing library is an environment fault (exit 2), not
# something the agent can fix by rewriting the problem.
if [[ ! -f "$SANDBOX_LIB/ralph_sandbox.py" ]]; then
  cat >&2 <<MSG

ERROR: ralph-lib/ralph_sandbox.py is missing.

ralph-ml-coding executes model-written Python. It will not do that without the
shared containment launcher (isolated interpreter, scrubbed environment, no
network, no writes outside the sandbox dir, memory cap, process-group kill).
Restore $SANDBOX_LIB/ralph_sandbox.py and re-run.

MSG
  exit 2
fi

# ── Find a Python that can actually run the solutions ────────────────────────
# Order: explicit override, repo venv, then PATH. numpy is the hard requirement;
# sklearn is optional and only ever used inside a self-test as a cross-check.
find_python() {
  local candidates=()
  [[ -n "${RALPH_ML_PYTHON:-}" ]] && candidates+=("$RALPH_ML_PYTHON")
  candidates+=("$PREP_ROOT/venv/bin/python3" "$PREP_ROOT/venv/bin/python")
  candidates+=(python3 python)
  local c resolved
  for c in "${candidates[@]}"; do
    resolved="$(command -v "$c" 2>/dev/null || true)"
    [[ -n "$resolved" ]] || continue
    if "$resolved" -c "import numpy" >/dev/null 2>&1; then
      printf '%s' "$resolved"
      return 0
    fi
  done
  return 1
}

if ! PYBIN="$(find_python)"; then
  cat >&2 <<'MSG'

ERROR: ralph-ml-coding cannot run solutions — no Python with numpy was found.

This track validates by EXECUTING each problem's reference solution against its
self-test, so an interpreter with numpy is mandatory. Tried, in order:
  $RALPH_ML_PYTHON, ./venv/bin/python3, ./venv/bin/python, python3, python

To fix, from the repo root:

  python3 -m venv venv
  ./venv/bin/python3 -m pip install --upgrade pip
  ./venv/bin/python3 -m pip install numpy scikit-learn

(scikit-learn is optional — it is only used inside self-tests as a cross-check
oracle, never in a solution.) Or point at an existing interpreter:

  RALPH_ML_PYTHON=/path/to/python3 ./ralph-ml-coding/validate.sh

MSG
  exit 2
fi

HAS_SKLEARN=0
"$PYBIN" -c "import sklearn" >/dev/null 2>&1 && HAS_SKLEARN=1

python3 - "$TARGET" "$PROBLEMS_DIR" "$PROBLEMS_JSON" "$PYBIN" "$EXEC_TIMEOUT" "$HAS_SKLEARN" "$SANDBOX_LIB" "$EXEC_MEM_MB" <<'PY'
import json
import re
import sys
from pathlib import Path

(target, problems_dir_str, problems_json_path, pybin, timeout_s, has_sklearn,
 sandbox_lib, mem_cap_mb) = sys.argv[1:9]
problems_dir = Path(problems_dir_str)
problems = json.loads(Path(problems_json_path).read_text())
timeout_s = int(timeout_s)
mem_cap_mb = int(mem_cap_mb)
has_sklearn = has_sklearn == "1"

sys.path.insert(0, sandbox_lib)
import ralph_sandbox

if target != "all":
    problems = [p for p in problems if p["id"] == target or p["slug"] == target]
    if not problems:
        print(f"Unknown problem: {target}", file=sys.stderr)
        sys.exit(1)

REQUIRED_SECTIONS = [
    "## Problem",
    "## Hints",
    "## Solution",
    "## Self-test",
    "## Complexity",
    "## Follow-ups",
]

PLACEHOLDER_PATTERNS = [
    r'\bTODO\b',
    r'\bPLACEHOLDER\b',
    r'Lorem ipsum',
    r'coming soon',
    r'<!--[^>]*\b(?:TODO|FIXME|XXX|FILL IN|REPLACE ME|PLACEHOLDER)\b',
]

# Prose floor by depth — code blocks are excluded from the count, so this
# measures explanation, not solution length.
DEFAULT_FLOOR = 250
DEPTH_FLOORS = {"intro": 200, "core": 350, "advanced": 500}

MIN_HINTS = 3
MIN_HINT_WORDS = 4          # a <details> body shorter than this is a stub, not a hint
MIN_ASSERTS = 2

# Asserts that hold no matter what the solution does. A self-test built only from
# these verifies nothing, which is how `assert True` satisfied the oracle check.
TRIVIAL_ASSERT = re.compile(
    r"^(?:True|1|-?\d+(?:\.\d+)?"
    r"|\w+\s+is\s+not\s+None"
    r"|\w+(?:\.\w+)*)\s*(?:,.*)?$")

TITLE_STOPWORDS = {
    "a", "an", "and", "for", "from", "how", "in", "its", "of", "or", "the", "to",
    "via", "when", "where", "which", "who", "why", "with", "implement", "using",
    "scratch", "your", "own",
}


def section(md, heading):
    """Text of one `## Heading` block, up to the next `## `."""
    m = re.search(rf'^{re.escape(heading)}\b(.*?)(?=^## |\Z)', md,
                  re.DOTALL | re.MULTILINE)
    return m.group(1) if m else ""


def code_blocks(text, lang="python"):
    return re.findall(rf'```{lang}\s*\n(.*?)```', text, re.DOTALL)


def strip_code(md):
    return re.sub(r'```.*?```', ' ', md, flags=re.DOTALL)


def flatten(text):
    return re.sub(r'[^a-z0-9]', '', text.lower())


SUFFIXES = ("ization", "isation", "ations", "ation", "ing", "ies", "es", "s")


def stem(token):
    t = token.lower()
    for suf in SUFFIXES:
        if t.endswith(suf) and len(t) - len(suf) >= 3:
            return t[: len(t) - len(suf)]
    return t


ATOMIC_SLASH = re.compile(r'\b([A-Za-z0-9]{1,3})/([A-Za-z0-9]{1,3})\b')


def split_slash(fragment):
    protected = ATOMIC_SLASH.sub('\\1\x00\\2', fragment)
    parts = [p.strip().replace('\x00', '/') for p in protected.split('/')]
    parts = [p for p in parts if p]
    if len(parts) > 1 and all(len(p) >= 2 for p in parts):
        return parts
    return [fragment]


def title_terms(title):
    """Co-equal things a compound title promises to implement."""
    source = re.sub(r'\([^)]*\)', ' ', title).rsplit(':', 1)[-1]
    fragments = re.split(r'(?i)\s+vs\.?\s+|&|,|\band\b', source)
    fragments = [p for frag in fragments for p in split_slash(frag)]
    terms = []
    for frag in fragments:
        frag = frag.strip(' .:-')
        tokens = [t for t in re.split(r'[^A-Za-z0-9]+', frag) if t]
        if [t for t in tokens if len(t) >= 2 and t.lower() not in TITLE_STOPWORDS]:
            terms.append(frag)
    return terms


def term_tokens(term):
    return [t for t in re.split(r'[^A-Za-z0-9]+', term)
            if t and t.lower() not in TITLE_STOPWORDS]


def shared_stems(terms):
    sets = [{stem(t) for t in term_tokens(term)} for term in terms]
    sets = [s for s in sets if s]
    if len(sets) < 2:
        return set()
    return set.intersection(*sets)


def term_in(term, blob, ignore=frozenset()):
    if flatten(term) and flatten(term) in blob:
        return True
    candidates = [stem(t) for t in term_tokens(term) if stem(t) not in ignore]
    if not candidates:
        candidates = [stem(t) for t in term_tokens(term)]
    return any(c and c in blob for c in candidates)


# ── io_contract parsing ──────────────────────────────────────────────────────
# Contracts come in two shapes, and both may name more than one thing:
#
#   fit_ridge(X, y, lam) -> tuple[...]
#   build_kdtree(X) -> KDNode and knn_query(tree, q, k) -> tuple[...]
#   class DecisionTree(max_depth, ...) with fit(X, y) -> None and predict(X) -> ...
#   class TfidfVectorizer with fit(corpus) -> None, transform(corpus) -> ... and a
#     vocabulary_ dict[str, int] attribute
#
# The old gate was `re.match(r'\s*([A-Za-z_]\w*)\s*\(', contract)`, which on a
# class-form contract matched the word `class`, then demanded `(` and found a
# space — so it returned None, the check was skipped, and the problem was
# reported OK with no gate and no message. Seven of the 32 entries are class
# form. It also only ever checked the FIRST name, so a contract promising two
# functions was half-enforced.

CLASS_HEAD = re.compile(r'^\s*class\s+([A-Za-z_]\w*)')
# 'and a vocabulary_ dict[str, int] attribute' — a named attribute, not a method.
CONTRACT_ATTRIBUTE = re.compile(
    r'\b(?:a|an)\s+([A-Za-z_]\w*)\b(?=.{0,60}?\battributes?\b)')


def top_level_calls(text):
    """Identifiers followed by '(' at paren depth 0.

    Depth matters: it keeps annotations inside an argument list from being read
    as things the solution must define.
    """
    names, depth = [], 0
    for i, ch in enumerate(text):
        if ch == '(':
            if depth == 0:
                m = re.search(r'([A-Za-z_]\w*)\s*$', text[:i])
                if m:
                    names.append(m.group(1))
            depth += 1
        elif ch == ')':
            depth = max(0, depth - 1)
    return names


def parse_io_contract(contract):
    """What the solution must define. None means the contract is unparseable."""
    text = contract.split('#')[0].strip()
    if not text:
        return None
    attributes = CONTRACT_ATTRIBUTE.findall(text)
    calls = top_level_calls(text)
    cls = CLASS_HEAD.match(text)
    if cls:
        name = cls.group(1)
        methods = [c for c in calls if c != name]
        if not methods and not attributes:
            return None
        return {"cls": name, "functions": [], "methods": methods,
                "attributes": attributes}
    if not calls:
        return None
    return {"cls": None, "functions": calls, "methods": [],
            "attributes": attributes}


def contract_violations(required, solution):
    """Every name the contract promises that the solution never defines."""
    missing = []
    if required["cls"] and not re.search(
            rf'\bclass\s+{re.escape(required["cls"])}\b', solution):
        missing.append(f"`class {required['cls']}`")
    for fn in required["functions"]:
        if not re.search(rf'\bdef\s+{re.escape(fn)}\s*\(', solution):
            missing.append(f"`def {fn}(...)`")
    for method in required["methods"]:
        if not re.search(rf'\bdef\s+{re.escape(method)}\s*\(', solution):
            missing.append(f"`def {method}(...)`")
    for attr in required["attributes"]:
        if not re.search(rf'\b{re.escape(attr)}\b', solution):
            missing.append(f"attribute `{attr}`")
    return missing


def build_source(solution, selftest, sabotage=""):
    """Solution, then optional sabotage stubs, then the self-test."""
    parts = ["# --- solution (extracted from ## Solution) ---", solution]
    if sabotage:
        parts += ["", "# --- contract symbols replaced with raising stubs ---", sabotage]
    parts += ["", "# --- self-test (extracted from ## Self-test) ---", selftest, ""]
    return "\n".join(parts)


SABOTAGE_BODY = '        raise AssertionError("ralph-sabotage: %s was never meant to run")'


def sabotage_stubs(required):
    """Redefinitions that make every contract symbol raise when called.

    Appended after the solution, so they shadow the real definitions by simple
    rebinding — no import machinery, no tracing, and it works the same whether
    the self-test calls a function or instantiates a class.
    """
    lines = []
    for fn in required["functions"]:
        lines.append("def %s(*args, **kwargs):" % fn)
        lines.append(SABOTAGE_BODY % fn)
        lines.append("")
    if required["cls"]:
        lines.append("class %s(object):" % required["cls"])
        lines.append("    def __init__(self, *args, **kwargs):")
        lines.append("        raise AssertionError("
                     "\"ralph-sabotage: %s was never meant to run\")" % required["cls"])
        for method in required["methods"]:
            if method in ("__init__",):
                continue
            lines.append("    def %s(self, *args, **kwargs):" % method)
            lines.append("    " + SABOTAGE_BODY % method)
        lines.append("")
    return "\n".join(lines)


def describe_required(required):
    names = list(required["functions"])
    if required["cls"]:
        names.append(required["cls"])
    if len(names) == 1:
        return "`%s`" % names[0]
    return ", ".join("`%s`" % n for n in names)


def run_python(source):
    """Execute a snippet under containment. Returns (ok, output tail).

    The code being run here was written by a model and has never been read by a
    human, so `cwd=tempdir` is not an acceptable boundary. ralph_sandbox.run
    gives it an isolated interpreter with an allowlisted environment (no tokens),
    no network, no writes outside its own directory, a resident-memory cap, and a
    kill that takes the whole process group rather than just the direct child.
    """
    result = ralph_sandbox.run(pybin, source, timeout_s,
                               filename="solution.py", memory_mb=mem_cap_mb)
    if result.start_error:
        return False, f"sandbox could not start the interpreter: {result.start_error}"
    if result.memory_exceeded:
        return False, (f"exceeded the {mem_cap_mb} MB memory cap "
                       f"(peak RSS {result.peak_rss_mb} MB) — killed")
    if result.timed_out:
        return False, f"timed out after {timeout_s}s (process group killed)"
    if result.returncode == 0:
        return True, ""
    return False, result.tail(6) or f"exit {result.returncode}"


errors = []
ok = []
skipped = []
failed_files = []

for p in problems:
    filename = f"{p['id']}.md"
    path = problems_dir / filename

    if not path.exists():
        skipped.append(f"SKIP  {filename} (not yet generated)")
        continue

    md = path.read_text(encoding="utf-8")
    problem_errors = []

    for sec in REQUIRED_SECTIONS:
        if sec not in md:
            problem_errors.append(f"missing required section: {sec!r}")

    prose = strip_code(md)
    for pattern in PLACEHOLDER_PATTERNS:
        if re.search(pattern, prose):
            problem_errors.append(f"placeholder text found matching: {pattern!r}")

    # Prose floor (code excluded — this measures explanation, not solution size)
    floor = DEPTH_FLOORS.get(p.get("depth"), DEFAULT_FLOOR)
    words = len(re.sub(r'[#*`|>\-]', ' ', prose).split())
    if words < floor:
        problem_errors.append(
            f"explanation too short ({words} words of prose) — "
            f"need ≥{floor} for depth={p.get('depth', 'unset')}"
        )

    # Progressive hint ladder, hidden, and before the solution
    hints = section(md, "## Hints")
    # Count blocks that actually say something. `<details></details>` satisfied the
    # old open-tag count, so three empty tags passed as a three-rung ladder.
    n_hints = 0
    for body in re.findall(r'<details\b[^>]*>(.*?)</details>', hints,
                           re.IGNORECASE | re.DOTALL):
        text = re.sub(r'<summary\b[^>]*>.*?</summary>', ' ', body,
                      flags=re.IGNORECASE | re.DOTALL)
        if len(re.sub(r'<[^>]+>', ' ', text).split()) >= MIN_HINT_WORDS:
            n_hints += 1
    if n_hints < MIN_HINTS:
        problem_errors.append(
            f"hint ladder has {n_hints} hidden <details> block(s) with a real body "
            f"(≥{MIN_HINT_WORDS} words outside <summary>) — need ≥{MIN_HINTS} "
            f"(nudge → approach → key insight)"
        )
    if "## Hints" in md and "## Solution" in md and md.index("## Hints") > md.index("## Solution"):
        problem_errors.append("hints appear after the solution — they must come before it")

    # Complexity must actually state a bound
    complexity = section(md, "## Complexity")
    # A bound needs something inside the parentheses. `O(?)` is the unfilled
    # template placeholder, and it used to satisfy this check — which meant the
    # template shipped in prompt.md passed its own validator.
    bounds = re.findall(r'O\s*\(([^)]*)\)', complexity)
    real_bounds = [b for b in bounds if re.search(r'[A-Za-z0-9]', b.replace('?', ''))]
    if not bounds:
        problem_errors.append("complexity section states no O(...) bound")
    elif not real_bounds:
        problem_errors.append(
            f"complexity section states no real O(...) bound — found only "
            f"{['O(' + b + ')' for b in bounds]}, which is the unfilled placeholder")

    # Follow-ups
    # `max(2, len(...) and 2)` collapsed to 2 for every entry, so a problem
    # declaring 3 follow-ups passed with 2.
    expected_followups = max(2, len(p.get("followups", [])))
    followups = section(md, "## Follow-ups")
    n_follow = len(re.findall(r'^\s*[-*\d]', followups, re.MULTILINE))
    if n_follow < expected_followups:
        problem_errors.append(
            f"only {n_follow} follow-up(s) listed — need ≥{expected_followups}")

    # ── The code itself ────────────────────────────────────────────────────
    # Parse the contract before looking at any code. A gate that quietly
    # evaporates when it cannot read its own input is worse than no gate, because
    # it reports OK — so an unparseable contract fails the problem outright and
    # says which entry in problems.json to fix.
    required = parse_io_contract(p.get("io_contract", ""))
    if required is None:
        problem_errors.append(
            f"io_contract could not be parsed, so the contract gate cannot run: "
            f"{p.get('io_contract', '')!r} — fix the entry in problems.json "
            f"(expected `name(args) -> ret`, optionally joined by `and`, or "
            f"`class Name(args) with method(args) -> ret, ...`)")

    sol_blocks = code_blocks(section(md, "## Solution"))
    test_blocks = code_blocks(section(md, "## Self-test"))

    if not sol_blocks:
        problem_errors.append("no ```python block in the Solution section")
    if not test_blocks:
        problem_errors.append("no ```python block in the Self-test section")

    solution = "\n\n".join(sol_blocks)
    selftest = "\n\n".join(test_blocks)

    if solution:
        # sklearn may cross-check a solution, never be the solution.
        bad = re.findall(r'^\s*(?:from|import)\s+(sklearn[\w.]*)', solution, re.MULTILINE)
        if bad:
            problem_errors.append(
                f"solution imports {sorted(set(bad))} — scikit-learn may only be used "
                f"in the self-test as a cross-check oracle, never in the solution")

        # Everything the io_contract promises must actually be defined.
        # `required` is None only when the contract could not be parsed, and that
        # is reported below, outside this block, so it fires even with no code.
        if required is not None:
            missing = contract_violations(required, solution)
            if missing:
                problem_errors.append(
                    f"solution does not define {', '.join(missing)} — "
                    f"io_contract requires it")

        # Compound titles: each promised thing must appear in the code.
        terms = title_terms(p["title"])
        if len(terms) >= 2:
            blob = flatten(solution)
            ignore = shared_stems(terms)
            uncovered = [t for t in terms if not term_in(t, blob, ignore)]
            if uncovered:
                problem_errors.append(
                    f"title promises {terms} but the solution code never mentions "
                    f"{uncovered}")

    # \bassert\b, not a substring search: 'print("assertions passed")' verifies nothing.
    if selftest and not re.search(r'\bassert\b', selftest):
        problem_errors.append("self-test contains no assert statement — it verifies nothing")
    elif selftest:
        asserts = re.findall(r'^\s*assert\b(.*)$', selftest, re.MULTILINE)
        substantive = [a for a in asserts if not TRIVIAL_ASSERT.match(a.strip())]
        if len(asserts) < MIN_ASSERTS:
            problem_errors.append(
                f"self-test has {len(asserts)} assert(s) — need ≥{MIN_ASSERTS}")
        if not substantive:
            problem_errors.append(
                "every assert in the self-test is trivially true (`assert True`, "
                "`assert 1`, a bare `is not None`) — it verifies nothing about the solution")

    # ── Execute. The defining check of this track. ─────────────────────────
    if solution and selftest:
        uses_sklearn = bool(re.search(r'^\s*(?:from|import)\s+sklearn', selftest, re.MULTILINE))
        if uses_sklearn and not has_sklearn:
            problem_errors.append(
                "self-test cross-checks against scikit-learn but sklearn is not "
                "installed — cannot verify (pip install scikit-learn)")
        else:
            passed, detail = run_python(build_source(solution, selftest))
            if not passed:
                problem_errors.append(f"SOLUTION DOES NOT PASS ITS OWN SELF-TEST: {detail}")
            elif required is not None:
                # Passing is not yet evidence the solution ran. A `def` whose body
                # raises, paired with `assert True`, passes too: the two blocks are
                # merely concatenated and nothing has required one to call the other.
                #
                # So sabotage it. Redefine every symbol the io_contract names —
                # after the solution, before the self-test — with a stub that
                # raises. A self-test that exercises the solution must now FAIL.
                # One that does not passes unchanged, and is caught here.
                sabotage = sabotage_stubs(required)
                if sabotage:
                    still_passed, _ = run_python(
                        build_source(solution, selftest, sabotage))
                    if still_passed:
                        problem_errors.append(
                            "SELF-TEST DOES NOT EXERCISE THE SOLUTION: it still passes "
                            "when " + describe_required(required) + " is replaced by a "
                            "stub that raises. Assert on what the contract's symbols "
                            "actually return.")

    if problem_errors:
        failed_files.append(filename)
        errors.extend([f"FAIL: {filename}: {e}" for e in problem_errors])
    else:
        ok.append(f"OK    {filename}")

print("\nValidation report — ralph-ml-coding")
print(f"  Interpreter: {pybin}  (sklearn: {'yes' if has_sklearn else 'no'})")
print(f"  Containment: {ralph_sandbox.describe()}")
print(f"  Checked: {len(ok) + len(failed_files)} | Passed: {len(ok)} | "
      f"Failed: {len(failed_files)} ({len(errors)} problems) | Skipped: {len(skipped)}")
print()

for msg in ok:
    print(f"  {msg}")
for msg in skipped:
    print(f"  {msg}")

if errors:
    print()
    for msg in errors:
        print(f"  {msg}", file=sys.stderr)
    sys.exit(1)
else:
    if len(skipped) == len(problems):
        print("  No problems generated yet — run the loop first.")
    else:
        print("\nAll generated problems pass validation, solutions included.")
    sys.exit(0)
PY
