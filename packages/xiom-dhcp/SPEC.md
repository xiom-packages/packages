# xiom.dhcp -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.dhcp`, version `0.1.0`).
Module: `src/dhcp.xi` (`module xiom.dhcp`).
Depends on `xiom.std`; the library module imports nothing (the tests use
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) DHCPv4 packet codec for the RFC 2131/2132 wire subset:

- `dhcp_is_packet` / `dhcp_parse`: decode the fixed BOOTP header, the magic
  cookie and the options area into a `DhcpPacket` index;
- option accessors: index walk (`dhcp_option_count`, `dhcp_option_code`,
  `dhcp_option_length`, `dhcp_find_option`, `dhcp_option_value`) plus typed
  readers for message type, subnet mask, requested IP, lease time, server
  id, router list and DNS list;
- `dhcp_append_option`, `dhcp_build_client`, `dhcp_build_discover`,
  `dhcp_build_request`: encode options and BOOTREQUEST frames (DISCOVER and
  REQUEST);
- deterministic `Err(Str)` messages for malformed input and invalid build
  arguments.

## Non-goals

- No sockets, UDP framing, retransmission, timers or the DORA lease state
  machine; this is a byte codec only.
- DHCPv6; BOOTP-only packets (the 99.130.83.99 magic cookie is required).
- Relay agents, `giaddr` processing, option 82, and option overload
  (options carried in `sname`/`file`).
- RENEWING/REBINDING `DHCPREQUEST` building (`ciaddr` is always zero in the
  builders) and all server-side builders (OFFER/ACK/NAK).
- Text decoding of option values (hostname, client id, parameter list are
  bytes); DNS name compression; message authentication.
- Streaming/incremental parsing: the whole packet is an in-memory
  `Vec[UInt8]`; option values are indexed in place and copied on demand.
- Validation of `op`, `htype`, `hlen`, `hops`, `secs` or the option
  message-type value range (returned raw).

## Byte-level layout

### Fixed header (236 bytes) and magic cookie

| Offset | Size | Field | Encoding | Notes |
|---|---|---|---|---|
| 0 | 1 | op | u8 | 1 = BOOTREQUEST, 2 = BOOTREPLY; not validated |
| 1 | 1 | htype | u8 | 1 = Ethernet; not validated |
| 2 | 1 | hlen | u8 | not validated; `chaddr` is copied as 16 raw bytes |
| 3 | 1 | hops | u8 | not validated |
| 4 | 4 | xid | u32 BE | transaction id |
| 8 | 2 | secs | u16 BE | seconds since client start |
| 10 | 2 | flags | u16 BE | bit 15 (0x8000) = broadcast; exposed as `broadcast` |
| 12 | 4 | ciaddr | u32 BE | client IP |
| 16 | 4 | yiaddr | u32 BE | "your" (offered/assigned) IP |
| 20 | 4 | siaddr | u32 BE | next server IP |
| 24 | 4 | giaddr | u32 BE | relay agent IP |
| 28 | 16 | chaddr | raw | client hardware address, zero-padded |
| 44 | 64 | sname | raw | server name, zero-padded |
| 108 | 128 | file | raw | boot file name, zero-padded |
| 236 | 4 | magic cookie | fixed | `99 130 83 99` |

IPv4 addresses decode to unsigned 32-bit integers in an `Int`
(0..4294967295; `192.168.1.100` is `3232235876`). All multi-byte fields
are big-endian.

### Options area (offset 240 to end)

Each option is a TLV entry, except the single-byte pad and end markers:

```
+--------+--------+------------------+
| code   | len    | value (len bytes)|
| 1 byte | 1 byte | len >= 0         |
+--------+--------+------------------+
```

`dhcp_parse` walks from offset 240:

1. code `0` (pad): skip one byte and continue;
2. code `255` (end): stop; all following bytes are ignored;
3. any other code: require a length byte and `len` value bytes inside the
   buffer; apply the shape rule below; record `(code, pos + 2, len)`; skip
   past the value.

A packet is malformed unless the walk reaches a `255` end option.

### Option shape rules

| Code | Name | Accepted length |
|---|---|---|
| 1 | subnet mask | exactly 4 |
| 3 | router | >= 4 and a multiple of 4 |
| 6 | DNS server | >= 4 and a multiple of 4 |
| 12 | hostname | >= 1 |
| 50 | requested IP address | exactly 4 |
| 51 | lease time | exactly 4 |
| 53 | message type | exactly 1 (value returned raw) |
| 54 | server identifier | exactly 4 |
| 55 | parameter request list | >= 1 |
| 61 | client identifier | >= 2 |
| 0 | pad | not an option entry; skipped |
| 255 | end | terminates the options area |
| any other | unknown | any length 0..255 (accepted as-is) |

The same rules are applied by `dhcp_parse` and by `dhcp_append_option`, so
anything the encoder accepts the decoder accepts, and vice versa (truncated
values aside).

## API signatures

All functions are free functions in module `xiom.dhcp` (no self methods):

```xi
pub type DhcpPacket = {
  op: Int;
  htype: Int;
  hlen: Int;
  hops: Int;
  xid: Int;
  secs: Int;
  flags: Int;
  broadcast: Bool;
  ciaddr: Int;
  yiaddr: Int;
  siaddr: Int;
  giaddr: Int;
  chaddr: Vec[UInt8];
  sname: Vec[UInt8];
  file: Vec[UInt8];
  option_codes: Vec[Int];
  option_offsets: Vec[Int];
  option_lengths: Vec[Int];
}

pub fn dhcp_is_packet(data: &Vec[UInt8]) -> Bool
pub fn dhcp_parse(data: &Vec[UInt8]) -> Result[DhcpPacket, Str]
pub fn dhcp_option_count(p: &DhcpPacket) -> Int
pub fn dhcp_option_code(p: &DhcpPacket, i: Int) -> Int
pub fn dhcp_option_length(p: &DhcpPacket, i: Int) -> Int
pub fn dhcp_find_option(p: &DhcpPacket, code: Int) -> Int
pub fn dhcp_option_value(data: &Vec[UInt8], p: &DhcpPacket, i: Int) -> Result[Vec[UInt8], Str]
pub fn dhcp_message_type(data: &Vec[UInt8], p: &DhcpPacket) -> Int
pub fn dhcp_option_u32(data: &Vec[UInt8], p: &DhcpPacket, code: Int) -> Int
pub fn dhcp_subnet_mask(data: &Vec[UInt8], p: &DhcpPacket) -> Int
pub fn dhcp_requested_ip(data: &Vec[UInt8], p: &DhcpPacket) -> Int
pub fn dhcp_lease_time(data: &Vec[UInt8], p: &DhcpPacket) -> Int
pub fn dhcp_server_id(data: &Vec[UInt8], p: &DhcpPacket) -> Int
pub fn dhcp_router_count(data: &Vec[UInt8], p: &DhcpPacket) -> Int
pub fn dhcp_router_at(data: &Vec[UInt8], p: &DhcpPacket, k: Int) -> Int
pub fn dhcp_dns_count(data: &Vec[UInt8], p: &DhcpPacket) -> Int
pub fn dhcp_dns_at(data: &Vec[UInt8], p: &DhcpPacket, k: Int) -> Int
pub fn dhcp_append_option(out: &mut Vec[UInt8], code: Int, value: &Vec[UInt8]) -> Result[Unit, Str]
pub fn dhcp_build_client(xid: Int, chaddr: &Vec[UInt8], broadcast: Bool, options: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn dhcp_build_discover(xid: Int, chaddr: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn dhcp_build_request(xid: Int, chaddr: &Vec[UInt8], requested_ip: Int, server_id: Int) -> Result[Vec[UInt8], Str]
```

## Semantics

`dhcp_is_packet(data)`
: `true` iff `data.len() >= 240` and bytes 236..239 are `99 130 83 99`.
  Option bytes are not inspected, so a sniffed packet may still fail
  `dhcp_parse`.

`dhcp_parse(data)`
: Validates the length and cookie, decodes the fixed header, then walks the
  options area as above. `chaddr` (16), `sname` (64) and `file` (128) are
  copied raw; `broadcast` is `flags >= 0x8000`. `option_offsets[i]` is the
  absolute index of the first value byte in `data`; option values with
  length 0 are recorded with an offset pointing at their (empty) span.
  On `Err` no partial packet is returned.

`dhcp_option_code` / `dhcp_option_length`
: Return `-1` when `i < 0` or `i >= dhcp_option_count(p)`.

`dhcp_find_option(p, code)`
: Linear scan in wire order; the first matching index wins; `-1` when no
  option matches (including an empty index).

`dhcp_option_value(data, p, i)`
: `Err("dhcp: option index out of range")` for a bad `i`; otherwise the
  recorded span is bounds-checked against `data` and the bytes are copied
  into a fresh vector. A shorter `data` than the parse buffer yields
  `Err("dhcp: option out of bounds")` when the span no longer fits.

`dhcp_message_type(data, p)`
: The option 53 value byte (`1` DISCOVER, `2` OFFER, `3` REQUEST,
  `4` DECLINE, `5` ACK, `6` NAK, `7` RELEASE, `8` INFORM), or `-1` when
  option 53 is absent or not exactly one byte. Values outside 1..8 are
  returned raw, not rejected.

`dhcp_option_u32(data, p, code)`
: The big-endian u32 value of a single-address option, or `-1` when the
  option is absent, not exactly 4 bytes, or out of bounds. `dhcp_subnet_mask`
  (1), `dhcp_requested_ip` (50), `dhcp_lease_time` (51) and
  `dhcp_server_id` (54) are thin wrappers over it.

`dhcp_router_count` / `dhcp_router_at`, `dhcp_dns_count` / `dhcp_dns_at`
: Address-list views over options 3 and 6. The count is 0 when the option is
  absent or malformed; `_at` returns the k-th (0-based) address and `-1`
  when `k` is negative or beyond the list. Only the first occurrence of the
  option is used.

`dhcp_append_option(out, code, value)`
: Encodes `code`, `value.len()` and the value bytes into `out`. Validates
  the code range (1..254), then the value length (<= 255), then the shape
  rule, in that order; nothing is written unless every check passes, so
  `out` is byte-for-byte unchanged on `Err` (atomic failure).

`dhcp_build_client(xid, chaddr, broadcast, options)`
: Builds `op=1`, `htype=1`, `hlen=chaddr.len()`, `hops=0`, `xid`, `secs=0`,
  `flags = 0x8000` when `broadcast` else 0, zero `ciaddr`/`yiaddr`/`siaddr`/
  `giaddr`, `chaddr` zero-padded to 16, zeroed `sname`/`file`, the magic
  cookie, then `options` verbatim and the end option `255`. `options` must
  hold complete TLV entries and must not include its own end option.
  Validation is xid first, then chaddr.

`dhcp_build_discover(xid, chaddr)`
: `dhcp_build_client` with options `53 = 1`, `61 = [1] + chaddr`,
  `55 = {1, 3, 6, 12, 51, 54}` and the broadcast bit set.

`dhcp_build_request(xid, chaddr, requested_ip, server_id)`
: `dhcp_build_client` with options `53 = 3`, `61 = [1] + chaddr`, then
  `50` when `requested_ip >= 0`, then `54` when `server_id >= 0`, then
  `55 = {1, 3, 6, 12, 51, 54}`, and the broadcast bit set. Negative IP
  arguments omit the corresponding option; values above 4294967295 are
  `Err("dhcp: bad ip address")`. This is the SELECTING / INIT-REBOOT form:
  `ciaddr` stays zero.

## Error string catalog

| Condition | Error text |
|---|---|
| `dhcp_parse`: `data.len() < 240` | `dhcp: short packet` |
| `dhcp_parse`: bytes 236..239 not `99 130 83 99` | `dhcp: bad cookie` |
| `dhcp_parse`: option code with no length byte, or declared value past the buffer end | `dhcp: truncated option` |
| `dhcp_parse`: documented option whose length violates its shape rule | `dhcp: bad option length` |
| `dhcp_parse`: options end without the 255 end marker | `dhcp: missing end` |
| `dhcp_option_value`: `i < 0` or `i >= count` | `dhcp: option index out of range` |
| `dhcp_option_value`: recorded span does not fit `data` | `dhcp: option out of bounds` |
| `dhcp_append_option`: `code < 1` or `code > 254` | `dhcp: bad option code` |
| `dhcp_append_option`: `value.len() > 255` | `dhcp: option value too long` |
| `dhcp_append_option`: documented code with a bad value length | `dhcp: bad option length` |
| builders: `xid < 0` or `xid > 4294967295` | `dhcp: bad xid` |
| builders: `chaddr.len() < 1` or `> 16` | `dhcp: bad chaddr length` |
| `dhcp_build_request`: `requested_ip` or `server_id` > 4294967295 | `dhcp: bad ip address` |

All strings are stable API. `dhcp_parse` error precedence is: short packet,
bad cookie, option walk in wire order (truncation before shape, per option),
missing end. In `dhcp_append_option`, the order is code range, value length,
shape. In the builders, the client header (xid, chaddr) is checked before
any option argument.

## Complexity

| Operation | Complexity |
|---|---|
| `dhcp_is_packet` | O(1) |
| `dhcp_parse` | O(data.len()) time, O(options) space (values stay in `data`) |
| `dhcp_option_count` / `dhcp_option_code` / `dhcp_option_length` | O(1) |
| `dhcp_find_option` | O(options) |
| `dhcp_option_value` | O(value length) |
| `dhcp_message_type` / `dhcp_option_u32` / mask / requested IP / lease / server id | O(options) |
| `dhcp_router_count` / `dhcp_dns_count` | O(options) |
| `dhcp_router_at` / `dhcp_dns_at` | O(options) |
| `dhcp_append_option` | O(value length) |
| `dhcp_build_client` | O(chaddr + options) |
| `dhcp_build_discover` / `dhcp_build_request` | O(chaddr) |

## Test plan

`tests/test_conformance.xi` (`module dhcp_tests`, 16 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Fixtures are assembled byte by byte in the test
file, not via the library:

- **OFFER fixture** (299 bytes): `op=2`, `htype=1`, `hlen=6`, `xid`
  0x12345678, `secs=5`, broadcast flag, `yiaddr` 192.168.1.100, `siaddr`
  192.168.1.1, `giaddr` 10.0.0.1, MAC `de:ad:be:ef:00:01`, sname "dhcpd",
  file "pxelinux.0"; options after a pad byte: 53=OFFER, 54, 51=86400,
  1=255.255.255.0, 3, 6 (two DNS servers), 12 "xiom-host", 61, then 255
  and four trailing bytes.
- **INFORM fixture** (244 bytes): flags 0, `secs=65535`, `ciaddr` set,
  sname "A...", file "BOOT...", option 53 = 8, end.
- Client frames are rebuilt independently in the test file with
  `client_frame` + `opt` + `push_be*` helpers and compared byte-for-byte
  against the builder output.

Coverage:

1. OFFER fixture: length, `is_packet`, all fixed header fields, `chaddr`/
   `sname`/`file` bytes pinned, option count;
2. flags 0 / no broadcast, `secs` boundary, sname/file markers, INFORM
   message type;
3. option index: 8 codes, absolute offsets
   (243/246/252/258/264/270/280/291), lengths, pad skipped, first-match
   `dhcp_find_option`, `-1` for absent/out-of-range;
4. exact `dhcp_option_value` slices (message type, hostname, client id);
   bad index and a short source buffer are the two documented errors;
5. typed accessors: message type 2, mask 4294967040, lease 86400, server id,
   router list (1 entry), DNS list (2 entries), requested IP absent;
6. short packet (empty/100/239 bytes) and bad cookie (first byte, last
   byte, all-zero 240-byte) with `is_packet` false;
7. truncated option: code without length, declared length overrunning,
   truncation after a valid option, exact-fit control parses;
8. missing end: header-only, pads only, complete option without 255; bytes
   after the 255 end option are ignored;
9. bad option length for codes 53, 1, 54, 12, 61, 51, 55, 3 and 6; controls
   for valid minimums and an unknown code;
10. `dhcp_append_option`: exact bytes `35 01 01 0c 04 78 69 6f 6d`, all
    error cases, unchanged `out`, and the 255-byte value boundary;
11. `dhcp_build_client`: exact 248-byte frame, parse-back of header,
    broadcast bit, padded chaddr, option values;
12. `dhcp_build_client` errors (xid -1 / 2^32, empty and 17-byte chaddr),
    boundaries xid 0 and 4294967295, 16-byte chaddr, unicast flags 0;
13. `dhcp_build_discover`: exact 261-byte frame (53, 61, 55), PRL and
    client id round-trip, no option 50;
14. `dhcp_build_request`: exact 273-byte frame (53, 61, 50, 54, 55),
    optional 50/54 omitted when negative, ip-range errors, xid error
    precedence, 4294967295/0 boundaries;
15. build -> parse -> rebuild is byte-identical; a DNS list parsed from the
    OFFER is re-framed and survives with both addresses;
16. unsigned boundaries: xid/secs/flags/addresses/lease at 4294967295 or
    65535, high-bit values preserved, message type value returned raw.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.dhcp
```

Last verified: compiler 0.61.3,
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## Known limitations

- DHCPv4 only; BOOTP packets without the magic cookie are rejected.
- No networking, lease state, relay handling or option overload.
- The options area must terminate with an end option (255); trailing bytes
  after it are ignored.
- Documented option shapes are length-checked; unknown option codes pass
  with any length. The message-type value is not range-checked.
- Duplicate options are indexed in wire order but typed accessors use the
  first occurrence.
- Server replies (OFFER/ACK) are parse-only; `DHCPREQUEST` building covers
  SELECTING / INIT-REBOOT (broadcast, `ciaddr = 0`), not RENEWING.
- Option values are raw bytes; no text decoding (hostname, client id, PRL).
- `DhcpPacket` stores absolute offsets into the parse buffer, so
  `data`-taking accessors need that buffer (or one holding the spans).
- Not thread-safe; `DhcpPacket` is a plain value type.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_packet`/`_err_packet`/`_ok_bytes`/`_err_bytes`/`_ok_unit`/`_err_unit`
  (constructing `Result` values directly inside other functions
  miscompiles in this compiler).
- Every byte read widens with `(data[pos] as Int) & 0xFF`; `UInt8` values
  are never compared with `Int` constants without that widening.
- Multi-byte fields are read and packed with arithmetic only
  (`+`, `*`, `/`, `%`), which avoids the v0.61.3 mask/bit-set miscompiles
  seen on operands with bit 31 set; `_be_byte` follows the `xiom.tlv`
  precedent.
- `DhcpPacket` (18 fields) is constructed inside `dhcp_parse` only and
  crosses function boundaries by reference or through `_ok_packet`
  (following the `xiom.pcap` `PcapFile` precedent).
- Vec reads are bound to typed locals (`let len: Int = ...`) before use;
  all index vectors are `Vec[Int]`.
- The module has no `Str` fields and never compares `Str` values, so the
  BUG 17 pointer-comparison pitfall does not arise inside it; the tests
  route every error-string check through `str_compare`.
- The package declares no `extern "C"` blocks (no FFI).
