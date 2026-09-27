# xiom.proxy -- specification

Byte-exact specification of the HAProxy PROXY protocol structure codec
implemented by `src/proxy.xi` (package `xiom.proxy` 0.1.0). The module is a
pure codec: it owns no sockets and no connection state, and every parser
consumes one header at a time out of an in-memory `Vec[UInt8]`.

All offsets in error messages are absolute byte offsets in the caller's
buffer, except where explicitly said otherwise.

## 1. v1: human-readable header

```
v1-line  = "PROXY" SP family SP rest CRLF
family   = "TCP4" | "TCP6" | "UNKNOWN"
CRLF     = %x0D %x0A
SP       = %x20
```

* `TCP4`: `rest = src-ipv4 SP dst-ipv4 SP src-port SP dst-port` -- exactly
  four tokens.
* `TCP6`: `rest = src-ipv6 SP dst-ipv6 SP src-port SP dst-port` -- exactly
  four tokens.
* `UNKNOWN`: everything after the single space following `UNKNOWN` up to the
  CRLF is an **opaque tail**, copied verbatim into `ProxyV1.opaque` and
  otherwise ignored (it may be empty; `PROXY UNKNOWN\r\n` is 15 bytes).

### 1.1 Field formats

* IPv4: exactly four decimal parts, 1..3 digits each, separated by one dot,
  **no leading zero** (so `010.0.0.1` is rejected), each value <= 255.
  Stored/emitted canonically as `a.b.c.d`.
* IPv6: colon-hex groups, 1..4 hex digits each, at most one `::`, which must
  stand for at least one zero group (so at most 7 explicit groups with `::`,
  exactly 8 without). Zone ids (`%`) and embedded dotted quads are rejected.
  Parsing accepts upper and lower case; rendering is canonical lowercase with
  leading zeros removed and the **first longest** run of two or more zero
  groups replaced by `::` (`1:0:0:2:0:0:0:3` renders as `1:0:0:2::3`).
* Ports: decimal 0..65535, no leading zero.
* Tokens are separated by exactly one space: a leading space, a trailing
  space or a double space is `proxy: bad v1 fields`.

`proxy_parse_v1` stores the address text exactly as received (canonically
validated, not rewritten); the encoders re-render canonical text.

### 1.2 Line cap

The line, including CRLF, is at most **107 bytes** (the HAProxy worst case:
`PROXY UNKNOWN` plus two 39-byte IPv6 addresses and two 5-digit ports).
`proxy_parse_v1` looks for CRLF inside `[off, off+107)`:

* CRLF found at `off+105`: 107-byte line, accepted;
* no CRLF and `data.len() - off >= 107`: `proxy: v1 line too long at <off>`;
* no CRLF and fewer bytes: `proxy: truncated header at <off>`.

A bare CR or LF cannot terminate the line; only a full CRLF ends it. For
`UNKNOWN` a bare CR/LF inside the opaque tail is tolerated because the whole
tail is ignored.

### 1.3 Encoders

| Function | Output |
|----------|--------|
| `proxy_v1_encode_tcp4` | `PROXY TCP4 <src> <dst> <sport> <dport>\r\n`, addresses validated and re-rendered |
| `proxy_v1_encode_tcp6` | same with canonical lowercase/compressed IPv6 |
| `proxy_v1_encode_unknown` | `PROXY UNKNOWN\r\n` (15 bytes) |
| `proxy_v1_encode_unknown_opaque` | `PROXY UNKNOWN <tail>\r\n`; tail must not contain CR/LF and the line must stay <= 107 bytes |

Ports outside 0..65535 are `proxy: bad port`; non-canonical addresses are
`proxy: bad ipv4` / `proxy: bad ipv6`.

## 2. v2: binary header

```
offset  size  field
0       12    signature 0D 0A 0D 0A 00 0D 0A 51 55 49 54 0A
12      1     ver_cmd: high nibble version (must be 2), low nibble command
              (0 LOCAL, 1 PROXY; other values rejected)
13      1     fam_prot: high nibble family (0 UNSPEC, 1 INET, 2 INET6,
              3 UNIX; > 3 rejected), low nibble protocol (0 UNSPEC,
              1 STREAM, 2 DGRAM; > 2 rejected)
14      2     length in bytes following this 16-byte fixed header,
              big-endian (0..65535)
16      length payload: address block + optional TLV stream
```

The header is exactly `16 + length` bytes. `proxy_parse_v2` requires that
many bytes to be present; a longer buffer is fine and `consumed` is
`16 + length`, so the next header or the application payload starts at
`off + consumed`.

### 2.1 Address blocks

| family | block size | layout |
|--------|-----------|--------|
| UNSPEC | 0 | none |
| INET   | 12 | src(4) dst(4) src-port(2) dst-port(2), all network order |
| INET6  | 36 | src(16) dst(16) src-port(2) dst-port(2), all network order |
| UNIX   | 216 | src-path(108) dst-path(108), NUL padded |

Ports are present for INET/INET6 regardless of the protocol nibble (the
block layout is decided by the family); STREAM/DGRAM is expected in practice.
`proxy_v2_address_block_len` returns 0/12/36/216 or -1 for an invalid family.
`ProxyV2.src_addr`/`dst_addr` hold the packed addresses (4 or 16 bytes) and
`unix_src`/`unix_dst` the 108-byte fields; fields not covered by the family
stay empty.

### 2.2 Length and truncation rules

* `data.len() - off < 16`: `proxy: truncated header at <off>`.
* signature mismatch: `proxy: bad signature at <off+i>` for the first wrong
  byte.
* version nibble != 2: `proxy: bad version at <off+12>`.
* command nibble not 0/1: `proxy: bad command at <off+12>`.
* family > 3: `proxy: bad family at <off+13>`; protocol > 2:
  `proxy: bad protocol at <off+13>`.
* `data.len() - off < 16 + length`: `proxy: truncated header at <off>`.
* command PROXY with `length < block size`: `proxy: bad address block at
  <off+14>`.
* command LOCAL with `length < block size`: accepted. The address fields are
  left empty, `payload` holds the raw `length` bytes and `tlvs` stays empty,
  because the receiver must skip exactly the announced length and the
  family is not authoritative for LOCAL.
* otherwise `tlvs = payload[block size .. length]` and `tlvs_off` is the
  absolute offset where that TLV stream starts.

`ProxyV2.payload` always contains the raw `length` bytes after the fixed
header. For LOCAL headers every address field is parsed structurally when
present but is **not authoritative**: the receiver must use the real
connection endpoints (the PROXY protocol spec requires discarding the
protocol block for LOCAL; `proxy_v2_is_local` is the explicit predicate).

### 2.3 Encoders

| Function | command | family/protocol | block |
|----------|---------|-----------------|-------|
| `proxy_v2_encode_proxy_tcp4` | PROXY | INET/STREAM | 12 |
| `proxy_v2_encode_proxy_udp4` | PROXY | INET/DGRAM | 12 |
| `proxy_v2_encode_proxy_tcp6` | PROXY | INET6/STREAM | 36 |
| `proxy_v2_encode_proxy_udp6` | PROXY | INET6/DGRAM | 36 |
| `proxy_v2_encode_proxy_unix` | PROXY | UNIX/STREAM | 216, paths <= 108 bytes NUL padded |
| `proxy_v2_encode_proxy_unspec` | PROXY | UNSPEC/UNSPEC | 0 |
| `proxy_v2_encode_local` | LOCAL | UNSPEC/UNSPEC | 0 |
| `proxy_v2_header` | any valid | any valid | raw caller-supplied body |

`proxy_v2_header(command, family, protocol, body)` is the low-level builder
used by the others; it validates the nibbles and that `body.len() <= 65535`,
but does not enforce body/family consistency (receivers do). Encoders reject
wrong address sizes (`proxy: bad ipv4 bytes`, `proxy: bad ipv6 bytes`), ports
outside 0..65535 (`proxy: bad port`), UNIX paths longer than 108
(`proxy: unix path too long`) and oversized bodies (`proxy: body too long`).

### 2.4 Sizing note

The length field caps the payload at **65535** bytes (`proxy_v2_max_len`).
The protocol is designed so the whole header fits the smallest segment every
TCP host must accept: 576 - 40 = **536** bytes (`proxy_v2_recommended_max`).
Senders SHOULD keep `16 + length <= 536`; this codec accepts up to the u16
cap and does not reject 537+ (a receiver-side policy decision).

## 3. TLV stream

```
TLV = type(u8) length(u16, big-endian) value(length bytes)
```

A TLV stream is walked with `proxy_tlv_next` (offsets relative to the stream)
or `proxy_tlv_next_in` (absolute offsets in a larger buffer, with an explicit
end). A cursor carries `tlv_type`, `value_start`, `value_end` and `next`.
`proxy_tlv_count` counts the TLVs that parse cleanly from the start and stops
at the first malformed one; `proxy_tlv_first` returns the offset of the first
TLV of a type, or -1.

Errors: `proxy: bad TLV at <off>` (offset out of range/negative),
`proxy: truncated TLV at <off>` (fewer than 3 bytes left),
`proxy: TLV length overrun at <off>` (declared value runs past the end).

### 3.1 Implemented type registry (canonical HAProxy registry, 2020)

| type | name | value |
|------|------|-------|
| 0x01 | ALPN | opaque bytes (e.g. a TLS ALPN protocol id) |
| 0x02 | AUTHORITY | UTF-8 host/SNI bytes |
| 0x03 | CRC32C | 4-byte big-endian u32 checksum |
| 0x04 | NOOP | zero or more padding bytes |
| 0x05 | UNIQUE_ID | opaque connection id (spec recommends <= 128 bytes) |
| 0x20 | SSL | structured, see 3.2 |
| 0x30 | NETNS | NUL-terminated namespace path string, see 3.3 |
| 0xEA | AWS | sub-TLV stream, see 3.4 |

`proxy_tlv_type_name` maps ids to these names ("UNKNOWN" otherwise) and
`proxy_tlv_expected_width` returns 4 for 0x03 and 0 for variable/structured or
unknown types. Unknown types are preserved raw in the TLV stream; the codec
never drops or rewrites them.

### 3.2 SSL TLV (type 0x20)

```
offset  size  field
0       1     client flags (bit 0 SSL, bit 1 cert on this connection,
              bit 2 cert on this session)
1       4     verify result, big-endian u32 (0 = verified)
5       ...   second-level TLV stream (same TLV layout)
```

Second-level types: `0x21` PP2_SUBTYPE_SSL_VERSION, `0x22`
PP2_SUBTYPE_SSL_CN, `0x23` PP2_SUBTYPE_SSL_CIPHER, `0x24`
PP2_SUBTYPE_SSL_SIG_ALG, `0x25` PP2_SUBTYPE_SSL_KEY_ALG; all are
length-prefixed values (the spec carries US-ASCII names). Unknown sub-TLVs
are preserved raw. `proxy_ssl_sub_tlvs` validates the 5-byte fixed prefix and
returns its span, `proxy_ssl_client_flags`/`proxy_ssl_verify` read the fixed
fields, `proxy_ssl_subtype_name` maps ids to names, and `proxy_ssl_encode`
builds the whole TLV (value length at most 65530).

### 3.3 NETNS TLV (type 0x30)

The value is the namespace path as a NUL-terminated string.

* `proxy_tlv_encode_netns(path)` builds the TLV: path bytes followed by one
  `0x00` terminator (`Err("proxy: TLV too long")` when path+1 exceeds 65535).
* `proxy_tlv_netns_path(value)` returns the bytes before the first NUL
  (empty for a NUL-only value) and `Err("proxy: bad netns")` when the value
  carries no terminator.

### 3.4 AWS TLV (type 0xEA)

The value is itself a sub-TLV stream (same type/length/value layout).
Documented sub-types:

| sub-type | name | value |
|----------|------|-------|
| 0x01 | VPC endpoint id | length-prefixed id bytes |
| 0x02 | VPC id | length-prefixed id bytes |

`proxy_aws_subtype_name` maps these ids to `"VPC_ENDPOINT_ID"` / `"VPC_ID"`
("UNKNOWN" otherwise). `proxy_aws_value(value, subtype)` walks the sub-TLV
stream, returns a copy of the first matching value, skips unknown sub-TLVs
(which stay preserved raw in the value), propagates walker errors, and
returns `Err("proxy: aws subtype missing")` when no sub-TLV of that type is
present. `proxy_aws_vpc_endpoint_id` and `proxy_aws_vpc_id` are the 0x01 and
0x02 shorthands.

### 3.5 TLV value helpers

`proxy_tlv_encode(type, value)`, `proxy_tlv_encode_empty(type)` and the
typed builders `proxy_tlv_encode_u16`/`_u32`/`_u64` (u64 as two u32 halves,
big-endian). Readers `proxy_tlv_read_u16`/`_u32` require exactly 2/4 bytes;
`proxy_tlv_read_u64_parts` returns the full-range `(hi, lo)` pair and
`proxy_tlv_read_u64` returns one Int, rejecting values >= 2^63 with
`proxy: u64 out of range`. Width errors are `proxy: bad TLV value length`.

## 4. CRC32C

`proxy_crc32c(data, from, to)` is CRC-32C (Castagnoli) as specified by
RFC 4960 appendix B: reflected, polynomial `0x82F63B78`, initial value
`0xFFFFFFFF`, final XOR `0xFFFFFFFF`. Known vector:
`CRC32C("123456789") = 0xE3069283`.

`proxy_v2_crc32c(header, value_off)` computes the checksum of a complete v2
header with the 4 bytes at `value_off` treated as zero.
`proxy_v2_verify_crc32c(header)` walks the TLV stream, finds the first
`PP2_TYPE_CRC32C` TLV, requires a 4-byte value, and compares the computed and
received checksums. It returns `Ok(false)` when no CRC32C TLV is present (or
a LOCAL header has no interpretable TLV stream) and errors (`proxy: bad TLV
value length` and the walk errors) when a CRC32C TLV is malformed. Tampering
with any header byte flips the result to `false`.

## 5. One-header helpers

* `proxy_detect_version(data, off)` -> 0/1/2: 2 when the 12-byte signature is
  present, 1 when `"PROXY "` is present, 0 when neither is decidable (also
  for a truncated signature prefix).
* `proxy_header_len(data, off)` -> `Ok((version, consumed))` with framing
  only: v2 validates signature + nibbles + reads the length and needs only
  the 16 fixed bytes (the payload may still be in flight); v1 validates
  `"PROXY "` and locates CRLF inside the 107-byte cap. Errors mirror the
  parse errors above, plus `proxy: unknown version at <off>`.
* `proxy_parse_one(data, off)` -> `Ok(ProxySummary)` with version, command,
  v2 family/protocol ids (v1 TCP4/TCP6 map to INET/INET6 + STREAM, UNKNOWN to
  UNSPEC/UNSPEC), ports and consumed.
* `proxy_payload_span(data, off, consumed)` -> `Ok((off+consumed,
  data.len()))`: the span of bytes after the header (empty span when nothing
  follows). `Err("proxy: bad header size at <off>")` when the range is
  negative or runs past the buffer.

## 6. Constants

| Function | Value |
|----------|-------|
| `proxy_v1_max_line` | 107 |
| `proxy_v2_fixed_len` | 16 |
| `proxy_v2_max_len` | 65535 |
| `proxy_v2_recommended_max` | 536 |
| `proxy_magic_v2` | `0D 0A 0D 0A 00 0D 0A 51 55 49 54 0A` |
| `proxy_v1_prefix` | `"PROXY "` |

## 7. Error catalog

Framing and field errors (all with a byte offset):

```
proxy: negative offset at <off>
proxy: truncated header at <off>
proxy: v1 line too long at <off>
proxy: bad v1 prefix at <off>
proxy: bad v1 protocol at <off>
proxy: bad v1 fields at <off>
proxy: bad v1 address at <off>
proxy: bad decimal at <off>
proxy: bad signature at <off>
proxy: bad version at <off>
proxy: bad command at <off>
proxy: bad family at <off>
proxy: bad protocol at <off>
proxy: bad address block at <off>
proxy: unknown version at <off>
proxy: bad TLV at <off>
proxy: truncated TLV at <off>
proxy: TLV length overrun at <off>
proxy: bad header size at <off>
```

Offset-free validation errors:

```
proxy: bad ipv4            proxy: bad ipv4 bytes
proxy: bad ipv6            proxy: bad ipv6 bytes
proxy: bad port            proxy: bad opaque tail
proxy: bad command         proxy: bad family
proxy: bad protocol        proxy: body too long
proxy: unix path too long  proxy: bad ssl tlv
proxy: ssl too long        proxy: bad TLV type
proxy: bad TLV value       proxy: bad TLV value length
proxy: TLV too long        proxy: u64 out of range
proxy: bad crc range       proxy: bad crc offset
proxy: bad netns           proxy: aws subtype missing
```

## 8. API surface

64 public functions, grouped:

* version/identification: `proxy_detect_version`, `proxy_header_len`,
  `proxy_parse_one`, `proxy_parse_v1`, `proxy_parse_v2`,
  `proxy_payload_span`, `proxy_magic_v2`, `proxy_v1_prefix`,
  `proxy_version_name`, `proxy_command_name`, `proxy_family_name`,
  `proxy_protocol_name`, `proxy_v1_family_name`,
  `proxy_v2_address_block_len`, `proxy_v2_is_local`;
* limits: `proxy_v1_max_line`, `proxy_v2_fixed_len`, `proxy_v2_max_len`,
  `proxy_v2_recommended_max`;
* addresses: `proxy_ipv4_parse`, `proxy_ipv4_render`, `proxy_ipv6_parse`,
  `proxy_ipv6_render`;
* v1 encoding: `proxy_v1_encode_tcp4`, `proxy_v1_encode_tcp6`,
  `proxy_v1_encode_unknown`, `proxy_v1_encode_unknown_opaque`;
* v2 encoding: `proxy_v2_header`, `proxy_v2_encode_proxy_tcp4`,
  `proxy_v2_encode_proxy_udp4`, `proxy_v2_encode_proxy_tcp6`,
  `proxy_v2_encode_proxy_udp6`, `proxy_v2_encode_proxy_unix`,
  `proxy_v2_encode_proxy_unspec`, `proxy_v2_encode_local`;
* TLVs: `proxy_tlv_encode`, `proxy_tlv_encode_empty`,
  `proxy_tlv_encode_u16`, `proxy_tlv_encode_u32`, `proxy_tlv_encode_u64`,
  `proxy_tlv_read_u16`, `proxy_tlv_read_u32`, `proxy_tlv_read_u64`,
  `proxy_tlv_read_u64_parts`, `proxy_tlv_type_name`,
  `proxy_tlv_expected_width`, `proxy_tlv_next`, `proxy_tlv_next_in`,
  `proxy_tlv_count`, `proxy_tlv_first`;
* SSL: `proxy_ssl_encode`, `proxy_ssl_sub_tlvs`,
  `proxy_ssl_client_flags`, `proxy_ssl_verify`, `proxy_ssl_subtype_name`;
* NETNS: `proxy_tlv_encode_netns`, `proxy_tlv_netns_path`;
* AWS: `proxy_aws_subtype_name`, `proxy_aws_value`,
  `proxy_aws_vpc_endpoint_id`, `proxy_aws_vpc_id`;
* CRC32C: `proxy_crc32c`, `proxy_v2_crc32c`, `proxy_v2_verify_crc32c`.
