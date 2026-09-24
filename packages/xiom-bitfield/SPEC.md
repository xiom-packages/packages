# xiom.bitfield -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.bitfield`, version `0.1.0`).
Module: `src/bitfield.xi` (`module xiom.bitfield`).
Depends on `xiom.std` only (platform dependency; the module itself imports
nothing).

## Scope

Pure-XIOM (no FFI) word-level bit helpers over the signed 64-bit `Int`:

- mask construction;
- bit-field extraction, replacement, clearing and single-bit toggling;
- population count and leading/trailing zero counts;
- bit reversal; 16-bit and 32-bit byte swaps;
- left/right rotation of a low `width`-bit field.

## Non-goals

- Bulk/dynamic bit vectors (`xiom.bits.bitarray` covers that) and
  arbitrary-precision integers.
- Sign extension (`xiom.bits.bitfield.bitfield_sign_extend` covers that);
  every extract here is unsigned.
- Clamping semantics: invalid fields are rejected, not truncated (see
  Field rules).
- Floating point or bitcasting: there is no i64<->f64 intrinsic.

## Bit model

- Every `value` is a 64-bit two's-complement pattern stored in the signed
  platform `Int`. Bit 0 is the least significant bit; bit 63 is the sign
  bit. Bit `k` of a negative value therefore reads as the sign-extension
  behaviour of two's complement (e.g. `bit_get(-1, 63, 1) == 1`).
- `INT64_MIN` is never written as `-2^63` anywhere in the module or the
  tests; it is constructed as `0 - 9223372036854775807 - 1`, so no
  intermediate overflows.
- Helpers that return a field of at most 63 bits return a non-negative
  `Int`. Helpers that return a full 64-bit pattern can return a negative
  `Int`; this is documented per function.
- No `&`, `|`, `^`, `~` or shift operators are used. Extraction is
  arithmetic (`_floor_div2` forces an exact non-negative remainder before
  dividing), `_pow2(k)` is built by doubling, and bit 63 is produced from
  the `INT64_MIN` literal. This sidesteps the v0.61.3 codegen defect where
  bitwise AND on operands with bit 31 set yields wrong bits (documented in
  `xiom.convert.base58` and `xiom.bits.bitwise`).

## Masking and field rules

`bit_mask(width)`:

| `width` | Result |
|---|---|
| `<= 0` | `0` |
| `1..63` | `2^width - 1` (non-negative) |
| `>= 64` | `-1` (all 64 bits) |

A field `(offset, width)` is **well-formed** when
`1 <= width <= 64`, `0 <= offset < 64` and `offset + width <= 64`.
For `bit_get` / `bit_set` / `bit_clear`:

| Function | Invalid field |
|---|---|
| `bit_get` | returns `0` |
| `bit_set` | returns `value` unchanged |
| `bit_clear` | returns `value` unchanged |

`bit_set` masks the incoming `field` to `width` bits before use: only bits
`0..width-1` of `field` are read, so a wider (or negative) `field` value
cannot disturb neighbouring bits. `bit_toggle` validates only `offset`
(`0..63`); outside that range it returns `value` unchanged.

## API signatures and semantics

```xi
pub fn bit_mask(width: Int) -> Int
pub fn bit_get(value: Int, offset: Int, width: Int) -> Int
pub fn bit_set(value: Int, offset: Int, width: Int, field: Int) -> Int
pub fn bit_clear(value: Int, offset: Int, width: Int) -> Int
pub fn bit_toggle(value: Int, offset: Int) -> Int
pub fn bit_count_ones(value: Int) -> Int
pub fn bit_leading_zeros(value: Int) -> Int
pub fn bit_trailing_zeros(value: Int) -> Int
pub fn bit_reverse(value: Int, width: Int) -> Int
pub fn bit_byte_swap16(value: Int) -> Int
pub fn bit_byte_swap32(value: Int) -> Int
pub fn bit_rotate_left(value: Int, width: Int, n: Int) -> Int
pub fn bit_rotate_right(value: Int, width: Int, n: Int) -> Int
```

- `bit_get(value, offset, width)` -- unsigned, right-justified low `width`
  bits of the pattern starting at `offset`. `bit_get(v, 0, 64)` returns `v`
  itself (including for negative `v`).
- `bit_set(value, offset, width, field)` -- the `width` bits at `offset` are
  replaced by the low `width` bits of `field`; every other bit of `value` is
  unchanged.
- `bit_clear(value, offset, width)` -- the field is zeroed; every other bit
  is unchanged.
- `bit_toggle(value, offset)` -- flips exactly the bit at `offset`.
- `bit_count_ones(value)` -- number of set bits in the 64-bit pattern:
  `0 -> 0`, `-1 -> 64`, `INT64_MIN -> 1`, `INT64_MAX -> 63`.
- `bit_leading_zeros(value)` -- count from bit 63 downwards until the first
  set bit: `0 -> 64`, `1 -> 63`, `2 -> 62`, `INT64_MAX -> 1`, any negative
  value (sign bit set) -> 0.
- `bit_trailing_zeros(value)` -- count from bit 0 upwards: `0 -> 64`,
  `1 -> 0`, `INT64_MIN -> 63`.
- `bit_reverse(value, width)` -- reverses the low `width` bits (1..64) and
  clears the rest; other widths -> `0`. `bit_reverse(1, 64) == INT64_MIN`,
  `bit_reverse(INT64_MIN, 64) == 1`, `bit_reverse(-1, 64) == -1`.
- `bit_byte_swap16(value)` -- swaps bytes 0 and 1 of the pattern, widened:
  result in `0..65535`. Higher bytes are ignored.
- `bit_byte_swap32(value)` -- swaps bytes 0<->3 and 1<->2, widened: result
  in `0..2^32-1`. Higher bytes are ignored.
- `bit_rotate_left(value, width, n)` -- rotates the low `width` bits left
  by `shift = n mod width` in `0..width-1` (negative `n` wraps), clearing
  bits above the field. Width 64 rotates the full pattern, so the result can
  be negative.
- `bit_rotate_right(value, width, n)` -- mirror image of
  `bit_rotate_left`.
- Invalid rotation widths (`width <= 0` or `width > 64`) yield `0`.

## Complexity

| Operation | Complexity |
|---|---|
| `bit_mask` | O(width) |
| `bit_get` / `bit_set` / `bit_clear` | O(width^2) worst case |
| `bit_toggle` | O(offset) |
| `bit_count_ones` / `bit_leading_zeros` / `bit_trailing_zeros` | O(64^2) worst case |
| `bit_reverse` | O(width^2) |
| `bit_byte_swap16` / `bit_byte_swap32` | O(1) |
| `bit_rotate_left` / `bit_rotate_right` | O(width^2) |

The quadratic factors come from the arithmetic extraction loops used to
avoid the v0.61.3 bitwise codegen path; word-sized inputs are 64 bits.

## Test plan

`tests/test_conformance.xi` (`module bitfield_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). The suite itself also avoids bitwise operators,
so expected values are decimal literals. Coverage:

1. `bit_mask` pinned at 0, 1, 8, 31, 32, 63, 64 and an over-wide 100;
2. `bit_get` on `0x0102030405060708` across byte boundaries (bytes, cross
   byte 8-bit field at offset 4, 16-bit at offset 24, 32-bit at offset 32,
   nibbles at offsets 56/60);
3. `bit_get` invalid fields -> 0, plus full-width and sign-bit reads
   (`INT64_MIN`, `-1`);
4. `bit_set` exact replacement incl. bit 63, negative bases and a negative
   input 0xFFFFFFFF;
5. over-wide `field` values masked to `width` (255 in a 4-bit field, 256 and
   -1 in an 8-bit field);
6. `bit_clear` exact zeroing incl. `bit_clear(-1, 0, 64) == 0` and a no-op
   on already-clear bits;
7. invalid `bit_set` / `bit_clear` fields leave the input unchanged;
8. `bit_toggle` exact flips incl. bit 63, negative values and invalid
   offsets;
9. popcount on 0, 1, 0x0F, `-1`, `INT64_MIN`, `INT64_MAX`, and alternating
   0x5555.../0xAAAA... (32/32);
10. leading zeros: 0 -> 64, 1 -> 63, 255/256, 2^32-1, `INT64_MAX` -> 1,
    negatives -> 0;
11. trailing zeros: 0 -> 64, 1 -> 0, 0xFF00, `INT64_MIN` -> 63;
12. `bit_reverse` width 8 pinned (0x12 -> 0x48, 0xB7 -> 0xED), width 1, and
    high bits ignored;
13. `bit_reverse` width 16 pinned (0x1234 -> 0x2C48) and inverses;
14. `bit_reverse` width 64 round-trips and invalid widths -> 0;
15. `bit_byte_swap16` pinned (0x1234 -> 0x3412, 0x5678 -> 0x7856, -1 ->
    0xFFFF);
16. `bit_byte_swap32` pinned (0x11223344 -> 0x44332211, 0x12345678 ->
    0x78563412, 0x00FF00FF -> 0xFF00FF00);
17. `bit_rotate_left` width 8 with `n` = 1, 8, 9, -1, -8 and pinned
    0x81/0xFF/0x01 cases;
18. `bit_rotate_left` width 32 with `n` = 1, 8, 32, 40 and the sign bit;
19. `bit_rotate_right` widths 8, 16, 32, 64 incl. `n = -1`, `n = width` and
    the `INT64_MIN` wrap;
20. width-64 rotation wraps the sign bit (`INT64_MIN + 1` rotated left 1 ==
    3, `INT64_MAX` rotated left 1 == -2), width 1 is the identity, and
    invalid rotation widths -> 0.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.bitfield
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- 64-bit word domain only; no `UInt128`, no arbitrary precision, no bulk
  bit arrays.
- Full-width helpers can return negative `Int`s because they return raw
  two's-complement patterns.
- Invalid fields are rejected outright (no clamping), unlike
  `xiom.bits.bitfield.bitfield_get`, which truncates at bit 63.
- Rotations and reversal operate only on the low `width` bits; higher bits
  are cleared, not rotated.
- Arithmetic implementation: O(width^2) for field and counting helpers.
- Plain value functions; no shared state.

## Compiler / stdlib notes for v0.61.3

- No bitwise or shift operators are used anywhere in `src/bitfield.xi` or
  the test suite: `&` on operands with bit 31 set is documented to
  miscompile (`xiom.convert.base58`), so byte/bit extraction uses exact
  division with a non-negative remainder and masks are built by doubling.
- `INT64_MIN` is built as `0 - 9223372036854775807 - 1`.
- Free functions only (no methods, no lambdas, no structs); each `.xi` file
  carries the copyright and SPDX lines.
- The module and this package share only the root `xiom` segment with
  `xiom.bits.*` stdlib modules, so the section-4 namespace check passes.
