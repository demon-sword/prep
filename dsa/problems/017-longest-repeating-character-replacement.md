# Longest Repeating Character Replacement — Medium — Variable window longest valid + freq (Sliding Window)

**LC:** https://leetcode.com/problems/longest-repeating-character-replacement/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "longest substring" with **at most k** changes / replacements / flips
- "same letter" / "repeating character" after replacing at most k chars
- "contiguous" substring in a string
- window validity tied to **frequency** of the dominant character

### Constraints that matter
- Length up to 10⁵ → O(n²) brute force TLE; need O(n) sliding window
- k can be 0 (degenerates to longest run of one char) or as large as n
- Only uppercase English letters → freq map size O(26)

### Pattern
Variable window — longest valid: expand `right`, shrink `left` while replacements needed exceed k; track max window length when valid.

---

## Approach

### Invariant
For window `[left..right]`, let `maxFreq` be the count of the most frequent character in that window. The window is **valid** when  
`(right - left + 1) - maxFreq ≤ k`  
(i.e. you can replace all non-dominant chars in at most k operations). When invalid, shrink from `left` until the inequality holds.

### Steps
1. Initialize `left ← 0`, `best ← 0`, `freq` as char → count map, `maxFreq ← 0`.
2. For each `right` from 0 to length(s) - 1:
   - Increment `freq[s[right]]`; set `maxFreq ← max(maxFreq, freq[s[right]])`.
   - While `(right - left + 1) - maxFreq > k`:
     - Decrement `freq[s[left]]`; increment `left`.
   - Set `best ← max(best, right - left + 1)`.
3. Return `best`.

Note: `maxFreq` is not decremented on shrink — it may overestimate the true max inside the window, which only makes the shrink loop run longer but never accepts an invalid window as the answer.

### Pseudocode skeleton
```
function characterReplacement(s, k):
    if length(s) equals 0:
        return 0

    left ← 0
    best ← 0
    maxFreq ← 0
    freq ← empty map from char to count

    for right from 0 to length(s) - 1:
        c ← s[right]
        freq[c] ← freq[c] + 1
        maxFreq ← max(maxFreq, freq[c])

        windowLen ← right - left + 1
        replacementsNeeded ← windowLen - maxFreq

        while replacementsNeeded > k:
            leftChar ← s[left]
            freq[leftChar] ← freq[leftChar] - 1
            left ← left + 1
            windowLen ← right - left + 1
            replacementsNeeded ← windowLen - maxFreq

        best ← max(best, right - left + 1)

    return best
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — `right` advances once; `left` advances at most n times total |
| **Space** | O(1) — at most 26 letter counts in `freq` |

---

## Tradeoffs

### Brute force
For every pair `(left, right)`, count char frequencies in `s[left..right]`, compute max freq, check if `length - maxFreq ≤ k`, track longest — O(n²) time, O(1) or O(26) space per window. Simple to reason about but TLE at n = 10⁵.

### Why this pattern
Adding one char at `right` changes validity in a predictable way; shrinking `left` monotonically restores validity. Incremental freq updates avoid recounting the whole window each step — same expand/shrink template as longest-valid substring problems.

### When NOT to use this
- **Longest substring with at most K distinct characters** — validity is `distinctCount ≤ K`, not `length - maxFreq ≤ K`; different shrink condition.
- **Minimum replacements to make entire string one character** — global optimization, not a sliding-window max-length scan.
- **Subsequence** (non-contiguous) with k replacements — not sliding window; DP or greedy on indices.

---

## Pitfalls
- **Decrementing `maxFreq` on every shrink** — unnecessary and error-prone; stale `maxFreq` is safe because an inflated `maxFreq` only triggers extra shrinks, never lengthens an invalid window into `best`.
- **Updating `best` before shrinking** — when `replacementsNeeded > k`, the current window is invalid; shrink first (or in the same loop), then record length.
- **Wrong validity formula** — use `windowLen - maxFreq`, not `windowLen - k` or counting only non-max chars without tying to the dominant letter.
- **Assuming you must pick the target letter upfront** — the optimal window’s dominant char is discovered implicitly via `maxFreq` as the window grows; no separate pass over the alphabet per window.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Longest Substring Without Repeating Characters](../problems/016-longest-substring-without-repeating-characters.md) | Same longest-valid variable window; k = 0 and validity = all unique (no freq-max trick) |
| [Minimum Window Substring](../problems/019-minimum-window-substring.md) | Variable window on strings; shortest valid window with freq targets |
| [Permutation in String](../problems/018-permutation-in-string.md) | Fixed-length window + freq match; existence check rather than max length |

---

## One-liner recall

> Expand right, track char freqs and maxFreq; while `windowLen - maxFreq > k`, shrink left; answer is max valid window length.
