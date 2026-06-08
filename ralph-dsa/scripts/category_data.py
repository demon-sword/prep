"""NeetCode 150 category metadata — single source for scaffold + validate."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

PREP_ROOT = Path(__file__).resolve().parents[2]
LIST_MD = PREP_ROOT / "dsa" / "neetcode-150-list.md"

SLUG_BY_NUM = {
    1: "01-arrays-hashing",
    2: "02-two-pointers",
    3: "03-sliding-window",
    4: "04-stack",
    5: "05-binary-search",
    6: "06-linked-list",
    7: "07-trees",
    8: "08-tries",
    9: "09-heap",
    10: "10-backtracking",
    11: "11-graphs",
    12: "12-advanced-graphs",
    13: "13-1d-dp",
    14: "14-2d-dp",
    15: "15-greedy",
    16: "16-intervals",
    17: "17-math-geometry",
    18: "18-bit-manipulation",
}


@dataclass(frozen=True)
class Problem:
    num: int
    name: str
    difficulty: str
    lc_url: str

    @property
    def slug(self) -> str:
        s = re.sub(r"[^\w\s-]", "", self.name.lower())
        s = re.sub(r"[\s_]+", "-", s).strip("-")
        return f"{self.num:03d}-{s}"

    @property
    def file(self) -> str:
        return f"problems/{self.slug}.md"


@dataclass(frozen=True)
class Category:
    num: int
    name: str
    slug: str
    problems: tuple[Problem, ...]

    @property
    def pattern_file(self) -> str:
        return f"patterns/{self.slug}.md"


def _slugify_name(name: str) -> str:
    s = re.sub(r"[^\w\s-]", "", name.lower())
    return re.sub(r"[\s_]+", "-", s).strip("-")


def parse_neetcode_list(path: Path = LIST_MD) -> list[Category]:
    text = path.read_text(encoding="utf-8")
    categories: list[Category] = []
    current_num: int | None = None
    current_name: str | None = None
    problems: list[Problem] = []

    def flush() -> None:
        nonlocal current_num, current_name, problems
        if current_num is None or current_name is None:
            return
        slug = SLUG_BY_NUM.get(current_num, f"{current_num:02d}-{_slugify_name(current_name)}")
        categories.append(
            Category(
                num=current_num,
                name=current_name,
                slug=slug,
                problems=tuple(problems),
            )
        )
        problems = []

    for line in text.splitlines():
        header = re.match(r"^##\s+(\d+)\.\s+(.+?)\s+\(\d+\)\s*$", line)
        if header:
            flush()
            current_num = int(header.group(1))
            current_name = header.group(2).strip()
            continue

        row = re.match(
            r"^\|\s+(\d+)\s+\|\s+([^|]+?)\s+\|\s+(Easy|Medium|Hard)\s+\|\s+\[(\d+)\]\((https://leetcode.com/problems/[^)]+)\)\s+\|",
            line,
        )
        if row and current_num is not None:
            problems.append(
                Problem(
                    num=int(row.group(1)),
                    name=row.group(2).strip(),
                    difficulty=row.group(3),
                    lc_url=row.group(5),
                )
            )

    flush()
    return categories


def get_category(slug: str) -> Category:
    for cat in parse_neetcode_list():
        if cat.slug == slug:
            return cat
    known = ", ".join(c.slug for c in parse_neetcode_list())
    raise SystemExit(f"Unknown category slug: {slug}\nKnown: {known}")


if __name__ == "__main__":
    for c in parse_neetcode_list():
        print(f"{c.slug}: {len(c.problems)} problems (#{c.problems[0].num}–#{c.problems[-1].num})")
