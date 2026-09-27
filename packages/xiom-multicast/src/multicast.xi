// XIOM -- xiom.multicast: IGMPv2/v3 and MLD/MLDv2 group management codecs
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codecs for the multicast group-management protocols:
//
//   * IGMPv1/v2 (RFC 1112 / RFC 2236): the 8-byte membership query (0x11),
//     v1 report (0x12), v2 report (0x16) and leave (0x17) messages;
//   * IGMPv3 (RFC 3376): the membership query with the Resv/S/QRV/QQIC
//     suffix and source list, and the v3 membership report (0x22) with
//     group records of types 1..6, per-record source lists and auxiliary
//     data;
//   * MLD (RFC 2710, ICMPv6 types 130/131/132) and MLDv2 (RFC 3810): the
//     same query/report shapes over 128-bit IPv6 addresses, with the MLDv2
//     query suffix (still type 130, distinguished by length) and the type
//     143 version 2 report;
//   * one's-complement checksums: the IGMP checksum over the whole message
//     and the ICMPv6 checksum over the IPv6 pseudo-header plus the message
//     (required by every MLD message).
//
// Source lists and group records stay in the source buffer and are located
// by absolute byte offsets, following the xiom.dhcp / xiom.stun precedent;
// the accessors copy addresses and auxiliary data out on demand.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by value or
//     reference.
//   * Ok/Err are constructed only in the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(b as Int) & 0xFF`; multi-byte fields are packed arithmetically
//     (no bitwise operator on high-bit operands).
//   * Vec[Int] element reads are bound to typed locals before use; this
//     module has no Str fields and never compares a Str with `==`.
//   * `&struct.field` is never passed directly as a `&Vec[UInt8]`
//     parameter; a local copy is bound first.
//   * parallel record vectors are pushed together and every accessor
//     guards each vector's length before reading (mirror-push discipline).
// See SPEC.md for the byte layout tables, error catalog and test matrix.

module xiom.multicast

use xiom.convert;

// --------------------------------------------------
//  Protocol constants
// --------------------------------------------------

/// IGMP Membership Query (0x11). Also carries every IGMPv3 query.
pub const IGMP_TYPE_QUERY: Int = 17;

/// IGMPv1 Membership Report (0x12).
pub const IGMP_TYPE_V1_REPORT: Int = 18;

/// IGMPv2 Membership Report (0x16).
pub const IGMP_TYPE_V2_REPORT: Int = 22;

/// IGMPv2 Leave Group (0x17).
pub const IGMP_TYPE_LEAVE: Int = 23;

/// IGMPv3 Membership Report (0x22).
pub const IGMP_TYPE_V3_REPORT: Int = 34;

/// Size of the fixed IGMPv1/v2 message (query, report or leave).
pub const IGMP_QUERY_SIZE: Int = 8;

/// Fixed size of an IGMPv3 query before the source list.
pub const IGMP_V3_QUERY_FIXED: Int = 12;

/// Fixed size of an IGMPv3 report before the group records.
pub const IGMP_V3_REPORT_FIXED: Int = 8;

/// Fixed size of an IGMPv3 group record before sources and auxiliary data.
pub const IGMP_RECORD_FIXED: Int = 8;

/// IGMPv3 record type 1: MODE_IS_INCLUDE.
pub const IGMP_RECORD_MODE_IS_INCLUDE: Int = 1;

/// IGMPv3 record type 2: MODE_IS_EXCLUDE.
pub const IGMP_RECORD_MODE_IS_EXCLUDE: Int = 2;

/// IGMPv3 record type 3: CHANGE_TO_INCLUDE_MODE.
pub const IGMP_RECORD_CHANGE_TO_INCLUDE: Int = 3;

/// IGMPv3 record type 4: CHANGE_TO_EXCLUDE_MODE.
pub const IGMP_RECORD_CHANGE_TO_EXCLUDE: Int = 4;

/// IGMPv3 record type 5: ALLOW_NEW_SOURCES.
pub const IGMP_RECORD_ALLOW_NEW_SOURCES: Int = 5;

/// IGMPv3 record type 6: BLOCK_OLD_SOURCES.
pub const IGMP_RECORD_BLOCK_OLD_SOURCES: Int = 6;

/// Default Max Resp Code of a query: 100 tenths of a second (10 s).
pub const IGMP_DEFAULT_MAX_RESP: Int = 100;

/// Default Querier's Robustness Variable when QRV is 0 (RFC 3376).
pub const IGMP_QRV_DEFAULT: Int = 2;

/// First address of 224.0.0.0/4, the IPv4 multicast block.
pub const IGMP_MULTICAST_BASE: Int = 3758096384;

/// Last address of 224.0.0.0/4.
pub const IGMP_MULTICAST_TOP: Int = 4026531839;

/// MLD Multicast Listener Query (ICMPv6 type 130).
pub const MLD_TYPE_QUERY: Int = 130;

/// MLD Multicast Listener Report (ICMPv6 type 131).
pub const MLD_TYPE_REPORT: Int = 131;

/// MLD Multicast Listener Done (ICMPv6 type 132).
pub const MLD_TYPE_DONE: Int = 132;

/// MLDv2 Version 2 Multicast Listener Report (ICMPv6 type 143).
pub const MLD_TYPE_V2_REPORT: Int = 143;

/// Size of every MLDv1 message (query, report or done).
pub const MLD_V1_SIZE: Int = 24;

/// Fixed size of an MLDv2 query before the source list.
pub const MLD_V2_QUERY_FIXED: Int = 28;

/// Fixed size of an MLDv2 report before the address records.
pub const MLD_V2_REPORT_FIXED: Int = 8;

/// Fixed size of an MLDv2 address record before sources and auxiliary data.
pub const MLD_RECORD_FIXED: Int = 20;

/// Size of an MLD IPv6 address in bytes.
pub const MLD_ADDRESS_SIZE: Int = 16;

/// ICMPv6 Next Header value used in the IPv6 pseudo-header.
pub const ICMPV6_NEXT_HEADER: Int = 58;

/// Default Max Response Code of an MLDv2 query: 10000 ms (10 s).
pub const MLD_DEFAULT_MAX_RESP: Int = 10000;

/// MLDv2 Max Response Code values below this are plain milliseconds.
pub const MLD_MAX_RESP_THRESHOLD: Int = 32768;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed IGMP message.
///
/// `msg_type` is the raw type byte, `version` is the protocol version this
/// module assigns to it (1: query with Max Resp Code 0, or the 0x12 report;
/// 2: the remaining 8-byte messages; 3: anything carrying the v3 suffix or
/// record structure). `max_resp` is the raw Max Resp Code/Time octet and
/// `group` the 32-bit group address as an unsigned Int (0 when the message
/// has no single group). `checksum` is the wire value and `checksum_ok`
/// the IGMP checksum verdict computed during parse.
///
/// For a v3 query, `suppress`, `qrv` (raw 0..7), `qqic` (raw octet),
/// `source_count` and `source_offset` (absolute offset of the first source
/// address, -1 when absent) describe the suffix and source list.
///
/// For a v3 report, the six `rec_*` vectors are parallel, one entry per
/// group record in wire order: record type, group address, source count,
/// absolute offset of the first source address, auxiliary data length in
/// 32-bit words and absolute offset of the auxiliary data. Fields are
/// implementation details; callers should use the free functions below.
pub type IgmpMessage = {
  msg_type: Int;
  version: Int;
  max_resp: Int;
  checksum: Int;
  checksum_ok: Bool;
  group: Int;
  suppress: Bool;
  qrv: Int;
  qqic: Int;
  source_count: Int;
  source_offset: Int;
  rec_types: Vec[Int];
  rec_groups: Vec[Int];
  rec_source_counts: Vec[Int];
  rec_source_offsets: Vec[Int];
  rec_aux_words: Vec[Int];
  rec_aux_offsets: Vec[Int];
}

/// A parsed MLD or MLDv2 message.
///
/// `msg_type` is the ICMPv6 type (130/131/132/143) and `version` is 1 or 2
/// (a type 130 message is version 2 when it carries the MLDv2 query
/// suffix). `max_delay` is the 32-bit Maximum Response Delay of the MLDv1
/// messages; `max_resp` and `reserved` are the 16-bit fields of an MLDv2
/// query. `group` holds the 16-byte multicast address of the query/report
/// messages (all zeroes = general query) and is empty for a type 143
/// report. `suppress`, `qrv`, `qqic`, `source_count` and `source_offset`
/// (absolute offset of the first 16-byte source address, -1 when absent)
/// describe the MLDv2 query suffix.
///
/// For a type 143 report the six `rec_*` vectors are parallel, one entry
/// per address record in wire order: record type, source count, absolute
/// offset of the 16-byte group address, absolute offset of the first
/// 16-byte source address, auxiliary data length in 32-bit words and
/// absolute offset of the auxiliary data. Fields are implementation
/// details; callers should use the free functions below.
pub type MldMessage = {
  msg_type: Int;
  version: Int;
  code: Int;
  checksum: Int;
  max_delay: Int;
  max_resp: Int;
  reserved: Int;
  suppress: Bool;
  qrv: Int;
  qqic: Int;
  source_count: Int;
  source_offset: Int;
  group: Vec[UInt8];
  rec_types: Vec[Int];
  rec_source_counts: Vec[Int];
  rec_group_offsets: Vec[Int];
  rec_source_offsets: Vec[Int];
  rec_aux_words: Vec[Int];
  rec_aux_offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[IgmpMessage, Str].
fn _ok_igmp(v: IgmpMessage) -> Result[IgmpMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[IgmpMessage, Str].
fn _err_igmp(m: Str) -> Result[IgmpMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[MldMessage, Str].
fn _ok_mld(v: MldMessage) -> Result[MldMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[MldMessage, Str].
fn _err_mld(m: Str) -> Result[MldMessage, Str] {
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

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); the caller guarantees the
// bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit big-endian integer at [pos, pos+2).
fn _u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned 32-bit big-endian integer at [pos, pos+4), returned in an Int
// (0..4294967295).
fn _u32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte),
// arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3 and this form is exact for the unsigned values this module
// packs.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append every byte of `v`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Copy `len` bytes of `data` starting at `off` (the caller guarantees the
// span is in bounds).
fn _copy_range(data: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(data[off + i]);
    i = i + 1;
  }
  return out;
}

// A fresh empty Int vector (used for the record vectors of messages that
// carry none).
fn _no_ints() -> Vec[Int] {
  return Vec[Int].new();
}

// A fresh empty byte vector.
fn _no_bytes() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

// True when `a` is exactly one IPv6 address long.
fn _addr16_ok(a: &Vec[UInt8]) -> Bool {
  return a.len() == MLD_ADDRESS_SIZE;
}

// True when `a` is a legal unsigned 32-bit IPv4 address value.
fn _addr32_ok(a: Int) -> Bool {
  return a >= 0 && a <= 4294967295;
}

// Word of a value: 2 ^ e computed by repeated doubling (no shifts, so the
// high-bit and mask traps never apply).
fn _pow2(e: Int) -> Int {
  var out = 1;
  var i = 0;
  while i < e {
    out = out * 2;
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  One's-complement checksums
// --------------------------------------------------

// Sum of the 16-bit big-endian words of `data` (a trailing odd byte is
// padded on the right with zero), added to `sum` without folding.
fn _sum_bytes(sum: Int, data: &Vec[UInt8]) -> Int {
  var s = sum;
  var i = 0;
  while i + 1 < data.len() {
    s = s + _byte(data, i) * 256 + _byte(data, i + 1);
    i = i + 2;
  }
  if i < data.len() {
    s = s + _byte(data, i) * 256;
  }
  return s;
}

// Fold an accumulator into 0..65535 with end-around carries.
fn _fold16(v: Int) -> Int {
  var s = v;
  while s > 65535 {
    s = s % 65536 + s / 65536;
  }
  return s;
}

// One's-complement sum of the IPv6 pseudo-header (source, destination,
// upper-layer length and next header 58) plus `data`.
fn _icmpv6_terms(src: &Vec[UInt8], dst: &Vec[UInt8], data: &Vec[UInt8]) -> Int {
  var s = _sum_bytes(0, src);
  s = _sum_bytes(s, dst);
  s = s + data.len() + ICMPV6_NEXT_HEADER;
  return _sum_bytes(s, data);
}

/// IGMP checksum of `data`: the one's-complement of the one's-complement
/// sum of all 16-bit big-endian words, a trailing odd byte padded on the
/// right with zero. Pass the message with its checksum field zeroed to
/// obtain the value to write. Complexity: O(data.len()).
pub fn igmp_checksum(data: &Vec[UInt8]) -> Int {
  return 65535 - _fold16(_sum_bytes(0, data));
}

/// True when the IGMP checksum of the complete message (checksum field
/// included) is valid, i.e. the folded sum is 0xFFFF.
/// Complexity: O(data.len()).
pub fn igmp_checksum_valid(data: &Vec[UInt8]) -> Bool {
  return _fold16(_sum_bytes(0, data)) == 65535;
}

/// ICMPv6 checksum of `data` against the IPv6 pseudo-header built from the
/// 16-byte source and destination addresses: source || destination ||
/// upper-layer length (32-bit) || zero zero zero || next header 58, then
/// the message itself. Returns -1 when either address is not 16 bytes.
/// Pass the message with its checksum field zeroed to obtain the value to
/// write. Complexity: O(src.len() + dst.len() + data.len()).
pub fn icmpv6_checksum(src: &Vec[UInt8], dst: &Vec[UInt8], data: &Vec[UInt8]) -> Int {
  if !_addr16_ok(src) {
    return -1;
  }
  if !_addr16_ok(dst) {
    return -1;
  }
  return 65535 - _fold16(_icmpv6_terms(src, dst, data));
}

/// True when the ICMPv6 checksum of the complete message (checksum field
/// included) is valid; false when either address is not 16 bytes.
/// Complexity: O(src.len() + dst.len() + data.len()).
pub fn icmpv6_checksum_valid(src: &Vec[UInt8], dst: &Vec[UInt8], data: &Vec[UInt8]) -> Bool {
  if !_addr16_ok(src) {
    return false;
  }
  if !_addr16_ok(dst) {
    return false;
  }
  return _fold16(_icmpv6_terms(src, dst, data)) == 65535;
}

// Rebuild `body` (zero checksum bytes at 2..3) with the IGMP checksum
// written into those bytes. Positional rebuild, no index assignment.
fn _with_igmp_checksum(body: &Vec[UInt8]) -> Vec[UInt8] {
  let cs = igmp_checksum(body);
  var out = Vec[UInt8].new();
  out.push(body[0]);
  out.push(body[1]);
  out.push((cs / 256) as UInt8);
  out.push((cs % 256) as UInt8);
  var i = 4;
  while i < body.len() {
    out.push(body[i]);
    i = i + 1;
  }
  return out;
}

// Rebuild `body` (zero checksum bytes at 2..3) with the ICMPv6 checksum of
// the pseudo-header (src, dst) plus body written into those bytes.
fn _with_icmpv6_checksum(body: &Vec[UInt8], src: &Vec[UInt8], dst: &Vec[UInt8]) -> Vec[UInt8] {
  let cs = icmpv6_checksum(src, dst, body);
  var out = Vec[UInt8].new();
  out.push(body[0]);
  out.push(body[1]);
  out.push((cs / 256) as UInt8);
  out.push((cs % 256) as UInt8);
  var i = 4;
  while i < body.len() {
    out.push(body[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Code-value decoding (RFC 3376 / RFC 3810)
// --------------------------------------------------

/// Decode an IGMP Max Resp Code octet to milliseconds: values below 128
/// are tenths of a second, larger values use the floating encoding
/// `(mant | 0x10) << (exp + 3)`. Returns -1 when `code` is outside 0..255.
/// Complexity: O(1).
pub fn igmp_max_resp_ms(code: Int) -> Int {
  if code < 0 || code > 255 {
    return -1;
  }
  if code < 128 {
    return code * 100;
  }
  let mant = code % 16;
  let exp = (code / 16) % 8;
  return (mant + 16) * _pow2(exp + 3) * 100;
}

/// Decode an IGMP/MLD QQIC octet to seconds: values below 128 are plain
/// seconds, larger values use the floating encoding
/// `(mant | 0x10) << (exp + 3)`. Returns -1 when `code` is outside 0..255.
/// Complexity: O(1).
pub fn igmp_qqic_seconds(code: Int) -> Int {
  if code < 0 || code > 255 {
    return -1;
  }
  if code < 128 {
    return code;
  }
  let mant = code % 16;
  let exp = (code / 16) % 8;
  return (mant + 16) * _pow2(exp + 3);
}

/// Decode an MLDv2 Max Response Code (16-bit) to milliseconds: values
/// below 32768 are plain milliseconds, larger values use the floating
/// encoding `(mant | 0x1000) << (exp + 3)`. Returns -1 when `code` is
/// outside 0..65535. Complexity: O(1).
pub fn mld_max_resp_ms(code: Int) -> Int {
  if code < 0 || code > 65535 {
    return -1;
  }
  if code < MLD_MAX_RESP_THRESHOLD {
    return code;
  }
  let mant = code % 4096;
  let exp = (code / 4096) % 8;
  return (mant + 4096) * _pow2(exp + 3);
}

/// Effective Querier's Robustness Variable: the raw QRV, or the RFC 3376
/// default 2 when the raw value is 0. Complexity: O(1).
pub fn igmp_qrv_effective(raw_qrv: Int) -> Int {
  if raw_qrv == 0 {
    return IGMP_QRV_DEFAULT;
  }
  return raw_qrv;
}

/// True when `addr` (an unsigned 32-bit Int) is inside 224.0.0.0/4.
/// Complexity: O(1).
pub fn igmp_is_multicast(addr: Int) -> Bool {
  return addr >= IGMP_MULTICAST_BASE && addr <= IGMP_MULTICAST_TOP;
}

/// True when the 16-byte address starts with 0xFF (ff00::/8), the IPv6
/// multicast block. Returns false for any other length.
/// Complexity: O(1).
pub fn mld_is_multicast(addr: &Vec[UInt8]) -> Bool {
  if !_addr16_ok(addr) {
    return false;
  }
  return _byte(addr, 0) == 255;
}

/// Short name of an IGMP message type; "unknown" otherwise.
/// Complexity: O(1).
pub fn igmp_message_name(msg_type: Int) -> Str {
  if msg_type == IGMP_TYPE_QUERY { return "membership query"; }
  if msg_type == IGMP_TYPE_V1_REPORT { return "v1 membership report"; }
  if msg_type == IGMP_TYPE_V2_REPORT { return "v2 membership report"; }
  if msg_type == IGMP_TYPE_LEAVE { return "leave group"; }
  if msg_type == IGMP_TYPE_V3_REPORT { return "v3 membership report"; }
  return "unknown";
}

/// Short name of an IGMPv3 group record type (1..6); "unknown" otherwise.
/// Complexity: O(1).
pub fn igmp_record_type_name(record_type: Int) -> Str {
  if record_type == IGMP_RECORD_MODE_IS_INCLUDE { return "mode is include"; }
  if record_type == IGMP_RECORD_MODE_IS_EXCLUDE { return "mode is exclude"; }
  if record_type == IGMP_RECORD_CHANGE_TO_INCLUDE { return "change to include mode"; }
  if record_type == IGMP_RECORD_CHANGE_TO_EXCLUDE { return "change to exclude mode"; }
  if record_type == IGMP_RECORD_ALLOW_NEW_SOURCES { return "allow new sources"; }
  if record_type == IGMP_RECORD_BLOCK_OLD_SOURCES { return "block old sources"; }
  return "unknown";
}

/// Short name of an MLD message type; "unknown" otherwise.
/// Complexity: O(1).
pub fn mld_message_name(msg_type: Int) -> Str {
  if msg_type == MLD_TYPE_QUERY { return "multicast listener query"; }
  if msg_type == MLD_TYPE_REPORT { return "multicast listener report"; }
  if msg_type == MLD_TYPE_DONE { return "multicast listener done"; }
  if msg_type == MLD_TYPE_V2_REPORT { return "version 2 multicast listener report"; }
  return "unknown";
}

// --------------------------------------------------
//  IGMP parsing
// --------------------------------------------------

/// Parse one IGMP message.
///
/// The message type, source list and record structure decide the accepted
/// length: 8 bytes for queries without the v3 suffix (report/leave too),
/// `12 + 4N` for IGMPv3 queries and `8 + records` for IGMPv3 reports.
/// Trailing bytes are rejected everywhere; nothing is silently ignored.
/// A bad checksum is not a parse error: `checksum_ok` reports it.
///
/// Errors (all stable, with byte offsets where a position is known):
///   * `igmp: short message` -- fewer than 8 bytes;
///   * `igmp: bad message type at 0` -- not 0x11, 0x12, 0x16, 0x17, 0x22;
///   * `igmp: bad length at 8` -- a report/leave whose length is not 8;
///   * `igmp: bad v3 query length at 8` -- 9..11 bytes for type 0x11;
///   * `igmp: truncated source list at 12` -- the declared source count
///     needs more bytes than the query carries;
///   * `igmp: trailing bytes at <end>` -- bytes after the declared span;
///   * `igmp: bad record count at 6` -- the report's record count cannot
///     fit the buffer, or fewer records were present;
///   * `igmp: truncated record at <pos>` -- a record header crosses the end;
///   * `igmp: bad record type at <pos>` -- record type outside 1..6;
///   * `igmp: truncated source list at <pos>` -- a record's source list
///     crosses the end;
///   * `igmp: bad aux data length at <pos>` -- a record's auxiliary data
///     crosses the end.
/// Precedence is: length, type, checksum flag, shape. Complexity:
/// O(data.len()).
pub fn igmp_parse(data: &Vec[UInt8]) -> Result[IgmpMessage, Str] {
  let n = data.len();
  if n < IGMP_QUERY_SIZE {
    return _err_igmp("igmp: short message");
  }
  let msg_type: Int = _byte(data, 0);
  if msg_type != IGMP_TYPE_QUERY && msg_type != IGMP_TYPE_V1_REPORT && msg_type != IGMP_TYPE_V2_REPORT && msg_type != IGMP_TYPE_LEAVE && msg_type != IGMP_TYPE_V3_REPORT {
    return _err_igmp("igmp: bad message type at 0");
  }
  let wire_checksum: Int = _u16(data, 2);
  var checksum_ok = false;
  if igmp_checksum_valid(data) {
    checksum_ok = true;
  }
  if msg_type == IGMP_TYPE_QUERY {
    if n == IGMP_QUERY_SIZE {
      let max_resp: Int = _byte(data, 1);
      var version = 2;
      if max_resp == 0 {
        version = 1;
      }
      var no1 = _no_ints();
      var no2 = _no_ints();
      var no3 = _no_ints();
      var no4 = _no_ints();
      var no5 = _no_ints();
      var no6 = _no_ints();
      return _ok_igmp(IgmpMessage{
        msg_type: msg_type;
        version: version;
        max_resp: max_resp;
        checksum: wire_checksum;
        checksum_ok: checksum_ok;
        group: _u32(data, 4);
        suppress: false;
        qrv: 0;
        qqic: 0;
        source_count: 0;
        source_offset: -1;
        rec_types: no1;
        rec_groups: no2;
        rec_source_counts: no3;
        rec_source_offsets: no4;
        rec_aux_words: no5;
        rec_aux_offsets: no6;
      });
    }
    if n < IGMP_V3_QUERY_FIXED {
      return _err_igmp("igmp: bad v3 query length at 8");
    }
    let count: Int = _u16(data, 10);
    let need = IGMP_V3_QUERY_FIXED + count * 4;
    if n < need {
      return _err_igmp("igmp: truncated source list at 12");
    }
    if n > need {
      return _err_igmp("igmp: trailing bytes at " + convert.int_to_string(need));
    }
    let flags: Int = _byte(data, 8);
    var sup = false;
    if (flags / 8) % 2 == 1 {
      sup = true;
    }
    var no1 = _no_ints();
    var no2 = _no_ints();
    var no3 = _no_ints();
    var no4 = _no_ints();
    var no5 = _no_ints();
    var no6 = _no_ints();
    return _ok_igmp(IgmpMessage{
      msg_type: msg_type;
      version: 3;
      max_resp: _byte(data, 1);
      checksum: wire_checksum;
      checksum_ok: checksum_ok;
      group: _u32(data, 4);
      suppress: sup;
      qrv: flags % 8;
      qqic: _byte(data, 9);
      source_count: count;
      source_offset: IGMP_V3_QUERY_FIXED;
      rec_types: no1;
      rec_groups: no2;
      rec_source_counts: no3;
      rec_source_offsets: no4;
      rec_aux_words: no5;
      rec_aux_offsets: no6;
    });
  }
  if msg_type == IGMP_TYPE_V1_REPORT || msg_type == IGMP_TYPE_V2_REPORT || msg_type == IGMP_TYPE_LEAVE {
    if n != IGMP_QUERY_SIZE {
      return _err_igmp("igmp: bad length at 8");
    }
    var version = 2;
    if msg_type == IGMP_TYPE_V1_REPORT {
      version = 1;
    }
    var no1 = _no_ints();
    var no2 = _no_ints();
    var no3 = _no_ints();
    var no4 = _no_ints();
    var no5 = _no_ints();
    var no6 = _no_ints();
    return _ok_igmp(IgmpMessage{
      msg_type: msg_type;
      version: version;
      max_resp: _byte(data, 1);
      checksum: wire_checksum;
      checksum_ok: checksum_ok;
      group: _u32(data, 4);
      suppress: false;
      qrv: 0;
      qqic: 0;
      source_count: 0;
      source_offset: -1;
      rec_types: no1;
      rec_groups: no2;
      rec_source_counts: no3;
      rec_source_offsets: no4;
      rec_aux_words: no5;
      rec_aux_offsets: no6;
    });
  }
  // IGMP_TYPE_V3_REPORT
  let m_count: Int = _u16(data, 6);
  if IGMP_V3_REPORT_FIXED + m_count * IGMP_RECORD_FIXED > n {
    return _err_igmp("igmp: bad record count at 6");
  }
  if m_count == 0 && n > IGMP_V3_REPORT_FIXED {
    return _err_igmp("igmp: trailing bytes at " + convert.int_to_string(IGMP_V3_REPORT_FIXED));
  }
  var types = _no_ints();
  var groups = _no_ints();
  var counts = _no_ints();
  var src_offsets = _no_ints();
  var words_v = _no_ints();
  var aux_offsets = _no_ints();
  var pos = IGMP_V3_REPORT_FIXED;
  while pos < n {
    if pos + IGMP_RECORD_FIXED > n {
      return _err_igmp("igmp: truncated record at " + convert.int_to_string(pos));
    }
    let rt: Int = _byte(data, pos);
    if rt < IGMP_RECORD_MODE_IS_INCLUDE || rt > IGMP_RECORD_BLOCK_OLD_SOURCES {
      return _err_igmp("igmp: bad record type at " + convert.int_to_string(pos));
    }
    let words: Int = _byte(data, pos + 1);
    let sc: Int = _u16(data, pos + 2);
    let src_off = pos + IGMP_RECORD_FIXED;
    let src_end = src_off + sc * 4;
    if src_end > n {
      return _err_igmp("igmp: truncated source list at " + convert.int_to_string(src_off));
    }
    let aux_off = src_end;
    let aux_end = aux_off + words * 4;
    if aux_end > n {
      return _err_igmp("igmp: bad aux data length at " + convert.int_to_string(aux_off));
    }
    types.push(rt);
    groups.push(_u32(data, pos + 4));
    counts.push(sc);
    src_offsets.push(src_off);
    words_v.push(words);
    aux_offsets.push(aux_off);
    pos = aux_end;
  }
  if types.len() != m_count {
    return _err_igmp("igmp: bad record count at 6");
  }
  return _ok_igmp(IgmpMessage{
    msg_type: msg_type;
    version: 3;
    max_resp: _byte(data, 1);
    checksum: wire_checksum;
    checksum_ok: checksum_ok;
    group: 0;
    suppress: false;
    qrv: 0;
    qqic: 0;
    source_count: 0;
    source_offset: -1;
    rec_types: types;
    rec_groups: groups;
    rec_source_counts: counts;
    rec_source_offsets: src_offsets;
    rec_aux_words: words_v;
    rec_aux_offsets: aux_offsets;
  });
}

// --------------------------------------------------
//  IGMP accessors
// --------------------------------------------------

/// Protocol version assigned to a parsed message: 1 (query with Max Resp
/// Code 0, or the 0x12 report), 2 (other 8-byte messages) or 3 (v3 query
/// or report). Complexity: O(1).
pub fn igmp_version(m: &IgmpMessage) -> Int {
  return m.version;
}

/// Query variant: 0 general (group 0, no sources), 1 group-specific
/// (group set, no sources), 2 group-and-source-specific (group set with
/// sources); -1 for a non-query or a malformed general query carrying
/// sources. Complexity: O(1).
pub fn igmp_query_variant(m: &IgmpMessage) -> Int {
  if m.msg_type != IGMP_TYPE_QUERY {
    return -1;
  }
  let cnt: Int = m.source_count;
  if cnt > 0 {
    if m.group == 0 {
      return -1;
    }
    return 2;
  }
  if m.group != 0 {
    return 1;
  }
  return 0;
}

/// `k`-th (0-based) source address of a v3 query as an unsigned 32-bit
/// Int, or -1 when `k` is negative, beyond the declared count, or the
/// recorded span does not fit `data`. Complexity: O(1).
pub fn igmp_source_at(data: &Vec[UInt8], m: &IgmpMessage, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  let cnt: Int = m.source_count;
  if k >= cnt {
    return -1;
  }
  let off: Int = m.source_offset;
  if off < 0 {
    return -1;
  }
  if off + (k + 1) * 4 > data.len() {
    return -1;
  }
  return _u32(data, off + k * 4);
}

// True when record index `i` is in range of every parallel record vector.
fn _igmp_record_exists(m: &IgmpMessage, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= m.rec_types.len() {
    return false;
  }
  if i >= m.rec_groups.len() {
    return false;
  }
  if i >= m.rec_source_counts.len() {
    return false;
  }
  if i >= m.rec_source_offsets.len() {
    return false;
  }
  if i >= m.rec_aux_words.len() {
    return false;
  }
  if i >= m.rec_aux_offsets.len() {
    return false;
  }
  return true;
}

/// Number of group records in a v3 report (0 for every other message).
/// Complexity: O(1).
pub fn igmp_record_count(m: &IgmpMessage) -> Int {
  return m.rec_types.len();
}

/// Record type of record `i`, or -1 when out of range. Complexity: O(1).
pub fn igmp_record_type(m: &IgmpMessage, i: Int) -> Int {
  if !_igmp_record_exists(m, i) {
    return -1;
  }
  let t: Int = m.rec_types[i];
  return t;
}

/// Group address of record `i` as an unsigned 32-bit Int, or -1 when out
/// of range. Complexity: O(1).
pub fn igmp_record_group(m: &IgmpMessage, i: Int) -> Int {
  if !_igmp_record_exists(m, i) {
    return -1;
  }
  let g: Int = m.rec_groups[i];
  return g;
}

/// Declared source count of record `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn igmp_record_source_count(m: &IgmpMessage, i: Int) -> Int {
  if !_igmp_record_exists(m, i) {
    return -1;
  }
  let c: Int = m.rec_source_counts[i];
  return c;
}

/// Auxiliary data length of record `i` in bytes (words * 4), or -1 when
/// out of range. Complexity: O(1).
pub fn igmp_record_aux_bytes(m: &IgmpMessage, i: Int) -> Int {
  if !_igmp_record_exists(m, i) {
    return -1;
  }
  let w: Int = m.rec_aux_words[i];
  return w * 4;
}

/// `k`-th source address of group record `i` as an unsigned 32-bit Int,
/// or -1 when any index is out of range or the recorded span does not fit
/// `data`. Complexity: O(1).
pub fn igmp_record_source_at(data: &Vec[UInt8], m: &IgmpMessage, i: Int, k: Int) -> Int {
  if !_igmp_record_exists(m, i) {
    return -1;
  }
  if k < 0 {
    return -1;
  }
  let cnt: Int = m.rec_source_counts[i];
  if k >= cnt {
    return -1;
  }
  let off: Int = m.rec_source_offsets[i];
  if off < 0 {
    return -1;
  }
  if off + (k + 1) * 4 > data.len() {
    return -1;
  }
  return _u32(data, off + k * 4);
}

/// Copy the auxiliary data bytes of group record `i` out of `data`.
///
/// Err("igmp: record index out of range") when `i` is out of range;
/// Err("igmp: record out of bounds") when the recorded span does not fit
/// `data`. A zero-length span yields an empty Ok. Complexity: O(span).
pub fn igmp_record_aux(data: &Vec[UInt8], m: &IgmpMessage, i: Int) -> Result[Vec[UInt8], Str] {
  if !_igmp_record_exists(m, i) {
    return _err_bytes("igmp: record index out of range");
  }
  let off: Int = m.rec_aux_offsets[i];
  let w: Int = m.rec_aux_words[i];
  let len = w * 4;
  if off < 0 || len < 0 {
    return _err_bytes("igmp: record out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("igmp: record out of bounds");
  }
  return _ok_bytes(_copy_range(data, off, len));
}

// --------------------------------------------------
//  IGMP building
// --------------------------------------------------

/// Build an IGMPv1/v2 Membership Query (0x11) for `group` with the raw
/// Max Resp Code octet `max_resp`.
///
/// Err("igmp: bad group address") when `group` is outside 0..4294967295;
/// Err("igmp: bad max resp code") when `max_resp` is outside 0..255.
/// Nothing is written on Err. Complexity: O(1).
pub fn igmp_build_query_v2(group: Int, max_resp: Int) -> Result[Vec[UInt8], Str] {
  if !_addr32_ok(group) {
    return _err_bytes("igmp: bad group address");
  }
  if max_resp < 0 || max_resp > 255 {
    return _err_bytes("igmp: bad max resp code");
  }
  var body = Vec[UInt8].new();
  body.push(IGMP_TYPE_QUERY as UInt8);
  body.push(max_resp as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, group, 4);
  return _ok_bytes(_with_igmp_checksum(&body));
}

/// Build an IGMPv1 Membership Report (0x12) for `group`.
///
/// Err("igmp: bad group address") when `group` is outside
/// 0..4294967295. Complexity: O(1).
pub fn igmp_build_report_v1(group: Int) -> Result[Vec[UInt8], Str] {
  if !_addr32_ok(group) {
    return _err_bytes("igmp: bad group address");
  }
  var body = Vec[UInt8].new();
  body.push(IGMP_TYPE_V1_REPORT as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, group, 4);
  return _ok_bytes(_with_igmp_checksum(&body));
}

/// Build an IGMPv2 Membership Report (0x16) for `group`.
///
/// Err("igmp: bad group address") when `group` is outside
/// 0..4294967295. Complexity: O(1).
pub fn igmp_build_report_v2(group: Int) -> Result[Vec[UInt8], Str] {
  if !_addr32_ok(group) {
    return _err_bytes("igmp: bad group address");
  }
  var body = Vec[UInt8].new();
  body.push(IGMP_TYPE_V2_REPORT as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, group, 4);
  return _ok_bytes(_with_igmp_checksum(&body));
}

/// Build an IGMPv2 Leave Group (0x17) for `group`.
///
/// Err("igmp: bad group address") when `group` is outside
/// 0..4294967295. Complexity: O(1).
pub fn igmp_build_leave(group: Int) -> Result[Vec[UInt8], Str] {
  if !_addr32_ok(group) {
    return _err_bytes("igmp: bad group address");
  }
  var body = Vec[UInt8].new();
  body.push(IGMP_TYPE_LEAVE as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, group, 4);
  return _ok_bytes(_with_igmp_checksum(&body));
}

/// Build an IGMPv3 Membership Query (0x11) with the Resv/S/QRV/QQIC
/// suffix and `sources` (each an unsigned 32-bit IPv4 Int).
///
/// `max_resp`, `qqic` and `qrv` are raw code octets (see
/// igmp_max_resp_ms / igmp_qqic_seconds for their meaning); `qrv` must be
/// 0..7. Errors: Err("igmp: bad group address"), Err("igmp: bad max resp
/// code"), Err("igmp: bad qrv"), Err("igmp: bad qqic"),
/// Err("igmp: too many sources") when the list exceeds 65535 entries and
/// Err("igmp: bad source address") for an address outside
/// 0..4294967295. Complexity: O(sources).
pub fn igmp_build_query_v3(group: Int, max_resp: Int, suppress: Bool, qrv: Int, qqic: Int, sources: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  if !_addr32_ok(group) {
    return _err_bytes("igmp: bad group address");
  }
  if max_resp < 0 || max_resp > 255 {
    return _err_bytes("igmp: bad max resp code");
  }
  if qrv < 0 || qrv > 7 {
    return _err_bytes("igmp: bad qrv");
  }
  if qqic < 0 || qqic > 255 {
    return _err_bytes("igmp: bad qqic");
  }
  let count = sources.len();
  if count > 65535 {
    return _err_bytes("igmp: too many sources");
  }
  var i = 0;
  while i < count {
    let s: Int = sources[i];
    if !_addr32_ok(s) {
      return _err_bytes("igmp: bad source address");
    }
    i = i + 1;
  }
  var flags = qrv;
  if suppress {
    flags = flags + 8;
  }
  var body = Vec[UInt8].new();
  body.push(IGMP_TYPE_QUERY as UInt8);
  body.push(max_resp as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, group, 4);
  body.push(flags as UInt8);
  body.push(qqic as UInt8);
  _push_be(&mut body, count, 2);
  i = 0;
  while i < count {
    let s2: Int = sources[i];
    _push_be(&mut body, s2, 4);
    i = i + 1;
  }
  return _ok_bytes(_with_igmp_checksum(&body));
}

/// Build an IGMPv3 Membership Report (0x22) from parallel record vectors.
///
/// One entry per group record: `record_types` (1..6), `groups` (unsigned
/// 32-bit Ints), `source_counts` and `aux_data` (each a multiple of 4
/// bytes, at most 255 words). The `sources` vector is flat: the first
/// `source_counts[0]` addresses belong to record 0, the next
/// `source_counts[1]` to record 1, and so on.
///
/// Errors: Err("igmp: record vector length mismatch") when the four
/// per-record vectors differ; Err("igmp: too many records");
/// Err("igmp: bad record type at index <i>"); Err("igmp: bad group
/// address"); Err("igmp: bad source count at index <i>");
/// Err("igmp: bad aux data length at index <i>") for a length that is
/// negative, not a multiple of 4, or over 255 words;
/// Err("igmp: source vector length mismatch") when the flat source count
/// does not equal the sum of `source_counts`; Err("igmp: bad source
/// address") for an address outside 0..4294967295.
/// Complexity: O(records + sources + aux).
pub fn igmp_build_report_v3(record_types: &Vec[Int], groups: &Vec[Int], source_counts: &Vec[Int], sources: &Vec[Int], aux_data: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  let m = record_types.len();
  if groups.len() != m || source_counts.len() != m || aux_data.len() != m {
    return _err_bytes("igmp: record vector length mismatch");
  }
  if m > 65535 {
    return _err_bytes("igmp: too many records");
  }
  var total_sources = 0;
  var i = 0;
  while i < m {
    let rt: Int = record_types[i];
    if rt < IGMP_RECORD_MODE_IS_INCLUDE || rt > IGMP_RECORD_BLOCK_OLD_SOURCES {
      return _err_bytes("igmp: bad record type at index " + convert.int_to_string(i));
    }
    let g: Int = groups[i];
    if !_addr32_ok(g) {
      return _err_bytes("igmp: bad group address");
    }
    let sc: Int = source_counts[i];
    if sc < 0 || sc > 65535 {
      return _err_bytes("igmp: bad source count at index " + convert.int_to_string(i));
    }
    let a: Vec[UInt8] = aux_data[i];
    if a.len() % 4 != 0 || a.len() / 4 > 255 {
      return _err_bytes("igmp: bad aux data length at index " + convert.int_to_string(i));
    }
    total_sources = total_sources + sc;
    i = i + 1;
  }
  if sources.len() != total_sources {
    return _err_bytes("igmp: source vector length mismatch");
  }
  var j = 0;
  while j < sources.len() {
    let s: Int = sources[j];
    if !_addr32_ok(s) {
      return _err_bytes("igmp: bad source address");
    }
    j = j + 1;
  }
  var body = Vec[UInt8].new();
  body.push(IGMP_TYPE_V3_REPORT as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, m, 2);
  var base = 0;
  var k = 0;
  while k < m {
    let rt2: Int = record_types[k];
    let sc2: Int = source_counts[k];
    let g2: Int = groups[k];
    let a2: Vec[UInt8] = aux_data[k];
    body.push(rt2 as UInt8);
    body.push((a2.len() / 4) as UInt8);
    _push_be(&mut body, sc2, 2);
    _push_be(&mut body, g2, 4);
    var q = 0;
    while q < sc2 {
      let s3: Int = sources[base + q];
      _push_be(&mut body, s3, 4);
      q = q + 1;
    }
    base = base + sc2;
    var p = 0;
    while p < a2.len() {
      body.push(a2[p]);
      p = p + 1;
    }
    k = k + 1;
  }
  return _ok_bytes(_with_igmp_checksum(&body));
}

// --------------------------------------------------
//  MLD parsing
// --------------------------------------------------

/// Parse one MLD or MLDv2 message (ICMPv6 types 130/131/132/143).
///
/// A type 130 message of exactly 24 bytes is an MLDv1 query; 28 or more
/// bytes make it an MLDv2 query (`28 + 16N`). Types 131 and 132 are
/// exactly 24 bytes. Type 143 is the MLDv2 report and carries records.
/// Trailing bytes are rejected everywhere. The ICMPv6 checksum cannot be
/// verified without the IPv6 source and destination addresses, so parse
/// stores the wire value only; use icmpv6_checksum_valid with the
/// addresses.
///
/// Errors (all stable, with byte offsets where a position is known):
///   * `mld: short message` -- fewer than 4 bytes, or a type 143 message
///     shorter than 8, or a query/report shorter than 24;
///   * `mld: bad message type at 0` -- not 130, 131, 132 or 143;
///   * `mld: bad query length at 24` -- a type 130 message of 25..27 bytes;
///   * `mld: bad length at 24` -- a report/done whose length is not 24;
///   * `mld: truncated source list at 28` -- the declared source count
///     needs more bytes than the query carries;
///   * `mld: trailing bytes at <end>` -- bytes after the declared span;
///   * `mld: bad record count at 6` -- the report's record count cannot
///     fit the buffer, or fewer records were present;
///   * `mld: truncated record at <pos>` -- a record header crosses the end;
///   * `mld: bad record type at <pos>` -- record type outside 1..6;
///   * `mld: truncated source list at <pos>` -- a record's source list
///     crosses the end;
///   * `mld: bad aux data length at <pos>` -- a record's auxiliary data
///     crosses the end.
/// Complexity: O(data.len()).
pub fn mld_parse(data: &Vec[UInt8]) -> Result[MldMessage, Str] {
  let n = data.len();
  if n < 4 {
    return _err_mld("mld: short message");
  }
  let msg_type: Int = _byte(data, 0);
  if msg_type != MLD_TYPE_QUERY && msg_type != MLD_TYPE_REPORT && msg_type != MLD_TYPE_DONE && msg_type != MLD_TYPE_V2_REPORT {
    return _err_mld("mld: bad message type at 0");
  }
  let wire_checksum: Int = _u16(data, 2);
  if msg_type == MLD_TYPE_V2_REPORT {
    if n < MLD_V2_REPORT_FIXED {
      return _err_mld("mld: short message");
    }
    let m_count: Int = _u16(data, 6);
    if MLD_V2_REPORT_FIXED + m_count * MLD_RECORD_FIXED > n {
      return _err_mld("mld: bad record count at 6");
    }
    if m_count == 0 && n > MLD_V2_REPORT_FIXED {
      return _err_mld("mld: trailing bytes at " + convert.int_to_string(MLD_V2_REPORT_FIXED));
    }
    var types = _no_ints();
    var counts = _no_ints();
    var group_offsets = _no_ints();
    var src_offsets = _no_ints();
    var words_v = _no_ints();
    var aux_offsets = _no_ints();
    var pos = MLD_V2_REPORT_FIXED;
    while pos < n {
      if pos + MLD_RECORD_FIXED > n {
        return _err_mld("mld: truncated record at " + convert.int_to_string(pos));
      }
      let rt: Int = _byte(data, pos);
      if rt < IGMP_RECORD_MODE_IS_INCLUDE || rt > IGMP_RECORD_BLOCK_OLD_SOURCES {
        return _err_mld("mld: bad record type at " + convert.int_to_string(pos));
      }
      let words: Int = _byte(data, pos + 1);
      let sc: Int = _u16(data, pos + 2);
      let group_off = pos + 4;
      let src_off = pos + MLD_RECORD_FIXED;
      let src_end = src_off + sc * MLD_ADDRESS_SIZE;
      if src_end > n {
        return _err_mld("mld: truncated source list at " + convert.int_to_string(src_off));
      }
      let aux_off = src_end;
      let aux_end = aux_off + words * 4;
      if aux_end > n {
        return _err_mld("mld: bad aux data length at " + convert.int_to_string(aux_off));
      }
      types.push(rt);
      counts.push(sc);
      group_offsets.push(group_off);
      src_offsets.push(src_off);
      words_v.push(words);
      aux_offsets.push(aux_off);
      pos = aux_end;
    }
    if types.len() != m_count {
      return _err_mld("mld: bad record count at 6");
    }
    var g0 = _no_bytes();
    return _ok_mld(MldMessage{
      msg_type: msg_type;
      version: 2;
      code: _byte(data, 1);
      checksum: wire_checksum;
      max_delay: 0;
      max_resp: 0;
      reserved: 0;
      suppress: false;
      qrv: 0;
      qqic: 0;
      source_count: 0;
      source_offset: -1;
      group: g0;
      rec_types: types;
      rec_source_counts: counts;
      rec_group_offsets: group_offsets;
      rec_source_offsets: src_offsets;
      rec_aux_words: words_v;
      rec_aux_offsets: aux_offsets;
    });
  }
  if n < MLD_V1_SIZE {
    return _err_mld("mld: short message");
  }
  let code: Int = _byte(data, 1);
  if msg_type == MLD_TYPE_QUERY {
    if n == MLD_V1_SIZE {
      var g1 = _copy_range(data, 8, MLD_ADDRESS_SIZE);
      var no1 = _no_ints();
      var no2 = _no_ints();
      var no3 = _no_ints();
      var no4 = _no_ints();
      var no5 = _no_ints();
      var no6 = _no_ints();
      return _ok_mld(MldMessage{
        msg_type: msg_type;
        version: 1;
        code: code;
        checksum: wire_checksum;
        max_delay: _u32(data, 4);
        max_resp: 0;
        reserved: 0;
        suppress: false;
        qrv: 0;
        qqic: 0;
        source_count: 0;
        source_offset: -1;
        group: g1;
        rec_types: no1;
        rec_source_counts: no2;
        rec_group_offsets: no3;
        rec_source_offsets: no4;
        rec_aux_words: no5;
        rec_aux_offsets: no6;
      });
    }
    if n < MLD_V2_QUERY_FIXED {
      return _err_mld("mld: bad query length at 24");
    }
    let count: Int = _u16(data, 26);
    let need = MLD_V2_QUERY_FIXED + count * MLD_ADDRESS_SIZE;
    if n < need {
      return _err_mld("mld: truncated source list at 28");
    }
    if n > need {
      return _err_mld("mld: trailing bytes at " + convert.int_to_string(need));
    }
    let flags: Int = _byte(data, 24);
    var sup = false;
    if (flags / 8) % 2 == 1 {
      sup = true;
    }
    var g2 = _copy_range(data, 8, MLD_ADDRESS_SIZE);
    var no1 = _no_ints();
    var no2 = _no_ints();
    var no3 = _no_ints();
    var no4 = _no_ints();
    var no5 = _no_ints();
    var no6 = _no_ints();
    return _ok_mld(MldMessage{
      msg_type: msg_type;
      version: 2;
      code: code;
      checksum: wire_checksum;
      max_delay: 0;
      max_resp: _u16(data, 4);
      reserved: _u16(data, 6);
      suppress: sup;
      qrv: flags % 8;
      qqic: _byte(data, 25);
      source_count: count;
      source_offset: MLD_V2_QUERY_FIXED;
      group: g2;
      rec_types: no1;
      rec_source_counts: no2;
      rec_group_offsets: no3;
      rec_source_offsets: no4;
      rec_aux_words: no5;
      rec_aux_offsets: no6;
    });
  }
  // MLD_TYPE_REPORT or MLD_TYPE_DONE
  if n != MLD_V1_SIZE {
    return _err_mld("mld: bad length at 24");
  }
  var g3 = _copy_range(data, 8, MLD_ADDRESS_SIZE);
  var no1 = _no_ints();
  var no2 = _no_ints();
  var no3 = _no_ints();
  var no4 = _no_ints();
  var no5 = _no_ints();
  var no6 = _no_ints();
  return _ok_mld(MldMessage{
    msg_type: msg_type;
    version: 1;
    code: code;
    checksum: wire_checksum;
    max_delay: _u32(data, 4);
    max_resp: 0;
    reserved: 0;
    suppress: false;
    qrv: 0;
    qqic: 0;
    source_count: 0;
    source_offset: -1;
    group: g3;
    rec_types: no1;
    rec_source_counts: no2;
    rec_group_offsets: no3;
    rec_source_offsets: no4;
    rec_aux_words: no5;
    rec_aux_offsets: no6;
  });
}

// --------------------------------------------------
//  MLD accessors
// --------------------------------------------------

/// Protocol version assigned to a parsed message: 1 for the 24-byte MLDv1
/// messages, 2 for an MLDv2 query or the type 143 report.
/// Complexity: O(1).
pub fn mld_version(m: &MldMessage) -> Int {
  return m.version;
}

/// The 16-byte multicast address of a query/report message (all zeroes for
/// a general query); an empty vector for a type 143 report.
/// Complexity: O(1).
pub fn mld_group(m: &MldMessage) -> Vec[UInt8] {
  let g: Vec[UInt8] = m.group;
  return _copy_range(&g, 0, g.len());
}

/// Query variant: 0 general (all-zero group), 1 group-specific (non-zero
/// group, no sources), 2 group-and-source-specific (non-zero group with
/// sources); -1 for a non-query or a malformed group carried with
/// sources. Complexity: O(address bytes).
pub fn mld_query_variant(m: &MldMessage) -> Int {
  if m.msg_type != MLD_TYPE_QUERY {
    return -1;
  }
  let g: Vec[UInt8] = m.group;
  if g.len() != MLD_ADDRESS_SIZE {
    return -1;
  }
  var all_zero = true;
  var i = 0;
  while i < MLD_ADDRESS_SIZE {
    let b: Int = (g[i] as Int) & 0xFF;
    if b != 0 {
      all_zero = false;
    }
    i = i + 1;
  }
  if all_zero {
    return 0;
  }
  let cnt: Int = m.source_count;
  if cnt > 0 {
    return 2;
  }
  return 1;
}

/// `k`-th (0-based) 16-byte source address of an MLDv2 query.
///
/// Err("mld: source index out of range") when `k` is negative or beyond
/// the declared count; Err("mld: source out of bounds") when the recorded
/// span does not fit `data`. Complexity: O(16).
pub fn mld_source_at(data: &Vec[UInt8], m: &MldMessage, k: Int) -> Result[Vec[UInt8], Str] {
  if k < 0 {
    return _err_bytes("mld: source index out of range");
  }
  let cnt: Int = m.source_count;
  if k >= cnt {
    return _err_bytes("mld: source index out of range");
  }
  let off: Int = m.source_offset;
  if off < 0 {
    return _err_bytes("mld: source out of bounds");
  }
  if off + (k + 1) * MLD_ADDRESS_SIZE > data.len() {
    return _err_bytes("mld: source out of bounds");
  }
  return _ok_bytes(_copy_range(data, off + k * MLD_ADDRESS_SIZE, MLD_ADDRESS_SIZE));
}

// True when record index `i` is in range of every parallel record vector.
fn _mld_record_exists(m: &MldMessage, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= m.rec_types.len() {
    return false;
  }
  if i >= m.rec_source_counts.len() {
    return false;
  }
  if i >= m.rec_group_offsets.len() {
    return false;
  }
  if i >= m.rec_source_offsets.len() {
    return false;
  }
  if i >= m.rec_aux_words.len() {
    return false;
  }
  if i >= m.rec_aux_offsets.len() {
    return false;
  }
  return true;
}

/// Number of address records in a type 143 report (0 otherwise).
/// Complexity: O(1).
pub fn mld_record_count(m: &MldMessage) -> Int {
  return m.rec_types.len();
}

/// Record type of record `i`, or -1 when out of range. Complexity: O(1).
pub fn mld_record_type(m: &MldMessage, i: Int) -> Int {
  if !_mld_record_exists(m, i) {
    return -1;
  }
  let t: Int = m.rec_types[i];
  return t;
}

/// Declared source count of record `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn mld_record_source_count(m: &MldMessage, i: Int) -> Int {
  if !_mld_record_exists(m, i) {
    return -1;
  }
  let c: Int = m.rec_source_counts[i];
  return c;
}

/// Auxiliary data length of record `i` in bytes (words * 4), or -1 when
/// out of range. Complexity: O(1).
pub fn mld_record_aux_bytes(m: &MldMessage, i: Int) -> Int {
  if !_mld_record_exists(m, i) {
    return -1;
  }
  let w: Int = m.rec_aux_words[i];
  return w * 4;
}

/// Copy the 16-byte group address of record `i` out of `data`.
///
/// Err("mld: record index out of range") when `i` is out of range;
/// Err("mld: record out of bounds") when the recorded span does not fit
/// `data`. Complexity: O(16).
pub fn mld_record_group(data: &Vec[UInt8], m: &MldMessage, i: Int) -> Result[Vec[UInt8], Str] {
  if !_mld_record_exists(m, i) {
    return _err_bytes("mld: record index out of range");
  }
  let off: Int = m.rec_group_offsets[i];
  if off < 0 || off + MLD_ADDRESS_SIZE > data.len() {
    return _err_bytes("mld: record out of bounds");
  }
  return _ok_bytes(_copy_range(data, off, MLD_ADDRESS_SIZE));
}

/// `k`-th source address of record `i` as 16 bytes.
///
/// Err("mld: record index out of range") / Err("mld: source index out of
/// range") for out-of-range indices; Err("mld: record out of bounds")
/// when the recorded span does not fit `data`. Complexity: O(16).
pub fn mld_record_source_at(data: &Vec[UInt8], m: &MldMessage, i: Int, k: Int) -> Result[Vec[UInt8], Str] {
  if !_mld_record_exists(m, i) {
    return _err_bytes("mld: record index out of range");
  }
  if k < 0 {
    return _err_bytes("mld: source index out of range");
  }
  let cnt: Int = m.rec_source_counts[i];
  if k >= cnt {
    return _err_bytes("mld: source index out of range");
  }
  let off: Int = m.rec_source_offsets[i];
  if off < 0 {
    return _err_bytes("mld: record out of bounds");
  }
  if off + (k + 1) * MLD_ADDRESS_SIZE > data.len() {
    return _err_bytes("mld: record out of bounds");
  }
  return _ok_bytes(_copy_range(data, off + k * MLD_ADDRESS_SIZE, MLD_ADDRESS_SIZE));
}

/// Copy the auxiliary data bytes of record `i` out of `data`.
///
/// Err("mld: record index out of range") when `i` is out of range;
/// Err("mld: record out of bounds") when the recorded span does not fit
/// `data`. A zero-length span yields an empty Ok. Complexity: O(span).
pub fn mld_record_aux(data: &Vec[UInt8], m: &MldMessage, i: Int) -> Result[Vec[UInt8], Str] {
  if !_mld_record_exists(m, i) {
    return _err_bytes("mld: record index out of range");
  }
  let off: Int = m.rec_aux_offsets[i];
  let w: Int = m.rec_aux_words[i];
  let len = w * 4;
  if off < 0 || len < 0 {
    return _err_bytes("mld: record out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("mld: record out of bounds");
  }
  return _ok_bytes(_copy_range(data, off, len));
}

// --------------------------------------------------
//  MLD building
// --------------------------------------------------

// Shared address checks for the MLD builders; "" when all three are
// 16 bytes, otherwise the specific first error.
fn _mld_addrs_err(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8]) -> Str {
  if !_addr16_ok(src) {
    return "mld: bad source address length";
  }
  if !_addr16_ok(dst) {
    return "mld: bad destination address length";
  }
  if !_addr16_ok(group) {
    return "mld: bad group address length";
  }
  return "";
}

/// Build an MLDv1 Multicast Listener Query (ICMPv6 type 130, 24 bytes)
/// from the 16-byte source and destination addresses, the 16-byte group
/// address (:: for a general query) and the 32-bit Maximum Response Delay
/// in milliseconds. The ICMPv6 checksum is computed over the IPv6
/// pseudo-header built from `src` and `dst`.
///
/// Errors: Err("mld: bad source address length"), Err("mld: bad
/// destination address length"), Err("mld: bad group address length") and
/// Err("mld: bad max response delay") when the delay is outside
/// 0..4294967295. Complexity: O(1).
pub fn mld_build_query_v1(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8], max_delay: Int) -> Result[Vec[UInt8], Str] {
  let ae = _mld_addrs_err(src, dst, group);
  if ae.len() > 0 {
    return _err_bytes(ae);
  }
  if max_delay < 0 || max_delay > 4294967295 {
    return _err_bytes("mld: bad max response delay");
  }
  var body = Vec[UInt8].new();
  body.push(MLD_TYPE_QUERY as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, max_delay, 4);
  _push_vec(&mut body, group);
  return _ok_bytes(_with_icmpv6_checksum(&body, src, dst));
}

/// Build an MLDv1 Multicast Listener Report (ICMPv6 type 131, 24 bytes)
/// for `group`; the Maximum Response Delay field is zero.
///
/// Errors as in mld_build_query_v1 without the delay error.
/// Complexity: O(1).
pub fn mld_build_report_v1(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let ae = _mld_addrs_err(src, dst, group);
  if ae.len() > 0 {
    return _err_bytes(ae);
  }
  var body = Vec[UInt8].new();
  body.push(MLD_TYPE_REPORT as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, 0, 4);
  _push_vec(&mut body, group);
  return _ok_bytes(_with_icmpv6_checksum(&body, src, dst));
}

/// Build an MLDv1 Multicast Listener Done (ICMPv6 type 132, 24 bytes) for
/// `group`; the Maximum Response Delay field is zero.
///
/// Errors as in mld_build_query_v1 without the delay error.
/// Complexity: O(1).
pub fn mld_build_done(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let ae = _mld_addrs_err(src, dst, group);
  if ae.len() > 0 {
    return _err_bytes(ae);
  }
  var body = Vec[UInt8].new();
  body.push(MLD_TYPE_DONE as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, 0, 4);
  _push_vec(&mut body, group);
  return _ok_bytes(_with_icmpv6_checksum(&body, src, dst));
}

/// Build an MLDv2 Multicast Listener Query (ICMPv6 type 130, `28 + 16N`
/// bytes): the MLDv1 prefix with the Maximum Response Code, the Resv/S/
/// QRV/QQIC suffix and the 16-byte source addresses.
///
/// `max_resp` is a raw 16-bit code (see mld_max_resp_ms), `qqic` a raw
/// octet (see igmp_qqic_seconds) and `qrv` must be 0..7. Errors: the
/// address errors of mld_build_query_v1, Err("mld: bad max resp code"),
/// Err("mld: bad qrv"), Err("mld: bad qqic"),
/// Err("mld: too many sources") over 65535 entries and
/// Err("mld: bad source address length") for a source that is not 16
/// bytes. Complexity: O(sources).
pub fn mld_build_query_v2(src: &Vec[UInt8], dst: &Vec[UInt8], group: &Vec[UInt8], max_resp: Int, suppress: Bool, qrv: Int, qqic: Int, sources: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  let ae = _mld_addrs_err(src, dst, group);
  if ae.len() > 0 {
    return _err_bytes(ae);
  }
  if max_resp < 0 || max_resp > 65535 {
    return _err_bytes("mld: bad max resp code");
  }
  if qrv < 0 || qrv > 7 {
    return _err_bytes("mld: bad qrv");
  }
  if qqic < 0 || qqic > 255 {
    return _err_bytes("mld: bad qqic");
  }
  let count = sources.len();
  if count > 65535 {
    return _err_bytes("mld: too many sources");
  }
  var i = 0;
  while i < count {
    let s: Vec[UInt8] = sources[i];
    if !_addr16_ok(&s) {
      return _err_bytes("mld: bad source address length");
    }
    i = i + 1;
  }
  var flags = qrv;
  if suppress {
    flags = flags + 8;
  }
  var body = Vec[UInt8].new();
  body.push(MLD_TYPE_QUERY as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, max_resp, 2);
  _push_be(&mut body, 0, 2);
  _push_vec(&mut body, group);
  body.push(flags as UInt8);
  body.push(qqic as UInt8);
  _push_be(&mut body, count, 2);
  i = 0;
  while i < count {
    let s2: Vec[UInt8] = sources[i];
    _push_vec(&mut body, &s2);
    i = i + 1;
  }
  return _ok_bytes(_with_icmpv6_checksum(&body, src, dst));
}

/// Build an MLDv2 Version 2 Multicast Listener Report (ICMPv6 type 143)
/// from parallel record vectors.
///
/// One entry per address record: `record_types` (1..6, the same codes as
/// IGMPv3), `groups` (16-byte addresses), `source_counts` and `aux_data`
/// (each a multiple of 4 bytes, at most 255 words). The `sources` vector
/// is flat: the first `source_counts[0]` 16-byte addresses belong to
/// record 0, the next `source_counts[1]` to record 1, and so on.
///
/// Errors: Err("mld: record vector length mismatch") when the per-record
/// vectors differ; Err("mld: too many records"); Err("mld: bad record
/// type at index <i>"); Err("mld: bad group address length");
/// Err("mld: bad source count at index <i>"); Err("mld: bad aux data
/// length at index <i>"); Err("mld: source vector length mismatch");
/// Err("mld: bad source address length"). Complexity: O(records +
/// sources + aux).
pub fn mld_build_report_v2(src: &Vec[UInt8], dst: &Vec[UInt8], record_types: &Vec[Int], groups: &Vec[Vec[UInt8]], source_counts: &Vec[Int], sources: &Vec[Vec[UInt8]], aux_data: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  if !_addr16_ok(src) {
    return _err_bytes("mld: bad source address length");
  }
  if !_addr16_ok(dst) {
    return _err_bytes("mld: bad destination address length");
  }
  let m = record_types.len();
  if groups.len() != m || source_counts.len() != m || aux_data.len() != m {
    return _err_bytes("mld: record vector length mismatch");
  }
  if m > 65535 {
    return _err_bytes("mld: too many records");
  }
  var total_sources = 0;
  var i = 0;
  while i < m {
    let rt: Int = record_types[i];
    if rt < IGMP_RECORD_MODE_IS_INCLUDE || rt > IGMP_RECORD_BLOCK_OLD_SOURCES {
      return _err_bytes("mld: bad record type at index " + convert.int_to_string(i));
    }
    let g: Vec[UInt8] = groups[i];
    if !_addr16_ok(&g) {
      return _err_bytes("mld: bad group address length");
    }
    let sc: Int = source_counts[i];
    if sc < 0 || sc > 65535 {
      return _err_bytes("mld: bad source count at index " + convert.int_to_string(i));
    }
    let a: Vec[UInt8] = aux_data[i];
    if a.len() % 4 != 0 || a.len() / 4 > 255 {
      return _err_bytes("mld: bad aux data length at index " + convert.int_to_string(i));
    }
    total_sources = total_sources + sc;
    i = i + 1;
  }
  if sources.len() != total_sources {
    return _err_bytes("mld: source vector length mismatch");
  }
  var j = 0;
  while j < sources.len() {
    let s: Vec[UInt8] = sources[j];
    if !_addr16_ok(&s) {
      return _err_bytes("mld: bad source address length");
    }
    j = j + 1;
  }
  var body = Vec[UInt8].new();
  body.push(MLD_TYPE_V2_REPORT as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  body.push(0 as UInt8);
  _push_be(&mut body, m, 2);
  var base = 0;
  var k = 0;
  while k < m {
    let rt2: Int = record_types[k];
    let sc2: Int = source_counts[k];
    let g2: Vec[UInt8] = groups[k];
    let a2: Vec[UInt8] = aux_data[k];
    body.push(rt2 as UInt8);
    body.push((a2.len() / 4) as UInt8);
    _push_be(&mut body, sc2, 2);
    _push_vec(&mut body, &g2);
    var q = 0;
    while q < sc2 {
      let s3: Vec[UInt8] = sources[base + q];
      _push_vec(&mut body, &s3);
      q = q + 1;
    }
    base = base + sc2;
    var p = 0;
    while p < a2.len() {
      body.push(a2[p]);
      p = p + 1;
    }
    k = k + 1;
  }
  return _ok_bytes(_with_icmpv6_checksum(&body, src, dst));
}
