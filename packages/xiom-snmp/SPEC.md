# xiom.snmp -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.snmp`, version `0.1.0`).
Module: `src/snmp.xi` (`module xiom.snmp`).
Depends on `xiom.std`; the library module imports `xiom.string.builder`
(the tests add `xiom.test`, `xiom.io`, `xiom.string`,
`xiom.string.compare` and `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI, no sockets) codec for the ASN.1 BER subset SNMP uses,
plus SNMPv1 (RFC 1157) / SNMPv2c (RFC 3416) message parsing and a minimal
encoder:

- BER framing: one-byte tags, definite short/long-form lengths, the
  universal types INTEGER, OCTET STRING, NULL, OBJECT IDENTIFIER and
  SEQUENCE, and the SMI application types IpAddress (0x40), Counter32
  (0x41), Gauge32 (0x42), TimeTicks (0x43), Opaque (0x44) and Counter64
  (0x46);
- message parsing: `SEQUENCE { INTEGER version, OCTET STRING community,
  PDU }` with version 0 or 1, PDU tags 0xA0..0xA7, the Trap v1 field order,
  the GetBulk non-repeaters / max-repetitions fields, error-status /
  error-index and a validated per-varbind index;
- typed varbind values with per-varbind name (OID) and value;
- encoding: minimal INTEGER, unsigned application values, OCTET STRING and
  OBJECT IDENTIFIER TLVs, plus one-varbind GetRequest and Response message
  builders that round-trip through the parser;
- deterministic `Err(Str)` messages that name the byte offset of the
  offending structure for every malformed input and every invalid encoder
  argument.

## Non-goals

- Sockets, transports, retransmission, sessions, request/response
  correlation: the codec sees byte buffers only.
- SNMPv3 (RFC 3412 USM/VACM headers): versions other than 0/1 are rejected.
- Trap v1 encoding, multi-varbind message builders, and builders for PDU
  kinds beyond the minimal GetRequest/Response pair (the internal shared
  builder covers kinds 0, 1, 2, 3, 5, 6, 7 with one varbind; kind 4 is
  decode-only).
- MIB knowledge, OID name resolution, error-status semantics and
  value-range semantics beyond the wire representation.
- Multi-byte BER tags, indefinite lengths, and length fields wider than
  63 bits.
- Counter64 values above 9223372036854775807 (the package stores them in a
  signed 64-bit `Int`).
- Text decoding: the community is kept as raw bytes and no value is
  interpreted as UTF-8.

## Byte-level layout

### BER TLV framing

| Field | Size | Encoding |
|---|---|---|
| tag | 1 | one byte; a tag whose low five bits are 11111 is rejected |
| length | 1..9 | definite form only |
| content | `length` | raw bytes |

The length field is one byte below 128. For 128 and above it is `0x80 | n`
followed by `n` big-endian length bytes with `n` in 1..8; the accumulated
value must fit a signed 64-bit Int (the top bit of an 8-byte length must be
0). Non-minimal long forms such as `0x82 0x00 0x05` are accepted on decode
(BER permits them); the indefinite form `0x80` is rejected. The declared
content must fit the buffer (`ber_tlv_decode`), and every nested structure
must also fit its container (see "Container rules").

### INTEGER (0x02)

Content must be 1..8 bytes and minimally encoded. Non-minimal forms are
rejected when the first two bytes are `00 00..7F` or `FF 80..FF`. The value
is the two's complement of the content, sign-extended from the first byte;
8-byte content spans the full `Int` range. A 9-byte content is
`ber: integer overflow`. A zero-byte content is `ber: empty integer`.

### OCTET STRING (0x04), NULL (0x05), Opaque (0x44)

OCTET STRING and Opaque copy their content verbatim; any length including
zero is valid. NULL must have zero-length content; anything else is
`ber: bad null`. Content bytes are never converted to `Str`, so a
community or value may contain 0x00 and any other byte value.

### OBJECT IDENTIFIER (0x06)

Content is a sequence of base-128 subidentifiers (high bit = continue).
Decoding rejects:

- empty content (`ber: empty oid`);
- a subidentifier whose first byte is the continuation-only `0x80`
  (`ber: non-minimal oid subidentifier`);
- a subidentifier that never terminates before the content end
  (`ber: truncated oid subidentifier`);
- an accumulated subidentifier above 2^56-1 before the next multiply
  (`ber: oid subidentifier overflow`).

The first subidentifier `v` splits into the first two arcs: `v < 40` gives
`(0, v)`; `v < 80` gives `(1, v-40)`; otherwise `(2, v-80)`. The decoded
arc list therefore always has at least two entries.

Encoding requires at least two arcs; the first arc must be 0, 1 or 2; the
second arc must be 0..39 when the first arc is 0 or 1, and must be >= 0 and
at most 9223372036854775727 (so `X*40+Y` cannot overflow) when the first
arc is 2; every remaining arc must be >= 0. Subidentifiers are written
minimally with the continuation bit set on every byte but the last.

### SMI application types

| Tag | Type | Content rules (decode) |
|---|---|---|
| 0x40 | IpAddress | exactly 4 bytes, else `ber: bad ipaddress` |
| 0x41 | Counter32 | unsigned 0..4294967295 |
| 0x42 | Gauge32 | unsigned 0..4294967295 |
| 0x43 | TimeTicks | unsigned 0..4294967295 |
| 0x46 | Counter64 | unsigned; must fit a signed 64-bit `Int` |

The application integer decoders accept one or more content bytes, skip
leading zero bytes (one redundant `0x00` is tolerated, as real agents emit
for values with the high bit set), reject an all-zero-length content as
`ber: empty integer`, and reject more significant bytes than the type
allows (`ber: value overflow`: more than 4 significant bytes for the 32-bit
types, more than 8 for Counter64) or an accumulation that does not fit
(`ber: value overflow`, Counter64 above 2^63-1).

### Message and PDU

```
Message ::= SEQUENCE {
  version   INTEGER,             -- 0 (v1) or 1 (v2c), else rejected
  community OCTET STRING,        -- raw bytes
  pdu       [0xA0..0xA7] IMPLICIT PDU
}
```

PDU field order by tag:

| Tag | Kind | Constant | Fields |
|---|---|---|---|
| 0xA0 | 0 | `SNMP_PDU_GET_REQUEST` | request-id, error-status, error-index, varbinds |
| 0xA1 | 1 | `SNMP_PDU_GET_NEXT_REQUEST` | same |
| 0xA2 | 2 | `SNMP_PDU_RESPONSE` | same |
| 0xA3 | 3 | `SNMP_PDU_SET_REQUEST` | same |
| 0xA4 | 4 | `SNMP_PDU_TRAP_V1` | enterprise OID, agent-addr IpAddress, generic-trap, specific-trap, time-stamp TimeTicks, varbinds |
| 0xA5 | 5 | `SNMP_PDU_GET_BULK_REQUEST` | request-id, non-repeaters, max-repetitions, varbinds |
| 0xA6 | 6 | `SNMP_PDU_INFORM_REQUEST` | same as GetRequest |
| 0xA7 | 7 | `SNMP_PDU_SNMPV2_TRAP` | same as GetRequest |

A PDU tag outside 0xA0..0xA7 is `snmp: bad pdu tag` at the tag byte. The
second and third integers are exposed under their per-kind names
(`error_status`/`error_index` or `non_repeaters`/`max_repetitions`); fields
that the kind does not carry are -1, as is `request_id` on Trap v1.

### Varbind

```
VarBind ::= SEQUENCE { name OBJECT IDENTIFIER, value <any supported tag> }
```

The variable-bindings list is a SEQUENCE of zero or more varbinds inside
the PDU. `snmp_message_parse` records the absolute offset of each varbind
SEQUENCE in `varbind_offsets`; `snmp_varbind_parse(data, off)` decodes one.
The value tag must be 0x02, 0x04, 0x05, 0x06, 0x40, 0x41, 0x42, 0x43, 0x44
or 0x46, else `ber: unsupported value tag` at the value TLV. The decoded
`SnmpValue` keeps the wire tag in `tag` and fills `int_val`, `bytes` or
`oid` according to the tag; unused fields stay empty/zero.

### Container rules

Every nested TLV must end at or before its container's end:

- a version/error/community/PDU field crossing the message SEQUENCE end is
  `ber: value overruns container` at the field's first byte;
- a PDU crossing the message SEQUENCE end likewise;
- a PDU field crossing the PDU end likewise;
- the varbind list crossing the PDU end likewise;
- a varbind crossing the list end likewise;
- a varbind name or value crossing the varbind SEQUENCE end likewise.

If a container declares more bytes than its fields consume, the leftover is
`snmp: trailing bytes` at the first leftover byte. This applies inside the
message SEQUENCE (after the PDU), inside the PDU (after the varbind list)
and inside a varbind SEQUENCE (after the value). Bytes **after** the
outermost message TLV are ignored, so a datagram carrying trailing junk
still parses; `SnmpMessage.next` points just past the message TLV.

### Offset convention

`at offset N` in a BER error names the first byte of the structure being
decoded: the tag byte for TLV-level errors and for `ber: tag mismatch`,
`ber: unsupported value tag`, `ber: bad ipaddress` and `ber: bad null`; the
TLV's first byte for content-level errors (`ber: empty integer`,
`ber: non-minimal integer`, `ber: integer overflow`, `ber: value overflow`,
`ber: empty oid`, `ber: non-minimal oid subidentifier`,
`ber: truncated oid subidentifier`, `ber: oid subidentifier overflow`). The
two exceptions are `ber_length_decode`, whose offsets name the first length
byte, and `snmp: unsupported version`, which names the version INTEGER TLV.
Encoder errors carry no offset.

## API signatures

All functions are free functions in module `xiom.snmp`:

```xi
pub type BerLength = { len: Int; size: Int; }
pub type BerTlv = { tag: Int; len: Int; size: Int; content: Int; next: Int; }
pub type BerInt = { value: Int; next: Int; }
pub type BerBytes = { bytes: Vec[UInt8]; next: Int; }
pub type BerOid = { arcs: Vec[Int]; next: Int; }
pub type SnmpValue = { tag: Int; int_val: Int; bytes: Vec[UInt8]; oid: Vec[Int]; next: Int; }
pub type SnmpVarBind = { name: Vec[Int]; value: SnmpValue; next: Int; }
pub type SnmpMessage = {
  version: Int;
  community: Vec[UInt8];
  community_offset: Int;
  community_length: Int;
  pdu_tag: Int;
  pdu_kind: Int;
  request_id: Int;
  error_status: Int;
  error_index: Int;
  non_repeaters: Int;
  max_repetitions: Int;
  enterprise: Vec[Int];
  agent_addr: Vec[UInt8];
  generic_trap: Int;
  specific_trap: Int;
  timestamp: Int;
  varbind_offsets: Vec[Int];
  pdu_offset: Int;
  next: Int;
}

pub fn ber_length_decode(data: &Vec[UInt8], off: Int) -> Result[BerLength, Str]
pub fn ber_tlv_decode(data: &Vec[UInt8], off: Int) -> Result[BerTlv, Str]
pub fn ber_int_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str]
pub fn ber_octet_string_decode(data: &Vec[UInt8], off: Int) -> Result[BerBytes, Str]
pub fn ber_null_decode(data: &Vec[UInt8], off: Int) -> Result[Int, Str]
pub fn ber_oid_decode(data: &Vec[UInt8], off: Int) -> Result[BerOid, Str]
pub fn ber_ipaddress_decode(data: &Vec[UInt8], off: Int) -> Result[BerBytes, Str]
pub fn ber_opaque_decode(data: &Vec[UInt8], off: Int) -> Result[BerBytes, Str]
pub fn ber_counter32_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str]
pub fn ber_gauge32_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str]
pub fn ber_timeticks_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str]
pub fn ber_counter64_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str]
pub fn ber_length_encode(len: Int) -> Vec[UInt8]
pub fn ber_int_encode(value: Int) -> Vec[UInt8]
pub fn ber_uint_encode(value: Int, tag: Int) -> Result[Vec[UInt8], Str]
pub fn ber_octet_string_encode(bytes: &Vec[UInt8]) -> Vec[UInt8]
pub fn ber_oid_encode(arcs: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn snmp_value_decode(data: &Vec[UInt8], off: Int) -> Result[SnmpValue, Str]
pub fn snmp_value_encode(value: &SnmpValue) -> Result[Vec[UInt8], Str]
pub fn snmp_varbind_parse(data: &Vec[UInt8], off: Int) -> Result[SnmpVarBind, Str]
pub fn snmp_message_parse(data: &Vec[UInt8]) -> Result[SnmpMessage, Str]
pub fn snmp_varbind_count(m: &SnmpMessage) -> Int
pub fn snmp_varbind_offset(m: &SnmpMessage, i: Int) -> Int
pub fn snmp_pdu_tag(kind: Int) -> Int
pub fn snmp_pdu_kind(tag: Int) -> Int
pub fn snmp_get_request_build(version: Int, community: &Vec[UInt8], request_id: Int, oid: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn snmp_response_build(version: Int, community: &Vec[UInt8], request_id: Int, oid: &Vec[Int], value: &SnmpValue) -> Result[Vec[UInt8], Str]
```

Exported constants: `SNMP_VERSION_V1` (0), `SNMP_VERSION_V2C` (1),
`SNMP_PDU_GET_REQUEST`..`SNMP_PDU_V2_TRAP` (0..7), `SNMP_TAG_INTEGER` (2),
`SNMP_TAG_OCTET_STRING` (4), `SNMP_TAG_NULL` (5), `SNMP_TAG_OID` (6),
`SNMP_TAG_SEQUENCE` (48), `SNMP_TAG_IPADDRESS` (64),
`SNMP_TAG_COUNTER32` (65), `SNMP_TAG_GAUGE32` (66),
`SNMP_TAG_TIMETICKS` (67), `SNMP_TAG_OPAQUE` (68),
`SNMP_TAG_COUNTER64` (70) and `SNMP_MAX_U32` (4294967295).

## Semantics

`ber_length_decode(data, off)`
: Decode the length field at `off`. Short form below 128; long form `0x80|n`
  with 1 <= n <= 8; `0x80` is `ber: indefinite length`; `n > 8` or an
  accumulated value that does not fit a signed 64-bit Int is
  `ber: length overflow`; missing bytes are `ber: truncated length`; a
  negative `off` is `ber: negative offset`. The returned `size` counts the
  length bytes only.

`ber_tlv_decode(data, off)`
: Decode tag and length and check `content + len <= data.len()`. The low
  five tag bits 11111 are `ber: multi-byte tag`. A value crossing the buffer
  is `ber: value overruns buffer` at `off`. `size` counts tag plus length
  bytes; `content` is `off + size`; `next` is `content + len`.

`ber_int_decode(data, off)`
: `ber_tlv_decode`, tag must be 0x02 (`ber: tag mismatch`), then the
  INTEGER rules above.

`ber_octet_string_decode(data, off)` / `ber_opaque_decode(data, off)`
: Tag 0x04 / 0x44, then copy the content verbatim (zero length allowed).

`ber_null_decode(data, off)`
: Tag 0x05 with zero-length content; returns the offset past the TLV.

`ber_oid_decode(data, off)`
: Tag 0x06, then the OID rules above.

`ber_ipaddress_decode(data, off)`
: Tag 0x40 with exactly 4 content bytes.

`ber_counter32_decode` / `ber_gauge32_decode` / `ber_timeticks_decode` /
`ber_counter64_decode`
: Tag 0x41 / 0x42 / 0x43 / 0x46 plus the unsigned rules above (4 or 8
  significant bytes).

`ber_length_encode(len)`
: Negative `len` yields an empty vector (documented as a caller error).
  Below 128 it is one byte; otherwise `0x80|n` plus the minimal big-endian
  value.

`ber_int_encode(value)`
: Minimal signed two's complement content (positive values get a `0x00`
  prefix when the top content byte has bit 7 set; negative values use the
  shortest sign-extended form), wrapped as tag 0x02 + definite length.

`ber_uint_encode(value, tag)`
: `tag` must be 0x41, 0x42, 0x43 or 0x46 (`ber: bad unsigned tag`);
  negative values are `ber: negative unsigned value`; a value above
  4294967295 on the 32-bit tags is `ber: value too large`. The content is
  the minimal big-endian unsigned value, where 0 is one `0x00` byte.

`ber_octet_string_encode(bytes)`
: Tag 0x04 + definite length + the bytes.

`ber_oid_encode(arcs)`
: The arc rules above; error order is `ber: oid needs two arcs`,
  `ber: bad first oid arc`, `ber: bad second oid arc`,
  `ber: negative oid arc` (checked per remaining arc while writing).

`snmp_value_decode(data, off)`
: `ber_tlv_decode`, then dispatch on the tag: INTEGER and the four
  application integer tags use their value rules; OCTET STRING, IpAddress
  and Opaque copy bytes; NULL requires zero length; OID decodes arcs. Any
  other tag is `ber: unsupported value tag` at `off`. The returned `next`
  is the offset past the value TLV.

`snmp_value_encode(value)`
: The inverse of `snmp_value_decode` for the supported tags; `value.next`
  is ignored. IpAddress requires exactly 4 bytes
  (`ber: bad ipaddress`); integers use `ber_uint_encode` rules; OIDs use
  `ber_oid_encode` rules. Unknown tags are `ber: unsupported value tag`.

`snmp_varbind_parse(data, off)`
: Decode SEQUENCE { OID, value }. Checks in order: the TLV must be a
  SEQUENCE (`ber: tag mismatch` at `off`); the name must be an OID; the
  name must not cross the SEQUENCE end; the value must decode and must not
  cross the SEQUENCE end; the value must end exactly at the SEQUENCE end
  (`snmp: trailing bytes` at the value's `next`). `next` is the SEQUENCE's
  `next`.

`snmp_message_parse(data)`
: Checks in order:
  1. the top TLV decodes and is a SEQUENCE (`ber: tag mismatch` at 0);
  2. the version INTEGER is inside the message container, is minimally
     encoded and equals 0 or 1 (`snmp: unsupported version` at the version
     TLV, `ber: value overruns container` at the version TLV when it
     crosses the message end);
  3. the community is an OCTET STRING inside the message (its `next` may
     not exceed `msg.next`); when it leaves no room for a PDU the parser
     reports `ber: truncated tag` at `community.next`;
  4. the PDU byte at `community.next` is 0xA0..0xA7
     (`snmp: bad pdu tag` at that byte);
  5. the PDU TLV decodes and ends exactly at the message end
     (`ber: value overruns container` / `snmp: trailing bytes`);
  6. the PDU fields decode per kind, each bounded by the PDU end;
  7. the varbind list is a SEQUENCE inside the PDU (`ber: tag mismatch` at
     its offset);
  8. each varbind is validated by `snmp_varbind_parse` and must end at or
     before the list end (`ber: value overruns container` at the varbind
     offset);
  9. the list must end exactly at the PDU end (`snmp: trailing bytes` at
     the list end).
  On success the index carries the version, the raw community bytes and
  their absolute offset/length, the PDU tag/kind/offset, the per-kind
  fields (-1 when absent), the trap fields, the varbind offsets and `next`
  (the offset just past the message TLV; trailing bytes after it are
  ignored).

`snmp_varbind_count(m)` / `snmp_varbind_offset(m, i)`
: Index size and the absolute offset of varbind `i`; offsets are -1 for a
  negative or out-of-range `i`.

`snmp_pdu_tag(kind)` / `snmp_pdu_kind(tag)`
: Pure mapping between kinds 0..7 and tags 0xA0..0xA7; -1 out of range.

`snmp_get_request_build(version, community, request_id, oid)`
: A GetRequest with one NULL varbind; error-status and error-index are 0.

`snmp_response_build(version, community, request_id, oid, value)`
: A Response with one varbind carrying `value`; error-status and
  error-index are 0. Both builders reject `version` outside 0..1 with
  `snmp: unsupported version` and propagate the OID/value encoder errors;
  community bytes are written verbatim and may contain 0x00.

The internal shared builder also accepts kinds 1, 3, 5, 6 and 7 (for kind 5
the second and third integers are the non-repeaters and max-repetitions)
and rejects kind 4 with `snmp: trap build unsupported`; only the two public
wrappers above are supported API.

## Error string catalog

| Condition | Error text |
|---|---|
| any decoder: `off < 0` | `ber: negative offset` |
| `ber_tlv_decode`/decoders: no tag byte at `off` | `ber: truncated tag at offset N` |
| tag low five bits 11111 | `ber: multi-byte tag at offset N` |
| length field missing bytes | `ber: truncated length at offset N` |
| length byte 0x80 | `ber: indefinite length at offset N` |
| more than 8 length bytes / length above 2^63-1 | `ber: length overflow at offset N` |
| declared content crosses the buffer | `ber: value overruns buffer at offset N` |
| nested TLV crosses its container | `ber: value overruns container at offset N` |
| unexpected tag in a typed decoder | `ber: tag mismatch at offset N` |
| INTEGER content empty | `ber: empty integer at offset N` |
| INTEGER content above 8 bytes | `ber: integer overflow at offset N` |
| INTEGER not minimal | `ber: non-minimal integer at offset N` |
| NULL with non-empty content | `ber: bad null at offset N` |
| OID content empty | `ber: empty oid at offset N` |
| OID subidentifier starts with 0x80 | `ber: non-minimal oid subidentifier at offset N` |
| OID subidentifier unterminated | `ber: truncated oid subidentifier at offset N` |
| OID subidentifier above 2^56-1 | `ber: oid subidentifier overflow at offset N` |
| IpAddress not 4 bytes | `ber: bad ipaddress at offset N` |
| application integer empty / too many significant bytes / above Int | `ber: value overflow at offset N` (empty: `ber: empty integer`) |
| varbind value tag unsupported | `ber: unsupported value tag at offset N` |
| container leftover bytes | `snmp: trailing bytes at offset N` |
| message version != 0/1 | `snmp: unsupported version at offset N` |
| PDU tag outside 0xA0..0xA7 | `snmp: bad pdu tag at offset N` |
| encoder: OID fewer than 2 arcs | `ber: oid needs two arcs` |
| encoder: first arc outside 0..2 | `ber: bad first oid arc` |
| encoder: second arc bad for the first | `ber: bad second oid arc` |
| encoder: remaining arc negative | `ber: negative oid arc` |
| encoder: unsigned tag not 0x41/0x42/0x43/0x46 | `ber: bad unsigned tag` |
| encoder: unsigned value negative | `ber: negative unsigned value` |
| encoder: 32-bit unsigned value above 4294967295 | `ber: value too large` |
| encoder: IpAddress not 4 bytes | `ber: bad ipaddress` |
| encoder: unsupported `SnmpValue.tag` | `ber: unsupported value tag` |
| builder: version outside 0..1 | `snmp: unsupported version` |
| builder: kind outside 0..7 | `snmp: bad pdu kind` |
| builder: kind 4 | `snmp: trap build unsupported` |

All error strings are stable API. The check order documented under
"Semantics" decides which error wins when several apply.

## Complexity

| Operation | Complexity |
|---|---|
| `ber_length_decode` / `ber_tlv_decode` | O(length bytes) / O(1) after the length |
| typed BER decoders | O(content bytes) |
| `snmp_value_decode` / `snmp_value_encode` | O(value bytes) |
| `snmp_varbind_parse` | O(name + value bytes) |
| `snmp_message_parse` | O(message bytes) time and space for the index |
| `snmp_varbind_count` / `snmp_varbind_offset` | O(1) |
| `snmp_pdu_tag` / `snmp_pdu_kind` | O(1) |
| BER/uint encoders | O(content bytes) |
| `snmp_get_request_build` / `snmp_response_build` | O(oid + community + value bytes) |

`snmp_message_parse` records offsets only; varbind values stay in the
source buffer until `snmp_varbind_parse` copies them out.

## Test plan

`tests/test_conformance.xi` (`module snmp_tests`, 19 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). All fixtures are synthetic: hex strings decoded
in-test plus messages assembled from the library's own encoders. No
external data files.

1. BER length: short form 0/1/127; long form 1/2/3 length bytes
   (128, 33023, 256, 5), trailing bytes, non-minimal long form accepted;
   truncated (empty, `81`, `8201`), indefinite (`80`), overflow
   (`88 FF*8`, `89 00*9`), negative offset and out-of-range offset.
2. BER TLV: header fields of `02 01 05`, empty `30 00`, trailing byte,
   128-byte content with `81 80`; multi-byte tags `1F`/`FF`; content
   overrunning the buffer; truncated tag, truncated length (`04 82 01`),
   length overflow (`04 89 ...`).
3. INTEGER decode: 0, 127, 128, 255, 256, -128, -1, -129, -256, 2^56,
   Int max, Int min; empty, non-minimal (`00 7F` and `FF FF`), 9-byte
   overflow, tag mismatch, truncated length.
4. OCTET STRING / NULL / Opaque / IpAddress: non-empty and empty strings,
   binary content with 0x00/0xFF, NULL next offset, bad NULL, tag
   mismatch, Opaque binary and empty, IpAddress 4 bytes, 3-byte and
   0-byte IpAddress rejected.
5. OID decode: first-arc split at 39/40 (0.39, 1.0), 79/80 (1.39, 2.0,
   2.1), 1.3.6.1, multi-byte 128 (`81 00`) and 16384 (`81 80 00`), large
   second arc 4294967295, trailing byte; empty, truncated, non-minimal
   (`80 01`), subidentifier overflow (`FF * 12`), tag mismatch.
6. OID encode: pinned bytes for 1.3.6.1, 0.0, 0.39, 1.0, 2.0, 2.16384,
   2.4294967295 and 1.3.128; errors for one arc, first arc 3/-1, second
   arc 40 for arc 0, second arc -1 for arc 2, negative third arc; decode
   round-trip of 1.3.6.1.2.1.1.1.0.
7. Counter32/Gauge32/TimeTicks/Counter64: 0xFFFFFFFF, 127, redundant
   leading zero, Gauge 256, TimeTicks 65536/256, Counter64 Int max and 5;
   overflow (5 significant bytes, 2^63, 9 bytes with a leading zero),
   empty, tag mismatches.
8. INTEGER encode: pinned bytes for 0, 127, 128, 255, 256, -1, -128,
   -129, -256, Int min, Int max; encode/decode round-trip over ten values
   including +/-2^56 and 4294967295.
9. GetRequest build: pinned 41-byte message with the sysDescr.0 OID,
   version/community/PDU/kind/request-id/error fields, community bytes,
   one NULL varbind, `next` == length.
10. Response build: INTEGER -42 round-trips through parse and byte-identical
    rebuild.
11. Every value type (INTEGER, OCTET STRING, NULL, OID, IpAddress,
    Counter32, Gauge32, TimeTicks, Opaque, Counter64) round-trips through
    the Response builder with name and value fields compared.
12. PDU tags 0xA0..0xA7: kinds 0, 1, 2, 3, 6, 7 with request-id/error
    fields; GetBulk non-repeaters=2 / max-repetitions=10 with
    error fields = -1; tag/kind mapping for every kind.
13. Trap v1: enterprise 1.3.6.1.4, agent-addr 192.0.2.1, generic 6,
    specific 2, timestamp 256, request-id/error fields -1, empty varbinds.
14. SNMPv2-Trap with two varbinds: sysUpTime.0 (TimeTicks 256) and
    snmpTrapOID (OID value), ordered offsets, typed values.
15. Malformed messages (exact offsets): empty input, top tag not SEQUENCE,
    version tag OCTET STRING, version 2, PDU tag 0xA8 and 0x30, trailing
    byte after the PDU (offset 26), trailing byte after the varbind list
    inside the PDU (offset 26), PDU crossing the message SEQUENCE (offset
    7), PDU TLV crossing the buffer (offset 7).
16. Malformed varbinds (exact offsets): varbind not a SEQUENCE (26), name
    not an OID (28), value tag 0x45 (33), extra bytes after the value
    (35), name crossing the varbind SEQUENCE (28).
17. Encoders: pinned `snmp_value_encode` bytes for all ten tags; errors
    for tag 0x99, 3-byte IpAddress, negative unsigned, 2^32 unsigned,
    one-arc OID; `ber_length_encode` 0/127/128/300/-1; `ber_uint_encode`
    tag/negative/too-large errors and 0xFFFFFFFF/0 pins.
18. Community: bytes `00 FF 80 7F 41` (NUL, high bytes) survive v1
    GetRequest build/parse with `community_offset` 7, `community_length`
    5; an all-NUL community survives a v2c Response.
19. Accessors: `snmp_pdu_tag`/`snmp_pdu_kind` mapping and -1 guards;
    two-varbind message counts and ordered offsets; -1 guards for
    negative/out-of-range indexes; empty varbind list has offset -1.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.snmp
```

Last verified: compiler 0.61.3,
`port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No transport: callers move bytes; UDP/TCP framing and retries are not
  part of this package.
- SNMPv3 is out of scope; versions other than 0/1 are rejected.
- Counter64 values above 9223372036854775807 cannot be represented and are
  rejected on decode (`ber: value overflow`) and cannot be built.
- Multi-byte BER tags, indefinite lengths, and length fields above 63 bits
  are rejected.
- The message builder supports one varbind and every kind except Trap v1;
  multi-varbind and trap builders are not implemented.
- `error-status`, `error-index` and `request-id` are BER-validated but not
  range-checked against RFC 3416 (e.g. error-status 99 parses).
- The community is never interpreted as text; NUL bytes are preserved.
- Non-minimal long-form lengths are accepted on decode (BER allows them),
  while INTEGER content and OID subidentifiers must be minimal.
- `SnmpMessage` is a plain value type over the source bytes; varbind
  accessors require the buffer the message was parsed from (or one holding
  at least the recorded offsets).
- Not thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_blen`/`_err_blen`, `_ok_tlv`/`_err_tlv`, `_ok_bint`/`_err_bint`,
  `_ok_bbytes`/`_err_bbytes`, `_ok_oid`/`_err_oid`, `_ok_arcs`/`_err_arcs`,
  `_ok_value`/`_err_value`, `_ok_vb`/`_err_vb`, `_ok_msg`/`_err_msg`,
  `_ok_bytes`/`_err_bytes` and `_ok_int`/`_err_int` (constructing Results
  directly inside larger functions miscompiles).
- Free functions only: no methods, no lambdas, no `Vec[StructType]`; the
  message index uses parallel `Vec[Int]`/`Vec[UInt8]` fields and constants
  plus if/elif dispatch (indexed `Vec[fn]` calls miscompile).
- Every byte read from a `Vec[UInt8]` is widened with
  `(data[pos] as Int) & 0xFF`; PDU tags 0xA0..0xA7 are only compared as
  widened Ints (comparing a UInt8 byte to a constant >= 128 mislowers).
- `Vec[Int]` element reads are bound to typed locals before use, and no
  `Str` value is read from a `Vec` or compared with `==` in the module;
  error text is assembled with `xiom.string.builder`.
- `&struct.field` expressions are never passed as `&Vec[...]` parameters;
  fields are bound to locals first (e.g. the community bytes and value
  vectors in `snmp_value_encode` and the message builders).
- All length/width arithmetic is division/modulo based; no bitwise operator
  is used, and negative `Int` two's complement encoding subtracts the
  positive remainder before dividing (truncating division would not
  terminate).
- No struct is constructed inside a function that returns a non-struct
  scalar `Result` except for the documented `SnmpValue` locals in the
  builders; `SnmpValue.next` is explicitly documented as ignored on
  encode.
- The tests route every `Str` comparison through
  `xiom.string.compare.str_compare` and call their 19 test functions
  directly from `main` (no `Vec[fn]` dispatch).
- The package declares no `extern "C"` blocks (no FFI).

