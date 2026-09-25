// XIOM -- xiom.miniseed: miniSEED fixed 48-byte record header codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of a miniSEED 2.x fixed
// data-record header codec. Scope: the 48-byte fixed header, the caller-
// supplied record size and the data payload span. Blockettes are located by
// their offsets but never parsed; samples are never decoded; there is no
// Steim decompression and no dataless SEED. See SPEC.md for the pinned
// semantics, the validation order and the error catalog.
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - miniseed_parse reads exactly one record: the record size is the length
//   of the buffer, so the caller slices a fixed-length stream into records
//   of the known size (the documented fixtures are 512 and 4096 bytes). The
//   fixed header does not encode the record length -- miniSEED carries it in
//   blockette 1000, which is out of scope -- so the record size is always
//   caller-supplied. miniseed_required_record_size reports the length needed
//   for a declared sample count.
// - The result is a MseedHeader: one flat value type of scalar fields. No
//   Vec of structs and no nested structs are used anywhere.
// - All multi-byte fields are big-endian. miniSEED 2.x fixed headers are
//   big-endian; little-endian records exist but their detection needs the
//   blockette 1000 word-order flag, which this module does not parse, so
//   there is no little-endian variant and no auto-detection.
// - The sample rate is exposed twice: as the raw (factor, multiplier) pair
//   and as an exact integer rational plus an integer micro-Hz value
//   (truncated toward zero), see miniseed_rate_num / miniseed_rate_den /
//   miniseed_rate_microhz and SPEC.md section 5.
// - The fixed header has no number-of-samples field: the count is implied
//   by the payload span and the encoding's bytes-per-sample. The module
//   derives it on request (miniseed_sample_count) and can check a declared
//   count against the span (miniseed_samples_fit).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the leaf helpers below
//     (_ok_header/_err_header/_ok_bytes/_err_bytes).
//   * every byte read is widened with `(data[pos] as Int) & _MS_BYTE_MASK`;
//     UInt8 values are never compared against Int constants without widening.
//   * Str values are never compared with `==` (BUG 17: `==` on Str values
//     read from Vec elements lowers to a pointer comparison); the module
//     performs no string equality at all, and every accessor binds the Str
//     field to a typed local before returning it.
//   * multi-byte writes go through _byte_low (arithmetic, negative-remainder
//     corrected) so negative i16/i32 values emit exact two's-complement
//     bytes without `<<` or `& 0xFF` on values that may have bit 31 set.

module xiom.miniseed

use xiom.string;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

// Fixed header length in bytes.
const _MS_HEADER_LEN: Int = 48;
// Widening mask for one raw byte.
const _MS_BYTE_MASK: Int = 255;
// Text field widths.
const _MS_SEQ_LEN: Int = 6;
const _MS_STATION_LEN: Int = 5;
const _MS_CHANNEL_LEN: Int = 3;
const _MS_NETWORK_LEN: Int = 2;
const _MS_LOCATION_LEN: Int = 2;
// Field ranges.
const _MS_MAX_DAY: Int = 366;
const _MS_MAX_HOUR: Int = 23;
const _MS_MAX_MINUTE: Int = 59;
const _MS_MAX_SECOND: Int = 60;
const _MS_MAX_TENTHS: Int = 9999;
const _MS_SPACE: Int = 32;
const _MS_MAX_PRINTABLE: Int = 126;
const _MS_I16_MIN: Int = -32768;
const _MS_I16_MAX: Int = 32767;
const _MS_I32_MIN: Int = -2147483648;
const _MS_I32_MAX: Int = 2147483647;
// Quality indicator bytes: D, R, Q, M or space.
const _MS_QUALITY_D: Int = 68;
const _MS_QUALITY_R: Int = 82;
const _MS_QUALITY_Q: Int = 81;
const _MS_QUALITY_M: Int = 77;
// Rate scaling: one Hz is 1,000,000 micro-Hz.
const _MS_MICRO: Int = 1000000;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed miniSEED 2.x fixed record header plus its caller-supplied
/// record size. Every field is a scalar; the type is flat (no nested structs,
/// no Vec of structs). Text fields are stored trimmed of surrounding spaces;
/// `unused` (byte 27) and `reserved2` (bytes 46..47) are preserved as parsed
/// but never validated; `record_size` is the length of the buffer the header
/// was parsed from and is not encoded in the header itself.
pub type MseedHeader = {
  sequence: Str;
  quality: Int;
  reserved: Int;
  station: Str;
  channel: Str;
  network: Str;
  location: Str;
  year: Int;
  day: Int;
  hour: Int;
  minute: Int;
  second: Int;
  unused: Int;
  tenths: Int;
  sample_rate_factor: Int;
  sample_rate_multiplier: Int;
  activity_flags: Int;
  io_flags: Int;
  data_quality_flags: Int;
  num_blockettes: Int;
  time_correction: Int;
  begin_data_offset: Int;
  begin_blockette_offset: Int;
  reserved2: Int;
  record_size: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[MseedHeader, Str].
fn _ok_header(v: MseedHeader) -> Result[MseedHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[MseedHeader, Str].
fn _err_header(m: Str) -> Result[MseedHeader, Str] {
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
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & _MS_BYTE_MASK;
}

// Big-endian UInt16 at `off` as an Int (0..65535).
fn _be16(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) * 256 + _byte(data, off + 1);
}

// Big-endian i16 at `off` as a signed Int (-32768..32767).
fn _be16_signed(data: &Vec[UInt8], off: Int) -> Int {
  let raw = _be16(data, off);
  if raw < 32768 { return raw; }
  return raw - 65536;
}

// Big-endian UInt32 at `off` as an Int (0..2^32-1).
fn _be32(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) * 16777216 + _byte(data, off + 1) * 65536 + _byte(data, off + 2) * 256 + _byte(data, off + 3);
}

// Big-endian i32 at `off` as a signed Int (-2^31..2^31-1).
fn _be32_signed(data: &Vec[UInt8], off: Int) -> Int {
  let raw = _be32(data, off);
  if raw < 2147483648 { return raw; }
  return raw - 4294967296;
}

// Byte `k` (0 = least significant) of the two's-complement pattern of `v`,
// as a value in 0..255. Arithmetic only: the remainder of a negative `q` is
// corrected before the division, so no bit operation on a possibly-negative
// value is needed.
fn _byte_low(v: Int, k: Int) -> Int {
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
  return b;
}

// Append `v` (0..65535) as two big-endian bytes; a negative `v` writes its
// low 16 bits of the two's-complement pattern.
fn _push_be16(out: &mut Vec[UInt8], v: Int) {
  out.push(_byte_low(v, 1) as UInt8);
  out.push(_byte_low(v, 0) as UInt8);
}

// Append `v` as four big-endian bytes (low 32 bits of the pattern).
fn _push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push(_byte_low(v, 3) as UInt8);
  out.push(_byte_low(v, 2) as UInt8);
  out.push(_byte_low(v, 1) as UInt8);
  out.push(_byte_low(v, 0) as UInt8);
}

// Append `s` followed by spaces up to `width` bytes; `s` must not be longer
// than `width` (callers validate).
fn _push_padded(out: &mut Vec[UInt8], s: Str, width: Int) {
  var i = 0;
  while i < width {
    if i < s.len() {
      out.push(string.byte_at(s, i));
    } else {
      out.push(_MS_SPACE as UInt8);
    }
    i = i + 1;
  }
}

// The `width` bytes at `off` as a Str, verbatim (no trimming).
fn _field_str(data: &Vec[UInt8], off: Int, width: Int) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < width {
    bytes.push(_byte(data, off + i) as UInt8);
    i = i + 1;
  }
  return Str::from_utf8(bytes);
}

// --------------------------------------------------
//  Validators
// --------------------------------------------------

// True when `c` (0..255) is an ASCII digit or a space; the sequence number
// character set.
fn _is_digit_or_space(c: Int) -> Bool {
  if c == _MS_SPACE { return true; }
  if c >= 48 && c <= 57 { return true; }
  return false;
}

// True when `c` (0..255) is printable ASCII (0x20..0x7E), the text-field
// character set for station/channel/network/location.
fn _is_printable(c: Int) -> Bool {
  return c >= _MS_SPACE && c <= _MS_MAX_PRINTABLE;
}

// True when the 6 sequence bytes are all digits or spaces.
fn _seq_ok(data: &Vec[UInt8]) -> Bool {
  var i = 0;
  while i < _MS_SEQ_LEN {
    if !_is_digit_or_space(_byte(data, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when the `width` bytes at `off` are all printable ASCII.
fn _text_ok(data: &Vec[UInt8], off: Int, width: Int) -> Bool {
  var i = 0;
  while i < width {
    if !_is_printable(_byte(data, off + i)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is at most `width` bytes and every byte is printable ASCII.
fn _str_ok(s: Str, width: Int) -> Bool {
  if s.len() > width { return false; }
  var i = 0;
  while i < s.len() {
    if !_is_printable((string.byte_at(s, i) as Int) & _MS_BYTE_MASK) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `q` is a valid quality indicator byte: D, R, Q, M or space.
fn _quality_ok(q: Int) -> Bool {
  if q == _MS_QUALITY_D { return true; }
  if q == _MS_QUALITY_R { return true; }
  if q == _MS_QUALITY_Q { return true; }
  if q == _MS_QUALITY_M { return true; }
  if q == _MS_SPACE { return true; }
  return false;
}

// Proleptic Gregorian leap-year rule: divisible by 4, except centuries that
// are not divisible by 400.
fn _is_leap(year: Int) -> Bool {
  if year % 400 == 0 { return true; }
  if year % 100 == 0 { return false; }
  return year % 4 == 0;
}

// True when `day` is a valid day-of-year for `year`: 1..365, plus 366 in a
// leap year.
fn _day_ok(year: Int, day: Int) -> Bool {
  if day < 1 { return false; }
  if day > _MS_MAX_DAY { return false; }
  if day == _MS_MAX_DAY && !_is_leap(year) { return false; }
  return true;
}

// True when `v` is inside 0..255.
fn _u8_ok(v: Int) -> Bool {
  return v >= 0 && v <= _MS_BYTE_MASK;
}

// --------------------------------------------------
//  Public API -- parsing
// --------------------------------------------------

/// Parse one miniSEED 2.x fixed record header.
///
/// The whole `data` buffer is treated as one record: `record_size` is
/// `data.len()`, so a caller reading a fixed-length stream slices one record
/// (512 or 4096 bytes) before calling. Multi-byte fields are read
/// big-endian.
///
/// Validation order (first failure wins): a buffer shorter than 48 bytes ->
/// `miniseed: truncated header`; quality byte not in {D, R, Q, M, space} ->
/// `miniseed: bad quality indicator`; reserved byte not in {0x00, 0x20} ->
/// `miniseed: bad reserved byte`; sequence bytes not all digits/spaces ->
/// `miniseed: bad sequence number`; station/channel/network/location bytes
/// outside 0x20..0x7E -> `miniseed: bad station` (and the matching
/// channel/network/location errors); day outside 1..366 or day 366 in a
/// non-leap year -> `miniseed: bad day`; hour > 23 -> `miniseed: bad hour`;
/// minute > 59 -> `miniseed: bad minute`; second > 60 -> `miniseed: bad
/// second`; tenths > 9999 -> `miniseed: bad tenths`; begin_data_offset < 48
/// or past the record -> `miniseed: bad data offset`; a first blockette
/// offset that is neither 0 nor inside 48..record_size, or a nonzero
/// blockette count with a zero offset -> `miniseed: bad blockette offset`.
/// The unused byte (27) and the two reserved bytes (46..47) are preserved
/// and never rejected.
///
/// Params: data - exactly one record, read only.
/// Returns: Ok(MseedHeader) with trimmed text fields and `record_size` set
/// to `data.len()`.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(48).
pub fn miniseed_parse(data: &Vec[UInt8]) -> Result[MseedHeader, Str] {
  let n = data.len();
  if n < _MS_HEADER_LEN { return _err_header("miniseed: truncated header"); }
  let quality: Int = _byte(data, 6);
  if !_quality_ok(quality) { return _err_header("miniseed: bad quality indicator"); }
  let reserved: Int = _byte(data, 7);
  if reserved != _MS_SPACE && reserved != 0 {
    return _err_header("miniseed: bad reserved byte");
  }
  if !_seq_ok(data) { return _err_header("miniseed: bad sequence number"); }
  if !_text_ok(data, 8, _MS_STATION_LEN) { return _err_header("miniseed: bad station"); }
  if !_text_ok(data, 13, _MS_CHANNEL_LEN) { return _err_header("miniseed: bad channel"); }
  if !_text_ok(data, 16, _MS_NETWORK_LEN) { return _err_header("miniseed: bad network"); }
  if !_text_ok(data, 18, _MS_LOCATION_LEN) { return _err_header("miniseed: bad location"); }
  let year: Int = _be16(data, 20);
  let day: Int = _be16(data, 22);
  if !_day_ok(year, day) { return _err_header("miniseed: bad day"); }
  let hour: Int = _byte(data, 24);
  if hour > _MS_MAX_HOUR { return _err_header("miniseed: bad hour"); }
  let minute: Int = _byte(data, 25);
  if minute > _MS_MAX_MINUTE { return _err_header("miniseed: bad minute"); }
  let second: Int = _byte(data, 26);
  if second > _MS_MAX_SECOND { return _err_header("miniseed: bad second"); }
  let unused: Int = _byte(data, 27);
  let tenths: Int = _be16(data, 28);
  if tenths > _MS_MAX_TENTHS { return _err_header("miniseed: bad tenths"); }
  let factor: Int = _be16_signed(data, 30);
  let multiplier: Int = _be16_signed(data, 32);
  let activity: Int = _byte(data, 34);
  let io_flags: Int = _byte(data, 35);
  let dq_flags: Int = _byte(data, 36);
  let nblk: Int = _byte(data, 37);
  let tc: Int = _be32_signed(data, 38);
  let bdo: Int = _be16(data, 42);
  let bbo: Int = _be16(data, 44);
  let reserved2: Int = _be16(data, 46);
  if bdo < _MS_HEADER_LEN { return _err_header("miniseed: bad data offset"); }
  if bdo > n { return _err_header("miniseed: bad data offset"); }
  if bbo != 0 {
    if bbo < _MS_HEADER_LEN { return _err_header("miniseed: bad blockette offset"); }
    if bbo > n { return _err_header("miniseed: bad blockette offset"); }
  }
  if nblk > 0 && bbo == 0 { return _err_header("miniseed: bad blockette offset"); }
  let seq: Str = string.str_trim(_field_str(data, 0, _MS_SEQ_LEN));
  let station: Str = string.str_trim(_field_str(data, 8, _MS_STATION_LEN));
  let channel: Str = string.str_trim(_field_str(data, 13, _MS_CHANNEL_LEN));
  let network: Str = string.str_trim(_field_str(data, 16, _MS_NETWORK_LEN));
  let location: Str = string.str_trim(_field_str(data, 18, _MS_LOCATION_LEN));
  let h = MseedHeader{
    sequence: seq;
    quality: quality;
    reserved: reserved;
    station: station;
    channel: channel;
    network: network;
    location: location;
    year: year;
    day: day;
    hour: hour;
    minute: minute;
    second: second;
    unused: unused;
    tenths: tenths;
    sample_rate_factor: factor;
    sample_rate_multiplier: multiplier;
    activity_flags: activity;
    io_flags: io_flags;
    data_quality_flags: dq_flags;
    num_blockettes: nblk;
    time_correction: tc;
    begin_data_offset: bdo;
    begin_blockette_offset: bbo;
    reserved2: reserved2;
    record_size: n;
  };
  return _ok_header(h);
}

// --------------------------------------------------
//  Public API -- accessors
// --------------------------------------------------

/// Sequence number (bytes 0..5), trimmed of leading/trailing spaces; an
/// all-space field yields "". Complexity: O(1).
pub fn miniseed_sequence(h: &MseedHeader) -> Str {
  let s: Str = h.sequence;
  return s;
}

/// Quality indicator as its raw ASCII byte: D 68, R 82, Q 81, M 77 or
/// space 32. Complexity: O(1).
pub fn miniseed_quality(h: &MseedHeader) -> Int {
  return h.quality;
}

/// Byte 7 (reserved) exactly as parsed: 0x00 or 0x20. Complexity: O(1).
pub fn miniseed_reserved(h: &MseedHeader) -> Int {
  return h.reserved;
}

/// Station identifier (bytes 8..12), trimmed. Complexity: O(1).
pub fn miniseed_station(h: &MseedHeader) -> Str {
  let s: Str = h.station;
  return s;
}

/// Channel identifier (bytes 13..15), trimmed. Complexity: O(1).
pub fn miniseed_channel(h: &MseedHeader) -> Str {
  let s: Str = h.channel;
  return s;
}

/// Network identifier (bytes 16..17), trimmed. Complexity: O(1).
pub fn miniseed_network(h: &MseedHeader) -> Str {
  let s: Str = h.network;
  return s;
}

/// Location identifier (bytes 18..19), trimmed; an all-space field yields
/// "". Complexity: O(1).
pub fn miniseed_location(h: &MseedHeader) -> Str {
  let s: Str = h.location;
  return s;
}

/// Start year (big-endian u16, bytes 20..21). Complexity: O(1).
pub fn miniseed_year(h: &MseedHeader) -> Int {
  return h.year;
}

/// Start day-of-year (big-endian u16, bytes 22..23), 1..366. Complexity:
/// O(1).
pub fn miniseed_day(h: &MseedHeader) -> Int {
  return h.day;
}

/// Start hour (byte 24), 0..23. Complexity: O(1).
pub fn miniseed_hour(h: &MseedHeader) -> Int {
  return h.hour;
}

/// Start minute (byte 25), 0..59. Complexity: O(1).
pub fn miniseed_minute(h: &MseedHeader) -> Int {
  return h.minute;
}

/// Start second (byte 26), 0..60; 60 is the documented leap-second value.
/// Complexity: O(1).
pub fn miniseed_second(h: &MseedHeader) -> Int {
  return h.second;
}

/// Byte 27 (unused), preserved as parsed and never validated. Complexity:
/// O(1).
pub fn miniseed_unused(h: &MseedHeader) -> Int {
  return h.unused;
}

/// Tenths of milliseconds (big-endian u16, bytes 28..29): 0..9999, i.e. the
/// sub-second offset in units of 0.0001 s. Complexity: O(1).
pub fn miniseed_tenths(h: &MseedHeader) -> Int {
  return h.tenths;
}

/// Sample rate factor (big-endian i16, bytes 30..31), raw. Complexity: O(1).
pub fn miniseed_sample_rate_factor(h: &MseedHeader) -> Int {
  return h.sample_rate_factor;
}

/// Sample rate multiplier (big-endian i16, bytes 32..33), raw. Complexity:
/// O(1).
pub fn miniseed_sample_rate_multiplier(h: &MseedHeader) -> Int {
  return h.sample_rate_multiplier;
}

/// Exact sample-rate numerator in Hz: rate = num / den with den >= 1. A zero
/// factor yields 0/1; a zero multiplier is treated as 1. The pair is not
/// reduced to lowest terms. Complexity: O(1).
pub fn miniseed_rate_num(h: &MseedHeader) -> Int {
  let f: Int = h.sample_rate_factor;
  var m: Int = h.sample_rate_multiplier;
  if f == 0 { return 0; }
  if m == 0 { m = 1; }
  if f > 0 {
    if m > 0 { return f * m; }
    return f;
  }
  if m > 0 { return m; }
  return 1;
}

/// Exact sample-rate denominator in Hz (>= 1) for miniseed_rate_num.
/// Complexity: O(1).
pub fn miniseed_rate_den(h: &MseedHeader) -> Int {
  let f: Int = h.sample_rate_factor;
  var m: Int = h.sample_rate_multiplier;
  if f == 0 { return 1; }
  if m == 0 { m = 1; }
  if f > 0 {
    if m > 0 { return 1; }
    return -m;
  }
  if m > 0 { return -f; }
  return f * m;
}

/// Sample rate in integer micro-Hz: floor((num / den) * 1,000,000), i.e. the
/// exact positive rational truncated toward zero. A zero factor yields 0.
/// All intermediate products fit an Int for any i16 factor/multiplier pair.
/// Complexity: O(1).
pub fn miniseed_rate_microhz(h: &MseedHeader) -> Int {
  let num = miniseed_rate_num(h);
  if num == 0 { return 0; }
  let den = miniseed_rate_den(h);
  return num * _MS_MICRO / den;
}

/// Activity flags byte (34), raw. Complexity: O(1).
pub fn miniseed_activity_flags(h: &MseedHeader) -> Int {
  return h.activity_flags;
}

/// I/O and clock flags byte (35), raw. Complexity: O(1).
pub fn miniseed_io_flags(h: &MseedHeader) -> Int {
  return h.io_flags;
}

/// Data quality flags byte (36), raw. Complexity: O(1).
pub fn miniseed_data_quality_flags(h: &MseedHeader) -> Int {
  return h.data_quality_flags;
}

/// Number of blockettes that follow the fixed header (byte 37), raw.
/// Complexity: O(1).
pub fn miniseed_num_blockettes(h: &MseedHeader) -> Int {
  return h.num_blockettes;
}

/// Time correction (big-endian i32, bytes 38..41) in 0.0001 s units.
/// Complexity: O(1).
pub fn miniseed_time_correction(h: &MseedHeader) -> Int {
  return h.time_correction;
}

/// Beginning of data offset (big-endian u16, bytes 42..43): byte 0 of the
/// record is index 0, so a value of 48 means the payload starts immediately
/// after the fixed header. Complexity: O(1).
pub fn miniseed_begin_data_offset(h: &MseedHeader) -> Int {
  return h.begin_data_offset;
}

/// First blockette offset (big-endian u16, bytes 44..45), 0 when there is
/// none. Complexity: O(1).
pub fn miniseed_begin_blockette_offset(h: &MseedHeader) -> Int {
  return h.begin_blockette_offset;
}

/// Bytes 46..47 (reserved, big-endian u16), preserved as parsed and never
/// validated. Complexity: O(1).
pub fn miniseed_reserved2(h: &MseedHeader) -> Int {
  return h.reserved2;
}

/// Record size in bytes supplied to miniseed_parse (the buffer length).
/// Complexity: O(1).
pub fn miniseed_record_size(h: &MseedHeader) -> Int {
  return h.record_size;
}

/// Payload span in bytes: record_size - begin_data_offset, or 0 when a
/// hand-built header has begin_data_offset outside 0..record_size.
/// Complexity: O(1).
pub fn miniseed_data_span(h: &MseedHeader) -> Int {
  let rs: Int = h.record_size;
  let bdo: Int = h.begin_data_offset;
  if bdo < 0 { return 0; }
  if bdo > rs { return 0; }
  return rs - bdo;
}

/// Number of whole samples that fit the payload span: floor(span /
/// sample_size). Zero when sample_size <= 0 (bytes per sample unknown) or
/// the span is empty; trailing pad bytes are not samples. Complexity: O(1).
pub fn miniseed_sample_count(h: &MseedHeader, sample_size: Int) -> Int {
  if sample_size <= 0 { return 0; }
  return miniseed_data_span(h) / sample_size;
}

/// True when the payload span holds at least `num_samples` samples of
/// `sample_size` bytes: `num_samples * sample_size <= span`, evaluated as
/// `num_samples <= span / sample_size` so no multiplication can overflow.
/// False for a negative count or a non-positive sample size. Complexity:
/// O(1).
pub fn miniseed_samples_fit(h: &MseedHeader, num_samples: Int, sample_size: Int) -> Bool {
  if num_samples < 0 { return false; }
  if sample_size <= 0 { return false; }
  return num_samples <= miniseed_data_span(h) / sample_size;
}

/// Record size needed to hold `num_samples` samples of `sample_size` bytes
/// starting at `begin_data_offset`: offset + samples * sample_size; 0 when
/// any argument is negative (or sample_size is zero). Complexity: O(1).
pub fn miniseed_required_record_size(begin_data_offset: Int, num_samples: Int, sample_size: Int) -> Int {
  if begin_data_offset < 0 { return 0; }
  if num_samples < 0 { return 0; }
  if sample_size <= 0 { return 0; }
  return begin_data_offset + num_samples * sample_size;
}

/// Proleptic Gregorian leap-year rule used by the day-of-year validation:
/// divisible by 4, except centuries that are not divisible by 400.
/// Complexity: O(1).
pub fn miniseed_is_leap_year(year: Int) -> Bool {
  return _is_leap(year);
}

// --------------------------------------------------
//  Public API -- payload and builder
// --------------------------------------------------

/// Copy the payload span (bytes begin_data_offset .. record_size) out of
/// `data`, the buffer the header was parsed from.
/// Params: data - the record buffer; h - the parsed (or hand-built) header.
/// Returns: Ok(bytes) of length miniseed_data_span(h).
/// Error case: Err("miniseed: truncated data") when the header's record
/// size or data offset does not fit `data`, or when a hand-built header has
/// an offset outside 48..record_size.
/// Complexity: O(span).
pub fn miniseed_data_bytes(data: &Vec[UInt8], h: &MseedHeader) -> Result[Vec[UInt8], Str] {
  let rs: Int = h.record_size;
  if rs < _MS_HEADER_LEN { return _err_bytes("miniseed: truncated data"); }
  if data.len() < rs { return _err_bytes("miniseed: truncated data"); }
  let off: Int = h.begin_data_offset;
  if off < _MS_HEADER_LEN { return _err_bytes("miniseed: truncated data"); }
  if off > rs { return _err_bytes("miniseed: truncated data"); }
  var out = Vec[UInt8].new();
  var i = off;
  while i < rs {
    out.push(data[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Build the canonical 48-byte fixed header from a MseedHeader.
///
/// The builder emits the header only (the caller appends the payload).
/// Sequence, station, channel, network and location are written in order and
/// space-padded to their field widths; the unused byte (27) and the two
/// reserved bytes (46..47) are written as 0; every other field is written as
/// given. `record_size` is not encoded, but it is validated against the data
/// offset so a header cannot claim a payload past its own record.
///
/// Validation order (first failure wins): sequence longer than 6 bytes or
/// outside digits/spaces -> `miniseed: bad sequence number`; quality not in
/// {D, R, Q, M, space} -> `miniseed: bad quality indicator`; reserved not in
/// {0, 32} -> `miniseed: bad reserved byte`; station/channel/network/
/// location longer than its width or outside 0x20..0x7E -> `miniseed: bad
/// station` (and the matching channel/network/location errors); year outside
/// 0..65535 -> `miniseed: bad year`; day outside 1..366 or day 366 in a
/// non-leap year -> `miniseed: bad day`; hour > 23 -> `miniseed: bad hour`;
/// minute > 59 -> `miniseed: bad minute`; second > 60 -> `miniseed: bad
/// second`; tenths > 9999 -> `miniseed: bad tenths`; factor or multiplier
/// outside -32768..32767 -> `miniseed: bad sample rate`; a flag byte or the
/// blockette count outside 0..255 -> `miniseed: bad flags`; time correction
/// outside -2^31..2^31-1 -> `miniseed: bad time correction`;
/// begin_data_offset < 48 -> `miniseed: bad data offset`; a blockette offset
/// that is neither 0 nor inside 48..record_size, or a nonzero blockette
/// count with a zero offset -> `miniseed: bad blockette offset`;
/// record_size < 48 or < begin_data_offset -> `miniseed: bad record size`.
///
/// Params: h - the header source, read only.
/// Returns: Ok(bytes), exactly 48 bytes, big-endian.
/// Error case: see the catalog above and SPEC.md.
/// Complexity: O(48).
pub fn miniseed_build(h: &MseedHeader) -> Result[Vec[UInt8], Str] {
  let seq: Str = h.sequence;
  if seq.len() > _MS_SEQ_LEN { return _err_bytes("miniseed: bad sequence number"); }
  var i = 0;
  while i < seq.len() {
    if !_is_digit_or_space((string.byte_at(seq, i) as Int) & _MS_BYTE_MASK) {
      return _err_bytes("miniseed: bad sequence number");
    }
    i = i + 1;
  }
  let quality: Int = h.quality;
  if !_quality_ok(quality) { return _err_bytes("miniseed: bad quality indicator"); }
  let reserved: Int = h.reserved;
  if reserved != _MS_SPACE && reserved != 0 {
    return _err_bytes("miniseed: bad reserved byte");
  }
  let station: Str = h.station;
  if !_str_ok(station, _MS_STATION_LEN) { return _err_bytes("miniseed: bad station"); }
  let channel: Str = h.channel;
  if !_str_ok(channel, _MS_CHANNEL_LEN) { return _err_bytes("miniseed: bad channel"); }
  let network: Str = h.network;
  if !_str_ok(network, _MS_NETWORK_LEN) { return _err_bytes("miniseed: bad network"); }
  let location: Str = h.location;
  if !_str_ok(location, _MS_LOCATION_LEN) { return _err_bytes("miniseed: bad location"); }
  let year: Int = h.year;
  if year < 0 || year > 65535 { return _err_bytes("miniseed: bad year"); }
  let day: Int = h.day;
  if !_day_ok(year, day) { return _err_bytes("miniseed: bad day"); }
  let hour: Int = h.hour;
  if hour < 0 || hour > _MS_MAX_HOUR { return _err_bytes("miniseed: bad hour"); }
  let minute: Int = h.minute;
  if minute < 0 || minute > _MS_MAX_MINUTE { return _err_bytes("miniseed: bad minute"); }
  let second: Int = h.second;
  if second < 0 || second > _MS_MAX_SECOND { return _err_bytes("miniseed: bad second"); }
  let tenths: Int = h.tenths;
  if tenths < 0 || tenths > _MS_MAX_TENTHS { return _err_bytes("miniseed: bad tenths"); }
  let factor: Int = h.sample_rate_factor;
  let multiplier: Int = h.sample_rate_multiplier;
  if factor < _MS_I16_MIN || factor > _MS_I16_MAX { return _err_bytes("miniseed: bad sample rate"); }
  if multiplier < _MS_I16_MIN || multiplier > _MS_I16_MAX { return _err_bytes("miniseed: bad sample rate"); }
  let activity: Int = h.activity_flags;
  let io_flags: Int = h.io_flags;
  let dq_flags: Int = h.data_quality_flags;
  let nblk: Int = h.num_blockettes;
  if !_u8_ok(activity) || !_u8_ok(io_flags) || !_u8_ok(dq_flags) || !_u8_ok(nblk) {
    return _err_bytes("miniseed: bad flags");
  }
  let tc: Int = h.time_correction;
  if tc < _MS_I32_MIN || tc > _MS_I32_MAX { return _err_bytes("miniseed: bad time correction"); }
  let bdo: Int = h.begin_data_offset;
  if bdo < _MS_HEADER_LEN { return _err_bytes("miniseed: bad data offset"); }
  let bbo: Int = h.begin_blockette_offset;
  let rs: Int = h.record_size;
  if bbo != 0 {
    if bbo < _MS_HEADER_LEN { return _err_bytes("miniseed: bad blockette offset"); }
    if bbo > rs { return _err_bytes("miniseed: bad blockette offset"); }
  }
  if nblk > 0 && bbo == 0 { return _err_bytes("miniseed: bad blockette offset"); }
  if rs < _MS_HEADER_LEN || rs < bdo { return _err_bytes("miniseed: bad record size"); }
  var out = Vec[UInt8].new();
  _push_padded(&mut out, seq, _MS_SEQ_LEN);
  out.push(quality as UInt8);
  out.push(reserved as UInt8);
  _push_padded(&mut out, station, _MS_STATION_LEN);
  _push_padded(&mut out, channel, _MS_CHANNEL_LEN);
  _push_padded(&mut out, network, _MS_NETWORK_LEN);
  _push_padded(&mut out, location, _MS_LOCATION_LEN);
  _push_be16(&mut out, year);
  _push_be16(&mut out, day);
  out.push(hour as UInt8);
  out.push(minute as UInt8);
  out.push(second as UInt8);
  out.push(0 as UInt8);
  _push_be16(&mut out, tenths);
  _push_be16(&mut out, factor);
  _push_be16(&mut out, multiplier);
  out.push(activity as UInt8);
  out.push(io_flags as UInt8);
  out.push(dq_flags as UInt8);
  out.push(nblk as UInt8);
  _push_be32(&mut out, tc);
  _push_be16(&mut out, bdo);
  _push_be16(&mut out, bbo);
  _push_be16(&mut out, 0);
  return _ok_bytes(out);
}
