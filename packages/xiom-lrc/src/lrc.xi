// XIOM -- xiom.lrc: LRC synced-lyrics parsing and canonical emitting
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, in-memory Str only: no FFI, no file I/O, no audio, no rendering
// and no encoding conversion (bytes pass through unchanged).
//
// Documented subset (full statement in SPEC.md):
//
//   document = *( blank / tagline / timeline / untimed )
//   tagline  = "[" name ":" value "]" *any        ; bytes after "]" ignored
//   timeline = timestamp *( "[" timestamp "]" ) text
//   timestamp= 2DIGIT ":" 2DIGIT "." frac
//   frac     = 2DIGIT | 3DIGIT                    ; centis | millis
//   name     = "ti" | "ar" | "al" | "by" | "offset"
//   offset   = [ "+" | "-" ] 1*18DIGIT            ; signed milliseconds
//   blank    = (no bytes)
//   untimed  = non-blank line not starting with "["  ; skipped
//
// Model: entries are flat and index-aligned -- `times` holds each entry time
// in whole milliseconds, `texts` the text after the last timestamp on its
// line -- plus the five documented metadata tags. The document offset is
// stored, not baked into the times (see lrc_offset_ms and
// lrc_adjusted_time_ms). Entries keep source order; a line with several
// timestamps appends one entry per timestamp in field order and is never
// sorted by time.
//
// v0.61.3 notes that shaped this module (see SPEC.md section 9):
//   * Free functions only; all scanning goes through _byte() as Int, so no
//     UInt8 constant >= 128 is ever involved in a comparison.
//   * Ok/Err for Result[Lyrics, Str] are constructed only in the leaf
//     helpers _ok_lyrics/_err_lyrics; the Lyrics literal itself is built
//     only by _make_lyrics.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec element reads bind a typed local first.
//   * No Vec[StructType], no match, no lambdas: entries are two parallel
//     Vecs, parsing is if/elif/while only.
//
// See SPEC.md for the grammar, error catalog, round-trip rules and test plan.

module xiom.lrc

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed LRC document: the five supported metadata tags, the signed
/// document offset in milliseconds, and index-aligned entry arrays.
/// Invariants for a value produced by `lrc_parse`: `times.len()` equals
/// `texts.len()` (the entry count); every `times[i]` is in 0..3599999 (the
/// parser rejects mm/ss above 59); `times` is in source order, not sorted.
pub type Lyrics = {
  title: Str;
  artist: Str;
  album: Str;
  by_text: Str;
  offset_ms: Int;
  times: Vec[Int];
  texts: Vec[Str];
}

// --------------------------------------------------
//  Byte constants (Int, see the module header)
// --------------------------------------------------

const _LF: Int = 10;
const _CR: Int = 13;
const _PLUS: Int = 43;
const _MINUS: Int = 45;
const _DOT: Int = 46;
const _COLON: Int = 58;
const _ZERO: Int = 48;
const _NINE: Int = 57;
const _OPEN: Int = 91;
const _CLOSE: Int = 93;
const _MAX_OFFSET_DIGITS: Int = 18;

// _ts_ms() return codes for malformed timestamps (valid results are >= 0).
const _TS_BAD_SHAPE: Int = -1;
const _TS_OUT_OF_RANGE: Int = -2;
const _TS_BAD_FRACTION: Int = -3;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// The one place a Lyrics value is assembled from the flat fields.
fn _make_lyrics(title: Str, artist: Str, album: Str, by_text: Str,
                offset_ms: Int, times: Vec[Int], texts: Vec[Str]) -> Lyrics {
  return Lyrics{
    title: title;
    artist: artist;
    album: album;
    by_text: by_text;
    offset_ms: offset_ms;
    times: times;
    texts: texts;
  };
}

// Ok(l) for Result[Lyrics, Str].
fn _ok_lyrics(l: Lyrics) -> Result[Lyrics, Str] {
  return Ok(l);
}

// Err(m) for Result[Lyrics, Str].
fn _err_lyrics(m: Str) -> Result[Lyrics, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal text helpers
// --------------------------------------------------

// Byte `pos` of `s` as an Int (0..255). Callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return string.byte_at(s, pos) as Int;
}

// Split `text` into lines on LF. A CR immediately before an LF is dropped,
// and one trailing CR at the very end of an unterminated final line is
// dropped too, so CRLF documents produce the same lines as LF documents and
// no line ever ends with CR. A trailing LF does not produce a final empty
// line. A lone CR elsewhere stays inside the line.
fn _split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var start = 0;
  var i = 0;
  while i < len {
    if _byte(text, i) == _LF {
      var end = i;
      if end > start && _byte(text, end - 1) == _CR { end = end - 1; }
      out.push(string.str_slice(text, start, end));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < len {
    var end = len;
    if end > start && _byte(text, end - 1) == _CR { end = end - 1; }
    out.push(string.str_slice(text, start, end));
  }
  return out;
}

// Index of the first byte equal to `want` at or after `from` in `s`, or -1
// when absent (including when `from` is at or past the end).
fn _find_byte_from(s: Str, from: Int, want: Int) -> Int {
  let len = s.len();
  var i = from;
  while i < len {
    if _byte(s, i) == want { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `s` is non-empty and its first byte is an ASCII digit. A bracket
// field whose first byte is a digit must be a timestamp, so this decides the
// tag/timestamp split.
fn _first_is_digit(s: Str) -> Bool {
  if s.len() == 0 { return false; }
  let c = _byte(s, 0);
  return c >= _ZERO && c <= _NINE;
}

// True when the `count` bytes of `s` starting at `from` are all ASCII digits.
// Callers guarantee the range is inside `s`.
fn _digits_at(s: Str, from: Int, count: Int) -> Bool {
  var i = 0;
  while i < count {
    let c = _byte(s, from + i);
    if c < _ZERO || c > _NINE { return false; }
    i = i + 1;
  }
  return true;
}

// Value of the two ASCII digits of `s` at `pos`. Callers validate them.
fn _two_digit_value(s: Str, pos: Int) -> Int {
  return (_byte(s, pos) - _ZERO) * 10 + (_byte(s, pos + 1) - _ZERO);
}

// Value of `count` ASCII digits of `s` starting at `pos`. Callers validate
// them and guarantee `count <= 3`.
fn _frac_value(s: Str, pos: Int, count: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < count {
    v = v * 10 + (_byte(s, pos + i) - _ZERO);
    i = i + 1;
  }
  return v;
}

// Whole milliseconds of a timestamp field body `mm:ss.xx` / `mm:ss.xxx`.
// Returns the millisecond value on success, or one of the _TS_* codes;
// shape is checked first, then mm/ss range, then fraction length.
fn _ts_ms(t: Str) -> Int {
  let len = t.len();
  if len < 7 { return _TS_BAD_SHAPE; }
  if _byte(t, 2) != _COLON { return _TS_BAD_SHAPE; }
  if _byte(t, 5) != _DOT { return _TS_BAD_SHAPE; }
  if !_digits_at(t, 0, 2) { return _TS_BAD_SHAPE; }
  if !_digits_at(t, 3, 2) { return _TS_BAD_SHAPE; }
  if !_digits_at(t, 6, len - 6) { return _TS_BAD_SHAPE; }
  let mm = _two_digit_value(t, 0);
  let ss = _two_digit_value(t, 3);
  if mm > 59 || ss > 59 { return _TS_OUT_OF_RANGE; }
  let frac_len = len - 6;
  if frac_len != 2 && frac_len != 3 { return _TS_BAD_FRACTION; }
  let frac = _frac_value(t, 6, frac_len);
  if frac_len == 2 { return mm * 60000 + ss * 1000 + frac * 10; }
  return mm * 60000 + ss * 1000 + frac;
}

// True when `v` is a valid [offset:] value: an optional '+' or '-' followed
// by 1..18 ASCII digits, with no whitespace and no other bytes. The 18-digit
// cap keeps the accumulated value inside Int range.
fn _offset_shape_ok(v: Str) -> Bool {
  let len = v.len();
  if len == 0 { return false; }
  var i = 0;
  let b0 = _byte(v, 0);
  if b0 == _PLUS || b0 == _MINUS { i = 1; }
  if i >= len { return false; }
  if len - i > _MAX_OFFSET_DIGITS { return false; }
  var j = i;
  while j < len {
    let c = _byte(v, j);
    if c < _ZERO || c > _NINE { return false; }
    j = j + 1;
  }
  return true;
}

// Signed value of a [offset:] body `v`. Callers validate it first with
// _offset_shape_ok, so `v` is non-empty and sign + digits only.
fn _offset_value(v: Str) -> Int {
  let len = v.len();
  var i = 0;
  var neg = false;
  let b0 = _byte(v, 0);
  if b0 == _MINUS { neg = true; i = 1; } elif b0 == _PLUS { i = 1; }
  var acc = 0;
  while i < len {
    acc = acc * 10 + (_byte(v, i) - _ZERO);
    i = i + 1;
  }
  if neg { return 0 - acc; }
  return acc;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one LRC document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Lyrics) for a valid document, including an empty one.
/// Grammar and decisions (full statement in SPEC.md):
///   * Lines are split on LF; a CR before LF (and a single trailing CR at
///     end of input) is removed. Blank lines are skipped.
///   * A line starting with "[" is a tag line or a timestamp line. The field
///     is closed by the first "]"; a missing "]" is "lrc: unclosed bracket",
///     checked before any classification.
///   * A field whose first byte is a digit must be `mm:ss.xx` or
///     `mm:ss.xxx`: exactly two digits, ":", two digits, ".", then two or
///     three digits. Malformed shape is "lrc: bad timestamp shape", mm or ss
///     above 59 is "lrc: time out of range" (checked before the fraction),
///     and a fraction length other than 2 or 3 is
///     "lrc: bad fraction length". Two fraction digits are centiseconds,
///     three are milliseconds.
///   * A timestamp line may carry several timestamp fields; each appends one
///     entry, in field order, with the text after the last "]" (verbatim,
///     possibly empty) as its text.
///   * Any other bracket field is a metadata tag `name:value` with `name` in
///     `ti`, `ar`, `al`, `by`, `offset`. Without a colon the error is
///     "lrc: tag missing colon"; an unrecognized name is
///     "lrc: unknown tag: [<field>]". Bytes after a tag's closing "]" are
///     ignored.
///   * `offset` takes an optional sign and 1..18 digits in milliseconds;
///     anything else is "lrc: bad offset value". A repeated tag overwrites
///     the earlier value (last one wins).
///   * A non-blank line not starting with "[" is untimed and is skipped.
///   * The offset is stored, not applied: see lrc_offset_ms and
///     lrc_adjusted_time_ms. Entries keep source order (never sorted).
/// Complexity: O(input length).
pub fn lrc_parse(text: Str) -> Result[Lyrics, Str] {
  var title = "";
  var artist = "";
  var album = "";
  var by_text = "";
  var offset_ms = 0;
  var times = Vec[Int].new();
  var texts = Vec[Str].new();
  let lines = _split_lines(text);
  let n = lines.len();
  var i = 0;
  while i < n {
    let line: Str = lines[i];
    let len = line.len();
    if len > 0 && _byte(line, 0) == _OPEN {
      let first_close = _find_byte_from(line, 1, _CLOSE);
      if first_close < 0 { return _err_lyrics("lrc: unclosed bracket"); }
      let first = string.str_slice(line, 1, first_close);
      if _first_is_digit(first) {
        // Timestamp line: collect the fields, then append one entry per
        // field with the shared verbatim text after the last "]".
        var line_times = Vec[Int].new();
        var pos = 0;
        while pos < len && _byte(line, pos) == _OPEN {
          let close = _find_byte_from(line, pos + 1, _CLOSE);
          if close < 0 { return _err_lyrics("lrc: unclosed bracket"); }
          let field = string.str_slice(line, pos + 1, close);
          let ms = _ts_ms(field);
          if ms == _TS_BAD_SHAPE { return _err_lyrics("lrc: bad timestamp shape"); }
          if ms == _TS_OUT_OF_RANGE { return _err_lyrics("lrc: time out of range"); }
          if ms == _TS_BAD_FRACTION { return _err_lyrics("lrc: bad fraction length"); }
          line_times.push(ms);
          pos = close + 1;
        }
        let text = string.str_slice(line, pos, len);
        var k = 0;
        while k < line_times.len() {
          let tv: Int = line_times[k];
          times.push(tv);
          texts.push(text);
          k = k + 1;
        }
      } else {
        // Metadata tag line: the first field decides; the rest is ignored.
        let colon = _find_byte_from(first, 0, _COLON);
        if colon < 0 { return _err_lyrics("lrc: tag missing colon"); }
        let name = string.str_slice(first, 0, colon);
        let value = string.str_slice(first, colon + 1, first.len());
        if compare.str_compare(name, "ti") == 0 {
          title = value;
        } elif compare.str_compare(name, "ar") == 0 {
          artist = value;
        } elif compare.str_compare(name, "al") == 0 {
          album = value;
        } elif compare.str_compare(name, "by") == 0 {
          by_text = value;
        } elif compare.str_compare(name, "offset") == 0 {
          if !_offset_shape_ok(value) { return _err_lyrics("lrc: bad offset value"); }
          offset_ms = _offset_value(value);
        } else {
          return _err_lyrics("lrc: unknown tag: [" + first + "]");
        }
      }
    }
    // Untimed lines (including blank and whitespace-only lines) are skipped.
    i = i + 1;
  }
  return _ok_lyrics(_make_lyrics(title, artist, album, by_text, offset_ms,
                                 times, texts));
}

// Decimal formatting for non-negative values; local so the module needs no
// conversion imports.
fn _int_str(n: Int) -> Str {
  if n <= 0 { return "0"; }
  var digits = Vec[Int].new();
  var x = n;
  while x > 0 {
    let d: Int = x % 10;
    digits.push(d);
    x = x / 10;
  }
  var out = "";
  var i = digits.len() - 1;
  while i >= 0 {
    let d: Int = digits[i];
    out = out + string.str_slice("0123456789", d, d + 1);
    i = i - 1;
  }
  return out;
}

// Zero-padded to at least two digits.
fn _pad2(n: Int) -> Str {
  let s = _int_str(n);
  if n < 10 { return "0" + s; }
  return s;
}

// Zero-padded to at least three digits.
fn _pad3(n: Int) -> Str {
  if n < 10 { return "00" + _int_str(n); }
  if n < 100 { return "0" + _int_str(n); }
  return _int_str(n);
}

// An explicit-sign decimal form, used for the canonical [offset:...] tag.
fn _signed_int_str(n: Int) -> Str {
  if n < 0 { return "-" + _int_str(0 - n); }
  return "+" + _int_str(n);
}

// Canonical timestamp field "[mm:ss.xx]" / "[mm:ss.xxx]": minutes and seconds
// are two digits; the fraction is centis when the millisecond remainder is a
// whole number of centiseconds, millis otherwise, so the exact time survives
// a round trip. Negative values clamp to zero. Minutes above 99 print with
// extra digits, which the parser then rejects (documented limitation).
fn _fmt_time(ms: Int) -> Str {
  var t = ms;
  if t < 0 { t = 0; }
  let mm = t / 60000;
  let ss = (t / 1000) % 60;
  let rem = t % 1000;
  var out = "[";
  out = out + _pad2(mm);
  out = out + ":";
  out = out + _pad2(ss);
  out = out + ".";
  if rem % 10 == 0 {
    out = out + _pad2(rem / 10);
  } else {
    out = out + _pad3(rem);
  }
  out = out + "]";
  return out;
}

/// Emit one Lyrics document in canonical form.
/// Params: l - the lyrics to serialize.
/// Returns: the metadata tags in the fixed order `ti`, `ar`, `al`, `by`,
/// `offset`, each written only when present (non-empty string, non-zero
/// offset); then the entries in stored source order, one
/// `[mm:ss.xx]text` (or `.xxx`) line each. `offset` always carries an
/// explicit sign. Every line is LF-terminated; a document with no metadata
/// and no entries emits "". Blank-line layout, unknown tags (which the
/// parser rejects) and untimed lines are not represented.
/// Error case: none.
/// Complexity: O(total output length).
pub fn lrc_emit(l: &Lyrics) -> Str {
  var out = "";
  if l.title.len() > 0 { out = out + "[ti:" + l.title + "]\n"; }
  if l.artist.len() > 0 { out = out + "[ar:" + l.artist + "]\n"; }
  if l.album.len() > 0 { out = out + "[al:" + l.album + "]\n"; }
  if l.by_text.len() > 0 { out = out + "[by:" + l.by_text + "]\n"; }
  if l.offset_ms != 0 {
    out = out + "[offset:" + _signed_int_str(l.offset_ms) + "]\n";
  }
  let n = l.times.len();
  var i = 0;
  while i < n {
    let t: Int = l.times[i];
    let tx: Str = l.texts[i];
    out = out + _fmt_time(t);
    out = out + tx;
    out = out + "\n";
    i = i + 1;
  }
  return out;
}

/// Number of timed entries. `lrc_parse` never returns a document with more
/// than one entry per timestamp field.
pub fn lrc_entry_count(l: &Lyrics) -> Int {
  return l.times.len();
}

/// Raw time of entry `i` in whole milliseconds (offset not applied); -1 when
/// `i` is negative or out of range. Use `lrc_adjusted_time_ms` for the
/// offset-applied time.
pub fn lrc_time_ms(l: &Lyrics, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= l.times.len() { return -1; }
  let v: Int = l.times[i];
  return v;
}

/// Time of entry `i` with the document offset applied, clamped at 0; -1 when
/// `i` is negative or out of range.
pub fn lrc_adjusted_time_ms(l: &Lyrics, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= l.times.len() { return -1; }
  let v: Int = l.times[i];
  var t = v + l.offset_ms;
  if t < 0 { t = 0; }
  return t;
}

/// Text of entry `i` (verbatim, possibly empty); "" when `i` is negative or
/// out of range.
pub fn lrc_text(l: &Lyrics, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= l.texts.len() { return ""; }
  let v: Str = l.texts[i];
  return v;
}

/// The `[ti:...]` title; "" when the document has no title tag.
pub fn lrc_title(l: &Lyrics) -> Str {
  return l.title;
}

/// The `[ar:...]` artist; "" when the document has no artist tag.
pub fn lrc_artist(l: &Lyrics) -> Str {
  return l.artist;
}

/// The `[al:...]` album; "" when the document has no album tag.
pub fn lrc_album(l: &Lyrics) -> Str {
  return l.album;
}

/// The `[by:...]` writer/attribution; "" when the document has no by tag.
pub fn lrc_by(l: &Lyrics) -> Str {
  return l.by_text;
}

/// The signed `[offset:...]` value in milliseconds (0 when absent). The
/// offset is stored, not applied to `lrc_time_ms`.
pub fn lrc_offset_ms(l: &Lyrics) -> Int {
  return l.offset_ms;
}
