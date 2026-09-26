// XIOM -- xiom.pcf: pure-XIOM X11 PCF bitmap-font codec subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// PCF (Portable Compiled Format) is the compiled bitmap-font format used by
// the X11 font system. This module implements a documented subset:
//
//   * file header: magic bytes 0x01 'f' 'c' 'p', a little-endian u32 table
//     count, then `count` 16-byte table entries (type, format, size, offset),
//     all u32 little-endian, table offsets absolute from the file start;
//   * the documented table types:
//       properties (1<<0), metrics (1<<1), bitmaps (1<<2), ink metrics
//       (1<<3), encodings (1<<4), swidths (1<<8), glyph names (1<<9),
//       BDF encodings (1<<10) and accelerators (1<<11).
//     metrics and bitmaps are required; encodings is parsed structurally when
//     present; every other table is preserved as a raw span (no properties,
//     glyph-name or accelerator semantics);
//   * metrics table: u32 count then `count` 12-byte records (left side
//     bearing i16, right side bearing i16, character width/advance i16,
//     ascent i16, descent i16, attributes u16) in format 0 (big-endian),
//     format 1 (little-endian) or format 2 (byte-mixed: count little-endian,
//     metric words big-endian). The historical compressed-metrics markers
//     0x00010000 and 0x00000100 are recognized and rejected;
//   * bitmaps table: u32 glyph count, per glyph a u32 metrics offset and a
//     u32 bitmap offset (both relative to their table), then per glyph a u32
//     padded size, then the bitmap bytes. Glyph rows are padded to 4 bytes;
//     the stored padded size is authoritative and only span-checked against
//     the table (see SPEC.md);
//   * encodings table: u16 minimum and u16 maximum encoding, a u16
//     first-pool index and a u16 count per glyph, then the flat u16 value
//     pool (every pooled value must lie within [minimum, maximum]).
//
// Everything is stored in flat parallel Vecs (no Vec of structs): the table
// directory, the per-glyph metrics, the per-glyph bitmap offsets/spans and
// the per-glyph encoding runs. See SPEC.md for the exact layouts, the
// validation order, the error catalog and the documented limitations
// (compression is out of scope; no rendering).
//
// v0.61.3 notes that shaped this module:
//   * free functions only; state travels by reference.
//   * all Ok/Err construction is confined to the leaf helpers below.
//   * every raw byte widens through `(b as Int) & 0xFF`; no shifts and no
//     bit tests are used anywhere (documented table-type constants are plain
//     Ints).
//   * typed locals are bound before every Vec element read.
//   * the per-glyph vectors are filled in lockstep with the glyph count.

module xiom.pcf

// --------------------------------------------------
//  Documented table types (see SPEC.md)
// --------------------------------------------------

// Properties table type.
pub const PCF_TABLE_PROPERTIES: Int = 1;

// Metrics table type (required).
pub const PCF_TABLE_METRICS: Int = 2;

// Bitmaps table type (required).
pub const PCF_TABLE_BITMAPS: Int = 4;

// Ink metrics table type (optional, raw span).
pub const PCF_TABLE_INK_METRICS: Int = 8;

// Encodings table type (optional, parsed structurally).
pub const PCF_TABLE_ENCODINGS: Int = 16;

// Swidths table type (optional, raw span).
pub const PCF_TABLE_SWIDTHS: Int = 256;

// Glyph names table type (optional, raw span).
pub const PCF_TABLE_GLYPH_NAMES: Int = 512;

// BDF encodings table type (optional, raw span).
pub const PCF_TABLE_BDF_ENCODINGS: Int = 1024;

// Accelerators table type (optional, raw span).
pub const PCF_TABLE_ACCELERATORS: Int = 2048;

// --------------------------------------------------
//  Documented metrics formats (metrics table format field)
// --------------------------------------------------

// Metrics format 0: count and metric words big-endian.
pub const PCF_METRICS_FORMAT_BE: Int = 0;

// Metrics format 1: count and metric words little-endian.
pub const PCF_METRICS_FORMAT_LE: Int = 1;

// Metrics format 2: byte-mixed -- count little-endian, metric words
// big-endian.
pub const PCF_METRICS_FORMAT_MIXED: Int = 2;

// Compressed-metrics marker (0x00010000), recognized and rejected.
pub const PCF_COMPRESSED_METRICS_FORMAT: Int = 65536;

// Historical PCF compressed-metrics marker (0x00000100), also recognized
// and rejected.
pub const PCF_LEGACY_COMPRESSED_FORMAT: Int = 256;

// --------------------------------------------------
//  Documented layout constants
// --------------------------------------------------

// Metrics table header size: the u32 glyph count.
pub const PCF_METRICS_HEADER_SIZE: Int = 4;

// Bytes per metrics record: five i16 fields plus one u16 field.
pub const PCF_METRIC_RECORD_SIZE: Int = 12;

// Bytes per bitmaps table per-glyph entry: metrics offset + bitmap offset.
pub const PCF_BITMAP_ENTRY_SIZE: Int = 8;

// Bitmaps table header size: the u32 glyph count.
pub const PCF_BITMAPS_HEADER_SIZE: Int = 4;

// Bitmaps table per-glyph padded-size field width.
pub const PCF_BITMAP_SPAN_SIZE: Int = 4;

// Glyph bitmap rows are padded to 4 bytes (documented; the stored padded
// size is the authority, see SPEC.md).
pub const PCF_ROW_PADDING: Int = 4;

// Smallest encodings table: u16 minimum + u16 maximum.
pub const PCF_ENCODINGS_HEADER_SIZE: Int = 4;

// Parsed PCF font index. The table directory is stored as four parallel
// vectors in file order; the per-glyph data is flattened into parallel
// vectors (metrics: six Ints per glyph; bitmaps: one span/offset per glyph;
// encodings: one run start/count per glyph plus one shared value pool).
// There is no Vec of structs anywhere. Fields are implementation details;
// callers should go through the free functions below.
pub type PcfFont = {
  table_types: Vec[Int];              // table type per directory entry
  table_formats: Vec[Int];            // table format field per entry
  table_offsets: Vec[Int];            // absolute file offset per entry
  table_sizes: Vec[Int];              // byte size per entry
  glyph_count: Int;                   // metrics/bitmaps glyph count
  metrics_format: Int;                // 0 (BE), 1 (LE) or 2 (mixed)
  metrics: Vec[Int];                  // 6 Ints per glyph, in glyph order
  bitmaps_table_offset: Int;          // absolute start of the bitmaps table
  bitmaps_table_size: Int;            // bitmaps table byte size
  bitmap_metrics_offsets: Vec[Int];   // per glyph: metrics-table-relative offset
  bitmap_offsets: Vec[Int];           // per glyph: bitmaps-table-relative offset
  bitmap_spans: Vec[Int];             // per glyph: padded bitmap size in bytes
  has_encodings: Bool;                // an encodings table was parsed
  encodings_table_offset: Int;        // absolute start (0 when absent)
  encodings_table_size: Int;          // byte size (0 when absent)
  encoding_min: Int;                  // lowest mapped encoding (0 when absent)
  encoding_max: Int;                  // highest mapped encoding (0 when absent)
  enc_starts: Vec[Int];               // per glyph: first pool index
  enc_counts: Vec[Int];               // per glyph: mapped encoding count
  enc_values: Vec[Int];               // flat encoding pool in glyph order
}

// --------------------------------------------------
//  Result leaf helpers (v0.61.3: Ok/Err construction is confined to fns
//  that return a Result directly, so fallible public fns return through
//  these).
// --------------------------------------------------

// Ok(v) for Result[PcfFont, Str].
fn _ok_font(v: PcfFont) -> Result[PcfFont, Str] { return Ok(v); }

// Err(m) for Result[PcfFont, Str].
fn _err_font(m: Str) -> Result[PcfFont, Str] { return Err(m); }

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] { return Err(m); }

// --------------------------------------------------
//  Byte readers (arithmetic only, no shifts or masks beyond the 0..255
//  widening)
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned little-endian u16 at `pos`; the caller guarantees pos + 2 <= len.
fn _le16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (data[pos] as Int) & 0xFF;
  let b1: Int = (data[pos + 1] as Int) & 0xFF;
  return b0 + b1 * 256;
}

// Unsigned big-endian u16 at `pos`; the caller guarantees pos + 2 <= len.
fn _be16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (data[pos] as Int) & 0xFF;
  let b1: Int = (data[pos + 1] as Int) & 0xFF;
  return b0 * 256 + b1;
}

// Unsigned little-endian u32 at `pos`; the caller guarantees pos + 4 <= len.
fn _le32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (data[pos] as Int) & 0xFF;
  let b1: Int = (data[pos + 1] as Int) & 0xFF;
  let b2: Int = (data[pos + 2] as Int) & 0xFF;
  let b3: Int = (data[pos + 3] as Int) & 0xFF;
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Unsigned big-endian u32 at `pos`; the caller guarantees pos + 4 <= len.
fn _be32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (data[pos] as Int) & 0xFF;
  let b1: Int = (data[pos + 1] as Int) & 0xFF;
  let b2: Int = (data[pos + 2] as Int) & 0xFF;
  let b3: Int = (data[pos + 3] as Int) & 0xFF;
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// u16 at `pos` in the requested word order (`msb_first` true = big-endian).
fn _word(data: &Vec[UInt8], pos: Int, msb_first: Bool) -> Int {
  if msb_first { return _be16(data, pos); }
  return _le16(data, pos);
}

// u32 at `pos` in the requested word order (`msb_first` true = big-endian).
fn _long(data: &Vec[UInt8], pos: Int, msb_first: Bool) -> Int {
  if msb_first { return _be32(data, pos); }
  return _le32(data, pos);
}

// Signed value of a u16 bit pattern (0..65535): 32768..65535 map to
// -32768..-1.
fn _signed16(v: Int) -> Int {
  if v >= 32768 { return v - 65536; }
  return v;
}

// --------------------------------------------------
//  Internal directory helpers
// --------------------------------------------------

// First index in `types` equal to `want`, or -1 when absent.
fn _find_table(types: &Vec[Int], want: Int) -> Int {
  var i = 0;
  while i < types.len() {
    let t: Int = types[i];
    if t == want { return i; }
    i = i + 1;
  }
  return -1;
}

// Copy the raw byte span [off, off + size) out of `data` as a fresh vector.
// The caller has already validated the span against the parse buffer; this
// re-checks against the supplied buffer and reports "pcf: table out of
// bounds" when it does not fit.
fn _copy_span(data: &Vec[UInt8], off: Int, size: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 { return _err_bytes("pcf: table out of bounds"); }
  if size < 0 { return _err_bytes("pcf: table out of bounds"); }
  if off > data.len() { return _err_bytes("pcf: table out of bounds"); }
  if size > data.len() - off { return _err_bytes("pcf: table out of bounds"); }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse and validate a PCF buffer into a flat PcfFont index.
///
/// Validation order (see SPEC.md):
///   1. buffer length >= 8 and the magic bytes 0x01 'f' 'c' 'p';
///   2. table count fits the remaining bytes (16 bytes per entry);
///   3. every table offset/size lies inside the buffer;
///   4. a metrics table is present; its format is 0, 1 or 2 (the compressed
///      markers 0x00010000 and 0x00000100 are rejected with their own
///      message); its size is exactly 4 + 12*count and every record parses;
///   5. a bitmaps table is present; its glyph count equals the metrics
///      count; its size holds the offset pairs and padded sizes; every
///      metrics offset is the glyph's canonical record offset; every bitmap
///      offset/span lies inside the bitmap data area;
///   6. when an encodings table is present: size fits the documented layout,
///      minimum <= maximum, every run fits the value pool and every pooled
///      value lies inside [minimum, maximum].
///
/// When a documented type appears more than once the first occurrence is the
/// one indexed for structured parsing (duplicates stay in the directory).
/// Unknown table types are accepted and preserved as raw spans. On error no
/// partial index is returned.
/// Complexity: O(tables + glyphs + pooled encodings).
pub fn pcf_parse(data: &Vec[UInt8]) -> Result[PcfFont, Str] {
  let n = data.len();
  if n < 8 { return _err_font("pcf: truncated header"); }
  let m0: Int = (data[0] as Int) & 0xFF;
  let m1: Int = (data[1] as Int) & 0xFF;
  let m2: Int = (data[2] as Int) & 0xFF;
  let m3: Int = (data[3] as Int) & 0xFF;
  if m0 != 1 { return _err_font("pcf: bad magic"); }
  if m1 != 102 { return _err_font("pcf: bad magic"); }
  if m2 != 99 { return _err_font("pcf: bad magic"); }
  if m3 != 112 { return _err_font("pcf: bad magic"); }
  let tcount = _le32(data, 4);
  if tcount > (n - 8) / 16 { return _err_font("pcf: truncated table directory"); }
  var table_types = Vec[Int].new();
  var table_formats = Vec[Int].new();
  var table_offsets = Vec[Int].new();
  var table_sizes = Vec[Int].new();
  var i = 0;
  while i < tcount {
    let entry = 8 + i * 16;
    let ttype = _le32(data, entry);
    let tformat = _le32(data, entry + 4);
    let tsize = _le32(data, entry + 8);
    let toff = _le32(data, entry + 12);
    if toff > n { return _err_font("pcf: table out of bounds"); }
    if tsize > n - toff { return _err_font("pcf: table out of bounds"); }
    table_types.push(ttype);
    table_formats.push(tformat);
    table_offsets.push(toff);
    table_sizes.push(tsize);
    i = i + 1;
  }
  // Required metrics table: first occurrence wins.
  let mi = _find_table(&table_types, PCF_TABLE_METRICS);
  if mi < 0 { return _err_font("pcf: missing metrics table"); }
  let moff: Int = table_offsets[mi];
  let msize: Int = table_sizes[mi];
  let mformat: Int = table_formats[mi];
  if mformat == PCF_COMPRESSED_METRICS_FORMAT { return _err_font("pcf: compressed metrics unsupported"); }
  if mformat == PCF_LEGACY_COMPRESSED_FORMAT { return _err_font("pcf: compressed metrics unsupported"); }
  if mformat != PCF_METRICS_FORMAT_BE {
    if mformat != PCF_METRICS_FORMAT_LE {
      if mformat != PCF_METRICS_FORMAT_MIXED { return _err_font("pcf: unsupported metrics format"); }
    }
  }
  if msize < PCF_METRICS_HEADER_SIZE { return _err_font("pcf: bad metrics table size"); }
  let count_msb: Bool = (mformat == PCF_METRICS_FORMAT_BE);
  let words_msb: Bool = (mformat != PCF_METRICS_FORMAT_LE);
  let glyph_count = _long(data, moff, count_msb);
  if msize != PCF_METRICS_HEADER_SIZE + PCF_METRIC_RECORD_SIZE * glyph_count {
    return _err_font("pcf: bad metrics table size");
  }
  var metrics = Vec[Int].new();
  var g = 0;
  while g < glyph_count {
    let rec = moff + PCF_METRICS_HEADER_SIZE + PCF_METRIC_RECORD_SIZE * g;
    let lsb = _word(data, rec, words_msb);
    let rsb = _word(data, rec + 2, words_msb);
    let advance = _word(data, rec + 4, words_msb);
    let ascent = _word(data, rec + 6, words_msb);
    let descent = _word(data, rec + 8, words_msb);
    let attributes = _word(data, rec + 10, words_msb);
    metrics.push(_signed16(lsb));
    metrics.push(_signed16(rsb));
    metrics.push(_signed16(advance));
    metrics.push(_signed16(ascent));
    metrics.push(_signed16(descent));
    metrics.push(attributes);
    g = g + 1;
  }
  // Required bitmaps table.
  let bi = _find_table(&table_types, PCF_TABLE_BITMAPS);
  if bi < 0 { return _err_font("pcf: missing bitmaps table"); }
  let boff: Int = table_offsets[bi];
  let bsize: Int = table_sizes[bi];
  if bsize < PCF_BITMAPS_HEADER_SIZE { return _err_font("pcf: bad bitmaps table size"); }
  let bcount = _le32(data, boff);
  if bcount != glyph_count { return _err_font("pcf: glyph count mismatch"); }
  let data_start = PCF_BITMAPS_HEADER_SIZE + (PCF_BITMAP_ENTRY_SIZE + PCF_BITMAP_SPAN_SIZE) * bcount;
  if bsize < data_start { return _err_font("pcf: bad bitmaps table size"); }
  var bitmap_metrics_offsets = Vec[Int].new();
  var bitmap_offsets = Vec[Int].new();
  var bitmap_spans = Vec[Int].new();
  var g2 = 0;
  while g2 < bcount {
    let mo = _le32(data, boff + PCF_BITMAPS_HEADER_SIZE + PCF_BITMAP_ENTRY_SIZE * g2);
    let bo = _le32(data, boff + PCF_BITMAPS_HEADER_SIZE + PCF_BITMAP_ENTRY_SIZE * g2 + 4);
    let span = _le32(data, boff + PCF_BITMAPS_HEADER_SIZE + PCF_BITMAP_ENTRY_SIZE * bcount + PCF_BITMAP_SPAN_SIZE * g2);
    let canonical_mo = PCF_METRICS_HEADER_SIZE + PCF_METRIC_RECORD_SIZE * g2;
    if mo != canonical_mo { return _err_font("pcf: bad metrics offset"); }
    if bo < data_start { return _err_font("pcf: bitmap out of bounds"); }
    if bo > bsize { return _err_font("pcf: bitmap out of bounds"); }
    if span > bsize - bo { return _err_font("pcf: bitmap out of bounds"); }
    bitmap_metrics_offsets.push(mo);
    bitmap_offsets.push(bo);
    bitmap_spans.push(span);
    g2 = g2 + 1;
  }
  // Optional encodings table.
  var has_encodings: Bool = false;
  var eoff = 0;
  var esize = 0;
  var emin = 0;
  var emax = 0;
  var enc_starts = Vec[Int].new();
  var enc_counts = Vec[Int].new();
  var enc_values = Vec[Int].new();
  let ei = _find_table(&table_types, PCF_TABLE_ENCODINGS);
  if ei >= 0 {
    has_encodings = true;
    eoff = table_offsets[ei];
    esize = table_sizes[ei];
    let per_glyph = PCF_ENCODINGS_HEADER_SIZE + 4 * glyph_count;
    if esize < per_glyph { return _err_font("pcf: bad encodings table size"); }
    let rest = esize - per_glyph;
    if rest % 2 != 0 { return _err_font("pcf: bad encodings table size"); }
    let pool_len = rest / 2;
    if pool_len > 65536 { return _err_font("pcf: encodings pool too large"); }
    emin = _le16(data, eoff);
    emax = _le16(data, eoff + 2);
    if emin > emax { return _err_font("pcf: bad encoding range"); }
    var g3 = 0;
    while g3 < glyph_count {
      let first = _le16(data, eoff + PCF_ENCODINGS_HEADER_SIZE + 2 * g3);
      let run = _le16(data, eoff + PCF_ENCODINGS_HEADER_SIZE + 2 * glyph_count + 2 * g3);
      if run == 0 {
        if first != 0 { return _err_font("pcf: bad encoding run"); }
      }
      if first + run > pool_len { return _err_font("pcf: bad encoding run"); }
      enc_starts.push(first);
      enc_counts.push(run);
      g3 = g3 + 1;
    }
    let pool_start = eoff + per_glyph;
    var k = 0;
    while k < pool_len {
      let v = _le16(data, pool_start + 2 * k);
      if v < emin { return _err_font("pcf: encoding out of range"); }
      if v > emax { return _err_font("pcf: encoding out of range"); }
      enc_values.push(v);
      k = k + 1;
    }
  }
  let font = PcfFont{
    table_types: table_types;
    table_formats: table_formats;
    table_offsets: table_offsets;
    table_sizes: table_sizes;
    glyph_count: glyph_count;
    metrics_format: mformat;
    metrics: metrics;
    bitmaps_table_offset: boff;
    bitmaps_table_size: bsize;
    bitmap_metrics_offsets: bitmap_metrics_offsets;
    bitmap_offsets: bitmap_offsets;
    bitmap_spans: bitmap_spans;
    has_encodings: has_encodings;
    encodings_table_offset: eoff;
    encodings_table_size: esize;
    encoding_min: emin;
    encoding_max: emax;
    enc_starts: enc_starts;
    enc_counts: enc_counts;
    enc_values: enc_values;
  };
  return _ok_font(font);
}

// --------------------------------------------------
//  Table-directory accessors
// --------------------------------------------------

/// Number of table entries in the directory.
/// Complexity: O(1).
pub fn pcf_table_count(p: &PcfFont) -> Int {
  return p.table_types.len();
}

/// Type of table entry `i`, or -1 when `i` is outside
/// 0..pcf_table_count(p)-1.
/// Complexity: O(1).
pub fn pcf_table_type(p: &PcfFont, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= p.table_types.len() { return -1; }
  let v: Int = p.table_types[i];
  return v;
}

/// Format field of table entry `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pcf_table_format(p: &PcfFont, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= p.table_formats.len() { return -1; }
  let v: Int = p.table_formats[i];
  return v;
}

/// Absolute file offset of table entry `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pcf_table_offset(p: &PcfFont, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= p.table_offsets.len() { return -1; }
  let v: Int = p.table_offsets[i];
  return v;
}

/// Byte size of table entry `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pcf_table_size(p: &PcfFont, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= p.table_sizes.len() { return -1; }
  let v: Int = p.table_sizes[i];
  return v;
}

/// Index of the first table entry whose type equals `ttype`, or -1 when no
/// entry matches (duplicate types keep the first occurrence).
/// Complexity: O(tables).
pub fn pcf_table_find(p: &PcfFont, ttype: Int) -> Int {
  let types: Vec[Int] = p.table_types;
  return _find_table(&types, ttype);
}

/// True when at least one table entry has type `ttype`.
/// Complexity: O(tables).
pub fn pcf_has_table(p: &PcfFont, ttype: Int) -> Bool {
  let i = pcf_table_find(p, ttype);
  return i >= 0;
}

/// Copy the raw bytes of the first table with type `ttype` out of `data`.
///
/// Err("pcf: no such table") when no entry has that type; Err("pcf: table
/// out of bounds") when the recorded span does not fit `data` (a forged or
/// stale index, or a shorter buffer than the one that was parsed).
/// Complexity: O(table size).
pub fn pcf_table_raw(data: &Vec[UInt8], p: &PcfFont, ttype: Int) -> Result[Vec[UInt8], Str] {
  let i = pcf_table_find(p, ttype);
  if i < 0 { return _err_bytes("pcf: no such table"); }
  let off: Int = p.table_offsets[i];
  let size: Int = p.table_sizes[i];
  return _copy_span(data, off, size);
}

// --------------------------------------------------
//  Metrics accessors
// --------------------------------------------------

/// Glyph count of the font (the metrics/bitmaps table count).
/// Complexity: O(1).
pub fn pcf_glyph_count(p: &PcfFont) -> Int {
  return p.glyph_count;
}

/// Metrics format of the parsed font: 0 (big-endian), 1 (little-endian) or
/// 2 (byte-mixed).
/// Complexity: O(1).
pub fn pcf_metrics_format(p: &PcfFont) -> Int {
  return p.metrics_format;
}

// Value of metric field `field` (0..5) for glyph `g`, or 0 when `g` is
// outside 0..pcf_glyph_count(p)-1. Internal; the public accessors name the
// fields.
fn _metric_field(p: &PcfFont, g: Int, field: Int) -> Int {
  if g < 0 { return 0; }
  if g >= p.glyph_count { return 0; }
  if field < 0 { return 0; }
  if field > 5 { return 0; }
  let v: Int = p.metrics[g * 6 + field];
  return v;
}

/// Left side bearing of glyph `g` (signed i16); 0 when `g` is out of range
/// (use pcf_metrics_at for an error channel).
/// Complexity: O(1).
pub fn pcf_metric_lsb(p: &PcfFont, g: Int) -> Int {
  return _metric_field(p, g, 0);
}

/// Right side bearing of glyph `g` (signed i16); 0 when `g` is out of range.
/// Complexity: O(1).
pub fn pcf_metric_rsb(p: &PcfFont, g: Int) -> Int {
  return _metric_field(p, g, 1);
}

/// Character width / advance of glyph `g` (signed i16); 0 when `g` is out of
/// range.
/// Complexity: O(1).
pub fn pcf_metric_advance(p: &PcfFont, g: Int) -> Int {
  return _metric_field(p, g, 2);
}

/// Ascent of glyph `g` (signed i16); 0 when `g` is out of range.
/// Complexity: O(1).
pub fn pcf_metric_ascent(p: &PcfFont, g: Int) -> Int {
  return _metric_field(p, g, 3);
}

/// Descent of glyph `g` (signed i16); 0 when `g` is out of range.
/// Complexity: O(1).
pub fn pcf_metric_descent(p: &PcfFont, g: Int) -> Int {
  return _metric_field(p, g, 4);
}

/// Attributes of glyph `g` (unsigned u16, 0..65535); 0 when `g` is out of
/// range.
/// Complexity: O(1).
pub fn pcf_metric_attributes(p: &PcfFont, g: Int) -> Int {
  return _metric_field(p, g, 5);
}

/// Copy the six metric fields of glyph `g` as
/// [left side bearing, right side bearing, advance, ascent, descent,
/// attributes] (the first five sign-extended, attributes unsigned).
///
/// Err("pcf: index out of range") when `g` is outside
/// 0..pcf_glyph_count(p)-1.
/// Complexity: O(1).
pub fn pcf_metrics_at(p: &PcfFont, g: Int) -> Result[Vec[Int], Str] {
  if g < 0 { return _err_ints("pcf: index out of range"); }
  if g >= p.glyph_count { return _err_ints("pcf: index out of range"); }
  var out = Vec[Int].new();
  var f = 0;
  while f < 6 {
    let v: Int = p.metrics[g * 6 + f];
    out.push(v);
    f = f + 1;
  }
  return _ok_ints(out);
}

// --------------------------------------------------
//  Bitmap accessors
// --------------------------------------------------

/// Padded bitmap size in bytes of glyph `g`, or -1 when `g` is outside
/// 0..pcf_glyph_count(p)-1. The stored padded size is authoritative (glyph
/// rows are documented to be padded to 4 bytes).
/// Complexity: O(1).
pub fn pcf_bitmap_span(p: &PcfFont, g: Int) -> Int {
  if g < 0 { return -1; }
  if g >= p.glyph_count { return -1; }
  let v: Int = p.bitmap_spans[g];
  return v;
}

/// Bitmaps-table-relative byte offset of glyph `g`'s bitmap bytes, or -1
/// when `g` is out of range.
/// Complexity: O(1).
pub fn pcf_bitmap_raw_offset(p: &PcfFont, g: Int) -> Int {
  if g < 0 { return -1; }
  if g >= p.glyph_count { return -1; }
  let v: Int = p.bitmap_offsets[g];
  return v;
}

/// Metrics-table-relative byte offset of glyph `g`'s 12-byte metric record
/// (the canonical 4 + 12*g value validated at parse time), or -1 when `g` is
/// out of range.
/// Complexity: O(1).
pub fn pcf_glyph_metrics_offset(p: &PcfFont, g: Int) -> Int {
  if g < 0 { return -1; }
  if g >= p.glyph_count { return -1; }
  let v: Int = p.bitmap_metrics_offsets[g];
  return v;
}

/// Total number of bitmap bytes stored in the bitmaps table's data area
/// (after the glyph count, offset pairs and padded sizes), including row
/// padding.
/// Complexity: O(1).
pub fn pcf_bitmap_size(p: &PcfFont) -> Int {
  return p.bitmaps_table_size - (PCF_BITMAPS_HEADER_SIZE + (PCF_BITMAP_ENTRY_SIZE + PCF_BITMAP_SPAN_SIZE) * p.glyph_count);
}

/// Copy glyph `g`'s padded bitmap bytes out of `data`, verbatim.
///
/// Err("pcf: index out of range") when `g` is outside
/// 0..pcf_glyph_count(p)-1; Err("pcf: bitmap bytes out of bounds") when the
/// recorded span does not fit `data`.
/// Complexity: O(span).
pub fn pcf_bitmap_bytes(data: &Vec[UInt8], p: &PcfFont, g: Int) -> Result[Vec[UInt8], Str] {
  if g < 0 { return _err_bytes("pcf: index out of range"); }
  if g >= p.glyph_count { return _err_bytes("pcf: index out of range"); }
  let rel: Int = p.bitmap_offsets[g];
  let span: Int = p.bitmap_spans[g];
  let off = p.bitmaps_table_offset + rel;
  if off < 0 { return _err_bytes("pcf: bitmap bytes out of bounds"); }
  if span < 0 { return _err_bytes("pcf: bitmap bytes out of bounds"); }
  if off > data.len() { return _err_bytes("pcf: bitmap bytes out of bounds"); }
  if span > data.len() - off { return _err_bytes("pcf: bitmap bytes out of bounds"); }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < span {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Encoding accessors
// --------------------------------------------------

/// True when the font carried an encodings table.
/// Complexity: O(1).
pub fn pcf_has_encodings(p: &PcfFont) -> Bool {
  return p.has_encodings;
}

/// Lowest mapped encoding of the encodings table, or -1 when no encodings
/// table is present (encodings are unsigned, so -1 is unambiguous).
/// Complexity: O(1).
pub fn pcf_encoding_min(p: &PcfFont) -> Int {
  if !p.has_encodings { return -1; }
  return p.encoding_min;
}

/// Highest mapped encoding of the encodings table, or -1 when no encodings
/// table is present.
/// Complexity: O(1).
pub fn pcf_encoding_max(p: &PcfFont) -> Int {
  if !p.has_encodings { return -1; }
  return p.encoding_max;
}

// Number of encodings mapped to glyph `g`, or -1 when `g` is out of range.
fn _enc_count(p: &PcfFont, g: Int) -> Int {
  if g < 0 { return -1; }
  if g >= p.glyph_count { return -1; }
  let v: Int = p.enc_counts[g];
  return v;
}

/// Number of encodings mapped to glyph `g`: 0 when no encodings table is
/// present, and -1 when `g` is outside 0..pcf_glyph_count(p)-1.
/// Complexity: O(1).
pub fn pcf_encoding_count(p: &PcfFont, g: Int) -> Int {
  if !p.has_encodings { return 0; }
  return _enc_count(p, g);
}

/// The `i`-th encoding mapped to glyph `g`, or -1 when no encodings table is
/// present, when `g` or `i` is out of range, or when glyph `g` has fewer
/// than `i + 1` mappings. Encodings are unsigned u16 values, so -1 is
/// unambiguous.
/// Complexity: O(1).
pub fn pcf_encoding_at(p: &PcfFont, g: Int, i: Int) -> Int {
  if !p.has_encodings { return -1; }
  if i < 0 { return -1; }
  let c = _enc_count(p, g);
  if c < 0 { return -1; }
  if i >= c { return -1; }
  let start: Int = p.enc_starts[g];
  let v: Int = p.enc_values[start + i];
  return v;
}

/// Copy all encodings mapped to glyph `g`, in pool order.
///
/// Err("pcf: no encodings table") when the font has no encodings table;
/// Err("pcf: index out of range") when `g` is outside
/// 0..pcf_glyph_count(p)-1.
/// Complexity: O(mappings).
pub fn pcf_encodings_at(p: &PcfFont, g: Int) -> Result[Vec[Int], Str] {
  if !p.has_encodings { return _err_ints("pcf: no encodings table"); }
  if g < 0 { return _err_ints("pcf: index out of range"); }
  if g >= p.glyph_count { return _err_ints("pcf: index out of range"); }
  let start: Int = p.enc_starts[g];
  let run: Int = p.enc_counts[g];
  var out = Vec[Int].new();
  var i = 0;
  while i < run {
    let v: Int = p.enc_values[start + i];
    out.push(v);
    i = i + 1;
  }
  return _ok_ints(out);
}

/// First glyph (lowest glyph index, then lowest pool position) mapped to
/// encoding `cp`, or -1 when no glyph maps it or no encodings table is
/// present.
///
/// This is the documented first-match rule: glyphs are scanned in index
/// order and each glyph's encodings in pool order; the first hit wins, so
/// duplicate mappings are tolerated. `cp` outside the table's documented
/// [minimum, maximum] range cannot match.
/// Complexity: O(total pooled encodings).
pub fn pcf_glyph_for_encoding(p: &PcfFont, cp: Int) -> Int {
  if !p.has_encodings { return -1; }
  if cp < p.encoding_min { return -1; }
  if cp > p.encoding_max { return -1; }
  var g = 0;
  while g < p.glyph_count {
    let start: Int = p.enc_starts[g];
    let run: Int = p.enc_counts[g];
    var i = 0;
    while i < run {
      let v: Int = p.enc_values[start + i];
      if v == cp { return g; }
      i = i + 1;
    }
    g = g + 1;
  }
  return -1;
}
