# Product of Array Except Self — Medium — Prefix/suffix aggregation (Arrays & Hashing)

**LC:** https://leetcode.com/problems/product-of-array-except-self/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "product of all elements **except** nums[i]"
- "output[i] depends on every other index, not self"
- "without using division" or "follow-up: O(1) extra space"
- "prefix" / "running product" across the array

### Constraints that matter
- n up to 10⁵ → must be O(n); nested loops over all pairs are O(n²)
- Integer products can overflow intermediate values in some languages — problem usually allows 32-bit result; be aware in interviews
- Output array does not count toward extra space in the follow-up
- Division is disallowed or brittle when zeros appear — use running products instead

### Pattern
Prefix/suffix aggregation — left pass stores product of all elements to the left of i; right pass multiplies product of all elements to the right; combine in O(n) with O(1) extra variables besides output.

---

## Approach

### Invariant
After the left pass, `answer[i]` equals the product of `nums[0..i-1]` (1 when i = 0). After the right pass, `answer[i]` equals (product left of i) × (product right of i), which is the product of all elements except `nums[i]`.

### Steps
1. Allocate `answer` of length n, initialized to 1.
2. **Left pass:** `prefix ← 1`. For i from 0 to n−1: set `answer[i] ← prefix`, then `prefix ← prefix * nums[i]`.
3. **Right pass:** `suffix ← 1`. For i from n−1 down to 0: `answer[i] ← answer[i] * suffix`, then `suffix ← suffix * nums[i]`.
4. Return `answer`.

### Pseudocode skeleton
```
function productExceptSelf(nums):
    n ← length(nums)
    answer ← array of size n, each cell 1

    prefix ← 1
    for i from 0 to n - 1:
        answer[i] ← prefix
        prefix ← prefix * nums[i]

    suffix ← 1
    for i from n - 1 down to 0:
        answer[i] ← answer[i] * suffix
        suffix ← suffix * nums[i]

    return answer
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — two linear passes |
| **Space** | O(1) extra — only `prefix` and `suffix` scalars; output array excluded per problem |

---

## Tradeoffs

### Brute force
For each index i, multiply all `nums[j]` where j ≠ i — O(n²) time. Simple to state but fails at n = 10⁵.

### Why this pattern
Each output slot is a **separable** aggregate: (everything left) × (everything right). Two running products avoid recomputing full ranges per index. Same idea as prefix sums for "sum except self."

### When NOT to use this
- **Only need sum except self** — prefix sum with one pass is enough; products need separate handling for zeros.
- **Allowed to use division** — compute total product, divide by `nums[i]` at each index — O(n) but breaks on zero in the array and often forbidden explicitly.
- **Sparse or index-query variant** — if queries are offline on static array, precompute prefix/suffix arrays once; online updates need a different structure.

---

## Pitfalls
- **Dividing total product by nums[i]** — fails when any element is 0 (two zeros → ambiguous); problem usually bans division.
- **Separate prefix and suffix arrays** — correct O(n) time but O(n) extra space; reuse `answer` for the left product, then multiply suffix in the second pass for O(1) extra.
- **Updating prefix before writing answer[i]** — order matters: store running product *before* including `nums[i]` at that index.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Two Sum](../problems/003-two-sum.md) | Also uses prefix-style decomposition of a global constraint per index (complement vs product) |
| [Top K Frequent Elements](../problems/005-top-k-frequent-elements.md) | Another linear-scan array technique; different aggregate (frequency rank vs running product) |
| [Group Anagrams](../problems/004-group-anagrams.md) | Bucketing by derived key; here each index gets a derived value from neighbors only |

---

## One-liner recall

> Fill answer with left-running products in one pass, then multiply each cell by right-running products in a second pass — no division, O(1) extra space.
