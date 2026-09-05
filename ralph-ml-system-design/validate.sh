#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-ml-system-design/validate.sh [concept-id]
# Without argument: validates all generated concepts.
# With argument: validates one concept (e.g. 01-feed-ranking-system).
#
# Exit 0 = pass, 1 = at least one FAIL. Callers MUST honour the exit code —
# never `|| true` this script.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONCEPTS_DIR="$PREP_ROOT/ml-system-design"
CONCEPTS_JSON="$SCRIPT_DIR/topics.json"

TARGET="${1:-all}"

python3 - "$TARGET" "$CONCEPTS_DIR" "$CONCEPTS_JSON" <<'PY'
import json
import re
import sys
import urllib.parse
from html import unescape
from pathlib import Path

target, concepts_dir_str, concepts_json_path = sys.argv[1:4]
concepts_dir = Path(concepts_dir_str)
concepts = json.loads(Path(concepts_json_path).read_text())

if target != "all":
    concepts = [c for c in concepts if c["id"] == target or c["slug"] == target]
    if not concepts:
        print(f"Unknown concept: {target}", file=sys.stderr)
        sys.exit(1)

REQUIRED_SECTIONS = [
    '<section id="problem">',
    '<section id="capacity">',
    '<section id="architecture">',
    '<section id="visualization">',
    '<section id="tradeoffs">',
    '<section id="takeaways">',
    'class="concept-nav"',
]

PLACEHOLDER_PATTERNS = [
    r'\bTODO\b',
    r'\bPLACEHOLDER\b',
    r'Lorem ipsum',
    r'coming soon',
    # Leftover template stubs. Narrow to explicit stub markers: '<!-- [A-Z]'
    # also matched ordinary section comments like '<!-- Controls -->'.
    r'<!--[^>]*\b(?:TODO|FIXME|XXX|FILL IN|REPLACE ME|PLACEHOLDER)\b',
]

# Self-containment allowlist. Google Fonts is the only off-origin host the spec
# permits; every other external reference (D3, Chart.js, CDN bundles) is a FAIL.
ALLOWED_EXTERNAL_HOSTS = {"fonts.googleapis.com", "fonts.gstatic.com"}

# Spec floor is 400 words; per-topic `depth` scales it. Entries with no depth
# field fall back to the spec floor.
DEFAULT_FLOOR = 700
DEPTH_FLOORS = {"intro": 500, "core": 800, "advanced": 1100}

# Capacity estimation gate. Each anchor named in topics.json must leave a trace
# in the capacity section — this is what stops a case study from hand-waving the
# back-of-envelope numeracy these interviews actually test.
#
# Both halves of this gate used to be decorative. Counting raw digits let a
# five-entry bibliography (years, volumes, page ranges) clear a floor of 12
# without estimating anything, and matching anchors by bare substring let
# 'systems' satisfy 'ms', 'constrain' satisfy 'train' and a 'docs/req/status'
# path satisfy 'req/s'. Numbers now have to be doing capacity work and anchors
# now have to match as words.
#
# Calibrated on real derivations for a five-anchor topic: a full one
# (DAU → QPS → peak → latency budget → replicas → cache → storage) yields 46
# qualifying quantities and 14 derivation steps, and a deliberately terse one
# spending a single line per anchor still yields 20 and 6. The floors sit below
# the terse case and above what a section of plausible-looking assertions
# reaches — an assertion table scores 16 quantities and 0 steps, and one padded
# out with unit conversions ('150 ms = 0.15 s') scores 23 and 0.
MIN_CAPACITY_NUMBERS = 16
MIN_DERIVATION_STEPS = 4
# How far a quantity may sit from a capacity term and still count. ~120 chars is
# a sentence or two either side: wide enough that a real derivation is never
# punished for phrasing, tight enough that numbers parked in a reference list at
# the far end of the section count for nothing.
QUANTITY_WINDOW = 120

CAPACITY_KEYWORDS = {
    "DAU to QPS derivation":              ["qps", "requests/s", "req/s"],
    "peak-to-average ratio":              ["peak"],
    "storage math with bytes-per-row":    ["byte", "kb", "mb", "gb", "tb"],
    "bandwidth":                          ["bandwidth", "gbps", "mbps", "/s"],
    "GPU/replica sizing":                 ["gpu", "replica", "instance", "node"],
    "latency budget decomposition":       ["latency", "ms", "budget"],
    "index size and shard count":         ["shard", "index", "partition"],
    "cache hit-rate and memory":          ["cache", "hit rate", "hit-rate"],
    "training data volume and retrain cost": ["train", "retrain", "epoch"],
    "cost per 1000 requests":             ["cost", "$", "usd", "per 1000", "per 1k"],
}

# Anchor keywords match on word boundaries. Several of them are not plain words,
# and a unit glued to its number ('150ms') has no \b in front of it, so the
# awkward ones get an explicit pattern; ordinary words fall back to a word-start
# match that still allows an inflection ('shard' → 'shards', 'train' →
# 'training', but never 'constrain').
KEYWORD_PATTERNS = {
    "qps":        r'(?<![a-z])qps(?![a-z])',
    "req/s":      r'(?<![a-z])req(?:uest)?s?\s*/\s*s(?:ec)?(?![a-z])',
    "requests/s": r'(?<![a-z])req(?:uest)?s?\s*/\s*s(?:ec)?(?![a-z])',
    "byte":       r'\bbytes?\b',
    "kb":         r'(?<![a-z])kb(?![a-z])',
    "mb":         r'(?<![a-z])mb(?![a-z])',
    "gb":         r'(?<![a-z])gb(?![a-z])',
    "tb":         r'(?<![a-z])tb(?![a-z])',
    "gbps":       r'(?<![a-z])gbps(?![a-z])',
    "mbps":       r'(?<![a-z])mbps(?![a-z])',
    # A unit denominator, not a path separator: 'GB/s' and '1000/sec' count,
    # 'docs/setup' and '/usr/sbin' do not.
    "/s":         r'(?<=[0-9a-z])\s*/\s*s(?:ec)?(?![a-z])',
    "ms":         r'(?<![a-z])ms(?![a-z])',
    "gpu":        r'\bgpus?\b',
    "node":       r'\bnodes?\b',
    "instance":   r'\binstances?\b',
    "index":      r'\bindex(?:es|ing)?\b',
    "cache":      r'\bcach(?:e|es|ed|ing)\b',
    "hit rate":   r'\bhit[\s-]?rate',
    "hit-rate":   r'\bhit[\s-]?rate',
    "cost":       r'\bcosts?\b',
    "peak":       r'\bpeaks?\b',
    "epoch":      r'\bepochs?\b',
    # Currency, not a shell variable or a lone glyph.
    "$":          r'\$\s?\d',
    "usd":        r'\busd\b',
    "per 1000":   r'\bper\s*1[,.]?000\b',
    "per 1k":     r'\bper\s*1\s*k\b',
}


def keyword_re(keyword):
    """Word-boundary matcher for one capacity keyword."""
    pattern = KEYWORD_PATTERNS.get(keyword)
    if pattern is None:
        pattern = r'\b' + re.escape(keyword).replace('\\ ', ' ').replace(' ', r'[\s-]+')
    return re.compile(pattern)


CAPACITY_VOCAB = [keyword_re(k)
                  for keywords in CAPACITY_KEYWORDS.values() for k in keywords]

# A number doing capacity work carries a unit, a scale suffix or a currency mark.
# A bare integer does not: page numbers, volume numbers, candidate counts and
# years are all bare, and none of them is an estimate.
_NUM = r'\d[\d,._]*'
QUANTITY = re.compile(
    r'\$\s?' + _NUM
    + r'|' + _NUM + r'\s*%'
    + r'|' + _NUM + r'\s*(?:ms|µs|us|ns|sec|secs|seconds?|s'
                    r'|min|mins|minutes?|hrs?|hours?|h|days?)(?![a-z])'
    + r'|' + _NUM + r'\s*(?:qps|rps|tps|req(?:uest)?s?\s*/\s*s(?:ec)?)(?![a-z])'
    + r'|' + _NUM + r'\s*[kmgtp]b(?:\s*/\s*s(?:ec)?)?(?![a-z])'
    + r'|' + _NUM + r'\s*[kmg]bps(?![a-z])'
    + r'|' + _NUM + r'\s*[kmb](?![a-z])'
    + r'|' + _NUM + r'\s*/\s*(?:s(?:ec)?|day|hour|month|week|year|user|request'
                    r'|row|query|item|node|region|replica)(?![a-z])',
    re.IGNORECASE)

# '1990' is bare and never matches above; '1990s' would look like 1990 seconds.
BARE_YEAR = re.compile(r'(?:19|20)\d\d\s*s?')

# Arithmetic that is actually derivation: two quantities joined by an operator.
# The old check accepted any one of ×x*/=÷+ anywhere in the section, which the
# letter 'x' in 'index' and the slash in any path satisfied for free.
#
# At most two short words may sit between a quantity and its operator, which is
# where the unit lives ('300M DAU × 20', '138 GB/s / 16'); three is prose, not a
# step, which is what separates 'a × b' from '105 replicas = 35 GPUs per
# region'. '=' is deliberately not an operator: 'A = B' on its own restates
# rather than derives, and a section of unit conversions ('150 ms = 0.15 s')
# computes nothing.
DERIVATION = re.compile(
    r'\d[\d,._]*(?:\s*[a-z%$/µ]{1,8}){0,2}\s*(?:[×x*÷+/]|→|->)\s*[~≈]?\s*\$?\d',
    re.IGNORECASE)


def capacity_quantities(text):
    """The numbers in a capacity section that are actually estimating something.

    A quantity counts when it carries a unit, a scale suffix or a currency mark
    AND lands within QUANTITY_WINDOW characters of a capacity term — so a
    reference list, a page range or a figure number sitting inside the section
    contributes nothing to the floor.
    """
    low = text.lower()
    spans = [m.span() for rx in CAPACITY_VOCAB for m in rx.finditer(low)]
    found = []
    for m in QUANTITY.finditer(text):
        if BARE_YEAR.fullmatch(m.group(0).strip()):
            continue
        if any(start - QUANTITY_WINDOW < m.end() and end + QUANTITY_WINDOW > m.start()
               for start, end in spans):
            found.append(m.group(0))
    return found

# Fragments that carry no topic meaning on their own — dropped from title terms.
TITLE_STOPWORDS = {
    "a", "an", "and", "for", "how", "in", "its", "of", "or", "the", "to",
    "when", "where", "which", "who", "why", "with",
}


SCRIPT_OR_STYLE = re.compile(r'<(script|style)\b[^>]*>.*?</\1>',
                             re.DOTALL | re.IGNORECASE)


def prose_of(html):
    """Page content with executable blocks removed.

    Placeholder scanning must not see inside <script>: a page may legitimately
    *depict* a placeholder as data rather than contain one. 31-agents-overview
    demonstrates an agent writing a lazy stub, and the string
    'assert True  # TODO(agent): just skip this test' is the point of that
    example, not an unfinished section.
    """
    return SCRIPT_OR_STYLE.sub(' ', html)


def strip_tags(html):
    return re.sub(r'<[^>]+>', ' ', html)


def flatten(text):
    """Lowercase, collapse everything non-alphanumeric — for substring matching."""
    return re.sub(r'[^a-z0-9]', '', text.lower())


def script_text(html):
    return "\n".join(
        re.findall(r'<script\b[^>]*>(.*?)</script>', html, re.DOTALL | re.IGNORECASE)
    )


# A slash between two short tokens joins an atomic abbreviation rather than
# separating two topics: 'A/B', 'CI/CD', 'I/O' are one term each, whereas the
# slash in 'XGBoost/LightGBM' genuinely separates two.
ATOMIC_SLASH = re.compile(r'\b([A-Za-z0-9]{1,3})/([A-Za-z0-9]{1,3})\b')


def split_slash(fragment):
    """Split on '/' only where it separates two real, distinct terms."""
    protected = ATOMIC_SLASH.sub('\\1\x00\\2', fragment)
    parts = [p.strip().replace('\x00', '/') for p in protected.split('/')]
    parts = [p for p in parts if p]
    if len(parts) > 1 and all(len(p) >= 2 for p in parts):
        return parts
    return [fragment]


def title_terms(title):
    """The co-equal topics a compound title promises.

    Only top-level conjunctions count ('t-SNE & UMAP' -> two algorithms, both
    owed an implementation). A parenthetical names implementations or examples
    of the one topic, not extra content — 'Gradient Boosting (XGBoost/LightGBM)'
    promises boosting, not two libraries — so parentheticals are dropped. Text
    after a colon is the enumeration ('Fine-Tuning Types: Full, Partial, PEFT').
    """
    source = re.sub(r'\([^)]*\)', ' ', title).rsplit(':', 1)[-1]
    fragments = re.split(r'(?i)\s+vs\.?\s+|&|,', source)
    fragments = [p for frag in fragments for p in split_slash(frag)]

    terms = []
    for frag in fragments:
        frag = frag.strip(' .:-')
        tokens = [t for t in re.split(r'[^A-Za-z0-9]+', frag) if t]
        meaningful = [t for t in tokens if len(t) >= 2 and t.lower() not in TITLE_STOPWORDS]
        if meaningful:
            terms.append(frag)
    return terms


SUFFIXES = ("ization", "isation", "ations", "ation", "ing", "ies", "es", "s")


def stem(token):
    """Crude suffix strip so 'Vanishing' matches 'vanish' and 'Gradients' 'gradient'."""
    t = token.lower()
    for suf in SUFFIXES:
        if t.endswith(suf) and len(t) - len(suf) >= 3:
            return t[: len(t) - len(suf)]
    return t


# A viz implements a mechanism under the vocabulary of that mechanism, not under
# the title's acronym: a convolution demo says kernel/stride, never "CNN". Map
# such terms to the tokens that actually evidence them. Extend as titles need it.
RELATED_TOKENS = {
    "cnn": ["conv", "kernel", "filter", "featuremap", "stride"],
    "rnn": ["recurr", "hidden", "timestep", "sequence"],
    "lstm": ["gate", "cellstate", "forget"],
    "gru": ["gate", "hidden", "reset"],
    "hypothesis": ["pvalue", "alpha", "null", "reject", "sample"],
    "significance": ["pvalue", "alpha", "confidence", "reject"],
    "testing": ["pvalue", "alpha", "sample", "trial"],
    "peft": ["lora", "adapter", "prefix", "frozen"],
    "perplexity": ["ppl", "entropy", "logprob"],
    "defenses": ["defen", "mitigat", "sanitiz", "guard", "filter"],
}


def term_tokens(term):
    return [t for t in re.split(r'[^A-Za-z0-9]+', term)
            if t and t.lower() not in TITLE_STOPWORDS]


def shared_stems(terms):
    """Stems common to every term in a compound title.

    'Data Drift vs Concept Drift' share 'drift', so finding 'drift' in the
    script says nothing about which of the two is implemented. Only the
    distinguishing part of each term can evidence it.
    """
    sets = [{stem(t) for t in term_tokens(term)} for term in terms]
    sets = [s for s in sets if s]
    if len(sets) < 2:
        return set()
    common = set.intersection(*sets)
    return common


def term_in(term, blob, ignore=frozenset()):
    """True unless every token evidencing `term` is wholly absent from `blob`
    (flattened script text — identifiers, strings and comments alike)."""
    if flatten(term) and flatten(term) in blob:
        return True
    tokens = term_tokens(term)
    candidates = []
    for tok in tokens:
        st = stem(tok)
        if st in ignore:
            continue
        candidates.append(st)
        candidates.extend(RELATED_TOKENS.get(st, []))
        candidates.extend(RELATED_TOKENS.get(tok.lower(), []))
    if not candidates:
        # Everything about this term is shared with its siblings — fall back to
        # its own tokens rather than asserting nothing.
        candidates = [stem(t) for t in tokens]
    return any(c and c in blob for c in candidates)


CODE_SIGNAL = re.compile(r'[=(){};]|\bdef\b|\bfor\b|\bif\b|\breturn\b|->|<-|←')


def has_real_code_block(html):
    """At least one <pre> holding multi-line, code-shaped content."""
    for pre in re.findall(r'<pre\b[^>]*>(.*?)</pre>', html, re.DOTALL | re.IGNORECASE):
        text = strip_tags(pre).strip()
        lines = [ln for ln in text.splitlines() if ln.strip()]
        if len(lines) >= 2 and CODE_SIGNAL.search(text):
            return True
    return False


errors = []
ok = []
skipped = []
failed_files = []

for c in concepts:
    filename = f"{c['id']}.html"
    path = concepts_dir / filename

    if not path.exists():
        skipped.append(f"SKIP  {filename} (not yet generated)")
        continue

    html = path.read_text(encoding="utf-8")

    concept_errors = []

    # Required sections
    for section in REQUIRED_SECTIONS:
        if section not in html:
            concept_errors.append(f"missing required element: {section!r}")

    # Header element
    if "<header" not in html:
        concept_errors.append("missing <header> element")

    # Event listener or animation (at least one interactive element)
    has_interaction = (
        "addEventListener" in html
        or "requestAnimationFrame" in html
        or "onclick" in html
        or "oninput" in html
    )
    if not has_interaction:
        concept_errors.append("no event listener or animation loop found — viz not interactive")

    # Placeholder check — authored prose only, never depicted code in <script>
    prose = prose_of(html)
    for pattern in PLACEHOLDER_PATTERNS:
        if re.search(pattern, prose):
            concept_errors.append(f"placeholder text found matching: {pattern!r}")

    # Self-contained check — no local asset files. Sibling concept .html links
    # are exempt: spec.md requires the concept-nav to link prev/next by relative path.
    all_refs = re.findall(r'(?:src|href)=["\']([^"\']+)["\']', html)
    local_refs = [
        r for r in all_refs
        if not re.match(r'(?:https?://|//|data:|#|mailto:)', r, re.IGNORECASE)
    ]
    local_assets = [
        r for r in local_refs
        if not re.fullmatch(r'(?:\./|\.\./concepts/)?[\w.-]+\.html', r)
    ]
    if local_assets:
        concept_errors.append(f"local asset references found (not self-contained): {local_assets}")

    # External references — the page must pull nothing off-origin but Google
    # Fonts. Decided on the parsed host with https required, so neither a
    # protocol-relative //cdn.example/... nor a lookalike host such as
    # fonts.googleapis.com.evil.example can pass as the allowlist.
    external_refs = [
        r for r in all_refs
        if re.match(r'(?:https?://|//)', r, re.IGNORECASE)
    ]
    disallowed_external = []
    for r in external_refs:
        parts = urllib.parse.urlsplit(r)
        if parts.scheme != "https" or (parts.hostname or "") not in ALLOWED_EXTERNAL_HOSTS:
            disallowed_external.append(r)
    if disallowed_external:
        concept_errors.append(
            f"external library/asset references found (not self-contained): "
            f"{disallowed_external}"
        )

    # Body length across the whole case study, scaled by declared depth
    floor = DEPTH_FLOORS.get(c.get("depth"), DEFAULT_FLOOR)
    body_words = len(strip_tags(prose_of(html)).split())
    if body_words < floor:
        concept_errors.append(
            f"case study too short ({body_words} words) — "
            f"need ≥{floor} words for depth={c.get('depth', 'unset')}"
        )

    # ── Capacity estimation: the load-bearing skill of this track ──────────
    # A case study that asserts numbers without deriving them is the exact
    # failure this track exists to prevent, so the gate is on arithmetic, not
    # on the section merely being present.
    cap = re.search(r'<section id="capacity">(.*?)</section>', html, re.DOTALL)
    if not cap:
        concept_errors.append("missing <section id=\"capacity\"> — capacity estimation is mandatory")
    else:
        # Entities first: '150&nbsp;ms' and '300M&nbsp;&times;&nbsp;20' are
        # arithmetic, and only look like prose until they are unescaped.
        cap_text = unescape(strip_tags(prose_of(cap.group(1))))
        numbers = capacity_quantities(cap_text)
        if len(numbers) < MIN_CAPACITY_NUMBERS:
            concept_errors.append(
                f"capacity section has only {len(numbers)} numbers doing capacity "
                f"work (carrying a unit or scale, near a capacity term) — "
                f"need ≥{MIN_CAPACITY_NUMBERS} for a real estimation"
            )
        steps = DERIVATION.findall(cap_text)
        if len(steps) < MIN_DERIVATION_STEPS:
            concept_errors.append(
                f"capacity section shows {len(steps)} steps of arithmetic "
                f"(number ×/÷ number, number → number) — "
                f"need ≥{MIN_DERIVATION_STEPS}: numbers must be DERIVED, not asserted"
            )
        low = cap_text.lower()
        missing_anchors = [
            a for a in c.get("capacity_anchors", [])
            if not any(keyword_re(k).search(low)
                       for k in CAPACITY_KEYWORDS.get(a, [a.split()[0].lower()]))
        ]
        if missing_anchors:
            concept_errors.append(
                f"capacity section never derives: {missing_anchors}"
            )

    # Title-to-JS coverage: every topic a compound title promises must actually
    # be implemented in the visualization, not just named in the heading.
    terms = title_terms(c["title"])
    if len(terms) >= 2:
        js = flatten(script_text(html))
        ignore = shared_stems(terms)
        uncovered = [t for t in terms if not term_in(t, js, ignore)]
        if uncovered:
            concept_errors.append(
                f"title promises {terms} but the <script> block never mentions "
                f"{uncovered} — that part of the title is unimplemented"
            )

    # Code block for algorithmic concepts
    if c.get("has_code") and not has_real_code_block(html):
        concept_errors.append(
            "has_code=true but no <pre> block with code-like content found"
        )

    if concept_errors:
        failed_files.append(filename)
        errors.extend([f"FAIL: {filename}: {e}" for e in concept_errors])
    else:
        ok.append(f"OK    {filename}")

# Report
print(f"\nValidation report — ralph-ml-system-design (case studies)")
print(f"  Checked: {len(ok) + len(failed_files)} | Passed: {len(ok)} | Failed: {len(failed_files)} ({len(errors)} problems) | Skipped: {len(skipped)}")
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
    if len(skipped) == len(concepts):
        print("  No concepts generated yet — run the loop first.")
    else:
        print(f"\nAll generated concepts pass validation.")
    sys.exit(0)
PY
