# Minimum Window Substring — Hard — Variable window — shortest valid (Sliding Window)

**LC:** https://leetcode.com/problems/minimum-window-substring/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "minimum window substring" of s that **contains all** characters of t
- shortest substring of s that includes every char from t (with required multiplicities)
- cover / include all characters of t — not necessarily in order
- return the actual substring, or `""` if none exists

### Constraints that matter
- Lengths up to 10⁵ → O(n²) brute force TLE; need O(n) sliding window
- t can have duplicate characters — must satisfy **frequency**, not just set membership
- Only uppercase and lowercase English letters → freq maps of size O(52) or O(1) alphabet

### Pattern
Variable window — shortest valid: expand `right` until the window covers all of t's char counts; shrink `left` while still valid, recording the minimum-length window at each valid step.

---

## Approach

### Invariant
`have[c]` tracks how many times char `c` appears in the current window `[left .. right]`. `formed` counts distinct chars c where `have[c] >= need[c]`. Window is **valid** when `formed == required`, where `required` is the number of distinct chars in t with positive frequency in `need`.

### Steps
1. Build `need` from frequency count of t. Set `required` = number of distinct chars with `need[c] > 0`. If t is empty, return `""`.
2. Initialize `left ← 0`, `have` empty counter, `formed ← 0`, `bestLen ← infinity`, `bestStart ← 0`.
3. For each `right` from 0 to length(s) - 1:
   - Add `s[right]` to `have`. If `have[s[right]]` now equals `need[s[right]]`, increment `formed`.
   - While `formed == required` (window valid):
     - If `right - left + 1 < bestLen`, update `bestLen` and `bestStart ← left`.
     - Remove `s[left]` from `have`; if count drops below `need[s[left]]`, decrement `formed`.
     - `left ← left + 1`.
4. Return `s[bestStart .. bestStart + bestLen - 1]` if `bestLen` is finite, else `""`.

### Pseudocode skeleton
```
function minWindow(s, t):
    if length(t) equals 0:
        return ""

    need ← freq count of t
    required ← count of distinct chars c where need[c] > 0
    have ← empty map from char to count
    formed ← 0
    left ← 0
    bestLen ← infinity
    bestStart ← 0

    for right from 0 to length(s) - 1:
        c ← s[right]
        have[c] ← have[c] + 1
        if have[c] equals need[c]:
            formed ← formed + 1

        while formed equals required:
            windowLen ← right - left + 1
            if windowLen < bestLen:
                bestLen ← windowLen
                bestStart ← left

            leftChar ← s[left]
            have[leftChar] ← have[leftChar] - 1
            if have[leftChar] < need[leftChar]:
                formed ← formed - 1
            left ← left + 1

    if bestLen equals infinity:
        return ""
    return substring s from bestStart of length bestLen
```

### Complexity
| | |
|-|-|
| **Time** | O(n + m) where n = length(s), m = length(t) — each pointer moves at most n steps |
| **Space** | O(1) — at most 52 letter counts in `need` and `have` |

---

## Tradeoffs

### Brute force
For every start index `i` in s, grow end `j` until all chars of t are covered (or give up), track minimum valid `[i..j]`. Each start may scan O(n) positions and recount frequencies — O(n²) or O(n² · σ) time. Too slow for n = 10⁵.

### Why this pattern
Validity is **monotonic**: adding to the right can only help coverage; removing from the left can only hurt. Once valid, shrinking while still valid explores all minimum windows ending at `right` without restarting from scratch.

### When NOT to use this
- **Fixed-length** cover (same length as t) → fixed window + freq match ([Permutation in String](../problems/018-permutation-in-string.md)).
- **Count** windows containing t, not minimum length → same expand logic but count valid windows instead of tracking min length.
- **Subsequence** cover (chars need not be contiguous) → DP or greedy with two pointers on t, not sliding window.

---

## Pitfalls
- **Treating t as a set instead of a multiset** — if t = `"aab"`, window must contain two `'a'` and one `'b'`; `formed` must compare counts, not just presence.
- **Updating best length before the window is valid** — only record `bestLen` inside the `while formed == required` loop, after expansion made the window valid.
- **Stopping shrink too early** — shrink while **still** valid (`formed == required` after each removal); the window after removal might still be valid and shorter.
- **Decrementing `formed` after removing left char incorrectly** — check `have[leftChar] < need[leftChar]` **after** decrementing count, not before.
- **Returning wrong bounds** — store `bestStart` and `bestLen`, not `left`/`right` at loop exit (pointers keep moving past the optimal window).

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Permutation in String](../problems/018-permutation-in-string.md) | Fixed k window + freq match; boolean "contains anagram" instead of shortest cover |
| [Longest Repeating Character Replacement](../problems/017-longest-repeating-character-replacement.md) | Variable window + freq map; maximize length with a budget instead of minimize with full cover |
| [Longest Substring Without Repeating Characters](../problems/016-longest-substring-without-repeating-characters.md) | Variable window on strings; expand/shrink with different validity rule |

---

## One-liner recall

> Expand until all t-char counts are met (`formed == required`), then shrink from the left while still valid, keeping the shortest window seen.
