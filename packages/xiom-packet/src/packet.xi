// XIOM -- xiom.packet: length-prefixed packet framing with CRC-32 validation
// Port task: replace the xiom.packet placeholder with a pure-XIOM framing
// codec (no FFI) and prove it green with scripts/port.ps1.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Wire format (one frame): [u32 LE payload length][payload][u32 LE CRC-32].
// packet_parse_all decodes a whole buffer of concatenated frames;
// PacketDecoder is a streaming buffer for chunked input. See SPEC.md for the
// byte-level format table, decoder state rules and the error catalog.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * the CRC-32 state is UInt and uses only `^`, `>>` and `& 1`; the
//     `& 0xFF`-on-bit-31-set and [256]-table forms miscompile in this
//     compiler (see the gzip `_gzip_crc32_impl` precedent).
//   * all u32 little-endian packing/unpacking is arithmetic (modulo and
//     division); no `& 0xFF` masking of values with bit 31 set.
//   * read-only helpers take `&` and the mutating decoder entries take
//     `&mut PacketDecoder`; no function mixes the two borrows on one local
//     (advisory E001).

module xiom.packet

/// Streaming frame decoder state.
/// `buf` holds unconsumed bytes plus (until the next feed) any consumed
/// prefix; `pos` is the index of the first unconsumed byte. Invariant:
/// 0 <= pos <= buf.len(). Fields are implementation details; callers must
/// go through the free functions below.
pub type PacketDecoder = {
  buf: Vec[UInt8];
  pos: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Vec[UInt8]], Str].
fn _ok_frames(v: Vec[Vec[UInt8]]) -> Result[Vec[Vec[UInt8]], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Vec[UInt8]], Str].
fn _err_frames(m: Str) -> Result[Vec[Vec[UInt8]], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte number `k` (0 = least significant) of the non-negative value `v`.
fn _byte_at(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    q = q / 256;
    i = i + 1;
  }
  return (q % 256) as UInt8;
}

// Append the low `size` bytes of the non-negative value `v` in
// LITTLE-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_at(v, i));
    i = i + 1;
  }
}

// Unsigned little-endian u32 at [pos, pos+4). The caller must guarantee
// pos + 4 <= data.len(); every call site checks first.
fn _le32_at(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var k = 3;
  while k >= 0 {
    v = v * 256 + (data[pos + k] as Int);
    k = k - 1;
  }
  return v;
}

// Copy bytes [start, end) into a fresh vector. The caller guarantees
// 0 <= start <= end <= data.len().
fn _copy_range(data: &Vec[UInt8], start: Int, end: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  CRC-32 (IEEE 802.3)
// --------------------------------------------------

/// CRC-32 of `data`: the standard reflected IEEE 802.3 checksum
/// (polynomial 0xEDB88320, init 0xFFFFFFFF, final XOR 0xFFFFFFFF),
/// returned as an unsigned 32-bit value in an Int (0..4294967295).
/// Check value: packet_crc32(b"123456789") == 0xCBF43926 (3421780262).
pub fn packet_crc32(data: &Vec[UInt8]) -> Int {
  return _crc_range(data, 0, data.len());
}

// CRC-32 of bytes [start, end), bitwise and table-free. All state is
// local: module-level [256] tables are mis-materialized by v0.61.3 (see
// the gzip module notes), and UInt avoids the signed-mask bug.
fn _crc_range(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var crc = 0xFFFFFFFF as UInt;
  var i = start;
  while i < end {
    crc = crc ^ (data[i] as UInt);
    var j = 0;
    while j < 8 {
      if (crc & 1) == 1 {
        crc = (crc >> 1) ^ (0xEDB88320 as UInt);
      } else {
        crc = crc >> 1;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  let masked = (crc ^ (0xFFFFFFFF as UInt)) as UInt32;
  return masked as Int;
}

// --------------------------------------------------
//  Framing
// --------------------------------------------------

/// Frame `payload` as [u32 LE length][payload][u32 LE CRC-32(payload)].
/// The length field is the payload length, not the frame length; total
/// frame size is 8 + payload.len(). The documented API bound is a payload
/// of at most 2^31-1 bytes.
pub fn packet_frame(payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = payload.len();
  _push_le(&mut out, n, 4);
  var i = 0;
  while i < n {
    out.push(payload[i]);
    i = i + 1;
  }
  _push_le(&mut out, _crc_range(payload, 0, n), 4);
  return out;
}

/// Decode every complete frame in `data`, in order, validating each payload
/// CRC. Ok holds one payload vector per frame (an empty input yields an
/// empty Ok). Err("packet: truncated frame") when a trailing partial frame
/// is found; Err("packet: crc mismatch") when a complete frame fails CRC
/// (the remaining bytes are then not decoded).
pub fn packet_parse_all(data: &Vec[UInt8]) -> Result[Vec[Vec[UInt8]], Str] {
  var frames = Vec[Vec[UInt8]].new();
  let total = data.len();
  var pos = 0;
  while pos < total {
    let remaining = total - pos;
    if remaining < 4 {
      return _err_frames("packet: truncated frame");
    }
    let len = _le32_at(data, pos);
    let need = len + 8;
    if remaining < need {
      return _err_frames("packet: truncated frame");
    }
    let payload = _copy_range(data, pos + 4, pos + 4 + len);
    let stored = _le32_at(data, pos + 4 + len);
    if packet_crc32(&payload) != stored {
      return _err_frames("packet: crc mismatch");
    }
    frames.push(payload);
    pos = pos + need;
  }
  return _ok_frames(frames);
}

/// True when `data` is exactly one complete, CRC-valid frame with no
/// trailing bytes: shorthand for "packet_parse_all yields exactly one
/// frame". False for empty input, partial frames, corruption and any
/// multi-frame buffer.
pub fn packet_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = packet_parse_all(data);
  if !r.is_ok {
    return false;
  }
  let frames = r.value;
  return frames.len() == 1;
}

// --------------------------------------------------
//  Streaming decoder
// --------------------------------------------------

/// Create an empty decoder (no buffered bytes, nothing consumed).
pub fn packet_decoder_new() -> PacketDecoder {
  return PacketDecoder{ buf: Vec[UInt8].new(); pos: 0; };
}

/// Number of bytes buffered but not yet consumed by packet_decoder_take
/// (never negative).
pub fn packet_decoder_buffered(d: &PacketDecoder) -> Int {
  return d.buf.len() - d.pos;
}

/// Count of structurally complete frames starting at the cursor: frames
/// whose declared length is fully buffered. CRC validity is NOT checked
/// here (packet_decoder_take / packet_parse_all validate it). O(frames).
fn _dec_count(buf: &Vec[UInt8], pos: Int) -> Int {
  var count = 0;
  let total = buf.len();
  var cursor = pos;
  var done = false;
  while !done && total - cursor >= 4 {
    let len = _le32_at(buf, cursor);
    let need = len + 8;
    if total - cursor >= need {
      count = count + 1;
      cursor = cursor + need;
    } else {
      done = true;
    }
  }
  return count;
}

/// Number of complete frames currently buffered. A frame counts once its
/// declared length is fully buffered, even if its CRC later turns out to
/// be corrupt (packet_decoder_take reports that).
pub fn packet_decoder_available(d: &PacketDecoder) -> Int {
  return _dec_count(&d.buf, d.pos);
}

/// Append `chunk` to the decoder buffer. The consumed prefix (bytes before
/// `pos`) is compacted away and `pos` resets to 0, so a decoder never
/// retains bytes that take already returned. O(buffered + chunk).
pub fn packet_decoder_feed(d: &mut PacketDecoder, chunk: &Vec[UInt8]) {
  var fresh = Vec[UInt8].new();
  var i = d.pos;
  while i < d.buf.len() {
    fresh.push(d.buf[i]);
    i = i + 1;
  }
  var j = 0;
  while j < chunk.len() {
    fresh.push(chunk[j]);
    j = j + 1;
  }
  d.buf = fresh;
  d.pos = 0;
}

/// Remove and return the payload of the next complete frame.
/// Err("packet: no complete frame") and nothing consumed when the buffer
/// holds no complete frame; Err("packet: crc mismatch") when the next
/// complete frame fails CRC -- in that case the cursor advances past the
/// corrupt frame, so the decoder resynchronizes on the following bytes.
pub fn packet_decoder_take(d: &mut PacketDecoder) -> Result[Vec[UInt8], Str] {
  if _dec_count(&d.buf, d.pos) == 0 {
    return _err_bytes("packet: no complete frame");
  }
  let len = _le32_at(&d.buf, d.pos);
  let need = len + 8;
  let payload = _copy_range(&d.buf, d.pos + 4, d.pos + 4 + len);
  let stored = _le32_at(&d.buf, d.pos + 4 + len);
  d.pos = d.pos + need;
  if packet_crc32(&payload) != stored {
    return _err_bytes("packet: crc mismatch");
  }
  return _ok_bytes(payload);
}
