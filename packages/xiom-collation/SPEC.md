# xiom.collation -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.collation` (`src/collation.xi`). Pure XIOM, no FFI.
Manifest: `package.xi` (name `xiom.collation`). Depends on `xiom.std` only
(`xiom.string.byte_at`, `xiom.string.str_len`).

## 1. Scope

Deterministic, dependency-free collation for `Str` values:

- `collate_compare` / `collate_equal`: case-insensitive lexicographic order
  with a case-sensitive tie-break;
- `collate_natural_compare`: numeric-aware order for runs of ASCII digits;
- `collate_sort` / `collate_natural_sort`: stable insertion sorts returning
  fresh vectors;
- `collate_key`: ASCII-case-folded key strings.

## 2. Non-goals

- Locale-aware collation (ICU/Unicode Collation Algorithm, tailorings, case
  folding beyond ASCII, normalization).
- Accent/diacritic insensitivity.
- Generic comparators or key types (XIOM v0.61.x has no first-class generic
  comparator plumbing here).
- Streaming comparison of huge inputs, or in-place sorting.
- Any FFI or file/registry integration.

## 3. Comparison model

`Str` is treated as its UTF-8 byte sequence. Every byte is read with
`xiom.string.byte_at` and masked to an unsigned value 0..255.

### 3.1 `collate_compare(a, b) -> Int`

Two passes:

1. **Primary (case-insensitive).** Walk both strings byte by byte; at each
   position fold `A`-`Z` (0x41..0x5A) to lowercase (`+0x20`) and compare the
   folded bytes: the first folded difference decides (-1 when `a` is smaller,
   1 when larger). If one string is a prefix of the other, the shorter sorts
   first.
2. **Tie-break (case-sensitive).** When the primary pass is equal (the strings
   have equal length and identical folded bytes), compare raw bytes from the
   start; at the first differing byte the larger byte value sorts first.
   Because the primary pass already matched, a raw difference can only be an
   ASCII letter-case pair, so the rule reads: **lowercase before uppercase**
   (`"apple" < "Apple"`, `"a" < "A"`).

The result is always exactly -1, 0 or 1, and is 0 only for byte-identical
strings. Complexity O(min(|a|, |b|)).

### 3.2 `collate_equal(a, b) -> Bool`

True iff `collate_compare(a, b) == 0`, i.e. exact byte equality. Case variants
are ordered by the tie-break and therefore not equal; case-insensitive
equality is expressed as `str_compare(collate_key(a), collate_key(b)) == 0`.

## 4. Natural comparison model

`collate_natural_compare(a, b) -> Int` walks both strings left to right:

- **Digit pair.** When the current byte of both strings is an ASCII digit,
  the two maximal digit runs are compared as integers without parsing:
  leading zeros are skipped (at least one digit is kept), the run with more
  significant digits is larger, then equal-length significant digits compare
  lexicographically. If the integer values are equal, the **longer raw run
  sorts first**, so `"007" < "7"`, `"x007" < "x7"`, `"run007" < "run7"`.
  Equal-value runs of equal length are byte-identical and continue the walk.
- **Any other pair** (including a digit against a non-digit) compares exactly
  like the `collate_compare` primary pass: folded bytes, first difference
  decides. A case-only difference (`A` vs `a`) is remembered as a pending
  tie-break, mirroring `collate_compare`'s primary/secondary structure: it is
  applied only if the entire primary comparison ties.
- **Exhaustion.** If one string is exhausted first, the shorter sorts first.
- Identical strings return 0; otherwise -1 or 1.

"Value first, then run length" means `"file2" < "file10"`, `"a9" < "a10"` and
`"x007" < "x7"`. Since runs are compared by digit count and digit values, no
integer overflow can occur for arbitrarily long digit runs. Complexity
O(|a| + |b|).

## 5. Sorting and keys

`collate_sort(words: &Vec[Str]) -> Vec[Str]`
: Stable insertion sort by `collate_compare`. Walks the input once, inserts
  each element into a fresh output vector after all strictly-smaller elements
  (`collate_compare(prev, w) > 0` is the shift condition), so elements that
  compare equal keep their relative input order. Only byte-identical elements
  compare equal, so this is stability for identical duplicates. The input is
  read through an immutable reference and never modified. O(n^2) comparisons,
  O(n) element moves.

`collate_natural_sort(words: &Vec[Str]) -> Vec[Str]`
: The same stable insertion sort using `collate_natural_compare`.

`collate_key(s: Str) -> Str`
: A copy of `s` with `A`-`Z` folded to `a`-`z`; every other byte is copied
  unchanged, so the length (in bytes) is preserved. Two strings differing only
  by ASCII letter case produce byte-identical keys. Comparing keys with
  `xiom.string.str_compare` reproduces the case-insensitive primary order of
  `collate_compare`; the lowercase-first case tie-break is deliberately not
  encoded (keys of case variants are equal even though the strings are
  ordered). O(|s|).

## 6. API signatures

```xi
pub fn collate_compare(a: Str, b: Str) -> Int
pub fn collate_equal(a: Str, b: Str) -> Bool
pub fn collate_natural_compare(a: Str, b: Str) -> Int
pub fn collate_sort(words: &Vec[Str]) -> Vec[Str]
pub fn collate_natural_sort(words: &Vec[Str]) -> Vec[Str]
pub fn collate_key(s: Str) -> Str
```

## 7. Test plan

`tests/test_conformance.xi` (module `collation_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Element checks use `str_compare` (BUG 17: `==` on
`Str` values read from a `Vec` lowers to a pointer comparison).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | case-insensitive order | `"apple" < "Banana"`, symmetric |
| t2 | case tie-break | lowercase first: `"apple" < "Apple"` |
| t3 | identical / prefix | `0` for identical, shorter prefix first |
| t4 | empty vs non-empty | `"" < "a"`, `"" == ""` |
| t5 | natural numeric runs | `"file2" < "file10"` |
| t6 | `a9` vs `a10` | multi-run versions too |
| t7 | leading zeros | `"x007" < "x7"`, `"007" < "7"` |
| t8 | equal values, unequal lengths | never 0; signs both ways |
| t9 | digit run at start | `"2abc" < "10abc"`, `"007x" < "7x"` |
| t10 | `collate_sort` order | case-insensitive with case tie-break |
| t11 | `collate_sort` stability | duplicates keep relative order |
| t12 | `collate_natural_sort` | `File1 < file2 < file10` |
| t13 | `collate_key` folds | ASCII letters folded, empty preserved |
| t14 | `collate_key` bytes | length preserved, non-ASCII untouched |
| t15 | natural vs plain | plain `"file10" < "file2"`; natural reverses |
| t16 | non-ASCII | unsigned UTF-8 byte order (`"z" < "é"`) |
| t17 | bare numbers | `2 < 007 < 7 < 10` naturally |
| t18 | antisymmetry | sign flips, 0 only for identical, case tie in natural |
| t19 | `collate_equal` semantics | exact equality; keys equal for case variants |
| t20 | fresh output | input unchanged; empty and single-element sorts |

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.collation
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## 8. Known limitations

- ASCII-oriented: case folding covers `A`-`Z` only. Non-ASCII letters (e.g.
  Latin-1, Greek, Cyrillic) are not folded, accents are significant, and no
  locale tailoring (Turkish dotless i, German sharp s, Swedish a-ring, ...) is
  applied.
- Bytes >= 0x80 compare by unsigned UTF-8 byte value. For well-formed UTF-8
  this matches code-point order, but it is not the Unicode Collation
  Algorithm; it is stable and platform-independent.
- `collate_equal` is exact equality, not case-insensitive equality (see 3.2).
- Natural comparison recognizes runs of ASCII digits only; `+`, `-`, `.` and
  `,` are ordinary characters (`"v1.10" < "v1.9"` only because of the `.` and
  digit runs are compared inside each component).
- Sorting is insertion sort, O(n^2) in the worst case; fine for small and
  medium vectors, not for large dataset sorting.
- No generic comparator parameter; the two sorts are fixed to the two
  comparators. No streaming API.
- `collate_key` is not an ICU-style multi-level collation key; it encodes only
  the ASCII case-insensitive primary order.

## 9. Compiler / stdlib notes (v0.61.3)

- Byte access goes through `xiom.string.byte_at` (raw byte), masked with
  `& 0xFF` so comparisons are unsigned regardless of the cast's sign behavior;
  the upstream `xiom.string.str_compare` does the same without the mask.
- No contracts (`requires`/`ensures`) are declared: the functions are total
  and the module follows the xiom.csv style (doc comments, no contract
  clauses), which also keeps library compilation under `--emit-ir` simple.
- `str_compare` is imported from `xiom.string.compare` in the tests, mirroring
  `xiom.csv`/`xiom.lru`; `use xiom.string;` alone does not export it.
- Only `&` (never `&mut`) is taken of locals at call sites, so the advisory
  E001 aliasing warning does not fire.
- The module name `xiom.collation` shares only the root `xiom` segment with
  the stdlib's `xiom.string.collate`; the section-4 namespace rule passes.
