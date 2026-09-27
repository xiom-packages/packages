# xiom.multicast -- Specification

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0

Wire formats, API contract, error catalog and test matrix for the
`xiom.multicast` package (IGMPv2/v3 and MLD/MLDv2 group-management codecs).
All multi-byte integers are big-endian, as on the wire.

## Scope

The package implements, as pure value codecs:

- IGMPv1/v2 messages (RFC 1112, RFC 2236): Membership Query (`0x11`),
  v1 Membership Report (`0x12`), v2 Membership Report (`0x16`), Leave
  Group (`0x17`).
- IGMPv3 messages (RFC 3376): Membership Query with the Resv/S/QRV/QQIC
  suffix and source list, and Version 3 Membership Report (`0x22`) with
  group records of record types 1..6, per-record source lists and
  auxiliary data.
- MLD messages (RFC 2710, ICMPv6 types 130/131/132) and MLDv2 (RFC 3810):
  the MLDv1 query/report/done shapes, the MLDv2 query suffix (still type
  130, distinguished by length) and the type 143 Version 2 Multicast
  Listener Report with the same record structure over 16-byte addresses.
- One's-complement checksums: the IGMP checksum over the whole message
  and the ICMPv6 checksum over the IPv6 pseudo-header plus the message,
  with computation and validation helpers for both.

The codec parses a complete message from one buffer and builds messages
from scalars, address vectors and parallel record vectors. Source lists,
group records and auxiliary data stay in the source buffer and are
addressed by absolute byte offsets; accessors copy values out on demand.

## Non-goals

- Sockets and transport; interface/group membership state; querier
  election; report suppression; robustness-variable timers.
- IGMP/MLD proxying and snooping, PIM, SSM channel management above the
  report/query formats.
- IP fragmentation/reassembly, checksum offload semantics and IPv6
  extension-header walking (the caller supplies the pseudo-header
  addresses and the upper-layer payload).
- Streaming/incremental parsing and concatenated messages.
- Cryptographic or authentication extensions (IPsec, IGMPv3 no such).

## Byte-level layout

### IGMPv1/v2 fixed message (8 bytes)

Offsets 0..7. Used by queries without the v3 suffix and by the v1/v2
reports and leave.

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Type: 0x11 query, 0x12 v1 report, 0x16 v2 report, 0x17 leave |
| 1 | 1 | Max Resp Time (queries; tenths of a second) or zero (reports/leave) |
| 2 | 2 | Checksum (entire IGMP message, one's complement) |
| 4 | 4 | Group Address (0.0.0.0 on a general query) |

### IGMPv3 Membership Query (`12 + 4N` bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Type = 0x11 |
| 1 | 1 | Max Resp Code |
| 2 | 2 | Checksum |
| 4 | 4 | Group Address (0.0.0.0 for a general query) |
| 8 | 1 | Resv (4 bits) \| S (1 bit, 0x08) \| QRV (3 bits) |
| 9 | 1 | QQIC |
| 10 | 2 | Number of Sources N |
| 12 | 4N | Source Address [1..N] |

### IGMPv3 Membership Report (`8 + records`)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Type = 0x22 |
| 1 | 1 | Reserved |
| 2 | 2 | Checksum |
| 4 | 2 | Reserved |
| 6 | 2 | Number of Group Records M |
| 8 | ... | Group Record [1..M] |

Group Record (fixed part 8 bytes; then sources, then auxiliary data):

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Record Type (1..6) |
| 1 | 1 | Aux Data Len in 32-bit words |
| 2 | 2 | Number of Sources N |
| 4 | 4 | Multicast Address |
| 8 | 4N | Source Address [1..N] |
| 8+4N | 4*aux | Auxiliary Data |

Record types: 1 MODE_IS_INCLUDE, 2 MODE_IS_EXCLUDE,
3 CHANGE_TO_INCLUDE_MODE, 4 CHANGE_TO_EXCLUDE_MODE, 5 ALLOW_NEW_SOURCES,
6 BLOCK_OLD_SOURCES.

### MLDv1 messages (24 bytes)

Types 130 query, 131 report, 132 done.

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Type (130/131/132) |
| 1 | 1 | Code (0) |
| 2 | 2 | ICMPv6 checksum |
| 4 | 4 | Maximum Response Delay in ms (0 in reports/done) |
| 8 | 16 | Multicast Address (`::` for a general query; the group for reports/done) |

### MLDv2 query (`28 + 16N` bytes, type 130)

The MLDv1 prefix, then the suffix. A 24-byte type 130 message is MLDv1;
25..27 bytes are rejected.

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Type = 130 |
| 1 | 1 | Code = 0 |
| 2 | 2 | ICMPv6 checksum |
| 4 | 2 | Maximum Response Code |
| 6 | 2 | Reserved |
| 8 | 16 | Multicast Address (`::` for a general query) |
| 24 | 1 | Resv (4 bits) \| S (1 bit, 0x08) \| QRV (3 bits) |
| 25 | 1 | QQIC |
| 26 | 2 | Number of Sources N |
| 28 | 16N | Source Address [1..N] |

### MLDv2 report (`8 + records`, type 143)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Type = 143 |
| 1 | 1 | Reserved |
| 2 | 2 | ICMPv6 checksum |
| 4 | 4 | Reserved |
| 6 | 2 | Number of Multicast Address Records M |
| 8 | ... | Multicast Address Record [1..M] |

Multicast Address Record (fixed part 20 bytes):

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Record Type (1..6, same codes as IGMPv3) |
| 1 | 1 | Aux Data Len in 32-bit words |
| 2 | 2 | Number of Sources N |
| 4 | 16 | Multicast Address |
| 20 | 16N | Source Address [1..N] |
| 20+16N | 4*aux | Auxiliary Data |

### Checksums

- **IGMP**: 16-bit one's-complement of the one's-complement sum of all
  16-bit words of the whole message. A trailing odd byte is padded on the
  right with a zero byte (the byte is the most significant half of the
  word). Validation: the folded sum of the complete message is `0xFFFF`.
- **ICMPv6** (every MLD message): the same over the IPv6 pseudo-header
  (`Source Address` 16 bytes, `Destination Address` 16 bytes,
  `Upper-Layer Packet Length` 32-bit, three zero bytes, `Next Header` 58)
  followed by the ICMPv6 message.

### Code encodings (RFC 3376 / RFC 3810)

- IGMP Max Resp Code (< 128): tenths of a second. Otherwise
  `(mant | 0x10) << (exp + 3)` tenths, with `mant = code & 0x0F` and
  `exp = (code >> 4) & 0x07`. Decoded to milliseconds by
  `igmp_max_resp_ms`.
- QQIC (< 128): seconds. Otherwise the same floating form, in seconds.
  Decoded by `igmp_qqic_seconds`.
- MLDv2 Max Response Code (< 32768): milliseconds. Otherwise
  `(mant | 0x1000) << (exp + 3)` milliseconds with `mant = code & 0x0FFF`
  and `exp = (code >> 12) & 0x07`. Decoded by `mld_max_resp_ms`.
- QRV 0 means "use the default robustness variable 2"
  (`igmp_qrv_effective`).

## API signatures

### Checksums

```
pub fn igmp_checksum(data: &Vec[UInt8]) -> Int
pub fn igmp_checksum_valid(data: &Vec[UInt8]) -> Bool
pub fn icmpv6_checksum(src: &Vec[UInt8], dst: &Vec[UInt8], data: &Vec[UInt8]) -> Int
pub fn icmpv6_checksum_valid(src: &Vec[UInt8], dst: &Vec[UInt8], data: &Vec[UInt8]) -> Bool
```

### Code decoding and predicates

```
pub fn igmp_max_resp_ms(code: Int) -> Int
pub fn igmp_qqic_seconds(code: Int) -> Int
pub fn mld_max_resp_ms(code: Int) -> Int
pub fn igmp_qrv_effective(raw_qrv: Int) -> Int
pub fn igmp_is_multicast(addr: Int) -> Bool
pub fn mld_is_multicast(addr: &Vec[UInt8]) -> Bool
pub fn igmp_message_name(msg_type: Int) -> Str
pub fn igmp_record_type_name(record_type: Int) -> Str
pub fn mld_message_name(msg_type: Int) -> Str
```

### IGMP

```
pub fn igmp_parse(data: &Vec[UInt8]) -> Result[IgmpMessage, Str]
pub fn igmp_version(m: &IgmpMessage) -> Int
pub fn igmp_query_variant(m: &IgmpMessage) -> Int
pub fn igmp_source_at(data: &Vec[UInt8], m: &IgmpMessage, k: Int) -> Int
pub fn igmp_record_count(m: &IgmpMessage) -> Int
pub fn igmp_record_type(m: &IgmpMessage, i: Int) -> Int
pub fn igmp_record_group(m: &IgmpMessage, i: Int) -> Int
pub fn igmp_record_source_count(m: &IgmpMessage, i: Int) -> Int
pub fn igmp_record_aux_bytes(m: &IgmpMessage, i: Int) -> Int
pub fn igmp_record_source_at(data: &Vec[UInt8], m: &IgmpMessage, i: Int, k: Int) -> Int
pub fn igmp_record_aux(data: &Vec[UInt8], m: &IgmpMessage, i: Int) -> Result[Vec[UInt8], Str]
pub fn igmp_build_query_v2(group: Int, max_resp: Int) -> Result[Vec[UInt8], Str]
pub fn igmp_build_report_v1(group: Int) -> Result[Vec[UInt8], Str]
pub fn igmp_build_report_v2(group: Int) -> Result[Vec[UInt8], Str]
pub fn igmp_build_leave(group: Int) -> Result[Vec[UInt8], Str]
pub fn igmp_build_query_v3(group: Int, max_resp: Int, suppress: Bool, qrv: Int, qqic: Int, sources: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn igmp_build_report_v3(record_types: &Vec[Int], groups: &Vec[Int], source_counts: &Vec[Int], sources: &Vec[Int], aux_data: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
```

### MLD

```
pub fn mld_parse(data: &Vec[UInt8]) -> Result[MldMessage, Str]
pub fn mld_version(m: &MldMessage) -> Int
pub fn mld_group(m: &MldMessage) -> Vec[UInt8]
pub fn mld_query_variant(m: &MldMessage) -> Int
pub fn mld_source_at(data: &Vec[UInt8], m: &MldMessage, k: Int) -> Result[Vec[UInt8], Str]
pub fn mld_record_count(m: &MldMessage) -> Int
pub fn mld_record_type(m: &MldMessage, i: Int) -> Int
pub fn mld_record_source_count(m: &MldMessage, i: Int) -> Int
pub fn mld_record_aux_bytes(m: &MldMessage, i: Int) -> Int
pub fn mld_record_group(data: &Vec[UInt8], m: &MldMessage, i: Int) -> Result[Vec[UInt8], Str]
pub fn mld_record_source_at(data: &Vec[UInt8], m: &MldMessage, i: Int, k: Int) -> Result[Vec[UInt8], Str]
pub fn mld_record_aux(data: &Vec[UInt8], m: &MldMessage, i: Int) -> Result[Vec[UInt8], Str]
pub fn mld_build_query_v1(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8], max_delay: Int) -> Result[Vec[UInt8], Str]
pub fn mld_build_report_v1(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn mld_build_done(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn mld_build_query_v2(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8], max_resp: Int, suppress: Bool, qrv: Int, qqic: Int, sources: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
pub fn mld_build_report_v2(src: &Vec[UInt8], dst: &Vec[UInt8], record_types: &Vec[Int], groups: &Vec[Vec[UInt8]], source_counts: &Vec[Int], sources: &Vec[Vec[UInt8]], aux_data: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
```

### Constants

`IGMP_TYPE_QUERY` 17, `IGMP_TYPE_V1_REPORT` 18, `IGMP_TYPE_V2_REPORT` 22,
`IGMP_TYPE_LEAVE` 23, `IGMP_TYPE_V3_REPORT` 34,
`IGMP_RECORD_MODE_IS_INCLUDE`..`IGMP_RECORD_BLOCK_OLD_SOURCES` 1..6,
`IGMP_QUERY_SIZE` 8, `IGMP_V3_QUERY_FIXED` 12, `IGMP_V3_REPORT_FIXED` 8,
`IGMP_RECORD_FIXED` 8, `IGMP_DEFAULT_MAX_RESP` 100, `IGMP_QRV_DEFAULT` 2,
`IGMP_MULTICAST_BASE` 3758096384 (224.0.0.0), `IGMP_MULTICAST_TOP`
4026531839 (239.255.255.255), `MLD_TYPE_QUERY` 130, `MLD_TYPE_REPORT` 131,
`MLD_TYPE_DONE` 132, `MLD_TYPE_V2_REPORT` 143, `MLD_V1_SIZE` 24,
`MLD_V2_QUERY_FIXED` 28, `MLD_V2_REPORT_FIXED` 8, `MLD_RECORD_FIXED` 20,
`MLD_ADDRESS_SIZE` 16, `ICMPV6_NEXT_HEADER` 58, `MLD_DEFAULT_MAX_RESP`
10000, `MLD_MAX_RESP_THRESHOLD` 32768.

## Semantics

- **IGMP version assignment.** An 8-byte query with Max Resp Code 0 is
  version 1; any other 8-byte query is version 2; a query carrying the
  v3 suffix is version 3. Type 0x12 is version 1; 0x16/0x17 are version 2;
  0x22 is version 3. The raw Max Resp Code octet is always preserved.
- **MLD version assignment.** 131/132 are version 1. A 24-byte type 130
  query is version 1; a type 130 query of 28+ bytes is version 2. A type
  143 report is version 2.
- **Query variants.** A query whose group field is zero and which carries
  no sources is a general query (variant 0); a non-zero group with no
  sources is group-specific (1); a non-zero group with sources is
  group-and-source-specific (2). A general query that declares sources is
  malformed and reported as variant -1.
- **All-or-nothing parse.** On the first shape error the parser returns
  `Err`; no partial index is produced. Checksum validity never causes an
  error (IGMP reports it in `checksum_ok`; MLD validation takes the
  addresses separately).
- **Offsets.** `IgmpMessage.source_offset`, `MldMessage.source_offset`,
  the `rec_*_offsets` vectors and `IgmpMessage.group`/record groups are
  absolute byte offsets into the buffer passed to the parser (addresses
  are decoded to Ints for IGMP; MLD stores offsets and copies on access).
  32-bit IPv4 values are unsigned Ints 0..4294967295.
- **Flat source vectors on build.** `igmp_build_report_v3` and
  `mld_build_report_v2` consume sources in record order: the first
  `source_counts[0]` entries belong to record 0, the next
  `source_counts[1]` to record 1, and so on. Builders validate before
  writing a byte, so a failed call leaves nothing partially built.
- **Record vector lengths.** Builders require `record_types`, `groups`,
  `source_counts` and `aux_data` to be the same length; accessors check
  every parallel vector before reading index `i`, so a hand-constructed
  message with mismatched vectors cannot read out of bounds.
- **Aux data.** Lengths are in 32-bit words on the wire; builders require
  the byte length to be a multiple of 4 and at most 255 words (1020
  bytes). A zero-length list is valid.
- **Address validation.** IGMP builders accept any 32-bit value; the
  caller decides whether it is a group. MLD builders require exactly 16
  bytes for every address. `igmp_is_multicast` / `mld_is_multicast` are
  provided for callers that want the range check.
- **Checksum writing.** Builders compute and write the checksum; there is
  no separate finalize step. `igmp_checksum` / `icmpv6_checksum` operate
  on whatever checksum bytes the input carries, so pass a zeroed-checksum
  message (as the builders do internally) to obtain the value to write,
  and the complete message to validate.

## Error string catalog

All messages are stable, lower-case, and prefixed `igmp: ` or `mld: `.
`<pos>` and `<end>` are decimal byte offsets; the builders use
`at index <i>` for vector element positions.

| Error | Condition |
|---|---|
| `igmp: short message` | `igmp_parse` with `data.len() < 8` |
| `igmp: bad message type at 0` | Type not 17, 18, 22, 23 or 34 |
| `igmp: bad length at 8` | Report/leave with a length other than 8 |
| `igmp: bad v3 query length at 8` | Query of 9..11 bytes |
| `igmp: truncated source list at 12` | `12 + 4N` exceeds the buffer |
| `igmp: trailing bytes at <end>` | Buffer longer than the declared span |
| `igmp: bad record count at 6` | `8 + 8M` exceeds the buffer, or fewer records present |
| `igmp: truncated record at <pos>` | Record header crosses the end |
| `igmp: bad record type at <pos>` | Record type outside 1..6 |
| `igmp: truncated source list at <pos>` | Record's `4N` source bytes cross the end |
| `igmp: bad aux data length at <pos>` | Record's `4*aux` data crosses the end |
| `igmp: record index out of range` | `igmp_record_aux` with a bad record index |
| `igmp: record out of bounds` | Record span does not fit the supplied buffer |
| `igmp: bad group address` | Group outside 0..4294967295 |
| `igmp: bad max resp code` | `max_resp` outside 0..255 |
| `igmp: bad qrv` | `qrv` outside 0..7 |
| `igmp: bad qqic` | `qqic` outside 0..255 |
| `igmp: too many sources` | More than 65535 sources |
| `igmp: bad source address` | Source outside 0..4294967295 |
| `igmp: record vector length mismatch` | The four per-record vectors differ |
| `igmp: too many records` | More than 65535 records |
| `igmp: bad record type at index <i>` | Record type outside 1..6 |
| `igmp: bad source count at index <i>` | Count outside 0..65535 |
| `igmp: bad aux data length at index <i>` | Not a multiple of 4 or over 255 words |
| `igmp: source vector length mismatch` | Flat source count differs from the sum |
| `mld: short message` | Buffer below 4 bytes, type 143 below 8, other types below 24 |
| `mld: bad message type at 0` | Type not 130, 131, 132 or 143 |
| `mld: bad query length at 24` | Type 130 of 25..27 bytes |
| `mld: bad length at 24` | Type 131/132 with a length other than 24 |
| `mld: truncated source list at 28` | `28 + 16N` exceeds the buffer |
| `mld: trailing bytes at <end>` | Buffer longer than the declared span |
| `mld: bad record count at 6` | `8 + 20M` exceeds the buffer, or fewer records present |
| `mld: truncated record at <pos>` | Record header crosses the end |
| `mld: bad record type at <pos>` | Record type outside 1..6 |
| `mld: truncated source list at <pos>` | Record's `16N` source bytes cross the end |
| `mld: bad aux data length at <pos>` | Record's `4*aux` data crosses the end |
| `mld: source index out of range` | `mld_source_at` / `mld_record_source_at` index |
| `mld: source out of bounds` | Recorded source span does not fit the buffer |
| `mld: record index out of range` | MLD record accessors with a bad index |
| `mld: record out of bounds` | Record span does not fit the supplied buffer |
| `mld: bad source address length` | Source address not 16 bytes |
| `mld: bad destination address length` | Destination address not 16 bytes |
| `mld: bad group address length` | Group address not 16 bytes |
| `mld: bad max response delay` | `max_delay` outside 0..4294967295 |
| `mld: bad max resp code` | `max_resp` outside 0..65535 |
| `mld: bad qrv` / `mld: bad qqic` | Out-of-range suffix codes |
| `mld: too many sources` / `mld: too many records` | Counts over 65535 |
| `mld: record vector length mismatch` | Per-record vectors differ |
| `mld: bad record type at index <i>` / `mld: bad source count at index <i>` / `mld: bad aux data length at index <i>` | Record builder field errors |
| `mld: source vector length mismatch` | Flat source count differs from the sum |

## Complexity

| Operation | Complexity |
|---|---|
| `igmp_parse` / `mld_parse` | O(data.len()) |
| `igmp_checksum*` / `icmpv6_checksum*` | O(buffer length) |
| Builders | O(inputs written) = O(message length) |
| Index accessors (`*_record_*`, `*_source_at`) | O(1) after the span check |
| `*_record_aux` | O(aux length) |
| `igmp_max_resp_ms` / `igmp_qqic_seconds` / `mld_max_resp_ms` | O(1) |

## Test plan

`tests/test_conformance.xi` (18 checks, all printing `[PASS]`) with
hardcoded wire fixtures produced by an independent one's-complement
implementation:

| Test | Coverage |
|---|---|
| t1 | IGMPv2 query fixture `11 64 0e 9a e0 00 00 01`; parse fields; checksum helpers; variant. |
| t2 | IGMPv1 query detection, v1/v2 reports, leave; report fixture `16 00 f8 fa ef 01 02 03`. |
| t3 | IGMP checksum vs an independent reference; single-bit corruption drops `checksum_ok`. |
| t4 | IGMPv3 general query; S/QRV/QQIC bytes; QRV-0 default. |
| t5 | IGMPv3 group-and-source query; source accessors and bounds. |
| t6 | IGMPv3 report with all six record types, sources and aux data. |
| t7 | IGMPv3 report decode, accessor rebuild, byte-identical re-encode. |
| t8 | IGMP length/type/count errors and offsets. |
| t9 | IGMPv3 record errors: bad type, truncated record, source list, aux. |
| t10 | MLDv1 query fixture `82 00 59 17 00 00 27 10 ...`; pseudo-header reference; report/done. |
| t11 | MLDv2 query with sources; checksum depends on the pseudo-header addresses. |
| t12 | MLDv2 report records, aux data, decode/re-encode round trip. |
| t13 | MLD length/type/count/record errors and offsets. |
| t14 | Max Resp / QQIC decoding, QRV default, multicast classification, names. |
| t15 | Every builder rejects malformed input with the documented error. |
| t16 | Accessor and pseudo-header guards on messages without records/sources. |
| t17 | Odd-length padding and single-byte-flip rejection for the checksum. |
| t18 | High-bit addresses (>= 2^31 and 255.255.255.255) survive packing. |

Run with:

```
& .\scripts\port.ps1 -Package xiom.multicast
```

## Known limitations

- The codec does not model querier/host state, timers, suppression or
  interface selection; it converts messages only.
- Trailing bytes are errors everywhere; concatenated messages are not
  supported.
- MLD checksum validity needs the IPv6 addresses, so `mld_parse` cannot
  set a verdict; use `icmpv6_checksum_valid`.
- A type 130 message of 25..27 bytes has no valid interpretation and is
  rejected rather than guessed.
- Auxiliary data must be word-aligned on build; partial words are
  rejected.
- Auxiliary data is preserved but not interpreted (no application-level
  schema).

## Compiler / stdlib notes for v0.61.3

The implementation follows the traps observed on the pinned compiler:

- Free functions only; no methods, no lambdas, no `Vec[function]`
  dispatch. `IgmpMessage` and `MldMessage` are flat value types; vector
  fields are parallel, never nested records.
- `Ok`/`Err` are constructed only in the small leaf helpers
  (`_ok_igmp`, `_err_igmp`, `_ok_mld`, `_err_mld`, `_ok_bytes`,
  `_err_bytes`); every other function returns their results.
- All byte reads widen with `(b as Int) & 0xFF`; all packing is
  arithmetic (`/`, `%`, and the `_be_byte` helper), never a bitwise
  operator on a value that may carry bit 31.
- `Vec[Int]` reads are bound to typed locals before use; `Str` values
  come only from `*_name` helpers and are compared with
  `xiom.string.compare.str_compare` in the tests (never `==`).
- `&struct.field` is never passed directly where `&Vec[UInt8]` is
  expected; a local copy is bound first (`mld_group`).
- Checksum assembly rebuilds the buffer positionally around the
  checksum bytes instead of assigning through `Vec` indices.
- The module header is `module xiom.multicast` without a semicolon; the
  only import is `use xiom.convert;` for `convert.int_to_string` in
  byte-offset error messages.
- Every parallel vector is pushed in the same order in all phases and
  every accessor guards each vector's length before reading.
