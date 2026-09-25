// XIOM -- xiom.woff: WOFF 1.0 font-container header and table directory codec
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.woff placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// WOFF 1.0 wraps an sfnt font in a simple container: a 44-byte header, a
// table directory of 20-byte entries, the font tables themselves (each
// optionally zlib compressed), an optional compressed metadata block and an
// optional private data block. This module is a structural codec for that
// container: woff_parse validates the header, the directory and the block
// layout and returns a flat Woff index (parallel Vecs, one slot per
// directory entry -- no Vec of structs, no methods); the accessors,
// woff_find_tag / woff_find_tag_str and the span copiers read that index;
// woff_build emits the canonical uncompressed layout.
//
// Deliberate scope boundaries (all pinned in SPEC.md):
//   * no zlib decompression and no recompression: a table whose compLength
//     is less than its origLength is kept raw and only flagged by
//     woff_table_is_compressed (compLength == origLength means stored
//     uncompressed); metadata bytes are likewise copied raw.
//   * no sfnt table parsing and no checksum verification: origChecksum is
//     exposed as a number, never validated.
//   * WOFF2 is a different format with a different header; "wOF2" does not
//     match "wOFF" and is rejected as a bad signature.
//   * the declared length must equal the buffer length, so trailing bytes
//     (and truncation) are rejected as "woff: length mismatch".
//   * spans must be in bounds, 4-byte aligned and non-overlapping, but
//     extraneous bytes between table spans are tolerated (no gap-free
//     layout check) and directory entries need not be sorted by tag; tags
//     may repeat and woff_find_tag returns the first match.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * all Ok/Err construction is confined to the leaf helpers below
//     (constructing a Result with a struct payload elsewhere miscompiles).
//   * all multi-byte fields are read/written arithmetically (modulo and
//     division) and every raw byte widens through `(x as Int) & 0xFF`;
//     `& 0xFF` on values with bit 31 set miscompiles in this compiler.
//   * the parallel Vecs of Woff are only ever appended in lockstep.
//   * Str comparisons go through string.str_compare, never `==`.

module xiom.woff

use xiom.string;

/// Parsed WOFF 1.0 container index. The 44-byte header fields are scalars;
/// the table directory is held in five parallel Vecs with one slot per
/// directory entry, in file order (no Vec of structs). Fields are
/// implementation details; callers should go through the free functions
/// below.
pub type Woff = {
  flavor: Int;            // sfnt version of the wrapped font (0..4294967295)
  length: Int;            // declared file size; equals the parsed buffer
  total_sfnt_size: Int;   // 12 + 16*numTables + padded origLengths
  major_version: Int;     // WOFF major version (0..65535)
  minor_version: Int;     // WOFF minor version (0..65535)
  meta_offset: Int;       // metadata block offset, 0 when absent
  meta_length: Int;       // compressed metadata length, 0 when absent
  meta_orig_length: Int;  // uncompressed metadata length (never verified)
  priv_offset: Int;       // private data offset, 0 when absent
  priv_length: Int;       // private data length, 0 when absent
  tags: Vec[Int];         // one 4-byte tag per entry, big-endian Int
  offsets: Vec[Int];      // file offset of each entry's data
  comp_lengths: Vec[Int]; // stored length (compressed bytes or raw bytes)
  orig_lengths: Vec[Int]; // uncompressed length
  checksums: Vec[Int];    // sfnt checksum, exposed but never verified
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Woff, Str].
fn _ok_woff(v: Woff) -> Result[Woff, Str] {
  return Ok(v);
}

// Err(m) for Result[Woff, Str].
fn _err_woff(m: Str) -> Result[Woff, Str] {
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

// --------------------------------------------------
//  Byte readers and writers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian Int of the `size` bytes at `pos`. The caller
// guarantees pos + size <= data.len().
fn _read_be(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < size {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3, and this form is exact for negative two's-complement values.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append the four signature bytes "wOFF" (0x77 0x4F 0x46 0x46).
fn _push_signature(out: &mut Vec[UInt8]) {
  out.push(119 as UInt8); // 'w'
  out.push(79 as UInt8);  // 'O'
  out.push(70 as UInt8);  // 'F'
  out.push(70 as UInt8);  // 'F'
}

// True when the first four bytes are the WOFF magic "wOFF".
fn _signature_is(data: &Vec[UInt8]) -> Bool {
  if _byte(data, 0) != 119 { return false; }
  if _byte(data, 1) != 79 { return false; }
  if _byte(data, 2) != 70 { return false; }
  if _byte(data, 3) != 70 { return false; }
  return true;
}

// --------------------------------------------------
//  Tags and alignment
// --------------------------------------------------

// A 4-printable-ASCII tag as a big-endian Int, or -1 when `s` is not
// exactly four bytes in 0x20..0x7E (e.g. "glyf", "OS/2").
fn _tag_of(s: Str) -> Int {
  if s.len() != 4 { return -1; }
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 32 || b > 126 { return -1; }
    v = v * 256 + b;
    i = i + 1;
  }
  return v;
}

// True when `tag` is a value in 0..4294967295 whose four bytes are all in
// 0x20..0x7E.
fn _tag_ok(tag: Int) -> Bool {
  if tag < 0 { return false; }
  if tag > 4294967295 { return false; }
  var v = tag;
  var i = 0;
  while i < 4 {
    let b = v % 256;
    if b < 32 || b > 126 { return false; }
    v = (v - b) / 256;
    i = i + 1;
  }
  return true;
}

// Smallest multiple of 4 that is >= v (v >= 0). Exact because the
// numerator is non-negative: integer division truncates toward zero.
fn _align4(v: Int) -> Int {
  return ((v + 3) / 4) * 4;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// The documented cap on the table count: 4096 entries. It bounds the
/// 44 + 20*numTables directory arithmetic and the O(entries^2) overlap
/// scan; real fonts carry a few dozen tables.
pub fn woff_max_tables() -> Int {
  return 4096;
}

/// Parse and validate a complete WOFF 1.0 container.
///
/// The buffer must be exactly the declared file: the header `length` field
/// must equal data.len(), so both truncated buffers and trailing bytes are
/// "woff: length mismatch". Directory entries are validated in file order
/// (tag ASCII, compLength <= origLength, zero compLength only with zero
/// origLength, 4-byte-aligned offsets, in-bounds spans), then the
/// totalSfntSize formula, then pairwise table overlap, then the metadata
/// and private blocks (alignment, bounds, overlap with tables and with each
/// other). See SPEC.md for the exact check order and the full error
/// catalog. On error no partial index is returned.
/// Complexity: O(numTables^2) worst case, bounded by woff_max_tables().
pub fn woff_parse(data: &Vec[UInt8]) -> Result[Woff, Str] {
  let n = data.len();
  if n < 44 { return _err_woff("woff: truncated header"); }
  if !_signature_is(data) { return _err_woff("woff: bad signature"); }
  let length = _read_be(data, 8, 4);
  if length != n { return _err_woff("woff: length mismatch"); }
  let num_tables = _read_be(data, 12, 2);
  let reserved = _read_be(data, 14, 2);
  if reserved != 0 { return _err_woff("woff: nonzero reserved"); }
  if num_tables > woff_max_tables() { return _err_woff("woff: too many tables"); }
  let dir_end = 44 + num_tables * 20;
  if dir_end > n { return _err_woff("woff: truncated directory"); }
  var tags = Vec[Int].new();
  var offsets = Vec[Int].new();
  var comp_lengths = Vec[Int].new();
  var orig_lengths = Vec[Int].new();
  var checksums = Vec[Int].new();
  var i = 0;
  while i < num_tables {
    let base = 44 + i * 20;
    let tag = _read_be(data, base, 4);
    if !_tag_ok(tag) { return _err_woff("woff: invalid table tag"); }
    let off = _read_be(data, base + 4, 4);
    let comp = _read_be(data, base + 8, 4);
    let orig = _read_be(data, base + 12, 4);
    let csum = _read_be(data, base + 16, 4);
    if comp > orig { return _err_woff("woff: compressed length exceeds original"); }
    if comp == 0 && orig > 0 { return _err_woff("woff: zero compLength with nonzero origLength"); }
    if off % 4 != 0 { return _err_woff("woff: unaligned table offset"); }
    if off < dir_end || off > n { return _err_woff("woff: table offset out of range"); }
    if comp > n - off { return _err_woff("woff: table data out of bounds"); }
    tags.push(tag);
    offsets.push(off);
    comp_lengths.push(comp);
    orig_lengths.push(orig);
    checksums.push(csum);
    i = i + 1;
  }
  var expect: Int = 12 + 16 * num_tables;
  i = 0;
  while i < num_tables {
    let olen: Int = orig_lengths[i];
    expect = expect + _align4(olen);
    i = i + 1;
  }
  let total = _read_be(data, 16, 4);
  if total != expect { return _err_woff("woff: bad total sfnt size"); }
  i = 0;
  while i < num_tables {
    let alen: Int = comp_lengths[i];
    if alen > 0 {
      let aoff: Int = offsets[i];
      var j = i + 1;
      while j < num_tables {
        let blen: Int = comp_lengths[j];
        if blen > 0 {
          let boff: Int = offsets[j];
          if aoff < boff + blen && boff < aoff + alen {
            return _err_woff("woff: overlapping tables");
          }
        }
        j = j + 1;
      }
    }
    i = i + 1;
  }
  let meta_offset = _read_be(data, 24, 4);
  let meta_length = _read_be(data, 28, 4);
  let meta_orig = _read_be(data, 32, 4);
  if meta_length > 0 {
    if meta_offset % 4 != 0 { return _err_woff("woff: unaligned metadata offset"); }
    if meta_offset < dir_end || meta_offset > n { return _err_woff("woff: metadata out of bounds"); }
    if meta_length > n - meta_offset { return _err_woff("woff: metadata out of bounds"); }
    i = 0;
    while i < num_tables {
      let tlen: Int = comp_lengths[i];
      if tlen > 0 {
        let toff: Int = offsets[i];
        if meta_offset < toff + tlen && toff < meta_offset + meta_length {
          return _err_woff("woff: metadata overlaps table");
        }
      }
      i = i + 1;
    }
  }
  let priv_offset = _read_be(data, 36, 4);
  let priv_length = _read_be(data, 40, 4);
  if priv_length > 0 {
    if priv_offset % 4 != 0 { return _err_woff("woff: unaligned private offset"); }
    if priv_offset < dir_end || priv_offset > n { return _err_woff("woff: private data out of bounds"); }
    if priv_length > n - priv_offset { return _err_woff("woff: private data out of bounds"); }
    i = 0;
    while i < num_tables {
      let tlen: Int = comp_lengths[i];
      if tlen > 0 {
        let toff: Int = offsets[i];
        if priv_offset < toff + tlen && toff < priv_offset + priv_length {
          return _err_woff("woff: private data overlaps table");
        }
      }
      i = i + 1;
    }
  }
  if meta_length > 0 && priv_length > 0 {
    if meta_offset < priv_offset + priv_length && priv_offset < meta_offset + meta_length {
      return _err_woff("woff: metadata overlaps private data");
    }
  }
  let w = Woff{
    flavor: _read_be(data, 4, 4);
    length: length;
    total_sfnt_size: total;
    major_version: _read_be(data, 20, 2);
    minor_version: _read_be(data, 22, 2);
    meta_offset: meta_offset;
    meta_length: meta_length;
    meta_orig_length: meta_orig;
    priv_offset: priv_offset;
    priv_length: priv_length;
    tags: tags;
    offsets: offsets;
    comp_lengths: comp_lengths;
    orig_lengths: orig_lengths;
    checksums: checksums;
  };
  return _ok_woff(w);
}

// --------------------------------------------------
//  Header accessors
// --------------------------------------------------

/// The "sfnt version" of the wrapped font (0..4294967295): 0x00010000 for
/// TrueType outlines or the tag 'OTTO' for CFF outlines are common, but any
/// 32-bit value is accepted.
pub fn woff_flavor(w: &Woff) -> Int {
  return w.flavor;
}

/// Declared total file size; for a parsed container this equals the buffer
/// length (exact-length policy).
pub fn woff_length(w: &Woff) -> Int {
  return w.length;
}

/// Number of table directory entries.
pub fn woff_num_tables(w: &Woff) -> Int {
  return w.tags.len();
}

/// Total size needed for the uncompressed sfnt font: 12 + 16*numTables +
/// the 4-byte-padded origLength of every table. woff_parse validates the
/// header field against this formula.
pub fn woff_total_sfnt_size(w: &Woff) -> Int {
  return w.total_sfnt_size;
}

/// WOFF major version field (0..65535); no behavior depends on it.
pub fn woff_major_version(w: &Woff) -> Int {
  return w.major_version;
}

/// WOFF minor version field (0..65535); no behavior depends on it.
pub fn woff_minor_version(w: &Woff) -> Int {
  return w.minor_version;
}

// --------------------------------------------------
//  Table directory accessors
// --------------------------------------------------

/// 4-byte tag of entry `i` as a big-endian Int, or -1 when `i` is outside
/// 0..woff_num_tables(w)-1.
pub fn woff_table_tag(w: &Woff, i: Int) -> Int {
  if i < 0 || i >= w.tags.len() { return -1; }
  return w.tags[i];
}

/// File offset of entry `i`'s data, or -1 when `i` is out of range. Every
/// parsed offset is 4-byte aligned.
pub fn woff_table_offset(w: &Woff, i: Int) -> Int {
  if i < 0 || i >= w.offsets.len() { return -1; }
  return w.offsets[i];
}

/// Stored length of entry `i` (compressed bytes when the entry is
/// compressed, otherwise the raw bytes), or -1 when `i` is out of range.
/// Padding is never included.
pub fn woff_table_comp_length(w: &Woff, i: Int) -> Int {
  if i < 0 || i >= w.comp_lengths.len() { return -1; }
  return w.comp_lengths[i];
}

/// Uncompressed length of entry `i`, or -1 when `i` is out of range.
pub fn woff_table_orig_length(w: &Woff, i: Int) -> Int {
  if i < 0 || i >= w.orig_lengths.len() { return -1; }
  return w.orig_lengths[i];
}

/// sfnt checksum of entry `i` (0..4294967295), or -1 when `i` is out of
/// range. Never verified: this codec does not parse sfnt tables.
pub fn woff_table_checksum(w: &Woff, i: Int) -> Int {
  if i < 0 || i >= w.checksums.len() { return -1; }
  return w.checksums[i];
}

/// The documented compression predicate: true when compLength < origLength,
/// i.e. the stored bytes are zlib data that this codec keeps raw. Equal
/// lengths mean the table is stored uncompressed, including the zero-length
/// case; false when `i` is out of range.
pub fn woff_table_is_compressed(w: &Woff, i: Int) -> Bool {
  if i < 0 || i >= w.tags.len() { return false; }
  let cl: Int = w.comp_lengths[i];
  let ol: Int = w.orig_lengths[i];
  return cl < ol;
}

/// Index of the first directory entry whose tag equals `tag` (a big-endian
/// Int such as woff_tag_of("glyf")), or -1 when no entry matches. Duplicate
/// tags are tolerated; the first match wins.
pub fn woff_find_tag(w: &Woff, tag: Int) -> Int {
  var i = 0;
  while i < w.tags.len() {
    let t: Int = w.tags[i];
    if t == tag { return i; }
    i = i + 1;
  }
  return -1;
}

/// woff_find_tag for a four-character tag string; -1 when `tag` is not four
/// printable-ASCII bytes or no entry matches.
pub fn woff_find_tag_str(w: &Woff, tag: Str) -> Int {
  return woff_find_tag(w, _tag_of(tag));
}

// --------------------------------------------------
//  Block accessors
// --------------------------------------------------

/// True when the container declares a metadata block (metaLength > 0).
pub fn woff_has_metadata(w: &Woff) -> Bool {
  return w.meta_length > 0;
}

/// True when the container declares a private data block (privLength > 0).
pub fn woff_has_private(w: &Woff) -> Bool {
  return w.priv_length > 0;
}

/// Metadata block offset in the parsed buffer, or 0 when absent. Validated
/// in bounds and 4-byte aligned when present.
pub fn woff_meta_offset(w: &Woff) -> Int {
  return w.meta_offset;
}

/// Compressed metadata length in bytes, or 0 when absent.
pub fn woff_meta_length(w: &Woff) -> Int {
  return w.meta_length;
}

/// Uncompressed metadata length from the header. Never verified: metadata
/// is zlib data this codec keeps raw.
pub fn woff_meta_orig_length(w: &Woff) -> Int {
  return w.meta_orig_length;
}

/// Private data block offset in the parsed buffer, or 0 when absent.
/// Validated in bounds and 4-byte aligned when present.
pub fn woff_priv_offset(w: &Woff) -> Int {
  return w.priv_offset;
}

/// Private data length in bytes, or 0 when absent.
pub fn woff_priv_length(w: &Woff) -> Int {
  return w.priv_length;
}

// --------------------------------------------------
//  Span copiers (raw bytes, no decompression)
// --------------------------------------------------

/// Copy entry `i`'s stored bytes (compLength of them) out of `data`,
/// verbatim. When woff_table_is_compressed is true these are the zlib
/// bytes, kept raw (this codec never inflates them).
///
/// Err("woff: index out of range") when `i` is outside the directory;
/// Err("woff: table data out of bounds") when the recorded span does not
/// fit `data` (forged or stale index).
/// Complexity: O(compLength).
pub fn woff_table_data(data: &Vec[UInt8], w: &Woff, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= w.tags.len() { return _err_bytes("woff: index out of range"); }
  let off: Int = w.offsets[i];
  let len: Int = w.comp_lengths[i];
  if off < 0 || len < 0 { return _err_bytes("woff: table data out of bounds"); }
  if off + len > data.len() { return _err_bytes("woff: table data out of bounds"); }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Copy the compressed metadata block out of `data`, verbatim (never
/// inflated). Err("woff: no metadata") when the container declares none;
/// Err("woff: metadata out of bounds") when the recorded span does not fit
/// `data`.
pub fn woff_meta_copy(data: &Vec[UInt8], w: &Woff) -> Result[Vec[UInt8], Str] {
  if w.meta_length <= 0 { return _err_bytes("woff: no metadata"); }
  let off: Int = w.meta_offset;
  let len: Int = w.meta_length;
  if off < 0 { return _err_bytes("woff: metadata out of bounds"); }
  if off + len > data.len() { return _err_bytes("woff: metadata out of bounds"); }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Copy the private data block out of `data`, verbatim. Err("woff: no
/// private data") when the container declares none; Err("woff: private
/// data out of bounds") when the recorded span does not fit `data`.
pub fn woff_priv_copy(data: &Vec[UInt8], w: &Woff) -> Result[Vec[UInt8], Str] {
  if w.priv_length <= 0 { return _err_bytes("woff: no private data"); }
  let off: Int = w.priv_offset;
  let len: Int = w.priv_length;
  if off < 0 { return _err_bytes("woff: private data out of bounds"); }
  if off + len > data.len() { return _err_bytes("woff: private data out of bounds"); }
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

/// Build the canonical uncompressed WOFF 1.0 layout: the 44-byte header
/// (signature "wOFF", the supplied flavor, exact length, the table count,
/// reserved 0, the computed totalSfntSize, majorVersion/minorVersion 0, and
/// zero metadata/private fields), then one 20-byte directory entry per
/// table in the given order (tag, 4-byte-aligned offset, compLength =
/// origLength = the data length, the supplied checksum), then every table's
/// bytes verbatim, each zero-padded to a 4-byte boundary.
///
/// Every table is stored uncompressed (compLength == origLength); callers
/// that need sorted tags supply them sorted, since entries are emitted in
/// the given order.
///
/// Params: flavor - sfnt version (0..4294967295);
///         tags - one 4-printable-ASCII-byte tag per table;
///         datas - one byte vector per table, in the same order;
///         checksums - one 0..4294967295 checksum per table.
/// Returns: Ok(bytes); zero tables yield the 44-byte header alone.
/// Error case: Err("woff: flavor out of range"); Err("woff: table vectors
/// length mismatch") when the three vectors differ in length;
/// Err("woff: too many tables") above woff_max_tables();
/// Err("woff: invalid table tag") for a tag whose bytes are not all in
/// 0x20..0x7E; Err("woff: checksum out of range"). Nothing is emitted
/// unless every check passes.
pub fn woff_build(flavor: Int, tags: &Vec[Int], datas: &Vec[Vec[UInt8]], checksums: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  if flavor < 0 || flavor > 4294967295 { return _err_bytes("woff: flavor out of range"); }
  let ntab = tags.len();
  if datas.len() != ntab { return _err_bytes("woff: table vectors length mismatch"); }
  if checksums.len() != ntab { return _err_bytes("woff: table vectors length mismatch"); }
  if ntab > woff_max_tables() { return _err_bytes("woff: too many tables"); }
  var i = 0;
  while i < ntab {
    let t: Int = tags[i];
    if !_tag_ok(t) { return _err_bytes("woff: invalid table tag"); }
    let c: Int = checksums[i];
    if c < 0 || c > 4294967295 { return _err_bytes("woff: checksum out of range"); }
    i = i + 1;
  }
  var sfnt: Int = 12 + 16 * ntab;
  var total: Int = 44 + 20 * ntab;
  i = 0;
  while i < ntab {
    let d: Vec[UInt8] = datas[i];
    let dl = d.len();
    sfnt = sfnt + _align4(dl);
    total = total + _align4(dl);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_signature(&mut out);
  _push_be(&mut out, flavor, 4);
  _push_be(&mut out, total, 4);
  _push_be(&mut out, ntab, 2);
  _push_be(&mut out, 0, 2);
  _push_be(&mut out, sfnt, 4);
  _push_be(&mut out, 0, 2);
  _push_be(&mut out, 0, 2);
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, 0, 4);
  var cursor: Int = 44 + 20 * ntab;
  i = 0;
  while i < ntab {
    let t: Int = tags[i];
    let d: Vec[UInt8] = datas[i];
    let c: Int = checksums[i];
    let dl = d.len();
    _push_be(&mut out, t, 4);
    _push_be(&mut out, cursor, 4);
    _push_be(&mut out, dl, 4);
    _push_be(&mut out, dl, 4);
    _push_be(&mut out, c, 4);
    cursor = cursor + _align4(dl);
    i = i + 1;
  }
  i = 0;
  while i < ntab {
    let d: Vec[UInt8] = datas[i];
    let dl = d.len();
    _push_bytes(&mut out, &d);
    var pad = _align4(dl) - dl;
    while pad > 0 {
      out.push(0 as UInt8);
      pad = pad - 1;
    }
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Map a four-character tag string to its big-endian Int, or -1 when `s` is
/// not exactly four bytes in 0x20..0x7E. The inverse direction is not
/// offered because this package never builds Str values from bytes.
pub fn woff_tag_of(s: Str) -> Int {
  return _tag_of(s);
}
