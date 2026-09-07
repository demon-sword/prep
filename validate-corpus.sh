#!/usr/bin/env bash
set -euo pipefail

# Usage: ./validate-corpus.sh [--final] [track ...]
#
# Corpus-level checks that only make sense across a finished run — the per-file
# validators cannot see these. Nothing in the pipeline noticed that self-attention
# is explained from scratch in three separate ai-engineering answer files,
# because every check was scoped to a single file.
#
# Tracks: ai-engineering  concepts  machine-learning  backend  dsa  system-design
#         mlops  ml-system-design  ml-coding  data-drills  tts
# With no argument, every track is checked.
#
# --final / RALPH_CORPUS_FINAL=1   Completeness gate, off by default. Without
#                   it, a track with fewer than 2 usable docs just prints SKIP
#                   and exits 0 — correct behaviour for a per-item run
#                   mid-generation, which legitimately has an incomplete
#                   corpus. But that means an ungenerated track (mlops,
#                   ml-system-design, ml-coding have all sat at zero files)
#                   prints the same clean SKIP as a finished one — a run that
#                   produced nothing looks identical to a run that produced
#                   everything. With the flag, each track is checked for
#                   completeness against its generator queue (see QUEUE_FILES
#                   below) before the redundancy comparison: zero files on
#                   disk found matching the track's glob is a FAIL, and fewer
#                   files than the queue's planned item count is a FAIL naming
#                   the missing ids. Category tracks with no flat id queue
#                   (ai-engineering, dsa, system-design) only get the
#                   non-empty check — data-drills gets the same treatment even
#                   though it DOES have a flat id queue, because its ids don't
#                   map onto filenames the way the per-id check needs (see
#                   QUEUE_FILES below). A track that passes completeness but
#                   still has fewer than 2 usable-for-comparison docs still
#                   prints SKIP for the redundancy half — that half is not a
#                   failure.
#
# Two complementary signals, because they catch different things:
#
#   COPIED TEXT     5-gram shingle overlap coefficient |A∩B| / min(|A|,|B|).
#                   Asymmetric on purpose, so a short note wholly restating part
#                   of a long one is caught. Binding — over threshold exits 1.
#                   RALPH_DEDUP_THRESHOLD (default 0.35).
#
#   REDUNDANT TOPIC TF-IDF cosine over content unigrams+bigrams. The 5-gram test
#                   only finds copy-paste: the three self-attention answers share
#                   just 3% of their 5-grams because each was written from
#                   scratch, yet they cover the same ground. Cosine ranks that
#                   trio at the top (~0.21 against a 0.011 median). Heuristic, so
#                   it warns rather than fails unless RALPH_DEDUP_STRICT=1.
#                   RALPH_DEDUP_COSINE (default 0.15).
#
# Exit 0 = clean, 1 = at least one binding failure.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THRESHOLD="${RALPH_DEDUP_THRESHOLD:-0.35}"
COSINE="${RALPH_DEDUP_COSINE:-0.15}"
MIN_SHINGLES="${RALPH_DEDUP_MIN_SHINGLES:-40}"
STRICT="${RALPH_DEDUP_STRICT:-0}"

# --final can land anywhere in the arg list (Ralph's callers append flags
# after track names as often as before them) and must never be swallowed as
# a track name.
FINAL=0
TRACKS=()
for arg in "$@"; do
  if [[ "$arg" == "--final" ]]; then
    FINAL=1
  else
    TRACKS+=("$arg")
  fi
done
if [[ "${RALPH_CORPUS_FINAL:-0}" == "1" ]]; then
  FINAL=1
fi

if [[ ${#TRACKS[@]} -eq 0 ]]; then
  TRACKS=(ai-engineering concepts machine-learning backend dsa system-design mlops ml-system-design ml-coding data-drills tts)
fi

python3 - "$SCRIPT_DIR" "$THRESHOLD" "$COSINE" "$MIN_SHINGLES" "$STRICT" "$FINAL" "${TRACKS[@]}" <<'PY'
import json
import math
import re
import sys
from collections import Counter
from itertools import combinations
from pathlib import Path

root = Path(sys.argv[1])
threshold = float(sys.argv[2])
cosine_threshold = float(sys.argv[3])
min_shingles = int(sys.argv[4])
strict = sys.argv[5] == "1"
final = sys.argv[6] == "1"
tracks = sys.argv[7:]

N = 5  # shingle width, in words

# (glob, how to pull the prose body out of one file)
TRACKS = {
    "ai-engineering":   ("ai-engineering/answers/[0-9]*.md",   "md_section"),
    "concepts":         ("ai-engineering/concepts/*.html",     "html_theory"),
    "machine-learning": ("machine_learning/concepts/*.html",   "html_theory"),
    "backend":          ("backend/concepts/*.html",            "html_theory"),
    "dsa":              ("dsa/problems/[0-9]*.md",             "md_section"),
    "system-design":    ("system-design/*/answers/[0-9]*.md",  "md_section"),
    "mlops":            ("mlops/concepts/*.html",              "html_theory"),
    "tts":              ("tts/concepts/*.html",                "html_theory"),
    "ml-system-design": ("ml-system-design/*.html",            "mlsd_body"),
    "ml-coding":        ("ml-coding/[0-9]*.md",                "mlcoding_body"),
    # ids are "sql-001" / "stat-001" (letters, not digits, unlike dsa/
    # ai-engineering) and the two families live in sibling dirs — one glob
    # with a `*` directory segment covers both instead of a second TRACKS
    # entry. `[a-z]*.md` (vs `*.md`) also excludes each family dir's
    # `_template.md` scaffold, which starts with `_`.
    "data-drills":      ("data-drills/*/[a-z]*.md",            "drills_body"),
}

# --final completeness: track -> its generator's queue file, which lists the
# planned ids. The remaining tracks (ai-engineering, dsa, system-design) are
# category-shaped with no flat id queue, so they only get the non-empty check.
#
# data-drills is deliberately NOT listed here even though
# ralph-data-drills/problems.json is a flat id queue (72 items, id "sql-001").
# The completeness check below matches ids against `p.stem for p in files`,
# i.e. it needs filename stem == id exactly. data-drills filenames are
# "<id>-<slug>.md" (problems.json's own "file" field says so: id "sql-001" ->
# "sql/sql-001-ranking-ties-three-ways.md") — the stem is never just the id,
# so wiring it in here would report all 72 items "missing" even on a fully
# generated corpus. Non-empty check only, like the category tracks above.
QUEUE_FILES = {
    "concepts":         "ralph-concepts/concepts.json",
    "machine-learning": "ralph-machine-learning/concepts.json",
    "backend":          "ralph-backend/concepts.json",
    "mlops":            "ralph-mlops/concepts.json",
    "tts":              "ralph-tts/concepts.json",
    "ml-system-design": "ralph-ml-system-design/topics.json",
    "ml-coding":        "ralph-ml-coding/problems.json",
}


def queue_ids(queue_path):
    # Queue files are a bare list of items in every generator seen so far, but
    # be tolerant of a {"concepts": [...]} wrapper too.
    data = json.loads(queue_path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        for value in data.values():
            if isinstance(value, list):
                data = value
                break
    return [item["id"] for item in data]


MD_SECTION = re.compile(r'^##\s+(?:Answer|Approach|Theory)\b(.*?)(?=^##\s|\Z)',
                        re.DOTALL | re.MULTILINE)
HTML_THEORY = re.compile(r'<section id="theory">(.*?)</section>', re.DOTALL)

STOPWORDS = set(
    "the a an and or of to in is are was were for with that this it as be by on "
    "you your we our can not but if then than from at its into use used using "
    "when where which how what why do does they them their there here also more "
    "most some such only very much many each other same both".split()
)


def strip_tags(text):
    text = re.sub(r'<(script|style)\b[^>]*>.*?</\1>', ' ', text,
                  flags=re.DOTALL | re.IGNORECASE)
    return re.sub(r'<[^>]+>', ' ', text)


MLSD_BODY = re.compile(
    r'<section id="(?:problem|architecture|tradeoffs)">(.*?)</section>', re.DOTALL)

# Sections named here are the only prose in a drill: the puzzle statement, the
# hint ladder, and the explanation of what went wrong / why the answer holds.
# Deliberately excludes Schema, Solution, Expected Result, Common Wrong Answer,
# Answer and Simulation — those are code fences and a bare number, and two
# drills built on the same seed table (e.g. the six window-function problems
# sharing an orders/events shape) legitimately repeat near-identical
# CREATE TABLE/INSERT boilerplate. That repetition is setup, not redundancy.
DRILLS_BODY = re.compile(
    r'^##\s+(?:Question|Hints|Worked Solution|Why It Is Wrong)\b(.*?)(?=^##\s|\Z)',
    re.DOTALL | re.MULTILINE)


def body_of(path, mode):
    raw = path.read_text(encoding="utf-8", errors="replace")
    if mode == "mlcoding_body":
        # Prose only. Two solutions legitimately share NumPy idiom, and that is
        # not redundancy — compare the explanations instead.
        return re.sub(r'```.*?```', ' ', raw, flags=re.DOTALL)
    if mode == "mlsd_body":
        # Skip #capacity: two case studies legitimately share derivation
        # boilerplate ("DAU x requests/day"), and that is not redundancy.
        return strip_tags(" ".join(MLSD_BODY.findall(raw)))
    if mode == "html_theory":
        m = HTML_THEORY.search(raw)
        return strip_tags(m.group(1)) if m else ""
    if mode == "drills_body":
        # Belt and braces: Hints items are prose but could in principle wrap
        # a small inline snippet in a fence, so strip fences from the kept
        # sections too, same as mlcoding_body does for its prose.
        chunks = DRILLS_BODY.findall(raw)
        return re.sub(r'```.*?```', ' ', "\n".join(chunks), flags=re.DOTALL)
    chunks = MD_SECTION.findall(raw)
    if chunks:
        return "\n".join(chunks)
    # No recognised section heading — fall back to the note minus front matter.
    return re.sub(r'^---.*?^---', ' ', raw, flags=re.DOTALL | re.MULTILINE)


def shingles(text):
    words = re.findall(r'[a-z0-9]+', text.lower())
    if len(words) < N:
        return set()
    return {" ".join(words[i:i + N]) for i in range(len(words) - N + 1)}


def term_counts(text):
    words = [w for w in re.findall(r'[a-z][a-z0-9_-]{2,}', text.lower())
             if w not in STOPWORDS]
    counts = Counter(words)
    counts.update(" ".join(pair) for pair in zip(words, words[1:]))
    return counts


def tfidf_vectors(counts_by_doc):
    doc_freq = Counter()
    for counts in counts_by_doc.values():
        doc_freq.update(set(counts))
    n_docs = len(counts_by_doc)
    vectors = {}
    for doc, counts in counts_by_doc.items():
        vec = {t: (1 + math.log(n)) * math.log(n_docs / (1 + doc_freq[t]))
               for t, n in counts.items()}
        norm = math.sqrt(sum(v * v for v in vec.values())) or 1.0
        vectors[doc] = {t: v / norm for t, v in vec.items()}
    return vectors


def cosine(a, b):
    if len(a) > len(b):
        a, b = b, a
    return sum(v * b.get(t, 0.0) for t, v in a.items())


exit_code = 0
warnings = 0

print("Corpus validation — cross-file redundancy")
print(f"  copied-text threshold: {threshold:.0%} 5-gram overlap")
print(f"  redundant-topic threshold: {cosine_threshold:.2f} cosine"
      f"{'  (STRICT: binding)' if strict else '  (advisory)'}\n")

for track in tracks:
    if track not in TRACKS:
        print(f"  unknown track: {track}", file=sys.stderr)
        exit_code = 1
        continue

    pattern, mode = TRACKS[track]
    files = sorted(root.glob(pattern))

    if final:
        # Completeness is judged on files that exist on disk, not on the
        # `bodies` dict below — that dict is filtered by min_shingles for the
        # redundancy comparison, which is a relevance filter, not an existence
        # one, and would misreport a real-but-short file as missing.
        if not files:
            print(f"  FAIL: {track} — corpus is EMPTY; the run produced nothing",
                  file=sys.stderr)
            exit_code = 1
            continue
        if track in QUEUE_FILES:
            expected_ids = queue_ids(root / QUEUE_FILES[track])
            found_ids = {p.stem for p in files}
            missing = [i for i in expected_ids if i not in found_ids]
            if missing:
                exit_code = 1
                produced = len(expected_ids) - len(missing)
                print(f"  FAIL: {track} — only {produced} of {len(expected_ids)} "
                      f"planned items produced", file=sys.stderr)
                for item_id in missing[:10]:
                    print(f"          missing: {item_id}", file=sys.stderr)
                continue

    bodies = {}
    for path in files:
        text = body_of(path, mode)
        if len(shingles(text)) >= min_shingles:
            bodies[path] = text

    if len(bodies) < 2:
        print(f"  SKIP  {track} — fewer than 2 usable docs")
        continue

    shingle_sets = {p: shingles(t) for p, t in bodies.items()}
    vectors = tfidf_vectors({p: term_counts(t) for p, t in bodies.items()})

    copied, redundant = [], []
    for a, b in combinations(bodies, 2):
        sa, sb = shingle_sets[a], shingle_sets[b]
        shared = len(sa & sb)
        if shared:
            overlap = shared / min(len(sa), len(sb))
            if overlap >= threshold:
                copied.append((overlap, shared / len(sa | sb), shared, a, b))
                continue
        sim = cosine(vectors[a], vectors[b])
        if sim >= cosine_threshold:
            redundant.append((sim, a, b))

    copied.sort(reverse=True, key=lambda r: r[0])
    redundant.sort(reverse=True, key=lambda r: r[0])

    label = f"{track} ({len(bodies)} docs)"
    if not copied and not redundant:
        print(f"  OK    {label} — no redundant pair")
        continue

    print(f"  {label}: {len(copied)} copied, {len(redundant)} redundant-topic")

    for overlap, jaccard, shared, a, b in copied:
        exit_code = 1
        print(f"  FAIL: COPIED TEXT — {overlap:.0%} 5-gram overlap "
              f"(jaccard {jaccard:.0%}, {shared} shared)", file=sys.stderr)
        print(f"          {a.relative_to(root)}", file=sys.stderr)
        print(f"          {b.relative_to(root)}", file=sys.stderr)

    for sim, a, b in redundant:
        if strict:
            exit_code = 1
            tag = "FAIL: REDUNDANT TOPIC"
        else:
            warnings += 1
            tag = "WARN: REDUNDANT TOPIC"
        print(f"  {tag} — cosine {sim:.2f}", file=sys.stderr)
        print(f"          {a.relative_to(root)}", file=sys.stderr)
        print(f"          {b.relative_to(root)}", file=sys.stderr)

if warnings and not strict:
    print(f"\n  {warnings} redundant-topic warning(s) — advisory. "
          f"Set RALPH_DEDUP_STRICT=1 to make them binding.")

sys.exit(exit_code)
PY
