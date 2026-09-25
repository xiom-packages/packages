# xiom.bloom -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.bloom`, version `0.1.0`).
Module: `src/bloom.xi` (`module xiom.bloom`).
Depends on `xiom.std` only (platform dependency; the module imports
`xiom.string` for byte access, the tests add `xiom.test`, `xiom.io` and
`xiom.string.compare`).

## Scope

Pure-XIOM (no FFI) Bloom filter over a flat byte buffer:

- construction from `(m bits, k hashes)` with strict validation;
- bit storage in a single `Vec[UInt8]` (no per-entry objects);
- insert/contains through `k` derived hashes using double hashing over two
  stable 32-bit hashes (FNV-1a plus an independent mixing hash);
- `clear` and the count of set bits;
- an integer permille estimate of the current false-positive rate;
- strict serialization to/from a byte buffer (version 1) with round-trip;
- `union` (exact) and `intersection` (bitwise AND, approximate as a set
  operation) for equal-shape filters.

All-integer arithmetic: no floats, no rounding surprises beyond the
documented fixed-point evaluation of the false-positive estimate.

## Non-goals

- Counting Bloom filters, deletion, or bucket counters of any kind.
- Scalable/partitioned/dynamic filters that grow with the key count.
- Cryptographic guarantees: the two hashes are non-cryptographic and an
  adversary can craft collisions. A `true` answer is always probabilistic.
- Hash-set or exact-set replacement: false positives are inherent.
- File or network IO; serialization only produces and consumes an in-memory
  byte buffer.
- Concurrency: plain value types, no locking, not thread-safe by themselves.

## Parameters and validation

| Constant | Value | Meaning |
|---|---|---|
| `bloom_max_bits()` | `1073741824` (2^30) | Largest accepted `m`, in bits (128 MiB of storage). |
| `bloom_max_hashes()` | `1024` | Largest accepted `k`. |
| `bloom_version()` | `1` | Serialization format version. |
| `bloom_header_len()` | `11` | Serialized header length in bytes. |

`bloom_new(m, k)` and `bloom_from_bytes` share one validation helper; the
first failing rule decides the message, in this order:

1. `m <= 0` -> `bloom: m must be positive`;
2. `k <= 0` -> `bloom: k must be positive`;
3. `m > 2^30` -> `bloom: m exceeds maximum`;
4. `k > 1024` -> `bloom: k exceeds maximum`.

A valid filter satisfies `0 < m <= 2^30`, `0 < k <= 1024` and stores exactly
`ceil(m / 8)` payload bytes.

## Bit storage

- Bit `j` (`0`-based) lives in `bits[j / 8]` at bit position `j % 8`,
  counting from the least significant bit: byte `b` holds bits
  `8b .. 8b+7`.
- Bits at positions `>= m` (the high padding bits of the last byte) are
  always zero in filters built by this module, and `bloom_from_bytes`
  rejects a buffer whose padding is not zero (see the error catalog).
- `bloom_set_count` counts exactly the `m` valid bits.
- `bloom_byte_len(bf)` is `ceil(m / 8)`.

Bit access is implemented arithmetically (division by powers of two built by
doubling) instead of shifts/masks, matching the v0.61.3 notes below.

## Hash construction

Two stable 32-bit hashes over the UTF-8 bytes of a `Str`; both return an
`Int` in `0..2^32-1`.

`bloom_hash1` -- FNV-1a 32-bit:

```
h = 2166136261                       (0x811C9DC5 offset basis)
for each byte b:
  h = (h XOR b) mod 2^32
  h = (h * 16777619) mod 2^32        (0x01000193 prime)
```

Pinned vectors (published FNV-1a values): `""` -> `2166136261`, `"a"` ->
`3826002220`, `"foobar"` -> `3214735720`, `"hello"` -> `1335831723`.

`bloom_hash2` -- independent mixing hash:

```
h = 2654435761                       (0x9E3779B9, Knuth golden-ratio constant)
for each byte b:
  h = (h + b + 1) mod 2^32
  h = (h * 2654435761) mod 2^32
h = (h + h / 65536) mod 2^32         (fold the high half into the low half)
h = (h * 2246822519) mod 2^32        (0x85EBCA6B finalizer)
h = (h + h / 65536) mod 2^32
```

Pinned vectors: `""` -> `1223194048`, `"a"` -> `2230179447`, `"bloom"` ->
`3295578999`, `"xiom.bloom"` -> `2938125760`.

Every 32x32 multiplication goes through an exact 16-bit-split helper
(`_mul32`) because a raw 32x32 product can exceed the signed 64-bit `Int`.
All arithmetic is modulo `2^32`; the two functions share no constant
combination, so they are independent enough for double hashing.

## Double hashing

For a hash pair `(h1, h2)` and probe ordinal `i`:

```
index_i = (h1 + i * h2) mod m        for i in 0..k-1
```

Both hashes are first reduced modulo `m` with floor semantics
(`_mod_floor`), so negative `Int` arguments are accepted and mapped into
`0..m-1`. The iterative form `cur = (cur + b) mod m` is used by
`bloom_insert`/`bloom_contains`; `bloom_derive_index` evaluates the direct
form. If `h2 mod m == 0`, every probe hits `h1 mod m`; callers passing
explicit hashes control this, and the built-in pair makes it rare.

`bloom_derive_index` rejects `i < 0` or `i >= k` with
`bloom: hash index out of range`; insert/contains never produce a bad `i`.

## Serialization layout (version 1)

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 1 | version | byte, must be `1` |
| 1 | 4 | `m` (bit length) | u32 little-endian |
| 5 | 2 | `k` | u16 little-endian |
| 7 | 4 | payload byte length | u32 little-endian, must equal `ceil(m / 8)` |
| 11 | `ceil(m / 8)` | payload bits | bit `j` at `payload[j / 8]` bit `j % 8`, LSB first |

Total length is exactly `11 + ceil(m / 8)`; padding bits are zero.
`bloom_to_bytes` never fails. `bloom_from_bytes` validates, in order:

1. length `>= 11` (else truncated);
2. version byte `== 1` (else unsupported version);
3. decoded `m`/`k` pass the shared size rules (else the size messages);
4. declared payload length `== ceil(m / 8)` (else byte length mismatch);
5. length `>= 11 + declared` (else truncated);
6. length `== 11 + declared` (else trailing bytes);
7. padding bits zero (else padding not zero).

## Error catalog

Deterministic `Err(Str)` messages; every message is pinned by a test.

| Message | Raised by | Condition |
|---|---|---|
| `bloom: m must be positive` | `bloom_new`, `bloom_from_bytes` | `m <= 0` |
| `bloom: k must be positive` | `bloom_new`, `bloom_from_bytes` | `k <= 0` |
| `bloom: m exceeds maximum` | `bloom_new`, `bloom_from_bytes` | `m > 2^30` |
| `bloom: k exceeds maximum` | `bloom_new`, `bloom_from_bytes` | `k > 1024` |
| `bloom: hash index out of range` | `bloom_derive_index` | `i < 0` or `i >= k` |
| `bloom: truncated buffer` | `bloom_from_bytes` | buffer shorter than the header or than header + declared payload |
| `bloom: unsupported version` | `bloom_from_bytes` | byte 0 is not `1` |
| `bloom: byte length mismatch` | `bloom_from_bytes` | declared payload length differs from `ceil(m / 8)` |
| `bloom: trailing bytes` | `bloom_from_bytes` | buffer longer than header + declared payload |
| `bloom: padding not zero` | `bloom_from_bytes` | a bit at position `>= m` is set |
| `bloom: union size mismatch` | `bloom_union` | `a.m != b.m` or `a.k != b.k` |
| `bloom: intersection size mismatch` | `bloom_intersection` | `a.m != b.m` or `a.k != b.k` |

## False-positive estimate

`bloom_fp_permille(bf)` returns an integer in `0..1000` (permille, i.e.
tenths of a percent). It uses the standard set-bit estimate

```
FPR ~= (X / m)^k
```

where `X = bloom_set_count(bf)`, which is the usual approximation of
`(1 - e^(-kn/m))^k`. Integer evaluation, documented rounding:

```
p   = floor(10^6 * X / m)      fill ratio in millionths
acc = 10^6
repeat k times: acc = floor(acc * p / 10^6)
result = floor((acc + 500) / 1000)   rounded to nearest permille
```

`X == 0` returns `0`; `X == m` returns `1000`. Because the estimate is based
on observed fill, it needs no insert counter and reacts to insert
duplicates. It is an approximation: do not treat it as an exact bound.

## API contract

```xi
pub type BloomFilter = { m: Int; k: Int; bits: Vec[UInt8]; }

pub fn bloom_max_bits() -> Int
pub fn bloom_max_hashes() -> Int
pub fn bloom_version() -> Int
pub fn bloom_header_len() -> Int

pub fn bloom_new(m: Int, k: Int) -> Result[BloomFilter, Str]
pub fn bloom_m(bf: &BloomFilter) -> Int
pub fn bloom_k(bf: &BloomFilter) -> Int
pub fn bloom_byte_len(bf: &BloomFilter) -> Int

pub fn bloom_hash1(s: Str) -> Int
pub fn bloom_hash2(s: Str) -> Int

pub fn bloom_derive_index(bf: &BloomFilter, h1: Int, h2: Int, i: Int) -> Result[Int, Str]
pub fn bloom_insert(bf: &mut BloomFilter, h1: Int, h2: Int)
pub fn bloom_contains(bf: &BloomFilter, h1: Int, h2: Int) -> Bool
pub fn bloom_add_str(bf: &mut BloomFilter, s: Str)
pub fn bloom_has_str(bf: &BloomFilter, s: Str) -> Bool
pub fn bloom_clear(bf: &mut BloomFilter)

pub fn bloom_set_count(bf: &BloomFilter) -> Int
pub fn bloom_is_empty(bf: &BloomFilter) -> Bool
pub fn bloom_fp_permille(bf: &BloomFilter) -> Int
pub fn bloom_equal(a: &BloomFilter, b: &BloomFilter) -> Bool

pub fn bloom_to_bytes(bf: &BloomFilter) -> Vec[UInt8]
pub fn bloom_from_bytes(data: &Vec[UInt8]) -> Result[BloomFilter, Str]

pub fn bloom_union(a: &BloomFilter, b: &BloomFilter) -> Result[BloomFilter, Str]
pub fn bloom_intersection(a: &BloomFilter, b: &BloomFilter) -> Result[BloomFilter, Str]
```

Semantics highlights:

- `bloom_insert` sets the `k` bits at `bloom_derive_index(bf, h1, h2, i)`;
  re-inserting a pair is a no-op. `bloom_add_str` is
  `bloom_insert(bf, bloom_hash1(s), bloom_hash2(s))`.
- `bloom_contains` is `true` only when all `k` probe bits are set: no false
  negatives for values inserted through this API, false positives possible.
- `bloom_clear` zeroes the payload, keeping `m`/`k`.
- `bloom_equal` compares `m`, `k` and every payload byte.
- `bloom_union` is the bitwise OR and is exact as a set union of the
  inserted values (any key in either input is reported; the false-positive
  rate can only grow). `bloom_intersection` is the bitwise AND and is
  APPROXIMATE: every key inserted into both inputs is still reported, but
  the AND of two filters can report keys present in neither input.
- `bloom_to_bytes` round-trips through `bloom_from_bytes` for every filter
  built by this module (`bloom_equal` is `true`).

## Complexity

| Operation | Time | Space |
|---|---|---|
| `bloom_new` / `bloom_from_bytes` | O(m) | O(m) |
| `bloom_insert` / `bloom_contains` | O(k) | O(1) |
| `bloom_add_str` / `bloom_has_str` | O(\|s\| + k) | O(1) |
| `bloom_clear` | O(m) | O(1) |
| `bloom_set_count` / `bloom_is_empty` / `bloom_fp_permille` | O(m + k) | O(1) |
| `bloom_equal` | O(m) | O(1) |
| `bloom_to_bytes` / `bloom_from_bytes` | O(m) | O(m) |
| `bloom_union` / `bloom_intersection` | O(m) | O(m) |

The per-bit byte helpers are O(8) constant work; `m` is capped at 2^30 bits.

## Test matrix

`tests/test_conformance.xi` (`module bloom_tests`, 25 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test and returns the failure
count; test functions are called directly, not through a dispatch table).

1. constants pinned: caps, version, header length;
2. `bloom_new` sizes, accessors, empty stats, `clear` on empty;
3. boundary sizes accepted: `m=1`, `k=1024`, `m=1024` (byte length 1/2/128);
4. non-positive `m` and `k` rejected with pinned messages (incl. `0, 0`);
5. oversized `m` and `k` rejected; very negative `m` is a positivity error;
6. index arithmetic pinned for `(3, 5)` on `m=16` -> `3, 8, 13, 2`;
   `i = -1` and `i = 4` -> hash-index error;
7. negative hashes wrap with floor semantics (`-1 mod 16 = 15`,
   `-17 mod 16 = 15`);
8. `k=1` insert sets exactly the `h1 mod m` bit; `h2` is ignored; repeat
   insert is a no-op;
9. `k=4` sets exactly the derived bits, is idempotent, and an overlapping
   insert adds only the new bit;
10. `clear` drops every bit and membership;
11. `m=1` degenerate filter: one bit, every pair reports membership;
12. string API determinism: identical inserts produce byte-identical
    filters and identical query outcomes for probes;
13. FNV-1a 32-bit pinned against published vectors and range-checked;
14. mixing hash pinned, deterministic, distinct from FNV-1a, range-checked;
15. exact set counts (including padding not counted for `m=11`);
16. false-positive permille pinned at 0 / 500 / 250 / 1000;
17. serialization layout pinned byte-for-byte (`m=16, k=3`, bits 3/8/13)
    and round-trip;
18. short buffers are `truncated buffer` (empty, 10-byte, header-only,
    one byte short) and the full buffer parses;
19. only version 1 is accepted (0 and 2 rejected);
20. declared byte length checked (too large and too small) and trailing
    bytes rejected;
21. decoded `m`/`k` reuse the `bloom_new` size rules (four messages);
22. dirty padding rejected; a clean `m=11` buffer and a real `m=11` filter
    round-trip;
23. union is the exact OR, union with an empty filter is the identity, and
    both mismatch shapes are `union size mismatch`;
24. intersection is the AND, intersection with an empty filter is empty,
    and both mismatch shapes are `intersection size mismatch`;
25. `bloom_equal` compares `m`, `k` and payload bits.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.bloom
```

Last verified: compiler 0.61.3,
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Probabilistic structure: false positives are possible and the documented
  estimate is approximate. Intersection is bitwise AND, not exact set
  intersection.
- No deletion and no insert counter: remove requires rebuilding from the
  original keys; the false-positive estimate infers the load from set bits.
- No `apply_diff`-style in-place mutation of the payload except through
  insert/clear; the struct's Vec field is exposed by value semantics, so
  callers should go through the functions.
- The `m` cap (2^30 bits) bounds allocation at 128 MiB; `bloom_new` near the
  cap is O(m) and allocates the whole payload up front.
- `k` is capped at 1024; larger probe counts are almost never useful and
  would make insert/contains proportionally slower.
- Filters are only interchangeable when both `m` and `k` match; there is no
  automatic resizing or rehashing.
- Non-cryptographic hashes; not suitable as a security primitive.

## Compiler / stdlib notes for v0.61.3

- Free functions only (no methods, no lambdas, no `Vec[StructType]`); the
  filter is a plain struct with one flat `Vec[UInt8]` payload.
- Raw bytes read from a `Vec[UInt8]` are widened with `(x as Int) & 0xFF`
  before arithmetic or comparison (comparing a raw `UInt8` against a
  constant `>= 128` miscompiles).
- No shift operators and no bitwise AND on values with bit 31 set; bit
  positions are read with division and powers of two built by doubling.
- Both hashes use `_mul32`, an exact 16-bit-split 32x32 multiply, because a
  raw 32x32 product can overflow the signed 64-bit `Int`.
- `Ok`/`Err` are constructed only in the tiny leaf helpers
  (`_ok_filter`/`_err_filter`/`_ok_int`/`_err_int`); the larger functions
  return those values.
- Test functions are called directly from `main` (indexed `Vec[fn]` calls
  miscompile); test files pass `&mut` at every call site to the read-only
  helper wrappers to keep the advisory E001 borrow warnings out of the
  output, and Str equality goes through `xiom.string.compare.str_compare`.
- The module shares only the root `xiom` segment with stdlib namespaces, so
  the section-4 namespace check passes.
