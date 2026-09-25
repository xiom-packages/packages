# xiom.stun

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) codec for RFC 5389 STUN messages: the
> 20-byte header with method/class bit packing, attribute TLVs with 4-byte
> padding, MAPPED-ADDRESS / XOR-MAPPED-ADDRESS / USERNAME / SOFTWARE /
> ERROR-CODE decoding and encoding, and raw pass-through of unknown
> attributes. No sockets, no TURN, no MESSAGE-INTEGRITY crypto.
> **Deps:** `xiom.std` only. The library module imports `xiom.string`; the
> tests add `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.stun` reads and writes STUN messages, the wire format used by ICE,
WebRTC and NAT traversal (RFC 5389). A message is a 20-byte header followed
by zero or more attribute TLVs:

```
[header: type | length | magic cookie 0x2112A442 | 96-bit transaction ID]
[attribute: type | length | value | 0..3 padding bytes]
[attribute: ...]
```

`stun_parse` validates the header, walks the attribute TLVs inside the
declared message length and returns a `StunMessage` index; attribute values
are not copied, they stay in the source buffer and `stun_attr_value` slices
them on demand. `stun_build` is the inverse: it takes parallel attribute
type/value vectors and writes a complete message with the magic cookie and
zero padding, validating every size before writing a byte. Address and
ERROR-CODE attributes get dedicated encode/decode helpers (including both
XOR rules), and every other attribute -- MESSAGE-INTEGRITY, FINGERPRINT,
PRIORITY, NONCE, ... -- is preserved as a raw TLV and can be re-emitted
unchanged.

The conformance suite pins the four RFC 5769 sample messages verbatim,
including the ones whose padding bytes are ASCII spaces.

## Wire format

Header, 20 bytes:

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 2 | message type | 14 bits used: 12-bit method + 2-bit class interleaved |
| 2 | 2 | message length | declared attribute bytes, excluding this header |
| 4 | 4 | magic cookie | always `21 12 A4 42` (0x2112A442) |
| 8 | 12 | transaction ID | 96 bits; the IPv6 XOR mask after the cookie |

The type field packs the method and class as in RFC 5389 section 6: bits
13..9 and 7..5 hold method bits M11..M7 and M6..M4, bit 8 (C1) and bit 4
(C0) hold the class, and bits 3..0 hold M3..M0. `stun_message_type` /
`stun_type_method` / `stun_type_class` convert both ways. Class values:
0 request, 1 indication, 2 success response, 3 error response.

Attribute TLV, 4-byte header + padded value:

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 2 | attribute type | e.g. 0x0020 XOR-MAPPED-ADDRESS |
| 2 | 2 | value length | unpadded value bytes |
| 4 | `length` | value | raw bytes |
| 4 + `length` | 0..3 | padding | any value on the wire; zeroes on build |

Documented attribute set:

| Type | Name | Value layout |
|---|---|---|
| 0x0001 | MAPPED-ADDRESS | `00 family port[2] address[4\|16]` |
| 0x0006 | USERNAME | UTF-8 bytes (application-defined length) |
| 0x0009 | ERROR-CODE | `00 00 class number reason...` (`class*100+number`) |
| 0x0020 | XOR-MAPPED-ADDRESS | MAPPED-ADDRESS with port/address XORed |
| 0x8022 | SOFTWARE | UTF-8 bytes (application-defined length) |

XOR rules (XOR-MAPPED-ADDRESS): the port is XORed with `0x2112` (the high
half of the cookie); an IPv4 address is XORed byte-wise with
`21 12 A4 42`; an IPv6 address is XORed with the 16-byte mask
`21 12 A4 42 || transaction ID`.

## API

| Function | Returns | Description |
|---|---|---|
| `stun_parse(data)` | `Result[StunMessage, Str]` | Header validation + full attribute index. |
| `stun_build(type, tid, types, values)` | `Result[Vec[UInt8], Str]` | Whole message from raw type, 12-byte tid, parallel attribute vectors. |
| `stun_is_message(data)` | `Bool` | `len >= 20`, 14-bit type, matching cookie. |
| `stun_attr_count(m)` | `Int` | Number of attributes. |
| `stun_attr_type(m, i)` | `Int` | Attribute type; -1 out of range. |
| `stun_find_attr(m, t)` | `Int` | First index of type `t`; -1 when absent. |
| `stun_attr_value(data, m, i)` | `Result[Vec[UInt8], Str]` | Raw value bytes (padding excluded). |
| `stun_attr_text(data, m, i)` | `Result[Str, Str]` | Value reinterpreted as UTF-8 (no validation). |
| `stun_attr_mapped_address(data, m, i)` | `Result[StunAddress, Str]` | Decode MAPPED-ADDRESS. |
| `stun_attr_xor_mapped_address(data, m, i)` | `Result[StunAddress, Str]` | Decode/un-XOR XOR-MAPPED-ADDRESS. |
| `stun_attr_error_code(data, m, i)` | `Result[Int, Str]` | ERROR-CODE as `class*100 + number`. |
| `stun_attr_error_reason(data, m, i)` | `Result[Str, Str]` | ERROR-CODE reason phrase. |
| `stun_encode_mapped_address(family, port, address)` | `Result[Vec[UInt8], Str]` | Encode a MAPPED-ADDRESS value. |
| `stun_encode_xor_mapped_address(family, port, address, tid)` | `Result[Vec[UInt8], Str]` | Encode an XOR-MAPPED-ADDRESS value. |
| `stun_encode_error_code(code, reason)` | `Result[Vec[UInt8], Str]` | Encode an ERROR-CODE value. |
| `stun_encode_username(name)` | `Vec[UInt8]` | UTF-8 bytes of a USERNAME value. |
| `stun_encode_software(text)` | `Vec[UInt8]` | UTF-8 bytes of a SOFTWARE value. |
| `stun_message_type(method, class)` | `Int` | Pack a type; -1 on bad method/class. |
| `stun_type_method(type)` / `stun_type_class(type)` | `Int` | Unpack a type; -1 when out of 14 bits. |
| `stun_class_name(c)` / `stun_method_name(m)` | `Str` | Documented names; "unknown" otherwise. |
| `stun_attr_name(t)` | `Str` | Attribute name for the documented set. |
| `stun_padded_len(n)` | `Int` | `(n + 3) / 4 * 4`; -1 when negative. |

`pub type StunMessage = { msg_type: Int; method: Int; msg_class: Int;
message_length: Int; magic_cookie: Int; transaction_id: Vec[UInt8];
attr_types: Vec[Int]; value_offsets: Vec[Int]; value_lengths: Vec[Int]; }`
and `pub type StunAddress = { family: Int; port: Int; address: Vec[UInt8]; }`.
Types, classes, families and the cookie are exported as `STUN_*` constants.

Errors: `Err("stun: truncated header")`, `Err("stun: bad message type")`,
`Err("stun: truncated message")`, `Err("stun: bad magic cookie")`,
`Err("stun: truncated attribute")`, `Err("stun: attribute overruns
message")`, `Err("stun: bad padding")`, `Err("stun: attribute out of
range")`, `Err("stun: attribute out of bounds")`,
`Err("stun: truncated address")`, `Err("stun: bad address family")`,
`Err("stun: bad address length")`, `Err("stun: truncated error code")`,
`Err("stun: bad error code")`, `Err("stun: bad port")`,
`Err("stun: bad transaction id")`, `Err("stun: bad attribute type")`,
`Err("stun: attribute too large")`, `Err("stun: attribute count
mismatch")` and `Err("stun: message too large")` (see `SPEC.md`).

## Usage

```xi
use xiom.stun;
use xiom.convert;
use xiom.io;
use xiom.encoding.hex;

// Decode a hex literal into bytes (a valid hex string in these examples).
fn hb(s: Str) -> Vec[UInt8] {
  match hex.hex_decode(s) {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// Parse an incoming Binding request.
var packet = Vec[UInt8].new();
// ... fill `packet` with the datagram bytes ...

match stun_parse(&packet) {
  Ok(m) => {
    io.println("class: " + stun_class_name(m.msg_class));
    io.println("attrs: " + convert.int_to_string(stun_attr_count(&m)));
    let u = stun_find_attr(&m, STUN_ATTR_USERNAME);
    if u >= 0 {
      match stun_attr_text(&packet, &m, u) {
        Ok(name) => { io.println("user: " + name); },
        Err(e) => { io.println("user error: " + e); },
      }
    }
  },
  Err(e) => { io.println("not a STUN message: " + e); },
}

// Build a Binding success response carrying XOR-MAPPED-ADDRESS.
let tid = hb("b7e7a701bc34d686fa87dfae");
let addr = hb("c0000201"); // 192.0.2.1
var types = Vec[Int].new();
types.push(STUN_ATTR_XOR_MAPPED_ADDRESS);
var values = Vec[Vec[UInt8]].new();
match stun_encode_xor_mapped_address(STUN_FAMILY_IPV4, 32853, &addr, &tid) {
  Ok(v) => { values.push(v); },
  Err(e) => { io.println("encode error: " + e); },
}
match stun_build(stun_message_type(STUN_METHOD_BINDING, STUN_CLASS_SUCCESS), &tid, &types, &values) {
  Ok(bytes) => { /* send `bytes` over the transport of your choice */ },
  Err(e) => { io.println("build error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.stun
```

Expected: the namespace check passes, 18 `[PASS]` lines, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`. The fixtures
include the four RFC 5769 sample messages (ICE request and IPv4/IPv6
responses, and the long-term-credentials request) plus hand-built
boundary and error messages.

## Limitations

- **No transport.** The codec works on in-memory `Vec[UInt8]`; it never
  opens sockets and does not know about UDP datagrams.
- **No TURN.** Only the Binding method is named; TURN methods and
  attributes are unknown raw TLVs.
- **No MESSAGE-INTEGRITY / FINGERPRINT cryptography.** Both attributes are
  accepted and re-emitted as opaque bytes; they are never computed or
  verified, so authentication and the RFC 5769 HMAC/CRC values are out of
  scope.
- **No RFC 3489 legacy messages.** The magic cookie is mandatory in both
  directions; messages without it are `stun: bad magic cookie`.
- **No method registry.** `stun_method_name` names Binding and reports
  "unknown" for everything else; a 12-bit method/class type can still be
  packed and parsed generically.
- **No UTF-8 validation.** `stun_attr_text` and the reason phrase go
  through the stdlib's lenient `Str::from_utf8`; use `stun_attr_value` for
  raw bytes.
- **Padding is not policed.** Per RFC 5389 padding bytes may carry any
  value and are skipped; `stun_build` writes zeroes.
- **`stun_parse` is all-or-nothing.** On the first malformed attribute
  the whole call is `Err`; the valid prefix is not returned. Bytes after
  the declared message length are ignored (trailing datagram junk).
- **Not thread-safe.** `StunMessage` is a plain value type holding
  offsets into the caller's source buffer, which must outlive it.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
