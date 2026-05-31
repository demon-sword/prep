# Group Anagrams — Medium — Canonical key grouping (Arrays & Hashing)

**LC:** https://leetcode.com/problems/group-anagrams/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "group the anagrams together"
- "strings that are anagrams of each other"
- "bucket / cluster equivalent strings"
- "same letters, different order" across multiple words

### Constraints that matter
- n up to 10⁴ strings, each length up to 100 → O(n · w log w) sort-key or O(n · w) signature-key both pass
- Lowercase English letters only → frequency signature fits in fixed 26 slots
- Output order of groups and strings within groups does not matter
- Empty string is valid — all empty strings share one key

### Pattern
Canonical key grouping — map each word to a normalized form (sorted characters or frequency signature); hash map buckets words sharing the same key.

---

## Approach

### Invariant
Every word in `groups[key]` is an anagram of every other word in that list, and no word from a different bucket shares the same multiset of characters. Each word is placed in exactly one bucket.

### Steps
1. Create empty map `groups` (canonicalKey → list of strings).
2. For each `word` in `strs`:
   - Compute `key`:
     - **Sort-key:** sort characters of `word` and join into a string, or
     - **Signature-key:** build `"#a2#b1..."` from 26-slot frequency counts.
   - If `key` not in `groups`, set `groups[key]` to empty list.
   - Append `word` to `groups[key]`.
3. Collect all lists from `groups.values()` and return as the answer.

### Pseudocode skeleton
```
function groupAnagrams(strs):
    groups ← empty map   // canonicalKey → list of strings

    for each word in strs:
        key ← canonicalKey(word)
        if key not in groups:
            groups[key] ← empty list
        append word to groups[key]

    return all values in groups as a list of lists

function canonicalKey(word):
    // Option A: sort-key
    chars ← characters of word
    sort chars ascending
    return join chars into string

function signatureKey(word):
    // Option B: frequency signature (O(w), no sort)
    count ← array of 26 zeros
    for each c in word:
        count[indexOf(c)] ← count[indexOf(c)] + 1
    key ← empty string
    for i from 0 to 25:
        if count[i] > 0:
            key ← key + "#" + charAt(i) + str(count[i])
    return key
```

### Complexity
| | |
|-|-|
| **Time** | O(n · w log w) with sort-key (w = max word length); O(n · w) with 26-slot signature-key |
| **Space** | O(n · w) — map stores every character across all bucket lists |

---

## Tradeoffs

### Brute force
For each pair of strings, check if they are anagrams (sort both or compare frequency maps) and merge into groups — O(n² · w log w) time. Correct but quadratic in the number of strings.

### Why this pattern
Anagram equivalence is an equivalence relation. One O(w) key computation per word plus O(1) average map insert groups all n words in a single pass — no pairwise comparisons.

### When NOT to use this
- **Single pair check** (is this one string an anagram of that one?) → Valid Anagram style frequency compare, not bucketing.
- **Need lexicographic order within groups** → sort each bucket after grouping; the hash step does not order strings.
- **Very long strings, huge alphabet** → signature key with sparse map may beat sorting very long words; sorted key is simpler for short lowercase words.

---

## Pitfalls
- **Using raw word as key** — `"eat"` and `"tea"` land in different buckets; must normalize first.
- **Mutating the input string when sorting** — sort a copy or build a char array; mutating shared references corrupts later iterations.
- **Forgetting empty string** — `""` has key `""` (sort) or empty signature; still needs one bucket, not skipped.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Valid Anagram](../problems/002-valid-anagram.md) | Same multiset notion — pairwise check vs bucket by canonical key |
| [Top K Frequent Elements](../problems/005-top-k-frequent-elements.md) | Also buckets by count-derived key; here key is character multiset not frequency rank |
| [Contains Duplicate](../problems/001-contains-duplicate.md) | Hash structure for grouping; set detects duplicates, map groups equivalents |

---

## One-liner recall

> Hash map keyed by sorted word (or `#charCount` signature); append each string to its key's list; return all lists.
