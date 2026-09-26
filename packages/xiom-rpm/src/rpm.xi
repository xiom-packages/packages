// XIOM -- xiom.rpm: RPM package lead and header parser
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.rpm placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: read-only parsing of the two structural layers every RPM file
// starts with -- the 96-byte program lead (magic ED AB EE DB, version, type,
// archnum, name[66], osnum, signature_type) and the generic header structure
// (magic 8E AD E8 01, 4 reserved bytes, index-entry count, data-store size,
// then 16-byte index entries of tag/type/offset/count and the data store).
// rpm_parse skips the signature header and decodes the main header;
// rpm_header_tag_str / rpm_header_tag_int look tags up in it. The payload
// (compressed cpio archive) is not touched, and nothing is ever written.
//
// v0.61.3 notes that shaped this module:
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic;
//   * Vec[Int] element reads are always bound to typed locals;
//   * accessors take &RpmHeader and index h.store/h.tags directly instead of
//     passing `&h.store` into a `&Vec[UInt8]` parameter;
//   * Str values are only built from NUL-free byte runs, so the built range
//     never contains 0x00;
//   * parallel vectors (tags/store) are length-guarded in every accessor.
// See SPEC.md for the layout tables, validation order, error catalog and
// test plan.

module xiom.rpm

use xiom.string;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Size of the RPM program lead in bytes.
pub const RPM_LEAD_SIZE: Int = 96;

/// First byte of the RPM lead magic (0xED).
pub const RPM_LEAD_MAGIC_0: Int = 237;

/// Second byte of the RPM lead magic (0xAB).
pub const RPM_LEAD_MAGIC_1: Int = 171;

/// Third byte of the RPM lead magic (0xEE).
pub const RPM_LEAD_MAGIC_2: Int = 238;

/// Fourth byte of the RPM lead magic (0xDB).
pub const RPM_LEAD_MAGIC_3: Int = 219;

/// Offset of the lead `name[66]` field.
pub const RPM_LEAD_NAME_OFFSET: Int = 10;

/// Width of the lead `name[66]` field in bytes.
pub const RPM_LEAD_NAME_SIZE: Int = 66;

/// First magic byte of the header structure (0x8E).
pub const RPM_HEADER_MAGIC_0: Int = 142;

/// Second magic byte of the header structure (0xAD).
pub const RPM_HEADER_MAGIC_1: Int = 173;

/// Third magic byte of the header structure (0xE8).
pub const RPM_HEADER_MAGIC_2: Int = 232;

/// Version byte of the header structure (1).
pub const RPM_HEADER_VERSION: Int = 1;

/// Bytes before the first index entry: magic+version (4), 4 reserved bytes,
/// entry count (4), store size (4).
pub const RPM_HEADER_PREFIX: Int = 16;

/// Size of one index entry: tag, type, offset, count (4 x 4 bytes).
pub const RPM_INDEX_ENTRY_SIZE: Int = 16;

/// Number of Int slots one index entry occupies in RpmHeader.tags.
pub const RPM_HDR_STRIDE: Int = 4;

/// NULL type: no data.
pub const RPM_TYPE_NULL: Int = 0;

/// CHAR type: one byte per value.
pub const RPM_TYPE_CHAR: Int = 1;

/// INT32 type: signed 32-bit big-endian values.
pub const RPM_TYPE_INT32: Int = 4;

/// STRING type: one NUL-terminated string.
pub const RPM_TYPE_STRING: Int = 6;

/// STRING_ARRAY type: `count` NUL-terminated strings.
pub const RPM_TYPE_STRING_ARRAY: Int = 8;

/// NAME tag: package name.
pub const RPM_TAG_NAME: Int = 1000;

/// VERSION tag: upstream version string.
pub const RPM_TAG_VERSION: Int = 1001;

/// RELEASE tag: package release string.
pub const RPM_TAG_RELEASE: Int = 1002;

/// SUMMARY tag: one-line description.
pub const RPM_TAG_SUMMARY: Int = 1004;

/// BUILDTIME tag: build time (seconds since the epoch, INT32).
pub const RPM_TAG_BUILDTIME: Int = 1006;

/// LICENSE tag: license string.
pub const RPM_TAG_LICENSE: Int = 1014;

/// GROUP tag: package group string.
pub const RPM_TAG_GROUP: Int = 1016;

/// OS tag: target operating system string.
pub const RPM_TAG_OS: Int = 1021;

/// ARCH tag: target architecture string.
pub const RPM_TAG_ARCH: Int = 1022;

/// PAYLOADCOMPRESSOR tag: payload compressor name (for example "zstd").
pub const RPM_TAG_PAYLOADCOMPRESSOR: Int = 1125;

// --------------------------------------------------
//  Parsed structures
// --------------------------------------------------

/// Parsed 96-byte RPM program lead. `name` is the NUL-terminated string in
/// the 66-byte `name` field (up to the first NUL; a field without a NUL is
/// returned in full). `ptype` is 0 for binary and 1 for source packages;
/// `archnum`, `osnum` and `signature_type` are the raw big-endian numbers.
pub type RpmLead = {
  major: Int;
  minor: Int;
  ptype: Int;
  archnum: Int;
  name: Str;
  osnum: Int;
  signature_type: Int;
}

/// Parsed RPM header structure. `tags` is a flat vector with stride
/// RPM_HDR_STRIDE: entry `i` owns `tags[i*4 .. i*4+3]` in the order tag,
/// type, offset, count. `store` is the data-store bytes copied out of the
/// source buffer; index entry offsets are relative to it. Fields are
/// implementation details; callers use the free functions below.
pub type RpmHeader = {
  tags: Vec[Int];
  store: Vec[UInt8];
}

/// Parsed RPM file prefix: the lead fields plus the decoded main header
/// (the signature header is validated and skipped, never stored).
pub type RpmPackage = {
  major: Int;
  minor: Int;
  ptype: Int;
  archnum: Int;
  lead_name: Str;
  osnum: Int;
  signature_type: Int;
  header: RpmHeader;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[RpmLead, Str].
fn _ok_lead(v: RpmLead) -> Result[RpmLead, Str] {
  return Ok(v);
}

// Err(m) for Result[RpmLead, Str].
fn _err_lead(m: Str) -> Result[RpmLead, Str] {
  return Err(m);
}

// Ok(v) for Result[RpmHeader, Str].
fn _ok_header(v: RpmHeader) -> Result[RpmHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[RpmHeader, Str].
fn _err_header(m: Str) -> Result[RpmHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[RpmPackage, Str].
fn _ok_package(v: RpmPackage) -> Result[RpmPackage, Str] {
  return Ok(v);
}

// Err(m) for Result[RpmPackage, Str].
fn _err_package(m: Str) -> Result[RpmPackage, Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Store byte at `pos` widened to an Int (0..255); callers guarantee the
// bounds.
fn _store_byte(h: &RpmHeader, pos: Int) -> Int {
  return (h.store[pos] as Int) & 0xFF;
}

// Big-endian 16-bit value at `pos`; the caller guarantees two bytes.
fn _u16be(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Big-endian 32-bit value at `pos` as an unsigned Int; the caller
// guarantees four bytes.
fn _u32be(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Big-endian signed 32-bit value at `off` in the header store; the caller
// guarantees off + 4 <= h.store.len(). Values with the high bit set are
// sign-extended by subtracting 2^32, which keeps every intermediate
// positive.
fn _hdr_i32(h: &RpmHeader, off: Int) -> Int {
  let u: Int = _store_byte(h, off) * 16777216 + _store_byte(h, off + 1) * 65536 + _store_byte(h, off + 2) * 256 + _store_byte(h, off + 3);
  if u >= 2147483648 {
    return u - 4294967296;
  }
  return u;
}

// Bytes [off, off + len) up to the first NUL as a Str; the caller
// guarantees the range fits. The NUL is never copied, so the built range
// cannot contain 0x00.
fn _cstr(data: &Vec[UInt8], off: Int, len: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < len && !done {
    let b: Int = _byte(data, off + i);
    if b == 0 {
      done = true;
    } else {
      bytes.push(b as UInt8);
      i = i + 1;
    }
  }
  return Str::from_utf8(bytes);
}

// Header magic code at `off`: 0 when the three magic bytes match, -1
// otherwise. The caller guarantees three readable bytes.
fn _header_magic_code(data: &Vec[UInt8], off: Int) -> Int {
  if _byte(data, off) != RPM_HEADER_MAGIC_0 { return -1; }
  if _byte(data, off + 1) != RPM_HEADER_MAGIC_1 { return -1; }
  if _byte(data, off + 2) != RPM_HEADER_MAGIC_2 { return -1; }
  return 0;
}

// Validated end offset (exclusive) of the header structure at absolute
// `off`, or -1 when the header magic, version, index or store is malformed.
// The caller guarantees nothing; all reads are bounds-checked.
fn _header_span_checked(data: &Vec[UInt8], off: Int) -> Int {
  if off < 0 {
    return -1;
  }
  if off + RPM_HEADER_PREFIX > data.len() {
    return -1;
  }
  if _header_magic_code(data, off) < 0 {
    return -1;
  }
  if _byte(data, off + 3) != RPM_HEADER_VERSION {
    return -1;
  }
  let count: Int = _u32be(data, off + 8);
  let store_size: Int = _u32be(data, off + 12);
  let index_start: Int = off + RPM_HEADER_PREFIX;
  if count > (data.len() - index_start) / RPM_INDEX_ENTRY_SIZE {
    return -1;
  }
  let store_start: Int = index_start + count * RPM_INDEX_ENTRY_SIZE;
  if store_size > data.len() - store_start {
    return -1;
  }
  return store_start + store_size;
}

// --------------------------------------------------
//  Lead
// --------------------------------------------------

/// True when `data` starts with the four-byte RPM lead magic ED AB EE DB.
/// A buffer shorter than four bytes is false. This is a magic probe only:
/// it does not require the full 96-byte lead and does not touch the header.
/// Complexity: O(1).
pub fn rpm_is_rpm(data: &Vec[UInt8]) -> Bool {
  if data.len() < 4 {
    return false;
  }
  if _byte(data, 0) != RPM_LEAD_MAGIC_0 { return false; }
  if _byte(data, 1) != RPM_LEAD_MAGIC_1 { return false; }
  if _byte(data, 2) != RPM_LEAD_MAGIC_2 { return false; }
  if _byte(data, 3) != RPM_LEAD_MAGIC_3 { return false; }
  return true;
}

/// Parse and validate the 96-byte RPM program lead at offset 0.
///
/// Err("rpm: truncated lead") when the buffer is shorter than 96 bytes;
/// Err("rpm: bad lead magic") when the first four bytes are not ED AB EE DB.
/// The 16 trailing lead bytes (the old reserved area) are not validated.
/// Complexity: O(1).
pub fn rpm_parse_lead(data: &Vec[UInt8]) -> Result[RpmLead, Str] {
  if data.len() < RPM_LEAD_SIZE {
    return _err_lead("rpm: truncated lead");
  }
  if !rpm_is_rpm(data) {
    return _err_lead("rpm: bad lead magic");
  }
  let major: Int = _byte(data, 4);
  let minor: Int = _byte(data, 5);
  let ptype: Int = _u16be(data, 6);
  let archnum: Int = _u16be(data, 8);
  let nm: Str = _cstr(data, RPM_LEAD_NAME_OFFSET, RPM_LEAD_NAME_SIZE);
  let osnum: Int = _u16be(data, 76);
  let sigtype: Int = _u16be(data, 78);
  let lead = RpmLead{
    major: major;
    minor: minor;
    ptype: ptype;
    archnum: archnum;
    name: nm;
    osnum: osnum;
    signature_type: sigtype;
  };
  return _ok_lead(lead);
}

/// Name of the canonical architecture family for the lead `archnum`:
/// 0 noarch, 1 i386 (the whole x86 family), 2 alpha, 3 sparc, 4 mips,
/// 5 ppc, 6 m68k, 7 sgi, 8 rs6000, 9 ia64, 10 mipsel, 11 mips64, 12 arm,
/// 13 m68kmint, 14 s390, 15 s390x, 16 ppc64, 17 sh, 18 xtensa, 19 aarch64,
/// 20 mipsr6, 21 mipsr6el; "unknown" for any other value.
///
/// `archnum` is a legacy lead field that many writers set to 1 for every
/// x86-family package: use the ARCH tag (RPM_TAG_ARCH) for the real
/// architecture. Complexity: O(1).
pub fn rpm_lead_arch_name(archnum: Int) -> Str {
  if archnum == 0 { return "noarch"; }
  if archnum == 1 { return "i386"; }
  if archnum == 2 { return "alpha"; }
  if archnum == 3 { return "sparc"; }
  if archnum == 4 { return "mips"; }
  if archnum == 5 { return "ppc"; }
  if archnum == 6 { return "m68k"; }
  if archnum == 7 { return "sgi"; }
  if archnum == 8 { return "rs6000"; }
  if archnum == 9 { return "ia64"; }
  if archnum == 10 { return "mipsel"; }
  if archnum == 11 { return "mips64"; }
  if archnum == 12 { return "arm"; }
  if archnum == 13 { return "m68kmint"; }
  if archnum == 14 { return "s390"; }
  if archnum == 15 { return "s390x"; }
  if archnum == 16 { return "ppc64"; }
  if archnum == 17 { return "sh"; }
  if archnum == 18 { return "xtensa"; }
  if archnum == 19 { return "aarch64"; }
  if archnum == 20 { return "mipsr6"; }
  if archnum == 21 { return "mipsr6el"; }
  return "unknown";
}

/// Lead `type` as a name: 0 "binary", 1 "source", anything else "unknown".
/// Complexity: O(1).
pub fn rpm_lead_type_name(ptype: Int) -> Str {
  if ptype == 0 { return "binary"; }
  if ptype == 1 { return "source"; }
  return "unknown";
}

/// Lead `osnum` as a name: 1 "linux", anything else "unknown".
/// Complexity: O(1).
pub fn rpm_lead_os_name(osnum: Int) -> Str {
  if osnum == 1 { return "linux"; }
  return "unknown";
}

// --------------------------------------------------
//  Header parsing
// --------------------------------------------------

/// Parse the RPM header structure at absolute offset `off`.
///
/// Layout: 4-byte magic word (0x8E 0xAD 0xE8 + version 0x01), 4 reserved
/// bytes (skipped, not required to be zero), 4-byte big-endian index-entry
/// count, 4-byte big-endian data-store size, then `count` index entries of
/// 16 bytes each (tag, type, offset, count -- each 4-byte big-endian) and
/// finally the data store. The prefix is RPM_HEADER_PREFIX (16) bytes.
///
/// Err("rpm: truncated header") when the 16-byte prefix does not fit;
/// Err("rpm: bad header magic") when the first three bytes are not 8E AD E8;
/// Err("rpm: bad header version") when the version byte is not 1;
/// Err("rpm: truncated index") when the index entries do not fit;
/// Err("rpm: truncated store") when the data store does not fit.
/// Index entries are copied structurally: no type is required and no
/// offset/count is range-checked here (rpm_validate does that).
/// Complexity: O(count + store_size).
pub fn rpm_parse_header(data: &Vec[UInt8], off: Int) -> Result[RpmHeader, Str] {
  if off < 0 {
    return _err_header("rpm: truncated header");
  }
  if off + RPM_HEADER_PREFIX > data.len() {
    return _err_header("rpm: truncated header");
  }
  if _header_magic_code(data, off) < 0 {
    return _err_header("rpm: bad header magic");
  }
  if _byte(data, off + 3) != RPM_HEADER_VERSION {
    return _err_header("rpm: bad header version");
  }
  let count: Int = _u32be(data, off + 8);
  let store_size: Int = _u32be(data, off + 12);
  let index_start: Int = off + RPM_HEADER_PREFIX;
  if count > (data.len() - index_start) / RPM_INDEX_ENTRY_SIZE {
    return _err_header("rpm: truncated index");
  }
  let store_start: Int = index_start + count * RPM_INDEX_ENTRY_SIZE;
  if store_size > data.len() - store_start {
    return _err_header("rpm: truncated store");
  }
  var tags = Vec[Int].new();
  var k = 0;
  while k < count {
    let base: Int = index_start + k * RPM_INDEX_ENTRY_SIZE;
    let tg: Int = _u32be(data, base);
    let tp: Int = _u32be(data, base + 4);
    let ofs: Int = _u32be(data, base + 8);
    let cnt: Int = _u32be(data, base + 12);
    tags.push(tg);
    tags.push(tp);
    tags.push(ofs);
    tags.push(cnt);
    k = k + 1;
  }
  var store = Vec[UInt8].new();
  var j = 0;
  while j < store_size {
    store.push(data[store_start + j]);
    j = j + 1;
  }
  let hdr = RpmHeader{
    tags: tags;
    store: store;
  };
  return _ok_header(hdr);
}

// --------------------------------------------------
//  Whole-file parse and validation
// --------------------------------------------------

/// Parse the structural layers of an RPM file: the 96-byte lead, the
/// signature header (validated structurally and skipped) and the main
/// header.
///
/// Err catalog: rpm_parse_lead's errors for the lead; Err("rpm: bad
/// signature header") when the header at offset 96 is malformed (bad magic
/// or version, truncated index or store); then rpm_parse_header's errors
/// for the main header. The payload after the main header is not read.
/// Complexity: O(lead + signature header + main header).
pub fn rpm_parse(data: &Vec[UInt8]) -> Result[RpmPackage, Str] {
  let lr = rpm_parse_lead(data);
  if !lr.is_ok {
    return _err_package(lr.error);
  }
  let lead: RpmLead = lr.value;
  let main_off: Int = _header_span_checked(data, RPM_LEAD_SIZE);
  if main_off < 0 {
    return _err_package("rpm: bad signature header");
  }
  let hr = rpm_parse_header(data, main_off);
  if !hr.is_ok {
    return _err_package(hr.error);
  }
  let hdr: RpmHeader = hr.value;
  let major: Int = lead.major;
  let minor: Int = lead.minor;
  let ptype: Int = lead.ptype;
  let archnum: Int = lead.archnum;
  let nm: Str = lead.name;
  let osnum: Int = lead.osnum;
  let sigtype: Int = lead.signature_type;
  let pkg = RpmPackage{
    major: major;
    minor: minor;
    ptype: ptype;
    archnum: archnum;
    lead_name: nm;
    osnum: osnum;
    signature_type: sigtype;
    header: hdr;
  };
  return _ok_package(pkg);
}

// Index of the first NUL byte in `h.store` at or after `off`, or -1 when
// absent. The caller guarantees off >= 0.
fn _store_nul_at(h: &RpmHeader, off: Int) -> Int {
  var i = off;
  while i < h.store.len() {
    if _store_byte(h, i) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Number of NUL bytes in `h.store` at or after `off`; this is the number of
// NUL-terminated strings that start in that range when it is a STRING_ARRAY
// store run. The caller guarantees off >= 0.
fn _store_nul_count(h: &RpmHeader, off: Int) -> Int {
  var n = 0;
  var i = off;
  while i < h.store.len() {
    if _store_byte(h, i) == 0 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// Structural validation of every main-header index entry. Unknown types
// (BIN(7), I18NSTRING(9), the INT16/INT8 family, ...) are accepted with
// only their offset bounded, because real RPM files carry them; the five
// documented types get exact bounds checks.
fn _validate_entries(h: &RpmHeader) -> Result[Unit, Str] {
  let n: Int = rpm_header_count(h);
  if n < 0 {
    return _err_unit("rpm: bad index entry");
  }
  var i = 0;
  while i < n {
    let tp: Int = h.tags[i * RPM_HDR_STRIDE + 1];
    let ofs: Int = h.tags[i * RPM_HDR_STRIDE + 2];
    let cnt: Int = h.tags[i * RPM_HDR_STRIDE + 3];
    if ofs < 0 || ofs > h.store.len() {
      return _err_unit("rpm: tag out of range");
    }
    if tp == RPM_TYPE_CHAR {
      if cnt > h.store.len() - ofs {
        return _err_unit("rpm: tag out of range");
      }
    } else if tp == RPM_TYPE_INT32 {
      if cnt > (h.store.len() - ofs) / 4 {
        return _err_unit("rpm: tag out of range");
      }
    } else if tp == RPM_TYPE_STRING {
      if ofs >= h.store.len() {
        return _err_unit("rpm: tag out of range");
      }
      if _store_nul_at(h, ofs) < 0 {
        return _err_unit("rpm: string missing NUL");
      }
    } else if tp == RPM_TYPE_STRING_ARRAY {
      if _store_nul_count(h, ofs) < cnt {
        return _err_unit("rpm: string missing NUL");
      }
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Validate an RPM file prefix: the lead, the signature header and the main
/// header structure, plus every main-header index entry of the documented
/// types (NULL/CHAR/INT32/STRING/STRING_ARRAY bounds; strings and every
/// STRING_ARRAY element must be NUL-terminated inside the store).
///
/// Unknown tag types are accepted (offset-bounded only) because real RPM
/// files carry BIN(7), INT16(3), INT8(5) and I18NSTRING(9) entries. The
/// error catalog is rpm_parse_lead's plus Err("rpm: bad signature header"),
/// rpm_parse_header's, Err("rpm: bad index entry"),
/// Err("rpm: tag out of range") and Err("rpm: string missing NUL").
/// Ok(()) carries no payload; the payload region itself is not validated.
/// Complexity: O(main header entries + store).
pub fn rpm_validate(data: &Vec[UInt8]) -> Result[Unit, Str] {
  let lr = rpm_parse_lead(data);
  if !lr.is_ok {
    return _err_unit(lr.error);
  }
  let main_off: Int = _header_span_checked(data, RPM_LEAD_SIZE);
  if main_off < 0 {
    return _err_unit("rpm: bad signature header");
  }
  let hr = rpm_parse_header(data, main_off);
  if !hr.is_ok {
    return _err_unit(hr.error);
  }
  let hdr: RpmHeader = hr.value;
  return _validate_entries(&hdr);
}

// --------------------------------------------------
//  Header accessors
// --------------------------------------------------

/// Number of index entries in `h` (`h.tags` length / RPM_HDR_STRIDE); -1
/// when the tags vector is not a whole number of entries (a defensive guard
/// against parallel-vector drift).
/// Complexity: O(1).
pub fn rpm_header_count(h: &RpmHeader) -> Int {
  if h.tags.len() % RPM_HDR_STRIDE != 0 {
    return -1;
  }
  return h.tags.len() / RPM_HDR_STRIDE;
}

/// Number of bytes in the header data store.
/// Complexity: O(1).
pub fn rpm_header_store_len(h: &RpmHeader) -> Int {
  return h.store.len();
}

// Entry field `slot` (0 tag, 1 type, 2 offset, 3 count) of entry `i`, or -1
// when `i` or `slot` is out of range.
fn _entry_field(h: &RpmHeader, i: Int, slot: Int) -> Int {
  let n: Int = rpm_header_count(h);
  if n < 0 {
    return -1;
  }
  if i < 0 || i >= n {
    return -1;
  }
  if slot < 0 || slot >= RPM_HDR_STRIDE {
    return -1;
  }
  let v: Int = h.tags[i * RPM_HDR_STRIDE + slot];
  return v;
}

/// Tag of index entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn rpm_header_entry_tag(h: &RpmHeader, i: Int) -> Int {
  return _entry_field(h, i, 0);
}

/// Type of index entry `i` (RPM_TYPE_*); -1 out of range.
/// Complexity: O(1).
pub fn rpm_header_entry_type(h: &RpmHeader, i: Int) -> Int {
  return _entry_field(h, i, 1);
}

/// Data-store offset of index entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn rpm_header_entry_offset(h: &RpmHeader, i: Int) -> Int {
  return _entry_field(h, i, 2);
}

/// Element count of index entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn rpm_header_entry_count(h: &RpmHeader, i: Int) -> Int {
  return _entry_field(h, i, 3);
}

/// Index of the first index entry whose tag is `tag`; -1 when absent.
/// Complexity: O(entries).
pub fn rpm_header_find(h: &RpmHeader, tag: Int) -> Int {
  let n: Int = rpm_header_count(h);
  if n < 0 {
    return -1;
  }
  var i = 0;
  while i < n {
    let tg: Int = h.tags[i * RPM_HDR_STRIDE];
    if tg == tag {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// True when an index entry with tag `tag` exists.
/// Complexity: O(entries).
pub fn rpm_header_has_tag(h: &RpmHeader, tag: Int) -> Bool {
  return rpm_header_find(h, tag) >= 0;
}

/// Type (RPM_TYPE_*) of the first entry with tag `tag`; -1 when absent.
/// Complexity: O(entries).
pub fn rpm_header_tag_type(h: &RpmHeader, tag: Int) -> Int {
  let i: Int = rpm_header_find(h, tag);
  if i < 0 {
    return -1;
  }
  let tp: Int = h.tags[i * RPM_HDR_STRIDE + 1];
  return tp;
}

// C string at `off` in the store: bytes up to the first NUL, or up to the
// end of the store when no NUL is present. "" when `off` is outside the
// store. The built range never contains 0x00.
fn _hdr_cstr(h: &RpmHeader, off: Int) -> Str {
  if off < 0 || off >= h.store.len() {
    return "";
  }
  var bytes = Vec[UInt8].new();
  var i = off;
  var done = false;
  while i < h.store.len() && !done {
    let b: Int = _store_byte(h, i);
    if b == 0 {
      done = true;
    } else {
      bytes.push(b as UInt8);
      i = i + 1;
    }
  }
  return Str::from_utf8(bytes);
}

// Element `idx` of the NUL-separated string run starting at `off` in the
// store; "" when the run ends before `idx` elements, `idx` is negative, or
// `off` is outside the store.
fn _hdr_array_str(h: &RpmHeader, off: Int, idx: Int) -> Str {
  if off < 0 || off >= h.store.len() || idx < 0 {
    return "";
  }
  var pos: Int = off;
  var k = 0;
  while k < idx {
    var done = false;
    while pos < h.store.len() && !done {
      let b: Int = _store_byte(h, pos);
      pos = pos + 1;
      if b == 0 {
        done = true;
      }
    }
    if !done {
      return "";
    }
    k = k + 1;
  }
  return _hdr_cstr(h, pos);
}

/// String value of `tag`: STRING(6) strings and STRING_ARRAY(8) first
/// elements are read as NUL-terminated strings, NULL(0) yields "". Every
/// other type, an absent tag and an out-of-range store offset yield "".
/// An unterminated string is returned up to the end of the store (use
/// rpm_validate to require the NUL). Compare the result with
/// xiom.string.compare.str_compare, not `==`.
/// Complexity: O(string length).
pub fn rpm_header_tag_str(h: &RpmHeader, tag: Int) -> Str {
  let i: Int = rpm_header_find(h, tag);
  if i < 0 {
    return "";
  }
  let tp: Int = h.tags[i * RPM_HDR_STRIDE + 1];
  let ofs: Int = h.tags[i * RPM_HDR_STRIDE + 2];
  if tp == RPM_TYPE_STRING {
    return _hdr_cstr(h, ofs);
  }
  if tp == RPM_TYPE_STRING_ARRAY {
    return _hdr_array_str(h, ofs, 0);
  }
  return "";
}

/// First integer value of `tag`: INT32(4) values are sign-extended,
/// CHAR(1) yields the first byte (0..255). NULL(0), every other type, an
/// absent tag and an out-of-range store span yield -1. Use
/// rpm_header_has_tag to tell an absent tag from a stored value of -1.
/// Complexity: O(1).
pub fn rpm_header_tag_int(h: &RpmHeader, tag: Int) -> Int {
  let i: Int = rpm_header_find(h, tag);
  if i < 0 {
    return -1;
  }
  let tp: Int = h.tags[i * RPM_HDR_STRIDE + 1];
  let ofs: Int = h.tags[i * RPM_HDR_STRIDE + 2];
  if tp == RPM_TYPE_INT32 {
    if ofs < 0 || ofs + 4 > h.store.len() {
      return -1;
    }
    return _hdr_i32(h, ofs);
  }
  if tp == RPM_TYPE_CHAR {
    if ofs < 0 || ofs >= h.store.len() {
      return -1;
    }
    return _store_byte(h, ofs);
  }
  return -1;
}

/// Number of elements in the STRING_ARRAY(8) value of `tag` (the entry's
/// count field); -1 when the tag is absent or is not a STRING_ARRAY.
/// Complexity: O(entries).
pub fn rpm_header_tag_str_array_count(h: &RpmHeader, tag: Int) -> Int {
  let i: Int = rpm_header_find(h, tag);
  if i < 0 {
    return -1;
  }
  let tp: Int = h.tags[i * RPM_HDR_STRIDE + 1];
  if tp != RPM_TYPE_STRING_ARRAY {
    return -1;
  }
  let cnt: Int = h.tags[i * RPM_HDR_STRIDE + 3];
  return cnt;
}

/// Element `idx` of the STRING_ARRAY(8) value of `tag`; "" when the tag is
/// absent, is not a STRING_ARRAY, `idx` is negative or beyond the count, or
/// the run is not NUL-terminated before the end of the store. Compare the
/// result with xiom.string.compare.str_compare, not `==`.
/// Complexity: O(offset + idx strings).
pub fn rpm_header_tag_str_array_at(h: &RpmHeader, tag: Int, idx: Int) -> Str {
  let i: Int = rpm_header_find(h, tag);
  if i < 0 {
    return "";
  }
  let tp: Int = h.tags[i * RPM_HDR_STRIDE + 1];
  if tp != RPM_TYPE_STRING_ARRAY {
    return "";
  }
  let ofs: Int = h.tags[i * RPM_HDR_STRIDE + 2];
  let cnt: Int = h.tags[i * RPM_HDR_STRIDE + 3];
  if idx < 0 || idx >= cnt {
    return "";
  }
  return _hdr_array_str(h, ofs, idx);
}

// --------------------------------------------------
//  Package getters
// --------------------------------------------------

/// NAME tag (1000) of the parsed main header; "" when absent or not a
/// string type. Compare with str_compare, not `==`.
/// Complexity: O(entries + string length).
pub fn rpm_get_name(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_NAME);
}

/// VERSION tag (1001); "" when absent or not a string type.
/// Complexity: O(entries + string length).
pub fn rpm_get_version(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_VERSION);
}

/// RELEASE tag (1002); "" when absent or not a string type.
/// Complexity: O(entries + string length).
pub fn rpm_get_release(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_RELEASE);
}

/// SUMMARY tag (1004); "" when absent or not a string type. Modern RPM
/// files store SUMMARY as I18NSTRING(9), which this parser does not render;
/// the synthetic STRING form is supported.
/// Complexity: O(entries + string length).
pub fn rpm_get_summary(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_SUMMARY);
}

/// LICENSE tag (1014); "" when absent or not a string type.
/// Complexity: O(entries + string length).
pub fn rpm_get_license(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_LICENSE);
}

/// GROUP tag (1016); "" when absent or not a string type. Modern RPM files
/// store GROUP as I18NSTRING(9), which this parser does not render.
/// Complexity: O(entries + string length).
pub fn rpm_get_group(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_GROUP);
}

/// OS tag (1021); "" when absent or not a string type.
/// Complexity: O(entries + string length).
pub fn rpm_get_os(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_OS);
}

/// ARCH tag (1022); "" when absent or not a string type. This is the
/// authoritative architecture string (the lead `archnum` is legacy).
/// Complexity: O(entries + string length).
pub fn rpm_get_arch(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_ARCH);
}

/// PAYLOADCOMPRESSOR tag (1125); "" when absent or not a string type.
/// Complexity: O(entries + string length).
pub fn rpm_get_payload_compressor(p: &RpmPackage) -> Str {
  return rpm_header_tag_str(&p.header, RPM_TAG_PAYLOADCOMPRESSOR);
}

/// BUILDTIME tag (1006) as a signed Int32; -1 when absent or not INT32.
/// Complexity: O(entries).
pub fn rpm_get_buildtime(p: &RpmPackage) -> Int {
  return rpm_header_tag_int(&p.header, RPM_TAG_BUILDTIME);
}
