// XIOM -- xiom.id3: ID3v2 tag inspection (version, size, text frames)
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.id3 placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: read-only inspection of a whole in-memory ID3v2 tag (the 10-byte
// header plus its frames) with the focus on text information frames
// (TIT2/TPE1/TALB/TXXX/...). Bytes are read as `data[pos] as Int`; multi-byte
// integers are decoded arithmetically (division/modulo), because `& 0xFF` on
// values with bit 31 set miscompiles in v0.61.3 (same bug documented in
// xiom.msgpack and xiom.wav).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * Frame ids and text payloads are materialized with
//     xiom.string.builder.sb_to_str (raw byte copy, byte-exact for both
//     latin1 and UTF-8), never with `==` on Str values read from a Vec[Str]
//     (BUG 17: that lowers to a pointer comparison; str_compare is used).
// See SPEC.md for the byte layout table, size encodings, encoding table,
// error catalog and test plan.

module xiom.id3

use xiom.string.builder;
use xiom.string.compare;

/// Text frames collected from one ID3v2 tag. `ids` and `texts` are
/// index-aligned: `texts[i]` is the decoded payload of frame `ids[i]`.
/// Only text frames (frame id starts with 'T') are collected. A text frame
/// whose encoding byte is neither 0 (latin1) nor 3 (UTF-8) is recorded with
/// an empty text (see id3_text_frames).
pub type Id3Tags = {
  ids: Vec[Str];
  texts: Vec[Str];
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(tags) for Result[Id3Tags, Str]; the two vectors are index-aligned.
fn _ok_tags(ids: Vec[Str], texts: Vec[Str]) -> Result[Id3Tags, Str] {
  return Ok(Id3Tags{ ids: ids; texts: texts; });
}

// Err(m) for Result[Id3Tags, Str].
fn _err_tags(m: Str) -> Result[Id3Tags, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` as an Int; callers guarantee 0 <= pos < data.len().
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return data[pos] as Int;
}

// True when the first three bytes are ASCII "ID3" (73 68 51).
fn _has_magic(data: &Vec[UInt8]) -> Bool {
  if data.len() < 3 {
    return false;
  }
  if _byte(data, 0) != 73 {
    return false;
  }
  if _byte(data, 1) != 68 {
    return false;
  }
  if _byte(data, 2) != 51 {
    return false;
  }
  return true;
}

// True when all `len` bytes at `pos` are zero (padding detector); callers
// guarantee the range is inside `data`.
fn _all_zero(data: &Vec[UInt8], pos: Int, len: Int) -> Bool {
  var i = 0;
  while i < len {
    if _byte(data, pos + i) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Syncsafe 28-bit big-endian read: four bytes, each contributing 7 bits
// (b0*2^21 + b1*2^14 + b2*2^7 + b3). Used by every tag header size field
// (ID3v2.2+) and by v2.4 frame sizes. Callers guarantee the four bytes are
// in bounds.
fn _synchsafe(data: &Vec[UInt8], pos: Int) -> Int {
  let b0 = _byte(data, pos);
  let b1 = _byte(data, pos + 1);
  let b2 = _byte(data, pos + 2);
  let b3 = _byte(data, pos + 3);
  return b0 * 2097152 + b1 * 16384 + b2 * 128 + b3;
}

// Plain unsigned 32-bit big-endian read (v2.3 frame sizes). Callers
// guarantee the four bytes are in bounds.
fn _be_u32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// Frame size for major version `ver`: syncsafe when 4, plain big-endian
// otherwise (v2.3; other majors are attempted with the v2.3 layout and are
// documented as such in SPEC.md).
fn _frame_size(data: &Vec[UInt8], pos: Int, ver: Int) -> Int {
  if ver == 4 {
    return _synchsafe(data, pos);
  }
  return _be_u32(data, pos);
}

// Copy `len` bytes at `pos` into a fresh Str, byte-exact (no transformation):
// latin1 bytes stay as they are and UTF-8 passes through. Callers guarantee
// the range is inside `data`.
fn _bytes_str(data: &Vec[UInt8], pos: Int, len: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    out.push(data[pos + i]);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// First text for `id` as an Ok result; Ok("") when the tag has no such
// frame. Used by the TIT2/TPE1/TALB convenience accessors.
fn _frame_text(tags: &Id3Tags, id: Str) -> Result[Str, Str] {
  let got = id3_frame(tags, id);
  match got {
    Some(v) => { return _ok_str(v); },
    None => { return _ok_str(""); },
  }
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when the buffer starts with the ASCII magic "ID3" at offset 0.
/// Only the three magic bytes are checked, so a truncated 3-byte buffer
/// still reports true (documented in SPEC.md).
pub fn id3_has_tag(data: &Vec[UInt8]) -> Bool {
  return _has_magic(data);
}

/// Major version of the tag (byte 3 of the header): 3 for ID3v2.3, 4 for
/// ID3v2.4. Other majors are returned as stored (e.g. 2 or 5); this module
/// parses frames with the v2.3 layout unless the major is 4.
/// Err("id3: truncated header") when the buffer is shorter than the 10-byte
/// header; Err("id3: bad magic") when it does not start with "ID3".
pub fn id3_version(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() < 10 {
    return _err_int("id3: truncated header");
  }
  if !_has_magic(data) {
    return _err_int("id3: bad magic");
  }
  return _ok_int(_byte(data, 3));
}

/// Total tag size in bytes: the syncsafe 28-bit size field (header bytes
/// 6..9) plus the 10 header bytes. The declared total may be smaller than
/// the buffer (audio data follows most tags); trailing bytes are ignored.
/// Err("id3: truncated header") when the buffer is shorter than 10 bytes;
/// Err("id3: bad magic") on a missing "ID3" magic; Err("id3: tag size
/// beyond buffer") when the declared total exceeds the buffer length.
pub fn id3_tag_size(data: &Vec[UInt8]) -> Result[Int, Str] {
  if data.len() < 10 {
    return _err_int("id3: truncated header");
  }
  if !_has_magic(data) {
    return _err_int("id3: bad magic");
  }
  let total = _synchsafe(data, 6) + 10;
  if total > data.len() {
    return _err_int("id3: tag size beyond buffer");
  }
  return _ok_int(total);
}

/// Walk the frames in the tag and collect its text frames.
///
/// Frame layout (v2.3/v2.4): 4-byte id, 4-byte size (v2.3 plain big-endian,
/// v2.4 syncsafe), 2 flag bytes (ignored), then the payload. The walk stops
/// at padding (a zero frame id) or at a zero frame size; a frame whose
/// payload would extend past the declared tag total is
/// Err("id3: frame size beyond tag"). Non-text frames (id not starting with
/// 'T') are skipped and the walk continues from the next frame.
///
/// Text frames: the first payload byte is the encoding; only 0 (latin1) and
/// 3 (UTF-8) are decoded, both byte-exact (no re-encoding). Any other
/// encoding is recorded with an empty text. The frame id is recorded either
/// way, so `ids` and `texts` stay index-aligned.
///
/// Structural errors are propagated from id3_tag_size.
pub fn id3_text_frames(data: &Vec[UInt8]) -> Result[Id3Tags, Str] {
  let hdr = id3_tag_size(data);
  if !hdr.is_ok {
    return _err_tags(hdr.error);
  }
  let total = hdr.value;
  let ver = _byte(data, 3);
  var ids = Vec[Str].new();
  var texts = Vec[Str].new();
  var pos = 10;
  var stop = false;
  while !stop && pos + 10 <= total {
    if _all_zero(data, pos, 4) {
      stop = true;
    } else {
      let fsize = _frame_size(data, pos + 4, ver);
      if fsize == 0 {
        stop = true;
      } elif pos + 10 + fsize > total {
        return _err_tags("id3: frame size beyond tag");
      } else {
        if _byte(data, pos) == 84 {
          let fid = _bytes_str(data, pos, 4);
          let enc = _byte(data, pos + 10);
          var body = "";
          if enc == 0 || enc == 3 {
            body = _bytes_str(data, pos + 11, fsize - 1);
          }
          ids.push(fid);
          texts.push(body);
        }
        pos = pos + 10 + fsize;
      }
    }
  }
  return _ok_tags(ids, texts);
}

/// First text frame whose id equals `id` (byte-exact str_compare), or None
/// when the tag has no such frame. `ids` and `texts` are walked together;
/// the first match wins.
pub fn id3_frame(tags: &Id3Tags, id: Str) -> Option[Str] {
  var i = 0;
  while i < tags.ids.len() {
    let fid = tags.ids[i];
    if compare.str_compare(fid, id) == 0 {
      let text = tags.texts[i];
      return Some(text);
    }
    i = i + 1;
  }
  return None;
}

/// Number of collected text frames (== ids.len() == texts.len()).
pub fn id3_frame_count(tags: &Id3Tags) -> Int {
  return tags.ids.len();
}

/// TIT2 (song title) text. Ok("") when the tag exists but has no TIT2
/// frame; structural errors are propagated from id3_text_frames.
pub fn id3_title(data: &Vec[UInt8]) -> Result[Str, Str] {
  let r = id3_text_frames(data);
  if !r.is_ok {
    return _err_str(r.error);
  }
  return _frame_text(&r.value, "TIT2");
}

/// TPE1 (lead artist) text. Ok("") when the tag exists but has no TPE1
/// frame; structural errors are propagated from id3_text_frames.
pub fn id3_artist(data: &Vec[UInt8]) -> Result[Str, Str] {
  let r = id3_text_frames(data);
  if !r.is_ok {
    return _err_str(r.error);
  }
  return _frame_text(&r.value, "TPE1");
}

/// TALB (album) text. Ok("") when the tag exists but has no TALB frame;
/// structural errors are propagated from id3_text_frames.
pub fn id3_album(data: &Vec[UInt8]) -> Result[Str, Str] {
  let r = id3_text_frames(data);
  if !r.is_ok {
    return _err_str(r.error);
  }
  return _frame_text(&r.value, "TALB");
}
