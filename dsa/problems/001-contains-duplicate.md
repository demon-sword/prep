# Contains Duplicate — Easy — Set membership (Arrays & Hashing)

**LC:** https://leetcode.com/problems/contains-duplicate/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "return true if any value appears at least twice"
- "every element is distinct" / "contains duplicate"
- "already seen" / "appears more than once"

### Constraints that matter
- n up to 10⁵ → need O(n) or O(n log n); O(n²) nested loops will TLE
- Unsorted input → can't assume order for early exit without preprocessing
- Integer values (not objects) → hash set works directly; no custom comparator needed

### Pattern
Set membership — track seen values; duplicate found when inserting a value already in the set.

---

## Approach

### Invariant
After processing index `i`, the set contains exactly the distinct values from `nums[0..i]`. If `nums[i]` is already in the set before insert, a duplicate exists.

### Steps
1. Create an empty hash set.
2. For each element `x` in `nums`:
   - If `x` is already in the set, return `true`.
   - Add `x` to the set.
3. If the loop finishes, return `false`.

### Pseudocode skeleton
```
function containsDuplicate(nums):
    seen ← empty set

    for each x in nums:
        if x in seen:
            return true
        add x to seen

    return false
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — one pass, O(1) average set ops |
| **Space** | O(n) — worst case all elements unique |

---

## Tradeoffs

### Brute force
Compare every pair `(i, j)` with nested loops — O(n²) time, O(1) space. Simple to code but fails on n = 10⁵.

### Why this pattern
Single pass with O(1) average lookup/insert turns duplicate detection into O(n). No sorting required; works on unsorted input.

### When NOT to use this
- If the problem requires **O(1) extra space** and in-place mutation is allowed, sort first then scan adjacent pairs — O(n log n) time, O(1) auxiliary space.
- If you need the **indices** of duplicates (not just existence), store value → index in a map instead of a set.

---

## Pitfalls
- **Sorting without checking the constraint** — sort + adjacent scan works but is O(n log n); set is simpler when O(n) space is allowed.
- **Using a map when a set suffices** — no need to store counts or indices; membership alone answers the question.
- **Early return forgotten** — must return `true` immediately on second sighting; don't keep scanning after finding a duplicate unless asked to count all duplicates.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Two Sum](../problems/003-two-sum.md) | Hash structure for O(1) lookup, but map stores complement/index |
| [Valid Anagram](../problems/002-valid-anagram.md) | Frequency counting — multiset variant of "have we seen this?" |
| [Longest Consecutive Sequence](../problems/009-longest-consecutive-sequence.md) | Hash set for O(1) membership, different goal (chain expansion) |

---

## One-liner recall

> One pass with a hash set — if inserting `x` fails because `x` is already there, return true.
