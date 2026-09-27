# xiom.bitcoin -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.bitcoin`, version `0.1.0`).
Module: `src/bitcoin.xi` (`module xiom.bitcoin`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.convert`). No FFI, no external packages.

This document specifies the byte layouts actually implemented. Where a
documented local cap or normalization deviates from Bitcoin Core behavior,
it is called out.

## 1. Conventions

- The platform `Int` is signed 64-bit. All lengths, offsets, counts and
  decoded numeric fields are `Int`.
- Every decode error is `Err(Str)` with the prefix `bitcoin: ` and, where a
  buffer position applies, the suffix `at offset N` (0-based, relative to
  the reader's buffer). The offset points at the first byte of the
  offending construct, except where a field-specific note says otherwise.
- Byte reads always widen through `(b as Int) & 0xFF`; the reader never
  reads past the buffer end.
- Errors leave the reader cursor unspecified; callers must not rely on the
  position after an `Err`.
- `Str` values are never compared with `==` inside the module (byte
  comparisons are used); callers/tests use
  `xiom.string.compare.str_compare`.

## 2. Reader

```xi
pub type Reader = {
  data: Vec[UInt8];
  pos: Int;
}
```

| Function | Behavior |
|---|---|
| `reader_new(data)` | Reader at offset 0 owning `data`. |
| `reader_pos(r)` / `reader_len(r)` / `reader_remaining(r)` | Current offset, total length, unconsumed bytes. |
| `reader_byte(r)` | Reads 1 byte (0..255) and advances. |
| `reader_take(r, n)` | Reads `n` bytes and advances; `n < 0` is `negative length`, short buffer is `truncated`. |
| `reader_skip(r, n)` | Advances by `n` and returns the new offset; same errors. |

`safe, no panics: every read is bounds-checked.`

## 3. Varints

### 3.1 CompactSize (canonical)

| First byte | Payload | Value range |
|---|---|---|
| `0x00`..`0xFC` | none | `0`..`252` |
| `0xFD` | 2 bytes little-endian | `253`..`65535` |
| `0xFE` | 4 bytes little-endian | `65536`..`4294967295` |
| `0xFF` | 8 bytes little-endian | `4294967296`..`INT64_MAX` |

Canonicality: `0xFD` is rejected below 253, `0xFE` below 65536, `0xFF`
below 4294967296 (`bitcoin: non-canonical compact size at offset N`).
A `0xFF` value with bit 63 set does not fit the signed Int and is rejected
(`bitcoin: unsigned 64-bit value exceeds signed 64-bit range at offset N`),
so the maximum decodable value is `9223372036854775807`.

- `compact_size_read(r)` -- decode, canonical.
- `compact_size_write(out, n)` -- canonical encode; `n < 0` appends nothing.
- `compact_size_encoded_len(n)` -- 1/3/5/9, `0` for negative.

### 3.2 Legacy unsigned varint (addr messages)

Same prefixes and byte widths as CompactSize, but **no minimality check**:
`fd fc 00` decodes as 252. Used by `addr_message_read` for its entry
count, matching pre-0.6 Bitcoin serialization.

- `varint_legacy_read(r)` / `varint_legacy_write(out, n)`.

### 3.3 varstr

`CompactSize length` followed by exactly that many payload bytes.

- `varstr_read(r)` -- `Err` is the CompactSize error or `truncated`.
- `varstr_write(out, data)` -- length + bytes.

## 4. Message framing

24-byte header:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | network magic (big-endian byte sequence) |
| 4 | 12 | command, ASCII, NUL-padded |
| 16 | 4 | payload length, u32 little-endian |
| 20 | 4 | checksum, raw bytes |

Magics (classified by `bitcoin_network_name`):

| Network | Bytes | Int value |
|---|---|---|
| mainnet | `F9 BE B4 D9` | `4190024921` |
| testnet3 | `0B 11 09 07` | `185665799` |
| regtest | `FA BF B5 DA` | `4206867930` |
| signet (default) | `0A 03 CF 40` | `168021824` |

Command rules (enforced on read and write): at most 12 bytes; every
non-NUL byte must be printable ASCII `0x20..0x7E`; NULs only as trailing
padding. An all-NUL command is accepted and yields the empty `Str`.
Violations: `bad command character at offset N` (offset of the byte) and
`bad command padding at offset N`.

Payload cap: `BITCOIN_MAX_PAYLOAD = 33554432` (32 MiB). A larger declared
length is rejected before any payload byte is read:
`bitcoin: payload length N exceeds cap M at offset N` where the offset is
the length field's first byte.

`message_header_read(r, expected_magic)` requires the caller's magic;
mismatch is `bitcoin: wrong network magic at offset N` (offset of the
magic). It does **not** consume the payload; `payload_start` is the offset
where the payload begins. `message_payload_read(r, h)` reads exactly
`payload_len` bytes; `message_payload_end(h) = payload_start +
payload_len` computes the span without buffer access.

The **checksum is preserved raw**; verification needs double-SHA-256 and is
caller-side. `message_header_write(out, magic, command, payload_len,
checksum)` emits 24 bytes and returns the count; validation errors:
`magic out of range`, `command longer than 12 bytes`,
`bad command character`, `payload length out of range`,
`checksum must be 4 bytes` (no offsets, since no buffer position exists).

`verack` is framing-only: a header whose command is `verack` with
`payload_len == 0` and no payload.

## 5. net_addr

| Field | Bytes | Encoding |
|---|---|---|
| time | 4 | u32 LE; only in `addr` entries, else absent (`-1`) |
| services | 8 | u64 LE, kept raw |
| ip | 16 | IPv6 / IPv4-mapped bytes |
| port | 2 | u16 **big-endian** |

`net_address_read(r, with_time)` decodes one entry (version messages pass
`false`). `net_address_ipv4(ip)` returns the 4 trailing bytes when `ip` is
`00..00 ff ff a.b.c.d`, else an empty vector.

u64 fields (`services`, `nonce`) are exposed as 8 raw little-endian bytes
because they may exceed `INT64_MAX`:

- `bitcoin_u64_fits_int(raw)` -- true when `len == 8` and bit 63 is clear.
- `bitcoin_u64_to_int(raw)` -- value, or `-1` when it does not fit
  (indistinguishable from a hypothetical `-1`; check `fits` first).
- `bitcoin_u64_le_bytes(v)` -- 8 LE bytes for `v >= 0`, empty otherwise.

## 6. Messages

### 6.1 version

| Field | Encoding |
|---|---|
| version | i32 LE |
| services | u64 LE raw |
| timestamp | i64 LE (signed) |
| addr_recv | net_addr (no time) |
| addr_from | net_addr (no time) |
| nonce | u64 LE raw |
| user_agent | varstr |
| start_height | i32 LE |
| relay | optional byte; absent means `-1`, else normalized to 0/1 |

`version_message_read(r)` returns a `VersionMessage` with the fields
above; `addr_recv`/`addr_from` are `NetAddress` values with `time == -1`.
Trailing bytes beyond `relay` are left unconsumed (callers check
`reader_remaining`).

### 6.2 addr

`legacy varint` entry count, then per entry: `u32 time` + net_addr. Counts
above `BITCOIN_MAX_ADDR_COUNT = 1000` are rejected
(`bitcoin: count N exceeds cap M at offset N`, offset after the count).
Parallel vectors: `times`, `services` (raw 8), `ips` (16), `ports`.

### 6.3 inv / getdata

`CompactSize` count, then per vector: `u32 LE type` + 32-byte hash.
Counts above `BITCOIN_MAX_INV_COUNT = 50000` are rejected; count 0 is
accepted. `getdata_message_read` is the same layout. Types:
`INV_TYPE_TX = 1`, `INV_TYPE_BLOCK = 2`, `INV_TYPE_FILTERED_BLOCK = 3`,
`INV_TYPE_CMPCT_BLOCK = 4`; `inv_type_name`/`inv_type_known` classify.
Other type codes are structurally decodable and reported as `unknown`.

### 6.4 tx

Legacy layout:

| Field | Encoding |
|---|---|
| version | i32 LE |
| input count | CompactSize |
| inputs | per input: 32-byte prev hash, u32 LE index, varstr script, u32 LE sequence |
| output count | CompactSize |
| outputs | per output: i64 LE value (satoshi), varstr script |
| locktime | u32 LE |

SegWit (BIP-144) inserts `0x00 0x01` after the version and a witness
stack per input before the locktime:

| Field | Encoding |
|---|---|
| marker + flag | `0x00` then `0x01` (flag must be exactly 1) |
| real input count | CompactSize, must be > 0 |
| ... | as legacy |
| witness stacks | per input: CompactSize item count, then that many varstrs |
| locktime | u32 LE |

Decoding rules and rejections:

- A first input count of 0 means "witness transaction": the next byte must
  be `0x01`. `0x00` is `zero-input transaction without witness flag`;
  any other value is `unsupported witness flag N` (offset of the byte).
- A zero real input count is `zero-input witness transaction at offset N`.
- Input, output and per-input witness item counts above
  `BITCOIN_MAX_TX_IO = 1000000` are rejected.
- All reads are bounds-checked (`truncated at offset N`).

The `Tx` result stores parallel vectors (`in_prev_hash`, `in_prev_index`,
`in_script`, `in_sequence`, `out_value`, `out_script`, `witness_counts`,
`witness_flat_start`, `witness_items`) and `byte_len`, the exact number of
wire bytes consumed. `witness_counts[i]` is input `i`'s item count and
`witness_flat_start[i]` is the index of its first item in
`witness_items`. For legacy transactions the witness vectors are empty.
`tx_write(out, t)` re-emits the same layout (marker/flag when `segwit` is
set) and returns the byte count.

### 6.5 block header and block

80-byte header: i32 LE version, 32-byte prev hash, 32-byte merkle root,
u32 LE time, u32 LE bits, u32 LE nonce. The block hash needs double
SHA-256 and is caller-side. `block_header_write` re-emits 80 bytes.

Block: header, CompactSize tx count (cap
`BITCOIN_MAX_BLOCK_TXS = 1000000`), then the tx stream. `block_read`
parses every transaction, so the stream is structurally validated, and
returns `tx_count`, `tx_bytes_start` / `tx_bytes_end` (offsets in the
source buffer of the consumed stream) and `byte_len`. Re-reading the
individual transactions means seeking a fresh reader to `tx_bytes_start`
and calling `tx_read` `tx_count` times.

## 7. Script walking

`script_parse(script)` walks the bytes and produces one entry per
instruction in parallel vectors plus a copy of the source:

| Field | Meaning |
|---|---|
| `script` / `script_len` | source bytes and length |
| `opcode[i]` | raw opcode byte |
| `push_len[i]` | `-1` not a push; `0` OP_0; `1` OP_1NEGATE/OP_1..OP_16; else the pushed data byte count |
| `data_start[i]` / `data_end[i]` | explicit data range, `-1` when none |

Push parsing with bounds:

| Opcode | Form |
|---|---|
| `0x00` (OP_0/OP_FALSE) | pushes empty |
| `0x01`..`0x4B` | next `op` bytes are the data |
| `0x4C` OP_PUSHDATA1 | 1 length byte, then data |
| `0x4D` OP_PUSHDATA2 | 2 length bytes LE, then data |
| `0x4E` OP_PUSHDATA4 | 4 length bytes LE, then data |
| `0x4F` OP_1NEGATE, `0x51`..`0x60` OP_1..OP_16 | push the number |

Errors: `bitcoin: truncated pushdata at offset N` when a length field is
incomplete; `bitcoin: script push exceeds script at offset N` when the
data runs past the end (offset of the opcode). Every other byte is
accepted as a bare opcode; no script semantics are evaluated.

`script_opcode` / `script_push_len` / `script_data` access entries
(out-of-range reads return `-1` / `-1` / empty). `script_is_push_only`
is true when every instruction pushes (BIP-62 push-only shape).
`script_op_name` names the documented opcode table
(`OP_0`/`OP_FALSE`, `OP_PUSHDATA1/2/4`, `OP_1NEGATE`, `OP_1`..`OP_16`,
`OP_RETURN`, `OP_DUP`, `OP_EQUAL`, `OP_EQUALVERIFY`, `OP_HASH160`,
`OP_CHECKSIG`, `OP_CHECKMULTISIG`, `OP_CHECKLOCKTIMEVERIFY`,
`OP_CHECKSEQUENCEVERIFY`), `OP_PUSHBYTES` for direct pushes and
`OP_UNKNOWN` otherwise.

Templates (`script_classify`) and payloads (`script_template_payload`):

| Result | Bytes | Layout | Payload |
|---|---|---|---|
| `p2pkh` | 25 | `76 a9 14 <20> 88 ac` | bytes 3..23 |
| `p2sh` | 23 | `a9 14 <20> 87` | bytes 2..22 |
| `p2wpkh` | 22 | `00 14 <20>` | bytes 2..22 |
| `p2wsh` | 34 | `00 20 <32>` | bytes 2..34 |
| `p2tr` | 34 | `51 20 <32>` | bytes 2..34 |
| `op_return` | >= 1 | first byte `6a` | none |
| `unknown` | any | anything else | none |

## 8. Base58

Alphabet: `123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz`
(no `0`, `O`, `I`, `l`).

- `base58_encode(data)` -- leading `0x00` bytes become leading `1`
  characters; the rest is a minimal base-58 number. Empty input yields "".
  O(n^2) worst case.
- `base58_decode(s)` -- leading `1` characters become leading `0x00`
  bytes; the rest is a big-endian byte value without leading zeros.
  `Err("bitcoin: base58 input too long")` above
  `BITCOIN_MAX_BASE58_LEN = 1024` characters;
  `Err("bitcoin: base58 invalid character at offset N")` otherwise.
  Empty input yields an empty vector.
- `base58_is_valid(s)` -- alphabet check only (no length cap).
- `base58_payload(raw)` / `base58_checksum(raw)` -- split a decoded
  Base58Check-shaped blob into everything but the trailing 4 bytes and the
  trailing 4 bytes (both empty when `raw.len() < 4`).

The 4-byte checksum is exposed raw. **No checksum verification happens**:
the caller must double-SHA-256 `base58_payload(raw)` and compare the first
4 bytes with `base58_checksum(raw)`.

## 9. Bech32 / Bech32m (BIP-173, BIP-350)

Alphabet: `qpzry9x8gf2tvdw0s3jn54khce6mua7l` (index = 5-bit value).
Variant constants: `BECH32_VARIANT_BECH32 = 0` (constant 1),
`BECH32_VARIANT_BECH32M = 1` (constant `0x2bc830a3`).

Format rules enforced by `bech32_decode`:

1. Total length 8..90 characters (`bad length`).
2. No mixed case; an all-uppercase string is folded to lowercase
   (`mixed case`).
3. The last `1` is the separator; it must not be the first character
   (`missing separator`), and the data part is at least 6 symbols
   (`bad length`).
4. HRP bytes in 33..126 (`invalid hrp character`); data symbols in the
   alphabet (`invalid data character`).
5. Polymod over `hrp-expand(hrp) + data` must equal 1 (Bech32) or
   `0x2bc830a3` (Bech32m); otherwise `bad checksum`. A string cannot be
   valid under both constants.

`bech32_decode` returns `Bech32Data { hrp, variant, values }` with the 6
checksum symbols removed. `bech32_encode(hrp, data, variant)` emits the
canonical lowercase form; errors: `bad variant`, `invalid hrp length`
(1..83), `invalid hrp character`, `mixed case` (uppercase HRP), `invalid
data value` (0..31), `bad length` (result over 90).

`bech32_convertbits(data, frombits, tobits, pad)` implements the BIP-173
bit regrouping (`invalid bits`, `convertbits overflow`, `invalid
padding`). `bech32_bytes_to_symbols` (8->5, padded) and
`bech32_symbols_to_bytes` (5->8, strict) are the canonical uses.

### 9.1 SegWit addresses

`segwit_decode(s)` applies the general rules and then:

1. The payload must contain a witness version (`missing witness version`).
2. Version 0..16 (`witness version out of range`).
3. Program = strict 5->8 conversion of the remaining symbols
   (`invalid padding`).
4. Program length 2..40 (`witness program length out of range`).
5. Version 0: the checksum constant must be Bech32
   (`wrong variant for witness v0`) and the program must be 20 or 32 bytes
   (`bad witness v0 program length`).
6. Version 1..16: the checksum constant must be Bech32m
   (`wrong variant for witness v1+`).

`segwit_encode(hrp, witver, program)` performs the reverse with the same
rules, selecting Bech32 for v0 and Bech32m for v1+.
`segwit_hrp` / `segwit_witver` / `segwit_program` are accessors.

## 10. Caps

| Constant | Value | Applies to |
|---|---|---|
| `BITCOIN_MAX_PAYLOAD` | 33554432 | declared message payload length |
| `BITCOIN_MAX_ADDR_COUNT` | 1000 | addr entries |
| `BITCOIN_MAX_INV_COUNT` | 50000 | inv/getdata vectors |
| `BITCOIN_MAX_TX_IO` | 1000000 | tx input/output/witness item counts |
| `BITCOIN_MAX_BLOCK_TXS` | 1000000 | block transaction count |
| `BITCOIN_MAX_BASE58_LEN` | 1024 | Base58 input characters |
| header sizes | 24 / 12 / 4 / 80 | header, command, checksum, block header |

These are documented local limits, not consensus rules.

## 11. Error catalog

Varints and readers:

| Condition | Text |
|---|---|
| buffer ends early | `bitcoin: truncated at offset N` |
| negative length argument | `bitcoin: negative length at offset N` |
| non-minimal CompactSize | `bitcoin: non-canonical compact size at offset N` |
| u64 value above INT64_MAX | `bitcoin: unsigned 64-bit value exceeds signed 64-bit range at offset N` |

Framing:

| Condition | Text |
|---|---|
| magic mismatch | `bitcoin: wrong network magic at offset N` |
| command byte outside 0x20..0x7E | `bitcoin: bad command character at offset N` |
| non-NUL byte after padding | `bitcoin: bad command padding at offset N` |
| declared payload above cap | `bitcoin: payload length N exceeds cap M at offset N` |

Messages:

| Condition | Text |
|---|---|
| addr/inv/tx/block count above cap | `bitcoin: count N exceeds cap M at offset N` |
| witness flag byte missing | `bitcoin: truncated witness flag at offset N` |
| zero inputs, flag 0x00 | `bitcoin: zero-input transaction without witness flag at offset N` |
| zero inputs, flag other than 0x01 | `bitcoin: unsupported witness flag N at offset N` |
| marker + flag but zero real inputs | `bitcoin: zero-input witness transaction at offset N` |

Script:

| Condition | Text |
|---|---|
| incomplete pushdata length | `bitcoin: truncated pushdata at offset N` |
| push data past end | `bitcoin: script push exceeds script at offset N` |

Base58:

| Condition | Text |
|---|---|
| input over 1024 chars | `bitcoin: base58 input too long` |
| byte outside the alphabet | `bitcoin: base58 invalid character at offset N` |

Bech32/Bech32m:

| Condition | Text |
|---|---|
| wrong length / data part shorter than 6 | `bitcoin: bech32 bad length` |
| mixed case | `bitcoin: bech32 mixed case` |
| no separator or empty HRP | `bitcoin: bech32 missing separator` |
| HRP byte outside 33..126 | `bitcoin: bech32 invalid hrp character` |
| data byte outside the alphabet | `bitcoin: bech32 invalid data character` |
| neither constant verifies | `bitcoin: bech32 bad checksum` |
| encoder: HRP length outside 1..83 | `bitcoin: bech32 invalid hrp length` |
| encoder: symbol outside 0..31 | `bitcoin: bech32 invalid data value` |
| encoder: variant not 0/1 | `bitcoin: bech32 bad variant` |
| convertbits: frombits/to bits outside 1..8 | `bitcoin: bech32 invalid bits` |
| convertbits: value out of range | `bitcoin: bech32 convertbits overflow` |
| convertbits: bad trailing bits | `bitcoin: bech32 invalid padding` |
| segwit: empty data part | `bitcoin: bech32 missing witness version` |
| segwit: version outside 0..16 | `bitcoin: bech32 witness version out of range` |
| segwit: program outside 2..40 | `bitcoin: bech32 witness program length out of range` |
| segwit: v0 with Bech32m | `bitcoin: bech32 wrong variant for witness v0` |
| segwit: v0 programs other than 20/32 | `bitcoin: bech32 bad witness v0 program length` |
| segwit: v1+ with Bech32 | `bitcoin: bech32 wrong variant for witness v1+` |

Writer-only validation (`message_header_write`): `bitcoin: magic out of
range`, `bitcoin: command longer than 12 bytes`, `bitcoin: bad command
character`, `bitcoin: payload length out of range`, `bitcoin: checksum
must be 4 bytes`.

## 12. Complexity

| Operation | Complexity |
|---|---|
| all reader/varint/varstr operations | O(bytes read) |
| `message_header_read` / `message_payload_read` | O(24) / O(payload) |
| `version_message_read` / `net_address_read` | O(fields) |
| `addr_message_read` / `inv_message_read` | O(entries * entry size) |
| `tx_read` / `tx_write` | O(transaction bytes) |
| `block_read` | O(block bytes) |
| `script_parse` / `script_classify` | O(script bytes) |
| `base58_encode` / `base58_decode` | O(n^2) worst case |
| `bech32_decode` / `bech32_encode` | O(characters) |
| `segwit_decode` / `segwit_encode` | O(characters) |

## 13. Test plan

`tests/test_conformance.xi` (`module bitcoin_tests`, 20 checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count):

1. CompactSize boundary encodings/decodings and encoded lengths;
2. CompactSize truncation, non-canonical forms, u64 overflow, offsets;
3. legacy varint non-minimal acceptance, varstr round-trips, reader
   bounds and byte-offset errors;
4. framing: magic for all four networks, command rules, empty command,
   payload cap, checksum raw, payload read and span;
5. version message fields (u64 raw helpers, net_addr, user agent, relay
   present/absent);
6. verack framing and a full framed transaction walk;
7. addr entries (legacy non-minimal count), IPv4-mapped extraction, cap;
8. inv/getdata vectors, type names, cap, empty list;
9. legacy transaction fields and `tx_write` round-trip;
10. SegWit transaction marker/flag, witness stack, round-trip;
11. transaction rejections (flags, empty inputs, oversized counts,
    truncation);
12. genesis block header and coinbase walk (script pushes and headline),
    block tx count cap;
13. script push parsing (direct/PUSHDATA1/2/4), opcode names, bounds,
    push-only;
14. script template classification and payload extraction;
15. Base58 alphabet, leading zeros, mainnet address round-trip, payload/
    checksum split, invalid characters, cap;
16. Bech32/Bech32m valid BIP vectors, canonical encoding, convertbits;
17. Bech32/Bech32m rejections and convertbits errors;
18. SegWit valid BIP-173/BIP-350 vectors (v0 20/32, v1 32/40, v16, v2);
19. SegWit rejections (wrong variant, version 17, short program, mixed
    case) and encoding round-trips;
20. header writer and its errors, writer edge cases, u64 helpers.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.bitcoin
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## 14. Non-goals

- SHA-256 / double-SHA-256, checksum or block-hash verification.
- Base58Check validation (the checksum is returned raw).
- Script execution, signature checks, consensus rules.
- P2P transport, sockets, DNS seeding, handshake state machines.
- ECDSA / secp256k1 / BIP-32 key derivation.
- Testnet4 and custom signet magic names (any magic can be read as an
  `Int`; only four networks are classified).
- Arbitrary-precision values: u64 protocol fields above `INT64_MAX` are
  exposed as raw bytes, and CompactSize values above it are rejected.

## 15. Compiler / stdlib notes for v0.61.3

- Free functions only; collections are parallel `Vec` fields (no
  `Vec[StructType]`).
- `Ok`/`Err` construction is confined to the leaf helpers at the top of
  the module.
- Every `Vec[Int]`/`Vec[UInt8]` element read is bound to a typed local
  first, and `&struct.field` is never passed where a `&Vec[UInt8]`
  parameter is expected.
- Because passing a **local** `Vec` to a `&mut Vec[UInt8]` helper without
  an explicit `&mut` silently writes to a copy, every mutating call site
  passes `&mut` explicitly (this bug class is invisible to the type
  checker in v0.61.3 and was caught by the conformance suite).
- No shifts and no bit tests on values that may have the sign bit set:
  little-endian reads use multiply/divide by 256, big-endian reads
  multiply by 2^24..2^0, and `_read_i32_le` / `_read_i64_le` /
  `_push_i32_le` / `_push_i64_le` round-trip the full signed 64-bit range
  with explicit sign arithmetic.
- `&mut Int` out-parameters miscompile; every helper returns its value.
- `int_to_string` is `xiom.convert.int_to_string`.
