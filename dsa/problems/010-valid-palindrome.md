# Valid Palindrome — Easy — Converging pointers (Two Pointers)

**LC:** https://leetcode.com/problems/valid-palindrome/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "palindrome" / "reads the same forward and backward"
- "consider only alphanumeric characters"
- "ignore cases" / "case-insensitive"
- "after converting all uppercase letters into lowercase letters"

### Constraints that matter
- Length up to 2×10⁵ → need O(n) single pass; building a cleaned string then reversing is O(n) time but doubles memory
- Only ASCII letters and digits matter — spaces and punctuation are skipped, not deleted from input
- Empty string after filtering is a palindrome (vacuously true)

### Pattern
Converging pointers with filter — advance `left` and `right` from both ends, skip non-alphanumeric characters, compare lowercase equivalents in O(n) time and O(1) extra space.

---

## Approach

### Invariant
At each comparison, `s[left..right]` (ignoring skipped junk outside the window) is a palindrome iff all previously compared mirrored pairs matched. Pointers only move inward after a successful match or after skipping invalid characters.

### Steps
1. Set `left ← 0`, `right ← length(s) - 1`.
2. While `left < right`:
   - Advance `left` while `left < right` and `s[left]` is not alphanumeric.
   - Advance `right` while `left < right` and `s[right]` is not alphanumeric.
   - If `lowercase(s[left]) ≠ lowercase(s[right])`, return `false`.
   - Move `left ← left + 1`, `right ← right - 1`.
3. Return `true` when pointers meet or cross.

### Pseudocode skeleton
```
function isPalindrome(s):
    left ← 0
    right ← length(s) - 1

    while left < right:
        while left < right and not isAlphanumeric(s[left]):
            left ← left + 1
        while left < right and not isAlphanumeric(s[right]):
            right ← right - 1

        if toLowerCase(s[left]) ≠ toLowerCase(s[right]):
            return false

        left ← left + 1
        right ← right - 1

    return true

function isAlphanumeric(c):
    return (c is letter A-Z or a-z) or (c is digit 0-9)
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each index visited at most once by `left` and once by `right` |
| **Space** | O(1) — only two indices; no auxiliary string |

---

## Tradeoffs

### Brute force
Build a new string keeping only lowercase alphanumerics, then compare it to its reverse — O(n) time, O(n) space for the filtered copy. Correct and easy to code, but wastes memory when O(1) space is achievable.

### Why this pattern
Palindrome checks naturally mirror from both ends. Two pointers skip junk in place without allocating a cleaned string. Each character is examined a constant number of times, matching the optimal linear bound.

### When NOT to use this
- **Linked list palindrome** — no random access; use fast/slow to find middle, reverse second half, then compare nodes.
- **Need the longest palindromic substring** — converging ends only answer yes/no for the whole string; expand-around-center or DP handles substrings.
- **Unicode normalization required** — case folding and combining characters need library support beyond simple ASCII `toLowerCase`.

---

## Pitfalls
- **Comparing before skipping** — treating `' '` or `','` as characters causes false negatives on inputs like `"A man, a plan, a canal: Panama"`.
- **Only skipping on one side** — must filter both `left` and `right` before each comparison; otherwise mismatched positions compare punctuation to letters.
- **Forgetting `left < right` in inner while loops** — can advance past the partner pointer and read out of bounds or double-count the middle character on odd-length filtered strings.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Two Sum II](../problems/011-two-sum-ii.md) | Same opposite-ends pointer movement on a sequence, different goal (pair sum vs char match) |
| [3Sum](../problems/012-3sum.md) | Two-pointer scan inward on sorted subarray — converging mechanics with sum target |
| [Container With Most Water](../problems/013-container-with-most-water.md) | Opposite ends shrink window; greedy move instead of symmetric compare |

---

## One-liner recall

> Two pointers from both ends; skip non-alphanumeric; lowercase-compare; mismatch → false; meet → true.
