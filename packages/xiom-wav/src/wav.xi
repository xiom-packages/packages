// XIOM -- xiom.wav: canonical PCM WAV (RIFF) header parsing, building and metadata
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.wav placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the canonical 44-byte PCM (audio format 1) WAV header plus the raw
// data chunk. Bytes are built with Vec[UInt8].push and all multi-byte
// integers are little-endian, written and read arithmetically (division and
// modulo); `& 0xFF` on values with bit 31 set miscompiles in v0.61.3 (same
// bug documented in xiom.msgpack and xiom.convert.base58).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * byte comparisons go through `data[pos] as Int` against small Int
//     constants, never against a UInt8 constant >= 128.
//   * WavFormat crosses function boundaries by reference (&WavFormat) and is
//     constructed only inside the _ok_fmt leaf helper and the builder.
// See SPEC.md for the byte layout table, validation rules, error catalog
// and test plan.

module xiom.wav

use xiom.string.builder;

/// Canonical PCM format descriptor.
/// `channels` is the channel count (>= 1 for files built here);
/// `sample_rate` is in Hz; `bits_per_sample` is one of 8, 16, 24 or 32.
pub type WavFormat = {
  channels: Int;
  sample_rate: Int;
  bits_per_sample: Int;
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(WavFormat) packed from the three header fields.
fn _ok_fmt(channels: Int, sample_rate: Int, bits_per_sample: Int) -> Result[WavFormat, Str] {
  return Ok(WavFormat{
    channels: channels;
    sample_rate: sample_rate;
    bits_per_sample: bits_per_sample;
  });
}

// Err(m) for Result[WavFormat, Str].
fn _err_fmt(m: Str) -> Result[WavFormat, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte number `k` of `v` (0 = least significant). Arithmetic only: `& 0xFF`
// on values with bit 31 set miscompiles in v0.61.3, and this form is exact
// for negative two's-complement values.
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

// Append the low `size` bytes of `v` in LITTLE-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_at(v, i));
    i = i + 1;
  }
}

// Byte at `pos` as an Int; callers guarantee 0 <= pos < data.len().
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return data[pos] as Int;
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

// Unsigned little-endian u16 at `pos`; callers guarantee the bounds.
fn _le_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256;
}

// channels clamped into the u16 field range with a minimum of 1.
fn _clamp_channels(c: Int) -> Int {
  if c < 1 { return 1; }
  if c > 65535 { return 65535; }
  return c;
}

// bits_per_sample clamped into the canonical set {8, 16, 24, 32} by
// rounding up to the next width, capped at 32.
fn _clamp_bits(b: Int) -> Int {
  if b <= 8 { return 8; }
  if b <= 16 { return 16; }
  if b <= 24 { return 24; }
  return 32;
}

// True when the four bytes at `pos` equal the ASCII codes a, b, c, d.
fn _tag_at(data: &Vec[UInt8], pos: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if _byte(data, pos) != a { return false; }
  if _byte(data, pos + 1) != b { return false; }
  if _byte(data, pos + 2) != c { return false; }
  if _byte(data, pos + 3) != d { return false; }
  return true;
}

// Derived block align for a format: channels * bits / 8.
fn _block_align(channels: Int, bits: Int) -> Int {
  return channels * bits / 8;
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// Build a complete canonical PCM WAV file: the fixed 44-byte header
/// ("RIFF" size "WAVE" "fmt " 16 PCM channels rate byte_rate block_align
/// bits "data" size, all multi-byte fields little-endian) followed by the
/// PCM payload bytes verbatim.
///
/// `f.channels` is clamped to 1..65535 and `f.bits_per_sample` is clamped
/// into the canonical set {8, 16, 24, 32} by rounding up to the next width
/// (capped at 32); the clamped values are what the header records.
/// `f.sample_rate` is written as given (as an unsigned 32-bit field).
/// byte_rate = sample_rate * channels * bits / 8 and block_align =
/// channels * bits / 8.
pub fn wav_build_pcm(pcm: &Vec[UInt8], f: &WavFormat) -> Vec[UInt8] {
  let channels = _clamp_channels(f.channels);
  let bits = _clamp_bits(f.bits_per_sample);
  let align = _block_align(channels, bits);
  let byte_rate = f.sample_rate * align;
  let data_size = pcm.len();
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "RIFF");
  _push_le(&mut out, 36 + data_size, 4);
  builder.sb_push_str(&mut out, "WAVE");
  builder.sb_push_str(&mut out, "fmt ");
  _push_le(&mut out, 16, 4);
  _push_le(&mut out, 1, 2);
  _push_le(&mut out, channels, 2);
  _push_le(&mut out, f.sample_rate, 4);
  _push_le(&mut out, byte_rate, 4);
  _push_le(&mut out, align, 2);
  _push_le(&mut out, bits, 2);
  builder.sb_push_str(&mut out, "data");
  _push_le(&mut out, data_size, 4);
  var i = 0;
  while i < pcm.len() {
    out.push(pcm[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// Structural validation shared by the public readers. On success the
// Result carries the header fields, and the 44-byte canonical layout, the
// RIFF size field and the data chunk bounds have all been verified.
// Error strings are the documented catalog in SPEC.md.
fn _parse(data: &Vec[UInt8]) -> Result[WavFormat, Str] {
  if data.len() < 44 {
    return _err_fmt("wav: truncated header");
  }
  if !_tag_at(data, 0, 82, 73, 70, 70) {
    return _err_fmt("wav: bad RIFF magic");
  }
  if !_tag_at(data, 8, 87, 65, 86, 69) {
    return _err_fmt("wav: bad WAVE magic");
  }
  if !_tag_at(data, 12, 102, 109, 116, 32) {
    return _err_fmt("wav: bad fmt chunk");
  }
  if _le_u32(data, 16) != 16 {
    return _err_fmt("wav: bad fmt chunk");
  }
  if _le_u16(data, 20) != 1 {
    return _err_fmt("wav: non-PCM format");
  }
  let bits = _le_u16(data, 34);
  if bits != 8 && bits != 16 && bits != 24 && bits != 32 {
    return _err_fmt("wav: invalid bits per sample");
  }
  if _le_u32(data, 4) != data.len() - 8 {
    return _err_fmt("wav: riff size mismatch");
  }
  if !_tag_at(data, 36, 100, 97, 116, 97) {
    return _err_fmt("wav: bad data chunk");
  }
  let data_size = _le_u32(data, 40);
  if data_size > data.len() - 44 {
    return _err_fmt("wav: data chunk out of range");
  }
  return _ok_fmt(_le_u16(data, 22), _le_u32(data, 24), bits);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse and validate a canonical PCM WAV (RIFF) file header.
/// Checks, in order: the 44-byte canonical minimum (Err("wav: truncated
/// header")); the "RIFF" and "WAVE" magic; the 16-byte "fmt " chunk with
/// audio format PCM = 1; bits_per_sample in {8, 16, 24, 32}; the RIFF
/// chunk size field matching the buffer (len - 8); the "data" chunk tag at
/// offset 36; and the data chunk size fitting inside the buffer.
/// See SPEC.md for the full error catalog. On success the returned
/// WavFormat reflects the stored channels / sample_rate / bits_per_sample
/// values (a structural zero channel count or zero rate is not rejected
/// here; the derived readers report those).
pub fn wav_header_parse(data: &Vec[UInt8]) -> Result[WavFormat, Str] {
  return _parse(data);
}

/// Copy of the data chunk bytes (the PCM payload): data_size bytes starting
/// at offset 44. Validated with the same rules as wav_header_parse first,
/// so any structural error is reported as Err.
pub fn wav_pcm_data(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let pr = _parse(data);
  if !pr.is_ok {
    return _err_bytes(pr.error);
  }
  let size = _le_u32(data, 40);
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    out.push(data[44 + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Number of sample frames: data_size / block_align, where block_align is
/// derived from the header as channels * bits / 8 (the stored field is not
/// trusted). Err("wav: zero block align") when the derived align is 0 (a
/// header with 0 channels); structural errors are reported as Err.
pub fn wav_frame_count(data: &Vec[UInt8]) -> Result[Int, Str] {
  let pr = _parse(data);
  if !pr.is_ok {
    return _err_int(pr.error);
  }
  let align = _block_align(pr.value.channels, pr.value.bits_per_sample);
  if align == 0 {
    return _err_int("wav: zero block align");
  }
  return _ok_int(_le_u32(data, 40) / align);
}

/// Duration in whole milliseconds: frames * 1000 / sample_rate (floor
/// division). Err("wav: zero sample rate") when the stored rate is 0;
/// structural errors are reported as Err.
pub fn wav_duration_ms(data: &Vec[UInt8]) -> Result[Int, Str] {
  let pr = _parse(data);
  if !pr.is_ok {
    return _err_int(pr.error);
  }
  if pr.value.sample_rate == 0 {
    return _err_int("wav: zero sample rate");
  }
  let align = _block_align(pr.value.channels, pr.value.bits_per_sample);
  if align == 0 {
    return _err_int("wav: zero block align");
  }
  let frames = _le_u32(data, 40) / align;
  return _ok_int(frames * 1000 / pr.value.sample_rate);
}

/// True when wav_header_parse succeeds.
pub fn wav_is_valid(data: &Vec[UInt8]) -> Bool {
  let pr = _parse(data);
  return pr.is_ok;
}

/// Unsigned 32-bit little-endian read at `offset` (each byte contributes
/// 0..255), for tests and tools. Err("wav: offset out of range") when
/// `offset` is negative or `offset + 4` exceeds the buffer length.
pub fn wav_le_u32(data: &Vec[UInt8], offset: Int) -> Result[Int, Str] {
  if offset < 0 {
    return _err_int("wav: offset out of range");
  }
  if offset + 4 > data.len() {
    return _err_int("wav: offset out of range");
  }
  return _ok_int(_le_u32(data, offset));
}
