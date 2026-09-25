# xiom.fletcher

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI), Int-only Fletcher-16 and Fletcher-32
> checksums in the classic ones'-complement form, one-shot and incremental.
> **Deps:** `xiom.std` only. The library module imports `xiom.string` (hex
> display); the tests use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`.

## What it is

`xiom.fletcher` computes Fletcher's checksum, the position-sensitive
error-detection code, over fully materialized `Vec[UInt8]` buffers:

- **Fletcher-16**: `sum1`/`sum2` run modulo **255**, checksum
  `sum2 * 256 + sum1` in `[0, 65278]` (`0x0000..0xFEFE`);
- **Fletcher-32**: `sum1`/`sum2` run modulo **65535**, checksum
  `sum2 * 65536 + sum1` in `[0, 4294901758]`
  (`0x00000000..0xFFFEFFFE`).

Both are available as a one-shot function and as an incremental
`init`/`update`/`finalize` triple over a single packed `Int` state, plus
strict (`*_checked`) variants that reject non-canonical states, `Bool`
state predicates and unsigned hex display helpers. Every expected number in
the conformance suite was computed with independent reference
implementations of the published algorithm and is pinned (see `SPEC.md`).

Fletcher's checksum catches burst errors and reordered-byte errors that a
plain sum misses; it is **not** a cryptographic hash, not a MAC and is
trivially forgeable. Adler-32 is a different checksum and is not part of
this package.

## Install / use

```
xiom pkg install xiom.fletcher@0.1.0     # consumer
```

```xi
use xiom.fletcher;
```

## Quick start

One-shot:

```xi
use xiom.fletcher;
use xiom.io;
use xiom.convert;

var data = Vec[UInt8].new();
data.push(97);   // 'a'
data.push(98);   // 'b'
data.push(99);   // 'c'

io.println(convert.int_to_string(fletcher16(&data)));  // 19495 (0x4C27)
io.println(convert.int_to_string(fletcher32(&data)));  // 38404390 (0x024A0126)
io.println(fletcher16_hex(fletcher16(&data)));         // "4c27"
io.println(fletcher32_hex(fletcher32(&data)));         // "024a0126"
```

Incremental:

```xi
var s = fletcher16_init();
s = fletcher16_update(s, &head);     // any chunk size, including empty
s = fletcher16_update(s, &tail);
let sum = fletcher16_finalize(s);    // == fletcher16(whole buffer)
```

The incremental and one-shot surfaces share one byte loop, so for every
split of the input the incremental result equals the one-shot result by
construction; the conformance suite pins that equality at every split point
of `"abcdefgh"` and `"abcdef"`, byte-at-a-time over a 300-byte buffer and
with chunk sizes 1..7 over a 43-byte message.

## API

All functions are free functions in module `xiom.fletcher`. `state` values
are packed exactly like checksums (see *Output order* below).

### Fletcher-16

| Function | Returns | Description |
|---|---|---|
| `fletcher16(data)` | `Int` | One-shot checksum in `[0, 65278]`; empty input is `0`. |
| `fletcher16_init()` | `Int` | Initial state `0`. |
| `fletcher16_update(state, data)` | `Int` | Continues the running sums; accepts and canonicalizes any `Int` state. |
| `fletcher16_finalize(state)` | `Int` | Canonicalizes; the identity on `init`/`update` states. |
| `fletcher16_update_checked(state, data)` | `Result[Int, Str]` | Strict update; `Err` on a non-canonical state. |
| `fletcher16_finalize_checked(state)` | `Result[Int, Str]` | Strict finalize; `Err` on a non-canonical state. |
| `fletcher16_state_valid(state)` | `Bool` | True for canonical states: `[0, 65278]` with `sum1 <= 254`. |
| `fletcher16_hex(value)` | `Str` | 4 lowercase hex digits of `value mod 2^16`. |

### Fletcher-32

| Function | Returns | Description |
|---|---|---|
| `fletcher32(data)` | `Int` | One-shot checksum in `[0, 4294901758]`; empty input is `0`. |
| `fletcher32_init()` | `Int` | Initial state `0`. |
| `fletcher32_update(state, data)` | `Int` | Continues the running sums; accepts and canonicalizes any `Int` state. |
| `fletcher32_finalize(state)` | `Int` | Canonicalizes; the identity on `init`/`update` states. |
| `fletcher32_update_checked(state, data)` | `Result[Int, Str]` | Strict update; `Err` on a non-canonical state. |
| `fletcher32_finalize_checked(state)` | `Result[Int, Str]` | Strict finalize; `Err` on a non-canonical state. |
| `fletcher32_state_valid(state)` | `Bool` | True for canonical states: `[0, 4294901758]` with `sum1 <= 65534`. |
| `fletcher32_hex(value)` | `Str` | 8 lowercase hex digits of `value mod 2^32`. |

No `pub type` is exported; the module has no state, no struct types and no
FFI.

## Output order (pinned)

The checksum Int packs `sum2` above `sum1`, `sum1` in the low-order word:

```
Fletcher-16 checksum = sum2 * 256   + sum1
Fletcher-32 checksum = sum2 * 65536 + sum1
```

This is the common convention (the same packing every implementation uses
to serialize the two accumulators). Because both components are canonical
residues, a Fletcher-16 value is never `0xFFxx` and a Fletcher-32 value is
never `0xFFFFxxxx`; e.g. `"abc"` is `0x4C27` (Fletcher-16) and `0x024A0126`
(Fletcher-32).

## Reduction cadence (pinned)

After **every** input byte, both sums are reduced:

```
Fletcher-16:  sum1 = (sum1 + b) % 255    sum2 = (sum2 + sum1) % 255
Fletcher-32:  sum1 = (sum1 + b) % 65535  sum2 = (sum2 + sum1) % 65535
```

so `sum1` is always in `[0, 254]` (resp. `[0, 65534]`) and `sum2` likewise.
Reducing per byte is mathematically equivalent to the classic deferred form
(addition is congruent modulo the modulus) and keeps every intermediate
tiny (`<= 509` / `<= 508` for Fletcher-16, `<= 65789` / `<= 131068` for
Fletcher-32), so the arithmetic is exact `Int` arithmetic with no overflow,
shift or masking subtleties.

## Error model

The error catalog has exactly one entry:

```
fletcher: invalid state
```

It is returned only by the `*_checked` incremental variants when the state
Int is outside the canonical contract (`fletcherN_state_valid` is false):
a negative value, a value above the maximum checksum, or a low component
equal to the modulus fold (`sum1 = 255` for Fletcher-16, `sum1 = 65535` for
Fletcher-32). The unchecked `update`/`finalize` never fail: they
canonicalize any `Int` deterministically -- low 16/32 bits first, then each
component modulo 255/65535 -- so `update(-1, d)` behaves as
`update(0, d)`. One-shot functions and hex helpers are total and cannot
fail.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.fletcher
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Fletcher-16 and Fletcher-32 only.** Fletcher-64 needs 64-bit modular
  sums and is out of scope; the classic variants are fixed here.
- **No Adler-32.** Adler-32 uses modulus 65521, initial value 1 and a
  different output fold; it is a separate checksum with its own package, not
  a mode of this one.
- **No block/table variants.** The implementation is the plain byte-wise
  recurrence; no lookup tables, slicing-by-N, SIMD, CLMUL or block forms.
- **Checksum, not cryptography.** Fletcher codes detect accidental
  corruption; they are not collision-resistant, not a MAC and offer no
  authenticity. Do not use them to verify adversarial input.
- **Whole buffers and packed Int state.** The input is a materialized
  `Vec[UInt8]`; the incremental API is explicit packed-`Int` state, not a
  hasher object. Non-canonical states are canonicalized (unchecked) or
  rejected (`*_checked`), never guessed.
- **Detection strength.** Fletcher-16 catches all single-byte errors and
  most burst errors, but its two 8-bit sums give a much smaller detection
  space than a CRC of the same width; prefer `xiom.crc` when stronger
  detection is required.
- No FFI, no `extern "C"` blocks, no unsafe code, no dependencies beyond
  `xiom.std`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
