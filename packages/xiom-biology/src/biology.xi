// XIOM -- xiom.biology: FASTA and FASTQ sequence parsing
// Port task: replace the xiom.biology placeholder with a real, tested,
// pure-XIOM bioinformatics text codec: FASTA records (header + wrapped
// sequence, base composition, GC content), FASTQ records (multi-line
// sequence and quality, Phred+33/+64, quality statistics), one-record
// streaming with consumed byte counts, whole-buffer walking, and format
// auto-detection. See SPEC.md for the grammar, alphabet, quality math and
// error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: text in, plain values out. Every entry point is a free function; a
// record is a flat struct of scalars and Str fields, and a multi-record walk
// returns parallel vectors (a Vec of structs is unsupported on this
// compiler). Parsing is byte-oriented: strings are indexed with
// string.byte_at, every byte is widened to Int with an explicit `& 255`
// mask, and all arithmetic is 64-bit signed integer math. Line endings may
// be LF or CRLF; a lone CR is not a line terminator (SPEC.md section 2).
//
// Language notes (XIOM v0.61.3), same discipline as xiom.nmea /
// xiom.meteorology:
//   * free functions only: no self methods, no lambdas, no Vec[StructType];
//     variable-length data travels in parallel Vec fields with mirrored
//     pushes;
//   * Str equality always goes through xiom.string.compare.str_compare
//     (BUG 17: `==` on a Str read from a Vec[Str] element lowers to a
//     pointer comparison); Vec element reads bind a typed `let` first;
//   * Ok/Err are constructed only in the leaf helpers below (constructing a
//     Result inside a larger function miscompiles);
//   * `&mut Int` write-through is miscompiled: helpers return values in
//     small carrier structs instead of out-parameters;
//   * string builders never receive a 0x00 byte (sb_to_str miscompiles with
//     NUL): every byte is validated before it is pushed;
//   * no Vec[Float64]; GC content and Phred scores are scaled integers and
//     every division is truncating (documented at each site).

module xiom.biology

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;
use xiom.convert;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Format codes returned by bio_detect_format / bio_format.
pub const BIO_FORMAT_UNKNOWN: Int = 0;
/// FASTA: records introduced by '>'.
pub const BIO_FORMAT_FASTA: Int = 1;
/// FASTQ: records introduced by '@'.
pub const BIO_FORMAT_FASTQ: Int = 2;

/// Phred+33 quality encoding (Sanger / Illumina 1.8+); the FASTQ default.
pub const BIO_PHRED33: Int = 0;
/// Phred+64 quality encoding (Illumina 1.3+); opt-in via the *_enc entry
/// points.
pub const BIO_PHRED64: Int = 1;

// ---------------------------------------------------------------------------
// Internal byte constants (ASCII values as Int; never UInt8 >= 128)
// ---------------------------------------------------------------------------

const _B_LF: Int = 10;
const _B_TAB: Int = 9;
const _B_CR: Int = 13;
const _B_SPACE: Int = 32;
const _B_PLUS: Int = 43;
const _B_GT: Int = 62;
const _B_AT: Int = 64;
const _B_A: Int = 65;
const _B_B: Int = 66;
const _B_C: Int = 67;
const _B_D: Int = 68;
const _B_G: Int = 71;
const _B_H: Int = 72;
const _B_K: Int = 75;
const _B_M: Int = 77;
const _B_N: Int = 78;
const _B_R: Int = 82;
const _B_S: Int = 83;
const _B_T: Int = 84;
const _B_U: Int = 85;
const _B_V: Int = 86;
const _B_W: Int = 87;
const _B_Y: Int = 89;
const _B_LOWER_A: Int = 97;
const _B_LOWER_Z: Int = 122;
const _B_Q_MIN: Int = 33;
const _B_Q_MAX: Int = 126;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// One parsed FASTA or FASTQ record. `kind` is BIO_FORMAT_FASTA or
/// BIO_FORMAT_FASTQ. `id`/`description` come from the header line;
/// `sequence` is the whitespace-stripped sequence text with its original
/// case preserved. Base counts are case-insensitive six-bucket counts: U
/// and every ambiguity code (RYSWKMBDHV) land in `count_other`.
/// `gc_permille` is (C + G) * 1000 / length, truncated. Quality fields
/// apply to FASTQ records only: `has_quality` is false for FASTA, where
/// `encoding`, `qual_min`, `qual_max` and `qual_mean10` are -1.
/// `qual_mean10` is the mean Phred score in tenths, truncated.
/// `offset` is the byte offset of the record's leading marker and
/// `next_offset` the offset where the next record starts (or the input
/// length), so the consumed byte count is next_offset - offset.
pub type BioRecord = {
  kind: Int;
  id: Str;
  description: Str;
  sequence: Str;
  quality: Str;
  seq_len: Int;
  count_a: Int;
  count_c: Int;
  count_g: Int;
  count_t: Int;
  count_n: Int;
  count_other: Int;
  gc_permille: Int;
  has_quality: Bool;
  encoding: Int;
  qual_min: Int;
  qual_max: Int;
  qual_mean10: Int;
  offset: Int;
  next_offset: Int;
}

/// Case-insensitive six-bucket base composition. `total` is the sum of the
/// six buckets.
pub type BaseCounts = {
  total: Int;
  count_a: Int;
  count_c: Int;
  count_g: Int;
  count_t: Int;
  count_n: Int;
  count_other: Int;
}

/// A whole-buffer walk result: one entry per record, in walk order, stored
/// as parallel vectors that always have equal lengths. Fields are
/// implementation details; callers should go through the bio_batch_*
/// accessors below.
pub type BioBatch = {
  fmt: Int;
  count: Int;
  ids: Vec[Str];
  descriptions: Vec[Str];
  sequences: Vec[Str];
  qualities: Vec[Str];
  lengths: Vec[Int];
  count_a: Vec[Int];
  count_c: Vec[Int];
  count_g: Vec[Int];
  count_t: Vec[Int];
  count_n: Vec[Int];
  count_other: Vec[Int];
  gc_permille: Vec[Int];
  qual_min: Vec[Int];
  qual_max: Vec[Int];
  qual_mean10: Vec[Int];
  offsets: Vec[Int];
  next_offsets: Vec[Int];
}

// ---------------------------------------------------------------------------
// Internal carrier types (returned by the scanning helpers; `&mut Int`
// out-parameters are miscompiled, so scans return these values instead)
// ---------------------------------------------------------------------------

// One physical line: [from, content_end) is the line without its trailing
// CR/LF; next_line is the first byte after the terminator (or the input
// length on the last, unterminated line).
type _LineScan = {
  content_end: Int;
  next_line: Int;
  has_lf: Bool;
}

// A parsed header line (marker already consumed): id is the first
// whitespace-free run, description the rest of the line trimmed of
// surrounding whitespace.
type _HeaderScan = {
  ok: Bool;
  id_start: Int;
  id_end: Int;
  desc_start: Int;
  desc_end: Int;
  next_line: Int;
}

// ---------------------------------------------------------------------------
// Result leaf constructors (see the module header)
// ---------------------------------------------------------------------------

fn _ok_record(v: BioRecord) -> Result[BioRecord, Str] {
  return Ok(v);
}

fn _err_record(m: Str) -> Result[BioRecord, Str] {
  return Err(m);
}

fn _ok_counts(v: BaseCounts) -> Result[BaseCounts, Str] {
  return Ok(v);
}

fn _err_counts(m: Str) -> Result[BaseCounts, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_batch(v: BioBatch) -> Result[BioBatch, Str] {
  return Ok(v);
}

fn _err_batch(m: Str) -> Result[BioBatch, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

// Every error message has the shape "bio: <what> at record <rec> offset
// <off>".
fn _err_at(what: Str, rec: Int, off: Int) -> Str {
  return "bio: " + what + " at record " + convert.int_to_string(rec) + " offset " + convert.int_to_string(off);
}

fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Byte at pos widened to 0..255. The caller guarantees pos < len.
fn _at(s: Str, pos: Int) -> Int {
  let b: UInt8 = string.byte_at(s, pos);
  return (b as Int) & 255;
}

fn _is_space(b: Int) -> Bool {
  return b == _B_SPACE || b == _B_TAB;
}

// Whitespace allowed inside a line (CR is tolerated before its terminator).
fn _is_line_ws(b: Int) -> Bool {
  return _is_space(b) || b == _B_CR;
}

fn _is_any_ws(b: Int) -> Bool {
  return _is_line_ws(b) || b == _B_LF;
}

// First byte at or after `from` that is not whitespace; the input length
// when the tail is all whitespace.
fn _skip_ws(s: Str, from: Int) -> Int {
  let n = s.len();
  var i = from;
  while i < n {
    if !_is_any_ws(_at(s, i)) { return i; }
    i = i + 1;
  }
  return n;
}

// Scan one physical line starting at `from` (which must be < len unless the
// input is empty).
fn _line_at(s: Str, from: Int) -> _LineScan {
  let n = s.len();
  var i = from;
  while i < n {
    if _at(s, i) == _B_LF {
      var ce = i;
      if ce > from && _at(s, ce - 1) == _B_CR { ce = ce - 1; }
      return _LineScan{ content_end: ce; next_line: i + 1; has_lf: true };
    }
    i = i + 1;
  }
  var ce2 = n;
  if ce2 > from && _at(s, ce2 - 1) == _B_CR { ce2 = ce2 - 1; }
  return _LineScan{ content_end: ce2; next_line: n; has_lf: false };
}

// Parse the header that starts at marker_pos (the '>' or '@' byte). ok is
// false when the header has no id token.
fn _scan_header(s: Str, marker_pos: Int) -> _HeaderScan {
  let n = s.len();
  var r = _HeaderScan{ ok: false; id_start: marker_pos + 1; id_end: marker_pos + 1; desc_start: marker_pos + 1; desc_end: marker_pos + 1; next_line: n };
  let ln = _line_at(s, marker_pos + 1);
  r.next_line = ln.next_line;
  let a = marker_pos + 1;
  let b = ln.content_end;
  var i = a;
  while i < b {
    if _is_line_ws(_at(s, i)) { break; }
    i = i + 1;
  }
  if i == a { return r; }
  r.id_start = a;
  r.id_end = i;
  var d = i;
  while d < b {
    if !_is_line_ws(_at(s, d)) { break; }
    d = d + 1;
  }
  var e = b;
  while e > d {
    if !_is_line_ws(_at(s, e - 1)) { break; }
    e = e - 1;
  }
  r.desc_start = d;
  r.desc_end = e;
  r.ok = true;
  return r;
}

// ---------------------------------------------------------------------------
// Alphabet and quality math
// ---------------------------------------------------------------------------

// Six-bucket base classifier, case-insensitive: 0 = A, 1 = C, 2 = G,
// 3 = T, 4 = N, 5 = other (U plus the ambiguity codes RYSWKMBDHV); -1 for
// any byte outside the legal alphabet.
fn _base_bucket(b: Int) -> Int {
  var c = b;
  if c >= _B_LOWER_A && c <= _B_LOWER_Z { c = c - 32; }
  if c == _B_A { return 0; }
  if c == _B_C { return 1; }
  if c == _B_G { return 2; }
  if c == _B_T { return 3; }
  if c == _B_N { return 4; }
  if c == _B_U { return 5; }
  if c == _B_R { return 5; }
  if c == _B_Y { return 5; }
  if c == _B_S { return 5; }
  if c == _B_W { return 5; }
  if c == _B_K { return 5; }
  if c == _B_M { return 5; }
  if c == _B_B { return 5; }
  if c == _B_D { return 5; }
  if c == _B_H { return 5; }
  if c == _B_V { return 5; }
  return -1;
}

// GC content in per-mille: (C + G) * 1000 / total, truncated toward zero.
// 0 when total is 0.
fn _gc6(a: Int, c: Int, g: Int, t: Int, n: Int, other: Int) -> Int {
  let total = a + c + g + t + n + other;
  if total <= 0 { return 0; }
  return (c + g) * 1000 / total;
}

fn _mk_counts(a: Int, c: Int, g: Int, t: Int, n: Int, other: Int) -> BaseCounts {
  return BaseCounts{ total: a + c + g + t + n + other; count_a: a; count_c: c; count_g: g; count_t: t; count_n: n; count_other: other };
}

// Phred score of one quality byte, or -1 when the byte is outside the
// encoding's legal range. Phred+33 accepts ASCII 33..126 (Q 0..93);
// Phred+64 accepts ASCII 64..126 (Q 0..62).
fn _phred_value(b: Int, encoding: Int) -> Int {
  if b < _B_Q_MIN || b > _B_Q_MAX { return -1; }
  if encoding == BIO_PHRED33 { return b - 33; }
  if encoding == BIO_PHRED64 {
    if b < 64 { return -1; }
    return b - 64;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Record factories and accessors
// ---------------------------------------------------------------------------

fn _mk_record(kind: Int, id: Str, desc: Str, seq: Str, qual: Str, seq_len: Int, a: Int, c: Int, g: Int, t: Int, n: Int, other: Int, gc: Int, has_q: Bool, enc: Int, qmin: Int, qmax: Int, qmean10: Int, off: Int, next_off: Int) -> BioRecord {
  return BioRecord{ kind: kind; id: id; description: desc; sequence: seq; quality: qual; seq_len: seq_len; count_a: a; count_c: c; count_g: g; count_t: t; count_n: n; count_other: other; gc_permille: gc; has_quality: has_q; encoding: enc; qual_min: qmin; qual_max: qmax; qual_mean10: qmean10; offset: off; next_offset: next_off };
}

fn _mk_batch(fmt: Int) -> BioBatch {
  return BioBatch{ fmt: fmt; count: 0; ids: Vec[Str].new(); descriptions: Vec[Str].new(); sequences: Vec[Str].new(); qualities: Vec[Str].new(); lengths: Vec[Int].new(); count_a: Vec[Int].new(); count_c: Vec[Int].new(); count_g: Vec[Int].new(); count_t: Vec[Int].new(); count_n: Vec[Int].new(); count_other: Vec[Int].new(); gc_permille: Vec[Int].new(); qual_min: Vec[Int].new(); qual_max: Vec[Int].new(); qual_mean10: Vec[Int].new(); offsets: Vec[Int].new(); next_offsets: Vec[Int].new() };
}

/// Record id (the first whitespace-free token of the header line).
/// Returns: the id text; the empty string is impossible for Ok records.
/// Complexity: O(1).
pub fn bio_record_id(r: &BioRecord) -> Str {
  let v: Str = r.id;
  return v;
}

/// Record description (the header line after the id, trimmed).
/// Returns: the description text; "" when the header had no description.
/// Complexity: O(1).
pub fn bio_record_description(r: &BioRecord) -> Str {
  let v: Str = r.description;
  return v;
}

/// Whitespace-stripped sequence text, original case preserved.
/// Complexity: O(1).
pub fn bio_record_sequence(r: &BioRecord) -> Str {
  let v: Str = r.sequence;
  return v;
}

/// Raw quality text (FASTQ only; "" for FASTA records).
/// Complexity: O(1).
pub fn bio_record_quality(r: &BioRecord) -> Str {
  let v: Str = r.quality;
  return v;
}

/// Sequence bytes as a fresh Vec[UInt8] (ASCII values, same order and case
/// as bio_record_sequence).
/// Complexity: O(len).
pub fn bio_record_sequence_bytes(r: &BioRecord) -> Vec[UInt8] {
  let seq: Str = r.sequence;
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < seq.len() {
    let b: UInt8 = string.byte_at(seq, i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

/// Record kind: BIO_FORMAT_FASTA or BIO_FORMAT_FASTQ.
/// Complexity: O(1).
pub fn bio_record_kind(r: &BioRecord) -> Int {
  return r.kind;
}

/// Sequence length (number of letters after whitespace stripping).
/// Complexity: O(1).
pub fn bio_record_length(r: &BioRecord) -> Int {
  return r.seq_len;
}

/// GC content in per-mille, truncated; see bio_gc_permille.
/// Complexity: O(1).
pub fn bio_record_gc_permille(r: &BioRecord) -> Int {
  return r.gc_permille;
}

/// True for FASTQ records (quality statistics present).
/// Complexity: O(1).
pub fn bio_record_has_quality(r: &BioRecord) -> Bool {
  return r.has_quality;
}

/// Quality encoding: BIO_PHRED33, BIO_PHRED64, or -1 for FASTA records.
/// Complexity: O(1).
pub fn bio_record_encoding(r: &BioRecord) -> Int {
  return r.encoding;
}

/// Minimum Phred score; -1 when the record has no quality.
/// Complexity: O(1).
pub fn bio_record_qual_min(r: &BioRecord) -> Int {
  return r.qual_min;
}

/// Maximum Phred score; -1 when the record has no quality.
/// Complexity: O(1).
pub fn bio_record_qual_max(r: &BioRecord) -> Int {
  return r.qual_max;
}

/// Mean Phred score in tenths, truncated toward zero; -1 when the record
/// has no quality.
/// Complexity: O(1).
pub fn bio_record_qual_mean10(r: &BioRecord) -> Int {
  return r.qual_mean10;
}

/// Byte offset of the record's leading marker.
/// Complexity: O(1).
pub fn bio_record_offset(r: &BioRecord) -> Int {
  return r.offset;
}

/// Byte offset where the next record starts (the input length when this is
/// the last record).
/// Complexity: O(1).
pub fn bio_record_next_offset(r: &BioRecord) -> Int {
  return r.next_offset;
}

/// Bytes consumed by this record: next_offset - offset.
/// Complexity: O(1).
pub fn bio_record_consumed(r: &BioRecord) -> Int {
  let nxt: Int = r.next_offset;
  let off: Int = r.offset;
  return nxt - off;
}

/// One base-count bucket by code: 0 = A, 1 = C, 2 = G, 3 = T, 4 = N,
/// 5 = other. Returns -1 for any other code.
/// Complexity: O(1).
pub fn bio_record_base_count(r: &BioRecord, bucket: Int) -> Int {
  if bucket == 0 { return r.count_a; }
  if bucket == 1 { return r.count_c; }
  if bucket == 2 { return r.count_g; }
  if bucket == 3 { return r.count_t; }
  if bucket == 4 { return r.count_n; }
  if bucket == 5 { return r.count_other; }
  return -1;
}

/// The record's six-bucket base composition.
/// Complexity: O(1).
pub fn bio_record_base_counts(r: &BioRecord) -> BaseCounts {
  return _mk_counts(r.count_a, r.count_c, r.count_g, r.count_t, r.count_n, r.count_other);
}

/// Batch format: BIO_FORMAT_FASTA or BIO_FORMAT_FASTQ.
/// Complexity: O(1).
pub fn bio_batch_format(b: &BioBatch) -> Int {
  return b.fmt;
}

/// Number of records in the batch.
/// Complexity: O(1).
pub fn bio_batch_count(b: &BioBatch) -> Int {
  return b.count;
}

/// Id of batch record `i`; "" when i is out of range.
/// Complexity: O(1).
pub fn bio_batch_id(b: &BioBatch, i: Int) -> Str {
  let vs: Vec[Str] = b.ids;
  if i < 0 || i >= vs.len() { return ""; }
  let v: Str = vs[i];
  return v;
}

/// Sequence text of batch record `i`; "" when i is out of range.
/// Complexity: O(1).
pub fn bio_batch_sequence(b: &BioBatch, i: Int) -> Str {
  let vs: Vec[Str] = b.sequences;
  if i < 0 || i >= vs.len() { return ""; }
  let v: Str = vs[i];
  return v;
}

/// Sequence length of batch record `i`; -1 when i is out of range.
/// Complexity: O(1).
pub fn bio_batch_length(b: &BioBatch, i: Int) -> Int {
  let vs: Vec[Int] = b.lengths;
  if i < 0 || i >= vs.len() { return -1; }
  let v: Int = vs[i];
  return v;
}

/// GC content (per-mille) of batch record `i`; -1 when i is out of range.
/// Complexity: O(1).
pub fn bio_batch_gc_permille(b: &BioBatch, i: Int) -> Int {
  let vs: Vec[Int] = b.gc_permille;
  if i < 0 || i >= vs.len() { return -1; }
  let v: Int = vs[i];
  return v;
}

/// Mean Phred score (tenths, truncated) of batch record `i`; -1 when i is
/// out of range or the record has no quality.
/// Complexity: O(1).
pub fn bio_batch_qual_mean10(b: &BioBatch, i: Int) -> Int {
  let vs: Vec[Int] = b.qual_mean10;
  if i < 0 || i >= vs.len() { return -1; }
  let v: Int = vs[i];
  return v;
}

/// Byte offset of batch record `i`; -1 when i is out of range.
/// Complexity: O(1).
pub fn bio_batch_offset(b: &BioBatch, i: Int) -> Int {
  let vs: Vec[Int] = b.offsets;
  if i < 0 || i >= vs.len() { return -1; }
  let v: Int = vs[i];
  return v;
}

/// Next-record offset of batch record `i`; -1 when i is out of range.
/// Complexity: O(1).
pub fn bio_batch_next_offset(b: &BioBatch, i: Int) -> Int {
  let vs: Vec[Int] = b.next_offsets;
  if i < 0 || i >= vs.len() { return -1; }
  let v: Int = vs[i];
  return v;
}

// ---------------------------------------------------------------------------
// Format detection
// ---------------------------------------------------------------------------

/// Format auto-detection from the first non-whitespace byte at or after
/// `from`: '>' -> BIO_FORMAT_FASTA, '@' -> BIO_FORMAT_FASTQ, anything else
/// (including an out-of-range offset or an all-whitespace tail) ->
/// BIO_FORMAT_UNKNOWN.
/// Complexity: O(len(s)).
pub fn bio_detect_format(s: Str, from: Int) -> Int {
  let n = s.len();
  if from < 0 || from > n { return BIO_FORMAT_UNKNOWN; }
  let i = _skip_ws(s, from);
  if i >= n { return BIO_FORMAT_UNKNOWN; }
  let b = _at(s, i);
  if b == _B_GT { return BIO_FORMAT_FASTA; }
  if b == _B_AT { return BIO_FORMAT_FASTQ; }
  return BIO_FORMAT_UNKNOWN;
}

/// Format of the whole buffer: bio_detect_format(s, 0).
/// Complexity: O(len(s)).
pub fn bio_format(s: Str) -> Int {
  return bio_detect_format(s, 0);
}

// ---------------------------------------------------------------------------
// Standalone base / quality helpers
// ---------------------------------------------------------------------------

/// Case-insensitive six-bucket base composition of a bare sequence text.
/// Params: seq - a sequence WITHOUT whitespace or newlines (use the record
/// parsers for wrapped input).
/// Returns: Ok(BaseCounts) when every byte is legal.
/// Error case: Err("bio: invalid base at record 0 offset N") for the first
/// illegal byte, with N relative to `seq` (a bare sequence is reported as
/// record 0).
/// Complexity: O(len(seq)).
pub fn bio_base_counts(seq: Str) -> Result[BaseCounts, Str] {
  var a = 0;
  var c = 0;
  var g = 0;
  var t = 0;
  var n = 0;
  var other = 0;
  var i = 0;
  while i < seq.len() {
    let bucket = _base_bucket(_at(seq, i));
    if bucket < 0 {
      return _err_counts(_err_at("invalid base", 0, i));
    }
    if bucket == 0 { a = a + 1; } elif bucket == 1 { c = c + 1; } elif bucket == 2 { g = g + 1; } elif bucket == 3 { t = t + 1; } elif bucket == 4 { n = n + 1; } else { other = other + 1; }
    i = i + 1;
  }
  return _ok_counts(_mk_counts(a, c, g, t, n, other));
}

/// GC content of a base composition in per-mille.
/// Params: counts - any six-bucket composition.
/// Returns: (C + G) * 1000 / total, truncated toward zero; 0 when total is
/// 0. Example: 2 G/C out of 4 -> 500; 2 out of 3 -> 666.
/// Error case: none.
/// Complexity: O(1).
pub fn bio_gc_permille(counts: BaseCounts) -> Int {
  return _gc6(counts.count_a, counts.count_c, counts.count_g, counts.count_t, counts.count_n, counts.count_other);
}

/// Phred score of one quality byte under an encoding.
/// Params: byte - the ASCII value (0..255); encoding - BIO_PHRED33 or
/// BIO_PHRED64.
/// Returns: the Phred score, or -1 when the byte is outside the encoding's
/// legal range or the encoding is unknown. Phred+33: 33..126 -> 0..93;
/// Phred+64: 64..126 -> 0..62.
/// Error case: none (-1 is the sentinel).
/// Complexity: O(1).
pub fn bio_phred_quality(byte: Int, encoding: Int) -> Int {
  return _phred_value(byte, encoding);
}

/// ASCII offset of a quality encoding: 33, 64, or -1 for unknown.
/// Complexity: O(1).
pub fn bio_phred_offset(encoding: Int) -> Int {
  if encoding == BIO_PHRED33 { return 33; }
  if encoding == BIO_PHRED64 { return 64; }
  return -1;
}

// ---------------------------------------------------------------------------
// FASTA
// ---------------------------------------------------------------------------

/// Parse one FASTA record starting at or after byte `from`.
/// Params: s - the buffer; from - the byte offset to start scanning
/// (whitespace before the '>' is skipped); rec_index - the record's index,
/// used verbatim in error messages.
/// Grammar: '>' header-line, then sequence lines until the next line that
/// starts with '>' or the end of input. Space, tab and CR are stripped
/// from sequence lines; the sequence alphabet is ACGTUN plus RYSWKMBDHV
/// (either case), everything else is an error. An empty header id or an
/// empty sequence is an error. The header line may be unterminated at EOF.
/// Returns: Ok(BioRecord) with kind BIO_FORMAT_FASTA, no quality fields,
/// and offset/next_offset delimiting the consumed span (next_offset points
/// at the next record's '>' after skipping blank lines, or at s.len()).
/// Error case: Err("bio: bad offset at record R offset N") for an
/// out-of-range `from`; Err("bio: missing FASTA header at record R offset
/// N"); Err("bio: empty FASTA header at record R offset N"); Err("bio:
/// invalid FASTA base at record R offset N"); Err("bio: empty FASTA
/// sequence at record R offset N").
/// Complexity: O(record size).
pub fn bio_fasta_parse_next(s: Str, from: Int, rec_index: Int) -> Result[BioRecord, Str] {
  let n = s.len();
  if from < 0 || from > n {
    return _err_record(_err_at("bad offset", rec_index, from));
  }
  let i = _skip_ws(s, from);
  if i >= n || _at(s, i) != _B_GT {
    return _err_record(_err_at("missing FASTA header", rec_index, i));
  }
  let h = _scan_header(s, i);
  if !h.ok {
    return _err_record(_err_at("empty FASTA header", rec_index, i));
  }
  let id = string.str_slice(s, h.id_start, h.id_end);
  let desc = string.str_slice(s, h.desc_start, h.desc_end);
  var sb: Vec[UInt8] = builder.sb_new();
  var ca = 0;
  var cc = 0;
  var cg = 0;
  var ct = 0;
  var cn = 0;
  var co = 0;
  var seq_len = 0;
  var j = h.next_line;
  var next_off = n;
  var bad_off = -1;
  var scanning = true;
  while scanning && j < n {
    let ln = _line_at(s, j);
    if ln.content_end > j && _at(s, j) == _B_GT {
      next_off = j;
      scanning = false;
    } else {
      var k = j;
      while k < ln.content_end && bad_off < 0 {
        let b = _at(s, k);
        if _is_line_ws(b) {
          k = k + 1;
        } else {
          let bucket = _base_bucket(b);
          if bucket < 0 {
            bad_off = k;
          } else {
            builder.sb_push_byte(&mut sb, b as UInt8);
            if bucket == 0 { ca = ca + 1; } elif bucket == 1 { cc = cc + 1; } elif bucket == 2 { cg = cg + 1; } elif bucket == 3 { ct = ct + 1; } elif bucket == 4 { cn = cn + 1; } else { co = co + 1; }
            seq_len = seq_len + 1;
            k = k + 1;
          }
        }
      }
      if bad_off >= 0 {
        scanning = false;
      } else {
        j = ln.next_line;
      }
    }
  }
  if bad_off >= 0 {
    return _err_record(_err_at("invalid FASTA base", rec_index, bad_off));
  }
  if seq_len == 0 {
    return _err_record(_err_at("empty FASTA sequence", rec_index, h.next_line));
  }
  let seq = builder.sb_to_str(&sb);
  let gc = _gc6(ca, cc, cg, ct, cn, co);
  return _ok_record(_mk_record(BIO_FORMAT_FASTA, id, desc, seq, "", seq_len, ca, cc, cg, ct, cn, co, gc, false, -1, -1, -1, -1, i, next_off));
}

// ---------------------------------------------------------------------------
// FASTQ
// ---------------------------------------------------------------------------

/// Parse one FASTQ record (Phred+33) starting at or after byte `from`.
/// Params: s/from/rec_index - see bio_fasta_parse_next.
/// Returns: bio_fastq_parse_next_enc with BIO_PHRED33.
/// Error case: see bio_fastq_parse_next_enc.
/// Complexity: O(record size).
pub fn bio_fastq_parse_next(s: Str, from: Int, rec_index: Int) -> Result[BioRecord, Str] {
  return bio_fastq_parse_next_enc(s, from, rec_index, BIO_PHRED33);
}

/// Parse one FASTQ record with an explicit quality encoding.
/// Params: s/from/rec_index - see bio_fasta_parse_next; encoding -
/// BIO_PHRED33 or BIO_PHRED64 (anything else is an error).
/// Grammar: '@' header-line, one or more sequence lines up to a line that
/// starts with '+', then quality lines whose bytes are counted until they
/// reach exactly the sequence length. The '+' line may repeat the header
/// id; when it does, the id must match. Sequence bytes are validated
/// against the same alphabet as FASTA; whitespace inside a sequence or
/// quality line is illegal (line terminators are not part of either).
/// Returns: Ok(BioRecord) with kind BIO_FORMAT_FASTQ, the raw quality text,
/// min/max Phred scores and the mean in tenths truncated toward zero
/// (sum in Int, divided once at the end); offset/next_offset delimit the
/// consumed span.
/// Error case: Err("bio: bad offset ..."); Err("bio: invalid quality
/// encoding at record R offset N"); Err("bio: missing FASTQ header ...");
/// Err("bio: empty FASTQ header ..."); Err("bio: invalid FASTQ base ...");
/// Err("bio: missing FASTQ separator ..."); Err("bio: empty FASTQ sequence
/// ..."); Err("bio: FASTQ repeated header mismatch ..."); Err("bio: invalid
/// FASTQ quality ...") for a byte outside the encoding's range; Err("bio:
/// FASTQ quality-length mismatch ...") when the quality run overshoots the
/// sequence length or the input ends first.
/// Complexity: O(record size).
pub fn bio_fastq_parse_next_enc(s: Str, from: Int, rec_index: Int, encoding: Int) -> Result[BioRecord, Str] {
  let n = s.len();
  if from < 0 || from > n {
    return _err_record(_err_at("bad offset", rec_index, from));
  }
  if encoding != BIO_PHRED33 && encoding != BIO_PHRED64 {
    return _err_record(_err_at("invalid quality encoding", rec_index, from));
  }
  let i = _skip_ws(s, from);
  if i >= n || _at(s, i) != _B_AT {
    return _err_record(_err_at("missing FASTQ header", rec_index, i));
  }
  let h = _scan_header(s, i);
  if !h.ok {
    return _err_record(_err_at("empty FASTQ header", rec_index, i));
  }
  let id = string.str_slice(s, h.id_start, h.id_end);
  let desc = string.str_slice(s, h.desc_start, h.desc_end);
  var sb: Vec[UInt8] = builder.sb_new();
  var ca = 0;
  var cc = 0;
  var cg = 0;
  var ct = 0;
  var cn = 0;
  var co = 0;
  var seq_len = 0;
  var j = h.next_line;
  var sep_pos = -1;
  var bad_off = -1;
  var scanning = true;
  while scanning && j < n {
    let ln = _line_at(s, j);
    if ln.content_end > j && _at(s, j) == _B_PLUS {
      sep_pos = j;
      scanning = false;
    } else {
      var k = j;
      while k < ln.content_end && bad_off < 0 {
        let b = _at(s, k);
        let bucket = _base_bucket(b);
        if bucket < 0 {
          bad_off = k;
        } else {
          builder.sb_push_byte(&mut sb, b as UInt8);
          if bucket == 0 { ca = ca + 1; } elif bucket == 1 { cc = cc + 1; } elif bucket == 2 { cg = cg + 1; } elif bucket == 3 { ct = ct + 1; } elif bucket == 4 { cn = cn + 1; } else { co = co + 1; }
          seq_len = seq_len + 1;
          k = k + 1;
        }
      }
      if bad_off >= 0 {
        scanning = false;
      } else {
        j = ln.next_line;
      }
    }
  }
  if bad_off >= 0 {
    return _err_record(_err_at("invalid FASTQ base", rec_index, bad_off));
  }
  if sep_pos < 0 {
    return _err_record(_err_at("missing FASTQ separator", rec_index, n));
  }
  if seq_len == 0 {
    return _err_record(_err_at("empty FASTQ sequence", rec_index, sep_pos));
  }
  let sep_line = _line_at(s, sep_pos);
  var rs = sep_pos + 1;
  var rb = sep_line.content_end;
  while rs < rb && _is_line_ws(_at(s, rs)) { rs = rs + 1; }
  while rb > rs && _is_line_ws(_at(s, rb - 1)) { rb = rb - 1; }
  if rb > rs {
    var re = rs;
    while re < rb && !_is_line_ws(_at(s, re)) { re = re + 1; }
    let rep = string.str_slice(s, rs, re);
    if !_str_eq(rep, id) {
      return _err_record(_err_at("FASTQ repeated header mismatch", rec_index, sep_pos));
    }
  }
  var qb: Vec[UInt8] = builder.sb_new();
  var qlen = 0;
  var qmin = -1;
  var qmax = -1;
  var qsum = 0;
  var jq = sep_line.next_line;
  var next_off = n;
  var q_done = false;
  while !q_done {
    if jq >= n {
      return _err_record(_err_at("FASTQ quality-length mismatch", rec_index, n));
    }
    let qln = _line_at(s, jq);
    var k = jq;
    while k < qln.content_end {
      if qlen >= seq_len {
        return _err_record(_err_at("FASTQ quality-length mismatch", rec_index, k));
      }
      let b = _at(s, k);
      let qv = _phred_value(b, encoding);
      if qv < 0 {
        return _err_record(_err_at("invalid FASTQ quality", rec_index, k));
      }
      builder.sb_push_byte(&mut qb, b as UInt8);
      qlen = qlen + 1;
      if qmin < 0 || qv < qmin { qmin = qv; }
      if qv > qmax { qmax = qv; }
      qsum = qsum + qv;
      k = k + 1;
    }
    if qlen == seq_len {
      q_done = true;
      next_off = qln.next_line;
    } else {
      jq = qln.next_line;
      if !qln.has_lf {
        return _err_record(_err_at("FASTQ quality-length mismatch", rec_index, n));
      }
    }
  }
  let seq = builder.sb_to_str(&sb);
  let qual = builder.sb_to_str(&qb);
  let gc = _gc6(ca, cc, cg, ct, cn, co);
  let qmean10 = (qsum * 10) / seq_len;
  return _ok_record(_mk_record(BIO_FORMAT_FASTQ, id, desc, seq, qual, seq_len, ca, cc, cg, ct, cn, co, gc, true, encoding, qmin, qmax, qmean10, i, next_off));
}

// ---------------------------------------------------------------------------
// Whole-buffer walking
// ---------------------------------------------------------------------------

/// Count records in a whole buffer, auto-detecting the format.
/// Params: s - the buffer.
/// Returns: Ok(count) after walking every record with full validation.
/// Error case: Err("bio: unknown format at record 0 offset 0") when the
/// first non-whitespace byte is neither '>' nor '@'; otherwise the first
/// per-record parse error, verbatim.
/// Complexity: O(len(s)).
pub fn bio_record_count(s: Str) -> Result[Int, Str] {
  return bio_record_count_enc(s, BIO_PHRED33);
}

/// Count records with an explicit quality encoding (FASTQ only).
/// Params: s - the buffer; encoding - BIO_PHRED33 or BIO_PHRED64.
/// Returns: Ok(count); see bio_record_count.
/// Error case: as bio_record_count, plus Err("bio: invalid quality
/// encoding at record 0 offset 0") for an unknown encoding.
/// Complexity: O(len(s)).
pub fn bio_record_count_enc(s: Str, encoding: Int) -> Result[Int, Str] {
  let fmt = bio_detect_format(s, 0);
  if fmt == BIO_FORMAT_UNKNOWN {
    return _err_int("bio: unknown format at record 0 offset 0");
  }
  if encoding != BIO_PHRED33 && encoding != BIO_PHRED64 {
    return _err_int(_err_at("invalid quality encoding", 0, 0));
  }
  let n = s.len();
  var count = 0;
  var from = 0;
  while _skip_ws(s, from) < n {
    if fmt == BIO_FORMAT_FASTA {
      let r = bio_fasta_parse_next(s, from, count);
      var nxt = -1;
      match r {
        Ok(v) => { nxt = v.next_offset; count = count + 1; },
        Err(e) => { return _err_int(e); },
      }
      from = nxt;
    } else {
      let r2 = bio_fastq_parse_next_enc(s, from, count, encoding);
      var nxt2 = -1;
      match r2 {
        Ok(v2) => { nxt2 = v2.next_offset; count = count + 1; },
        Err(e2) => { return _err_int(e2); },
      }
      from = nxt2;
    }
  }
  return _ok_int(count);
}

/// Parse every record of a whole buffer into a BioBatch (Phred+33 FASTQ).
/// Params: s - the buffer.
/// Returns: bio_parse_all_enc(s, BIO_PHRED33).
/// Error case: see bio_parse_all_enc.
/// Complexity: O(len(s)).
pub fn bio_parse_all(s: Str) -> Result[BioBatch, Str] {
  return bio_parse_all_enc(s, BIO_PHRED33);
}

/// Parse every record of a whole buffer into a BioBatch with an explicit
/// quality encoding.
/// Params: s - the buffer; encoding - BIO_PHRED33 or BIO_PHRED64.
/// Returns: Ok(BioBatch) with one entry per record in walk order; the
/// parallel vectors always have equal lengths.
/// Error case: Err("bio: unknown format at record 0 offset 0") when the
/// first non-whitespace byte is neither '>' nor '@'; Err("bio: invalid
/// quality encoding at record 0 offset 0") for an unknown encoding;
/// otherwise the first per-record parse error, verbatim.
/// Complexity: O(len(s)).
pub fn bio_parse_all_enc(s: Str, encoding: Int) -> Result[BioBatch, Str] {
  let fmt = bio_detect_format(s, 0);
  if fmt == BIO_FORMAT_UNKNOWN {
    return _err_batch("bio: unknown format at record 0 offset 0");
  }
  if encoding != BIO_PHRED33 && encoding != BIO_PHRED64 {
    return _err_batch(_err_at("invalid quality encoding", 0, 0));
  }
  let n = s.len();
  var b = _mk_batch(fmt);
  var from = 0;
  while _skip_ws(s, from) < n {
    let idx = b.count;
    if fmt == BIO_FORMAT_FASTA {
      let r = bio_fasta_parse_next(s, from, idx);
      match r {
        Ok(v) => {
          b.ids.push(v.id);
          b.descriptions.push(v.description);
          b.sequences.push(v.sequence);
          b.qualities.push(v.quality);
          b.lengths.push(v.seq_len);
          b.count_a.push(v.count_a);
          b.count_c.push(v.count_c);
          b.count_g.push(v.count_g);
          b.count_t.push(v.count_t);
          b.count_n.push(v.count_n);
          b.count_other.push(v.count_other);
          b.gc_permille.push(v.gc_permille);
          b.qual_min.push(v.qual_min);
          b.qual_max.push(v.qual_max);
          b.qual_mean10.push(v.qual_mean10);
          b.offsets.push(v.offset);
          b.next_offsets.push(v.next_offset);
          b.count = idx + 1;
          from = v.next_offset;
        },
        Err(e) => { return _err_batch(e); },
      }
    } else {
      let r2 = bio_fastq_parse_next_enc(s, from, idx, encoding);
      match r2 {
        Ok(v2) => {
          b.ids.push(v2.id);
          b.descriptions.push(v2.description);
          b.sequences.push(v2.sequence);
          b.qualities.push(v2.quality);
          b.lengths.push(v2.seq_len);
          b.count_a.push(v2.count_a);
          b.count_c.push(v2.count_c);
          b.count_g.push(v2.count_g);
          b.count_t.push(v2.count_t);
          b.count_n.push(v2.count_n);
          b.count_other.push(v2.count_other);
          b.gc_permille.push(v2.gc_permille);
          b.qual_min.push(v2.qual_min);
          b.qual_max.push(v2.qual_max);
          b.qual_mean10.push(v2.qual_mean10);
          b.offsets.push(v2.offset);
          b.next_offsets.push(v2.next_offset);
          b.count = idx + 1;
          from = v2.next_offset;
        },
        Err(e2) => { return _err_batch(e2); },
      }
    }
  }
  return _ok_batch(b);
}
