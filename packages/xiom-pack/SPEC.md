# xiom.pack -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Manifest: `package.xi` (`xiom.pack`, version `0.1.2`).
Module: `src/pack.xi` (`module xiom.pack`).
Depends on `xiom.std` (`xiom.string`; the tests additionally use
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) format-string codec for fixed-width integer fields
over in-memory `Vec[UInt8]` buffers:

- `pack_format` encodes one `Int` per token into a fresh `Vec[UInt8]`;
- `unpack_format` decodes the tokens from a buffer at an explicit offset;
- `pack_size` / `pack_token_size` report encoded widths;
- twelve convenience appenders (`pack_u16_le`/`_be`, `pack_s16_le`/`_be`,
  `pack_u32_le`/`_be`, `pack_s32_le`/`_be`, `pack_u64_le`/`_be`,
  `pack_s64_le`/`_be`) push one masked field onto an existing buffer;
- deterministic `Err("pack: ...")` strings for every rejection path.

## Non-goals

- Floats: XIOM v0.61.3 has no `Int <-> Float64` bitcast
  (`xiom.num.float` is a documented zero-returning stub), so exact IEEE-754
  payloads cannot be produced; no float tokens exist.
- Strings, byte blobs, nested records/tuples, arrays and repeated groups.
- Alignment, padding, host-endian ("native") tokens and dynamic widths.
- Arbitrary-precision or 128-bit integers; the domain is the platform `Int`.
- Streaming over sockets/files; the API works on byte vectors.
- A text representation of packed values (no hex/JSON rendering; use
  `xiom.encoding.hex` on the resulting bytes).

## Format-string grammar

```
fmt     := token? ( space+ token )*  space*
token   := "u8"  | "s8"  | "b8"
         | "u16le" | "u16be" | "s16le" | "s16be"
         | "u32le" | "u32be" | "s32le" | "s32be"
         | "u64le" | "u64be" | "s64le" | "s64be"
space   := 0x20
```

- Tokens are matched case-sensitively and exactly; `U8`, `u16` (no endian
  suffix) and `s8le` are unknown tokens.
- One or more space bytes separate tokens; runs of spaces and leading or
  trailing spaces are skipped. `""` and `"   "` denote zero fields.
- The number of tokens in `fmt` must equal `values.len()` in `pack_format`;
  otherwise the result is `Err("pack: token count mismatch")`.
- `pack_token_size` returns the byte width of a single token (0 when
  unknown). `pack_size(fmt)` is the sum over all tokens, or
  `Err("pack: unknown token '<token>'")` for the first unknown token.

## Token table

| Token | Width | Accepted range | Byte order | Notes |
|---|---|---|---|---|
| `u8` | 1 | `0 .. 255` | -- | |
| `s8` | 1 | `-128 .. 127` | -- | two's complement |
| `b8` | 1 | `0 .. 1` | -- | decodes nonzero as 1 |
| `u16le` | 2 | `0 .. 65535` | little-endian | LSB first |
| `u16be` | 2 | `0 .. 65535` | big-endian | MSB first |
| `s16le` | 2 | `-32768 .. 32767` | little-endian | two's complement |
| `s16be` | 2 | `-32768 .. 32767` | big-endian | two's complement |
| `u32le` | 4 | `0 .. 4294967295` | little-endian | |
| `u32be` | 4 | `0 .. 4294967295` | big-endian | |
| `s32le` | 4 | `-2147483648 .. 2147483647` | little-endian | two's complement |
| `s32be` | 4 | `-2147483648 .. 2147483647` | big-endian | two's complement |
| `u64le` | 8 | any `Int` (bit pattern `0 .. 2^64-1`) | little-endian | see below |
| `u64be` | 8 | any `Int` (bit pattern `0 .. 2^64-1`) | big-endian | see below |
| `s64le` | 8 | `INT64_MIN .. INT64_MAX` | little-endian | two's complement |
| `s64be` | 8 | `INT64_MIN .. INT64_MAX` | big-endian | two's complement |

### Encoding rules

- Unsigned fields write the low 1/2/4/8 bytes of `v`; the range check
  guarantees the value fits, so no bits are lost.
- Signed fields write the low 1/2/4/8 bytes of the two's-complement
  representation of `v`; the range check guarantees the sign extension is
  exact within the width.
- `b8` writes `0x00` for `0` and `0x01` for `1`.
- `u64*` accepts every `Int`: there is no unsigned 64-bit primitive, so a
  value with bit 63 set (including `-1`, the `2^64-1` bit pattern) is
  written as its raw 64-bit two's-complement pattern. `s64*` shares the
  same byte rule; every `Int` is a valid signed 64-bit value.
- Little-endian tokens write the least significant byte first; big-endian
  tokens write the most significant byte first. For 1-byte tokens the
  distinction does not exist, so `u8`/`s8`/`b8` have no `le`/`be` variants.

Examples:

| Field | Value | Bytes |
|---|---|---|
| `u8` | `0x12` | `12` |
| `s8` | `-1` | `ff` |
| `b8` | `1` | `01` |
| `u16le` | `0x1234` | `34 12` |
| `u16be` | `0x1234` | `12 34` |
| `s16le` | `-2` | `fe ff` |
| `s16be` | `-2` | `ff fe` |
| `u32le` | `0xffffffff` | `ff ff ff ff` |
| `s32be` | `-2147483648` | `80 00 00 00` |
| `u64be` | `0x0102030405060708` | `01 02 03 04 05 06 07 08` |
| `u64le` | `-1` (`2^64-1`) | `ff` x8 |
| `s64be` | `INT64_MIN` | `80 00 00 00 00 00 00 00` |

## Decoding rules

`unpack_format(fmt, data, offset)` validates in this order:

1. `offset < 0` -> `Err("pack: negative offset")`.
2. `fmt` parsed via `pack_size`; the first unknown token ->
   `Err("pack: unknown token '<token>'")`.
3. `offset > data.len()` or `data.len() - offset < pack_size(fmt)` ->
   `Err("pack: truncated data")`. (`offset == data.len()` is valid for an
   empty format, yielding `Ok(empty)`.)
4. Fields are read in token order; each read advances the cursor by the
   token width, starting at `offset`.

Value semantics:

- `u8`/`u16*`/`u32*` decode to non-negative `Int`s in the token range.
- `s8`/`s16*`/`s32*` are sign-extended from the width's sign bit.
- `s64*` is the signed 64-bit value.
- `u64*` returns the raw bit pattern: a value with bit 63 set decodes as the
  same negative `Int`, so `ff` x8 decodes as `-1` and
  `80 00 00 00 00 00 00 00` (BE) as `INT64_MIN`.
- `b8` returns `0` for a zero byte and `1` for any nonzero byte.

## API signatures

All functions are free functions in module `xiom.pack`:

```xi
pub fn pack_format(fmt: Str, values: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn unpack_format(fmt: Str, data: &Vec[UInt8], offset: Int) -> Result[Vec[Int], Str]
pub fn pack_size(fmt: Str) -> Result[Int, Str]
pub fn pack_token_size(token: Str) -> Int

pub fn pack_u16_le(out: &mut Vec[UInt8], v: Int)
pub fn pack_u16_be(out: &mut Vec[UInt8], v: Int)
pub fn pack_s16_le(out: &mut Vec[UInt8], v: Int)
pub fn pack_s16_be(out: &mut Vec[UInt8], v: Int)
pub fn pack_u32_le(out: &mut Vec[UInt8], v: Int)
pub fn pack_u32_be(out: &mut Vec[UInt8], v: Int)
pub fn pack_s32_le(out: &mut Vec[UInt8], v: Int)
pub fn pack_s32_be(out: &mut Vec[UInt8], v: Int)
pub fn pack_u64_le(out: &mut Vec[UInt8], v: Int)
pub fn pack_u64_be(out: &mut Vec[UInt8], v: Int)
pub fn pack_s64_le(out: &mut Vec[UInt8], v: Int)
pub fn pack_s64_be(out: &mut Vec[UInt8], v: Int)
```

The appenders append exactly 2/4/8 bytes and are **masked to width**: bits
above the low 2/4/8 bytes are dropped (`pack_u16_le(out, 0x12345)` appends
`45 23`; `pack_u32_le(out, 4294967296)` appends `00 00 00 00`). They never
range-check and never fail.

## Error catalog

| Condition | Error text |
|---|---|
| `values.len() !=` token count in `pack_format` | `pack: token count mismatch` |
| Unknown token in `pack_format`, `pack_size` or `unpack_format` | `pack: unknown token '<token>'` |
| Value outside the token's range in `pack_format` (u8/s8/b8/u16*/s16*/u32*/s32*) | `pack: <token> out of range` |
| `offset < 0` in `unpack_format` | `pack: negative offset` |
| `offset` past `data.len()`, or fewer than `pack_size(fmt)` bytes from `offset` | `pack: truncated data` |

`pack: <token> out of range` uses the exact token text, e.g.
`pack: u8 out of range`, `pack: s16le out of range`. `u64*` and `s64*`
never produce an out-of-range error: every `Int` is a valid 64-bit pattern.

## Complexity

| Operation | Complexity |
|---|---|
| `pack_format` / `unpack_format` | O(tokens) + O(payload bytes) |
| `pack_size` / `pack_token_size` | O(tokens) / O(1) |
| each appender | O(1) |

## Test plan

`tests/test_conformance.xi` (`module pack_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. empty format with empty values packs to an empty vector (`pack_size("")`
   is `Ok(0)`, `unpack_format("", ...)` is `Ok(empty)`);
2. `u8` exact bytes `00`/`12`/`ff` and decode;
3. `s8` pinned at `-1` -> `ff`, `-128` -> `80`, `127` -> `7f`, and
   sign-extended decode;
4. `b8` values `0`/`1`, nonzero decode canonicalisation and range errors;
5. `u16le`/`u16be` exact bytes for `0x1234` (`34 12` / `12 34`) and
   `65535`;
6. `s16le`/`s16be` two's-complement negatives (`-2`, `-32768`, `32767`);
7. `u32le`/`u32be` for `0x12345678` (`78 56 34 12` / `12 34 56 78`);
8. `u32` `0xffffffff` pinned to all-`ff` in both byte orders;
9. `s32le`/`s32be` boundaries `-2^31`, `2^31-1`, `-1`;
10. `u64le`/`u64be` byte reversal for `0x0102030405060708` and `2^63-1`;
11. `u64` max (`2^64-1`) is `ff` x8 and decodes as `Int -1`;
12. `s64le`/`s64be` `INT64_MIN`, `INT64_MAX`, `-1`;
13. per-token range violations are `Err(pack: <token> out of range)`;
14. token-count mismatches are `Err(pack: token count mismatch)`;
15. `pack_size` table and `pack_token_size` widths (incl. unknown -> 0);
16. six-field format round-trip pinned to 18 bytes;
17. offset reads inside a longer stream (prefix and suffix bytes);
18. truncated data and negative offsets are `Err`;
19. unknown tokens (`u9`, `nope`, `U8`, `u16`, `s8le`) are `Err` in
    `pack_format`, `pack_size` and `unpack_format`;
20. unsigned appenders write masked low bytes in order;
21. signed appenders write two's-complement bytes in order;
22. all 19 token spellings in one 15-field format round-trip (59 bytes).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.pack
```

Last verified: compiler 0.64.0,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)` in 11.9 s and 12.3 s
(two consecutive runs with the hardening clauses active).

## Contracts (hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/pack.xi` in the batch #24
hardening pass (compiler v0.64.0; version bump to 0.1.2 by the coordinator):
24 clauses across the 16 public entry points (4 core functions + 12
appenders). `xiom --dump-contracts src/pack.xi` lists all 24, so none was
dropped, and two consecutive
`.\scripts\port.ps1 -Package xiom.pack -TimeoutSec 60` runs ended
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)` with the clauses
active (11.9 s and 12.3 s). The 22-check conformance suite exercises all 16
entry points; none of the clauses trapped under the suite.

`xiom-verify src/pack.xi --check` (Z3 on v0.64.0) result: **0 proven /
2 violated / 37 unknown / 21 errors**, with the verifier's own summary
"z3 rejected the generated SMT (emitter bug) ... This is not a proof
failure of the code under test." The 21 errors are emitter artifacts
(unknown constants `_token_is` / `_split_tokens` / `_ok_int` / `_err_ints`
in the generated SMT); the two `VIOLATED [X7001]` lines for
`pack_token_size` are spurious consequences of the rejected SMT, not
counterexamples (the function only returns the literal widths 0..8 and the
suite pins them). The emitter skips every clause whose `Str`/`Vec` `.len()`
has an unresolved operand sort or whose function body is built from the
call/loop helpers, so all 24 clauses are runtime-checked only on this
toolchain.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `pack_token_size` | `ensures: result >= 0`; `ensures: result <= 8`; `ensures: token.len() == 0 => result == 0` | runtime-checked (body calls `_token_is`; emitter errors) |
| `pack_size` | `ensures: fmt.len() == 0 => result is Ok`; `ensures: result is Err => fmt.len() > 0`; `ensures: result is Ok => result.value >= 0` | runtime-checked (emitter: `Str` length sort unresolved) |
| `pack_format` | `ensures: fmt.len() == 0 && values.len() == 0 => result is Ok`; `ensures: fmt.len() == 0 && values.len() > 0 => result is Err`; `ensures: result is Ok => values.len() <= fmt.len()` | runtime-checked (emitter: `Str` length sort unresolved) |
| `unpack_format` | `ensures: offset < 0 => result is Err`; `ensures: offset > data.len() => result is Err`; `ensures: result is Ok => offset >= 0 && offset <= data.len()` | runtime-checked (emitter: unsupported expression) |
| `pack_u16_le` / `pack_u16_be` / `pack_s16_le` / `pack_s16_be` | `ensures: out.len() == out.len()@pre + 2` | runtime-checked (`@pre` frame through the `&mut Vec[UInt8]` param) |
| `pack_u32_le` / `pack_u32_be` / `pack_s32_le` / `pack_s32_be` | `ensures: out.len() == out.len()@pre + 4` | runtime-checked (`@pre` frame) |
| `pack_u64_le` / `pack_u64_be` / `pack_s64_le` / `pack_s64_be` | `ensures: out.len() == out.len()@pre + 8` | runtime-checked (`@pre` frame) |

The clauses stay inside the proven families: scalar bounds and sentinels,
guard pairs (`x invalid => result is Err` / `Err => x invalid`), an exact
count invariant (`values.len() <= fmt.len()` whenever `pack_format` is Ok),
and the per-appender `@pre` frame counts. No clause uses tuple-component
access, a `Result`-payload length check, struct payload fields, `Str`
equality, or indexing; no clause calls the function it guards or a
transitive callee, so there is no postcondition call-cycle. The first two
clauses of `pack_format` are the empty-format guard pair; its third clause
refines the token-count rule (token count == `values.len()`, tokens are
separated by at least one non-token byte, so the count never exceeds the
byte length of `fmt`).

## Known limitations

- Integers only: no floats/strings/bytes/nested values, no alignment or
  padding, no dynamic widths.
- `u64` values are the platform `Int` bit pattern; `2^64-1` is `-1` and
  decoding bit-63 values yields negative `Int`s.
- `b8` decodes any nonzero byte as `1` (lenient canonicalisation).
- The appenders mask silently (no `Result`, no range check).
- `fmt` is parsed on every call (no cached/compiled format object).
- Plain value functions; no thread-safety concerns beyond the underlying
  `Vec` ownership model.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_int` /
  `_err_int` / `_ok_ints` / `_err_ints` / `_ok_bytes` / `_err_bytes`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- Raw bytes widen through `(x as Int) & 0xFF` before use; `& 0xFF` on
  operands with bit 31 set miscompiles, so byte extraction is arithmetic
  (modulo/division with a negative-remainder correction).
- No `<<` shift is used. Decoding an 8-byte field accumulates the low seven
  bytes with a `place` factor (max `2^56-1`) and applies the top byte as an
  explicit `+2^56` term, folding bit 63 into `INT64_MIN`, so no intermediate
  exceeds `INT64_MAX`.
- Str comparisons go through `string.str_compare`; `==` on `Str` values read
  from a `Vec[Str]` lowers to a pointer comparison (BUG 17). Tests import
  `xiom.string.compare` and route every equality through `str_compare`.
- Free functions only: no methods, no lambdas, no `Vec[StructType]`.
