# xiom.zkp -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.zkp`, version `0.1.0`).
Module: `src/zkp.xi` (`module xiom.zkp`).
Depends on `xiom.std` (`xiom.string`, `xiom.convert`). No FFI. No sibling
package dependency.

## 1. Scope

Byte-level serialization structures for BLS12-381 Groth16/PLONK proof blobs:

```xi
pub fn zkp_bls12_381_modulus() -> Vec[UInt8]
pub fn zkp_fp_len() -> Int
pub fn zkp_fp_compare_modulus(data: &Vec[UInt8], offset: Int) -> Result[Int, Str]
pub fn zkp_fp_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_fp_is_modulus(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_fp2_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_fp_be_to_le(be: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn zkp_fp_le_to_be(le: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn zkp_fp2_be_to_le(be: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn zkp_point_length(kind: Int) -> Int
pub fn zkp_point_kind_name(kind: Int) -> Str
pub fn zkp_point_flags(kind: Int, data: &Vec[UInt8], offset: Int) -> Result[Int, Str]
pub fn zkp_point_summary(kind: Int, data: &Vec[UInt8], offset: Int) -> Result[Str, Str]
pub fn zkp_g1_compressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_g1_uncompressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_g2_compressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_g2_uncompressed_validate(data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_point_validate(kind: Int, data: &Vec[UInt8], offset: Int) -> Result[Bool, Str]
pub fn zkp_groth16_proof_len() -> Int
pub fn zkp_groth16_proof_decode(data: &Vec[UInt8]) -> Result[Groth16Proof, Str]
pub fn zkp_groth16_proof_validate(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn zkp_groth16_proof_a(p: &Groth16Proof) -> Vec[UInt8]
pub fn zkp_groth16_proof_b(p: &Groth16Proof) -> Vec[UInt8]
pub fn zkp_groth16_proof_c(p: &Groth16Proof) -> Vec[UInt8]
pub fn zkp_groth16_vk_len(ic_count: Int) -> Int
pub fn zkp_groth16_vk_decode(data: &Vec[UInt8], ic_count: Int) -> Result[Groth16Vk, Str]
pub fn zkp_groth16_vk_validate(data: &Vec[UInt8], ic_count: Int) -> Result[Bool, Str]
pub fn zkp_groth16_vk_alpha(vk: &Groth16Vk) -> Vec[UInt8]
pub fn zkp_groth16_vk_beta(vk: &Groth16Vk) -> Vec[UInt8]
pub fn zkp_groth16_vk_gamma(vk: &Groth16Vk) -> Vec[UInt8]
pub fn zkp_groth16_vk_delta(vk: &Groth16Vk) -> Vec[UInt8]
pub fn zkp_groth16_vk_ic_count(vk: &Groth16Vk) -> Int
pub fn zkp_groth16_vk_ic_point(vk: &Groth16Vk, i: Int) -> Result[Vec[UInt8], Str]
pub fn zkp_plonk_proof_len() -> Int
pub fn zkp_plonk_proof_point_name(i: Int) -> Str
pub fn zkp_plonk_proof_eval_name(i: Int) -> Str
pub fn zkp_plonk_proof_decode(data: &Vec[UInt8]) -> Result[PlonkProof, Str]
pub fn zkp_plonk_proof_validate(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn zkp_plonk_proof_g1(p: &PlonkProof, i: Int) -> Result[Vec[UInt8], Str]
pub fn zkp_plonk_proof_eval(p: &PlonkProof, i: Int) -> Result[Vec[UInt8], Str]
pub fn zkp_plonk_vk_len() -> Int
pub fn zkp_plonk_vk_point_name(i: Int) -> Str
pub fn zkp_plonk_vk_decode(data: &Vec[UInt8]) -> Result[PlonkVk, Str]
pub fn zkp_plonk_vk_validate(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn zkp_plonk_vk_omega(vk: &PlonkVk) -> Vec[UInt8]
pub fn zkp_plonk_vk_k1(vk: &PlonkVk) -> Vec[UInt8]
pub fn zkp_plonk_vk_k2(vk: &PlonkVk) -> Vec[UInt8]
pub fn zkp_plonk_vk_x2(vk: &PlonkVk) -> Vec[UInt8]
pub fn zkp_plonk_vk_n8(vk: &PlonkVk) -> Int
pub fn zkp_plonk_vk_g1(vk: &PlonkVk, i: Int) -> Result[Vec[UInt8], Str]
pub fn zkp_scheme_expected_len(scheme: Int) -> Int
pub fn zkp_scheme_name(scheme: Int) -> Str
pub fn zkp_scheme_detect(data: &Vec[UInt8]) -> Int
pub fn zkp_blob_validate(data: &Vec[UInt8]) -> Result[Bool, Str]
pub fn zkp_proof_hex_decode(text: Str) -> Result[Vec[UInt8], Str]
```

Decoded structures (flat; no `Vec[StructType]` inside them):

```xi
pub type Groth16Proof = { a: Vec[UInt8]; b: Vec[UInt8]; c: Vec[UInt8]; }
pub type Groth16Vk = { alpha: Vec[UInt8]; beta: Vec[UInt8]; gamma: Vec[UInt8];
                       delta: Vec[UInt8]; ic_count: Int; ic: Vec[UInt8]; }
pub type PlonkProof = { points: Vec[UInt8]; evals: Vec[UInt8]; }
pub type PlonkVk = { n8: Int; omega: Vec[UInt8]; k1: Vec[UInt8];
                     k2: Vec[UInt8]; x2: Vec[UInt8]; points: Vec[UInt8]; }
```

## 2. Non-goals

- **No curve arithmetic, no subgroup checks, no pairings, no hashing.** A
  point can pass every rule here and still not be on the curve; a blob can
  pass `zkp_blob_validate` and still be an invalid proof of nothing.
- **No Fr modulus.** PLONK evaluations are opaque 32-byte big-endian limbs;
  only their length is structural.
- **No proof-system semantics**: no A/B/C wiring equations, no IC evaluation,
  no public inputs, no transcript/Fiat-Shamir logic.
- **No encoders.** This package decodes and validates byte structures; it
  does not turn field elements or points back into bytes.
- **No JSON.** snarkjs-style JSON is not parsed; the inputs are raw bytes or
  hex text.

## 3. Encoding conventions

### 3.1 Fp (48 bytes, big-endian)

The BLS12-381 base field modulus is embedded as the 48 big-endian bytes of

```
p = 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab
```

(`zkp_bls12_381_modulus()` returns exactly these 48 bytes).

A 48-byte value is **canonical** iff it is strictly below p. Canonicality is
decided by a bytewise comparison from the most significant byte down (never
big-integer arithmetic): `zkp_fp_compare_modulus` returns `-1` (below), `0`
(exactly p) or `1` (above); `zkp_fp_validate` is `Ok(true)` only for `-1`.
Values with unused high bytes are fine (leading zeros are significant bytes
of the 384-bit integer, so `p` itself is `0x1a...` and any first byte `<
0x1a` is automatically below p).

Little-endian variants (arkworks-style serializers emit field elements
least-significant byte first) are supported by conversion only:
`zkp_fp_be_to_le` reverses the 48 bytes; `zkp_fp_le_to_be` is the same
operation (byte reversal is its own inverse); both reject any input that is
not exactly 48 bytes. No value changes: only the byte order.

### 3.2 Fp2 (96 bytes)

`Fp2 = c0 || c1`, each limb 48 bytes big-endian. A value is canonical iff
both limbs are canonical. `zkp_fp2_be_to_le` reverses each limb in place and
keeps the `c0`-first order (`reverse(c0) || reverse(c1)`).

### 3.3 Point flag bits (compressed forms)

The top byte `b0` of a compressed point carries three flag bits. They are
extracted with division/modulo only (no shifts):

| Flag | Value | Test |
|---|---|---|
| compression | `0x80` (128) | `b0 / 128` |
| infinity | `0x40` (64) | `(b0 / 64) % 2` |
| sort/sign | `0x20` (32) | `(b0 / 32) % 2` |

The x coordinate begins with `b0 % 32` (the top three bits cleared) followed
by the remaining bytes. `zkp_point_flags` returns the packed value
`compression * 4 + infinity * 2 + sign` (0..7) without judging legality;
`zkp_point_summary` renders it as
`"<kind> compression=C infinity=I sign=S"`, e.g.
`"G1 compressed compression=1 infinity=0 sign=1"`.

### 3.4 G1 compressed (48 bytes)

Layout: 48 bytes, top byte flags.

Rules (`zkp_g1_compressed_validate`):

1. Compression flag must be set; otherwise `Ok(false)`.
2. If the infinity flag is set: the sign flag must be clear, the x field
   (masked top byte plus bytes 1..47) must be all zero; otherwise `Ok(false)`.
   A legal infinity is `0xC0` followed by 47 zero bytes.
3. Otherwise (not infinity): the x field must be canonical (`< p`);
   `Ok(false)` when `>= p`.
4. `x = 0` *without* the infinity flag is a legal encoding (the BLS12-381
   curve has points with x = 0, namely (0, +/-2)); it is not treated as
   infinity.

### 3.5 G1 uncompressed (96 bytes)

Layout: `x || y`, 48 bytes each, big-endian.

Rules (`zkp_g1_uncompressed_validate`):

1. The top three bits of byte 0 must be cleared (`b0 / 32 == 0`); otherwise
   `Ok(false)`. (This also rejects a compressed first byte fed to the
   uncompressed parser.)
2. The all-zero 96 bytes are the infinity encoding -> `Ok(true)`.
3. Otherwise x must be canonical and y must be canonical; otherwise
   `Ok(false)`.

### 3.6 G2 compressed (96 bytes)

Layout: `x = c0 || c1`, each limb 48 bytes; flags live in the top byte of
`c0` (byte 0 of the buffer).

Rules (`zkp_g2_compressed_validate`):

1. Compression flag must be set.
2. If infinity: sign clear, c0 all zero (masked top byte) and c1 all zero.
   A legal infinity is `0xC0` followed by 95 zero bytes.
3. Otherwise c0 (with flags cleared) and c1 must both be canonical.

### 3.7 G2 uncompressed (192 bytes)

Layout: `x || y` = `c0 || c1 || c2 || c3`, 48 bytes per limb.

Rules (`zkp_g2_uncompressed_validate`):

1. The top three bits of byte 0 must be cleared.
2. The all-zero 192 bytes are the infinity encoding -> `Ok(true)`.
3. Otherwise all four limbs must be canonical.

### 3.8 Point kinds

| Tag constant | Value | Bytes | Layout |
|---|---|---|---|
| `ZKP_POINT_G1_COMPRESSED` | 0 | 48 | flags + x |
| `ZKP_POINT_G1_UNCOMPRESSED` | 1 | 96 | x \|\| y |
| `ZKP_POINT_G2_COMPRESSED` | 2 | 96 | flags + c0 \|\| c1 |
| `ZKP_POINT_G2_UNCOMPRESSED` | 3 | 192 | c0 \|\| c1 \|\| c2 \|\| c3 |

## 4. Groth16

### 4.1 Proof (192 bytes)

```
offset   length  field
0        48      A   compressed G1
48       96      B   compressed G2
144      48      C   compressed G1
```

`zkp_groth16_proof_decode` checks the total length only and returns copies.
`zkp_groth16_proof_validate` checks the total length (Err) and then the
compressed-point rules for A (G1), B (G2) and C (G1) (`Ok(false)` on a rule
violation). `zkp_groth16_proof_a/b/c` return 48/96/48-byte copies.

### 4.2 Verification key (variable length)

```
offset      length         field
0           48             alpha   compressed G1
48          96             beta    compressed G2
144         96             gamma   compressed G2
240         96             delta   compressed G2
336         48 * ic_count  IC points, each compressed G1
```

`zkp_groth16_vk_len(ic_count) = 336 + 48 * ic_count` (`-1` for a negative
count). **The IC count is supplied by the caller as context; this profile has
no count prefix on the wire.** `zkp_groth16_vk_decode(data, ic_count)`
requires exactly that length and flattens the IC points into one buffer;
`zkp_groth16_vk_ic_point(vk, i)` extracts point `i`; validation checks alpha
as G1, beta/gamma/delta as G2 and every IC point as G1.

## 5. PLONK (snarkjs-shaped binary profile)

This package defines one binary profile so the layouts are deterministic.
It is shaped like snarkjs' PLONK artifacts but is **a package-local
convention, not a bit-compatible snarkjs format** (see limitations).

### 5.1 Proof (528 bytes)

```
offset   length  part
0        48      A    compressed G1
48       48      B    compressed G1
96       48      C    compressed G1
144      48      Z    compressed G1
192      48      T1   compressed G1
240      48      T2   compressed G1
288      48      T3   compressed G1
336      48      W1   compressed G1
384      48      W2   compressed G1
432      32      a    evaluation (Fr limb)
464      32      b    evaluation (Fr limb)
496      32      c    evaluation (Fr limb)
```

Total 9 * 48 + 3 * 32 = 528. Chosen conventions: the nine commitments are
compressed G1 points validated by the G1 rules; the three evaluations are
opaque 32-byte big-endian limbs (no Fr modulus is embedded, so only the
length is enforced). `zkp_plonk_proof_point_name` gives A, B, C, Z, T1, T2,
T3, W1, W2; `zkp_plonk_proof_eval_name` gives a, b, c.

### 5.2 Verification key (580 bytes)

```
offset   length  part
0        4       n8    domain size, 4-byte little-endian u32
4        48      omega Fp slot (big-endian)
52       48      k1    Fp slot
100      48      k2    Fp slot
148      96      X_2   compressed G2
244      336     7 compressed G1 points (48 each)
```

Total 4 + 3 * 48 + 96 + 7 * 48 = 580. Chosen conventions:

- `n8` is a 4-byte little-endian u32, decoded to Int as
  `b0 + b1*256 + b2*65536 + b3*16777216` (snarkjs binary headers are
  little-endian).
- `omega`, `k1`, `k2` are full 48-byte Fp slots checked for canonicality.
  (snarkjs JSON stores these as Fr scalars; this profile uses the 48-byte Fp
  slot layout given in the package brief.)
- `X_2` is a compressed G2 point; the trailing 7 G1 points are named
  Qm, Ql, Qr, Qo, Qc, S1, S2 by `zkp_plonk_vk_point_name` (this package's
  7-point profile).

`zkp_plonk_vk_decode` checks the total length and decodes n8; 
`zkp_plonk_vk_validate` checks the length, the three Fp canonicalities, the
G2 rules for X_2 and the G1 rules for all 7 points.

## 6. Structural helpers

### 6.1 Expected lengths

| Scheme | Length |
|---|---|
| Groth16 proof | 192 |
| PLONK proof | 528 |
| Groth16 VK | 336 + 48 * ic_count |
| PLONK VK | 580 |

`zkp_scheme_expected_len(1) = 192`, `(2) = 528`, anything else `-1`.

### 6.2 Scheme detection

`zkp_scheme_detect` is length-based only:

- exactly 192 -> `ZKP_SCHEME_GROTH16` (1)
- exactly 528 -> `ZKP_SCHEME_PLONK` (2)
- anything else -> `ZKP_SCHEME_UNKNOWN` (0)

**Ambiguity (documented):** 192 bytes is also the uncompressed G2 point
length, and 96 bytes is both a compressed G2 and an uncompressed G1. 528 is
unique among the lengths in this package. Detection must only be applied to
buffers already known to be proof blobs; `zkp_blob_validate` then runs the
matching structural validator (`Ok(false)` for a rule violation, Err only
for an unknown length).

### 6.3 Validation semantics

Every `*_validate` function returns `Result[Bool, Str]` with a strict split:

- `Ok(true)` -- all structural rules hold;
- `Ok(false)` -- the buffer is present and the right length, but an encoding
  rule is violated (bad flags, non-canonical limb, ...);
- `Err(...)` -- the buffer is too short/wrong length or an argument is
  invalid (unknown kind, negative count). Err messages carry byte offsets.

Decode functions (`*_decode`) check total length only and copy the parts;
they perform no flag validation. This split lets callers separate "shape"
from "encoding rules".

## 7. Hex decode

`zkp_proof_hex_decode(text)`:

- `text` must start with `0x` or `0X` (the prefix occupies offsets 0 and 1);
  otherwise Err.
- Payload digits may be mixed case; the byte value is `hi * 16 + lo`.
- An odd number of payload digits is rejected before any digit is read.
- The first non-hex digit is reported with its offset counted from the start
  of `text` and its byte value.
- `"0x"` yields `Ok(empty)`.
- No whitespace, separators or underscores are accepted.

## 8. Error catalog

Messages are exact; `{}` marks the formatted parts. Every public Err uses
the literal prefix `zkp: `.

| # | Message | Trigger |
|---|---|---|
| 1 | `zkp: fp needs 48 bytes at offset {off}, have {have}` | `zkp_fp_compare_modulus`/`zkp_fp_validate`/`zkp_fp_is_modulus` with fewer than 48 bytes from `off`. |
| 2 | `zkp: fp2 needs 96 bytes at offset {off}, have {have}` | `zkp_fp2_validate` with fewer than 96 bytes from `off`. |
| 3 | `zkp: fp endian conversion needs 48 bytes, have {n}` | `zkp_fp_be_to_le`/`zkp_fp_le_to_be` on a buffer that is not 48 bytes. |
| 4 | `zkp: fp2 endian conversion needs 96 bytes, have {n}` | `zkp_fp2_be_to_le` on a buffer that is not 96 bytes. |
| 5 | `zkp: unknown point kind {k}` | Point helper called with a tag outside 0..3. |
| 6 | `zkp: g1 compressed needs 48 bytes at offset {off}, have {have}` | G1-compressed validator truncation. |
| 7 | `zkp: g1 uncompressed needs 96 bytes at offset {off}, have {have}` | G1-uncompressed validator truncation. |
| 8 | `zkp: g2 compressed needs 96 bytes at offset {off}, have {have}` | G2-compressed validator truncation. |
| 9 | `zkp: g2 uncompressed needs 192 bytes at offset {off}, have {have}` | G2-uncompressed validator truncation. |
| 10 | `zkp: {kind name} needs {need} bytes at offset {off}, have {have}` | `zkp_point_flags`/`zkp_point_summary` truncation (kind name from `zkp_point_kind_name`). |
| 11 | `zkp: groth16 proof needs 192 bytes at offset 0, have {n}` | Groth16 proof decode/validate length mismatch. |
| 12 | `zkp: groth16 vk ic count {i} is negative` | Negative `ic_count` in VK decode/validate. |
| 13 | `zkp: groth16 vk with {i} ic points needs {need} bytes at offset 0, have {n}` | Groth16 VK length mismatch. |
| 14 | `zkp: groth16 vk ic index {i} out of range (count {c})` | `zkp_groth16_vk_ic_point` index outside 0..c-1. |
| 15 | `zkp: groth16 vk ic buffer is shortened` | Stored IC buffer cannot hold point `i` (hand-built struct). |
| 16 | `zkp: plonk proof needs 528 bytes at offset 0, have {n}` | PLONK proof decode/validate length mismatch. |
| 17 | `zkp: plonk g1 index {i} out of range 0..8` | `zkp_plonk_proof_g1` index outside 0..8. |
| 18 | `zkp: plonk g1 point {i} is missing from the buffer` | Stored points buffer too short for point `i`. |
| 19 | `zkp: plonk eval index {i} out of range 0..2` | `zkp_plonk_proof_eval` index outside 0..2. |
| 20 | `zkp: plonk eval {i} is missing from the buffer` | Stored evals buffer too short for evaluation `i`. |
| 21 | `zkp: plonk vk needs 580 bytes at offset 0, have {n}` | PLONK VK decode/validate length mismatch. |
| 22 | `zkp: plonk vk g1 index {i} out of range 0..6` | `zkp_plonk_vk_g1` index outside 0..6. |
| 23 | `zkp: plonk vk g1 point {i} is missing from the buffer` | Stored points buffer too short for point `i`. |
| 24 | `zkp: unknown scheme for length {n} (expected 192 groth16 or 528 plonk)` | `zkp_blob_validate` on a length that is not 192 or 528. |
| 25 | `zkp: hex text must start with 0x` | Hex text without a `0x`/`0X` prefix (including `""` and 1-char inputs). |
| 26 | `zkp: hex payload length {p} is odd` | Odd number of hex digits after the prefix. |
| 27 | `zkp: hex invalid character at offset {off} (byte {b})` | First non-hex digit; `off` counts from the start of the text. |

Examples:

- (1): a 47-byte buffer -> `... at offset 0, have 47`; a 48-byte buffer at
  offset 1 -> `... at offset 1, have 47`.
- (5): tag 99 -> `zkp: unknown point kind 99`.
- (10): `zkp: G1 uncompressed needs 96 bytes at offset 0, have 48` when 48
  bytes are passed to the uncompressed kind.
- (13): 432 bytes with `ic_count = 3` -> `... needs 480 bytes at offset 0,
  have 432`.
- (14): `zkp: groth16 vk ic index 2 out of range (count 2)`.
- (27): `0xg0` -> `zkp: hex invalid character at offset 2 (byte 103)`.

## 9. Invariants

- `zkp_bls12_381_modulus()` is always the same 48 bytes and
  `zkp_fp_validate` of it is `Ok(false)`.
- `zkp_fp_le_to_be(zkp_fp_be_to_le(v))` equals `v` for every 48-byte `v`.
- For every decoded Groth16 proof, concatenating `a || b || c` reproduces the
  original 192-byte blob; likewise the 9 G1 points plus 3 evaluations
  reproduce the PLONK 528-byte blob.
- Any compressed x field `>= p` fails validation, including x = p itself;
  x = p - 1 passes.
- The all-zero uncompressed buffers are valid infinity encodings; compressed
  infinity requires the explicit `0xC0` flag byte.
- `zkp_scheme_detect` is pure length classification: the same 192 bytes are
  a Groth16 proof candidate and an uncompressed G2 point.

## 10. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `zkp_fp_compare_modulus(d, off)` | any buffer | `-1`/`0`/`1` vs p | (1) |
| `zkp_fp_validate(d, off)` | any buffer | canonical? | (1) |
| `zkp_fp_is_modulus(d, off)` | any buffer | exactly p? | (1) |
| `zkp_fp2_validate(d, off)` | any buffer | both limbs canonical? | (2) |
| `zkp_fp_be_to_le(v)` / `zkp_fp_le_to_be(v)` | 48 bytes | reversed copy | (3) |
| `zkp_fp2_be_to_le(v)` | 96 bytes | limb-wise reversed copy | (4) |
| `zkp_point_length(k)` | tag | 48/96/96/192 or -1 | none |
| `zkp_point_kind_name(k)` | tag | kind name or "" | none |
| `zkp_point_flags(k, d, off)` | tag + point | packed 0..7 | (5), (10) |
| `zkp_point_summary(k, d, off)` | tag + point | summary string | (5), (10) |
| `zkp_g1_compressed_validate(d, off)` | buffer | legal encoding? | (6) |
| `zkp_g1_uncompressed_validate(d, off)` | buffer | legal encoding? | (7) |
| `zkp_g2_compressed_validate(d, off)` | buffer | legal encoding? | (8) |
| `zkp_g2_uncompressed_validate(d, off)` | buffer | legal encoding? | (9) |
| `zkp_point_validate(k, d, off)` | tag + buffer | dispatch to the four | (5) + the kind's |
| `zkp_groth16_proof_decode(d)` | buffer | `Groth16Proof` | (11) |
| `zkp_groth16_proof_validate(d)` | buffer | structural verdict | (11) |
| `zkp_groth16_proof_a/b/c(p)` | decoded proof | 48/96/48-byte copies | none |
| `zkp_groth16_vk_len(ic)` | count | length or -1 | none |
| `zkp_groth16_vk_decode(d, ic)` | buffer + count | `Groth16Vk` | (12), (13) |
| `zkp_groth16_vk_validate(d, ic)` | buffer + count | structural verdict | (12), (13) |
| `zkp_groth16_vk_alpha/beta/gamma/delta(vk)` | VK | point copies | none |
| `zkp_groth16_vk_ic_count(vk)` | VK | count | none |
| `zkp_groth16_vk_ic_point(vk, i)` | VK + index | 48-byte copy | (14), (15) |
| `zkp_plonk_proof_decode(d)` | buffer | `PlonkProof` | (16) |
| `zkp_plonk_proof_validate(d)` | buffer | structural verdict | (16) |
| `zkp_plonk_proof_g1(p, i)` | proof + 0..8 | 48-byte copy | (17), (18) |
| `zkp_plonk_proof_eval(p, i)` | proof + 0..2 | 32-byte copy | (19), (20) |
| `zkp_plonk_proof_point_name(i)` | 0..8 | A..W2 or "" | none |
| `zkp_plonk_proof_eval_name(i)` | 0..2 | a/b/c or "" | none |
| `zkp_plonk_vk_decode(d)` | buffer | `PlonkVk` | (21) |
| `zkp_plonk_vk_validate(d)` | buffer | structural verdict | (21) |
| `zkp_plonk_vk_omega/k1/k2/x2(vk)` | VK | scalar/point copies | none |
| `zkp_plonk_vk_n8(vk)` | VK | domain size | none |
| `zkp_plonk_vk_g1(vk, i)` | VK + 0..6 | 48-byte copy | (22), (23) |
| `zkp_plonk_vk_point_name(i)` | 0..6 | Qm..S2 or "" | none |
| `zkp_scheme_expected_len(s)` | tag | 192/528/-1 | none |
| `zkp_scheme_name(s)` | tag | "groth16"/"plonk"/"unknown" | none |
| `zkp_scheme_detect(d)` | buffer | scheme tag by length | none |
| `zkp_blob_validate(d)` | buffer | detect + validate | (24) |
| `zkp_proof_hex_decode(text)` | hex text | bytes | (25), (26), (27) |

## 11. Test plan

`tests/test_conformance.xi` (module `zkp_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Buffers are built in-test; the modulus expectation is the
published hex literal decoded by a test-local reader (not read back from the
library). All `Str` equality uses `compare.str_compare` (BUG 17 discipline).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | modulus pin | 48 bytes, byte-equal to the published p hex literal |
| t2 | fp canonicality | zero and p-1 pass; exact p and 0xff..ff fail; offsets in Err |
| t3 | fp compare | -1/0/1 around p; `is_modulus` true only for exact p |
| t4 | fp endian | 48-byte reversal round-trips; LE modulus starts `...ab`; length Err |
| t5 | fp2 | c0/c1 canonicality; limb-wise LE conversion; length Errs |
| t6 | g1 compressed | canonical x under flags; x=p fails, x=p-1 passes; compression required |
| t7 | g1 infinity | 0xC0 + zero x passes; sign, x tail, masked-top variants fail |
| t8 | g1 uncompressed | x/y canonical; flags cleared; all-zero infinity |
| t9 | g2 compressed | both limbs canonical; infinity flag + zero limbs + no sign |
| t10 | g2 uncompressed | four limbs canonical; flags cleared; all-zero infinity |
| t11 | lengths/kinds/flags | 48/96/96/192/-1, kind names, packed flag values |
| t12 | summaries/dispatch | exact summary strings; `zkp_point_validate` dispatch |
| t13 | groth16 proof | 192-byte A\|\|B\|\|C decode, accessors round-trip, length Errs |
| t14 | groth16 negative | corrupted A/B/C -> `Ok(false)`; wrong length -> Err |
| t15 | groth16 vk | 336/432 lengths, IC accessors, negative count, corruption |
| t16 | plonk proof | 528 layout, point/eval accessors, names, corruption |
| t17 | plonk vk | 580 layout, n8=1024, accessors, bad omega, length Err |
| t18 | scheme detection | 192/528 tags, ambiguous 96 -> unknown, names, blob validate |
| t19 | hex decode | prefix forms, mixed case, odd length, bad digits with offsets |
| t20 | pipeline | hex -> bytes -> scheme -> decode -> accessors reconstruct the blob |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.zkp
# port: PASS (passed=20 failed=0 program_exit=0 exit=0)
```

## 12. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]` fields,
  no `Vec[fn]` dispatch, no `match` in the library.
- `Ok`/`Err` are constructed only in the leaf helpers
  (`_ok_bytes`/`_err_bytes`, `_ok_bool`/`_err_bool`, ... one pair per Result
  type).
- Every byte read is widened and masked: `(x as Int) & 0xFF`; `Vec[Int]`/
  `Vec[Str]` element reads are bound to typed locals.
- No bitwise shifts: flags use division/modulo by 128/64/32, the masked top
  byte is `b0 % 32`, the n8 u32 is `b0 + b1*256 + b2*65536 + b3*16777216`,
  and the 48-byte modulus comparison is a bytewise loop.
- `Vec[UInt8]` struct fields are read element-wise through the borrow; no
  accessor passes `&struct.field` to a `&Vec[UInt8]` parameter.
- No `==` on `Str` anywhere in the library; the test suite routes every
  string comparison through `xiom.string.compare.str_compare`.
- Number formatting uses `convert.int_to_string`; the test suite's hex
  encoder uses `int_to_base` from `xiom.convert.int`.

## 13. Known limitations

- **Serialization only** (section 2): structural validity is not
  cryptographic validity.
- **No Fr modulus**: PLONK evaluations are opaque 32-byte limbs.
- **PLONK profile is package-local** (section 5): the 48-byte Fp slots for
  omega/k1/k2 and the 7-point G1 tail are this package's conventions, not a
  bit-compatible snarkjs binary format.
- **Length ambiguity** in scheme detection (section 6.2).
- **No subgroup membership checks**; canonical coordinates and flag rules are
  the whole validation.
- **No encoders**, no JSON, no streaming; in-memory O(n).
