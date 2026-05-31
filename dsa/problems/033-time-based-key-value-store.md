# Time Based Key-Value Store — Medium — Partition search on timestamps (Binary Search)

**LC:** https://leetcode.com/problems/time-based-key-value-store/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- **design** a key-value store with **timestamps** on each set
- **get** returns value at key with **largest timestamp ≤ query** (floor by time)
- all **set** timestamps for a given key are **strictly increasing**
- up to 2×10⁵ operations — need **O(log n)** per get, not linear scan over history

### Constraints that matter
- Timestamps on `set` are **strictly increasing** per key → each key's history is a **sorted list** by time without extra sorting
- `get(key, timestamp)` returns `""` if no stored timestamp ≤ query
- Values and keys are strings; timestamps are positive integers
- Many keys, many sets per key — store per-key lists; binary search only the list for the queried key

### Pattern
Partition search on sorted timestamps — binary search for the **rightmost** entry with `storedTime ≤ queryTimestamp`, tracking the best value seen when moving right.

---

## Approach

### Invariant
For a fixed `key`, `entries` is sorted by timestamp. After processing `mid`, if `entries[mid].time ≤ query`, that entry is a valid candidate and any better candidate (larger time still ≤ query) lies at indices `> mid`.

### Steps
1. **Data structure:** `map` from `key` → list of `(timestamp, value)` pairs appended on each `set`.
2. **set(key, value, timestamp):** append `(timestamp, value)` to `map[key]` (order preserved by strictly increasing timestamps).
3. **get(key, timestamp):**
   - If key missing or list empty, return `""`.
   - `left ← 0`, `right ← length(entries) - 1`, `result ← ""`.
   - While `left <= right`:
     - `mid ← left + (right - left) / 2`.
     - If `entries[mid].time <= timestamp`: `result ← entries[mid].value`, `left ← mid + 1` (search for a later valid entry).
     - Else: `right ← mid - 1`.
   - Return `result` (last valid value found, or `""` if none).

**Alternative:** standard lower-bound style — find first index with `time > query`, return value at `index - 1` (or `""` if index is 0).

### Pseudocode skeleton
```
class TimeMap:
    store ← empty map from string to list of (timestamp, value)

    function set(key, value, timestamp):
        if key not in store:
            store[key] ← empty list
        append (timestamp, value) to store[key]

    function get(key, timestamp):
        if key not in store:
            return ""

        entries ← store[key]
        if length(entries) equals 0:
            return ""

        left ← 0
        right ← length(entries) - 1
        result ← ""

        while left <= right:
            mid ← left + (right - left) / 2
            if entries[mid].timestamp <= timestamp:
                result ← entries[mid].value
                left ← mid + 1
            else:
                right ← mid - 1

        return result
```

### Complexity
| | |
|-|-|
| **Time** | `set` O(1) amortized append; `get` O(log k) where k = number of sets for that key |
| **Space** | O(total number of set calls) — all pairs stored |

---

## Tradeoffs

### Brute force
On `get`, scan the key's list from the end (or start) for the largest timestamp ≤ query. O(k) per get — fails at 2×10⁵ operations when k grows large.

### Why this pattern
Strictly increasing set timestamps give a **sorted sequence** per key for free. The query is "floor timestamp" — classic binary search for rightmost element satisfying `time ≤ query`, same family as lower_bound / upper_bound partition search.

### When NOT to use this
- **Timestamps not monotonic** on set — must sort entries per key (O(k log k)) or use a tree map keyed by timestamp before binary search.
- **Need range queries** (all values between t1 and t2) — consider segment tree or ordered map with iterators.
- **Exact timestamp match only** — simple hash `(key, timestamp) → value` is O(1) without lists.

---

## Pitfalls
- **Returning on first `entries[mid].time <= query`** — an earlier mid might satisfy the inequality but a **later** entry can still be ≤ query with a larger timestamp; must continue with `left ← mid + 1` and keep the latest valid `result`.
- **Using `while left < right` and returning `entries[right]`** without proving `right` is the floor — easy off-by-one when no entry qualifies or when only index 0 works.
- **Binary searching the wrong structure** — BS runs on **one key's list**, not across all keys; missing key must return `""` before search.
- **Forgetting empty key** — `get` on never-set key should return `""`, not error.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Binary Search](../problems/028-binary-search.md) | Same halving discipline; here the predicate is `time ≤ query` and you want the **last** true index |
| [Median of Two Sorted Arrays](../problems/034-median-of-two-sorted-arrays.md) | Also partition-style BS on sorted sequences — different answer (median vs floor value) |
| [Search in Rotated Sorted Array](../problems/032-search-in-rotated-sorted-array.md) | Another BS variant where "which half to keep" depends on comparing mid to a boundary condition |

---

## One-liner recall

> Per key append `(time, val)` on set; on get BS that list for rightmost `time ≤ query`, updating answer when `entries[mid].time ≤ query` and moving `left ← mid + 1`.
