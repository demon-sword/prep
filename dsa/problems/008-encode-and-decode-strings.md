# Encode and Decode Strings — Medium — Length-prefix serialization (Arrays & Hashing)

**LC:** https://leetcode.com/problems/encode-and-decode-strings/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "encode a list of strings to a single string and decode back"
- "strings may contain any characters" / no guarantee on charset
- "design `encode` and `decode` such that they are inverses"
- delimiter-based join fails because payload can contain the delimiter

### Constraints that matter
- Variable-length strings with arbitrary content — a naive delimiter (`","`, `"#"`, newline) is ambiguous when payload contains it
- Must round-trip exactly: `decode(encode(strs)) == strs` including empty strings and empty list
- Total encoded length is O(sum of string lengths) plus O(m) length metadata for m strings
- No requirement for human-readable output — only unambiguous parsing

### Pattern
Length-prefix serialization — prefix each payload with its byte/char length and a fixed separator, then decode by reading length first and slicing exactly that many characters.

---

## Approach

### Invariant
While scanning the encoded buffer, the next token is always `digits + "#" + payload` where `payload` has exactly `len` characters. After consuming one token, the cursor lands on the start of the next token (or end of string).

### Steps
1. **Encode:** for each string `s`, append `str(length(s)) + "#" + s` to the result buffer.
2. **Decode:** maintain index `i` at the start of the next token.
3. Find delimiter `#` at position `j` starting from `i`; parse integer `len` from `s[i..j-1]`.
4. Extract `payload ← s[j+1 .. j+len]` (exactly `len` chars, may include `#`, commas, spaces, etc.).
5. Append `payload` to output list; set `i ← j + 1 + len`.
6. Repeat until `i == length(s)`.

### Pseudocode skeleton
```
function encode(strs):
    result ← empty string
    for each s in strs:
        result ← result + str(length(s)) + "#" + s
    return result

function decode(s):
    i ← 0
    out ← empty list

    while i < length(s):
        j ← i
        while s[j] ≠ "#":
            j ← j + 1

        len ← integer parse of s[i .. j-1]
        start ← j + 1
        end ← start + len - 1
        payload ← s[start .. end]

        append payload to out
        i ← end + 1

    return out
```

### Complexity
| | |
|-|-|
| **Time** | O(L) — L = total characters across all strings; each char written once in encode, read once in decode |
| **Space** | O(L) — encoded string length is O(L + m) for m strings; decode output is O(L) |

---

## Tradeoffs

### Brute force
Join with a chosen delimiter (e.g. comma) and escape occurrences inside strings — possible but error-prone (need escape rules for escape chars). Length-prefix avoids escaping entirely: the parser never scans payload for structure, only slices a fixed width.

### Why this pattern
Serialization with **self-describing boundaries** — length metadata tells the decoder how far to read regardless of payload content. Same "hash/map key" mindset as canonical keys in Group Anagrams: normalize representation so lookup (here, parsing) is unambiguous.

### When NOT to use this
- **Fixed-width records** — if every string has the same length, pad or use raw concatenation.
- **Binary protocols with endianness** — use fixed-width length fields (4-byte int) instead of decimal digits + `#`.
- **Streaming / unbounded strings** — length-prefix still works but consider chunked framing or protobuf-style varints for efficiency.

---

## Pitfalls
- **Delimiter-only encoding** — `join(strs, ",")` breaks when a string contains `","`; always prefix with length.
- **Off-by-one on slice end** — payload is `len` characters starting at `j+1`, so next index is `j + 1 + len`, not `j + len`.
- **Assuming non-empty list or strings** — encode `[]` as `""`; encode `[""]` as `"0#"`; decoder must handle `len == 0`.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Group Anagrams](../problems/004-group-anagrams.md) | Canonical string representation as a stable key — here the key is length metadata for parsing |
| [Valid Anagram](../problems/002-valid-anagram.md) | Fixed-alphabet encoding of multiset info; both problems need a representation immune to content ambiguity |
| [Longest Consecutive Sequence](../problems/009-longest-consecutive-sequence.md) | Hash-set membership for O(1) checks — different domain, but same category tooling for structured lookups |

---

## One-liner recall

> Encode each string as `len + "#" + payload`; decode by reading digits until `#`, then slice exactly `len` characters — payload content never affects parsing.
