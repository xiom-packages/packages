// XIOM -- xiom.pptx: PowerPoint PresentationML reader/writer
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM port of the xiom.pptx triplet (pptx-read, pptx-write,
// pptx-slide): a minimal PowerPoint PresentationML subset over a
// self-implemented ZIP container.
//
// ZIP container (implemented here, no C, no FFI):
//   * writer: local file headers + central directory + EOCD; entries are
//     STORED (method 0) or DEFLATE (method 8) with CRC-32 (via
//     xiom.compress.gzip.gzip_crc32). DEFLATE payloads come from
//     xiom.compress.deflate (fixed-Huffman producer); inputs above
//     64 KiB fall back to level 0 (stored DEFLATE blocks) so the O(n^2)
//     fixed-Huffman matcher never runs on large parts.
//   * reader: EOCD scan (including archive comments), central-directory
//     walk with strict signature/bounds/name cross-checks against the
//     local headers, STORED entries, and DEFLATE entries. DEFLATE is
//     decoded with xiom.compress.deflate.deflate_decompress_capped first;
//     when that fails, a local RFC 1951 decoder handles STORED and
//     FIXED-Huffman blocks only. DYNAMIC-Huffman blocks (BTYPE 2) are
//     rejected with a documented error -- see SPEC.md.
//
// PresentationML subset (written by this module):
//   [Content_Types].xml, _rels/.rels, ppt/presentation.xml,
//   ppt/_rels/presentation.xml.rels, ppt/slides/slideN.xml with a shape
//   tree of rectangular text boxes (position/size in EMU + one text run).
//   The reader understands exactly that shape of file: sldIdLst order via
//   r:id -> relationship target resolution, sldSz, and p:sp shapes with
//   a:off/a:ext/a:t. Unknown parts and unknown XML are ignored.
//
// Geometry is integer EMU (1 inch = 914400, 1 mm = 36000, 1 pt = 12700);
// there is no Vec[Float64] and no rounding beyond truncation toward zero.
//
// v0.62.2 conventions that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[fn]
//     dispatch, no Vec[StructType] fields (parallel Vecs instead);
//   * Ok/Err construction is confined to the tiny leaf helpers below;
//   * every UInt8 is widened once with `(b as Int) & 0xFF` before entering
//     Int arithmetic or comparisons;
//   * every Vec element read is bound to an explicitly typed local first;
//   * struct-field Vec handles are bound to locals before being passed as
//     `&Vec[UInt8]`;
//   * `&mut` is written explicitly at every call site;
//   * Str output is materialized with xiom.string.builder.sb_to_str only
//     after the bytes were validated as NUL-free; control bytes are
//     rejected (sb_to_str aborts on 0x00, and \0 truncates Str literals);
//   * parallel Vecs are pushed in lockstep and guarded for length drift;
//   * every loop makes progress and every scan is bounded by a cap.

module xiom.pptx

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.convert;
use xiom.compress.deflate;
use xiom.compress.gzip;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

pub const PPTX_EMU_PER_INCH: Int = 914400;
pub const PPTX_EMU_PER_POINT: Int = 12700;
pub const PPTX_EMU_PER_MM: Int = 36000;
pub const PPTX_DEFAULT_WIDTH_EMU: Int = 12192000;
pub const PPTX_DEFAULT_HEIGHT_EMU: Int = 6858000;

const _MAX_SLIDES: Int = 10000;
const _MAX_SHAPES: Int = 100000;
const _MAX_TEXT_BYTES: Int = 1048576;
const _MAX_ZIP_ENTRIES: Int = 4096;
const _MAX_PART_BYTES: Int = 8388608;         // per-part decode cap
const _DEFLATE_FIXED_MAX_INPUT: Int = 65536;  // above this: stored blocks
const _MAX_BLOCKS: Int = 1048576;
const _ZIP_LOCAL_SIG: Int = 0x04034b50;
const _ZIP_CENTRAL_SIG: Int = 0x02014b50;
const _ZIP_EOCD_SIG: Int = 0x06054b50;

// --------------------------------------------------
//  Types (all Vec fields are flat scalar vectors)
// --------------------------------------------------

/// A presentation: integer-EMU canvas size, a slide count and a flattened
/// shape list. Shapes are grouped by slide through `shape_slide` (owners are
/// kept in insertion order); `shape_text_off`/`shape_text_len` are spans
/// into the shared `text` byte pool.
pub type PptxPresentation = {
  width_emu: Int;
  height_emu: Int;
  slide_count: Int;
  shape_slide: Vec[Int];
  shape_kind: Vec[Int];
  shape_x: Vec[Int];
  shape_y: Vec[Int];
  shape_w: Vec[Int];
  shape_h: Vec[Int];
  shape_text_off: Vec[Int];
  shape_text_len: Vec[Int];
  text: Vec[UInt8];
}

/// Writer-side ZIP accumulator: one entry per index; names and payloads are
/// concatenated into byte pools with parallel offsets/lengths.
pub type ZipWriter = {
  names: Vec[UInt8];
  name_off: Vec[Int];
  name_len: Vec[Int];
  method: Vec[Int];
  payload: Vec[UInt8];
  payload_off: Vec[Int];
  payload_len: Vec[Int];
}

/// Read-side ZIP archive: central-directory facts per entry plus a copy of
/// every entry's compressed bytes in one pool.
pub type ZipArchive = {
  names: Vec[UInt8];
  name_off: Vec[Int];
  name_len: Vec[Int];
  method: Vec[Int];
  comp_size: Vec[Int];
  uncomp_size: Vec[Int];
  crc: Vec[Int];
  local_off: Vec[Int];
  comp: Vec[UInt8];
  comp_off: Vec[Int];
}

/// A pool of strings stored as UTF-8 bytes plus parallel offsets/lengths.
type _StrPool = {
  bytes: Vec[UInt8];
  off: Vec[Int];
  len: Vec[Int];
}

/// Relationship table: matching-index pools of relationship ids and targets.
type _RelTable = {
  ids: _StrPool;
  targets: _StrPool;
}

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}
fn _ok_zip(v: ZipArchive) -> Result[ZipArchive, Str] {
  return Ok(v);
}
fn _err_zip(m: Str) -> Result[ZipArchive, Str] {
  return Err(m);
}
fn _ok_pres(v: PptxPresentation) -> Result[PptxPresentation, Str] {
  return Ok(v);
}
fn _err_pres(m: Str) -> Result[PptxPresentation, Str] {
  return Err(m);
}
fn _ok_pool(v: _StrPool) -> Result[_StrPool, Str] {
  return Ok(v);
}
fn _err_pool(m: Str) -> Result[_StrPool, Str] {
  return Err(m);
}
fn _ok_rel(v: _RelTable) -> Result[_RelTable, Str] {
  return Ok(v);
}
fn _err_rel(m: Str) -> Result[_RelTable, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and vector helpers
// --------------------------------------------------

fn _push_u8(out: &mut Vec[UInt8], v: Int) {
  var q = v % 256;
  if q < 0 {
    q = q + 256;
  };
  out.push((q as UInt8));
}

fn _push_u16le(out: &mut Vec[UInt8], v: Int) {
  _push_u8(out, v % 256);
  _push_u8(out, (v / 256) % 256);
}

fn _push_u32le(out: &mut Vec[UInt8], v: Int) {
  _push_u8(out, v % 256);
  _push_u8(out, (v / 256) % 256);
  _push_u8(out, (v / 65536) % 256);
  _push_u8(out, (v / 16777216) % 256);
}

fn _read_u16le(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: UInt8 = data[pos];
  let b1: UInt8 = data[pos + 1];
  let x0: Int = (b0 as Int) & 0xFF;
  let x1: Int = (b1 as Int) & 0xFF;
  return x0 + x1 * 256;
}

fn _read_u32le(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: UInt8 = data[pos];
  let b1: UInt8 = data[pos + 1];
  let b2: UInt8 = data[pos + 2];
  let b3: UInt8 = data[pos + 3];
  let x0: Int = (b0 as Int) & 0xFF;
  let x1: Int = (b1 as Int) & 0xFF;
  let x2: Int = (b2 as Int) & 0xFF;
  let x3: Int = (b3 as Int) & 0xFF;
  return x0 + x1 * 256 + x2 * 65536 + x3 * 16777216;
}

fn _slice(buf: &Vec[UInt8], off: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  let total = buf.len();
  while i < n {
    let p = off + i;
    if p >= 0 && p < total {
      let b: UInt8 = buf[p];
      out.push(b);
    };
    i = i + 1;
  };
  return out;
}

fn _append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  let n = src.len();
  while i < n {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  };
}

fn _append_range(dst: &mut Vec[UInt8], src: &Vec[UInt8], off: Int, n: Int) {
  var i = 0;
  let total = src.len();
  while i < n {
    let p = off + i;
    if p >= 0 && p < total {
      let b: UInt8 = src[p];
      dst.push(b);
    };
    i = i + 1;
  };
}

fn _bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    };
    i = i + 1;
  };
  return true;
}

// --------------------------------------------------
//  Str helpers (byte-based; no Vec[Str] anywhere)
// --------------------------------------------------

fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn _find_from(hay: Str, needle: Str, from: Int) -> Int {
  let hn = string.str_len(hay);
  let nn = string.str_len(needle);
  if nn == 0 {
    if from <= hn {
      return from;
    };
    return -1;
  };
  var i = from;
  if i < 0 {
    i = 0;
  };
  while i + nn <= hn {
    var j = 0;
    var ok = true;
    while j < nn {
      let a: UInt8 = string.byte_at(hay, i + j);
      let b: UInt8 = string.byte_at(needle, j);
      if a != b {
        ok = false;
        j = nn;
      } else {
        j = j + 1;
      };
    };
    if ok {
      return i;
    };
    i = i + 1;
  };
  return -1;
}

fn _starts_at(s: Str, at: Int, lit: Str) -> Bool {
  if at < 0 {
    return false;
  };
  return _find_from(s, lit, at) == at;
}

fn _ends_with(s: Str, suffix: Str) -> Bool {
  let n = string.str_len(s);
  let m = string.str_len(suffix);
  if m > n {
    return false;
  };
  return _find_from(s, suffix, n - m) == n - m;
}

fn _has_dotdot(s: Str) -> Bool {
  return _find_from(s, "..", 0) >= 0;
}

/// Parse a decimal integer attribute. Errors on empty, non-digit, and
/// > 18-digit inputs (no wraparound, no silent truncation).
fn _parse_int_attr(s: Str) -> Result[Int, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_int("pptx: empty integer attribute");
  };
  var i = 0;
  var neg = false;
  let b0: UInt8 = string.byte_at(s, 0);
  let x0: Int = (b0 as Int) & 0xFF;
  if x0 == 45 {
    neg = true;
    i = 1;
  };
  if i >= n {
    return _err_int("pptx: malformed integer attribute");
  };
  var v = 0;
  var digits = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    let x: Int = (b as Int) & 0xFF;
    if x < 48 || x > 57 {
      return _err_int("pptx: malformed integer attribute");
    };
    v = v * 10 + (x - 48);
    digits = digits + 1;
    if digits > 18 {
      return _err_int("pptx: integer attribute out of range");
    };
    i = i + 1;
  };
  if neg {
    v = 0 - v;
  };
  return _ok_int(v);
}

fn _attr_value(tag: Str, name: Str, from: Int) -> Result[Str, Str] {
  let needle = name + "=\"";
  let p = _find_from(tag, needle, from);
  if p < 0 {
    return _err_str("pptx: missing attribute " + name);
  };
  let vs = p + string.str_len(needle);
  let e = _find_from(tag, "\"", vs);
  if e < 0 {
    return _err_str("pptx: unterminated attribute " + name);
  };
  return _ok_str(string.str_slice(tag, vs, e));
}

fn _attr_int(tag: Str, name: Str, from: Int) -> Result[Int, Str] {
  let vr = _attr_value(tag, name, from);
  if !vr.is_ok {
    return _err_int(vr.error);
  };
  let v: Str = vr.value;
  return _parse_int_attr(v);
}

/// Reject NUL and XML-illegal control bytes, then materialize a Str. Used for
/// whole XML parts (writer output and reader input).
fn _part_to_str(b: &Vec[UInt8]) -> Result[Str, Str] {
  var i = 0;
  let n = b.len();
  while i < n {
    let bb: UInt8 = b[i];
    let x: Int = (bb as Int) & 0xFF;
    if x == 0 {
      return _err_str("pptx: part contains NUL byte");
    };
    if x < 32 && x != 9 && x != 10 && x != 13 {
      return _err_str("pptx: part contains control byte");
    };
    i = i + 1;
  };
  return _ok_str(builder.sb_to_str(b));
}

// --------------------------------------------------
//  Geometry (integer EMU; truncation toward zero)
// --------------------------------------------------

pub fn pptx_inches_to_emu(inches: Int) -> Int {
  return inches * PPTX_EMU_PER_INCH;
}

pub fn pptx_emu_to_inches(emu: Int) -> Int {
  return emu / PPTX_EMU_PER_INCH;
}

pub fn pptx_mm_to_emu(mm: Int) -> Int {
  return mm * PPTX_EMU_PER_MM;
}

pub fn pptx_emu_to_mm(emu: Int) -> Int {
  return emu / PPTX_EMU_PER_MM;
}

pub fn pptx_points_to_emu(points: Int) -> Int {
  return points * PPTX_EMU_PER_POINT;
}

pub fn pptx_emu_to_points(emu: Int) -> Int {
  return emu / PPTX_EMU_PER_POINT;
}

// --------------------------------------------------
//  Presentation model
// --------------------------------------------------

/// New presentation with an explicit canvas size. Non-positive dimensions
/// fall back to the 16:9 default (12192000 x 6858000 EMU).
pub fn pptx_presentation_new(width_emu: Int, height_emu: Int) -> PptxPresentation {
  var w = width_emu;
  var h = height_emu;
  if w <= 0 {
    w = PPTX_DEFAULT_WIDTH_EMU;
  };
  if h <= 0 {
    h = PPTX_DEFAULT_HEIGHT_EMU;
  };
  return PptxPresentation{
    width_emu: w;
    height_emu: h;
    slide_count: 0;
    shape_slide: Vec[Int].new();
    shape_kind: Vec[Int].new();
    shape_x: Vec[Int].new();
    shape_y: Vec[Int].new();
    shape_w: Vec[Int].new();
    shape_h: Vec[Int].new();
    shape_text_off: Vec[Int].new();
    shape_text_len: Vec[Int].new();
    text: Vec[UInt8].new();
  };
}

pub fn pptx_presentation_new_default() -> PptxPresentation {
  return pptx_presentation_new(PPTX_DEFAULT_WIDTH_EMU, PPTX_DEFAULT_HEIGHT_EMU);
}

pub fn pptx_presentation_width(pres: &PptxPresentation) -> Int {
  return pres.width_emu;
}

pub fn pptx_presentation_height(pres: &PptxPresentation) -> Int {
  return pres.height_emu;
}

pub fn pptx_slide_count(pres: &PptxPresentation) -> Int {
  return pres.slide_count;
}

pub fn pptx_shape_count(pres: &PptxPresentation) -> Int {
  return pres.shape_kind.len();
}

/// Append a slide; returns its index. Errors when the slide cap is reached.
pub fn pptx_add_slide(pres: &mut PptxPresentation) -> Result[Int, Str] {
  if pres.slide_count >= _MAX_SLIDES {
    return _err_int("pptx: slide limit reached");
  };
  let idx = pres.slide_count;
  pres.slide_count = pres.slide_count + 1;
  return _ok_int(idx);
}

fn _validate_text(s: Str) -> Result[Int, Str] {
  let n = string.str_len(s);
  if n > _MAX_TEXT_BYTES {
    return _err_int("pptx: text exceeds size cap");
  };
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    let x: Int = (b as Int) & 0xFF;
    if x < 32 && x != 9 && x != 10 && x != 13 {
      return _err_int("pptx: text contains control character");
    };
    i = i + 1;
  };
  return _ok_int(n);
}

/// Shared shape append (used by the public add and by the XML reader).
/// Every parallel vector receives exactly one push.
fn _push_shape(pres: &mut PptxPresentation, slide: Int, kind: Int, x: Int, y: Int, w: Int, h: Int, text: Str) -> Result[Int, Str] {
  if pres.shape_kind.len() >= _MAX_SHAPES {
    return _err_int("pptx: shape limit reached");
  };
  let vr = _validate_text(text);
  if !vr.is_ok {
    return _err_int(vr.error);
  };
  let tn: Int = vr.value;
  let off = pres.text.len();
  var i = 0;
  while i < tn {
    let b: UInt8 = string.byte_at(text, i);
    pres.text.push(b);
    i = i + 1;
  };
  pres.shape_slide.push(slide);
  pres.shape_kind.push(kind);
  pres.shape_x.push(x);
  pres.shape_y.push(y);
  pres.shape_w.push(w);
  pres.shape_h.push(h);
  pres.shape_text_off.push(off);
  pres.shape_text_len.push(tn);
  return _ok_int(pres.shape_kind.len() - 1);
}

/// Add a rectangular text box to a slide; returns the global shape index.
pub fn pptx_add_text_box(pres: &mut PptxPresentation, slide: Int, x: Int, y: Int, w: Int, h: Int, text: Str) -> Result[Int, Str] {
  if slide < 0 || slide >= pres.slide_count {
    return _err_int("pptx: slide index out of range");
  };
  if w <= 0 || h <= 0 {
    return _err_int("pptx: shape size must be positive");
  };
  return _push_shape(pres, slide, 0, x, y, w, h, text);
}

fn _shape_index_ok(pres: &PptxPresentation, shape: Int) -> Bool {
  if shape < 0 {
    return false;
  };
  if shape >= pres.shape_kind.len() {
    return false;
  };
  return pres.shape_slide.len() == pres.shape_kind.len() && pres.shape_x.len() == pres.shape_kind.len() && pres.shape_y.len() == pres.shape_kind.len() && pres.shape_w.len() == pres.shape_kind.len() && pres.shape_h.len() == pres.shape_kind.len() && pres.shape_text_off.len() == pres.shape_kind.len() && pres.shape_text_len.len() == pres.shape_kind.len();
}

pub fn pptx_shape_slide(pres: &PptxPresentation, shape: Int) -> Result[Int, Str] {
  if !_shape_index_ok(pres, shape) {
    return _err_int("pptx: shape index out of range");
  };
  let v: Int = pres.shape_slide[shape];
  return _ok_int(v);
}

pub fn pptx_shape_kind(pres: &PptxPresentation, shape: Int) -> Result[Int, Str] {
  if !_shape_index_ok(pres, shape) {
    return _err_int("pptx: shape index out of range");
  };
  let v: Int = pres.shape_kind[shape];
  return _ok_int(v);
}

pub fn pptx_shape_x(pres: &PptxPresentation, shape: Int) -> Result[Int, Str] {
  if !_shape_index_ok(pres, shape) {
    return _err_int("pptx: shape index out of range");
  };
  let v: Int = pres.shape_x[shape];
  return _ok_int(v);
}

pub fn pptx_shape_y(pres: &PptxPresentation, shape: Int) -> Result[Int, Str] {
  if !_shape_index_ok(pres, shape) {
    return _err_int("pptx: shape index out of range");
  };
  let v: Int = pres.shape_y[shape];
  return _ok_int(v);
}

pub fn pptx_shape_width(pres: &PptxPresentation, shape: Int) -> Result[Int, Str] {
  if !_shape_index_ok(pres, shape) {
    return _err_int("pptx: shape index out of range");
  };
  let v: Int = pres.shape_w[shape];
  return _ok_int(v);
}

pub fn pptx_shape_height(pres: &PptxPresentation, shape: Int) -> Result[Int, Str] {
  if !_shape_index_ok(pres, shape) {
    return _err_int("pptx: shape index out of range");
  };
  let v: Int = pres.shape_h[shape];
  return _ok_int(v);
}

pub fn pptx_shape_text(pres: &PptxPresentation, shape: Int) -> Result[Str, Str] {
  if !_shape_index_ok(pres, shape) {
    return _err_str("pptx: shape index out of range");
  };
  let off: Int = pres.shape_text_off[shape];
  let ln: Int = pres.shape_text_len[shape];
  if off < 0 || ln < 0 || off + ln > pres.text.len() {
    return _err_str("pptx: shape text span invalid");
  };
  let pool: Vec[UInt8] = pres.text;
  let raw = _slice(&pool, off, ln);
  return _ok_str(builder.sb_to_str(&raw));
}

pub fn pptx_slide_shape_count(pres: &PptxPresentation, slide: Int) -> Int {
  if slide < 0 || slide >= pres.slide_count {
    return 0;
  };
  var count = 0;
  var i = 0;
  let n = pres.shape_slide.len();
  while i < n {
    let owner: Int = pres.shape_slide[i];
    if owner == slide {
      count = count + 1;
    };
    i = i + 1;
  };
  return count;
}

/// Global shape index of the `nth` shape (0-based) on `slide`.
pub fn pptx_slide_shape(pres: &PptxPresentation, slide: Int, nth: Int) -> Result[Int, Str] {
  if slide < 0 || slide >= pres.slide_count {
    return _err_int("pptx: slide index out of range");
  };
  if nth < 0 {
    return _err_int("pptx: shape index out of range");
  };
  var seen = 0;
  var i = 0;
  let n = pres.shape_slide.len();
  while i < n {
    let owner: Int = pres.shape_slide[i];
    if owner == slide {
      if seen == nth {
        return _ok_int(i);
      };
      seen = seen + 1;
    };
    i = i + 1;
  };
  return _err_int("pptx: shape index out of range");
}

pub fn pptx_shape_kind_name(kind: Int) -> Str {
  if kind == 0 {
    return "text_box";
  };
  return "unknown";
}

fn _pres_consistent(pres: &PptxPresentation) -> Bool {
  let n = pres.shape_kind.len();
  if pres.shape_slide.len() != n || pres.shape_x.len() != n || pres.shape_y.len() != n || pres.shape_w.len() != n || pres.shape_h.len() != n || pres.shape_text_off.len() != n || pres.shape_text_len.len() != n {
    return false;
  };
  if pres.width_emu <= 0 || pres.height_emu <= 0 || pres.slide_count < 0 {
    return false;
  };
  var i = 0;
  while i < n {
    let owner: Int = pres.shape_slide[i];
    let kind: Int = pres.shape_kind[i];
    let off: Int = pres.shape_text_off[i];
    let ln: Int = pres.shape_text_len[i];
    if owner < 0 || owner >= pres.slide_count {
      return false;
    };
    if kind != 0 {
      return false;
    };
    if off < 0 || ln < 0 || off + ln > pres.text.len() {
      return false;
    };
    i = i + 1;
  };
  return true;
}

// --------------------------------------------------
//  XML escape / unescape
// --------------------------------------------------

/// Append `s` escaped for an XML text node. Rejects control bytes other than
/// tab, LF and CR (XML 1.0 cannot represent them, and sb_to_str must not see
/// a NUL).
fn _xml_escape(out: &mut Vec[UInt8], s: Str) -> Result[Int, Str] {
  var i = 0;
  let n = string.str_len(s);
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    let x: Int = (b as Int) & 0xFF;
    if x == 38 {
      builder.sb_push_str(out, "&amp;");
    } else {
      if x == 60 {
        builder.sb_push_str(out, "&lt;");
      } else {
        if x == 62 {
          builder.sb_push_str(out, "&gt;");
        } else {
          if x == 34 {
            builder.sb_push_str(out, "&quot;");
          } else {
            if x == 39 {
              builder.sb_push_str(out, "&apos;");
            } else {
              if x < 32 && x != 9 && x != 10 && x != 13 {
                return _err_int("pptx: text contains control character");
              };
              out.push(b);
            };
          };
        };
      };
    };
    i = i + 1;
  };
  return _ok_int(0);
}

/// Decode the five predefined XML entities. Numeric character references are
/// rejected (this module never writes them; a minimal subset parser should
/// not guess). Control bytes are rejected.
fn _xml_unescape(s: Str) -> Result[Str, Str] {
  var out = builder.sb_new();
  var i = 0;
  let n = string.str_len(s);
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    let x: Int = (b as Int) & 0xFF;
    if x == 38 {
      if _starts_at(s, i, "&amp;") {
        out.push(38u8);
        i = i + 5;
      } else {
        if _starts_at(s, i, "&lt;") {
          out.push(60u8);
          i = i + 4;
        } else {
          if _starts_at(s, i, "&gt;") {
            out.push(62u8);
            i = i + 4;
          } else {
            if _starts_at(s, i, "&quot;") {
              out.push(34u8);
              i = i + 6;
            } else {
              if _starts_at(s, i, "&apos;") {
                out.push(39u8);
                i = i + 6;
              } else {
                return _err_str("pptx: unsupported xml entity");
              };
            };
          };
        };
      };
    } else {
      if x < 32 && x != 9 && x != 10 && x != 13 {
        return _err_str("pptx: control character in xml text");
      };
      out.push(b);
      i = i + 1;
    };
  };
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Str pools and relationship scanning
// --------------------------------------------------

fn _pool_new() -> _StrPool {
  return _StrPool{ bytes: Vec[UInt8].new(); off: Vec[Int].new(); len: Vec[Int].new(); };
}

fn _pool_add(p: &mut _StrPool, s: Str) {
  let off = p.bytes.len();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    p.bytes.push(b);
    i = i + 1;
  };
  p.off.push(off);
  p.len.push(n);
}

fn _pool_len(p: &_StrPool) -> Int {
  return p.len.len();
}

fn _pool_get(p: &_StrPool, i: Int) -> Str {
  if i < 0 || i >= p.len.len() {
    return "";
  };
  let off: Int = p.off[i];
  let n: Int = p.len[i];
  if off < 0 || n < 0 || off + n > p.bytes.len() {
    return "";
  };
  let pool: Vec[UInt8] = p.bytes;
  let raw = _slice(&pool, off, n);
  return builder.sb_to_str(&raw);
}

fn _pool_find_eq(p: &_StrPool, s: Str) -> Int {
  let n = p.len.len();
  let m = string.str_len(s);
  var i = 0;
  while i < n {
    let off: Int = p.off[i];
    let ln: Int = p.len[i];
    if ln == m && off >= 0 && off + ln <= p.bytes.len() {
      var j = 0;
      var ok = true;
      while j < m {
        let a: UInt8 = p.bytes[off + j];
        let b: UInt8 = string.byte_at(s, j);
        if a != b {
          ok = false;
          j = m;
        } else {
          j = j + 1;
        };
      };
      if ok {
        return i;
      };
    };
    i = i + 1;
  };
  return -1;
}

fn _scan_rels(rx: Str) -> Result[_RelTable, Str] {
  var ids = _pool_new();
  var targets = _pool_new();
  var pos = 0;
  var count = 0;
  var scanning = true;
  while scanning {
    let p = _find_from(rx, "<Relationship ", pos);
    if p < 0 {
      scanning = false;
    } else {
      let e = _find_from(rx, "/>", p);
      if e < 0 {
        return _err_rel("pptx: malformed relationship element");
      };
      let tag = string.str_slice(rx, p, e + 2);
      let idr = _attr_value(tag, "Id", 0);
      let tr = _attr_value(tag, "Target", 0);
      let ty = _attr_value(tag, "Type", 0);
      if idr.is_ok && tr.is_ok && ty.is_ok {
        let tyv: Str = ty.value;
        if _ends_with(tyv, "/slide") {
          let idv: Str = idr.value;
          let tv: Str = tr.value;
          _pool_add(&mut ids, idv);
          _pool_add(&mut targets, tv);
        };
      };
      pos = e + 2;
      count = count + 1;
      if count > _MAX_ZIP_ENTRIES {
        return _err_rel("pptx: relationship limit reached");
      };
    };
  };
  return _ok_rel(_RelTable{ ids: ids; targets: targets; });
}

/// Resolve the ordered slide part names: every p:sldId r:id is matched to a
/// relationship of type .../slide, whose target becomes a package path.
fn _collect_slide_parts(px: Str, rx: Str) -> Result[_StrPool, Str] {
  let rr = _scan_rels(rx);
  if !rr.is_ok {
    return _err_pool(rr.error);
  };
  let rel: _RelTable = rr.value;
  let ids: _StrPool = rel.ids;
  let targets: _StrPool = rel.targets;
  var parts = _pool_new();
  var pos = 0;
  var count = 0;
  var scanning = true;
  while scanning {
    let p = _find_from(px, "<p:sldId ", pos);
    if p < 0 {
      scanning = false;
    } else {
      let e = _find_from(px, "/>", p);
      if e < 0 {
        return _err_pool("pptx: malformed sldId element");
      };
      let tag = string.str_slice(px, p, e + 2);
      let ridr = _attr_value(tag, "r:id", 0);
      if !ridr.is_ok {
        return _err_pool("pptx: sldId element missing r:id");
      };
      let rid: Str = ridr.value;
      let ri = _pool_find_eq(&ids, rid);
      if ri < 0 {
        return _err_pool("pptx: sldId references unknown relationship");
      };
      let target: Str = _pool_get(&targets, ri);
      let pr = _part_name_from_target(target);
      if !pr.is_ok {
        return _err_pool(pr.error);
      };
      let pn: Str = pr.value;
      _pool_add(&mut parts, pn);
      pos = e + 2;
      count = count + 1;
      if count > _MAX_SLIDES {
        return _err_pool("pptx: slide limit reached");
      };
    };
  };
  return _ok_pool(parts);
}

fn _part_name_from_target(t: Str) -> Result[Str, Str] {
  let n = string.str_len(t);
  if n == 0 {
    return _err_str("pptx: empty relationship target");
  };
  if _has_dotdot(t) {
    return _err_str("pptx: relationship target escapes package");
  };
  let b0: UInt8 = string.byte_at(t, 0);
  let x0: Int = (b0 as Int) & 0xFF;
  if x0 == 47 {
    return _ok_str(string.str_slice(t, 1, n));
  };
  return _ok_str("ppt/" + t);
}

// --------------------------------------------------
//  PresentationML part builders
// --------------------------------------------------

fn _xml_header(out: &mut Vec[UInt8]) {
  builder.sb_push_str(out, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>");
}

fn _slide_part_name(one_based: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "ppt/slides/slide");
  builder.sb_push_int(&mut sb, one_based);
  builder.sb_push_str(&mut sb, ".xml");
  return builder.sb_to_str(&sb);
}

fn _rid_name(one_based: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "rId");
  builder.sb_push_int(&mut sb, one_based);
  return builder.sb_to_str(&sb);
}

fn _content_types_xml(pres: &PptxPresentation) -> Result[Vec[UInt8], Str] {
  var out = builder.sb_new();
  _xml_header(&mut out);
  builder.sb_push_str(&mut out, "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">");
  builder.sb_push_str(&mut out, "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>");
  builder.sb_push_str(&mut out, "<Default Extension=\"xml\" ContentType=\"application/xml\"/>");
  builder.sb_push_str(&mut out, "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/>");
  var s = 0;
  while s < pres.slide_count {
    builder.sb_push_str(&mut out, "<Override PartName=\"/ppt/slides/slide");
    builder.sb_push_int(&mut out, s + 1);
    builder.sb_push_str(&mut out, ".xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>");
    s = s + 1;
  };
  builder.sb_push_str(&mut out, "</Types>");
  return _ok_bytes(out);
}

fn _root_rels_xml() -> Result[Vec[UInt8], Str] {
  var out = builder.sb_new();
  _xml_header(&mut out);
  builder.sb_push_str(&mut out, "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
  builder.sb_push_str(&mut out, "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/>");
  builder.sb_push_str(&mut out, "</Relationships>");
  return _ok_bytes(out);
}

fn _presentation_xml(pres: &PptxPresentation) -> Result[Vec[UInt8], Str] {
  var out = builder.sb_new();
  _xml_header(&mut out);
  builder.sb_push_str(&mut out, "<p:presentation xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">");
  builder.sb_push_str(&mut out, "<p:sldIdLst>");
  var s = 0;
  while s < pres.slide_count {
    builder.sb_push_str(&mut out, "<p:sldId id=\"");
    builder.sb_push_int(&mut out, 256 + s);
    builder.sb_push_str(&mut out, "\" r:id=\"");
    let rid = _rid_name(s + 1);
    builder.sb_push_str(&mut out, rid);
    builder.sb_push_str(&mut out, "\"/>");
    s = s + 1;
  };
  builder.sb_push_str(&mut out, "</p:sldIdLst><p:sldSz cx=\"");
  builder.sb_push_int(&mut out, pres.width_emu);
  builder.sb_push_str(&mut out, "\" cy=\"");
  builder.sb_push_int(&mut out, pres.height_emu);
  builder.sb_push_str(&mut out, "\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>");
  return _ok_bytes(out);
}

fn _presentation_rels_xml(pres: &PptxPresentation) -> Result[Vec[UInt8], Str] {
  var out = builder.sb_new();
  _xml_header(&mut out);
  builder.sb_push_str(&mut out, "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
  var s = 0;
  while s < pres.slide_count {
    builder.sb_push_str(&mut out, "<Relationship Id=\"");
    let rid = _rid_name(s + 1);
    builder.sb_push_str(&mut out, rid);
    builder.sb_push_str(&mut out, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide");
    builder.sb_push_int(&mut out, s + 1);
    builder.sb_push_str(&mut out, ".xml\"/>");
    s = s + 1;
  };
  builder.sb_push_str(&mut out, "</Relationships>");
  return _ok_bytes(out);
}

fn _slide_xml(pres: &PptxPresentation, slide: Int) -> Result[Vec[UInt8], Str] {
  var out = builder.sb_new();
  _xml_header(&mut out);
  builder.sb_push_str(&mut out, "<p:sld xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\">");
  builder.sb_push_str(&mut out, "<p:cSld><p:spTree>");
  builder.sb_push_str(&mut out, "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>");
  builder.sb_push_str(&mut out, "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>");
  var k = 0;
  var i = 0;
  let n = pres.shape_kind.len();
  while i < n {
    let owner: Int = pres.shape_slide[i];
    if owner == slide {
      let x: Int = pres.shape_x[i];
      let y: Int = pres.shape_y[i];
      let w: Int = pres.shape_w[i];
      let h: Int = pres.shape_h[i];
      let off: Int = pres.shape_text_off[i];
      let ln: Int = pres.shape_text_len[i];
      if off < 0 || ln < 0 || off + ln > pres.text.len() {
        return _err_bytes("pptx: shape text span invalid");
      };
      builder.sb_push_str(&mut out, "<p:sp><p:nvSpPr><p:cNvPr id=\"");
      builder.sb_push_int(&mut out, 2 + k);
      builder.sb_push_str(&mut out, "\" name=\"TextBox ");
      builder.sb_push_int(&mut out, k + 1);
      builder.sb_push_str(&mut out, "\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"");
      builder.sb_push_int(&mut out, x);
      builder.sb_push_str(&mut out, "\" y=\"");
      builder.sb_push_int(&mut out, y);
      builder.sb_push_str(&mut out, "\"/><a:ext cx=\"");
      builder.sb_push_int(&mut out, w);
      builder.sb_push_str(&mut out, "\" cy=\"");
      builder.sb_push_int(&mut out, h);
      builder.sb_push_str(&mut out, "\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\"/><a:lstStyle/><a:p><a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>");
      let pool: Vec[UInt8] = pres.text;
      let raw = _slice(&pool, off, ln);
      let text = builder.sb_to_str(&raw);
      let er = _xml_escape(&mut out, text);
      if !er.is_ok {
        return _err_bytes(er.error);
      };
      builder.sb_push_str(&mut out, "</a:t></a:r></a:p></p:txBody></p:sp>");
      k = k + 1;
    };
    i = i + 1;
  };
  builder.sb_push_str(&mut out, "</p:spTree></p:cSld></p:sld>");
  return _ok_bytes(out);
}

// --------------------------------------------------
//  ZIP writer
// --------------------------------------------------

pub fn zip_writer_new() -> ZipWriter {
  return ZipWriter{
    names: Vec[UInt8].new();
    name_off: Vec[Int].new();
    name_len: Vec[Int].new();
    method: Vec[Int].new();
    payload: Vec[UInt8].new();
    payload_off: Vec[Int].new();
    payload_len: Vec[Int].new();
  };
}

fn _zip_name_valid(name: Str) -> Result[Int, Str] {
  let n = string.str_len(name);
  if n < 1 {
    return _err_int("pptx: zip entry name is empty");
  };
  if n > 255 {
    return _err_int("pptx: zip entry name too long");
  };
  let b0: UInt8 = string.byte_at(name, 0);
  let x0: Int = (b0 as Int) & 0xFF;
  if x0 == 47 {
    return _err_int("pptx: zip entry name must be relative");
  };
  if _has_dotdot(name) {
    return _err_int("pptx: zip entry name must not contain ..");
  };
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(name, i);
    let x: Int = (b as Int) & 0xFF;
    if x < 32 || x > 126 || x == 92 {
      return _err_int("pptx: zip entry name must be printable ascii");
    };
    i = i + 1;
  };
  return _ok_int(n);
}

/// Append an entry; returns its index. `method` is 0 (stored) or 8 (deflate).
pub fn zip_writer_add(w: &mut ZipWriter, name: Str, data: &Vec[UInt8], method: Int) -> Result[Int, Str] {
  if method != 0 && method != 8 {
    return _err_int("pptx: unsupported compression method");
  };
  let nvr = _zip_name_valid(name);
  if !nvr.is_ok {
    return _err_int(nvr.error);
  };
  if w.name_len.len() >= _MAX_ZIP_ENTRIES {
    return _err_int("pptx: zip entry limit reached");
  };
  let plen = data.len();
  if w.payload.len() + plen > 268435456 {
    return _err_int("pptx: zip payload pool exceeds cap");
  };
  let noff = w.names.len();
  var i = 0;
  let nn = string.str_len(name);
  while i < nn {
    let b: UInt8 = string.byte_at(name, i);
    w.names.push(b);
    i = i + 1;
  };
  w.name_off.push(noff);
  w.name_len.push(nn);
  let poff = w.payload.len();
  i = 0;
  while i < plen {
    let b: UInt8 = data[i];
    w.payload.push(b);
    i = i + 1;
  };
  w.payload_off.push(poff);
  w.payload_len.push(plen);
  w.method.push(method);
  return _ok_int(w.method.len() - 1);
}

pub fn zip_writer_entry_count(w: &ZipWriter) -> Int {
  return w.name_len.len();
}

/// Serialize the accumulated entries: local headers + data, central
/// directory, EOCD. Deflate entries use the stdlib fixed-Huffman producer for
/// inputs up to 64 KiB and stored DEFLATE blocks above that.
pub fn zip_writer_finish(w: &ZipWriter) -> Result[Vec[UInt8], Str] {
  let n = w.name_len.len();
  if w.name_off.len() != n || w.method.len() != n || w.payload_off.len() != n || w.payload_len.len() != n {
    return _err_bytes("pptx: zip writer state is inconsistent");
  };
  if n > _MAX_ZIP_ENTRIES {
    return _err_bytes("pptx: zip entry limit reached");
  };
  var crcs = Vec[Int].new();
  var comp_off = Vec[Int].new();
  var comp_size = Vec[Int].new();
  var comp_pool = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let poff: Int = w.payload_off[i];
    let plen: Int = w.payload_len[i];
    if poff < 0 || plen < 0 || poff + plen > w.payload.len() {
      return _err_bytes("pptx: zip writer payload span invalid");
    };
    let src: Vec[UInt8] = w.payload;
    let payload = _slice(&src, poff, plen);
    let c32: UInt32 = gzip.gzip_crc32(&payload);
    let ci: Int = c32 as Int;
    var comp = Vec[UInt8].new();
    let m: Int = w.method[i];
    if m == 0 {
      comp = payload;
    } else {
      var lvl = 6;
      if plen > _DEFLATE_FIXED_MAX_INPUT {
        lvl = 0;
      };
      comp = deflate.deflate_compress_level(&payload, lvl);
    };
    crcs.push(ci);
    comp_off.push(comp_pool.len());
    comp_size.push(comp.len());
    _append_bytes(&mut comp_pool, &comp);
    i = i + 1;
  };
  var out = Vec[UInt8].new();
  var local_off = Vec[Int].new();
  i = 0;
  while i < n {
    local_off.push(out.len());
    let m: Int = w.method[i];
    let cv: Int = crcs[i];
    let cs: Int = comp_size[i];
    let us: Int = w.payload_len[i];
    let nl: Int = w.name_len[i];
    let noff: Int = w.name_off[i];
    let coff: Int = comp_off[i];
    _push_u32le(&mut out, _ZIP_LOCAL_SIG);
    _push_u16le(&mut out, 20);
    _push_u16le(&mut out, 0);
    _push_u16le(&mut out, m);
    _push_u16le(&mut out, 0);
    _push_u16le(&mut out, 0);
    _push_u32le(&mut out, cv);
    _push_u32le(&mut out, cs);
    _push_u32le(&mut out, us);
    _push_u16le(&mut out, nl);
    _push_u16le(&mut out, 0);
    let npool: Vec[UInt8] = w.names;
    _append_range(&mut out, &npool, noff, nl);
    _append_range(&mut out, &comp_pool, coff, cs);
    i = i + 1;
  };
  let cd_off = out.len();
  i = 0;
  while i < n {
    let m: Int = w.method[i];
    let cv: Int = crcs[i];
    let cs: Int = comp_size[i];
    let us: Int = w.payload_len[i];
    let nl: Int = w.name_len[i];
    let noff: Int = w.name_off[i];
    let lo: Int = local_off[i];
    _push_u32le(&mut out, _ZIP_CENTRAL_SIG);
    _push_u16le(&mut out, 20);
    _push_u16le(&mut out, 20);
    _push_u16le(&mut out, 0);
    _push_u16le(&mut out, m);
    _push_u16le(&mut out, 0);
    _push_u16le(&mut out, 0);
    _push_u32le(&mut out, cv);
    _push_u32le(&mut out, cs);
    _push_u32le(&mut out, us);
    _push_u16le(&mut out, nl);
    _push_u16le(&mut out, 0);
    _push_u16le(&mut out, 0);
    _push_u16le(&mut out, 0);
    _push_u16le(&mut out, 0);
    _push_u32le(&mut out, 0);
    _push_u32le(&mut out, lo);
    let npool: Vec[UInt8] = w.names;
    _append_range(&mut out, &npool, noff, nl);
    i = i + 1;
  };
  let cd_size = out.len() - cd_off;
  _push_u32le(&mut out, _ZIP_EOCD_SIG);
  _push_u16le(&mut out, 0);
  _push_u16le(&mut out, 0);
  _push_u16le(&mut out, n);
  _push_u16le(&mut out, n);
  _push_u32le(&mut out, cd_size);
  _push_u32le(&mut out, cd_off);
  _push_u16le(&mut out, 0);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Local RFC 1951 decoder: STORED + FIXED-Huffman blocks
// --------------------------------------------------

fn _bit(data: &Vec[UInt8], pos: Int) -> Int {
  if pos < 0 {
    return -1;
  };
  let byte_idx = pos / 8;
  if byte_idx >= data.len() {
    return -1;
  };
  let b: UInt8 = data[byte_idx];
  let x: Int = (b as Int) & 0xFF;
  let shift = pos % 8;
  return (x >> shift) & 1;
}

fn _read_bits_lsb(data: &Vec[UInt8], pos: Int, count: Int) -> Int {
  var v = 0;
  var place = 1;
  var i = 0;
  while i < count {
    let b = _bit(data, pos + i);
    if b < 0 {
      return -1;
    };
    v = v + b * place;
    place = place * 2;
    i = i + 1;
  };
  return v;
}

/// One fix-up on the two RFC 1951 length tables; kept local because the
/// stdlib exposes only the whole-stream entry points.
fn _fx_len_base(code: Int) -> Int {
  if code >= 281 {
    if code == 285 {
      return 258;
    };
    return 131 + (code - 281) * 32;
  };
  if code >= 277 {
    return 67 + (code - 277) * 16;
  };
  if code >= 273 {
    return 35 + (code - 273) * 8;
  };
  if code >= 269 {
    return 19 + (code - 269) * 4;
  };
  if code >= 265 {
    return 11 + (code - 265) * 2;
  };
  return 3 + (code - 257);
}

fn _fx_len_extra(code: Int) -> Int {
  if code < 265 || code == 285 {
    return 0;
  };
  if code < 269 {
    return 1;
  };
  if code < 273 {
    return 2;
  };
  if code < 277 {
    return 3;
  };
  if code < 281 {
    return 4;
  };
  return 5;
}

fn _fx_dist_base(code: Int) -> Int {
  if code < 4 {
    return code + 1;
  };
  if code < 6 {
    return 5 + (code - 4) * 2;
  };
  if code < 8 {
    return 9 + (code - 6) * 4;
  };
  if code < 10 {
    return 17 + (code - 8) * 8;
  };
  if code < 12 {
    return 33 + (code - 10) * 16;
  };
  if code < 14 {
    return 65 + (code - 12) * 32;
  };
  if code < 16 {
    return 129 + (code - 14) * 64;
  };
  if code < 18 {
    return 257 + (code - 16) * 128;
  };
  if code < 20 {
    return 513 + (code - 18) * 256;
  };
  if code < 22 {
    return 1025 + (code - 20) * 512;
  };
  if code < 24 {
    return 2049 + (code - 22) * 1024;
  };
  if code < 26 {
    return 4097 + (code - 24) * 2048;
  };
  if code < 28 {
    return 8193 + (code - 26) * 4096;
  };
  return 16385 + (code - 28) * 8192;
}

fn _fx_dist_extra(code: Int) -> Int {
  if code < 4 {
    return 0;
  };
  if code < 26 {
    return 1 + (code - 4) / 2;
  };
  return 13;
}

/// Decode one fixed-Huffman literal/length symbol. Returns (symbol, new bit
/// position); symbol -1 means malformed or truncated input. Codes are read
/// MSB-first as RFC 1951 3.1.1 requires.
fn _fx_lit_sym(data: &Vec[UInt8], pos: Int) -> (Int, Int) {
  var code = 0;
  var len = 0;
  var p = pos;
  while len < 9 {
    let b = _bit(data, p);
    if b < 0 {
      return (-1, p);
    };
    p = p + 1;
    code = code * 2 + b;
    len = len + 1;
    if len == 7 {
      if code <= 23 {
        return (256 + code, p);
      };
    } else {
      if len == 8 {
        if code >= 48 && code <= 191 {
          return (code - 48, p);
        };
        if code >= 192 && code <= 199 {
          return (280 + code - 192, p);
        };
      } else {
        if len == 9 {
          if code >= 400 && code <= 511 {
            return (144 + code - 400, p);
          };
          return (-1, p);
        };
      };
    };
  };
  return (-1, p);
}

fn _fx_dist_sym(data: &Vec[UInt8], pos: Int) -> (Int, Int) {
  var code = 0;
  var p = pos;
  var i = 0;
  while i < 5 {
    let b = _bit(data, p);
    if b < 0 {
      return (-1, p);
    };
    p = p + 1;
    code = code * 2 + b;
    i = i + 1;
  };
  if code > 29 {
    return (-1, p);
  };
  return (code, p);
}

/// Local inflater for STORED and FIXED-Huffman DEFLATE streams, with an
/// output ceiling. DYNAMIC-Huffman blocks are rejected loudly (see SPEC.md).
pub fn zip_inflate_fixed(data: &Vec[UInt8], max_out: Int) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  var pos = 0;
  var done = false;
  var blocks = 0;
  while !done {
    blocks = blocks + 1;
    if blocks > _MAX_BLOCKS {
      return _err_bytes("pptx: deflate: block limit exceeded");
    };
    let b0 = _bit(data, pos);
    let b1 = _bit(data, pos + 1);
    let b2 = _bit(data, pos + 2);
    if b0 < 0 || b1 < 0 || b2 < 0 {
      return _err_bytes("pptx: deflate: truncated block header");
    };
    let bfinal = b0;
    let btype = b1 + b2 * 2;
    pos = pos + 3;
    if btype == 0 {
      pos = ((pos + 7) / 8) * 8;
      let boff = pos / 8;
      if boff + 4 > data.len() {
        return _err_bytes("pptx: deflate: truncated stored block header");
      };
      let blen = _read_u16le(data, boff);
      let bnlen = _read_u16le(data, boff + 2);
      if (blen ^ 65535) != bnlen {
        return _err_bytes("pptx: deflate: stored length mismatch");
      };
      if boff + 4 + blen > data.len() {
        return _err_bytes("pptx: deflate: stored block truncated");
      };
      if out.len() + blen > max_out {
        return _err_bytes("pptx: deflate: output exceeds cap");
      };
      var i = 0;
      while i < blen {
        let b: UInt8 = data[boff + 4 + i];
        out.push(b);
        i = i + 1;
      };
      pos = (boff + 4 + blen) * 8;
    } else {
      if btype == 1 {
        var sdone = false;
        while !sdone {
          let ls = _fx_lit_sym(data, pos);
          if ls.0 < 0 {
            return _err_bytes("pptx: deflate: bad literal/length symbol");
          };
          pos = ls.1;
          let s = ls.0;
          if s == 256 {
            sdone = true;
          } else {
            if s < 256 {
              if out.len() >= max_out {
                return _err_bytes("pptx: deflate: output exceeds cap");
              };
              out.push((s as UInt8));
            } else {
              if s > 285 {
                return _err_bytes("pptx: deflate: invalid length code");
              };
              let le = _fx_len_extra(s);
              let ev = _read_bits_lsb(data, pos, le);
              if ev < 0 {
                return _err_bytes("pptx: deflate: truncated length extra bits");
              };
              pos = pos + le;
              let mlen = _fx_len_base(s) + ev;
              let ds = _fx_dist_sym(data, pos);
              if ds.0 < 0 {
                return _err_bytes("pptx: deflate: bad distance symbol");
              };
              pos = ds.1;
              let de = _fx_dist_extra(ds.0);
              let dv = _read_bits_lsb(data, pos, de);
              if dv < 0 {
                return _err_bytes("pptx: deflate: truncated distance extra bits");
              };
              pos = pos + de;
              let mdist = _fx_dist_base(ds.0) + dv;
              if mdist > out.len() {
                return _err_bytes("pptx: deflate: distance exceeds output");
              };
              if out.len() + mlen > max_out {
                return _err_bytes("pptx: deflate: output exceeds cap");
              };
              var j = 0;
              while j < mlen {
                out.push(out[out.len() - mdist]);
                j = j + 1;
              };
            };
          };
        };
      } else {
        return _err_bytes("pptx: deflate: dynamic-huffman blocks unsupported");
      };
    };
    if bfinal == 1 {
      done = true;
    };
  };
  return _ok_bytes(out);
}

// --------------------------------------------------
//  ZIP reader
// --------------------------------------------------

fn _zip_index_ok(a: &ZipArchive, i: Int) -> Bool {
  if i < 0 {
    return false;
  };
  let n = a.method.len();
  if i >= n {
    return false;
  };
  return a.name_off.len() == n && a.name_len.len() == n && a.comp_size.len() == n && a.uncomp_size.len() == n && a.crc.len() == n && a.local_off.len() == n && a.comp_off.len() == n;
}

/// Parse a ZIP archive: EOCD scan (archive comments included), central
/// directory walk with strict bounds and local-header cross-checks. Entry
/// payloads are copied decompressed-on-demand later by `zip_entry_data`.
pub fn zip_read(data: &Vec[UInt8]) -> Result[ZipArchive, Str] {
  let n = data.len();
  if n < 22 {
    return _err_zip("pptx: not a zip archive (no end of central directory)");
  };
  var min_off = n - 22 - 65535;
  if min_off < 0 {
    min_off = 0;
  };
  var eocd = -1;
  var i = n - 22;
  while i >= min_off {
    let s: Int = _read_u32le(data, i);
    if s == _ZIP_EOCD_SIG {
      eocd = i;
      i = min_off - 1;
    } else {
      i = i - 1;
    };
  };
  if eocd < 0 {
    return _err_zip("pptx: not a zip archive (no end of central directory)");
  };
  let total: Int = _read_u16le(data, eocd + 10);
  let cd_size: Int = _read_u32le(data, eocd + 12);
  let cd_off: Int = _read_u32le(data, eocd + 16);
  let clen: Int = _read_u16le(data, eocd + 20);
  if eocd + 22 + clen != n {
    return _err_zip("pptx: zip end record does not end the file");
  };
  if total > _MAX_ZIP_ENTRIES {
    return _err_zip("pptx: zip entry count exceeds cap");
  };
  if cd_off < 0 || cd_size < 0 || cd_off + cd_size > eocd {
    return _err_zip("pptx: zip central directory out of bounds");
  };
  var names = Vec[UInt8].new();
  var name_off = Vec[Int].new();
  var name_len = Vec[Int].new();
  var method = Vec[Int].new();
  var comp_size = Vec[Int].new();
  var uncomp_size = Vec[Int].new();
  var crc = Vec[Int].new();
  var local_off = Vec[Int].new();
  var comp = Vec[UInt8].new();
  var comp_off = Vec[Int].new();
  var pos = cd_off;
  var k = 0;
  while k < total {
    if pos + 46 > n {
      return _err_zip("pptx: truncated central directory");
    };
    if _read_u32le(data, pos) != _ZIP_CENTRAL_SIG {
      return _err_zip("pptx: bad central directory signature");
    };
    let flags: Int = _read_u16le(data, pos + 8);
    if (flags & 8) != 0 {
      return _err_zip("pptx: zip data descriptors unsupported");
    };
    let m: Int = _read_u16le(data, pos + 10);
    if m != 0 && m != 8 {
      return _err_zip("pptx: unsupported zip compression method");
    };
    let crc_v: Int = _read_u32le(data, pos + 16);
    let csz: Int = _read_u32le(data, pos + 20);
    let usz: Int = _read_u32le(data, pos + 24);
    let nl: Int = _read_u16le(data, pos + 28);
    let el: Int = _read_u16le(data, pos + 30);
    let cl: Int = _read_u16le(data, pos + 32);
    let lo: Int = _read_u32le(data, pos + 42);
    if pos + 46 + nl + el + cl > n {
      return _err_zip("pptx: truncated central directory entry");
    };
    var j = 0;
    while j < nl {
      let nb: UInt8 = data[pos + 46 + j];
      let nx: Int = (nb as Int) & 0xFF;
      if nx == 0 {
        return _err_zip("pptx: zip entry name contains NUL");
      };
      names.push(nb);
      j = j + 1;
    };
    name_off.push(names.len() - nl);
    name_len.push(nl);
    if lo < 0 || lo + 30 > n {
      return _err_zip("pptx: zip local header out of bounds");
    };
    if _read_u32le(data, lo) != _ZIP_LOCAL_SIG {
      return _err_zip("pptx: bad local header signature");
    };
    let lflags: Int = _read_u16le(data, lo + 6);
    if (lflags & 8) != 0 {
      return _err_zip("pptx: zip data descriptors unsupported");
    };
    let lmethod: Int = _read_u16le(data, lo + 8);
    if lmethod != m {
      return _err_zip("pptx: zip local and central methods differ");
    };
    let lnl: Int = _read_u16le(data, lo + 26);
    let lel: Int = _read_u16le(data, lo + 28);
    let data_off = lo + 30 + lnl + lel;
    if data_off < 0 || data_off + csz > n {
      return _err_zip("pptx: zip entry data out of bounds");
    };
    if lnl != nl {
      return _err_zip("pptx: zip local and central names differ");
    };
    var j2 = 0;
    while j2 < nl {
      let a1: UInt8 = data[lo + 30 + j2];
      let a2: UInt8 = data[pos + 46 + j2];
      if a1 != a2 {
        return _err_zip("pptx: zip local and central names differ");
      };
      j2 = j2 + 1;
    };
    comp_off.push(comp.len());
    var j3 = 0;
    while j3 < csz {
      let cb: UInt8 = data[data_off + j3];
      comp.push(cb);
      j3 = j3 + 1;
    };
    method.push(m);
    comp_size.push(csz);
    uncomp_size.push(usz);
    crc.push(crc_v);
    local_off.push(lo);
    pos = pos + 46 + nl + el + cl;
    k = k + 1;
  };
  if pos != cd_off + cd_size {
    return _err_zip("pptx: central directory size mismatch");
  };
  return _ok_zip(ZipArchive{
    names: names;
    name_off: name_off;
    name_len: name_len;
    method: method;
    comp_size: comp_size;
    uncomp_size: uncomp_size;
    crc: crc;
    local_off: local_off;
    comp: comp;
    comp_off: comp_off;
  });
}

pub fn zip_entry_count(a: &ZipArchive) -> Int {
  return a.method.len();
}

pub fn zip_entry_find(a: &ZipArchive, name: Str) -> Int {
  let n = a.name_len.len();
  let m = string.str_len(name);
  var i = 0;
  while i < n {
    let noff: Int = a.name_off[i];
    let ln: Int = a.name_len[i];
    if ln == m && noff >= 0 && noff + ln <= a.names.len() {
      var j = 0;
      var ok = true;
      while j < m {
        let x: UInt8 = a.names[noff + j];
        let y: UInt8 = string.byte_at(name, j);
        if x != y {
          ok = false;
          j = m;
        } else {
          j = j + 1;
        };
      };
      if ok {
        return i;
      };
    };
    i = i + 1;
  };
  return -1;
}

pub fn zip_entry_name(a: &ZipArchive, i: Int) -> Result[Str, Str] {
  if !_zip_index_ok(a, i) {
    return _err_str("pptx: zip entry index out of range");
  };
  let noff: Int = a.name_off[i];
  let nl: Int = a.name_len[i];
  if noff < 0 || nl < 0 || noff + nl > a.names.len() {
    return _err_str("pptx: zip entry name span invalid");
  };
  let pool: Vec[UInt8] = a.names;
  let raw = _slice(&pool, noff, nl);
  return _part_to_str(&raw);
}

pub fn zip_entry_method(a: &ZipArchive, i: Int) -> Result[Int, Str] {
  if !_zip_index_ok(a, i) {
    return _err_int("pptx: zip entry index out of range");
  };
  let v: Int = a.method[i];
  return _ok_int(v);
}

pub fn zip_entry_crc(a: &ZipArchive, i: Int) -> Result[Int, Str] {
  if !_zip_index_ok(a, i) {
    return _err_int("pptx: zip entry index out of range");
  };
  let v: Int = a.crc[i];
  return _ok_int(v);
}

pub fn zip_entry_size(a: &ZipArchive, i: Int) -> Result[Int, Str] {
  if !_zip_index_ok(a, i) {
    return _err_int("pptx: zip entry index out of range");
  };
  let v: Int = a.uncomp_size[i];
  return _ok_int(v);
}

pub fn zip_entry_compressed_size(a: &ZipArchive, i: Int) -> Result[Int, Str] {
  if !_zip_index_ok(a, i) {
    return _err_int("pptx: zip entry index out of range");
  };
  let v: Int = a.comp_size[i];
  return _ok_int(v);
}

pub fn zip_entry_local_offset(a: &ZipArchive, i: Int) -> Result[Int, Str] {
  if !_zip_index_ok(a, i) {
    return _err_int("pptx: zip entry index out of range");
  };
  let v: Int = a.local_off[i];
  return _ok_int(v);
}

/// CRC-32 (IEEE) of `data`, exposed so callers can verify entry checksums
/// without importing the compression stack themselves.
pub fn zip_crc32(data: &Vec[UInt8]) -> Int {
  let c: UInt32 = gzip.gzip_crc32(data);
  return c as Int;
}

/// Entry payload: STORED entries are copied, DEFLATE entries are inflated
/// with the stdlib capped inflater and fall back to the local
/// STORED+fixed-Huffman decoder. Declared size and CRC-32 are enforced.
pub fn zip_entry_data(a: &ZipArchive, i: Int) -> Result[Vec[UInt8], Str] {
  if !_zip_index_ok(a, i) {
    return _err_bytes("pptx: zip entry index out of range");
  };
  let m: Int = a.method[i];
  let csz: Int = a.comp_size[i];
  let usz: Int = a.uncomp_size[i];
  let coff: Int = a.comp_off[i];
  let cvec: Vec[UInt8] = a.comp;
  if coff < 0 || csz < 0 || coff + csz > cvec.len() {
    return _err_bytes("pptx: zip entry data span invalid");
  };
  let comp = _slice(&cvec, coff, csz);
  var out = Vec[UInt8].new();
  if m == 0 {
    if csz != usz {
      return _err_bytes("pptx: stored entry size mismatch");
    };
    out = comp;
  } else {
    let dec = deflate.deflate_decompress_capped(&comp, _MAX_PART_BYTES);
    if dec.is_ok {
      let dv: Vec[UInt8] = dec.value;
      out = dv;
    } else {
      let fb = zip_inflate_fixed(&comp, _MAX_PART_BYTES);
      if !fb.is_ok {
        return _err_bytes(fb.error);
      };
      let fv: Vec[UInt8] = fb.value;
      out = fv;
    };
  };
  if out.len() != usz {
    return _err_bytes("pptx: zip entry uncompressed size mismatch");
  };
  let stored: Int = a.crc[i];
  let c32: UInt32 = gzip.gzip_crc32(&out);
  let actual: Int = c32 as Int;
  if actual != stored {
    return _err_bytes("pptx: zip entry crc mismatch");
  };
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Presentation serialize / parse
// --------------------------------------------------

/// Serialize a presentation to PPTX bytes; every part is DEFLATE-compressed.
pub fn pptx_presentation_to_bytes(pres: &PptxPresentation) -> Result[Vec[UInt8], Str] {
  return pptx_presentation_to_bytes_method(pres, 8);
}

/// Serialize a presentation to PPTX bytes; every part is STORED.
pub fn pptx_presentation_to_bytes_stored(pres: &PptxPresentation) -> Result[Vec[UInt8], Str] {
  return pptx_presentation_to_bytes_method(pres, 0);
}

pub fn pptx_presentation_to_bytes_method(pres: &PptxPresentation, method: Int) -> Result[Vec[UInt8], Str] {
  if method != 0 && method != 8 {
    return _err_bytes("pptx: unsupported compression method");
  };
  if !_pres_consistent(pres) {
    return _err_bytes("pptx: presentation model is inconsistent");
  };
  var w = zip_writer_new();
  let ctr = _content_types_xml(pres);
  if !ctr.is_ok {
    return _err_bytes(ctr.error);
  };
  let ctv: Vec[UInt8] = ctr.value;
  let ra = zip_writer_add(&mut w, "[Content_Types].xml", &ctv, method);
  if !ra.is_ok {
    return _err_bytes(ra.error);
  };
  let rlr = _root_rels_xml();
  if !rlr.is_ok {
    return _err_bytes(rlr.error);
  };
  let rlv: Vec[UInt8] = rlr.value;
  let ra2 = zip_writer_add(&mut w, "_rels/.rels", &rlv, method);
  if !ra2.is_ok {
    return _err_bytes(ra2.error);
  };
  let pxr = _presentation_xml(pres);
  if !pxr.is_ok {
    return _err_bytes(pxr.error);
  };
  let pxv: Vec[UInt8] = pxr.value;
  let ra3 = zip_writer_add(&mut w, "ppt/presentation.xml", &pxv, method);
  if !ra3.is_ok {
    return _err_bytes(ra3.error);
  };
  let prr = _presentation_rels_xml(pres);
  if !prr.is_ok {
    return _err_bytes(prr.error);
  };
  let prv: Vec[UInt8] = prr.value;
  let ra4 = zip_writer_add(&mut w, "ppt/_rels/presentation.xml.rels", &prv, method);
  if !ra4.is_ok {
    return _err_bytes(ra4.error);
  };
  var s = 0;
  while s < pres.slide_count {
    let sxr = _slide_xml(pres, s);
    if !sxr.is_ok {
      return _err_bytes(sxr.error);
    };
    let sxv: Vec[UInt8] = sxr.value;
    let part = _slide_part_name(s + 1);
    let ra5 = zip_writer_add(&mut w, part, &sxv, method);
    if !ra5.is_ok {
      return _err_bytes(ra5.error);
    };
    s = s + 1;
  };
  return zip_writer_finish(&w);
}

fn _parse_slide_into(pres: &mut PptxPresentation, slide: Int, sx: Str) -> Result[Int, Str] {
  if _find_from(sx, "<p:sld", 0) < 0 {
    return _err_int("pptx: not a presentationml slide part");
  };
  var pos = 0;
  var count = 0;
  var scanning = true;
  while scanning {
    let sp = _find_from(sx, "<p:sp>", pos);
    if sp < 0 {
      scanning = false;
    } else {
      let spe = _find_from(sx, "</p:sp>", sp);
      if spe < 0 {
        return _err_int("pptx: unterminated shape element");
      };
      let chunk = string.str_slice(sx, sp, spe + 7);
      let offp = _find_from(chunk, "<a:off", 0);
      if offp < 0 {
        return _err_int("pptx: shape missing a:off");
      };
      let offe = _find_from(chunk, "/>", offp);
      if offe < 0 {
        return _err_int("pptx: malformed a:off element");
      };
      let offtag = string.str_slice(chunk, offp, offe + 2);
      let xr = _attr_int(offtag, "x", 0);
      if !xr.is_ok {
        return _err_int(xr.error);
      };
      let yr = _attr_int(offtag, "y", 0);
      if !yr.is_ok {
        return _err_int(yr.error);
      };
      let extp = _find_from(chunk, "<a:ext", 0);
      if extp < 0 {
        return _err_int("pptx: shape missing a:ext");
      };
      let exte = _find_from(chunk, "/>", extp);
      if exte < 0 {
        return _err_int("pptx: malformed a:ext element");
      };
      let exttag = string.str_slice(chunk, extp, exte + 2);
      let wr = _attr_int(exttag, "cx", 0);
      if !wr.is_ok {
        return _err_int(wr.error);
      };
      let hr = _attr_int(exttag, "cy", 0);
      if !hr.is_ok {
        return _err_int(hr.error);
      };
      let tp = _find_from(chunk, "<a:t>", 0);
      if tp < 0 {
        return _err_int("pptx: shape missing a:t text");
      };
      let te = _find_from(chunk, "</a:t>", tp);
      if te < 0 {
        return _err_int("pptx: unterminated a:t text");
      };
      let raw = string.str_slice(chunk, tp + 5, te);
      let ur = _xml_unescape(raw);
      if !ur.is_ok {
        return _err_int(ur.error);
      };
      let text: Str = ur.value;
      let pr = _push_shape(pres, slide, 0, xr.value, yr.value, wr.value, hr.value, text);
      if !pr.is_ok {
        return _err_int(pr.error);
      };
      pos = spe + 7;
      count = count + 1;
      if count > _MAX_SHAPES {
        return _err_int("pptx: shape limit reached");
      };
    };
  };
  return _ok_int(0);
}

/// Parse PPTX bytes back into a presentation model.
pub fn pptx_presentation_from_bytes(data: &Vec[UInt8]) -> Result[PptxPresentation, Str] {
  let ar = zip_read(data);
  if !ar.is_ok {
    return _err_pres(ar.error);
  };
  let arch: ZipArchive = ar.value;
  let pi = zip_entry_find(&arch, "ppt/presentation.xml");
  if pi < 0 {
    return _err_pres("pptx: missing part ppt/presentation.xml");
  };
  let pr = zip_entry_data(&arch, pi);
  if !pr.is_ok {
    return _err_pres(pr.error);
  };
  let pb: Vec[UInt8] = pr.value;
  let psr = _part_to_str(&pb);
  if !psr.is_ok {
    return _err_pres(psr.error);
  };
  let px: Str = psr.value;
  if _find_from(px, "<p:presentation", 0) < 0 {
    return _err_pres("pptx: not a presentationml presentation part");
  };
  let ri = zip_entry_find(&arch, "ppt/_rels/presentation.xml.rels");
  if ri < 0 {
    return _err_pres("pptx: missing part ppt/_rels/presentation.xml.rels");
  };
  let rr = zip_entry_data(&arch, ri);
  if !rr.is_ok {
    return _err_pres(rr.error);
  };
  let rb: Vec[UInt8] = rr.value;
  let rsr = _part_to_str(&rb);
  if !rsr.is_ok {
    return _err_pres(rsr.error);
  };
  let rx: Str = rsr.value;
  let partsr = _collect_slide_parts(px, rx);
  if !partsr.is_ok {
    return _err_pres(partsr.error);
  };
  let parts: _StrPool = partsr.value;
  var pw = PPTX_DEFAULT_WIDTH_EMU;
  var ph = PPTX_DEFAULT_HEIGHT_EMU;
  let szp = _find_from(px, "<p:sldSz ", 0);
  if szp >= 0 {
    let sze = _find_from(px, "/>", szp);
    if sze < 0 {
      return _err_pres("pptx: malformed sldSz element");
    };
    let sztag = string.str_slice(px, szp, sze + 2);
    let cxr = _attr_int(sztag, "cx", 0);
    if !cxr.is_ok {
      return _err_pres(cxr.error);
    };
    let cyr = _attr_int(sztag, "cy", 0);
    if !cyr.is_ok {
      return _err_pres(cyr.error);
    };
    pw = cxr.value;
    ph = cyr.value;
    if pw <= 0 || ph <= 0 {
      return _err_pres("pptx: sldSz dimensions must be positive");
    };
  };
  var pres = pptx_presentation_new(pw, ph);
  let sc = _pool_len(&parts);
  if sc > _MAX_SLIDES {
    return _err_pres("pptx: slide limit reached");
  };
  var s = 0;
  while s < sc {
    let part: Str = _pool_get(&parts, s);
    let ei = zip_entry_find(&arch, part);
    if ei < 0 {
      return _err_pres("pptx: missing slide part " + part);
    };
    let dr = zip_entry_data(&arch, ei);
    if !dr.is_ok {
      return _err_pres(dr.error);
    };
    let db: Vec[UInt8] = dr.value;
    let sr = _part_to_str(&db);
    if !sr.is_ok {
      return _err_pres(sr.error);
    };
    let sx: Str = sr.value;
    let sp = _parse_slide_into(&mut pres, s, sx);
    if !sp.is_ok {
      return _err_pres(sp.error);
    };
    s = s + 1;
  };
  pres.slide_count = sc;
  if !_pres_consistent(&pres) {
    return _err_pres("pptx: presentation model is inconsistent");
  };
  return _ok_pres(pres);
}
