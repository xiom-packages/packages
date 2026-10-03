# xiom.proxy

HAProxy PROXY protocol **structure codec**: v1 text lines and v2 binary
headers, byte-exact, in pure XIOM.

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.3` on the XIOM registry.
> **Scope:** framing and field codec only. This package never opens a socket
> and owns no connection state; callers hand it `Vec[UInt8]` buffers and get
> typed structs plus exact `consumed` byte counts back, which is what a
> connection acceptor needs to strip a PROXY header from the front of its
> input buffer. See `SPEC.md` for the byte-level layouts.

## What is implemented

* **v1 text** (`PROXY TCP4|TCP6|UNKNOWN`): address/port fields, canonical
  IPv4 dotted-quad and IPv6 colon-hex parse/render (no zone ids), arbitrary
  opaque tails for `UNKNOWN`, single-space field rules, leading-zero
  rejection, and the **107-byte line cap** including CRLF.
* **v2 binary**: the 12-byte signature, version/command byte (LOCAL/PROXY),
  family/protocol byte (UNSPEC/INET/INET6/UNIX and UNSPEC/STREAM/DGRAM),
  big-endian `u16` length, IPv4 (12-byte), IPv6 (36-byte), UNIX (216-byte)
  and empty UNSPEC address blocks, plus truncation and length checks.
* **TLVs** after the address block: type `u8` + big-endian `u16` length +
  value; encode, walk, count, find. The canonical HAProxy registry (2020) is
  implemented: `0x01` ALPN, `0x02` AUTHORITY, `0x03` CRC32C (`u32`), `0x04`
  NOOP, `0x05` UNIQUE_ID, `0x20` SSL (nested TLV stream), `0x30` NETNS
  (NUL-terminated namespace path, with `proxy_tlv_encode_netns` /
  `proxy_tlv_netns_path`), and `0xEA` AWS (sub-TLV stream with
  `proxy_aws_vpc_endpoint_id` / `proxy_aws_vpc_id`). Unknown TLVs and
  unknown AWS sub-TLVs are preserved raw.
* **Nested SSL**: `u8` client flags + `u32` verify + second-level TLVs
  `0x21` VERSION, `0x22` CN, `0x23` CIPHER, `0x24` SIG_ALG, `0x25` KEY_ALG.
* **CRC32C**: Castagnoli (RFC 4960 appendix B) checksum plus verification of
  a header's `PP2_TYPE_CRC32C` TLV with the checksum field zeroed.
* **Helpers**: version detection from the first bytes, `proxy_header_len`
  framing (v2 works from the 16 fixed bytes alone), `proxy_parse_one`
  version-agnostic summary, `proxy_payload_span` for the bytes after a
  header, and byte-offset errors.

## What is *not* implemented

* No sockets, no accept loop, no timeouts, no connection state.
* No automatic protocol guessing: `proxy_detect_version` only reports what
  the first bytes are; callers must configure the protocol (the PROXY protocol
  spec explicitly forbids guessing).
* v1 IPv6 parsing accepts colon-hex groups only: zone ids (`%eth0`) and
  embedded dotted quads (`::ffff:1.2.3.4`) are rejected.
* No X.509 decoding: the SSL TLV is kept as bytes plus sub-TLV spans.
* Unknown TLVs are not type-checked against `proxy_tlv_expected_width`; the
  parser preserves them, the caller decides.
* AWS: only the documented sub-types (VPC endpoint id, VPC id) have named
  decoders; other sub-TLVs are walked/preserved raw.

## Usage

```xiom
use xiom.proxy;

fn read_header(buf: &Vec[UInt8]) -> Int {
  // 1. How long is the header? Works even before the whole v2 header is
  //    buffered (v2 needs only the 16 fixed bytes).
  let hl = proxy_header_len(buf, 0);
  if !hl.is_ok {
    // Bad or unknown header: drop the connection.
    return -1;
  }
  let pair: (Int, Int) = hl.value;
  let version: Int = pair.0;
  let consumed: Int = pair.1;

  // 2. Decode only when the whole header is buffered.
  if consumed > buf.len() {
    return 0; // need more bytes
  }
  if version == 2 {
    let op2 = proxy_parse_v2(buf, 0);
    if !op2.is_ok {
      return -1;
    }
    let op: ProxyV2 = op2.value;
    if op.command == 0 {
      // LOCAL: use the real connection endpoints; the parsed fields are not
      // authoritative.
      return op.consumed;
    }
    // op.src_addr / op.dst_addr are packed network-order bytes (4 or 16),
    // op.src_port / op.dst_port are the ports.
    return op.consumed;
  }

  let op1 = proxy_parse_v1(buf, 0);
  if !op1.is_ok {
    return -1;
  }
  let op: ProxyV1 = op1.value;
  // op.src_addr / op.dst_addr are the textual addresses as received;
  // op.family is proxy_v1_family_name(op.family) ("TCP4" / "TCP6" / "UNKNOWN").
  return op.consumed;
}
```

Encoding a header with TLVs (all buffer building is plain `Vec[UInt8]`):

```xiom
use xiom.proxy;

fn build_header() -> Result[Vec[UInt8], Str] {
  var h2 = Vec[UInt8].new();
  h2.push(104 as UInt8);               // 'h'
  h2.push(50 as UInt8);                // '2'
  let alpn = proxy_tlv_encode(1, &h2); // ALPN
  if !alpn.is_ok {
    return Err(alpn.error);
  }
  let body: Vec[UInt8] = alpn.value;
  var src = Vec[UInt8].new();
  src.push(192 as UInt8);              // 192.0.2.1 packed
  src.push(0 as UInt8);
  src.push(2 as UInt8);
  src.push(1 as UInt8);
  return proxy_v2_encode_proxy_tcp4(&src, &src, 8080, 443, &body);
}
```

The tests in `tests/test_conformance.xi` are the executable specification;
each synthetic header is built in-test from hex literals.

## Error convention

All parse errors are `Str` values of the form `proxy: <what> at <offset>`,
where `<offset>` is the absolute byte offset in the caller's buffer of the
first offending byte (or of the header start for whole-line framing errors).
The TLV walker reports offsets relative to the TLV stream when called via
`proxy_tlv_next`, and absolute offsets when called via `proxy_tlv_next_in`.

## Build and test

```powershell
# from the repository root
.\scripts\port.ps1 -Package xiom.proxy
```

## License

MIT OR Apache-2.0.
