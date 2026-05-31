# Valid Sudoku — Medium — Per-group seen sets (Arrays & Hashing)

**LC:** https://leetcode.com/problems/valid-sudoku/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "determine if a 9×9 Sudoku board is valid"
- "each row, column, and 3×3 sub-box must contain digits 1–9 **without repetition**"
- "only filled cells need validation" / empty cells are `'.'`
- "uniqueness within row, column, and box"

### Constraints that matter
- Fixed 9×9 grid → at most 81 cells; O(81) = O(1) is fine, but the **pattern** generalizes to n×n boards
- Only digits `'1'`–`'9'` and `'.'` appear — no need for full Sudoku solving (placement), only **validation**
- Must check three independent groupings: row, column, and box — one global set is wrong

### Pattern
Per-group seen sets — maintain separate hash sets for each row, column, and 3×3 box; reject on first duplicate digit in any group.

---

## Approach

### Invariant
For every filled cell `(r, c)` with digit `d`, `d` has not appeared before in row `r`, column `c`, or box `boxIndex(r, c)`. Empty cells are skipped and never enter a set.

### Steps
1. Initialize three collections of 9 sets: `rows[0..8]`, `cols[0..8]`, `boxes[0..8]`.
2. For each cell `(r, c)` from `(0,0)` to `(8,8)`:
   - If `board[r][c] == '.'`, continue.
   - Let `d ← board[r][c]`.
   - Compute `b ← (r / 3) * 3 + (c / 3)` — box index 0–8.
   - If `d` is already in `rows[r]`, `cols[c]`, or `boxes[b]`, return false.
   - Insert `d` into all three sets.
3. If the loop finishes without conflict, return true.

### Pseudocode skeleton
```
function isValidSudoku(board):
    rows ← array of 9 empty sets
    cols ← array of 9 empty sets
    boxes ← array of 9 empty sets

    for r from 0 to 8:
        for c from 0 to 8:
            cell ← board[r][c]
            if cell == '.':
                continue

            b ← (r / 3) * 3 + (c / 3)

            if cell in rows[r]:
                return false
            if cell in cols[c]:
                return false
            if cell in boxes[b]:
                return false

            add cell to rows[r]
            add cell to cols[c]
            add cell to boxes[b]

    return true
```

### Complexity
| | |
|-|-|
| **Time** | O(1) — fixed 81 cells, each O(1) set lookup/insert |
| **Space** | O(1) — at most 9×9 = 81 digits stored across all sets |

---

## Tradeoffs

### Brute force
For each filled cell, scan its entire row, column, and box for duplicates — O(81 × 27) still constant for 9×9, but redundant rescans; the hash-set approach is one pass with O(1) per cell.

### Why this pattern
Uniqueness is a **membership** question within fixed groups. Hash sets give O(1) "already seen?" per digit per group. Same frequency/seen-set idea as Valid Anagram, applied to three parallel partitionings of the grid.

### When NOT to use this
- **Must also solve / fill the board** — backtracking or constraint propagation, not just validation.
- **Streaming cells one at a time** — sets still work; alternatively encode seen bits in integers (9 bits per group) for tighter memory.
- **Very large sparse boards** — fixed 9-set arrays are fine; for huge n, consider bitmasks per row/col/box.

---

## Pitfalls
- **One global set for the whole board** — a digit can appear once per row, once per column, and once per box; global dedup incorrectly rejects valid boards.
- **Wrong box index** — use `(r / 3) * 3 + (c / 3)`, not `r / 3 + c / 3` or `(r, c)` as a pair key without normalizing to 0–8.
- **Validating empty cells** — `'.'` must be skipped; treating it as a digit breaks input assumptions.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Contains Duplicate](../problems/001-contains-duplicate.md) | Set membership — duplicate detection in a single collection |
| [Valid Anagram](../problems/002-valid-anagram.md) | Per-symbol frequency / multiset constraint across fixed groups |
| [Group Anagrams](../problems/004-group-anagrams.md) | Partitioning items into buckets by a derived key; here buckets are row/col/box |

---

## One-liner recall

> One pass over the board: for each digit, if it's already in that row's, column's, or box's set, return false; otherwise add it to all three sets.
