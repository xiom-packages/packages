# xiom.bitfield

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** bit manipulation helpers for 64-bit `Int` words: masks, field
> extract/replace/clear/toggle, popcount, leading/trailing zeros, reversal,
> byte swaps and rotations.
> **Deps:** `xiom.std` only (the module itself imports nothing; the tests add
> `xiom.test` and `xiom.io`).
> No FFI.

## What it is

`xiom.bitfield` treats every `Int` as a 64-bit two's-complement bit pattern
and provides the classic word-level helpers:

- **masks** (`bit_mask`) for pre-sizing buffers and field math;
- **field access** (`bit_get` / `bit_set` / `bit_clear` / `bit_toggle`) with
  all-or-nothing validation: an invalid field yields `0` (get) or leaves the
  input unchanged (set/clear/toggle);
- **counting** (`bit_count_ones`, `bit_leading_zeros`, `bit_trailing_zeros`)
  over the full 64-bit pattern, including the sign bit;
- **reversal and byte order** (`bit_reverse`, `bit_byte_swap16`,
  `bit_byte_swap32`);
- **rotation** (`bit_rotate_left` / `bit_rotate_right`) of a low `width`-bit
  field, with `n` reduced modulo `width`.

All functions are free functions without FFI. The implementation avoids
`&`, `|`, `^` and shift operators entirely (see `SPEC.md` for the v0.61.3
codegen note) and uses exact arithmetic instead, so the results are pinned
for negative inputs as well.

## API

| Function | Returns | Description |
|---|---|---|
| `bit_mask(width)` | `Int` | Low `width` bits set; `width <= 0` -> `0`; `width >= 64` -> `-1`. |
| `bit_get(value, offset, width)` | `Int` | Extract `width` bits at 0-based `offset`; invalid -> `0`. |
| `bit_set(value, offset, width, field)` | `Int` | Replace the field with `field` masked to `width`; invalid -> `value`. |
| `bit_clear(value, offset, width)` | `Int` | Zero the field; invalid -> `value`. |
| `bit_toggle(value, offset)` | `Int` | Flip bit `offset`; `offset` outside `0..63` -> `value`. |
| `bit_count_ones(value)` | `Int` | Popcount over the 64-bit pattern (`-1` -> 64, `INT64_MIN` -> 1). |
| `bit_leading_zeros(value)` | `Int` | Zero bits above the highest set bit; `0` -> 64; negatives -> 0. |
| `bit_trailing_zeros(value)` | `Int` | Zero bits below the lowest set bit; `0` -> 64. |
| `bit_reverse(value, width)` | `Int` | Reverse the low `width` bits (1..64); other widths -> `0`. |
| `bit_byte_swap16(value)` | `Int` | Swap the low two bytes, widened to `0..65535`. |
| `bit_byte_swap32(value)` | `Int` | Swap the low four bytes, widened to `0..2^32-1`. |
| `bit_rotate_left(value, width, n)` | `Int` | Rotate the low `width` bits left by `n mod width`; width 1..64. |
| `bit_rotate_right(value, width, n)` | `Int` | Rotate the low `width` bits right by `n mod width`; width 1..64. |

## Sign model

`Int` is a signed 64-bit word, so bit 63 is the sign bit and the same
pattern can be read as negative. Helpers return a non-negative result
whenever the answer fits below bit 63; full-width results (`bit_get` with
`offset + width == 64`, `bit_reverse` with width 64, rotations with width
64) return the whole two's-complement pattern and can be negative:

```xi
bit_get(0 - 9223372036854775807 - 1, 0, 64)   // INT64_MIN (round trip)
bit_reverse(1, 64)                            // INT64_MIN
bit_rotate_right(1, 64, 1)                    // INT64_MIN
```

## Usage

```xi
use xiom.bitfield;

let flags = bit_set(0, 4, 2, 2);          // 32  (bits 4..5 = 0b10)
let two = bit_get(flags, 4, 2);           // 2
let low12 = bit_mask(12);                 // 4095
let ones = bit_count_ones(-1);            // 64
let rev = bit_reverse(0xB7, 8);           // 237 (0xED)
let swapped = bit_byte_swap16(0x1234);    // 13330 (0x3412)
let rolled = bit_rotate_left(1, 8, 7);    // 128
let rolled_back = bit_rotate_right(128, 8, 7); // 1
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.bitfield
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **64-bit `Int` model only.** There is no `UInt128`/arbitrary-precision or
  bulk bit-array type; for dynamic bit vectors use `xiom.bits.bitarray`.
  Values are interpreted as two's-complement bit patterns, so helpers that
  return a full 64-bit word (`bit_get` width 64, `bit_reverse` width 64,
  `bit_rotate_*` width 64) can return a negative `Int`.
- **All-or-nothing field validation.** `bit_get` / `bit_set` / `bit_clear`
  reject a field that runs past bit 63 (`offset + width > 64`) rather than
  clamping it; `bit_get` yields `0` and `bit_set` / `bit_clear` return the
  input unchanged.
- **`n mod width` rotation.** `n` may be any `Int` (including negative);
  it is reduced modulo `width`. `width == 1` makes every rotation the
  identity, because every `n` is `0 mod 1`.
- **Reversal/rotation are field-local.** Only the low `width` bits take
  part; bits above the field are cleared, never rotated in.
- **Arithmetic implementation.** The module deliberately avoids the
  bitwise operators that miscompile in v0.61.3, so counting helpers are
  O(64^2) worst case and rotations O(width^2). Word-sized use is fine;
  it is not a throughput-optimized bulk library.
- Plain value functions; no shared mutable state and no thread-safety
  concerns of their own.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
