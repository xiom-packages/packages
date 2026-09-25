# xiom.ulid

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) ULID codec: 128 bits (48-bit millisecond
> timestamp + 80-bit randomness) as 26 Crockford base32 characters, with
> caller-supplied timestamp and randomness, strict validation and
> component-wise decoding.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string` and `xiom.string.compare`).

## What it is

`xiom.ulid` is a small, dependency-light codec for the ULID layout: a 128-bit
value made of a 48-bit Unix millisecond timestamp (most significant) followed
by 80 bits of randomness, rendered as 26 Crockford base32 characters
(`0123456789ABCDEFGHJKMNPQRSTVWXYZ`). Text output is uppercase canonical;
decoding is case-insensitive, and the ambiguous letters `I`, `L`, `O` and `U`
are **rejected** rather than folded to `1`/`0`.

There is deliberately **no randomness generation and no clock access inside
the package**. The caller owns both: `ulid_encode` takes the millisecond
timestamp and the 80 random bits as two 40-bit halves (`rand_hi`, `rand_lo`),
so every function is deterministic, unit-testable, and the caller decides
which RNG (or fixed test vector) supplies the entropy.

The 80-bit randomness is returned by three component accessors
(`ulid_timestamp`, `ulid_random_hi`, `ulid_random_lo`) instead of a struct, so
every value stays inside `Int` and the module keeps the flat free-function
style of the v0.61.3 package family.

## Install / use

```
xiom pkg install xiom.ulid@0.1.0
```

```xi
use xiom.ulid;
use xiom.io;

// The caller owns the clock and the RNG: a 48-bit millisecond timestamp and
// two 40-bit randomness halves. This example uses fixed components so the
// output is reproducible.
let id = ulid_encode(1700000000000, 4886718345, 654570336784);
if id.is_ok {
  io.println(id.value);                       // 01HF7YAT0004HMASW9K1KPXCGG
  io.println(ulid_is_valid(id.value));        // true
}

match ulid_canonical("01arz3ndektsv4rrffq69g5fav") {
  Ok(v)  => { io.println(v); },               // 01ARZ3NDEKTSV4RRFFQ69G5FAV
  Err(e) => { io.println(e); },               // never taken here
}

match ulid_timestamp("01ARZ3NDEKTSV4RRFFQ69G5FAV") {
  Ok(t)  => { io.println(t); },               // 1469922850259
  Err(e) => { io.println(e); },
}
```

Generating IDs within one millisecond: encode with the same timestamp and keep
the randomness strictly increasing, using `ulid_monotonic_ok` to check each
candidate against the previous value.

## API

| Function | Returns | Description |
|---|---|---|
| `ulid_alphabet()` | `Str` | The 32-character Crockford alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`. |
| `ulid_encode(timestamp, rand_hi, rand_lo)` | `Result[Str, Str]` | Components => canonical 26-character ULID; validates the 48-bit timestamp and both 40-bit randomness halves. |
| `ulid_timestamp(s)` | `Result[Int, Str]` | 48-bit millisecond timestamp (characters 0..9). |
| `ulid_random_hi(s)` | `Result[Int, Str]` | High 40 bits of the randomness (characters 10..17). |
| `ulid_random_lo(s)` | `Result[Int, Str]` | Low 40 bits of the randomness (characters 18..25). |
| `ulid_is_valid(s)` | `Bool` | True exactly when the length, alphabet and 128-bit range checks pass. |
| `ulid_canonical(s)` | `Result[Str, Str]` | Re-emit an accepted ULID in canonical uppercase form. |
| `ulid_compare(a, b)` | `Result[Int, Str]` | `-1`/`0`/`1` over the decoded `(timestamp, rand_hi, rand_lo)` tuple. |
| `ulid_equal(a, b)` | `Result[Bool, Str]` | True when both ULIDs carry the same 128-bit value (case-insensitive). |
| `ulid_monotonic_ok(prev, next)` | `Result[Bool, Str]` | True when `next` is strictly greater than `prev`; within the same millisecond this requires strictly greater randomness. |

Error catalog (every message starts with `ulid: `):

| Message | Raised by |
|---|---|
| `ulid: expected 26 characters` | every decoding/validating function |
| `ulid: invalid character` | every decoding/validating function; `I`, `L`, `O`, `U` (either case) and all non-alphabet bytes |
| `ulid: overflow` | decoding; the top two bits of the 130-bit text are set (first character `8`..`Z`/`8`..`z`), so the value cannot fit 128 bits |
| `ulid: timestamp out of range` | `ulid_encode`; timestamp outside `0..2^48-1` |
| `ulid: randomness out of range` | `ulid_encode`; either randomness half outside `0..2^40-1` |

`ulid_is_valid` has no error channel: it returns `false` exactly when the
other functions would return one of the first three errors.

## Ordering and monotonicity

ULID order is the decoded 128-bit order: timestamp first, then `rand_hi`,
then `rand_lo`. For canonical uppercase text this is the same as byte-wise
lexicographic comparison, so ULIDs stored as text sort correctly under
ordinary string ordering. `ulid_compare` and `ulid_equal` decode first, so
case differences never affect the result.

`ulid_monotonic_ok(prev, next)` is the strict progression check for
caller-generated IDs:

- a greater timestamp always passes;
- the same timestamp requires strictly greater 80-bit randomness (the value
  must advance; an equal or smaller randomness is not monotonic);
- a smaller timestamp always fails.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ulid
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No RNG, no clock.** `ulid_encode` masks and formats caller-supplied
  components; it never generates entropy or reads the time. Callers that need
  unpredictable IDs must supply bytes from a cryptographic source.
- **No bit-level randomness helpers.** The randomness enters and leaves as two
  40-bit `Int` halves; there is no uint128/byte-vector view of the 128 bits.
- **Strict input.** 26 bytes exactly, alphabet characters only; `I`, `L`, `O`,
  `U` (either case) are invalid, not folded; no whitespace, hyphens or
  prefixes are accepted.
- **Overflow is rejected.** Any 26-character text whose value exceeds
  `2^128 - 1` (first character `8`..`Z`) is `Err("ulid: overflow")`, so the
  largest valid ULID is `7ZZZZZZZZZZZZZZZZZZZZZZZZZ`.
- **No ULID parsing from other formats.** There is no binary (16-byte), hex,
  UUID or base64 conversion; only the canonical 26-character text.
- **In-memory only.** No streaming API, no file I/O, no FFI, no registry
  integration.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
