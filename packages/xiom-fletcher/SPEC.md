# xiom.fletcher -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.fletcher`, version `0.1.0`).
Module: `src/fletcher.xi` (`module xiom.fletcher`).
Depends on `xiom.std`; the library module imports `xiom.string` (for the
hex display helpers); the tests import `xiom.test`, `xiom.io`,
`xiom.string` and `xiom.string.compare`.

## Scope

A pure-XIOM (no FFI), Int-only implementation of Fletcher's checksum in the
classic ones'-complement form over fully materialized `Vec[UInt8]` buffers:

- **Fletcher-16**: `sum1`/`sum2` modulo 255;
- **Fletcher-32**: `sum1`/`sum2` modulo 65535;
- one-shot functions `fletcher16` / `fletcher32`;
- incremental triples `fletcher16_init/update/finalize` and
  `fletcher32_init/update/finalize` over a single packed `Int` state;
- strict `fletcher16_update_checked` / `fletcher16_finalize_checked` and the
  32-bit pair, plus the total predicates `fletcher16_state_valid` /
  `fletcher32_state_valid` (the whole error catalog);
- unsigned display helpers `fletcher16_hex` (4 digits) and `fletcher32_hex`
  (8 digits).

## Non-goals

- **Adler-32.** It is a different checksum (modulus 65521, initial value 1,
  a different output fold). It belongs to its own package family and is not
  implemented, wrapped or emulated here.
- **Fletcher-64** (64-bit sums, modulus 2^32 - 1) and any other width;
  only exactly the 16-bit and 32-bit variants above exist.
- **Block, table, slicing-by-N, SIMD or CLMUL variants.** The recurrence is
  computed byte-by-byte; there are no lookup tables or block forms.
- **Cryptographic claims of any kind.** Fletcher's checksum is an
  error-detection code: not collision-resistant, not a MAC, trivially
  forgeable against an adversary.
- **Streaming objects, structs, methods or callbacks.** The incremental
  state is an explicit packed `Int`; the module exports no `pub type`.
- **BigInt, FFI or dependencies beyond `xiom.std`.**

## Algorithm

Fletcher's checksum keeps two running sums over the input octets, the
second one weighted by position (each byte contributes to `sum2` once per
later byte). For an input `d[0..n-1]`:

```
sum1 = 0
sum2 = 0
for each byte b = d[i] in order:
  sum1 = (sum1 + b) mod m
  sum2 = (sum2 + sum1) mod m
checksum = sum2 * radix + sum1
```

with the classic ones'-complement parameters:

| Variant | Modulus `m` | Radix | Canonical `sum1`,`sum2` | Checksum range | Empty input |
|---|---|---|---|---|---|
| Fletcher-16 | `255` (2^8 - 1) | `256` | `[0, 254]` | `[0, 65278]` (`0x0000..0xFEFE`) | `0` |
| Fletcher-32 | `65535` (2^16 - 1) | `65536` | `[0, 65534]` | `[0, 4294901758]` (`0x00000000..0xFFFEFFFE`) | `0` |

### Reduction cadence (pinned)

Both sums are reduced **after every byte**, exactly as written above. This
is a documented choice, not an implementation detail:

- it is equivalent to the classic deferred form: addition is congruent
  modulo `m`, so reducing once at the end reaches the same canonical
  residues;
- it keeps the pre-reduction values tiny -- at most `254 + 255 = 509` and
  `254 + 254 = 508` for Fletcher-16, `65534 + 255 = 65789` and
  `65534 + 65534 = 131068` for Fletcher-32 -- so every step is exact `Int`
  arithmetic;
- no shift, bitwise AND or masking is ever needed, which keeps the module
  clear of the v0.61.3 high-bit bitwise codegen hazards.

A deferred implementation that folds the two accumulators only at the end
produces the same canonical checksum; the conformance suite proves this by
comparing against a test-local deferred reference (`ref16`/`ref32`).

### Output order (pinned)

The checksum is the packed integer

```
Fletcher-16: sum2 * 256   + sum1      (sum1 in the low byte)
Fletcher-32: sum2 * 65536 + sum1      (sum1 in the low word)
```

This is the common convention (`(sum2 << 8) | sum1`, `(sum2 << 16) | sum1`
in the customary unsigned encodings) and it is the only output order this
package produces or accepts: the incremental state is packed the same way.

Consequences of the canonical residues: no Fletcher-16 checksum has its low
byte equal to `0xFF` and no Fletcher-32 checksum has its low word equal to
`0xFFFF`; e.g. `"abc"` is `0x4C27` / `0x024A0126`, never `0xC827` /
`0x024AFFFF`.

### Byte handling

Every input byte is read from a `Vec[UInt8]` and widened with
`(b as Int) & 255` before entering the sums, so bytes with bit 7 set
(`0x80..0xFF`) enter as `128..255`; no raw `UInt8` is compared against a
constant `>= 128` anywhere. The input may have any length, including zero.

### Canonical state and canonicalization

A canonical state is a packed checksum value whose components are canonical
residues. The unchecked incremental functions accept any `Int` state and
canonicalize it deterministically:

1. take the low `radix` bits (`state mod 2^16`, resp. `state mod 2^32`);
2. split into `sum1 = low component` and `sum2 = high component`;
3. reduce each component modulo `m` (255 resp. 65535).

`fletcherN_init` returns the canonical empty state `0`;
`fletcherN_update` returns a canonical state; `fletcherN_finalize` is the
identity on canonical states and the same canonicalization otherwise, so
`finalize(update(init, data)) == update(init, data) == fletcherN(data)`.

Examples pinned by the tests:

| Variant | Raw state | Canonical state |
|---|---|---|
| 16 | `-1`, `255`, `65535` | `0` |
| 16 | `511` | `256` |
| 16 | `4294901761` (`0xFFFF0001`) | `1` |
| 16 | `65278` (`0xFEFE`, maximum) | `65278` |
| 32 | `-1`, `4294967295` | `0` |
| 32 | `65535` | `0` |
| 32 | `131071` (`0x0001FFFF`) | `65536` (`0x00010000`) |
| 32 | `4294901759` (`0xFFFEFFFF`) | `4294836224` (`0xFFFE0000`) |
| 32 | `4294901758` (`0xFFFEFFFE`, maximum) | `4294901758` |

## API contract

```xi
pub fn fletcher16_init() -> Int
pub fn fletcher16(data: &Vec[UInt8]) -> Int
pub fn fletcher16_update(state: Int, data: &Vec[UInt8]) -> Int
pub fn fletcher16_finalize(state: Int) -> Int
pub fn fletcher16_state_valid(state: Int) -> Bool
pub fn fletcher16_update_checked(state: Int, data: &Vec[UInt8]) -> Result[Int, Str]
pub fn fletcher16_finalize_checked(state: Int) -> Result[Int, Str]
pub fn fletcher16_hex(value: Int) -> Str

pub fn fletcher32_init() -> Int
pub fn fletcher32(data: &Vec[UInt8]) -> Int
pub fn fletcher32_update(state: Int, data: &Vec[UInt8]) -> Int
pub fn fletcher32_finalize(state: Int) -> Int
pub fn fletcher32_state_valid(state: Int) -> Bool
pub fn fletcher32_update_checked(state: Int, data: &Vec[UInt8]) -> Result[Int, Str]
pub fn fletcher32_finalize_checked(state: Int) -> Result[Int, Str]
pub fn fletcher32_hex(value: Int) -> Str
```

### Semantics

- `fletcherN(data)` -- one-shot checksum in `[0, max]`; empty input `0`.
- `fletcherN_init()` -- `0`, the empty state.
- `fletcherN_update(state, data)` -- `fletcherN` of the concatenated stream
  starting from the canonicalization of `state`; total, never fails.
- `fletcherN_finalize(state)` -- canonical checksum of `state`; the
  identity on canonical states; total, never fails.
- `fletcherN_state_valid(state)` -- true iff `0 <= state <= max` and the
  low component `state % radix <= m - 1` (i.e. `sum1 <= 254` for 16-bit,
  `sum1 <= 65534` for 32-bit, which together with the range bound also
  covers `sum2`). A `Bool`; total, never fails.
- `fletcherN_update_checked(state, data)` -- `Ok(update(state, data))` when
  `state_valid(state)`, else `Err("fletcher: invalid state")`; `data` is
  not read in the error case.
- `fletcherN_finalize_checked(state)` -- `Ok(finalize(state))` when
  `state_valid(state)`, else `Err("fletcher: invalid state")`.
- `fletcherN_hex(value)` -- exactly 4 (resp. 8) lowercase hex digits of the
  low 16 (resp. 32) bits of `value`, unsigned (`-1` renders `"ffff"` /
  `"ffffffff"`, `65536` renders `"0000"`).

### Error catalog

Exactly one message exists:

| Message | Returned by | Condition |
|---|---|---|
| `fletcher: invalid state` | `fletcher16_update_checked`, `fletcher16_finalize_checked`, `fletcher32_update_checked`, `fletcher32_finalize_checked` | the state is not canonical |

Every other function is total: the one-shot functions, `init`, the unchecked
`update`/`finalize`, the state predicates and the hex helpers cannot fail.
The message is deterministic and identical across both widths and all four
rejection paths; the tests pin it with `compare.str_compare` (never `==` on
`Str`).

## Test vectors

All values were computed with **independent** reference implementations of
the algorithm (two Python implementations -- per-byte reduction and fully
deferred reduction -- agreeing on every entry) and then pinned. `sum1` is
the low component of each checksum.

| Input | Length | Fletcher-16 | Hex | Fletcher-32 | Hex |
|---|---|---|---|---|---|
| `""` (empty) | 0 | `0` | `0x0000` | `0` | `0x00000000` |
| `"a"` | 1 | `24929` | `0x6161` | `6357089` | `0x00610061` |
| `"abc"` | 3 | `19495` | `0x4C27` | `38404390` | `0x024A0126` |
| `"abcdef"` | 6 | `8279` | `0x2057` | `135791189` | `0x08180255` |
| `"abcdefgh"` | 8 | `1575` | `0x0627` | `234357540` | `0x0DF80324` |
| `"123456789"` | 9 | `7902` | `0x1EDE` | `152371677` | `0x091501DD` |
| `"Hello, world!"` | 13 | `29069` | `0x718D` | `542180489` | `0x20510489` |
| `ff 00 80 7f 01` | 5 | `33025` | `0x8101` | `125436415` | `0x077A01FF` |
| ramp, byte `k` = `k % 256` | 300 | `64181` | `0xFAB5` | `3425600306` | `0xCC2E8332` |
| ramp, byte `k` = `k % 256` | 1000 | `25877` | `0x6515` | `3900499757` | `0xE87CE72D` |
| `1000 x 0xFF` | 1000 | `0` | `0x0000` | `2022171675` | `0x7887E41B` |

The 300-byte ramp is the required `>= 255`-byte wrap case: its `sum1`
crosses the 255 modulus many times (300 bytes of average value ~127 sum to
well over 255). The 1000-byte ramp and `1000 x 0xFF` cross the 65535
modulus of Fletcher-32 several times. `1000 x 0xFF` is also a boundary
case for Fletcher-16: `255` is `0 mod 255`, so the checksum is exactly `0`.

Prefix vectors for `"abcdefgh"` (all 9 prefixes, pinned by test `t8`):

| Prefix length | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|---|
| Fletcher-16 | `0` | `24929` | `9667` | `19495` | `55179` | `51440` | `8279` | `57022` | `1575` |
| Fletcher-32 | `0` | `6357089` | `19136707` | `38404390` | `64225674` | `96666095` | `135791189` | `181666492` | `234357540` |

## Complexity

| Operation | Complexity |
|---|---|
| `fletcherN` | O(data.len()) time, O(1) space |
| `fletcherN_init` | O(1) |
| `fletcherN_update` | O(data.len()) time, O(1) space |
| `fletcherN_finalize` | O(1) |
| `fletcherN_state_valid` | O(1) |
| `fletcherN_update_checked` / `_finalize_checked` | same as their unchecked counterparts |
| `fletcherN_hex` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module fletcher_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. `t1` init state `0`; one-shot/update/finalize of empty input `0`, both widths;
2. `t2` Fletcher-16 canonical vectors: empty, `"a"`, `"abc"`, `"abcdef"`, `"abcdefgh"`;
3. `t3` Fletcher-32 canonical vectors: same five inputs;
4. `t4` `"123456789"` and `"Hello, world!"` pinned for both widths;
5. `t5` high-bit bytes `ff 00 80 7f 01` pinned for both widths (masked widening);
6. `t6` 300-byte ramp pinned for both widths (the `>= 255`-byte wrap case);
7. `t7` 1000-byte ramp and `1000 x 0xFF` pinned for both widths (deep wrap; `255 == 0 mod 255`);
8. `t8` all 9 prefixes of `"abcdefgh"` pinned for both widths;
9. `t9` incremental == one-shot at every split of `"abcdefgh"`, both widths;
10. `t10` incremental == one-shot at every split of `"abcdef"`, both widths;
11. `t11` byte-at-a-time streaming over the 300-byte ramp, both widths;
12. `t12` chunk sizes 1..7 over a 43-byte message, both widths;
13. `t13` update results are canonical (`sum1`/`sum2` bounds, `state_valid`, finalize identity) and pinned;
14. `t14` `state_valid` boundaries: `0`, `254`, `65278` / `0`, `65534`, `4294901758` accepted; `255`, `511`, `65279`, `65280`, `65535`, `-1` and the 32-bit wrap values rejected;
15. `t15` unchecked canonicalization of raw states (`-1`, `255`, `65535`, `511`, `4294901761`, `65278`, `4294901759`, `131071`, `65536`-equivalents) and the `+ radix` invariance;
16. `t16` checked update: `Ok` equals the unchecked result for canonical states; pinned `Err` for `255`, `-1`, `65280` / `65535`, `2^32`;
17. `t17` checked finalize: identity `Ok` on canonical states; pinned `Err` otherwise, both widths;
18. `t18` hex helpers: fixed width, lowercase, unsigned reduction (`-1`, `65536`, `2^32`, computed checksums);
19. `t19` test-local deferred-reduction reference agrees with the module on every pinned buffer, both widths;
20. `t20` determinism, separation of different buffers, empty update identity;
21. `t21` one-shot == `finalize(update(init, data))`; 7-byte chunked stream round-trip over the 300-byte ramp;
22. `t22` the single error message is deterministic across repeated calls and all four rejection paths.

Test-fixture notes: `bytes_of` builds `Vec[UInt8]` with
`xiom.string.byte_at`; `chunk` copies a fresh byte range for each streaming
step (never a borrowed field); `ramp` builds byte `k` = `k % 256`;
`high_bytes` pushes `255, 0, 128, 127, 1`; `ref16`/`ref32` are the
independent deferred references. Err strings are compared with
`xiom.string.compare.str_compare`; no `Str` is ever read out of a `Vec` and
no `Str ==` is used, so BUG 17 is unreachable. Test dispatch is direct
`tN()` calls, not a `Vec[fn]` table.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.fletcher
```

Expected: `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No Fletcher-64 and no non-standard widths.
- No Adler-32 (documented separate package family).
- No block/table/slicing/SIMD variants; the byte-wise recurrence only.
- Not a cryptographic hash and not an authenticity mechanism.
- The input must be a materialized `Vec[UInt8]`; the incremental interface
  is a packed `Int` state, not a buffering hasher object.
- Unchecked `update`/`finalize` canonicalize silently rather than
  diagnosing; callers who need strictness must use the `*_checked`
  variants or `state_valid`.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas, `Vec[fn]` dispatch, struct
  types or `Vec[StructType]`.
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_int`/`_err_int`,
  never inside a larger function.
- Bytes read from `Vec[UInt8]` are always widened with `(b as Int) & 255`;
  constants `>= 128` are never compared against a raw `UInt8`.
- All reductions are `%` on non-negative values below `2^17`; no `&`, `<<`
  or `>>` ever sees a high bit, so the high-bit bitwise codegen hazards are
  unreachable.
- The module never compares `Str` values and builds `Str` only from
  lowercase hex digits, so the string-builder NUL trap is unreachable.
- No mutable borrows (`&mut`) are used; the incremental state is passed and
  returned by value.
- The package declares no `extern "C"` blocks (no FFI).
