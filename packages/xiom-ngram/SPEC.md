# xiom.ngram -- Specification

Status: `incubating` (implemented, harness-green, not published).
Module: `xiom.ngram` (`src/ngram.xi`). Manifest: `package.xi` (name
`xiom.ngram`, version `0.1.0`). Pure XIOM, no FFI. Depends on `xiom.std`
(`xiom.string`, `xiom.string.compare`, `xiom.convert.int`).

## 1. Scope

Text n-grams and set-similarity scoring over UTF-8 `Str` inputs:

- word scanning (`ngram_words`),
- word n-gram construction (`ngram_shingles`),
- byte-level character n-grams (`ngram_char_shingles`),
- order-preserving de-duplication (`ngram_unique`),
- set similarity in permille (`ngram_jaccard`, `ngram_dice`),
- MinHash signatures (`ngram_minhash_signature`) and their comparison
  (`ngram_signature_similarity`).

All scanning is byte-wise over the UTF-8 representation. Every entry point is
infallible: functions return `Vec[Str]`, `Vec[Int]` or `Int`, never a
`Result`, and never panic on any input (bytes are never decoded).

## 2. Non-goals

- Unicode-aware segmentation: no UAX #29, no case folding beyond ASCII.
- Language modeling: no count tables, no smoothing, no probabilities.
- Cryptographic hashing or collision-resistant digests.
- Approximate-nearest-neighbour indexes (LSH bands, inverted indexes).
- Weighted, positional or edit-distance similarity; similarity is on sets.
- Streaming / incremental APIs; whole inputs live in memory.
- No FFI and no file I/O.

## 3. Definitions

1. **Word byte.** A byte in `[0-9A-Za-z]` (`48..57`, `65..90`, `97..122`).
   Every other byte is a separator: ASCII punctuation and whitespace,
   underscore, and every byte of a multi-byte UTF-8 sequence.
2. **Word token.** A maximal run of word bytes, lowercased with ASCII
   lowering (stdlib `str_lower`). Tokens are ASCII-only by construction.
3. **Word shingle.** A contiguous window of `n` tokens joined with single
   spaces (`"the quick"`). Contents are verbatim; no escaping, so a token
   that itself contains a space makes the join ambiguous.
4. **Character shingle.** `str_slice(text, i, i + n)` for
   `i in 0..len-n`: a verbatim byte window of length `n`. `n` counts bytes,
   not characters; UTF-8 slices pass through byte-exact.
5. **Shingle set.** The distinct shingles of a sequence: duplicates collapse
   and order is ignored. Jaccard and Dice always operate on the sets;
   `ngram_unique` exposes the collapse directly (first-seen order).

## 4. Semantics

- `ngram_words("")` is `[]`; separator-only text is `[]`; separator runs
  collapse. `"Hello, World!"` -> `["hello","world"]`;
  `"café"` -> `["caf"]`; `"naïve"` -> `["na","ve"]`; `"a—b"` -> `["a","b"]`.
- `ngram_shingles(words, n)` returns `words.len() - n + 1` shingles when
  `n >= 1` and `words.len() >= n`, otherwise `[]` (so `n < 1` is always `[]`).
  `n = 1` returns the words unchanged (as fresh `Str` values); `n =
  words.len()` returns one shingle.
- `ngram_char_shingles(text, n)` returns `text.len() - n + 1` shingles when
  `n >= 1` and `text.len() >= n`, otherwise `[]`.
- `ngram_unique` keeps the first occurrence of each distinct shingle;
  `[]` for an empty input.
- No function mutates its inputs; every returned `Vec` is freshly allocated.

## 5. Similarity formulas

With `A`, `B` the distinct shingle sets of the two arguments, `inter =
|A ∩ B|`, and integer division truncating toward zero:

| Function | Formula | Value |
|---|---|---|
| `ngram_jaccard` | `floor(1000 * inter / |A ∪ B|)` | 0..1000 |
| `ngram_dice` | `floor(2000 * inter / (|A| + |B|))` | 0..1000 |

Degenerate cases: `ngram_jaccard` is `0` when both sets are empty (the union
is empty) and `0` when either side is empty; `ngram_dice` is `0` whenever
`|A| + |B| = 0` and `0` when either side is empty (the numerator is 0).

Pinned examples:

| A | B | Jaccard | Dice |
|---|---|---|---|
| `{a,b,c}` | `{a,b,c}` | 1000 | 1000 |
| `{a,b,c,d}` | `{c,d,e,f}` | 333 (= 2/6) | 500 (= 4/8) |
| `{a,b}` | `{b,c}` | 333 (= 1/3) | 500 (= 2/4) |
| `{a,b,c}` | `{a,b,c,d}` | 750 (= 3/4) | 857 (= 6/7) |
| `{a}` | `{a,b}` | 500 (= 1/2) | 666 (= 2/3) |
| `{}` | `{}` | 0 | 0 |

## 6. MinHash

### 6.1 Hash recipe

`ngram_minhash_signature(shingles, hashes, seed)` computes, for each slot
`i in 0..hashes`, the minimum over all shingles `s` of

```
h(seed, i, s) = FNV1a32( bytes( decimal(seed) + ":" + decimal(i) + ":" + s ) )
```

where `decimal(x)` is the base-10 rendering of a signed `Int` (`-7` -> `"-7"`)
from `xiom.convert.int.int_to_string`, and FNV-1a 32-bit is

```
h0 = 2166136261
for each byte b:
  h = ((h XOR b) * 16777619) mod 2^32
```

evaluated incrementally over the three parts and the two literal `":"`
separators (equivalent to hashing the concatenation). All arithmetic stays in
non-negative `Int` values below `2^56` before the `mod`, so no overflow
occurs on 64-bit `Int`. The result of every slot is therefore in
`0..2^32-1`.

### 6.2 Signature semantics

- The result has exactly `hashes` elements (one per slot), in slot order.
- Empty `shingles` yields a vector of `hashes` zeros (each slot's minimum is
  taken over an empty range and defined as 0).
- `hashes < 1` yields `[]` (documented total behaviour; `hashes >= 1` is the
  intended use).
- The signature is deterministic in `(shingles, hashes, seed)`; duplicate
  shingles cannot lower a minimum twice, so the signature depends only on the
  underlying shingle set.

### 6.3 Signature similarity

`ngram_signature_similarity(a, b)` is `floor(1000 * matches / len(a))` where
`matches` counts positions with equal elements; it is `0` when the lengths
differ and `0` when both are empty. For signatures produced with the same
`hashes` and seed this estimates the Jaccard similarity (MinHash property);
it is an estimate because the hash space is only 32 bits and finite.

## 7. API signatures

```xi
pub fn ngram_words(text: Str) -> Vec[Str]
pub fn ngram_shingles(words: &Vec[Str], n: Int) -> Vec[Str]
pub fn ngram_char_shingles(text: Str, n: Int) -> Vec[Str]
pub fn ngram_unique(shingles: &Vec[Str]) -> Vec[Str]
pub fn ngram_jaccard(a: &Vec[Str], b: &Vec[Str]) -> Int
pub fn ngram_dice(a: &Vec[Str], b: &Vec[Str]) -> Int
pub fn ngram_minhash_signature(shingles: &Vec[Str], hashes: Int, seed: Int) -> Vec[Int]
pub fn ngram_signature_similarity(a: &Vec[Int], b: &Vec[Int]) -> Int
```

No function has an error path. Negative `n`, `hashes` and `seed` are
accepted (`n < 1` and `hashes < 1` clamp to empty results; `seed` is signed
and hashed verbatim).

## 8. Complexity

| Function | Time | Memory |
|---|---|---|
| `ngram_words` | O(len) | O(tokens) |
| `ngram_shingles` | O(n * window chars) | O(output bytes) |
| `ngram_char_shingles` | O(n * (len - n + 1)) | O(output bytes) |
| `ngram_unique` | O(k²) str_compare | O(distinct) |
| `ngram_jaccard` / `ngram_dice` | O(k²) str_compare | O(distinct) |
| `ngram_minhash_signature` | O(hashes * k * key length) | O(hashes) |
| `ngram_signature_similarity` | O(length) | O(1) |

`k` is the number of distinct shingles. All counts are small relative to the
input for the intended near-duplicate workflows; there is no hashing index,
so set operations are quadratic in the number of distinct shingles.

## 9. Test plan

`tests/test_conformance.xi` (module `ngram_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | words: scan and lowercase | basic token + ASCII lowering |
| t2 | words: underscore/digits | `_` separates, `[0-9]` are word bytes (rule 1) |
| t3 | words: non-ASCII separators | `café`, `naïve`, CJK, em dash (rule 1) |
| t4 | words: separator runs | collapse, empty and punctuation-only (rule 1) |
| t5 | shingles: bigrams of a sentence | known window contents and count |
| t6 | shingles: n = 1, 3, len | identity, trigrams, full-length window |
| t7 | shingles: too short / n < 1 | empty vectors (section 4) |
| t8 | char shingles: counts/edges | `abcde` n = 1, 2, 5, 6, 0, empty |
| t9 | char shingles: UTF-8 | verbatim byte slices, split multi-byte char |
| t10 | unique: first-seen order | order, duplicates, empty, single |
| t11 | jaccard: identical/empty | 1000 with duplicates, 0 for empty pair |
| t12 | jaccard: disjoint/one empty | 0 in both directions |
| t13 | jaccard: pinned overlaps | 333 (2/6), 333 (1/3), 750, symmetry |
| t14 | dice: identical/half | 1000, 500, 500 |
| t15 | dice: subset/empty | 666 (2/3), 0 for empty and disjoint |
| t16 | minhash: length/zeros | length = hashes, all zeros for empty, hashes = 0 |
| t17 | minhash: determinism | repeatable; seed change changes signature; length |
| t18 | minhash: range | every slot in 0..2^32-1 |
| t19 | signature similarity | 1000 identical, 0 disjoint, 500 partial, mismatch 0 |
| t20 | near-duplicate ordering 1 | one-word change outranks unrelated text |
| t21 | near-duplicate ordering 2 | second concrete pair preserves ordering |
| t22 | pipeline | words -> shingles -> unique/jaccard/dice/minhash |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); every `Vec` element read is pinned with a typed `let`.

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.ngram
```

Last verified: compiler 0.61.3, `port: PASS (passed=22 failed=0
program_exit=0 exit=0)`.

## 10. Known limitations

- ASCII-only word alphabet and ASCII-only lowercasing; accented letters and
  CJK are separators, so no Unicode word tokens are ever produced.
- Character shingles are bytes, not Unicode characters; `n` is a byte count.
- The MinHash hash is 32-bit FNV-1a over a decimal-rendered key: not
  cryptographic, collision-prone at scale, and not compatible with any other
  library's FNV/MinHash convention.
- Similarity is set-based: order, multiplicity and position are ignored;
  scores are truncated permille, so equality on sets is exactly 1000 but
  small overlaps may score 0.
- `ngram_shingles` joins with a literal space and does not escape token
  content.
- No streaming, no indexes, no parallel hashing; everything is in memory and
  single-threaded.

## 11. Compiler / stdlib notes for v0.61.3

- `str_compare` lives in `xiom.string.compare`, not `xiom.string`; the module
  imports both.
- `int_to_string` is taken from `xiom.convert.int`.
- Vec-sourced `Str` elements are compared only via `str_compare` (BUG 17) and
  every element read is pinned with a typed `let` (`let s: Str = v[i];`).
- All code uses free functions, `while` loops, flat `if`/`elif`/`else`; there
  are no inline lambdas, no `self` methods, no `match`, no `mut` patterns and
  no `Vec[StructType]`.
- The `^` XOR operator is used only between non-negative `Int` values below
  `2^32`; the subsequent `% 4294967296` keeps every intermediate below `2^56`.
- Only `&` (never `&mut`) is taken of locals in call sites, so the E001
  borrow-order warning does not fire.
