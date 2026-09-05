#!/usr/bin/env python3
"""
study.py — spaced-repetition retrieval practice over this repo's study material.

Single source of truth: study/state.json
Generated views (never hand-edit): study/PROGRESS.md, dsa/progress.md

Design notes
------------
* Scheduling is SM-2 (Wozniak). Self-rating drives the next interval; there is no
  fixed day-1/3/7/14 ladder anywhere in this file.
* The status vocabulary deliberately reuses the one already defined in dsa/README.md
  (todo/hint/solo/review/mastered) so the repo speaks one language.
* Retrieval practice, not re-reading: `drill` shows a question, hides the answer,
  waits for you to actually recall it, then reveals and asks for a rating.
* stdlib only, Python 3.8+.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import random
import re
import sys
import textwrap
from typing import Dict, Iterable, List, Optional, Tuple

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_PATH = os.path.join(REPO, "study", "state.json")
PROGRESS_PATH = os.path.join(REPO, "study", "PROGRESS.md")
DSA_PROGRESS_PATH = os.path.join(REPO, "dsa", "progress.md")

SCHEMA_VERSION = 1

# ---------------------------------------------------------------------------
# Ratings
# ---------------------------------------------------------------------------

# SM-2 quality values. We expose a 4-point scale because 0-5 self-rating is
# famously noisy; these four map onto the SM-2 qualities that actually differ.
RATINGS: Dict[str, int] = {
    "again": 0,
    "hard": 3,
    "good": 4,
    "easy": 5,
}
RATING_ALIASES: Dict[str, str] = {
    "a": "again", "0": "again", "1": "again", "n": "again", "no": "again",
    "h": "hard", "2": "hard",
    "g": "good", "3": "good", "y": "good", "yes": "good", "": "good",
    "e": "easy", "4": "easy",
}

TRACKS = [
    "ai-answers",
    "ai-concepts",
    "ml-concepts",
    "be-concepts",
    "mlops-concepts",
    "ml-coding",
    "ml-sys-design",
    "data-drills",
    "dsa",
    "dsa-patterns",
    "sys-design",
]

TRACK_LABELS = {
    "ai-answers": "AI Engineering answers",
    "ai-concepts": "AI Engineering concepts",
    "ml-concepts": "Machine Learning concepts",
    "be-concepts": "Backend / distributed concepts",
    "mlops-concepts": "MLOps concepts",
    "ml-coding": "ML coding (from scratch)",
    "ml-sys-design": "ML system design",
    "data-drills": "Data drills (SQL / stats)",
    "dsa": "DSA (NeetCode 150)",
    "dsa-patterns": "DSA patterns",
    "sys-design": "System design",
}

STATUSES = ["todo", "hint", "solo", "review", "mastered"]


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def today() -> dt.date:
    override = os.environ.get("STUDY_TODAY")
    if override:
        return dt.date.fromisoformat(override)
    return dt.date.today()


def parse_date(s: Optional[str]) -> Optional[dt.date]:
    if not s:
        return None
    try:
        return dt.date.fromisoformat(s)
    except ValueError:
        return None


def iso(d: Optional[dt.date]) -> Optional[str]:
    return d.isoformat() if d else None


def squash(text: str, limit: int = 400) -> str:
    """Collapse whitespace and markdown noise into a single readable line."""
    text = re.sub(r"\s+", " ", text or "").strip()
    text = re.sub(r"`{1,3}", "", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"\[(.+?)\]\([^)]*\)", r"\1", text)
    if len(text) > limit:
        text = text[: limit - 1].rstrip() + "…"
    return text


def color(s: str, c: str) -> str:
    if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
        return s
    codes = {
        "red": "31", "green": "32", "yellow": "33", "blue": "34",
        "magenta": "35", "cyan": "36", "grey": "90", "bold": "1",
    }
    return f"\033[{codes.get(c, '0')}m{s}\033[0m"


# ---------------------------------------------------------------------------
# SM-2
# ---------------------------------------------------------------------------

def sm2(item: dict, quality: int, on: dt.date) -> dict:
    """Apply one SM-2 review. Mutates and returns `item`.

    Textbook SM-2:
      q < 3           -> repetition count resets, relearn tomorrow
      q >= 3          -> interval 1, then 6, then previous * ease
      EF' = EF + (0.1 - (5-q)*(0.08 + (5-q)*0.02)), floored at 1.3
    """
    ease = float(item.get("ease") or 2.5)
    reps = int(item.get("reps") or 0)
    interval = int(item.get("interval_days") or 0)

    if quality < 3:
        reps = 0
        interval = 1
        item["lapses"] = int(item.get("lapses") or 0) + 1
    else:
        if reps == 0:
            interval = 1
        elif reps == 1:
            interval = 6
        else:
            interval = max(1, int(round(interval * ease)))
        reps += 1

    ease = ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
    ease = max(1.3, round(ease, 3))

    item["ease"] = ease
    item["reps"] = reps
    item["interval_days"] = interval
    item["last_reviewed"] = iso(on)
    item["next_due"] = iso(on + dt.timedelta(days=interval))

    hist = item.get("history") or []
    hist.append(f"{iso(on)}:{quality}")  # one line per review keeps diffs tight
    item["history"] = hist[-10:]  # cap so the store stays diffable

    item["status"] = derive_status(item, quality)
    return item


def last_history_quality(item: dict) -> int:
    """Most recent self-rating. Tolerates the older [date, q] list form."""
    hist = item.get("history") or []
    if not hist:
        return 4
    last = hist[-1]
    try:
        if isinstance(last, str):
            return int(last.rsplit(":", 1)[1])
        return int(last[1])
    except (ValueError, IndexError, TypeError):
        return 4


def derive_status(item: dict, last_quality: Optional[int] = None) -> str:
    """Map SM-2 state onto the repo's existing todo/hint/solo/review/mastered vocabulary."""
    reps = int(item.get("reps") or 0)
    interval = int(item.get("interval_days") or 0)
    if not item.get("last_reviewed"):
        return "todo"
    if last_quality is None:
        last_quality = last_history_quality(item)
    if last_quality < 4:
        return "hint"
    if interval >= 60 and reps >= 4:
        return "mastered"
    if interval >= 21:
        return "review"
    return "solo"


# ---------------------------------------------------------------------------
# Store
# ---------------------------------------------------------------------------

def new_item(id_: str, track: str, title: str, path: str, prompt: str, answer: str) -> dict:
    return {
        "id": id_,
        "track": track,
        "title": title,
        "path": path,
        "prompt": prompt,
        "answer": answer,
        "status": "todo",
        "reps": 0,
        "lapses": 0,
        "ease": 2.5,
        "interval_days": 0,
        "last_reviewed": None,
        "next_due": None,
        "history": [],
    }


def load_state() -> dict:
    if not os.path.exists(STATE_PATH):
        return {"version": SCHEMA_VERSION, "generated": None, "items": []}
    with open(STATE_PATH, encoding="utf-8") as fh:
        return json.load(fh)


def save_state(state: dict) -> None:
    state["version"] = SCHEMA_VERSION
    state["generated"] = dt.datetime.now().isoformat(timespec="seconds")
    state["items"] = sorted(state["items"], key=lambda i: i["id"])
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, STATE_PATH)


def items_by_id(state: dict) -> Dict[str, dict]:
    return {i["id"]: i for i in state["items"]}


def resolve(state: dict, needle: str) -> dict:
    """Resolve any unique substring of an id to exactly one item."""
    exact = [i for i in state["items"] if i["id"] == needle]
    if exact:
        return exact[0]
    hits = [i for i in state["items"] if needle.lower() in i["id"].lower()]
    if not hits:
        raise SystemExit(f"no item matches '{needle}'")
    if len(hits) > 1:
        lines = "\n".join(f"  {h['id']}" for h in hits[:12])
        more = f"\n  … and {len(hits) - 12} more" if len(hits) > 12 else ""
        raise SystemExit(f"'{needle}' is ambiguous ({len(hits)} matches):\n{lines}{more}")
    return hits[0]


# ---------------------------------------------------------------------------
# Seeding — build items from what is actually on disk
# ---------------------------------------------------------------------------

def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError):
        return ""


def extract_h1(md: str) -> str:
    m = re.search(r"^#\s+(.+?)\s*$", md, re.M)
    return squash(m.group(1)) if m else ""


def extract_one_liner(md: str) -> str:
    """Pull the blockquote under '## One-liner recall'."""
    m = re.search(r"##\s*One-liner recall\s*(.*?)(?:\n##\s|\Z)", md, re.S | re.I)
    if not m:
        return ""
    block = m.group(1)
    quoted = re.findall(r"^\s*>\s?(.*)$", block, re.M)
    text = " ".join(q.strip() for q in quoted if q.strip())
    if not text:  # unfilled template
        return ""
    if text.startswith("<!--"):
        return ""
    return squash(text, 600)


def seed_ai_answers() -> List[dict]:
    out = []
    d = os.path.join(REPO, "ai-engineering", "answers")
    if not os.path.isdir(d):
        return out
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md") or fn.startswith("_"):
            continue
        path = os.path.join(d, fn)
        md = read(path)
        title = extract_h1(md) or fn[:-3]
        answer = extract_one_liner(md)
        if not answer:
            answer = "(no one-liner recorded — open the file and read the Answer section)"
        cat = fn.split("-")[0]
        out.append(new_item(
            id_=f"ai-answers/{fn[:-3]}",
            track="ai-answers",
            title=title,
            path=os.path.relpath(path, REPO),
            prompt=title,
            answer=answer,
        ))
        out[-1]["group"] = f"cat-{cat}"
    return out


def _seed_concepts(track: str, json_rel: str, page_dir_rel: str) -> List[dict]:
    """Concept tracks are described by the ralph-*/concepts.json manifests (read-only)."""
    out = []
    jp = os.path.join(REPO, json_rel)
    if not os.path.exists(jp):
        return out
    try:
        entries = json.load(open(jp, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return out
    for e in entries:
        cid = e.get("id") or e.get("slug")
        if not cid:
            continue
        title = e.get("title") or cid
        desc = squash(e.get("description") or "", 600)
        rel = _page_or_dir(page_dir_rel, f"{cid}.html", json_rel)
        # A concept page has no written answer, so generate a retrieval prompt from
        # the manifest: ask for an explanation, and use the description as the
        # recall target to check yourself against.
        out.append(new_item(
            id_=f"{track}/{cid}",
            track=track,
            title=title,
            path=rel,
            prompt=f"Explain {title} — mechanism, why it matters, and one production tradeoff.",
            answer=desc or "(no description in the concept manifest)",
        ))
        out[-1]["group"] = e.get("group") or "general"
    return out


def _manifest(json_rel: str) -> List[dict]:
    """Read a ralph-*/ manifest. These are owned by the generators — read-only here."""
    jp = os.path.join(REPO, json_rel)
    if not os.path.exists(jp):
        return []
    try:
        entries = json.load(open(jp, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    return entries if isinstance(entries, list) else []


def _page_or_dir(dir_rel: str, filename: str, fallback: str = "") -> str:
    """Link the generated file once it exists, else its directory, else the manifest.

    The manifests run ahead of the generators, so an item is studiable before its
    page is written — and for a track that has produced nothing yet the output
    directory does not exist either. Falling back to the manifest that declares the
    item keeps every path in the generated views resolvable at all times.
    """
    for cand in (os.path.join(dir_rel, filename), dir_rel, fallback):
        if cand and os.path.exists(os.path.join(REPO, cand)):
            return cand
    return dir_rel


def seed_ml_coding() -> List[dict]:
    """`ralph-ml-coding/problems.json` — implement-it-from-scratch ML problems.

    Retrieval here is the signature plus the invariant, not the finished function:
    if you cannot state the contract cold you cannot write the code.
    """
    out = []
    for e in _manifest("ralph-ml-coding/problems.json"):
        cid = e.get("id") or e.get("slug")
        if not cid:
            continue
        title = e.get("title") or cid
        contract = squash(e.get("io_contract") or "", 300)
        desc = squash(e.get("description") or "", 600)
        prompt = (f"{title} — state the signature, the invariant that must hold, and the "
                  f"time/space complexity before writing any code.")
        answer = (f"Contract: {contract}\n\n{desc}" if contract else desc) or \
                 "(no description in the problem manifest)"
        out.append(new_item(
            id_=f"ml-coding/{cid}",
            track="ml-coding",
            title=title,
            path=_page_or_dir("ml-coding", f"{cid}.md", "ralph-ml-coding/problems.json"),
            prompt=prompt,
            answer=answer,
        ))
        out[-1]["group"] = e.get("group") or "general"
        if e.get("difficulty"):
            out[-1]["difficulty"] = e["difficulty"].capitalize()
    return out


def seed_ml_sys_design() -> List[dict]:
    """`ralph-ml-system-design/topics.json` — ML design rounds.

    The scale block is the part that is actually hard to recall under pressure, so
    it is folded into the answer as named figures rather than left in the prose.
    """
    out = []
    for e in _manifest("ralph-ml-system-design/topics.json"):
        cid = e.get("id") or e.get("slug")
        if not cid:
            continue
        title = e.get("title") or cid
        desc = squash(e.get("description") or "", 600)
        scale = e.get("scale") or {}
        if isinstance(scale, dict) and scale:
            figures = "\n".join(f"  • {k.replace('_', ' ')}: {v}" for k, v in scale.items())
            answer = f"{desc}\n\nScale to quote:\n{figures}"
        else:
            answer = desc or "(no description in the topic manifest)"
        out.append(new_item(
            id_=f"ml-sys-design/{cid}",
            track="ml-sys-design",
            title=title,
            path=_page_or_dir("ml-system-design", f"{cid}.md",
                              "ralph-ml-system-design/topics.json"),
            prompt=f"{title} — whiteboard it end to end: candidate generation, features, "
                   f"ranking, serving budget, and how it is evaluated online.",
            answer=answer,
        ))
        out[-1]["group"] = e.get("group") or "general"
    return out


def seed_data_drills() -> List[dict]:
    """`ralph-data-drills/problems.json` — SQL and stats drills.

    The manifest carries an explicit `file`, so honour it rather than reconstructing
    a path from the id; the two do not agree (`sql-001` lives at `sql/sql-001-*.md`).
    """
    out = []
    for e in _manifest("ralph-data-drills/problems.json"):
        cid = e.get("id") or e.get("slug")
        if not cid:
            continue
        title = e.get("title") or cid
        topics = e.get("topics") or []
        focus = squash(e.get("focus") or e.get("description") or "", 600)
        rel = e.get("file") or ""
        hint = f" ({', '.join(topics[:4])})" if topics else ""
        out.append(new_item(
            id_=f"data-drills/{cid}",
            track="data-drills",
            title=title,
            path=_page_or_dir("data-drills", rel, "ralph-data-drills/problems.json"),
            prompt=f"{title}{hint} — write the query/derivation from scratch and say what "
                   f"makes the naive version wrong.",
            answer=focus or "(no focus in the drill manifest)",
        ))
        out[-1]["group"] = e.get("group") or e.get("family") or "general"
        if e.get("difficulty"):
            out[-1]["difficulty"] = e["difficulty"].capitalize()
    return out


NEETCODE_ROW = re.compile(r"^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|\s*(Easy|Medium|Hard)\s*\|", re.M)


def seed_dsa() -> List[dict]:
    """All 150 NeetCode problems; the ones with written notes get their real one-liner.

    Source of record is dsa/neetcode-150-list.md — the immutable reference index.
    We deliberately do NOT read dsa/progress.md here: this tool *generates* that file,
    and seeding from your own output is a circular dependency that silently loses data
    the moment the generated format changes.
    """
    out = []
    src = read(os.path.join(REPO, "dsa", "neetcode-150-list.md"))

    # `## 4. Stack (7)` -> "Stack"; rows are `| # | Problem | Difficulty | [LC](url) |`
    cats: Dict[int, str] = {}
    rows: List[Tuple[int, str, str]] = []
    current = "Uncategorised"
    for line in src.splitlines():
        h = re.match(r"^##\s+(?:\d+\.\s*)?(.+?)\s*(?:\(\d+\))?\s*$", line)
        if h:
            name = h.group(1).strip()
            if name.lower() != "category overview":
                current = name
            continue
        r = NEETCODE_ROW.match(line)
        if r:
            num = int(r.group(1))
            rows.append((num, squash(r.group(2)), r.group(3)))
            cats[num] = current

    # index the written notes by leading problem number
    notes: Dict[int, str] = {}
    pdir = os.path.join(REPO, "dsa", "problems")
    if os.path.isdir(pdir):
        for fn in sorted(os.listdir(pdir)):
            m = re.match(r"^(\d{3})-", fn)
            if m and fn.endswith(".md"):
                notes[int(m.group(1))] = os.path.join(pdir, fn)

    seen = set()
    for num, name, diff in rows:
        if num in seen:
            continue
        seen.add(num)
        path = notes.get(num)
        answer = extract_one_liner(read(path)) if path else ""
        slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
        out.append(new_item(
            id_=f"dsa/{num:03d}-{slug}",
            track="dsa",
            title=name,
            path=os.path.relpath(path, REPO) if path else "dsa/problems/",
            prompt=f"{name} [{diff}] — state the pattern, the invariant, and the "
                   f"time/space complexity before writing any code.",
            answer=answer or f"(no notes yet — solve it, then write dsa/problems/{num:03d}-*.md)",
        ))
        out[-1]["group"] = cats.get(num, "Uncategorised")
        out[-1]["has_notes"] = bool(path)
        out[-1]["difficulty"] = diff
    return out


def seed_dsa_patterns() -> List[dict]:
    out = []
    d = os.path.join(REPO, "dsa", "patterns")
    if not os.path.isdir(d):
        return out
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md") or fn.startswith("_"):
            continue
        path = os.path.join(d, fn)
        md = read(path)
        title = extract_h1(md) or fn[:-3]
        # first paragraph after the H1 is the pattern's summary
        body = re.sub(r"^#\s+.+?$", "", md, count=1, flags=re.M).strip()
        first = ""
        for para in body.split("\n\n"):
            p = para.strip()
            if p and not p.startswith(("---", "#", "|", ">")):
                first = squash(p, 500)
                break
        out.append(new_item(
            id_=f"dsa-patterns/{fn[:-3]}",
            track="dsa-patterns",
            title=title,
            path=os.path.relpath(path, REPO),
            prompt=f"{title} — what problem signals trigger this pattern, and what is the template?",
            answer=first or "(no summary paragraph found)",
        ))
        out[-1]["group"] = "patterns"
    return out


def seed_sys_design() -> List[dict]:
    """One item per answer document; the '###' questions inside become sub-prompts."""
    out = []
    root = os.path.join(REPO, "system-design")
    if not os.path.isdir(root):
        return out
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in sorted(filenames):
            if not fn.endswith(".md") or fn.startswith("_"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), REPO)
            if "/answers/" not in rel.replace(os.sep, "/") and not fn.endswith("design-doc.md"):
                continue
            md = read(os.path.join(dirpath, fn))
            title = extract_h1(md) or fn[:-3]
            qs = re.findall(r"^###\s+(.+?)\s*$", md, re.M)
            qs = [squash(q, 160) for q in qs if q.strip().endswith("?")][:6]
            topic = os.path.basename(dirpath if "/answers" not in rel else os.path.dirname(dirpath))
            slug = re.sub(r"[^a-z0-9]+", "-", f"{topic}-{fn[:-3]}".lower()).strip("-")
            answer = ("Key questions to be able to answer cold:\n"
                      + "\n".join(f"  • {q}" for q in qs)) if qs else squash(md[:600], 600)
            out.append(new_item(
                id_=f"sys-design/{slug}",
                track="sys-design",
                title=title,
                path=rel,
                prompt=f"{title} — whiteboard this section end to end.",
                answer=answer,
            ))
            out[-1]["group"] = topic
    return out


def build_items() -> List[dict]:
    items: List[dict] = []
    items += seed_ai_answers()
    items += _seed_concepts("ai-concepts", "ralph-concepts/concepts.json", "ai-engineering/concepts")
    items += _seed_concepts("ml-concepts", "ralph-machine-learning/concepts.json", "machine_learning/concepts")
    items += _seed_concepts("be-concepts", "ralph-backend/concepts.json", "backend/concepts")
    items += _seed_concepts("mlops-concepts", "ralph-mlops/concepts.json", "mlops/concepts")
    items += seed_ml_coding()
    items += seed_ml_sys_design()
    items += seed_data_drills()
    items += seed_dsa()
    items += seed_dsa_patterns()
    items += seed_sys_design()
    return items


# Fields regenerated from disk on every seed. Everything else is scheduling
# state and must survive re-seeding untouched.
CONTENT_FIELDS = ("track", "title", "path", "prompt", "answer", "group", "has_notes", "difficulty")


def cmd_seed(args) -> int:
    state = load_state()
    existing = items_by_id(state)
    fresh = build_items()

    added, updated = 0, 0
    for f in fresh:
        old = existing.get(f["id"])
        if old is None:
            existing[f["id"]] = f
            added += 1
        else:
            for k in CONTENT_FIELDS:
                if k in f and old.get(k) != f[k]:
                    old[k] = f[k]
                    updated += 1
            # keep derived status honest after any manual edit
            old["status"] = derive_status(old)

    fresh_ids = {f["id"] for f in fresh}
    orphans = [i for i in existing.values() if i["id"] not in fresh_ids]
    if args.prune and orphans:
        for o in orphans:
            del existing[o["id"]]

    state["items"] = list(existing.values())

    # --- migration: adopt whatever real state already exists on disk -------
    migrated = migrate_from_disk(state) if not args.no_migrate else 0

    save_state(state)
    print(f"seeded {len(state['items'])} items  (+{added} new, {updated} content fields refreshed)")
    if migrated:
        print(f"migrated {migrated} items from existing on-disk state")
    if orphans:
        word = "pruned" if args.prune else "orphaned (use --prune to remove)"
        print(f"{len(orphans)} {word}")
    return 0


def migrate_from_disk(state: dict) -> int:
    """Requirement 5: existing real progress must not read 'todo'.

    The only genuine signal on disk is that a dsa problem has a *written note file*
    with a filled-in one-liner. That means it was solved and written up, which in
    this repo's own vocabulary is at least `solo`. We seed those as a first
    successful review so they enter the schedule instead of sitting at todo.
    """
    n = 0
    on = today()
    for it in state["items"]:
        if it["track"] != "dsa" or not it.get("has_notes"):
            continue
        if it.get("last_reviewed"):
            continue  # already scheduled; never clobber
        # one prior 'good' review, backdated to the note's mtime where available
        src = os.path.join(REPO, it["path"])
        when = on
        if os.path.exists(src):
            when = dt.date.fromtimestamp(os.path.getmtime(src))
            if when > on:
                when = on
        sm2(it, RATINGS["good"], when)
        n += 1
    return n


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

def due_items(state: dict, track: Optional[str] = None, on: Optional[dt.date] = None) -> List[dict]:
    on = on or today()
    out = []
    for i in state["items"]:
        if track and i["track"] != track:
            continue
        nd = parse_date(i.get("next_due"))
        if nd is None or nd <= on:
            out.append(i)
    # never-seen first, then most overdue, then hardest
    def key(i):
        nd = parse_date(i.get("next_due"))
        overdue = (on - nd).days if nd else 10_000
        return (-overdue, float(i.get("ease") or 2.5))
    return sorted(out, key=key)


def fmt_row(i: dict, on: dt.date) -> str:
    nd = parse_date(i.get("next_due"))
    if nd is None:
        when = color("new", "cyan")
    else:
        d = (on - nd).days
        when = color(f"{d}d overdue", "red") if d > 0 else color("due", "yellow")
    status_c = {"todo": "grey", "hint": "red", "solo": "yellow",
                "review": "blue", "mastered": "green"}.get(i["status"], "grey")
    return (f"  {color(i['id'], 'bold'):<58} {color(i['status'], status_c):<9} {when}")


def cmd_due(args) -> int:
    state = load_state()
    if not state["items"]:
        print("state is empty — run: ./study/study.sh seed")
        return 1
    on = today()
    items = due_items(state, args.track, on)
    total = len(items)
    shown = items[: args.n]
    if not total:
        print(color("nothing due. next up:", "green"))
        upcoming = sorted(
            (i for i in state["items"] if parse_date(i.get("next_due"))),
            key=lambda i: i["next_due"])[:5]
        for i in upcoming:
            print(f"  {i['id']:<58} {i['next_due']}")
        return 0
    scope = f" in {args.track}" if args.track else ""
    print(color(f"{total} due{scope} (showing {len(shown)}):", "bold"))
    for i in shown:
        print(fmt_row(i, on))
    if total > len(shown):
        print(color(f"  … {total - len(shown)} more", "grey"))
    print(f"\n  drill them: {color('./study/study.sh drill' + (f' --track {args.track}' if args.track else ''), 'cyan')}")
    return 0


def cmd_next(args) -> int:
    state = load_state()
    items = due_items(state, args.track)
    if not items:
        print("nothing due.")
        return 0
    i = items[0]
    print(color(i["title"], "bold"))
    print(color(i["id"], "grey"))
    print(f"  {i['path']}")
    print(f"\n  mark it: ./study/study.sh mark {i['id']} good")
    return 0


def cmd_mark(args) -> int:
    state = load_state()
    it = resolve(state, args.id)
    key = RATING_ALIASES.get(args.rating.lower(), args.rating.lower())
    if key not in RATINGS:
        raise SystemExit(f"bad rating '{args.rating}' — use again|hard|good|easy")
    before = it.get("interval_days") or 0
    sm2(it, RATINGS[key], today())
    save_state(state)
    print(f"{color(it['id'], 'bold')}  {key}")
    print(f"  interval {before}d → {it['interval_days']}d   ease {it['ease']}   "
          f"status {it['status']}   next {it['next_due']}")
    return 0


def cmd_drill(args) -> int:
    """Retrieval practice: question first, answer hidden until you commit to a recall."""
    state = load_state()
    if not state["items"]:
        print("state is empty — run: ./study/study.sh seed")
        return 1
    on = today()
    queue = due_items(state, args.track, on)
    if not queue:
        print(color("nothing due — nice.", "green"))
        return 0
    if args.shuffle:
        random.shuffle(queue)
    queue = queue[: args.n]

    print(color(f"\n  {len(queue)} item drill — recall out loud before revealing.\n", "bold"))
    done = 0
    for idx, it in enumerate(queue, 1):
        print(color("─" * 72, "grey"))
        print(f"  {color(f'[{idx}/{len(queue)}]', 'grey')} {color(it['track'], 'cyan')}  "
              f"{color(it['status'], 'grey')}")
        print()
        for line in textwrap.wrap(it["prompt"], 68):
            print(f"  {color(line, 'bold')}")
        print()
        try:
            input(color("  ...recall it, then press Enter to reveal ", "grey"))
        except (EOFError, KeyboardInterrupt):
            print("\n  stopped.")
            break
        print()
        for line in it["answer"].split("\n"):
            for w in textwrap.wrap(line, 68) or [""]:
                print(f"  {color(w, 'green')}")
        print(color(f"\n  source: {it['path']}", "grey"))
        print()
        try:
            raw = input(color("  rate  [a]gain [h]ard [g]ood [e]asy  (Enter=good, q=quit) ", "yellow")).strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\n  stopped.")
            break
        if raw in ("q", "quit"):
            print("  stopped.")
            break
        key = RATING_ALIASES.get(raw, raw)
        if key not in RATINGS:
            key = "good"
        sm2(it, RATINGS[key], on)
        save_state(state)  # persist after every card, so a Ctrl-C loses nothing
        done += 1
        print(f"  → {color(key, 'magenta')}, next in {it['interval_days']}d ({it['next_due']})\n")

    print(color("─" * 72, "grey"))
    print(f"  reviewed {done} item(s). remaining due: {len(due_items(state, args.track, on))}")
    return 0


def track_stats(state: dict, track: str, on: dt.date) -> dict:
    items = [i for i in state["items"] if i["track"] == track]
    counts = {s: 0 for s in STATUSES}
    for i in items:
        counts[i.get("status", "todo")] = counts.get(i.get("status", "todo"), 0) + 1
    started = len(items) - counts["todo"]
    due = len([i for i in items if not i.get("next_due") or parse_date(i["next_due"]) <= on])
    return {
        "track": track, "total": len(items), "counts": counts,
        "started": started, "due": due,
        "pct": (100.0 * started / len(items)) if items else 0.0,
        "mastered_pct": (100.0 * counts["mastered"] / len(items)) if items else 0.0,
    }


def bar(pct: float, width: int = 24) -> str:
    filled = int(round(pct / 100 * width))
    return "█" * filled + "·" * (width - filled)


def cmd_progress(args) -> int:
    state = load_state()
    if not state["items"]:
        print("state is empty — run: ./study/study.sh seed")
        return 1
    on = today()
    tracks = [args.track] if args.track else TRACKS
    print()
    print(f"  {'track':<30} {'progress':<26} {'started':>9} {'mastered':>9} {'due':>6}")
    print(f"  {'-'*30} {'-'*26} {'-'*9} {'-'*9} {'-'*6}")
    tot = mast = start = duec = 0
    for t in tracks:
        s = track_stats(state, t, on)
        if not s["total"]:
            continue
        tot += s["total"]; mast += s["counts"]["mastered"]
        start += s["started"]; duec += s["due"]
        print(f"  {TRACK_LABELS.get(t, t):<30} {bar(s['pct'])} {s['started']:>4}/{s['total']:<4} "
              f"{s['counts']['mastered']:>9} {s['due']:>6}")
    print(f"  {'-'*30} {'-'*26} {'-'*9} {'-'*9} {'-'*6}")
    print(f"  {'TOTAL':<30} {bar(100.0*start/tot if tot else 0)} {start:>4}/{tot:<4} {mast:>9} {duec:>6}")
    print()
    return 0


def cmd_weak(args) -> int:
    """Weakest = actually attempted and going badly. Never-touched items are 'not started', not 'weak'."""
    state = load_state()
    on = today()
    seen = [i for i in state["items"] if i.get("reps") is not None and i.get("last_reviewed")]
    if not seen:
        print("nothing reviewed yet — run a drill first.")
        return 0

    def weakness(i: dict) -> float:
        ease = float(i.get("ease") or 2.5)
        lapses = int(i.get("lapses") or 0)
        nd = parse_date(i.get("next_due"))
        overdue = max(0, (on - nd).days) if nd else 0
        # low ease and repeated lapses dominate; overdue is a mild tiebreaker
        return (2.5 - ease) * 3.0 + lapses * 2.0 + min(overdue, 30) * 0.05

    ranked = sorted(seen, key=weakness, reverse=True)[: args.n]
    print(color("\n  weakest items (low ease · lapses · overdue)\n", "bold"))
    print(f"  {'id':<52} {'ease':>5} {'lapses':>7} {'status':<9} next")
    print(f"  {'-'*52} {'-'*5} {'-'*7} {'-'*9} {'-'*10}")
    for i in ranked:
        print(f"  {i['id']:<52} {i.get('ease', 2.5):>5} {i.get('lapses', 0):>7} "
              f"{i.get('status', 'todo'):<9} {i.get('next_due') or '—'}")

    # weakest *areas*, which is what you actually act on
    groups: Dict[Tuple[str, str], List[float]] = {}
    for i in seen:
        groups.setdefault((i["track"], i.get("group", "general")), []).append(weakness(i))
    if groups:
        print(color("\n  weakest areas\n", "bold"))
        ranked_g = sorted(groups.items(), key=lambda kv: sum(kv[1]) / len(kv[1]), reverse=True)[:8]
        for (t, g), vals in ranked_g:
            label = f"{t}/{g}"
            print(f"  {label:<46} n={len(vals):<4} score={sum(vals)/len(vals):.2f}")
    print()
    return 0


def cmd_stats(args) -> int:
    state = load_state()
    on = today()
    items = state["items"]
    if not items:
        print("state is empty — run: ./study/study.sh seed")
        return 1
    counts = {s: 0 for s in STATUSES}
    for i in items:
        counts[i.get("status", "todo")] = counts.get(i.get("status", "todo"), 0) + 1
    d = len(due_items(state, None, on))
    print(f"{len(items)} items · {counts['todo']} todo · {counts['hint']} hint · "
          f"{counts['solo']} solo · {counts['review']} review · {counts['mastered']} mastered · {d} due")
    return 0


# ---------------------------------------------------------------------------
# Generated views
# ---------------------------------------------------------------------------

GEN_WARNING = "<!-- GENERATED by study/study.py — do not hand-edit. Run: ./study/study.sh render -->"


def broken_paths(state: dict) -> List[str]:
    """A generated view is only useful if its links land. Check before claiming success."""
    return sorted({i["path"] for i in state["items"]
                   if not os.path.exists(os.path.join(REPO, i["path"]))})


def cmd_render(args) -> int:
    state = load_state()
    if not state["items"]:
        print("state is empty — run: ./study/study.sh seed")
        return 1
    on = today()
    write_progress_md(state, on)
    write_dsa_progress_md(state, on)
    print(f"wrote {os.path.relpath(PROGRESS_PATH, REPO)} and {os.path.relpath(DSA_PROGRESS_PATH, REPO)}")
    bad = broken_paths(state)
    if bad:
        print(color(f"warning: {len(bad)} item path(s) do not exist — links in the "
                    f"generated views will not resolve:", "yellow"))
        for b in bad[:5]:
            print(f"  {b}")
        if len(bad) > 5:
            print(f"  ... and {len(bad) - 5} more")
    return 0


def write_progress_md(state: dict, on: dt.date) -> None:
    L: List[str] = []
    L.append("# Study Progress")
    L.append("")
    L.append(GEN_WARNING)
    L.append("")
    L.append(f"Generated {on.isoformat()} from `study/state.json`.")
    L.append("")
    L.append("Daily loop: `./study/study.sh due` → `./study/study.sh drill`. "
             "See [`study/README.md`](README.md).")
    L.append("")
    L.append("## Summary")
    L.append("")
    L.append("| Track | Started | Total | Mastered | Due today |")
    L.append("|-------|---------|-------|----------|-----------|")
    tot = start = mast = duec = 0
    for t in TRACKS:
        s = track_stats(state, t, on)
        if not s["total"]:
            continue
        tot += s["total"]; start += s["started"]
        mast += s["counts"]["mastered"]; duec += s["due"]
        L.append(f"| {TRACK_LABELS.get(t, t)} | {s['started']} | {s['total']} "
                 f"| {s['counts']['mastered']} | {s['due']} |")
    L.append(f"| **Total** | **{start}** | **{tot}** | **{mast}** | **{duec}** |")
    L.append("")
    L.append("## Status vocabulary")
    L.append("")
    L.append("| Status | Meaning |")
    L.append("|--------|---------|")
    L.append("| `todo` | Never reviewed |")
    L.append("| `hint` | Last attempt needed help (rated again/hard) |")
    L.append("| `solo` | Recalled unaided, interval < 21d |")
    L.append("| `review` | Interval 21–59d |")
    L.append("| `mastered` | Interval ≥ 60d after ≥ 4 successful reviews |")
    L.append("")
    for t in TRACKS:
        items = sorted((i for i in state["items"] if i["track"] == t), key=lambda i: i["id"])
        if not items:
            continue
        L.append(f"## {TRACK_LABELS.get(t, t)}")
        L.append("")
        L.append("| Item | Status | Reps | Ease | Last | Next |")
        L.append("|------|--------|------|------|------|------|")
        for i in items:
            short = i["id"].split("/", 1)[-1]
            L.append(f"| [{short}]({os.path.relpath(os.path.join(REPO, i['path']), os.path.dirname(PROGRESS_PATH))}) "
                     f"| `{i['status']}` | {i.get('reps', 0)} | {i.get('ease', 2.5)} "
                     f"| {i.get('last_reviewed') or '—'} | {i.get('next_due') or '—'} |")
        L.append("")
    with open(PROGRESS_PATH, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L).rstrip() + "\n")


def write_dsa_progress_md(state: dict, on: dt.date) -> None:
    """dsa/progress.md was a dead hand-maintained table. It is now a generated view."""
    items = [i for i in state["items"] if i["track"] == "dsa"]
    if not items:
        return
    by_group: Dict[str, List[dict]] = {}
    for i in items:
        by_group.setdefault(i.get("group", "Uncategorised"), []).append(i)

    counts = {s: 0 for s in STATUSES}
    for i in items:
        counts[i.get("status", "todo")] = counts.get(i.get("status", "todo"), 0) + 1

    L: List[str] = []
    L.append("# NeetCode 150 — Progress")
    L.append("")
    L.append(GEN_WARNING)
    L.append("")
    L.append("Single source of truth is `study/state.json`. Do not edit this table by hand —")
    L.append("mark progress with `./study/study.sh mark <id> <rating>` or `./study/study.sh drill --track dsa`,")
    L.append("then `./study/study.sh render`.")
    L.append("")
    L.append("**Status:** `todo` · `hint` · `solo` · `review` · `mastered` "
             "(scheduling is SM-2, not a fixed ladder)")
    L.append("")
    L.append("---")
    L.append("")
    L.append("## Summary")
    L.append("")
    L.append("| Metric | Count |")
    L.append("|--------|-------|")
    L.append(f"| Mastered | {counts['mastered']} |")
    L.append(f"| Review | {counts['review']} |")
    L.append(f"| Solo | {counts['solo']} |")
    L.append(f"| Needs work (hint) | {counts['hint']} |")
    L.append(f"| Todo | {counts['todo']} |")
    L.append(f"| **Total** | **{len(items)}** |")
    L.append("")
    L.append("---")
    L.append("")
    for g, rows in by_group.items():
        L.append(f"## {g}")
        L.append("")
        L.append("| # | Problem | Difficulty | Notes | Status | Last | Next |")
        L.append("|---|---------|------------|-------|--------|------|------|")
        for i in sorted(rows, key=lambda r: r["id"]):
            num = i["id"].split("/")[-1][:3]
            name = i["title"]
            notes = f"[`{os.path.basename(i['path'])}`](problems/{os.path.basename(i['path'])})" \
                if i.get("has_notes") else "—"
            L.append(f"| {int(num)} | {name} | {i.get('difficulty', '—')} | {notes} "
                     f"| `{i['status']}` | {i.get('last_reviewed') or '—'} "
                     f"| {i.get('next_due') or '—'} |")
        L.append("")
    with open(DSA_PROGRESS_PATH, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L).rstrip() + "\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(
        prog="study",
        description="Spaced-repetition retrieval practice over this repo (SM-2).")
    sub = p.add_subparsers(dest="cmd")

    s = sub.add_parser("seed", help="build/refresh state.json from disk (idempotent)")
    s.add_argument("--prune", action="store_true", help="drop items whose source file is gone")
    s.add_argument("--no-migrate", action="store_true", help="skip seeding state from on-disk progress")
    s.set_defaults(fn=cmd_seed)

    s = sub.add_parser("due", help="what is due today")
    s.add_argument("--track", choices=TRACKS)
    s.add_argument("-n", type=int, default=20)
    s.set_defaults(fn=cmd_due)

    s = sub.add_parser("drill", help="retrieval practice: ask, hide, reveal, rate")
    s.add_argument("--track", choices=TRACKS)
    s.add_argument("-n", type=int, default=10)
    s.add_argument("--shuffle", action="store_true")
    s.set_defaults(fn=cmd_drill)

    s = sub.add_parser("mark", help="mark one item reviewed")
    s.add_argument("id")
    s.add_argument("rating", nargs="?", default="good")
    s.set_defaults(fn=cmd_mark)

    s = sub.add_parser("progress", help="progress per track")
    s.add_argument("--track", choices=TRACKS)
    s.set_defaults(fn=cmd_progress)

    s = sub.add_parser("weak", help="weakest items and areas")
    s.add_argument("-n", type=int, default=15)
    s.set_defaults(fn=cmd_weak)

    s = sub.add_parser("next", help="single highest-priority item")
    s.add_argument("--track", choices=TRACKS)
    s.set_defaults(fn=cmd_next)

    s = sub.add_parser("render", help="regenerate study/PROGRESS.md and dsa/progress.md")
    s.set_defaults(fn=cmd_render)

    s = sub.add_parser("stats", help="one-line summary")
    s.set_defaults(fn=cmd_stats)

    args = p.parse_args(argv)
    if not getattr(args, "fn", None):
        p.print_help()
        return 1
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
