# xiom.adler32

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI), Int-only Adler-32 checksum (RFC 1950) over
> fully materialized `Vec[UInt8]` buffers, one-shot and incremental.
> **Deps:** `xiom.std` only. The library module imports `xiom.string` (hex
> display); the tests use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`.

## What it is

`xiom.adler32` computes Adler-32, the checksum defined in RFC 1950 and used
by zlib, gzip and PNG, over fully materialized `Vec[UInt8]` buffers. Two
16-bit running sums modulo **65521** (the largest prime below 2^16),
initialized to `s1 = 1` and `s2 = 0`, fold into the zlib-compatible 32-bit
value `s2 * 65536 + s1` (`(s2 << 16) | s1`).

The API is:

- `adler32(data)` -- one-shot checksum;
- `adler32_init` / `adler32_update` / `adler32_finalize` -- incremental over
  a single packed `Int` state;
- `adler32_update_checked` / `adler32_finalize_checked` /
  `adler32_state_valid` -- strict variants and the total state predicate;
- `adler32_hex(value)` -- 8-digit lowercase unsigned hex display.

Every expected number in the conformance suite was computed with independent
references (Python's `zlib.adler32`, the original C implementation, plus
per-byte and fully deferred pure-Python references) and is pinned; see
`SPEC.md`.

Adler-32 is an **error-detection checksum**, not a cryptographic hash: it is
not collision-resistant, not a MAC and is trivially forgeable. This package
computes checksum values only; it does not read or write zlib/gzip
containers.

## Install / use

```
xiom pkg install xiom.adler32@0.1.0     # consumer
```

```xi
use xiom.adler32;
```

## Quick start

One-shot:

```xi
use xiom.adler32;
use xiom.io;
use xiom.convert;

var data = Vec[UInt8].new();
data.push(97);   // 'a'
data.push(98);   // 'b'
data.push(99);   // 'c'

io.println(convert.int_to_string(adler32(&data)));  // 38600999 (0x024D0127)
io.println(adler32_hex(adler32(&data)));            // "024d0127"
```

Incremental:

```xi
var s = adler32_init();                  // 1
s = adler32_update(s, &head);            // any chunk size, including empty
s = adler32_update(s, &tail);
let sum = adler32_finalize(s);           // == adler32(whole buffer)
```

The one-shot and incremental surfaces share one byte loop, so for every
split of the input the incremental result equals the one-shot result; the
conformance suite pins that equality at every split of `"abcdefgh"` and
`"abcdef"`, byte-at-a-time over a 6000-byte buffer and with chunk sizes 1..7
and 5551/5552/5553.

## API

All functions are free functions in module `xiom.adler32`. A `state` value
is packed exactly like a checksum: `s2 * 65536 + s1`.

| Function | Returns | Description |
|---|---|---|
| `adler32(data)` | `Int` | One-shot checksum in `[0, 4293984240]`; empty input is `1`. |
| `adler32_init()` | `Int` | Initial state `1`. |
| `adler32_update(state, data)` | `Int` | Continues the running sums; accepts and canonicalizes any `Int` state. |
| `adler32_finalize(state)` | `Int` | Canonicalizes; the identity on `init`/`update` states. |
| `adler32_update_checked(state, data)` | `Result[Int, Str]` | Strict update; `Err` on a non-canonical state. |
| `adler32_finalize_checked(state)` | `Result[Int, Str]` | Strict finalize; `Err` on a non-canonical state. |
| `adler32_state_valid(state)` | `Bool` | True for canonical states: `[0, 4293984240]` with `s1 <= 65520`. |
| `adler32_hex(value)` | `Str` | 8 lowercase hex digits of `value mod 2^32`. |

No `pub type` is exported; the module has no state, no struct types and no
FFI.

## Output order (pinned)

The checksum Int packs `s2` above `s1`, `s1` in the low 16 bits:

```
checksum = s2 * 65536 + s1        (zlib: (s2 << 16) | s1)
```

so the empty input is `1` and a canonical value lies in
`[0, 4293984240]` (`0x00000000..0xFFF0FFF0`); e.g. `"abc"` is `0x024D0127`
and `"Wikipedia"` is `0x11E60398`.

## Reduction cadence (pinned, deferred)

Inside one `update` call the sums are accumulated **without** reduction for
at most **5552 bytes** (the classic zlib `NMAX`) and are then reduced modulo
65521; every `update` call and every `finalize` reduces the state again.
Within one block the largest values are

```
s1 <= 65520 + 5552 * 255                           = 1481280
s2 <= 65520 + 65520 * 5552 + 255 * 5552 * 5553 / 2 = 4294690200
```

and `4294690200 < 2^32`, the standard Adler-32 argument for the 5552 block
size. Deferring is exact: addition is congruent modulo 65521, so reducing
once per block -- or only at finalize -- reaches exactly the same residues as
reducing after every byte. The conformance suite proves the agreement on
inputs longer than 5552 bytes against test-local per-byte and fully deferred
references.

## Error model

The error catalog has exactly one entry:

```
adler32: invalid state
```

It is returned only by the `*_checked` incremental variants when the state
Int is outside the canonical contract (`adler32_state_valid` is false): a
negative value, a value above the maximum checksum `4293984240`, or a low
word `s1 > 65520`. The unchecked `update`/`finalize` never fail: they
canonicalize any `Int` deterministically -- low 32 bits first, then each
component modulo 65521 -- so `update(-1, d)` behaves as `update(917518, d)`.
The one-shot function and the hex helper are total and cannot fail.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.adler32
```

Expected: the namespace check passes, 22 `[PASS]` lines, and a final
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Adler-32 only.** No other checksums (no CRC, Fletcher, FNV, Murmur), no
  cryptographic hashes.
- **No containers and no compression.** The package computes checksum values
  only; it does not parse or write zlib/gzip streams, deflate blocks or PNG
  chunks.
- **Checksum, not cryptography.** Adler-32 detects accidental corruption; it
  is not collision-resistant, not a MAC and offers no authenticity. Do not
  use it to verify adversarial input.
- **Detection strength.** Adler-32 has a much smaller error-detection
  capability than CRC-32, especially on short inputs; prefer `xiom.crc` when
  stronger detection is required.
- **Whole buffers and packed Int state.** The input is a materialized
  `Vec[UInt8]`; the incremental API is explicit packed-`Int` state, not a
  buffering hasher object. Non-canonical states are canonicalized (unchecked)
  or rejected (`*_checked`), never guessed.
- No FFI, no `extern "C"` blocks, no unsafe code, no dependencies beyond
  `xiom.std`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
