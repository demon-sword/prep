# Two Sum — Easy — Complement map (Arrays & Hashing)

**LC:** https://leetcode.com/problems/two-sum/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "return indices of the two numbers such that they add up to target"
- "exactly one solution" / "same element twice"
- "find a pair that sums to target"
- "complement" / "partner value"

### Constraints that matter
- n up to 10⁴ → O(n²) nested loops pass but O(n) hash map is standard optimal
- **Return indices**, not values — must store value → index in the map
- Exactly one valid pair exists — no need to handle multiple answers or no-solution edge cases
- Unsorted array — two pointers after sorting would lose original indices unless you track them

### Pattern
Complement map — for each `nums[i]`, check if `target - nums[i]` was seen earlier; store value → index as you scan left to right.

---

## Approach

### Invariant
After processing index `i`, the map contains `{ nums[j] → j }` for all `j < i`. If `target - nums[i]` is in the map, the pair `(seen[need], i)` sums to target.

### Steps
1. Create empty map `seen` (value → index).
2. For each index `i` and value `x = nums[i]`:
   - Compute `need = target - x`.
   - If `need` is in `seen`, return `[seen[need], i]`.
   - Set `seen[x] = i` (store current value before moving on).
3. Loop guarantees exactly one solution per problem statement — return is always inside the loop.

### Pseudocode skeleton
```
function twoSum(nums, target):
    seen ← empty map   // value → index

    for i from 0 to length(nums) - 1:
        x ← nums[i]
        need ← target - x

        if need in seen:
            return [seen[need], i]

        seen[x] ← i

    return none   // unreachable given "exactly one solution"
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — one pass, O(1) average map lookup/insert |
| **Space** | O(n) — map holds up to n entries in worst case |

---

## Tradeoffs

### Brute force
Nested loops over all pairs `(i, j)` with `i < j` — O(n²) time, O(1) space. Correct and easy to write but slower than necessary even at n = 10⁴.

### Why this pattern
Each element needs one complement lookup. Hash map gives O(1) average access, so one left-to-right pass finds the partner as soon as the second element of the pair is seen — O(n) total.

### When NOT to use this
- **Array is sorted** and problem asks for values or any pair (not original indices) → two pointers from both ends in O(n) time, O(1) space (Two Sum II — two pointers category).
- **Need all pairs** summing to target → map can count frequencies or store lists of indices; single complement check is insufficient.
- **Multiple targets or streaming queries** → preprocess value → indices multimap once, answer queries separately.

---

## Pitfalls
- **Storing index before checking complement** — if you insert `nums[i]` first, then check `target - nums[i]`, you might match `i` with itself when `need == x` and duplicate values exist. Check complement **before** inserting current index (or skip when `seen[need] == i`).
- **Returning values instead of indices** — problem asks for positions; map must store index, not count alone.
- **Sorting + two pointers on unsorted Two Sum** — loses original indices unless you carry index metadata; hash map is simpler for this exact prompt.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Contains Duplicate](../problems/001-contains-duplicate.md) | Hash structure for O(1) lookup; set checks membership, map stores complement partner |
| [Group Anagrams](../problems/004-group-anagrams.md) | Hash map buckets by derived key — here key is prior value, query is complement |
| [Longest Consecutive Sequence](../problems/009-longest-consecutive-sequence.md) | Set membership for O(1) checks; different goal (chain length, not pair sum) |

---

## One-liner recall

> One pass: if `target - nums[i]` is in the map, return `[map[need], i]`; else map `nums[i] = i`.
