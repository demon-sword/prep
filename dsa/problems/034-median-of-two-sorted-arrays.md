# Median of Two Sorted Arrays — Hard — Partition search on two sorted arrays (Binary Search)

**LC:** https://leetcode.com/problems/median-of-two-sorted-arrays/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- **median** of two **sorted** arrays in **O(log(m+n))** time
- two sorted arrays of size m and n — do **not** merge them
- find the middle value (or average of two middles) of the combined sorted sequence
- "partition" the union into equal left/right halves where every left element ≤ every right element

### Constraints that matter
- m, n up to 1000 — O(m+n) merge works for correctness but the problem expects **O(log(min(m,n)))**
- Arrays are **sorted ascending** — global order exists without materializing the merge
- Total length can be **odd or even** — odd → single middle element; even → average of two middle elements
- Either array can be empty in theory; handle partition boundaries with ±infinity sentinels

### Pattern
Partition binary search on the **shorter** array — choose cut `i` in `a` and `j = totalLeft - i` in `b` so that `max(left halves) ≤ min(right halves)` on both sides; median lives at the partition boundary.

---

## Approach

### Invariant
Binary search partition index `i` in the shorter array `a` (length `m`). For each `i`, `j = totalLeft - i` fixes the left-half size. A valid partition satisfies `aLeftMax ≤ bRightMin` and `bLeftMax ≤ aRightMin`, meaning the virtual merged left half is entirely ≤ the virtual merged right half — then the median is determined by boundary elements only.

### Steps
1. **Ensure `a` is shorter:** if `length(a) > length(b)`, swap them (search space is `0..m` on the shorter array).
2. **Compute target left size:** `totalLeft ← (m + n + 1) / 2` — left half gets the extra element when total is odd.
3. **Binary search `i` in `[0, m]`:**
   - `i ← lo + (hi - lo) / 2`, `j ← totalLeft - i`.
   - `aLeftMax ← a[i-1]` or `-∞` if `i = 0`; `aRightMin ← a[i]` or `+∞` if `i = m`.
   - `bLeftMax ← b[j-1]` or `-∞` if `j = 0`; `bRightMin ← b[j]` or `+∞` if `j = n`.
4. **Check validity:**
   - If `aLeftMax ≤ bRightMin` and `bLeftMax ≤ aRightMin` → partition found.
   - If `aLeftMax > bRightMin` → `i` too large → `hi ← i - 1`.
   - Else (`bLeftMax > aRightMin`) → `i` too small → `lo ← i + 1`.
5. **Compute median from boundary:**
   - If `(m + n)` is odd: return `max(aLeftMax, bLeftMax)`.
   - Else: return `(max(aLeftMax, bLeftMax) + min(aRightMin, bRightMin)) / 2`.

**Why search the shorter array?** Partition index `i` ranges `0..m`; searching the shorter array gives O(log(min(m,n))) and guarantees `j` stays in `[0, n]` for any valid `i`.

### Pseudocode skeleton
```
function findMedianSortedArrays(a, b):
    if length(a) > length(b):
        swap a and b

    m ← length(a)
    n ← length(b)
    totalLeft ← (m + n + 1) / 2
    lo ← 0
    hi ← m

    while lo <= hi:
        i ← lo + (hi - lo) / 2
        j ← totalLeft - i

        aLeftMax  ← a[i - 1] if i > 0 else -infinity
        aRightMin ← a[i]     if i < m else +infinity
        bLeftMax  ← b[j - 1] if j > 0 else -infinity
        bRightMin ← b[j]     if j < n else +infinity

        if aLeftMax <= bRightMin and bLeftMax <= aRightMin:
            if (m + n) mod 2 equals 1:
                return max(aLeftMax, bLeftMax)
            else:
                return (max(aLeftMax, bLeftMax) + min(aRightMin, bRightMin)) / 2
        else if aLeftMax > bRightMin:
            hi ← i - 1
        else:
            lo ← i + 1
```

### Complexity
| | |
|-|-|
| **Time** | O(log(min(m, n))) — binary search on shorter array only |
| **Space** | O(1) — no merge buffer |

---

## Tradeoffs

### Brute force
Merge both arrays into one sorted array (O(m+n) time, O(m+n) space), then return middle element(s). Correct but violates the O(log(m+n)) requirement and is the first instinct to avoid in interviews when log is specified.

### Why this pattern
The median depends only on **border elements** between left and right halves of the combined sequence — not on scanning the merge. Partition search treats `i` as the decision variable: monotonicity holds because increasing `i` moves one element from `b`'s left to `a`'s left, eventually fixing `aLeftMax > bRightMin`. Same family as timestamp floor search — binary search a **split point**, not a value.

### When NOT to use this
- **Single sorted array median** — index `n/2` in O(1) time; no partition needed.
- **K-th smallest of two arrays (general K)** — related but often solved with a different two-pointer or heap approach unless K is specifically the median.
- **Unsorted inputs** — must sort first O((m+n) log(m+n)); partition BS requires sorted order.
- **Many merge queries** — if you repeatedly need full merged order, materializing merge or using a heap may be simpler than partition BS each time.

---

## Pitfalls
- **Merging arrays first** — passes small tests but fails the stated O(log(m+n)) constraint; interviewers expect partition BS.
- **Searching the longer array** — `j = totalLeft - i` can go out of bounds `[0, n]` when `i` is chosen on the longer array; always binary search the **shorter** array.
- **Off-by-one on `totalLeft`** — use `(m + n + 1) / 2` (ceil half) so the left partition gets the extra element when total length is odd; using `floor((m+n)/2)` breaks the odd-length case.
- **Forgetting ±infinity at boundaries** — when `i = 0` or `i = m` (or `j = 0`, `j = n`), one side of the partition is empty; use sentinels so comparisons remain valid.
- **Wrong median formula for even length** — must average `max(left)` and `min(right)`, not arbitrary elements from the arrays.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Time Based Key-Value Store](../problems/033-time-based-key-value-store.md) | Also partition-style BS on sorted data — search a split point rather than an exact value |
| [Binary Search](../problems/028-binary-search.md) | Core halving discipline; here the predicate is "valid partition" instead of `nums[mid] == target` |
| [Search a 2D Matrix](../problems/029-search-a-2d-matrix.md) | Another way to avoid materializing a merged structure — treat implicit sorted order via index math |

---

## One-liner recall

> BS partition index `i` on the **shorter** array with `j = (m+n+1)/2 - i`; when `max(lefts) ≤ min(rights)` on both sides, odd → `max(lefts)`, even → average of `max(lefts)` and `min(rights)`.
