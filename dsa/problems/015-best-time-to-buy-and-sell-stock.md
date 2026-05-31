# Best Time to Buy and Sell Stock — Easy — One-pass running extremum (Sliding Window)

**LC:** https://leetcode.com/problems/best-time-to-buy-and-sell-stock/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "maximize profit" / "best time to buy and sell"
- "at most one transaction" / "buy once then sell once"
- "buy before you sell" / "future day to sell"
- "array of prices" where index is day

### Constraints that matter
- Length up to 10⁵ → need O(n); checking every buy/sell pair is O(n²) and TLE
- Only **one** transaction allowed — not unlimited trades (that is a different problem)
- Prices are non-negative integers; profit is `sellPrice - buyPrice` (zero if never profitable)

### Pattern
One-pass running extremum — scan prices left to right, keep the minimum price seen so far, and at each day compute profit if you sold today after buying at that minimum.

---

## Approach

### Invariant
After processing `prices[0..i]`, `minPrice` is the lowest price in that prefix (best buy day so far), and `best` is the maximum profit achievable using only buys on or before day `i` and a sell on or before day `i`.

### Steps
1. Initialize `minPrice ← infinity`, `best ← 0`.
2. For each `price` in `prices`:
   - Update `minPrice ← min(minPrice, price)` (cheapest buy opportunity up to today).
   - Update `best ← max(best, price - minPrice)` (best profit if selling today).
3. Return `best` (0 if prices only decrease).

### Pseudocode skeleton
```
function maxProfit(prices):
    if length(prices) < 2:
        return 0

    minPrice ← infinity
    best ← 0

    for price in prices:
        // profit if we sell today after buying at minPrice seen earlier
        if price > minPrice:
            best ← max(best, price - minPrice)

        // extend cheapest buy day (must happen after profit check uses prior min)
        minPrice ← min(minPrice, price)

    return best
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — single pass over prices |
| **Space** | O(1) — only `minPrice` and `best` |

---

## Tradeoffs

### Brute force
For every pair `(i, j)` with `i < j`, compute `prices[j] - prices[i]` and take the maximum — O(n²) time, O(1) space. Simple to state in an interview but fails on large `n`.

### Why this pattern
Selling on day `j` is optimal only if you bought at the minimum price in `prices[0..j-1]`. That minimum is a running extremum updated in O(1) per day — no explicit window shrink/expand, but the same "only need state at the left boundary" idea as sliding-window prep.

### When NOT to use this
- **Unlimited transactions** (LC 122) — sum all positive day-to-day deltas, not one running min.
- **At most two transactions** (LC 123) or **cooldown** (LC 309) — need DP or state machine, not a single min tracker.
- **Best profit with fee** or **k transactions** — DP over days and remaining trades.

---

## Pitfalls
- **Updating `minPrice` before computing profit** — using today's price as both buy and sell on the same day yields 0; use the previous minimum when evaluating `price - minPrice`, or update `minPrice` after the profit step.
- **Returning negative profit** — if the array is strictly decreasing, answer is `0` (no transaction), not a negative number; initialize `best` to 0.
- **Treating as classic variable window** — there is no `left`/`right` shrink loop; forcing a two-pointer window adds complexity without benefit for one transaction.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Longest Substring Without Repeating Characters](../problems/016-longest-substring-without-repeating-characters.md) | Same category; true variable window with expand/shrink — contrast with this one-pass scan |
| [Sliding Window Maximum](../problems/020-sliding-window-maximum.md) | Also linear scan with auxiliary structure (deque vs running min) |
| [Longest Repeating Character Replacement](../problems/017-longest-repeating-character-replacement.md) | Window + incremental state; harder variant of "track best while scanning" |

---

## One-liner recall

> One pass: keep running min price; at each day, profit = price − minSoFar; track max profit (floor at 0).
