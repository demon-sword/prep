# Permutation in String — Medium — Fixed window + freq match (Sliding Window)

**LC:** https://leetcode.com/problems/permutation-in-string/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "permutation of s1" **contained in** s2 / substring that is an anagram of s1
- "any permutation" / "rearrangement" of one string inside another
- fixed window length equals `length(s1)` — not variable-length optimization
- boolean existence check, not max/min length

### Constraints that matter
- Lengths up to 10⁴ → O(n·m) brute force TLE; need O(n) single pass with sliding window
- Only lowercase English letters → freq maps of size O(26)
- Empty s1 is a permutation of any substring (edge case: return true if s1 empty)

### Pattern
Fixed window — size k = `length(s1)`: slide through s2, maintain char frequencies in the current window, compare incrementally to s1's freq map.

---

## Approach

### Invariant
When `right ≥ k - 1`, window `[right - k + 1 .. right]` has exactly k characters. `have` tracks window frequencies; `matches` counts how many distinct characters c satisfy `have[c] == need[c]`. Window is a permutation of s1 iff `matches == required`, where `required` is the number of distinct chars in s1 with positive frequency.

### Steps
1. If `length(s1) > length(s2)`, return false. Build `need` from freq count of s1; set `required` = distinct chars in need.
2. Initialize `left ← 0`, `have` empty counter, `matches ← 0`, `k ← length(s1)`.
3. For each `right` from 0 to length(s2) - 1:
   - Add `s2[right]` to `have`; if its count now equals `need[s2[right]]`, increment `matches`.
   - If `right >= k`: remove `s2[right - k]` from window (decrement `have`; if count drops below `need`, decrement `matches`).
   - If `matches == required`, return true (found a length-k window matching s1's multiset).
4. Return false.

### Pseudocode skeleton
```
function checkInclusion(s1, s2):
    k ← length(s1)
    if k > length(s2):
        return false

    need ← freq count of s1
    required ← number of distinct chars c where need[c] > 0
    have ← empty map from char to count
    matches ← 0

    for right from 0 to length(s2) - 1:
        c ← s2[right]
        have[c] ← have[c] + 1
        if have[c] equals need[c]:
            matches ← matches + 1

        if right >= k:
            leftChar ← s2[right - k]
            if have[leftChar] equals need[leftChar]:
                matches ← matches - 1
            have[leftChar] ← have[leftChar] - 1

        if matches equals required:
            return true

    return false
```

### Complexity
| | |
|-|-|
| **Time** | O(n + m) where n = length(s1), m = length(s2) — each index visited once |
| **Space** | O(1) — at most 26 letter counts in `need` and `have` |

---

## Tradeoffs

### Brute force
For every start index `i` in s2 where a length-k substring fits, extract `s2[i..i+k-1]`, sort both strings (or count freqs from scratch) and compare — O(m · k log k) or O(m · k) time. With m, k up to 10⁴ this is too slow.

### Why this pattern
Window size is fixed by definition of permutation (same length as s1). Sliding one char in and one char out updates frequencies in O(1); the `matches` counter avoids comparing full maps each step.

### When NOT to use this
- **Variable-length** anagram search (e.g. minimum window containing all chars of t) → shortest valid variable window ([Minimum Window Substring](../problems/019-minimum-window-substring.md)).
- **Count** how many permutation substrings exist → fixed window still works but accumulate count instead of early return.
- **Permutation of array** without contiguous requirement → not sliding window; backtracking or sorting.

---

## Pitfalls
- **Comparing full freq maps every step** — correct but wasteful; track `matches` and update only when a char's count crosses the `need` threshold.
- **Forgetting to decrement `matches` before removing the left char** — check equality **before** decrementing `have[leftChar]`, or you miss the transition from matched to unmatched.
- **Off-by-one on window size** — only check `matches == required` after the window has k chars (`right >= k - 1`); removing at `right >= k` keeps window size exactly k.
- **Sorting each window to detect anagram** — O(k log k) per position; freq counter is O(1) per slide with O(26) space.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Minimum Window Substring](../problems/019-minimum-window-substring.md) | Variable window + freq targets; shortest substring containing all of t |
| [Longest Repeating Character Replacement](../problems/017-longest-repeating-character-replacement.md) | String window + freq map; variable length with replacement budget |
| [Longest Substring Without Repeating Characters](../problems/016-longest-substring-without-repeating-characters.md) | Variable window on strings; validity via duplicate detection |

---

## One-liner recall

> Slide a length-k window over s2; incrementally match char freqs to s1 via a `matches` counter; return true when all distinct chars align.
