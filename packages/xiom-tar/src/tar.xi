// XIOM -- xiom.tar: POSIX ustar archive codec (parse and build)
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.tar placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: uncompressed POSIX ustar archives. tar_parse walks 512-byte header
// blocks, validates the magic and the unsigned checksum, parses the octal
// fields, joins prefix/name with '/' and indexes the payloads; tar_build
// emits ustar headers (typeflag '0', mode 0644, uid/gid 0, mtime 0), each
// payload padded to a 512-byte boundary, then the two zero-block terminator.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * TarArchive (six Vec fields) is constructed inside tar_parse and
//     crosses function boundaries only by reference or through
//     _ok_archive, following the xiom.bmp BmpInfo precedent.
//   * Str values read from Vec[Str] fields are bound to typed locals;
//     callers compare them with str_compare (BUG 17: `==` on a Str read
//     from a Vec lowers to a pointer comparison).
// See SPEC.md for the byte layout table, validation rules, error catalog
// and test plan.

module xiom.tar

use xiom.string;

/// Parsed tar archive index. One entry per valid header block, in file
/// order; the payload bytes stay in the source buffer and are located by
/// `data_offsets` (absolute index of the first payload byte) and `sizes`.
/// `types` maps the raw typeflag to 0 for a regular file ('0' or NUL), 5
/// for a directory ('5'), and to the raw typeflag byte value otherwise.
pub type TarArchive = {
  names: Vec[Str];
  types: Vec[Int];
  sizes: Vec[Int];
  modes: Vec[Int];
  mtimes: Vec[Int];
  data_offsets: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[TarArchive, Str].
fn _ok_archive(v: TarArchive) -> Result[TarArchive, Str] {
  return Ok(v);
}

// Err(m) for Result[TarArchive, Str].
fn _err_archive(m: Str) -> Result[TarArchive, Str] {
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

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned tar checksum of the 512 bytes starting at `base`: the sum of all
// bytes with the 8-byte checksum field (offsets 148..155) read as spaces.
fn _checksum(data: &Vec[UInt8], base: Int) -> Int {
  var sum: Int = 0;
  var i = 0;
  while i < 512 {
    if i >= 148 && i < 156 {
      sum = sum + 32;
    } else {
      sum = sum + _byte(data, base + i);
    }
    i = i + 1;
  }
  return sum;
}

// True when all 512 bytes at `off` are zero (an end-of-archive block).
fn _zero_block(data: &Vec[UInt8], off: Int) -> Bool {
  var i = 0;
  while i < 512 {
    if _byte(data, off + i) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when every byte in [off, end) is zero.
fn _tail_zero(data: &Vec[UInt8], off: Int, end: Int) -> Bool {
  var i = off;
  while i < end {
    if _byte(data, i) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ustar magic: bytes 257..261 are "ustar" and byte 262 is NUL (POSIX
// magic "ustar\0") or space (GNU magic "ustar "). The version bytes are
// not validated.
fn _magic_ok(data: &Vec[UInt8], base: Int) -> Bool {
  if _byte(data, base + 257) != 117 { return false; }
  if _byte(data, base + 258) != 115 { return false; }
  if _byte(data, base + 259) != 116 { return false; }
  if _byte(data, base + 260) != 97 { return false; }
  if _byte(data, base + 261) != 114 { return false; }
  let ver = _byte(data, base + 262);
  if ver != 0 && ver != 32 { return false; }
  return true;
}

// NUL-terminated field [off, off + max) as a Str: bytes up to the first
// NUL (or the field end); the NUL and any following bytes are dropped.
fn _field_str(data: &Vec[UInt8], off: Int, max: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  var done = false;
  while i < max && !done {
    let b: Int = _byte(data, off + i);
    if b == 0 {
      done = true;
    } else {
      bytes.push(b as UInt8);
    }
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// Octal field [off, off + len) as a non-negative Int. Leading NULs and
// spaces are skipped; digits accumulate until the field end or a NUL/space
// terminator; any other byte is Err("tar: bad octal"). A field with no
// digits at all (all NULs/spaces) is 0. Fields that a later digit follows
// after a terminator are rejected.
fn _octal(data: &Vec[UInt8], off: Int, len: Int) -> Result[Int, Str] {
  var v: Int = 0;
  var seen = false;
  var closed = false;
  var bad = false;
  var i = 0;
  while i < len {
    let c: Int = _byte(data, off + i);
    if c >= 48 && c <= 55 {
      if closed {
        bad = true;
      } else {
        v = v * 8 + (c - 48);
        seen = true;
      }
    } elif c == 0 || c == 32 {
      if seen {
        closed = true;
      }
    } else {
      bad = true;
    }
    i = i + 1;
  }
  if bad {
    return _err_int("tar: bad octal");
  }
  return _ok_int(v);
}

// Raw typeflag byte mapped to the documented type code.
fn _type_code(t: Int) -> Int {
  if t == 0 { return 0; }
  if t == 48 { return 0; }
  if t == 53 { return 5; }
  return t;
}

// Entry name: prefix joined with the name through '/' when the prefix is
// non-empty (POSIX ustar rule).
fn _join_name(prefix: Str, name: Str) -> Str {
  if prefix.len() == 0 {
    return name;
  }
  return string.str_concat(prefix, string.str_concat("/", name));
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
fn _push_zero(out: &mut Vec[UInt8], count: Int) {
  var i = 0;
  while i < count {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Append the zero-padded octal representation of the non-negative `v` as
// exactly `digits` ASCII octal digits (no terminator). Values wider than
// `digits` octal digits are truncated to the low `digits` digits.
fn _push_octal(out: &mut Vec[UInt8], v: Int, digits: Int) {
  var div: Int = 1;
  var k = 1;
  while k < digits {
    div = div * 8;
    k = k + 1;
  }
  var n = v;
  var i = 0;
  while i < digits {
    var d: Int = 0;
    if div > 0 {
      d = (n / div) % 8;
      n = n % div;
    }
    out.push((48 + d) as UInt8);
    div = div / 8;
    i = i + 1;
  }
}

// Append one complete 512-byte ustar header for a regular file. Layout:
// name[100], mode[8] "0000644\0", uid[8] "0000000\0", gid[8] "0000000\0",
// size[12] (11 octal digits + NUL), mtime[12] (11 octal digits + NUL),
// checksum[8] (6 octal digits + NUL + space), typeflag '0', linkname[100],
// magic "ustar\0", version "00", uname[32], gname[32], devmajor[8],
// devminor[8] (zeroed octal fields), prefix[155], pad[12].
fn _write_header(out: &mut Vec<UInt8>, name: Str, size: Int) {
  let base = out.len();
  var i = 0;
  while i < 100 {
    if i < name.len() {
      out.push(string.byte_at(name, i));
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  _push_octal(out, 420, 7);
  out.push(0 as UInt8);
  _push_octal(out, 0, 7);
  out.push(0 as UInt8);
  _push_octal(out, 0, 7);
  out.push(0 as UInt8);
  _push_octal(out, size, 11);
  out.push(0 as UInt8);
  _push_octal(out, 0, 11);
  out.push(0 as UInt8);
  _push_zero(out, 8);
  out.push(48 as UInt8);
  _push_zero(out, 100);
  _push_str(out, "ustar");
  out.push(0 as UInt8);
  _push_str(out, "00");
  _push_zero(out, 32);
  _push_zero(out, 32);
  _push_octal(out, 0, 7);
  out.push(0 as UInt8);
  _push_octal(out, 0, 7);
  out.push(0 as UInt8);
  _push_zero(out, 155);
  _push_zero(out, 12);
  let sum = _checksum(out, base);
  var cs = Vec[UInt8].new();
  _push_octal(&mut cs, sum, 6);
  var j = 0;
  while j < 6 {
    out[base + 148 + j] = cs[j];
    j = j + 1;
  }
  out[base + 154] = 0 as UInt8;
  out[base + 155] = 32 as UInt8;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse an uncompressed POSIX ustar archive.
///
/// Walks 512-byte header blocks from offset 0. A block that is entirely
/// zero ends the archive (the documented two-zero-block terminator); a
/// buffer that ends before the next header is also tolerated, and a short
/// trailing run of zero bytes is treated as the start of the terminator.
/// Each regular header is validated in this order: magic bytes 257..262
/// ("ustar" + NUL or space) -> Err("tar: bad magic"); the stored checksum
/// field is octal -> Err("tar: bad octal"); the stored checksum equals the
/// unsigned sum of the 512 bytes with the checksum field read as spaces ->
/// Err("tar: bad checksum"); mode/size/mtime fields are octal -> Err("tar:
/// bad octal"); the payload fits in the buffer -> Err("tar: truncated
/// data"). A partial non-zero header block is Err("tar: truncated
/// header").
///
/// On success the returned TarArchive lists every entry in file order.
/// Entry names are prefix + '/' + name when the ustar prefix field is
/// non-empty; sizes/modes/mtimes are the parsed octal values; types maps
/// the typeflag to 0 for '0'/NUL, 5 for '5' and to the raw byte value
/// otherwise; data_offsets points at the first payload byte in `data`.
/// Padding after a payload is skipped (512-byte alignment). Bytes after
/// the terminating zero block are ignored.
pub fn tar_parse(data: &Vec[UInt8]) -> Result[TarArchive, Str] {
  var names = Vec[Str].new();
  var types = Vec[Int].new();
  var sizes = Vec[Int].new();
  var modes = Vec[Int].new();
  var mtimes = Vec[Int].new();
  var offsets = Vec[Int].new();
  let n = data.len();
  var pos = 0;
  var stop = false;
  while !stop && pos < n {
    if pos + 512 > n {
      if _tail_zero(data, pos, n) {
        stop = true;
      } else {
        return _err_archive("tar: truncated header");
      }
    } else {
      if _zero_block(data, pos) {
        stop = true;
      } else {
        if !_magic_ok(data, pos) {
          return _err_archive("tar: bad magic");
        }
        let stored = _octal(data, pos + 148, 8);
        if !stored.is_ok {
          return _err_archive("tar: bad octal");
        }
        if stored.value != _checksum(data, pos) {
          return _err_archive("tar: bad checksum");
        }
        let mode = _octal(data, pos + 100, 8);
        if !mode.is_ok {
          return _err_archive("tar: bad octal");
        }
        let size = _octal(data, pos + 124, 12);
        if !size.is_ok {
          return _err_archive("tar: bad octal");
        }
        let mtime = _octal(data, pos + 136, 12);
        if !mtime.is_ok {
          return _err_archive("tar: bad octal");
        }
        let off = pos + 512;
        if size.value > n - off {
          return _err_archive("tar: truncated data");
        }
        let name = _field_str(data, pos, 100);
        let prefix = _field_str(data, pos + 345, 155);
        names.push(_join_name(prefix, name));
        types.push(_type_code(_byte(data, pos + 156)));
        sizes.push(size.value);
        modes.push(mode.value);
        mtimes.push(mtime.value);
        offsets.push(off);
        let padded = ((size.value + 511) / 512) * 512;
        pos = off + padded;
      }
    }
  }
  let archive = TarArchive{
    names: names;
    types: types;
    sizes: sizes;
    modes: modes;
    mtimes: mtimes;
    data_offsets: offsets;
  };
  return _ok_archive(archive);
}

/// Number of parsed entries. Complexity: O(1).
pub fn tar_entry_count(a: &TarArchive) -> Int {
  return a.names.len();
}

/// Name of entry `i` (including the joined ustar prefix). Out-of-range
/// indices return "" (the archive API stays infallible here; tar_entry_data
/// reports range errors). Complexity: O(1).
pub fn tar_entry_name(a: &TarArchive, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= a.names.len() {
    return "";
  }
  let name: Str = a.names[i];
  return name;
}

/// Declared size in bytes of entry `i`; 0 for an out-of-range index.
/// Complexity: O(1).
pub fn tar_entry_size(a: &TarArchive, i: Int) -> Int {
  if i < 0 {
    return 0;
  }
  if i >= a.sizes.len() {
    return 0;
  }
  let size: Int = a.sizes[i];
  return size;
}

/// Copy the payload bytes of entry `i` out of `data` (the buffer passed to
/// tar_parse): `sizes[i]` bytes starting at `data_offsets[i]`.
/// Err("tar: entry out of range") when `i` is negative or >=
/// tar_entry_count(a); Err("tar: truncated data") when the recorded range
/// does not fit in `data` (for example when a shorter buffer is passed).
/// A zero-size entry (directory) yields an empty Ok. Complexity: O(size).
pub fn tar_entry_data(data: &Vec[UInt8], a: &TarArchive, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 {
    return _err_bytes("tar: entry out of range");
  }
  if i >= a.names.len() {
    return _err_bytes("tar: entry out of range");
  }
  let off: Int = a.data_offsets[i];
  let size: Int = a.sizes[i];
  if off < 0 || size < 0 {
    return _err_bytes("tar: entry out of range");
  }
  if off + size > data.len() {
    return _err_bytes("tar: truncated data");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < size {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Build an uncompressed POSIX ustar archive from parallel name/payload
/// vectors. Every entry is a regular file: typeflag '0', mode 0644
/// ("0000644"), uid/gid 0, mtime 0, empty linkname/uname/gname/prefix,
/// checksum computed over the 512-byte header (unsigned, checksum field
/// read as spaces) and stored as 6 octal digits + NUL + space. Each payload
/// is emitted verbatim and padded with zeros to a 512-byte boundary; the
/// archive ends with two 512-byte zero blocks (1024 zero bytes).
///
/// Err("tar: payload count mismatch") when names.len() != payloads.len();
/// Err("tar: name too long") when a name is longer than 100 bytes (the
/// ustar name field width; such names need a prefix split or GNU longname
/// extensions, which this module does not emit). Names of exactly 100 bytes
/// are accepted and stored without a NUL terminator. An empty build (no
/// entries) yields the 1024-byte terminator alone. Complexity: O(total
/// payload + 512 * entries).
pub fn tar_build(names: &Vec[Str], payloads: &Vec[Vec[UInt8]]) -> Result[Vec[UInt8], Str] {
  if names.len() != payloads.len() {
    return _err_bytes("tar: payload count mismatch");
  }
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    if nm.len() > 100 {
      return _err_bytes("tar: name too long");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let pl: Vec[UInt8] = payloads[i];
    _write_header(&mut out, nm, pl.len());
    _push_bytes(&mut out, &pl);
    let padded = ((pl.len() + 511) / 512) * 512;
    _push_zero(&mut out, padded - pl.len());
    i = i + 1;
  }
  _push_zero(&mut out, 1024);
  return _ok_bytes(out);
}
