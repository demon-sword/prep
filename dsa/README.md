# DSA Prep (NeetCode 150)

Pattern-first coding interview prep. Notes are **recall cards**, not textbooks — each file should be scannable in under 2 minutes.

## How to study

1. **Attempt first** — 20–25 min on LeetCode before notes or video.
2. **Write immediately** — copy `problems/_template.md` while the solution is fresh (5–10 min).
3. **Re-solve next day** — from the one-liner only, no video.
4. **Synthesize by topic** — after finishing a NeetCode category, update the matching file in `patterns/`.
5. **Review on schedule** — day 1 → day 3 → day 7 → day 14 until status is `mastered`.

## Status legend

| Status | Meaning |
|--------|---------|
| `todo` | Not attempted |
| `hint` | Needed hint or partial solution |
| `solo` | Solved without help |
| `review` | Solved but needs spaced repetition |
| `mastered` | Can re-derive code and explain tradeoffs cold |

## Folder layout

```
dsa/
├── README.md                    # this file — conventions & workflow
├── neetcode-150-list.md         # all 150 problems — category, #, difficulty, LC links
├── progress.md                  # all 150 problems — status & review dates
├── patterns/
│   ├── recognition-guide.md     # phrase → pattern decision map
│   ├── _template.md             # copy when adding a new pattern doc
│   └── …                        # one file per NeetCode category
└── problems/
    ├── _template.md             # copy for each problem note
    └── …                        # e.g. 001-two-sum.md
```

## What to write (two layers)

| Layer | File | When | Goal |
|-------|------|------|------|
| **Problem card** | `problems/<slug>.md` | After every attempt | Personal recall: pattern, skeleton, pitfalls |
| **Pattern doc** | `patterns/<topic>.md` | After finishing a category | Synthesis: when to use, sub-patterns, templates |

**Rule:** If you solved it cleanly and it's a repeat of an earlier pattern, skip a full problem note — update `progress.md` and add the problem to the pattern doc's list only.

## Per-problem format

Use three parts (compressed from system-design notes):

1. **Framing** — trigger phrases + constraints that pick the pattern
2. **Approach** — invariant, algorithm steps, pseudocode skeleton
3. **Tradeoffs** — brute force vs optimal; when *not* to use this pattern

See [`problems/_template.md`](./problems/_template.md).

## Pattern doc format

Each pattern file covers:

1. **Recognition** — problem signals (what you read in the prompt)
2. **Sub-patterns** — variants (e.g. sliding window: fixed vs variable)
3. **Templates** — minimal pseudocode skeletons (language-agnostic)
4. **Anti-patterns** — common wrong routes
5. **NeetCode problems** — checklist for that bucket

See [`patterns/_template.md`](./patterns/_template.md) and [`patterns/recognition-guide.md`](./patterns/recognition-guide.md).

## Naming conventions

- **Problems:** `NNN-slug.md` — zero-padded number + kebab-case slug, e.g. `003-longest-substring-without-repeating.md`
- **Patterns:** `NN-topic-slug.md` — prefix matches NeetCode order, e.g. `03-sliding-window.md`

## What to include vs skip

| Include | Skip |
|---------|------|
| Pattern name + trigger phrases | Full NeetCode transcript |
| Pseudocode skeleton (10–20 lines) | Language-specific implementations |
| Pitfalls *you* hit | Line-by-line commented solution |
| Similar / follow-up problems | Proof-level theory |
| Status + review dates | Copy-paste from editorial |

## Quick links

- [NeetCode 150 problem list](./neetcode-150-list.md)
- [Progress tracker](./progress.md)
- [Pattern recognition guide](./patterns/recognition-guide.md)
- [Problem note template](./problems/_template.md)
- [Pattern doc template](./patterns/_template.md)
- [Ralph DSA generator](../ralph-dsa/README.md) — auto-generate notes one category at a time

## Ralph loop (optional)

Generate notes for one NeetCode category:

```bash
./ralph-dsa/scaffold.sh 01-arrays-hashing
./ralph-dsa/loop.sh 01-arrays-hashing 15
./ralph-dsa/validate.sh 01-arrays-hashing
```

Then scaffold the next category (`02-two-pointers`, etc.). See [`ralph-dsa/README.md`](../ralph-dsa/README.md).
