# xiom.murmur3 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.murmur3`, version `0.1.0`).
Module: `src/murmur3.xi` (`module xiom.murmur3`).
Depends on `xiom.std`; the library module imports `xiom.string` (for the
hex display helper). The tests import `xiom.test`, `xiom.io` and
`xiom.string`.

## 1. Scope

A pure-XIOM (no FFI), Int-only implementation of the MurmurHash3 x86_32
variant by Austin Appleby, following the canonical reference
implementation in the smhasher harness
(<https://github.com/aappleby/smhasher>; the algorithm is public domain,
the smhasher code is MIT), over fully materialized `Vec[UInt8]` buffers:

- one-shot function `murmur3_x86_32(data, seed)`;
- streaming state `Murmur3State{h1, length, tail}` with
  `murmur3_x86_32_init`, `murmur3_x86_32_update` and
  `murmur3_x86_32_finalize`, plus read-only accessors and an invariant
  predicate;
- the specification constants (`_c1`, `_c2`, `_fmix_c1`, `_fmix_c2`,
  `_default_seed`, `_smhasher_seed`, `_smhasher_value`);
- the arithmetic rotation helper `murmur3_x86_32_rotl32(x, r)`;
- unsigned display helper `murmur3_x86_32_hex(value)`.

The one-shot function and the streaming `update` share the same mixing
helpers, so the two surfaces cannot drift; the conformance suite pins
their equality at every split point of several messages.

## 2. Non-goals

- `x86_128` and `x64_128` MurmurHash3 variants: they need 128-bit output
  words and, for `x64_128`, a 64-bit block word and 64-bit finalization.
  This package is x86_32 only.
- Any other hash family (xxHash, CityHash, SpookyHash, SipHash, CRC,
  FNV, SHA, ...) -- this package is MurmurHash3 x86_32 only.
- Cryptographic claims of any kind: MurmurHash3 is not a MAC, is not
  collision-resistant and is not designed to resist adversarial inputs.
- Keyed/secret variants, HMAC-style construction, or an
  output-truncation API.
- Lookup tables, SIMD, FFI, or any dependency beyond `xiom.std`.
- Streaming hasher objects with hidden internal buffers or methods: the
  state is an explicit plain struct threaded by the caller.

## 3. Specification constants

| Name | Hex | Decimal | Role |
|---|---|---|---|
| `c1` | `0xCC9E2D51` | `3432918353` | Body multiplier 1 |
| `c2` | `0x1B873593` | `461845907` | Body multiplier 2 |
| `fmix c1` | `0x85EBCA6B` | `2246822507` | Avalanche multiplier 1 |
| `fmix c2` | `0xC2B2AE35` | `3266489909` | Avalanche multiplier 2 |
| body multiplier | `5` | `5` | `h1 = h1*5 + 0xE6546B64` |
| body addend | `0xE6546B64` | `3864292196` | Body addend |
| `k1` rotation | `15` | `15` | `rotl32(k1, 15)` |
| `h1` rotation | `13` | `13` | `rotl32(h1, 13)` |
| default seed | `0x00000000` | `0` | Canonical seed |
| smhasher seed | `0x00000100` | `256` | `VerificationTest` seed |
| smhasher value | `0xB0F57EE3` | `2968878819` | `VerificationTest` result |

`murmur3_x86_32_default_seed()` returns the canonical default seed `0`;
`murmur3_x86_32_smhasher_seed()` returns `256`, the seed the smhasher
`VerificationTest` uses; `murmur3_x86_32_smhasher_value()` returns
`0xB0F57EE3`, the digest that protocol produces (section 8.5).

## 4. Algorithm

Reference pseudocode, exactly as published (32-bit arithmetic, wrapping):

```text
MurmurHash3_x86_32(key, len, seed):
  h1 = seed
  c1 = 0xCC9E2D51
  c2 = 0x1B873593

  for each full 4-byte block k1 (little-endian) in key:
    k1 = k1 * c1
    k1 = rotl32(k1, 15)
    k1 = k1 * c2
    h1 = h1 xor k1
    h1 = rotl32(h1, 13)
    h1 = h1 * 5 + 0xE6546B64

  k1 = 0
  tail = remaining 1..3 bytes
  if tail has 3 bytes: k1 = k1 xor (tail[2] << 16)
  if tail has 2 bytes: k1 = k1 xor (tail[1] << 8)
  if tail has 1 byte:  k1 = k1 xor tail[0]
                       k1 = k1 * c1
                       k1 = rotl32(k1, 15)
                       k1 = k1 * c2
                       h1 = h1 xor k1

  h1 = h1 xor len                 (uint32)
  h1 = fmix32(h1)
  return h1

fmix32(h):
  h = h xor (h >> 16)
  h = h * 0x85EBCA6B
  h = h xor (h >> 13)
  h = h * 0xC2B2AE35
  h = h xor (h >> 16)
  return h
```

All shifting/XORing is uint32 semantics. This package implements the
same steps with the arithmetic schemes of section 6.

## 5. Numeric representation

| Value | Domain |
|---|---|
| 32-bit word (`h1`, `k1`) | non-negative `Int` in `[0, 2^32)` |
| seed | any `Int`; reduced modulo `2^32` on entry |
| digest | non-negative `Int` in `[0, 2^32)` |
| streaming length | non-negative `Int`; folded as `length mod 2^32` |
| tail | 0..3 bytes, in stream order |

The empty buffer with seed 0 hashes to 0 because `fmix32(0) = 0`; a
digest of 0 is a legitimate hash value, not a sentinel.

Negative seeds are mapped into `[0, 2^32)` arithmetically (the residue is
shifted into range before the division), so `-1` means `0xFFFFFFFF` and
`-2^32` means 0, independent of the compiler's `%` sign convention.

## 6. Wrapping arithmetic (Int-only, exact)

The package never uses BigInt, FFI, or the compiler's overflow behavior,
and never applies a bitwise operator to a value that can have bit 31 set.

### 6.1 Wrapping multiply (`_mul32`)

Both operands are reduced to `[0, 2^32)` and split into 16-bit limbs:
`a = a1*2^16 + a0`, `b = b1*2^16 + b0`, with each limb in `[0, 65535]`.
The product terms below `2^32` are:

```text
t0 = a0*b0                    r0 = t0 mod 2^16      c0 = floor(t0 / 2^16)
t1 = a1*b0 + a0*b1 + c0       r1 = t1 mod 2^16
result = r1*2^16 + r0
```

Bounds: `t0 <= 65535^2 = 4 294 836 225 < 2^32`, `c0 <= 65534`, and
`t1 <= 2*65535^2 + 65534 = 8 589 737 984 < 2^33`. Every intermediate is
exact in Int64; the result is exactly `a*b mod 2^32`. Higher columns
(`a1*b1*2^32` and above) vanish modulo `2^32`.

### 6.2 Rotation (`_rotl32`, `murmur3_x86_32_rotl32`)

```text
rotl32(x, r) = (x * 2^r mod 2^32) + floor(x / 2^(32-r))
```

with `x` reduced to `[0, 2^32)` and `r` reduced to `[0, 31]`. The first
term holds bits `0..31-r` of `x` shifted into positions `r..31`; the
second holds bits `32-r..31` shifted into positions `0..r-1`. The two
terms occupy disjoint bit ranges, so their sum is the bitwise OR and the
rotated word, in `[0, 2^32)`.

Exactness: the product `x * 2^r` is at most `(2^32 - 1) * 2^31 < 2^63`,
so it is representable in Int; `2^r` and `2^(32-r)` are built by
multiplication loops. No `<<` or `>>` appears anywhere in the module.
`r` is reduced modulo 32 first (`-31` behaves as `1`, `63` as `31`), so
the function is total.

### 6.3 XOR and right shift

`_xor32(a, b)` splits both operands into 16-bit halves, applies `^` to
halves below `2^16`, and recombines with `* 65536 +`. `^` therefore never
sees a value with bit 31 set (the v0.61.3 hazard).

`h >> k` is `_rshift32(h, k) = h / 2^k` (floor division on a
non-negative `h`), used for the two `>> 16` and the one `>> 13` of the
avalanche.

### 6.4 Body and tail mixing

`_mix_block(h1, k1)` performs the four body steps with `_mul32`,
`_rotl32` and `_xor32`:

```text
k = _mul32(k1, c1); k = _rotl32(k, 15); k = _mul32(k, c2);
h = _xor32(h1, k); h = _rotl32(h, 13);
return (h*5 + 0xE6546B64) mod 2^32
```

`h*5 + 0xE6546B64 <= (2^32 - 1)*5 + 3 864 292 196 < 2^35`, exact in
Int; the final `% 2^32` wraps it. `_tail_mix(h1, k1)` is the same key
mixing without the `h1` rotation and multiply-add.

## 7. Tail handling

The body consumes only complete little-endian 4-byte blocks. The final
`len mod 4` bytes (0..3) are packed little-endian into a `k1` word:
`b0 + b1*2^8 + b2*2^16` (missing high bytes are zero). A non-empty tail
is mixed with `_tail_mix`; an empty tail is skipped entirely. The packed
value is below `2^24`, so it is unaffected by the wrapping multiply's
domain.

## 8. Streaming semantics

### 8.1 State and invariants

```text
Murmur3State { h1: Int; length: Int; tail: Vec[UInt8]; }
```

- `h1` in `[0, 2^32)`;
- `length >= 0` is the total number of bytes fed since init;
- `tail` holds exactly the last `length mod 4` bytes of the stream (0..3
  of them); the tail is what is left after every complete 4-byte block
  was mixed.

`murmur3_x86_32_state_is_valid` checks these predicates.

### 8.2 `init`

`murmur3_x86_32_init(seed)` returns `h1 = seed mod 2^32`, `length = 0`,
empty tail (satisfying the invariants).

### 8.3 `update`

`murmur3_x86_32_update(state, data)` mixes every byte of `data` in stream
order:

- if the state has `t` buffered bytes (1..3) and `data.len() >= 4 - t`,
  the buffered bytes plus the first `4 - t` data bytes form one complete
  block and are mixed immediately;
- every remaining complete 4-byte block of `data` is mixed in order;
- the final 0..3 bytes of `data` become the new tail;
- `length` grows by `data.len()`, `h1` is the running word.

If `data.len() < 4 - t`, the bytes are appended to the tail and no block
is mixed. Empty `data` is a no-op. The early-return path and the main
path store the same `length` growth.

### 8.4 `finalize`

`murmur3_x86_32_finalize(state)` mixes the buffered tail (if any) with
`_tail_mix`, folds `length mod 2^32` with `_xor32`, runs `_fmix32` and
returns the digest. It does not consume or modify the state, so it may be
called repeatedly for the same digest. It must not be followed by another
`update` (the tail has already been absorbed, and the state would no
longer be canonical); calling `update` after `finalize` is outside the
contract even though it cannot crash.

**Equality theorem.** For any split of a buffer `data` into
`data = c1 || c2 || ... || cn` and any seed:

```text
finalize(update(...update(update(init(seed), c1), c2)..., cn))
  == murmur3_x86_32(data, seed)
```

Both sides process the same complete blocks in the same order and the
same final tail, then apply the same length fold and avalanche. The
conformance suite checks this at every split point of several messages,
including empty chunks and nonzero seeds.

### 8.5 Error contract

`update` and `finalize` validate the state first and return
`Err("murmur3: invalid streaming state")` for a state that violates the
invariants (section 10). For any state built by `init` and advanced only
by `update`, the error is unreachable. A rejected `update` leaves the
state untouched.

## 9. API contract

```xi
pub type Murmur3State = {
  h1: Int;
  length: Int;
  tail: Vec[UInt8];
}

pub fn murmur3_x86_32(data: &Vec[UInt8], seed: Int) -> Int
pub fn murmur3_x86_32_init(seed: Int) -> Murmur3State
pub fn murmur3_x86_32_update(state: &mut Murmur3State, data: &Vec[UInt8]) -> Result[Unit, Str]
pub fn murmur3_x86_32_finalize(state: &Murmur3State) -> Result[Int, Str]
pub fn murmur3_x86_32_state_is_valid(state: &Murmur3State) -> Bool
pub fn murmur3_x86_32_state_h1(state: &Murmur3State) -> Int
pub fn murmur3_x86_32_state_length(state: &Murmur3State) -> Int
pub fn murmur3_x86_32_state_tail_len(state: &Murmur3State) -> Int
pub fn murmur3_x86_32_state_tail(state: &Murmur3State) -> Vec[UInt8]

pub fn murmur3_x86_32_rotl32(x: Int, r: Int) -> Int
pub fn murmur3_x86_32_hex(value: Int) -> Str

pub fn murmur3_x86_32_c1() -> Int
pub fn murmur3_x86_32_c2() -> Int
pub fn murmur3_x86_32_fmix_c1() -> Int
pub fn murmur3_x86_32_fmix_c2() -> Int
pub fn murmur3_x86_32_default_seed() -> Int
pub fn murmur3_x86_32_smhasher_seed() -> Int
pub fn murmur3_x86_32_smhasher_value() -> Int
```

Guarantees:

| Property | Statement |
|---|---|
| Determinism | Equal buffers and seeds produce equal digests; no hidden state. |
| One-shot == streaming | Both share the same block/tail/mix helpers; checked at every split point. |
| Empty input | `murmur3_x86_32(empty, 0) == 0`; streaming an empty stream `finalize`s to 0. |
| Result range | Digests and `rotl32` results are in `[0, 2^32)`, non-negative. |
| Seed arithmetic | Seeds are reduced modulo `2^32`, `-1` == `0xFFFFFFFF`. |
| Wrap exactness | Modular products are computed with bounded Int arithmetic only. |
| Rotation exactness | Rotations are the arithmetic identity of section 6.2, not shifts. |
| Totality | The one-shot function, helpers and accessors never fail; streaming rejects only forged states. |
| Purity | No FFI, no global state; allocation is limited to the tail buffer, the returned `Vec` copy and the returned `Str`. |

## 10. Error catalog

Exactly one error message exists:

| Message | Constructor | Raised by | Condition |
|---|---|---|---|
| `murmur3: invalid streaming state` | `_err_unit` / `_err_int` | `murmur3_x86_32_update`, `murmur3_x86_32_finalize` | `h1 < 0`, `h1 >= 2^32`, `length < 0`, or `tail.len() > 3` |

The message is deterministic; tests pin it with
`xiom.string.compare.str_compare`. `Ok`/`Err` values are constructed only
in the four leaf helpers (`_ok_unit`, `_err_unit`, `_ok_int`,
`_err_int`), per the v0.61.3 rules.

## 11. Test vectors

All expected values below were computed with two independent reference
implementations of the published algorithm (a Python port written with
struct packing, and a Node.js port written with `Math.imul` and shift
operators) and agree exactly. The smhasher `VerificationTest` value
independently reproduces the well-known `0xB0F57EE3`.

### 11.1 Canonical seed-0 vectors

| Input | Digest (hex) | Digest (decimal) |
|---|---|---|
| `""` | `0x00000000` | `0` |
| `"a"` | `0x3C2569B2` | `1009084850` |
| `"abc"` | `0xB3DD93FA` | `3017643002` |
| `"Hello, world!"` | `0xC0363E43` | `3224780355` |
| `"The quick brown fox jumps over the lazy dog"` | `0x2E4FF723` | `776992547` |
| `ff 00 80 7f 01` | `0x837747D0` | `2205632464` |
| 300 bytes, byte `k = k % 256` | `0x65CC68F3` | `1707895027` |
| 1000 x `0xFF` | `0x9D6195A3` | `2640418211` |

### 11.2 Length boundary vectors (`"abcdefgh"` prefixes)

| Bytes | Digest (hex) | Digest (decimal) |
|---|---|---|
| 0 | `0x00000000` | `0` |
| 1 (`"a"`) | `0x3C2569B2` | `1009084850` |
| 2 (`"ab"`) | `0x9BBFD75F` | `2613040991` |
| 3 (`"abc"`) | `0xB3DD93FA` | `3017643002` |
| 4 (`"abcd"`) | `0x43ED676A` | `1139631978` |
| 5 (`"abcde"`) | `0xE89B9AF6` | `3902511862` |
| 6 (`"abcdef"`) | `0x6181C085` | `1635893381` |
| 7 (`"abcdefg"`) | `0x883C9B06` | `2285673222` |
| 8 (`"abcdefgh"`) | `0x49DDCCC4` | `1239272644` |

This table exercises tail lengths 1, 2, 3, the empty tail after a block,
and the transition to a second block; it is the primary body/tail
boundary check.

### 11.3 Nonzero-seed vectors

| Input | Seed | Digest (hex) | Digest (decimal) |
|---|---|---|---|
| `""` | `1` | `0x514E28B7` | `1364076727` |
| `"a"` | `0xFFFFFFFF` (`-1`) | `0x2A684527` | `711476519` |
| `"abc"` | `1` | `0xAA75E9FF` | `2859854335` |
| `"abc"` | `0x9747B28C` (`2538058380`) | `0xC84A62DD` | `3360318173` |
| `"abc"` | `0xFFFFFFFF` (`-1`) | `0xFC80C2AF` | `4236296879` |
| `"Hello, world!"` | `1` | `0xAA5DC85B` | `2858272859` |
| `ff 00 80 7f 01` | `0xFFFFFFFF` | `0x4363163A` | `1130567226` |
| 300-byte ramp | `1` | `0x84C2BB4C` | `2227354444` |
| 300-byte ramp | `123456789` | `0x9C681440` | `2624066624` |
| 300-byte ramp | `0xFFFFFFFF` | `0x4BAD3B60` | `1269644128` |
| 43-byte sentence | `123456789` | `0x6F0F1461` | `1863259233` |

### 11.4 smhasher `VerificationTest` value

smhasher's verification protocol hashes each prefix of the byte ramp
`0x00..0xFF` with seed `256 - length`, writes the 256 digests
little-endian (1024 bytes) and hashes that array with seed 0. For
MurmurHash3 x86_32 the published result is:

| Protocol | Result |
|---|---|
| `VerificationTest` (256-prefix key schedule) | `0xB0F57EE3` (2968878819) |

The suite reproduces the whole protocol, so this one check exercises
hundreds of distinct lengths, seeds `1..256`, long multi-block inputs,
and the avalanche at once.

### 11.5 Rotation vectors

| Call | Result |
|---|---|
| `rotl32(0, 0)` | `0` |
| `rotl32(1, 0)` | `1` |
| `rotl32(0x80000000, 1)` | `0x00000001` (bit 31 set on input) |
| `rotl32(1, 31)` | `0x80000000` |
| `rotl32(0xFFFFFFFF, 16)` | `0xFFFFFFFF` |
| `rotl32(0x12345678, 16)` | `0x56781234` |
| `rotl32(0xDEADBEEF, 15)` | `0xDF77EF56` |
| `rotl32(0xDEADBEEF, 13)` | `0xB7DDFBD5` |
| `rotl32(0, 17)` | `0` |
| `rotl32(-1, 1)` | `0xFFFFFFFF` |
| `rotl32(1, 63)` | `0x80000000` (`r mod 32`) |
| `rotl32(1, -31)` | `2` |

### 11.6 Hex helper vectors

| Call | Result |
|---|---|
| `murmur3_x86_32_hex(0)` | `"00000000"` |
| `murmur3_x86_32_hex(4294967295)` | `"ffffffff"` |
| `murmur3_x86_32_hex(-1)` | `"ffffffff"` |
| `murmur3_x86_32_hex(4294967301)` | `"00000005"` |
| `murmur3_x86_32_hex(murmur3_x86_32("Hello, world!", 0))` | `"c0363e43"` |
| `murmur3_x86_32_hex(murmur3_x86_32("Hello, world!", 1))` | `"aa5dc85b"` |

## 12. Test matrix

`tests/test_conformance.xi` (`module murmur3_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Test dispatch is direct `tN()` calls -- no
`Vec[fn]` table, per the v0.61.3 compiler notes.

| # | Check | Covers |
|---|---|---|
| 1 | specification constants, canonical seeds, smhasher value | section 3 |
| 2 | `rotl32` pinned (bit-31 operands, r = 0/1/13/15/16/31, r mod 32, negative x and r) | section 6.2 |
| 3 | canonical seed-0 vectors: empty, `a`, `abc`, `Hello, world!` | sections 11.1 |
| 4 | nonzero-seed vectors incl. `0x9747B28C` and `-1` | section 11.3 |
| 5 | all lengths 0..8 of `"abcdefgh"` | section 11.2 |
| 6 | high-bit bytes `ff 00 80 7f 01` at seeds 0 and `-1`; `a` at `-1` | byte widening |
| 7 | 300-byte ramp at four seeds, 43-byte sentence at two, 1000 x `0xFF` | section 11.1/11.3 |
| 8 | smhasher `VerificationTest` value | section 11.4 |
| 9 | streaming at every split of `"Hello, world!"`, seeds 0 and 1 | split equality |
| 10 | streaming at every split of `"abcdefgh"`, seeds 0 and `123456789` | block/tail boundaries |
| 11 | byte-at-a-time streaming over the 300-byte ramp | split equality, long input |
| 12 | streaming with chunk sizes 1..7 and mixed seeds over 43 bytes | chunk granularity |
| 13 | state accessors: h1/length/tail, seed reduction, validity | section 8.1 |
| 14 | empty stream/updates, finalize repeatable and non-destructive | section 8.4 |
| 15 | invalid states rejected with the pinned message, state untouched | section 10 |
| 16 | hex helper pinned incl. `-1` and `2^32 + 5` | section 11.6 |
| 17 | determinism, seed sensitivity, input sensitivity | guarantees |
| 18 | seed reduction: `-1` == `0xFFFFFFFF`, `2^32 + 5` == `5`, `-2^32` == `0` | section 5 |

Test-fixture notes: `bytes_of` builds `Vec[UInt8]` with
`xiom.string.byte_at`; `chunk` slices a buffer for streaming;
`pattern_300`, `high_bytes`, `repeat_byte` and `ramp_256` mirror the
`xiom.crc`/`xiom.fnv` fixtures. Byte reads are always widened with
`(x as Int) & 255`. Every mutable state is passed with an explicit
`&mut` at the call site (trap 12), and readers follow updates in source
order so the advisory v0.61.3 borrow checker stays quiet. The only `Str`
comparisons are between `murmur3_x86_32_hex()` results and string
literals (`xiom.hello` pattern), or through
`xiom.string.compare.str_compare` for the error message, so BUG 17
(`==` on a `Str` read from a Vec) is unreachable.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.murmur3
```

Expected: `namespace-check` OK (1 module, 0 conflicts), 18 `[PASS]`
lines, `xiom.murmur3: all tests passed`, and
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## 13. Complexity

| Operation | Time | Space |
|---|---|---|
| `murmur3_x86_32(data, seed)` | O(data.len()) | O(1) |
| `murmur3_x86_32_update(state, data)` | O(data.len()) | O(1) plus the new tail (0..3 bytes) |
| `murmur3_x86_32_finalize(state)` | O(1) | O(1) |
| `murmur3_x86_32_rotl32(x, r)` | O(1): two power-of-two loops | O(1) |
| `_mul32` per multiply | O(1): two limb splits + two column steps | O(1) |
| `murmur3_x86_32_hex(value)` | O(1): 8 digit steps plus small Str concatenations | O(1) |
| accessors | O(1) (tail copy is at most 3 bytes) | O(1) |

The limb split and the division-based rotation are deliberately slower
than native 32-bit multiply/rotate instructions: they buy provable Int64
bounds under v0.61.3, not speed.

## 14. Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas, `Vec[fn]` dispatch or
  `Vec[StructType]`.
- `Murmur3State` is a plain struct; `Ok`/`Err` values are constructed
  only in the four leaf helpers (`_ok_unit`, `_err_unit`, `_ok_int`,
  `_err_int`). No struct-returning function constructs a `Result`.
- No bitwise operator sees a large operand: the only XORs are on 16-bit
  halves (`_xor32`) and the only `&` is the byte-widening mask
  `(b as Int) & 255` / `(b as Int) & 0xFF`. The multiply paths use
  `*`, `+`, `-`, `%`, `/` exclusively; rotations use `*`, `/`, `%`; right
  shifts use `/`.
- `%` and `/` are only applied to non-negative values (after residue
  adjustment in `_u32` and validation in `update`/`finalize`), so the
  code is correct under both truncating and flooring remainder
  semantics.
- Struct fields are copied to locals before use (`let buffered =
  state.tail`) and never passed to a `&Vec[UInt8]` parameter directly
  (the `&struct.field` trap).
- Tests pass `&mut state` explicitly at every call site; readers follow
  writers so the advisory E001 borrow check does not fire.
- `murmur3_x86_32_hex` builds strings from hex digits only, so no NUL
  byte can reach the string builder.
- The package declares no `extern "C"` blocks (no FFI).

## 15. Known limitations

- Non-cryptographic by design: no collision resistance, no
  authentication, no resistance to adversarial inputs.
- Only the x86_32 variant; no x86_128 or x64_128.
- Seeds are 32-bit (reduced modulo `2^32`).
- `finalize` must not be followed by `update` on the same state; the API
  documents the intended lifecycle (init -> update* -> finalize).
- The streaming tail is a small `Vec[UInt8]` field, so an update that
  crosses a block boundary allocates at most one small buffer; the
  one-shot path allocates nothing.
- The arithmetic rotation/multiply schemes are slower than native
  operators; they are a correctness device for compiler v0.61.3.

## 16. Verification

Last verified: compiler 0.61.3, via
`& .\scripts\port.ps1 -Package xiom.murmur3`:

```
port: PASS (passed=18 failed=0 program_exit=0 exit=0)
```

The harness-green run covers the canonical seed-0 and nonzero-seed
vectors, the length-boundary table, the smhasher `VerificationTest`
value, the rotation table, streaming/one-shot equality at every split
point, the state invariants, the single error path, and the hex display
helper.
