// XIOM -- xiom.aiff: AIFF/AIFF-C container header codec (FORM/COMM/SSND, chunk index)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structural parsing and building of AIFF and AIFF-C containers: the
// FORM header (big-endian size, form type "AIFF" or "AIFC"), the COMM chunk
// (channels, sample frames, sample size, 80-bit IEEE extended sample rate),
// the SSND chunk (offset, block size and the sample byte span) and an index
// of every chunk, including optional NAME/AUTH/ANNO/(c) /MARK/INST and
// unknown chunks, preserved as raw spans. Odd-sized chunks are padded to even
// lengths, as the format requires.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * Strs built from file bytes are only created for byte ranges validated
//     as printable ASCII (0x20..0x7E): builder.sb_to_str hands out a
//     NUL-terminated C string, so a raw 0x00 byte would silently truncate
//     and trip its `result.len() == sb.len()` contract at run time.
//   * AiffInfo (parallel Vec fields, never a Vec[StructType]) is constructed
//     inside aiff_parse and crosses function boundaries only by reference or
//     through _ok_info.
//   * Vec[Str] elements are only ever read into typed locals and compared
//     with string.str_compare (BUG 17: `==` on such Str values lowers to a
//     pointer comparison).
// See SPEC.md for the byte layout tables, the 80-bit float encoding and
// rounding rules, the error catalog and the test matrix.

module xiom.aiff

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Format descriptor for aiff_build. `aifc` selects the FORM type: false
/// emits "AIFF" (an 18-byte COMM chunk; the compression fields are ignored),
/// true emits "AIFC" (COMM carries a 4-byte compression type plus a Pascal
/// compression name, defaulting to "not compressed" when empty).
/// `channels` is clamped to 1..65535, `sample_frames` to 0..4294967295,
/// `sample_size` to 1..32 and `ssnd_offset`/`ssnd_block_size` to
/// 0..4294967295. `sample_rate` is encoded with aiff_encode_sample_rate
/// (rates <= 0 encode as 0 Hz).
pub type AiffFormat = {
  aifc: Bool;
  channels: Int;
  sample_frames: Int;
  sample_size: Int;
  sample_rate: Int;
  compression_type: Str;
  compression_name: Str;
  ssnd_offset: Int;
  ssnd_block_size: Int;
}

/// Parsed AIFF/AIFF-C header plus the chunk index.
///
/// COMM fields: `channels`, `sample_frames`, `sample_size` (bits per sample,
/// 1..32) and `sample_rate` (integer Hz, rounded to nearest, ties up);
/// `rate_exact` is true when the stored 80-bit value encodes exactly
/// `sample_rate`. `aifc` is false for a FORM/AIFF file and true for
/// FORM/AIFC. `compression_type` is "NONE" for AIFF and the 4-character
/// AIFF-C type otherwise; `compression_name` is "" for AIFF and the Pascal
/// name for AIFC.
///
/// SSND fields: `ssnd_offset` and `ssnd_block_size` are the stored u32
/// fields; `ssnd_data_offset` is the absolute byte offset of the first
/// sample byte in the parsed buffer; `ssnd_data_size` is the number of
/// sample bytes (chunk payload minus the 8-byte SSND header minus
/// `ssnd_offset`).
///
/// Chunk index: `chunk_ids[i]`, `chunk_offsets[i]` (absolute offset of the
/// chunk's first id byte) and `chunk_sizes[i]` (declared payload size, the
/// padding byte excluded) for every chunk in file order, COMM and SSND
/// included. Unknown and optional chunks are only indexed, never
/// interpreted.
pub type AiffInfo = {
  aifc: Bool;
  channels: Int;
  sample_frames: Int;
  sample_size: Int;
  sample_rate: Int;
  rate_exact: Bool;
  compression_type: Str;
  compression_name: Str;
  ssnd_offset: Int;
  ssnd_block_size: Int;
  ssnd_data_offset: Int;
  ssnd_data_size: Int;
  chunk_ids: Vec[Str];
  chunk_offsets: Vec[Int];
  chunk_sizes: Vec[Int];
}

// Field bundle returned by _decode_comm; internal because aiff_parse copies
// the values into AiffInfo.
type CommFields = {
  channels: Int;
  sample_frames: Int;
  sample_size: Int;
  sample_rate: Int;
  rate_exact: Bool;
  compression_type: Str;
  compression_name: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[AiffInfo, Str].
fn _ok_info(v: AiffInfo) -> Result[AiffInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[AiffInfo, Str].
fn _err_info(m: Str) -> Result[AiffInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[CommFields, Str].
fn _ok_comm(v: CommFields) -> Result[CommFields, Str] {
  return Ok(v);
}

// Err(m) for Result[CommFields, Str].
fn _err_comm(m: Str) -> Result[CommFields, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
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

// Byte number `k` of `v` (0 = least significant). Arithmetic only: `& 0xFF`
// on values with bit 31 set miscompiles in v0.61.3, and this form is exact
// for negative two's-complement values too (needed for the 80-bit mantissa).
fn _byte_of(v: Int, k: Int) -> UInt8 {
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

// Append the low `size` bytes of `v` in BIG-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_byte_of(v, i));
    i = i - 1;
  }
}

// Overwrite the `size` bytes at `pos` with the big-endian image of `v`.
// Callers guarantee 0 <= pos and pos + size <= out.len().
fn _write_be(out: &mut Vec[UInt8], pos: Int, v: Int, size: Int) {
  var i = 0;
  while i < size {
    out[pos + i] = _byte_of(v, size - 1 - i);
    i = i + 1;
  }
}

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u16 at `pos`; callers guarantee the bounds.
fn _be_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
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

// True when the four bytes at `pos` equal the ASCII codes a, b, c, d.
fn _tag_at(data: &Vec[UInt8], pos: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if _byte(data, pos) != a { return false; }
  if _byte(data, pos + 1) != b { return false; }
  if _byte(data, pos + 2) != c { return false; }
  if _byte(data, pos + 3) != d { return false; }
  return true;
}

// True when all four bytes at `pos` are printable ASCII (0x20..0x7E).
fn _printable4(data: &Vec[UInt8], pos: Int) -> Bool {
  var i = 0;
  while i < 4 {
    let b = _byte(data, pos + i);
    if b < 32 { return false; }
    if b > 126 { return false; }
    i = i + 1;
  }
  return true;
}

// True when the `n` bytes at `pos` are all printable ASCII (0x20..0x7E).
fn _printable_range(data: &Vec[UInt8], pos: Int, n: Int) -> Bool {
  var i = 0;
  while i < n {
    let b = _byte(data, pos + i);
    if b < 32 { return false; }
    if b > 126 { return false; }
    i = i + 1;
  }
  return true;
}

// Build a Str from `n` bytes at `pos`. Callers guarantee the bytes are
// printable ASCII, so the NUL-terminated result preserves every byte.
fn _str_range(data: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < n {
    builder.sb_push_byte(&mut sb, _byte(data, pos + i) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Build a 4-character Str from the printable bytes at `pos`.
fn _str4(data: &Vec[UInt8], pos: Int) -> Str {
  return _str_range(data, pos, 4);
}

// True when every byte of `s` is printable ASCII (0x20..0x7E).
fn _printable_str(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 32 { return false; }
    if b > 126 { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  80-bit IEEE extended sample rate
// --------------------------------------------------

// Bit `j` (0 = most significant of the 64-bit mantissa) of the mantissa that
// starts at `pos`. Callers guarantee j in 0..63.
fn _mant_bit(data: &Vec[UInt8], pos: Int, j: Int) -> Int {
  let b = _byte(data, pos + j / 8);
  var k = 7 - j % 8;
  var d = 1;
  var i = 0;
  while i < k {
    d = d * 2;
    i = i + 1;
  }
  return (b / d) % 2;
}

/// Encode an integer Hz sample rate as the 10 big-endian bytes of the 80-bit
/// IEEE 754 extended format: 1 sign bit, 15 exponent bits biased by 16383,
/// then an explicit integer bit at position 63 followed by 63 fraction bits.
///
/// Integer rates up to 2^31-1 (every practical audio rate) are represented
/// exactly. Any rate <= 0 encodes as +0.0 (ten zero bytes). No Float64 is
/// involved: the significand is normalized by arithmetic doubling, and bytes
/// are extracted arithmetically, so negative two's-complement mantissas
/// (rates >= 2^62) are emitted correctly as well.
/// Complexity: O(1).
pub fn aiff_encode_sample_rate(rate: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if rate <= 0 {
    var z = 0;
    while z < 10 {
      out.push(0 as UInt8);
      z = z + 1;
    }
    return out;
  }
  // k = index of the highest set bit of rate (rate < 2^63 for any Int >= 0).
  var k = 0;
  var t = rate;
  while t > 1 {
    t = t / 2;
    k = k + 1;
  }
  // Exponent field: no sign bit (rates are non-negative), bias 16383.
  let exp = 16383 + k;
  // Mantissa = rate * 2^(63 - k); the top bit lands on position 63.
  var mant = rate;
  var j = 0;
  while j < 63 - k {
    mant = mant * 2;
    j = j + 1;
  }
  out.push((exp / 256) as UInt8);
  out.push((exp % 256) as UInt8);
  var i = 7;
  while i >= 0 {
    out.push(_byte_of(mant, i));
    i = i - 1;
  }
  return out;
}

/// Decode a 10-byte 80-bit extended sample rate at `offset` to integer Hz.
///
/// The decoded magnitude is rounded to the nearest integer hertz with ties
/// rounded up (round half away from zero; e.g. 44100.5 -> 44101 and
/// 44099.5 -> 44100). Zero and pseudo-denormal encodings decode to 0. The
/// value is rejected as Err("aiff: bad sample rate") when the exponent field
/// is 0x7FFF (infinity or NaN), when the sign bit is set (negative rates and
/// negative zero), or when the magnitude is >= 2^31 (outside the supported
/// integer range). Err("aiff: offset out of range") when `offset < 0` or
/// `offset + 10 > data.len()`. No Float64 is used: the significand is shifted
/// and rounded with bit arithmetic.
/// Complexity: O(1).
pub fn aiff_decode_sample_rate(data: &Vec[UInt8], offset: Int) -> Result[Int, Str] {
  if offset < 0 {
    return _err_int("aiff: offset out of range");
  }
  if offset + 10 > data.len() {
    return _err_int("aiff: offset out of range");
  }
  let b0 = _byte(data, offset);
  if b0 >= 128 {
    return _err_int("aiff: bad sample rate");
  }
  let e = b0 * 256 + _byte(data, offset + 1);
  if e == 32767 {
    return _err_int("aiff: bad sample rate");
  }
  var m_nonzero = false;
  var i = 0;
  while i < 8 {
    if _byte(data, offset + 2 + i) != 0 {
      m_nonzero = true;
    }
    i = i + 1;
  }
  if e == 0 {
    return _ok_int(0);
  }
  // value = M * 2^(e - 16383 - 63) = M >> (16446 - e), rounded.
  let s = 16446 - e;
  if s <= 0 {
    // e >= 16446: any nonzero normalized mantissa is >= 2^63.
    if m_nonzero {
      return _err_int("aiff: bad sample rate");
    }
    return _ok_int(0);
  }
  if s >= 65 {
    return _ok_int(0);
  }
  if s == 64 {
    if _byte(data, offset + 2) >= 128 {
      return _ok_int(1);
    }
    return _ok_int(0);
  }
  // 1 <= s <= 63: quotient bits, then the first discarded bit as the tie.
  var q: Int = 0;
  var j = 0;
  while j < 64 - s {
    q = q * 2 + _mant_bit(data, offset + 2, j);
    if q > 2147483647 {
      return _err_int("aiff: bad sample rate");
    }
    j = j + 1;
  }
  let round_bit = _mant_bit(data, offset + 2, 64 - s);
  return _ok_int(q + round_bit);
}

// True when the stored 10 bytes at `pos` are exactly the encoding of `rate`.
fn _rate_exact_at(data: &Vec[UInt8], pos: Int, rate: Int) -> Bool {
  let enc = aiff_encode_sample_rate(rate);
  var i = 0;
  while i < 10 {
    if _byte(data, pos + i) != ((enc[i] as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}
// --------------------------------------------------
//  Builder helpers
// --------------------------------------------------

// channels clamped into the u16 field range with a minimum of 1.
fn _clamp_channels(c: Int) -> Int {
  if c < 1 { return 1; }
  if c > 65535 { return 65535; }
  return c;
}

// Unsigned 32-bit field clamp.
fn _clamp_u32(v: Int) -> Int {
  if v < 0 { return 0; }
  if v > 4294967295 { return 4294967295; }
  return v;
}

// sample_size clamped into the AIFF range 1..32.
fn _clamp_sample_size(b: Int) -> Int {
  if b < 1 { return 1; }
  if b > 32 { return 32; }
  return b;
}

// Append a 4-character code: the first four bytes of `code`, right-padded
// with spaces (0x20) when shorter, truncated when longer.
fn _push_code4(p: &mut Vec[UInt8], code: Str) {
  var i = 0;
  while i < 4 {
    var b: Int = 32;
    if i < code.len() {
      b = (string.byte_at(code, i) as Int) & 0xFF;
    }
    p.push(b as UInt8);
    i = i + 1;
  }
}

// Build the COMM payload: 18 bytes for AIFF, plus the 4-byte compression
// type and the even-length Pascal compression name for AIFC.
fn _comm_payload(f: &AiffFormat) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  _push_be(&mut p, _clamp_channels(f.channels), 2);
  _push_be(&mut p, _clamp_u32(f.sample_frames), 4);
  _push_be(&mut p, _clamp_sample_size(f.sample_size), 2);
  let rate_bytes = aiff_encode_sample_rate(f.sample_rate);
  var i = 0;
  while i < 10 {
    p.push(rate_bytes[i]);
    i = i + 1;
  }
  if f.aifc {
    _push_code4(&mut p, f.compression_type);
    var name = f.compression_name;
    if name.len() == 0 {
      name = "not compressed";
    }
    var n = name.len();
    if n > 255 {
      n = 255;
    }
    p.push(n as UInt8);
    var j = 0;
    while j < n {
      p.push(string.byte_at(name, j));
      j = j + 1;
    }
    // A Pascal string occupies an even number of bytes: 1 length byte plus
    // the characters, plus one pad byte when the total would be odd.
    if n % 2 == 0 {
      p.push(0 as UInt8);
    }
  }
  return p;
}

// Append one chunk (id, big-endian payload size, payload, pad byte when the
// payload size is odd) to `out`. Callers guarantee `id` is 4 characters.
fn _push_chunk(out: &mut Vec[UInt8], id: Str, payload: &Vec[UInt8]) {
  builder.sb_push_str(out, id);
  _push_be(out, payload.len(), 4);
  var i = 0;
  while i < payload.len() {
    out.push(payload[i]);
    i = i + 1;
  }
  if payload.len() % 2 == 1 {
    out.push(0 as UInt8);
  }
}

// --------------------------------------------------
//  COMM decoding
// --------------------------------------------------

// Decode and validate one COMM chunk payload at `pos` (chunk header
// included), `size` being the declared payload size. See SPEC.md for the
// rule order and the error catalog.
fn _decode_comm(data: &Vec[UInt8], pos: Int, size: Int, aifc: Bool) -> Result[CommFields, Str] {
  if size < 18 {
    return _err_comm("aiff: bad COMM size");
  }
  let channels = _be_u16(data, pos + 8);
  if channels == 0 {
    return _err_comm("aiff: zero channels");
  }
  let frames = _be_u32(data, pos + 10);
  let ssize = _be_u16(data, pos + 14);
  if ssize < 1 || ssize > 32 {
    return _err_comm("aiff: bad sample size");
  }
  let rr = aiff_decode_sample_rate(data, pos + 16);
  if !rr.is_ok {
    return _err_comm(rr.error);
  }
  if rr.value == 0 {
    return _err_comm("aiff: zero sample rate");
  }
  let exact = _rate_exact_at(data, pos + 16, rr.value);
  var ctype = "NONE";
  var cname = "";
  if aifc {
    // 18 base bytes + 4 type bytes + at least 2 pstring bytes.
    if size < 24 {
      return _err_comm("aiff: bad COMM size");
    }
    if !_printable4(data, pos + 26) {
      return _err_comm("aiff: bad compression type");
    }
    ctype = _str4(data, pos + 26);
    let nlen = _byte(data, pos + 30);
    if nlen == 0 {
      return _err_comm("aiff: bad compression name");
    }
    // Name bytes occupy payload offsets 23..23+nlen-1, pad included.
    var need = 23 + nlen;
    if nlen % 2 == 0 {
      need = need + 1;
    }
    if need > size {
      return _err_comm("aiff: bad compression name");
    }
    if !_printable_range(data, pos + 31, nlen) {
      return _err_comm("aiff: bad compression name");
    }
    cname = _str_range(data, pos + 31, nlen);
  }
  let cf = CommFields{
    channels: channels;
    sample_frames: frames;
    sample_size: ssize;
    sample_rate: rr.value;
    rate_exact: exact;
    compression_type: ctype;
    compression_name: cname;
  };
  return _ok_comm(cf);
}

// --------------------------------------------------
//  Public API: building
// --------------------------------------------------

/// Build a complete AIFF or AIFF-C file: the FORM header, one COMM chunk and
/// one SSND chunk, in that order. The SSND payload is the 8-byte
/// offset/blockSize header, `f.ssnd_offset` zero bytes (the stored offset
/// field counts them, so the sample data starts `ssnd_offset` bytes after the
/// header) and then `samples` verbatim, followed by one pad byte when the
/// payload size is odd. The FORM size field is written last as
/// `file.len() - 8`.
///
/// Clamping: `channels` to 1..65535, `sample_frames` and the SSND fields to
/// 0..4294967295, `sample_size` to 1..32. `sample_rate` is encoded as the
/// 80-bit extended value (rates <= 0 encode as 0 Hz). Compression fields are
/// ignored for AIFF; for AIFC the compression type is padded/truncated to
/// exactly 4 bytes and an empty compression name becomes "not compressed".
/// See aiff_append_chunk for optional chunks.
/// Complexity: O(samples.len() + ssnd_offset).
pub fn aiff_build(samples: &Vec[UInt8], f: &AiffFormat) -> Vec[UInt8] {
  let comm = _comm_payload(f);
  let soff = _clamp_u32(f.ssnd_offset);
  var ssnd = Vec[UInt8].new();
  _push_be(&mut ssnd, soff, 4);
  _push_be(&mut ssnd, _clamp_u32(f.ssnd_block_size), 4);
  var z = 0;
  while z < soff {
    ssnd.push(0 as UInt8);
    z = z + 1;
  }
  var i = 0;
  while i < samples.len() {
    ssnd.push(samples[i]);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "FORM");
  _push_be(&mut out, 0, 4);
  if f.aifc {
    builder.sb_push_str(&mut out, "AIFC");
  } else {
    builder.sb_push_str(&mut out, "AIFF");
  }
  _push_chunk(&mut out, "COMM", &comm);
  _push_chunk(&mut out, "SSND", &ssnd);
  let total = out.len() - 8;
  _write_be(&mut out, 4, total, 4);
  return out;
}

/// Append one chunk to an existing FORM buffer and rewrite the FORM size
/// field to `file.len() - 8`. `id` must be exactly 4 printable ASCII
/// characters; the payload is copied verbatim and followed by one pad byte
/// when its size is odd. This is how optional chunks (NAME, AUTH, ANNO,
/// "(c) ", MARK, INST, COMT, ...) and unknown chunks are added after an
/// aiff_build result.
///
/// Err("aiff: not a FORM container") when `file.len() < 12`;
/// Err("aiff: bad FORM magic") when the buffer does not start with "FORM";
/// Err("aiff: bad chunk id") when `id` is not 4 printable characters. Every
/// check runs before the first byte is appended, so `file` is unchanged on
/// Err. Complexity: O(payload.len()).
pub fn aiff_append_chunk(file: &mut Vec[UInt8], id: Str, payload: &Vec[UInt8]) -> Result[Unit, Str] {
  if file.len() < 12 {
    return _err_unit("aiff: not a FORM container");
  }
  if !_tag_at(file, 0, 70, 79, 82, 77) {
    return _err_unit("aiff: bad FORM magic");
  }
  if id.len() != 4 {
    return _err_unit("aiff: bad chunk id");
  }
  if !_printable_str(id) {
    return _err_unit("aiff: bad chunk id");
  }
  _push_chunk(file, id, payload);
  let total = file.len() - 8;
  _write_be(file, 4, total, 4);
  return _ok_unit();
}

// --------------------------------------------------
//  Public API: parsing
// --------------------------------------------------

/// Parse and validate an AIFF or AIFF-C container header.
///
/// Checks, in order (first failure wins): non-empty buffer; at least the
/// 12-byte FORM header; "FORM" magic; form type "AIFF" or "AIFC"; the FORM
/// size field equal to `data.len() - 8`; then the chunk walk from offset 12:
/// an 8-byte chunk header is present, the 4-byte chunk id is printable
/// ASCII, the declared payload fits in the remaining bytes, an odd payload
/// has its pad byte, and COMM and SSND are each seen at most once (COMM must
/// precede SSND). COMM content is validated while walking: payload size,
/// nonzero channels, sample size 1..32, decodable nonzero 80-bit sample rate
/// and, for AIFC, a printable 4-byte compression type and an even-length
/// non-empty printable Pascal compression name. At the end of the walk both
/// COMM and SSND must have been seen.
///
/// See SPEC.md for the exact error catalog. Success returns the AiffInfo
/// header plus the index of every chunk in file order.
/// Complexity: O(data.len()).
pub fn aiff_parse(data: &Vec[UInt8]) -> Result[AiffInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _err_info("aiff: empty input");
  }
  if n < 12 {
    return _err_info("aiff: truncated form header");
  }
  if !_tag_at(data, 0, 70, 79, 82, 77) {
    return _err_info("aiff: bad FORM magic");
  }
  var aifc = false;
  if _tag_at(data, 8, 65, 73, 70, 70) {
    aifc = false;
  } elif _tag_at(data, 8, 65, 73, 70, 67) {
    aifc = true;
  } else {
    return _err_info("aiff: bad form type");
  }
  if _be_u32(data, 4) != n - 8 {
    return _err_info("aiff: bad FORM size");
  }
  var chunk_ids = Vec[Str].new();
  var chunk_offsets = Vec[Int].new();
  var chunk_sizes = Vec[Int].new();
  var comm_seen = false;
  var ssnd_seen = false;
  var channels = 0;
  var frames = 0;
  var ssize = 0;
  var rate = 0;
  var rate_exact = false;
  var ctype = "NONE";
  var cname = "";
  var ssnd_offset = 0;
  var ssnd_block = 0;
  var ssnd_data_offset = 0;
  var ssnd_data_size = 0;
  var pos = 12;
  while pos < n {
    if n - pos < 8 {
      return _err_info("aiff: truncated chunk header");
    }
    if !_printable4(data, pos) {
      return _err_info("aiff: bad chunk id");
    }
    let cid = _str4(data, pos);
    let csize = _be_u32(data, pos + 4);
    if csize > n - pos - 8 {
      return _err_info("aiff: chunk size overrun");
    }
    if csize % 2 == 1 {
      if n - pos - 8 <= csize {
        return _err_info("aiff: truncated chunk padding");
      }
    }
    if _tag_at(data, pos, 67, 79, 77, 77) {
      if comm_seen {
        return _err_info("aiff: duplicate COMM");
      }
      let cr = _decode_comm(data, pos, csize, aifc);
      if !cr.is_ok {
        return _err_info(cr.error);
      }
      let cf = cr.value;
      channels = cf.channels;
      frames = cf.sample_frames;
      ssize = cf.sample_size;
      rate = cf.sample_rate;
      rate_exact = cf.rate_exact;
      ctype = cf.compression_type;
      cname = cf.compression_name;
      comm_seen = true;
    }
    if _tag_at(data, pos, 83, 83, 78, 68) {
      if ssnd_seen {
        return _err_info("aiff: duplicate SSND");
      }
      if !comm_seen {
        return _err_info("aiff: SSND before COMM");
      }
      if csize < 8 {
        return _err_info("aiff: short SSND");
      }
      let off = _be_u32(data, pos + 8);
      if off > csize - 8 {
        return _err_info("aiff: short SSND");
      }
      ssnd_offset = off;
      ssnd_block = _be_u32(data, pos + 12);
      ssnd_data_offset = pos + 16 + off;
      ssnd_data_size = csize - 8 - off;
      ssnd_seen = true;
    }
    chunk_ids.push(cid);
    chunk_offsets.push(pos);
    chunk_sizes.push(csize);
    pos = pos + 8 + csize;
    if csize % 2 == 1 {
      pos = pos + 1;
    }
  }
  if !comm_seen {
    return _err_info("aiff: missing COMM");
  }
  if !ssnd_seen {
    return _err_info("aiff: missing SSND");
  }
  let info = AiffInfo{
    aifc: aifc;
    channels: channels;
    sample_frames: frames;
    sample_size: ssize;
    sample_rate: rate;
    rate_exact: rate_exact;
    compression_type: ctype;
    compression_name: cname;
    ssnd_offset: ssnd_offset;
    ssnd_block_size: ssnd_block;
    ssnd_data_offset: ssnd_data_offset;
    ssnd_data_size: ssnd_data_size;
    chunk_ids: chunk_ids;
    chunk_offsets: chunk_offsets;
    chunk_sizes: chunk_sizes;
  };
  return _ok_info(info);
}

/// True when aiff_parse succeeds. Complexity: O(data.len()).
pub fn aiff_is_valid(data: &Vec[UInt8]) -> Bool {
  let pr = aiff_parse(data);
  return pr.is_ok;
}

// --------------------------------------------------
//  Public API: chunk index and sample access
// --------------------------------------------------

/// Number of indexed chunks (COMM and SSND included). Complexity: O(1).
pub fn aiff_chunk_count(info: &AiffInfo) -> Int {
  return info.chunk_ids.len();
}

/// 4-character id of chunk `i`; "" when `i` is negative or
/// >= aiff_chunk_count(info). Complexity: O(1).
pub fn aiff_chunk_id(info: &AiffInfo, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= info.chunk_ids.len() {
    return "";
  }
  let id: Str = info.chunk_ids[i];
  return id;
}

/// Absolute byte offset of chunk `i`'s first id byte; -1 when `i` is
/// negative or >= aiff_chunk_count(info). Complexity: O(1).
pub fn aiff_chunk_offset(info: &AiffInfo, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= info.chunk_offsets.len() {
    return -1;
  }
  let off: Int = info.chunk_offsets[i];
  return off;
}

/// Declared payload size of chunk `i` (the padding byte excluded); -1 when
/// `i` is negative or >= aiff_chunk_count(info). Complexity: O(1).
pub fn aiff_chunk_size(info: &AiffInfo, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= info.chunk_sizes.len() {
    return -1;
  }
  let size: Int = info.chunk_sizes[i];
  return size;
}

/// Index of the first chunk whose id equals `id`, or -1 when there is none.
/// The comparison is the canonical byte-wise string.str_compare.
/// Complexity: O(chunk_count).
pub fn aiff_find_chunk(info: &AiffInfo, id: Str) -> Int {
  var i = 0;
  while i < info.chunk_ids.len() {
    let e: Str = info.chunk_ids[i];
    if string.str_compare(e, id) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Copy the raw payload bytes of chunk `i` (the 8-byte header and the pad
/// byte are excluded). Err("aiff: chunk index out of range") when `i` is
/// negative or >= aiff_chunk_count(info); Err("aiff: chunk size overrun")
/// when the indexed span does not fit `data` (e.g. `info` was parsed from a
/// different buffer). Complexity: O(chunk size).
pub fn aiff_chunk_data(data: &Vec[UInt8], info: &AiffInfo, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 {
    return _err_bytes("aiff: chunk index out of range");
  }
  if i >= info.chunk_ids.len() {
    return _err_bytes("aiff: chunk index out of range");
  }
  let off: Int = info.chunk_offsets[i];
  let size: Int = info.chunk_sizes[i];
  if off < 0 {
    return _err_bytes("aiff: chunk size overrun");
  }
  if off + 8 + size > data.len() {
    return _err_bytes("aiff: chunk size overrun");
  }
  var out = Vec[UInt8].new();
  var i2 = 0;
  while i2 < size {
    out.push(data[off + 8 + i2]);
    i2 = i2 + 1;
  }
  return _ok_bytes(out);
}

/// Copy the sample bytes of the SSND chunk: `info.ssnd_data_size` bytes
/// starting at `info.ssnd_data_offset`. Err("aiff: short SSND") when that
/// span does not fit `data` (e.g. `info` was parsed from a different buffer).
/// The SSND offset/block-size fields and the sample size are metadata only;
/// no sample decoding or decompression is performed.
/// Complexity: O(ssnd_data_size).
pub fn aiff_sample_data(data: &Vec<UInt8>, info: &AiffInfo) -> Result[Vec[UInt8], Str] {
  let off = info.ssnd_data_offset;
  let size = info.ssnd_data_size;
  if off < 0 {
    return _err_bytes("aiff: short SSND");
  }
  if size < 0 {
    return _err_bytes("aiff: short SSND");
  }
  if off + size > data.len() {
    return _err_bytes("aiff: short SSND");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Playback duration in whole milliseconds: `sample_frames * 1000 /
/// sample_rate` (floor division). Err("aiff: zero sample rate") when the
/// decoded rate is 0; aiff_parse never returns a zero rate, so this is only
/// reachable for hand-built AiffInfo values. Complexity: O(1).
pub fn aiff_duration_ms(info: &AiffInfo) -> Result[Int, Str] {
  if info.sample_rate <= 0 {
    return _err_int("aiff: zero sample rate");
  }
  return _ok_int(info.sample_frames * 1000 / info.sample_rate);
}
