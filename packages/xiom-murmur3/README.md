# xiom.murmur3

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI), Int-only implementation of the
> MurmurHash3 x86_32 non-cryptographic hash, as a one-shot function and as
> an explicit streaming state with `init`/`update`/`finalize`.
> **Deps:** `xiom.std` only. The library module imports `xiom.string`
> (for the hex display helper); the tests use `xiom.test`, `xiom.io` and
> `xiom.string`.

## What it is

`xiom.murmur3` implements the x86_32 variant of MurmurHash3 as published
by Austin Appleby and used by the smhasher test harness
(<https://github.com/aappleby/smhasher>; the algorithm is public domain,
the smhasher code is MIT), for byte buffers (`Vec[UInt8]`):

- `murmur3_x86_32(data, seed)` -- one-shot 32-bit digest, returned as a
  non-negative `Int` in `[0, 2^32)`;
- `murmur3_x86_32_init/update/finalize` -- the same algorithm over an
  explicit `Murmur3State{h1, length, tail}` so a stream can be hashed in
  arbitrary chunks;
- `murmur3_x86_32_hex(value)` -- 8 lowercase hex digits for unsigned
  display;
- the specification constants (multipliers `c1`/`c2`, the fmix32 pair,
  the canonical seeds and the smhasher verification value);
- `murmur3_x86_32_rotl32(x, r)` -- the arithmetic 32-bit rotation the
  module uses internally, exposed and pinned.

The body loop, tail handling and avalanche follow the reference C code
byte for byte. The implementation is pinned against the canonical
smhasher values: the short-key digests at seed 0 (`""` -> `0`,
`"a"` -> `0x3C2569B2`, `"abc"` -> `0xB3DD93FA`,
`"Hello, world!"` -> `0xC0363E43`), nonzero-seed digests, and the full
smhasher `VerificationTest` value `0xB0F57EE3` for the 256-prefix key
schedule at seed 256. See `SPEC.md` for the complete tables.

## Install / use

```
xiom pkg install xiom.murmur3@0.1.0     # consumer
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Then import the module:

```xi
use xiom.murmur3;
```

## Quick start

```xi
use xiom.murmur3;
use xiom.io;
use xiom.string;

// Build the byte buffer for "abc".
var data = Vec[UInt8].new();
var text = "abc";
var i = 0;
while i < text.len() {
  data.push(string.byte_at(text, i));
  i = i + 1;
}

io.println(murmur3_x86_32_hex(murmur3_x86_32(&data, 0)));      // b3dd93fa
io.println(murmur3_x86_32_hex(murmur3_x86_32(&data, 1)));      // aa75e9ff
io.println(murmur3_x86_32_hex(murmur3_x86_32(&data, 0 - 1)));  // fc80c2af
```

`io.println` accepts the `Str` directly; use `xiom.convert.int_to_string`
if you need the signed decimal value of the digest instead.

### Streaming hashing

```xi
use xiom.murmur3;

// Caller-supplied chunks in stream order.
var head = Vec[UInt8].new();
var tail = Vec[UInt8].new();

var s = murmur3_x86_32_init(0);              // seed 0
let r1 = murmur3_x86_32_update(&mut s, &head);
let r2 = murmur3_x86_32_update(&mut s, &tail);
let fin = murmur3_x86_32_finalize(&s);

// For states built by init and advanced only by update, update/finalize
// never return Err: the error path only guards forged states.
if r1.is_ok && r2.is_ok && fin.is_ok {
  // fin.value equals murmur3_x86_32(whole_buffer, 0)
}
```

`update` buffers the trailing 0..3 bytes and completes blocks across
chunk boundaries, so streaming and one-shot agree at every split point
(the conformance suite checks every split of several messages).

## API summary

All functions are free functions in module `xiom.murmur3`.

### Constants

| Function | Returns | Value |
|---|---|---|
| `murmur3_x86_32_c1()` | `Int` | `3432918353` (`0xCC9E2D51`) |
| `murmur3_x86_32_c2()` | `Int` | `461845907` (`0x1B873593`) |
| `murmur3_x86_32_fmix_c1()` | `Int` | `2246822507` (`0x85EBCA6B`) |
| `murmur3_x86_32_fmix_c2()` | `Int` | `3266489909` (`0xC2B2AE35`) |
| `murmur3_x86_32_default_seed()` | `Int` | `0` (the canonical default) |
| `murmur3_x86_32_smhasher_seed()` | `Int` | `256` (smhasher `VerificationTest` seed) |
| `murmur3_x86_32_smhasher_value()` | `Int` | `2968878819` (`0xB0F57EE3`) |

### One-shot

| Function | Returns | Description |
|---|---|---|
| `murmur3_x86_32(data, seed)` | `Int` | The 32-bit digest in `[0, 2^32)`; `seed` is reduced modulo `2^32`. Empty input, seed 0, yields 0. |

### Streaming (`Murmur3State`)

`Murmur3State` is `{ h1: Int; length: Int; tail: Vec[UInt8]; }`: the
running word, the bytes fed so far, and the 0..3 buffered tail bytes.

| Function | Returns | Description |
|---|---|---|
| `murmur3_x86_32_init(seed)` | `Murmur3State` | Fresh state; `seed` reduced modulo `2^32`. |
| `murmur3_x86_32_update(state, data)` | `Result[Unit, Str]` | Advance the state; `&mut` at the call site. |
| `murmur3_x86_32_finalize(state)` | `Result[Int, Str]` | The digest; non-destructive. |
| `murmur3_x86_32_state_is_valid(state)` | `Bool` | Invariant predicate (`h1` in `[0, 2^32)`, `length >= 0`, tail 0..3 bytes). |
| `murmur3_x86_32_state_h1(state)` | `Int` | The running word. |
| `murmur3_x86_32_state_length(state)` | `Int` | Bytes fed so far. |
| `murmur3_x86_32_state_tail_len(state)` | `Int` | Buffered tail length (0..3). |
| `murmur3_x86_32_state_tail(state)` | `Vec[UInt8]` | A copy of the buffered tail bytes. |

### Rotation helper

| Function | Returns | Description |
|---|---|---|
| `murmur3_x86_32_rotl32(x, r)` | `Int` | `x mod 2^32` rotated left by `r mod 32`, computed with `*`, `/`, `%` only. |

### Unsigned display

| Function | Returns | Description |
|---|---|---|
| `murmur3_x86_32_hex(value)` | `Str` | 8 lowercase hex digits of `value mod 2^32`. |

## Numeric model

- **No 64-bit state, no BigInt.** A 32-bit word is always a non-negative
  `Int` in `[0, 2^32)`.
- **Wrapping multiply without overflow semantics:** `_mul32` splits both
  factors into 16-bit limbs, multiplies the columns and keeps the terms
  below `2^32`; every intermediate stays below `2^34`, so the wrapped
  product is exact in `Int`.
- **Rotations without shifts:**
  `rotl32(x, r) = (x * 2^r mod 2^32) + floor(x / 2^(32-r))`. The first
  term holds the low bits of `x` in the high positions, the second holds
  the high bits in the low positions; the bit ranges are disjoint, so the
  sum is the rotated word and stays in `[0, 2^32)`.
- **XOR without high-bit operands:** both operands are split into 16-bit
  halves, `^` is applied to halves below `2^16` and the result is
  recombined arithmetically. No bitwise operator ever sees bit 31 set,
  which keeps the module clear of the v0.61.3 high-bit codegen bugs.
- **Right shifts** (`h >> 16`, `h >> 13`) are floor divisions by
  `2^16` and `2^13`.
- **Seeds** are reduced modulo `2^32`: `-1` means `0xFFFFFFFF`,
  `2^32 + 5` means `5`.

## Error model

The one-shot function and the read-only helpers are total. The streaming
`update` and `finalize` return a `Result` with exactly one error message:

| Message | Raised when |
|---|---|
| `murmur3: invalid streaming state` | `h1` is outside `[0, 2^32)`, `length` is negative, or the buffered tail is longer than 3 bytes. |

`Err` is unreachable for states built by `murmur3_x86_32_init` and
advanced only by `murmur3_x86_32_update`; it exists to reject forged
states (the struct fields are readable, so a caller can build one) before
they can violate the block loop. A rejected update leaves the state
untouched. Hash collisions are inherent to any hash function and are not
reported; this package makes no collision or cryptographic claim.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.murmur3
```

Expected: the namespace check passes, 18 `[PASS]` lines, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Not cryptographic.** MurmurHash3 is a fast, simple non-cryptographic
  hash: it is trivially forgeable, provides no authentication, and must
  not be used for signatures, MACs, password hashing or adversarial
  collision resistance. (MurmurHash3 has known seed-independent
  weaknesses; it is not a replacement for a keyed cryptographic hash.)
- **Only x86_32.** The `x86_128` and `x64_128` variants are not
  implemented: they need 128-bit output words and, for `x64_128`, a
  64-bit block word. This is a documented non-goal, not a gap.
- **No other hash families.** No xxHash, CityHash, SpookyHash, SipHash,
  CRC, FNV or cryptographic hashes live here.
- **No streaming object beyond the state struct.** The state is passed
  explicitly (`&mut` for update); there is no hasher handle with internal
  mutation, no `update`-then-digest-without-finalize shortcut.
- **Not optimized.** Every multiply goes through the limb split and every
  rotation through division loops to keep all arithmetic provably inside
  Int64 for compiler v0.61.3. Correct and portable, not fast.
- **Seed is a 32-bit value.** Seeds are reduced modulo `2^32`, so
  `seed` and `seed + 2^32` are the same hash. That is the specification,
  not a defect.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
