// XIOM -- xiom.netstring: DJB netstring framing codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A netstring frame is `<length>:<payload>,`: the payload length written as
// ASCII decimal (at least one digit, no leading zeros except "0" itself), a
// colon, exactly that many raw payload bytes, then a trailing comma. A
// stream is zero or more frames concatenated with nothing between them.
// Payloads are raw bytes with no escaping, so any byte value may appear
// inside a frame. See SPEC.md for the exact grammar, the error catalog and
// the documented limitations (no sockets/IO, no escaping, no nesting).
//
// Layout of one frame (offsets are absolute indices into the source buffer):
//
//   pos                     payload_offset        payload_offset+length
//   |                        |                     |
//   +--------+--------+------+---------------------+--------+
//   | digits |  ':'   |      payload bytes        |  ','   |
//   +--------+--------+------+---------------------+--------+
//   <------------------ parsed as one frame ------------------->
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference or
//     in plain structs.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic or
//     comparisons, so no UInt8 value is ever compared as a signed byte.
//   * the length accumulator checks for Int overflow digit by digit, so a
//     malformed length can never wrap into a plausible small length.
//   * netstring_append and netstring_build are infallible: every Vec length
//     has a decimal form, so there is no build-side error channel.

module xiom.netstring

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[NetstringList, Str].
fn _ok_list(v: NetstringList) -> Result[NetstringList, Str] {
  return Ok(v);
}

// Err(m) for Result[NetstringList, Str].
fn _err_list(m: Str) -> Result[NetstringList, Str] {
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

// Internal payload span of one frame. `offset` is the absolute index of the
// first payload byte and `length` the payload size; the frame as a whole
// ends at offset + length + 1 (the trailing comma). Used only to pass parse
// results between module functions.
type FramePos = {
  offset: Int;
  length: Int;
}

// Ok(v) for Result[FramePos, Str].
fn _ok_frame(v: FramePos) -> Result[FramePos, Str] {
  return Ok(v);
}

// Err(m) for Result[FramePos, Str].
fn _err_frame(m: Str) -> Result[FramePos, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed netstring index: flat parallel storage, one entry per frame in
/// stream order. The payload bytes stay in the source buffer and are located
/// by `payload_offsets[i]` (absolute index of the first payload byte) and
/// `payload_lengths[i]` (payload size in bytes). Fields are implementation
/// details; callers should go through the free functions below.
pub type NetstringList = {
  payload_offsets: Vec[Int];
  payload_lengths: Vec[Int];
}

/// Pull cursor over a complete netstring buffer. A cursor holds no reference
/// to the data, so the same buffer must be passed to every
/// `netstring_cursor_next` call. `pos` is the absolute byte offset of the
/// next frame, `index` the number of frames consumed so far, and
/// `payload_offset`/`payload_length` describe the frame consumed by the last
/// successful call (-1 before the first one). Construct through
/// `netstring_cursor_new`; on error the cursor is left unchanged.
pub type NetstringCursor = {
  pos: Int;
  index: Int;
  payload_offset: Int;
  payload_length: Int;
}

// --------------------------------------------------
//  Internal byte and digit helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int in 0..255. Callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// True when `b` (0..255) is an ASCII decimal digit (0x30..0x39).
fn _is_digit(b: Int) -> Bool {
  return b >= 48 && b <= 57;
}

// Number of decimal digits of n >= 0 (0 -> 1). Internal twin of
// netstring_digit_count, used by _push_dec.
fn _digit_count(n: Int) -> Int {
  var d = 1;
  var t = n;
  while t >= 10 {
    t = t / 10;
    d = d + 1;
  }
  return d;
}

// Append the decimal representation of `n` (n >= 0) to `out`, most
// significant digit first. Arithmetic only: `place` never exceeds the
// highest power of ten in `n`, so it cannot overflow.
fn _push_dec(out: &mut Vec[UInt8], n: Int) {
  let digits = _digit_count(n);
  var place: Int = 1;
  var k = 1;
  while k < digits {
    place = place * 10;
    k = k + 1;
  }
  var rest = n;
  var p = place;
  while p > 0 {
    let d = rest / p;
    rest = rest - d * p;
    out.push((48 + d) as UInt8);
    p = p / 10;
  }
}

// Append the bytes of `v` verbatim.
fn _push_bytes(out: &mut Vec<UInt8>, v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Frame parsing
// --------------------------------------------------

// Parse exactly one frame starting at absolute offset `pos`, where the
// caller guarantees 0 <= pos < data.len(). Returns the payload span.
//
// Check order (first failure wins):
//   1. a frame start that is neither a digit nor ':' -> trailing garbage;
//   2. zero length digits (i.e. ':') -> bad length digits;
//   3. a leading zero with more than one digit -> bad length digits;
//   4. length value above INT64_MAX -> length overflow;
//   5. the digit run reaches the buffer end -> missing colon;
//   6. the byte after the digit run is not ':' -> bad length digits;
//   7. declared length beyond the remaining bytes -> payload too short;
//   8. no comma exactly after the payload -> missing comma.
fn _parse_frame(data: &Vec[UInt8], pos: Int) -> Result[FramePos, Str] {
  let total = data.len();
  let first = _byte(data, pos);
  if first != 58 && !_is_digit(first) {
    return _err_frame("netstring: trailing garbage");
  }
  var n: Int = 0;
  var digits = 0;
  var first_zero = false;
  var overflow = false;
  var p = pos;
  while p < total {
    let b = _byte(data, p);
    if !_is_digit(b) {
      break;
    }
    let d = b - 48;
    if digits == 0 && d == 0 {
      first_zero = true;
    }
    if n > (9223372036854775807 - d) / 10 {
      overflow = true;
    } else {
      n = n * 10 + d;
    }
    digits = digits + 1;
    p = p + 1;
  }
  if digits == 0 {
    return _err_frame("netstring: bad length digits");
  }
  if first_zero && digits > 1 {
    return _err_frame("netstring: bad length digits");
  }
  if overflow {
    return _err_frame("netstring: length overflow");
  }
  if p >= total {
    return _err_frame("netstring: missing colon");
  }
  if _byte(data, p) != 58 {
    return _err_frame("netstring: bad length digits");
  }
  let start = p + 1;
  if n > total - start {
    return _err_frame("netstring: payload too short");
  }
  let comma_at = start + n;
  if comma_at >= total {
    return _err_frame("netstring: missing comma");
  }
  if _byte(data, comma_at) != 44 {
    return _err_frame("netstring: missing comma");
  }
  return _ok_frame(FramePos{ offset: start; length: n; });
}

// --------------------------------------------------
//  Parsing and access
// --------------------------------------------------

/// Parse a complete netstring stream into a flat index of payload spans.
///
/// Frames are walked from offset 0 until the buffer ends, so a truncated or
/// malformed tail is an error, never a silent stop. An empty buffer yields
/// Ok with zero frames. On Err no partial list is returned; the message is
/// one of the six parse-catalog strings in SPEC.md.
/// Complexity: O(data.len()).
pub fn netstring_parse(data: &Vec[UInt8]) -> Result[NetstringList, Str] {
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  let total = data.len();
  var pos = 0;
  while pos < total {
    let fr = _parse_frame(data, pos);
    if !fr.is_ok {
      return _err_list(fr.error);
    }
    let f: FramePos = fr.value;
    offsets.push(f.offset);
    lengths.push(f.length);
    pos = f.offset + f.length + 1;
  }
  return _ok_list(NetstringList{ payload_offsets: offsets; payload_lengths: lengths; });
}

/// Number of frames in `l`.
/// Complexity: O(1).
pub fn netstring_count(l: &NetstringList) -> Int {
  return l.payload_offsets.len();
}

/// Absolute offset of the payload of frame `i`, or -1 when `i` is negative
/// or >= netstring_count(l).
/// Complexity: O(1).
pub fn netstring_offset(l: &NetstringList, i: Int) -> Int {
  if i < 0 || i >= l.payload_offsets.len() {
    return -1;
  }
  let off: Int = l.payload_offsets[i];
  return off;
}

/// Length in bytes of the payload of frame `i`, or -1 when `i` is negative
/// or >= netstring_count(l).
/// Complexity: O(1).
pub fn netstring_length(l: &NetstringList, i: Int) -> Int {
  if i < 0 || i >= l.payload_lengths.len() {
    return -1;
  }
  let len: Int = l.payload_lengths[i];
  return len;
}

/// Copy the payload bytes of frame `i` out of `data`.
///
/// `data` must be the buffer the list was parsed from (or one holding at
/// least the recorded span). Err("netstring: index out of range") when `i`
/// is negative or >= netstring_count(l); Err("netstring: payload out of
/// bounds") when the recorded span does not fit `data`.
/// Complexity: O(payload length).
pub fn netstring_payload(data: &Vec[UInt8], l: &NetstringList, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= l.payload_offsets.len() {
    return _err_bytes("netstring: index out of range");
  }
  let off: Int = l.payload_offsets[i];
  let len: Int = l.payload_lengths[i];
  if off < 0 || len < 0 || off > data.len() || len > data.len() - off {
    return _err_bytes("netstring: payload out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Append one frame for `payload` to `out`: the decimal payload length, ':',
/// the payload bytes verbatim, then ','. Infallible: every payload length
/// has a decimal form. Use netstring_build for a whole stream.
/// Complexity: O(payload length).
pub fn netstring_append(out: &mut Vec[UInt8], payload: &Vec[UInt8]) {
  _push_dec(out, payload.len());
  out.push(58 as UInt8);
  _push_bytes(out, payload);
  out.push(44 as UInt8);
}

/// Build a whole netstring stream from `payloads`: every vector becomes one
/// frame, in order, exactly as if netstring_append had been called for each.
/// Infallible; an empty input yields an empty vector.
/// Complexity: O(total payload bytes).
pub fn netstring_build(payloads: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < payloads.len() {
    let p: Vec[UInt8] = payloads[i];
    netstring_append(&mut out, &p);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Sizing
// --------------------------------------------------

/// Number of decimal digits in the length field of a frame whose payload is
/// `n` bytes: 0 -> 1, 9 -> 1, 10 -> 2, 100 -> 3. Returns -1 when n < 0.
/// Complexity: O(digits).
pub fn netstring_digit_count(n: Int) -> Int {
  if n < 0 {
    return -1;
  }
  return _digit_count(n);
}

/// Total encoded size of one frame with a `payload_len`-byte payload:
/// digit count + 1 (colon) + payload_len + 1 (comma). Returns -1 when
/// payload_len < 0.
/// Complexity: O(digits).
pub fn netstring_frame_size(payload_len: Int) -> Int {
  if payload_len < 0 {
    return -1;
  }
  return _digit_count(payload_len) + 2 + payload_len;
}

// --------------------------------------------------
//  Cursor
// --------------------------------------------------

/// Fresh cursor positioned at the start of a buffer. The cursor stores
/// payload_offset = payload_length = -1 until the first successful
/// netstring_cursor_next.
/// Complexity: O(1).
pub fn netstring_cursor_new() -> NetstringCursor {
  return NetstringCursor{ pos: 0; index: 0; payload_offset: -1; payload_length: -1; };
}

/// Byte offset of the next frame. Equals the buffer length once every frame
/// has been consumed and marks where an incomplete tail starts, so a
/// streaming consumer can retain the tail, append more bytes and resume.
/// Complexity: O(1).
pub fn netstring_cursor_position(c: &NetstringCursor) -> Int {
  return c.pos;
}

/// Number of frames consumed so far.
/// Complexity: O(1).
pub fn netstring_cursor_index(c: &NetstringCursor) -> Int {
  return c.index;
}

/// Absolute offset of the payload of the frame consumed by the last
/// successful netstring_cursor_next, or -1 before the first one.
/// Complexity: O(1).
pub fn netstring_cursor_payload_offset(c: &NetstringCursor) -> Int {
  return c.payload_offset;
}

/// Length in bytes of the payload of the frame consumed by the last
/// successful netstring_cursor_next, or -1 before the first one.
/// Complexity: O(1).
pub fn netstring_cursor_payload_length(c: &NetstringCursor) -> Int {
  return c.payload_length;
}

/// Consume the next frame of `data`.
///
/// Returns Ok(i) with the 0-based index of the frame just consumed (0, 1,
/// 2, ...), or Ok(-1) when the cursor has reached the end of the buffer
/// (including an empty buffer). On Err the message is one of the six
/// parse-catalog strings and the cursor is left completely unchanged, so a
/// truncated tail can be retried after more bytes arrive. A cursor whose
/// `pos` is negative is treated as exhausted.
/// Complexity: O(frame length).
pub fn netstring_cursor_next(data: &Vec[UInt8], c: &mut NetstringCursor) -> Result[Int, Str] {
  let total = data.len();
  if c.pos < 0 || c.pos >= total {
    return _ok_int(-1);
  }
  let fr = _parse_frame(data, c.pos);
  if !fr.is_ok {
    return _err_int(fr.error);
  }
  let f: FramePos = fr.value;
  c.payload_offset = f.offset;
  c.payload_length = f.length;
  c.pos = f.offset + f.length + 1;
  c.index = c.index + 1;
  return _ok_int(c.index - 1);
}
