# xiom.stun -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.stun`, version `0.1.0`).
Module: `src/stun.xi` (`module xiom.stun`).
Depends on `xiom.std`; the library module imports `xiom.string` (the tests
add `xiom.test`, `xiom.io`, `xiom.string.compare` and
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for the RFC 5389 subset of STUN:

- `stun_parse`: header validation plus a full attribute index (type and
  absolute unpadded value offset/length per attribute);
- `stun_attr_type` / `stun_attr_value` / `stun_find_attr` /
  `stun_attr_count`: read the index back, raw values included;
- `stun_build`: whole-message construction from a raw 14-bit type, a
  12-byte transaction ID and parallel attribute type/value vectors, with
  4-byte zero padding;
- dedicated helpers for MAPPED-ADDRESS, XOR-MAPPED-ADDRESS, ERROR-CODE,
  USERNAME and SOFTWARE, including both XOR rules;
- method/class bit packing, class/method/attribute names, padding math;
- deterministic `Err(Str)` messages for malformed input and invalid
  build/encode arguments.

## Non-goals

- Sockets, transports, retransmission, requests/responses correlation:
  the codec sees byte buffers only.
- TURN (RFC 5766) and any other STUN extension beyond the documented
  attribute set: their attributes pass through as raw TLVs, their methods
  are unnamed but still representable in the 12-bit method space.
- MESSAGE-INTEGRITY and FINGERPRINT cryptography: both are accepted,
  indexed and re-emitted as opaque bytes, never computed or verified.
- RFC 3489 legacy messages without the magic cookie.
- The full RFC 5389 method registry: only Binding (0x001) is named.
- UTF-8 validation of text attributes and reason phrases.
- Streaming/incremental parsing: the whole message is an in-memory
  `Vec[UInt8]`.
- Multiple messages per buffer or message framing over a stream.

## Byte-level layout

### Header (20 bytes, offsets from the message start)

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 2 | message type | 14 bits, see below |
| 2 | 2 | message length | unsigned big-endian, attribute bytes only |
| 4 | 4 | magic cookie | `21 12 A4 42` (0x2112A442) |
| 8 | 12 | transaction ID | 96 raw bits |

Bytes after `20 + message length` are ignored by `stun_parse`; a valid
message may be followed by trailing bytes in the same buffer. The declared
message length does not include the header.

### Message type bit packing

The two most significant bits are zero. The remaining 14 bits hold the
12-bit method (`M11..M0`) and the 2-bit class (`C1`, `C0`) interleaved:

| Type bit | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Field | M11 | M10 | M9 | M8 | M7 | C1 | M6 | M5 | M4 | C0 | M3 | M2 | M1 | M0 |

Class values: 0 = request, 1 = indication, 2 = success response,
3 = error response. Example: Binding request = 0x0001, Binding success
response = 0x0101, Binding error response = 0x0111, Binding indication =
0x0011.

### Attribute TLV

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 2 | attribute type | unsigned big-endian |
| 2 | 2 | value length | unsigned big-endian, unpadded |
| 4 | `length` | value | raw bytes |
| 4 + `length` | 0..3 | padding | any value on receive; zeroes on build |

Attributes are packed back to back inside the declared message span and
each one ends on a 4-byte boundary. A zero-length value is valid. On
decode the padding bytes are skipped and their values are never inspected
(RFC 5389 allows any value; the RFC 5769 ICE fixtures use ASCII spaces).
Because the message span advances by `4 + padded(length)`, a misaligned
message length (not a multiple of 4) is rejected as
`stun: truncated attribute` or `stun: bad padding` rather than silently
accepted.

### MAPPED-ADDRESS / XOR-MAPPED-ADDRESS value

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 1 | reserved | ignored on decode, 0 on encode |
| 1 | 1 | family | 0x01 IPv4, 0x02 IPv6 |
| 2 | 2 | port | unsigned big-endian |
| 4 | 4 or 16 | address | IPv4 or IPv6 bytes, network order |

Value length is therefore 8 (IPv4) or 20 (IPv6). For
XOR-MAPPED-ADDRESS the port and address fields are stored XORed; the
reserved/family bytes are not.

### ERROR-CODE value

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 2 | reserved | ignored on decode, 0 on encode |
| 2 | 1 | class | hundreds digit (3..6 on encode) |
| 3 | 1 | number | 0..99 (not range-checked on decode) |
| 4 | rest | reason phrase | bytes, passed to `Str::from_utf8` |

The decoded error code is `class * 100 + number` (for example 420). The
five high bits of the class byte are ignored on decode.

## XOR rules

Let `cookie = 21 12 A4 42` (0x2112A442) and `tid` be the 12 transaction ID
bytes. For XOR-MAPPED-ADDRESS:

- `X-Port = Port XOR 0x2112`;
- IPv4: `X-Address[i] = Address[i] XOR cookie[i]` for i in 0..3;
- IPv6: `X-Address[i] = Address[i] XOR mask[i]` for i in 0..15, where
  `mask = cookie || tid` (bytes 0..3 are the cookie, bytes 4..15 the
  transaction ID).

Decoding applies the same operation (XOR is its own inverse). The codec
implements the XOR bitwise but arithmetically (see the compiler notes), so
the result is exact for all byte values.

## API signatures

All functions are free functions in module `xiom.stun`:

```xi
pub type StunMessage = {
  msg_type: Int;
  method: Int;
  msg_class: Int;
  message_length: Int;
  magic_cookie: Int;
  transaction_id: Vec[UInt8];
  attr_types: Vec[Int];
  value_offsets: Vec[Int];
  value_lengths: Vec[Int];
}

pub type StunAddress = {
  family: Int;
  port: Int;
  address: Vec[UInt8];
}

pub fn stun_parse(data: &Vec[UInt8]) -> Result[StunMessage, Str]
pub fn stun_build(msg_type: Int, transaction_id: &Vec[UInt8], attr_types: &Vec[Int], attr_values: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str]
pub fn stun_is_message(data: &Vec[UInt8]) -> Bool
pub fn stun_attr_count(m: &StunMessage) -> Int
pub fn stun_attr_type(m: &StunMessage, i: Int) -> Int
pub fn stun_find_attr(m: &StunMessage, attr_type: Int) -> Int
pub fn stun_attr_value(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Vec[UInt8], Str]
pub fn stun_attr_text(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Str, Str]
pub fn stun_attr_mapped_address(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[StunAddress, Str]
pub fn stun_attr_xor_mapped_address(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[StunAddress, Str]
pub fn stun_attr_error_code(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Int, Str]
pub fn stun_attr_error_reason(data: &Vec[UInt8], m: &StunMessage, i: Int) -> Result[Str, Str]
pub fn stun_encode_mapped_address(family: Int, port: Int, address: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn stun_encode_xor_mapped_address(family: Int, port: Int, address: &Vec[UInt8], transaction_id: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
pub fn stun_encode_error_code(code: Int, reason: Str) -> Result[Vec[UInt8], Str]
pub fn stun_encode_username(name: Str) -> Vec[UInt8]
pub fn stun_encode_software(text: Str) -> Vec[UInt8]
pub fn stun_message_type(method: Int, msg_class: Int) -> Int
pub fn stun_type_method(msg_type: Int) -> Int
pub fn stun_type_class(msg_type: Int) -> Int
pub fn stun_class_name(msg_class: Int) -> Str
pub fn stun_method_name(method: Int) -> Str
pub fn stun_attr_name(attr_type: Int) -> Str
pub fn stun_padded_len(n: Int) -> Int
```

Exported constants: `STUN_MAGIC_COOKIE` (554869826), `STUN_HEADER_SIZE`
(20), `STUN_ATTR_HEADER_SIZE` (4), `STUN_CLASS_REQUEST/INDICATION/SUCCESS/
ERROR` (0..3), `STUN_METHOD_BINDING` (1),
`STUN_ATTR_MAPPED_ADDRESS/USERNAME/ERROR_CODE/XOR_MAPPED_ADDRESS/SOFTWARE`
(1, 6, 9, 32, 32802) and `STUN_FAMILY_IPV4/IPV6` (1, 2).

## Semantics

`stun_parse(data)`
: Checks, in this order:

  1. `data.len() >= 20`, else `stun: truncated header`;
  2. the 14-bit type check, else `stun: bad message type`;
  3. `20 + message length <= data.len()`, else `stun: truncated message`;
  4. cookie equals `0x2112A442`, else `stun: bad magic cookie`;
  5. the attribute walk within `[20, 20 + message length)`: a remainder
     shorter than 4 bytes is `stun: truncated attribute`, a declared value
     length beyond the remainder is `stun: attribute overruns message`,
     and a padded span beyond the remainder is `stun: bad padding`.

  On success the message type is decoded into `method`/`msg_class`, the
  cookie is stored (always `STUN_MAGIC_COOKIE`) and the three attribute
  vectors hold one entry per attribute in wire order. `value_lengths` is
  the unpadded length and `value_offsets` is the absolute index of the
  first value byte in `data`. Parsing is all-or-nothing: the first
  malformed attribute makes the whole call `Err`.

`stun_is_message(data)`
: `true` iff `data.len() >= 20`, the two high type bits are zero and the
  cookie matches. Attribute bytes and the declared length are not
  inspected, so it is a cheap sniff, not a validation.

`stun_attr_type(m, i)`
: Type of attribute `i`, or -1 when `i < 0` or `i >= stun_attr_count(m)`.

`stun_find_attr(m, attr_type)`
: Linear scan in wire order; the first matching index wins, -1 when
  absent. Unknown attribute types are found like any other (this is how
  raw pass-through is addressed).

`stun_attr_value(data, m, i)`
: `Err("stun: attribute out of range")` for a bad `i`; the recorded span
  is bounds-checked against `data` and copied into a fresh vector
  (`Err("stun: attribute out of bounds")` on a short buffer). Zero-length
  values yield an empty `Ok`.

`stun_attr_text(data, m, i)`
: The raw value bytes handed to `Str::from_utf8` with no further
  validation (the pinned stdlib accepts stray high bytes). Errors as
  `stun_attr_value`.

`stun_attr_mapped_address` / `stun_attr_xor_mapped_address`
: Fetch the value, then require at least the 4-byte prefix
  (`stun: truncated address`), a family of 1 or 2
  (`stun: bad address family`), a value length of exactly 8 or 20 bytes
  (`stun: bad address length`) and -- for the XOR form -- a 12-byte
  transaction ID (`stun: bad transaction id`). The XOR form un-XORs the
  port and the 4/16 address bytes as described above.

`stun_attr_error_code` / `stun_attr_error_reason`
: Fetch the value, require at least 4 bytes
  (`stun: truncated error code`), and return `class * 100 + number` or
  the reason bytes as a `Str`. The reserved bytes and the reason phrase
  are not policed further.

`stun_build(msg_type, transaction_id, attr_types, attr_values)`
: Validates, in order: type in 0..16383 (`stun: bad message type`); a
  12-byte ID (`stun: bad transaction id`); equal vector lengths
  (`stun: attribute count mismatch`); then per attribute a type in
  0..65535 (`stun: bad attribute type`), a value of at most 65535 bytes
  (`stun: attribute too large`) and a running padded total of at most
  65535 (`stun: message too large`). Only then does it write the header
  (type, total, cookie, ID) and each attribute (`type, length, value,
  zero padding`). Nothing is written on `Err`.

`stun_encode_mapped_address` / `stun_encode_xor_mapped_address`
: Validate family (1 or 2), then the address length (4 or 16), then the
  port (0..65535); the XOR form additionally needs a 12-byte transaction
  ID. They return the attribute value bytes only -- the caller passes
  them to `stun_build` (or writes them into a message buffer).

`stun_encode_error_code(code, reason)`
: `code` must be in 300..699; the value is `00 00 (code / 100) (code %
  100)` followed by the UTF-8 bytes of `reason`.

`stun_encode_username` / `stun_encode_software`
: Return the UTF-8 bytes of the argument with no validation or length
  rule (STUN leaves those to the application).

`stun_message_type` / `stun_type_method` / `stun_type_class`
: Pure packing/inversion; the packer returns -1 for a method outside
  0..4095 or a class outside 0..3, the unpackers return -1 for a type
  outside 0..16383.

`stun_class_name` / `stun_method_name` / `stun_attr_name`
: Infallible name lookups restricted to the documented set
  (request/indication/success response/error response; binding;
  MAPPED-ADDRESS/USERNAME/ERROR-CODE/XOR-MAPPED-ADDRESS/SOFTWARE);
  anything else is "unknown". There is no extension registry beyond this.

`stun_padded_len(n)`
: `(n + 3) / 4 * 4` for `n >= 0`, -1 for negative `n`.

## Error string catalog

| Condition | Error text |
|---|---|
| `stun_parse`: `data.len() < 20` | `stun: truncated header` |
| `stun_parse`: type has a nonzero bit 14/15 | `stun: bad message type` |
| `stun_parse`: `20 + declared > data.len()` | `stun: truncated message` |
| `stun_parse`: cookie != 0x2112A442 | `stun: bad magic cookie` |
| `stun_parse`: `0 < remaining < 4` inside the message span | `stun: truncated attribute` |
| `stun_parse`: declared value length > remaining - 4 | `stun: attribute overruns message` |
| `stun_parse`: padded value span > remaining - 4 | `stun: bad padding` |
| `stun_attr_value`/`stun_attr_text`/address/error-code decoders: bad `i` | `stun: attribute out of range` |
| `stun_attr_value` and friends: recorded span beyond `data` | `stun: attribute out of bounds` |
| address decoders: value shorter than 4 bytes | `stun: truncated address` |
| address decoders: family not 1/2 | `stun: bad address family` |
| address decoders: value length != 8/20 for the family | `stun: bad address length` |
| XOR address decoder/encoder: transaction ID != 12 bytes | `stun: bad transaction id` |
| address encoders: family not 1/2 | `stun: bad address family` |
| address encoders: address length != 4/16 for the family | `stun: bad address length` |
| address encoders: port outside 0..65535 | `stun: bad port` |
| ERROR-CODE decode: value shorter than 4 bytes | `stun: truncated error code` |
| `stun_encode_error_code`: code outside 300..699 | `stun: bad error code` |
| `stun_build`: type outside 0..16383 | `stun: bad message type` |
| `stun_build`: transaction ID != 12 bytes | `stun: bad transaction id` |
| `stun_build`: `attr_types.len() != attr_values.len()` | `stun: attribute count mismatch` |
| `stun_build`: attribute type outside 0..65535 | `stun: bad attribute type` |
| `stun_build`: a value longer than 65535 bytes | `stun: attribute too large` |
| `stun_build`: padded attribute total > 65535 | `stun: message too large` |

All error strings are stable API. The parse checks are ordered as listed;
in particular a header-level structural error (`truncated message`) is
reported before the cookie check, and the type check precedes both.
Address encode check order is family, address length, port (and
transaction ID last in the XOR form); decode order is prefix length,
family, value length (and transaction ID in the XOR form). `stun_is_message`,
the name lookups and `stun_padded_len` never produce an error string.

## Complexity

| Operation | Complexity |
|---|---|
| `stun_parse` | O(message length) time/space for the index; values stay in `data` |
| `stun_build` | O(total value bytes) time/space |
| `stun_is_message` | O(1) |
| `stun_attr_count` / `stun_attr_type` / `stun_find_attr` | O(1) / O(1) / O(attributes) |
| `stun_attr_value` / `stun_attr_text` | O(value length) |
| address and error-code codecs | O(value length) |
| type/name helpers and `stun_padded_len` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module stun_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). The fixtures are the four RFC 5769 sample
messages verbatim plus hand-built hex messages:

1. RFC 5769 sample request (108 bytes): type/method/class, length 88,
   cookie, transaction ID, six attributes in order, SOFTWARE text, raw
   PRIORITY/MESSAGE-INTEGRITY/FINGERPRINT bytes and the 3-space USERNAME
   padding skipped (value is exactly 9 bytes).
2. RFC 5769 IPv4 response: class success, length 60, SOFTWARE
   "test vector", XOR-MAPPED-ADDRESS un-maps to 192.0.2.1:32853, raw
   MESSAGE-INTEGRITY and FINGERPRINT.
3. RFC 5769 IPv6 response: length 72, 20-byte XOR-MAPPED-ADDRESS
   un-maps to `2001:db8:1234:5678:11:2233:4455:6677`:32853.
4. RFC 5769 long-term request: UTF-8 USERNAME ("マトリックス", 18 bytes)
   and REALM, unknown NONCE (0x0015) and MESSAGE-INTEGRITY preserved, and
   `stun_build` from the parsed index reproduces the 116 bytes exactly.
5. Address encoders reproduce the RFC 5769 MAPPED-ADDRESS and
   XOR-MAPPED-ADDRESS values for IPv4 and IPv6 byte for byte.
6. `stun_build` writes a pinned 32-byte MAPPED-ADDRESS message exactly;
   parsing it back decodes family 1, port 8080 and 192.0.2.1.
7. `stun_build` pads a 9-byte USERNAME with three zero bytes and keeps
   attribute order; the pinned 52-byte message parses back.
8. `stun_is_message` matrix: valid headers and a message whose declared
   length overruns the buffer are true; short input, all-zero input and a
   type with bit 15 set are false.
9. Empty, 4-byte and 19-byte inputs are `stun: truncated header`.
10. Type bit 15 set and a zero cookie are the two errors; when both are
    wrong the type error wins.
11. Declared lengths beyond the buffer are `stun: truncated message`;
    an exact fit with a zero-length attribute parses to one attribute.
12. Trailing 2/3-byte partial headers are `stun: truncated attribute`;
    values whose declared length exceeds the remainder (with and without
    a valid prefix) are `stun: attribute overruns message`; padded spans
    that do not fit are `stun: bad padding` (message lengths 5 and 6).
13. `stun_build` rejects type 16384/-1, an 11-byte ID, mismatched vector
    lengths, attribute type 65536, a 65536-byte value and a 65535-byte
    value whose padded total exceeds 65535.
14. Accessors: count, -1/out-of-range type reads, `stun_find_attr` first
    match and -1, `stun_attr_value`/`stun_attr_text` range errors, a
    short source buffer (`stun: attribute out of bounds`) and an empty
    index.
15. Address codecs: family 3 (`stun: bad address family`) for decode and
    encode, family/length mismatch (`stun: bad address length`), a
    3-byte value (`stun: truncated address`), port 70000/-1
    (`stun: bad port`) and an 11-byte XOR transaction ID
    (`stun: bad transaction id`).
16. ERROR-CODE: encode 420/"Unknown Attribute" to pinned bytes, decode it
    back through a built message (code, reason, class bits), bounds 299/
    700, and a 3-byte value (`stun: truncated error code`).
17. Type packing inverts for classes 0..3 and method 0x123; out-of-range
    method/class/type inputs return -1; class/method/attribute names and
    `stun_padded_len` (including -1) match the documented set.
18. Header-only message (declared length 0) parses with zero attributes,
    building one reproduces the 20 bytes, trailing junk after the
    declared span is ignored, and a zero-length SOFTWARE attribute
    survives the round-trip.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.stun
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Parse-only validation: outgoing attribute values built through the
  generic `stun_build` are not semantically checked beyond size.
- The index stores offsets into the parse buffer; `stun_attr_value` and
  the decoders require the same buffer (or one holding the recorded
  spans).
- Unknown attributes are preserved but not interpreted; callers must
  know their value layout.
- `stun_attr_text` and the reason phrase inherit the stdlib's lenient
  `Str::from_utf8`; malformed UTF-8 is not rejected.
- Misaligned message lengths (not multiples of 4) are always rejected,
  even when the trailing bytes could be read as a value; the error is
  `stun: truncated attribute` or `stun: bad padding` depending on the
  shape.
- Only the Binding method has a name; TURN/ICE method names are
  "unknown".
- MESSAGE-INTEGRITY/FINGERPRINT are not verified, so the codec must not
  be used as an authentication check.
- Not thread-safe; `StunMessage` is a plain value type over shared
  source bytes.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_msg`/`_err_msg`/`_ok_addr`/`_err_addr`/`_ok_bytes`/`_err_bytes`/
  `_ok_str`/`_err_str`/`_ok_int`/`_err_int` (constructing Results directly
  inside larger functions miscompiles in this compiler).
- Bytes are never XORed with a bitwise operator: `_xor_byte` rebuilds the
  result bit by bit with modulo/division, and all 16/32-bit packing uses
  `_be_byte` arithmetic (`& 0xFF` on values with bit 31 set miscompiles,
  and bit-set operations on high values are not trustworthy).
- Every byte read from a `Vec[UInt8]` is widened with
  `(b as Int) & 0xFF`; a `&struct.field` expression is never passed as a
  `&Vec[UInt8]` parameter (a local is bound first, e.g. the transaction ID
  in `stun_attr_xor_mapped_address`).
- `StunMessage` and `StunAddress` are flat: no `Vec[StructType]` and no
  struct-typed fields; the attribute index uses three parallel `Vec[Int]`
  fields.
- The module compares no `Str` values; `stun_attr_name` and friends only
  return literals. The tests route every name and error comparison through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a `Str` read from a
  `Vec` lowers to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI).
- `tests/test_conformance.xi` calls its 18 test functions directly from
  `main`; there is no indexed `Vec[fn]` dispatch (which miscompiles).
