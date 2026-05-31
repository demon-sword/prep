# Longest Substring Without Repeating Characters — Medium — Variable window longest valid (Sliding Window)

**LC:** https://leetcode.com/problems/longest-substring-without-repeating-characters/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "longest substring" / "longest length" of a substring
- "without repeating characters" / "all unique" / "no duplicate"
- "contiguous characters" in a string
- classic warm-up for sliding window on strings

### Constraints that matter
- Length up to 5×10⁴ → O(n²) nested loops TLE; need O(n) single pass
- ASCII or Unicode — map/set size bounded by alphabet (O(1) or O(σ) space)
- Empty string → answer 0; single char → answer 1

### Pattern
Variable window — longest valid: expand `right`, shrink `left` while the window contains a duplicate, track max length when valid.

---

## Approach

### Invariant
For window `[left..right]`, every character appears at most once. `lastSeen[c]` stores the most recent index of character `c` inside the current valid window (or -1 if absent).

### Steps
1. Initialize `left ← 0`, `best ← 0`, `lastSeen` as empty map (char → index).
2. For each `right` from 0 to length(s) - 1:
   - If `s[right]` was seen at index `prev` and `prev >= left`, jump `left` to `prev + 1` (duplicate inside window).
   - Record `lastSeen[s[right]] ← right`.
   - Update `best ← max(best, right - left + 1)`.
3. Return `best`.

Alternative (explicit shrink loop): add `s[right]` to a freq map; while freq > 1, remove `s[left]` and increment `left`; then update best.

### Pseudocode skeleton
```
function lengthOfLongestSubstring(s):
    if length(s) equals 0:
        return 0

    left ← 0
    best ← 0
    lastSeen ← empty map from char to index

    for right from 0 to length(s) - 1:
        c ← s[right]

        if c in lastSeen and lastSeen[c] >= left:
            // duplicate inside current window — shrink from left past prior c
            left ← lastSeen[c] + 1

        lastSeen[c] ← right
        best ← max(best, right - left + 1)

    return best
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each index visited by `right` once; `left` only moves forward |
| **Space** | O(min(n, σ)) — map holds at most one entry per distinct char in window |

---

## Tradeoffs

### Brute force
For every start index `i`, extend `j` while chars in `s[i..j]` are unique (use a set), track max length — O(n²) time in worst case (all unique), O(min(n, σ)) space per window. Clear but TLE at n = 5×10⁴.

### Why this pattern
Validity is **monotonic**: adding a char can only introduce one duplicate; removing from the left restores uniqueness. A two-pointer window with incremental state gives O(n) without rescanning the whole window.

### When NOT to use this
- **Longest subsequence** without repeats — not contiguous; DP or greedy on indices, not sliding window.
- **At most K distinct** or **K replacements allowed** — same expand/shrink shape but need freq counts and different validity checks (see #17).
- **Count** all substrings without repeats — different problem; may need combinatorics or contribution technique, not just max length.

---

## Pitfalls
- **Not moving `left` when duplicate is outside window** — if `lastSeen[c] < left`, the old occurrence is already excluded; only jump when `lastSeen[c] >= left`.
- **Updating best before fixing duplicate** — window length after expand may include two copies of `c`; either shrink with a while-loop until valid, or jump `left` first, then update best.
- **Off-by-one on jump** — set `left ← lastSeen[c] + 1`, not `lastSeen[c]`, so the duplicate char is excluded from the window.
- **Using a set without removing on shrink** — if you only add on expand and jump `left` without deleting stale chars from a set, the set can lie; prefer last-index map or remove `s[left]` in the shrink loop.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Longest Repeating Character Replacement](../problems/017-longest-repeating-character-replacement.md) | Same longest-valid variable window; allows K replacements instead of zero duplicates |
| [Minimum Window Substring](../problems/019-minimum-window-substring.md) | Variable window on strings; optimize **shortest** valid window instead of longest |
| [Permutation in String](../problems/018-permutation-in-string.md) | Fixed-size window + freq match; checks existence of length-k valid window |

---

## One-liner recall

> Expand right; if char seen inside window, jump left past its last index; track max `right - left + 1`.
