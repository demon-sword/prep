"""AI engineering interview category metadata — single source for scaffold + validate."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

PREP_ROOT = Path(__file__).resolve().parents[2]
QUESTIONS_MD = PREP_ROOT / "ai-engineering" / "interview-questions.md"

# Maps category slug → source section number in interview-questions.md
SECTION_BY_SLUG: dict[str, int] = {
    "01-llm-fundamentals":     1,
    "02-rag-systems":          2,
    "03-agents-tool-use":      3,
    "04-fine-tuning-training": 4,
    "05-evaluation-metrics":   5,
    "06-ml-fundamentals":      6,
    "07-cost-latency":         9,   # §9, not §7
    "08-safety-guardrails":   10,
    "09-system-design-ai":    11,
    "10-behavioral":          18,
}

# Human-readable names (used in plan.md and progress.txt)
NAME_BY_SLUG: dict[str, str] = {
    "01-llm-fundamentals":     "LLM Fundamentals",
    "02-rag-systems":          "RAG Systems",
    "03-agents-tool-use":      "Agents & Tool Use",
    "04-fine-tuning-training": "Fine-Tuning & Training",
    "05-evaluation-metrics":   "Evaluation & Metrics",
    "06-ml-fundamentals":      "ML Fundamentals",
    "07-cost-latency":         "Cost & Latency Optimization",
    "08-safety-guardrails":    "Safety & Guardrails",
    "09-system-design-ai":     "System Design — AI",
    "10-behavioral":           "Behavioral",
}

# Canonical ordering — cat_num (1-based) is the position in this list.
# This drives the NN- file prefix, independent of source section number.
SLUGS_IN_ORDER = list(SECTION_BY_SLUG.keys())


def _slugify(text: str, maxlen: int = 60) -> str:
    """Lowercase, strip non-word chars, collapse whitespace→dash, cap at maxlen."""
    s = re.sub(r"[^\w\s-]", "", text.lower())
    s = re.sub(r"[\s_]+", "-", s).strip("-")
    return s[:maxlen].rstrip("-")  # rstrip prevents trailing dash after truncation


@dataclass(frozen=True)
class Question:
    num: int        # sequential within category (1-based)
    cat_num: int    # category number 1–10 (drives the NN- file prefix)
    text: str       # verbatim question text (⭐ etc. preserved for display)

    @property
    def slug(self) -> str:
        return _slugify(self.text)

    @property
    def file(self) -> str:
        return f"answers/{self.cat_num:02d}-{self.num:03d}-{self.slug}.md"


@dataclass(frozen=True)
class Category:
    num: int                      # 1–10 (position in SLUGS_IN_ORDER)
    slug: str                     # e.g. "02-rag-systems"
    name: str                     # e.g. "RAG Systems"
    source_section: int           # section number in interview-questions.md
    questions: tuple[Question, ...]

    @property
    def category_file(self) -> str:
        return f"categories/{self.slug}.md"


def _parse_questions(path: Path = QUESTIONS_MD) -> dict[int, list[str]]:
    """
    Parse interview-questions.md → {section_number: [question_text, ...]}.

    Captures:
      - Lines starting with `- `   (bullet items)
      - Lines starting with `N. `  (numbered items — §9 uses these for its top-3)

    Sub-headings (###) and blank lines are skipped.
    Question text stored verbatim (⭐ etc. kept; stripped in _slugify).
    """
    text = path.read_text(encoding="utf-8")
    result: dict[int, list[str]] = {}
    current_section: int | None = None

    for line in text.splitlines():
        # Top-level section heading: ## N. Title
        header = re.match(r"^## (\d+)\.\s+(.+)", line)
        if header:
            current_section = int(header.group(1))
            result[current_section] = []
            continue

        if current_section is None:
            continue

        # Bullet item
        bullet = re.match(r"^- (.+)", line)
        if bullet:
            result[current_section].append(bullet.group(1).strip())
            continue

        # Numbered item (e.g. "1. Your app gets 1M queries/day…")
        numbered = re.match(r"^\d+\. (.+)", line)
        if numbered:
            result[current_section].append(numbered.group(1).strip())

    return result


def parse_all_categories(path: Path = QUESTIONS_MD) -> list[Category]:
    """Parse interview-questions.md and return all 10 categories in canonical order."""
    raw = _parse_questions(path)
    categories = []
    for cat_num_1based, slug in enumerate(SLUGS_IN_ORDER, start=1):
        sec_num = SECTION_BY_SLUG[slug]
        name = NAME_BY_SLUG[slug]
        raw_questions = raw.get(sec_num, [])
        questions = tuple(
            Question(num=i, cat_num=cat_num_1based, text=q)
            for i, q in enumerate(raw_questions, start=1)
        )
        categories.append(Category(
            num=cat_num_1based,
            slug=slug,
            name=name,
            source_section=sec_num,
            questions=questions,
        ))
    return categories


def get_category(slug: str, path: Path = QUESTIONS_MD) -> Category:
    """Return the Category for the given slug, or exit with an error."""
    for cat in parse_all_categories(path):
        if cat.slug == slug:
            return cat
    known = "\n  ".join(SLUGS_IN_ORDER)
    raise SystemExit(f"Unknown category slug: {slug!r}\nKnown slugs:\n  {known}")


if __name__ == "__main__":
    for cat in parse_all_categories():
        first = cat.questions[0].file if cat.questions else "—"
        print(
            f"{cat.slug}: {len(cat.questions)} questions "
            f"(§{cat.source_section})  first→ {first}"
        )
