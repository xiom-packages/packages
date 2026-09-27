# xiom.merkle -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.merkle`, version `0.1.0`).
Module: `src/merkle.xi` (`module xiom.merkle`).
Depends on `xiom.std`; the library imports `xiom.string`,
`xiom.string.builder` and `xiom.convert` (tests add `xiom.test`,
`xiom.io`, `xiom.string.compare`).

## 1. Scope

A binary Merkle tree over an ordered list of caller-supplied leaf byte
buffers, plus single-leaf inclusion proofs, using SHA-256 and RFC 6962
domain separation. Pure XIOM, no FFI, no I/O.

## 2. Non-goals

- RFC 6962 section 2.1.1's TLS wire encoding of proofs (see 6).
- Consistency proofs, Signed Tree Heads, certificate/transparency logs.
- Streaming or incremental construction; logs with more than `Int` leaves.
- A configurable hash function or a public general-purpose SHA-256 API
  (SHA-256 here is internal to the module).
- Constant-time behavior and side-channel hardening.
- Serialization of trees or proofs to bytes.

## 3. Data model

### Leaves and offsets

Leaves are supplied as one flat `Vec[UInt8]` plus an `offsets: Vec[Int]`:

- `offsets.len() == leaf_count + 1`;
- `offsets[0] == 0`;
- offsets are non-decreasing (`offsets[i] <= offsets[i + 1]`, so empty
  leaves are allowed);
- `offsets[offsets.len() - 1] == data.len()`.

Leaf `i` is `data[offsets[i] .. offsets[i + 1]]`. Empty leaves (equal
consecutive offsets) are valid and hash as `SHA256(0x00)`.

### `MerkleTree`

```xi
pub type MerkleTree = {
  leaf_count: Int;
  level_count: Int;
  level_sizes: Vec[Int];
  hashes: Vec[UInt8];
}
```

- `hashes` stores every level concatenated, level 0 (leaf hashes) first;
  each node occupies exactly 32 bytes; `hashes.len() == 32 *
  sum(level_sizes)`.
- `level_sizes[l]` is the node count of level `l`; the byte offset of
  level `l`'s first node is `32 * (level_sizes[0] + ... +
  level_sizes[l - 1])`.
- Level 0 has `leaf_count` nodes; the last level has exactly 1 node (the
  root); `level_count == level_sizes.len()`.
- The empty tree: `leaf_count == 0`, `level_count == 0`, both vectors
  empty. Its root is defined as `SHA256("")`.

### `MerkleProof`

```xi
pub type MerkleProof = {
  leaf_index: Int;
  leaf_count: Int;
  sibling_count: Int;
  siblings: Vec[UInt8];
}
```

- `siblings` is `sibling_count * 32` bytes; sibling `k` is at
  `siblings[k * 32 .. (k + 1) * 32]`.
- Siblings are ordered from the leaf's level upward (bottom level first).
- `leaf_count` is the leaf count of the tree the proof was generated from;
  it determines the fold shape during verification.
- Levels at which the path node has no sibling (odd-node promotion)
  contribute no entry, so `sibling_count` depends on the leaf index and
  the tree shape.

## 4. Hashing rules

For a digest length of 32 bytes (`merkle_hash_len()`):

```
leaf_hash(leaf)      = SHA256(0x00 || leaf bytes)
internal(left, right) = SHA256(0x01 || left || right)
```

`internal` requires both children to be exactly 32 bytes (enforced by
`merkle_internal_hash`). SHA-256 is FIPS 180-4, implemented inside the
module and **internal**: it is not exported. It is documented as internal
because the stdlib candidates are unsuitable for a pure-XIOM package:
`xiom.crypto.sha256` is FFI-backed (C runtime, `unsafe`) and
`xiom.crypto.sha` is the deprecated legacy `Vec[Int]` module.

### Tree construction (level by level)

Level 0 is the list of leaf hashes in input order. To reduce a level with
`count` nodes: pair nodes `(0,1), (2,3), ...` and hash each pair as
`internal(left, right)`; if `count` is odd, the last node is **promoted
unchanged** to the next level. Repeat until one node remains; that is the
root.

Promotion is not duplication: the promoted node's hash is copied, never
re-hashed as `internal(n, n)`. This is what RFC 6962 does: its recursive
definition `MTH(D[n]) = SHA256(0x01 || MTH(D[0:k]) || MTH(D[k:n]))` with
`k` the largest power of two smaller than `n` produces exactly the same
tree as this iterative odd-promotion rule (checked for every `n` in the
tested range 1..7, and the rules coincide by induction: the left subtree
always has the largest power-of-two smaller than `n` leaves, and the
right-subtree spine is exactly the promoted-node chain).

### Empty tree

`merkle_root` of the empty tree is `SHA256("")` =
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
`merkle_root`, `merkle_root_hex` and all tree accessors work; only
`merkle_proof_generate` errors (there is no leaf to prove).

### Deviations from RFC 6962 (explicit)

1. Only section 2.1 (hash rules, empty tree, tree shape) is implemented.
   The TLS-serialized `SignedCertificateTimestamp`/audit-path framing of
   section 2.1.1 is **not** implemented: a proof is a raw sibling hash
   list plus `leaf_index`/`leaf_count`, not
   `u64 leaf_index || u64 tree_size || h[0] || h[1] || ...`.
2. The promotion rule is expressed iteratively (per level) rather than as
   the RFC's recursive power-of-two split; the resulting trees are
   identical (see above).
3. No signatures, no consistency proofs, no log integration.

## 5. Level shapes and pinned vectors

Sizes per level for the tested shapes (`level_sizes`):

| leaves n | level sizes | root (hex, leaf sets below) |
|---|---|---|
| 0 | (none; root = SHA256("")) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| 1 | [1] | `022a6979e6dab7aa5ae4c3e5e45f7e977112a7e63593820dbec1ec738a24f93c` |
| 2 | [2, 1] | `b137985ff484fb600db93107c77b0365c80d78f5b429ded0fd97361d077999eb` |
| 3 | [3, 2, 1] | `36642e73c2540ab121e3a6bf9545b0a24982cd830eb13d3cd19de3ce6c021ec1` |
| 4 | [4, 2, 1] | `33376a3bd63e9993708a84ddfe6c28ae58b83505dd1fed711bd924ec5a6239f0` |
| 5 | [5, 3, 2, 1] | `fe14a5426fbd70c0fa73f52342afed0da0bd23c4838662ccf6b88a3070ead97b` |
| 6 | [6, 3, 2, 1] | `e069fc12e231ccfd4516bf1617945fb3ccd5cc8910d92d6265289f088f777fdd` |
| 7 | [7, 4, 2, 1] | `4ae191939f548d9934740b88dea2c5cb89bb8870fc4505cd79dec6bbfaaee9cb` |

Roots above are for one-byte leaves: `n` leaves are the first `n` ASCII
letters `a`, `b`, `c`, ... (`"a"`, `"ab"`, `"abc"`, ... in one buffer,
offsets `0..n`). They were computed independently (Python `hashlib`, RFC
6962 rules) and are pinned in `tests/test_conformance.xi`.

Pinned leaf-hash vectors (SHA-256 exercised through `merkle_leaf_hash`):

| leaf bytes | leaf hash (hex) |
|---|---|
| empty | `6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d` |
| `"abc"` | `609f6e36d2405585188d5cfd761f407c7cc46a7d3f314c88270469dde315fcd1` |
| 55 x `'a'` (0x00 prefix makes a 56-byte message: one-block boundary) | `2f96780fb415b287dd95897a04ef96fde6a5f5b0c771d0a1175543bc3250718e` |
| 56 x `'a'` (57-byte message: crosses into the second block) | `4632d4b47c0932896996fe232ae65a5af500608fabd0bdbfbb6856795eaf9d85` |

## 6. Proof format and verification

### Generation (`merkle_proof_generate(tree, leaf_index)`)

Walk from level 0 to the level below the root, tracking the running node
index `idx` (starts at `leaf_index`) and level size `size`:

- if `idx` is odd: the node is a right child; record the node at
  `idx - 1` (its left sibling);
- else if `idx + 1 < size`: the node is a left child with a right sibling;
  record the node at `idx + 1`;
- else: the node is promoted at this level; record nothing.

Then `idx = idx / 2` and `size = ceil(size / 2)`.

`merkle_proof_sibling_count` therefore varies with the leaf index; for a
7-leaf tree the counts are `[3, 3, 3, 3, 3, 3, 2]` for leaves `0..6`.

### Verification (`merkle_proof_verify(proof, leaf, root)`)

1. Structural checks (all `Err`, see section 7): `leaf_count > 0`,
   `0 <= leaf_index < leaf_count`, `sibling_count >= 0`,
   `siblings.len()` is a multiple of 32 and equals `32 * sibling_count`.
2. `h = merkle_leaf_hash(leaf)`. If `root.len() != 32`, return
   `Ok(false)` (a wrong-length root cannot match).
3. Fold: with `idx = leaf_index`, `size = leaf_count`, `consumed = 0`,
   while `size > 1`:
   - if `idx` is odd: take the next sibling `s`, `h = internal(s, h)`;
   - else if `idx + 1 < size`: take the next sibling `s`,
     `h = internal(h, s)`;
   - else: promoted node, take nothing;
   - if a sibling is needed but none remains, return `Ok(false)`;
   - `idx = idx / 2`, `size = ceil(size / 2)`.
4. If `consumed != sibling_count`, return `Ok(false)` (wrong proof
   length for this shape).
5. Return `Ok(h == root)`.

Rejections to expect:

| Tampering | Result |
|---|---|
| wrong leaf bytes | `Ok(false)` |
| wrong root (any byte, including a 31-byte root) | `Ok(false)` |
| tampered sibling hash | `Ok(false)` |
| reordered siblings | `Ok(false)` |
| valid proof re-labelled with a different `leaf_index` | `Ok(false)` |
| `sibling_count` inconsistent with `siblings.len()` | `Err` |
| `siblings.len()` not a multiple of 32 | `Err` |
| `leaf_count <= 0`, `leaf_index` out of range, negative count | `Err` |

## 7. Error catalog

Every error message is deterministic. Messages that name an index or
offset carry it inline.

### `merkle_tree_from_leaves`

| Condition | Message |
|---|---|
| `offsets.len() == 0` | `merkle: offsets must be non-empty` |
| `offsets[0] != 0` | `merkle: offsets[0] must be 0 (got V)` |
| first decrease at `i` | `merkle: offsets[i]=V is below offsets[i-1]=W` |
| last offset `!= data.len()` | `merkle: offsets[j]=V must equal data length L` |

### `merkle_internal_hash`

| Condition | Message |
|---|---|
| `left.len() != 32` or `right.len() != 32` | `merkle: internal hash children must be 32 bytes each (left L, right R)` |

### `merkle_level_size`

| Condition | Message |
|---|---|
| empty tree | `merkle: tree has no levels (empty tree)` |
| level outside `0..level_count-1` | `merkle: level L out of range 0..H` |

### `merkle_level_hash`

| Condition | Message |
|---|---|
| empty tree | `merkle: tree has no levels (empty tree)` |
| level outside range | `merkle: level L out of range 0..H` |
| node outside `0..size-1` | `merkle: node I out of range at level L (size S)` |

### `merkle_proof_generate`

| Condition | Message |
|---|---|
| empty tree | `merkle: empty tree has no inclusion proofs` |
| `leaf_index` outside `0..leaf_count-1` | `merkle: leaf index I out of range 0..M` |

### `merkle_proof_verify`

| Condition | Message |
|---|---|
| `leaf_count <= 0` | `merkle: proof leaf count L must be positive` |
| `leaf_index` outside range | `merkle: proof leaf index I out of range 0..M` |
| `sibling_count < 0` | `merkle: proof sibling count C is negative` |
| `siblings.len() % 32 != 0` | `merkle: proof siblings length N is not a multiple of 32` |
| `siblings.len() / 32 != sibling_count` | `merkle: proof sibling count C does not match siblings length N` |

### `merkle_proof_sibling`

| Condition | Message |
|---|---|
| `i` outside `0..sibling_count-1` | `merkle: sibling index I out of range 0..M` |
| buffer shorter than declared count | `merkle: sibling I is missing from the proof buffer` |

Functions not listed above (`merkle_hash_len`, `merkle_leaf_count`,
`merkle_level_count`, `merkle_hex`, `merkle_leaf_hash`, `merkle_root`,
`merkle_root_hex`, the proof accessors) have no error case.

## 8. Complexity

| Operation | Complexity |
|---|---|
| `merkle_leaf_hash` | O(leaf.len()) |
| `merkle_internal_hash` | O(1) (one SHA-256 over 65 bytes) |
| `merkle_tree_from_leaves` | O(data.len() + n) time, n leaf hashes, O(n) memory |
| `merkle_root` / `merkle_root_hex` | O(level_count + 32) |
| `merkle_level_size` / `merkle_level_count` / `merkle_leaf_count` | O(1) |
| `merkle_level_hash` | O(level_count + 32) |
| `merkle_proof_generate` | O(level_count) |
| `merkle_proof_verify` | O(log n) hashes |
| `merkle_proof_sibling` | O(32) |

`n` is the leaf count; `level_count == 1 + floor(log2(n))` for `n >= 1`.

## 9. Test plan

`tests/test_conformance.xi` (`module merkle_tests`, 22 named tests,
hello-style printer returning the failure count). Coverage:

1. hash length and hex rendering (empty, single byte, 0x00/0xFF bytes);
2. empty tree: root `SHA256("")`, counts, proof rejection;
3. leaf-hash vectors: empty, `"abc"`, 55/56-byte padding boundary;
4. one-leaf tree: root == leaf hash, empty proof, level shape;
5. two-leaf tree: levels and both proofs checked against independently
   recomputed hashes;
6. three-leaf tree: promotion, level 1 == `[internal(a,b), leaf c]`;
7. seven-leaf tree: full level-by-level recomputation and pinned root;
8. four/five/six-leaf shapes and promotion chains, pinned roots;
9. offset error catalog (empty, first != 0, decrease, end mismatch);
10. empty leaves via equal consecutive offsets;
11. level accessor error catalog;
12. `merkle_internal_hash` rejects 31/33-byte children with lengths, and
    is order-sensitive;
13. inclusion proofs round-trip for all 7 leaves, sibling counts
    `[3,3,3,3,3,3,2]`;
14. five-leaf promotion: leaf 4 has exactly one sibling;
15. tampered leaf -> `Ok(false)`;
16. tampered/short root -> `Ok(false)`;
17. tampered/reordered siblings -> `Ok(false)`;
18. wrong `leaf_index` -> `Ok(false)`; out-of-range generate -> `Err`;
19. structural proof `Err` catalog (counts, lengths, ranges);
20. proof accessors match independently recomputed levels;
21. root hex is lowercase (`64` chars), deterministic, order-sensitive;
22. shapes 1..7: leaf count, leaf level size, single root.

All inputs are built in-test; nothing reads files or the environment. Str
comparisons go through `compare.str_compare` on typed locals (BUG 17
discipline).

The optional 1,000,000 x `'a'` SHA-256 vector is not pinned: the three
mandatory vectors (empty, `"abc"`, 55/56-byte padding boundary) are
covered above, and multi-block behavior is already exercised by every
56/57-byte leaf message and by every internal node (65-byte message, two
compressed blocks).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.merkle
```

Last verified: compiler 0.61.3, twice in a row,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## 10. Known limitations

- Proofs are not wire-encoded; callers serializing them must define their
  own framing (the RFC 6962 TLS framing is deliberately out of scope).
- No consistency proofs or multi-proof batching; generating `n` proofs is
  O(n) sibling copies, not O(n) hashes.
- SHA-256 is unkeyed; this module provides integrity against accidental
  tampering of a known root, not authentication.
- All state is in memory; there is no streaming tree builder.
- `merkle_proof_verify` returns `Err` only for malformed proof structure;
  any cryptographic mismatch is `Ok(false)`.

## 11. Compiler / stdlib notes for v0.61.3

- Free functions only; no methods, lambdas or `Vec[fn]` dispatch; no
  `Vec[StructType]` (tree levels are a flat `Vec[UInt8]` plus parallel
  `Vec[Int]` metadata; the two are pushed in lockstep, trap 16).
- SHA-256 32-bit arithmetic avoids every known bad lowering: no `&` with a
  32-bit mask, no `~`, no bit tests on values with bit 31 set. Rotations
  are divisor/modulo; AND is `(a + b - (a XOR b)) / 2`; NOT is
  `2^32 - 1 - a`; all additions reduce with `% 4294967296`.
- The 64 round constants are built into a runtime `Vec[Int]`: module-level
  const arrays are mis-materialized by this compiler (see the
  `xiom.crypto` SHA-512 note and `xiom.compress.gzip`).
- `&struct.field` is never passed to a `&Vec[UInt8]` parameter; hash bytes
  are copied into local `Vec`s first (trap 4).
- No `&mut Int` out-parameters anywhere: `_compress_block` returns the new
  8-word state; in-place `h = f(h)` updates go through a fresh local.
- Every `UInt8` read is widened and masked: `(x as Int) & 0xFF` (trap 3).
- Ceiling division uses the remainder form `q = a / b; if a % b > 0 { q =
  q + 1 }` (trap 18); all numerators are non-negative.
- The package declares no `extern "C"` block (no FFI) and builds no
  module-level tables.
