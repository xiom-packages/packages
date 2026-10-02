# xiom.upnp

> **Status:** `stable` -- conformance-tested (18/18); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI) codec for the SSDP messages of UPnP device
> discovery -- M-SEARCH requests, NOTIFY notifications (`ssdp:alive`,
> `ssdp:byebye`, `ssdp:update`) and HTTP/1.1 200 search responses. Parsing,
> typed extraction, USN / ST / NT classification and canonical
> serialisation. No sockets, no multicast, no XML device descriptions and
> no SOAP control.
> **Deps:** `xiom.std` only. The library module imports `xiom.string`,
> `xiom.string.compare` and `xiom.convert.int`; the tests add `xiom.test`
> and `xiom.io`.

## What it is

`xiom.upnp` reads and writes the datagram messages that drive UPnP
discovery (UPnP Device Architecture 1.0/1.1, "SSDP"). It is a codec: it
turns bytes into a flat `SsdpMessage` value and back, and it validates the
documented structure on the way in.

| Form | Start line | Required headers |
|---|---|---|
| M-SEARCH request | `M-SEARCH * HTTP/1.1` | HOST, MAN, MX, ST (USER-AGENT optional) |
| NOTIFY `ssdp:alive` | `NOTIFY * HTTP/1.1` | HOST, CACHE-CONTROL (max-age >= 1), LOCATION, NT, NTS, USN |
| NOTIFY `ssdp:byebye` | `NOTIFY * HTTP/1.1` | HOST, NT, NTS, USN |
| NOTIFY `ssdp:update` | `NOTIFY * HTTP/1.1` | HOST, NT, NTS, USN, BOOTID.UPNP.ORG |
| Search response | `HTTP/1.1 200 OK` | CACHE-CONTROL, DATE, EXT, LOCATION, ST, USN (SERVER optional) |

Every header is kept, in wire order, in parallel `names` / `values` /
`header_offsets` vectors; header names are matched ASCII
case-insensitively everywhere and the as-sent casing is preserved.
The documented fields (HOST, MAN, MX, ST, USER-AGENT, NT, NTS, USN,
LOCATION, SERVER, DATE, EXT, CACHE-CONTROL, max-age, BOOTID.UPNP.ORG,
CONFIGID.UPNP.ORG, SEARCHPORT.UPNP.ORG) are also decoded into typed
struct fields.

Two standalone classifiers do the UPnP-aware work:

* `usn_split` parses `uuid:<id>`, `uuid:<id>::urn:...`,
  `uuid:<id>::upnp:rootdevice` and bare `urn:...` USNs;
* `upnp_classify_target` classifies `ssdp:all`, `upnp:rootdevice`,
  `uuid:<id>` and `urn:<domain>:device|service:<type>:<ver>` ST/NT values.

The two serialisers (`upnp_build_msearch`, `upnp_build_notify_alive`)
write canonical header-name casing and CRLF line endings, and their output
parses back through `upnp_parse` (round-trip is covered by the tests).

## API

| Function | Returns | Description |
|---|---|---|
| `upnp_parse(data)` | `Result[SsdpMessage, SsdpError]` | Parse a datagram; full validation with byte offsets. |
| `upnp_parse_text(s)` | `Result[SsdpMessage, SsdpError]` | Same, from a `Str`. |
| `upnp_header_count(m)` | `Int` | Number of headers. |
| `upnp_header(m, name)` | `Str` | First value of a case-insensitive name, "" when absent. |
| `upnp_has_header(m, name)` | `Bool` | Presence test. |
| `upnp_header_name(m, i)` / `upnp_header_value(m, i)` | `Str` | Header `i` as sent / trimmed; "" out of range. |
| `upnp_header_offset(m, i)` | `Int` | Absolute offset of header `i`; -1 out of range. |
| `usn_split(usn)` | `Result[UsnSplit, SsdpError]` | Split a Unique Service Name. |
| `upnp_classify_target(s)` | `Result[SsdpTarget, SsdpError]` | Classify an ST or NT value. |
| `upnp_is_device_uuid(s)` | `Bool` | Canonical 8-4-4-4-12 hex check. |
| `upnp_validate_authority(s)` | `Bool` | Loose host / host:port / `[ipv6]:port` check. |
| `upnp_validate_location(s)` | `Bool` | Loose http/https URL check. |
| `upnp_build_msearch(host, mx, st, user_agent)` | `Result[Vec[UInt8], SsdpError]` | Canonical M-SEARCH bytes. |
| `upnp_build_notify_alive(host, max_age, location, nt, usn, server, bootid, configid)` | `Result[Vec[UInt8], SsdpError]` | Canonical ssdp:alive bytes; `server == ""` and negative IDs omit their header. |
| `upnp_msg_kind_name(kind)` / `upnp_nts_name(kind)` / `upnp_target_name(kind)` / `upnp_usn_kind_name(kind)` | `Str` | Stable names for the kind constants. |
| `upnp_canonical_header_name(name)` | `Str` | Canonical casing for known SSDP headers, input unchanged otherwise. |

Constants: `UPNP_MAX_MESSAGE` (8192), `UPNP_SSDP_ADDRESS`, `UPNP_SSDP_PORT`,
`UPNP_SSDP_HOST`, `UPNP_KIND_*`, `UPNP_NTS_*`, `UPNP_TARGET_*`,
`UPNP_USN_*`. Types: `SsdpMessage`, `SsdpError` (`message` + `offset`),
`SsdpTarget`, `UsnSplit` -- all flat (parallel vectors, no nested structs).

## Usage

```xi
use xiom.upnp;
use xiom.io;
use xiom.convert.int;

// Parse an M-SEARCH as it would arrive from a control point. In production
// the bytes come from a UDP socket; here they are synthetic.
match upnp_parse_text("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: ssdp:all\r\n\r\n") {
  Ok(m) => {
    io.println("kind: " + upnp_msg_kind_name(m.kind));
    io.println("search target: " + m.st);
    io.println("MX: " + int_to_string(m.mx) + " seconds");
  },
  Err(e) => {
    io.println("bad SSDP message at byte " + int_to_string(e.offset) + ": " + e.message);
  },
}

// Build a NOTIFY ssdp:alive and parse it back.
match upnp_build_notify_alive(
  "239.255.255.250:1900",
  1800,
  "http://192.168.1.10:8200/desc.xml",
  "urn:schemas-upnp-org:device:MediaRenderer:1",
  "uuid:2fac1234-31f8-11b4-a222-08002b34c003::urn:schemas-upnp-org:device:MediaRenderer:1",
  "Linux/6.1 UPnP/1.1 demo/1.0",
  42,
  7) {
  Ok(bytes) => { /* send `bytes` over UDP */ },
  Err(e) => { io.println("build error: " + e.message); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.upnp
```

Expected: the namespace check passes, 18 `[PASS]` lines, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`. Every fixture is
built in-test: canonical M-SEARCH, alive/byebye/update NOTIFY, a 200
response, USN and ST/NT forms, byte-exact round-trips, and malformed or
truncated buffers whose errors are pinned by message and offset.

## Limitations

- **No transport.** The codec works on in-memory `Vec[UInt8]`; it never
  opens sockets, joins the multicast group or sends datagrams.
- **No XML.** Device and service descriptions, SOAP actions and eventing
  are out of scope.
- **No HTTP bodies.** A message ends at the first blank line (or the end
  of the datagram); any bytes after that are ignored.
- **Only three forms.** Other methods, HTTP versions, response statuses
  (anything but 200) and payload-bearing messages are rejected.
- **Strict line rules.** Bare CR / bare LF, NUL, C0 controls and DEL are
  rejected; a final line without CRLF is accepted only at end of buffer.
- **Conservative header-name grammar.** Names must match the RFC 7230
  token set; UTF-8 letters are not token characters.
- **Loose LOCATION/DATE checks.** The URL check covers scheme, host and
  port shape only; DATE is only checked for RFC-1123 shape, not calendar
  validity. USN UUIDs must be canonical 8-4-4-4-12 hex.
- **First header wins.** Duplicate headers are all preserved in the
  vectors, but the typed fields use the first occurrence.
- **Not thread-safe.** `SsdpMessage` is a plain value type; `Str` values
  are copied into it by the parser.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
