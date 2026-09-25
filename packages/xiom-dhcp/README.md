# xiom.dhcp

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM DHCPv4 packet codec for the RFC 2131/2132 wire
> subset: fixed BOOTP header, magic cookie, options TLV parse/build.
> **Deps:** `xiom.std` only. The library module is dependency-free; the
> tests use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI, no sockets, no lease state.

## What it is

`xiom.dhcp` encodes and decodes DHCPv4 messages: the fixed 236-byte BOOTP
header (`op`, `htype`, `hlen`, `hops`, `xid`, `secs`, `flags` with the
broadcast bit, `ciaddr`, `yiaddr`, `siaddr`, `giaddr`, `chaddr[16]`,
`sname[64]`, `file[128]`), the `99.130.83.99` magic cookie, and the options
area as tag-length-value entries. Pad (`0`) is skipped, the end option
(`255`) terminates the walk, and every other option is indexed by code with
its absolute value offset and declared length.

The codec parses any DHCPv4 packet -- server replies such as OFFER and ACK
are the interesting cases -- and builds BOOTREQUEST client frames
(DISCOVER and REQUEST) with `dhcp_build_discover` / `dhcp_build_request`.
It is a pure value codec: no sockets, no timers, no lease state machine,
no relay handling, no option overload.

## Quick start

```xi
use xiom.dhcp;
use xiom.io;

// Build a DHCPDISCOVER for xid 0x12345678 and MAC de:ad:be:ef:00:01.
var mac = Vec[UInt8].new();
mac.push(222 as UInt8); mac.push(173 as UInt8); mac.push(190 as UInt8);
mac.push(239 as UInt8); mac.push(0 as UInt8);   mac.push(1 as UInt8);
let dr = dhcp_build_discover(305419896, &mac);
match dr {
  Ok(frame) => { /* send frame over UDP 68 -> 67 */ },
  Err(e) => { io.println("discover: " + e); },
}

// Parse a server reply (OFFER or ACK) and read the lease parameters.
let reply: Vec[UInt8] = ...;
let pr = dhcp_parse(&reply);
match pr {
  Ok(p) => {
    let msg = dhcp_message_type(&reply, &p);   // 2 = OFFER, 5 = ACK
    let offer_ip = p.yiaddr;
    let lease = dhcp_lease_time(&reply, &p);
    let server = dhcp_server_id(&reply, &p);
    let mask = dhcp_subnet_mask(&reply, &p);
    var d = 0;
    while d < dhcp_dns_count(&reply, &p) {
      io.println("dns " + xiom.convert.int_to_string(dhcp_dns_at(&reply, &p, d)));
      d = d + 1;
    }
  },
  Err(e) => { io.println("parse error: " + e); },
}
```

Never build the frame by hand: `dhcp_build_discover` and
`dhcp_build_request` fill the fixed header, set the broadcast bit, append
the magic cookie and end option. For custom option sets, encode entries
with `dhcp_append_option` and hand the blob to `dhcp_build_client`.

## API

| Function | Returns | Description |
|---|---|---|
| `dhcp_is_packet(data)` | `Bool` | `len >= 240` and a valid magic cookie; options not inspected. |
| `dhcp_parse(data)` | `Result[DhcpPacket, Str]` | Decode the header and index every non-pad option. |
| `dhcp_option_count(p)` | `Int` | Number of indexed options (end option excluded). |
| `dhcp_option_code(p, i)` | `Int` | Code of option `i`; `-1` out of range. |
| `dhcp_option_length(p, i)` | `Int` | Declared value length of option `i`; `-1` out of range. |
| `dhcp_find_option(p, code)` | `Int` | First option index with `code`; `-1` when absent. |
| `dhcp_option_value(data, p, i)` | `Result[Vec[UInt8], Str]` | Copy option `i`'s value bytes out of `data`. |
| `dhcp_message_type(data, p)` | `Int` | Option 53 value (1..8); `-1` when absent. |
| `dhcp_option_u32(data, p, code)` | `Int` | 4-byte single-address option (1, 50, 51, 54, ...); `-1` when absent. |
| `dhcp_subnet_mask(data, p)` | `Int` | Option 1 as an unsigned 32-bit Int; `-1` when absent. |
| `dhcp_requested_ip(data, p)` | `Int` | Option 50 as an unsigned 32-bit Int; `-1` when absent. |
| `dhcp_lease_time(data, p)` | `Int` | Option 51 seconds; `-1` when absent. |
| `dhcp_server_id(data, p)` | `Int` | Option 54 as an unsigned 32-bit Int; `-1` when absent. |
| `dhcp_router_count(data, p)` | `Int` | Number of option 3 addresses. |
| `dhcp_router_at(data, p, k)` | `Int` | k-th option 3 address; `-1` out of range. |
| `dhcp_dns_count(data, p)` | `Int` | Number of option 6 addresses. |
| `dhcp_dns_at(data, p, k)` | `Int` | k-th option 6 address; `-1` out of range. |
| `dhcp_append_option(out, code, value)` | `Result[Unit, Str]` | Encode one option into `out`; `out` untouched on `Err`. |
| `dhcp_build_client(xid, chaddr, broadcast, options)` | `Result[Vec[UInt8], Str]` | BOOTREQUEST frame around caller-encoded options. |
| `dhcp_build_discover(xid, chaddr)` | `Result[Vec[UInt8], Str]` | DHCPDISCOVER: 53, client id 61, parameter list 55. |
| `dhcp_build_request(xid, chaddr, requested_ip, server_id)` | `Result[Vec[UInt8], Str]` | DHCPREQUEST: 53, 61, optional 50/54, 55. |

IPv4 addresses are unsigned 32-bit integers in an `Int`
(`192.168.1.100` is `3232235876`). Parsed packets keep option values in the
source buffer, so `data`-taking accessors need the same buffer that was
passed to `dhcp_parse` (or one holding at least the indexed spans).

## Error model

Every fallible call returns `Result[..., Str]` with one of these stable
messages (exact texts; see SPEC.md for the precise conditions):

| Error | Raised by |
|---|---|
| `dhcp: short packet` | `dhcp_parse` when `data.len() < 240` |
| `dhcp: bad cookie` | `dhcp_parse` when bytes 236..239 are not 99.130.83.99 |
| `dhcp: truncated option` | `dhcp_parse` on a missing length byte or an overrunning value |
| `dhcp: bad option length` | `dhcp_parse` / `dhcp_append_option` on a documented option shape mismatch |
| `dhcp: missing end` | `dhcp_parse` when the 255 end option never appears |
| `dhcp: option index out of range` | `dhcp_option_value` with a bad index |
| `dhcp: option out of bounds` | `dhcp_option_value` when the span does not fit `data` |
| `dhcp: bad option code` | `dhcp_append_option` for code 0, 255 or outside 0..255 |
| `dhcp: option value too long` | `dhcp_append_option` when `value.len() > 255` |
| `dhcp: bad xid` | builders when `xid` is outside 0..4294967295 |
| `dhcp: bad chaddr length` | builders when `chaddr` is empty or longer than 16 |
| `dhcp: bad ip address` | `dhcp_build_request` when an IP exceeds 4294967295 |

`dhcp_is_packet` and the typed accessors never fail: absent or malformed
values are reported as `-1` (or `0`/`false`), and `dhcp_parse` is
all-or-nothing -- it returns no partial packet.

## Limitations

- **DHCPv4 only, subset.** No DHCPv6, no BOOTP-only packets (the magic
  cookie is required), no relay/giaddr processing, no option overload
  (sname/file carrying options).
- **No networking and no lease logic.** The codec only turns bytes into
  values and back; UDP sockets, retransmission, timers and the DORA state
  machine are the caller's responsibility.
- **Parsing requires the end option.** The options area must end with 255;
  trailing bytes after it are ignored.
- **Documented option shapes are enforced.** Options 1, 3, 6, 12, 50, 51,
  53, 54, 55 and 61 are length-checked per RFC 2132; unknown codes accept
  any length. The message-type *value* is returned raw (not restricted to
  1..8).
- **First match wins.** Duplicate options are preserved in wire order, but
  the typed accessors and `dhcp_find_option` use the first occurrence.
- **Client builders only.** DISCOVER and REQUEST (SELECTING / INIT-REBOOT
  form) are built; OFFER/ACK are parse-only, and RENEWING/REBINDING
  requests (ciaddr set) are not modelled.
- **IPv4 addresses and lists, raw bytes elsewhere.** Hostname (12),
  parameter list (55) and client id (61) values come back as bytes via
  `dhcp_option_value`; there is no text decoding.
- Not thread-safe; `DhcpPacket` is a plain value type over the source
  buffer.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.dhcp
```

Expected: the namespace check passes, 16 `[PASS]` lines, and a final
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
