# xiom.zkp

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.2` on the XIOM registry.
> **Scope:** byte-level serialization structures for BLS12-381 zero-knowledge
> proof blobs: Fp/Fp2 encodings, compressed/uncompressed G1/G2 point flag
> rules, Groth16 and PLONK proof/verification-key layouts, structural
> validation and scheme detection. **No curve arithmetic, no subgroup checks,
> no pairings, no hashing and no proof verification.**
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.convert`; tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.convert.int`).

## What it is

`xiom.zkp` is a small, dependency-light codec for the wire shapes of
BLS12-381 Groth16 and PLONK proofs. It answers structural questions:

- Does this blob have the right byte length for the scheme?
- Is this 48-byte Fp value canonical (< the BLS12-381 modulus p)?
- Do the compression/infinity/sign flags form a legal point encoding?
- Which point is at which offset in a Groth16 proof, PLONK proof or
  verification key?

It deliberately does **not** answer "is this proof valid": there is no curve
math, no pairing, no subgroup check and no hashing here. A blob accepted by
`zkp_blob_validate` is structurally well-formed only; on-curve membership and
proof verification are out of scope.

## Install / use

```
xiom pkg install xiom.zkp@0.1.0
```

```xi
use xiom.zkp;
use xiom.io;

// Decode a 192-byte Groth16 proof (A G1 || B G2 || C G1).
let r = zkp_groth16_proof_decode(&proof_bytes);
if r.is_ok {
  let p: Groth16Proof = r.value;
  let a = zkp_groth16_proof_a(&p);   // 48-byte compressed G1 copy
  let b = zkp_groth16_proof_b(&p);   // 96-byte compressed G2 copy
  let c = zkp_groth16_proof_c(&p);   // 48-byte compressed G1 copy
}

// Structural checks (length + flags + canonical coordinates).
let v = zkp_blob_validate(&proof_bytes);
if v.is_ok {
  io.println("structurally valid: " + convert.bool_to_string(v.value));
}

// Hex form, offsets in error messages.
let hx = zkp_proof_hex_decode("0x1a0111ea...");
```

## API

| Function | Returns | Description |
|---|---|---|
| `zkp_bls12_381_modulus()` | `Vec[UInt8]` | The 48-byte big-endian BLS12-381 modulus p. |
| `zkp_fp_len()` | `Int` | `48`. |
| `zkp_fp_compare_modulus(data, offset)` | `Result[Int, Str]` | Bytewise compare of 48 bytes against p: `-1` below, `0` equal, `1` above. |
| `zkp_fp_validate(data, offset)` | `Result[Bool, Str]` | Canonical Fp (< p): `Ok(true)`/`Ok(false)`, Err on truncation. |
| `zkp_fp_is_modulus(data, offset)` | `Result[Bool, Str]` | Exact equality with p (boundary checks). |
| `zkp_fp2_validate(data, offset)` | `Result[Bool, Str]` | `c0 \|\| c1`, both limbs canonical. |
| `zkp_fp_be_to_le(be)` | `Result[Vec[UInt8], Str]` | 48-byte byte reversal (arkworks-style LE output). |
| `zkp_fp_le_to_be(le)` | `Result[Vec[UInt8], Str]` | The inverse direction (same reversal). |
| `zkp_fp2_be_to_le(be)` | `Result[Vec[UInt8], Str]` | Reverses each 48-byte limb, keeps c0-first order. |
| `zkp_point_length(kind)` | `Int` | Bytes for a `ZKP_POINT_*` tag (`-1` unknown). |
| `zkp_point_kind_name(kind)` | `Str` | `"G1 compressed"`, `"G1 uncompressed"`, `"G2 compressed"`, `"G2 uncompressed"`. |
| `zkp_point_flags(kind, data, offset)` | `Result[Int, Str]` | Packed flags: compression\*4 + infinity\*2 + sign. |
| `zkp_point_summary(kind, data, offset)` | `Result[Str, Str]` | e.g. `"G1 compressed compression=1 infinity=0 sign=1"`. |
| `zkp_g1_compressed_validate(data, offset)` | `Result[Bool, Str]` | 48-byte compressed G1 rules. |
| `zkp_g1_uncompressed_validate(data, offset)` | `Result[Bool, Str]` | 96-byte x \|\| y rules. |
| `zkp_g2_compressed_validate(data, offset)` | `Result[Bool, Str]` | 96-byte c0 \|\| c1 with flags rules. |
| `zkp_g2_uncompressed_validate(data, offset)` | `Result[Bool, Str]` | 192-byte x \|\| y rules. |
| `zkp_point_validate(kind, data, offset)` | `Result[Bool, Str]` | Dispatch on the kind tag. |
| `zkp_groth16_proof_len()` | `Int` | `192`. |
| `zkp_groth16_proof_decode(data)` | `Result[Groth16Proof, Str]` | Split A \|\| B \|\| C (length only). |
| `zkp_groth16_proof_validate(data)` | `Result[Bool, Str]` | Length + point rules for A, B, C. |
| `zkp_groth16_proof_a/b/c(p)` | `Vec[UInt8]` | Copies of the three point encodings. |
| `zkp_groth16_vk_len(ic_count)` | `Int` | `336 + 48 * ic_count` (`-1` negative). |
| `zkp_groth16_vk_decode(data, ic_count)` | `Result[Groth16Vk, Str]` | Fixed part + flat IC buffer; the IC count is context, not a prefix. |
| `zkp_groth16_vk_validate(data, ic_count)` | `Result[Bool, Str]` | Length + point rules for every part. |
| `zkp_groth16_vk_alpha/beta/gamma/delta(vk)` | `Vec[UInt8]` | Copies of the fixed key points. |
| `zkp_groth16_vk_ic_count(vk)` | `Int` | Stored IC point count. |
| `zkp_groth16_vk_ic_point(vk, i)` | `Result[Vec[UInt8], Str]` | IC point `i` (48-byte copy). |
| `zkp_plonk_proof_len()` | `Int` | `528`. |
| `zkp_plonk_proof_decode(data)` | `Result[PlonkProof, Str]` | 9 G1 points + 3 evaluations (length only). |
| `zkp_plonk_proof_validate(data)` | `Result[Bool, Str]` | Length + G1 rules for all 9 points. |
| `zkp_plonk_proof_g1(p, i)` | `Result[Vec[UInt8], Str]` | Point `i` (0..8). |
| `zkp_plonk_proof_eval(p, i)` | `Result[Vec[UInt8], Str]` | Evaluation `i` (0..2, 32 bytes). |
| `zkp_plonk_proof_point_name(i)` | `Str` | A, B, C, Z, T1, T2, T3, W1, W2. |
| `zkp_plonk_proof_eval_name(i)` | `Str` | a, b, c. |
| `zkp_plonk_vk_len()` | `Int` | `580`. |
| `zkp_plonk_vk_decode(data)` | `Result[PlonkVk, Str]` | n8 \|\| omega \|\| k1 \|\| k2 \|\| X_2 \|\| 7 G1. |
| `zkp_plonk_vk_validate(data)` | `Result[Bool, Str]` | Length + Fp/G2/G1 rules. |
| `zkp_plonk_vk_n8(vk)` | `Int` | Domain size from the 4-byte LE prefix. |
| `zkp_plonk_vk_omega/k1/k2/x2(vk)` | `Vec[UInt8]` | Copies of the scalar slots and X_2. |
| `zkp_plonk_vk_g1(vk, i)` | `Result[Vec[UInt8], Str]` | G1 point `i` (0..6). |
| `zkp_plonk_vk_point_name(i)` | `Str` | Qm, Ql, Qr, Qo, Qc, S1, S2. |
| `zkp_scheme_expected_len(scheme)` | `Int` | `192` Groth16, `528` PLONK, `-1` unknown. |
| `zkp_scheme_name(scheme)` | `Str` | `"groth16"`, `"plonk"`, `"unknown"`. |
| `zkp_scheme_detect(data)` | `Int` | Length-based detection; ambiguous lengths documented. |
| `zkp_blob_validate(data)` | `Result[Bool, Str]` | Detect + validate a proof blob. |
| `zkp_proof_hex_decode(text)` | `Result[Vec[UInt8], Str]` | `0x`/`0X`-prefixed hex; odd length rejected. |

Public constants: `ZKP_FP_LEN` (48), `ZKP_FP2_LEN` (96),
`ZKP_G1_COMPRESSED_LEN` (48), `ZKP_G1_UNCOMPRESSED_LEN` (96),
`ZKP_G2_COMPRESSED_LEN` (96), `ZKP_G2_UNCOMPRESSED_LEN` (192),
`ZKP_GROTH16_PROOF_LEN` (192), `ZKP_GROTH16_VK_FIXED_LEN` (336),
`ZKP_PLONK_PROOF_LEN` (528), `ZKP_PLONK_G1_COUNT` (9), `ZKP_PLONK_EVAL_LEN`
(32), `ZKP_PLONK_EVAL_COUNT` (3), `ZKP_PLONK_VK_LEN` (580),
`ZKP_PLONK_VK_G1_COUNT` (7), the `ZKP_POINT_*` kind tags, the `ZKP_SCHEME_*`
tags and the flag values `ZKP_FLAG_COMPRESSION` (128), `ZKP_FLAG_INFINITY`
(64), `ZKP_FLAG_SIGN` (32).

## Encoding rules in one screen

- **Fp** is 48 bytes big-endian. Canonicality is a bytewise compare against
  the embedded modulus p (most significant byte first); `>= p` is rejected.
  Little-endian toolchains (arkworks-style) use the byte-reversal helpers;
  Fp2 is `c0 || c1`.
- **Compressed points** put three flags in the top byte: compression `0x80`,
  infinity `0x40`, sign `0x20`; the x coordinate is the top byte with those
  bits cleared plus the remaining bytes. The compression flag is required.
- **Infinity** needs the flag, a zero x field, and the sign flag clear.
  `x = 0` *without* the infinity flag is a legal encoding (the curve points
  (0, +/-2)), not an error.
- **Uncompressed points** must have the three top bits cleared; the all-zero
  buffer is the infinity encoding; coordinates must be canonical.
- **Groth16** proof is `A(G1) || B(G2) || C(G1)` = 192 bytes; the
  verification key is `alpha(G1) || beta(G2) || gamma(G2) || delta(G2) || IC`
  with the IC count supplied by the caller.
- **PLONK** (this package's binary profile) proof is 9 compressed G1 points
  (432) plus 3 x 32-byte evaluations (96) = 528 bytes; the verification key
  is n8 (4-byte LE) || omega || k1 || k2 (48-byte Fp slots) || X_2 (96) ||
  7 G1 points (336) = 580 bytes.

See [SPEC.md](SPEC.md) for the byte-level layouts and the full error catalog.

## Tests

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.zkp
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Serialization only.** No curve arithmetic, no subgroup checks, no
  pairings, no hashing, no verification. Structurally valid does not mean
  cryptographically valid.
- **No Fr modulus.** PLONK evaluations are opaque 32-byte big-endian limbs;
  only their length is enforced.
- **PLONK VK profile is package-local.** It follows the layout in the package
  brief (48-byte Fp slots, 7 G1 points); snarkjs' own JSON/binary encodings
  differ in details, so this is not a bit-compatible snarkjs format.
- **Scheme detection is length-based** and ambiguous where lengths overlap
  (192 is also an uncompressed G2 point; 96 is both a compressed G2 and an
  uncompressed G1). Use it only on buffers known to be proof blobs.
- **No subgroup membership checks.** x and y canonicality is all the
  validation there is beyond the flag rules.
- **In-memory, O(n).** No streaming reader/writer.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
