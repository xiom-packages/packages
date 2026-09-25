# xiom.fnv -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.fnv`, version `0.1.0`).
Module: `src/fnv.xi` (`module xiom.fnv`).
Depends on `xiom.std`; the library module imports `xiom.string` (for the
hex display helpers); the tests import `xiom.test`, `xiom.io` and
`xiom.string`.

## Scope

A pure-XIOM (no FFI), Int-only implementation of the Fowler/Noll/Vo hash
family as published at <https://www.isthe.com/chongo/tech/comp/fnv/>
(CC0 public domain), over fully materialized `Vec[UInt8]` buffers:

- one-shot functions `fnv1_32`, `fnv1a_32`, `fnv1_64`, `fnv1a_64`;
- incremental triples `fnv_<v>_init/update/finalize` for each of the
  four variants, over an explicit state `Int`;
- the specification constants (`fnv_offset_basis32/64`,
  `fnv_prime32/64`);
- unsigned display helpers `fnv_hex32` (8 digits) and `fnv_hex64`
  (16 digits).

The one-shot functions and the incremental `update` share one byte loop
per variant, so the two surfaces are equal by construction and the
conformance suite pins that equality at every split point.

## Non-goals

- 128-bit and 256-bit FNV variants; FNV-0; xor-folding to non-power-of-two
  hash sizes; seeded/keyed wrappers.
- Any other hash family (Adler, CRC, xxHash, ...) -- this package is FNV
  only.
- Cryptographic claims of any kind: FNV is not a MAC, is not
  collision-resistant and is trivially forgeable.
- Streaming hasher objects, struct types, methods, or callback-based
  dispatch: the incremental API is explicit state Ints.
- Lookup tables, SIMD, FFI or any dependency beyond `xiom.std`.
- Error types: every function is total (see the error catalog below).

## Specification constants

| Width | Offset basis (hex) | Offset basis (decimal) | Prime (hex) | Prime (decimal) |
|---|---|---|---|---|
| 32 | `0x811C9DC5` | `2166136261` | `0x01000193` | `16777619` |
| 64 | `0xCBF29CE484222325` | `14695981039346656037` | `0x00000100000001B3` | `1099511628211` |

Both FNV-1 and FNV-1a use the same offset basis and prime per width. The
32-bit offset basis 2166136261 is representable as a non-negative `Int`;
the 64-bit basis is not, so `fnv_offset_basis64()` returns it as the
signed two's-complement value `14695981039346656037 - 2^64 =
-3750763034362895579`.

## Algorithm

Definitions follow the FNV specification exactly.

**FNV-1** (and `fnv1_32` / `fnv1_64`):

```
hash = offset_basis
for each octet b of data, in order:
  hash = (hash * prime) mod 2^width
  hash = hash xor b
return hash
```

**FNV-1a** (and `fnv1a_32` / `fnv1a_64`): the same loop with the two
operations exchanged:

```
hash = offset_basis
for each octet b of data, in order:
  hash = hash xor b
  hash = (hash * prime) mod 2^width
return hash
```

The XOR operates on the low-order octet of the hash (the specification's
"xor the bottom with the current octet"). An empty input returns the
offset basis unchanged, for both variants and both widths.

Incremental semantics: `fnv_<v>_update(state, data)` applies the byte
loop above starting from `state`, so for any split `data = a || b`:

```
fnv_<v>_update(fnv_<v>_update(fnv_<v>_init(), a), b) == fnv_<v>(data)
```

`fnv_<v>_finalize(state)` is the identity: FNV applies no output
transformation (no final XOR, no avalanche). It exists so the incremental
API has the classic init/update/finalize shape.

## Numeric representation

| Width | State domain | Result |
|---|---|---|
| 32 | non-negative `Int` in `[0, 2^32)` | same, so `[0, 2^32 - 1]` |
| 64 | any `Int`, interpreted as its 64-bit two's-complement pattern | signed view of the unsigned 64-bit hash |

For 64 bits, unsigned values `>= 2^63` are negative in the returned
`Int`; `fnv_hex64` renders the pattern unsigned. For example the empty
input is `-3750763034362895579` (`0xCBF29CE484222325`), and
`fnv1a_64("foobar")` is `-8821353812377114648`
(`0x85944171F73967E8`).

`update` is total: a 32-bit state of any `Int` is reduced modulo `2^32`
by the multiply; a 64-bit state of any `Int` is consumed as its
two's-complement pattern by the limb decomposition.

## Wrapping arithmetic (Int-only, exact)

The package never uses BigInt, FFI, or the compiler's `*`/`<<` overflow
behavior. The modular products are computed with bounds that keep every
intermediate inside Int64.

### 32-bit multiply

```
_mul32(state) = ((state mod 2^32) * 16777619) mod 2^32
```

`(2^32 - 1) * 16777619` is below `7.21 * 10^16`, far below the Int64
maximum `9223372036854775807`, so the product is exact; the trailing
modulo performs the wrap. The negative-residue adjustment keeps the
result non-negative under either truncating or flooring `%` semantics.

### 64-bit multiply: limb split

The prime is decomposed as `1099511628211 = 435 + 256 * 2^32`, and the
state into four 16-bit limbs (each in `[0, 65535]`):

```
state = x3 * 2^48 + x2 * 2^32 + x1 * 2^16 + x0
```

The product terms with total weight below `2^64` are, by 16-bit column:

```
col 0: x0 * 435
col 1: x1 * 435
col 2: x2 * 435 + x0 * 256
col 3: x3 * 435 + x1 * 256
```

Higher columns (`x2*256` at col 4 and above) are multiples of `2^64` and
vanish modulo `2^64`. Carries are propagated from col 0 to col 3:

```
r0 = t0 mod 2^16      c0 = floor(t0 / 2^16)
t1 = x1*435 + c0      r1 = t1 mod 2^16      c1 = floor(t1 / 2^16)
t2 = x2*435 + x0*256 + c1                  r2, c2 likewise
t3 = x3*435 + x1*256 + c2                  r3 = t3 mod 2^16
```

Bounds (all well below Int64, so nothing overflows):

| Value | Upper bound | Bound as a power of two |
|---|---|---|
| `t0` | `65535 * 435 = 28 507 725` | `2^25` |
| `c0` | `434` | |
| `t1` | `28 507 725 + 434 = 28 508 159` | `2^25` |
| `c1` | `435` | |
| `t2` | `28 507 725 + 16 776 960 + 435 = 45 285 120` | `2^26` |
| `c2` | `690` | |
| `t3` | `28 507 725 + 16 776 960 + 690 = 45 285 375` | `2^26` |

The final assembly interprets the 64-bit result as a signed `Int`. Let
`base = r2*2^32 + r1*2^16 + r0` (below `2^48`) and `top = r3` when
`r3 < 2^15`, otherwise `top = r3 - 2^16`:

```
result = top * 2^48 + base
```

`top * 2^48` lies in `[-2^63, 2^63 - 2^48]` and `base < 2^48`, so the
result is exactly the two's-complement value of the unsigned product in
`[-2^63, 2^63 - 1]`: no intermediate or final overflow.

Limb extraction (`_limb64`) is pure division/modulo; negative residues
are shifted into `[0, 2^16)` before the division, which makes the
extraction exact under both truncating and flooring integer semantics.

The scheme was validated over 50 000 random 64-bit patterns plus the
bounds edges (`0`, `1`, `-1`, `INT64_MIN`, `INT64_MAX`, ±2^47, ±2^48 and
the offset basis) against a BigInteger reference: zero mismatches.

### Per-byte XOR

`_xor_low_byte(state, b)` computes the low octet `state mod 256`
(adjusted to `[0, 256)`), XORs it with `b` in `[0, 255]`, and rebuilds
the state arithmetically:

```
state - low + (low xor b)
```

Because the XOR only ever sees values below 256, no bitwise operator is
applied to a value that can have bit 31 (or 63) set. No `&`, `<<` or
`>>` appears anywhere in the 32/64-bit multiply paths; the only bitwise
operators in the module are this small-octet XOR and the read-side
`(data[i] as Int) & 255` mask.

## API contract

```xi
pub fn fnv_offset_basis32() -> Int
pub fn fnv_prime32() -> Int
pub fn fnv_offset_basis64() -> Int
pub fn fnv_prime64() -> Int

pub fn fnv1_32(data: &Vec[UInt8]) -> Int
pub fn fnv1a_32(data: &Vec[UInt8]) -> Int
pub fn fnv1_64(data: &Vec[UInt8]) -> Int
pub fn fnv1a_64(data: &Vec[UInt8]) -> Int

pub fn fnv1_32_init() -> Int
pub fn fnv1_32_update(state: Int, data: &Vec[UInt8]) -> Int
pub fn fnv1_32_finalize(state: Int) -> Int
pub fn fnv1a_32_init() -> Int
pub fn fnv1a_32_update(state: Int, data: &Vec[UInt8]) -> Int
pub fn fnv1a_32_finalize(state: Int) -> Int
pub fn fnv1_64_init() -> Int
pub fn fnv1_64_update(state: Int, data: &Vec[UInt8]) -> Int
pub fn fnv1_64_finalize(state: Int) -> Int
pub fn fnv1a_64_init() -> Int
pub fn fnv1a_64_update(state: Int, data: &Vec[UInt8]) -> Int
pub fn fnv1a_64_finalize(state: Int) -> Int

pub fn fnv_hex32(value: Int) -> Str
pub fn fnv_hex64(value: Int) -> Str
```

Guarantees:

| Property | Statement |
|---|---|
| Determinism | Equal buffers produce equal results; no hidden state. |
| One-shot == incremental | Both call the same per-variant byte loop. |
| Empty input | Returns the offset basis (`fnv_<v>_init()`). |
| 32-bit range | Results are in `[0, 2^32 - 1]`, non-negative. |
| 64-bit pattern | Results are the signed two's-complement view; `fnv_hex64` gives the unsigned digits. |
| Wrap exactness | Modular products are computed with bounded Int arithmetic only. |
| Totality | No input combination produces an error, panic or trap. |
| Purity | No FFI, no allocation beyond the returned `Str` in the hex helpers, no global state. |

## Error catalog

**None.** This package defines no error type and constructs no
`Result`/`Err` value; there is no `Err(Str)` message to catalog. Every
function is total:

- any `Vec[UInt8]`, including the empty vector and arbitrary high-bit
  bytes, is a valid input;
- any `Int` is a valid state: 32-bit states are reduced modulo `2^32`,
  64-bit states are interpreted as two's-complement patterns;
- `fnv_hex32` and `fnv_hex64` accept any `Int` and render it unsigned
  (`fnv_hex32(-1) == "ffffffff"`,
  `fnv_hex64(-1) == "ffffffffffffffff"`);
- an empty input returns the offset basis by specification, not as a
  failure;
- a digest of 0 is a legitimate hash value (and is pinned by the
  zero-hash vectors), not a sentinel.

Callers who need a distinguishable "invalid" signal must validate their
own inputs before calling; the package deliberately has no contract to
violate.

## Test vectors

### Official FNV reference vectors

These entries are taken verbatim from the official reference tables in
`test_fnv.c` of <https://github.com/lcn2/fnv> (`fnv1_32_vector`,
`fnv1a_32_vector`, `fnv1_64_vector`, `fnv1a_64_vector`; entries 0-11):

| Input | `fnv1_32` | `fnv1a_32` | `fnv1_64` | `fnv1a_64` |
|---|---|---|---|---|
| `""` | `0x811C9DC5` | `0x811C9DC5` | `0xCBF29CE484222325` | `0xCBF29CE484222325` |
| `"a"` | `0x050C5D7E` | `0xE40C292C` | `0xAF63BD4C8601B7BE` | `0xAF63DC4C8601EC8C` |
| `"fo"` | `0x6B772514` | `0x6222E842` | `0x08326207B4EB2F34` | `0x08985907B541D342` |
| `"foo"` | `0x408F5E13` | `0xA9F37ED7` | `0xD8CBC7186BA13533` | `0xDCB27518FED9D577` |
| `"foob"` | `0xB4B1178B` | `0x3F5076EF` | `0x0378817EE2ED65CB` | `0xDD120E790C2512AF` |
| `"fooba"` | `0xFDC80FB0` | `0x39AAA18A` | `0xD329D59B9963F790` | `0xCAC165AFA2FEF40A` |
| `"foobar"` | `0x31F0B262` | `0xBF9CF968` | `0x340D8765A4DDA9C2` | `0x85944171F73967E8` |

The 64-bit columns are shown unsigned; the functions return them as
signed Ints (e.g. `"a"` FNV-1 is `-5808590958014384194` and `"foobar"`
FNV-1a is `-8821353812377114648`).

### Official zero-hash challenge vectors

The shortest published zero-hash solutions from the official FNV page
(each hashes to exactly 0, a strong wrap-arithmetic check):

| Variant | Bytes | Result |
|---|---|---|
| `fnv1_32` | `01 47 6c 10 f3` | `0` |
| `fnv1a_32` | `cc 24 31 c4` | `0` |
| `fnv1_64` | `92 06 77 4c e0 2f 89 2a d2` | `0` |
| `fnv1a_64` | `d5 6b b9 53 42 87 08 36` | `0` |

### Secondary pinned vectors

Computed with three independent BigInteger implementations (Python,
Node.js and .NET via PowerShell) of the published algorithm and pinned in
the suite:

| Input | `fnv1_32` | `fnv1a_32` | `fnv1_64` (unsigned) | `fnv1a_64` (unsigned) |
|---|---|---|---|---|
| `"123456789"` | `0x24148816` | `0xBB86B11C` | `0xA72FFC362BF916D6` | `0x06D5573923C6CDFC` |
| `ff 00 80 7f 01` | `0xC12F8A8C` | `0xB1AD6CD6` | `0x8A68B4A0D4855F2C` | `0x88891DE14B143DD6` |
| 300 bytes, byte `k = k % 256` | `0xA74ACF01` | `0x32B4A3F9` | `0x335CDE9E7DDBB021` | `0x4C68C7903CE32299` |
| 1000 x `0xFF` | `0x72B1826D` | `0xDA53A9FD` | `0xB80952D39A7FB24D` | `0xE5F75FF1E6D4E1DD` |
| `"The quick brown fox jumps over the lazy dog"` | `0xE9C86C6E` | `0x048FFF90` | `0xA8B2F3117DE37ACE` | `0xF3F9B7F5E7E47110` |

The 1000 x `0xFF` vector forces many wraps at both widths, and the
zero-hash vectors pin exact cancellation to 0 modulo `2^32`/`2^64`.

### Hex helper vectors

| Call | Result |
|---|---|
| `fnv_hex32(0)` | `"00000000"` |
| `fnv_hex32(fnv1_32("foobar"))` | `"31f0b262"` |
| `fnv_hex32(fnv1a_32("foobar"))` | `"bf9cf968"` |
| `fnv_hex32(-1)` | `"ffffffff"` |
| `fnv_hex32(4294967301)` | `"00000005"` |
| `fnv_hex64(fnv_offset_basis64())` | `"cbf29ce484222325"` |
| `fnv_hex64(fnv1_64("foobar"))` | `"340d8765a4dda9c2"` |
| `fnv_hex64(fnv1a_64("foobar"))` | `"85944171f73967e8"` |
| `fnv_hex64(-1)` | `"ffffffffffffffff"` |

## Test matrix

`tests/test_conformance.xi` (`module fnv_tests`, 19 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Test dispatch is direct `tN()` calls -- no
`Vec[fn]` table, per the v0.61.3 compiler notes.

| # | Check | Covers |
|---|---|---|
| 1 | constants, primes and init states | specification values; `init() == offset_basis()` |
| 2 | FNV-1 32 official vectors (empty, a, fo, foo, foob, fooba, foobar) | published table |
| 3 | FNV-1a 32 official vectors (same inputs) | published table |
| 4 | FNV-1 64 official vectors (same inputs) | published table + signed view |
| 5 | FNV-1a 64 official vectors (same inputs) | published table + signed view |
| 6 | `"123456789"` all four | secondary cross-check |
| 7 | high-bit bytes `ff 00 80 7f 01` all four | byte widening with bit 7 set |
| 8 | 300-byte pattern `k % 256` all four | long input, byte-boundary desync |
| 9 | 1000 x `0xFF` all four | repeated deep wrapping at both widths |
| 10 | four zero-hash challenge solutions | exact modular cancellation to 0 |
| 11 | long ASCII sentence all four | text input |
| 12 | `fnv1a_32` incremental at every split of `"foobar"` | one-shot == incremental, empty chunk included |
| 13 | `fnv1_64` incremental at every split of `"foobar"` | one-shot == incremental at 64 bits |
| 14 | byte-at-a-time incremental, all four variants | update granularity 1, all algorithms |
| 15 | empty update identity, finalize identity, init == one-shot(empty) | boundary semantics of the incremental API |
| 16 | `fnv_hex32` pinned (incl. `-1`, `2^32 + 5`) | unsigned display, reduction of out-of-range values |
| 17 | `fnv_hex64` pinned (incl. `-1`, offset basis) | unsigned display of the signed pattern |
| 18 | determinism across repeated calls and equal buffers | purity |
| 19 | FNV-1 vs FNV-1a agree on empty, differ on non-empty | variant separation |

Test-fixture notes: `bytes_of` builds `Vec[UInt8]` with
`xiom.string.byte_at`; `chunk` slices a buffer for incremental feeding;
`pattern_300` and `high_bytes` mirror the `xiom.crc` suite. The only Str
comparisons are between `fnv_hex*()` results and string literals (the
`xiom.hello` pattern), so BUG 17 (`==` on a `Str` read from a `Vec`) is
unreachable. Mutable borrows are never taken; buffers are bound to local
`let` names before every `&Vec[UInt8]` call.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.fnv
```

Expected: `namespace-check` OK (1 module, 0 conflicts), 19 `[PASS]`
lines, `xiom.fnv: all tests passed`, and
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Complexity

| Operation | Time | Space |
|---|---|---|
| `fnv_<v>_32(data)` / `_32_update` | O(data.len()) | O(1) |
| `fnv_<v>_64(data)` / `_64_update` | O(data.len()) | O(1) |
| `_mul64` per byte | O(1): 4 limb extractions + 4 column steps, ~40 fixed operations | O(1) |
| `fnv_<v>_init` / `_finalize` | O(1) | O(1) |
| `fnv_hex32` / `fnv_hex64` | O(1): 8 / 16 digit steps plus small Str concatenations | O(1) |

The 64-bit path is deliberately slower than a native unsigned multiply:
the limb split buys provable Int64 bounds under v0.61.3, not speed.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas, `Vec[fn]` dispatch or struct
  types; the module constructs no `Ok`/`Err`.
- No bitwise operator ever sees a large operand. The read-side mask is
  `(data[i] as Int) & 255` (small right operand); the per-byte mixing
  XOR is applied to octets only; the multiply paths use `*`, `+`, `-`,
  `%` and `/` exclusively. This sidesteps the documented high-bit
  bitwise codegen bugs.
- `%` and `/` are used only on non-negative values after a
  negative-residue adjustment in `_limb64`, so the code is correct under
  both truncating and flooring remainder semantics.
- The 64-bit product does not rely on wrapping `*`; it is computed by the
  bounded limb split above, so no overflow behavior of the compiler is
  part of the contract.
- Tests bind every buffer to a typed local (`let d = ...`) and pass
  `&d`, never a struct field or call result, and call `tN()` directly
  rather than indexing a `Vec[fn]`.
- `fnv_hex*` build strings with `xiom.string.str_slice` concatenation.
  The bytes are always printable hex digits, so no NUL can reach the
  string path.
- The package declares no `extern "C"` blocks (no FFI).

## Known limitations

- Non-cryptographic by design; no collision resistance or authenticity.
- Only widths 32 and 64 and only FNV-1/FNV-1a; no FNV-0, no 128/256-bit,
  no xor-folding, no seeded wrapper.
- The incremental API is explicit state Ints; there is no hasher object.
- 64-bit results are signed views; unsigned decimal display requires the
  hex helper or caller-side conversion.
- The 64-bit limb split is slower than a native multiply; it is a
  correctness device for compiler v0.61.3, not an optimization.
- No protection against misuse of arbitrary states beyond the documented
  reduction semantics: `update(12345, data)` is a valid call and simply
  hashes from the state `12345`.

## Verification

Last verified: compiler 0.61.3, via
`& .\scripts\port.ps1 -Package xiom.fnv`:

```
port: PASS (passed=19 failed=0 program_exit=0 exit=0)
```

The harness green covers the official FNV reference vectors, the
zero-hash challenge vectors, the pinned secondary vectors, the
incremental/one-shot equality round-trips and the hex display helpers.
