# xiom.multicast

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM codecs for the multicast group-management protocols:
> IGMPv1/v2/v3 (IPv4) and MLD/MLDv2 (IPv6) message parse/build, source
> lists and group records, one's-complement checksums.
> **Deps:** `xiom.std` only. The library module imports `xiom.convert` for
> decimal offsets in error strings; the tests use `xiom.test`, `xiom.io`,
> `xiom.string`, `xiom.string.compare`, `xiom.encoding.hex` and
> `xiom.convert`. No FFI, no sockets, no timers, no group state.

## What it is

`xiom.multicast` turns the wire formats of the multicast group-management
protocols into values and back:

- **IGMPv1/v2** (RFC 1112 / RFC 2236): the 8-byte Membership Query
  (`0x11`), v1 report (`0x12`), v2 report (`0x16`) and Leave Group
  (`0x17`), with the Max Resp Time octet and the 32-bit group address.
- **IGMPv3** (RFC 3376): the Membership Query with the Resv/S/QRV/QQIC
  suffix and source list, and the v3 Membership Report (`0x22`) with group
  records of types 1..6, per-record source lists and auxiliary data.
- **MLD** (RFC 2710, ICMPv6 types 130/131/132) and **MLDv2** (RFC 3810):
  the same query/report shapes over 128-bit IPv6 addresses. A type 130
  message of exactly 24 bytes is MLDv1; 28 or more bytes carry the MLDv2
  suffix. Type 143 is the MLDv2 report.
- **Checksums**: the IGMP 16-bit one's-complement checksum over the whole
  message, and the ICMPv6 checksum over the IPv6 pseudo-header plus the
  message (required by every MLD message).

The codec is a pure value codec: source lists and group records stay in the
source buffer and are located by absolute byte offsets; accessors copy
addresses and auxiliary data out on demand. Sockets, interface selection,
querier state machines and report suppression are the caller's job.

## Quick start

```xi
use xiom.multicast;
use xiom.io;

// Build an IGMPv2 Membership Query for 224.0.0.1, Max Resp 100 (10 s).
let qr = igmp_build_query_v2(3758096385, 100);
match qr {
  Ok(pkt) => { /* send pkt over IP protocol 2 */ },
  Err(e) => { io.println("query: " + e); },
}

// Parse an IGMPv3 report and walk its group records.
let reply: Vec[UInt8] = ...;
let pr = igmp_parse(&reply);
match pr {
  Ok(m) => {
    if m.version == 3 {
      var i = 0;
      while i < igmp_record_count(&m) {
        io.println(igmp_record_type_name(igmp_record_type(&m, i)));
        var k = 0;
        while k < igmp_record_source_count(&m, i) {
          io.println(xiom.convert.int_to_string(igmp_record_source_at(&reply, &m, i, k)));
          k = k + 1;
        }
        i = i + 1;
      }
    }
  },
  Err(e) => { io.println("parse error: " + e); },
}

// Build an MLDv1 report for ff3e::101 from fe80::1 to the group.
let src = ...;  // 16 bytes
let grp = ...;  // 16 bytes
let mr = mld_build_report_v1(&src, &grp, &grp);
```

## API

### Checksums and code decoding

| Function | Returns | Description |
|---|---|---|
| `igmp_checksum(data)` | `Int` | Complement of the 16-bit sum of `data`; pass the message with a zeroed checksum field to obtain the value to write. |
| `igmp_checksum_valid(data)` | `Bool` | True when the folded sum of the complete message is `0xFFFF`. |
| `icmpv6_checksum(src, dst, data)` | `Int` | Same over the IPv6 pseudo-header (`src`, `dst`, length, next header 58); `-1` when an address is not 16 bytes. |
| `icmpv6_checksum_valid(src, dst, data)` | `Bool` | Folded-sum check with the pseudo-header; false on a bad address length. |
| `igmp_max_resp_ms(code)` | `Int` | Decode an IGMP Max Resp Code octet to milliseconds (floating form above 127); `-1` out of range. |
| `igmp_qqic_seconds(code)` | `Int` | Decode an IGMP/MLD QQIC octet to seconds. |
| `mld_max_resp_ms(code)` | `Int` | Decode an MLDv2 16-bit Max Response Code to milliseconds. |
| `igmp_qrv_effective(raw)` | `Int` | Raw QRV, or 2 when the raw value is 0. |
| `igmp_is_multicast(addr)` | `Bool` | `addr` inside 224.0.0.0/4. |
| `mld_is_multicast(addr)` | `Bool` | 16-byte address starting with `0xFF`. |
| `igmp_message_name(t)` / `igmp_record_type_name(t)` / `mld_message_name(t)` | `Str` | Stable short names; `"unknown"` otherwise. |

### IGMP

| Function | Returns | Description |
|---|---|---|
| `igmp_parse(data)` | `Result[IgmpMessage, Str]` | Decode a query, v1/v2 report, leave or v3 report. |
| `igmp_version(m)` | `Int` | 1, 2 or 3 as assigned by the codec. |
| `igmp_query_variant(m)` | `Int` | 0 general, 1 group-specific, 2 group-and-source; `-1` for non-queries. |
| `igmp_source_at(data, m, k)` | `Int` | k-th v3 query source as an unsigned 32-bit Int; `-1` out of range. |
| `igmp_record_count(m)` | `Int` | Number of v3 report group records. |
| `igmp_record_type(m, i)` | `Int` | Record type (1..6); `-1` out of range. |
| `igmp_record_group(m, i)` | `Int` | Record group address; `-1` out of range. |
| `igmp_record_source_count(m, i)` | `Int` | Declared source count; `-1` out of range. |
| `igmp_record_aux_bytes(m, i)` | `Int` | Auxiliary data length in bytes; `-1` out of range. |
| `igmp_record_source_at(data, m, i, k)` | `Int` | k-th source of record `i`; `-1` out of range. |
| `igmp_record_aux(data, m, i)` | `Result[Vec[UInt8], Str]` | Copy record `i`'s auxiliary data. |
| `igmp_build_query_v2(group, max_resp)` | `Result[Vec[UInt8], Str]` | 8-byte query (code 0 also builds the v1 form). |
| `igmp_build_report_v1(group)` / `igmp_build_report_v2(group)` / `igmp_build_leave(group)` | `Result[Vec[UInt8], Str]` | 8-byte `0x12` / `0x16` / `0x17` messages. |
| `igmp_build_query_v3(group, max_resp, suppress, qrv, qqic, sources)` | `Result[Vec[UInt8], Str]` | v3 query with the suffix and source list. |
| `igmp_build_report_v3(record_types, groups, source_counts, sources, aux_data)` | `Result[Vec[UInt8], Str]` | v3 report from parallel record vectors; `sources` is flat. |

### MLD

| Function | Returns | Description |
|---|---|---|
| `mld_parse(data)` | `Result[MldMessage, Str]` | Decode a type 130/131/132/143 message. |
| `mld_version(m)` | `Int` | 1 or 2 (2 for a suffixed query or a type 143 report). |
| `mld_group(m)` | `Vec[UInt8]` | 16-byte group address (empty for a type 143 report). |
| `mld_query_variant(m)` | `Int` | 0 general, 1 group-specific, 2 group-and-source; `-1` for non-queries. |
| `mld_source_at(data, m, k)` | `Result[Vec[UInt8], Str]` | k-th 16-byte source of an MLDv2 query. |
| `mld_record_count(m)` / `mld_record_type(m, i)` / `mld_record_source_count(m, i)` / `mld_record_aux_bytes(m, i)` | `Int` | Record index accessors; `-1` out of range. |
| `mld_record_group(data, m, i)` / `mld_record_source_at(data, m, i, k)` / `mld_record_aux(data, m, i)` | `Result[Vec[UInt8], Str]` | Copy the record's 16-byte group, a source, or the auxiliary data. |
| `mld_build_query_v1(src, dst, group, max_delay)` | `Result[Vec[UInt8], Str]` | 24-byte type 130 query. |
| `mld_build_report_v1(src, dst, group)` / `mld_build_done(src, dst, group)` | `Result[Vec[UInt8], Str]` | 24-byte type 131 / 132 messages. |
| `mld_build_query_v2(src, dst, group, max_resp, suppress, qrv, qqic, sources)` | `Result[Vec[UInt8], Str]` | MLDv2 query (`28 + 16N` bytes). |
| `mld_build_report_v2(src, dst, record_types, groups, source_counts, sources, aux_data)` | `Result[Vec[UInt8], Str]` | Type 143 report; `groups`/`sources` hold 16-byte addresses, `sources` is flat. |

IPv4 addresses are unsigned 32-bit integers in an `Int` (`224.0.0.1` is
`3758096385`); IPv6 addresses are exactly 16 bytes. Parsed messages keep
source lists and records in the source buffer, so `data`-taking accessors
need the same buffer that was passed to the parser. The MLD builders take
the IPv6 source and destination addresses because the ICMPv6 checksum
covers the pseudo-header; a type 143 report's destination is normally the
group being reported.

## Error model

Every fallible call returns `Result[..., Str]` with one of these stable
messages (exact texts, byte offsets where the position is known; see
SPEC.md for the precise conditions):

| Error | Raised by |
|---|---|
| `igmp: short message` | `igmp_parse` when `data.len() < 8` |
| `igmp: bad message type at 0` | `igmp_parse` for a type other than 0x11/0x12/0x16/0x17/0x22 |
| `igmp: bad length at 8` | `igmp_parse` for a report/leave whose length is not 8 |
| `igmp: bad v3 query length at 8` | `igmp_parse` for a 9..11-byte query |
| `igmp: truncated source list at 12` | `igmp_parse` when the declared source count overruns the query |
| `igmp: trailing bytes at <end>` | `igmp_parse` when bytes follow the declared span |
| `igmp: bad record count at 6` | `igmp_parse` when the record count cannot fit the buffer |
| `igmp: truncated record at <pos>` | `igmp_parse` when a record header crosses the end |
| `igmp: bad record type at <pos>` | `igmp_parse` for a record type outside 1..6 |
| `igmp: truncated source list at <pos>` | `igmp_parse` when a record's source list crosses the end |
| `igmp: bad aux data length at <pos>` | `igmp_parse` when a record's auxiliary data crosses the end |
| `igmp: record index out of range` / `igmp: record out of bounds` | `igmp_record_aux` |
| `igmp: bad group address` | IGMP builders for an address outside 0..4294967295 |
| `igmp: bad max resp code` / `igmp: bad qrv` / `igmp: bad qqic` | query builders |
| `igmp: too many sources` / `igmp: bad source address` | query builders |
| `igmp: record vector length mismatch` / `igmp: too many records` | `igmp_build_report_v3` |
| `igmp: bad record type at index <i>` / `igmp: bad source count at index <i>` / `igmp: bad aux data length at index <i>` | `igmp_build_report_v3` |
| `igmp: source vector length mismatch` | `igmp_build_report_v3` when the flat source count differs from the sum |
| `mld: short message` | `mld_parse` when the buffer is below the type's minimum |
| `mld: bad message type at 0` | `mld_parse` for a type other than 130/131/132/143 |
| `mld: bad query length at 24` / `mld: bad length at 24` | `mld_parse` shape errors |
| `mld: truncated source list at 28` | `mld_parse` when the MLDv2 query source count overruns |
| `mld: trailing bytes at <end>` | `mld_parse` when bytes follow the declared span |
| `mld: bad record count at 6` | `mld_parse` when the record count cannot fit the buffer |
| `mld: truncated record at <pos>` / `mld: bad record type at <pos>` / `mld: truncated source list at <pos>` / `mld: bad aux data length at <pos>` | `mld_parse` record walk |
| `mld: source index out of range` / `mld: source out of bounds` / `mld: record index out of range` / `mld: record out of bounds` | MLD accessors |
| `mld: bad source address length` / `mld: bad destination address length` / `mld: bad group address length` | MLD builders for addresses that are not 16 bytes |
| `mld: bad max response delay` / `mld: bad max resp code` / `mld: bad qrv` / `mld: bad qqic` / `mld: too many sources` | MLD builders |
| `mld: record vector length mismatch` / `mld: too many records` / `mld: bad record type at index <i>` / `mld: bad source count at index <i>` / `mld: bad aux data length at index <i>` / `mld: source vector length mismatch` | `mld_build_report_v2` |

Parsers never fail on a bad checksum: `IgmpMessage.checksum_ok` carries the
IGMP verdict, and MLD messages expose the wire `checksum` value only (use
`icmpv6_checksum_valid` with the IPv6 addresses). Parsing is
all-or-nothing -- no partial message is returned.

## Limitations

- **Group management only.** This is not a socket API: joining/leaving
  groups, report suppression, querier election and interface management
  are out of scope, as are PIM, SSM channel semantics and IGMP proxying.
- **No streaming.** `*_parse` expects one complete message per buffer;
  there is no incremental parser and no IP-layer reassembly.
- **Trailing bytes are rejected.** Unlike a UDP datagram, the parsers
  require the buffer to end exactly where the declared structure ends.
- **Checksums are not verified at parse time** (IGMP exposes the verdict
  per message; MLD needs the IPv6 addresses from the caller).
- **Auxiliary data must be a whole number of 32-bit words** on build (the
  wire format cannot represent a partial word); at most 255 words per
  record.
- **Version detection is length/flag-based.** A type 130 message of 24
  bytes is MLDv1; 25..27 bytes are rejected. An IGMP query of 8 bytes with
  Max Resp Code 0 is reported as version 1.
- **IGMPv1 report is parse/build only as `0x12`**; there is no v1/v2
  compatibility state machine.
- Not thread-safe; parsed message types are plain value types over the
  source buffer.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.multicast
```

Expected: the namespace check passes, 18 `[PASS]` lines, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
