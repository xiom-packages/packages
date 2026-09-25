// XIOM -- xiom.m3u: M3U/M3U8 playlist parsing and canonical emitting
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, in-memory Str only: no FFI, no file I/O, no URL validation
// beyond a non-empty path, and no HLS playback semantics. The codec covers
// the line grammar shared by plain M3U and extended M3U:
//
//   document = *blank [ "#EXTM3U" LF ] *( blank / tag / extinf / path )
//   tag      = "#" *( byte except LF )     ; preserved verbatim
//   extinf   = "#EXTINF:" seconds "," title
//   seconds  = 1*18DIGIT                   ; non-negative, no sign and no
//                                            decimal point
//   title    = *( byte except LF )         ; verbatim, may be empty
//   path     = 1*( byte except LF )        ; verbatim, never starts "#"
//   blank    = (no bytes)
//
// Model: entries are flat and index-aligned. `durations`, `titles`, `paths`,
// `tag_starts` and `tag_ends` all have the entry count as length. Entry i is
// path paths[i] with #EXTINF duration durations[i] seconds (-1 = no #EXTINF)
// and title titles[i]; its preceding raw tag lines are
// tags[tag_starts[i] .. tag_ends[i]]. Those ranges tile the tags vector
// prefix, so tags after tag_ends[last] are trailing tags (for example
// #EXT-X-ENDLIST). Vec[StructType] is unsupported in this compiler, hence
// the parallel Vecs with per-entry ranges instead of a list of entries.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[Playlist, Str] are constructed only in the leaf
//     helpers _ok_playlist/_err_playlist; the Playlist literal itself is
//     built only by _make_playlist.
//   * Every input byte is read through _byte() as an Int, so no UInt8
//     constant >= 128 is ever involved in a comparison.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec element reads always bind a typed local first.
//
// See SPEC.md for the grammar, error catalog, round-trip rules, test plan.

module xiom.m3u

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed playlist: parallel per-entry arrays plus one raw-line tag store.
/// Invariants for a value produced by `m3u_parse`: the five per-entry Vecs
/// all have the entry count as length; `tag_starts[i] <= tag_ends[i]`; the
/// ranges tile the tags prefix (`tag_starts[i] == tag_ends[i - 1]` and
/// `tag_starts[0] == 0`); `tags` after `tag_ends[last]` are trailing tags.
/// `durations[i]` is -1 when entry i had no #EXTINF; otherwise it is a
/// non-negative whole number of seconds.
pub type Playlist = {
  has_header: Bool;
  durations: Vec[Int];
  titles: Vec[Str];
  paths: Vec[Str];
  tag_starts: Vec[Int];
  tag_ends: Vec[Int];
  tags: Vec[Str];
}

// --------------------------------------------------
//  Byte constants (Int, see the module header)
// --------------------------------------------------

const _LF: Int = 10;
const _CR: Int = 13;
const _HASH: Int = 35;
const _COMMA: Int = 44;
const _ZERO: Int = 48;
const _NINE: Int = 57;
const _MAX_DURATION_DIGITS: Int = 18;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// The one place a Playlist value is assembled from the parallel Vecs.
fn _make_playlist(has_header: Bool, durations: Vec[Int], titles: Vec[Str],
                  paths: Vec[Str], tag_starts: Vec[Int], tag_ends: Vec[Int],
                  tags: Vec[Str]) -> Playlist {
  return Playlist{
    has_header: has_header;
    durations: durations;
    titles: titles;
    paths: paths;
    tag_starts: tag_starts;
    tag_ends: tag_ends;
    tags: tags;
  };
}

// Ok(p) for Result[Playlist, Str].
fn _ok_playlist(p: Playlist) -> Result[Playlist, Str] {
  return Ok(p);
}

// Err(m) for Result[Playlist, Str].
fn _err_playlist(m: Str) -> Result[Playlist, Str] {
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

// Index of the first byte equal to `want` in `s`, or -1 when absent.
fn _find_byte(s: Str, want: Int) -> Int {
  let len = s.len();
  var i = 0;
  while i < len {
    if _byte(s, i) == want {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Parse one #EXTINF seconds field to whole seconds, or -1 when it is not
// 1..18 ASCII digits. Empty, signed, whitespace-padded and decimal (floating
// point) durations are all rejected; leading zeros are accepted. The 18-digit
// cap keeps the accumulation below Int range, so the result is exact.
fn _parse_seconds(s: Str) -> Int {
  let len = s.len();
  if len == 0 { return -1; }
  if len > _MAX_DURATION_DIGITS { return -1; }
  var v = 0;
  var i = 0;
  while i < len {
    let c = _byte(s, i);
    if c < _ZERO || c > _NINE { return -1; }
    v = v * 10 + (c - _ZERO);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one M3U/M3U8 document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Playlist) for a valid document (including an empty one).
/// Grammar and decisions (full statement in SPEC.md):
///   * The `#EXTM3U` header is optional. It is recognized only as the first
///     non-blank line; blank lines before it are allowed. `#EXTM3U` anywhere
///     else is preserved as an ordinary raw tag, so a path line before the
///     header is accepted (plain M3U) and documented.
///   * A `#EXTINF:` line must be `#EXTINF:<digits>,<title>`: 1..18 ASCII
///     digits, no sign, no decimal point (float durations are rejected), no
///     whitespace; the title is the verbatim remainder after the first comma
///     and may be empty. A line whose first seven bytes are `#EXTINF` but
///     which is not that form is an "m3u: bad #EXTINF: ..." error.
///   * Every other line starting with `#` (for example `#EXT-X-VERSION:3`,
///     `#EXT-X-ENDLIST` or a plain comment) is preserved verbatim as a raw
///     tag. A path line never starts with `#`.
///   * A non-blank line that does not start with `#` is a path: it is stored
///     verbatim (no trimming, no URL validation beyond being non-empty, no
///     file existence check).
///   * Blank lines are ignored everywhere, including between `#EXTINF` and
///     its path. Tags and comments may also sit between them; they stay
///     attached to the entry as preceding tags.
/// Errors: "m3u: bad #EXTINF: <line>", "m3u: bad duration in #EXTINF: <line>",
/// "m3u: missing path after #EXTINF"; see SPEC.md.
/// Complexity: O(input length).
pub fn m3u_parse(text: Str) -> Result[Playlist, Str] {
  var has_header = false;
  var seen_nonblank = false;
  var durations = Vec[Int].new();
  var titles = Vec[Str].new();
  var paths = Vec[Str].new();
  var tag_starts = Vec[Int].new();
  var tag_ends = Vec[Int].new();
  var tags = Vec[Str].new();
  var tag_mark = 0;
  var pending_extinf = false;
  var pending_dur = -1;
  var pending_title = "";
  let lines = _split_lines(text);
  let n = lines.len();
  var i = 0;
  while i < n {
    let line: Str = lines[i];
    let len = line.len();
    if len > 0 {
      let was_first = !seen_nonblank;
      seen_nonblank = true;
      let b0 = _byte(line, 0);
      if b0 == _HASH {
        if was_first && compare.str_compare(line, "#EXTM3U") == 0 {
          has_header = true;
        } elif string.str_starts_with(line, "#EXTINF:") {
          if pending_extinf {
            return _err_playlist("m3u: missing path after #EXTINF");
          }
          let body = string.str_slice(line, 8, len);
          let comma = _find_byte(body, _COMMA);
          if comma < 0 {
            return _err_playlist("m3u: bad #EXTINF: " + line);
          }
          let dur_text = string.str_slice(body, 0, comma);
          let seconds = _parse_seconds(dur_text);
          if seconds < 0 {
            return _err_playlist("m3u: bad duration in #EXTINF: " + line);
          }
          pending_dur = seconds;
          pending_title = string.str_slice(body, comma + 1, body.len());
          pending_extinf = true;
        } elif string.str_starts_with(line, "#EXTINF") {
          return _err_playlist("m3u: bad #EXTINF: " + line);
        } else {
          tags.push(line);
        }
      } else {
        durations.push(pending_dur);
        titles.push(pending_title);
        paths.push(line);
        tag_starts.push(tag_mark);
        tag_ends.push(tags.len());
        tag_mark = tags.len();
        pending_extinf = false;
        pending_dur = -1;
        pending_title = "";
      }
    }
    i = i + 1;
  }
  if pending_extinf {
    return _err_playlist("m3u: missing path after #EXTINF");
  }
  return _ok_playlist(_make_playlist(has_header, durations, titles, paths,
                                     tag_starts, tag_ends, tags));
}

/// Emit one playlist in canonical extended-M3U form.
/// Params: p - the playlist to serialize.
/// Returns: text starting with the `#EXTM3U` header line (always written,
/// even when the parsed input had no header), then for each entry its
/// preceding raw tags in stored order, `#EXTINF:<seconds>,<title>` when the
/// duration is >= 0, and the path; trailing tags follow the last path. Every
/// line is LF-terminated, so the result always ends with LF and an empty
/// playlist emits "#EXTM3U\n". A negative duration is treated as "no
/// #EXTINF" and skipped. Blank-line input layout is not preserved.
/// Error case: none.
/// Complexity: O(total output length).
pub fn m3u_emit(p: &Playlist) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "#EXTM3U\n");
  let n = p.paths.len();
  var i = 0;
  while i < n {
    let a: Int = p.tag_starts[i];
    let b: Int = p.tag_ends[i];
    var j = a;
    while j < b {
      let t: Str = p.tags[j];
      builder.sb_push_str(&mut out, t);
      out.push(10u8);
      j = j + 1;
    }
    let d: Int = p.durations[i];
    if d >= 0 {
      builder.sb_push_str(&mut out, "#EXTINF:");
      builder.sb_push_int(&mut out, d);
      out.push(44u8);
      let ti: Str = p.titles[i];
      builder.sb_push_str(&mut out, ti);
      out.push(10u8);
    }
    let pa: Str = p.paths[i];
    builder.sb_push_str(&mut out, pa);
    out.push(10u8);
    i = i + 1;
  }
  var base = 0;
  let tn = p.tag_ends.len();
  if tn > 0 {
    let last: Int = p.tag_ends[tn - 1];
    base = last;
  }
  var k = base;
  while k < p.tags.len() {
    let t: Str = p.tags[k];
    builder.sb_push_str(&mut out, t);
    out.push(10u8);
    k = k + 1;
  }
  return builder.sb_to_str(&out);
}

/// Number of entries (path lines) in the playlist.
pub fn m3u_entry_count(p: &Playlist) -> Int {
  return p.paths.len();
}

/// True when the parsed document began with a `#EXTM3U` header line.
pub fn m3u_has_header(p: &Playlist) -> Bool {
  return p.has_header;
}

/// Whole-second duration of entry `i`; -1 when `i` is out of range or when
/// the entry had no `#EXTINF`. Durations are never negative after parsing,
/// so -1 is an unambiguous "absent" sentinel.
pub fn m3u_duration_seconds(p: &Playlist, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= p.durations.len() { return -1; }
  let v: Int = p.durations[i];
  return v;
}

/// Title of entry `i` from its `#EXTINF` line (verbatim, possibly empty);
/// "" when `i` is out of range.
pub fn m3u_title(p: &Playlist, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= p.titles.len() { return ""; }
  let v: Str = p.titles[i];
  return v;
}

/// Path of entry `i` (verbatim); "" when `i` is out of range.
pub fn m3u_path(p: &Playlist, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= p.paths.len() { return ""; }
  let v: Str = p.paths[i];
  return v;
}

/// Total number of raw tag/comment lines stored in the playlist (both
/// per-entry and trailing).
pub fn m3u_tag_count(p: &Playlist) -> Int {
  return p.tags.len();
}

/// Raw tag/comment line `j` in document order; "" when `j` is out of range.
pub fn m3u_tag(p: &Playlist, j: Int) -> Str {
  if j < 0 { return ""; }
  if j >= p.tags.len() { return ""; }
  let v: Str = p.tags[j];
  return v;
}

/// Number of raw tag/comment lines directly preceding entry `i`; 0 when `i`
/// is out of range.
pub fn m3u_entry_tag_count(p: &Playlist, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= p.tag_starts.len() { return 0; }
  let a: Int = p.tag_starts[i];
  let b: Int = p.tag_ends[i];
  return b - a;
}

/// Raw tag/comment line number `j` of entry `i` (0-based within the entry);
/// "" when `i` or `j` is out of range.
pub fn m3u_entry_tag(p: &Playlist, i: Int, j: Int) -> Str {
  if i < 0 { return ""; }
  if i >= p.tag_starts.len() { return ""; }
  let a: Int = p.tag_starts[i];
  let b: Int = p.tag_ends[i];
  if j < 0 { return ""; }
  if a + j >= b { return ""; }
  let v: Str = p.tags[a + j];
  return v;
}

/// Number of trailing raw tag/comment lines, i.e. tags after the last
/// entry's range (for example a closing `#EXT-X-ENDLIST`). When there are no
/// entries, every stored tag is trailing.
pub fn m3u_trailing_tag_count(p: &Playlist) -> Int {
  var base = 0;
  let n = p.tag_ends.len();
  if n > 0 {
    let last: Int = p.tag_ends[n - 1];
    base = last;
  }
  return p.tags.len() - base;
}

/// Trailing raw tag/comment line `j`; "" when `j` is out of range.
pub fn m3u_trailing_tag(p: &Playlist, j: Int) -> Str {
  let total = m3u_trailing_tag_count(p);
  if j < 0 { return ""; }
  if j >= total { return ""; }
  var base = 0;
  let n = p.tag_ends.len();
  if n > 0 {
    let last: Int = p.tag_ends[n - 1];
    base = last;
  }
  let v: Str = p.tags[base + j];
  return v;
}
