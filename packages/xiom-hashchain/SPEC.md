# xiom.hashchain -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.62.1; not
published).
Manifest: `package.xi` (`xiom.hashchain`, version `0.1.0`).
Module: `src/hashchain.xi` (`module xiom.hashchain`).
Depends on `xiom.std`; the library imports `xiom.string` and `xiom.convert`
(tests add `xiom.test`, `xiom.io`, `xiom.string.compare`).

## 1. Scope

An append-only chain of hash-linked record blocks over caller-supplied byte
buffers: deterministic 32-byte SHA-256 block digests, a zero-prev genesis
rule, explicit prev links, block/traversal accessors, and whole-chain
integrity verification that reports the FIRST broken index. Pure XIOM, no
FFI, no I/O, no clock.

## 2. Non-goals

- Consensus, distributed agreement, proof-of-work, signatures,
  authentication, tamper-proofing against a full-chain rewriter.
- Detecting prefix truncation (dropping trailing blocks) without an
  externally pinned tip digest.
- Payload privacy/encryption; payloads are stored verbatim.
- Serialization to bytes, persistence, streaming; no incremental digest
  caching (chains are values, so each append copies).
- A configurable hash function or a public general-purpose SHA-256 API
  (SHA-256 here is internal to the module).
- Constant-time behavior and side-channel hardening.
- `Vec[Vec[UInt8]]` payload storage; payloads are flattened (see 3).

## 3. Data model

### Chain layout (parallel Vec fields)

```xi
pub type HashChain = {
  count: Int;
  payload_offsets: Vec[Int];
  payload_bytes: Vec[UInt8];
  prev_digests: Vec[UInt8];
  digests: Vec[UInt8];
}
```

- `count` is the number of blocks. Block `i` (`0 <= i < count`) consists of:
  - payload: `payload_bytes[payload_offsets[i] .. payload_offsets[i + 1]]`,
    possibly empty;
  - `prev_digests[i * 32 .. (i + 1) * 32]`: the 32-byte digest of block
    `i - 1` (block 0 commits to the zero digest);
  - `digests[i * 32 .. (i + 1) * 32]`: the block's own 32-byte digest.
- There is no `Vec[Vec[UInt8]]` and no `Vec[StructType]` anywhere: payloads
  live in one flat buffer addressed by `payload_offsets`.

### Structural invariants

A chain is **well formed** when:

1. `count >= 0`;
2. `payload_offsets.len() == count + 1`;
3. `prev_digests.len() == count * 32`;
4. `digests.len() == count * 32`;
5. `payload_offsets[0] == 0`;
6. offsets are non-decreasing (`payload_offsets[i] <= payload_offsets[i+1]`,
   so empty payloads are equal consecutive offsets);
7. `payload_offsets[count] == payload_bytes.len()`.

All chains produced by `chain_new`, `chain_append` and `chain_from_payloads`
satisfy these invariants. `chain_verify` re-checks all of them before any
per-block check.

### Empty chain and genesis

- The **empty chain** is `count == 0`, `payload_offsets == [0]`,
  `payload_bytes`, `prev_digests` and `digests` all empty. It is trivially
  consistent (`chain_verify` returns `Ok(true)`).
- Block 0 is the **genesis block**. Genesis rule: `prev_digests[0..32]` must
  be the 32 zero bytes. `chain_from_payloads` and the first `chain_append`
  on the empty chain construct it this way; `chain_verify` enforces it.
- A chain is appended with `chain_append(chain, payload)`:
  - `count == 0` -> new block 0 with prev digest = 32 zero bytes;
  - otherwise -> new block `count` with
    `prev_digests[count] = digests[count - 1]`.
  The input chain is not modified; a fresh chain is returned.

### Build from flattened payloads

`chain_from_payloads(data, offsets)` uses the same offset rules with
`data` in place of `payload_bytes`; `offsets.len() - 1` blocks are built in
order, each linking the previous one, starting from the zero prev digest.
Offsets are validated first (see 6), so `Ok` chains are well formed.

## 4. Digest construction

### Preimage

For a block with previous digest `P` (32 bytes) and payload bytes `X`
(arbitrary length `L >= 0`):

```
preimage = D || P || uint64_be(L) || X
digest   = SHA256(preimage)
```

where `D` is the 23-byte ASCII domain separator `"xiom.hashchain.v1.block"`.

- `D` domain-separates these digests from every other SHA-256 use.
- The explicit 64-bit big-endian length makes the preimage unambiguous: two
  different payload splits of the same byte run hash differently
  (pinned in test `digest construction`).
- SHA-256 output is 32 bytes; `chain_digest_size()` returns 32.
- Genesis block digest: `chain_compute_digest(zeros32, payload_0)`.
- Determinism rule: the digest depends only on `P` and `X` — no clock, no
  IO, no randomness, no ambient state. Same inputs -> same digests; this
  holds across chains, processes and builds.

`chain_compute_digest(prev_digest, payload)` exposes the recomputation to
callers (used by tests and by external verifiers); it requires
`prev_digest.len() == 32`.

### SHA-256 provenance

SHA-256 is implemented inside the module as the private `_hc_sha256`
(FIPS 180-4): message schedule, 64 rounds, round constants built at runtime,
padding including the empty-input case. It mirrors the private `_sha256` of
`packages/xiom-merkle/src/merkle.xi` (same construction, renamed helpers,
adapted to the v0.62.x compiler), which is KAT-verified against FIPS 180-4
vectors.

The stdlib path was checked first and is not usable from packages:

- `xiom.crypto.sha256` (`E:\xiom-lang\stdlib\xiom\crypto\crypto.xi`) is
  FFI-backed: it wraps `unsafe { xiom_sha256_hash(...) }`.
- Under v0.62.0 and v0.62.1 the package test pipeline fails to link it:
  `lld-link: error: undefined symbol: xiom_sha256_hash`.
- The alternative `xiom.crypto.sha` is the legacy `Vec[Int]` module marked
  do-not-use-in-new-systems.

`_hc_sha256` is private (not exported). 32-bit words stay in `0..2^32-1`
using `% 4294967296` arithmetic; rotations are divisor/modulo; AND is
`(a + b - (a XOR b)) / 2`; NOT is `2^32 - 1 - a`; every `UInt8` read is
widened and masked (`(x as Int) & 0xFF`), so no raw 32-bit mask or `~` ever
touches a value with bit 31 set.

## 5. Verification algorithm

`chain_verify(chain) -> Result[Bool, Str]` checks, in this exact order:

1. **Structure**: invariants 1-7 of section 3, in the order: count,
   offsets length, prev_digests length, digests length, then the offset table
   (non-empty, `[0] == 0`, non-decreasing, last == payload length).
2. For each block `i` in `0..count-1`, in order:
   1. **Genesis rule** (`i == 0`): `prev_digests[0..32]` is all zero.
   2. **Prev link** (`i > 0`):
      `prev_digests[i*32..] == digests[(i-1)*32..]`.
   3. **Content**: recompute
      `d = SHA256(D || prev_digests[i] || uint64_be(len) || payload_i)` and
      require `d == digests[i]`.

The first failed check returns `Err(message)`. Because blocks are checked in
order, the message names the **first broken index**:

- a tampered payload or stored digest is reported at its own block `i`
  (content check), unless an earlier block is already broken;
- a tampered prev digest is reported at block `i` (link check), except at
  block 0 where the genesis rule fires first;
- reordering payloads between blocks `i` and `j` is reported at `min(i, j)`
  (content check on the first moved payload);
- reordering whole blocks (payload + prev + digest triples) is reported at
  the first moved index (link check);
- a fully rewritten chain that is internally consistent verifies: an
  external tip pin is required to detect replacement (see 2).

`Ok(true)` is returned when every check passes, including the empty chain.

## 6. Error catalog

Catalog A -- offset-table problems (used by `chain_from_payloads` and
`chain_verify`), where `V`, `W`, `L`, `i`, `n` are the offending values:

| Message |
|---|
| `hashchain: payload_offsets must be non-empty` |
| `hashchain: payload_offsets[0] must be 0 (got V)` |
| `hashchain: payload_offsets[i]=V is below payload_offsets[i - 1]=W` |
| `hashchain: payload_offsets[n]=V must equal payload bytes length L` |

Catalog B -- structural chain problems (`chain_verify`):

| Message |
|---|
| `hashchain: chain count C is negative` |
| `hashchain: payload_offsets length L must equal count + 1 = N` |
| `hashchain: prev_digests length L must equal count * 32 = N` |
| `hashchain: digests length L must equal count * 32 = N` |

Catalog C -- per-block verification failures (`chain_verify`):

| Message |
|---|
| `hashchain: block 0 prev digest must be the 32 zero bytes (genesis rule)` |
| `hashchain: block I prev link broken (prev digest mismatch)` |
| `hashchain: block I digest mismatch (payload or stored digest tampered)` |

Catalog D -- accessor and argument errors:

| Message |
|---|
| `hashchain: block index I out of range (chain is empty)` |
| `hashchain: block index I out of range 0..M (count C)` |
| `hashchain: digests length L is too short for block I` |
| `hashchain: prev_digests length L is too short for block I` |
| `hashchain: payload_offsets length L is too short for block I` |
| `hashchain: payload offsets are malformed for block I (start S, end E, bytes L)` |
| `hashchain: chain has no tip (count C)` |
| `hashchain: prev digest must be 32 bytes (got N)` |

`chain_index_of` never errors: it returns -1 for "not found", for the empty
chain, and when a malformed offset table stops the scan.

## 7. Complexity

| Operation | Cost |
|---|---|
| `chain_new`, `chain_len`, `chain_is_empty`, `chain_digest_size` | O(1) |
| `chain_append` | O(total chain bytes) copy + one SHA-256 over the new block's preimage |
| `chain_from_payloads` | O(data.len() + block count), one SHA-256 per block |
| `chain_verify` | O(total chain bytes), one SHA-256 per block |
| `chain_compute_digest` | one SHA-256 over `23 + 32 + 8 + payload.len()` bytes |
| block accessors | O(32) or O(payload length); offset checks O(1) |
| `chain_tip_*` | O(1) / O(32) |
| `chain_index_of` | O(total payload bytes) |
| `chain_hex` | O(buf.len()) |

No allocation is reused between calls: chains are immutable values.

## 8. Test plan

`tests/test_conformance.xi` runs 20 checks, all fixtures built in-test:

1. empty chain: shape, `Ok(true)` verify, accessors report no blocks;
2. genesis block: zero prev digest, pinned digest, verify `Ok`;
3. one-block append/verify round-trip; digest size 32;
4. three-block chain: prev links, pinned digests, tip accessors;
5. pinned SHA-256 vectors: empty payload, `"abc"`, linked `"def"`,
   55/56/64-byte padding boundaries;
6. determinism: append-built vs `chain_from_payloads`-built chains;
7. payload tamper detected at block 1;
8. first broken index wins (block 0 reported despite block 2 damage);
9. stored-digest tamper detected at its own index (blocks 0 and 2);
10. prev tamper: link break at block 1; nonzero genesis prev caught by the
    genesis rule;
11. reordered payloads: first swapped position reported (0 and 1 cases);
12. whole-block reordering: links break at the first moved block;
13. `chain_from_payloads` round-trip plus the pinned offset error catalog;
14. empty payloads are legal and keep the links intact;
15. traversal accessors and out-of-range errors are precise;
16. structural invariants: length, count and offset problems are named;
17. hex rendering: lowercase, empty, high-bit bytes (0x80, 0xFF);
18. SHA-256 padding boundaries through `chain_append`;
19. digest construction: domain separator and length prefix are hashed;
20. append returns a new chain: input untouched, growth links and verifies.

### Ground truth

Every expected digest is computed **outside XIOM** with .NET
`System.Security.Cryptography.SHA256` over the exact preimage
`D || prev || uint64_be(len) || payload`, so the tests never share a hash
implementation with the module. Pinned vectors include:

| Preimage (prev, payload) | Digest (hex) |
|---|---|
| zeros32, `""` | `3ffa10c4a3b2f48a1ddfb40e296ec65eeec931c7076bf52e0072dbf5303b57af` |
| zeros32, `"abc"` | `ae4bc4096045e1b295a1d769dbb71f60d53bb4d66374b97ce76e2de27e59f183` |
| previous, `"def"` | `c0163411c394af33960b11a4273d4861b5f269f14fa78068e5db39ade20bd559` |
| zeros32, `"genesis"` | `ce7325cbe2e110fb8384fd8be8571eb1325a3e2ab8bd4928a49280917760753c` |
| zeros32, 55 x `"a"` | `48557b1a8a96c9ebeacb31bbde4b85ede278f59c982ad675bc93bbabf5fc0fe6` |
| zeros32, 56 x `"a"` | `be6bd486bbe767f64d9452de87cc58a973a06809e8cf16991ebcdfdb16891a16` |
| zeros32, 64 x `"a"` | `b296aa774b1540e37c97f5201efe90065f8df973cd039d121d059ed8a3f5f694` |
| `"aaa"` chain: d0 | `fab461d274f2bb69de398dc40de4f4e24f757b859cca19643002a6f049d9b96d` |
| d1 (prev=d0), `"bbb"` | `4e62d047f32b13c602fa414203792d9005e47dec18f375b74b3e563baf71ed54` |
| d2 (prev=d1), `"ccc"` | `9f8232e7010f8c3446bf9704c0a3a5c7cbf27cc903116b60becb00567e5ee684` |

Negative pins: a wrong-length-field variant and a no-domain-separator variant
of the `"abc"` preimage are pinned too; the module digest must differ from
both (`dc8f4b2e...` and `8a295b0c...`).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.hashchain
```

Expected tail: `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## 9. Provenance and license

- Chain design, errors, tests and docs: original to this package.
- Private SHA-256: mirror of `packages/xiom-merkle/src/merkle.xi`'s private
  `_sha256` (FIPS 180-4), itself derived from the FIPS 180-4 specification.
- License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
