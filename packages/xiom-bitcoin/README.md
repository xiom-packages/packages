# xiom.bitcoin

Bitcoin wire-format and address **structure** codec in pure XIOM (no FFI).

> **Status:** `incubating` -- implemented and harness-green with compiler
> v0.61.3; not published.

## Scope (honest)

`xiom.bitcoin` parses and re-emits Bitcoin byte layouts. It is a structural
codec, not a node, not a wallet and not a validator:

- **No hashing.** SHA-256 / double-SHA-256 are not implemented, so the
  package never verifies a message checksum, a Base58Check checksum or a
  block hash. Those fields are preserved raw and verification is
  **caller-side** (see below).
- **No script execution or consensus validation.** Scripts are walked as
  bytes; opcodes are never executed and no consensus rule is enforced.
- **No networking.** Only in-memory byte buffers are handled.
- **No cryptography.** No secp256k1, no signatures, no key handling.

Implemented:

- **CompactSize** varints with canonical (minimal-length) enforcement, the
  **legacy unsigned varint** used by old `addr` messages (non-minimal
  accepted), and **varstr** (CompactSize length + bytes).
- **Message framing**: 4-byte network magic (mainnet, testnet3, regtest,
  signet), 12-byte NUL-padded ASCII command, u32 payload length with a
  documented 32 MiB cap, 4-byte checksum kept raw.
- **Messages**: `version`, `verack` (framing), `addr` (legacy varint
  count), `inv`/`getdata` (CompactSize count + inventory vectors),
  `tx` (legacy and BIP-144 SegWit with witness stacks), block header and
  block (header + tx count + consumed tx stream).
- **Script walking**: bounded push parsing (direct, OP_PUSHDATA1/2/4),
  opcode names, push-only detection, and output-template classification
  (`p2pkh`, `p2sh`, `p2wpkh`, `p2wsh`, `p2tr`, `op_return`, `unknown`).
- **Base58** (Bitcoin alphabet, leading-zero handling) and
  **Bech32 / Bech32m** witness address decoding and encoding per
  BIP-173/BIP-350 (polymod checksum, v0 20/32-byte rule, v1+ Bech32m
  constant).

Dependencies: `xiom.std` only (`xiom.string`, `xiom.string.builder`,
`xiom.convert`); the tests additionally use `xiom.test`, `xiom.io` and
`xiom.encoding.hex`.

## Verify

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.bitcoin
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Caller-side responsibilities

| Field | What the caller must do |
|---|---|
| Message `checksum` | Compare the 4 raw bytes against the first 4 bytes of double-SHA-256 over the payload. |
| Base58Check checksum | Compare `base58_checksum(raw)` against the first 4 bytes of double-SHA-256 over `base58_payload(raw)`. |
| Block hash | Double-SHA-256 the 80-byte header (little-endian display order). |
| Script semantics | Interpret opcodes, verify signatures, apply consensus rules. |
| Network magic | Pass the expected magic to `message_header_read` (or classify with `bitcoin_network_name`). |

## Usage

Decode a framed transaction:

```xi
use xiom.bitcoin;

var r = reader_new(wire_bytes);
let h = message_header_read(&mut r, BITCOIN_MAGIC_MAINNET);   // header
if !h.is_ok { /* error text in h.error */ }
let hdr: MessageHeader = h.value;
let cmd: Str = hdr.command;                                    // "tx"
let pl = message_payload_read(&mut r, &hdr);
if pl.is_ok {
  let payload: Vec[UInt8] = pl.value;
  var tr = reader_new(payload);
  let t = tx_read(&mut tr);
  if t.is_ok {
    let tx: Tx = t.value;
    // tx.in_count, tx.in_script[0], tx.out_value[0], ...
  }
}
```

Decode an address without hashing:

```xi
let raw = base58_decode("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa");
if raw.is_ok {
  let blob: Vec[UInt8] = raw.value;          // version + hash + 4-byte checksum
  let payload = base58_payload(&blob);       // 21 bytes
  let cksum = base58_checksum(&blob);        // raw; verify with your SHA-256
}

let w = segwit_decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
if w.is_ok {
  let a: SegwitAddress = w.value;            // witver 0, 20-byte program
}
```

Walk a script and classify an output:

```xi
let s = script_parse(&script_bytes);
if s.is_ok {
  let d: ScriptDoc = s.value;                // per-instruction opcodes/pushes
}
let kind = script_classify(&script_bytes);   // "p2pkh", "p2tr", ...
```

## Error convention

Every decode error is an `Err(Str)` beginning with `bitcoin: ` and, where a
buffer position is meaningful, ending in `at offset N` where `N` is a
0-based byte offset into the reader's buffer. See `SPEC.md` for the full
catalog.

## Known limitations

- **Signed 64-bit Int platform.** CompactSize values above `INT64_MAX`
  (bit 63 set in the u64 form) are rejected, not truncated. u64 protocol
  fields that may exceed that range (`services`, `nonce`) are exposed as
  their raw 8 little-endian bytes; use `bitcoin_u64_to_int` when the value
  is known to fit.
- **Documented local caps**, not consensus rules: 32 MiB payload, 1000
  addr entries, 50000 inventory vectors, 1,000,000 transaction
  inputs/outputs/witness items, 1,000,000 transactions per block, 1024
  Base58 characters.
- **`addr` uses the legacy varint** count (non-minimal accepted) by
  design; `inv`/`getdata` use canonical CompactSize.
- **Zero-input transactions are rejected** (`bitcoin: zero-input
  transaction without witness flag` / `bitcoin: zero-input witness
  transaction`); consensus-invalid but serializable, and out of scope.
- **Witness flag must be 0x01**; any other non-zero flag is rejected as
  unsupported.
- **No testnet4/custom magic classification.** Any 4-byte magic can be
  read by passing it as `expected_magic`; only the four documented networks
  have names.
- **No BigInt**: Base58 conversion uses the platform Int internally per
  digit, which is exact for the whole byte-array algorithm (no numeric
  overflow is possible because the working values stay below 2^16 per
  step).

## Tests

`tests/test_conformance.xi` (`module bitcoin_tests`, 20 checks). Buffers
are synthetic, built in-test; large byte vectors were generated by an
independent reference implementation and cross-checked, and the
Bech32/Bech32m vectors are the pinned BIP-173/BIP-350 vectors. Coverage:
CompactSize boundaries and rejections, legacy varints, varstr, reader
bounds, framing (magic/command/cap/checksum), version/verack/addr/inv/
getdata, legacy and SegWit transaction round-trips, the genesis block
header and coinbase walk, script pushes and templates, Base58, and
Bech32/Bech32m/segwit valid and invalid vectors.
