// XIOM -- xiom.ar: Unix ar archive codec (parse and build)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the common ar(5) container. ar_parse validates the 8-byte global
// magic ("!<arch>\n"), walks 60-byte member headers (name[16], mtime[12],
// uid[6], gid[6], mode[8], size[10], terminating 0x60 0x0A), decodes plain
// trailing-space-padded names and BSD "#1/<len>" extended names, and returns
// a flat ArArchive index: names, header/data offsets, payload sizes, mtimes,
// uids, gids and modes. Payload bytes stay in the source buffer and are
// located by data_offsets/sizes. ar_build/ar_append write canonical headers
// (mtime/uid/gid/size in ASCII decimal, mode in ASCII octal, space padded)
// and pad every odd-sized member with a single newline (0x0A) so the stream
// stays even. No filesystem I/O, no symbol tables, no thin archives.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic; UInt8
//     values are never compared against Int constants without widening.
//   * Vec[Int] element reads are always bound to typed locals (untyped reads
//     can mis-lower to pointer/Str comparisons in this compiler).
//   * ArArchive (eight Vec fields, flat parallel storage) is constructed
//     inside ar_parse and crosses function boundaries only by reference or
//     through _ok_archive.
//   * Str values read from Vec[Str] fields are bound to typed locals and are
//     only ever compared through xiom.string.compare.str_compare.
// See SPEC.md for the byte layout tables, validation order, error catalog
// and test plan.

module xiom.ar

use xiom.string;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Length of the global archive magic ("!<arch>\n"): 8 bytes.
pub const AR_MAGIC_LEN: Int = 8;

/// Width of one member header: 60 bytes.
pub const AR_HEADER_LEN: Int = 60;

/// Largest member name the codec accepts, in bytes (plain or BSD extended).
pub const AR_MAX_NAME: Int = 255;

/// Position of `mtime` inside the flat metadata vector.
pub const AR_META_MTIME: Int = 0;

/// Position of `uid` inside the flat metadata vector.
pub const AR_META_UID: Int = 1;

/// Position of `gid` inside the flat metadata vector.
pub const AR_META_GID: Int = 2;

/// Position of the ASCII octal `mode` inside the flat metadata vector.
pub const AR_META_MODE: Int = 3;

/// Number of metadata values per entry (stride of the flat metadata vector).
pub const AR_META_LEN: Int = 4;

// --------------------------------------------------
//  Parsed archive index
// --------------------------------------------------

/// Parsed ar archive index. One logical slot per member, in stream order.
///
/// `names[i]` is the decoded member name: plain names lose their trailing
/// spaces and one trailing '/' (the GNU/SysV regular-member marker), BSD
/// "#1/<len>" names are read from the start of the member data. `sizes[i]`
/// is the payload size (for BSD names the embedded name bytes are excluded)
/// and `data_offsets[i]` is the absolute index of the first payload byte in
/// the source buffer. `header_offsets[i]` is the absolute index of the
/// 60-byte member header. mtimes/uids/gids are ASCII decimal fields and
/// `modes` is an ASCII octal field, all stored as parsed. Fields are
/// implementation details; callers use the free functions below.
pub type ArArchive = {
  names: Vec[Str];
  header_offsets: Vec[Int];
  data_offsets: Vec[Int];
  sizes: Vec[Int];
  mtimes: Vec[Int];
  uids: Vec[Int];
  gids: Vec[Int];
  modes: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[ArArchive, Str].
fn _ok_archive(v: ArArchive) -> Result[ArArchive, Str] {
  return Ok(v);
}

// Err(m) for Result[ArArchive, Str].
fn _err_archive(m: Str) -> Result[ArArchive, Str] {
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

// Decimal field of `width` bytes at `off` as a non-negative Int.
//
// Leading spaces are skipped, at least one digit is required, and after the
// digits only spaces may follow; a digit after a space, an empty/all-space
// field and any other byte are Err("ar: bad decimal field").
fn _dec_field(data: &Vec[UInt8], off: Int, width: Int) -> Result[Int, Str] {
  var v: Int = 0;
  var seen = false;
  var closed = false;
  var bad = false;
  var i = 0;
  while i < width {
    let c: Int = _byte(data, off + i);
    if c >= 48 && c <= 57 {
      if closed {
        bad = true;
      } else {
        v = v * 10 + (c - 48);
        seen = true;
      }
    } elif c == 32 {
      if seen {
        closed = true;
      }
    } else {
      bad = true;
    }
    i = i + 1;
  }
  if bad || !seen {
    return _err_int("ar: bad decimal field");
  }
  return _ok_int(v);
}

// Octal field of `width` bytes at `off` as a non-negative Int; same shape as
// _dec_field with base 8 and Err("ar: bad octal field").
fn _oct_field(data: &Vec[UInt8], off: Int, width: Int) -> Result[Int, Str] {
  var v: Int = 0;
  var seen = false;
  var closed = false;
  var bad = false;
  var i = 0;
  while i < width {
    let c: Int = _byte(data, off + i);
    if c >= 48 && c <= 55 {
      if closed {
        bad = true;
      } else {
        v = v * 8 + (c - 48);
        seen = true;
      }
    } elif c == 32 {
      if seen {
        closed = true;
      }
    } else {
      bad = true;
    }
    i = i + 1;
  }
  if bad || !seen {
    return _err_int("ar: bad octal field");
  }
  return _ok_int(v);
}

// True when the 16-byte name field at `pos` is a BSD extended name field
// (starts with "#1/").
fn _is_bsd(data: &Vec[UInt8], pos: Int) -> Bool {
  if _byte(data, pos) != 35 {
    return false;
  }
  if _byte(data, pos + 1) != 49 {
    return false;
  }
  if _byte(data, pos + 2) != 47 {
    return false;
  }
  return true;
}

// Plain name bytes at `pos`: the bytes up to (not including) the first space
// or the full 16-byte field, whichever comes first. No trimming is done.
fn _plain_name(data: &Vec[UInt8], pos: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < 16 && !done {
    let c: Int = _byte(data, pos + i);
    if c == 32 {
      done = true;
    } else {
      bytes.push(c as UInt8);
    }
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// `len` bytes at `off` as a Str (the caller guarantees the bounds).
fn _bytes_str(data: &Vec[UInt8], off: Int, len: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < len {
    bytes.push(data[off + i]);
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// True when the eight bytes at offset 0 are the global archive magic
// "!<arch>\n"; a buffer shorter than 8 bytes never matches.
fn _magic_ok(data: &Vec[UInt8]) -> Bool {
  if data.len() < AR_MAGIC_LEN {
    return false;
  }
  if _byte(data, 0) != 33 {
    return false;
  }
  if _byte(data, 1) != 60 {
    return false;
  }
  if _byte(data, 2) != 97 {
    return false;
  }
  if _byte(data, 3) != 114 {
    return false;
  }
  if _byte(data, 4) != 99 {
    return false;
  }
  if _byte(data, 5) != 104 {
    return false;
  }
  if _byte(data, 6) != 62 {
    return false;
  }
  if _byte(data, 7) != 10 {
    return false;
  }
  return true;
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

// Append `count` space bytes (0x20).
fn _push_spaces(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(32 as UInt8);
    i = i + 1;
  }
}

// Append the ASCII decimal digits of the non-negative `v` (no leading
// zeros; 0 is "0").
fn _push_dec_plain(out: &mut Vec[UInt8], v: Int) {
  if v == 0 {
    out.push(48 as UInt8);
  } else {
    var digits = Vec[UInt8].new();
    var n: Int = v;
    while n > 0 {
      let d: Int = n % 10;
      digits.push((48 + d) as UInt8);
      n = n / 10;
    }
    var i: Int = digits.len() - 1;
    while i >= 0 {
      out.push(digits[i]);
      i = i - 1;
    }
  }
}

// Append the ASCII octal digits of the non-negative `v` (no leading zeros;
// 0 is "0").
fn _push_oct_plain(out: &mut Vec[UInt8], v: Int) {
  if v == 0 {
    out.push(48 as UInt8);
  } else {
    var digits = Vec[UInt8].new();
    var n: Int = v;
    while n > 0 {
      let d: Int = n % 8;
      digits.push((48 + d) as UInt8);
      n = n / 8;
    }
    var i: Int = digits.len() - 1;
    while i >= 0 {
      out.push(digits[i]);
      i = i - 1;
    }
  }
}

// Append `v` as decimal digits followed by spaces to exactly `width` bytes;
// the caller guarantees the digits fit.
fn _push_dec_padded(out: &mut Vec[UInt8], v: Int, width: Int) {
  let mark: Int = out.len();
  _push_dec_plain(out, v);
  _push_spaces(out, width - (out.len() - mark));
}

// Append `v` as octal digits followed by spaces to exactly `width` bytes;
// the caller guarantees the digits fit.
fn _push_oct_padded(out: &mut Vec[UInt8], v: Int, width: Int) {
  let mark: Int = out.len();
  _push_oct_plain(out, v);
  _push_spaces(out, width - (out.len() - mark));
}

// True when the name must use the BSD "#1/<len>" form: longer than the
// 16-byte plain field, containing a space, or starting/ending with '/'
// (a plain field is space terminated, and a trailing '/' is the GNU
// regular-member marker, so neither can round-trip through the plain form).
fn _name_needs_bsd(name: Str) -> Bool {
  let n: Int = name.len();
  if n > 16 {
    return true;
  }
  var i = 0;
  while i < n {
    if ((string.byte_at(name, i) as Int) & 0xFF) == 32 {
      return true;
    }
    i = i + 1;
  }
  if ((string.byte_at(name, 0) as Int) & 0xFF) == 47 {
    return true;
  }
  if ((string.byte_at(name, n - 1) as Int) & 0xFF) == 47 {
    return true;
  }
  return false;
}

// Validate and append one complete member to `out`: the 60-byte header, the
// BSD name bytes when used, the data, and one 0x0A pad byte when the member
// size is odd. All validation runs before the first byte is written, so
// `out` is unchanged on Err.
//
// Err("ar: bad name") for an empty name, Err("ar: name too long") above
// AR_MAX_NAME bytes, Err("ar: field overflow") when a metadata value is
// negative or wider than its field (mtime 12, uid/gid 6, mode 8 octal
// digits, size 10 decimal digits).
fn _write_member(out: &mut Vec[UInt8], name: Str, mtime: Int, uid: Int, gid: Int, mode: Int, data: &Vec[UInt8]) -> Result[Unit, Str] {
  let name_len: Int = name.len();
  if name_len == 0 {
    return _err_unit("ar: bad name");
  }
  if name_len > AR_MAX_NAME {
    return _err_unit("ar: name too long");
  }
  if mtime < 0 || mtime > 999999999999 {
    return _err_unit("ar: field overflow");
  }
  if uid < 0 || uid > 999999 {
    return _err_unit("ar: field overflow");
  }
  if gid < 0 || gid > 999999 {
    return _err_unit("ar: field overflow");
  }
  if mode < 0 || mode > 16777215 {
    return _err_unit("ar: field overflow");
  }
  let bsd: Bool = _name_needs_bsd(name);
  let data_len: Int = data.len();
  var size: Int = data_len;
  if bsd {
    size = name_len + data_len;
  }
  if size > 9999999999 {
    return _err_unit("ar: field overflow");
  }
  let name_mark: Int = out.len();
  if bsd {
    _push_str(out, "#1/");
    _push_dec_plain(out, name_len);
  } else {
    _push_str(out, name);
  }
  _push_spaces(out, 16 - (out.len() - name_mark));
  _push_dec_padded(out, mtime, 12);
  _push_dec_padded(out, uid, 6);
  _push_dec_padded(out, gid, 6);
  _push_oct_padded(out, mode, 8);
  _push_dec_padded(out, size, 10);
  out.push(96 as UInt8);
  out.push(10 as UInt8);
  if bsd {
    _push_str(out, name);
  }
  _push_bytes(out, data);
  if size % 2 == 1 {
    out.push(10 as UInt8);
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// The eight global magic bytes, "!<arch>\n". Every archive starts with
/// them; `ar_append` writes members only, so compose it with `ar_append` for
/// streaming builds or use `ar_build`. Complexity: O(1).
pub fn ar_global() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(33 as UInt8);
  out.push(60 as UInt8);
  out.push(97 as UInt8);
  out.push(114 as UInt8);
  out.push(99 as UInt8);
  out.push(104 as UInt8);
  out.push(62 as UInt8);
  out.push(10 as UInt8);
  return out;
}

/// Parse an ar archive buffer.
///
/// The first eight bytes must be the global magic "!<arch>\n" ->
/// Err("ar: bad global magic") (an empty or shorter buffer is also that
/// error). Members are then walked from offset 8; each member occupies a
/// 60-byte header followed by `size` data bytes, plus one 0x0A pad byte when
/// `size` is odd.
///
/// Per-member validation order (first failure wins): header fits ->
/// Err("ar: truncated header"); the terminator bytes 58..59 are 0x60 0x0A ->
/// Err("ar: bad terminator"); the name field (plain or "#1/<len>") is valid
/// -> Err("ar: bad name") for an empty name or a BSD length below 1,
/// Err("ar: unsupported special member") when a plain name starts with '/'
/// (the GNU symbol table "/", long-name table "//" and "/<digits>"
/// references), Err("ar: name too long") above AR_MAX_NAME bytes,
/// Err("ar: bad decimal field") for a malformed "#1/" length; mtime, uid,
/// gid and size are ASCII decimal and mode is ASCII octal ->
/// Err("ar: bad decimal field") / Err("ar: bad octal field"); the declared
/// size fits the buffer -> Err("ar: truncated data"); a BSD name length not
/// greater than the declared size -> Err("ar: size/data mismatch"); the odd
/// size pad byte exists -> Err("ar: missing padding") and is 0x0A ->
/// Err("ar: bad padding").
///
/// On success the returned ArArchive lists every member in file order.
/// Plain names lose their trailing spaces and one trailing '/'; BSD names
/// are read from the start of the member data and excluded from
/// `sizes`/`data_offsets`. A magic-only buffer parses to zero entries.
/// Complexity: O(data.len()).
pub fn ar_parse(data: &Vec[UInt8]) -> Result[ArArchive, Str] {
  if !_magic_ok(data) {
    return _err_archive("ar: bad global magic");
  }
  var names = Vec[Str].new();
  var header_offsets = Vec[Int].new();
  var data_offsets = Vec[Int].new();
  var sizes = Vec[Int].new();
  var mtimes = Vec[Int].new();
  var uids = Vec[Int].new();
  var gids = Vec[Int].new();
  var modes = Vec[Int].new();
  let n = data.len();
  var pos = AR_MAGIC_LEN;
  while pos < n {
    if n - pos < AR_HEADER_LEN {
      return _err_archive("ar: truncated header");
    }
    if _byte(data, pos + 58) != 96 {
      return _err_archive("ar: bad terminator");
    }
    if _byte(data, pos + 59) != 10 {
      return _err_archive("ar: bad terminator");
    }
    let bsd: Bool = _is_bsd(data, pos);
    var member_name: Str = "";
    var name_len: Int = 0;
    if bsd {
      let lr = _dec_field(data, pos + 3, 13);
      if !lr.is_ok {
        return _err_archive("ar: bad decimal field");
      }
      name_len = lr.value;
      if name_len < 1 {
        return _err_archive("ar: bad name");
      }
      if name_len > AR_MAX_NAME {
        return _err_archive("ar: name too long");
      }
    } else {
      let raw: Str = _plain_name(data, pos);
      let raw_len: Int = raw.len();
      if raw_len == 0 {
        return _err_archive("ar: bad name");
      }
      if ((string.byte_at(raw, 0) as Int) & 0xFF) == 47 {
        return _err_archive("ar: unsupported special member");
      }
      if ((string.byte_at(raw, raw_len - 1) as Int) & 0xFF) == 47 {
        member_name = string.str_slice(raw, 0, raw_len - 1);
      } else {
        member_name = raw;
      }
    }
    let mr = _dec_field(data, pos + 16, 12);
    if !mr.is_ok {
      return _err_archive("ar: bad decimal field");
    }
    let ur = _dec_field(data, pos + 28, 6);
    if !ur.is_ok {
      return _err_archive("ar: bad decimal field");
    }
    let gr = _dec_field(data, pos + 34, 6);
    if !gr.is_ok {
      return _err_archive("ar: bad decimal field");
    }
    let mor = _oct_field(data, pos + 40, 8);
    if !mor.is_ok {
      return _err_archive("ar: bad octal field");
    }
    let sr = _dec_field(data, pos + 48, 10);
    if !sr.is_ok {
      return _err_archive("ar: bad decimal field");
    }
    let mtime: Int = mr.value;
    let uid: Int = ur.value;
    let gid: Int = gr.value;
    let mode: Int = mor.value;
    let size: Int = sr.value;
    let body_start: Int = pos + AR_HEADER_LEN;
    if size > n - body_start {
      return _err_archive("ar: truncated data");
    }
    var payload_off: Int = body_start;
    var payload_size: Int = size;
    if bsd {
      if size < name_len {
        return _err_archive("ar: size/data mismatch");
      }
      member_name = _bytes_str(data, body_start, name_len);
      payload_off = body_start + name_len;
      payload_size = size - name_len;
    }
    names.push(member_name);
    header_offsets.push(pos);
    data_offsets.push(payload_off);
    sizes.push(payload_size);
    mtimes.push(mtime);
    uids.push(uid);
    gids.push(gid);
    modes.push(mode);
    let body_end: Int = body_start + size;
    if size % 2 == 1 {
      if body_end >= n {
        return _err_archive("ar: missing padding");
      }
      if _byte(data, body_end) != 10 {
        return _err_archive("ar: bad padding");
      }
      pos = body_end + 1;
    } else {
      pos = body_end;
    }
  }
  let archive = ArArchive{
    names: names;
    header_offsets: header_offsets;
    data_offsets: data_offsets;
    sizes: sizes;
    mtimes: mtimes;
    uids: uids;
    gids: gids;
    modes: modes;
  };
  return _ok_archive(archive);
}

/// Number of parsed members. Complexity: O(1).
pub fn ar_count(a: &ArArchive) -> Int {
  return a.names.len();
}

/// Name of entry `i`, or "" when `i` is out of range. The result is a Str
/// read from a Vec[Str] field: callers must compare it with
/// xiom.string.compare.str_compare rather than `==`. Complexity: O(1).
pub fn ar_entry_name(a: &ArArchive, i: Int) -> Str {
  if i < 0 || i >= a.names.len() {
    return "";
  }
  let nm: Str = a.names[i];
  return nm;
}

/// Absolute offset of entry `i`'s 60-byte member header in the parse buffer;
/// -1 out of range. Complexity: O(1).
pub fn ar_entry_header_offset(a: &ArArchive, i: Int) -> Int {
  if i < 0 || i >= a.header_offsets.len() {
    return -1;
  }
  let v: Int = a.header_offsets[i];
  return v;
}

/// Payload size of entry `i` in bytes (BSD name bytes excluded); -1 out of
/// range. Complexity: O(1).
pub fn ar_entry_size(a: &ArArchive, i: Int) -> Int {
  if i < 0 || i >= a.sizes.len() {
    return -1;
  }
  let v: Int = a.sizes[i];
  return v;
}

/// Absolute offset of entry `i`'s first payload byte in the parse buffer
/// (just past the BSD name bytes when used); -1 out of range.
/// Complexity: O(1).
pub fn ar_entry_data_offset(a: &ArArchive, i: Int) -> Int {
  if i < 0 || i >= a.data_offsets.len() {
    return -1;
  }
  let v: Int = a.data_offsets[i];
  return v;
}

/// Modification time of entry `i` (seconds since the epoch, as stored);
/// -1 out of range. Complexity: O(1).
pub fn ar_entry_mtime(a: &ArArchive, i: Int) -> Int {
  if i < 0 || i >= a.mtimes.len() {
    return -1;
  }
  let v: Int = a.mtimes[i];
  return v;
}

/// User id of entry `i`; -1 out of range. Complexity: O(1).
pub fn ar_entry_uid(a: &ArArchive, i: Int) -> Int {
  if i < 0 || i >= a.uids.len() {
    return -1;
  }
  let v: Int = a.uids[i];
  return v;
}

/// Group id of entry `i`; -1 out of range. Complexity: O(1).
pub fn ar_entry_gid(a: &ArArchive, i: Int) -> Int {
  if i < 0 || i >= a.gids.len() {
    return -1;
  }
  let v: Int = a.gids[i];
  return v;
}

/// File mode of entry `i` (decoded from the ASCII octal mode field); -1 out
/// of range. Complexity: O(1).
pub fn ar_entry_mode(a: &ArArchive, i: Int) -> Int {
  if i < 0 || i >= a.modes.len() {
    return -1;
  }
  let v: Int = a.modes[i];
  return v;
}

/// Copy the payload bytes of entry `i` out of `data` (the buffer passed to
/// ar_parse): `sizes[i]` bytes starting at `data_offsets[i]`.
///
/// Err("ar: entry out of range") when `i` is negative or >= ar_count(a)
/// (or a hand-built archive carries a negative offset/size);
/// Err("ar: truncated data") when the recorded range does not fit in `data`.
/// A zero-size member yields an empty Ok. Complexity: O(size).
pub fn ar_entry_data(data: &Vec[UInt8], a: &ArArchive, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= a.names.len() {
    return _err_bytes("ar: entry out of range");
  }
  let off: Int = a.data_offsets[i];
  let size: Int = a.sizes[i];
  if off < 0 || size < 0 {
    return _err_bytes("ar: entry out of range");
  }
  if off + size > data.len() {
    return _err_bytes("ar: truncated data");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < size {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Append one complete member to `out` (no global magic; use ar_build or
/// prepend ar_global for a whole archive).
///
/// `meta` must hold exactly AR_META_LEN (4) values in field order: mtime,
/// uid, gid, mode. `data.len()` is written as the member size; names above
/// 16 bytes, names containing a space and names starting or ending with '/'
/// use the BSD "#1/<len>" form, every other name is written space padded in
/// the 16-byte plain field. All validation runs before the first byte is
/// written, so `out` is byte-for-byte unchanged on Err.
///
/// Err("ar: metadata length mismatch") when meta.len() != 4;
/// Err("ar: bad name") for an empty name; Err("ar: name too long") above
/// AR_MAX_NAME bytes; Err("ar: field overflow") when a metadata value is
/// negative or does not fit its field. Complexity: O(name + data).
pub fn ar_append(out: &mut Vec[UInt8], name: Str, meta: &Vec[Int], data: &Vec[UInt8]) -> Result[Unit, Str] {
  if meta.len() != AR_META_LEN {
    return _err_unit("ar: metadata length mismatch");
  }
  let mtime: Int = meta[AR_META_MTIME];
  let uid: Int = meta[AR_META_UID];
  let gid: Int = meta[AR_META_GID];
  let mode: Int = meta[AR_META_MODE];
  return _write_member(out, name, mtime, uid, gid, mode, data);
}

/// Build a whole ar archive from parallel name/data vectors plus a flat
/// metadata buffer.
///
/// `metas` must hold names.len() * AR_META_LEN values with entry `i`'s four
/// fields (mtime, uid, gid, mode) at `metas[i*4 .. i*4+3]`, the same order
/// ar_append takes, and `datas[i]` is the payload of `names[i]`. The result
/// starts with the global magic and contains every member with its odd-size
/// newline pad; there is no trailing terminator (an ar archive has none).
///
/// Err("ar: entry count mismatch") when names.len() != datas.len();
/// Err("ar: metadata length mismatch") when
/// metas.len() != names.len() * AR_META_LEN; otherwise the first per-entry
/// error (the ar_append catalog). An empty build yields exactly the 8-byte
/// global magic. Complexity: O(total name + data bytes).
pub fn ar_build(names: &Vec[Str], datas: &Vec[Vec[UInt8]], metas: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let count: Int = names.len();
  if datas.len() != count {
    return _err_bytes("ar: entry count mismatch");
  }
  if metas.len() != count * AR_META_LEN {
    return _err_bytes("ar: metadata length mismatch");
  }
  let magic = ar_global();
  var out = Vec[UInt8].new();
  _push_bytes(&mut out, &magic);
  var i = 0;
  while i < count {
    let nm: Str = names[i];
    let dt: Vec[UInt8] = datas[i];
    let mtime: Int = metas[i * AR_META_LEN + AR_META_MTIME];
    let uid: Int = metas[i * AR_META_LEN + AR_META_UID];
    let gid: Int = metas[i * AR_META_LEN + AR_META_GID];
    let mode: Int = metas[i * AR_META_LEN + AR_META_MODE];
    let r = _write_member(&mut out, nm, mtime, uid, gid, mode, &dt);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
    i = i + 1;
  }
  return _ok_bytes(out);
}
