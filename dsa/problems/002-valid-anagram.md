# Valid Anagram — Easy — Frequency counter (Arrays & Hashing)

**LC:** https://leetcode.com/problems/valid-anagram/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "anagram" / "same letters, different order"
- "permutation of each other"
- "rearrange the letters of s to form t"
- "character frequency must match"

### Constraints that matter
- Lengths up to 5×10⁴ → O(n log n) sort works but O(n) frequency count is preferred
- Lowercase English letters only → fixed-size array of 26 counters is O(1) space
- Different lengths → immediate false without building counts

### Pattern
Frequency counter — compare multisets of characters; equal frequency maps (or sort-then-compare) prove anagram equivalence.

---

## Approach

### Invariant
After processing `s[0..i]` and `t[0..i]`, the net frequency delta for every character is zero iff the prefixes are anagrams of each other. After full pass, all 26 counts must be zero.

### Steps
1. If `length(s) ≠ length(t)`, return `false`.
2. Allocate `count[26]` initialized to zero (or a hash map for arbitrary alphabet).
3. For each index `i` from `0` to `length(s) - 1`:
   - Increment `count[s[i]]`.
   - Decrement `count[t[i]]`.
4. If any entry in `count` is non-zero, return `false`; otherwise return `true`.

### Pseudocode skeleton
```
function isAnagram(s, t):
    if length(s) ≠ length(t):
        return false

    count ← array of 26 zeros

    for i from 0 to length(s) - 1:
        count[indexOf(s[i])] ← count[indexOf(s[i])] + 1
        count[indexOf(t[i])] ← count[indexOf(t[i])] - 1

    for each c in count:
        if c ≠ 0:
            return false

    return true
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — one pass over n characters, n = length(s) |
| **Space** | O(1) — 26 fixed counters (or O(k) for k distinct chars in map variant) |

---

## Tradeoffs

### Brute force
Sort both strings and compare — O(n log n) time, O(n) space if copies are sorted. Correct and simple, but frequency counting is strictly better on large n.

### Why this pattern
Anagram equivalence is multiset equality. Increment/decrement in one synchronized pass avoids building two full frequency maps and comparing them separately — single O(n) scan with O(1) extra space for lowercase letters.

### When NOT to use this
- **Unicode or large alphabet** — use hash map instead of size-26 array.
- **Need the actual rearrangement** — counting only answers yes/no; constructing the permutation needs different logic.
- **Streaming / unknown length** — sort-merge or external count may be required if you can't hold both strings.

---

## Pitfalls
- **Skipping length check** — wastes work building counts when `|s| ≠ |t|` guarantees failure.
- **Building two maps then comparing** — works but extra memory and a second comparison loop; single delta array is cleaner.
- **Sorting in place when immutability matters** — LeetCode strings are immutable in some languages; sort creates O(n) copy anyway, so counting wins on time and clarity.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Group Anagrams](../problems/004-group-anagrams.md) | Same canonical key idea — frequency signature or sorted word buckets equivalent strings |
| [Contains Duplicate](../problems/001-contains-duplicate.md) | Hash structure for membership; anagram is multiset not set |
| [Top K Frequent Elements](../problems/005-top-k-frequent-elements.md) | Build frequency map first, then use counts for ranking |

---

## One-liner recall

> Same length required; one pass increment `s[i]` and decrement `t[i]` in a 26-slot counter — all zeros means anagram.
