// XIOM -- xiom.efi: UEFI Firmware File System (FFS) file/section codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a documented UEFI FFS
// codec subset: the 24-byte FFS file header, the 32-byte large-file header
// (FFS_ATTRIB_LARGE_FILE plus the documented 0xFFFFFF extended-size rule),
// a section walker over the documented PI section types, and a canonical
// single-section builder. Firmware volume parsing, PE/TE parsing, dependency
// expression evaluation and section compression are documented non-goals.
// See SPEC.md for the byte layout tables, the documented type-name subset,
// the error catalog, the integrity-check stances and the test plan.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - `ffs_parse` validates the header and walks the section stream, returning
//   an FfsFile of flat parallel vectors: one element per section for the
//   type, declared size, absolute section offset, absolute data offset and
//   data size. Nested content (compression payloads, disposable sections)
//   stays raw; only the leaf metadata named in SPEC.md is decoded.
// - The name GUID is exposed as the 32 lowercase hex characters of the 16
//   raw on-disk bytes (no byte-order rewriting).
// - Section data is located by the documented per-type header sizes; the
//   section size field includes the 4-byte common header and any 4-byte
//   alignment padding. Trailing bytes that are all zero (the documented
//   8-byte file-alignment pad) terminate the walk and are ignored.
// - `ffs_build` emits a canonical small-header file with exactly one
//   section, zero-filled padding and, when FFS_ATTRIB_CHECKSUM is set, the
//   documented additive 8-bit header/file checksums. Large-file building is
//   rejected.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * little-endian packing is arithmetic (modulo/division), which is exact
//     for values with bit 31 set; `&` is only used with the small masks 1,
//     0x01 and 0x40.
//   * 64-bit extended sizes accumulate into a signed Int; values with bit
//     63 set come out negative and are rejected as "efi: bad file size"
//     (the xiom.gpt LBA precedent).
//   * Str values read from Vec elements are bound to typed locals; the
//     module performs no `==` on Str values at all.
//   * nested helpers receive the existing `&mut` reference (gpt/tar
//     precedent); only the top-level builder holds a `&mut` local.

module xiom.efi

use xiom.string;

// --------------------------------------------------
//  Documented constants
// --------------------------------------------------

const _FFS_HEADER_SIZE: Int = 24;
const _FFS_HEADER2_SIZE: Int = 32;
const _FFS_SECTION_HEADER: Int = 4;
const _FFS_SIZE_MAX: Int = 16777215;
const _FFS_EXT_SIZE: Int = 16777215;
const _FFS_ATTR_LARGE: Int = 1;
const _FFS_ATTR_CHECKSUM: Int = 64;
const _FFS_GUID_CHARS: Int = 32;

// Documented FFS file type subset (SPEC.md "File types").
const _FFS_RAW: Int = 1;
const _FFS_FREEFORM: Int = 2;
const _FFS_SECURITY_CORE: Int = 3;
const _FFS_PEI_CORE: Int = 4;
const _FFS_DXE_CORE: Int = 5;
const _FFS_DRIVER: Int = 7;
const _FFS_APPLICATION: Int = 9;
const _FFS_SMM: Int = 10;
const _FFS_FIRMWARE_VOLUME_IMAGE: Int = 11;
const _FFS_COMBINED_PEIM: Int = 12;
const _FFS_PEIM: Int = 13;
const _FFS_DXE_DRIVER: Int = 14;
const _FFS_SMM_DRIVER: Int = 15;
const _FFS_SMM_CORE: Int = 16;
const _FFS_OEM_MIN: Int = 224;
const _FFS_OEM_MAX: Int = 239;
const _FFS_PAD: Int = 240;
const _FFS_FFS_MIN: Int = 241;
const _FFS_FFS_MAX: Int = 254;
const _FFS_FREE_SPACE: Int = 255;

// Documented section type subset (SPEC.md "Section types").
const _SEC_COMPRESSION: Int = 1;
const _SEC_GUID_DEFINED: Int = 2;
const _SEC_DISPOSABLE: Int = 3;
const _SEC_PE32: Int = 16;
const _SEC_PIC: Int = 17;
const _SEC_TE: Int = 18;
const _SEC_DXE_DEPEX: Int = 19;
const _SEC_VERSION: Int = 20;
const _SEC_UI: Int = 21;
const _SEC_COMPATIBILITY16: Int = 22;
const _SEC_FIRMWARE_VOLUME_IMAGE: Int = 23;
const _SEC_FREEFORM_SUBTYPE_GUID: Int = 24;
const _SEC_RAW: Int = 25;
const _SEC_PEI_DEPEX: Int = 27;
const _SEC_SMM_DEPEX: Int = 28;

// --------------------------------------------------
//  Public model
// --------------------------------------------------

/// Parsed FFS file. The scalar fields are the file header values (`size` is
/// the declared file size: the 24-bit field for small files, the 64-bit
/// ExtendedSize for large files). The five vectors are the flat parallel
/// section columns, one element per section in stream order: declared type,
/// declared total size (header + body + alignment padding), absolute offset
/// of the section header, absolute offset of the section data and the data
/// byte count. Fields are implementation details; callers should go through
/// the free functions below.
pub type FfsFile = {
  name: Str;
  integrity_check: Int;
  file_type: Int;
  attributes: Int;
  size: Int;
  state: Int;
  large: Bool;
  header_size: Int;
  section_types: Vec[Int];
  section_sizes: Vec[Int];
  section_offsets: Vec[Int];
  section_data_offsets: Vec[Int];
  section_data_sizes: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[FfsFile, Str].
fn _ok_file(v: FfsFile) -> Result[FfsFile, Str] {
  return Ok(v);
}

// Err(m) for Result[FfsFile, Str].
fn _err_file(m: Str) -> Result[FfsFile, Str] {
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

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian UInt16 at `off` as an Int; callers guarantee the bounds.
fn _u16(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256;
}

// Little-endian UInt24 at `off` as an Int; callers guarantee the bounds.
fn _u24(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536;
}

// Little-endian UInt32 at `off` as an Int (0..2^32-1); callers guarantee the
// bounds. Accumulated byte by byte (the xiom.gpt `_le32` shape).
fn _le32(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + _byte(data, off + i);
    i = i - 1;
  }
  return v;
}

// Little-endian 64-bit field at `off` as a signed Int; callers guarantee the
// bounds. The accumulator wraps to the two's-complement bit pattern when bit
// 63 is set (Int is signed 64-bit), so such values come out negative and the
// file-size check rejects them (SPEC.md documents this).
fn _le64(data: &Vec[UInt8], off: Int) -> Int {
  var v: Int = 0;
  var i = 7;
  while i >= 0 {
    v = v * 256 + _byte(data, off + i);
    i = i - 1;
  }
  return v;
}

// Byte number `k` of `v` (0 = least significant). Arithmetic only: `& 0xFF`
// on values with bit 31 set miscompiles in v0.61.3, and this form is exact
// for negative two's-complement values too (xiom.gpt precedent).
fn _byte_at(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in little-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_at(v, i));
    i = i + 1;
  }
}

// Append `count` zero bytes.
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// True when all `count` bytes at `start` are zero; callers guarantee the
// span. Used for the documented trailing file-alignment pad.
fn _all_zero(data: &Vec[UInt8], start: Int, count: Int) -> Bool {
  var i = 0;
  while i < count {
    if _byte(data, start + i) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Sum of the `count` bytes at `start`, skipping absolute position `skip`
// (pass -1 to skip nothing). Callers guarantee the span.
fn _span_sum(data: &Vec[UInt8], start: Int, count: Int, skip: Int) -> Int {
  var s = 0;
  var i = 0;
  while i < count {
    let pos: Int = start + i;
    if pos != skip {
      s = s + _byte(data, pos);
    }
    i = i + 1;
  }
  return s;
}

// --------------------------------------------------
//  Internal GUID and name helpers
// --------------------------------------------------

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 otherwise.
fn _hex_value(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 97 && c <= 102 { return c - 87; }
  if c >= 65 && c <= 70 { return c - 55; }
  return -1;
}

// Lowercase hex digit byte for a 0..15 value.
fn _hex_nibble(n: Int) -> UInt8 {
  if n < 10 { return (48 + n) as UInt8; }
  return (87 + n) as UInt8;
}

// True when `s` is exactly 32 hexadecimal characters (either case).
fn _name_ok(s: Str) -> Bool {
  if s.len() != _FFS_GUID_CHARS { return false; }
  var i = 0;
  while i < _FFS_GUID_CHARS {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if _hex_value(c) < 0 { return false; }
    i = i + 1;
  }
  return true;
}

// Append the 16 raw bytes encoded by `s` (32 hex characters). Callers
// guarantee `_name_ok(s)`.
fn _name_push(s: Str, out: &mut Vec[UInt8]) {
  var i = 0;
  while i < _FFS_GUID_CHARS {
    let hi: Int = _hex_value((string.byte_at(s, i) as Int) & 0xFF);
    let lo: Int = _hex_value((string.byte_at(s, i + 1) as Int) & 0xFF);
    out.push((hi * 16 + lo) as UInt8);
    i = i + 2;
  }
}

// The 16 bytes at `off` as 32 lowercase hex characters (raw on-disk order,
// no byte swapping). Callers guarantee the bounds.
fn _hex_at(data: &Vec[UInt8], off: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    let b: Int = _byte(data, off + i);
    bytes.push(_hex_nibble(b / 16));
    bytes.push(_hex_nibble(b % 16));
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// --------------------------------------------------
//  Internal section helpers
// --------------------------------------------------

// True when a UI section body at [off, off+len) is even-sized and every
// documented terminal condition holds: at least one code unit and the last
// code unit is 0x0000 (the documented UTF-16LE terminal NUL).
fn _ui_ok(data: &Vec[UInt8], off: Int, len: Int) -> Bool {
  if len < 2 { return false; }
  if len % 2 != 0 { return false; }
  let last: Int = _u16(data, off + len - 2);
  if last != 0 { return false; }
  return true;
}

// Decode the UTF-16LE UI string in [off, end) to printable ASCII. Scanning
// stops at the first 0x0000 code unit; every code unit outside 0x20..0x7E is
// replaced with '?'. A trailing odd byte is ignored (defensive only: parse
// rejects odd-length UI bodies).
fn _ui_decode(data: &Vec[UInt8], off: Int, end: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var pos = off;
  var done = false;
  while pos + 1 < end && !done {
    let unit: Int = _u16(data, pos);
    if unit == 0 {
      done = true;
    } elif unit >= 32 && unit <= 126 {
      bytes.push(unit as UInt8);
    } else {
      bytes.push(63 as UInt8);
    }
    pos = pos + 2;
  }
  return Str::from_utf8(bytes);
}

// Safe section count: the minimum of the five parallel section vector
// lengths, so a hand-built file with drifted vectors reports the indexing
// maximum. A parsed file reports the number of sections walked.
fn _sec_min(f: &FfsFile) -> Int {
  var n = f.section_types.len();
  if f.section_sizes.len() < n { n = f.section_sizes.len(); }
  if f.section_offsets.len() < n { n = f.section_offsets.len(); }
  if f.section_data_offsets.len() < n { n = f.section_data_offsets.len(); }
  if f.section_data_sizes.len() < n { n = f.section_data_sizes.len(); }
  return n;
}

// True when section `i` exists and its recorded data span fits in `data`.
fn _sec_span_ok(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Bool {
  if i < 0 { return false; }
  if i >= _sec_min(f) { return false; }
  let off: Int = f.section_data_offsets[i];
  let len: Int = f.section_data_sizes[i];
  if off < 0 || len < 0 { return false; }
  if off > data.len() { return false; }
  if len > data.len() - off { return false; }
  return true;
}

// True when the recorded file header/size spans fit in `data` and the
// large flag agrees with header_size.
fn _file_spans_ok(data: &Vec[UInt8], f: &FfsFile) -> Bool {
  let h: Int = f.header_size;
  if h != _FFS_HEADER_SIZE && h != _FFS_HEADER2_SIZE { return false; }
  if f.large && h != _FFS_HEADER2_SIZE { return false; }
  if !f.large && h != _FFS_HEADER_SIZE { return false; }
  if f.size < h { return false; }
  if f.size > data.len() { return false; }
  return true;
}

// Copy [off, off+len) out of `data` into a fresh vector.
fn _copy_span(data: &Vec[UInt8], off: Int, len: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 || len < 0 { return _err_bytes("efi: span out of bounds"); }
  if off > data.len() { return _err_bytes("efi: span out of bounds"); }
  if len > data.len() - off { return _err_bytes("efi: span out of bounds"); }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Public API -- parsing
// --------------------------------------------------

/// Parse one FFS file.
///
/// Validation order (first failure wins): a buffer shorter than 24 bytes is
/// Err("efi: truncated header"); when the large-file bit is set the buffer
/// must reach 32 bytes and the 24-bit size field must be 0xFFFFFF, else
/// Err("efi: truncated header") / Err("efi: bad large-file size"); the
/// extended size must be non-negative, the file size at least the header
/// size -> Err("efi: bad file size"); the declared size must fit in the
/// buffer -> Err("efi: truncated file").
///
/// The section stream is then walked from the end of the header: a section
/// whose declared size is below 4 is Err("efi: bad section size"), one that
/// exceeds the remaining bytes is Err("efi: section overruns file"), and
/// nonzero trailing bytes shorter than a section header are
/// Err("efi: truncated section"). The documented per-type headers are
/// validated: Err("efi: section too small") when they do not fit,
/// Err("efi: bad section data offset") for a GUID-defined data offset
/// outside 20..section_size, and Err("efi: bad ui string") when a user
/// interface body is odd-sized or does not end in a 0x0000 code unit.
///
/// Trailing bytes that are all zero (the documented 8-byte file-alignment
/// pad) terminate the walk and are ignored, so the section sizes are only
/// required to sum to at most size - header_size. Unknown section types are
/// passed through raw. The name GUID, the integrity check and the state byte
/// are stored raw.
///
/// Params: data - the whole file image, read only.
/// Returns: Ok(FfsFile) with one element per walked section in each parallel
/// vector.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(data.len()).
pub fn ffs_parse(data: &Vec[UInt8]) -> Result[FfsFile, Str] {
  let n = data.len();
  if n < _FFS_HEADER_SIZE { return _err_file("efi: truncated header"); }
  let attributes: Int = _byte(data, 19);
  let large: Bool = (attributes & _FFS_ATTR_LARGE) != 0;
  var header_size: Int = _FFS_HEADER_SIZE;
  var size: Int = 0;
  if large {
    if n < _FFS_HEADER2_SIZE { return _err_file("efi: truncated header"); }
    header_size = _FFS_HEADER2_SIZE;
    let size_field: Int = _u24(data, 20);
    if size_field != _FFS_EXT_SIZE { return _err_file("efi: bad large-file size"); }
    size = _le64(data, 24);
    if size < 0 { return _err_file("efi: bad file size"); }
  } else {
    size = _u24(data, 20);
  }
  if size < header_size { return _err_file("efi: bad file size"); }
  if size > n { return _err_file("efi: truncated file"); }
  let name: Str = _hex_at(data, 0);
  let integrity: Int = _u16(data, 16);
  let ftype: Int = _byte(data, 18);
  let state: Int = _byte(data, 23);
  var sec_types = Vec[Int].new();
  var sec_sizes = Vec[Int].new();
  var sec_offsets = Vec[Int].new();
  var sec_data_offsets = Vec[Int].new();
  var sec_data_sizes = Vec[Int].new();
  var pos = header_size;
  var stop = false;
  while pos < size && !stop {
    let remaining: Int = size - pos;
    if _all_zero(data, pos, remaining) {
      stop = true;
    } else {
      if remaining < _FFS_SECTION_HEADER { return _err_file("efi: truncated section"); }
      let ssize: Int = _u24(data, pos);
      let stype: Int = _byte(data, pos + 3);
      if ssize < _FFS_SECTION_HEADER { return _err_file("efi: bad section size"); }
      if ssize > remaining { return _err_file("efi: section overruns file"); }
      var data_off: Int = pos + _FFS_SECTION_HEADER;
      var data_size: Int = ssize - _FFS_SECTION_HEADER;
      if stype == _SEC_COMPRESSION {
        if ssize < 8 { return _err_file("efi: section too small"); }
        data_off = pos + 8;
        data_size = ssize - 8;
      } elif stype == _SEC_GUID_DEFINED {
        if ssize < 24 { return _err_file("efi: section too small"); }
        let header_off: Int = _u16(data, pos + 20);
        if header_off < 20 { return _err_file("efi: bad section data offset"); }
        if header_off > ssize { return _err_file("efi: bad section data offset"); }
        data_off = pos + header_off;
        data_size = ssize - header_off;
      } elif stype == _SEC_FREEFORM_SUBTYPE_GUID {
        if ssize < 20 { return _err_file("efi: section too small"); }
        data_off = pos + 20;
        data_size = ssize - 20;
      } elif stype == _SEC_VERSION {
        if ssize < 8 { return _err_file("efi: section too small"); }
        data_off = pos + _FFS_SECTION_HEADER;
        data_size = ssize - _FFS_SECTION_HEADER;
      } elif stype == _SEC_UI {
        if !_ui_ok(data, data_off, data_size) { return _err_file("efi: bad ui string"); }
      }
      sec_types.push(stype);
      sec_sizes.push(ssize);
      sec_offsets.push(pos);
      sec_data_offsets.push(data_off);
      sec_data_sizes.push(data_size);
      pos = pos + ssize;
    }
  }
  let file = FfsFile{
    name: name;
    integrity_check: integrity;
    file_type: ftype;
    attributes: attributes;
    size: size;
    state: state;
    large: large;
    header_size: header_size;
    section_types: sec_types;
    section_sizes: sec_sizes;
    section_offsets: sec_offsets;
    section_data_offsets: sec_data_offsets;
    section_data_sizes: sec_data_sizes;
  };
  return _ok_file(file);
}

// --------------------------------------------------
//  Public API -- file accessors
// --------------------------------------------------

/// File name GUID as the 32 lowercase hex characters of the 16 raw on-disk
/// bytes. Complexity: O(1).
pub fn ffs_file_name(f: &FfsFile) -> Str {
  let s: Str = f.name;
  return s;
}

/// Raw file type byte (0..255); stored as parsed, never validated.
/// Complexity: O(1).
pub fn ffs_file_type(f: &FfsFile) -> Int {
  return f.file_type;
}

/// Name of the documented file type `t` (SPEC.md "File types"): the named
/// subset, "OEM" for 224..239, "PAD" for 240, "FFS" for 241..254,
/// "FREE_SPACE" for 255 and "UNKNOWN" otherwise. Complexity: O(1).
pub fn ffs_file_type_name(t: Int) -> Str {
  if t == _FFS_RAW { return "RAW"; }
  if t == _FFS_FREEFORM { return "FREEFORM"; }
  if t == _FFS_SECURITY_CORE { return "SECURITY_CORE"; }
  if t == _FFS_PEI_CORE { return "PEI_CORE"; }
  if t == _FFS_DXE_CORE { return "DXE_CORE"; }
  if t == _FFS_DRIVER { return "DRIVER"; }
  if t == _FFS_APPLICATION { return "APPLICATION"; }
  if t == _FFS_SMM { return "SMM"; }
  if t == _FFS_FIRMWARE_VOLUME_IMAGE { return "FIRMWARE_VOLUME_IMAGE"; }
  if t == _FFS_COMBINED_PEIM { return "COMBINED_PEIM"; }
  if t == _FFS_PEIM { return "PEIM"; }
  if t == _FFS_DXE_DRIVER { return "DXE_DRIVER"; }
  if t == _FFS_SMM_DRIVER { return "SMM_DRIVER"; }
  if t == _FFS_SMM_CORE { return "SMM_CORE"; }
  if t >= _FFS_OEM_MIN && t <= _FFS_OEM_MAX { return "OEM"; }
  if t == _FFS_PAD { return "PAD"; }
  if t >= _FFS_FFS_MIN && t <= _FFS_FFS_MAX { return "FFS"; }
  if t == _FFS_FREE_SPACE { return "FREE_SPACE"; }
  return "UNKNOWN";
}

/// Raw attributes byte (0..255). Bit 0x01 is FFS_ATTRIB_LARGE_FILE, bit 0x40
/// is FFS_ATTRIB_CHECKSUM; all other bits are preserved raw.
/// Complexity: O(1).
pub fn ffs_file_attributes(f: &FfsFile) -> Int {
  return f.attributes;
}

/// Declared file size in bytes: the 24-bit Size field for small files, the
/// 64-bit ExtendedSize for large files. Complexity: O(1).
pub fn ffs_file_size(f: &FfsFile) -> Int {
  return f.size;
}

/// Raw state byte (0..255), stored as parsed. Complexity: O(1).
pub fn ffs_file_state(f: &FfsFile) -> Int {
  return f.state;
}

/// Raw 16-bit integrity check, stored exactly as in the header. Use
/// `ffs_integrity_ok` for the documented verification stance.
/// Complexity: O(1).
pub fn ffs_file_integrity_check(f: &FfsFile) -> Int {
  return f.integrity_check;
}

/// True when the large-file attribute is set. Complexity: O(1).
pub fn ffs_file_is_large(f: &FfsFile) -> Bool {
  return f.large;
}

/// Header size in bytes: 24 for small files, 32 for large files.
/// Complexity: O(1).
pub fn ffs_file_header_size(f: &FfsFile) -> Int {
  return f.header_size;
}

// --------------------------------------------------
//  Public API -- section accessors
// --------------------------------------------------

/// Safe section count: the minimum of the five parallel section vector
/// lengths. A parsed file reports the number of sections walked.
/// Complexity: O(1).
pub fn ffs_section_count(f: &FfsFile) -> Int {
  return _sec_min(f);
}

/// Raw section type byte of section `i`; -1 when `i` is negative or out of
/// range. Complexity: O(1).
pub fn ffs_section_type(f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let v: Int = f.section_types[i];
  return v;
}

/// Name of the documented section type `t` (SPEC.md "Section types"), or
/// "UNKNOWN". Complexity: O(1).
pub fn ffs_section_type_name(t: Int) -> Str {
  if t == _SEC_COMPRESSION { return "COMPRESSION"; }
  if t == _SEC_GUID_DEFINED { return "GUID_DEFINED"; }
  if t == _SEC_DISPOSABLE { return "DISPOSABLE"; }
  if t == _SEC_PE32 { return "PE32"; }
  if t == _SEC_PIC { return "PIC"; }
  if t == _SEC_TE { return "TE"; }
  if t == _SEC_DXE_DEPEX { return "DXE_DEPEX"; }
  if t == _SEC_VERSION { return "VERSION"; }
  if t == _SEC_UI { return "USER_INTERFACE"; }
  if t == _SEC_COMPATIBILITY16 { return "COMPATIBILITY16"; }
  if t == _SEC_FIRMWARE_VOLUME_IMAGE { return "FIRMWARE_VOLUME_IMAGE"; }
  if t == _SEC_FREEFORM_SUBTYPE_GUID { return "FREEFORM_SUBTYPE_GUID"; }
  if t == _SEC_RAW { return "RAW"; }
  if t == _SEC_PEI_DEPEX { return "PEI_DEPEX"; }
  if t == _SEC_SMM_DEPEX { return "SMM_DEPEX"; }
  return "UNKNOWN";
}

/// Declared total size in bytes of section `i` (common header + type header
/// + data + alignment padding); -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn ffs_section_size(f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let v: Int = f.section_sizes[i];
  return v;
}

/// Absolute offset of the first byte of section `i` (its common header);
/// -1 when `i` is negative or out of range. Complexity: O(1).
pub fn ffs_section_offset(f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let v: Int = f.section_offsets[i];
  return v;
}

/// Absolute offset of the first data byte of section `i` (the byte after the
/// documented per-type header); -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn ffs_section_data_offset(f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let v: Int = f.section_data_offsets[i];
  return v;
}

/// Data byte count of section `i` (declared size minus the documented
/// per-type header size; for a UI section this includes the terminal NUL and
/// any alignment padding); -1 when `i` is negative or out of range.
/// Complexity: O(1).
pub fn ffs_section_data_size(f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let v: Int = f.section_data_sizes[i];
  return v;
}

// --------------------------------------------------
//  Public API -- raw spans
// --------------------------------------------------

/// Copy the whole raw section `i` (common header, type header, data and
/// alignment padding) out of `data`.
///
/// Err("efi: index out of range") when `i` is negative or >= section count;
/// Err("efi: span out of bounds") when the recorded span does not fit in
/// `data`. Complexity: O(section size).
pub fn ffs_section_raw(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 { return _err_bytes("efi: index out of range"); }
  if i >= _sec_min(f) { return _err_bytes("efi: index out of range"); }
  let off: Int = f.section_offsets[i];
  let len: Int = f.section_sizes[i];
  return _copy_span(data, off, len);
}

/// Copy the data bytes of section `i` (the section minus its documented
/// per-type header) out of `data`. The bytes are returned verbatim, so a UI
/// section includes its terminal NUL and a padded section includes its
/// alignment padding.
///
/// Err("efi: index out of range") when `i` is negative or >= section count;
/// Err("efi: span out of bounds") when the recorded span does not fit in
/// `data`. Complexity: O(section data size).
pub fn ffs_section_data(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 { return _err_bytes("efi: index out of range"); }
  if i >= _sec_min(f) { return _err_bytes("efi: index out of range"); }
  let off: Int = f.section_data_offsets[i];
  let len: Int = f.section_data_sizes[i];
  return _copy_span(data, off, len);
}

// --------------------------------------------------
//  Public API -- type-specific readers
// --------------------------------------------------

/// VERSION section (0x14) BuildNumber field (u16 LE), or -1 when section `i`
/// is not a VERSION section, is out of range, or its recorded span does not
/// cover the 4-byte documented payload. Complexity: O(1).
pub fn ffs_section_build_number(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let stype: Int = f.section_types[i];
  if stype != _SEC_VERSION { return -1; }
  if !_sec_span_ok(data, f, i) { return -1; }
  if f.section_data_sizes[i] < 4 { return -1; }
  let off: Int = f.section_data_offsets[i];
  return _u16(data, off);
}

/// VERSION section (0x14) Version field (u16 LE), or -1 when section `i` is
/// not a VERSION section, is out of range, or its recorded span does not
/// cover the 4-byte documented payload. Complexity: O(1).
pub fn ffs_section_version(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let stype: Int = f.section_types[i];
  if stype != _SEC_VERSION { return -1; }
  if !_sec_span_ok(data, f, i) { return -1; }
  if f.section_data_sizes[i] < 4 { return -1; }
  let off: Int = f.section_data_offsets[i];
  return _u16(data, off + 2);
}

/// USER_INTERFACE section (0x15) string decoded from UTF-16LE to printable
/// ASCII (stop at the first 0x0000, non-ASCII code units become '?'); ""
/// when section `i` is not a UI section, is out of range, or its recorded
/// span does not fit in `data`. Complexity: O(section data size).
pub fn ffs_section_ui_string(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= _sec_min(f) { return ""; }
  let stype: Int = f.section_types[i];
  if stype != _SEC_UI { return ""; }
  if !_sec_span_ok(data, f, i) { return ""; }
  let off: Int = f.section_data_offsets[i];
  let len: Int = f.section_data_sizes[i];
  return _ui_decode(data, off, off + len);
}

/// GUID of a GUID_DEFINED (0x02) or FREEFORM_SUBTYPE_GUID (0x18) section as
/// 32 lowercase hex characters of the raw on-disk bytes; "" for any other
/// type, an out-of-range index, or a recorded span that does not cover the
/// 16 GUID bytes. Complexity: O(1).
pub fn ffs_section_guid(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= _sec_min(f) { return ""; }
  let stype: Int = f.section_types[i];
  if stype != _SEC_GUID_DEFINED && stype != _SEC_FREEFORM_SUBTYPE_GUID { return ""; }
  let so: Int = f.section_offsets[i];
  if so < 0 { return ""; }
  if so + 20 > data.len() { return ""; }
  return _hex_at(data, so + 4);
}

/// GUID_DEFINED section (0x02) DataOffset field (u16 LE, measured from the
/// start of the section header); -1 for any other type, an out-of-range
/// index, or a span that does not hold the 20-byte documented header.
/// Complexity: O(1).
pub fn ffs_section_guid_data_offset(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let stype: Int = f.section_types[i];
  if stype != _SEC_GUID_DEFINED { return -1; }
  let so: Int = f.section_offsets[i];
  if so < 0 { return -1; }
  if so + 24 > data.len() { return -1; }
  return _u16(data, so + 20);
}

/// GUID_DEFINED section (0x02) Attributes field (u16 LE); -1 for any other
/// type, an out-of-range index, or a span that does not hold the 20-byte
/// documented header. Complexity: O(1).
pub fn ffs_section_guid_attributes(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let stype: Int = f.section_types[i];
  if stype != _SEC_GUID_DEFINED { return -1; }
  let so: Int = f.section_offsets[i];
  if so < 0 { return -1; }
  if so + 24 > data.len() { return -1; }
  return _u16(data, so + 22);
}

/// COMPRESSION section (0x01) UncompressedLength field (u32 LE); -1 for any
/// other type, an out-of-range index, or a span that does not hold the
/// 8-byte documented header. The compressed payload stays raw and is never
/// decompressed. Complexity: O(1).
pub fn ffs_section_compression_length(data: &Vec[UInt8], f: &FfsFile, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _sec_min(f) { return -1; }
  let stype: Int = f.section_types[i];
  if stype != _SEC_COMPRESSION { return -1; }
  let so: Int = f.section_offsets[i];
  if so < 0 { return -1; }
  if so + 8 > data.len() { return -1; }
  return _le32(data, so + 4);
}

// --------------------------------------------------
//  Public API -- integrity checks
// --------------------------------------------------

/// Documented 8-bit header checksum: the value that must be stored in the
/// low integrity byte so that the sum of the header bytes (the low integrity
/// byte itself treated as zero, all other bytes as stored, including the
/// high integrity byte and the extended size) is 0 modulo 256. -1 when the
/// recorded header/size span does not fit in `data`. Complexity:
/// O(header_size).
pub fn ffs_header_checksum(data: &Vec[UInt8], f: &FfsFile) -> Int {
  if !_file_spans_ok(data, f) { return -1; }
  let s: Int = _span_sum(data, 0, f.header_size, 16);
  return (256 - s % 256) % 256;
}

/// Documented 8-bit data checksum: the value that must be stored in the high
/// integrity byte so that the sum of the file data bytes (header_size..size)
/// is 0 modulo 256. -1 when the recorded span does not fit in `data`.
/// Complexity: O(size - header_size).
pub fn ffs_data_checksum(data: &Vec[UInt8], f: &FfsFile) -> Int {
  if !_file_spans_ok(data, f) { return -1; }
  let s: Int = _span_sum(data, f.header_size, f.size - f.header_size, -1);
  return (256 - s % 256) % 256;
}

/// Documented integrity-check stance.
///
/// When FFS_ATTRIB_CHECKSUM (0x40) is clear, the 16-bit integrity check must
/// be the zero vector; when it is set, the low byte must equal
/// `ffs_header_checksum` and the high byte must equal `ffs_data_checksum`.
/// `ffs_parse` never rejects a mismatch; call this helper explicitly. False
/// when the recorded header/size span does not fit in `data`.
/// Complexity: O(size).
pub fn ffs_integrity_ok(data: &Vec[UInt8], f: &FfsFile) -> Bool {
  if !_file_spans_ok(data, f) { return false; }
  if (f.attributes & _FFS_ATTR_CHECKSUM) == 0 {
    return f.integrity_check == 0;
  }
  let want_header: Int = ffs_header_checksum(data, f);
  let want_file: Int = ffs_data_checksum(data, f);
  if want_header < 0 { return false; }
  if want_file < 0 { return false; }
  let stored: Int = f.integrity_check;
  let sh: Int = stored % 256;
  let sf: Int = (stored / 256) % 256;
  return sh == want_header && sf == want_file;
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

// True when `body` satisfies the documented per-type header for a section of
// type `stype`: minimum size, the GUID-defined data offset window and the UI
// terminal NUL. Unknown types accept any body.
fn _section_body_ok(stype: Int, body: &Vec[UInt8]) -> Bool {
  let n = body.len();
  if stype == _SEC_COMPRESSION {
    if n < 4 { return false; }
  } elif stype == _SEC_GUID_DEFINED {
    if n < 20 { return false; }
    let data_off: Int = _u16(body, 16);
    if data_off < 20 { return false; }
    if data_off > _FFS_SECTION_HEADER + n { return false; }
  } elif stype == _SEC_FREEFORM_SUBTYPE_GUID {
    if n < 16 { return false; }
  } elif stype == _SEC_VERSION {
    if n < 4 { return false; }
  } elif stype == _SEC_UI {
    if !_ui_ok(body, 0, n) { return false; }
  }
  return true;
}

// Overwrite the 16-bit integrity check of a checksum-attributed file: the
// high byte (data checksum) first, then the low byte (header checksum,
// computed over the header with its own byte treated as zero and the data
// byte already in place). A single helper patches both bytes so the mutable
// reference is never held across two borrows of the same buffer.
fn _seal_integrity(out: &mut Vec[UInt8], header_size: Int, total: Int) {
  let ds: Int = (256 - _span_sum(out, header_size, total - header_size, -1) % 256) % 256;
  out[17] = ds as UInt8;
  let hs: Int = (256 - _span_sum(out, 0, header_size, 16) % 256) % 256;
  out[16] = hs as UInt8;
}

/// Build one canonical FFS file containing exactly one section.
///
/// The file always uses the 24-byte small header; `name` is re-encoded from
/// the 32 hex characters to the 16 raw GUID bytes, and the caller's type,
/// attributes and state bytes are written verbatim. `section_type` is the
/// common section type byte and `body` is the section body *after* the
/// 4-byte common header, including any documented per-type header bytes
/// (e.g. the 4-byte VERSION payload or the 20-byte GUID_DEFINED header). The
/// builder appends zero padding to the next 4-byte section boundary and then
/// to the next 8-byte file boundary; the declared size fields include that
/// padding.
///
/// The integrity check is always written: 0x0000 when FFS_ATTRIB_CHECKSUM is
/// clear, otherwise the documented additive 8-bit header and data checksums
/// (header byte first, computed with its own byte zeroed). Large-file
/// attributes are rejected because the canonical builder never emits the
/// 32-byte header.
///
/// Params: name - 32 hex characters; file_type/attributes/state - bytes
/// 0..255; section_type - byte 0..255; body - section body, read only.
/// Returns: Ok(bytes) whose length is a multiple of 8.
/// Error case: Err("efi: bad name"), Err("efi: bad file type"),
/// Err("efi: bad attributes"), Err("efi: large files unsupported"),
/// Err("efi: bad state"), Err("efi: bad section type"),
/// Err("efi: bad section body") for a body that violates the documented
/// per-type minimums, or Err("efi: file too large") when the padded file
/// would not fit the 24-bit size field.
/// Complexity: O(body length).
pub fn ffs_build(name: Str, file_type: Int, attributes: Int, state: Int, section_type: Int, body: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_name_ok(name) { return _err_bytes("efi: bad name"); }
  if file_type < 0 || file_type > 255 { return _err_bytes("efi: bad file type"); }
  if attributes < 0 || attributes > 255 { return _err_bytes("efi: bad attributes"); }
  if (attributes & _FFS_ATTR_LARGE) != 0 { return _err_bytes("efi: large files unsupported"); }
  if state < 0 || state > 255 { return _err_bytes("efi: bad state"); }
  if section_type < 0 || section_type > 255 { return _err_bytes("efi: bad section type"); }
  if !_section_body_ok(section_type, body) { return _err_bytes("efi: bad section body"); }
  var sec_size: Int = _FFS_SECTION_HEADER + body.len();
  let sec_pad: Int = (4 - sec_size % 4) % 4;
  sec_size = sec_size + sec_pad;
  var total: Int = _FFS_HEADER_SIZE + sec_size;
  let file_pad: Int = (8 - total % 8) % 8;
  total = total + file_pad;
  if total > _FFS_SIZE_MAX { return _err_bytes("efi: file too large"); }
  var out = Vec[UInt8].new();
  _name_push(name, &mut out);
  _push_le(&mut out, 0, 2);
  out.push(file_type as UInt8);
  out.push(attributes as UInt8);
  _push_le(&mut out, total, 3);
  out.push(state as UInt8);
  _push_le(&mut out, sec_size, 3);
  out.push(section_type as UInt8);
  _push_bytes(&mut out, body);
  _push_zero(&mut out, sec_pad);
  _push_zero(&mut out, file_pad);
  if (attributes & _FFS_ATTR_CHECKSUM) != 0 {
    _seal_integrity(&mut out, _FFS_HEADER_SIZE, total);
  }
  return _ok_bytes(out);
}
