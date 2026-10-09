// XIOM -- xiom.bonjour: mDNS / DNS-SD (RFC 6762 / RFC 6763) message codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets) encoder and decoder for Bonjour traffic:
// the mDNS message framing (12-byte header with flags and the QD/AN/NS/AR
// counts, questions, resource records), domain names with compression
// pointers (validated on decode, optional on encode), the PTR/SRV/TXT/A/AAAA
// record types with their RDATA layouts, and the DNS-SD conventions built on
// top: the `_services._dns-sd._udp.local` enumeration name, service type and
// instance names, subtype labels, TXT key=value lists, the `local` domain
// checks, and the PTR/SRV/TXT builders for the advertise / browse / query
// forms.
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
//     never compared with `==` (BUG 17 discipline): all string equality
//     goes through xiom.string.compare.str_compare.
//   * the whole-message index is flat (parallel Vec[Int] fields) because
//     Vec[StructType] is unsupported in this compiler.
//   * at the ABI a Str is a NUL-terminated C string, so a label containing
//     a 0x00 byte cannot be represented; labels are validated as printable
//     (0x20..0x7E) before any sb_to_str call, in both directions.
//   * no `match` is used in this module (no mut in match arms).

module xiom.bonjour

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// The IANA-assigned mDNS UDP port.
pub const BONJOUR_PORT: Int = 5353;
/// The IPv4 mDNS multicast group, as a presentation string.
pub const BONJOUR_MDNS_IPV4: Str = "224.0.0.251";
/// The IPv6 mDNS multicast group, as a presentation string.
pub const BONJOUR_MDNS_IPV6: Str = "ff02::fb";

/// RR/query TYPE codes covered by the RDATA helpers (RFC 1035, RFC 3596,
/// RFC 2782).
pub const BONJOUR_TYPE_A: Int = 1;
pub const BONJOUR_TYPE_PTR: Int = 12;
pub const BONJOUR_TYPE_TXT: Int = 16;
pub const BONJOUR_TYPE_AAAA: Int = 28;
pub const BONJOUR_TYPE_SRV: Int = 33;
pub const BONJOUR_TYPE_ANY: Int = 255;

/// The class used by every mDNS record: Internet (IN).
pub const BONJOUR_CLASS_IN: Int = 1;
/// The top bit of the 16-bit class field: cache-flush in responses,
/// unicast-response (QU) in questions (RFC 6762 sections 5.4 and 10.2).
pub const BONJOUR_CLASS_TOP_BIT: Int = 32768;

/// Recommended TTLs (seconds): 120 for host records, 4500 for PTR/SRV/TXT
/// service records (RFC 6762 section 10, RFC 6763 section 6.1).
pub const BONJOUR_TTL_HOST: Int = 120;
pub const BONJOUR_TTL_SERVICE: Int = 4500;

/// The special-use domain served by mDNS.
pub const BONJOUR_DOMAIN: Str = "local";
/// Prefix of the DNS-SD service enumeration name
/// (`BONJOUR_ENUM_PREFIX + BONJOUR_DOMAIN` = `_services._dns-sd._udp.local`).
pub const BONJOUR_ENUM_PREFIX: Str = "_services._dns-sd._udp.";

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Parsed 12-byte mDNS header. `qr`, `aa`, `tc`, `rd` and `ra` are single
/// bits (0/1); `opcode` is 0..15; `z` is the 3-bit reserved field (0..7);
/// `rcode` is 0..15; `id` and the four counts are 0..65535.
pub type BonjourHeader = {
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
pub type BonjourName = {
  labels: Vec[Str];
  next: Int;
  compressed: Bool;
}

/// Parsed question entry: the name, QTYPE, QCLASS (including the top
/// unicast-response bit) and the offset just past QCLASS (`next`).
pub type BonjourQuestion = {
  name: BonjourName;
  qtype: Int;
  qclass: Int;
  next: Int;
}

/// Parsed resource record. `rclass` includes the cache-flush bit;
/// `rdata_offset`/`rdata_length` locate the RDATA inside the source buffer
/// (copy it out with bonjour_rr_rdata); `next` is the offset just past the
/// RDATA.
pub type BonjourRecord = {
  name: BonjourName;
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
pub type BonjourMessage = {
  header: BonjourHeader;
  question_offsets: Vec[Int];
  record_offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

fn _ok_header(v: BonjourHeader) -> Result[BonjourHeader, Str] {
  return Ok(v);
}

fn _err_header(m: Str) -> Result[BonjourHeader, Str] {
  return Err(m);
}

fn _ok_name(v: BonjourName) -> Result[BonjourName, Str] {
  return Ok(v);
}

fn _err_name(m: Str) -> Result[BonjourName, Str] {
  return Err(m);
}

fn _ok_labels(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

fn _err_labels(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

fn _ok_question(v: BonjourQuestion) -> Result[BonjourQuestion, Str] {
  return Ok(v);
}

fn _err_question(m: Str) -> Result[BonjourQuestion, Str] {
  return Err(m);
}

fn _ok_record(v: BonjourRecord) -> Result[BonjourRecord, Str] {
  return Ok(v);
}

fn _err_record(m: Str) -> Result[BonjourRecord, Str] {
  return Err(m);
}

fn _ok_message(v: BonjourMessage) -> Result[BonjourMessage, Str] {
  return Ok(v);
}

fn _err_message(m: Str) -> Result[BonjourMessage, Str] {
  return Err(m);
}

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

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

// Printable ASCII (space through tilde). DNS-SD labels and TXT strings are
// limited to this subset so they survive the NUL-terminated Str runtime.
fn _is_printable(b: Int) -> Bool {
  if b < 32 {
    return false;
  }
  if b > 126 {
    return false;
  }
  return true;
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

// Concatenate two byte vectors into a fresh one.
fn _concat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
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
fn _flags_word(h: &BonjourHeader) -> Int {
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
//  Domain names
// --------------------------------------------------

// Split a textual name into validated label strings (see bonjour_name_encode
// for the exact rules). Root ("" or ".") yields an empty Vec.
fn _name_split(name: Str) -> Result[Vec[Str], Str] {
  let n = name.len();
  var end = n;
  if n > 0 {
    if _byte_str(name, n - 1) == 46 {
      end = n - 1;
    }
  }
  var labels = Vec[Str].new();
  if end == 0 {
    return _ok_labels(labels);
  }
  var wire = 0;
  var start = 0;
  var i = 0;
  while i <= end {
    if i == end || _byte_str(name, i) == 46 {
      let llen = i - start;
      if llen == 0 {
        return _err_labels("bonjour: empty label");
      }
      if llen > 63 {
        return _err_labels("bonjour: label too long");
      }
      wire = wire + 1 + llen;
      if wire > 254 {
        return _err_labels("bonjour: name too long");
      }
      var lbl_bytes = Vec[UInt8].new();
      var k = start;
      while k < i {
        let b = _byte_str(name, k);
        if b == 0 {
          return _err_labels("bonjour: label contains NUL byte");
        }
        if !_is_printable(b) {
          return _err_labels("bonjour: label not printable");
        }
        lbl_bytes.push(b as UInt8);
        k = k + 1;
      }
      labels.push(builder.sb_to_str(&lbl_bytes));
      start = i + 1;
    }
    i = i + 1;
  }
  return _ok_labels(labels);
}

// Encode validated labels in uncompressed wire form (length bytes + bytes +
// terminating 0x00).
fn _encode_labels(labels: &Vec[Str]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < labels.len() {
    let lbl: Str = labels[i];
    let llen = lbl.len();
    out.push(llen as UInt8);
    builder.sb_push_str(&mut out, lbl);
    i = i + 1;
  }
  out.push(0 as UInt8);
  return out;
}

// Join labels [start, len) with '.' into a fresh Str (used for compression
// suffix lookup).
fn _join_labels(labels: &Vec[Str], start: Int) -> Str {
  var sb = builder.sb_new();
  var i = start;
  var first = true;
  while i < labels.len() {
    if !first {
      builder.sb_push_str(&mut sb, ".");
    }
    let lbl: Str = labels[i];
    builder.sb_push_str(&mut sb, lbl);
    first = false;
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// Encode a textual domain name to uncompressed wire form: each label as
/// one length byte (1..63) followed by its bytes, then a terminating 0x00.
///
/// The name is split on '.' bytes; a single trailing dot is allowed and
/// ignored. "" and "." both encode the root name as the single byte 0x00.
/// Label bytes must be printable ASCII (0x20..0x7E) and must not be 0x00,
/// so every label survives the NUL-terminated Str runtime.
///
/// Errors: Err("bonjour: empty label") for an empty label (leading dot,
/// consecutive dots, or a dot-only name other than "."); Err("bonjour:
/// label too long") for a label longer than 63 bytes; Err("bonjour: name
/// too long") when the encoded name would exceed 255 bytes including the
/// length bytes and the terminating zero; Err("bonjour: label contains NUL
/// byte") / Err("bonjour: label not printable") for bad label bytes.
/// Checks run per label in that order.
/// Complexity: O(name length).
pub fn bonjour_name_encode(name: Str) -> Result[Vec[UInt8], Str]
  ensures: name.len() == 0 => result is Ok;
  ensures: result is Err => name.len() > 0;
{
  let lr = _name_split(name);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let labels: Vec[Str] = lr.value;
  return _ok_bytes(_encode_labels(&labels));
}

/// Encode a name with optional RFC 1035 compression: before writing label
/// `i`, the suffix formed by labels `i..` is looked up in `prior_names`
/// (exact, case-sensitive match); on a hit whose `prior_offsets[j]` is in
/// 0..16383, the remainder is emitted as a two-byte compression pointer and
/// encoding stops. Names without a matching suffix are written in full.
///
/// `prior_names[j]` must be a name previously encoded at absolute message
/// offset `prior_offsets[j]`; both vectors are read in parallel and the
/// lookup stops at the shorter one. Output is a valid, decodable name
/// either way (pointers point backwards at already-emitted bytes).
/// Errors: the bonjour_name_encode catalog.
/// Complexity: O(labels * name length) worst case.
pub fn bonjour_name_encode_compressed(name: Str, prior_names: &Vec[Str], prior_offsets: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let lr = _name_split(name);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let labels: Vec[Str] = lr.value;
  let count = labels.len();
  var out = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < count && !done {
    let suffix = _join_labels(&labels, i);
    var hit = -1;
    var j = 0;
    while j < prior_names.len() && j < prior_offsets.len() && hit < 0 {
      let pn: Str = prior_names[j];
      if compare.str_compare(suffix, pn) == 0 {
        let poff: Int = prior_offsets[j];
        if poff >= 0 && poff < 16384 {
          hit = poff;
        }
      }
      j = j + 1;
    }
    if hit >= 0 {
      out.push((192 + hit / 256) as UInt8);
      out.push((hit % 256) as UInt8);
      done = true;
    } else {
      let lbl: Str = labels[i];
      out.push(lbl.len() as UInt8);
      builder.sb_push_str(&mut out, lbl);
      i = i + 1;
    }
  }
  if !done {
    out.push(0 as UInt8);
  }
  return _ok_bytes(out);
}

/// Decode the domain name starting at `off`, following compression
/// pointers when present.
///
/// The returned `next` is the offset just past the name in `data` (past the
/// terminating zero, or past the pointer when the name ended in one).
/// Pointers may target any earlier or later offset inside `data`; loops are
/// detected and rejected, as are targets outside the buffer. Label bytes
/// must be printable ASCII (0x20..0x7E).
///
/// Errors: Err("bonjour: negative offset") for off < 0; Err("bonjour:
/// truncated name") when the buffer ends inside a name or a pointer's
/// second byte is missing; Err("bonjour: truncated label") when a label's
/// declared bytes run past the end; Err("bonjour: unsupported label type")
/// for a length byte with bits 7..6 = 01 or 10; Err("bonjour: pointer out
/// of range") for a pointer target at or past data.len(); Err("bonjour:
/// compression loop") when pointer following does not terminate;
/// Err("bonjour: name too long") when the expanded name exceeds 255 bytes;
/// Err("bonjour: label contains NUL byte") / Err("bonjour: label not
/// printable") for bad label bytes.
/// Complexity: O(name bytes + pointer jumps * name bytes) worst case.
pub fn bonjour_name_decode(data: &Vec[UInt8], off: Int) -> Result[BonjourName, Str]
  ensures: off < 0 => result is Err;
  ensures: off >= data.len() => result is Err;
  ensures: result is Ok => off >= 0 && off < data.len();
{
  if off < 0 {
    return _err_name("bonjour: negative offset");
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
      return _err_name("bonjour: truncated name");
    }
    let b: Int = _byte(data, pos);
    let kind = b / 64;
    if kind == 3 {
      if pos + 1 >= total {
        return _err_name("bonjour: truncated name");
      }
      let target = (b % 64) * 256 + _byte(data, pos + 1);
      if next < 0 {
        next = pos + 2;
      }
      if target >= total {
        return _err_name("bonjour: pointer out of range");
      }
      jumps = jumps + 1;
      if jumps > total {
        return _err_name("bonjour: compression loop");
      }
      pos = target;
      compressed = true;
    } elif kind != 0 {
      return _err_name("bonjour: unsupported label type");
    } elif b == 0 {
      if next < 0 {
        next = pos + 1;
      }
      let nm = BonjourName{ labels: labels; next: next; compressed: compressed; };
      return _ok_name(nm);
    } else {
      if pos + 1 + b > total {
        return _err_name("bonjour: truncated label");
      }
      wire = wire + 1 + b;
      if wire > 254 {
        return _err_name("bonjour: name too long");
      }
      var k = 0;
      while k < b {
        let lb = _byte(data, pos + 1 + k);
        if lb == 0 {
          return _err_name("bonjour: label contains NUL byte");
        }
        if !_is_printable(lb) {
          return _err_name("bonjour: label not printable");
        }
        k = k + 1;
      }
      labels.push(_str_between(data, pos + 1, pos + 1 + b));
      pos = pos + 1 + b;
    }
  }
  return _err_name("bonjour: truncated name");
}

/// Render a decoded name in presentation form: labels joined with '.', no
/// trailing dot. The root name (no labels) renders as "".
/// Complexity: O(name length).
pub fn bonjour_name_to_str(n: &BonjourName) -> Str {
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
//  Header
// --------------------------------------------------

/// Encode a header as exactly 12 bytes: ID[2], flags[2], QDCOUNT[2],
/// ANCOUNT[2], NSCOUNT[2], ARCOUNT[2]. All multi-byte fields are big-endian.
/// Out-of-range field values are masked to their width (see SPEC.md); this
/// function cannot fail. Complexity: O(1).
pub fn bonjour_header_encode(h: &BonjourHeader) -> Vec[UInt8]
  ensures: result.len() == 12;
{
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, _mask_bits(h.id, 16));
  _push_u16_be(&mut out, _flags_word(h));
  _push_u16_be(&mut out, _mask_bits(h.qdcount, 16));
  _push_u16_be(&mut out, _mask_bits(h.ancount, 16));
  _push_u16_be(&mut out, _mask_bits(h.nscount, 16));
  _push_u16_be(&mut out, _mask_bits(h.arcount, 16));
  return out;
}

/// Decode the 12-byte header at offset 0. Every bit pattern is valid, so
/// the only error is Err("bonjour: truncated header") when `data` is
/// shorter than 12 bytes. Bytes after offset 12 are ignored.
/// Complexity: O(1).
pub fn bonjour_header_decode(data: &Vec[UInt8]) -> Result[BonjourHeader, Str]
  ensures: data.len() < 12 => result is Err;
  ensures: data.len() >= 12 => result is Ok;
{
  if data.len() < 12 {
    return _err_header("bonjour: truncated header");
  }
  let flags = _u16_be_at(data, 2);
  let h = BonjourHeader{
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
//  Class bits (cache-flush / unicast-response)
// --------------------------------------------------

/// The 16-bit class value to write: `BONJOUR_CLASS_IN`, plus
/// `BONJOUR_CLASS_TOP_BIT` when `top` is true. In a response record the top
/// bit is cache-flush; in a question it is unicast-response (QU).
/// Complexity: O(1).
pub fn bonjour_class_value(top: Bool) -> Int
  ensures: top => result == 32769;
  ensures: !top => result == 1;
{
  if top {
    return BONJOUR_CLASS_IN + BONJOUR_CLASS_TOP_BIT;
  }
  return BONJOUR_CLASS_IN;
}

/// True when the cache-flush bit is set in a parsed record's class.
/// Complexity: O(1).
pub fn bonjour_class_flush(rclass: Int) -> Bool {
  let v = _mask_bits(rclass, 16);
  if v / BONJOUR_CLASS_TOP_BIT == 1 {
    return true;
  }
  return false;
}

/// True when the unicast-response (QU) bit is set in a parsed question's
/// class. Same bit as the cache-flush bit, read from a question.
/// Complexity: O(1).
pub fn bonjour_class_unicast(qclass: Int) -> Bool {
  let v = _mask_bits(qclass, 16);
  if v / BONJOUR_CLASS_TOP_BIT == 1 {
    return true;
  }
  return false;
}

/// The class with the top bit cleared: the bare IN value (1) in the
/// documented subset. Complexity: O(1).
pub fn bonjour_class_base(rclass: Int) -> Int {
  return _mask_bits(rclass, 16) % BONJOUR_CLASS_TOP_BIT;
}

// --------------------------------------------------
//  Questions
// --------------------------------------------------

/// Encode one question entry: the uncompressed name, then QTYPE[2] and
/// QCLASS[2] (both big-endian, masked to 16 bits; pass the QU bit through
/// `qclass` or use bonjour_class_value). Name errors propagate unchanged.
/// Complexity: O(name length).
pub fn bonjour_question_encode(name: Str, qtype: Int, qclass: Int) -> Result[Vec[UInt8], Str]
  ensures: name.len() == 0 => result is Ok;
  ensures: result is Err => name.len() > 0;
{
  let nr = bonjour_name_encode(name);
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

/// Parse the question entry at `off`: name, QTYPE, QCLASS (raw, including
/// the QU bit), and the offset just past QCLASS (`next`). Name errors
/// propagate unchanged (including Err("bonjour: negative offset"));
/// Err("bonjour: truncated question") when fewer than 4 bytes follow the
/// name. Complexity: O(name length).
pub fn bonjour_question_parse(data: &Vec[UInt8], off: Int) -> Result[BonjourQuestion, Str] {
  let nr = bonjour_name_decode(data, off);
  if !nr.is_ok {
    return _err_question(nr.error);
  }
  let nm: BonjourName = nr.value;
  let after = nm.next;
  if after + 4 > data.len() {
    return _err_question("bonjour: truncated question");
  }
  let q = BonjourQuestion{
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
/// 65535 bytes is Err("bonjour: rdata too long"). Name errors propagate.
/// Complexity: O(name length + RDATA length).
pub fn bonjour_rr_encode(name: Str, rtype: Int, rclass: Int, ttl: Int, rdata: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let nr = bonjour_name_encode(name);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let nb: Vec[UInt8] = nr.value;
  let rdlen = rdata.len();
  if rdlen > 65535 {
    return _err_bytes("bonjour: rdata too long");
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

/// Parse the resource record at `off`: owner name, TYPE, CLASS (raw,
/// including the cache-flush bit), TTL (0..4294967295), RDLENGTH and the
/// RDATA span (`rdata_offset`, `rdata_length`; copy it out with
/// bonjour_rr_rdata).
/// Name errors propagate unchanged (including Err("bonjour: negative
/// offset")); Err("bonjour: truncated record") when fewer than 10 bytes
/// follow the name; Err("bonjour: truncated rdata") when the declared
/// RDLENGTH runs past the buffer end. Complexity: O(name length).
pub fn bonjour_rr_parse(data: &Vec[UInt8], off: Int) -> Result[BonjourRecord, Str] {
  let nr = bonjour_name_decode(data, off);
  if !nr.is_ok {
    return _err_record(nr.error);
  }
  let nm: BonjourName = nr.value;
  let after = nm.next;
  let total = data.len();
  if after + 10 > total {
    return _err_record("bonjour: truncated record");
  }
  let rdlength = _u16_be_at(data, after + 8);
  let rdata_off = after + 10;
  if rdata_off + rdlength > total {
    return _err_record("bonjour: truncated rdata");
  }
  let r = BonjourRecord{
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
/// Err("bonjour: rdata out of range") when the recorded span is negative
/// or does not fit `data`; a zero-length RDATA yields an empty Ok.
/// Complexity: O(rdata_length).
pub fn bonjour_rr_rdata(data: &Vec[UInt8], r: &BonjourRecord) -> Result[Vec[UInt8], Str] {
  let off: Int = r.rdata_offset;
  let len: Int = r.rdata_length;
  if off < 0 || len < 0 {
    return _err_bytes("bonjour: rdata out of range");
  }
  if off + len > data.len() {
    return _err_bytes("bonjour: rdata out of range");
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
//  RDATA builders (PTR, SRV, TXT, A, AAAA)
// --------------------------------------------------

/// Build PTR RDATA: the target name encoded uncompressed.
/// Complexity: O(name length).
pub fn bonjour_rdata_ptr(target: Str) -> Result[Vec[UInt8], Str] {
  let nr = bonjour_name_encode(target);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let nb: Vec[UInt8] = nr.value;
  return _ok_bytes(nb);
}

/// Build SRV RDATA: PRIORITY[2], WEIGHT[2], PORT[2] (each masked to 16
/// bits) followed by the target host name encoded uncompressed.
/// Name errors propagate unchanged.
/// Complexity: O(name length).
pub fn bonjour_rdata_srv(priority: Int, weight: Int, port: Int, target: Str) -> Result[Vec[UInt8], Str] {
  let nr = bonjour_name_encode(target);
  if !nr.is_ok {
    return _err_bytes(nr.error);
  }
  let tb: Vec[UInt8] = nr.value;
  var out = Vec[UInt8].new();
  _push_u16_be(&mut out, _mask_bits(priority, 16));
  _push_u16_be(&mut out, _mask_bits(weight, 16));
  _push_u16_be(&mut out, _mask_bits(port, 16));
  _push_bytes(&mut out, &tb);
  return _ok_bytes(out);
}

/// Build TXT RDATA from key=value strings: each string as one length byte
/// (0..255) followed by its bytes. Strings are not rewritten; pass them
/// through bonjour_txt_pair for the "key=value" / boolean-key convention.
/// Errors: Err("bonjour: TXT string too long") when a string exceeds 255
/// bytes; Err("bonjour: TXT byte not printable") for bytes outside
/// 0x20..0x7E. An empty `pairs` is legal and yields an empty RDATA.
/// Complexity: O(total string bytes).
pub fn bonjour_rdata_txt(pairs: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < pairs.len() {
    let p: Str = pairs[i];
    let plen = p.len();
    if plen > 255 {
      return _err_bytes("bonjour: TXT string too long");
    }
    var k = 0;
    while k < plen {
      let b = _byte_str(p, k);
      if !_is_printable(b) {
        return _err_bytes("bonjour: TXT byte not printable");
      }
      k = k + 1;
    }
    out.push(plen as UInt8);
    builder.sb_push_str(&mut out, p);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Build A RDATA from exactly 4 address octets (network order).
/// Err("bonjour: bad A rdata") for any other length. Complexity: O(1).
pub fn bonjour_rdata_a(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  ensures: octets.len() != 4 => result is Err;
  ensures: octets.len() == 4 => result is Ok;
{
  if octets.len() != 4 {
    return _err_bytes("bonjour: bad A rdata");
  }
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, octets);
  return _ok_bytes(out);
}

/// Build AAAA RDATA from exactly 16 address octets (network order).
/// Err("bonjour: bad AAAA rdata") for any other length. Complexity: O(1).
pub fn bonjour_rdata_aaaa(octets: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  ensures: octets.len() != 16 => result is Err;
  ensures: octets.len() == 16 => result is Ok;
{
  if octets.len() != 16 {
    return _err_bytes("bonjour: bad AAAA rdata");
  }
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, octets);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  RDATA parsers (PTR, SRV, TXT, A, AAAA)
// --------------------------------------------------

/// Render 4-byte A RDATA as "a.b.c.d".
/// Err("bonjour: bad A rdata") when the length is not 4. Complexity: O(1).
pub fn bonjour_rdata_a_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str]
  ensures: rdata.len() != 4 => result is Err;
  ensures: rdata.len() == 4 => result is Ok;
{
  if rdata.len() != 4 {
    return _err_str("bonjour: bad A rdata");
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

/// Render 16-byte AAAA RDATA as full-form lowercase IPv6 (8 groups, no "::"
/// compression). Err("bonjour: bad AAAA rdata") when the length is not 16.
/// Complexity: O(1).
pub fn bonjour_rdata_aaaa_to_str(rdata: &Vec[UInt8]) -> Result[Str, Str] {
  if rdata.len() != 16 {
    return _err_str("bonjour: bad AAAA rdata");
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

/// Decode the name stored in RDATA at [off, off+len): used for PTR targets
/// and SRV hosts. Compression pointers are followed (the encoded name may
/// end in a pointer), but the name's end must fall inside the RDATA span.
/// Errors: Err("bonjour: bad rdata name") when len < 1 or the name ends
/// past off+len; otherwise the bonjour_name_decode catalog.
/// Complexity: O(name bytes).
pub fn bonjour_rdata_name(data: &Vec[UInt8], off: Int, len: Int) -> Result[BonjourName, Str] {
  if len < 1 {
    return _err_name("bonjour: bad rdata name");
  }
  let nr = bonjour_name_decode(data, off);
  if !nr.is_ok {
    return _err_name(nr.error);
  }
  let nm: BonjourName = nr.value;
  if nm.next > off + len {
    return _err_name("bonjour: bad rdata name");
  }
  return _ok_name(nm);
}

/// The PTR target as a presentation string: the name in RDATA [off,
/// off+len) rendered by bonjour_name_to_str.
/// Err("bonjour: bad PTR rdata") when len < 1; otherwise the
/// bonjour_rdata_name catalog (which includes the end-of-span check).
/// Complexity: O(name bytes).
pub fn bonjour_rdata_ptr_target(data: &Vec[UInt8], off: Int, len: Int) -> Result[Str, Str] {
  if len < 1 {
    return _err_str("bonjour: bad PTR rdata");
  }
  let nr = bonjour_rdata_name(data, off, len);
  if !nr.is_ok {
    return _err_str(nr.error);
  }
  let nm: BonjourName = nr.value;
  return _ok_str(bonjour_name_to_str(&nm));
}

/// The 16-bit priority of SRV RDATA at [off, off+len).
/// Err("bonjour: bad SRV rdata") when len < 7 or the field is out of
/// bounds. Complexity: O(1).
pub fn bonjour_rdata_srv_priority(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str]
  ensures: len < 7 => result is Err;
  ensures: off < 0 => result is Err;
  ensures: off + 6 > data.len() => result is Err;
  ensures: result is Ok => len >= 7 && off >= 0 && off + 6 <= data.len();
{
  if len < 7 {
    return _err_int("bonjour: bad SRV rdata");
  }
  if off < 0 || off + 6 > data.len() {
    return _err_int("bonjour: bad SRV rdata");
  }
  return _ok_int(_u16_be_at(data, off));
}

/// The 16-bit weight of SRV RDATA at [off, off+len).
/// Err("bonjour: bad SRV rdata") when len < 7 or the field is out of
/// bounds. Complexity: O(1).
pub fn bonjour_rdata_srv_weight(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str] {
  if len < 7 {
    return _err_int("bonjour: bad SRV rdata");
  }
  if off < 0 || off + 6 > data.len() {
    return _err_int("bonjour: bad SRV rdata");
  }
  return _ok_int(_u16_be_at(data, off + 2));
}

/// The 16-bit port of SRV RDATA at [off, off+len).
/// Err("bonjour: bad SRV rdata") when len < 7 or the field is out of
/// bounds. Complexity: O(1).
pub fn bonjour_rdata_srv_port(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str] {
  if len < 7 {
    return _err_int("bonjour: bad SRV rdata");
  }
  if off < 0 || off + 6 > data.len() {
    return _err_int("bonjour: bad SRV rdata");
  }
  return _ok_int(_u16_be_at(data, off + 4));
}

/// The target host name of SRV RDATA at [off, off+len) (the name after the
/// 6-byte priority/weight/port prefix). Err("bonjour: bad SRV rdata") when
/// len < 7; otherwise the bonjour_rdata_name catalog.
/// Complexity: O(name bytes).
pub fn bonjour_rdata_srv_target(data: &Vec[UInt8], off: Int, len: Int) -> Result[BonjourName, Str] {
  if len < 7 {
    return _err_name("bonjour: bad SRV rdata");
  }
  return bonjour_rdata_name(data, off + 6, len - 6);
}

/// Parse TXT RDATA into its character-strings: each entry is a length byte
/// followed by that many printable bytes; a zero length byte yields "".
/// Errors: Err("bonjour: truncated TXT string") when a declared string runs
/// past the RDATA end; Err("bonjour: TXT byte not printable") for bytes
/// outside 0x20..0x7E. Empty RDATA yields an empty Ok (DNS-SD represents
/// "no attributes" with a single empty string, not an absent RDATA).
/// Complexity: O(RDATA length).
pub fn bonjour_rdata_txt_parse(rdata: &Vec[UInt8]) -> Result[Vec[Str], Str] {
  var list = Vec[Str].new();
  let n = rdata.len();
  var pos = 0;
  while pos < n {
    let slen = _byte(rdata, pos);
    if pos + 1 + slen > n {
      return _err_labels("bonjour: truncated TXT string");
    }
    var sb = builder.sb_new();
    var k = 0;
    while k < slen {
      let b = _byte(rdata, pos + 1 + k);
      if !_is_printable(b) {
        return _err_labels("bonjour: TXT byte not printable");
      }
      sb.push(b as UInt8);
      k = k + 1;
    }
    list.push(builder.sb_to_str(&sb));
    pos = pos + 1 + slen;
  }
  return _ok_labels(list);
}

// --------------------------------------------------
//  TXT key=value helpers
// --------------------------------------------------

/// Build one TXT string from a key and value: "key=value", or just "key"
/// when `value` is empty (the DNS-SD boolean-attribute form).
/// Errors: Err("bonjour: empty TXT key") for an empty key;
/// Err("bonjour: TXT key contains '='") when the key itself holds '=';
/// Err("bonjour: TXT byte not printable") for bytes outside 0x20..0x7E in
/// either part. The result may still exceed 255 bytes; bonjour_rdata_txt
/// enforces that limit.
/// Complexity: O(key + value bytes).
pub fn bonjour_txt_pair(key: Str, value: Str) -> Result[Str, Str]
  ensures: key.len() == 0 => result is Err;
  ensures: result is Ok => key.len() > 0;
{
  let klen = key.len();
  if klen == 0 {
    return _err_str("bonjour: empty TXT key");
  }
  var i = 0;
  while i < klen {
    let b = _byte_str(key, i);
    if b == 61 {
      return _err_str("bonjour: TXT key contains '='");
    }
    if !_is_printable(b) {
      return _err_str("bonjour: TXT byte not printable");
    }
    i = i + 1;
  }
  let vlen = value.len();
  i = 0;
  while i < vlen {
    let b = _byte_str(value, i);
    if !_is_printable(b) {
      return _err_str("bonjour: TXT byte not printable");
    }
    i = i + 1;
  }
  if vlen == 0 {
    return _ok_str(key);
  }
  return _ok_str(key + "=" + value);
}

/// Look up `key` in a parsed TXT list and return its value. A pair
/// "key=value" matches on the part before the first '='; a bare "key"
/// matches with value "". Err("bonjour: TXT key not found") when no pair
/// matches. Complexity: O(total TXT bytes).
pub fn bonjour_txt_get(pairs: &Vec[Str], key: Str) -> Result[Str, Str] {
  var i = 0;
  while i < pairs.len() {
    let p: Str = pairs[i];
    let plen = p.len();
    var eq = -1;
    var k = 0;
    while k < plen && eq < 0 {
      if _byte_str(p, k) == 61 {
        eq = k;
      }
      k = k + 1;
    }
    if eq < 0 {
      if compare.str_compare(p, key) == 0 {
        return _ok_str("");
      }
    } else {
      let pkey = string.str_slice(p, 0, eq);
      if compare.str_compare(pkey, key) == 0 {
        return _ok_str(string.str_slice(p, eq + 1, plen));
      }
    }
    i = i + 1;
  }
  return _err_str("bonjour: TXT key not found");
}

// --------------------------------------------------
//  DNS-SD names
// --------------------------------------------------

/// The DNS-SD service enumeration name: "_services._dns-sd._udp.local".
/// Complexity: O(1).
pub fn bonjour_service_enum_name() -> Str
  ensures: result.len() == 28;
{
  return BONJOUR_ENUM_PREFIX + BONJOUR_DOMAIN;
}

/// True when `name` is in the mDNS `local` domain: exactly "local", or any
/// name ending in ".local" (ASCII case-insensitive, no trailing dot).
/// Complexity: O(name length).
pub fn bonjour_is_local_name(name: Str) -> Bool
  ensures: name.len() == 0 => !result;
  ensures: name.len() >= 1 && name.len() <= 4 => !result;
  ensures: name.len() == 6 => !result;
  ensures: result => name.len() >= 5 && name.len() != 6;
{
  let n = name.len();
  if n == 0 {
    return false;
  }
  let lower = string.str_lower(name);
  if n == 5 {
    return compare.str_compare(lower, BONJOUR_DOMAIN) == 0;
  }
  if n > 6 {
    let tail = string.str_slice(lower, n - 6, n);
    return compare.str_compare(tail, ".local") == 0;
  }
  return false;
}

/// `name` when it is a local name, else Err("bonjour: not a local domain").
/// Complexity: O(name length).
pub fn bonjour_check_local_name(name: Str) -> Result[Str, Str] {
  if bonjour_is_local_name(name) {
    return _ok_str(name);
  }
  return _err_str("bonjour: not a local domain");
}

// Strip one leading '_' when present (service and subtype inputs may be
// given with or without it).
fn _strip_underscore(s: Str) -> Str {
  let n = s.len();
  if n == 0 {
    return s;
  }
  if _byte_str(s, 0) == 95 {
    return string.str_slice(s, 1, n);
  }
  return s;
}

// True when `s` is a non-empty printable label fragment without '.'.
fn _valid_label_text(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    let b = _byte_str(s, i);
    if b == 46 {
      return false;
    }
    if !_is_printable(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Build a DNS-SD service type name: "_<service>.<proto>.<domain>", e.g.
/// bonjour_service_type("http", "_tcp", "local") -> "_http._tcp.local".
/// `service` may be given with or without a leading '_'; `proto` must be
/// "tcp" or "udp" (case-insensitive, leading '_' optional); `domain` must
/// be a local name.
/// Errors: Err("bonjour: empty service"), Err("bonjour: service contains
/// '.'"), Err("bonjour: service not printable"), Err("bonjour: bad service
/// protocol"), Err("bonjour: not a local domain").
/// Complexity: O(input length).
pub fn bonjour_service_type(service: Str, proto: Str, domain: Str) -> Result[Str, Str] {
  let s = _strip_underscore(service);
  if s.len() == 0 {
    return _err_str("bonjour: empty service");
  }
  var i = 0;
  while i < s.len() {
    let b = _byte_str(s, i);
    if b == 46 {
      return _err_str("bonjour: service contains '.'");
    }
    if !_is_printable(b) {
      return _err_str("bonjour: service not printable");
    }
    i = i + 1;
  }
  let p = _strip_underscore(proto);
  var pout = "";
  if compare.str_compare_ignore_case(p, "tcp") == 0 {
    pout = "_tcp";
  } elif compare.str_compare_ignore_case(p, "udp") == 0 {
    pout = "_udp";
  } else {
    return _err_str("bonjour: bad service protocol");
  }
  if !bonjour_is_local_name(domain) {
    return _err_str("bonjour: not a local domain");
  }
  return _ok_str("_" + s + "." + pout + "." + domain);
}

/// Build a service type name in the `local` domain:
/// bonjour_service_type(service, proto, BONJOUR_DOMAIN).
/// Complexity: O(input length).
pub fn bonjour_service_type_name(service: Str, proto: Str) -> Result[Str, Str] {
  return bonjour_service_type(service, proto, BONJOUR_DOMAIN);
}

/// Build a service instance name: "<instance>.<service_type>", e.g.
/// bonjour_instance_name("Office", "_http._tcp.local") ->
/// "Office._http._tcp.local". The instance is a single label; the service
/// type must be a local name.
/// Errors: Err("bonjour: empty instance"), Err("bonjour: instance contains
/// '.'"), Err("bonjour: instance not printable"), Err("bonjour: not a local
/// domain").
/// Complexity: O(input length).
pub fn bonjour_instance_name(instance: Str, service_type: Str) -> Result[Str, Str] {
  if !_valid_label_text(instance) {
    if instance.len() == 0 {
      return _err_str("bonjour: empty instance");
    }
    var i = 0;
    while i < instance.len() {
      if _byte_str(instance, i) == 46 {
        return _err_str("bonjour: instance contains '.'");
      }
      i = i + 1;
    }
    return _err_str("bonjour: instance not printable");
  }
  if !bonjour_is_local_name(service_type) {
    return _err_str("bonjour: not a local domain");
  }
  return _ok_str(instance + "." + service_type);
}

/// Build a DNS-SD subtype name: "_<subtype>._sub.<service_type>", e.g.
/// bonjour_subtype_name("printer", "_http._tcp.local") ->
/// "_printer._sub._http._tcp.local". The subtype may be given with or
/// without a leading '_' and is a single label; the service type must be a
/// local name.
/// Errors: Err("bonjour: empty subtype"), Err("bonjour: subtype contains
/// '.'"), Err("bonjour: subtype not printable"), Err("bonjour: not a local
/// domain").
/// Complexity: O(input length).
pub fn bonjour_subtype_name(subtype: Str, service_type: Str) -> Result[Str, Str] {
  let s = _strip_underscore(subtype);
  if s.len() == 0 {
    return _err_str("bonjour: empty subtype");
  }
  if !_valid_label_text(s) {
    var i = 0;
    while i < s.len() {
      if _byte_str(s, i) == 46 {
        return _err_str("bonjour: subtype contains '.'");
      }
      i = i + 1;
    }
    return _err_str("bonjour: subtype not printable");
  }
  if !bonjour_is_local_name(service_type) {
    return _err_str("bonjour: not a local domain");
  }
  return _ok_str("_" + s + "._sub." + service_type);
}

/// Build the PTR RDATA used by the service enumeration record: a PTR whose
/// target is `service_type` (which must be a local name).
/// Errors: Err("bonjour: not a local domain") plus the bonjour_rdata_ptr
/// catalog. Complexity: O(name length).
pub fn bonjour_enum_rdata(service_type: Str) -> Result[Vec[UInt8], Str] {
  if !bonjour_is_local_name(service_type) {
    return _err_bytes("bonjour: not a local domain");
  }
  return bonjour_rdata_ptr(service_type);
}

// --------------------------------------------------
//  Message builders (query, browse, advertise)
// --------------------------------------------------

/// Build a one-question mDNS query: a 12-byte header (ID=0, QR=0, Opcode=0,
/// AA=TC=RA=Z=RCODE=0, RD=1 when `unicast` else 0, QDCOUNT=1, AN=NS=AR=0)
/// followed by the question with the given QTYPE and class IN plus the QU
/// bit when `unicast`.
/// Name errors propagate unchanged. Complexity: O(name length).
pub fn bonjour_query_name(name: Str, qtype: Int, unicast: Bool) -> Result[Vec[UInt8], Str] {
  let qr = bonjour_question_encode(name, qtype, bonjour_class_value(unicast));
  if !qr.is_ok {
    return _err_bytes(qr.error);
  }
  let qb: Vec[UInt8] = qr.value;
  var rdv = 0;
  if unicast {
    rdv = 1;
  }
  let h = BonjourHeader{
    id: 0;
    qr: 0;
    opcode: 0;
    aa: 0;
    tc: 0;
    rd: rdv;
    ra: 0;
    z: 0;
    rcode: 0;
    qdcount: 1;
    ancount: 0;
    nscount: 0;
    arcount: 0;
  };
  let hb = bonjour_header_encode(&h);
  return _ok_bytes(_concat(hb, qb));
}

/// Build a PTR browse query for a service type (e.g. "_http._tcp.local").
/// Err("bonjour: not a local domain") when the type is not local; name
/// errors propagate. Complexity: O(name length).
pub fn bonjour_service_query(service_type: Str, unicast: Bool) -> Result[Vec[UInt8], Str] {
  if !bonjour_is_local_name(service_type) {
    return _err_bytes("bonjour: not a local domain");
  }
  return bonjour_query_name(service_type, BONJOUR_TYPE_PTR, unicast);
}

/// Build an SRV query for a service instance name (e.g.
/// "Office._http._tcp.local"). Err("bonjour: not a local domain") when the
/// name is not local; name errors propagate. Complexity: O(name length).
pub fn bonjour_instance_query(instance_name: Str, unicast: Bool) -> Result[Vec[UInt8], Str] {
  if !bonjour_is_local_name(instance_name) {
    return _err_bytes("bonjour: not a local domain");
  }
  return bonjour_query_name(instance_name, BONJOUR_TYPE_SRV, unicast);
}

/// Build the DNS-SD service enumeration query: PTR for
/// "_services._dns-sd._udp.<domain>". Err("bonjour: not a local domain")
/// when the domain is not local. Complexity: O(name length).
pub fn bonjour_enum_query(domain: Str) -> Result[Vec[UInt8], Str] {
  if !bonjour_is_local_name(domain) {
    return _err_bytes("bonjour: not a local domain");
  }
  let name = BONJOUR_ENUM_PREFIX + domain;
  return bonjour_query_name(name, BONJOUR_TYPE_PTR, false);
}

/// Build a PTR record: owner `owner` points at `target`, with `ttl` and the
/// cache-flush bit per `flush` (PTR records are normally shared, so pass
/// flush = false; a goodbye record is a PTR with ttl 0).
/// Errors propagate from the name and RDATA builders.
/// Complexity: O(owner + target length).
pub fn bonjour_ptr_record(owner: Str, target: Str, ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str] {
  let rr = bonjour_rdata_ptr(target);
  if !rr.is_ok {
    return _err_bytes(rr.error);
  }
  let rd: Vec[UInt8] = rr.value;
  return bonjour_rr_encode(owner, BONJOUR_TYPE_PTR, bonjour_class_value(flush), ttl, &rd);
}

/// Build an SRV record: owner `instance`, priority/weight/port (masked to
/// 16 bits) and target host, with `ttl` and the cache-flush bit per
/// `flush` (SRV is unique to an instance, so flush = true is valid).
/// Errors propagate from the name and RDATA builders.
/// Complexity: O(owner + host length).
pub fn bonjour_srv_record(instance: Str, priority: Int, weight: Int, port: Int, host: Str, ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str] {
  let rr = bonjour_rdata_srv(priority, weight, port, host);
  if !rr.is_ok {
    return _err_bytes(rr.error);
  }
  let rd: Vec[UInt8] = rr.value;
  return bonjour_rr_encode(instance, BONJOUR_TYPE_SRV, bonjour_class_value(flush), ttl, &rd);
}

/// Build a TXT record: owner `instance`, RDATA from the key=value strings
/// per `pairs`, `ttl` and the cache-flush bit per `flush` (TXT is unique to
/// an instance, so flush = true is valid; pass an empty list for no
/// attributes).
/// Errors propagate from the name and RDATA builders.
/// Complexity: O(owner length + total TXT bytes).
pub fn bonjour_txt_record(instance: Str, pairs: &Vec[Str], ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str] {
  let rr = bonjour_rdata_txt(pairs);
  if !rr.is_ok {
    return _err_bytes(rr.error);
  }
  let rd: Vec[UInt8] = rr.value;
  return bonjour_rr_encode(instance, BONJOUR_TYPE_TXT, bonjour_class_value(flush), ttl, &rd);
}

/// Build an A record: owner `owner`, 4 address octets, `ttl` and the
/// cache-flush bit per `flush` (host address records use flush = true).
/// Errors propagate from the name and RDATA builders.
/// Complexity: O(owner length).
pub fn bonjour_a_record(owner: Str, octets: &Vec[UInt8], ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str] {
  let rr = bonjour_rdata_a(octets);
  if !rr.is_ok {
    return _err_bytes(rr.error);
  }
  let rd: Vec[UInt8] = rr.value;
  return bonjour_rr_encode(owner, BONJOUR_TYPE_A, bonjour_class_value(flush), ttl, &rd);
}

/// Build an AAAA record: owner `owner`, 16 address octets, `ttl` and the
/// cache-flush bit per `flush`. Errors propagate from the name and RDATA
/// builders. Complexity: O(owner length).
pub fn bonjour_aaaa_record(owner: Str, octets: &Vec[UInt8], ttl: Int, flush: Bool) -> Result[Vec[UInt8], Str] {
  let rr = bonjour_rdata_aaaa(octets);
  if !rr.is_ok {
    return _err_bytes(rr.error);
  }
  let rd: Vec[UInt8] = rr.value;
  return bonjour_rr_encode(owner, BONJOUR_TYPE_AAAA, bonjour_class_value(flush), ttl, &rd);
}

/// Build a goodbye PTR record: the same service PTR with TTL 0 (RFC 6762
/// section 10.1). Complexity: O(owner + target length).
pub fn bonjour_goodbye_ptr(owner: Str, target: Str) -> Result[Vec[UInt8], Str] {
  return bonjour_ptr_record(owner, target, 0, false);
}

/// Build the DNS-SD advertise response for one service instance: a header
/// with ANCOUNT = 3 followed by three answer records in this order:
///   1. PTR  service_type -> instance   (TTL 4500, no flush)
///   2. SRV  instance -> host:port      (TTL 4500, flush)
///   3. TXT  instance -> pairs          (TTL 4500, flush)
/// `instance`, `service_type` and `host` must be local names; names are
/// emitted uncompressed. Errors: Err("bonjour: not a local domain") for a
/// non-local name, otherwise the record builders' catalogs.
/// Complexity: O(instance + type + host length + TXT bytes).
pub fn bonjour_advertise(instance: Str, service_type: Str, port: Int, host: Str, pairs: &Vec[Str]) -> Result[Vec[UInt8], Str] {
  if !bonjour_is_local_name(instance) {
    return _err_bytes("bonjour: not a local domain");
  }
  if !bonjour_is_local_name(service_type) {
    return _err_bytes("bonjour: not a local domain");
  }
  if !bonjour_is_local_name(host) {
    return _err_bytes("bonjour: not a local domain");
  }
  let pr = bonjour_ptr_record(service_type, instance, BONJOUR_TTL_SERVICE, false);
  if !pr.is_ok {
    return _err_bytes(pr.error);
  }
  let b1: Vec[UInt8] = pr.value;
  let sr = bonjour_srv_record(instance, 0, 0, port, host, BONJOUR_TTL_SERVICE, true);
  if !sr.is_ok {
    return _err_bytes(sr.error);
  }
  let b2: Vec[UInt8] = sr.value;
  let tr = bonjour_txt_record(instance, pairs, BONJOUR_TTL_SERVICE, true);
  if !tr.is_ok {
    return _err_bytes(tr.error);
  }
  let b3: Vec[UInt8] = tr.value;
  let h = BonjourHeader{
    id: 0;
    qr: 1;
    opcode: 0;
    aa: 1;
    tc: 0;
    rd: 0;
    ra: 0;
    z: 0;
    rcode: 0;
    qdcount: 0;
    ancount: 3;
    nscount: 0;
    arcount: 0;
  };
  let hb = bonjour_header_encode(&h);
  var body = _concat(hb, b1);
  body = _concat(body, b2);
  body = _concat(body, b3);
  return _ok_bytes(body);
}

// --------------------------------------------------
//  Whole messages
// --------------------------------------------------

/// Parse a whole mDNS message: the header, then QDCOUNT questions, then
/// ANCOUNT + NSCOUNT + ARCOUNT resource records, in order. Names are
/// decoded only far enough to find every section boundary; their offsets
/// are recorded in the BonjourMessage index and the entries themselves are
/// read with bonjour_question_parse / bonjour_rr_parse at those offsets.
///
/// Errors: the bonjour_header_decode catalog ("bonjour: truncated header");
/// Err("bonjour: truncated question") / Err("bonjour: truncated record")
/// when a declared entry has no bytes left; otherwise the name and record
/// errors propagate unchanged. Bytes after the last declared entry are
/// ignored. Complexity: O(message length).
pub fn bonjour_message_parse(data: &Vec[UInt8]) -> Result[BonjourMessage, Str]
  ensures: data.len() < 12 => result is Err;
  ensures: result is Ok => data.len() >= 12;
{
  let hr = bonjour_header_decode(data);
  if !hr.is_ok {
    return _err_message(hr.error);
  }
  let h: BonjourHeader = hr.value;
  let total = data.len();
  var q_offsets = Vec[Int].new();
  var r_offsets = Vec[Int].new();
  var pos = 12;
  var i = 0;
  while i < h.qdcount {
    if pos >= total {
      return _err_message("bonjour: truncated question");
    }
    let qr = bonjour_question_parse(data, pos);
    if !qr.is_ok {
      return _err_message(qr.error);
    }
    let q: BonjourQuestion = qr.value;
    q_offsets.push(pos);
    pos = q.next;
    i = i + 1;
  }
  let records = h.ancount + h.nscount + h.arcount;
  i = 0;
  while i < records {
    if pos >= total {
      return _err_message("bonjour: truncated record");
    }
    let rr = bonjour_rr_parse(data, pos);
    if !rr.is_ok {
      return _err_message(rr.error);
    }
    let r: BonjourRecord = rr.value;
    r_offsets.push(pos);
    pos = r.next;
    i = i + 1;
  }
  let m = BonjourMessage{ header: h; question_offsets: q_offsets; record_offsets: r_offsets; };
  return _ok_message(m);
}

/// Number of parsed questions in the index. Complexity: O(1).
pub fn bonjour_message_question_count(m: &BonjourMessage) -> Int {
  return m.question_offsets.len();
}

/// Number of parsed resource records in the index (answers, authority and
/// additional together). Complexity: O(1).
pub fn bonjour_message_record_count(m: &BonjourMessage) -> Int {
  return m.record_offsets.len();
}

/// Absolute offset of the i-th question's name in the parse buffer, or -1
/// when i is negative or >= bonjour_message_question_count(m).
/// Complexity: O(1).
pub fn bonjour_message_question_offset(m: &BonjourMessage, i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= m.question_offsets.len() => result == -1;
  ensures: result != -1 => i >= 0 && i < m.question_offsets.len();
{
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
/// or -1 when i is negative or >= bonjour_message_record_count(m).
/// Complexity: O(1).
pub fn bonjour_message_record_offset(m: &BonjourMessage, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.record_offsets.len() {
    return -1;
  }
  let off: Int = m.record_offsets[i];
  return off;
}
