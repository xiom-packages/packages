// XIOM -- xiom.mp3: MPEG-1/2/2.5 frame headers, stream scan and ID3 tags
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structural MP3 parsing only -- no audio decoding.
//   * MPEG-1/2/2.5 frame headers: sync 0xFFE, version, layer, bitrate index
//     and table (per version/layer), sample-rate index and table, padding,
//     channel mode, mode extension, copyright/original/emphasis, CRC flag,
//     frame length in bytes and samples per frame;
//   * buffer scan: locate the first valid frame, count consecutive frames,
//     derive total samples and duration in whole milliseconds, flag
//     free-format frames and trailing corruption, and stop cleanly at an
//     ID3v1 tail tag;
//   * ID3v2.3/2.4 tag header (ID3 + version + flags + syncsafe size) and
//     frame walk with per-frame ids/sizes and text frames (TIT2, TPE1, TALB,
//     TRCK, TYER/TDRC, TCON); a whole-tag unsynchronisation flag is
//     de-escaped;
//   * ID3v1 128-byte tail tag: TAG, title/artist/album/year/comment/genre
//     and the ID3v1.1 track byte.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; bit fields
//     are extracted with division and modulo, never with shifts or `&` on
//     signed values.
//   * a Str is built from file bytes only when no 0x00 can end up inside it:
//     builder.sb_to_str hands out a NUL-terminated C string, so a raw 0x00
//     would silently truncate the result and trip its `result.len() ==
//     sb.len()` contract at run time. Text helpers stop at the first NUL.
//   * Mp3Scan keeps frame offsets and lengths in index-aligned parallel
//     vectors (no Vec[StructType]); every push mirrors a sibling push.
//   * Str values read from Vec[Str] are only ever compared with
//     string.compare.str_compare (BUG 17: `==` lowers to a pointer compare).
// See SPEC.md for the byte layout tables, the error catalog and the test
// matrix.

module xiom.mp3

use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed MPEG-1/2/2.5 audio frame header.
///
/// `version` is 1 (MPEG-1), 2 (MPEG-2) or 25 (MPEG-2.5); `layer` is 1, 2 or
/// 3 (Layer I/II/III). `bitrate_kbps` is > 0: headers carrying the
/// free-format bitrate index are rejected (see mp3_parse_frame_header), so
/// `frame_length` is always computable. `crc` is true when the protection
/// bit says a 16-bit CRC follows the header. `channel_mode` is 0 stereo,
/// 1 joint stereo, 2 dual channel, 3 mono; `mode_extension` is the raw 2-bit
/// field. `emphasis` is 0 none, 1 50/15 ms, 2 reserved, 3 CCITT J.17.
/// `frame_length` is the total frame size in bytes (header included, CRC and
/// padding included); `samples_per_frame` is 384, 1152 or 576.
pub type Mp3FrameHeader = {
  version: Int;
  layer: Int;
  bitrate_kbps: Int;
  sample_rate: Int;
  padding: Bool;
  crc: Bool;
  channel_mode: Int;
  mode_extension: Int;
  copyright: Bool;
  original: Bool;
  emphasis: Int;
  frame_length: Int;
  samples_per_frame: Int;
}

/// Result of scanning a buffer for consecutive MPEG audio frames.
///
/// `start` is the scan start offset as passed in; `offset` is the absolute
/// offset of the first valid frame; `frame_count` is the number of complete
/// consecutive frames counted, and `end_offset` is one past the last one.
/// `trailing_bytes` is `data.len() - end_offset`: the ID3v1 tail tag
/// included when the scan stopped at one (in that case `corrupted` stays
/// false). `corrupted` is true when the bytes after the last complete frame
/// do not parse as another frame with the same version/layer/sample rate
/// (junk, a partial frame, or a mismatched stream). `frame_offsets[i]` and
/// `frame_lengths[i]` are index-aligned with the counted frames. The
/// reported version/layer/sample rate/channel mode/bitrate are those of the
/// first frame; bitrate may vary per frame (VBR is accepted).
pub type Mp3Scan = {
  start: Int;
  offset: Int;
  frame_count: Int;
  end_offset: Int;
  trailing_bytes: Int;
  version: Int;
  layer: Int;
  sample_rate: Int;
  bitrate_kbps: Int;
  channel_mode: Int;
  samples_per_frame: Int;
  total_samples: Int;
  duration_ms: Int;
  corrupted: Bool;
  frame_offsets: Vec[Int];
  frame_lengths: Vec[Int];
}

/// Parsed ID3v2.3/2.4 tag header (the 10-byte header).
///
/// `version` is the major version byte and is only 3 or 4 (other majors are
/// rejected); `revision` is the revision byte; `flags` is the raw flags
/// byte. `payload_size` is the syncsafe-decoded 28-bit size field and
/// `total_size` is `10 + payload_size` (the footer, when present, is outside
/// the size field per the ID3v2.4 spec). `unsynchronised` (bit 7),
/// `extended_header` (bit 6, rejected by mp3_id3v2_frames),
/// `experimental` (bit 5) and `footer` (bit 4, v2.4) are the decoded flag
/// bits.
pub type Mp3Id3v2Info = {
  version: Int;
  revision: Int;
  flags: Int;
  payload_size: Int;
  total_size: Int;
  unsynchronised: Bool;
  extended_header: Bool;
  experimental: Bool;
  footer: Bool;
}

/// Text frames collected from one ID3v2 tag, in tag order.
///
/// `ids[i]`, `sizes[i]` and `texts[i]` are index-aligned: `texts[i]` is the
/// decoded payload of frame `ids[i]`. `sizes[i]` is the stored frame size
/// (v2.3 plain big-endian, v2.4 syncsafe). Only text frames (id starting
/// with 'T') get a decoded text; any other frame, or a text frame whose
/// encoding byte is neither 0 (latin1) nor 3 (UTF-8), is recorded with an
/// empty text. Text bytes stop at the first 0x00 (a NUL would truncate the
/// underlying C string), so multi-string frames keep only the first string.
pub type Mp3Id3v2Frames = {
  ids: Vec[Str];
  sizes: Vec[Int];
  texts: Vec[Str];
}

/// Parsed ID3v1 128-byte tail tag.
///
/// `title`, `artist`, `album`, `year` and `comment` are the fixed-size
/// fields with trailing NUL padding trimmed (each also stops at the first
/// 0x00). `track` is 0 and `has_track` false for ID3v1.0; for ID3v1.1
/// (`comment[28] == 0`, `comment[29] != 0`) `track` is the stored byte
/// (1..255) and `has_track` is true. `genre` is the raw genre byte
/// (0..255); mp3_id3v1_genre_name maps 0..79.
pub type Mp3Id3v1 = {
  title: Str;
  artist: Str;
  album: Str;
  year: Str;
  comment: Str;
  track: Int;
  has_track: Bool;
  genre: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Mp3FrameHeader, Str].
fn _ok_header(v: Mp3FrameHeader) -> Result[Mp3FrameHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[Mp3FrameHeader, Str].
fn _err_header(m: Str) -> Result[Mp3FrameHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[Mp3Scan, Str].
fn _ok_scan(v: Mp3Scan) -> Result[Mp3Scan, Str] {
  return Ok(v);
}

// Err(m) for Result[Mp3Scan, Str].
fn _err_scan(m: Str) -> Result[Mp3Scan, Str] {
  return Err(m);
}

// Ok(v) for Result[Mp3Id3v2Info, Str].
fn _ok_id3v2(v: Mp3Id3v2Info) -> Result[Mp3Id3v2Info, Str] {
  return Ok(v);
}

// Err(m) for Result[Mp3Id3v2Info, Str].
fn _err_id3v2(m: Str) -> Result[Mp3Id3v2Info, Str] {
  return Err(m);
}

// Ok(v) for Result[Mp3Id3v2Frames, Str].
fn _ok_frames(v: Mp3Id3v2Frames) -> Result[Mp3Id3v2Frames, Str] {
  return Ok(v);
}

// Err(m) for Result[Mp3Id3v2Frames, Str].
fn _err_frames(m: Str) -> Result[Mp3Id3v2Frames, Str] {
  return Err(m);
}

// Ok(v) for Result[Mp3Id3v1, Str].
fn _ok_v1(v: Mp3Id3v1) -> Result[Mp3Id3v1, Str] {
  return Ok(v);
}

// Err(m) for Result[Mp3Id3v1, Str].
fn _err_v1(m: Str) -> Result[Mp3Id3v1, Str] {
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
//  Internal byte and string helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u32 at `pos`; callers guarantee the bounds.
fn _be_u32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// True when the `n` bytes at `pos` are all zero (padding detector).
fn _all_zero(data: &Vec[UInt8], pos: Int, n: Int) -> Bool {
  var i = 0;
  while i < n {
    if _byte(data, pos + i) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the three bytes at `pos` equal the ASCII codes a, b, c.
fn _tag3_at(data: &Vec[UInt8], pos: Int, a: Int, b: Int, c: Int) -> Bool {
  if _byte(data, pos) != a { return false; }
  if _byte(data, pos + 1) != b { return false; }
  if _byte(data, pos + 2) != c { return false; }
  return true;
}

// Build a Str from at most `n` bytes at `pos`, stopping before the first
// 0x00. Callers guarantee the range is inside `data`. The stop-at-NUL rule
// is what keeps builder.sb_to_str's `result.len() == sb.len()` contract:
// a raw 0x00 would terminate the C string early.
fn _str_until_nul(data: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b = _byte(data, pos + i);
    if b == 0 {
      i = n;
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// Error text with the byte offset appended: "<msg> at <off>".
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + convert.int_to_string(off);
}

// True when the buffer starts with the three ASCII bytes "ID3".
fn _has_id3v2_magic(data: &Vec[UInt8]) -> Bool {
  if data.len() < 3 {
    return false;
  }
  if _byte(data, 0) != 73 { return false; }
  if _byte(data, 1) != 68 { return false; }
  if _byte(data, 2) != 51 { return false; }
  return true;
}

// Frame payload size at `pos` for major version `ver`: syncsafe (4 x 7
// bits, each byte's high bit clear) for v2.4, plain big-endian u32 for
// v2.3. Returns -1 when a v2.4 size byte has its high bit set. `pos` is the
// frame start; the size field sits at `pos + 4`.
fn _frame_size(data: &Vec[UInt8], pos: Int, ver: Int) -> Int {
  if ver == 4 {
    var v = 0;
    var i = 0;
    while i < 4 {
      let b = _byte(data, pos + 4 + i);
      if b >= 128 {
        return -1;
      }
      v = v * 128 + b;
      i = i + 1;
    }
    return v;
  }
  return _be_u32(data, pos + 4);
}

// --------------------------------------------------
//  Frame header tables
// --------------------------------------------------

/// Name of a version code: 1 -> "MPEG-1", 2 -> "MPEG-2", 25 -> "MPEG-2.5",
/// anything else -> "". Complexity: O(1).
pub fn mp3_version_name(version: Int) -> Str {
  if version == 1 { return "MPEG-1"; }
  if version == 2 { return "MPEG-2"; }
  if version == 25 { return "MPEG-2.5"; }
  return "";
}

/// Name of a layer code: 1 -> "Layer I", 2 -> "Layer II", 3 -> "Layer III",
/// anything else -> "". Complexity: O(1).
pub fn mp3_layer_name(layer: Int) -> Str {
  if layer == 1 { return "Layer I"; }
  if layer == 2 { return "Layer II"; }
  if layer == 3 { return "Layer III"; }
  return "";
}

/// Name of a channel mode: 0 -> "stereo", 1 -> "joint stereo", 2 -> "dual
/// channel", 3 -> "mono", anything else -> "". Complexity: O(1).
pub fn mp3_channel_mode_name(mode: Int) -> Str {
  if mode == 0 { return "stereo"; }
  if mode == 1 { return "joint stereo"; }
  if mode == 2 { return "dual channel"; }
  if mode == 3 { return "mono"; }
  return "";
}

/// Name of an emphasis code: 0 -> "none", 1 -> "50/15 ms", 2 -> "reserved",
/// 3 -> "CCITT J.17", anything else -> "". Complexity: O(1).
pub fn mp3_emphasis_name(emphasis: Int) -> Str {
  if emphasis == 0 { return "none"; }
  if emphasis == 1 { return "50/15 ms"; }
  if emphasis == 2 { return "reserved"; }
  if emphasis == 3 { return "CCITT J.17"; }
  return "";
}

/// Sample rate in Hz for (`version`, `index`), or 0 when the index or the
/// version is invalid. Tables: MPEG-1 {44100, 48000, 32000}, MPEG-2
/// {22050, 24000, 16000}, MPEG-2.5 {11025, 12000, 8000}. Index 3 is
/// reserved and never reaches this table from a parsed header.
/// Complexity: O(1).
pub fn mp3_sample_rate(version: Int, index: Int) -> Int {
  if index < 0 || index > 2 {
    return 0;
  }
  if version == 1 {
    if index == 0 { return 44100; }
    if index == 1 { return 48000; }
    return 32000;
  }
  if version == 2 {
    if index == 0 { return 22050; }
    if index == 1 { return 24000; }
    return 16000;
  }
  if version == 25 {
    if index == 0 { return 11025; }
    if index == 1 { return 12000; }
    return 8000;
  }
  return 0;
}

/// Bitrate in kbps for (`version`, `layer`, `index`). Returns 0 for the
/// free-format index 0 and -1 for index 15 (bad), for an out-of-range index
/// or for an unknown version/layer. Tables:
/// MPEG-1 Layer I {32,64,96,128,160,192,224,256,288,320,352,384,416,448},
/// MPEG-1 Layer II {32,48,56,64,80,96,112,128,160,192,224,256,320,384},
/// MPEG-1 Layer III {32,40,48,56,64,80,96,112,128,160,192,224,256,320},
/// MPEG-2/2.5 Layer I {32,48,56,64,80,96,112,128,144,160,176,192,224,256},
/// MPEG-2/2.5 Layers II/III {8,16,24,32,40,48,56,64,80,96,112,128,144,160}.
/// Complexity: O(1).
pub fn mp3_bitrate_kbps(version: Int, layer: Int, index: Int) -> Int {
  if index < 0 || index > 15 {
    return -1;
  }
  if index == 15 {
    return -1;
  }
  if index == 0 {
    return 0;
  }
  if version != 1 && version != 2 && version != 25 {
    return -1;
  }
  if layer < 1 || layer > 3 {
    return -1;
  }
  if version == 1 {
    if layer == 1 {
      return index * 32;
    }
    if layer == 2 {
      if index == 1 { return 32; }
      if index == 2 { return 48; }
      if index == 3 { return 56; }
      if index == 4 { return 64; }
      if index == 5 { return 80; }
      if index == 6 { return 96; }
      if index == 7 { return 112; }
      if index == 8 { return 128; }
      if index == 9 { return 160; }
      if index == 10 { return 192; }
      if index == 11 { return 224; }
      if index == 12 { return 256; }
      if index == 13 { return 320; }
      return 384;
    }
    if index == 1 { return 32; }
    if index == 2 { return 40; }
    if index == 3 { return 48; }
    if index == 4 { return 56; }
    if index == 5 { return 64; }
    if index == 6 { return 80; }
    if index == 7 { return 96; }
    if index == 8 { return 112; }
    if index == 9 { return 128; }
    if index == 10 { return 160; }
    if index == 11 { return 192; }
    if index == 12 { return 224; }
    if index == 13 { return 256; }
    return 320;
  }
  if layer == 1 {
    if index == 1 { return 32; }
    if index == 2 { return 48; }
    if index == 3 { return 56; }
    if index == 4 { return 64; }
    if index == 5 { return 80; }
    if index == 6 { return 96; }
    if index == 7 { return 112; }
    if index == 8 { return 128; }
    if index == 9 { return 144; }
    if index == 10 { return 160; }
    if index == 11 { return 176; }
    if index == 12 { return 192; }
    if index == 13 { return 224; }
    return 256;
  }
  if index == 1 { return 8; }
  if index == 2 { return 16; }
  if index == 3 { return 24; }
  if index == 4 { return 32; }
  if index == 5 { return 40; }
  if index == 6 { return 48; }
  if index == 7 { return 56; }
  if index == 8 { return 64; }
  if index == 9 { return 80; }
  if index == 10 { return 96; }
  if index == 11 { return 112; }
  if index == 12 { return 128; }
  if index == 13 { return 144; }
  return 160;
}

/// Samples per frame for (`version`, `layer`), or 0 for an invalid pair:
/// Layer I -> 384, Layer II -> 1152, Layer III MPEG-1 -> 1152, Layer III
/// MPEG-2/2.5 -> 576. Complexity: O(1).
pub fn mp3_samples_per_frame(version: Int, layer: Int) -> Int {
  if version != 1 && version != 2 && version != 25 {
    return 0;
  }
  if layer == 1 {
    return 384;
  }
  if layer == 2 {
    return 1152;
  }
  if layer == 3 {
    if version == 1 {
      return 1152;
    }
    return 576;
  }
  return 0;
}

/// Frame length in bytes for a normal (non-free-format) header. Returns 0
/// when the length cannot be computed (bitrate <= 0 i.e. free format,
/// sample rate <= 0, unknown version/layer). Formulas: Layer I
/// `(12 * bitrate / sample_rate + padding) * 4`; Layer II and MPEG-1
/// Layer III `144 * bitrate / sample_rate + padding`; MPEG-2/2.5 Layer III
/// `72 * bitrate / sample_rate + padding` (bitrate in bit/s, integer floor
/// division). Complexity: O(1).
pub fn mp3_frame_length(version: Int, layer: Int, bitrate_kbps: Int, sample_rate: Int, padding: Bool) -> Int {
  if bitrate_kbps <= 0 {
    return 0;
  }
  if sample_rate <= 0 {
    return 0;
  }
  if mp3_samples_per_frame(version, layer) == 0 {
    return 0;
  }
  var pad = 0;
  if padding {
    pad = 1;
  }
  if layer == 1 {
    return ((12 * bitrate_kbps * 1000) / sample_rate + pad) * 4;
  }
  if layer == 2 {
    return (144 * bitrate_kbps * 1000) / sample_rate + pad;
  }
  if version == 1 {
    return (144 * bitrate_kbps * 1000) / sample_rate + pad;
  }
  return (72 * bitrate_kbps * 1000) / sample_rate + pad;
}

// --------------------------------------------------
//  Public API: frame header
// --------------------------------------------------

/// Parse and validate the 4-byte frame header at `offset`.
///
/// Checks, in order (first failure wins, all errors carry the byte offset):
/// `offset < 0` or `offset + 4 > data.len()` -> Err("mp3: offset out of
/// range") / Err("mp3: truncated frame header at N"); the 11 sync bits
/// (`B0 == 0xFF` and `B1 >= 0xE0`) -> Err("mp3: bad sync at N"); reserved
/// version bits (01) -> Err("mp3: reserved version at N"); reserved layer
/// bits (00) -> Err("mp3: reserved layer at N"); bitrate index 15 ->
/// Err("mp3: bad bitrate index at N"); bitrate index 0 (free format, whose
/// length needs a sync-distance search) -> Err("mp3: free format at N");
/// sample-rate index 3 -> Err("mp3: bad sample rate index at N").
///
/// On success every field is filled, `frame_length` is computed with
/// mp3_frame_length (always > 0 for an accepted header) and
/// `samples_per_frame` with mp3_samples_per_frame.
/// Complexity: O(1).
pub fn mp3_parse_frame_header(data: &Vec[UInt8], offset: Int) -> Result[Mp3FrameHeader, Str] {
  if offset < 0 {
    return _err_header("mp3: offset out of range");
  }
  if offset + 4 > data.len() {
    return _err_header(_at("mp3: truncated frame header", offset));
  }
  let b0 = _byte(data, offset);
  let b1 = _byte(data, offset + 1);
  let b2 = _byte(data, offset + 2);
  let b3 = _byte(data, offset + 3);
  if b0 != 255 {
    return _err_header(_at("mp3: bad sync", offset));
  }
  if b1 < 224 {
    return _err_header(_at("mp3: bad sync", offset));
  }
  let vbits = (b1 / 8) % 4;
  if vbits == 1 {
    return _err_header(_at("mp3: reserved version", offset));
  }
  var version = 1;
  if vbits == 0 {
    version = 25;
  } elif vbits == 2 {
    version = 2;
  }
  let lbits = (b1 / 2) % 4;
  if lbits == 0 {
    return _err_header(_at("mp3: reserved layer", offset));
  }
  let layer = 4 - lbits;
  var crc = false;
  if b1 % 2 == 0 {
    crc = true;
  }
  let br_index = b2 / 16;
  if br_index == 15 {
    return _err_header(_at("mp3: bad bitrate index", offset));
  }
  if br_index == 0 {
    return _err_header(_at("mp3: free format", offset));
  }
  let sr_index = (b2 / 4) % 4;
  if sr_index == 3 {
    return _err_header(_at("mp3: bad sample rate index", offset));
  }
  var padding = false;
  if (b2 / 2) % 2 == 1 {
    padding = true;
  }
  let bitrate = mp3_bitrate_kbps(version, layer, br_index);
  let rate = mp3_sample_rate(version, sr_index);
  let mode = b3 / 64;
  let mode_ext = (b3 / 16) % 4;
  var copyright = false;
  if (b3 / 8) % 2 == 1 {
    copyright = true;
  }
  var original = false;
  if (b3 / 4) % 2 == 1 {
    original = true;
  }
  let emphasis = b3 % 4;
  let flen = mp3_frame_length(version, layer, bitrate, rate, padding);
  if flen <= 0 {
    return _err_header(_at("mp3: bad frame length", offset));
  }
  let h = Mp3FrameHeader{
    version: version;
    layer: layer;
    bitrate_kbps: bitrate;
    sample_rate: rate;
    padding: padding;
    crc: crc;
    channel_mode: mode;
    mode_extension: mode_ext;
    copyright: copyright;
    original: original;
    emphasis: emphasis;
    frame_length: flen;
    samples_per_frame: mp3_samples_per_frame(version, layer);
  };
  return _ok_header(h);
}

/// Duration of one frame in whole milliseconds: `samples_per_frame * 1000 /
/// sample_rate` (floor division); 0 when the sample rate is <= 0 (only
/// reachable for hand-built headers). Complexity: O(1).
pub fn mp3_frame_duration_ms(header: &Mp3FrameHeader) -> Int {
  if header.sample_rate <= 0 {
    return 0;
  }
  return header.samples_per_frame * 1000 / header.sample_rate;
}

// --------------------------------------------------
//  Public API: buffer scan
// --------------------------------------------------

/// Offset of the first valid frame header at or after `start`.
///
/// The scan walks byte by byte, skipping any byte that does not begin a
/// candidate header: sync mismatch (B0 != 0xFF or B1 < 0xE0), reserved
/// version/layer bits, bitrate index 15 or sample-rate index 3. The first
/// candidate that passes all of those with a zero bitrate index is a
/// free-format frame, reported as Err("mp3: free format at N") because its
/// length cannot be computed from the header alone.
///
/// Errors: Err("mp3: offset out of range") when `start < 0` or
/// `start > data.len()`; Err("mp3: no frame found") when no candidate is
/// found (including `start == data.len()`); Err("mp3: free format at N") as
/// above. Complexity: O(data.len() - start).
pub fn mp3_find_frame(data: &Vec[UInt8], start: Int) -> Result[Int, Str] {
  if start < 0 {
    return _err_int("mp3: offset out of range");
  }
  if start > data.len() {
    return _err_int("mp3: offset out of range");
  }
  var pos = start;
  while pos + 4 <= data.len() {
    let b0 = _byte(data, pos);
    if b0 != 255 {
      pos = pos + 1;
    } else {
      let b1 = _byte(data, pos + 1);
      if b1 < 224 {
        pos = pos + 1;
      } else {
        let vbits = (b1 / 8) % 4;
        let lbits = (b1 / 2) % 4;
        let b2 = _byte(data, pos + 2);
        let br_index = b2 / 16;
        let sr_index = (b2 / 4) % 4;
        if vbits == 1 || lbits == 0 || br_index == 15 || sr_index == 3 {
          pos = pos + 1;
        } elif br_index == 0 {
          return _err_int(_at("mp3: free format", pos));
        } else {
          return _ok_int(pos);
        }
      }
    }
  }
  return _err_int("mp3: no frame found");
}

/// Scan for consecutive complete frames starting at `start`.
///
/// The first frame is located with mp3_find_frame and parsed; a first frame
/// whose declared length does not fit the buffer is Err("mp3: truncated
/// frame at N"). Then every following frame is parsed and counted while its
/// version, layer and sample rate match the first frame (bitrate may vary:
/// VBR is accepted) and the complete frame fits in the buffer. The scan
/// stops, without marking corruption, at the end of the buffer or at a
/// trailing ID3v1 tag (exactly 128 remaining bytes starting with "TAG").
/// Any other trailing bytes - junk, a partial frame, or a frame with a
/// mismatched version/layer/sample rate - stop the scan with
/// `corrupted = true`.
///
/// `duration_ms` is `frame_count * samples_per_frame * 1000 / sample_rate`
/// (floor division). See Mp3Scan for the result fields.
/// Complexity: O(scan length).
pub fn mp3_scan_from(data: &Vec[UInt8], start: Int) -> Result[Mp3Scan, Str] {
  let fr = mp3_find_frame(data, start);
  if !fr.is_ok {
    return _err_scan(fr.error);
  }
  let first = fr.value;
  let hr = mp3_parse_frame_header(data, first);
  if !hr.is_ok {
    return _err_scan(hr.error);
  }
  let base = hr.value;
  if first + base.frame_length > data.len() {
    return _err_scan(_at("mp3: truncated frame", first));
  }
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  offsets.push(first);
  lengths.push(base.frame_length);
  var count = 1;
  var cur = first + base.frame_length;
  var corrupted = false;
  var stop = false;
  while !stop {
    if cur > data.len() {
      corrupted = true;
      stop = true;
    } elif cur == data.len() {
      stop = true;
    } elif cur + 4 > data.len() {
      corrupted = true;
      stop = true;
    } elif data.len() - cur == 128 && _tag3_at(data, cur, 84, 65, 71) {
      stop = true;
    } else {
      let nxt = mp3_parse_frame_header(data, cur);
      if !nxt.is_ok {
        corrupted = true;
        stop = true;
      } else {
        let h = nxt.value;
        if h.version != base.version || h.layer != base.layer || h.sample_rate != base.sample_rate {
          corrupted = true;
          stop = true;
        } elif cur + h.frame_length > data.len() {
          corrupted = true;
          stop = true;
        } else {
          offsets.push(cur);
          lengths.push(h.frame_length);
          count = count + 1;
          cur = cur + h.frame_length;
        }
      }
    }
  }
  let total = count * base.samples_per_frame;
  let dur = total * 1000 / base.sample_rate;
  let scan = Mp3Scan{
    start: start;
    offset: first;
    frame_count: count;
    end_offset: cur;
    trailing_bytes: data.len() - cur;
    version: base.version;
    layer: base.layer;
    sample_rate: base.sample_rate;
    bitrate_kbps: base.bitrate_kbps;
    channel_mode: base.channel_mode;
    samples_per_frame: base.samples_per_frame;
    total_samples: total;
    duration_ms: dur;
    corrupted: corrupted;
    frame_offsets: offsets;
    frame_lengths: lengths;
  };
  return _ok_scan(scan);
}

// --------------------------------------------------
//  Public API: ID3v2
// --------------------------------------------------

/// Parse the 10-byte ID3v2 tag header at offset 0.
///
/// Checks, in order (first failure wins): `data.len() < 10` ->
/// Err("mp3: truncated id3v2 header at 0"); missing "ID3" magic ->
/// Err("mp3: bad id3v2 magic at 0"); major version other than 3 or 4 ->
/// Err("mp3: unsupported id3v2 version at 3"); a size byte with its high
/// bit set (not syncsafe) -> Err("mp3: bad syncsafe size at N") with N the
/// offending byte offset (6..9); declared `total_size` past the buffer ->
/// Err("mp3: id3v2 size overrun at 6").
///
/// The returned total size does not include a v2.4 footer (the footer flag
/// is reported, and per the ID3v2.4 spec the size field excludes it).
/// Trailing bytes after the tag are ignored. Complexity: O(1).
pub fn mp3_id3v2_header(data: &Vec[UInt8]) -> Result[Mp3Id3v2Info, Str] {
  if data.len() < 10 {
    return _err_id3v2("mp3: truncated id3v2 header at 0");
  }
  if !_has_id3v2_magic(data) {
    return _err_id3v2("mp3: bad id3v2 magic at 0");
  }
  let version = _byte(data, 3);
  if version != 3 && version != 4 {
    return _err_id3v2(_at("mp3: unsupported id3v2 version", 3));
  }
  let revision = _byte(data, 4);
  let flags = _byte(data, 5);
  var size = 0;
  var i = 6;
  while i < 10 {
    let b = _byte(data, i);
    if b >= 128 {
      return _err_id3v2(_at("mp3: bad syncsafe size", i));
    }
    size = size * 128 + b;
    i = i + 1;
  }
  let total = 10 + size;
  if total > data.len() {
    return _err_id3v2(_at("mp3: id3v2 size overrun", 6));
  }
  var unsync = false;
  if flags / 128 == 1 {
    unsync = true;
  }
  var ext = false;
  if (flags / 64) % 2 == 1 {
    ext = true;
  }
  var exp = false;
  if (flags / 32) % 2 == 1 {
    exp = true;
  }
  var footer = false;
  if (flags / 16) % 2 == 1 {
    footer = true;
  }
  let info = Mp3Id3v2Info{
    version: version;
    revision: revision;
    flags: flags;
    payload_size: size;
    total_size: total;
    unsynchronised: unsync;
    extended_header: ext;
    experimental: exp;
    footer: footer;
  };
  return _ok_id3v2(info);
}

/// Walk the frames of the ID3v2.3/2.4 tag at offset 0.
///
/// The tag payload (`payload_size` bytes after the header) is first copied
/// into a logical buffer; when the unsynchronisation flag is set every
/// `0xFF 0x00` pair is de-escaped to a single `0xFF` during the copy (the
/// stored frame sizes describe the logical stream, so they still apply).
/// Then frames are read until padding (a zero frame id), a zero frame size,
/// the end of the payload, or a tail shorter than a frame header. v2.3
/// frame sizes are plain big-endian u32; v2.4 frame sizes are syncsafe and
/// a byte with its high bit set is Err("mp3: bad id3v2 frame size at N").
/// A frame whose payload crosses the end of the logical payload is
/// Err("mp3: id3v2 frame overrun at N"); an extended header flag is
/// Err("mp3: unsupported id3v2 extended header at 5").
///
/// Frame-level error offsets N are offsets into the logical (de-
/// unsynchronised) tag payload; header-level errors carry absolute buffer
/// offsets. Every frame is recorded in `ids`/`sizes`; text frames (id
/// starting with 'T') with encoding 0 (latin1) or 3 (UTF-8) also get a text,
/// truncated at the first NUL. See Mp3Id3v2Frames.
/// Complexity: O(payload_size).
pub fn mp3_id3v2_frames(data: &Vec[UInt8]) -> Result[Mp3Id3v2Frames, Str] {
  let hr = mp3_id3v2_header(data);
  if !hr.is_ok {
    return _err_frames(hr.error);
  }
  let info = hr.value;
  if info.extended_header {
    return _err_frames("mp3: unsupported id3v2 extended header at 5");
  }
  var body = Vec[UInt8].new();
  var i = 0;
  while i < info.payload_size {
    let b = _byte(data, 10 + i);
    body.push(b as UInt8);
    if info.unsynchronised && b == 255 && i + 1 < info.payload_size {
      if _byte(data, 11 + i) == 0 {
        i = i + 1;
      }
    }
    i = i + 1;
  }
  var ids = Vec[Str].new();
  var sizes = Vec[Int].new();
  var texts = Vec[Str].new();
  var pos = 0;
  var stop = false;
  while !stop {
    if pos + 10 > body.len() {
      stop = true;
    } elif _all_zero(&body, pos, 4) {
      stop = true;
    } else {
      let fsize = _frame_size(&body, pos, info.version);
      if fsize < 0 {
        return _err_frames(_at("mp3: bad id3v2 frame size", pos));
      }
      if fsize == 0 {
        stop = true;
      } elif pos + 10 + fsize > body.len() {
        return _err_frames(_at("mp3: id3v2 frame overrun", pos));
      } else {
        let fid = _str_until_nul(&body, pos, 4);
        var text = "";
        if _byte(&body, pos) == 84 {
          let enc = _byte(&body, pos + 10);
          if enc == 0 || enc == 3 {
            text = _str_until_nul(&body, pos + 11, fsize - 1);
          }
        }
        ids.push(fid);
        sizes.push(fsize);
        texts.push(text);
        pos = pos + 10 + fsize;
      }
    }
  }
  let frames = Mp3Id3v2Frames{
    ids: ids;
    sizes: sizes;
    texts: texts;
  };
  return _ok_frames(frames);
}

/// Number of recorded frames (== ids.len() == sizes.len() == texts.len()).
/// Complexity: O(1).
pub fn mp3_id3v2_frame_count(frames: &Mp3Id3v2Frames) -> Int {
  return frames.ids.len();
}

/// Frame id at index `i`, or "" when `i` is negative or >=
/// mp3_id3v2_frame_count(frames). Complexity: O(1).
pub fn mp3_id3v2_frame_id(frames: &Mp3Id3v2Frames, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= frames.ids.len() {
    return "";
  }
  let v: Str = frames.ids[i];
  return v;
}

/// Stored payload size of frame `i`, or -1 when `i` is negative or
/// >= mp3_id3v2_frame_count(frames). Complexity: O(1).
pub fn mp3_id3v2_frame_size(frames: &Mp3Id3v2Frames, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= frames.sizes.len() {
    return -1;
  }
  let v: Int = frames.sizes[i];
  return v;
}

/// Decoded text of frame `i` ("" for non-text frames, unsupported text
/// encodings and out-of-range `i`). Complexity: O(1).
pub fn mp3_id3v2_frame_text(frames: &Mp3Id3v2Frames, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= frames.texts.len() {
    return "";
  }
  let v: Str = frames.texts[i];
  return v;
}

/// Index of the first frame whose id equals `id` (byte-wise
/// string.compare.str_compare), or -1 when there is none.
/// Complexity: O(frame_count).
pub fn mp3_id3v2_find(frames: &Mp3Id3v2Frames, id: Str) -> Int {
  var i = 0;
  while i < frames.ids.len() {
    let e: Str = frames.ids[i];
    if compare.str_compare(e, id) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// First text frame whose id equals `id`, or "" when there is none (also ""
/// when the frame exists but carries no decoded text).
/// Complexity: O(frame_count).
pub fn mp3_id3v2_text(frames: &Mp3Id3v2Frames, id: Str) -> Str {
  let i = mp3_id3v2_find(frames, id);
  if i < 0 {
    return "";
  }
  let v: Str = frames.texts[i];
  return v;
}

// Shared body of the convenience readers: Ok(text of `id`, "" when absent);
// structural errors from mp3_id3v2_frames propagate.
fn _text_of(data: &Vec[UInt8], id: Str) -> Result[Str, Str] {
  let r = mp3_id3v2_frames(data);
  if !r.is_ok {
    return _err_str(r.error);
  }
  return _ok_str(mp3_id3v2_text(&r.value, id));
}

/// TIT2 (song title). Ok("") when the tag has no TIT2 frame; structural
/// errors propagate from mp3_id3v2_frames. Complexity: O(payload_size).
pub fn mp3_id3v2_title(data: &Vec[UInt8]) -> Result[Str, Str] {
  return _text_of(data, "TIT2");
}

/// TPE1 (lead artist). Ok("") when the tag has no TPE1 frame; structural
/// errors propagate from mp3_id3v2_frames. Complexity: O(payload_size).
pub fn mp3_id3v2_artist(data: &Vec[UInt8]) -> Result[Str, Str] {
  return _text_of(data, "TPE1");
}

/// TALB (album). Ok("") when the tag has no TALB frame; structural errors
/// propagate from mp3_id3v2_frames. Complexity: O(payload_size).
pub fn mp3_id3v2_album(data: &Vec[UInt8]) -> Result[Str, Str] {
  return _text_of(data, "TALB");
}

/// TRCK (track number, usually "N" or "N/M"). Ok("") when the tag has no
/// TRCK frame; structural errors propagate from mp3_id3v2_frames.
/// Complexity: O(payload_size).
pub fn mp3_id3v2_track(data: &Vec[UInt8]) -> Result[Str, Str] {
  return _text_of(data, "TRCK");
}

/// Year: TYER (ID3v2.3) when present, otherwise TDRC (ID3v2.4); Ok("") when
/// neither exists. Structural errors propagate from mp3_id3v2_frames.
/// Complexity: O(payload_size).
pub fn mp3_id3v2_year(data: &Vec[UInt8]) -> Result[Str, Str] {
  let r = mp3_id3v2_frames(data);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let y = mp3_id3v2_text(&r.value, "TYER");
  if compare.str_compare(y, "") != 0 {
    return _ok_str(y);
  }
  return _ok_str(mp3_id3v2_text(&r.value, "TDRC"));
}

/// TCON (content type / genre string). Ok("") when the tag has no TCON
/// frame; structural errors propagate from mp3_id3v2_frames.
/// Complexity: O(payload_size).
pub fn mp3_id3v2_genre(data: &Vec[UInt8]) -> Result[Str, Str] {
  return _text_of(data, "TCON");
}

// --------------------------------------------------
//  Public API: whole-buffer scan
// --------------------------------------------------

/// Scan a whole buffer for consecutive MPEG audio frames.
///
/// When the buffer starts with a valid ID3v2 tag ("ID3" plus a parseable
/// 10-byte header) the scan starts at `total_size` (the tag is skipped, a
/// v2.4 footer included because the size field excludes it and the footer
/// directly follows the payload); a malformed ID3v2 header propagates its
/// error. Otherwise the scan starts at 0. The scan then behaves exactly
/// like mp3_scan_from, including the clean stop at an ID3v1 tail tag.
/// Complexity: O(data.len()).
pub fn mp3_scan(data: &Vec[UInt8]) -> Result[Mp3Scan, Str] {
  var start = 0;
  if data.len() >= 10 && _has_id3v2_magic(data) {
    let hr = mp3_id3v2_header(data);
    if !hr.is_ok {
      return _err_scan(hr.error);
    }
    start = hr.value.total_size;
  }
  return mp3_scan_from(data, start);
}

// --------------------------------------------------
//  Public API: ID3v1
// --------------------------------------------------

/// True when the buffer ends with a 128-byte ID3v1 tag ("TAG" at
/// `data.len() - 128`). False for buffers shorter than 128 bytes.
/// Complexity: O(1).
pub fn mp3_has_id3v1(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  if n < 128 {
    return false;
  }
  let base = n - 128;
  return _tag3_at(data, base, 84, 65, 71);
}

/// Parse the 128-byte ID3v1 tail tag.
///
/// Requirements: `data.len() >= 128` and "TAG" at `data.len() - 128`.
/// Errors: Err("mp3: empty input") for an empty buffer;
/// Err("mp3: truncated id3v1 tag (128 bytes required)") when shorter than
/// 128 bytes; Err("mp3: no id3v1 tag at N") when the magic is missing, N
/// being `data.len() - 128`. Fields are trimmed at the first NUL. The
/// ID3v1.1 layout is detected by a zero byte at comment offset 28 followed
/// by a nonzero track byte; otherwise the whole 30-byte comment is used and
/// `has_track` is false. Complexity: O(1).
pub fn mp3_id3v1(data: &Vec[UInt8]) -> Result[Mp3Id3v1, Str] {
  let n = data.len();
  if n == 0 {
    return _err_v1("mp3: empty input");
  }
  if n < 128 {
    return _err_v1("mp3: truncated id3v1 tag (128 bytes required)");
  }
  let base = n - 128;
  if !_tag3_at(data, base, 84, 65, 71) {
    return _err_v1(_at("mp3: no id3v1 tag", base));
  }
  let title = _str_until_nul(data, base + 3, 30);
  let artist = _str_until_nul(data, base + 33, 30);
  let album = _str_until_nul(data, base + 63, 30);
  let year = _str_until_nul(data, base + 93, 4);
  var comment = "";
  var track = 0;
  var has_track = false;
  if _byte(data, base + 125) == 0 && _byte(data, base + 126) != 0 {
    has_track = true;
    track = _byte(data, base + 126);
    comment = _str_until_nul(data, base + 97, 28);
  } else {
    comment = _str_until_nul(data, base + 97, 30);
  }
  let genre = _byte(data, base + 127);
  let tag = Mp3Id3v1{
    title: title;
    artist: artist;
    album: album;
    year: year;
    comment: comment;
    track: track;
    has_track: has_track;
    genre: genre;
  };
  return _ok_v1(tag);
}

/// Canonical ID3v1 genre name for the original Winamp set 0..79, or "" for
/// every other value (including the 255 "none" sentinel and the later
/// 80..147 extensions, which are reported unknown). The full table:
/// 0 Blues, 1 Classic Rock, 2 Country, 3 Dance, 4 Disco, 5 Funk, 6 Grunge,
/// 7 Hip-Hop, 8 Jazz, 9 Metal, 10 New Age, 11 Oldies, 12 Other, 13 Pop,
/// 14 R&B, 15 Rap, 16 Reggae, 17 Rock, 18 Techno, 19 Industrial,
/// 20 Alternative, 21 Ska, 22 Death Metal, 23 Pranks, 24 Soundtrack,
/// 25 Euro-Techno, 26 Ambient, 27 Trip-Hop, 28 Vocal, 29 Jazz+Funk,
/// 30 Fusion, 31 Trance, 32 Classical, 33 Instrumental, 34 Acid, 35 House,
/// 36 Game, 37 Sound Clip, 38 Gospel, 39 Noise, 40 AlternRock, 41 Bass,
/// 42 Soul, 43 Punk, 44 Space, 45 Meditative, 46 Instrumental Pop,
/// 47 Instrumental Rock, 48 Ethnic, 49 Gothic, 50 Darkwave,
/// 51 Techno-Industrial, 52 Electronic, 53 Pop-Folk, 54 Eurodance,
/// 55 Dream, 56 Southern Rock, 57 Comedy, 58 Cult, 59 Gangsta, 60 Top 40,
/// 61 Christian Rap, 62 Pop/Funk, 63 Jungle, 64 Native American,
/// 65 Cabaret, 66 New Wave, 67 Psychadelic, 68 Rave, 69 Showtunes,
/// 70 Trailer, 71 Lo-Fi, 72 Tribal, 73 Acid Punk, 74 Acid Jazz, 75 Polka,
/// 76 Retro, 77 Musical, 78 Rock & Roll, 79 Hard Rock.
/// Complexity: O(1).
pub fn mp3_id3v1_genre_name(genre: Int) -> Str {
  if genre == 0 { return "Blues"; }
  if genre == 1 { return "Classic Rock"; }
  if genre == 2 { return "Country"; }
  if genre == 3 { return "Dance"; }
  if genre == 4 { return "Disco"; }
  if genre == 5 { return "Funk"; }
  if genre == 6 { return "Grunge"; }
  if genre == 7 { return "Hip-Hop"; }
  if genre == 8 { return "Jazz"; }
  if genre == 9 { return "Metal"; }
  if genre == 10 { return "New Age"; }
  if genre == 11 { return "Oldies"; }
  if genre == 12 { return "Other"; }
  if genre == 13 { return "Pop"; }
  if genre == 14 { return "R&B"; }
  if genre == 15 { return "Rap"; }
  if genre == 16 { return "Reggae"; }
  if genre == 17 { return "Rock"; }
  if genre == 18 { return "Techno"; }
  if genre == 19 { return "Industrial"; }
  if genre == 20 { return "Alternative"; }
  if genre == 21 { return "Ska"; }
  if genre == 22 { return "Death Metal"; }
  if genre == 23 { return "Pranks"; }
  if genre == 24 { return "Soundtrack"; }
  if genre == 25 { return "Euro-Techno"; }
  if genre == 26 { return "Ambient"; }
  if genre == 27 { return "Trip-Hop"; }
  if genre == 28 { return "Vocal"; }
  if genre == 29 { return "Jazz+Funk"; }
  if genre == 30 { return "Fusion"; }
  if genre == 31 { return "Trance"; }
  if genre == 32 { return "Classical"; }
  if genre == 33 { return "Instrumental"; }
  if genre == 34 { return "Acid"; }
  if genre == 35 { return "House"; }
  if genre == 36 { return "Game"; }
  if genre == 37 { return "Sound Clip"; }
  if genre == 38 { return "Gospel"; }
  if genre == 39 { return "Noise"; }
  if genre == 40 { return "AlternRock"; }
  if genre == 41 { return "Bass"; }
  if genre == 42 { return "Soul"; }
  if genre == 43 { return "Punk"; }
  if genre == 44 { return "Space"; }
  if genre == 45 { return "Meditative"; }
  if genre == 46 { return "Instrumental Pop"; }
  if genre == 47 { return "Instrumental Rock"; }
  if genre == 48 { return "Ethnic"; }
  if genre == 49 { return "Gothic"; }
  if genre == 50 { return "Darkwave"; }
  if genre == 51 { return "Techno-Industrial"; }
  if genre == 52 { return "Electronic"; }
  if genre == 53 { return "Pop-Folk"; }
  if genre == 54 { return "Eurodance"; }
  if genre == 55 { return "Dream"; }
  if genre == 56 { return "Southern Rock"; }
  if genre == 57 { return "Comedy"; }
  if genre == 58 { return "Cult"; }
  if genre == 59 { return "Gangsta"; }
  if genre == 60 { return "Top 40"; }
  if genre == 61 { return "Christian Rap"; }
  if genre == 62 { return "Pop/Funk"; }
  if genre == 63 { return "Jungle"; }
  if genre == 64 { return "Native American"; }
  if genre == 65 { return "Cabaret"; }
  if genre == 66 { return "New Wave"; }
  if genre == 67 { return "Psychadelic"; }
  if genre == 68 { return "Rave"; }
  if genre == 69 { return "Showtunes"; }
  if genre == 70 { return "Trailer"; }
  if genre == 71 { return "Lo-Fi"; }
  if genre == 72 { return "Tribal"; }
  if genre == 73 { return "Acid Punk"; }
  if genre == 74 { return "Acid Jazz"; }
  if genre == 75 { return "Polka"; }
  if genre == 76 { return "Retro"; }
  if genre == 77 { return "Musical"; }
  if genre == 78 { return "Rock & Roll"; }
  if genre == 79 { return "Hard Rock"; }
  return "";
}
