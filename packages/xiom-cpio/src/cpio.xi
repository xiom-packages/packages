// XIOM -- xiom.cpio: cpio archive header codec (newc and odc)
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.cpio placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the ASCII cpio header formats `newc` ("070701", 13 eight-digit
// hexadecimal fields) and `odc` ("070707", ten octal fields). cpio_parse
// walks a buffer of concatenated entries until the "TRAILER!!!" entry and
// returns a flat CpioArchive index: names, per-entry format codes, one flat
// stride-11 Int vector of metadata fields, declared file sizes, data offsets
// and next-header offsets. cpio_append/cpio_build write the same layout with
// the format's alignment (4 bytes for newc, 2 for odc) and append the
// canonical trailer. No filesystem I/O, no compression, no binary cpio, no
// device semantics: every field is parsed and re-emitted verbatim.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int] element reads are always bound to typed locals (untyped reads
//     can mis-lower to pointer/Str comparisons in this compiler).
//   * the per-entry metadata lives in one flat stride-11 Vec[Int] (no
//     Vec[StructType], no Vec[Vec[Int]]); CpioArchive crosses function
//     boundaries only by reference or through _ok_archive.
//   * Str values read from Vec[Str] fields are bound to typed locals; the
//     parser never compares names with `==` (it matches the trailer
//     byte-wise, and BUG 17 makes `==` on Vec[Str] elements unsafe anyway).
// See SPEC.md for the layout tables, validation order, error catalog and
// test plan.

module xiom.cpio

use xiom.string;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Format code of the newc ("070701") ASCII header.
pub const CPIO_FORMAT_NEWC: Int = 0;

/// Format code of the odc ("070707") ASCII header.
pub const CPIO_FORMAT_ODC: Int = 1;

/// Position of `ino` inside the flat metadata vector.
pub const CPIO_META_INO: Int = 0;

/// Position of `mode` inside the flat metadata vector.
pub const CPIO_META_MODE: Int = 1;

/// Position of `uid` inside the flat metadata vector.
pub const CPIO_META_UID: Int = 2;

/// Position of `gid` inside the flat metadata vector.
pub const CPIO_META_GID: Int = 3;

/// Position of `nlink` inside the flat metadata vector.
pub const CPIO_META_NLINK: Int = 4;

/// Position of `mtime` inside the flat metadata vector.
pub const CPIO_META_MTIME: Int = 5;

/// Position of the device major number (newc) / combined `dev` (odc)
/// inside the flat metadata vector.
pub const CPIO_META_DEVMAJOR: Int = 6;

/// Position of the device minor number (newc; -1 in odc entries) inside
/// the flat metadata vector.
pub const CPIO_META_DEVMINOR: Int = 7;

/// Position of the rdev major number (newc) / combined `rdev` (odc)
/// inside the flat metadata vector.
pub const CPIO_META_RDEVMAJOR: Int = 8;

/// Position of the rdev minor number (newc; -1 in odc entries) inside the
/// flat metadata vector.
pub const CPIO_META_RDEVMINOR: Int = 9;

/// Position of the newc `check` field (-1 in odc entries) inside the flat
/// metadata vector.
pub const CPIO_META_CHECK: Int = 10;

/// Number of metadata values per entry (stride of the flat field vector).
pub const CPIO_META_LEN: Int = 11;

// --------------------------------------------------
//  Parsed archive index
// --------------------------------------------------

/// Parsed cpio archive index. One logical slot per entry (the terminating
/// "TRAILER!!!" entry is consumed, not stored), in stream order.
///
/// `fields` is a flat vector with stride CPIO_META_LEN: entry `i` owns
/// `fields[i*11 .. i*11+10]` in the order ino, mode, uid, gid, nlink, mtime,
/// devmajor, devminor, rdevmajor, rdevminor, check. For odc entries the
/// combined `dev`/`rdev` numbers are stored in devmajor/rdevmajor and the
/// fields odc does not carry (devminor, rdevminor, check) read -1.
/// `data_offsets[i]` is the absolute index of the first data byte in the
/// source buffer; `next_offsets[i]` is the absolute index just past the
/// entry's data padding (the next header, or the trailer header for the last
/// entry). Fields are implementation details; callers use the free functions
/// below.
pub type CpioArchive = {
  names: Vec[Str];
  formats: Vec[Int];
  fields: Vec[Int];
  filesizes: Vec[Int];
  data_offsets: Vec[Int];
  next_offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[CpioArchive, Str].
fn _ok_archive(v: CpioArchive) -> Result[CpioArchive, Str] {
  return Ok(v);
}

// Err(m) for Result[CpioArchive, Str].
fn _err_archive(m: Str) -> Result[CpioArchive, Str] {
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

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte and field helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Hex digit value of an ASCII byte, or -1 when it is not a hex digit.
fn _hex_val(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 97 && c <= 102 { return c - 87; }
  if c >= 65 && c <= 70 { return c - 55; }
  return -1;
}

// Octal digit value of an ASCII byte, or -1 when it is not an octal digit.
fn _oct_val(c: Int) -> Int {
  if c >= 48 && c <= 55 { return c - 48; }
  return -1;
}

// `len` hex digits at `off` as a non-negative Int.
// Err("cpio: non-hex digit") on the first byte that is not [0-9a-fA-F].
fn _hex_field(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str] {
  var v: Int = 0;
  var i = 0;
  while i < len {
    let c: Int = _byte(data, off + i);
    let d: Int = _hex_val(c);
    if d < 0 {
      return _err_int("cpio: non-hex digit");
    }
    v = v * 16 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// `len` octal digits at `off` as a non-negative Int.
// Err("cpio: bad octal") on the first byte that is not [0-7].
fn _oct_field(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str] {
  var v: Int = 0;
  var i = 0;
  while i < len {
    let c: Int = _byte(data, off + i);
    let d: Int = _oct_val(c);
    if d < 0 {
      return _err_int("cpio: bad octal");
    }
    v = v * 8 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// Magic code at `off`: CPIO_FORMAT_NEWC for "070701", CPIO_FORMAT_ODC for
// "070707", -1 otherwise. The caller guarantees six readable bytes.
fn _magic_code(data: &Vec[UInt8], off: Int) -> Int {
  if _byte(data, off) != 48 { return -1; }
  if _byte(data, off + 1) != 55 { return -1; }
  if _byte(data, off + 2) != 48 { return -1; }
  if _byte(data, off + 3) != 55 { return -1; }
  if _byte(data, off + 4) != 48 { return -1; }
  let last: Int = _byte(data, off + 5);
  if last == 49 { return CPIO_FORMAT_NEWC; }
  if last == 55 { return CPIO_FORMAT_ODC; }
  return -1;
}

// Fixed header width of `format`: 110 for newc, 76 for odc.
fn _header_len(format: Int) -> Int {
  if format == CPIO_FORMAT_ODC { return 76; }
  return 110;
}

// Alignment of `format`: 4 for newc, 2 for odc.
fn _entry_align(format: Int) -> Int {
  if format == CPIO_FORMAT_ODC { return 2; }
  return 4;
}

// True when the namesize-byte name at `off` is exactly "TRAILER!!!" + NUL.
fn _is_trailer(data: &Vec[UInt8], off: Int, namesize: Int) -> Bool {
  if namesize != 11 { return false; }
  if _byte(data, off) != 84 { return false; }
  if _byte(data, off + 1) != 82 { return false; }
  if _byte(data, off + 2) != 65 { return false; }
  if _byte(data, off + 3) != 73 { return false; }
  if _byte(data, off + 4) != 76 { return false; }
  if _byte(data, off + 5) != 69 { return false; }
  if _byte(data, off + 6) != 82 { return false; }
  if _byte(data, off + 7) != 33 { return false; }
  if _byte(data, off + 8) != 33 { return false; }
  if _byte(data, off + 9) != 33 { return false; }
  return true;
}

// Index of the first NUL byte in [off, off + len), or -1 when absent.
fn _find_nul(data: &Vec[UInt8], off: Int, len: Int) -> Int {
  var i = 0;
  while i < len {
    if _byte(data, off + i) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Name bytes [off, off + len) as a Str (the caller excludes the NUL).
fn _name_str(data: &Vec[UInt8], off: Int, len: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < len {
    bytes.push(data[off + i]);
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// Advance `pos` to the next `align`-byte boundary, requiring every skipped
// padding byte to be NUL. Err("cpio: alignment mismatch") when the padding
// is truncated or holds a non-NUL byte.
fn _skip_pad(data: &Vec[UInt8], pos: Int, align: Int) -> Result[Int, Str] {
  let rem: Int = pos % align;
  if rem == 0 {
    return _ok_int(pos);
  }
  let pad: Int = align - rem;
  let end: Int = pos + pad;
  if end > data.len() {
    return _err_int("cpio: alignment mismatch");
  }
  var i = pos;
  while i < end {
    if _byte(data, i) != 0 {
      return _err_int("cpio: alignment mismatch");
    }
    i = i + 1;
  }
  return _ok_int(end);
}

// Newc header fields at `pos` in canonical order: ino, mode, uid, gid,
// nlink, mtime, devmajor, devminor, rdevmajor, rdevminor, check, filesize,
// namesize. The wire order puts filesize and namesize before check, so the
// two are permuted here.
fn _read_newc_fields(data: &Vec[UInt8], pos: Int) -> Result[Vec[Int], Str] {
  var w = Vec[Int].new();
  var k = 0;
  while k < 13 {
    let r = _hex_field(data, pos + 6 + k * 8, 8);
    if !r.is_ok {
      return _err_ints("cpio: non-hex digit");
    }
    let x: Int = r.value;
    w.push(x);
    k = k + 1;
  }
  let ino: Int = w[0];
  let mode: Int = w[1];
  let uid: Int = w[2];
  let gid: Int = w[3];
  let nlink: Int = w[4];
  let mtime: Int = w[5];
  let filesize: Int = w[6];
  let devmajor: Int = w[7];
  let devminor: Int = w[8];
  let rdevmajor: Int = w[9];
  let rdevminor: Int = w[10];
  let namesize: Int = w[11];
  let check: Int = w[12];
  var v = Vec[Int].new();
  v.push(ino);
  v.push(mode);
  v.push(uid);
  v.push(gid);
  v.push(nlink);
  v.push(mtime);
  v.push(devmajor);
  v.push(devminor);
  v.push(rdevmajor);
  v.push(rdevminor);
  v.push(check);
  v.push(filesize);
  v.push(namesize);
  return _ok_ints(v);
}

// Odc header fields at `pos` in the same canonical order as
// _read_newc_fields. The combined `dev`/`rdev` numbers land in
// devmajor/rdevmajor; devminor, rdevminor and check are -1 because odc has
// no such fields.
fn _read_odc_fields(data: &Vec[UInt8], pos: Int) -> Result[Vec[Int], Str] {
  let devr = _oct_field(data, pos + 6, 6);
  if !devr.is_ok { return _err_ints("cpio: bad octal"); }
  let inor = _oct_field(data, pos + 12, 6);
  if !inor.is_ok { return _err_ints("cpio: bad octal"); }
  let moder = _oct_field(data, pos + 18, 6);
  if !moder.is_ok { return _err_ints("cpio: bad octal"); }
  let uidr = _oct_field(data, pos + 24, 6);
  if !uidr.is_ok { return _err_ints("cpio: bad octal"); }
  let gidr = _oct_field(data, pos + 30, 6);
  if !gidr.is_ok { return _err_ints("cpio: bad octal"); }
  let nlinkr = _oct_field(data, pos + 36, 6);
  if !nlinkr.is_ok { return _err_ints("cpio: bad octal"); }
  let rdevr = _oct_field(data, pos + 42, 6);
  if !rdevr.is_ok { return _err_ints("cpio: bad octal"); }
  let mtimer = _oct_field(data, pos + 48, 11);
  if !mtimer.is_ok { return _err_ints("cpio: bad octal"); }
  let namesizer = _oct_field(data, pos + 59, 6);
  if !namesizer.is_ok { return _err_ints("cpio: bad octal"); }
  let filesizer = _oct_field(data, pos + 65, 11);
  if !filesizer.is_ok { return _err_ints("cpio: bad octal"); }
  let dev: Int = devr.value;
  let ino: Int = inor.value;
  let mode: Int = moder.value;
  let uid: Int = uidr.value;
  let gid: Int = gidr.value;
  let nlink: Int = nlinkr.value;
  let rdev: Int = rdevr.value;
  let mtime: Int = mtimer.value;
  let namesize: Int = namesizer.value;
  let filesize: Int = filesizer.value;
  var v = Vec[Int].new();
  v.push(ino);
  v.push(mode);
  v.push(uid);
  v.push(gid);
  v.push(nlink);
  v.push(mtime);
  v.push(dev);
  v.push(-1);
  v.push(rdev);
  v.push(-1);
  v.push(-1);
  v.push(filesize);
  v.push(namesize);
  return _ok_ints(v);
}

// Dispatch to the per-format field reader.
fn _read_fields(data: &Vec[UInt8], pos: Int, format: Int) -> Result[Vec[Int], Str] {
  if format == CPIO_FORMAT_NEWC {
    return _read_newc_fields(data, pos);
  }
  return _read_odc_fields(data, pos);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a cpio byte stream made of newc and/or odc entries.
///
/// Walks entries from offset 0. Each entry's magic selects its format; the
/// fixed header is parsed (hex for newc, octal for odc), the name must fill
/// exactly `namesize` bytes and end in NUL, and the padding between the name
/// and the data and after the data must be present NUL bytes up to the
/// format's alignment (4 bytes for newc, 2 for odc). The first entry whose
/// name is exactly "TRAILER!!!" terminates the archive: it is not stored and
/// any following bytes (including its own padding) are ignored. A stream
/// holding only the trailer is valid and has zero entries.
///
/// Validation order per entry: six-byte magic -> Err("cpio: bad magic");
/// fixed header present -> Err("cpio: truncated header"); field digits ->
/// Err("cpio: non-hex digit") for newc or Err("cpio: bad octal") for odc;
/// namesize >= 1 -> Err("cpio: bad namesize"); name field inside the buffer
/// -> Err("cpio: truncated name"); a NUL inside the name field ->
/// Err("cpio: name missing NUL"); the first NUL not the final name byte ->
/// Err("cpio: bad namesize"); header/name and data padding present and NUL ->
/// Err("cpio: alignment mismatch"); declared filesize fits the buffer ->
/// Err("cpio: truncated data"). A stream that ends before a trailer is
/// Err("cpio: missing trailer") (an empty buffer included).
/// Complexity: O(data.len()).
pub fn cpio_parse(data: &Vec[UInt8]) -> Result[CpioArchive, Str] {
  var names = Vec[Str].new();
  var formats = Vec[Int].new();
  var fields = Vec[Int].new();
  var filesizes = Vec[Int].new();
  var data_offsets = Vec[Int].new();
  var next_offsets = Vec[Int].new();
  let n = data.len();
  var pos = 0;
  var done = false;
  while !done && pos < n {
    let remaining: Int = n - pos;
    if remaining < 6 {
      return _err_archive("cpio: truncated header");
    }
    let format: Int = _magic_code(data, pos);
    if format < 0 {
      return _err_archive("cpio: bad magic");
    }
    let hlen: Int = _header_len(format);
    if remaining < hlen {
      return _err_archive("cpio: truncated header");
    }
    let fr = _read_fields(data, pos, format);
    if !fr.is_ok {
      return _err_archive(fr.error);
    }
    let fv: Vec[Int] = fr.value;
    let filesize: Int = fv[11];
    let namesize: Int = fv[12];
    if namesize < 1 {
      return _err_archive("cpio: bad namesize");
    }
    let name_start: Int = pos + hlen;
    if namesize > n - name_start {
      return _err_archive("cpio: truncated name");
    }
    let nul_at: Int = _find_nul(data, name_start, namesize);
    if nul_at < 0 {
      return _err_archive("cpio: name missing NUL");
    }
    if nul_at != namesize - 1 {
      return _err_archive("cpio: bad namesize");
    }
    if _is_trailer(data, name_start, namesize) {
      done = true;
    } else {
      let align: Int = _entry_align(format);
      let padr = _skip_pad(data, name_start + namesize, align);
      if !padr.is_ok {
        return _err_archive(padr.error);
      }
      let data_start: Int = padr.value;
      if filesize > n - data_start {
        return _err_archive("cpio: truncated data");
      }
      let endr = _skip_pad(data, data_start + filesize, align);
      if !endr.is_ok {
        return _err_archive(endr.error);
      }
      let next_pos: Int = endr.value;
      let nm: Str = _name_str(data, name_start, nul_at);
      names.push(nm);
      formats.push(format);
      var k = 0;
      while k < CPIO_META_LEN {
        let x: Int = fv[k];
        fields.push(x);
        k = k + 1;
      }
      filesizes.push(filesize);
      data_offsets.push(data_start);
      next_offsets.push(next_pos);
      pos = next_pos;
    }
  }
  if !done {
    return _err_archive("cpio: missing trailer");
  }
  let archive = CpioArchive{
    names: names;
    formats: formats;
    fields: fields;
    filesizes: filesizes;
    data_offsets: data_offsets;
    next_offsets: next_offsets;
  };
  return _ok_archive(archive);
}

/// Detect the format of the first entry: CPIO_FORMAT_NEWC, CPIO_FORMAT_ODC,
/// or -1 when the buffer is shorter than six bytes or the magic is neither.
/// Complexity: O(1).
pub fn cpio_detect_format(data: &Vec[UInt8]) -> Int {
  if data.len() < 6 {
    return -1;
  }
  return _magic_code(data, 0);
}

// --------------------------------------------------
//  Archive readers
// --------------------------------------------------

/// Number of parsed entries (the trailer is not counted).
/// Complexity: O(1).
pub fn cpio_count(a: &CpioArchive) -> Int {
  return a.names.len();
}

/// Format code of entry `i` (CPIO_FORMAT_NEWC or CPIO_FORMAT_ODC); -1 when
/// `i` is negative or >= cpio_count(a).
/// Complexity: O(1).
pub fn cpio_entry_format(a: &CpioArchive, i: Int) -> Int {
  if i < 0 || i >= a.names.len() {
    return -1;
  }
  let f: Int = a.formats[i];
  return f;
}

/// Raw metadata field `k` of entry `i`; `k` follows the CPIO_META_*
/// constants. Returns -1 when `i` is out of range or `k` is outside
/// 0..CPIO_META_LEN-1.
/// Complexity: O(1).
pub fn cpio_entry_field(a: &CpioArchive, i: Int, k: Int) -> Int {
  if i < 0 || i >= a.names.len() {
    return -1;
  }
  if k < 0 || k >= CPIO_META_LEN {
    return -1;
  }
  let v: Int = a.fields[i * CPIO_META_LEN + k];
  return v;
}

/// Name of entry `i`, or "" when `i` is out of range. The result is a Str
/// read from a Vec[Str] field: callers must compare it with
/// xiom.string.compare.str_compare rather than `==`.
/// Complexity: O(1).
pub fn cpio_entry_name(a: &CpioArchive, i: Int) -> Str {
  if i < 0 || i >= a.names.len() {
    return "";
  }
  let nm: Str = a.names[i];
  return nm;
}

/// Inode number of entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_ino(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_INO);
}

/// Mode bits of entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_mode(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_MODE);
}

/// User id of entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_uid(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_UID);
}

/// Group id of entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_gid(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_GID);
}

/// Link count of entry `i`; -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_nlink(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_NLINK);
}

/// Modification time of entry `i` (seconds since the epoch, as stored);
/// -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_mtime(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_MTIME);
}

/// Device major number of entry `i`; for odc entries this is the combined
/// `dev` field. -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_devmajor(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_DEVMAJOR);
}

/// Device minor number of entry `i`; -1 out of range and also -1 for odc
/// entries, which do not carry a separate minor number.
/// Complexity: O(1).
pub fn cpio_entry_devminor(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_DEVMINOR);
}

/// Rdev major number of entry `i`; for odc entries this is the combined
/// `rdev` field. -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_rdevmajor(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_RDEVMAJOR);
}

/// Rdev minor number of entry `i`; -1 out of range and also -1 for odc
/// entries, which do not carry a separate minor number.
/// Complexity: O(1).
pub fn cpio_entry_rdevminor(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_RDEVMINOR);
}

/// Newc `check` field of entry `i` (stored verbatim, 0 in canonical
/// archives); -1 out of range and -1 for odc entries, which have no check
/// field.
/// Complexity: O(1).
pub fn cpio_entry_check(a: &CpioArchive, i: Int) -> Int {
  return cpio_entry_field(a, i, CPIO_META_CHECK);
}

/// Declared file size of entry `i` in bytes; -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_filesize(a: &CpioArchive, i: Int) -> Int {
  if i < 0 || i >= a.filesizes.len() {
    return -1;
  }
  let v: Int = a.filesizes[i];
  return v;
}

/// Absolute offset of entry `i`'s first data byte in the parse buffer;
/// -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_data_offset(a: &CpioArchive, i: Int) -> Int {
  if i < 0 || i >= a.data_offsets.len() {
    return -1;
  }
  let v: Int = a.data_offsets[i];
  return v;
}

/// Absolute offset just past entry `i`'s data padding: the next header in
/// the stream, or the trailer header for the last entry. -1 out of range.
/// Complexity: O(1).
pub fn cpio_entry_next_offset(a: &CpioArchive, i: Int) -> Int {
  if i < 0 || i >= a.next_offsets.len() {
    return -1;
  }
  let v: Int = a.next_offsets[i];
  return v;
}

/// Copy the data bytes of entry `i` out of `data`: `filesizes[i]` bytes
/// starting at `data_offsets[i]`.
///
/// Err("cpio: entry out of range") when `i` is negative or >=
/// cpio_count(a); Err("cpio: truncated data") when the recorded span does
/// not fit `data` (for example when a shorter buffer is passed). A zero-size
/// entry yields an empty Ok.
/// Complexity: O(filesize).
pub fn cpio_entry_data(data: &Vec[UInt8], a: &CpioArchive, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= a.names.len() {
    return _err_bytes("cpio: entry out of range");
  }
  let off: Int = a.data_offsets[i];
  let size: Int = a.filesizes[i];
  if off < 0 || size < 0 {
    return _err_bytes("cpio: entry out of range");
  }
  if off + size > data.len() {
    return _err_bytes("cpio: truncated data");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < size {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Writer helpers
// --------------------------------------------------

// Append the bytes of `s`.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
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

// Append `count` zero bytes.
fn _push_zeros(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append `v` as exactly `digits` lowercase hexadecimal ASCII digits, most
// significant first. Values wider than `digits` hex digits are truncated to
// the low `digits` digits; callers validate the range first.
fn _push_hex(out: &mut Vec[UInt8], v: Int, digits: Int) {
  var div: Int = 1;
  var k = 1;
  while k < digits {
    div = div * 16;
    k = k + 1;
  }
  var n = v;
  var i = 0;
  while i < digits {
    let d: Int = (n / div) % 16;
    n = n % div;
    if d < 10 {
      out.push((48 + d) as UInt8);
    } else {
      out.push((87 + d) as UInt8);
    }
    div = div / 16;
    i = i + 1;
  }
}

// Append the zero-padded octal representation of the non-negative `v` as
// exactly `digits` ASCII octal digits (no terminator). Values wider than
// `digits` octal digits are truncated to the low `digits` digits; callers
// validate the range first.
fn _push_octal(out: &mut Vec<UInt8>, v: Int, digits: Int) {
  var div: Int = 1;
  var k = 1;
  while k < digits {
    div = div * 8;
    k = k + 1;
  }
  var n = v;
  var i = 0;
  while i < digits {
    let d: Int = (n / div) % 8;
    n = n % div;
    out.push((48 + d) as UInt8);
    div = div / 8;
    i = i + 1;
  }
}

// Validate and append one complete entry to `out`: header, name + NUL,
// NUL padding to the format's alignment, data, then NUL padding to the same
// alignment. The 11 metadata values are read from meta[base .. base+10].
// All validation runs before the first byte is written, so `out` is
// unchanged on Err. Callers guarantee `format` is valid and `meta` holds at
// least base + CPIO_META_LEN values.
fn _append_at(out: &mut Vec<UInt8>, format: Int, name: Str, meta: &Vec[Int], base: Int, data: &Vec[UInt8]) -> Result[Unit, Str] {
  let namesize: Int = name.len() + 1;
  let filesize: Int = data.len();
  let f_ino: Int = meta[base + CPIO_META_INO];
  let f_mode: Int = meta[base + CPIO_META_MODE];
  let f_uid: Int = meta[base + CPIO_META_UID];
  let f_gid: Int = meta[base + CPIO_META_GID];
  let f_nlink: Int = meta[base + CPIO_META_NLINK];
  let f_mtime: Int = meta[base + CPIO_META_MTIME];
  let f_devmajor: Int = meta[base + CPIO_META_DEVMAJOR];
  let f_devminor: Int = meta[base + CPIO_META_DEVMINOR];
  let f_rdevmajor: Int = meta[base + CPIO_META_RDEVMAJOR];
  let f_rdevminor: Int = meta[base + CPIO_META_RDEVMINOR];
  let f_check: Int = meta[base + CPIO_META_CHECK];
  if format == CPIO_FORMAT_NEWC {
    if f_ino < 0 || f_ino > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_mode < 0 || f_mode > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_uid < 0 || f_uid > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_gid < 0 || f_gid > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_nlink < 0 || f_nlink > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_mtime < 0 || f_mtime > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_devmajor < 0 || f_devmajor > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_devminor < 0 || f_devminor > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_rdevmajor < 0 || f_rdevmajor > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_rdevminor < 0 || f_rdevminor > 4294967295 { return _err_unit("cpio: size overflow"); }
    if f_check < 0 || f_check > 4294967295 { return _err_unit("cpio: size overflow"); }
    if namesize > 4294967295 { return _err_unit("cpio: size overflow"); }
    if filesize > 4294967295 { return _err_unit("cpio: size overflow"); }
    _push_str(out, "070701");
    _push_hex(out, f_ino, 8);
    _push_hex(out, f_mode, 8);
    _push_hex(out, f_uid, 8);
    _push_hex(out, f_gid, 8);
    _push_hex(out, f_nlink, 8);
    _push_hex(out, f_mtime, 8);
    _push_hex(out, filesize, 8);
    _push_hex(out, f_devmajor, 8);
    _push_hex(out, f_devminor, 8);
    _push_hex(out, f_rdevmajor, 8);
    _push_hex(out, f_rdevminor, 8);
    _push_hex(out, namesize, 8);
    _push_hex(out, f_check, 8);
  } else {
    if f_ino < 0 || f_ino > 262143 { return _err_unit("cpio: size overflow"); }
    if f_mode < 0 || f_mode > 262143 { return _err_unit("cpio: size overflow"); }
    if f_uid < 0 || f_uid > 262143 { return _err_unit("cpio: size overflow"); }
    if f_gid < 0 || f_gid > 262143 { return _err_unit("cpio: size overflow"); }
    if f_nlink < 0 || f_nlink > 262143 { return _err_unit("cpio: size overflow"); }
    if f_devmajor < 0 || f_devmajor > 262143 { return _err_unit("cpio: size overflow"); }
    if f_rdevmajor < 0 || f_rdevmajor > 262143 { return _err_unit("cpio: size overflow"); }
    if f_mtime < 0 || f_mtime > 8589934591 { return _err_unit("cpio: size overflow"); }
    if namesize > 262143 { return _err_unit("cpio: size overflow"); }
    if filesize > 8589934591 { return _err_unit("cpio: size overflow"); }
    _push_str(out, "070707");
    _push_octal(out, f_devmajor, 6);
    _push_octal(out, f_ino, 6);
    _push_octal(out, f_mode, 6);
    _push_octal(out, f_uid, 6);
    _push_octal(out, f_gid, 6);
    _push_octal(out, f_nlink, 6);
    _push_octal(out, f_rdevmajor, 6);
    _push_octal(out, f_mtime, 11);
    _push_octal(out, namesize, 6);
    _push_octal(out, filesize, 11);
  }
  _push_str(out, name);
  out.push(0 as UInt8);
  if format == CPIO_FORMAT_NEWC {
    _push_zeros(out, (4 - ((110 + namesize) % 4)) % 4);
  } else {
    _push_zeros(out, (2 - ((76 + namesize) % 2)) % 2);
  }
  _push_bytes(out, data);
  if format == CPIO_FORMAT_NEWC {
    _push_zeros(out, (4 - (filesize % 4)) % 4);
  } else {
    _push_zeros(out, (2 - (filesize % 2)) % 2);
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Append one complete cpio entry to `out` in the requested format.
///
/// `meta` must hold exactly CPIO_META_LEN (11) values in field order: ino,
/// mode, uid, gid, nlink, mtime, devmajor, devminor, rdevmajor, rdevminor,
/// check. `data.len()` is written as the entry's filesize. For odc,
/// devminor/rdevminor/check are ignored (the format has no such fields) and
/// the combined `dev`/`rdev` numbers come from devmajor/rdevmajor.
///
/// Err("cpio: bad format") when `format` is neither CPIO_FORMAT_NEWC nor
/// CPIO_FORMAT_ODC; Err("cpio: metadata length mismatch") when
/// meta.len() != 11; Err("cpio: size overflow") when a used field is
/// negative or does not fit its fixed width (newc: all fields and the
/// name/data sizes are 8 hex digits; odc: ino/mode/uid/gid/nlink/dev/rdev/
/// namesize are 6 octal digits and mtime/filesize are 11). Every check runs
/// before the first byte is written, so `out` is unchanged on Err.
/// Complexity: O(name + data).
pub fn cpio_append(out: &mut Vec[UInt8], format: Int, name: Str, meta: &Vec[Int], data: &Vec[UInt8]) -> Result[Unit, Str] {
  if format != CPIO_FORMAT_NEWC && format != CPIO_FORMAT_ODC {
    return _err_unit("cpio: bad format");
  }
  if meta.len() != CPIO_META_LEN {
    return _err_unit("cpio: metadata length mismatch");
  }
  return _append_at(out, format, name, meta, 0, data);
}

/// Append the canonical trailer entry of `format` to `out`: a header with
/// nlink 1 and every other metadata field 0, filesize 0, namesize 11 and
/// the name "TRAILER!!!" + NUL, followed by the format's NUL padding.
///
/// Err("cpio: bad format") when `format` is neither CPIO_FORMAT_NEWC nor
/// CPIO_FORMAT_ODC; `out` is unchanged on Err. The result is 124 bytes for
/// newc and 88 bytes for odc.
/// Complexity: O(1).
pub fn cpio_append_trailer(out: &mut Vec<UInt8>, format: Int) -> Result[Unit, Str] {
  if format != CPIO_FORMAT_NEWC && format != CPIO_FORMAT_ODC {
    return _err_unit("cpio: bad format");
  }
  var meta = Vec[Int].new();
  meta.push(0);
  meta.push(0);
  meta.push(0);
  meta.push(0);
  meta.push(1);
  meta.push(0);
  meta.push(0);
  meta.push(0);
  meta.push(0);
  meta.push(0);
  meta.push(0);
  var empty = Vec[UInt8].new();
  return _append_at(out, format, "TRAILER!!!", &meta, 0, &empty);
}

/// Build a whole cpio stream in `format` from parallel name/data vectors
/// plus a flat metadata buffer: `metas` must hold names.len() * CPIO_META_LEN
/// values with entry `i`'s 11 fields at `metas[i*11 .. i*11+10]` (the same
/// order cpio_append takes), and `datas[i]` is the data of `names[i]`. Every
/// entry is emitted with the entry writer and the stream ends with the
/// canonical trailer.
///
/// Err("cpio: bad format") for an unknown format; Err("cpio: entry count
/// mismatch") when names.len() != datas.len(); Err("cpio: metadata length
/// mismatch") when metas.len() != names.len() * 11; otherwise the first
/// entry error (the cpio_append catalog). An empty build yields exactly the
/// trailer entry (124 bytes for newc, 88 for odc).
/// Complexity: O(total name + data bytes).
pub fn cpio_build(format: Int, names: &Vec[Str], datas: &Vec[Vec[UInt8]], metas: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  if format != CPIO_FORMAT_NEWC && format != CPIO_FORMAT_ODC {
    return _err_bytes("cpio: bad format");
  }
  let count = names.len();
  if datas.len() != count {
    return _err_bytes("cpio: entry count mismatch");
  }
  if metas.len() != count * CPIO_META_LEN {
    return _err_bytes("cpio: metadata length mismatch");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < count {
    let nm: Str = names[i];
    let dt: Vec[UInt8] = datas[i];
    let r = _append_at(&mut out, format, nm, metas, i * CPIO_META_LEN, &dt);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
    i = i + 1;
  }
  let tr = cpio_append_trailer(&mut out, format);
  if !tr.is_ok {
    return _err_bytes(tr.error);
  }
  return _ok_bytes(out);
}
