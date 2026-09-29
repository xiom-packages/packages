# xiom.hashchain

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.0` on the XIOM registry.
> **Scope:** append-only hash-linked record chains over caller byte buffers:
> deterministic SHA-256 block digests, a zero-prev genesis rule, prev links,
> and first-error integrity verification.
> **Deps:** `xiom.std` (library: `xiom.string`, `xiom.convert`; tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`). Pure XIOM, no FFI, no IO,
> no clock.

## What it is

`xiom.hashchain` builds a sequence of blocks where every block commits to the
block before it:

- each block carries a caller-supplied **payload** (arbitrary bytes, possibly
  empty) and a 32-byte SHA-256 digest;
- the digest commits to the previous digest and to the payload:
  `SHA256(D || prev_digest || uint64_be(payload_len) || payload)`, with
  `D = "xiom.hashchain.v1.block"` a domain separator and the length field
  making the preimage unambiguous for every payload split;
- block 0 is the **genesis block**: its previous digest is the 32 zero bytes;
- every later block `i` links `prev_digests[i] == digests[i - 1]`;
- `chain_verify` re-checks the structural invariants, the genesis rule, every
  prev link and every recomputed digest, and reports the **first** broken
  index in a precise error message;
- digests are deterministic: same inputs produce the same digests. There is
  no IO, no clock and no randomness anywhere in the module.

Payloads are stored flattened: one `payload_bytes` buffer plus a
`payload_offsets` table (`count + 1` entries), so no `Vec[Vec[UInt8]]` and no
`Vec[StructType]` is needed. The full layout is documented in `SPEC.md` and in
`src/hashchain.xi`.

SHA-256 is implemented **inside this module** (FIPS 180-4) as a private,
pure-XIOM mirror of the KAT-verified private `_sha256` in
`packages/xiom-merkle/src/merkle.xi`; it is internal and not exported as a
general hash API. The stdlib `xiom.crypto.sha256` was checked first and
rejected because it is FFI-backed and fails to link from packages at
v0.62.0/v0.62.1 (`undefined symbol: xiom_sha256_hash`).

## Non-goals (honest scope)

- **Integrity only, not consensus.** This is not a blockchain: no
  proof-of-work, no signatures, no authentication, no distributed agreement,
  no double-spend protection. `chain_verify` detects an inconsistent chain
  presentation; a party that can rewrite the whole chain can recompute every
  digest and present a self-consistent replacement.
- **Prefix truncation is not detectable** from the chain itself: dropping
  trailing blocks yields a shorter chain that verifies. Pin a tip digest
  externally (`chain_tip_digest` / `chain_digest_hex` style checks) when that
  matters.
- No payload privacy or encryption; payload bytes are stored verbatim.
- No serialization to bytes, no persistence, no streaming; each
  `chain_append` is O(total chain bytes) because chains are values.
- No configurable hash function; SHA-256 is fixed. Not constant-time.

## API

| Function | Returns | Description |
|---|---|---|
| `chain_digest_size()` | `Int` | 32, the digest length in bytes. |
| `chain_new()` | `HashChain` | The empty chain (0 blocks; the first append creates the genesis block). |
| `chain_len(chain)` | `Int` | Number of blocks (0 for the empty chain). |
| `chain_is_empty(chain)` | `Bool` | True when there are no blocks. |
| `chain_append(chain, payload)` | `HashChain` | New chain with one block appended; links the previous digest (zero prev for the genesis block). |
| `chain_from_payloads(data, offsets)` | `Result[HashChain, Str]` | Build from flattened payloads (`payload i = data[offsets[i]..offsets[i+1]]`). |
| `chain_compute_digest(prev_digest, payload)` | `Result[Vec[UInt8], Str]` | Recompute the expected 32-byte block digest (`prev_digest` must be 32 bytes). |
| `chain_verify(chain)` | `Result[Bool, Str]` | `Ok(true)` when every block checks; `Err` naming the first broken index and check. |
| `chain_block_digest(chain, index)` | `Result[Vec[UInt8], Str]` | Stored 32-byte digest of one block. |
| `chain_block_prev(chain, index)` | `Result[Vec[UInt8], Str]` | The 32-byte prev digest block `index` commits to (zero for genesis). |
| `chain_block_payload(chain, index)` | `Result[Vec[UInt8], Str]` | Copy of one block's payload bytes (possibly empty). |
| `chain_block_len(chain, index)` | `Result[Int, Str]` | Payload length of one block. |
| `chain_tip_index(chain)` | `Result[Int, Str]` | Index of the last block (`Err` on the empty chain). |
| `chain_tip_digest(chain)` | `Result[Vec[UInt8], Str]` | Digest of the last block (the tip). |
| `chain_index_of(chain, payload)` | `Int` | First block index with byte-equal payload, or -1. |
| `chain_hex(buf)` | `Str` | Lowercase hex of any byte buffer. |

`HashChain` fields and their invariants are documented in `src/hashchain.xi`
and `SPEC.md`; build chains through the functions above.

## Usage

```xi
use xiom.io;
use xiom.hashchain;
use xiom.string;

fn build_and_tamper_check() -> Bool {
  let empty = chain_new();
  let a = "first record";
  let b = "second record";
  var pa = Vec[UInt8].new();
  var pb = Vec[UInt8].new();
  var i = 0;
  while i < a.len() { pa.push(string.byte_at(a, i)); i = i + 1; }
  i = 0;
  while i < b.len() { pb.push(string.byte_at(b, i)); i = i + 1; }

  let c1 = chain_append(&empty, &pa);        // block 0: genesis (zero prev)
  let c2 = chain_append(&c1, &pb);           // block 1: links digest of block 0
  io.println(chain_hex(&chain_tip_digest(&c2).value));  // 64 hex chars

  let v = chain_verify(&c2);
  if !v.is_ok { return false; }
  return v.value;                            // true: chain is consistent
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 20 `[PASS]` lines, then `xiom.hashchain: all tests passed`, exit 0.
From the repository root:

```
& .\scripts\port.ps1 -Package xiom.hashchain
```

Last verified: compiler 0.62.1, twice in a row,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Implementation notes

- Pure XIOM, free functions only, no `Vec[StructType]`: a chain is five
  parallel fields (count, payload_offsets, payload_bytes, prev_digests,
  digests), all mirrored on every append.
- 32-bit SHA-256 words stay in `0..2^32-1` via `% 4294967296`; rotations are
  divisor/modulo, AND is `(a + b - (a XOR b)) / 2` and NOT is `2^32-1 - a`,
  so no raw 32-bit mask or `~` ever touches a value with bit 31 set.
- The 64 SHA-256 round constants are built into a runtime `Vec[Int]` because
  module-level const arrays are mis-materialized by the toolchain.
- Every `UInt8` read is widened and masked (`(x as Int) & 0xFF`).
- See `SPEC.md` for the chain layout, the digest preimage, the verification
  order, the exact error catalog and the pinned test vectors.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
