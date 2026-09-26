# xiom.snmp

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets) ASN.1 BER decoder plus an
> SNMPv1/v2c message parser and a minimal GetRequest/Response encoder, per
> RFC 1157 and RFC 3416. Covers the BER subset SNMP uses: one-byte tags,
> definite short/long-form lengths, INTEGER, OCTET STRING, NULL, OBJECT
> IDENTIFIER, SEQUENCE and the SMI application types IpAddress (0x40),
> Counter32 (0x41), Gauge32 (0x42), TimeTicks (0x43), Opaque (0x44) and
> Counter64 (0x46). Messages carry version 0 (v1) or 1 (v2c), a raw
> community and a PDU tagged 0xA0..0xA7.
> **Deps:** `xiom.std` only. The library module imports
> `xiom.string.builder`; the tests add `xiom.test`, `xiom.io`,
> `xiom.string`, `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.snmp` reads SNMP messages and writes the subset needed to ask a
question and answer it:

```
SEQUENCE {
  INTEGER version          -- 0 (v1) or 1 (v2c)
  OCTET STRING community   -- raw bytes, any value
  PDU 0xA0..0xA7 {
    request-id / error-status / error-index (or trap fields / bulk counters)
    SEQUENCE OF VarBind
  }
}
VarBind ::= SEQUENCE { OBJECT IDENTIFIER name, <typed value> }
```

`snmp_message_parse` validates the whole message, walks every varbind and
returns a flat `SnmpMessage` index; varbind values are not copied into the
index, `snmp_varbind_offset` + `snmp_varbind_parse` read them back from the
source buffer. The BER layer is exposed function by function
(`ber_length_decode`, `ber_tlv_decode`, `ber_int_decode`,
`ber_oid_decode`, ...), so callers can decode individual TLVs or build
their own structures on top.

On the write side `ber_int_encode`, `ber_uint_encode`,
`ber_octet_string_encode` and `ber_oid_encode` produce minimal BER TLVs,
and `snmp_get_request_build` / `snmp_response_build` emit complete
one-varbind messages that `snmp_message_parse` reads back byte-identically.
The trap form (0xA4) and the full GetBulk / multi-varbind builders are
decode-only in this version.

Every malformed input is rejected with a stable `Err(Str)` naming the byte
offset of the offending structure, for example
`ber: non-minimal integer at offset 12` or `snmp: bad pdu tag at offset 7`.

## Wire format

BER TLV (one-byte tags only):

| Field | Encoding |
|---|---|
| tag | 1 byte; low five bits 11111 (multi-byte tags) rejected |
| length | definite form: 1 byte below 128, else `0x80\|n` + n big-endian bytes (n = 1..8) |
| content | `length` raw bytes |

Documented tags:

| Tag | Type | Content rules |
|---|---|---|
| 0x02 | INTEGER | 1..8 bytes, minimal two's complement (0x00/0xFF sign-extension rejected) |
| 0x04 | OCTET STRING | any bytes, zero-length allowed |
| 0x05 | NULL | exactly 0 bytes |
| 0x06 | OBJECT IDENTIFIER | base-128 subidentifiers; first encodes X*40+Y; no leading 0x80 |
| 0x30 | SEQUENCE | nested TLVs |
| 0x40 | IpAddress | exactly 4 bytes |
| 0x41 / 0x42 / 0x43 | Counter32 / Gauge32 / TimeTicks | unsigned 0..4294967295 (one redundant leading zero byte tolerated) |
| 0x44 | Opaque | any bytes |
| 0x46 | Counter64 | unsigned; values above 2^63-1 are rejected (see limitations) |

PDU tags and field order:

| Tag | PDU | Fields after the tag |
|---|---|---|
| 0xA0 | GetRequest | request-id, error-status, error-index, varbinds |
| 0xA1 | GetNextRequest | same as GetRequest |
| 0xA2 | Response | same as GetRequest |
| 0xA3 | SetRequest | same as GetRequest |
| 0xA4 | Trap (v1) | enterprise OID, agent-addr IpAddress, generic-trap, specific-trap, time-stamp TimeTicks, varbinds |
| 0xA5 | GetBulkRequest | request-id, non-repeaters, max-repetitions, varbinds |
| 0xA6 | InformRequest | same as GetRequest |
| 0xA7 | SNMPv2-Trap | same as GetRequest |

Absent fields are exposed as `-1` in `SnmpMessage`: `request_id` on Trap v1,
`error_status`/`error_index` on Trap v1 and GetBulkRequest, and
`non_repeaters`/`max_repetitions` on every other kind.

## API

| Function | Returns | Description |
|---|---|---|
| `ber_length_decode(data, off)` | `Result[BerLength, Str]` | Decode a length field (`len`, `size`). |
| `ber_tlv_decode(data, off)` | `Result[BerTlv, Str]` | Decode a tag/length header and bounds-check the content. |
| `ber_int_decode(data, off)` | `Result[BerInt, Str]` | Signed minimal INTEGER. |
| `ber_octet_string_decode(data, off)` | `Result[BerBytes, Str]` | OCTET STRING bytes. |
| `ber_null_decode(data, off)` | `Result[Int, Str]` | NULL; returns the offset past it. |
| `ber_oid_decode(data, off)` | `Result[BerOid, Str]` | OID arc list. |
| `ber_ipaddress_decode(data, off)` | `Result[BerBytes, Str]` | 4-byte IpAddress. |
| `ber_opaque_decode(data, off)` | `Result[BerBytes, Str]` | Opaque bytes. |
| `ber_counter32_decode` / `ber_gauge32_decode` / `ber_timeticks_decode` | `Result[BerInt, Str]` | Unsigned 32-bit application values. |
| `ber_counter64_decode(data, off)` | `Result[BerInt, Str]` | Unsigned 64-bit value (bounded by Int). |
| `ber_length_encode(len)` | `Vec[UInt8]` | Minimal definite length bytes. |
| `ber_int_encode(value)` | `Vec[UInt8]` | Minimal signed INTEGER TLV. |
| `ber_uint_encode(value, tag)` | `Result[Vec[UInt8], Str]` | Unsigned application TLV (0x41/0x42/0x43/0x46). |
| `ber_octet_string_encode(bytes)` | `Vec[UInt8]` | OCTET STRING TLV. |
| `ber_oid_encode(arcs)` | `Result[Vec[UInt8], Str]` | OID TLV with X*40+Y and arc checks. |
| `snmp_value_decode(data, off)` | `Result[SnmpValue, Str]` | Type-dispatched varbind value. |
| `snmp_value_encode(value)` | `Result[Vec[UInt8], Str]` | Encode a `SnmpValue` TLV (`next` ignored). |
| `snmp_varbind_parse(data, off)` | `Result[SnmpVarBind, Str]` | SEQUENCE { OID, value }. |
| `snmp_message_parse(data)` | `Result[SnmpMessage, Str]` | Whole-message validation + varbind index. |
| `snmp_varbind_count(m)` | `Int` | Index size. |
| `snmp_varbind_offset(m, i)` | `Int` | Absolute offset of varbind `i`; -1 out of range. |
| `snmp_pdu_tag(kind)` / `snmp_pdu_kind(tag)` | `Int` | 0..7 <-> 0xA0..0xA7; -1 out of range. |
| `snmp_get_request_build(version, community, request_id, oid)` | `Result[Vec[UInt8], Str]` | One-varbind GetRequest (NULL value). |
| `snmp_response_build(version, community, request_id, oid, value)` | `Result[Vec[UInt8], Str]` | One-varbind Response. |

Types: `BerLength`, `BerTlv`, `BerInt`, `BerBytes`, `BerOid`, `SnmpValue`,
`SnmpVarBind`, `SnmpMessage`. Constants: `SNMP_VERSION_*`,
`SNMP_PDU_*` (0..7), `SNMP_TAG_*` (2, 4, 5, 6, 48, 64, 65, 66, 67, 68, 70)
and `SNMP_MAX_U32`.

## Usage

```xi
use xiom.snmp;
use xiom.string;

// "public" as raw bytes.
fn community() -> Vec[UInt8] {
  var c = Vec[UInt8].new();
  c.push(112); c.push(117); c.push(98);
  c.push(108); c.push(105); c.push(99);
  return c;
}

// Build and parse a v2c GetRequest for sysDescr.0 (1.3.6.1.2.1.1.1.0).
pub fn get_sysdescr() -> Result[Str, Str] {
  var oid = Vec[Int].new();
  oid.push(1); oid.push(3); oid.push(6); oid.push(1); oid.push(2);
  oid.push(1); oid.push(1); oid.push(1); oid.push(0);
  let comm = community();

  let br = snmp_get_request_build(SNMP_VERSION_V2C, &comm, 1234, &oid);
  if !br.is_ok {
    return Err("build failed");
  }
  let bytes: Vec[UInt8] = br.value;
  let pr = snmp_message_parse(&bytes);
  if !pr.is_ok {
    return Err(pr.error);
  }
  let m: SnmpMessage = pr.value;
  if snmp_varbind_count(&m) != 1 {
    return Err("expected one varbind");
  }
  let vb = snmp_varbind_parse(&bytes, snmp_varbind_offset(&m, 0));
  if !vb.is_ok {
    return Err(vb.error);
  }
  // Inspect vb.value: tag + int_val / bytes / oid.
  return Ok("parsed one varbind");
}
```

Response values are built with `SnmpValue`:

```xi
use xiom.snmp;

fn uptime_value(ticks: Int) -> SnmpValue {
  return SnmpValue{
    tag: SNMP_TAG_TIMETICKS;
    int_val: ticks;
    bytes: Vec[UInt8].new();
    oid: Vec[Int].new();
    next: 0;                // ignored by snmp_value_encode
  };
}
```

## Errors

All error strings are stable. BER errors point at the offending structure's
first byte (`ber: tag mismatch at offset 4`, `ber: non-minimal integer at
offset 12`, `ber: value overruns container at offset 20`, ...). The full
catalog is in SPEC.md; the message-level errors are
`snmp: unsupported version`, `snmp: bad pdu tag`, `snmp: trailing bytes`,
`snmp: bad pdu kind` and `snmp: trap build unsupported`. Encoder-side
errors carry no offset: `ber: oid needs two arcs`, `ber: bad first oid arc`,
`ber: negative unsigned value`, `ber: value too large`, ...

## Testing

`tests/test_conformance.xi` holds 19 synthetic-fixture tests (no external
data files): short/long-form lengths and their malformed variants, signed
and minimal INTEGERs, every OCTET STRING / NULL / Opaque / IpAddress /
OID boundary, all four application integer types, OID encode round-trips
for first-arc 0/1/2 and multi-byte subidentifiers, every PDU tag 0xA0..0xA7
(including the Trap v1 field order and the GetBulk counters), Trap/v2-Trap
varbinds, GetRequest/Response byte-pinned round-trips for all ten value
types, raw binary communities, and a matrix of malformed messages with
exact byte offsets.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.snmp
```

## Limitations

- No sockets, no session handling, no retransmission or request
  correlation: the codec reads and writes byte buffers only.
- SNMPv3 (RFC 3412/3414) is out of scope: versions other than 0 and 1 are
  rejected.
- Counter64 is stored in a signed 64-bit `Int`, so wire values above
  9223372036854775807 are rejected as `ber: value overflow`.
- Multi-byte BER tags, indefinite lengths and length fields above 63 bits
  are rejected.
- The message builder emits one varbind and supports every PDU kind except
  Trap v1 (`snmp: trap build unsupported`); multi-varbind and trap builders
  are not implemented.
- `error-status` / `error-index` / `request-id` are not range-checked
  semantically (they are BER-validated only).
- No MIB knowledge: OIDs and values are treated as opaque typed data.
- Non-minimal long-form lengths are accepted on decode (BER allows them);
  INTEGER and OID subidentifiers must be minimal.
