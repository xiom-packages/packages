# xiom.adler32 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.adler32`, version `0.1.0`).
Module: `src/adler32.xi` (`module xiom.adler32`).
Depends on `xiom.std`; the library module imports `xiom.string` (for the hex
display helper); the tests import `xiom.test`, `xiom.io`, `xiom.string` and
`xiom.string.compare`.

## Scope

A pure-XIOM (no FFI), Int-only implementation of Adler-32 (RFC 1950,
section 9) over fully materialized `Vec[UInt8]` buffers:

- one-shot `adler32`;
- incremental triple `adler32_init/update/finalize` over a single packed
  `Int` state;
- strict `adler32_update_checked` / `adler32_finalize_checked` plus the
  total predicate `adler32_state_valid` (the whole error catalog);
- unsigned display helper `adler32_hex` (8 digits).

## Non-goals

- **zlib/gzip containers, deflate and PNG internals.** Only the checksum
  value is computed; no stream parsing, framing or compression.
- **Other checksums** (CRC, Fletcher, FNV, Murmur) and cryptographic hashes.
- **Cryptographic claims of any kind.** Adler-32 is an error-detection code:
  not collision-resistant, not a MAC, trivially forgeable.
- **Block, table, slicing-by-N, SIMD or CLMUL variants.** The recurrence is
  computed byte-by-byte; there are no lookup tables or block forms.
- **Streaming objects, structs, methods or callbacks.** The incremental
  state is an explicit packed `Int`; the module exports no `pub type`.
- **BigInt, FFI or dependencies beyond `xiom.std`.**

## Algorithm

Adler-32 keeps two running sums over the input octets, modulo 65521 (the
largest prime below 2^16), initialized to `s1 = 1` and `s2 = 0`. For an
input `d[0..n-1]`:

```
s1 = 1
s2 = 0
for each byte b = d[i] in order:
  s1 = (s1 + b) mod 65521
  s2 = (s2 + s1) mod 65521
checksum = s2 * 65536 + s1
```

The checksum packs `s1` in the low 16 bits and `s2` in the high 16 bits (the
zlib `(s2 << 16) | s1` fold). The empty input yields `1`; every canonical
value is an `Int` in `[0, 4293984240]` (`0x00000000..0xFFF0FFF0`).

### Reduction cadence (pinned, deferred)

The accumulator is reduced modulo 65521 after **every 5552 input bytes**
(the classic zlib `NMAX`) inside an update call, and again at the end of
every `update` call and at `finalize`. This is a documented choice, not an
implementation detail:

- it is the standard Adler-32 block size, chosen so the deferred sums stay
  below 2^32: with byte values in `[0, 255]` and residues in `[0, 65520]`
  the largest values reached inside one block are

  ```
  s1 <= 65520 + 5552 * 255                           = 1481280
  s2 <= 65520 + 65520 * 5552 + 255 * 5552 * 5553 / 2 = 4294690200
  ```

  and `4294690200 < 2^32` (by 277096);
- it is **exactly equivalent** to reducing after every byte: addition is
  congruent modulo 65521, so `(s1 mod m) + b = s1 + b (mod m)` and
  `(s2 mod m) + (s1 mod m) = s2 + s1 (mod m)`;
- in XIOM the sums are 64-bit `Int` values, so even the fully deferred form
  is exact; the 5552 cadence is kept because it is the canonical Adler-32
  bound and keeps every intermediate below 2^32.

The conformance suite proves the equivalence on inputs **longer than 5552
bytes** (5553- and 6000-byte ramps and `0xFF` runs) against a test-local
per-byte reference, and against a fully deferred reference that applies no
`%` until the end. Reduction boundaries are not observable in results: they
depend on call boundaries only, never on the values produced.

### Byte handling

Every input byte is read from a `Vec[UInt8]` and widened with
`(b as Int) & 255` before entering the sums, so bytes with bit 7 set
(`0x80..0xFF`) enter as `128..255`; no raw `UInt8` is compared against a
constant `>= 128` anywhere. The input may have any length, including zero.

### Canonical state and canonicalization

A canonical state is a packed checksum value whose components are canonical
residues. The unchecked incremental functions accept any `Int` state and
canonicalize it deterministically:

1. take the low 32 bits (`state mod 2^32`);
2. split into `s1 = low word` and `s2 = high word`;
3. reduce each component modulo 65521.

`adler32_init` returns the canonical empty state `1`; `adler32_update`
returns a canonical state; `adler32_finalize` is the identity on canonical
states and the same canonicalization otherwise, so
`finalize(update(init, data)) == update(init, data) == adler32(data)`.

Examples pinned by the tests:

| Raw state | Canonical state |
|---|---|
| `-1`, `4294967295` | `917518` (`0x000E000E`) |
| `65521` | `0` |
| `65535` | `14` (`0x0000000E`) |
| `65536` | `65536` (`0x00010000`) |
| `4294901760` (`0xFFFF0000`) | `917504` (`0x000E0000`) |
| `4294901761` (`0xFFFF0001`) | `917505` (`0x000E0001`) |
| `4293984240` (`0xFFF0FFF0`, maximum) | `4293984240` |
| `4293984241` (`0xFFF0FFF1`) | `4293918720` (`0xFFF00000`) |
| `4294967296` (`2^32`) | `0` |

## API contract

```xi
pub fn adler32_init() -> Int
pub fn adler32(data: &Vec[UInt8]) -> Int
pub fn adler32_update(state: Int, data: &Vec[UInt8]) -> Int
pub fn adler32_finalize(state: Int) -> Int
pub fn adler32_state_valid(state: Int) -> Bool
pub fn adler32_update_checked(state: Int, data: &Vec[UInt8]) -> Result[Int, Str]
pub fn adler32_finalize_checked(state: Int) -> Result[Int, Str]
pub fn adler32_hex(value: Int) -> Str
```

### Semantics

- `adler32(data)` -- one-shot checksum in `[0, 4293984240]`; empty input
  is `1`.
- `adler32_init()` -- `1`, the empty state (s1 = 1, s2 = 0).
- `adler32_update(state, data)` -- `adler32` of the concatenated stream
  starting from the canonicalization of `state`; total, never fails.
- `adler32_finalize(state)` -- canonical checksum of `state`; the identity
  on canonical states; total, never fails.
- `adler32_state_valid(state)` -- true iff `0 <= state <= 4293984240` and
  the low word `state % 65536 <= 65520` (range and low word together also
  bound the high word: `s2 <= 65520`). A `Bool`; total, never fails.
- `adler32_update_checked(state, data)` -- `Ok(update(state, data))` when
  `state_valid(state)`, else `Err("adler32: invalid state")`; `data` is not
  read in the error case.
- `adler32_finalize_checked(state)` -- `Ok(finalize(state))` when
  `state_valid(state)`, else `Err("adler32: invalid state")`.
- `adler32_hex(value)` -- exactly 8 lowercase hex digits of the low 32 bits
  of `value`, unsigned (`-1` renders `"ffffffff"`, `2^32` renders
  `"00000000"`).

### Error catalog

Exactly one message exists:

| Message | Returned by | Condition |
|---|---|---|
| `adler32: invalid state` | `adler32_update_checked`, `adler32_finalize_checked` | the state is not canonical |

Every other function is total: the one-shot function, `init`, the unchecked
`update`/`finalize`, the state predicate and the hex helper cannot fail. The
message is deterministic and identical across both rejection paths; the
tests pin it with `compare.str_compare` (never `==` on `Str`).

## Test vectors

All values were computed with **independent** reference implementations
(Python's `zlib.adler32` -- the original C implementation -- plus a per-byte
and a fully deferred pure-Python implementation, agreeing on every entry) and
then pinned.

| Input | Length | Adler-32 | Hex |
|---|---|---|---|
| `""` (empty) | 0 | `1` | `0x00000001` |
| `"a"` | 1 | `6422626` | `0x00620062` |
| `"abc"` | 3 | `38600999` | `0x024D0127` |
| `"Wikipedia"` | 9 | `300286872` | `0x11E60398` |
| `"abcdef"` | 6 | `136184406` | `0x081E0256` |
| `"123456789"` | 9 | `152961502` | `0x091E01DE` |
| `"Hello, world!"` | 13 | `543032458` | `0x205E048A` |
| `"abd"` | 3 | `38666536` | `0x024E0128` |
| `ff 00 80 7f 01` | 5 | `125764096` | `0x077F0200` |
| `1000 x 0xFF` | 1000 | `3874088006` | `0xE6E9E446` |
| ramp, byte `k` = `k % 256` | 300 | `3503981363` | `0xD0DA8333` |
| ramp, byte `k` = `k % 256` | 1000 | `486795068` | `0x1D03E73C` |
| ramp, byte `k` = `k % 256` | 5552 | `2043458111` | `0x79CCB23F` |
| ramp, byte `k` = `k % 256` | 5553 | `751481583` | `0x2CCAB2EF` |
| ramp, byte `k` = `k % 256` | 6000 | `1525910894` | `0x5AF38D6E` |
| `5552 x 0xFF` | 5552 | `4052720524` | `0xF18F9B8C` |
| `5553 x 0xFF` | 5553 | `2385091723` | `0x8E299C8B` |
| `6000 x 0xFF` | 6000 | `2761382378` | `0xA49759EA` |
| `6000 x 0x00` | 6000 | `393216001` | `0x17700001` |

The 5552-byte fixtures sit exactly on the pinned cadence boundary; the
5553- and 6000-byte fixtures cross it, which is the required proof case
(`> 5552` bytes). The `6000 x 0x00` vector has `s1 = 1` and `s2 = 6000`,
so its checksum is `6000 * 65536 + 1` -- an easy hand check.

Prefix vectors for `"abcdefgh"` (all 9 prefixes, pinned by test `t8`):

| Prefix length | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| Adler-32 | `1` | `6422626` | `19267780` | `38600999` | `64487819` | `96993776` | `136184406` | `182125245` | `234881829` |

## Complexity

| Operation | Complexity |
|---|---|
| `adler32` | O(data.len()) time, O(1) space |
| `adler32_init` | O(1) |
| `adler32_update` | O(data.len()) time, O(1) space |
| `adler32_finalize` | O(1) |
| `adler32_state_valid` | O(1) |
| `adler32_update_checked` / `_finalize_checked` | same as their unchecked counterparts |
| `adler32_hex` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module adler32_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. `t1` init state `1`; one-shot/update/finalize of empty input `1`;
2. `t2` canonical vectors: empty, `"a"`, `"abc"`, `"Wikipedia"`;
3. `t3` `"abcdef"`, `"123456789"`, `"Hello, world!"` pinned;
4. `t4` high-bit bytes `ff 00 80 7f 01` pinned (masked widening);
5. `t5` `1000 x 0xFF` pinned;
6. `t6` 6000-byte ramp and 6000 zero bytes pinned (the required wrap case);
7. `t7` NMAX boundary pinned: ramps of 5552/5553/6000 bytes and `0xFF`
   runs of 5552/5553/6000 bytes;
8. `t8` all 9 prefixes of `"abcdefgh"` pinned;
9. `t9` incremental == one-shot at every split of `"abcdefgh"`;
10. `t10` incremental == one-shot at every split of `"abcdef"`;
11. `t11` byte-at-a-time streaming over the 6000-byte ramp (crosses NMAX);
12. `t12` chunk sizes 1..7 over a 43-byte message and 5551/5552/5553 over
    the 6000-byte ramp;
13. `t13` update results are canonical (`s1`/`s2` bounds, `state_valid`,
    finalize identity) and pinned;
14. `t14` `state_valid` boundaries: `0`, `1`, `65520`, `65536`, `917518`,
    `4293918720`, `4293984240` accepted; `65521`, `65535`, `4293984241`,
    `4294901759`, `4294901760`, `4294967295`, `4294967296`, `-1` rejected;
15. `t15` unchecked canonicalization of raw states (`-1`, `65521`, `65535`,
    `65536`, `4294901760`, `4294901761`, `4293984240`, `4293984241`,
    `2^32`) and the `+ 2^32` invariance;
16. `t16` checked update: `Ok` equals the unchecked result for canonical
    states; pinned `Err` for `65521`, `-1`, `4293984241`, `2^32`;
17. `t17` checked finalize: identity `Ok` on canonical states; pinned `Err`
    otherwise;
18. `t18` hex helper: fixed width, lowercase, unsigned reduction (`-1`,
    `2^32`, computed checksums);
19. `t19` test-local per-byte and fully deferred references agree with the
    module on every pinned buffer, including all `> 5552`-byte inputs (the
    cadence proof obligation);
20. `t20` determinism, separation of different buffers, empty update
    identity;
21. `t21` one-shot == `finalize(update(init, data))`; 5552-byte chunked
    stream over the 6000-byte ramp round-trips;
22. `t22` the single error message is deterministic across repeated calls
    and both rejection paths.

Test-fixture notes: `bytes_of` builds `Vec[UInt8]` with
`xiom.string.byte_at`; `chunk` copies a fresh byte range for each streaming
step (never a borrowed field); `ramp` builds byte `k` = `k % 256`;
`high_bytes` pushes `255, 0, 128, 127, 1`; `repeat_byte` builds runs;
`ref_bytewise`/`ref_deferred` are the independent test-local references. Err
strings are compared with `xiom.string.compare.str_compare`; no `Str` is
ever read out of a `Vec` and no `Str ==` is used, so BUG 17 is unreachable.
Test dispatch is direct `tN()` calls, not a `Vec[fn]` table.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.adler32
```

Expected: `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

Last verified: compiler 0.61.3, twice in a row,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No zlib/gzip container parsing or writing, no deflate, no PNG chunk I/O;
  only the checksum value.
- No other checksums and no cryptographic hashes.
- No block/table/slicing/SIMD variants; the byte-wise recurrence only.
- Not a cryptographic hash and not an authenticity mechanism.
- The input must be a materialized `Vec[UInt8]`; the incremental interface
  is a packed `Int` state, not a buffering hasher object.
- Unchecked `update`/`finalize` canonicalize silently rather than
  diagnosing; callers who need strictness must use the `*_checked` variants
  or `state_valid`.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas, `Vec[fn]` dispatch, struct
  types or `Vec[StructType]`.
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_int`/`_err_int`,
  never inside a larger function.
- Bytes read from `Vec[UInt8]` are always widened with `(b as Int) & 255`;
  constants `>= 128` are never compared against a raw `UInt8`.
- All reductions are `%` on non-negative values below `2^32`; no `&`, `<<`
  or `>>` ever sees a high bit, so the high-bit bitwise codegen hazards are
  unreachable.
- The module never compares `Str` values and builds `Str` only from
  lowercase hex digits, so the string-builder NUL trap is unreachable.
- No mutable borrows (`&mut`) are used; the incremental state is passed and
  returned by value.
- The package declares no `extern "C"` blocks (no FFI).

## References

- RFC 1950 (ZLIB Compressed Data Format Specification), section 9: Adler-32.
- zlib `adler32.c`, the reference implementation this package's vectors were
  cross-checked against.
