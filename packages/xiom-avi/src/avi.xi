// XIOM -- xiom.avi: RIFF/AVI structure -- chunk walking and the main AVI header (avih)
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.avi placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the RIFF container skeleton of an AVI file. avi_is_file checks the
// "RIFF" + size + "AVI " signature, avi_riff_size reads the RIFF ChunkSize
// field, avi_find_chunk walks the TOP-LEVEL chunk list (4-byte id + LE u32
// size + payload, word-aligned to 2 bytes) and returns the payload offset,
// and avi_parse_avih locates the "avih" (main AVI header) chunk at the top
// level or inside the first "LIST hdrl" and returns the five metadata fields
// this package exposes. All multi-byte integers are little-endian and are
// read arithmetically (division and modulo); `& 0xFF` on Int operands with
// bit 31 set miscompiles in v0.61.3 (see xiom.wav and xiom.tar).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * AviInfo crosses function boundaries only by reference (&AviInfo) and
//     is constructed only inside the _ok_info leaf helper.
//   * the chunk walker (_scan_range) returns plain Int codes instead of a
//     Result; the public functions map those codes to the documented error
//     strings through the leaf helpers.
// See SPEC.md for the chunk layout table, the avih field map, the error
// catalog and the test plan.

module xiom.avi

use xiom.string;

/// Main AVI header (avih) fields exposed by this package: frame duration in
/// microseconds, total frame count, frame width and height in pixels, and
/// the stream count (see SPEC.md for the exact payload offsets).
pub type AviInfo = {
  micro_sec_per_frame: Int;
  total_frames: Int;
  width: Int;
  height: Int;
  streams: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Err(m) for Result[AviInfo, Str].
fn _err_info(m: Str) -> Result[AviInfo, Str] {
  return Err(m);
}

// Ok(AviInfo) packed from the five exposed header fields.
fn _ok_info(micro_sec_per_frame: Int, total_frames: Int, width: Int, height: Int, streams: Int) -> Result[AviInfo, Str] {
  return Ok(AviInfo{
    micro_sec_per_frame: micro_sec_per_frame;
    total_frames: total_frames;
    width: width;
    height: height;
    streams: streams;
  });
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned little-endian u32 at `pos`; callers guarantee the bounds.
fn _le_u32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + _byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// True when the four bytes at `pos` equal the ASCII codes a, b, c, d.
fn _tag4(data: &Vec[UInt8], pos: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if _byte(data, pos) != a { return false; }
  if _byte(data, pos + 1) != b { return false; }
  if _byte(data, pos + 2) != c { return false; }
  if _byte(data, pos + 3) != d { return false; }
  return true;
}

// True when the four bytes at `pos` equal the four bytes of `id`. The caller
// guarantees id.len() == 4 and that the bytes at `pos..pos+4` exist.
fn _id_at(data: &Vec[UInt8], pos: Int, id: Str) -> Bool {
  var i = 0;
  while i < 4 {
    if _byte(data, pos + i) != (string.byte_at(id, i) as Int) { return false; }
    i = i + 1;
  }
  return true;
}

// Chunk walker over [start, end): returns the payload offset (header offset
// + 8) of the first chunk whose 4-byte id matches, or a negative code:
// -1 = no match, -2 = partial chunk header at the tail, -3 = a declared
// payload does not fit before `end`. Callers guarantee the file header was
// validated and that 12 <= start <= end <= data.len().
fn _scan_range(data: &Vec[UInt8], id: Str, start: Int, end: Int) -> Int {
  var pos = start;
  var result = -1;
  var stop = false;
  while !stop && pos < end {
    if pos + 8 > end {
      result = -2;
      stop = true;
    } else {
      let size = _le_u32(data, pos + 4);
      if pos + 8 + size > end {
        result = -3;
        stop = true;
      } elif _id_at(data, pos, id) {
        result = pos + 8;
        stop = true;
      } else {
        pos = pos + 8 + size + (size % 2);
      }
    }
  }
  return result;
}

// Top-level walk over the whole buffer.
fn _scan(data: &Vec[UInt8], id: Str, start: Int) -> Int {
  return _scan_range(data, id, start, data.len());
}

// Map a negative walker code to its documented error string.
fn _scan_error(code: Int) -> Str {
  if code == -2 { return "avi: chunk truncated"; }
  return "avi: chunk out of range";
}

// Read the avih payload at `off`. Ten little-endian u32 fields make up the
// 56-byte payload; this package exposes micro_sec_per_frame (payload + 0),
// total_frames (+ 16), streams (+ 24, the historical dwStreams slot),
// width (+ 32) and height (+ 36) (AVIMAINHEADER layout).
fn _avih_at(data: &Vec[UInt8], off: Int) -> Result[AviInfo, Str] {
  if off + 56 > data.len() {
    return _err_info("avi: truncated avih");
  }
  let micro = _le_u32(data, off);
  let frames = _le_u32(data, off + 16);
  let width = _le_u32(data, off + 32);
  let height = _le_u32(data, off + 36);
  let streams = _le_u32(data, off + 24);
  return _ok_info(micro, frames, width, height, streams);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when `data` starts with the AVI RIFF signature: "RIFF" at 0, a size
/// field at 4 and the "AVI " form type at 8, so the buffer must be at least
/// 12 bytes. The stored RIFF size is returned by avi_riff_size but is never
/// cross-checked against the buffer length (a mismatched size field does not
/// make this predicate false).
pub fn avi_is_file(data: &Vec[UInt8]) -> Bool {
  if data.len() < 12 { return false; }
  if !_tag4(data, 0, 82, 73, 70, 70) { return false; }
  if !_tag4(data, 8, 65, 86, 73, 32) { return false; }
  return true;
}

/// Unsigned 32-bit little-endian RIFF ChunkSize field (offset 4) of an AVI
/// file. Validates the same 12-byte header as avi_is_file, in this order:
/// len >= 12 -> Err("avi: truncated header"); "RIFF" -> Err("avi: bad RIFF
/// magic"); "AVI " -> Err("avi: bad AVI magic"). The stored size is
/// returned as-is (for a well-formed file it is len - 8); no cross-check is
/// performed.
pub fn avi_riff_size(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() < 12 { return _err_int("avi: truncated header"); }
  if !_tag4(data, 0, 82, 73, 70, 70) { return _err_int("avi: bad RIFF magic"); }
  if !_tag4(data, 8, 65, 86, 73, 32) { return _err_int("avi: bad AVI magic"); }
  return _ok_int(_le_u32(data, 4));
}

/// Find a TOP-LEVEL RIFF chunk by its 4-byte `id` and return the absolute
/// offset of its payload (chunk header offset + 8). The walk starts at
/// `start` (normally 12, the first byte after the RIFF header) and steps
/// chunk to chunk: 4-byte id, unsigned LE u32 size, `size` payload bytes,
/// then one padding byte when `size` is odd (word alignment).
///
/// LIST chunks are NOT entered: a LIST payload is skipped as a whole, so an
/// avih nested in "LIST hdrl" is not found here (avi_parse_avih performs
/// that second search). Errors, in order: len < 12 -> Err("avi: truncated
/// header"); bad "RIFF" -> Err("avi: bad RIFF magic"); bad "AVI " ->
/// Err("avi: bad AVI magic"); id.len() != 4 -> Err("avi: bad chunk id");
/// start < 12 or start > len -> Err("avi: bad start offset"); a declared
/// payload that does not fit -> Err("avi: chunk out of range"); a partial
/// chunk header at the tail -> Err("avi: chunk truncated"); no match ->
/// Err("avi: chunk not found"). A missing final padding byte after an odd
/// payload is tolerated (the walk simply ends).
pub fn avi_find_chunk(data: &Vec[UInt8], id: Str, start: Int) -> Result[Int, Str] {
  if data.len() < 12 { return _err_int("avi: truncated header"); }
  if !_tag4(data, 0, 82, 73, 70, 70) { return _err_int("avi: bad RIFF magic"); }
  if !_tag4(data, 8, 65, 86, 73, 32) { return _err_int("avi: bad AVI magic"); }
  if id.len() != 4 { return _err_int("avi: bad chunk id"); }
  if start < 12 || start > data.len() { return _err_int("avi: bad start offset"); }
  let found = _scan(data, id, start);
  if found >= 0 { return _ok_int(found); }
  if found == -1 { return _err_int("avi: chunk not found"); }
  return _err_int(_scan_error(found));
}

/// Parse the main AVI header ("avih" chunk) into an AviInfo.
///
/// Search order: the first TOP-LEVEL "avih" chunk; when there is none, the
/// first TOP-LEVEL "LIST" chunk is entered, its 4-byte list type must be
/// "hdrl", and the first "avih" inside that hdrl payload is used. The
/// nested walk is bounded by the LIST chunk size. Subsequent LIST chunks
/// and LISTs nested in other LISTs are not searched (see SPEC.md).
///
/// Header errors are reported first (truncated header / bad RIFF magic /
/// bad AVI magic); a structural error found while walking is reported as
/// Err("avi: chunk out of range") or Err("avi: chunk truncated"); a
/// missing avih (or an avih-less LIST) is Err("avi: avih not found"); an
/// avih payload shorter than the full 56 bytes is Err("avi: truncated
/// avih"). On success the five exposed fields are read from the payload
/// offsets in SPEC.md.
pub fn avi_parse_avih(data: &Vec[UInt8]) -> Result[AviInfo, Str] {
  if data.len() < 12 { return _err_info("avi: truncated header"); }
  if !_tag4(data, 0, 82, 73, 70, 70) { return _err_info("avi: bad RIFF magic"); }
  if !_tag4(data, 8, 65, 86, 73, 32) { return _err_info("avi: bad AVI magic"); }
  let direct = _scan(data, "avih", 12);
  if direct >= 0 {
    return _avih_at(data, direct);
  }
  if direct != -1 {
    return _err_info(_scan_error(direct));
  }
  let list = _scan(data, "LIST", 12);
  if list < 0 {
    if list == -1 {
      return _err_info("avi: avih not found");
    }
    return _err_info(_scan_error(list));
  }
  let size = _le_u32(data, list - 4);
  var end = list + size;
  if end > data.len() { end = data.len(); }
  if end < list + 4 {
    return _err_info("avi: avih not found");
  }
  if !_tag4(data, list, 104, 100, 114, 108) {
    return _err_info("avi: avih not found");
  }
  let inner = _scan_range(data, "avih", list + 4, end);
  if inner >= 0 {
    return _avih_at(data, inner);
  }
  if inner != -1 {
    return _err_info(_scan_error(inner));
  }
  return _err_info("avi: avih not found");
}

/// Play duration in whole milliseconds: total_frames * micro_sec_per_frame
/// / 1000, truncated towards zero (integer division). A negative
/// micro_sec_per_frame is used as given.
pub fn avi_duration_ms(info: &AviInfo) -> Int {
  return info.total_frames * info.micro_sec_per_frame / 1000;
}

/// Frames per second in thousandths, rounded to the nearest permille:
/// (1000000000 + micro / 2) / micro. micro_sec_per_frame <= 0 yields 0.
/// Example: 40000 us/frame -> 25000 (25.000 fps); 33367 -> 29970
/// (29.970 fps, rounded from 29.9696).
pub fn avi_fps_permille(info: &AviInfo) -> Int {
  if info.micro_sec_per_frame <= 0 {
    return 0;
  }
  return (1000000000 + info.micro_sec_per_frame / 2) / info.micro_sec_per_frame;
}
