// XIOM -- xiom.jpeg: JPEG (ITU-T T.81) marker and segment parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. This module implements the marker/segment layer of the
// JPEG interchange format (ITU-T T.81 / ISO/IEC 10918-1) over flat
// Vec[UInt8] buffers. Entropy-coded data is never decoded:
//
//   image  := SOI segment* EOI
//   marker := FF (FF)* code
//   segment:= FF code BE16(length) payload[length-2]
//
// Parsed structurally (T.81 Annex B):
//   SOI   start of image, must be the first two bytes
//   APP0  JFIF (version, units, density, thumbnail dimensions)
//   APP1  EXIF header presence ("Exif\0\0")
//   APPn  opaque index of every APP0..APP15 segment
//   DQT   table id + precision (8-bit / 16-bit) + 64 quant values
//   SOF0  baseline DCT: precision, height, width, components
//   SOF1  extended sequential DCT: same layout
//   SOF2  progressive DCT: same layout, progressive flag
//   DHT   table class/id, 16 code counts, symbol list length
//   SOS   component selectors, spectral selection, successive approximation
//   DRI   restart interval
//   COM   comment segment index
//   EOI   end of image
//
// Scan data: from the end of the SOS segment payload to the next non-stuffed
// FF marker code, honoring FF00 byte-stuffing and RST0..RST7 restart markers
// (counted, never interpreted). Unknown markers, unsupported SOF variants
// (lossless, arithmetic, differential, hierarchical) and DAC/DNL are
// rejected with an explicit message; they are outside the v0.1 scope.
//
// Parsed results use parallel Vec fields (no Vec[StructType]): the frame
// component list, the quant-table index with a flat 64-value store, the
// Huffman-table index with a flat 16-count store, the scan index with a flat
// selector store, the APP index and the COM index. There are no Vec[Str]
// fields at all, so no byte range is ever turned into a Str: identifiers are
// compared byte-wise.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[i] as Int) & 0xFF`.
//   * every Vec[Int] element read is bound to a typed local.
//   * `as` is a reserved keyword; no casts of Int to UInt8 are needed here.
//   * success is signalled by a JpegError with offset -1 (see _no_err), so
//     no Str comparison (len on a struct field) is used for control flow.
//   * no Vec[Float64], no lambdas, no methods, no table-driven dispatch.
// See SPEC.md for the byte layout tables, the validation order, the full
// error catalog and the test matrix.

module xiom.jpeg

use xiom.convert;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// SOI marker code (0xD8): start of image.
pub fn jpeg_soi() -> Int {
  return 216;
}

/// EOI marker code (0xD9): end of image.
pub fn jpeg_eoi() -> Int {
  return 217;
}

/// SOS marker code (0xDA): start of scan.
pub fn jpeg_sos() -> Int {
  return 218;
}

/// SOF0 marker code (0xC0): baseline sequential DCT.
pub fn jpeg_frame_baseline() -> Int {
  return 192;
}

/// SOF1 marker code (0xC1): extended sequential DCT.
pub fn jpeg_frame_extended() -> Int {
  return 193;
}

/// SOF2 marker code (0xC2): progressive DCT.
pub fn jpeg_frame_progressive() -> Int {
  return 194;
}

/// First restart marker code (RST0, 0xD0).
pub fn jpeg_restart_first() -> Int {
  return 208;
}

/// Last restart marker code (RST7, 0xD7).
pub fn jpeg_restart_last() -> Int {
  return 215;
}

/// Smallest legal segment length field (the two length bytes themselves).
pub fn jpeg_min_segment_length() -> Int {
  return 2;
}

/// Offset sentinel for "absent" (also the success offset of _no_err).
pub fn jpeg_no_offset() -> Int {
  return -1;
}

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parse failure: a message plus the absolute byte offset it refers to.
/// `offset` is always >= 0 in values returned by jpeg_parse; the internal
/// success sentinel uses -1 and never escapes.
pub type JpegError = {
  message: Str;
  offset: Int;
}

/// Parsed JPEG marker stream.
///
/// Frame: `width`, `height`, `precision` and `frame_marker` (192/193/194)
/// decode the validated SOF segment; `progressive` is 1 for SOF2 and 0
/// otherwise. Components are stored in frame order with one entry each in
/// `component_id`, `component_h`, `component_v` and `component_quant`
/// (sampling factors are 1..4, quant table ids 0..3).
///
/// JFIF: `has_jfif` is 1 when an APP0 segment with the "JFIF\0" identifier
/// parsed; the version/units/density/thumbnail fields then hold its values.
/// `has_exif` is 1 when an APP1 segment starts with "Exif\0\0" and
/// `exif_offset` is that segment's marker offset (-1 when absent).
///
/// Quant tables: `quant_id`/`quant_precision` hold one entry per table;
/// `quant_value_offset` is the index of the table's first value inside the
/// flat `quant_values` vector (64 values per table, 0..255 or 0..65535).
///
/// Huffman tables: `dht_class` (0 DC, 1 AC), `dht_id` (0..3), `dht_symbols`
/// (the sum of the 16 counts, 0..256) and `dht_count_offset` into the flat
/// `dht_counts` vector (16 counts per table).
///
/// Scans: one entry per SOS segment. `scan_ss`/`scan_se` are the spectral
/// selection bounds, `scan_ah`/`scan_al` the successive approximation bits.
/// `scan_component_offset` indexes the flat selector store
/// (`scan_component_id`/`scan_component_dc`/`scan_component_ac`), with
/// `scan_component_count` selectors for the scan. `scan_data_offset` and
/// `scan_data_length` delimit the raw, still-stuffed entropy bytes;
/// `scan_restart_count` counts RST0..RST7 markers inside that span and
/// `scan_marker_offset` is the FF that begins the terminating marker.
///
/// APP/COM: `app_marker` (224..239), `app_offset` (marker FF), `app_length`
/// (declared length field) and `app_data_offset` (first payload byte) index
/// every APP segment in stream order; comments are indexed by
/// `com_offset`/`com_length`.
///
/// DRI/EOI: `restart_interval` is -1 when no DRI was seen; `dri_count` is
/// the number of DRI segments (a later DRI replaces the interval).
/// `eoi_offset` is the FF of the EOI marker and `total_bytes` the buffer
/// length, so `total_bytes - (eoi_offset + 2)` bytes follow EOI.
pub type JpegImage = {
  width: Int;
  height: Int;
  precision: Int;
  frame_marker: Int;
  progressive: Int;
  component_id: Vec[Int];
  component_h: Vec[Int];
  component_v: Vec[Int];
  component_quant: Vec[Int];
  has_jfif: Int;
  jfif_version_major: Int;
  jfif_version_minor: Int;
  jfif_units: Int;
  jfif_density_x: Int;
  jfif_density_y: Int;
  jfif_thumb_w: Int;
  jfif_thumb_h: Int;
  has_exif: Int;
  exif_offset: Int;
  quant_id: Vec[Int];
  quant_precision: Vec[Int];
  quant_value_offset: Vec[Int];
  quant_values: Vec[Int];
  dht_class: Vec[Int];
  dht_id: Vec[Int];
  dht_symbols: Vec[Int];
  dht_count_offset: Vec[Int];
  dht_counts: Vec[Int];
  scan_ss: Vec[Int];
  scan_se: Vec[Int];
  scan_ah: Vec[Int];
  scan_al: Vec[Int];
  scan_component_count: Vec[Int];
  scan_component_offset: Vec[Int];
  scan_component_id: Vec[Int];
  scan_component_dc: Vec[Int];
  scan_component_ac: Vec[Int];
  scan_data_offset: Vec[Int];
  scan_data_length: Vec[Int];
  scan_restart_count: Vec[Int];
  scan_marker_offset: Vec[Int];
  app_marker: Vec[Int];
  app_offset: Vec[Int];
  app_length: Vec[Int];
  app_data_offset: Vec[Int];
  com_offset: Vec[Int];
  com_length: Vec[Int];
  restart_interval: Int;
  dri_count: Int;
  eoi_offset: Int;
  total_bytes: Int;
}

// Internal mutable scan state: the public fields plus the seen flags. The
// public type exposes counts through the accessors, so no count can drift
// away from its vector length.
type _Acc = {
  width: Int;
  height: Int;
  precision: Int;
  frame_marker: Int;
  progressive: Int;
  component_id: Vec[Int];
  component_h: Vec[Int];
  component_v: Vec[Int];
  component_quant: Vec[Int];
  seen_sof: Int;
  has_jfif: Int;
  seen_jfif: Int;
  jfif_version_major: Int;
  jfif_version_minor: Int;
  jfif_units: Int;
  jfif_density_x: Int;
  jfif_density_y: Int;
  jfif_thumb_w: Int;
  jfif_thumb_h: Int;
  has_exif: Int;
  exif_offset: Int;
  quant_id: Vec[Int];
  quant_precision: Vec[Int];
  quant_value_offset: Vec[Int];
  quant_values: Vec[Int];
  dht_class: Vec[Int];
  dht_id: Vec[Int];
  dht_symbols: Vec[Int];
  dht_count_offset: Vec[Int];
  dht_counts: Vec[Int];
  scan_ss: Vec[Int];
  scan_se: Vec[Int];
  scan_ah: Vec[Int];
  scan_al: Vec[Int];
  scan_component_count: Vec[Int];
  scan_component_offset: Vec[Int];
  scan_component_id: Vec[Int];
  scan_component_dc: Vec[Int];
  scan_component_ac: Vec[Int];
  scan_data_offset: Vec[Int];
  scan_data_length: Vec[Int];
  scan_restart_count: Vec[Int];
  scan_marker_offset: Vec[Int];
  app_marker: Vec[Int];
  app_offset: Vec[Int];
  app_length: Vec[Int];
  app_data_offset: Vec[Int];
  com_offset: Vec[Int];
  com_length: Vec[Int];
  restart_interval: Int;
  dri_count: Int;
  eoi_offset: Int;
  total_bytes: Int;
}

// Validated scan parameters handed back by _parse_sos so the caller can
// record them together with the entropy span it discovers afterwards.
type _ScanInfo = {
  ss: Int;
  se: Int;
  ah: Int;
  al: Int;
  comp_count: Int;
  comp_offset: Int;
}

// --------------------------------------------------
//  Result leaf helpers (v0.61.3: Ok/Err may only be constructed in fns that
//  return a Result directly, so every fallible public fn returns through
//  these). Success inside the parser is an error value with offset -1.
// --------------------------------------------------

// Ok(v) for Result[JpegImage, JpegError].
fn _ok_img(v: JpegImage) -> Result[JpegImage, JpegError] {
  return Ok(v);
}

// Err(e) for Result[JpegImage, JpegError].
fn _fail_img(e: JpegError) -> Result[JpegImage, JpegError] {
  return Err(e);
}

// The success sentinel: an error value that no caller may report.
fn _no_err() -> JpegError {
  return JpegError{ message: ""; offset: -1 };
}

// A real parse failure at an absolute byte offset.
fn _bad(m: Str, off: Int) -> JpegError {
  return JpegError{ message: m; offset: off };
}

// --------------------------------------------------
//  Byte readers and message helpers
// --------------------------------------------------

// Unsigned byte at index i (widened and masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Big-endian unsigned 16-bit value at `off` (0..65535).
fn _be16(data: &Vec[UInt8], off: Int) -> Int {
  return _b(data, off) * 256 + _b(data, off + 1);
}

// Append one message with an absolute byte offset: "<base> at <off>".
fn _at(base: Str, off: Int) -> Str {
  return base + " at " + convert.int_to_string(off);
}

// True for the SOF markers this module decodes: C0, C1, C2.
fn _is_sof(code: Int) -> Bool {
  if (code == 192 || code == 193 || code == 194) { return true; }
  return false;
}

// True for every other SOF-family marker (C3, C5..C7, C9..CB, CD..CF):
// lossless, differential and arithmetic frames, outside the v0.1 scope.
fn _is_sof_family(code: Int) -> Bool {
  if (code < 192 || code > 207) { return false; }
  if (code == 192 || code == 193 || code == 194) { return false; }
  if (code == 196 || code == 200 || code == 204) { return false; }
  return true;
}

// True for marker codes that end an entropy-coded scan when they follow an
// FF fill run inside scan data (every marker the grammar recognises outside
// the RST0..RST7 and stuffed-FF cases).
fn _is_scan_terminator(code: Int) -> Bool {
  if (code >= 192 && code <= 207) { return true; }
  if (code >= 216 && code <= 223) { return true; }
  if (code >= 224 && code <= 239) { return true; }
  if (code == 254) { return true; }
  return false;
}

// True when data[d, d+5) is the JFIF identifier "JFIF\0".
fn _is_jfif_id(data: &Vec[UInt8], d: Int, len: Int) -> Bool {
  if (len < 5) { return false; }
  if (_b(data, d) != 74) { return false; }
  if (_b(data, d + 1) != 70) { return false; }
  if (_b(data, d + 2) != 73) { return false; }
  if (_b(data, d + 3) != 70) { return false; }
  if (_b(data, d + 4) != 0) { return false; }
  return true;
}

// True when data[d, d+6) is the EXIF identifier "Exif\0\0".
fn _is_exif_id(data: &Vec[UInt8], d: Int, len: Int) -> Bool {
  if (len < 6) { return false; }
  if (_b(data, d) != 69) { return false; }
  if (_b(data, d + 1) != 120) { return false; }
  if (_b(data, d + 2) != 105) { return false; }
  if (_b(data, d + 3) != 102) { return false; }
  if (_b(data, d + 4) != 0) { return false; }
  if (_b(data, d + 5) != 0) { return false; }
  return true;
}

// --------------------------------------------------
//  Index append helpers: every sibling vector always receives exactly one
//  entry, so parallel-Vec drift is structurally impossible.
// --------------------------------------------------

// Append one APP index record.
fn _push_app(a: &mut _Acc, code: Int, off: Int, len: Int, data_off: Int) {
  a.app_marker.push(code);
  a.app_offset.push(off);
  a.app_length.push(len + 2);
  a.app_data_offset.push(data_off);
}

// Append one scan record (all ten vectors get one entry).
fn _push_scan(a: &mut _Acc, ss: Int, se: Int, ah: Int, al: Int, comp_count: Int, comp_offset: Int, data_off: Int, data_len: Int, rst: Int, marker_off: Int) {
  a.scan_ss.push(ss);
  a.scan_se.push(se);
  a.scan_ah.push(ah);
  a.scan_al.push(al);
  a.scan_component_count.push(comp_count);
  a.scan_component_offset.push(comp_offset);
  a.scan_data_offset.push(data_off);
  a.scan_data_length.push(data_len);
  a.scan_restart_count.push(rst);
  a.scan_marker_offset.push(marker_off);
}

// --------------------------------------------------
//  Segment parsers: each returns _no_err() on success or _bad(msg, offset);
//  partial pushes before an error are discarded with the accumulator.
// --------------------------------------------------

// SOF0/SOF1/SOF2: precision, height, width, component list.
fn _parse_sof(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int, code: Int) -> JpegError {
  if (a.seen_sof != 0) { return _bad(_at("jpeg: duplicate SOF", p), p); }
  if (len < 6) { return _bad(_at("jpeg: invalid SOF length", p), p); }
  let precision = _b(data, d);
  let height = _be16(data, d + 1);
  let width = _be16(data, d + 3);
  let nf = _b(data, d + 5);
  if (nf == 0) { return _bad(_at("jpeg: invalid component count", d + 5), d + 5); }
  if (len != 6 + 3 * nf) { return _bad(_at("jpeg: invalid SOF length", p), p); }
  if (code == 192) {
    if (precision != 8) { return _bad(_at("jpeg: invalid precision", d), d); }
  } else {
    if (precision != 8 && precision != 12) { return _bad(_at("jpeg: invalid precision", d), d); }
  }
  if (width == 0) { return _bad(_at("jpeg: zero frame dimension", d + 3), d + 3); }
  if (height == 0) { return _bad(_at("jpeg: zero frame dimension", d + 1), d + 1); }
  var i = 0;
  while (i < nf) {
    let cid = _b(data, d + 6 + 3 * i);
    let hv = _b(data, d + 7 + 3 * i);
    let tq = _b(data, d + 8 + 3 * i);
    let hh = hv / 16;
    let vv = hv % 16;
    if (hh < 1 || hh > 4) { return _bad(_at("jpeg: invalid sampling factor", d + 7 + 3 * i), d + 7 + 3 * i); }
    if (vv < 1 || vv > 4) { return _bad(_at("jpeg: invalid sampling factor", d + 7 + 3 * i), d + 7 + 3 * i); }
    if (tq > 3) { return _bad(_at("jpeg: invalid quant table id", d + 8 + 3 * i), d + 8 + 3 * i); }
    var j = 0;
    while (j < a.component_id.len()) {
      let prev: Int = a.component_id[j];
      if (prev == cid) { return _bad(_at("jpeg: duplicate component id", d + 6 + 3 * i), d + 6 + 3 * i); }
      j = j + 1;
    }
    a.component_id.push(cid);
    a.component_h.push(hh);
    a.component_v.push(vv);
    a.component_quant.push(tq);
    i = i + 1;
  }
  a.width = width;
  a.height = height;
  a.precision = precision;
  a.frame_marker = code;
  if (code == 194) {
    a.progressive = 1;
  } else {
    a.progressive = 0;
  }
  a.seen_sof = 1;
  return _no_err();
}

// DQT: one or more tables; Pq/Tq byte, then 64 (8-bit) or 64 x 2 (16-bit)
// big-endian values, each in 1..255 or 1..65535.
fn _parse_dqt(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> JpegError {
  if (len == 0) { return _bad(_at("jpeg: empty DQT", p), p); }
  var i = 0;
  while (i < len) {
    let info = _b(data, d + i);
    let pq = info / 16;
    let tq = info % 16;
    if (pq > 1) { return _bad(_at("jpeg: invalid DQT precision", d + i), d + i); }
    if (tq > 3) { return _bad(_at("jpeg: invalid DQT table id", d + i), d + i); }
    var need = 64;
    if (pq == 1) { need = 128; }
    if (i + 1 + need > len) { return _bad(_at("jpeg: truncated DQT table", d + i), d + i); }
    a.quant_id.push(tq);
    a.quant_precision.push(pq);
    a.quant_value_offset.push(a.quant_values.len());
    var k = 0;
    while (k < 64) {
      var v = 0;
      var voff = d + i + 1 + k;
      if (pq == 1) {
        v = _be16(data, d + i + 1 + 2 * k);
        voff = d + i + 1 + 2 * k;
      } else {
        v = _b(data, d + i + 1 + k);
      }
      if (v == 0) { return _bad(_at("jpeg: zero quant value", voff), voff); }
      a.quant_values.push(v);
      k = k + 1;
    }
    i = i + 1 + need;
  }
  return _no_err();
}

// DHT: one or more tables; Tc/Th byte, 16 code counts, then the symbol list
// (sum of the counts) whose bytes stay opaque.
fn _parse_dht(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> JpegError {
  if (len == 0) { return _bad(_at("jpeg: empty DHT", p), p); }
  var i = 0;
  while (i < len) {
    if (i + 17 > len) { return _bad(_at("jpeg: truncated DHT", d + i), d + i); }
    let info = _b(data, d + i);
    let tc = info / 16;
    let th = info % 16;
    if (tc > 1) { return _bad(_at("jpeg: invalid DHT class", d + i), d + i); }
    if (th > 3) { return _bad(_at("jpeg: invalid DHT table id", d + i), d + i); }
    var total = 0;
    var k = 0;
    while (k < 16) {
      total = total + _b(data, d + i + 1 + k);
      k = k + 1;
    }
    if (total > 256) { return _bad(_at("jpeg: DHT symbol count overflow", d + i), d + i); }
    if (i + 17 + total > len) { return _bad(_at("jpeg: truncated DHT", d + i), d + i); }
    a.dht_class.push(tc);
    a.dht_id.push(th);
    a.dht_symbols.push(total);
    a.dht_count_offset.push(a.dht_counts.len());
    k = 0;
    while (k < 16) {
      a.dht_counts.push(_b(data, d + i + 1 + k));
      k = k + 1;
    }
    i = i + 17 + total;
  }
  return _no_err();
}

// DRI: exactly one big-endian 16-bit restart interval.
fn _parse_dri(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int) -> JpegError {
  if (len != 2) { return _bad(_at("jpeg: invalid DRI length", p), p); }
  a.restart_interval = _be16(data, d);
  a.dri_count = a.dri_count + 1;
  return _no_err();
}

// SOS: component selectors, spectral selection and successive approximation.
// Every selector must name a frame component and appear at most once in the
// scan; Ns is 1..4 (T.81 limit). Interleaved and non-interleaved scans are
// both accepted; whether each component appears exactly once over all scans
// is an entropy-level rule and is not enforced here.
fn _parse_sos(a: &mut _Acc, data: &Vec[UInt8], p: Int, d: Int, len: Int, out: &mut _ScanInfo) -> JpegError {
  if (a.seen_sof == 0) { return _bad(_at("jpeg: SOS before SOF", p), p); }
  if (len < 1) { return _bad(_at("jpeg: invalid SOS length", p), p); }
  let ns = _b(data, d);
  if (len != 1 + 2 * ns + 3) { return _bad(_at("jpeg: invalid SOS length", p), p); }
  if (ns == 0) { return _bad(_at("jpeg: invalid scan component count", d), d); }
  if (ns > 4) { return _bad(_at("jpeg: invalid scan component count", d), d); }
  out.comp_offset = a.scan_component_id.len();
  out.comp_count = ns;
  var k = 0;
  while (k < ns) {
    let cid = _b(data, d + 1 + 2 * k);
    let tdta = _b(data, d + 2 + 2 * k);
    var found = 0;
    var j = 0;
    while (j < a.component_id.len()) {
      let cj: Int = a.component_id[j];
      if (cj == cid) { found = 1; }
      j = j + 1;
    }
    if (found == 0) { return _bad(_at("jpeg: unknown scan component", d + 1 + 2 * k), d + 1 + 2 * k); }
    var dup = 0;
    j = out.comp_offset;
    while (j < a.scan_component_id.len()) {
      let sj: Int = a.scan_component_id[j];
      if (sj == cid) { dup = 1; }
      j = j + 1;
    }
    if (dup != 0) { return _bad(_at("jpeg: duplicate scan component", d + 1 + 2 * k), d + 1 + 2 * k); }
    let td = tdta / 16;
    let ta = tdta % 16;
    if (td > 3) { return _bad(_at("jpeg: invalid DC table selector", d + 2 + 2 * k), d + 2 + 2 * k); }
    if (ta > 3) { return _bad(_at("jpeg: invalid AC table selector", d + 2 + 2 * k), d + 2 + 2 * k); }
    a.scan_component_id.push(cid);
    a.scan_component_dc.push(td);
    a.scan_component_ac.push(ta);
    k = k + 1;
  }
  let ss = _b(data, d + 1 + 2 * ns);
  let se = _b(data, d + 2 + 2 * ns);
  let ahal = _b(data, d + 3 + 2 * ns);
  let ah = ahal / 16;
  let al = ahal % 16;
  if (ss > 63 || se > 63) { return _bad(_at("jpeg: invalid spectral selection", d + 1 + 2 * ns), d + 1 + 2 * ns); }
  if (ss > se) { return _bad(_at("jpeg: invalid spectral selection", d + 1 + 2 * ns), d + 1 + 2 * ns); }
  if (ah > 13 || al > 13) { return _bad(_at("jpeg: invalid successive approximation", d + 3 + 2 * ns), d + 3 + 2 * ns); }
  if (a.progressive == 0) {
    if (ss != 0) { return _bad(_at("jpeg: invalid spectral selection", d + 1 + 2 * ns), d + 1 + 2 * ns); }
    if (se != 63) { return _bad(_at("jpeg: invalid spectral selection", d + 2 + 2 * ns), d + 2 + 2 * ns); }
    if (ah != 0 || al != 0) { return _bad(_at("jpeg: invalid successive approximation", d + 3 + 2 * ns), d + 3 + 2 * ns); }
  } else {
    if (ss == 0 && se != 0) { return _bad(_at("jpeg: invalid spectral selection", d + 1 + 2 * ns), d + 1 + 2 * ns); }
    if (ah != 0 && ah != al + 1) { return _bad(_at("jpeg: invalid successive approximation", d + 3 + 2 * ns), d + 3 + 2 * ns); }
  }
  out.ss = ss;
  out.se = se;
  out.ah = ah;
  out.al = al;
  return _no_err();
}

// APP0..APP15: always indexed; APP0 with the JFIF identifier additionally
// decodes the JFIF header, APP1 with "Exif\0\0" sets the EXIF flag. Anything
// else stays an opaque indexed segment.
fn _parse_app(a: &mut _Acc, data: &Vec[UInt8], code: Int, p: Int, d: Int, len: Int) -> JpegError {
  _push_app(a, code, p, len, d);
  if (code == 224 && _is_jfif_id(data, d, len)) {
    if (a.seen_jfif != 0) { return _bad(_at("jpeg: duplicate JFIF", p), p); }
    if (len < 14) { return _bad(_at("jpeg: invalid JFIF segment", p), p); }
    let major = _b(data, d + 5);
    let minor = _b(data, d + 6);
    let units = _b(data, d + 7);
    if (units > 2) { return _bad(_at("jpeg: invalid JFIF units", d + 7), d + 7); }
    let dx = _be16(data, d + 8);
    let dy = _be16(data, d + 10);
    if (dx == 0 || dy == 0) { return _bad(_at("jpeg: invalid JFIF density", d + 8), d + 8); }
    let tw = _b(data, d + 12);
    let th = _b(data, d + 13);
    if (14 + 3 * tw * th != len) { return _bad(_at("jpeg: invalid JFIF segment", p), p); }
    a.jfif_version_major = major;
    a.jfif_version_minor = minor;
    a.jfif_units = units;
    a.jfif_density_x = dx;
    a.jfif_density_y = dy;
    a.jfif_thumb_w = tw;
    a.jfif_thumb_h = th;
    a.has_jfif = 1;
    a.seen_jfif = 1;
  } elif (code == 225 && _is_exif_id(data, d, len)) {
    a.has_exif = 1;
    a.exif_offset = p;
  }
  return _no_err();
}

// COM: comment payload stays opaque; only the span is indexed.
fn _parse_com(a: &mut _Acc, p: Int, len: Int) {
  a.com_offset.push(p);
  a.com_length.push(len);
}

// Move the accumulator into the public result type, dropping the seen flags.
fn _finish(a: _Acc) -> JpegImage {
  let width: Int = a.width;
  let height: Int = a.height;
  let precision: Int = a.precision;
  let frame_marker: Int = a.frame_marker;
  let progressive: Int = a.progressive;
  let component_id: Vec[Int] = a.component_id;
  let component_h: Vec[Int] = a.component_h;
  let component_v: Vec[Int] = a.component_v;
  let component_quant: Vec[Int] = a.component_quant;
  let has_jfif: Int = a.has_jfif;
  let jfif_version_major: Int = a.jfif_version_major;
  let jfif_version_minor: Int = a.jfif_version_minor;
  let jfif_units: Int = a.jfif_units;
  let jfif_density_x: Int = a.jfif_density_x;
  let jfif_density_y: Int = a.jfif_density_y;
  let jfif_thumb_w: Int = a.jfif_thumb_w;
  let jfif_thumb_h: Int = a.jfif_thumb_h;
  let has_exif: Int = a.has_exif;
  let exif_offset: Int = a.exif_offset;
  let quant_id: Vec[Int] = a.quant_id;
  let quant_precision: Vec[Int] = a.quant_precision;
  let quant_value_offset: Vec[Int] = a.quant_value_offset;
  let quant_values: Vec[Int] = a.quant_values;
  let dht_class: Vec[Int] = a.dht_class;
  let dht_id: Vec[Int] = a.dht_id;
  let dht_symbols: Vec[Int] = a.dht_symbols;
  let dht_count_offset: Vec[Int] = a.dht_count_offset;
  let dht_counts: Vec[Int] = a.dht_counts;
  let scan_ss: Vec[Int] = a.scan_ss;
  let scan_se: Vec[Int] = a.scan_se;
  let scan_ah: Vec[Int] = a.scan_ah;
  let scan_al: Vec[Int] = a.scan_al;
  let scan_component_count: Vec[Int] = a.scan_component_count;
  let scan_component_offset: Vec[Int] = a.scan_component_offset;
  let scan_component_id: Vec[Int] = a.scan_component_id;
  let scan_component_dc: Vec[Int] = a.scan_component_dc;
  let scan_component_ac: Vec[Int] = a.scan_component_ac;
  let scan_data_offset: Vec[Int] = a.scan_data_offset;
  let scan_data_length: Vec[Int] = a.scan_data_length;
  let scan_restart_count: Vec[Int] = a.scan_restart_count;
  let scan_marker_offset: Vec[Int] = a.scan_marker_offset;
  let app_marker: Vec[Int] = a.app_marker;
  let app_offset: Vec[Int] = a.app_offset;
  let app_length: Vec[Int] = a.app_length;
  let app_data_offset: Vec[Int] = a.app_data_offset;
  let com_offset: Vec[Int] = a.com_offset;
  let com_length: Vec[Int] = a.com_length;
  let restart_interval: Int = a.restart_interval;
  let dri_count: Int = a.dri_count;
  let eoi_offset: Int = a.eoi_offset;
  let total_bytes: Int = a.total_bytes;
  return JpegImage{
    width: width;
    height: height;
    precision: precision;
    frame_marker: frame_marker;
    progressive: progressive;
    component_id: component_id;
    component_h: component_h;
    component_v: component_v;
    component_quant: component_quant;
    has_jfif: has_jfif;
    jfif_version_major: jfif_version_major;
    jfif_version_minor: jfif_version_minor;
    jfif_units: jfif_units;
    jfif_density_x: jfif_density_x;
    jfif_density_y: jfif_density_y;
    jfif_thumb_w: jfif_thumb_w;
    jfif_thumb_h: jfif_thumb_h;
    has_exif: has_exif;
    exif_offset: exif_offset;
    quant_id: quant_id;
    quant_precision: quant_precision;
    quant_value_offset: quant_value_offset;
    quant_values: quant_values;
    dht_class: dht_class;
    dht_id: dht_id;
    dht_symbols: dht_symbols;
    dht_count_offset: dht_count_offset;
    dht_counts: dht_counts;
    scan_ss: scan_ss;
    scan_se: scan_se;
    scan_ah: scan_ah;
    scan_al: scan_al;
    scan_component_count: scan_component_count;
    scan_component_offset: scan_component_offset;
    scan_component_id: scan_component_id;
    scan_component_dc: scan_component_dc;
    scan_component_ac: scan_component_ac;
    scan_data_offset: scan_data_offset;
    scan_data_length: scan_data_length;
    scan_restart_count: scan_restart_count;
    scan_marker_offset: scan_marker_offset;
    app_marker: app_marker;
    app_offset: app_offset;
    app_length: app_length;
    app_data_offset: app_data_offset;
    com_offset: com_offset;
    com_length: com_length;
    restart_interval: restart_interval;
    dri_count: dri_count;
    eoi_offset: eoi_offset;
    total_bytes: total_bytes;
  };
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse and structurally validate one JPEG buffer. Nothing is decoded: no
/// Huffman tables are built and no entropy bytes are interpreted.
///
/// Validation order and messages (see SPEC.md for the full catalog):
///   1. fewer than 2 bytes or a first marker other than FFD8 ->
///      "jpeg: missing SOI at 0";
///   2. marker stream: a byte that is not FF -> "jpeg: invalid marker"; a
///      trailing FF run -> "jpeg: truncated marker"; FF00 -> "jpeg: invalid
///      marker"; a second SOI -> "jpeg: unexpected SOI"; RST0..RST7 ->
///      "jpeg: unexpected restart marker"; SOF3..SOF15 (other than DHT) ->
///      "jpeg: unsupported frame type"; anything else unknown ->
///      "jpeg: unsupported marker";
///   3. segments: length field missing -> "jpeg: truncated segment"; length
///      below 2 -> "jpeg: invalid segment length"; segment past the buffer
///      -> "jpeg: segment length out of bounds";
///   4. per-marker payload validation (SOF, DQT, DHT, DRI, SOS, APP/COM);
///   5. SOS is followed by raw scan data up to the next non-stuffed marker
///      (FF00 stuffing and RST markers are consumed; EOF without a marker ->
///      "jpeg: missing EOI");
///   6. EOI: no SOF -> "jpeg: missing SOF"; no SOS -> "jpeg: missing SOS";
///      EOF without EOI -> "jpeg: missing EOI" (or "jpeg: missing SOF" when
///      no frame was seen). Bytes after EOI are allowed and counted by
///      jpeg_trailing_bytes.
/// Complexity: O(input bytes).
pub fn jpeg_parse(data: &Vec[UInt8]) -> Result[JpegImage, JpegError] {
  let n = data.len();
  if (n < 2) { return _fail_img(_bad(_at("jpeg: missing SOI", 0), 0)); }
  if (_b(data, 0) != 255) { return _fail_img(_bad(_at("jpeg: missing SOI", 0), 0)); }
  if (_b(data, 1) != 216) { return _fail_img(_bad(_at("jpeg: missing SOI", 0), 0)); }
  var a = _Acc{
    width: 0;
    height: 0;
    precision: 0;
    frame_marker: 0;
    progressive: 0;
    component_id: Vec[Int].new();
    component_h: Vec[Int].new();
    component_v: Vec[Int].new();
    component_quant: Vec[Int].new();
    seen_sof: 0;
    has_jfif: 0;
    seen_jfif: 0;
    jfif_version_major: 0;
    jfif_version_minor: 0;
    jfif_units: 0;
    jfif_density_x: 0;
    jfif_density_y: 0;
    jfif_thumb_w: 0;
    jfif_thumb_h: 0;
    has_exif: 0;
    exif_offset: -1;
    quant_id: Vec[Int].new();
    quant_precision: Vec[Int].new();
    quant_value_offset: Vec[Int].new();
    quant_values: Vec[Int].new();
    dht_class: Vec[Int].new();
    dht_id: Vec[Int].new();
    dht_symbols: Vec[Int].new();
    dht_count_offset: Vec[Int].new();
    dht_counts: Vec[Int].new();
    scan_ss: Vec[Int].new();
    scan_se: Vec[Int].new();
    scan_ah: Vec[Int].new();
    scan_al: Vec[Int].new();
    scan_component_count: Vec[Int].new();
    scan_component_offset: Vec[Int].new();
    scan_component_id: Vec[Int].new();
    scan_component_dc: Vec[Int].new();
    scan_component_ac: Vec[Int].new();
    scan_data_offset: Vec[Int].new();
    scan_data_length: Vec[Int].new();
    scan_restart_count: Vec[Int].new();
    scan_marker_offset: Vec[Int].new();
    app_marker: Vec[Int].new();
    app_offset: Vec[Int].new();
    app_length: Vec[Int].new();
    app_data_offset: Vec[Int].new();
    com_offset: Vec[Int].new();
    com_length: Vec[Int].new();
    restart_interval: -1;
    dri_count: 0;
    eoi_offset: -1;
    total_bytes: n;
  };
  var pos = 2;
  var saw_eoi = 0;
  while (pos < n && saw_eoi == 0) {
    if (_b(data, pos) != 255) { return _fail_img(_bad(_at("jpeg: invalid marker", pos), pos)); }
    var q = pos;
    while (q < n && _b(data, q) == 255) { q = q + 1; }
    if (q >= n) { return _fail_img(_bad(_at("jpeg: truncated marker", pos), pos)); }
    let code = _b(data, q);
    let moff = q - 1;
    let after = q + 1;
    if (code == 0) { return _fail_img(_bad(_at("jpeg: invalid marker", moff), moff)); }
    if (code == 1) { return _fail_img(_bad(_at("jpeg: unsupported marker", moff), moff)); }
    if (code == 216) { return _fail_img(_bad(_at("jpeg: unexpected SOI", moff), moff)); }
    if (code == 217) {
      if (a.seen_sof == 0) { return _fail_img(_bad(_at("jpeg: missing SOF", moff), moff)); }
      if (a.scan_ss.len() == 0) { return _fail_img(_bad(_at("jpeg: missing SOS", moff), moff)); }
      a.eoi_offset = moff;
      a.total_bytes = n;
      saw_eoi = 1;
    } elif (code >= 208 && code <= 215) {
      return _fail_img(_bad(_at("jpeg: unexpected restart marker", moff), moff));
    } elif (_is_sof_family(code)) {
      return _fail_img(_bad(_at("jpeg: unsupported frame type", moff), moff));
    } else {
      if (after + 2 > n) { return _fail_img(_bad(_at("jpeg: truncated segment", moff), moff)); }
      let seglen = _be16(data, after);
      if (seglen < 2) { return _fail_img(_bad(_at("jpeg: invalid segment length", moff), moff)); }
      let send = after + seglen;
      if (send > n) { return _fail_img(_bad(_at("jpeg: segment length out of bounds", moff), moff)); }
      let d = after + 2;
      let plen = seglen - 2;
      if (_is_sof(code)) {
        let e = _parse_sof(&mut a, data, moff, d, plen, code);
        if (e.offset >= 0) { return _fail_img(e); }
      } elif (code == 196) {
        let e = _parse_dht(&mut a, data, moff, d, plen);
        if (e.offset >= 0) { return _fail_img(e); }
      } elif (code == 219) {
        let e = _parse_dqt(&mut a, data, moff, d, plen);
        if (e.offset >= 0) { return _fail_img(e); }
      } elif (code == 221) {
        let e = _parse_dri(&mut a, data, moff, d, plen);
        if (e.offset >= 0) { return _fail_img(e); }
      } elif (code == 224 || (code >= 225 && code <= 239)) {
        let e = _parse_app(&mut a, data, code, moff, d, plen);
        if (e.offset >= 0) { return _fail_img(e); }
      } elif (code == 254) {
        _parse_com(&mut a, moff, seglen);
      } elif (code == 218) {
        var sp = _ScanInfo{ ss: 0; se: 0; ah: 0; al: 0; comp_count: 0; comp_offset: 0 };
        let e = _parse_sos(&mut a, data, moff, d, plen, &mut sp);
        if (e.offset >= 0) { return _fail_img(e); }
        var di = send;
        var rst = 0;
        var mpos = -1;
        while (di < n && mpos < 0) {
          let b = _b(data, di);
          if (b != 255) {
            di = di + 1;
          } else {
            if (di + 1 >= n) { return _fail_img(_bad(_at("jpeg: truncated marker", di), di)); }
            let nc = _b(data, di + 1);
            if (nc == 0) {
              di = di + 2;
            } elif (nc >= 208 && nc <= 215) {
              rst = rst + 1;
              di = di + 2;
            } elif (nc == 255) {
              di = di + 1;
            } elif (_is_scan_terminator(nc)) {
              mpos = di;
            } else {
              di = di + 2;
            }
          }
        }
        if (mpos < 0) { return _fail_img(_bad(_at("jpeg: missing EOI", n), n)); }
        _push_scan(&mut a, sp.ss, sp.se, sp.ah, sp.al, sp.comp_count, sp.comp_offset, send, mpos - send, rst, mpos);
        pos = mpos;
      } else {
        return _fail_img(_bad(_at("jpeg: unsupported marker", moff), moff));
      }
      if (saw_eoi == 0 && code != 218) {
        pos = send;
      }
    }
  }
  if (saw_eoi == 0) {
    if (a.seen_sof == 0) { return _fail_img(_bad(_at("jpeg: missing SOF", n), n)); }
    return _fail_img(_bad(_at("jpeg: missing EOI", n), n));
  }
  return _ok_img(_finish(a));
}

// --------------------------------------------------
//  Classification
// --------------------------------------------------

/// True when the buffer starts with FFD8. Malformed or short buffers return
/// false rather than an error; use jpeg_parse when the reason matters.
/// Complexity: O(1).
pub fn jpeg_is_jpeg(data: &Vec[UInt8]) -> Bool {
  if (data.len() < 2) { return false; }
  if (_b(data, 0) != 255) { return false; }
  if (_b(data, 1) != 216) { return false; }
  return true;
}

// --------------------------------------------------
//  Frame accessors
// --------------------------------------------------

/// Frame width in pixels as stored in SOF (1..65535).
/// Complexity: O(1).
pub fn jpeg_width(img: &JpegImage) -> Int {
  return img.width;
}

/// Frame height in pixels as stored in SOF (1..65535).
/// Complexity: O(1).
pub fn jpeg_height(img: &JpegImage) -> Int {
  return img.height;
}

/// Sample precision in bits: 8 for SOF0, 8 or 12 for SOF1/SOF2.
/// Complexity: O(1).
pub fn jpeg_precision(img: &JpegImage) -> Int {
  return img.precision;
}

/// Frame marker that was parsed: 192 (SOF0), 193 (SOF1) or 194 (SOF2).
/// Complexity: O(1).
pub fn jpeg_frame_marker(img: &JpegImage) -> Int {
  return img.frame_marker;
}

/// True when the frame is progressive (SOF2).
/// Complexity: O(1).
pub fn jpeg_is_progressive(img: &JpegImage) -> Bool {
  return img.progressive != 0;
}

/// Number of frame components (1..255).
/// Complexity: O(1).
pub fn jpeg_component_count(img: &JpegImage) -> Int {
  return img.component_id.len();
}

/// Component identifier `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn jpeg_component_id(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.component_id.len()) { return -1; }
  let v: Int = img.component_id[i];
  return v;
}

/// Horizontal sampling factor of component `i` (1..4), or -1.
/// Complexity: O(1).
pub fn jpeg_component_h(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.component_h.len()) { return -1; }
  let v: Int = img.component_h[i];
  return v;
}

/// Vertical sampling factor of component `i` (1..4), or -1.
/// Complexity: O(1).
pub fn jpeg_component_v(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.component_v.len()) { return -1; }
  let v: Int = img.component_v[i];
  return v;
}

/// Quantization table id of component `i` (0..3), or -1.
/// Complexity: O(1).
pub fn jpeg_component_quant(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.component_quant.len()) { return -1; }
  let v: Int = img.component_quant[i];
  return v;
}

// --------------------------------------------------
//  JFIF / EXIF accessors
// --------------------------------------------------

/// True when a JFIF APP0 segment was parsed.
/// Complexity: O(1).
pub fn jpeg_has_jfif(img: &JpegImage) -> Bool {
  return img.has_jfif != 0;
}

/// JFIF major version (1 for all published JFIF versions), 0 when absent.
/// Complexity: O(1).
pub fn jpeg_jfif_version_major(img: &JpegImage) -> Int {
  return img.jfif_version_major;
}

/// JFIF minor version (0..2 for published versions), 0 when absent.
/// Complexity: O(1).
pub fn jpeg_jfif_version_minor(img: &JpegImage) -> Int {
  return img.jfif_version_minor;
}

/// JFIF density units: 0 aspect ratio, 1 dots per inch, 2 dots per cm.
/// Complexity: O(1).
pub fn jpeg_jfif_units(img: &JpegImage) -> Int {
  return img.jfif_units;
}

/// JFIF horizontal pixel density (always > 0 when JFIF is present).
/// Complexity: O(1).
pub fn jpeg_jfif_density_x(img: &JpegImage) -> Int {
  return img.jfif_density_x;
}

/// JFIF vertical pixel density (always > 0 when JFIF is present).
/// Complexity: O(1).
pub fn jpeg_jfif_density_y(img: &JpegImage) -> Int {
  return img.jfif_density_y;
}

/// JFIF thumbnail width in pixels (0..255).
/// Complexity: O(1).
pub fn jpeg_jfif_thumb_w(img: &JpegImage) -> Int {
  return img.jfif_thumb_w;
}

/// JFIF thumbnail height in pixels (0..255).
/// Complexity: O(1).
pub fn jpeg_jfif_thumb_h(img: &JpegImage) -> Int {
  return img.jfif_thumb_h;
}

/// True when an APP1 segment starting with "Exif\0\0" was seen.
/// Complexity: O(1).
pub fn jpeg_has_exif(img: &JpegImage) -> Bool {
  return img.has_exif != 0;
}

/// Marker offset of the first EXIF APP1 segment, or -1 when absent.
/// Complexity: O(1).
pub fn jpeg_exif_offset(img: &JpegImage) -> Int {
  return img.exif_offset;
}

// --------------------------------------------------
//  Quantization table accessors
// --------------------------------------------------

/// Number of DQT tables across the whole stream.
/// Complexity: O(1).
pub fn jpeg_quant_table_count(img: &JpegImage) -> Int {
  return img.quant_id.len();
}

/// Table id (0..3) of quant table `t`, or -1.
/// Complexity: O(1).
pub fn jpeg_quant_id(img: &JpegImage, t: Int) -> Int {
  if (t < 0 || t >= img.quant_id.len()) { return -1; }
  let v: Int = img.quant_id[t];
  return v;
}

/// Precision of quant table `t`: 0 = 8-bit, 1 = 16-bit, or -1.
/// Complexity: O(1).
pub fn jpeg_quant_precision(img: &JpegImage, t: Int) -> Int {
  if (t < 0 || t >= img.quant_precision.len()) { return -1; }
  let v: Int = img.quant_precision[t];
  return v;
}

/// Index of quant table `t`'s first value inside the flat value store, or -1.
/// Complexity: O(1).
pub fn jpeg_quant_value_offset(img: &JpegImage, t: Int) -> Int {
  if (t < 0 || t >= img.quant_value_offset.len()) { return -1; }
  let v: Int = img.quant_value_offset[t];
  return v;
}

/// Value `k` (0..63, natural order) of quant table `t`, or -1 when any index
/// is out of range. The flat store is bounds-checked against the table's
/// 64-value window so a drifted structure can not read out of window.
/// Complexity: O(1).
pub fn jpeg_quant_value(img: &JpegImage, t: Int, k: Int) -> Int {
  if (t < 0 || t >= img.quant_value_offset.len()) { return -1; }
  if (k < 0 || k > 63) { return -1; }
  let base: Int = img.quant_value_offset[t];
  if (base < 0 || base + 64 > img.quant_values.len()) { return -1; }
  let v: Int = img.quant_values[base + k];
  return v;
}

// --------------------------------------------------
//  Huffman table accessors (counts only; no decode tables)
// --------------------------------------------------

/// Number of DHT tables across the whole stream.
/// Complexity: O(1).
pub fn jpeg_dht_table_count(img: &JpegImage) -> Int {
  return img.dht_class.len();
}

/// Class of DHT table `t`: 0 DC, 1 AC, or -1.
/// Complexity: O(1).
pub fn jpeg_dht_class(img: &JpegImage, t: Int) -> Int {
  if (t < 0 || t >= img.dht_class.len()) { return -1; }
  let v: Int = img.dht_class[t];
  return v;
}

/// Id (0..3) of DHT table `t`, or -1.
/// Complexity: O(1).
pub fn jpeg_dht_id(img: &JpegImage, t: Int) -> Int {
  if (t < 0 || t >= img.dht_id.len()) { return -1; }
  let v: Int = img.dht_id[t];
  return v;
}

/// Number of symbols of DHT table `t` (sum of its 16 counts, 0..256), or -1.
/// Complexity: O(1).
pub fn jpeg_dht_symbol_count(img: &JpegImage, t: Int) -> Int {
  if (t < 0 || t >= img.dht_symbols.len()) { return -1; }
  let v: Int = img.dht_symbols[t];
  return v;
}

/// Index of DHT table `t`'s first count inside the flat count store, or -1.
/// Complexity: O(1).
pub fn jpeg_dht_count_offset(img: &JpegImage, t: Int) -> Int {
  if (t < 0 || t >= img.dht_count_offset.len()) { return -1; }
  let v: Int = img.dht_count_offset[t];
  return v;
}

/// Count `k` (0..15) of DHT table `t`, or -1 when any index is out of range.
/// The flat store is bounds-checked against the table's 16-count window.
/// Complexity: O(1).
pub fn jpeg_dht_count(img: &JpegImage, t: Int, k: Int) -> Int {
  if (t < 0 || t >= img.dht_count_offset.len()) { return -1; }
  if (k < 0 || k > 15) { return -1; }
  let base: Int = img.dht_count_offset[t];
  if (base < 0 || base + 16 > img.dht_counts.len()) { return -1; }
  let v: Int = img.dht_counts[base + k];
  return v;
}

// --------------------------------------------------
//  Scan accessors
// --------------------------------------------------

/// Number of SOS scans in the stream.
/// Complexity: O(1).
pub fn jpeg_scan_count(img: &JpegImage) -> Int {
  return img.scan_ss.len();
}

/// Spectral selection start `Ss` of scan `s`, or -1.
/// Complexity: O(1).
pub fn jpeg_scan_ss(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_ss.len()) { return -1; }
  let v: Int = img.scan_ss[s];
  return v;
}

/// Spectral selection end `Se` of scan `s`, or -1.
/// Complexity: O(1).
pub fn jpeg_scan_se(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_se.len()) { return -1; }
  let v: Int = img.scan_se[s];
  return v;
}

/// Successive approximation high bit `Ah` of scan `s`, or -1.
/// Complexity: O(1).
pub fn jpeg_scan_ah(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_ah.len()) { return -1; }
  let v: Int = img.scan_ah[s];
  return v;
}

/// Successive approximation low bit `Al` of scan `s`, or -1.
/// Complexity: O(1).
pub fn jpeg_scan_al(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_al.len()) { return -1; }
  let v: Int = img.scan_al[s];
  return v;
}

/// Number of component selectors in scan `s` (1..4), or -1.
/// Complexity: O(1).
pub fn jpeg_scan_component_count(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_component_count.len()) { return -1; }
  let v: Int = img.scan_component_count[s];
  return v;
}

/// Index of scan `s`'s first selector inside the flat selector store, or -1.
/// Complexity: O(1).
pub fn jpeg_scan_component_offset(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_component_offset.len()) { return -1; }
  let v: Int = img.scan_component_offset[s];
  return v;
}

/// Component identifier of selector `k` in scan `s`, or -1 when any index is
/// out of range or the selector lies outside the scan's window.
/// Complexity: O(1).
pub fn jpeg_scan_component_id(img: &JpegImage, s: Int, k: Int) -> Int {
  if (s < 0 || s >= img.scan_component_offset.len()) { return -1; }
  if (s >= img.scan_component_count.len()) { return -1; }
  let count: Int = img.scan_component_count[s];
  if (k < 0 || k >= count) { return -1; }
  let base: Int = img.scan_component_offset[s];
  if (base < 0 || base + count > img.scan_component_id.len()) { return -1; }
  let v: Int = img.scan_component_id[base + k];
  return v;
}

/// DC Huffman table selector of selector `k` in scan `s` (0..3), or -1.
/// Complexity: O(1).
pub fn jpeg_scan_component_dc(img: &JpegImage, s: Int, k: Int) -> Int {
  if (s < 0 || s >= img.scan_component_offset.len()) { return -1; }
  if (s >= img.scan_component_count.len()) { return -1; }
  let count: Int = img.scan_component_count[s];
  if (k < 0 || k >= count) { return -1; }
  let base: Int = img.scan_component_offset[s];
  if (base < 0 || base + count > img.scan_component_dc.len()) { return -1; }
  let v: Int = img.scan_component_dc[base + k];
  return v;
}

/// AC Huffman table selector of selector `k` in scan `s` (0..3), or -1.
/// Complexity: O(1).
pub fn jpeg_scan_component_ac(img: &JpegImage, s: Int, k: Int) -> Int {
  if (s < 0 || s >= img.scan_component_offset.len()) { return -1; }
  if (s >= img.scan_component_count.len()) { return -1; }
  let count: Int = img.scan_component_count[s];
  if (k < 0 || k >= count) { return -1; }
  let base: Int = img.scan_component_offset[s];
  if (base < 0 || base + count > img.scan_component_ac.len()) { return -1; }
  let v: Int = img.scan_component_ac[base + k];
  return v;
}

/// Absolute offset of scan `s`'s first entropy byte (right after the SOS
/// length field payload), or -1.
/// Complexity: O(1).
pub fn jpeg_scan_data_offset(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_data_offset.len()) { return -1; }
  let v: Int = img.scan_data_offset[s];
  return v;
}

/// Raw byte length of scan `s`'s entropy span, still byte-stuffed and still
/// containing restart markers, or -1.
/// Complexity: O(1).
pub fn jpeg_scan_data_length(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_data_length.len()) { return -1; }
  let v: Int = img.scan_data_length[s];
  return v;
}

/// Number of RST0..RST7 markers consumed inside scan `s`'s entropy span,
/// or -1.
/// Complexity: O(1).
pub fn jpeg_scan_restart_count(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_restart_count.len()) { return -1; }
  let v: Int = img.scan_restart_count[s];
  return v;
}

/// Offset of the FF byte that begins scan `s`'s terminating marker, or -1.
/// Complexity: O(1).
pub fn jpeg_scan_marker_offset(img: &JpegImage, s: Int) -> Int {
  if (s < 0 || s >= img.scan_marker_offset.len()) { return -1; }
  let v: Int = img.scan_marker_offset[s];
  return v;
}

// --------------------------------------------------
//  APP / COM accessors
// --------------------------------------------------

/// Number of indexed APP0..APP15 segments.
/// Complexity: O(1).
pub fn jpeg_app_segment_count(img: &JpegImage) -> Int {
  return img.app_marker.len();
}

/// Marker code (224..239) of APP segment `i`, or -1.
/// Complexity: O(1).
pub fn jpeg_app_marker(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.app_marker.len()) { return -1; }
  let v: Int = img.app_marker[i];
  return v;
}

/// Marker offset (the FF byte) of APP segment `i`, or -1.
/// Complexity: O(1).
pub fn jpeg_app_offset(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.app_offset.len()) { return -1; }
  let v: Int = img.app_offset[i];
  return v;
}

/// Declared length field of APP segment `i` (>= 2), or -1.
/// Complexity: O(1).
pub fn jpeg_app_length(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.app_length.len()) { return -1; }
  let v: Int = img.app_length[i];
  return v;
}

/// Absolute offset of APP segment `i`'s first payload byte, or -1.
/// Complexity: O(1).
pub fn jpeg_app_data_offset(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.app_data_offset.len()) { return -1; }
  let v: Int = img.app_data_offset[i];
  return v;
}

/// Number of indexed COM segments.
/// Complexity: O(1).
pub fn jpeg_comment_count(img: &JpegImage) -> Int {
  return img.com_offset.len();
}

/// Marker offset of comment segment `i`, or -1.
/// Complexity: O(1).
pub fn jpeg_comment_offset(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.com_offset.len()) { return -1; }
  let v: Int = img.com_offset[i];
  return v;
}

/// Declared length field of comment segment `i` (>= 2), or -1.
/// Complexity: O(1).
pub fn jpeg_comment_length(img: &JpegImage, i: Int) -> Int {
  if (i < 0 || i >= img.com_length.len()) { return -1; }
  let v: Int = img.com_length[i];
  return v;
}

// --------------------------------------------------
//  DRI / EOI accessors
// --------------------------------------------------

/// Latest restart interval (0..65535), or -1 when no DRI was seen.
/// Complexity: O(1).
pub fn jpeg_restart_interval(img: &JpegImage) -> Int {
  return img.restart_interval;
}

/// True when at least one DRI segment was seen.
/// Complexity: O(1).
pub fn jpeg_has_dri(img: &JpegImage) -> Bool {
  return img.dri_count != 0;
}

/// Number of DRI segments seen (a later DRI replaces the interval).
/// Complexity: O(1).
pub fn jpeg_dri_count(img: &JpegImage) -> Int {
  return img.dri_count;
}

/// Offset of the FF byte that begins the EOI marker.
/// Complexity: O(1).
pub fn jpeg_eoi_offset(img: &JpegImage) -> Int {
  return img.eoi_offset;
}

/// Size of the parsed buffer in bytes.
/// Complexity: O(1).
pub fn jpeg_total_bytes(img: &JpegImage) -> Int {
  return img.total_bytes;
}

/// Number of bytes after the EOI marker (0 when EOI is last).
/// Complexity: O(1).
pub fn jpeg_trailing_bytes(img: &JpegImage) -> Int {
  return img.total_bytes - (img.eoi_offset + 2);
}

// --------------------------------------------------
//  Error accessors
// --------------------------------------------------

/// Human-readable failure message (always non-empty for Err values returned
/// by jpeg_parse).
/// Complexity: O(1).
pub fn jpeg_error_message(e: &JpegError) -> Str {
  let m: Str = e.message;
  return m;
}

/// Absolute byte offset the failure refers to (always >= 0 for Err values
/// returned by jpeg_parse).
/// Complexity: O(1).
pub fn jpeg_error_offset(e: &JpegError) -> Int {
  return e.offset;
}
