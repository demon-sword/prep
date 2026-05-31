# Longest Consecutive Sequence — Medium — Set + start-only expansion (Arrays & Hashing)

**LC:** https://leetcode.com/problems/longest-consecutive-sequence/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "longest consecutive elements sequence"
- "sequence of integers where each element is exactly 1 greater than the previous"
- "unsorted array" / "must run in O(n) time"
- "consecutive chain" / "streak of +1 values"

### Constraints that matter
- Array is **unsorted** — sorting is O(n log n) and the problem asks for O(n)
- Values can be negative, zero, or duplicate — duplicates don't extend a chain; dedupe via set
- n up to 10⁵ → need linear time; nested loops or expanding from every element is O(n²)
- Return **length** only, not the actual subsequence — no need to track indices or elements

### Pattern
Hash set + start-only expansion — put all numbers in a set for O(1) membership; only begin counting when `num - 1` is absent (sequence start), then walk `num, num+1, num+2, ...` while each successor exists.

---

## Approach

### Invariant
Each integer belongs to at most one consecutive chain. A chain is counted exactly once: from its smallest element (the start). Every element is visited at most twice — once when considered as a candidate start (skipped if not a start), once inside a forward walk that only runs from starts.

### Steps
1. Build `numSet` from all elements in `nums` (duplicates collapse automatically).
2. Initialize `best ← 0`.
3. For each `num` in `numSet`:
   - If `(num - 1)` is in `numSet`, skip — `num` is not a chain start.
   - Otherwise set `length ← 0`, `current ← num`.
   - While `current` is in `numSet`: increment `length`, set `current ← current + 1`.
   - Update `best ← max(best, length)`.
4. Return `best`.

### Pseudocode skeleton
```
function longestConsecutive(nums):
    numSet ← empty set
    for each x in nums:
        add x to numSet

    best ← 0

    for each num in numSet:
        if (num - 1) in numSet:
            continue   // not the start of a chain

        length ← 0
        current ← num
        while current in numSet:
            length ← length + 1
            current ← current + 1

        best ← max(best, length)

    return best
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each element inserted into set once; each element visited at most twice (outer loop + inner walk from starts only) |
| **Space** | O(n) — hash set holds up to n distinct values |

---

## Tradeoffs

### Brute force
Sort the array and scan for longest run of consecutive values — O(n log n) time, O(1) or O(n) space depending on sort. Fails the stated O(n) requirement. Alternatively, for each element, expand forward and backward counting neighbors — without the start check, each element participates in O(n) expansions → O(n²).

### Why this pattern
Consecutive chains are defined by **membership** (`is x in the set?`), not order. A hash set gives O(1) average lookups. The start-only rule (`num - 1` absent) ensures each chain is walked once from its minimum, amortizing inner loops to O(n) total.

### When NOT to use this
- **Sorted array with O(1) extra space allowed** — single pass comparing `nums[i]` to `nums[i-1]` is simpler and O(n) time, O(1) space.
- **Need the actual subsequence elements or indices** — track start/end during expansion or use union-find for component sizes.
- **Range is small and bounded** — e.g. values in [0, 10000] → boolean array or counting sort can replace hash set.

---

## Pitfalls
- **Expanding from every element** — inner `while current+1 in set` from each `num` revisits the same chain repeatedly; always skip when `num - 1` exists in the set.
- **Forgetting duplicates** — `[1, 2, 0, 1]` should return 3, not 4; building a set dedupes before expansion.
- **Sorting when O(n) is required** — O(n log n) passes many judges but misses the intended hash-set insight; interview follow-up is usually "can you do O(n)?"

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Contains Duplicate](../problems/001-contains-duplicate.md) | Hash set for O(1) membership — here membership drives chain extension, not duplicate detection |
| [Two Sum](../problems/003-two-sum.md) | Hash structure turns O(n²) scan into O(n); same category tooling for fast lookups |
| [Encode and Decode Strings](../problems/008-encode-and-decode-strings.md) | Structured use of hash/set primitives in Arrays & Hashing — different domain, same O(n) single-pass mindset |

---

## One-liner recall

> Hash all nums into a set; for each `num` where `num-1` is missing, walk forward counting `num, num+1, ...` in the set and track the max length.
