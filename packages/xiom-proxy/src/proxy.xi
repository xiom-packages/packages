// XIOM -- xiom.proxy: HAProxy PROXY protocol v1/v2 structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no connection state) encoder/parser for the
// HAProxy PROXY protocol structure, both wire formats:
//
//   v1  human-readable line: "PROXY TCP4|TCP6|UNKNOWN ..." CRLF
//   v2  binary header: 12-byte signature + ver/cmd + fam/proto + u16 length,
//       followed by the address block and an optional TLV stream.
//
// Scope: framing and field codec only. Nothing in this module opens, reads or
// writes a socket; callers hand it Vec[UInt8] buffers and get typed structs
// plus exact consumed byte counts back, which is what a connection acceptor
// needs to strip a header from the front of its input buffer.
//
// v1 rules implemented (HAProxy proxy-protocol.txt section 2.1):
//   - line length at most 107 bytes including CRLF; overlong lines and lines
//     without CRLF inside that window are rejected;
//   - "PROXY " followed by TCP4, TCP6 or UNKNOWN;
//   - TCP4/TCP6: source address, destination address, source port,
//     destination port, single spaces, CRLF; ports are decimal 0..65535 with
//     no leading zeroes; IPv4 is dotted-quad with no leading zeroes;
//   - UNKNOWN: the rest of the line before CRLF is an opaque tail, copied
//     verbatim and otherwise ignored;
//   - CRLF framing errors carry the byte offset where the header was expected.
//
// v2 rules implemented (section 2.2):
//   - 12-byte signature 0D 0A 0D 0A 00 0D 0A 51 55 49 54 0A;
//   - version high nibble must be 2 (other values rejected); command low
//     nibble must be LOCAL (0) or PROXY (1);
//   - family high nibble of byte 13 must be AF_UNSPEC (0), AF_INET (1),
//     AF_INET6 (2) or AF_UNIX (3); protocol low nibble must be UNSPEC (0),
//     STREAM (1) or DGRAM (2);
//   - u16 big-endian length = address block + TLV stream; the header is
//     exactly 16 + length bytes; a length that does not fit the buffer is a
//     truncation error, and for PROXY commands a length smaller than the
//     family's address block is an error;
//   - INET block 2*4 + 2*2 = 12 bytes, INET6 block 2*16 + 2*2 = 36 bytes,
//     UNIX block 2*108 = 216 bytes, UNSPEC block 0 bytes;
//   - LOCAL headers may carry a short or absent address block; this codec
//     keeps the parsed fields but marks them non-authoritative and never
//     requires the family block, because the receiver must skip exactly the
//     announced length;
//   - TLVs: type u8 + big-endian u16 length + value. The canonical HAProxy
//     registry (2020) is implemented: ALPN (0x01), AUTHORITY (0x02), CRC32C
//     (0x03, u32), NOOP (0x04), UNIQUE_ID (0x05), SSL (0x20, structured),
//     NETNS (0x30, NUL-terminated namespace path) and AWS (0xEA, sub-TLV
//     stream). Unknown TLVs are kept raw and can be walked without
//     interpretation.
//   - the SSL value is u8 client flags + u32 verify + a nested TLV stream
//     (VERSION 0x21, CN 0x22, CIPHER 0x23, SIG_ALG 0x24, KEY_ALG 0x25).
//   - the AWS value is a sub-TLV stream; documented sub-types are VPC
//     endpoint id (0x01) and VPC id (0x02), both length-prefixed values.
//   - CRC32C helpers implement RFC 4960 appendix B (Castagnoli, reflected
//     polynomial 0x82F63B78) over the header with the checksum field zeroed.
//
// Errors are Str values of the form "proxy: <what> at <offset>", where
// <offset> is the absolute byte offset in the caller's buffer of the first
// offending byte (or of the header start for whole-line framing errors).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles);
//   * every byte read from a Vec[UInt8] widens with `(data[pos] as Int) &
//     0xFF` before it enters Int arithmetic or comparisons;
//   * Vec reads are bound to typed locals and struct fields are copied into
//     typed locals before they are passed by reference;
//   * big-endian u16/u32 reads and writes are explicit byte composition;
//   * free functions only, no match-in-src, no Vec[StructType], no
//     angle-bracket generics, no `log`, no floats, no `&mut Int` out-params.

module xiom.proxy

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Byte constants (Int, always compared masked)
// --------------------------------------------------

const _PX_SPACE: Int = 32;
const _PX_CR: Int = 13;
const _PX_LF: Int = 10;
const _PX_DOT: Int = 46;
const _PX_COLON: Int = 58;
const _PX_PERCENT: Int = 37;

// v1 line cap including CRLF (HAProxy: a 108-byte buffer always suffices).
const _PX_V1_MAX_LINE: Int = 107;

// v2 fixed header (signature + ver/cmd + fam/proto + u16 length).
const _PX_V2_FIXED: Int = 16;

// v2 length field cap (u16) and the recommended atomic-header budget: the
// whole header is designed to fit in the smallest guaranteed TCP segment
// (576 - 40 = 536 bytes), so senders SHOULD keep 16 + length <= 536.
const _PX_V2_MAX_LEN: Int = 65535;
const _PX_V2_RECOMMENDED: Int = 536;

const _PX_U16_MAX: Int = 65535;
const _PX_U32_MAX: Int = 4294967295;
const _PX_INT31_MAX: Int = 2147483647;

// Reflected Castagnoli polynomial for CRC-32C (0x82F63B78).
const _PX_CRC32C_POLY: Int = 2197175160;

const _PX_VERSION_1: Int = 1;
const _PX_VERSION_2: Int = 2;

const _PX_CMD_LOCAL: Int = 0;
const _PX_CMD_PROXY: Int = 1;

const _PX_FAM_UNSPEC: Int = 0;
const _PX_FAM_INET: Int = 1;
const _PX_FAM_INET6: Int = 2;
const _PX_FAM_UNIX: Int = 3;

const _PX_PROTO_UNSPEC: Int = 0;
const _PX_PROTO_STREAM: Int = 1;
const _PX_PROTO_DGRAM: Int = 2;

const _PX_V1_UNKNOWN: Int = 0;
const _PX_V1_TCP4: Int = 1;
const _PX_V1_TCP6: Int = 2;

const _PX_TLV_ALPN: Int = 1;
const _PX_TLV_AUTHORITY: Int = 2;
const _PX_TLV_CRC32C: Int = 3;
const _PX_TLV_NOOP: Int = 4;
const _PX_TLV_UNIQUE_ID: Int = 5;
const _PX_TLV_SSL: Int = 32;
const _PX_TLV_NETNS: Int = 48;
const _PX_TLV_AWS: Int = 234;

const _PX_SSL_VERSION: Int = 33;   // PP2_SUBTYPE_SSL_VERSION (0x21)
const _PX_SSL_CN: Int = 34;        // PP2_SUBTYPE_SSL_CN (0x22)
const _PX_SSL_CIPHER: Int = 35;    // PP2_SUBTYPE_SSL_CIPHER (0x23)
const _PX_SSL_SIG_ALG: Int = 36;   // PP2_SUBTYPE_SSL_SIG_ALG (0x24)
const _PX_SSL_KEY_ALG: Int = 37;   // PP2_SUBTYPE_SSL_KEY_ALG (0x25)

// Documented AWS sub-TLV types (inside PP2_TYPE_AWS, 0xEA).
const _PX_AWS_VPC_ENDPOINT: Int = 1;
const _PX_AWS_VPC: Int = 2;

// --------------------------------------------------
//  Decoded structures
// --------------------------------------------------

/// One decoded v1 header line. `family` is a _PX_V1_* id (UNKNOWN 0, TCP4 1,
/// TCP6 2). `src_addr`/`dst_addr` hold the textual addresses exactly as they
/// appeared on the wire (canonical form is validated, not rewritten).
/// `opaque` is the UNKNOWN tail after the protocol token (empty for TCP4/
/// TCP6). `consumed` counts the line including CRLF, starting at the parse
/// offset.
pub type ProxyV1 = {
  family: Int;
  src_addr: Vec[UInt8];
  dst_addr: Vec[UInt8];
  src_port: Int;
  dst_port: Int;
  opaque: Vec[UInt8];
  consumed: Int;
}

/// One decoded v2 header. `command` is LOCAL (0) or PROXY (1); `family` and
/// `protocol` are the validated nibbles. `src_addr`/`dst_addr` are packed
/// network-order addresses for INET (4 bytes) and INET6 (16 bytes), empty
/// otherwise; `src_port`/`dst_port` are ports for INET/INET6 and 0
/// otherwise. `unix_src`/`unix_dst` are the 108-byte AF_UNIX fields.
/// `tlvs` is the TLV stream when the announced length covers the family
/// block (always the case for PROXY because short blocks are rejected);
/// `payload` is the raw bytes after the 16-byte fixed header. `tlvs_off` is
/// the absolute buffer offset where `tlvs` starts. `consumed` = 16 + length.
/// For LOCAL headers every address field is structurally parsed but NOT
/// authoritative: the receiver must use the real connection endpoints.
pub type ProxyV2 = {
  version: Int;
  command: Int;
  family: Int;
  protocol: Int;
  src_addr: Vec[UInt8];
  dst_addr: Vec[UInt8];
  src_port: Int;
  dst_port: Int;
  unix_src: Vec[UInt8];
  unix_dst: Vec[UInt8];
  tlvs: Vec[UInt8];
  payload: Vec[UInt8];
  tlvs_off: Int;
  consumed: Int;
}

/// Version-agnostic structural summary returned by proxy_parse_one: enough to
/// dispatch without decoding addresses. `family`/`protocol` use the v2 ids;
/// for v1 lines TCP4/TCP6 map to INET/INET6 + STREAM and UNKNOWN maps to
/// UNSPEC/UNSPEC. `command` is always PROXY for v1 and the header nibble for
/// v2 (for LOCAL it is not authoritative).
pub type ProxySummary = {
  version: Int;
  command: Int;
  family: Int;
  protocol: Int;
  src_port: Int;
  dst_port: Int;
  consumed: Int;
}

/// One TLV located inside a TLV stream: `value_start`/`value_end` are offsets
/// into the buffer the cursor was walked in, `next` is the offset just after
/// the TLV. All offsets are plain Ints; callers keep the buffer alive.
pub type ProxyTlvCursor = {
  tlv_type: Int;
  value_start: Int;
  value_end: Int;
  next: Int;
}

// --------------------------------------------------
//  Result constructors (leaf-only, see module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// Ok(v) for Result[ProxyV1, Str].
fn _ok_v1(v: ProxyV1) -> Result[ProxyV1, Str] {
  return Ok(v);
}

// Err(m) for Result[ProxyV1, Str].
fn _err_v1(m: Str) -> Result[ProxyV1, Str] {
  return Err(m);
}

// Ok(v) for Result[ProxyV2, Str].
fn _ok_v2(v: ProxyV2) -> Result[ProxyV2, Str] {
  return Ok(v);
}

// Err(m) for Result[ProxyV2, Str].
fn _err_v2(m: Str) -> Result[ProxyV2, Str] {
  return Err(m);
}

// Ok(v) for Result[ProxySummary, Str].
fn _ok_sum(v: ProxySummary) -> Result[ProxySummary, Str] {
  return Ok(v);
}

// Err(m) for Result[ProxySummary, Str].
fn _err_sum(m: Str) -> Result[ProxySummary, Str] {
  return Err(m);
}

// Ok(v) for Result[ProxyTlvCursor, Str].
fn _ok_tlv(v: ProxyTlvCursor) -> Result[ProxyTlvCursor, Str] {
  return Ok(v);
}

// Err(m) for Result[ProxyTlvCursor, Str].
fn _err_tlv(m: Str) -> Result[ProxyTlvCursor, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Decimal text of v for error messages and decimal fields (never 0x00).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// "<msg> at <off>": the error text convention of this module.
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + _int_str(off);
}

// Append every byte of v to out.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append data[a, b) to out; callers guarantee the bounds.
fn _copy_span(data: &Vec[UInt8], a: Int, b: Int, out: &mut Vec[UInt8]) {
  var i = a;
  while i < b {
    out.push(data[i]);
    i = i + 1;
  }
}

// Append v (0..65535) as two big-endian bytes.
fn _push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) & 0xFF) as UInt8);
  out.push((v & 0xFF) as UInt8);
}

// Unsigned big-endian u16 at [pos, pos+2); callers guarantee the bounds.
fn _read_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Append v (0..4294967295) as four big-endian bytes.
fn _push_u32(out: &mut Vec[UInt8], v: Int) {
  _push_u16(out, (v / 65536) & _PX_U16_MAX);
  _push_u16(out, v & _PX_U16_MAX);
}

// Unsigned big-endian u32 at [pos, pos+4); callers guarantee the bounds.
fn _read_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _read_u16(data, pos) * 65536 + _read_u16(data, pos + 2);
}

// Append a u64 given as its two u32 halves (hi first), big-endian.
fn _push_u64_parts(out: &mut Vec[UInt8], hi: Int, lo: Int) {
  _push_u32(out, hi);
  _push_u32(out, lo);
}

// Lowercase hex character code for a nibble 0..15.
fn _hex_char(d: Int) -> UInt8 {
  if d < 10 {
    return ((48 + d) & 0xFF) as UInt8;
  }
  return ((87 + d) & 0xFF) as UInt8;
}

// Hex value of a byte, or -1 when it is not an ASCII hex digit.
fn _hex_val(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 97 && c <= 102 { return c - 87; }
  if c >= 65 && c <= 70 { return c - 55; }
  return -1;
}

// Append one 16-bit group as lowercase hex without leading zeroes.
fn _push_group_hex(out: &mut Vec[UInt8], v: Int) {
  if v == 0 {
    out.push(48 as UInt8);
    return;
  }
  var started = false;
  var place = 4096;
  while place > 0 {
    let d = (v / place) % 16;
    if d != 0 { started = true; }
    if started { out.push(_hex_char(d)); }
    place = place / 16;
  }
}

// Append one 16-bit group as two big-endian bytes.
fn _push_group_bytes(out: &mut Vec[UInt8], v: Int) {
  _push_u16(out, v);
}

// Index of the CR of the first CRLF in [from, limit), or -1.
fn _find_crlf(data: &Vec[UInt8], from: Int, limit: Int) -> Int {
  var i = from;
  while i + 1 < limit {
    if _byte(data, i) == _PX_CR && _byte(data, i + 1) == _PX_LF {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first byte equal to `target` in [from, to), or -1.
fn _find_byte(data: &Vec[UInt8], from: Int, to: Int, target: Int) -> Int {
  var i = from;
  while i < to {
    if _byte(data, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when data[a, b) is exactly the ASCII literal `lit` (case-sensitive).
fn _span_eq_lit(data: &Vec[UInt8], a: Int, b: Int, lit: Str) -> Bool {
  if b - a != lit.len() {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    if _byte(data, a + i) != ((string.byte_at(lit, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Split data[start, end) on single spaces and push the token spans into
// `spans` (two Ints per token). A leading space, a trailing space or a double
// space makes the split fail (spans may then hold the tokens seen so far).
fn _split_tokens(data: &Vec[UInt8], start: Int, end: Int, spans: &mut Vec[Int]) -> Bool {
  var i = start;
  while i < end {
    if _byte(data, i) == _PX_SPACE {
      return false;
    }
    let ts = i;
    while i < end && _byte(data, i) != _PX_SPACE {
      i = i + 1;
    }
    spans.push(ts);
    spans.push(i);
    if i < end {
      i = i + 1;
      if i >= end {
        return false;
      }
    }
  }
  return true;
}

// Parse data[a, b) as a canonical decimal integer (1..cap, no sign, no
// leading zero except "0"). Err("proxy: bad decimal").
fn _parse_dec(data: &Vec[UInt8], a: Int, b: Int, cap: Int) -> Result[Int, Str] {
  if a >= b {
    return _err_int("proxy: bad decimal");
  }
  if _byte(data, a) == 48 && b - a > 1 {
    return _err_int("proxy: bad decimal");
  }
  let lim = cap / 10;
  let rem = cap % 10;
  var v: Int = 0;
  var i = a;
  while i < b {
    let c = _byte(data, i);
    if c < 48 || c > 57 {
      return _err_int("proxy: bad decimal");
    }
    let d = c - 48;
    if v > lim {
      return _err_int("proxy: bad decimal");
    }
    if v == lim && d > rem {
      return _err_int("proxy: bad decimal");
    }
    v = v * 10 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// --------------------------------------------------
//  Protocol identification and constants
// --------------------------------------------------

/// Maximum v1 line length in bytes including CRLF. Params: none.
/// Returns: 107. Error case: none.
pub fn proxy_v1_max_line() -> Int { return _PX_V1_MAX_LINE; }

/// v2 fixed header length in bytes (signature + 4 control bytes).
/// Params: none. Returns: 16. Error case: none.
pub fn proxy_v2_fixed_len() -> Int { return _PX_V2_FIXED; }

/// v2 length-field cap in bytes (the u16 maximum). Params: none.
/// Returns: 65535. Error case: none.
pub fn proxy_v2_max_len() -> Int { return _PX_V2_MAX_LEN; }

/// Recommended maximum total v2 header size (16 + length) so the whole header
/// fits the smallest TCP segment every host must accept (576 - 40 = 536).
/// Params: none. Returns: 536. Error case: none.
pub fn proxy_v2_recommended_max() -> Int { return _PX_V2_RECOMMENDED; }

/// The 12-byte v2 signature. Params: none.
/// Returns: 0D 0A 0D 0A 00 0D 0A 51 55 49 54 0A. Error case: none.
pub fn proxy_magic_v2() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_magic_v2(&mut out);
  return out;
}

// Append the 12 v2 signature bytes.
fn _push_magic_v2(out: &mut Vec[UInt8]) {
  out.push(13 as UInt8);
  out.push(10 as UInt8);
  out.push(13 as UInt8);
  out.push(10 as UInt8);
  out.push(0 as UInt8);
  out.push(13 as UInt8);
  out.push(10 as UInt8);
  out.push(81 as UInt8);
  out.push(85 as UInt8);
  out.push(73 as UInt8);
  out.push(84 as UInt8);
  out.push(10 as UInt8);
}

// Signature byte i (0..11) as an Int.
fn _sig_byte(i: Int) -> Int {
  if i == 0 { return 13; }
  if i == 1 { return 10; }
  if i == 2 { return 13; }
  if i == 3 { return 10; }
  if i == 4 { return 0; }
  if i == 5 { return 13; }
  if i == 6 { return 10; }
  if i == 7 { return 81; }
  if i == 8 { return 85; }
  if i == 9 { return 73; }
  if i == 10 { return 84; }
  return 10;
}

// True when data[off, off+12) is exactly the v2 signature.
fn _magic_at(data: &Vec[UInt8], off: Int) -> Bool {
  var i = 0;
  while i < 12 {
    if _byte(data, off + i) != _sig_byte(i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when data[off, off+avail) is a prefix of the v2 signature.
fn _prefix_of_magic(data: &Vec[UInt8], off: Int, avail: Int) -> Bool {
  if avail <= 0 { return false; }
  var i = 0;
  while i < avail {
    if _byte(data, off + i) != _sig_byte(i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// The v1 line prefix. Params: none. Returns: "PROXY ". Error case: none.
pub fn proxy_v1_prefix() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(80 as UInt8);
  out.push(82 as UInt8);
  out.push(79 as UInt8);
  out.push(88 as UInt8);
  out.push(89 as UInt8);
  out.push(32 as UInt8);
  return out;
}

/// Detect the header version from the first bytes at `off`: 2 when the 12-byte
/// v2 signature is present, 1 when the buffer starts with "PROXY ", 0 when
/// neither is decidable (including a truncated prefix). Params: data - the
/// buffer; off - header start. Returns: 0, 1 or 2. Error case: none.
/// Complexity: O(1).
pub fn proxy_detect_version(data: &Vec[UInt8], off: Int) -> Int {
  if off < 0 {
    return 0;
  }
  if data.len() - off >= 12 && _magic_at(data, off) {
    return _PX_VERSION_2;
  }
  if data.len() - off >= 6 && _span_eq_lit(data, off, off + 6, "PROXY ") {
    return _PX_VERSION_1;
  }
  return 0;
}

/// Name of a version id ("V1", "V2", "UNKNOWN"). Params: v - version id.
/// Returns: the name. Error case: none.
pub fn proxy_version_name(v: Int) -> Str {
  if v == _PX_VERSION_1 { return "V1"; }
  if v == _PX_VERSION_2 { return "V2"; }
  return "UNKNOWN";
}

/// Name of a v2 command id ("LOCAL", "PROXY", "UNKNOWN"). Params: c - command
/// nibble. Returns: the name. Error case: none.
pub fn proxy_command_name(c: Int) -> Str {
  if c == _PX_CMD_LOCAL { return "LOCAL"; }
  if c == _PX_CMD_PROXY { return "PROXY"; }
  return "UNKNOWN";
}

/// Name of a v2 family id ("UNSPEC", "INET", "INET6", "UNIX", "UNKNOWN").
/// Params: f - family nibble. Returns: the name. Error case: none.
pub fn proxy_family_name(f: Int) -> Str {
  if f == _PX_FAM_UNSPEC { return "UNSPEC"; }
  if f == _PX_FAM_INET { return "INET"; }
  if f == _PX_FAM_INET6 { return "INET6"; }
  if f == _PX_FAM_UNIX { return "UNIX"; }
  return "UNKNOWN";
}

/// Name of a v2 protocol id ("UNSPEC", "STREAM", "DGRAM", "UNKNOWN").
/// Params: p - protocol nibble. Returns: the name. Error case: none.
pub fn proxy_protocol_name(p: Int) -> Str {
  if p == _PX_PROTO_UNSPEC { return "UNSPEC"; }
  if p == _PX_PROTO_STREAM { return "STREAM"; }
  if p == _PX_PROTO_DGRAM { return "DGRAM"; }
  return "UNKNOWN";
}

/// Name of a v1 family id ("UNKNOWN", "TCP4", "TCP6", "UNKNOWN").
/// Params: f - v1 family id. Returns: the name. Error case: none.
pub fn proxy_v1_family_name(f: Int) -> Str {
  if f == _PX_V1_UNKNOWN { return "UNKNOWN"; }
  if f == _PX_V1_TCP4 { return "TCP4"; }
  if f == _PX_V1_TCP6 { return "TCP6"; }
  return "UNKNOWN";
}

/// Size of the v2 address block for a family: UNSPEC 0, INET 12, INET6 36,
/// UNIX 216, and -1 for a family outside 0..3. Params: family - family nibble.
/// Returns: the byte size or -1. Error case: none.
pub fn proxy_v2_address_block_len(family: Int) -> Int {
  if family == _PX_FAM_UNSPEC { return 0; }
  if family == _PX_FAM_INET { return 12; }
  if family == _PX_FAM_INET6 { return 36; }
  if family == _PX_FAM_UNIX { return 216; }
  return -1;
}

/// True when the command byte is LOCAL (0). For LOCAL headers the parsed
/// address fields are not authoritative. Params: command - command nibble.
/// Returns: the predicate. Error case: none.
pub fn proxy_v2_is_local(command: Int) -> Bool {
  return command == _PX_CMD_LOCAL;
}

// --------------------------------------------------
//  IPv4 text parse/render
// --------------------------------------------------

// True when data[a, b) is a canonical dotted quad: four decimal parts,
// 1..3 digits each, no leading zero, each value <= 255.
fn _ipv4_span_ok(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  var i = a;
  var part = 0;
  while part < 4 {
    var v = 0;
    var cnt = 0;
    while i < b && _byte(data, i) != _PX_DOT {
      let c = _byte(data, i);
      if c < 48 || c > 57 {
        return false;
      }
      v = v * 10 + (c - 48);
      cnt = cnt + 1;
      if cnt > 3 {
        return false;
      }
      i = i + 1;
    }
    if cnt == 0 {
      return false;
    }
    if cnt > 1 && _byte(data, i - cnt) == 48 {
      return false;
    }
    if v > 255 {
      return false;
    }
    part = part + 1;
    if part < 4 {
      if i >= b || _byte(data, i) != _PX_DOT {
        return false;
      }
      i = i + 1;
    }
  }
  return i == b;
}

/// Parse a textual IPv4 address into 4 packed network-order bytes. Rejects
/// empty, non-decimal, non-canonical (leading zero) and out-of-range parts.
/// Params: text - dotted quad. Returns: the 4 bytes.
/// Error case: Err("proxy: bad ipv4").
pub fn proxy_ipv4_parse(text: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_ipv4_span_ok(text, 0, text.len()) {
    return _err_bytes("proxy: bad ipv4");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < text.len() {
    var v = 0;
    while i < text.len() && _byte(text, i) != _PX_DOT {
      v = v * 10 + (_byte(text, i) - 48);
      i = i + 1;
    }
    out.push((v & 0xFF) as UInt8);
    if i < text.len() {
      i = i + 1;
    }
  }
  return _ok_bytes(out);
}

/// Render 4 packed IPv4 bytes as a canonical dotted quad ("a.b.c.d").
/// Params: bytes - exactly 4 bytes. Returns: the text.
/// Error case: Err("proxy: bad ipv4 bytes") when bytes.len() != 4.
pub fn proxy_ipv4_render(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if bytes.len() != 4 {
    return _err_bytes("proxy: bad ipv4 bytes");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    if i > 0 { out.push(46 as UInt8); }
    builder.sb_push_int(&mut out, _byte(bytes, i));
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  IPv6 text parse/render (colon-hex, no zone ids)
// --------------------------------------------------

/// Parse a textual IPv6 address (colon-hex groups with at most one "::", no
/// zone id, no embedded dotted quad) into 16 packed network-order bytes.
/// Each group is 1..4 hex digits; "::" must stand for at least one zero
/// group, so at most 7 explicit groups may accompany it. Params: text - the
/// address. Returns: the 16 bytes. Error case: Err("proxy: bad ipv6").
pub fn proxy_ipv6_parse(text: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = text.len();
  if n == 0 {
    return _err_bytes("proxy: bad ipv6");
  }
  var vals = Vec[Int].new();
  var dbl: Int = -1;
  var i = 0;
  if _byte(text, 0) == _PX_COLON {
    if n < 2 || _byte(text, 1) != _PX_COLON {
      return _err_bytes("proxy: bad ipv6");
    }
    dbl = 0;
    i = 2;
  }
  while i < n {
    var v: Int = 0;
    var cnt: Int = 0;
    while i < n {
      let h = _hex_val(_byte(text, i));
      if h < 0 {
        break;
      }
      v = v * 16 + h;
      cnt = cnt + 1;
      if cnt > 4 {
        return _err_bytes("proxy: bad ipv6");
      }
      i = i + 1;
    }
    if cnt == 0 {
      return _err_bytes("proxy: bad ipv6");
    }
    vals.push(v);
    if i >= n {
      break;
    }
    if _byte(text, i) != _PX_COLON {
      return _err_bytes("proxy: bad ipv6");
    }
    i = i + 1;
    if i >= n {
      return _err_bytes("proxy: bad ipv6");
    }
    if _byte(text, i) == _PX_COLON {
      if dbl >= 0 {
        return _err_bytes("proxy: bad ipv6");
      }
      dbl = vals.len();
      i = i + 1;
      if i >= n {
        break;
      }
    }
  }
  var out = Vec[UInt8].new();
  if dbl < 0 {
    if vals.len() != 8 {
      return _err_bytes("proxy: bad ipv6");
    }
    var g = 0;
    while g < 8 {
      let gv: Int = vals[g];
      _push_group_bytes(&mut out, gv);
      g = g + 1;
    }
    return _ok_bytes(out);
  }
  if vals.len() > 7 {
    return _err_bytes("proxy: bad ipv6");
  }
  let zeros = 8 - vals.len();
  var g = 0;
  while g < dbl {
    let gv: Int = vals[g];
    _push_group_bytes(&mut out, gv);
    g = g + 1;
  }
  var z = 0;
  while z < zeros {
    _push_group_bytes(&mut out, 0);
    z = z + 1;
  }
  while g < vals.len() {
    let gv: Int = vals[g];
    _push_group_bytes(&mut out, gv);
    g = g + 1;
  }
  return _ok_bytes(out);
}

// Longest run of zero groups (length >= 2, first longest), or -1.
fn _zero_run_start(g: &Vec[Int]) -> Int {
  var best_start: Int = -1;
  var best_len: Int = 0;
  var s = 0;
  while s < 8 {
    let gv: Int = g[s];
    if gv == 0 {
      let rs = s;
      var zz = s;
      while zz < 8 {
        let zv: Int = g[zz];
        if zv != 0 {
          break;
        }
        zz = zz + 1;
      }
      let rl = zz - rs;
      if rl >= 2 && rl > best_len {
        best_len = rl;
        best_start = rs;
      }
      s = zz;
    } else {
      s = s + 1;
    }
  }
  return best_start;
}

// Length of the zero run starting at best_start (only called with a valid
// best_start from _zero_run_start).
fn _zero_run_len(g: &Vec[Int], best_start: Int) -> Int {
  var zz = best_start;
  while zz < 8 {
    let zv: Int = g[zz];
    if zv != 0 {
      break;
    }
    zz = zz + 1;
  }
  return zz - best_start;
}

/// Render 16 packed IPv6 bytes as canonical lowercase compressed text (the
/// longest zero run of two or more groups becomes "::"). Params: bytes -
/// exactly 16 bytes. Returns: the text.
/// Error case: Err("proxy: bad ipv6 bytes") when bytes.len() != 16.
pub fn proxy_ipv6_render(bytes: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if bytes.len() != 16 {
    return _err_bytes("proxy: bad ipv6 bytes");
  }
  var g = Vec[Int].new();
  var i = 0;
  while i < 16 {
    let hi = _byte(bytes, i);
    let lo = _byte(bytes, i + 1);
    g.push(hi * 256 + lo);
    i = i + 2;
  }
  let bstart = _zero_run_start(&g);
  var out = Vec[UInt8].new();
  if bstart < 0 {
    var k = 0;
    while k < 8 {
      if k > 0 { out.push(58 as UInt8); }
      let gv: Int = g[k];
      _push_group_hex(&mut out, gv);
      k = k + 1;
    }
    return _ok_bytes(out);
  }
  let blen = _zero_run_len(&g, bstart);
  var k = 0;
  while k < bstart {
    if k > 0 { out.push(58 as UInt8); }
    let gv: Int = g[k];
    _push_group_hex(&mut out, gv);
    k = k + 1;
  }
  out.push(58 as UInt8);
  out.push(58 as UInt8);
  k = bstart + blen;
  while k < 8 {
    if k > bstart + blen { out.push(58 as UInt8); }
    let gv: Int = g[k];
    _push_group_hex(&mut out, gv);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// True when data[a, b) parses as an IPv6 address.
fn _ipv6_span_ok(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  var tmp = Vec[UInt8].new();
  _copy_span(data, a, b, &mut tmp);
  let r = proxy_ipv6_parse(&tmp);
  return r.is_ok;
}

// --------------------------------------------------
//  v1 line encode
// --------------------------------------------------

// Build the v1 family token + fields for a validated TCP header.
fn _v1_make(family: Int, src: Vec[UInt8], dst: Vec[UInt8], sport: Int, dport: Int, opaque: Vec[UInt8], consumed: Int) -> ProxyV1 {
  return ProxyV1{
    family: family;
    src_addr: src;
    dst_addr: dst;
    src_port: sport;
    dst_port: dport;
    opaque: opaque;
    consumed: consumed;
  };
}

/// Encode the short UNKNOWN form: "PROXY UNKNOWN\r\n". Params: none.
/// Returns: the 15 line bytes. Error case: none.
pub fn proxy_v1_encode_unknown() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_v1_prefix(&mut out);
  _push_str(&mut out, "UNKNOWN");
  _push_crlf(&mut out);
  return out;
}

// Append "PROXY ".
fn _push_v1_prefix(out: &mut Vec[UInt8]) {
  _push_str(out, "PROXY ");
}

// Append CR LF.
fn _push_crlf(out: &mut Vec[UInt8]) {
  out.push(13 as UInt8);
  out.push(10 as UInt8);
}

// Append every byte of the ASCII Str s.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(((string.byte_at(s, i) as Int) & 0xFF) as UInt8);
    i = i + 1;
  }
}

/// Encode "PROXY UNKNOWN <tail>\r\n" with an opaque tail. The tail must not
/// contain CR or LF, and the whole line must stay within the 107-byte cap
/// (tail at most 91 bytes). Params: tail - opaque bytes (may be empty).
/// Returns: the line bytes. Error case: Err("proxy: bad opaque tail") or
/// Err("proxy: v1 line too long").
pub fn proxy_v1_encode_unknown_opaque(tail: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var i = 0;
  while i < tail.len() {
    let c = _byte(tail, i);
    if c == _PX_CR || c == _PX_LF {
      return _err_bytes("proxy: bad opaque tail");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_v1_prefix(&mut out);
  _push_str(&mut out, "UNKNOWN ");
  _push_vec(&mut out, tail);
  _push_crlf(&mut out);
  if out.len() > _PX_V1_MAX_LINE {
    return _err_bytes("proxy: v1 line too long");
  }
  return _ok_bytes(out);
}

/// Encode a v1 TCP4 line. Addresses must be canonical dotted quads and ports
/// must be 0..65535. Params: src/dst - IPv4 text; sport/dport - ports.
/// Returns: the line bytes. Error case: Err("proxy: bad ipv4") or
/// Err("proxy: bad port").
pub fn proxy_v1_encode_tcp4(src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int) -> Result[Vec[UInt8], Str] {
  let sr = proxy_ipv4_parse(src);
  if !sr.is_ok {
    return _err_bytes(sr.error);
  }
  let dr = proxy_ipv4_parse(dst);
  if !dr.is_ok {
    return _err_bytes(dr.error);
  }
  if !_port_ok(sport) || !_port_ok(dport) {
    return _err_bytes("proxy: bad port");
  }
  let sb: Vec[UInt8] = sr.value;
  let db: Vec[UInt8] = dr.value;
  let srr = proxy_ipv4_render(&sb);
  let drr = proxy_ipv4_render(&db);
  if !srr.is_ok || !drr.is_ok {
    return _err_bytes("proxy: bad ipv4");
  }
  let sv: Vec[UInt8] = srr.value;
  let dv: Vec[UInt8] = drr.value;
  var out = Vec[UInt8].new();
  _push_v1_prefix(&mut out);
  _push_str(&mut out, "TCP4 ");
  _push_vec(&mut out, &sv);
  _push_space(&mut out);
  _push_vec(&mut out, &dv);
  _push_space(&mut out);
  _push_dec(&mut out, sport);
  _push_space(&mut out);
  _push_dec(&mut out, dport);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

// True when p is a legal port number.
fn _port_ok(p: Int) -> Bool {
  return p >= 0 && p <= _PX_U16_MAX;
}

// Append one ASCII space.
fn _push_space(out: &mut Vec[UInt8]) {
  out.push(32 as UInt8);
}

// Append the decimal text of a non-negative Int.
fn _push_dec(out: &mut Vec[UInt8], v: Int) {
  builder.sb_push_int(out, v);
}

/// Encode a v1 TCP6 line. Addresses are parsed and re-rendered canonically
/// (lowercase, longest zero run compressed). Params: src/dst - IPv6 text;
/// sport/dport - ports. Returns: the line bytes. Error case:
/// Err("proxy: bad ipv6") or Err("proxy: bad port").
pub fn proxy_v1_encode_tcp6(src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int) -> Result[Vec[UInt8], Str] {
  let sr = proxy_ipv6_parse(src);
  if !sr.is_ok {
    return _err_bytes(sr.error);
  }
  let dr = proxy_ipv6_parse(dst);
  if !dr.is_ok {
    return _err_bytes(dr.error);
  }
  if !_port_ok(sport) || !_port_ok(dport) {
    return _err_bytes("proxy: bad port");
  }
  let sb: Vec[UInt8] = sr.value;
  let db: Vec[UInt8] = dr.value;
  let srr = proxy_ipv6_render(&sb);
  let drr = proxy_ipv6_render(&db);
  if !srr.is_ok || !drr.is_ok {
    return _err_bytes("proxy: bad ipv6");
  }
  let sv: Vec[UInt8] = srr.value;
  let dv: Vec[UInt8] = drr.value;
  var out = Vec[UInt8].new();
  _push_v1_prefix(&mut out);
  _push_str(&mut out, "TCP6 ");
  _push_vec(&mut out, &sv);
  _push_space(&mut out);
  _push_vec(&mut out, &dv);
  _push_space(&mut out);
  _push_dec(&mut out, sport);
  _push_space(&mut out);
  _push_dec(&mut out, dport);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  v1 line parse
// --------------------------------------------------

/// Parse one v1 header line starting at `off`. The line must start with
/// "PROXY ", end with CRLF inside the 107-byte cap, and carry either TCP4/
/// TCP6 with both addresses and both ports or UNKNOWN with an arbitrary
/// opaque tail. Params: data - the buffer; off - header start. Returns:
/// the decoded ProxyV1 with `consumed` = line bytes. Error cases:
/// Err("proxy: bad v1 prefix at <off>"), Err("proxy: v1 line too long at
/// <off>"), Err("proxy: truncated header at <off>"), Err("proxy: bad v1
/// fields at <off>"), Err("proxy: bad v1 protocol at <off>"),
/// Err("proxy: bad v1 address at <off>"), Err("proxy: bad decimal at <off>").
/// Complexity: O(line length).
pub fn proxy_parse_v1(data: &Vec[UInt8], off: Int) -> Result[ProxyV1, Str] {
  if off < 0 {
    return _err_v1(_at("proxy: negative offset", off));
  }
  let total = data.len();
  if off >= total {
    return _err_v1(_at("proxy: truncated header", off));
  }
  var lim: Int = total;
  if off + _PX_V1_MAX_LINE < lim {
    lim = off + _PX_V1_MAX_LINE;
  }
  let cr = _find_crlf(data, off, lim);
  if cr < 0 {
    if lim - off >= _PX_V1_MAX_LINE {
      return _err_v1(_at("proxy: v1 line too long", off));
    }
    return _err_v1(_at("proxy: truncated header", off));
  }
  if cr + 2 - off > _PX_V1_MAX_LINE {
    return _err_v1(_at("proxy: v1 line too long", off));
  }
  let consumed = cr + 2 - off;
  if !_span_eq_lit(data, off, off + 6, "PROXY ") {
    return _err_v1(_at("proxy: bad v1 prefix", off));
  }
  let t0s = off + 6;
  let sp = _find_byte(data, t0s, cr, _PX_SPACE);
  var t0e = cr;
  if sp >= 0 {
    t0e = sp;
  }
  if t0e <= t0s {
    return _err_v1(_at("proxy: bad v1 protocol", t0s));
  }
  if _span_eq_lit(data, t0s, t0e, "UNKNOWN") {
    var opaque = Vec[UInt8].new();
    if t0e < cr {
      _copy_span(data, t0e + 1, cr, &mut opaque);
    }
    return _ok_v1(_v1_make(_PX_V1_UNKNOWN, Vec[UInt8].new(), Vec[UInt8].new(), 0, 0, opaque, consumed));
  }
  let is4 = _span_eq_lit(data, t0s, t0e, "TCP4");
  let is6 = _span_eq_lit(data, t0s, t0e, "TCP6");
  if !is4 && !is6 {
    return _err_v1(_at("proxy: bad v1 protocol", t0s));
  }
  var spans = Vec[Int].new();
  if !_split_tokens(data, t0e + 1, cr, &mut spans) {
    return _err_v1(_at("proxy: bad v1 fields", t0e + 1));
  }
  if spans.len() != 8 {
    return _err_v1(_at("proxy: bad v1 fields", t0e + 1));
  }
  let s1: Int = spans[0];
  let e1: Int = spans[1];
  let s2: Int = spans[2];
  let e2: Int = spans[3];
  let s3: Int = spans[4];
  let e3: Int = spans[5];
  let s4: Int = spans[6];
  let e4: Int = spans[7];
  if is4 {
    if !_ipv4_span_ok(data, s1, e1) {
      return _err_v1(_at("proxy: bad v1 address", s1));
    }
    if !_ipv4_span_ok(data, s2, e2) {
      return _err_v1(_at("proxy: bad v1 address", s2));
    }
  } else {
    if !_ipv6_span_ok(data, s1, e1) {
      return _err_v1(_at("proxy: bad v1 address", s1));
    }
    if !_ipv6_span_ok(data, s2, e2) {
      return _err_v1(_at("proxy: bad v1 address", s2));
    }
  }
  let p3 = _parse_dec(data, s3, e3, _PX_U16_MAX);
  if !p3.is_ok {
    return _err_v1(_at(p3.error, s3));
  }
  let p4 = _parse_dec(data, s4, e4, _PX_U16_MAX);
  if !p4.is_ok {
    return _err_v1(_at(p4.error, s4));
  }
  var src = Vec[UInt8].new();
  var dst = Vec[UInt8].new();
  _copy_span(data, s1, e1, &mut src);
  _copy_span(data, s2, e2, &mut dst);
  var fam = _PX_V1_TCP4;
  if is6 {
    fam = _PX_V1_TCP6;
  }
  let sport: Int = p3.value;
  let dport: Int = p4.value;
  return _ok_v1(_v1_make(fam, src, dst, sport, dport, Vec[UInt8].new(), consumed));
}

// --------------------------------------------------
//  v2 encode
// --------------------------------------------------

// Build a complete v2 header: signature + ver/cmd + fam/proto + u16 length +
// body. The body is not size-checked against the family.
fn _px_v2_header(command: Int, family: Int, protocol: Int, body: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if command != _PX_CMD_LOCAL && command != _PX_CMD_PROXY {
    return _err_bytes("proxy: bad command");
  }
  if family < 0 || family > 3 {
    return _err_bytes("proxy: bad family");
  }
  if protocol < 0 || protocol > 2 {
    return _err_bytes("proxy: bad protocol");
  }
  if body.len() > _PX_U16_MAX {
    return _err_bytes("proxy: body too long");
  }
  var out = Vec[UInt8].new();
  _push_magic_v2(&mut out);
  out.push(((32 + command) & 0xFF) as UInt8);
  out.push(((family * 16 + protocol) & 0xFF) as UInt8);
  _push_u16(&mut out, body.len());
  _push_vec(&mut out, body);
  return _ok_bytes(out);
}

/// Build a v2 header from raw body bytes. `command` must be LOCAL (0) or
/// PROXY (1); `family` 0..3; `protocol` 0..2; `body` at most the family block
/// plus TLVs (the caller is responsible for the family/body fit; the parsers
/// enforce it on receive). Params: command/family/protocol - header nibbles;
/// body - bytes after the 16-byte fixed header. Returns: the header bytes.
/// Error case: Err("proxy: bad command"), Err("proxy: bad family"),
/// Err("proxy: bad protocol"), Err("proxy: body too long").
pub fn proxy_v2_header(command: Int, family: Int, protocol: Int, body: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _px_v2_header(command, family, protocol, body);
}

// Build an INET (IPv4) address block: src(4) dst(4) sport(2) dport(2).
fn _px_v2_encode_inet4(protocol: Int, src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int, tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if src.len() != 4 || dst.len() != 4 {
    return _err_bytes("proxy: bad ipv4 bytes");
  }
  if !_port_ok(sport) || !_port_ok(dport) {
    return _err_bytes("proxy: bad port");
  }
  var body = Vec[UInt8].new();
  _push_vec(&mut body, src);
  _push_vec(&mut body, dst);
  _push_u16(&mut body, sport);
  _push_u16(&mut body, dport);
  _push_vec(&mut body, tlvs);
  return _px_v2_header(_PX_CMD_PROXY, _PX_FAM_INET, protocol, &body);
}

// Build an INET6 (IPv6) address block: src(16) dst(16) sport(2) dport(2).
fn _px_v2_encode_inet6(protocol: Int, src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int, tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if src.len() != 16 || dst.len() != 16 {
    return _err_bytes("proxy: bad ipv6 bytes");
  }
  if !_port_ok(sport) || !_port_ok(dport) {
    return _err_bytes("proxy: bad port");
  }
  var body = Vec[UInt8].new();
  _push_vec(&mut body, src);
  _push_vec(&mut body, dst);
  _push_u16(&mut body, sport);
  _push_u16(&mut body, dport);
  _push_vec(&mut body, tlvs);
  return _px_v2_header(_PX_CMD_PROXY, _PX_FAM_INET6, protocol, &body);
}

// Append one AF_UNIX path padded with NULs to exactly 108 bytes.
fn _push_unix_path(out: &mut Vec[UInt8], path: &Vec[UInt8]) {
  _push_vec(out, path);
  var i = path.len();
  while i < 108 {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

/// Encode a v2 PROXY header with an INET/STREAM (TCP over IPv4) address
/// block. Params: src/dst - 4 packed bytes each; sport/dport - ports 0..65535;
/// tlvs - optional raw TLV stream (may be empty). Returns: the header bytes.
/// Error case: Err("proxy: bad ipv4 bytes"), Err("proxy: bad port"),
/// Err("proxy: body too long").
pub fn proxy_v2_encode_proxy_tcp4(src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int, tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _px_v2_encode_inet4(_PX_PROTO_STREAM, src, dst, sport, dport, tlvs);
}

/// Encode a v2 PROXY header with an INET/DGRAM (UDP over IPv4) address
/// block. Same contract as proxy_v2_encode_proxy_tcp4.
pub fn proxy_v2_encode_proxy_udp4(src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int, tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _px_v2_encode_inet4(_PX_PROTO_DGRAM, src, dst, sport, dport, tlvs);
}

/// Encode a v2 PROXY header with an INET6/STREAM (TCP over IPv6) address
/// block. Params: src/dst - 16 packed bytes each; sport/dport - ports
/// 0..65535; tlvs - optional raw TLV stream. Returns: the header bytes.
/// Error case: Err("proxy: bad ipv6 bytes"), Err("proxy: bad port"),
/// Err("proxy: body too long").
pub fn proxy_v2_encode_proxy_tcp6(src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int, tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _px_v2_encode_inet6(_PX_PROTO_STREAM, src, dst, sport, dport, tlvs);
}

/// Encode a v2 PROXY header with an INET6/DGRAM (UDP over IPv6) address
/// block. Same contract as proxy_v2_encode_proxy_tcp6.
pub fn proxy_v2_encode_proxy_udp6(src: &Vec[UInt8], dst: &Vec[UInt8], sport: Int, dport: Int, tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _px_v2_encode_inet6(_PX_PROTO_DGRAM, src, dst, sport, dport, tlvs);
}

/// Encode a v2 PROXY header with an AF_UNIX/STREAM address block: two 108-byte
/// NUL-padded path fields. Params: src_path/dst_path - at most 108 bytes each;
/// tlvs - optional raw TLV stream. Returns: the header bytes.
/// Error case: Err("proxy: unix path too long"), Err("proxy: body too long").
pub fn proxy_v2_encode_proxy_unix(src_path: &Vec[UInt8], dst_path: &Vec[UInt8], tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if src_path.len() > 108 || dst_path.len() > 108 {
    return _err_bytes("proxy: unix path too long");
  }
  var body = Vec[UInt8].new();
  _push_unix_path(&mut body, src_path);
  _push_unix_path(&mut body, dst_path);
  _push_vec(&mut body, tlvs);
  return _px_v2_header(_PX_CMD_PROXY, _PX_FAM_UNIX, _PX_PROTO_STREAM, &body);
}

/// Encode a v2 LOCAL header (command LOCAL, family/protocol UNSPEC) carrying
/// an optional TLV stream. The receiver keeps the real connection endpoints
/// and must not trust the fields. Params: tlvs - raw TLV stream (may be
/// empty). Returns: the header bytes. Error case: Err("proxy: body too
/// long").
pub fn proxy_v2_encode_local(tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _px_v2_header(_PX_CMD_LOCAL, _PX_FAM_UNSPEC, _PX_PROTO_UNSPEC, tlvs);
}

/// Encode a v2 PROXY header with an UNSPEC address block and an optional TLV
/// stream. Params: tlvs - raw TLV stream (may be empty). Returns: the header
/// bytes. Error case: Err("proxy: body too long").
pub fn proxy_v2_encode_proxy_unspec(tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _px_v2_header(_PX_CMD_PROXY, _PX_FAM_UNSPEC, _PX_PROTO_UNSPEC, tlvs);
}

// --------------------------------------------------
//  v2 parse
// --------------------------------------------------

// Fresh ProxyV2 with every field empty/zero.
fn _empty_v2(command: Int, family: Int, protocol: Int, consumed: Int) -> ProxyV2 {
  return ProxyV2{
    version: _PX_VERSION_2;
    command: command;
    family: family;
    protocol: protocol;
    src_addr: Vec[UInt8].new();
    dst_addr: Vec[UInt8].new();
    src_port: 0;
    dst_port: 0;
    unix_src: Vec[UInt8].new();
    unix_dst: Vec[UInt8].new();
    tlvs: Vec[UInt8].new();
    payload: Vec[UInt8].new();
    tlvs_off: 0;
    consumed: consumed;
  };
}

/// Parse one v2 header starting at `off`. The fixed 16 bytes must be present;
/// the announced length must fit the buffer, the version nibble must be 2,
/// the command LOCAL/PROXY, the family 0..3, the protocol 0..2, and a PROXY
/// command must announce at least its family's address block. Address bytes
/// are copied packed (network order); the TLV stream is copied raw. Params:
/// data - the buffer; off - header start. Returns: the decoded ProxyV2 with
/// `consumed` = 16 + length. Error cases: Err("proxy: truncated header at
/// <off>"), Err("proxy: bad signature at <off>"), Err("proxy: bad version at
/// <off>"), Err("proxy: bad command at <off>"), Err("proxy: bad family at
/// <off>"), Err("proxy: bad protocol at <off>"), Err("proxy: bad address
/// block at <off>"). Complexity: O(header size).
pub fn proxy_parse_v2(data: &Vec[UInt8], off: Int) -> Result[ProxyV2, Str] {
  if off < 0 {
    return _err_v2(_at("proxy: negative offset", off));
  }
  let total = data.len();
  if off >= total {
    return _err_v2(_at("proxy: truncated header", off));
  }
  if total - off < _PX_V2_FIXED {
    return _err_v2(_at("proxy: truncated header", off));
  }
  var i = 0;
  while i < 12 {
    if _byte(data, off + i) != _sig_byte(i) {
      return _err_v2(_at("proxy: bad signature", off + i));
    }
    i = i + 1;
  }
  let ver_cmd = _byte(data, off + 12);
  let version = ver_cmd / 16;
  let command = ver_cmd % 16;
  if version != _PX_VERSION_2 {
    return _err_v2(_at("proxy: bad version", off + 12));
  }
  if command != _PX_CMD_LOCAL && command != _PX_CMD_PROXY {
    return _err_v2(_at("proxy: bad command", off + 12));
  }
  let fam_prot = _byte(data, off + 13);
  let family = fam_prot / 16;
  let protocol = fam_prot % 16;
  if family > 3 {
    return _err_v2(_at("proxy: bad family", off + 13));
  }
  if protocol > 2 {
    return _err_v2(_at("proxy: bad protocol", off + 13));
  }
  let length = _read_u16(data, off + 14);
  if total - off < _PX_V2_FIXED + length {
    return _err_v2(_at("proxy: truncated header", off));
  }
  let payload_off = off + _PX_V2_FIXED;
  let need = proxy_v2_address_block_len(family);
  if command == _PX_CMD_PROXY && length < need {
    return _err_v2(_at("proxy: bad address block", off + 14));
  }
  var op = _empty_v2(command, family, protocol, _PX_V2_FIXED + length);
  var payload = Vec[UInt8].new();
  _copy_span(data, payload_off, payload_off + length, &mut payload);
  op.payload = payload;
  if length >= need {
    if family == _PX_FAM_INET {
      var src = Vec[UInt8].new();
      var dst = Vec[UInt8].new();
      _copy_span(data, payload_off, payload_off + 4, &mut src);
      _copy_span(data, payload_off + 4, payload_off + 8, &mut dst);
      op.src_addr = src;
      op.dst_addr = dst;
      op.src_port = _read_u16(data, payload_off + 8);
      op.dst_port = _read_u16(data, payload_off + 10);
    }
    if family == _PX_FAM_INET6 {
      var src = Vec[UInt8].new();
      var dst = Vec[UInt8].new();
      _copy_span(data, payload_off, payload_off + 16, &mut src);
      _copy_span(data, payload_off + 16, payload_off + 32, &mut dst);
      op.src_addr = src;
      op.dst_addr = dst;
      op.src_port = _read_u16(data, payload_off + 32);
      op.dst_port = _read_u16(data, payload_off + 34);
    }
    if family == _PX_FAM_UNIX {
      var us = Vec[UInt8].new();
      var ud = Vec[UInt8].new();
      _copy_span(data, payload_off, payload_off + 108, &mut us);
      _copy_span(data, payload_off + 108, payload_off + 216, &mut ud);
      op.unix_src = us;
      op.unix_dst = ud;
    }
    var tlvs = Vec[UInt8].new();
    _copy_span(data, payload_off + need, payload_off + length, &mut tlvs);
    op.tlvs = tlvs;
    op.tlvs_off = payload_off + need;
  } else {
    op.tlvs_off = payload_off;
  }
  return _ok_v2(op);
}

// --------------------------------------------------
//  One-header helpers
// --------------------------------------------------

/// Frame one header without decoding its fields: for a v1 line it validates
/// "PROXY " and locates CRLF inside the 107-byte cap; for a v2 header it
/// validates the signature, version, command, family, protocol and reads the
/// length (the rest of the header need not be buffered yet). Params: data -
/// the buffer; off - header start. Returns: Ok((version, consumed)) where
/// consumed is the total header size in bytes. Error cases: Err("proxy:
/// negative offset at <off>"), Err("proxy: truncated header at <off>"),
/// Err("proxy: v1 line too long at <off>"), Err("proxy: bad version at
/// <off>"), Err("proxy: bad command at <off>"), Err("proxy: bad family at
/// <off>"), Err("proxy: bad protocol at <off>"), Err("proxy: unknown version
/// at <off>"). Complexity: O(1) for v2, O(line) for v1.
pub fn proxy_header_len(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  if off < 0 {
    return _err_pair(_at("proxy: negative offset", off));
  }
  let v = proxy_detect_version(data, off);
  if v == _PX_VERSION_2 {
    if data.len() - off < _PX_V2_FIXED {
      return _err_pair(_at("proxy: truncated header", off));
    }
    let ver_cmd = _byte(data, off + 12);
    if ver_cmd / 16 != _PX_VERSION_2 {
      return _err_pair(_at("proxy: bad version", off + 12));
    }
    let command = ver_cmd % 16;
    if command != _PX_CMD_LOCAL && command != _PX_CMD_PROXY {
      return _err_pair(_at("proxy: bad command", off + 12));
    }
    let fam_prot = _byte(data, off + 13);
    if fam_prot / 16 > 3 {
      return _err_pair(_at("proxy: bad family", off + 13));
    }
    if fam_prot % 16 > 2 {
      return _err_pair(_at("proxy: bad protocol", off + 13));
    }
    let length = _read_u16(data, off + 14);
    return _ok_pair((_PX_VERSION_2, _PX_V2_FIXED + length));
  }
  if v == _PX_VERSION_1 {
    let total = data.len();
    var lim: Int = total;
    if off + _PX_V1_MAX_LINE < lim {
      lim = off + _PX_V1_MAX_LINE;
    }
    let cr = _find_crlf(data, off, lim);
    if cr < 0 {
      if lim - off >= _PX_V1_MAX_LINE {
        return _err_pair(_at("proxy: v1 line too long", off));
      }
      return _err_pair(_at("proxy: truncated header", off));
    }
    if cr + 2 - off > _PX_V1_MAX_LINE {
      return _err_pair(_at("proxy: v1 line too long", off));
    }
    return _ok_pair((_PX_VERSION_1, cr + 2 - off));
  }
  let avail = data.len() - off;
  if avail <= 0 {
    return _err_pair(_at("proxy: truncated header", off));
  }
  if avail < 12 && _prefix_of_magic(data, off, avail) {
    return _err_pair(_at("proxy: truncated header", off));
  }
  return _err_pair(_at("proxy: unknown version", off));
}

/// Parse exactly one header of either version and summarize it. Params:
/// data - the buffer; off - header start. Returns: Ok(summary) with
/// `consumed` = header bytes and family/protocol in v2 ids (v1 TCP4/TCP6 map
/// to INET/INET6 + STREAM, UNKNOWN to UNSPEC/UNSPEC). Error cases: any
/// proxy_parse_v1/proxy_parse_v2 error, or Err("proxy: unknown version at
/// <off>") when neither signature matches. Complexity: O(header size).
pub fn proxy_parse_one(data: &Vec[UInt8], off: Int) -> Result[ProxySummary, Str] {
  let v = proxy_detect_version(data, off);
  if v == _PX_VERSION_1 {
    let r = proxy_parse_v1(data, off);
    if !r.is_ok {
      return _err_sum(r.error);
    }
    let op: ProxyV1 = r.value;
    var family = _PX_FAM_UNSPEC;
    var protocol = _PX_PROTO_UNSPEC;
    if op.family == _PX_V1_TCP4 {
      family = _PX_FAM_INET;
      protocol = _PX_PROTO_STREAM;
    }
    if op.family == _PX_V1_TCP6 {
      family = _PX_FAM_INET6;
      protocol = _PX_PROTO_STREAM;
    }
    return _ok_sum(ProxySummary{
      version: _PX_VERSION_1;
      command: _PX_CMD_PROXY;
      family: family;
      protocol: protocol;
      src_port: op.src_port;
      dst_port: op.dst_port;
      consumed: op.consumed;
    });
  }
  if v == _PX_VERSION_2 {
    let r = proxy_parse_v2(data, off);
    if !r.is_ok {
      return _err_sum(r.error);
    }
    let op: ProxyV2 = r.value;
    return _ok_sum(ProxySummary{
      version: _PX_VERSION_2;
      command: op.command;
      family: op.family;
      protocol: op.protocol;
      src_port: op.src_port;
      dst_port: op.dst_port;
      consumed: op.consumed;
    });
  }
  let hl = proxy_header_len(data, off);
  if hl.is_ok {
    return _err_sum(_at("proxy: unknown version", off));
  }
  return _err_sum(hl.error);
}

/// Span of the bytes following one header in the buffer: (off + consumed,
/// data.len()). An empty span (start == end) means no payload follows.
/// Params: data - the buffer; off - header start; consumed - header size
/// (from a parse or proxy_header_len). Returns: the payload span.
/// Error case: Err("proxy: bad header size at <off>") when the range is
/// negative or runs past the buffer.
pub fn proxy_payload_span(data: &Vec[UInt8], off: Int, consumed: Int) -> Result[(Int, Int), Str] {
  if off < 0 || consumed < 0 {
    return _err_pair(_at("proxy: bad header size", off));
  }
  if off > data.len() || data.len() - off < consumed {
    return _err_pair(_at("proxy: bad header size", off));
  }
  return _ok_pair((off + consumed, data.len()));
}

// --------------------------------------------------
//  TLV codec (type u8 + big-endian u16 length + value)
// --------------------------------------------------

/// Encode one TLV. Params: t - type byte 0..255; value - raw value bytes
/// (0..65535). Returns: type + u16 length + value. Error case: Err("proxy:
/// bad TLV type"), Err("proxy: TLV too long").
pub fn proxy_tlv_encode(t: Int, value: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if t < 0 || t > 255 {
    return _err_bytes("proxy: bad TLV type");
  }
  if value.len() > _PX_U16_MAX {
    return _err_bytes("proxy: TLV too long");
  }
  var out = Vec[UInt8].new();
  out.push((t & 0xFF) as UInt8);
  _push_u16(&mut out, value.len());
  _push_vec(&mut out, value);
  return _ok_bytes(out);
}

/// Encode a zero-length TLV. Params: t - type byte. Returns: the 3 bytes.
/// Error case: Err("proxy: bad TLV type").
pub fn proxy_tlv_encode_empty(t: Int) -> Result[Vec[UInt8], Str] {
  var empty = Vec[UInt8].new();
  return proxy_tlv_encode(t, &empty);
}

/// Encode a u16-valued TLV (big-endian). Params: t - type; v - 0..65535.
/// Returns: the TLV bytes. Error case: Err("proxy: bad TLV value").
pub fn proxy_tlv_encode_u16(t: Int, v: Int) -> Result[Vec[UInt8], Str] {
  if v < 0 || v > _PX_U16_MAX {
    return _err_bytes("proxy: bad TLV value");
  }
  var body = Vec[UInt8].new();
  _push_u16(&mut body, v);
  return proxy_tlv_encode(t, &body);
}

/// Encode a u32-valued TLV (big-endian). Params: t - type; v - 0..4294967295.
/// Returns: the TLV bytes. Error case: Err("proxy: bad TLV value").
pub fn proxy_tlv_encode_u32(t: Int, v: Int) -> Result[Vec[UInt8], Str] {
  if v < 0 || v > _PX_U32_MAX {
    return _err_bytes("proxy: bad TLV value");
  }
  var body = Vec[UInt8].new();
  _push_u32(&mut body, v);
  return proxy_tlv_encode(t, &body);
}

/// Encode a u64-valued TLV from its two u32 halves (hi first, big-endian).
/// Params: t - type; hi/lo - 0..4294967295 each. Returns: the TLV bytes.
/// Error case: Err("proxy: bad TLV value").
pub fn proxy_tlv_encode_u64(t: Int, hi: Int, lo: Int) -> Result[Vec[UInt8], Str] {
  if hi < 0 || hi > _PX_U32_MAX || lo < 0 || lo > _PX_U32_MAX {
    return _err_bytes("proxy: bad TLV value");
  }
  var body = Vec[UInt8].new();
  _push_u64_parts(&mut body, hi, lo);
  return proxy_tlv_encode(t, &body);
}

/// Decode a 2-byte big-endian TLV value. Params: value - exactly 2 bytes.
/// Returns: the u16. Error case: Err("proxy: bad TLV value length").
pub fn proxy_tlv_read_u16(value: &Vec[UInt8]) -> Result[Int, Str] {
  if value.len() != 2 {
    return _err_int("proxy: bad TLV value length");
  }
  return _ok_int(_read_u16(value, 0));
}

/// Decode a 4-byte big-endian TLV value. Params: value - exactly 4 bytes.
/// Returns: the u32. Error case: Err("proxy: bad TLV value length").
pub fn proxy_tlv_read_u32(value: &Vec[UInt8]) -> Result[Int, Str] {
  if value.len() != 4 {
    return _err_int("proxy: bad TLV value length");
  }
  return _ok_int(_read_u32(value, 0));
}

/// Decode an 8-byte big-endian TLV value as two u32 halves (hi first).
/// Params: value - exactly 8 bytes. Returns: (hi, lo).
/// Error case: Err("proxy: bad TLV value length").
pub fn proxy_tlv_read_u64_parts(value: &Vec[UInt8]) -> Result[(Int, Int), Str] {
  if value.len() != 8 {
    return _err_pair("proxy: bad TLV value length");
  }
  let hi = _read_u32(value, 0);
  let lo = _read_u32(value, 4);
  return _ok_pair((hi, lo));
}

/// Decode an 8-byte big-endian TLV value as one Int. Values with the top bit
/// set cannot be represented; they are Err("proxy: u64 out of range") --
/// use proxy_tlv_read_u64_parts for the full range. Params: value - exactly
/// 8 bytes. Returns: the value when below 2^63.
/// Error case: Err("proxy: bad TLV value length"), Err("proxy: u64 out of
/// range").
pub fn proxy_tlv_read_u64(value: &Vec[UInt8]) -> Result[Int, Str] {
  let p = proxy_tlv_read_u64_parts(value);
  if !p.is_ok {
    return _err_int(p.error);
  }
  let pair: (Int, Int) = p.value;
  let hi: Int = pair.0;
  let lo: Int = pair.1;
  if hi > _PX_INT31_MAX {
    return _err_int("proxy: u64 out of range");
  }
  return _ok_int(hi * 4294967296 + lo);
}

/// Name of a registered TLV type id: "ALPN", "AUTHORITY", "CRC32C", "NOOP",
/// "UNIQUE_ID", "SSL", "NETNS", "AWS", "UNKNOWN". Params: t - TLV type.
/// Returns: the name. Error case: none.
pub fn proxy_tlv_type_name(t: Int) -> Str {
  if t == _PX_TLV_ALPN { return "ALPN"; }
  if t == _PX_TLV_AUTHORITY { return "AUTHORITY"; }
  if t == _PX_TLV_CRC32C { return "CRC32C"; }
  if t == _PX_TLV_NOOP { return "NOOP"; }
  if t == _PX_TLV_UNIQUE_ID { return "UNIQUE_ID"; }
  if t == _PX_TLV_SSL { return "SSL"; }
  if t == _PX_TLV_NETNS { return "NETNS"; }
  if t == _PX_TLV_AWS { return "AWS"; }
  return "UNKNOWN";
}

/// Expected value width in bytes for a known fixed-width TLV type: CRC32C 4;
/// 0 means variable/structured. Params: t - TLV type. Returns: the width or
/// 0. Error case: none.
pub fn proxy_tlv_expected_width(t: Int) -> Int {
  if t == _PX_TLV_CRC32C { return 4; }
  return 0;
}

// Locate one TLV in data[off, end). All offsets are absolute to `data`.
fn _tlv_next(data: &Vec[UInt8], off: Int, end: Int) -> Result[ProxyTlvCursor, Str] {
  if off < 0 || off > end || end > data.len() {
    return _err_tlv(_at("proxy: bad TLV", off));
  }
  if end - off < 3 {
    return _err_tlv(_at("proxy: truncated TLV", off));
  }
  let t = _byte(data, off);
  let vl = _read_u16(data, off + 1);
  if end - (off + 3) < vl {
    return _err_tlv(_at("proxy: TLV length overrun", off));
  }
  return _ok_tlv(ProxyTlvCursor{
    tlv_type: t;
    value_start: off + 3;
    value_end: off + 3 + vl;
    next: off + 3 + vl;
  });
}

/// Locate the TLV at `off` inside a standalone TLV stream (offsets relative
/// to `tlvs`). Params: tlvs - the stream; off - TLV start. Returns: the
/// cursor with value span and next offset. Error cases: Err("proxy: bad TLV
/// at <off>"), Err("proxy: truncated TLV at <off>"), Err("proxy: TLV length
/// overrun at <off>").
pub fn proxy_tlv_next(tlvs: &Vec[UInt8], off: Int) -> Result[ProxyTlvCursor, Str] {
  return _tlv_next(tlvs, off, tlvs.len());
}

/// Locate the TLV at absolute offset `off` inside data[off, end); same
/// contract as proxy_tlv_next with an explicit end (for walking TLVs that
/// live inside a larger header buffer). Params: data - the buffer; off -
/// TLV start; end - one past the last TLV byte. Returns: the cursor.
/// Error cases: as proxy_tlv_next.
pub fn proxy_tlv_next_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[ProxyTlvCursor, Str] {
  return _tlv_next(data, off, end);
}

/// Number of TLVs that parse cleanly from the start of a TLV stream; stops at
/// the first malformed TLV. Params: tlvs - the stream. Returns: the count
/// (>= 0). Error case: none.
pub fn proxy_tlv_count(tlvs: &Vec[UInt8]) -> Int {
  var n = 0;
  var off = 0;
  while off < tlvs.len() {
    let r = _tlv_next(tlvs, off, tlvs.len());
    if !r.is_ok {
      return n;
    }
    let c: ProxyTlvCursor = r.value;
    n = n + 1;
    off = c.next;
  }
  return n;
}

/// Offset of the first TLV of type `want` in a standalone TLV stream, or -1.
/// Params: tlvs - the stream; want - type id. Returns: the offset or -1.
/// Error case: none.
pub fn proxy_tlv_first(tlvs: &Vec[UInt8], want: Int) -> Int {
  var off = 0;
  while off < tlvs.len() {
    let r = _tlv_next(tlvs, off, tlvs.len());
    if !r.is_ok {
      return -1;
    }
    let c: ProxyTlvCursor = r.value;
    if c.tlv_type == want {
      return off;
    }
    off = c.next;
  }
  return -1;
}

// --------------------------------------------------
//  SSL TLV (nested TLV stream)
// --------------------------------------------------

/// Span of the nested TLVs inside an SSL TLV value: the value starts with a
/// 1-byte client flag field and a 4-byte big-endian verify field, so the
/// sub-TLV stream starts at offset 5. Params: value - SSL TLV value bytes.
/// Returns: (5, value.len()). Error case: Err("proxy: bad ssl tlv") when the
/// value is shorter than the 5 fixed bytes.
pub fn proxy_ssl_sub_tlvs(value: &Vec[UInt8]) -> Result[(Int, Int), Str] {
  if value.len() < 5 {
    return _err_pair("proxy: bad ssl tlv");
  }
  return _ok_pair((5, value.len()));
}

/// Client flag byte of an SSL TLV value (bit 0 SSL, bit 1 cert on this
/// connection, bit 2 cert on this session). Params: value - SSL TLV value.
/// Returns: 0..255. Error case: Err("proxy: bad ssl tlv").
pub fn proxy_ssl_client_flags(value: &Vec[UInt8]) -> Result[Int, Str] {
  if value.len() < 5 {
    return _err_int("proxy: bad ssl tlv");
  }
  return _ok_int(_byte(value, 0));
}

/// Verify result (big-endian u32) of an SSL TLV value: zero means the client
/// certificate verified. Params: value - SSL TLV value. Returns: the value.
/// Error case: Err("proxy: bad ssl tlv").
pub fn proxy_ssl_verify(value: &Vec[UInt8]) -> Result[Int, Str] {
  if value.len() < 5 {
    return _err_int("proxy: bad ssl tlv");
  }
  return _ok_int(_read_u32(value, 1));
}

/// Name of an SSL sub-TLV type: "VERSION", "CN", "CIPHER", "SIG_ALG",
/// "KEY_ALG", "UNKNOWN". Params: t - sub-TLV type. Returns: the name.
/// Error case: none.
pub fn proxy_ssl_subtype_name(t: Int) -> Str {
  if t == _PX_SSL_VERSION { return "VERSION"; }
  if t == _PX_SSL_CN { return "CN"; }
  if t == _PX_SSL_CIPHER { return "CIPHER"; }
  if t == _PX_SSL_SIG_ALG { return "SIG_ALG"; }
  if t == _PX_SSL_KEY_ALG { return "KEY_ALG"; }
  return "UNKNOWN";
}

/// Encode an SSL TLV (type 0x20): u8 client flags + u32 verify + nested TLV
/// stream. Params: flags - 0..255; verify - 0..4294967295; sub_tlvs - raw
/// nested TLV stream (may be empty). Returns: the TLV bytes. Error case:
/// Err("proxy: bad ssl tlv"), Err("proxy: ssl too long").
pub fn proxy_ssl_encode(flags: Int, verify: Int, sub_tlvs: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if flags < 0 || flags > 255 {
    return _err_bytes("proxy: bad ssl tlv");
  }
  if verify < 0 || verify > _PX_U32_MAX {
    return _err_bytes("proxy: bad ssl tlv");
  }
  if sub_tlvs.len() > _PX_U16_MAX - 5 {
    return _err_bytes("proxy: ssl too long");
  }
  var body = Vec[UInt8].new();
  body.push((flags & 0xFF) as UInt8);
  _push_u32(&mut body, verify);
  _push_vec(&mut body, sub_tlvs);
  return proxy_tlv_encode(_PX_TLV_SSL, &body);
}

// --------------------------------------------------
//  NETNS TLV (0x30, NUL-terminated namespace path)
// --------------------------------------------------

/// Encode a NETNS TLV (type 0x30): the namespace path bytes followed by one
/// NUL terminator. Params: path - US-ASCII path bytes (0..65534). Returns:
/// the TLV bytes. Error case: Err("proxy: TLV too long") when the path plus
/// terminator cannot fit a TLV value.
pub fn proxy_tlv_encode_netns(path: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if path.len() > _PX_U16_MAX - 1 {
    return _err_bytes("proxy: TLV too long");
  }
  var body = Vec[UInt8].new();
  _push_vec(&mut body, path);
  body.push(0 as UInt8);
  return proxy_tlv_encode(_PX_TLV_NETNS, &body);
}

/// Decode a NETNS TLV value: the namespace path is NUL-terminated, so this
/// returns the bytes before the first NUL (empty for a NUL-only value).
/// Params: value - NETNS TLV value bytes. Returns: the path without the
/// terminator. Error case: Err("proxy: bad netns") when there is no NUL.
pub fn proxy_tlv_netns_path(value: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var i = 0;
  while i < value.len() {
    if _byte(value, i) == 0 {
      var out = Vec[UInt8].new();
      _copy_span(value, 0, i, &mut out);
      return _ok_bytes(out);
    }
    i = i + 1;
  }
  return _err_bytes("proxy: bad netns");
}

// --------------------------------------------------
//  AWS TLV (0xEA, sub-TLV stream)
// --------------------------------------------------

/// Name of a documented AWS sub-TLV type: "VPC_ENDPOINT_ID" (0x01), "VPC_ID"
/// (0x02), "UNKNOWN". Params: t - sub-TLV type. Returns: the name.
/// Error case: none.
pub fn proxy_aws_subtype_name(t: Int) -> Str {
  if t == _PX_AWS_VPC_ENDPOINT { return "VPC_ENDPOINT_ID"; }
  if t == _PX_AWS_VPC { return "VPC_ID"; }
  return "UNKNOWN";
}

/// Copy the value of the first AWS sub-TLV of type `subtype` out of an AWS
/// TLV value (the value is a sub-TLV stream). Unknown sub-TLVs are skipped
/// and preserved in the raw value; malformed sub-TLV framing propagates the
/// walker error. Params: value - AWS TLV value bytes; subtype - sub-TLV type
/// id. Returns: the sub-TLV value bytes. Error cases: the
/// proxy_tlv_next error, or Err("proxy: aws subtype missing") when no
/// sub-TLV of that type is present.
pub fn proxy_aws_value(value: &Vec[UInt8], subtype: Int) -> Result[Vec[UInt8], Str] {
  var off = 0;
  while off < value.len() {
    let r = _tlv_next(value, off, value.len());
    if !r.is_ok {
      return _err_bytes(r.error);
    }
    let c: ProxyTlvCursor = r.value;
    if c.tlv_type == subtype {
      var out = Vec[UInt8].new();
      _copy_span(value, c.value_start, c.value_end, &mut out);
      return _ok_bytes(out);
    }
    off = c.next;
  }
  return _err_bytes("proxy: aws subtype missing");
}

/// VPC endpoint id from an AWS TLV value (sub-type 0x01). Params: value -
/// AWS TLV value bytes. Returns: the endpoint id bytes. Error case: as
/// proxy_aws_value.
pub fn proxy_aws_vpc_endpoint_id(value: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return proxy_aws_value(value, _PX_AWS_VPC_ENDPOINT);
}

/// VPC id from an AWS TLV value (sub-type 0x02). Params: value - AWS TLV
/// value bytes. Returns: the VPC id bytes. Error case: as proxy_aws_value.
pub fn proxy_aws_vpc_id(value: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return proxy_aws_value(value, _PX_AWS_VPC);
}

// --------------------------------------------------
//  CRC32C
// --------------------------------------------------

/// CRC-32C (Castagnoli, reflected, RFC 4960 appendix B) over data[from, to).
/// Params: data - the buffer; from/to - byte range. Returns: the 32-bit
/// checksum as an Int. Error case: Err("proxy: bad crc range").
/// Complexity: O(range length).
pub fn proxy_crc32c(data: &Vec[UInt8], from: Int, to: Int) -> Result[Int, Str] {
  if from < 0 || to < from || to > data.len() {
    return _err_int("proxy: bad crc range");
  }
  var crc: Int = _PX_U32_MAX;
  var i = from;
  while i < to {
    crc = crc ^ _byte(data, i);
    var k = 0;
    while k < 8 {
      if (crc % 2) == 1 {
        crc = crc / 2;
        crc = crc ^ _PX_CRC32C_POLY;
      } else {
        crc = crc / 2;
      }
      k = k + 1;
    }
    i = i + 1;
  }
  return _ok_int(crc ^ _PX_U32_MAX);
}

/// CRC-32C of a complete v2 header with the 4-byte checksum field at
/// `value_off` treated as zero, as required by PP2_TYPE_CRC32C. Params:
/// header - a complete v2 header (16 + length bytes or more); value_off -
/// absolute offset of the 4-byte CRC value inside it. Returns: the checksum.
/// Error case: Err("proxy: truncated header"), Err("proxy: bad crc offset").
pub fn proxy_v2_crc32c(header: &Vec[UInt8], value_off: Int) -> Result[Int, Str] {
  if header.len() < _PX_V2_FIXED {
    return _err_int("proxy: truncated header");
  }
  let length = _read_u16(header, 14);
  if header.len() < _PX_V2_FIXED + length {
    return _err_int("proxy: truncated header");
  }
  if value_off < 0 || _PX_V2_FIXED + length - value_off < 4 {
    return _err_int("proxy: bad crc offset");
  }
  var tmp = Vec[UInt8].new();
  var i = 0;
  while i < _PX_V2_FIXED + length {
    if i >= value_off && i < value_off + 4 {
      tmp.push(0 as UInt8);
    } else {
      tmp.push(header[i]);
    }
    i = i + 1;
  }
  return proxy_crc32c(&tmp, 0, tmp.len());
}

/// Check a v2 header against its CRC32C TLV, if present. Walks the TLV
/// stream (starting after the family block), computes the checksum with the
/// checksum field zeroed and compares. Params: header - a complete v2 header
/// buffer. Returns: Ok(true) when a 4-byte CRC32C TLV matches, Ok(false)
/// when no CRC32C TLV is present (or a LOCAL header has no interpretable TLV
/// stream). Error cases: Err("proxy: truncated header"), Err("proxy: bad
/// version"), Err("proxy: bad family"), Err("proxy: bad address block"), and
/// the proxy_tlv_next walk errors.
pub fn proxy_v2_verify_crc32c(header: &Vec[UInt8]) -> Result[Bool, Str] {
  if header.len() < _PX_V2_FIXED {
    return _err_bool("proxy: truncated header");
  }
  let length = _read_u16(header, 14);
  if header.len() < _PX_V2_FIXED + length {
    return _err_bool("proxy: truncated header");
  }
  let ver_cmd = _byte(header, 12);
  if ver_cmd / 16 != _PX_VERSION_2 {
    return _err_bool("proxy: bad version");
  }
  let command = ver_cmd % 16;
  let family = _byte(header, 13) / 16;
  let need = proxy_v2_address_block_len(family);
  if need < 0 {
    return _err_bool("proxy: bad family");
  }
  if length < need {
    if command == _PX_CMD_LOCAL {
      return _ok_bool(false);
    }
    return _err_bool("proxy: bad address block");
  }
  var off = _PX_V2_FIXED + need;
  let end = _PX_V2_FIXED + length;
  while off < end {
    let r = _tlv_next(header, off, end);
    if !r.is_ok {
      return _err_bool(r.error);
    }
    let c: ProxyTlvCursor = r.value;
    if c.tlv_type == _PX_TLV_CRC32C {
      if c.value_end - c.value_start != 4 {
        return _err_bool(_at("proxy: bad TLV value length", c.value_start));
      }
      let want = _read_u32(header, c.value_start);
      let got = proxy_v2_crc32c(header, c.value_start);
      if !got.is_ok {
        return _err_bool(got.error);
      }
      let gv: Int = got.value;
      return _ok_bool(gv == want);
    }
    off = c.next;
  }
  return _ok_bool(false);
}
