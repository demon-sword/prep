#!/usr/bin/env bash
set -euo pipefail

# Usage: ./ralph-tts/validate.sh [concept-id]
# Without argument: validates all generated concepts.
# With argument: validates one concept (e.g. 01-data-validation).
#
# Exit 0 = pass, 1 = at least one FAIL. Callers MUST honour the exit code —
# never `|| true` this script.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONCEPTS_DIR="$PREP_ROOT/tts/concepts"
CONCEPTS_JSON="$SCRIPT_DIR/concepts.json"

TARGET="${1:-all}"

python3 - "$TARGET" "$CONCEPTS_DIR" "$CONCEPTS_JSON" <<'PY'
import json
import re
import sys
import urllib.parse
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
    '<section id="theory">',
    '<section id="visualization">',
    '<section id="interview-line">',
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

# Every way other than src=/href= that a page can pull a URL. src= and href=
# alone were a front door with three side doors behind it: CSS @import and
# url(), dynamic import(), fetch(), and the worker constructors all reach the
# same CDNs. Matched on the string literal, which is what a hard-coded bundle
# reference actually is.
LOADER_PATTERNS = [
    r'@import\s+(?:url\(\s*)?["\']([^"\']+)["\']',       # CSS @import
    r'\burl\(\s*["\']?\s*([^"\')\s]+)\s*["\']?\s*\)',   # CSS url(...)
    r'\bimport\s*\(\s*["\']([^"\']+)["\']',              # dynamic import()
    r'\bfetch\s*\(\s*["\']([^"\']+)["\']',               # fetch()
    r'\bnew\s+Worker\s*\(\s*["\']([^"\']+)["\']',        # new Worker()
    r'\bimportScripts\s*\(\s*["\']([^"\']+)["\']',        # worker importScripts()
    r'\bnew\s+(?:EventSource|WebSocket)\s*\(\s*["\']([^"\']+)["\']',
]

# The manifest's `viz` field was written on every entry and read by no code
# path — the same defect class as a spec'd field nothing enforces. It names the
# interactive mechanism the page owes the reader, so when it promises something
# the reader can manipulate, the page must contain something manipulable. Kept
# to the presence of a control rather than a particular tag: a button group is
# a legitimate implementation of "an algorithm selector", and demanding
# <select> would fail a correct page.
VIZ_PROMISES_CONTROL = re.compile(
    r'\bslider|\btoggle|\bdropdown|\bselector|\bselect\b|\bcheckbox|\bbutton|\bclick|'
    r'\bdrag|\bpick\b|\bchoose|\badjust|\btune\b|\bknob|\bstep through|\bscrub',
    re.IGNORECASE)
VIZ_CONTROL_ELEMENTS = [
    r'type=["\']range["\']', r'<select\b', r'<button\b', r'type=["\']checkbox["\']',
    r'type=["\']radio["\']', r'<input\b', r'contenteditable', r'<textarea\b',
    r'draggable=', r'(?:mousedown|pointerdown|dragstart|touchstart)',
]

# Takeaway bullets. spec.md fixes the range at 4-6; the count was previously
# unchecked, which is how a section with zero bullets and one with seven both
# passed. Binding, because "4-6 bullets" is not a preference.
TAKEAWAY_MIN_BULLETS = 4
TAKEAWAY_MAX_BULLETS = 6

# Real tool/library/system names the takeaways must cite. Seeded from this
# track's own spec.md list, then extended with the rest of the names a senior
# page in this domain would legitimately reach for — a closed list of only the
# spec's examples would fail a page for naming a real tool the spec did not
# happen to enumerate. Two DISTINCT names required: one is a mention, two is a
# comparison, and the spec asks for senior-level specifics rather than a
# beginner summary.
TAKEAWAY_MIN_TOOLS = 2
TOOL_NAMES = [n.strip() for n in """MLflow|Feast|Tecton|Evidently|Great Expectations|Airflow|Seldon|KServe|Triton|
TFDV|TFX|DVC|Delta Lake|Iceberg|Hudi|SageMaker|Vertex AI|Kubeflow|Dagster|Prefect|Spark|BentoML|
Ray|Weights & Biases|W&B|Neptune|WhyLabs|Arize|Soda|Deequ|LakeFS|Pachyderm|Hopsworks|ONNX|
TorchServe|Prometheus|Grafana|Redis|Kafka|Flink|dbt|Snowflake|BigQuery|Databricks|Optuna|
scikit-learn|sklearn|PyTorch|TensorFlow|pandas|Parquet|Avro|Protobuf|Argo|Metaflow|Comet|
ClearML|Fiddler|Alibi|Kedro|Jenkins|GitHub Actions|Terraform|Kubernetes|Docker|Airbyte|Fivetran""".replace("\n", "").split("|") if n.strip()]
TOOL_NAME_RE = re.compile(
    r'(?<![\w-])(?:' + "|".join(sorted((re.escape(n) for n in TOOL_NAMES), key=len, reverse=True))
    + r')(?![\w-])', re.IGNORECASE)

# Spec floor is 400 words; per-topic `depth` scales it. Entries with no depth
# field fall back to the spec floor.
DEFAULT_FLOOR = 400
DEPTH_FLOORS = {"intro": 300, "core": 500, "advanced": 700}

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

    # Self-contained check. Collect every URL the page can load, not just the
    # ones in src=/href=. Scanning only those two attributes closed the front
    # door and left CSS @import, dynamic import(), fetch(), Worker and srcset
    # reaching the same CDNs — each is a string literal in a page that
    # hard-codes a bundle, so each is matched here and put through the same
    # allowlist. Sibling concept .html links are exempt: spec.md requires the
    # concept-nav to link prev/next by relative path.
    all_refs = re.findall(r'(?:src|href)=["\']([^"\']+)["\']', html)
    for pat in LOADER_PATTERNS:
        all_refs.extend(re.findall(pat, html))
    for raw in re.findall(r'srcset=["\']([^"\']+)["\']', html, re.IGNORECASE):
        # "a.png 1x, b.png 2x" — the URL is the first token of each candidate.
        all_refs.extend(part.strip().split()[0] for part in raw.split(",") if part.strip())

    # One decision per reference: off-origin or not, and if off-origin whether
    # the host is allowed. Decided on the parsed URL rather than a prefix match,
    # so neither a protocol-relative //cdn.example/... , a non-http scheme such
    # as wss://, nor a lookalike host like fonts.googleapis.com.evil.example can
    # pass as the allowlist. Anything unparseable fails closed.
    local_assets = []
    disallowed_external = []
    for r in all_refs:
        if not r or re.match(r'(?:data:|blob:|#|mailto:|javascript:)', r, re.IGNORECASE):
            continue
        try:
            parts = urllib.parse.urlsplit(r)
        except ValueError:
            disallowed_external.append(r)
            continue
        if parts.netloc or r.startswith("//"):
            if parts.scheme.lower() != "https" or (parts.hostname or "") not in ALLOWED_EXTERNAL_HOSTS:
                disallowed_external.append(r)
        elif not re.fullmatch(r'(?:\./|\.\./concepts/)?[\w.-]+\.html', r):
            local_assets.append(r)

    if local_assets:
        concept_errors.append(f"local asset references found (not self-contained): {local_assets}")
    if disallowed_external:
        concept_errors.append(
            f"external library/asset references found (not self-contained): "
            f"{sorted(set(disallowed_external))}"
        )

    # Theory length, scaled by the concept's declared depth
    floor = DEPTH_FLOORS.get(c.get("depth"), DEFAULT_FLOOR)
    theory_match = re.search(r'<section id="theory">(.*?)</section>', html, re.DOTALL)
    if theory_match:
        # Strip tags to count text content approximately
        text_only = strip_tags(theory_match.group(1))
        word_count = len(text_only.split())
        if word_count < floor:
            concept_errors.append(
                f"theory section too short ({word_count} words) — "
                f"need ≥{floor} words for depth={c.get('depth', 'unset')}"
            )

    # Takeaways: bullet count and named tools. Both are spec requirements that
    # nothing enforced — a takeaways section could carry zero bullets, or seven,
    # or read as a generic beginner summary naming nothing real, and still pass.
    takeaways_match = re.search(r'<section id="takeaways">(.*?)</section>', html, re.DOTALL)
    if takeaways_match:
        takeaways = takeaways_match.group(1)
        bullets = len(re.findall(r'<li\b', takeaways))
        if not TAKEAWAY_MIN_BULLETS <= bullets <= TAKEAWAY_MAX_BULLETS:
            concept_errors.append(
                f"takeaways has {bullets} bullet(s) — spec requires "
                f"{TAKEAWAY_MIN_BULLETS}-{TAKEAWAY_MAX_BULLETS}"
            )
        named = {m.lower() for m in TOOL_NAME_RE.findall(strip_tags(takeaways))}
        if len(named) < TAKEAWAY_MIN_TOOLS:
            concept_errors.append(
                f"takeaways names {len(named)} real tool/library/system "
                f"({sorted(named) or 'none'}) — spec requires at least "
                f"{TAKEAWAY_MIN_TOOLS} distinct names"
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

    # viz-to-page coverage: if the manifest promises the reader can manipulate
    # something, the page must contain a control to manipulate. `has_interaction`
    # above only proves a listener exists somewhere; a page can register one and
    # still ship no slider, button, or input for the promised mechanism.
    viz = c.get("viz") or ""
    if VIZ_PROMISES_CONTROL.search(viz):
        if not any(re.search(pat, html, re.IGNORECASE) for pat in VIZ_CONTROL_ELEMENTS):
            concept_errors.append(
                "viz promises an interactive control but the page has no control "
                "element (no range/checkbox/radio/select/button/input/drag handler)"
            )

    # Code block for algorithmic concepts.
    #
    # `has_code` is a per-entry editorial judgement, not an accident, so the
    # contract stands and the pages get fixed — flipping the flag to false would
    # make the corpus green by deleting the requirement. But an entry that still
    # carries a queued `gaps` item is not failed for the very thing that gap
    # exists to fix; the debt stays visible in the DEPTH QUEUE advisory, and the
    # check re-binds by itself the moment the page is regenerated and its gaps
    # array is drained. Self-restoring, with no flag anyone has to remember.
    if c.get("has_code") and not has_real_code_block(html) and not c.get("gaps"):
        concept_errors.append(
            "has_code=true but no <pre> block with code-like content found"
        )

    if concept_errors:
        failed_files.append(filename)
        errors.extend([f"FAIL: {filename}: {e}" for e in concept_errors])
    else:
        ok.append(f"OK    {filename}")

# Report
print(f"\nValidation report — ralph-tts")
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
