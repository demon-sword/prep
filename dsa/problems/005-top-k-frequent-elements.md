# Top K Frequent Elements — Medium — Frequency map + bucket sort (Arrays & Hashing)

**LC:** https://leetcode.com/problems/top-k-frequent-elements/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "k most frequent elements"
- "return the k highest counts / modes"
- "which numbers appear most often"
- "frequency ranking" without full sort of all unique values

### Constraints that matter
- n up to 10⁵ → counting pass must be O(n); avoid O(n log n) full sort of all uniques if bucket or heap-of-k suffices
- k is in range [1, number of unique elements] → answer always has exactly k distinct values
- Output order does not matter (unless follow-up asks for descending frequency)
- Integer keys — hash map for counts; max frequency ≤ n so bucket index fits in n+1 slots

### Pattern
Frequency map + bucket sort — count occurrences, bucket each value by its frequency index, scan buckets from highest frequency downward until k elements collected.

---

## Approach

### Invariant
After the counting pass, every value `num` sits in `buckets[freq[num]]`. Scanning buckets from index n down to 1 visits values in non-increasing frequency order; the first k values collected are the k most frequent.

### Steps
1. Build `freq` map: one pass over `nums`, increment count per value.
2. Create `buckets` — array of `n + 1` empty lists; index `i` holds all numbers that appear exactly `i` times.
3. For each `(num, count)` in `freq`, append `num` to `buckets[count]`.
4. Initialize empty `result`. For `i` from `n` down to `1`:
   - For each `num` in `buckets[i]`, append to `result`.
   - Stop when `length(result) == k`.
5. Return `result`.

### Pseudocode skeleton
```
function topKFrequent(nums, k):
    freq ← empty map
    for each num in nums:
        freq[num] ← freq.get(num, 0) + 1

    n ← length(nums)
    buckets ← array of n + 1 empty lists   // index = frequency

    for each (num, count) in freq:
        append num to buckets[count]

    result ← empty list
    for i from n down to 1:
        for each num in buckets[i]:
            append num to result
            if length(result) = k:
                return result

    return result   // k ≤ unique count, always reachable
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — one count pass, one bucket fill, one reverse scan (each element touched O(1) times) |
| **Space** | O(n) — freq map and buckets store at most n distinct values |

---

## Tradeoffs

### Brute force
Count frequencies, sort all unique `(value, count)` pairs by count descending, take first k keys — O(n log u) where u = unique count. Correct but sorting every unique element when only top k matter.

### Why this pattern
Frequency counting is the natural first step (same as Valid Anagram / Group Anagrams). Bucketing by frequency turns "top k by count" into a linear reverse scan — no heap, no compare-based sort. Alternative: min-heap of size k over `(count, value)` pairs — O(n log k), better when k ≪ u.

### When NOT to use this
- **k = 1 or very small, u huge** — min-heap of size k is O(n log k) and may beat allocating n+1 buckets.
- **Need sorted output by value within same frequency** — bucket sort gives frequency order only; tie-break requires extra sorting per bucket.
- **Streaming / unknown n** — fixed bucket array needs max frequency bound; heap handles dynamic input more naturally.

---

## Pitfalls
- **Max-heap of all uniques then pop k** — works but O(u log u); interview expects bucket O(n) or min-heap O(n log k).
- **Bucket array too small** — max frequency is at most n, so allocate `n + 1` buckets, not `k + 1`.
- **Min-heap with wrong comparator** — if using heap variant, keep size k with **smallest count at top** so you evict low-frequency entries; a max-heap of entire map is the wrong structure for space/time.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Valid Anagram](../problems/002-valid-anagram.md) | Same frequency-count building block before ranking |
| [Group Anagrams](../problems/004-group-anagrams.md) | Also buckets items by a derived key; here key is numeric frequency not character signature |
| [Contains Duplicate](../problems/001-contains-duplicate.md) | Hash map tracks presence/count; this problem ranks by count instead of detecting repeats |

---

## One-liner recall

> Count freqs in a map; bucket each value by its count in an array of size n+1; scan buckets high→low until k values collected.
