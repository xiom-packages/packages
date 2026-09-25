// XIOM -- xiom.tzif: RFC 8536 TZif time zone file codec (v1/v2/v3)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a TZif codec for file
// versions 1, 2 and 3: the 44-byte header, the version 1 data block, the
// repeated version 2+ header and 64-bit data block, and the raw footer.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - tzif_parse validates the header magic, the version byte, the RFC 8536
//   count rules (typecnt != 0, charcnt != 0, isstdcnt/isutcnt either 0 or
//   typecnt), the computed block size against the buffer, the parsed block
//   contents (transition type index < typecnt, designation index < charcnt
//   with a NUL at or after every index, isdst 0/1, indicators 0/1, utoff
//   != -2^31) and the footer framing of versions 2/3.
// - The result is a TzifFile of flat parallel vectors: one element per
//   transition (times, type_indices), per local time type (utoffs, isdsts,
//   desig_indices, designations), per leap record (leap_occurs,
//   leap_corrections) and per indicator (isstd, isut). No Vec of structs.
// - Version 2/3 files expose the 64-bit data block; the version 1 block is
//   checked for its header counts and total size and then skipped (RFC 8536
//   section 4 says readers should ignore it). The footer TZ string is kept
//   as a raw token and never parsed (no POSIX TZ string interpretation).
// - All multi-octet integers are big-endian (network byte order), for the
//   32-bit and the 64-bit fields alike, as RFC 8536 section 3 requires.
// - tzif_build_v1 writes version 1 only. It rebuilds the designation table
//   canonically (each type's string + NUL, in type order) and recomputes
//   the designation indices; the stored desig_indices are not used.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Result payloads inside other functions miscompiles).
//   * every Vec[UInt8] byte read is widened with `(b as Int) & 0xFF`.
//   * all big-endian extraction/packing is arithmetic (modulo/division)
//     because `& 0xFF` on operands with bit 31 set miscompiles (same bug
//     documented in xiom.tlv and xiom.msgpack).
//   * Str values read from Vec[Str] are bound to typed locals; the module
//     performs no `==` on Str values at all.

module xiom.tzif

use xiom.string;

/// Parsed TZif file.
///
/// The scalar count fields describe the exposed block: the only block of a
/// version 1 file, or the 64-bit second block of a version 2/3 file (the
/// version 1 block of versions 2/3 is skipped, see tzif_parse). The vectors
/// are flat parallel columns, one push per iteration, so a parsed file
/// always has intact parallel vectors. The version 1 designation table
/// bytes are decoded per local time type with the RFC 8536 rule: the string
/// begins at the record's desigidx and runs to the first NUL at or after
/// it (designations may overlap, and the string may be empty). `footer`
/// carries the raw TZ string of a version 2/3 footer without its two NUL
/// line delimiters; it is "" for version 1 files and for an empty TZ
/// string.
pub type TzifFile = {
  version: Int;
  timecnt: Int;
  typecnt: Int;
  leapcnt: Int;
  charcnt: Int;
  isstdcnt: Int;
  isutcnt: Int;
  times: Vec[Int];
  type_indices: Vec[Int];
  utoffs: Vec[Int];
  isdsts: Vec[Int];
  desig_indices: Vec[Int];
  designations: Vec[Str];
  leap_occurs: Vec[Int];
  leap_corrections: Vec[Int];
  isstd: Vec[Int];
  isut: Vec[Int];
  footer: Str;
}

// Header counts of one block (the version 1 header or the version 2+
// header). Field order matches the wire layout of the header tail.
type _Counts = {
  isutcnt: Int;
  isstdcnt: Int;
  leapcnt: Int;
  timecnt: Int;
  typecnt: Int;
  charcnt: Int;
}

// Parallel vectors of one parsed data block.
type _Block = {
  times: Vec[Int];
  type_indices: Vec[Int];
  utoffs: Vec[Int];
  isdsts: Vec[Int];
  desig_indices: Vec[Int];
  designations: Vec[Str];
  leap_occurs: Vec[Int];
  leap_corrections: Vec[Int];
  isstd: Vec[Int];
  isut: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[TzifFile, Str].
fn _ok_file(v: TzifFile) -> Result[TzifFile, Str] {
  return Ok(v);
}

// Err(m) for Result[TzifFile, Str].
fn _err_file(m: Str) -> Result[TzifFile, Str] {
  return Err(m);
}

// Ok(v) for Result[_Block, Str].
fn _ok_block(v: _Block) -> Result[_Block, Str] {
  return Ok(v);
}

// Err(m) for Result[_Block, Str].
fn _err_block(m: Str) -> Result[_Block, Str] {
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

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
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

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian 32-bit value at `pos` (0..2^32-1).
// The caller guarantees pos + 4 <= data.len().
fn _read_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Signed big-endian 32-bit value at `pos` (two's complement).
fn _read_i32(data: &Vec[UInt8], pos: Int) -> Int {
  let u = _read_u32(data, pos);
  if u >= 2147483648 {
    return u - 4294967296;
  }
  return u;
}

// Signed big-endian 64-bit value at `pos` (two's complement).
//
// The single 64-bit pattern whose magnitude is 2^63 (0x8000000000000000,
// INT64_MIN) cannot be negated in the 64-bit Int type, so it is rejected
// with Err("tzif: 64-bit value out of Int range"); every other 64-bit
// pattern, negative or positive, is returned exactly.
fn _read_i64(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  let hi = _read_u32(data, pos);
  let lo = _read_u32(data, pos + 4);
  if hi < 2147483648 {
    return _ok_int(lo + hi * 4294967296);
  }
  if hi == 2147483648 && lo == 0 {
    return _err_int("tzif: 64-bit value out of Int range");
  }
  var mag_hi = 0;
  var mag_lo = 0;
  if lo == 0 {
    mag_hi = 4294967296 - hi;
  } else {
    mag_hi = 4294967296 - hi - 1;
    mag_lo = 4294967296 - lo;
  }
  return _ok_int(0 - (mag_hi * 4294967296 + mag_lo));
}

// Byte `shift` of `v` in two's complement (0 = least significant byte).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3, and this form is exact for negative values.
fn _be_byte(v: Int, shift: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift {
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

// --------------------------------------------------
//  Internal header helpers
// --------------------------------------------------

// True when the four bytes at `off` are the ASCII magic "TZif".
fn _magic_ok(data: &Vec[UInt8], off: Int) -> Bool {
  if _byte(data, off) != 84 { return false; }
  if _byte(data, off + 1) != 90 { return false; }
  if _byte(data, off + 2) != 105 { return false; }
  if _byte(data, off + 3) != 102 { return false; }
  return true;
}

// File version number for a version byte: 1 for NUL, 2 for '2', 3 for '3',
// 0 for any unsupported byte. The caller guarantees one readable byte.
fn _version_number(b: Int) -> Int {
  if b == 0 { return 1; }
  if b == 50 { return 2; }
  if b == 51 { return 3; }
  return 0;
}

// The six count fields at `off` (isutcnt, isstdcnt, leapcnt, timecnt,
// typecnt, charcnt). The caller guarantees off + 24 <= data.len().
fn _read_counts(data: &Vec[UInt8], off: Int) -> _Counts {
  return _Counts{
    isutcnt: _read_u32(data, off);
    isstdcnt: _read_u32(data, off + 4);
    leapcnt: _read_u32(data, off + 8);
    timecnt: _read_u32(data, off + 12);
    typecnt: _read_u32(data, off + 16);
    charcnt: _read_u32(data, off + 20);
  };
}

// True when the RFC 8536 count rules hold for one block: typecnt and
// charcnt must be nonzero and each indicator count must be 0 or typecnt.
fn _counts_ok(c: _Counts) -> Bool {
  if c.typecnt == 0 { return false; }
  if c.charcnt == 0 { return false; }
  if c.isstdcnt != 0 && c.isstdcnt != c.typecnt { return false; }
  if c.isutcnt != 0 && c.isutcnt != c.typecnt { return false; }
  return true;
}

// The documented message for the first count rule _counts_ok rejects. Only
// called when _counts_ok(c) is false.
fn _counts_err(c: _Counts) -> Str {
  if c.typecnt == 0 { return "tzif: zero time type count"; }
  if c.charcnt == 0 { return "tzif: zero designation count"; }
  if c.isstdcnt != 0 && c.isstdcnt != c.typecnt { return "tzif: standard indicator count mismatch"; }
  return "tzif: UT indicator count mismatch";
}

// Total byte size of the data block described by `c` whose time fields are
// `time_size` bytes wide (4 for version 1, 8 for version 2/3).
fn _block_size(c: _Counts, time_size: Int) -> Int {
  return c.timecnt * (time_size + 1) + c.typecnt * 6 + c.charcnt + c.leapcnt * (time_size + 4) + c.isstdcnt + c.isutcnt;
}

// --------------------------------------------------
//  Internal data block parser
// --------------------------------------------------

// Parse and validate one data block starting at `off`, with time fields
// `time_size` bytes wide. The caller guarantees that the whole block fits
// in `data` (off + _block_size(c, time_size) <= data.len()).
//
// Validation order: transition type indices, then ttinfo records (utoff
// != -2^31, isdst 0/1, desigidx < charcnt), then designation decoding (a
// NUL must exist at or after every desigidx), then leap records, then
// indicator bytes 0/1, then the UT/local => standard/wall implication.
fn _parse_block(data: &Vec[UInt8], off: Int, time_size: Int, c: _Counts) -> Result[_Block, Str] {
  var times = Vec[Int].new();
  var type_indices = Vec[Int].new();
  var utoffs = Vec[Int].new();
  var isdsts = Vec[Int].new();
  var desig_indices = Vec[Int].new();
  var designations = Vec[Str].new();
  var leap_occurs = Vec[Int].new();
  var leap_corrections = Vec[Int].new();
  var isstd = Vec[Int].new();
  var isut = Vec[Int].new();
  var pos = off;
  var i = 0;
  while i < c.timecnt {
    if time_size == 8 {
      let r = _read_i64(data, pos);
      if !r.is_ok {
        let m: Str = r.error;
        return _err_block(m);
      }
      let t64: Int = r.value;
      times.push(t64);
    } else {
      times.push(_read_i32(data, pos));
    }
    pos = pos + time_size;
    i = i + 1;
  }
  i = 0;
  while i < c.timecnt {
    let b: Int = _byte(data, pos);
    if b >= c.typecnt {
      return _err_block("tzif: transition type index out of range");
    }
    type_indices.push(b);
    pos = pos + 1;
    i = i + 1;
  }
  i = 0;
  while i < c.typecnt {
    let u = _read_i32(data, pos);
    if u == -2147483648 {
      return _err_block("tzif: invalid UT offset");
    }
    let dst: Int = _byte(data, pos + 4);
    if dst != 0 && dst != 1 {
      return _err_block("tzif: invalid DST flag");
    }
    let di: Int = _byte(data, pos + 5);
    if di >= c.charcnt {
      return _err_block("tzif: designation index out of range");
    }
    utoffs.push(u);
    isdsts.push(dst);
    desig_indices.push(di);
    pos = pos + 6;
    i = i + 1;
  }
  let desig_base = pos;
  pos = pos + c.charcnt;
  i = 0;
  while i < c.typecnt {
    let di2: Int = desig_indices[i];
    var bytes = Vec[UInt8].new();
    var k = di2;
    var done = false;
    while k < c.charcnt && !done {
      let b2: Int = _byte(data, desig_base + k);
      if b2 == 0 {
        done = true;
      } else {
        bytes.push(b2 as UInt8);
      }
      k = k + 1;
    }
    if !done {
      return _err_block("tzif: unterminated designation");
    }
    designations.push(Str::from_utf8(bytes));
    i = i + 1;
  }
  i = 0;
  while i < c.leapcnt {
    if time_size == 8 {
      let r2 = _read_i64(data, pos);
      if !r2.is_ok {
        let m2: Str = r2.error;
        return _err_block(m2);
      }
      let o64: Int = r2.value;
      leap_occurs.push(o64);
      leap_corrections.push(_read_i32(data, pos + 8));
      pos = pos + 12;
    } else {
      leap_occurs.push(_read_i32(data, pos));
      leap_corrections.push(_read_i32(data, pos + 4));
      pos = pos + 8;
    }
    i = i + 1;
  }
  i = 0;
  while i < c.isstdcnt {
    let b3: Int = _byte(data, pos);
    if b3 != 0 && b3 != 1 {
      return _err_block("tzif: invalid indicator value");
    }
    isstd.push(b3);
    pos = pos + 1;
    i = i + 1;
  }
  i = 0;
  while i < c.isutcnt {
    let b4: Int = _byte(data, pos);
    if b4 != 0 && b4 != 1 {
      return _err_block("tzif: invalid indicator value");
    }
    isut.push(b4);
    pos = pos + 1;
    i = i + 1;
  }
  if c.isstdcnt == c.typecnt && c.isutcnt == c.typecnt {
    i = 0;
    while i < c.typecnt {
      let ss: Int = isstd[i];
      let uu: Int = isut[i];
      if uu == 1 && ss != 1 {
        return _err_block("tzif: UT indicator without standard indicator");
      }
      i = i + 1;
    }
  }
  let block = _Block{
    times: times;
    type_indices: type_indices;
    utoffs: utoffs;
    isdsts: isdsts;
    desig_indices: desig_indices;
    designations: designations;
    leap_occurs: leap_occurs;
    leap_corrections: leap_corrections;
    isstd: isstd;
    isut: isut;
  };
  return _ok_block(block);
}

// Assemble a TzifFile from one parsed block and its counts.
fn _file_from(version: Int, c: _Counts, b: _Block, footer: Str) -> TzifFile {
  return TzifFile{
    version: version;
    timecnt: c.timecnt;
    typecnt: c.typecnt;
    leapcnt: c.leapcnt;
    charcnt: c.charcnt;
    isstdcnt: c.isstdcnt;
    isutcnt: c.isutcnt;
    times: b.times;
    type_indices: b.type_indices;
    utoffs: b.utoffs;
    isdsts: b.isdsts;
    desig_indices: b.desig_indices;
    designations: b.designations;
    leap_occurs: b.leap_occurs;
    leap_corrections: b.leap_corrections;
    isstd: b.isstd;
    isut: b.isut;
    footer: footer;
  };
}

// --------------------------------------------------
//  Public API -- parsing and accessors
// --------------------------------------------------

/// Parse a TZif file (RFC 8536, versions 1, 2 and 3).
///
/// Validation order (first failure wins): a buffer shorter than 44 bytes ->
/// Err("tzif: truncated header"); magic bytes must be "TZif" ->
/// Err("tzif: bad magic"); the version byte must be NUL, '2' or '3' ->
/// Err("tzif: unsupported version"); the version 1 header counts must
/// satisfy the RFC rules -> Err("tzif: zero time type count"),
/// Err("tzif: zero designation count"),
/// Err("tzif: standard indicator count mismatch") or
/// Err("tzif: UT indicator count mismatch"); the version 1 data block must
/// fit -> Err("tzif: data block overruns buffer").
///
/// Version 1: any byte after the data block is Err("tzif: trailing bytes");
/// otherwise the block is parsed and exposed.
///
/// Versions 2/3: the version 1 block is skipped (only its header counts and
/// total size are checked); the second header must fit ->
/// Err("tzif: truncated second header"), carry the magic ->
/// Err("tzif: bad second header magic") and repeat the version byte ->
/// Err("tzif: second header version mismatch"); the second header counts
/// must satisfy the same RFC rules; the 64-bit block must fit ->
/// Err("tzif: data block overruns buffer"); the footer must be a NUL-DEL
/// (0x0A) pair delimiting the TZ string -> Err("tzif: missing footer"),
/// the TZ string must contain no NUL -> Err("tzif: NUL in footer"), and
/// nothing may follow the closing 0x0A -> Err("tzif: trailing bytes").
///
/// Data block contents: every transition type index must be < typecnt ->
/// Err("tzif: transition type index out of range"); every utoff must not
/// be -2^31 -> Err("tzif: invalid UT offset"); every isdst byte must be
/// 0/1 -> Err("tzif: invalid DST flag"); every desigidx must be < charcnt
/// -> Err("tzif: designation index out of range"); every designation must
/// be NUL-terminated at or after its index ->
/// Err("tzif: unterminated designation"); every indicator byte must be
/// 0/1 -> Err("tzif: invalid indicator value"); when both indicator tables
/// are present, a UT/local value of 1 requires the matching standard/wall
/// value to be 1 -> Err("tzif: UT indicator without standard indicator").
/// A 64-bit field equal to 0x8000000000000000 is
/// Err("tzif: 64-bit value out of Int range").
///
/// The footer bytes are kept raw; no POSIX TZ string parsing is performed.
/// Complexity: O(data.len()).
pub fn tzif_parse(data: &Vec[UInt8]) -> Result[TzifFile, Str] {
  let n = data.len();
  if n < 44 { return _err_file("tzif: truncated header"); }
  if !_magic_ok(data, 0) { return _err_file("tzif: bad magic"); }
  let version = _version_number(_byte(data, 4));
  if version == 0 { return _err_file("tzif: unsupported version"); }
  let c1 = _read_counts(data, 20);
  if !_counts_ok(c1) { return _err_file(_counts_err(c1)); }
  let v1_size = _block_size(c1, 4);
  if 44 + v1_size > n { return _err_file("tzif: data block overruns buffer"); }
  if version == 1 {
    if 44 + v1_size != n { return _err_file("tzif: trailing bytes"); }
    let br = _parse_block(data, 44, 4, c1);
    if !br.is_ok {
      let m: Str = br.error;
      return _err_file(m);
    }
    let b1: _Block = br.value;
    return _ok_file(_file_from(1, c1, b1, ""));
  }
  let hoff = 44 + v1_size;
  if hoff + 44 > n { return _err_file("tzif: truncated second header"); }
  if !_magic_ok(data, hoff) { return _err_file("tzif: bad second header magic"); }
  let vbyte2: Int = _byte(data, hoff + 4);
  if _version_number(vbyte2) != version { return _err_file("tzif: second header version mismatch"); }
  let c2 = _read_counts(data, hoff + 20);
  if !_counts_ok(c2) { return _err_file(_counts_err(c2)); }
  let v2_size = _block_size(c2, 8);
  let bend = hoff + 44 + v2_size;
  if bend > n { return _err_file("tzif: data block overruns buffer"); }
  if bend >= n { return _err_file("tzif: missing footer"); }
  if _byte(data, bend) != 10 { return _err_file("tzif: missing footer"); }
  let fstart = bend + 1;
  var fend = -1;
  var k = fstart;
  while k < n {
    if _byte(data, k) == 10 {
      fend = k;
      k = n;
    } else {
      k = k + 1;
    }
  }
  if fend < 0 { return _err_file("tzif: missing footer"); }
  var fbytes = Vec[UInt8].new();
  k = fstart;
  while k < fend {
    let fb: Int = _byte(data, k);
    if fb == 0 { return _err_file("tzif: NUL in footer"); }
    fbytes.push(fb as UInt8);
    k = k + 1;
  }
  if fend + 1 != n { return _err_file("tzif: trailing bytes"); }
  let footer = Str::from_utf8(fbytes);
  let br2 = _parse_block(data, hoff + 44, 8, c2);
  if !br2.is_ok {
    let m2: Str = br2.error;
    return _err_file(m2);
  }
  let b2: _Block = br2.value;
  return _ok_file(_file_from(version, c2, b2, footer));
}

/// File format version: 1, 2 or 3. Complexity: O(1).
pub fn tzif_version(f: &TzifFile) -> Int {
  return f.version;
}

/// Transition count of the exposed block. Complexity: O(1).
pub fn tzif_timecnt(f: &TzifFile) -> Int {
  return f.timecnt;
}

/// Local time type count of the exposed block. Complexity: O(1).
pub fn tzif_typecnt(f: &TzifFile) -> Int {
  return f.typecnt;
}

/// Leap-second record count of the exposed block. Complexity: O(1).
pub fn tzif_leapcnt(f: &TzifFile) -> Int {
  return f.leapcnt;
}

/// Designation table byte count of the exposed block. Complexity: O(1).
pub fn tzif_charcnt(f: &TzifFile) -> Int {
  return f.charcnt;
}

/// Standard/wall indicator count of the exposed block (0 or typecnt).
/// Complexity: O(1).
pub fn tzif_isstdcnt(f: &TzifFile) -> Int {
  return f.isstdcnt;
}

/// UT/local indicator count of the exposed block (0 or typecnt).
/// Complexity: O(1).
pub fn tzif_isutcnt(f: &TzifFile) -> Int {
  return f.isutcnt;
}

/// Raw footer TZ string (the bytes between the two 0x0A delimiters), "" for
/// version 1 files and for an empty TZ string. Never parsed.
/// Complexity: O(1).
pub fn tzif_footer(f: &TzifFile) -> Str {
  return f.footer;
}

/// Transition time `i` as a signed UNIX leap-time second count; for
/// versions 2/3 the 64-bit second-block value. Err("tzif: index out of
/// range") when i is negative or >= tzif_timecnt. Complexity: O(1).
pub fn tzif_transition_time(f: &TzifFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.times.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.times[i];
  return _ok_int(v);
}

/// Local time type index of transition `i`. Err("tzif: index out of range")
/// when i is negative or >= tzif_timecnt. Complexity: O(1).
pub fn tzif_transition_type(f: &TzifFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.type_indices.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.type_indices[i];
  return _ok_int(v);
}

/// UT offset in seconds of local time type `t` (the value to add to UT to
/// get local time). Err("tzif: index out of range") when t is negative or
/// >= tzif_typecnt. Complexity: O(1).
pub fn tzif_type_utoff(f: &TzifFile, t: Int) -> Result[Int, Str] {
  if t < 0 || t >= f.utoffs.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.utoffs[t];
  return _ok_int(v);
}

/// DST flag of local time type `t` (0 standard, 1 daylight saving).
/// Err("tzif: index out of range") when t is negative or >= tzif_typecnt.
/// Complexity: O(1).
pub fn tzif_type_isdst(f: &TzifFile, t: Int) -> Result[Int, Str] {
  if t < 0 || t >= f.isdsts.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.isdsts[t];
  return _ok_int(v);
}

/// Decoded designation string of local time type `t` (may be empty).
/// Err("tzif: index out of range") when t is negative or >= tzif_typecnt.
/// Complexity: O(designation length).
pub fn tzif_type_designation(f: &TzifFile, t: Int) -> Result[Str, Str] {
  if t < 0 || t >= f.designations.len() {
    return _err_str("tzif: index out of range");
  }
  let v: Str = f.designations[t];
  return _ok_str(v);
}

/// Decoded designation string of the local time type of transition `i`.
/// Err("tzif: index out of range") when i is negative or >= tzif_timecnt.
/// Complexity: O(designation length).
pub fn tzif_transition_designation(f: &TzifFile, i: Int) -> Result[Str, Str] {
  let tr = tzif_transition_type(f, i);
  if !tr.is_ok {
    let m: Str = tr.error;
    return _err_str(m);
  }
  let ty: Int = tr.value;
  return tzif_type_designation(f, ty);
}

/// Occurrence time of leap-second record `i` as a signed UNIX leap-time
/// second count. Err("tzif: index out of range") when i is negative or
/// >= tzif_leapcnt. Complexity: O(1).
pub fn tzif_leap_occur(f: &TzifFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.leap_occurs.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.leap_occurs[i];
  return _ok_int(v);
}

/// Correction value of leap-second record `i` (LEAPCORR on or after the
/// occurrence). Err("tzif: index out of range") when i is negative or
/// >= tzif_leapcnt. Complexity: O(1).
pub fn tzif_leap_correction(f: &TzifFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.leap_corrections.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.leap_corrections[i];
  return _ok_int(v);
}

/// Standard/wall indicator of local time type `t` (0 wall, 1 standard).
/// Err("tzif: no standard indicator table") when the file stores none
/// (isstdcnt == 0); Err("tzif: index out of range") when t is negative or
/// >= tzif_typecnt. Complexity: O(1).
pub fn tzif_std_indicator(f: &TzifFile, t: Int) -> Result[Int, Str] {
  if f.isstd.len() == 0 {
    return _err_int("tzif: no standard indicator table");
  }
  if t < 0 || t >= f.isstd.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.isstd[t];
  return _ok_int(v);
}

/// UT/local indicator of local time type `t` (0 local, 1 UT).
/// Err("tzif: no UT indicator table") when the file stores none
/// (isutcnt == 0); Err("tzif: index out of range") when t is negative or
/// >= tzif_typecnt. Complexity: O(1).
pub fn tzif_ut_indicator(f: &TzifFile, t: Int) -> Result[Int, Str] {
  if f.isut.len() == 0 {
    return _err_int("tzif: no UT indicator table");
  }
  if t < 0 || t >= f.isut.len() {
    return _err_int("tzif: index out of range");
  }
  let v: Int = f.isut[t];
  return _ok_int(v);
}

// --------------------------------------------------
//  Public API -- version 1 building
// --------------------------------------------------

/// Build a version 1 TZif file from the parallel vectors of `f`.
///
/// Only the vectors are used: counts are recomputed from their lengths, the
/// version field must be 1 (the result carries the NUL version byte), and
/// the designation table is rebuilt canonically as each type's designation
/// string followed by a NUL, in type order, with designation indices
/// recomputed from that layout. A type designation may therefore not
/// contain a NUL byte; overlapping designations of a parsed table are
/// canonicalized. Stored desig_indices, count fields and footer are not
/// used.
///
/// Params: f - the source file model, read only.
/// Returns: Ok(bytes) of the complete version 1 file: header, data block,
/// nothing else.
/// Error case: Err("tzif: builder writes version 1 only") when version != 1;
/// Err("tzif: zero time type count") when there is no local time type;
/// Err("tzif: ttinfo vector length mismatch") when utoffs, isdsts,
/// desig_indices and designations differ in length;
/// Err("tzif: transition vector length mismatch") when times and
/// type_indices differ; Err("tzif: leap vector length mismatch") when
/// leap_occurs and leap_corrections differ;
/// Err("tzif: standard indicator count mismatch") and
/// Err("tzif: UT indicator count mismatch") when an indicator vector is
/// neither empty nor typecnt long; Err("tzif: transition time out of
/// range"), Err("tzif: transition type index out of range"),
/// Err("tzif: UT offset out of range"), Err("tzif: invalid UT offset")
/// (exactly -2^31), Err("tzif: invalid DST flag"),
/// Err("tzif: leap occurrence out of range"),
/// Err("tzif: leap correction out of range"),
/// Err("tzif: invalid indicator value"),
/// Err("tzif: UT indicator without standard indicator") and
/// Err("tzif: NUL in designation") for out-of-range field values, and
/// Err("tzif: designation table too large") when a designation index would
/// not fit the one-octet desigidx field.
/// Complexity: O(total vector contents).
pub fn tzif_build_v1(f: &TzifFile) -> Result[Vec[UInt8], Str] {
  if f.version != 1 { return _err_bytes("tzif: builder writes version 1 only"); }
  let typecnt = f.utoffs.len();
  if typecnt == 0 { return _err_bytes("tzif: zero time type count"); }
  if f.isdsts.len() != typecnt { return _err_bytes("tzif: ttinfo vector length mismatch"); }
  if f.desig_indices.len() != typecnt { return _err_bytes("tzif: ttinfo vector length mismatch"); }
  if f.designations.len() != typecnt { return _err_bytes("tzif: ttinfo vector length mismatch"); }
  let timecnt = f.times.len();
  if f.type_indices.len() != timecnt { return _err_bytes("tzif: transition vector length mismatch"); }
  let leapcnt = f.leap_occurs.len();
  if f.leap_corrections.len() != leapcnt { return _err_bytes("tzif: leap vector length mismatch"); }
  if f.isstd.len() != 0 && f.isstd.len() != typecnt { return _err_bytes("tzif: standard indicator count mismatch"); }
  if f.isut.len() != 0 && f.isut.len() != typecnt { return _err_bytes("tzif: UT indicator count mismatch"); }
  var table = Vec[UInt8].new();
  var offsets = Vec[Int].new();
  var t = 0;
  while t < typecnt {
    let off0 = table.len();
    if off0 > 255 { return _err_bytes("tzif: designation table too large"); }
    offsets.push(off0);
    let s: Str = f.designations[t];
    var k = 0;
    while k < s.len() {
      let c: Int = (string.byte_at(s, k) as Int) & 0xFF;
      if c == 0 { return _err_bytes("tzif: NUL in designation"); }
      table.push(c as UInt8);
      k = k + 1;
    }
    table.push(0 as UInt8);
    t = t + 1;
  }
  var i = 0;
  while i < timecnt {
    let tv: Int = f.times[i];
    if tv < -2147483648 || tv > 2147483647 { return _err_bytes("tzif: transition time out of range"); }
    let ty: Int = f.type_indices[i];
    if ty < 0 || ty >= typecnt { return _err_bytes("tzif: transition type index out of range"); }
    i = i + 1;
  }
  t = 0;
  while t < typecnt {
    let uo: Int = f.utoffs[t];
    if uo < -2147483648 || uo > 2147483647 { return _err_bytes("tzif: UT offset out of range"); }
    if uo == -2147483648 { return _err_bytes("tzif: invalid UT offset"); }
    let dd: Int = f.isdsts[t];
    if dd != 0 && dd != 1 { return _err_bytes("tzif: invalid DST flag"); }
    t = t + 1;
  }
  i = 0;
  while i < leapcnt {
    let lo: Int = f.leap_occurs[i];
    if lo < -2147483648 || lo > 2147483647 { return _err_bytes("tzif: leap occurrence out of range"); }
    let lc: Int = f.leap_corrections[i];
    if lc < -2147483648 || lc > 2147483647 { return _err_bytes("tzif: leap correction out of range"); }
    i = i + 1;
  }
  if f.isstd.len() == typecnt {
    t = 0;
    while t < typecnt {
      let sv: Int = f.isstd[t];
      if sv != 0 && sv != 1 { return _err_bytes("tzif: invalid indicator value"); }
      t = t + 1;
    }
  }
  if f.isut.len() == typecnt {
    t = 0;
    while t < typecnt {
      let uv: Int = f.isut[t];
      if uv != 0 && uv != 1 { return _err_bytes("tzif: invalid indicator value"); }
      if uv == 1 {
        if f.isstd.len() != typecnt { return _err_bytes("tzif: UT indicator without standard indicator"); }
        let sv2: Int = f.isstd[t];
        if sv2 != 1 { return _err_bytes("tzif: UT indicator without standard indicator"); }
      }
      t = t + 1;
    }
  }
  var out = Vec[UInt8].new();
  out.push(84 as UInt8);
  out.push(90 as UInt8);
  out.push(105 as UInt8);
  out.push(102 as UInt8);
  out.push(0 as UInt8);
  var z = 0;
  while z < 15 {
    out.push(0 as UInt8);
    z = z + 1;
  }
  _push_be(&mut out, f.isut.len(), 4);
  _push_be(&mut out, f.isstd.len(), 4);
  _push_be(&mut out, leapcnt, 4);
  _push_be(&mut out, timecnt, 4);
  _push_be(&mut out, typecnt, 4);
  _push_be(&mut out, table.len(), 4);
  i = 0;
  while i < timecnt {
    let tv2: Int = f.times[i];
    _push_be(&mut out, tv2, 4);
    i = i + 1;
  }
  i = 0;
  while i < timecnt {
    let ty2: Int = f.type_indices[i];
    out.push(ty2 as UInt8);
    i = i + 1;
  }
  t = 0;
  while t < typecnt {
    let uo2: Int = f.utoffs[t];
    let dd2: Int = f.isdsts[t];
    let oo: Int = offsets[t];
    _push_be(&mut out, uo2, 4);
    out.push(dd2 as UInt8);
    out.push(oo as UInt8);
    t = t + 1;
  }
  var p = 0;
  while p < table.len() {
    out.push(table[p]);
    p = p + 1;
  }
  i = 0;
  while i < leapcnt {
    let lo2: Int = f.leap_occurs[i];
    let lc2: Int = f.leap_corrections[i];
    _push_be(&mut out, lo2, 4);
    _push_be(&mut out, lc2, 4);
    i = i + 1;
  }
  if f.isstd.len() == typecnt {
    t = 0;
    while t < typecnt {
      let sv3: Int = f.isstd[t];
      out.push(sv3 as UInt8);
      t = t + 1;
    }
  }
  if f.isut.len() == typecnt {
    t = 0;
    while t < typecnt {
      let uv2: Int = f.isut[t];
      out.push(uv2 as UInt8);
      t = t + 1;
    }
  }
  return _ok_bytes(out);
}
