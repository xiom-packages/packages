// XIOM -- xiom.dns: DNS message wire codec (RFC 1035 subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets) encoder and decoder for DNS messages:
// the 12-byte header, domain names (labels, plus compression pointers on
// decode only), the question section, and resource records whose RDATA is
// A, AAAA, CNAME, MX or TXT. Builders never emit compression pointers, so
// every builder output is self-contained. See SPEC.md for the exact byte
// layout, the error catalog and the documented subset.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; nothing is a method and there are no lambdas.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * all big-endian packing/unpacking is arithmetic (division/modulo),
//     and every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before it enters Int arithmetic.
//   * Vec elements are read into typed locals before use; Str values are
//     assembled with xiom.string.builder (sb_push_str / sb_to_str) and are
//     never compared with `==` (BUG 17 discipline).
//   * the whole-message index is flat (parallel Vec[Int] fields) because
//     Vec[StructType] is unsupported in this compiler.
//   * at the ABI a Str is a NUL-terminated C string, so a label containing
//     a 0x00 byte cannot be represented: both directions reject it with
//     `dns: label contains NUL byte` (see SPEC.md).

module xiom.dns

use xiom.string;
use xiom.string.builder;

// Resource-record type codes covered by the RDATA helpers (RFC 1035 plus
// RFC 3596 for AAAA).
pub const DNS_TYPE_A: Int = 1;
pub const DNS_TYPE_CNAME: Int = 5;
pub const DNS_TYPE_MX: Int = 15;
pub const DNS_TYPE_TXT: Int = 16;
pub const DNS_TYPE_AAAA: Int = 28;

// The class used by the query builder: Internet (IN).
pub const DNS_CLASS_IN: Int = 1;

/// Parsed 12-byte DNS header. `id` is 0..65535; `qr`, `aa`, `tc`, `rd` and
/// `ra` are single bits (0/1); `opcode` is 0..15; `z` is the 3-bit reserved
/// field (0..7); `rcode` is 0..15; the four counts are 0..65535.
pub type DnsHeader = {
  id: Int;
  qr: Int;
  opcode: Int;
  aa: Int;
  tc: Int;
  rd: Int;
  ra: Int;
  z: Int;
  rcode: Int;
  qdcount: Int;
  ancount: Int;
  nscount: Int;
  arcount: Int;
}

/// Decoded domain name. `labels` holds the label byte strings in order
/// (empty for the root name). `next` is the offset just past the name in
/// the source buffer: after the terminating 0x00, or after the two pointer
/// bytes when the name ended at a compression pointer. `compressed` is
/// true when at least one pointer was followed.
pub type DnsName = {
  labels: Vec[Str];
  next: Int;
  compressed: Bool;
}

/// Parsed question entry: the name, QTYPE, QCLASS and the offset just past
/// QCLASS (`next`).
pub type DnsQuestion = {
  name: DnsName;
  qtype: Int;
  qclass: Int;
  next: Int;
}

/// Parsed resource record. `rdata_offset`/`rdata_length` locate the RDATA
/// inside the source buffer (copy it out with dns_rr_rdata); `next` is the
/// offset just past the RDATA.
pub type DnsRecord = {
  name: DnsName;
  rtype: Int;
  rclass: Int;
  ttl: Int;
  rdata_offset: Int;
  rdata_length: Int;
  next: Int;
}

/// Whole-message index. `question_offsets[i]` is the absolute offset of the
/// i-th question's name and `record_offsets[i]` the absolute offset of the
/// i-th resource record's name. Records are in section order: the first
/// `ancount` are answers, the next `nscount` authority records and the rest
/// additional records (per the header counts).
pub type DnsMessage = {
  header: DnsHeader;
  question_offsets: Vec[Int];
  record_offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[DnsHeader, Str].
fn _ok_header(v: DnsHeader) -> Result[DnsHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[DnsHeader, Str].
fn _err_header(m: Str) -> Result[DnsHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[DnsName, Str].
fn _ok_name(v: DnsName) -> Result[DnsName, Str] {
  return Ok(v);
}

// Err(m) for Result[DnsName, Str].
fn _err_name(m: Str) -> Result[DnsName, Str] {
  return Err(m);
}

// Ok(v) for Result[DnsQuestion, Str].
fn _ok_question(v: DnsQuestion) -> Result[DnsQuestion, Str] {
  return Ok(v);
}

// Err(m) for Result[DnsQuestion, Str].
fn _err_question(m: Str) -> Result[DnsQuestion, Str] {
  return Err(m);
}

// Ok(v) for Result[DnsRecord, Str].
fn _ok_record(v: DnsRecord) -> Result[DnsRecord, Str] {
  return Ok(v);
}

// Err(m) for Result[DnsRecord, Str].
fn _err_record(m: Str) -> Result[DnsRecord, Str] {
  return Err(m);
}

// Ok(v) for Result[DnsMessage, Str].
fn _ok_message(v: DnsMessage) -> Result[DnsMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[DnsMessage, Str].
fn _err_message(m: Str) -> Result[DnsMessage, Str] {
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Byte `pos` of a Str widened to an Int (0..255); callers guarantee bounds.
fn _byte_str(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// `v` reduced modulo 2^`bits` into 0..2^bits-1: the field-width masking
// rule of SPEC.md (bit fields and 16/32-bit numeric fields alike).
fn _mask_bits(v: Int, bits: Int) -> Int {
  var span: Int = 1;
  var i = 0;
  while i < bits {
    span = span * 2;
    i = i + 1;
  }
  var r = v % span;
  if r < 0 {
    r = r + span;
  }
  return r;
}

// Append `v` (already 0..65535) as two big-endian bytes.
fn _push_u16_be(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append `v` (already 0..4294967295) as four big-endian bytes.
fn _push_u32_be(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 16777216) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Unsigned big-endian 16-bit value at [pos, pos+2); caller checks bounds.
fn _u16_be_at(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned big-endian 32-bit value at [pos, pos+4); caller checks bounds.
fn _u32_be_at(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Copy bytes [start, end) into a fresh vector; caller guarantees
// 0 <= start <= end <= data.len().
fn _copy_range(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Materialize bytes [start, end) as a Str (one allocation, no validation).
fn _str_between(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  let bytes = _copy_range(data, start, end);
  return builder.sb_to_str(&bytes);
}

// Lowercase ASCII hex digit for a nibble 0..15.
fn _hex_digit(nib: Int) -> UInt8 {
  if nib < 10 {
    return (48 + nib) as UInt8;
  }
  return (87 + nib) as UInt8;
}

// Append a 16-bit group as lowercase hex, 1..4 digits, no padding.
fn _push_hex16(sb: &mut Vec[UInt8], v: Int) {
  let d3 = (v / 4096) % 16;
  let d2 = (v / 256) % 16;
  let d1 = (v / 16) % 16;
  let d0 = v % 16;
  if d3 != 0 {
    sb.push(_hex_digit(d3));
    sb.push(_hex_digit(d2));
    sb.push(_hex_digit(d1));
    sb.push(_hex_digit(d0));
    return;
  }
  if d2 != 0 {
    sb.push(_hex_digit(d2));
    sb.push(_hex_digit(d1));
    sb.push(_hex_digit(d0));
    return;
  }
  if d1 != 0 {
    sb.push(_hex_digit(d1));
    sb.push(_hex_digit(d0));
    return;
  }
  sb.push(_hex_digit(d0));
}

// The packed flags word of `h`: QR(15), Opcode(14..11), AA(10), TC(9),
// RD(8), RA(7), Z(6..4), RCODE(3..0). Every field is masked to its width.
fn _flags_word(h: &DnsHeader) -> Int {
  let qr = _mask_bits(h.qr, 1);
  let opcode = _mask_bits(h.opcode, 4);
  let aa = _mask_bits(h.aa, 1);
  let tc = _mask_bits(h.tc, 1);
  let rd = _mask_bits(h.rd, 1);
  let ra = _mask_bits(h.ra, 1);
  let z = _mask_bits(h.z, 3);
  let rcode = _mask_bits(h.rcode, 4);
  return qr * 32768 + opcode * 2048 + aa * 1024 + tc * 512 + rd * 256 + ra * 128 + z * 16 + rcode;
}

// --------------------------------------------------
//  Header
// --------------------------------------------------

/// Encode a DNS header as exactly 12 bytes: ID[2], flags[2],
/// QDCOUNT[2], ANCOUNT[2], NSCOUNT[2], ARCOUNT[2]. All multi-byte fields
/// are big-endian. Out-of-range field values are masked to their width
/// (see SPEC.md); this function cannot fail.
/// Complexity: O(1).
pub fn dns_header_encode(h: &DnsHeader) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, _mask_bits(h.id, 16));
  _push_u16_be(&mut out, _flags_word(h));
  _push_u16_be(&mut out, _mask_bits(h.qdcount, 16));
  _push_u16_be(&mut out, _mask_bits(h.ancount, 16));
  _push_u16_be(&mut out, _mask_bits(h.nscount, 16));
  _push_u16_be(&mut out, _mask_bits(h.arcount, 16));
  return out;
}

/// Decode the 12-byte DNS header at offset 0. Every bit pattern is valid,
/// so the only error is Err("dns: truncated header") when `data` is shorter
/// than 12 bytes. Bytes after offset 12 are ignored.
/// Complexity: O(1).
pub fn dns_header_decode(data: &Vec[UInt8]) -> Result[DnsHeader, Str] {
  if data.len() < 12 {
    return _err_header("dns: truncated header");
  }
  let flags = _u16_be_at(data, 2);
  let h = DnsHeader{
    id: _u16_be_at(data, 0);
    qr: flags / 32768;
    opcode: (flags / 2048) % 16;
    aa: (flags / 1024) % 2;
    tc: (flags / 512) % 2;
    rd: (flags / 256) % 2;
    ra: (flags / 128) % 2;
    z: (flags / 16) % 8;
    rcode: flags % 16;
    qdcount: _u16_be_at(data, 4);
    ancount: _u16_be_at(data, 6);
    nscount: _u16_be_at(data, 8);
    arcount: _u16_be_at(data, 10);
  };
  return _ok_header(h);
}

// --------------------------------------------------
//  Domain names
// --------------------------------------------------

/// Encode a textual domain name to uncompressed wire form: each label as
/// one length byte (1..63) followed by its bytes, then a terminating 0x00.
///
/// The name is split on '.' bytes; a single trailing dot is allowed and
/// ignored. "" and "." both encode the root name as the single byte 0x00.
/// Label bytes are copied verbatim (no charset check), but an embedded
/// 0x00 is rejected because a Str cannot carry it.
///
/// Errors: Err("dns: empty label") for an empty label (leading dot,
/// consecutive dots, or a dot-only name other than "."); Err("dns: label
/// too long") for a label longer than 63 bytes; Err("dns: name too long")
/// when the encoded name would exceed 255 bytes including the length bytes
/// and the terminating zero; Err("dns: label contains NUL byte") for a
/// label containing 0x00. Checks run per label in that order.
/// Complexity: O(name length).
pub fn dns_name_encode(name: Str) -> Result[Vec[UInt8], Str] {
  let n = name.len();
  var end = n;
  if n > 0 {
    if _byte_str(name, n - 1) == 46 {
      end = n - 1;
    }
  }
  var out = Vec[UInt8].new();
  if end == 0 {
    out.push(0 as UInt8);
    return _ok_bytes(out);
  }
  var wire = 0;
  var start = 0;
  var i = 0;
  while i <= end {
    if i == end || _byte_str(name, i) == 46 {
      let llen = i - start;
      if llen == 0 {
        return _err_bytes("dns: empty label");
      }
      if llen > 63 {
        return _err_bytes("dns: label too long");
      }
      wire = wire + 1 + llen;
      if wire > 254 {
        return _err_bytes("dns: name too long");
      }
      out.push(llen as UInt8);
      var k = start;
      while k < i {
        let b = _byte_str(name, k);
        if b == 0 {
          return _err_bytes("dns: label contains NUL byte");
        }
        out.push(b as UInt8);
        k = k + 1;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  out.push(0 as UInt8);
  return _ok_bytes(out);
}

/// Decode the domain name starting at `off`, following compression
/// pointers when present (the only place compression is supported; output
/// builders never emit pointers).
///
/// The returned `next` is the offset just past the name in `data` (past the
/// terminating zero, or past the pointer when the name ended in one).
/// Pointers may target any earlier or later offset inside `data`; loops are
/// detected and rejected, as are targets outside the buffer.
///
/// Errors: Err("dns: negative offset") for off < 0; Err("dns: truncated
/// name") when the buffer ends inside a name or a pointer's second byte is
/// missing; Err("dns: truncated label") when a label's declared bytes run
/// past the end; Err("dns: unsupported label type") for a length byte with
/// bits 7..6 = 01 or 10; Err("dns: pointer out of range") for a pointer
/// target at or past data.len(); Err("dns: compression loop") when pointer
/// following does not terminate; Err("dns: name too long") when the
/// expanded name exceeds 255 bytes; Err("dns: label contains NUL byte")
/// when a label carries 0x00 (a Str cannot represent it).
/// Complexity: O(name bytes + pointer jumps * name bytes) worst case.
pub fn dns_name_decode(data: &Vec[UInt8], off: Int) -> Result[DnsName, Str] {
  if off < 0 {
    return _err_name("dns: negative offset");
  }
  let total = data.len();
  var labels = Vec[Str].new();
  var pos = off;
  var next = -1;
  var jumps = 0;
  var wire = 0;
  var compressed = false;
  while true {
    if pos >= total {
      return _err_name("dns: truncated name");
    }
    let b: Int = _byte(data, pos);
    let kind = b / 64;
    if kind == 3 {
      if pos + 1 >= total {
        return _err_name("dns: truncated name");
      }
      let target = (b % 64) * 256 + _byte(data, pos + 1);
      if next < 0 {
        next = pos + 2;
      }
      if target >= total {
        return _err_name("dns: pointer out of range");
      }
      jumps = jumps + 1;
      if jumps > total {
        return _err_name("dns: compression loop");
      }
      pos = target;
      compressed = true;
    } elif kind != 0 {
      return _err_name("dns: unsupported label type");
    } elif b == 0 {
      if next < 0 {
        next = pos + 1;
      }
      let nm = DnsName{ labels: labels; next: next; compressed: compressed; };
      return _ok_name(nm);
    } else {
      if pos + 1 + b > total {
        return _err_name("dns: truncated label");
      }
      wire = wire + 1 + b;
      if wire > 254 {
        return _err_name("dns: name too long");
      }
      var k = 0;
      while k < b {
        if _byte(data, pos + 1 + k) == 0 {
          return _err_name("dns: label contains NUL byte");
        }
        k = k + 1;
      }
      labels.push(_str_between(data, pos + 1, pos + 1 + b));
      pos = pos + 1 + b;
    }
  }
  return _err_name("dns: truncated name");
}

/// Render a decoded name in presentation form: labels joined with '.', no
/// trailing dot. The root name (no labels) renders as "". The rendering is
/// informational; to re-encode, join the labels with '.' yourself or
/// round-trip the original bytes.
/// Complexity: O(name length).
pub fn dns_name_to_str(n: &DnsName) -> Str {
  var sb = builder.sb_new();
  let count = n.labels.len();
  var i = 0;
  while i < count {
    if i > 0 {
      builder.sb_push_str(&mut sb, ".");
    }
    let lbl: Str = n.labels[i];
    builder.sb_push_str(&mut sb, lbl);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Question section
// --------------------------------------------------

/// Encode one question entry: the uncompressed name, then QTYPE[2] and
/// QCLASS[2] (both big-endian, masked to 16 bits). Name errors propagate
/// unchanged.
/// Complexity: O(name length).
pub fn dns_question_encode(name: Str, qtype: Int, qclass: Int) -> Result[Vec[UInt8], Str] {
  let nr = dns_name_encode(name);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let nb: Vec[UInt8] = nr.value;
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, &nb);
  _push_u16_be(&mut out, _mask_bits(qtype, 16));
  _push_u16_be(&mut out, _mask_bits(qclass, 16));
  return _ok_bytes(out);
}

/// Parse the question entry at `off`: name, QTYPE, QCLASS, and the offset
/// just past QCLASS (`next`). Name errors propagate unchanged
/// (including Err("dns: negative offset")); Err("dns: truncated question")
/// when fewer than 4 bytes follow the name.
/// Complexity: O(name length).
pub fn dns_question_parse(data: &Vec[UInt8], off: Int) -> Result[DnsQuestion, Str] {
  let nr = dns_name_decode(data, off);
  if !nr.is_ok {
    return _err_question(nr.error);
  }
  let nm: DnsName = nr.value;
  let after = nm.next;
  if after + 4 > data.len() {
    return _err_question("dns: truncated question");
  }
  let q = DnsQuestion{
    name: nm;
    qtype: _u16_be_at(data, after);
    qclass: _u16_be_at(data, after + 2);
    next: after + 4;
  };
  return _ok_question(q);
}

// --------------------------------------------------
//  Resource records
// --------------------------------------------------

/// Encode one resource record: the uncompressed owner name, TYPE[2],
/// CLASS[2], TTL[4] (unsigned 32-bit), RDLENGTH[2] and the RDATA bytes
/// verbatim. rtype/rclass/ttl are masked to their width; RDATA longer than
/// 65535 bytes is Err("dns: rdata too long"). Name errors propagate.
/// Complexity: O(name length + RDATA length).
pub fn dns_rr_encode(name: Str, rtype: Int, rclass: Int, ttl: Int, rdata: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let nr = dns_name_encode(name);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let nb: Vec[UInt8] = nr.value;
  let rdlen = rdata.len();
  if rdlen > 65535 {
    return _err_bytes("dns: rdata too long");
  }
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, &nb);
  _push_u16_be(&mut out, _mask_bits(rtype, 16));
  _push_u16_be(&mut out, _mask_bits(rclass, 16));
  _push_u32_be(&mut out, _mask_bits(ttl, 32));
  _push_u16_be(&mut out, rdlen);
  _push_bytes(&mut out, rdata);
  return _ok_bytes(out);
}

/// Parse the resource record at `off`: owner name, TYPE, CLASS, TTL
/// (0..4294967295), RDLENGTH and the RDATA span (`rdata_offset`,
/// `rdata_length`; copy it out with dns_rr_rdata).
/// Name errors propagate unchanged (including Err("dns: negative offset"));
/// Err("dns: truncated record") when fewer than 10 bytes follow the name;
/// Err("dns: truncated rdata") when the declared RDLENGTH runs past the
/// buffer end.
/// Complexity: O(name length).
pub fn dns_rr_parse(data: &Vec<UInt8>, off: Int) -> Result[DnsRecord, Str] {
  let nr = dns_name_decode(data, off);
  if !nr.is_ok {
    return _err_record(nr.error);
  }
  let nm: DnsName = nr.value;
  let after = nm.next;
  let total = data.len();
  if after + 10 > total {
    return _err_record("dns: truncated record");
  }
  let rdlength = _u16_be_at(data, after + 8);
  let rdata_off = after + 10;
  if rdata_off + rdlength > total {
    return _err_record("dns: truncated rdata");
  }
  let r = DnsRecord{
    name: nm;
    rtype: _u16_be_at(data, after);
    rclass: _u16_be_at(data, after + 2);
    ttl: _u32_be_at(data, after + 4);
    rdata_offset: rdata_off;
    rdata_length: rdlength;
    next: rdata_off + rdlength;
  };
  return _ok_record(r);
}

/// Copy the RDATA of a parsed record out of `data` (the buffer it was
/// parsed from, or one holding at least the recorded span).
/// Err("dns: rdata out of range") when the recorded span is negative or
/// does not fit `data`; a zero-length RDATA yields an empty Ok.
/// Complexity: O(rdata_length).
pub fn dns_rr_rdata(data: &Vec<UInt8>, r: &DnsRecord) -> Result[Vec[UInt8], Str] {
  let off: Int = r.rdata_offset;
  let len: Int = r.rdata_length;
  if off < 0 || len < 0 {
    return _err_bytes("dns: rdata out of range");
  }
  if off + len > data.len() {
    return _err_bytes("dns: rdata out of range");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  RDATA builders (A, AAAA, CNAME, MX, TXT)
// --------------------------------------------------

/// Build A RDATA from exactly 4 address octets (network order).
/// Err("dns: bad A rdata") for any other length.
/// Complexity: O(1).
pub fn dns_rdata_a(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if octets.len() != 4 {
    return _err_bytes("dns: bad A rdata");
  }
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, octets);
  return _ok_bytes(out);
}

/// Build AAAA RDATA from exactly 16 address octets (network order).
/// Err("dns: bad AAAA rdata") for any other length.
/// Complexity: O(1).
pub fn dns_rdata_aaaa(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if octets.len() != 16 {
    return _err_bytes("dns: bad AAAA rdata");
  }
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, octets);
  return _ok_bytes(out);
}

/// Build CNAME RDATA: the target name encoded uncompressed (no pointer is
/// ever emitted). Name errors propagate unchanged.
/// Complexity: O(name length).
pub fn dns_rdata_cname(name: Str) -> Result[Vec[UInt8], Str] {
  let nr = dns_name_encode(name);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let nb: Vec[UInt8] = nr.value;
  return _ok_bytes(nb);
}

/// Build MX RDATA: a 16-bit big-endian preference (masked to 16 bits)
/// followed by the exchange name encoded uncompressed. Name errors
/// propagate unchanged.
/// Complexity: O(name length).
pub fn dns_rdata_mx(preference: Int, exchange: Str) -> Result[Vec[UInt8], Str] {
  let nr = dns_name_encode(exchange);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let nb: Vec[UInt8] = nr.value;
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, _mask_bits(preference, 16));
  _push_bytes(&mut out, &nb);
  return _ok_bytes(out);
}

/// Build TXT RDATA as one character-string: a length byte followed by the
/// text bytes verbatim (embedded 0x00 is allowed -- a character-string is
/// binary). Err("dns: txt too long") when text.len() > 255.
/// Complexity: O(text length).
pub fn dns_rdata_txt(text: Str) -> Result[Vec[UInt8], Str] {
  let n = text.len();
  if n > 255 {
    return _err_bytes("dns: txt too long");
  }
  var out = Vec[UInt8].new();
  out.push(n as UInt8);
  builder.sb_push_str(&mut out, text);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  RDATA parsers (A, AAAA, CNAME, MX, TXT)
// --------------------------------------------------

/// Render 4-byte A RDATA as "a.b.c.d".
/// Err("dns: bad A rdata") when the length is not 4.
/// Complexity: O(1).
pub fn dns_rdata_a_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str] {
  if rdata.len() != 4 {
    return _err_str("dns: bad A rdata");
  }
  var sb = builder.sb_new();
  var i = 0;
  while i < 4 {
    if i > 0 {
      builder.sb_push_str(&mut sb, ".");
    }
    builder.sb_push_int(&mut sb, _byte(rdata, i));
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

/// Render 16-byte AAAA RDATA as full-form lowercase IPv6 (8 groups, no
/// "::" compression): e.g. "2001:db8:0:0:0:0:0:1" (RFC 5952 style would
/// compress; this package does not).
/// Err("dns: bad AAAA rdata") when the length is not 16.
/// Complexity: O(1).
pub fn dns_rdata_aaaa_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str] {
  if rdata.len() != 16 {
    return _err_str("dns: bad AAAA rdata");
  }
  var sb = builder.sb_new();
  var i = 0;
  while i < 8 {
    if i > 0 {
      builder.sb_push_str(&mut sb, ":");
    }
    _push_hex16(&mut sb, _byte(rdata, i * 2) * 256 + _byte(rdata, i * 2 + 1));
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

/// Decode the name stored in RDATA at [off, off+len): used for CNAME
/// targets and MX exchanges. Compression pointers are followed (the
/// encoded name may end in a pointer), but the name's end must fall inside
/// the RDATA span.
/// Errors: Err("dns: bad rdata name") when len < 1 or the name ends past
/// off+len; otherwise the dns_name_decode catalog.
/// Complexity: O(name bytes).
pub fn dns_rdata_name(data: &Vec<UInt8>, off: Int, len: Int) -> Result[DnsName, Str] {
  if len < 1 {
    return _err_name("dns: bad rdata name");
  }
  let nr = dns_name_decode(data, off);
  if !nr.is_ok {
    return _err_name(nr.error);
  }
  let nm: DnsName = nr.value;
  if nm.next > off + len {
    return _err_name("dns: bad rdata name");
  }
  return _ok_name(nm);
}

/// The 16-bit big-endian preference of MX RDATA at [off, off+len).
/// Err("dns: bad MX rdata") when len < 3 or the field is out of bounds.
/// Complexity: O(1).
pub fn dns_rdata_mx_preference(data: &Vec<UInt8>, off: Int, len: Int) -> Result[Int, Str] {
  if len < 3 {
    return _err_int("dns: bad MX rdata");
  }
  if off < 0 || off + 2 > data.len() {
    return _err_int("dns: bad MX rdata");
  }
  return _ok_int(_u16_be_at(data, off));
}

/// The exchange name of MX RDATA at [off, off+len) (the name after the
/// 2-byte preference). Err("dns: bad MX rdata") when len < 3; otherwise the
/// dns_rdata_name catalog.
/// Complexity: O(name bytes).
pub fn dns_rdata_mx_exchange(data: &Vec<UInt8>, off: Int, len: Int) -> Result[DnsName, Str] {
  if len < 3 {
    return _err_name("dns: bad MX rdata");
  }
  return dns_rdata_name(data, off + 2, len - 2);
}

/// Parse TXT RDATA holding exactly one character-string: the first byte is
/// the string length and must account for the whole RDATA. The text is
/// copied verbatim (no UTF-8 or NUL validation).
/// Err("dns: bad TXT rdata") when the RDATA is empty or holds more or less
/// than one complete character-string (multi-string TXT is a documented
/// non-goal).
/// Complexity: O(text length).
pub fn dns_rdata_txt_parse(rdata: &Vec[UInt8]) -> Result[Str, Str] {
  let n = rdata.len();
  if n < 1 {
    return _err_str("dns: bad TXT rdata");
  }
  let slen = _byte(rdata, 0);
  if slen + 1 != n {
    return _err_str("dns: bad TXT rdata");
  }
  var sb = builder.sb_new();
  var i = 0;
  while i < slen {
    builder.sb_push_byte(&mut sb, rdata[i + 1]);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  Whole messages
// --------------------------------------------------

/// Build a standard recursive query: a 12-byte header with the given `id`
/// (masked to 16 bits), QR=0, Opcode=0, RD=1, all other flags zero,
/// QDCOUNT=1 and AN/NS/AR=0, followed by one question with class IN and the
/// given `qtype` (masked to 16 bits). Name errors propagate.
/// Complexity: O(name length).
pub fn dns_query_build(id: Int, name: Str, qtype: Int) -> Result[Vec[UInt8], Str] {
  let nr = dns_name_encode(name);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let nb: Vec[UInt8] = nr.value;
  let h = DnsHeader{
    id: _mask_bits(id, 16);
    qr: 0;
    opcode: 0;
    aa: 0;
    tc: 0;
    rd: 1;
    ra: 0;
    z: 0;
    rcode: 0;
    qdcount: 1;
    ancount: 0;
    nscount: 0;
    arcount: 0;
  };
  let hb = dns_header_encode(&h);
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, &hb);
  _push_bytes(&mut out, &nb);
  _push_u16_be(&mut out, _mask_bits(qtype, 16));
  _push_u16_be(&mut out, DNS_CLASS_IN);
  return _ok_bytes(out);
}

/// Parse a whole DNS message: the header, then QDCOUNT questions, then
/// ANCOUNT + NSCOUNT + ARCOUNT resource records, in order. Names are
/// decoded only far enough to find every section boundary; their offsets
/// are recorded in the DnsMessage index (question_offsets /
/// record_offsets) and the entries themselves are read with
/// dns_question_parse / dns_rr_parse at those offsets.
///
/// Errors: the dns_header_decode catalog ("dns: truncated header");
/// Err("dns: truncated question") / Err("dns: truncated record") when a
/// declared entry has no bytes left; otherwise the name and record errors
/// propagate unchanged. Bytes after the last declared entry are ignored.
/// Complexity: O(message length).
pub fn dns_message_parse(data: &Vec[UInt8]) -> Result[DnsMessage, Str] {
  let hr = dns_header_decode(data);
  if !hr.is_ok {
    return _err_message(hr.error);
  }
  let h: DnsHeader = hr.value;
  let total = data.len();
  var q_offsets = Vec[Int].new();
  var r_offsets = Vec[Int].new();
  var pos = 12;
  var i = 0;
  while i < h.qdcount {
    if pos >= total {
      return _err_message("dns: truncated question");
    }
    let qr = dns_question_parse(data, pos);
    if !qr.is_ok {
      return _err_message(qr.error);
    }
    let q: DnsQuestion = qr.value;
    q_offsets.push(pos);
    pos = q.next;
    i = i + 1;
  }
  let records = h.ancount + h.nscount + h.arcount;
  i = 0;
  while i < records {
    if pos >= total {
      return _err_message("dns: truncated record");
    }
    let rr = dns_rr_parse(data, pos);
    if !rr.is_ok {
      return _err_message(rr.error);
    }
    let r: DnsRecord = rr.value;
    r_offsets.push(pos);
    pos = r.next;
    i = i + 1;
  }
  let m = DnsMessage{ header: h; question_offsets: q_offsets; record_offsets: r_offsets; };
  return _ok_message(m);
}

/// Number of parsed questions in the index. Complexity: O(1).
pub fn dns_message_question_count(m: &DnsMessage) -> Int {
  return m.question_offsets.len();
}

/// Number of parsed resource records in the index (answers, authority and
/// additional together). Complexity: O(1).
pub fn dns_message_record_count(m: &DnsMessage) -> Int {
  return m.record_offsets.len();
}

/// Absolute offset of the i-th question's name in the parse buffer, or -1
/// when i is negative or >= dns_message_question_count(m).
/// Complexity: O(1).
pub fn dns_message_question_offset(m: &DnsMessage, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.question_offsets.len() {
    return -1;
  }
  let off: Int = m.question_offsets[i];
  return off;
}

/// Absolute offset of the i-th resource record's name in the parse buffer,
/// or -1 when i is negative or >= dns_message_record_count(m).
/// Complexity: O(1).
pub fn dns_message_record_offset(m: &DnsMessage, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.record_offsets.len() {
    return -1;
  }
  let off: Int = m.record_offsets[i];
  return off;
}
