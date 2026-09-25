// XIOM -- xiom.qoi: QOI image chunk-stream codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. This module implements the container and op-stream
// layers of the Quite OK Image format (QOI) over flat Vec[UInt8] buffers:
//
//   header := "qoif" BE32(width) BE32(height) channels colorspace
//   data   := op+ end_marker
//
// The 14-byte header carries the ASCII magic "qoif", the width and height as
// unsigned 32-bit big-endian integers, a channels byte (3 = RGB, 4 = RGBA)
// and a colorspace byte (0 = sRGB channels with linear alpha, 1 = all
// channels linear). The colorspace is informative only; ops are identical in
// both.
//
// The data section is a stream of ops. Every possible tag byte 0x00..0xFF
// belongs to exactly one of the six ops below, so an unknown op cannot occur
// by construction and there is no "unknown op" error:
//
//   0x00..0x3F  INDEX  6-bit index into the rolling 64-entry index
//   0x40..0x7F  DIFF   2-bit signed dr, dg, db deltas (-2..1)
//   0x80..0xBF  LUMA   6-bit signed dg (-32..31) plus a second byte with
//                      4-bit signed dr-dg and db-dg deltas (-8..7)
//   0xC0..0xFD  RUN    run length 1..62 (stored with a bias of -1)
//   0xFE        RGB    3 explicit bytes r, g, b
//   0xFF        RGBA   4 explicit bytes r, g, b, a
//
// Parsing produces a flat record list -- parallel Vec[Int] fields on one
// QoiStream, no Vec[StructType] -- and NEVER materializes pixels. An op's
// byte span is 1 (INDEX, DIFF, RUN), 2 (LUMA), 4 (RGB) or 5 (RGBA).
//
// The op stream is consumed under the pixel budget width*height implied by
// the header: ops are read until the budget is exactly filled (a RUN that
// would push the count past the budget is "qoi: run overflow"), then exactly
// the 8-byte end marker (7 * 0x00 followed by 0x01) must follow, with no
// trailing bytes ("qoi: trailing data"). SPEC.md documents the reference
// decoder's rolling 64-entry index (zero-initialized; the previous-pixel
// register it is updated from starts at (0, 0, 0, 255)); the record layer
// only keeps ops, so index and pixel values are never evaluated.
//
// qoi_walk is an optional bounded validation pass over the records: it
// re-checks op semantics, counts the produced pixels and returns a documented
// integer checksum of the op kinds. No Float64 appears anywhere in the codec.
//
// qoi_emit rebuilds the header, every op and the end marker from the record
// list alone, so for any buffer qoi_parse accepts, the emitted bytes are
// byte-identical to the input.
//
// See SPEC.md for the byte-level layout, the validation order and the full
// error catalog.

module xiom.qoi

// A parsed QOI container: header fields plus the flat op record list.
//
// The seven record vectors are parallel: entry i is the i-th op of the data
// section in stream order and every vector has exactly op_count entries.
// The header fields are already validated by qoi_parse (dimensions > 0,
// width*height <= qoi_max_pixels(), channels 3 or 4, colorspace 0 or 1).
pub type QoiStream = {
  width: Int;
  height: Int;
  channels: Int;
  colorspace: Int;
  op_kind: Vec[Int];
  op_offset: Vec[Int];
  op_span: Vec[Int];
  op_a: Vec[Int];
  op_b: Vec[Int];
  op_c: Vec[Int];
  op_d: Vec[Int];
}

// Summary returned by qoi_walk: the number of ops, the number of pixels the
// op records produce (equal to width*height on success) and the documented
// integer checksum of the op-kind sequence.
pub type QoiWalk = {
  op_count: Int;
  pixel_count: Int;
  checksum: Int;
}

// Internal mutable scan state. Mirrors QoiStream plus the cursor and the
// running pixel count; _finish copies it into the public type.
type _Parser = {
  width: Int;
  height: Int;
  channels: Int;
  colorspace: Int;
  pos: Int;
  produced: Int;
  op_kind: Vec[Int];
  op_offset: Vec[Int];
  op_span: Vec[Int];
  op_a: Vec[Int];
  op_b: Vec[Int];
  op_c: Vec[Int];
  op_d: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
// return a Result directly, so every fallible public fn returns through one
// of these).
// ---------------------------------------------------------------------------

fn _err_stream(m: Str) -> Result[QoiStream, Str] { return Err(m); }
fn _ok_stream(v: QoiStream) -> Result[QoiStream, Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
fn _err_walk(m: Str) -> Result[QoiWalk, Str] { return Err(m); }
fn _ok_walk(v: QoiWalk) -> Result[QoiWalk, Str] { return Ok(v); }

// ---------------------------------------------------------------------------
// Codec constants
// ---------------------------------------------------------------------------

// Documented total-pixel cap: 400,000,000 pixels, the guard the reference
// implementation applies (at the worst-case 5 bytes per pixel this is about
// 2 GB). It is enforced on the header before width*height is formed, so the
// product cannot overflow the 64-bit Int and any op count stays inside it.
pub fn qoi_max_pixels() -> Int {
  return 400000000;
}

// Fixed header size in bytes: magic 4 + width 4 + height 4 + channels 1 +
// colorspace 1.
pub fn qoi_header_size() -> Int {
  return 14;
}

// End-marker size in bytes: seven 0x00 bytes followed by a single 0x01.
pub fn qoi_end_marker_size() -> Int {
  return 8;
}

// Op kind code for an explicit RGB op, 0xFE.
pub fn qoi_kind_rgb() -> Int {
  return 0;
}

// Op kind code for an explicit RGBA op, 0xFF.
pub fn qoi_kind_rgba() -> Int {
  return 1;
}

// Op kind code for an INDEX op, tag 0x00..0x3F.
pub fn qoi_kind_index() -> Int {
  return 2;
}

// Op kind code for a DIFF op, tag 0x40..0x7F.
pub fn qoi_kind_diff() -> Int {
  return 3;
}

// Op kind code for a LUMA op, tag 0x80..0xBF.
pub fn qoi_kind_luma() -> Int {
  return 4;
}

// Op kind code for a RUN op, tag 0xC0..0xFD.
pub fn qoi_kind_run() -> Int {
  return 5;
}

// Flag bit for ops whose payload carries explicit channel bytes (RGB, RGBA).
pub fn qoi_flag_raw() -> Int {
  return 1;
}

// Flag bit for ops that reference the rolling index (INDEX).
pub fn qoi_flag_index() -> Int {
  return 2;
}

// Flag bit for ops that carry signed deltas (DIFF, LUMA).
pub fn qoi_flag_delta() -> Int {
  return 4;
}

// Flag bit for ops that repeat the previous pixel (RUN).
pub fn qoi_flag_run() -> Int {
  return 8;
}

// ---------------------------------------------------------------------------
// Byte readers and writers
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widening masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Big-endian 32-bit value at `off` (0..4294967295).
fn _be32(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) * 16777216 + _b(data, off + 1) * 65536 + _b(data, off + 2) * 256 + _b(data, off + 3);
}

// True when data[0, 4) is exactly "qoif" (ASCII 113 111 105 102).
fn _magic_is(data: &Vec[UInt8]) -> Bool {
  if (_b(data, 0) != 113) { return false; }
  if (_b(data, 1) != 111) { return false; }
  if (_b(data, 2) != 105) { return false; }
  if (_b(data, 3) != 102) { return false; }
  return true;
}

// True when data[off, off+8) is exactly the end marker: 7 * 0x00, 0x01.
fn _marker_is(data: &Vec[UInt8], off: Int) -> Bool {
  if (_b(data, off) != 0) { return false; }
  if (_b(data, off + 1) != 0) { return false; }
  if (_b(data, off + 2) != 0) { return false; }
  if (_b(data, off + 3) != 0) { return false; }
  if (_b(data, off + 4) != 0) { return false; }
  if (_b(data, off + 5) != 0) { return false; }
  if (_b(data, off + 6) != 0) { return false; }
  if (_b(data, off + 7) != 1) { return false; }
  return true;
}

// Append `v` (0..4294967295) to `out` as four big-endian bytes.
fn _push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append the canonical 14-byte header. Fields must already be validated.
fn _put_header(out: &mut Vec[UInt8], width: Int, height: Int, channels: Int, colorspace: Int) {
  out.push(113 as UInt8); // 'q'
  out.push(111 as UInt8); // 'o'
  out.push(105 as UInt8); // 'i'
  out.push(102 as UInt8); // 'f'
  _push_be32(out, width);
  _push_be32(out, height);
  out.push(channels as UInt8);
  out.push(colorspace as UInt8);
}

// Append the canonical 8-byte end marker: 7 * 0x00, 0x01.
fn _put_end_marker(out: &mut Vec[UInt8]) {
  var i = 0;
  while (i < 7) {
    out.push(0 as UInt8);
    i = i + 1;
  }
  out.push(1 as UInt8);
}

// ---------------------------------------------------------------------------
// Header validation shared by the parser, emitter and walker
// ---------------------------------------------------------------------------

// Dimension error message: "" when 0 < width*height <= qoi_max_pixels(),
// otherwise the parse-facing message. The height guard divides by width, so
// the width*height product is only formed after it is known to fit.
fn _dim_error(width: Int, height: Int) -> Str {
  if (width == 0) { return "qoi: zero width"; }
  if (height == 0) { return "qoi: zero height"; }
  if (width > qoi_max_pixels()) { return "qoi: dimension overflow"; }
  if (height > qoi_max_pixels() / width) { return "qoi: dimension overflow"; }
  return "";
}

// True when a record set's header fields are usable: positive dimensions
// inside the documented cap, channels 3 or 4, colorspace 0 or 1.
fn _header_ok(s: &QoiStream) -> Bool {
  if (s.width < 0) { return false; }
  if (s.height < 0) { return false; }
  let e = _dim_error(s.width, s.height);
  if (e.len() > 0) { return false; }
  if (s.channels != 3 && s.channels != 4) { return false; }
  if (s.colorspace < 0 || s.colorspace > 1) { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Op records
// ---------------------------------------------------------------------------

// Append one op record; all seven vectors always receive exactly one entry,
// so parallel-Vec drift is structurally impossible.
fn _push_op(p: &mut _Parser, kind: Int, off: Int, span: Int, a: Int, b: Int, c: Int, d: Int) {
  p.op_kind.push(kind);
  p.op_offset.push(off);
  p.op_span.push(span);
  p.op_a.push(a);
  p.op_b.push(b);
  p.op_c.push(c);
  p.op_d.push(d);
}

// Scan the op stream under the pixel budget `total`, starting at offset 14
// and filling the parser record vectors. Returns "" on success (the cursor
// then sits on the first end-marker byte) or the documented error message.
fn _scan_ops(p: &mut _Parser, data: &Vec[UInt8], n: Int, total: Int) -> Str {
  while (p.produced < total) {
    if (p.pos >= n) { return "qoi: truncated op"; }
    let off = p.pos;
    let tag = _b(data, off);
    if (tag == 254) {
      // RGB: tag plus r, g, b.
      if (off + 4 > n) { return "qoi: truncated op"; }
      _push_op(p, 0, off, 4, _b(data, off + 1), _b(data, off + 2), _b(data, off + 3), -1);
      p.pos = off + 4;
      p.produced = p.produced + 1;
    } elif (tag == 255) {
      // RGBA: tag plus r, g, b, a.
      if (off + 5 > n) { return "qoi: truncated op"; }
      _push_op(p, 1, off, 5, _b(data, off + 1), _b(data, off + 2), _b(data, off + 3), _b(data, off + 4));
      p.pos = off + 5;
      p.produced = p.produced + 1;
    } elif (tag < 64) {
      // INDEX: the tag's low 6 bits are the index.
      _push_op(p, 2, off, 1, tag, -1, -1, -1);
      p.pos = off + 1;
      p.produced = p.produced + 1;
    } elif (tag < 128) {
      // DIFF: three 2-bit signed deltas biased by 2.
      _push_op(p, 3, off, 1, ((tag / 16) % 4) - 2, ((tag / 4) % 4) - 2, (tag % 4) - 2, -1);
      p.pos = off + 1;
      p.produced = p.produced + 1;
    } elif (tag < 192) {
      // LUMA: 6-bit dg and a second byte with two 4-bit dr-dg / db-dg deltas.
      if (off + 2 > n) { return "qoi: truncated op"; }
      let b2 = _b(data, off + 1);
      _push_op(p, 4, off, 2, (tag % 64) - 32, ((b2 / 16) % 16) - 8, (b2 % 16) - 8, -1);
      p.pos = off + 2;
      p.produced = p.produced + 1;
    } else {
      // RUN: low 6 bits biased by -1 give the run length 1..62.
      let run = (tag % 64) + 1;
      if (p.produced + run > total) { return "qoi: run overflow"; }
      _push_op(p, 5, off, 1, run, -1, -1, -1);
      p.pos = off + 1;
      p.produced = p.produced + run;
    }
  }
  return "";
}

// Move the parser's record vectors into the public stream type, dropping the
// cursor.
fn _finish(p: _Parser) -> QoiStream {
  let width: Int = p.width;
  let height: Int = p.height;
  let channels: Int = p.channels;
  let colorspace: Int = p.colorspace;
  let op_kind: Vec[Int] = p.op_kind;
  let op_offset: Vec[Int] = p.op_offset;
  let op_span: Vec[Int] = p.op_span;
  let op_a: Vec[Int] = p.op_a;
  let op_b: Vec[Int] = p.op_b;
  let op_c: Vec[Int] = p.op_c;
  let op_d: Vec[Int] = p.op_d;
  return QoiStream{
    width: width;
    height: height;
    channels: channels;
    colorspace: colorspace;
    op_kind: op_kind;
    op_offset: op_offset;
    op_span: op_span;
    op_a: op_a;
    op_b: op_b;
    op_c: op_c;
    op_d: op_d;
  };
}

// True when all seven record vectors have identical lengths.
fn _records_parallel(s: &QoiStream) -> Bool {
  let n = s.op_kind.len();
  if (s.op_offset.len() != n) { return false; }
  if (s.op_span.len() != n) { return false; }
  if (s.op_a.len() != n) { return false; }
  if (s.op_b.len() != n) { return false; }
  if (s.op_c.len() != n) { return false; }
  if (s.op_d.len() != n) { return false; }
  return true;
}

// "" when record i is internally consistent with its kind (span and payload
// ranges), else "qoi: invalid record".
fn _record_error(s: &QoiStream, i: Int) -> Str {
  let k: Int = s.op_kind[i];
  let span: Int = s.op_span[i];
  let a: Int = s.op_a[i];
  let b: Int = s.op_b[i];
  let c: Int = s.op_c[i];
  let d: Int = s.op_d[i];
  if (k == 0) {
    if (span != 4) { return "qoi: invalid record"; }
    if (a < 0 || a > 255) { return "qoi: invalid record"; }
    if (b < 0 || b > 255) { return "qoi: invalid record"; }
    if (c < 0 || c > 255) { return "qoi: invalid record"; }
    if (d != -1) { return "qoi: invalid record"; }
    return "";
  } elif (k == 1) {
    if (span != 5) { return "qoi: invalid record"; }
    if (a < 0 || a > 255) { return "qoi: invalid record"; }
    if (b < 0 || b > 255) { return "qoi: invalid record"; }
    if (c < 0 || c > 255) { return "qoi: invalid record"; }
    if (d < 0 || d > 255) { return "qoi: invalid record"; }
    return "";
  } elif (k == 2) {
    if (span != 1) { return "qoi: invalid record"; }
    if (a < 0 || a > 63) { return "qoi: invalid record"; }
    if (b != -1 || c != -1 || d != -1) { return "qoi: invalid record"; }
    return "";
  } elif (k == 3) {
    if (span != 1) { return "qoi: invalid record"; }
    if (a < -2 || a > 1) { return "qoi: invalid record"; }
    if (b < -2 || b > 1) { return "qoi: invalid record"; }
    if (c < -2 || c > 1) { return "qoi: invalid record"; }
    if (d != -1) { return "qoi: invalid record"; }
    return "";
  } elif (k == 4) {
    if (span != 2) { return "qoi: invalid record"; }
    if (a < -32 || a > 31) { return "qoi: invalid record"; }
    if (b < -8 || b > 7) { return "qoi: invalid record"; }
    if (c < -8 || c > 7) { return "qoi: invalid record"; }
    if (d != -1) { return "qoi: invalid record"; }
    return "";
  } elif (k == 5) {
    if (span != 1) { return "qoi: invalid record"; }
    if (a < 1 || a > 62) { return "qoi: invalid record"; }
    if (b != -1 || c != -1 || d != -1) { return "qoi: invalid record"; }
    return "";
  }
  return "qoi: invalid record";
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

/// Parse one complete QOI buffer into header fields plus a flat op record
/// list. Nothing is materialized: only op tags, payloads, spans, absolute
/// offsets and the header are kept.
///
/// Validation order and messages (see SPEC.md for the catalog):
///   1. fewer than 4 bytes -> "qoi: truncated header";
///   2. bytes 0..3 not "qoif" -> "qoi: bad magic";
///   3. fewer than 14 bytes -> "qoi: truncated header";
///   4. width 0 / height 0 -> "qoi: zero width" / "qoi: zero height";
///   5. width*height above qoi_max_pixels() -> "qoi: dimension overflow";
///   6. channels not 3 or 4 -> "qoi: invalid channels";
///   7. colorspace not 0 or 1 -> "qoi: invalid colorspace";
///   8. the op stream must fill width*height pixels exactly; running out of
///      bytes inside an op is "qoi: truncated op" and a RUN past the budget
///      is "qoi: run overflow";
///   9. fewer than 8 bytes after the last op -> "qoi: truncated end marker";
///      bytes that are not 7 * 0x00 + 0x01 -> "qoi: bad end marker"; bytes
///      after a valid marker -> "qoi: trailing data".
/// Complexity: O(input bytes).
pub fn qoi_parse(data: &Vec[UInt8]) -> Result[QoiStream, Str] {
  let n = data.len();
  if (n < 4) { return _err_stream("qoi: truncated header"); }
  if (!_magic_is(data)) { return _err_stream("qoi: bad magic"); }
  if (n < 14) { return _err_stream("qoi: truncated header"); }
  let width = _be32(data, 4);
  let height = _be32(data, 8);
  let e = _dim_error(width, height);
  if (e.len() > 0) { return _err_stream(e); }
  let channels = _b(data, 12);
  if (channels != 3 && channels != 4) { return _err_stream("qoi: invalid channels"); }
  let colorspace = _b(data, 13);
  if (colorspace != 0 && colorspace != 1) { return _err_stream("qoi: invalid colorspace"); }
  let total = width * height;
  var p = _Parser{
    width: width;
    height: height;
    channels: channels;
    colorspace: colorspace;
    pos: 14;
    produced: 0;
    op_kind: Vec[Int].new();
    op_offset: Vec[Int].new();
    op_span: Vec[Int].new();
    op_a: Vec[Int].new();
    op_b: Vec[Int].new();
    op_c: Vec[Int].new();
    op_d: Vec[Int].new();
  };
  let scan = _scan_ops(&mut p, data, n, total);
  if (scan.len() > 0) { return _err_stream(scan); }
  let end = p.pos;
  if (n - end < 8) { return _err_stream("qoi: truncated end marker"); }
  if (!_marker_is(data, end)) { return _err_stream("qoi: bad end marker"); }
  if (n > end + 8) { return _err_stream("qoi: trailing data"); }
  return _ok_stream(_finish(p));
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Width in pixels from the parsed header (1..400000000).
/// Complexity: O(1).
pub fn qoi_width(s: &QoiStream) -> Int {
  return s.width;
}

/// Height in rows from the parsed header (1..400000000).
/// Complexity: O(1).
pub fn qoi_height(s: &QoiStream) -> Int {
  return s.height;
}

/// Header channels byte: 3 = RGB, 4 = RGBA.
/// Complexity: O(1).
pub fn qoi_channels(s: &QoiStream) -> Int {
  return s.channels;
}

/// Header colorspace byte: 0 = sRGB with linear alpha, 1 = all channels
/// linear.
/// Complexity: O(1).
pub fn qoi_colorspace(s: &QoiStream) -> Int {
  return s.colorspace;
}

/// Byte offset of the first op / end marker (always qoi_header_size(), 14).
/// Complexity: O(1).
pub fn qoi_data_offset(s: &QoiStream) -> Int {
  return 14;
}

/// Total decoded pixels implied by the header: width * height.
/// Complexity: O(1).
pub fn qoi_pixel_count(s: &QoiStream) -> Int {
  return s.width * s.height;
}

/// Number of op records (each record covers 1 op; a RUN record may cover up
/// to 62 pixels).
/// Complexity: O(1).
pub fn qoi_op_count(s: &QoiStream) -> Int {
  return s.op_kind.len();
}

/// Kind code of op `i` (qoi_kind_*), or -1 when `i` is outside the record
/// range.
/// Complexity: O(1).
pub fn qoi_op_kind(s: &QoiStream, i: Int) -> Int {
  if (i < 0 || i >= s.op_kind.len()) { return -1; }
  let k: Int = s.op_kind[i];
  return k;
}

/// Class flag of op `i`: qoi_flag_raw() for RGB/RGBA, qoi_flag_index() for
/// INDEX, qoi_flag_delta() for DIFF/LUMA, qoi_flag_run() for RUN; -1 when
/// `i` is outside the record range or the stored kind is not in the catalog.
/// Complexity: O(1).
pub fn qoi_op_flags(s: &QoiStream, i: Int) -> Int {
  let k = qoi_op_kind(s, i);
  if (k == 0 || k == 1) { return qoi_flag_raw(); }
  if (k == 2) { return qoi_flag_index(); }
  if (k == 3 || k == 4) { return qoi_flag_delta(); }
  if (k == 5) { return qoi_flag_run(); }
  return -1;
}

/// Absolute byte offset of op `i`'s tag byte in the buffer passed to
/// qoi_parse, or -1 when `i` is outside the record range.
/// Complexity: O(1).
pub fn qoi_op_offset(s: &QoiStream, i: Int) -> Int {
  if (i < 0 || i >= s.op_offset.len()) { return -1; }
  let v: Int = s.op_offset[i];
  return v;
}

/// Byte span of op `i` including the tag (1, 2, 4 or 5), or -1 when `i` is
/// outside the record range.
/// Complexity: O(1).
pub fn qoi_op_span(s: &QoiStream, i: Int) -> Int {
  if (i < 0 || i >= s.op_span.len()) { return -1; }
  let v: Int = s.op_span[i];
  return v;
}

/// Payload slot a of op `i` (see SPEC.md for the per-kind slot table), or -1
/// when the slot is unused or `i` is outside the record range.
/// Complexity: O(1).
pub fn qoi_op_a(s: &QoiStream, i: Int) -> Int {
  if (i < 0 || i >= s.op_a.len()) { return -1; }
  let v: Int = s.op_a[i];
  return v;
}

/// Payload slot b of op `i`, or -1 when the slot is unused or `i` is outside
/// the record range.
/// Complexity: O(1).
pub fn qoi_op_b(s: &QoiStream, i: Int) -> Int {
  if (i < 0 || i >= s.op_b.len()) { return -1; }
  let v: Int = s.op_b[i];
  return v;
}

/// Payload slot c of op `i`, or -1 when the slot is unused or `i` is outside
/// the record range.
/// Complexity: O(1).
pub fn qoi_op_c(s: &QoiStream, i: Int) -> Int {
  if (i < 0 || i >= s.op_c.len()) { return -1; }
  let v: Int = s.op_c[i];
  return v;
}

/// Payload slot d of op `i`, or -1 when the slot is unused or `i` is outside
/// the record range.
/// Complexity: O(1).
pub fn qoi_op_d(s: &QoiStream, i: Int) -> Int {
  if (i < 0 || i >= s.op_d.len()) { return -1; }
  let v: Int = s.op_d[i];
  return v;
}

/// Run length (1..62) when op `i` is a RUN op, otherwise -1 (including an
/// out-of-range `i`).
/// Complexity: O(1).
pub fn qoi_run_length(s: &QoiStream, i: Int) -> Int {
  if (qoi_op_kind(s, i) != 5) { return -1; }
  if (i < 0 || i >= s.op_a.len()) { return -1; }
  let v: Int = s.op_a[i];
  return v;
}

// ---------------------------------------------------------------------------
// Canonical emitter
// ---------------------------------------------------------------------------

/// Rebuild the complete QOI byte string from the record list alone: header,
/// every op payload re-encoded to its tag form, then the end marker. The
/// record set must be internally consistent with the header dimensions (the
/// seven vectors parallel, payloads in range, ops producing exactly
/// width*height pixels); otherwise Err("qoi: invalid record").
///
/// For any buffer qoi_parse accepts, the result is byte-identical to the
/// input.
/// Complexity: O(emitted bytes).
pub fn qoi_emit(s: &QoiStream) -> Result[Vec[UInt8], Str] {
  if (!_records_parallel(s)) { return _err_bytes("qoi: invalid record"); }
  if (!_header_ok(s)) { return _err_bytes("qoi: invalid record"); }
  let total = s.width * s.height;
  let count = s.op_kind.len();
  var out = Vec[UInt8].new();
  _put_header(&mut out, s.width, s.height, s.channels, s.colorspace);
  var produced = 0;
  var i = 0;
  while (i < count) {
    let e = _record_error(s, i);
    if (e.len() > 0) { return _err_bytes(e); }
    let k: Int = s.op_kind[i];
    let a: Int = s.op_a[i];
    let b: Int = s.op_b[i];
    let c: Int = s.op_c[i];
    let d: Int = s.op_d[i];
    if (k == 0) {
      out.push(254 as UInt8);
      out.push(a as UInt8);
      out.push(b as UInt8);
      out.push(c as UInt8);
      produced = produced + 1;
    } elif (k == 1) {
      out.push(255 as UInt8);
      out.push(a as UInt8);
      out.push(b as UInt8);
      out.push(c as UInt8);
      out.push(d as UInt8);
      produced = produced + 1;
    } elif (k == 2) {
      out.push(a as UInt8);
      produced = produced + 1;
    } elif (k == 3) {
      out.push((64 + (a + 2) * 16 + (b + 2) * 4 + (c + 2)) as UInt8);
      produced = produced + 1;
    } elif (k == 4) {
      out.push((128 + (a + 32)) as UInt8);
      out.push(((b + 8) * 16 + (c + 8)) as UInt8);
      produced = produced + 1;
    } else {
      if (produced + a > total) { return _err_bytes("qoi: invalid record"); }
      out.push((192 + (a - 1)) as UInt8);
      produced = produced + a;
    }
    i = i + 1;
  }
  if (produced != total) { return _err_bytes("qoi: invalid record"); }
  _put_end_marker(&mut out);
  return _ok_bytes(out);
}

// ---------------------------------------------------------------------------
// Bounded walk
// ---------------------------------------------------------------------------

/// Walk the op records without materializing pixels and validate their
/// semantics:
///
///   * every record is structurally consistent (as in qoi_emit);
///   * produced pixels never exceed width*height (a RUN past the budget is
///     "qoi: run overflow", a single-pixel op past it is
///     "qoi: pixel count overflow") and end exactly at width*height
///     ("qoi: pixel count mismatch");
///   * the one canonical-encoder rule stated by the reference
///     implementation: two consecutive INDEX ops must not address the same
///     index ("qoi: repeated index"); consecutive RUN ops are accepted,
///     since the reference decoder accepts them.
///
/// On success it returns the op count, the produced pixel count (equal to
/// width*height) and a checksum of the op-kind sequence:
///
///   checksum = sum over i of (kind_i + 1) * (i + 1), modulo 2^32
///
/// This is a documented integer checksum of op kinds, not a pixel hash and
/// not a cryptographic digest; it uses only Int arithmetic (no Float64).
/// Complexity: O(op count).
pub fn qoi_walk(s: &QoiStream) -> Result[QoiWalk, Str] {
  if (!_records_parallel(s)) { return _err_walk("qoi: invalid record"); }
  if (!_header_ok(s)) { return _err_walk("qoi: invalid record"); }
  let total = s.width * s.height;
  let count = s.op_kind.len();
  var produced = 0;
  var sum = 0;
  var prev_kind = -1;
  var prev_index = -1;
  var i = 0;
  while (i < count) {
    let e = _record_error(s, i);
    if (e.len() > 0) { return _err_walk(e); }
    let k: Int = s.op_kind[i];
    if (k == 2) {
      let idx: Int = s.op_a[i];
      if (prev_kind == 2 && prev_index == idx) { return _err_walk("qoi: repeated index"); }
      prev_index = idx;
    } else {
      prev_index = -1;
    }
    prev_kind = k;
    if (k == 5) {
      let run: Int = s.op_a[i];
      if (produced + run > total) { return _err_walk("qoi: run overflow"); }
      produced = produced + run;
    } else {
      if (produced + 1 > total) { return _err_walk("qoi: pixel count overflow"); }
      produced = produced + 1;
    }
    sum = (sum + (k + 1) * (i + 1)) & 4294967295;
    i = i + 1;
  }
  if (produced != total) { return _err_walk("qoi: pixel count mismatch"); }
  let w = QoiWalk{ op_count: count; pixel_count: produced; checksum: sum; };
  return _ok_walk(w);
}
