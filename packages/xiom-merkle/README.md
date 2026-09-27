# xiom.merkle

> **Status:** IMPLEMENTED -- harness-green with compiler v0.61.3
> (`port: PASS (passed=22 failed=0)`); not published.
> **Scope:** a Merkle tree and inclusion proofs over caller-supplied leaf
> byte buffers, with RFC 6962-style domain-separated SHA-256.
> **Deps:** `xiom.std` (library: `xiom.string`, `xiom.string.builder`,
> `xiom.convert`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`). Pure XIOM, no FFI.

## What it is

`xiom.merkle` builds a binary Merkle tree over an ordered list of leaf byte
buffers and produces compact inclusion proofs:

- leaf hash `= SHA256(0x00 || leaf bytes)`, internal node
  `= SHA256(0x01 || left || right)` (RFC 6962 domain separation);
- the tree is built level by level; an odd node is **promoted** to the next
  level unchanged (never duplicated), which reproduces the RFC 6962
  split-at-the-largest-smaller-power-of-two tree shape;
- the empty tree root is `SHA256("")` (RFC 6962's `MTH({})`);
- roots are exposed as a 32-byte `Vec[UInt8]` and as lowercase hex;
- a proof is a sibling-hash list (bottom level first) plus the leaf index
  and the leaf count it was generated for; verification folds the leaf hash
  back up and compares against a caller-supplied root.

SHA-256 is implemented **inside this module** (FIPS 180-4) and is internal:
it is not exported as a general hash API. The stdlib alternatives were
rejected because `xiom.crypto.sha256` is FFI-backed (C runtime + `unsafe`)
and `xiom.crypto.sha` is the legacy `Vec[Int]` module explicitly marked
do-not-use-in-new-systems; this package stays pure XIOM.

## Non-goals (honest scope)

- No TLS wire serialization. RFC 6962 section 2.1.1's
  `leaf_index, tree_size, audit_path` framing is not implemented; proofs are
  exposed as the raw sibling list described in `SPEC.md`.
- No streaming/incremental tree: all leaves are materialized in one call.
- No tree persistence, no consistency proofs, no signatures (the RFC 6962
  STH signing layer is out of scope).
- No configurable hash function; SHA-256 is fixed.
- Not constant-time; do not use proof verification as a side-channel
  hardened primitive.

## API

| Function | Returns | Description |
|---|---|---|
| `merkle_hash_len()` | `Int` | 32, the digest length in bytes. |
| `merkle_hex(buf)` | `Str` | Lowercase hex of any byte buffer. |
| `merkle_leaf_hash(leaf)` | `Vec[UInt8]` | `SHA256(0x00 \|\| leaf)`; 32 bytes. |
| `merkle_internal_hash(l, r)` | `Result[Vec[UInt8], Str]` | `SHA256(0x01 \|\| l \|\| r)`; both children must be 32 bytes. |
| `merkle_tree_from_leaves(data, offsets)` | `Result[MerkleTree, Str]` | Build from flat bytes + offsets (leaf `i` is `data[offsets[i]..offsets[i+1]]`). |
| `merkle_leaf_count(t)` / `merkle_level_count(t)` | `Int` | Shape accessors. |
| `merkle_level_size(t, level)` | `Result[Int, Str]` | Nodes at a level (level 0 = leaves). |
| `merkle_level_hash(t, level, index)` | `Result[Vec[UInt8], Str]` | One node hash, for level-by-level checks. |
| `merkle_root(t)` | `Vec[UInt8]` | 32-byte root (`SHA256("")` for the empty tree). |
| `merkle_root_hex(t)` | `Str` | Lowercase 64-char root. |
| `merkle_proof_generate(t, leaf_index)` | `Result[MerkleProof, Str]` | Inclusion proof for one leaf. |
| `merkle_proof_verify(proof, leaf, root)` | `Result[Bool, Str]` | `Ok(true)` valid; `Ok(false)` mismatch; `Err` malformed proof. |
| `merkle_proof_leaf_index(proof)` | `Int` | Index the proof was generated for. |
| `merkle_proof_leaf_count(proof)` | `Int` | Leaf count of the source tree. |
| `merkle_proof_sibling_count(proof)` | `Int` | Number of sibling hashes. |
| `merkle_proof_sibling(proof, i)` | `Result[Vec[UInt8], Str]` | Sibling `i` (0-based, bottom level first), 32 bytes. |

`MerkleTree` and `MerkleProof` fields are documented in `src/merkle.xi` and
`SPEC.md`; construct trees and proofs through the functions above.

## Usage

```xi
use xiom.io;
use xiom.merkle;
use xiom.string;

// Leaves "hello" and "world" are the two slices of one flat buffer.
fn root_and_proof() -> Bool {
  let src = "helloworld";
  var data = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    data.push(string.byte_at(src, i));
    i = i + 1;
  }
  var offsets = Vec[Int].new();
  offsets.push(0);
  offsets.push(5);
  offsets.push(10);
  let built = merkle_tree_from_leaves(&data, &offsets);
  if !built.is_ok {
    return false;
  }
  let tree = built.value;
  let root = merkle_root(&tree);            // 32 bytes
  io.println(merkle_root_hex(&tree));       // 64 lowercase hex chars
  let proof = merkle_proof_generate(&tree, 1);
  if !proof.is_ok {
    return false;
  }
  // leaf 1 is "world": data[5..10)
  var leaf = Vec[UInt8].new();
  var j = 5;
  while j < 10 {
    leaf.push(data[j]);
    j = j + 1;
  }
  let res = merkle_proof_verify(&proof.value, &leaf, &root);
  if !res.is_ok {
    return false;
  }
  return res.value;                          // true: proof is valid
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 22 `[PASS]` lines, then `xiom.merkle: all tests passed`, exit 0.
From the repository root:

```
& .\scripts\port.ps1 -Package xiom.merkle
```

Last verified: compiler 0.61.3, twice in a row,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Implementation notes

- Pure XIOM, free functions only, no `Vec[StructType]`: the tree stores all
  level hashes in one flat byte buffer plus parallel level-size metadata.
- 32-bit SHA-256 words stay in `0..2^32-1` via `% 4294967296`; rotations are
  divisor/modulo, AND is `(a + b - (a XOR b)) / 2` and NOT is `2^32-1 - a`,
  so no raw 32-bit mask or `~` ever touches a value with bit 31 set
  (v0.61.3 trap; see `docs/COMPILER-FINDINGS.md`).
- The 64 SHA-256 round constants are built into a runtime `Vec[Int]`
  because module-level const arrays are mis-materialized by v0.61.3.
- See `SPEC.md` for the hashing rules, the proof format, the exact error
  catalog and the pinned test vectors.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
