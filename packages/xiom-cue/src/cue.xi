// XIOM -- xiom.cue: CUE sheet parsing and canonical emitting
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, in-memory Str only: no FFI, no file I/O, and no audio-data
// verification, no disc-ID math and no burning. The codec covers a strict,
// documented subset of the CDRWIN/EAC CUE sheet grammar:
//
//   line       = ws* directive ws*              ; ws = SP | TAB
//   directive  = "CATALOG" SP (quoted / 13DIGIT)
//              / "FILE" SP quoted SP type
//              / "TRACK" SP nn SP type
//              / "INDEX" SP nn SP time
//              / "PREGAP" SP time
//              / "POSTGAP" SP time
//              / "PERFORMER" SP (quoted / bare)
//              / "TITLE" SP (quoted / bare)
//              / "SONGWRITER" SP (quoted / bare)
//              / "ISRC" SP (quoted / 12ALNUM)
//              / "REM" [ SP text ]
//   quoted     = '"' *( char / '""' ) '"'       ; "" is a literal quote
//   time       = 2DIGIT ":" 2DIGIT ":" 2DIGIT   ; mm:ss:ff, ff in 00..74
//   nn         = 2DIGIT                          ; tracks 01..99, indexes 00..99
//
// Keywords are case-sensitive uppercase. Every document is parsed into one
// flat element stream; there is no Vec[StructType] (unsupported in this
// compiler), so a parsed sheet is ten parallel Vecs with one slot per
// element. The element kind says which Vecs carry meaning:
//
//   FILE       texts = name, texts2 = type, quoted = 1, files = file ordinal
//   TRACK      nums = number, texts2 = type, files = file ordinal,
//              tracks = own track ordinal
//   INDEX      nums = number, mins/secs/frames = mm/ss/ff,
//              files/tracks = owning file/track ordinals
//   PREGAP     mins/secs/frames, files/tracks
//   POSTGAP    mins/secs/frames, files/tracks
//   PERFORMER  texts = value, quoted = 1 when the source used quotes
//   TITLE      texts = value, quoted flag as above
//   SONGWRITER texts = value, quoted flag as above
//   ISRC       texts = code, quoted flag as above
//   CATALOG    texts = number, quoted flag as above
//   REM        texts = body after "REM", verbatim (never quoted)
//
// TRACK starts a track body; FILE ends it (a multi-file sheet is legal), so
// "the current track" is simply the most recent TRACK after the most recent
// FILE. A track that never receives an INDEX 01 is Err (section 5 of
// SPEC.md); every other structural rule is position based: INDEX, PREGAP,
// POSTGAP and ISRC require a current track, CATALOG requires no current
// track.
//
// v0.61.3 notes that shaped this module (SPEC.md section 9):
//   * Free functions only; no methods, lambdas, match or Vec[StructType].
//   * Ok/Err for Result[Cue, Str] are constructed only in the leaf helpers
//     _ok_cue/_err_cue; the Cue literal itself is built only by _make_cue.
//   * Every input byte is read through _byte() as an Int, so no UInt8
//     constant >= 128 is ever involved in a comparison.
//   * Str values never go through `==`; keyword dispatch uses
//     xiom.string.compare.str_compare, and every Vec element read binds a
//     typed local first.
//   * `&mut Vec` arguments are written as `&mut out` at every call site.
//   * Input containing a NUL byte is rejected before any slicing, so
//     xiom.string.builder.sb_to_str is never handed a NUL-containing buffer.
//
// See SPEC.md for the exact grammar, the error catalog, the round-trip rules
// and the test matrix.

module xiom.cue

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Element kinds (public, stable codes)
// --------------------------------------------------

/// Element kind: `FILE "name" type`, top level, starts a new file group.
pub const EK_FILE: Int = 1;
/// Element kind: `TRACK nn type`, starts a track body.
pub const EK_TRACK: Int = 2;
/// Element kind: `INDEX nn mm:ss:ff`, belongs to the current track.
pub const EK_INDEX: Int = 3;
/// Element kind: `PREGAP mm:ss:ff`, belongs to the current track.
pub const EK_PREGAP: Int = 4;
/// Element kind: `POSTGAP mm:ss:ff`, belongs to the current track.
pub const EK_POSTGAP: Int = 5;
/// Element kind: `PERFORMER value` (quoted or bare, either level).
pub const EK_PERFORMER: Int = 6;
/// Element kind: `TITLE value` (quoted or bare, either level).
pub const EK_TITLE: Int = 7;
/// Element kind: `SONGWRITER value` (quoted or bare, either level).
pub const EK_SONGWRITER: Int = 8;
/// Element kind: `REM body`, passed through verbatim.
pub const EK_REM: Int = 9;
/// Element kind: `ISRC code`, track level only.
pub const EK_ISRC: Int = 10;
/// Element kind: `CATALOG number`, top level only (no current track).
pub const EK_CATALOG: Int = 11;

// --------------------------------------------------
//  Byte constants (Int, see the module header)
// --------------------------------------------------

const _TAB: Int = 9;
const _LF: Int = 10;
const _CR: Int = 13;
const _SP: Int = 32;
const _DQ: Int = 34;
const _ZERO: Int = 48;
const _NINE: Int = 57;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed CUE sheet: ten index-aligned Vecs with one slot per element.
/// For a value produced by `cue_parse`, all ten Vecs have length
/// `cue_element_count(c)`, `kinds[i]` is one of the `EK_*` codes, and
/// `files[i]`/`tracks[i]` are the ordinals of the owning FILE/TRACK element
/// (-1 when none). `nums`, `mins`, `secs`, `frames`, `texts`, `texts2` and
/// `quoted` carry meaning per kind as documented in the module header.
pub type Cue = {
  kinds: Vec[Int];
  nums: Vec[Int];
  mins: Vec[Int];
  secs: Vec[Int];
  frames: Vec[Int];
  texts: Vec[Str];
  texts2: Vec[Str];
  quoted: Vec[Int];
  files: Vec[Int];
  tracks: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// The one place a Cue value is assembled from the parallel Vecs.
fn _make_cue(kinds: Vec[Int], nums: Vec[Int], mins: Vec[Int], secs: Vec[Int],
             frames: Vec[Int], texts: Vec[Str], texts2: Vec[Str],
             quoted: Vec[Int], files: Vec[Int], tracks: Vec[Int]) -> Cue {
  return Cue{
    kinds: kinds;
    nums: nums;
    mins: mins;
    secs: secs;
    frames: frames;
    texts: texts;
    texts2: texts2;
    quoted: quoted;
    files: files;
    tracks: tracks;
  };
}

// Ok(c) for Result[Cue, Str].
fn _ok_cue(c: Cue) -> Result[Cue, Str] {
  return Ok(c);
}

// Err(m) for Result[Cue, Str].
fn _err_cue(m: Str) -> Result[Cue, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal text helpers
// --------------------------------------------------

// Byte `pos` of `s` as an Int (0..255). Callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return string.byte_at(s, pos) as Int;
}

// True when `b` is an ASCII digit.
fn _is_digit(b: Int) -> Bool {
  return b >= _ZERO && b <= _NINE;
}

// True when `b` is "A".."Z".
fn _is_upper(b: Int) -> Bool {
  return b >= 65 && b <= 90;
}

// True when `b` is "a".."z".
fn _is_lower(b: Int) -> Bool {
  return b >= 97 && b <= 122;
}

// True when `b` starts an identifier token (letter or underscore).
fn _is_ident_start(b: Int) -> Bool {
  return _is_upper(b) || _is_lower(b) || b == 95;
}

// True when `b` continues an identifier token (letter, digit or underscore).
fn _is_ident_byte(b: Int) -> Bool {
  return _is_ident_start(b) || _is_digit(b);
}

// True when `b` is a space or tab.
fn _is_ws_byte(b: Int) -> Bool {
  return b == _SP || b == _TAB;
}

// Index of the first byte equal to `want` in `s`, or -1 when absent.
fn _find_byte(s: Str, want: Int) -> Int {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == want {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when `s` contains a space or tab.
fn _has_ws(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _is_ws_byte(_byte(s, i)) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// End (exclusive) of the identifier token starting at `start`; `start` must
// be an identifier start byte.
fn _scan_token(s: Str, start: Int) -> Int {
  var i = start;
  while i < s.len() && _is_ident_byte(_byte(s, i)) {
    i = i + 1;
  }
  return i;
}

// Position of the first byte at or after `pos` that is not a space or tab.
fn _skip_ws(s: Str, pos: Int) -> Int {
  var i = pos;
  var go = true;
  while i < s.len() && go {
    if _is_ws_byte(_byte(s, i)) {
      i = i + 1;
    } else {
      go = false;
    }
  }
  return i;
}

// Value of the two ASCII digits at `pos`, or -1 when either byte is not a
// digit or the field does not fit.
fn _parse_two(s: Str, pos: Int) -> Int {
  if pos < 0 {
    return -1;
  }
  if pos + 1 >= s.len() {
    return -1;
  }
  let d1 = _byte(s, pos);
  let d2 = _byte(s, pos + 1);
  if !_is_digit(d1) || !_is_digit(d2) {
    return -1;
  }
  return (d1 - _ZERO) * 10 + (d2 - _ZERO);
}

// Parse a complete "mm:ss:ff" token that must occupy the rest of `s` from
// `pos`. Returns the packed value mm*10000 + ss*100 + ff, or:
//   -1 bad shape (wrong length, missing colons, non-digits)
//   -2 seconds above 59
//   -3 frames above 74
// Minutes are exactly two digits (00..99), so no extra range check is
// possible or needed.
fn _parse_time(s: Str, pos: Int) -> Int {
  if pos < 0 {
    return -1;
  }
  if pos + 8 != s.len() {
    return -1;
  }
  if _byte(s, pos + 2) != 58 || _byte(s, pos + 5) != 58 {
    return -1;
  }
  let mm = _parse_two(s, pos);
  let ss = _parse_two(s, pos + 3);
  let ff = _parse_two(s, pos + 6);
  if mm < 0 || ss < 0 || ff < 0 {
    return -1;
  }
  if ss > 59 {
    return -2;
  }
  if ff > 74 {
    return -3;
  }
  return mm * 10000 + ss * 100 + ff;
}

// Index of the closing quote of the quoted string starting at `start`
// (`s[start]` is '"'), or -1 when the quote is never closed. A doubled quote
// "" inside the string is a literal quote and does not close it.
fn _quoted_end(s: Str, start: Int) -> Int {
  var i = start + 1;
  while i < s.len() {
    if _byte(s, i) == _DQ {
      if i + 1 < s.len() && _byte(s, i + 1) == _DQ {
        i = i + 2;
      } else {
        return i;
      }
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Decoded value of the quoted string `s[start..end]` (both quotes included,
// `end` is the index of the closing quote). `""` decodes to one `"`; every
// other byte is copied verbatim. NUL-free input and exact bounds are
// guaranteed by the caller.
fn _decode_quoted(s: Str, start: Int, end: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = start + 1;
  while i < end {
    if _byte(s, i) == _DQ && i + 1 < end && _byte(s, i + 1) == _DQ {
      out.push(34u8);
      i = i + 2;
    } else {
      out.push(string.byte_at(s, i));
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// True when `s` is exactly 13 ASCII digits (a CATALOG number).
fn _is_catalog(s: Str) -> Bool {
  if s.len() != 13 {
    return false;
  }
  var i = 0;
  while i < 13 {
    if !_is_digit(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly 12 ASCII alphanumerics (an ISRC code).
fn _is_isrc(s: Str) -> Bool {
  if s.len() != 12 {
    return false;
  }
  var i = 0;
  while i < 12 {
    let b = _byte(s, i);
    let ok = _is_digit(b) || _is_upper(b) || _is_lower(b);
    if !ok {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Keyword to element kind; 0 when `kw` is not a known keyword. Keywords are
// case-sensitive uppercase.
fn _kind_of(kw: Str) -> Int {
  if compare.str_compare(kw, "CATALOG") == 0 { return EK_CATALOG; }
  if compare.str_compare(kw, "FILE") == 0 { return EK_FILE; }
  if compare.str_compare(kw, "INDEX") == 0 { return EK_INDEX; }
  if compare.str_compare(kw, "ISRC") == 0 { return EK_ISRC; }
  if compare.str_compare(kw, "PERFORMER") == 0 { return EK_PERFORMER; }
  if compare.str_compare(kw, "POSTGAP") == 0 { return EK_POSTGAP; }
  if compare.str_compare(kw, "PREGAP") == 0 { return EK_PREGAP; }
  if compare.str_compare(kw, "REM") == 0 { return EK_REM; }
  if compare.str_compare(kw, "SONGWRITER") == 0 { return EK_SONGWRITER; }
  if compare.str_compare(kw, "TITLE") == 0 { return EK_TITLE; }
  if compare.str_compare(kw, "TRACK") == 0 { return EK_TRACK; }
  return 0;
}

// Two-digit decimal text for `v` (clamped to 0..99). Used only for the
// "track nn has no INDEX 01" message; the result is NUL-free ASCII.
fn _two_digits_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  _push_two_digits(&mut out, v);
  return builder.sb_to_str(&out);
}

// Append two zero-padded ASCII digits for `v`, clamped to 0..99.
fn _push_two_digits(out: &mut Vec[UInt8], v: Int) {
  var n = v;
  if n < 0 { n = 0; }
  if n > 99 { n = 99; }
  out.push((_ZERO + n / 10) as UInt8);
  out.push((_ZERO + n % 10) as UInt8);
}

// Append "mm:ss:ff" with each component clamped to two digits.
fn _push_time(out: &mut Vec[UInt8], mm: Int, ss: Int, ff: Int) {
  _push_two_digits(out, mm);
  out.push(58u8);
  _push_two_digits(out, ss);
  out.push(58u8);
  _push_two_digits(out, ff);
}

// Append `s` as a quoted CUE string: wrapped in quotes, with each embedded
// quote doubled.
fn _push_quoted(out: &mut Vec[UInt8], s: Str) {
  out.push(34u8);
  var i = 0;
  let n = s.len();
  while i < n {
    if _byte(s, i) == _DQ {
      out.push(34u8);
      out.push(34u8);
    } else {
      out.push(string.byte_at(s, i));
    }
    i = i + 1;
  }
  out.push(34u8);
}

// Append a value according to its stored quoting flag: quoted when `q != 0`,
// raw otherwise.
fn _push_value(out: &mut Vec[UInt8], s: Str, q: Int) {
  if q != 0 {
    _push_quoted(out, s);
  } else {
    builder.sb_push_str(out, s);
  }
}

// --------------------------------------------------
//  Public API -- parse and emit
// --------------------------------------------------

/// Parse one CUE sheet document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Cue) for a structurally valid sheet (including an empty one);
/// Err with a "cue: ..." message otherwise. See SPEC.md for the full error
/// catalog. Lines are trimmed of surrounding space/tab, so indentation is
/// insignificant; blank lines are skipped. Each non-blank line is one
/// directive. A quoted value uses `""` for a literal quote and has no other
/// escapes, so backslashes in Windows paths survive verbatim. Every TRACK
/// must receive an INDEX 01 before the next TRACK (or FILE, or EOF), and
/// INDEX/PREGAP/POSTGAP/ISRC require a current track while CATALOG must not
/// follow a TRACK. Track numbers are 01..99 (exactly two digits), index
/// numbers 00..99 (exactly two digits), times mm:ss:ff with ss 00..59 and
/// ff 00..74. Input containing a NUL byte is rejected.
/// Complexity: O(input length).
pub fn cue_parse(text: Str) -> Result[Cue, Str] {
  if _find_byte(text, 0) >= 0 {
    return _err_cue("cue: NUL byte in input");
  }
  var kinds = Vec[Int].new();
  var nums = Vec[Int].new();
  var mins = Vec[Int].new();
  var secs = Vec[Int].new();
  var frames = Vec[Int].new();
  var texts = Vec[Str].new();
  var texts2 = Vec[Str].new();
  var quoted = Vec[Int].new();
  var files = Vec[Int].new();
  var tracks = Vec[Int].new();
  var track_nums = Vec[Int].new();
  var has_index01 = Vec[Int].new();
  var file_ord = -1;
  var track_ord = -1;
  var track_count = 0;
  var in_track = false;
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len {
    if i == len || _byte(text, i) == _LF {
      var raw = string.str_slice(text, line_start, i);
      let rl = raw.len();
      if rl > 0 && _byte(raw, rl - 1) == _CR {
        raw = string.str_slice(raw, 0, rl - 1);
      }
      let line = string.str_trim(raw);
      let ll = line.len();
      if ll > 0 {
        let b0 = _byte(line, 0);
        if !_is_ident_start(b0) {
          return _err_cue("cue: text outside catalog: " + line);
        }
        let tok_end = _scan_token(line, 0);
        let tok = string.str_slice(line, 0, tok_end);
        let k = _kind_of(tok);
        if k == 0 {
          return _err_cue("cue: unknown keyword: " + tok);
        }
        if k == EK_CATALOG && in_track {
          return _err_cue("cue: keyword not allowed here: " + tok);
        }
        if (k == EK_INDEX || k == EK_PREGAP || k == EK_POSTGAP || k == EK_ISRC) && !in_track {
          return _err_cue("cue: keyword not allowed here: " + tok);
        }
        let pos = _skip_ws(line, tok_end);
        var ek = 0;
        var en = 0;
        var em = 0;
        var es = 0;
        var ef = 0;
        var et = "";
        var e2 = "";
        var eq = 0;
        if k == EK_FILE {
          if pos >= ll {
            return _err_cue("cue: bad FILE: " + line);
          }
          if pos == tok_end || _byte(line, pos) != _DQ {
            return _err_cue("cue: bad FILE: " + line);
          }
          let qe = _quoted_end(line, pos);
          if qe < 0 {
            return _err_cue("cue: unterminated quote: " + line);
          }
          let ty = string.str_trim(string.str_slice(line, qe + 1, ll));
          if ty.len() == 0 || _has_ws(ty) || _find_byte(ty, _DQ) >= 0 {
            return _err_cue("cue: bad FILE: " + line);
          }
          ek = EK_FILE;
          et = _decode_quoted(line, pos, qe);
          e2 = ty;
          eq = 1;
          file_ord = file_ord + 1;
          track_ord = -1;
          in_track = false;
        } elif k == EK_TRACK {
          let tn = _parse_two(line, pos);
          if tn < 1 {
            return _err_cue("cue: bad track number: " + line);
          }
          if pos + 2 < ll && !_is_ws_byte(_byte(line, pos + 2)) {
            return _err_cue("cue: bad track number: " + line);
          }
          let p2 = _skip_ws(line, pos + 2);
          let ty = string.str_trim(string.str_slice(line, p2, ll));
          if ty.len() == 0 || _has_ws(ty) {
            return _err_cue("cue: bad track type: " + line);
          }
          ek = EK_TRACK;
          en = tn;
          e2 = ty;
          track_ord = track_count;
          track_count = track_count + 1;
          track_nums.push(tn);
          has_index01.push(0);
          in_track = true;
        } elif k == EK_INDEX {
          let inum = _parse_two(line, pos);
          if inum < 0 {
            return _err_cue("cue: bad index number: " + line);
          }
          if pos + 2 < ll && !_is_ws_byte(_byte(line, pos + 2)) {
            return _err_cue("cue: bad index number: " + line);
          }
          let p2 = _skip_ws(line, pos + 2);
          let tp = _parse_time(line, p2);
          if tp == -1 {
            return _err_cue("cue: bad index time: " + line);
          }
          if tp == -2 {
            return _err_cue("cue: second out of range: " + line);
          }
          if tp == -3 {
            return _err_cue("cue: frame out of range: " + line);
          }
          ek = EK_INDEX;
          en = inum;
          em = tp / 10000;
          es = (tp / 100) % 100;
          ef = tp % 100;
          if inum == 1 {
            has_index01[track_ord] = 1;
          }
        } elif k == EK_PREGAP || k == EK_POSTGAP {
          let tp = _parse_time(line, pos);
          if tp == -1 {
            return _err_cue("cue: bad gap time: " + line);
          }
          if tp == -2 {
            return _err_cue("cue: second out of range: " + line);
          }
          if tp == -3 {
            return _err_cue("cue: frame out of range: " + line);
          }
          if k == EK_PREGAP {
            ek = EK_PREGAP;
          } else {
            ek = EK_POSTGAP;
          }
          em = tp / 10000;
          es = (tp / 100) % 100;
          ef = tp % 100;
        } elif k == EK_PERFORMER || k == EK_TITLE || k == EK_SONGWRITER {
          if pos >= ll {
            return _err_cue("cue: missing value: " + line);
          }
          if pos == tok_end {
            return _err_cue("cue: missing value: " + line);
          }
          if _byte(line, pos) == _DQ {
            let qe = _quoted_end(line, pos);
            if qe < 0 {
              return _err_cue("cue: unterminated quote: " + line);
            }
            if _skip_ws(line, qe + 1) < ll {
              return _err_cue("cue: trailing text after quote: " + line);
            }
            et = _decode_quoted(line, pos, qe);
            eq = 1;
          } else {
            et = string.str_slice(line, pos, ll);
            eq = 0;
          }
          ek = k;
        } elif k == EK_REM {
          et = string.str_trim(string.str_slice(line, tok_end, ll));
          ek = EK_REM;
        } elif k == EK_ISRC {
          if pos >= ll || pos == tok_end {
            return _err_cue("cue: bad ISRC: " + line);
          }
          if _byte(line, pos) == _DQ {
            let qe = _quoted_end(line, pos);
            if qe < 0 {
              return _err_cue("cue: unterminated quote: " + line);
            }
            if _skip_ws(line, qe + 1) < ll {
              return _err_cue("cue: trailing text after quote: " + line);
            }
            et = _decode_quoted(line, pos, qe);
            eq = 1;
          } else {
            et = string.str_slice(line, pos, ll);
          }
          if !_is_isrc(et) {
            return _err_cue("cue: bad ISRC: " + line);
          }
          ek = EK_ISRC;
        } elif k == EK_CATALOG {
          if pos >= ll || pos == tok_end {
            return _err_cue("cue: bad CATALOG: " + line);
          }
          if _byte(line, pos) == _DQ {
            let qe = _quoted_end(line, pos);
            if qe < 0 {
              return _err_cue("cue: unterminated quote: " + line);
            }
            if _skip_ws(line, qe + 1) < ll {
              return _err_cue("cue: trailing text after quote: " + line);
            }
            et = _decode_quoted(line, pos, qe);
            eq = 1;
          } else {
            et = string.str_slice(line, pos, ll);
          }
          if !_is_catalog(et) {
            return _err_cue("cue: bad CATALOG: " + line);
          }
          ek = EK_CATALOG;
        } else {
          return _err_cue("cue: unknown keyword: " + tok);
        }
        kinds.push(ek);
        nums.push(en);
        mins.push(em);
        secs.push(es);
        frames.push(ef);
        texts.push(et);
        texts2.push(e2);
        quoted.push(eq);
        files.push(file_ord);
        tracks.push(track_ord);
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  var t = 0;
  while t < has_index01.len() {
    let hv: Int = has_index01[t];
    if hv == 0 {
      let tnum: Int = track_nums[t];
      return _err_cue("cue: track " + _two_digits_str(tnum) + " has no INDEX 01");
    }
    t = t + 1;
  }
  return _ok_cue(_make_cue(kinds, nums, mins, secs, frames, texts, texts2,
                           quoted, files, tracks));
}

/// Emit one CUE sheet in canonical form.
/// Params: c - the sheet to serialize (a value produced by `cue_parse`, or a
/// hand-built Cue whose ten Vecs all have the same length and whose Str
/// fields contain no NUL bytes).
/// Returns: every known element on its own LF-terminated line, in stored
/// order: top-level lines at column 0 and track-body lines indented by two
/// spaces. Track and index numbers are zero-padded to two digits; times are
/// emitted as mm:ss:ff with each component clamped to two digits (mm/ss
/// 00..99, ff 00..74 for parsed sheets). Quoting is reproduced from the
/// stored `quoted` flags: flags set emit `"..."` with embedded quotes
/// doubled, flags clear emit the value verbatim. REM emits `REM` plus the
/// body when it is non-empty. An empty sheet emits "". Unknown kind codes
/// are skipped.
/// Error case: none.
/// Complexity: O(total output length).
pub fn cue_emit(c: &Cue) -> Str {
  var out = Vec[UInt8].new();
  let n = c.kinds.len();
  var i = 0;
  while i < n {
    let k: Int = c.kinds[i];
    if k >= EK_FILE && k <= EK_CATALOG {
      let tr: Int = c.tracks[i];
      if k != EK_TRACK && tr >= 0 {
        builder.sb_push_str(&mut out, "  ");
      }
      if k == EK_FILE {
        let nm: Str = c.texts[i];
        let ty: Str = c.texts2[i];
        builder.sb_push_str(&mut out, "FILE ");
        _push_quoted(&mut out, nm);
        out.push(32u8);
        builder.sb_push_str(&mut out, ty);
      } elif k == EK_TRACK {
        let tn: Int = c.nums[i];
        let ty: Str = c.texts2[i];
        builder.sb_push_str(&mut out, "TRACK ");
        _push_two_digits(&mut out, tn);
        out.push(32u8);
        builder.sb_push_str(&mut out, ty);
      } elif k == EK_INDEX {
        let inum: Int = c.nums[i];
        let mm: Int = c.mins[i];
        let ss: Int = c.secs[i];
        let ff: Int = c.frames[i];
        builder.sb_push_str(&mut out, "INDEX ");
        _push_two_digits(&mut out, inum);
        out.push(32u8);
        _push_time(&mut out, mm, ss, ff);
      } elif k == EK_PREGAP {
        let mm: Int = c.mins[i];
        let ss: Int = c.secs[i];
        let ff: Int = c.frames[i];
        builder.sb_push_str(&mut out, "PREGAP ");
        _push_time(&mut out, mm, ss, ff);
      } elif k == EK_POSTGAP {
        let mm: Int = c.mins[i];
        let ss: Int = c.secs[i];
        let ff: Int = c.frames[i];
        builder.sb_push_str(&mut out, "POSTGAP ");
        _push_time(&mut out, mm, ss, ff);
      } elif k == EK_PERFORMER || k == EK_TITLE || k == EK_SONGWRITER {
        let txt: Str = c.texts[i];
        let q: Int = c.quoted[i];
        if k == EK_PERFORMER {
          builder.sb_push_str(&mut out, "PERFORMER ");
        } elif k == EK_TITLE {
          builder.sb_push_str(&mut out, "TITLE ");
        } else {
          builder.sb_push_str(&mut out, "SONGWRITER ");
        }
        _push_value(&mut out, txt, q);
      } elif k == EK_REM {
        let txt: Str = c.texts[i];
        builder.sb_push_str(&mut out, "REM");
        if txt.len() > 0 {
          out.push(32u8);
          builder.sb_push_str(&mut out, txt);
        }
      } elif k == EK_ISRC {
        let txt: Str = c.texts[i];
        let q: Int = c.quoted[i];
        builder.sb_push_str(&mut out, "ISRC ");
        _push_value(&mut out, txt, q);
      } elif k == EK_CATALOG {
        let txt: Str = c.texts[i];
        let q: Int = c.quoted[i];
        builder.sb_push_str(&mut out, "CATALOG ");
        _push_value(&mut out, txt, q);
      }
      out.push(10u8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Internal element lookup
// --------------------------------------------------

// Number of elements of kind `kind`.
fn _count_kind(c: &Cue, kind: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < c.kinds.len() {
    let k: Int = c.kinds[i];
    if k == kind {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// Element index of the `n`-th element of kind `kind` (0-based), or -1.
fn _nth_kind(c: &Cue, kind: Int, n: Int) -> Int {
  if n < 0 {
    return -1;
  }
  var seen = 0;
  var i = 0;
  while i < c.kinds.len() {
    let k: Int = c.kinds[i];
    if k == kind {
      if seen == n {
        return i;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Public API -- generic element accessors
// --------------------------------------------------

/// Number of elements in the stream.
pub fn cue_element_count(c: &Cue) -> Int {
  return c.kinds.len();
}

/// Kind (`EK_*`) of element `i`; -1 when `i` is out of range.
pub fn cue_element_kind(c: &Cue, i: Int) -> Int {
  if i < 0 || i >= c.kinds.len() {
    return -1;
  }
  let v: Int = c.kinds[i];
  return v;
}

/// Number of elements of kind `kind`.
pub fn cue_element_kind_count(c: &Cue, kind: Int) -> Int {
  return _count_kind(c, kind);
}

/// Numeric field of element `i`: TRACK/INDEX number, 0 for other kinds; -1
/// when `i` is out of range.
pub fn cue_element_num(c: &Cue, i: Int) -> Int {
  if i < 0 || i >= c.nums.len() {
    return -1;
  }
  let v: Int = c.nums[i];
  return v;
}

/// Minute field of element `i` (INDEX/PREGAP/POSTGAP); 0 for other kinds,
/// -1 when `i` is out of range.
pub fn cue_element_min(c: &Cue, i: Int) -> Int {
  if i < 0 || i >= c.mins.len() {
    return -1;
  }
  let v: Int = c.mins[i];
  return v;
}

/// Second field of element `i` (INDEX/PREGAP/POSTGAP); 0 for other kinds,
/// -1 when `i` is out of range.
pub fn cue_element_sec(c: &Cue, i: Int) -> Int {
  if i < 0 || i >= c.secs.len() {
    return -1;
  }
  let v: Int = c.secs[i];
  return v;
}

/// Frame field of element `i` (INDEX/PREGAP/POSTGAP, 0..74); 0 for other
/// kinds, -1 when `i` is out of range.
pub fn cue_element_frame(c: &Cue, i: Int) -> Int {
  if i < 0 || i >= c.frames.len() {
    return -1;
  }
  let v: Int = c.frames[i];
  return v;
}

/// Total CD frames of element `i` as (mm*60 + ss)*75 + ff when the element
/// is an INDEX, PREGAP or POSTGAP; -1 for other kinds or an out-of-range
/// index. Values are exact integers (a full 99:59:74 is 449999 frames).
pub fn cue_element_frames(c: &Cue, i: Int) -> Int {
  let k = cue_element_kind(c, i);
  if k == EK_INDEX || k == EK_PREGAP || k == EK_POSTGAP {
    let mm: Int = c.mins[i];
    let ss: Int = c.secs[i];
    let ff: Int = c.frames[i];
    return (mm * 60 + ss) * 75 + ff;
  }
  return -1;
}

/// Primary text of element `i`: FILE name, PERFORMER/TITLE/SONGWRITER value,
/// ISRC code, CATALOG number or REM body; "" for other kinds and for an
/// out-of-range index.
pub fn cue_element_text(c: &Cue, i: Int) -> Str {
  if i < 0 || i >= c.texts.len() {
    return "";
  }
  let v: Str = c.texts[i];
  return v;
}

/// Secondary text of element `i`: FILE type or TRACK type; "" for other
/// kinds and for an out-of-range index.
pub fn cue_element_text2(c: &Cue, i: Int) -> Str {
  if i < 0 || i >= c.texts2.len() {
    return "";
  }
  let v: Str = c.texts2[i];
  return v;
}

/// True when the primary text of element `i` was quoted in the source
/// (always false for REM and for an out-of-range index).
pub fn cue_element_quoted(c: &Cue, i: Int) -> Bool {
  if i < 0 || i >= c.quoted.len() {
    return false;
  }
  let v: Int = c.quoted[i];
  return v != 0;
}

/// Ordinal of the FILE element that governs element `i` (-1 when the element
/// precedes the first FILE or `i` is out of range).
pub fn cue_element_file(c: &Cue, i: Int) -> Int {
  if i < 0 || i >= c.files.len() {
    return -1;
  }
  let v: Int = c.files[i];
  return v;
}

/// Ordinal of the TRACK element that governs element `i` (-1 when the
/// element is outside a track body or `i` is out of range). A TRACK element
/// reports its own ordinal; FILE and top-level elements report -1.
pub fn cue_element_track(c: &Cue, i: Int) -> Int {
  if i < 0 || i >= c.tracks.len() {
    return -1;
  }
  let v: Int = c.tracks[i];
  return v;
}

// --------------------------------------------------
//  Public API -- typed accessors: files
// --------------------------------------------------

/// Number of FILE elements.
pub fn cue_file_count(c: &Cue) -> Int {
  return _count_kind(c, EK_FILE);
}

/// Element index of the `j`-th FILE element; -1 when `j` is out of range.
pub fn cue_file_element(c: &Cue, j: Int) -> Int {
  return _nth_kind(c, EK_FILE, j);
}

/// File name of the `j`-th FILE element (always quoted in the source; no
/// escaping beyond doubled quotes); "" when `j` is out of range.
pub fn cue_file_name(c: &Cue, j: Int) -> Str {
  let i = _nth_kind(c, EK_FILE, j);
  if i < 0 {
    return "";
  }
  let v: Str = c.texts[i];
  return v;
}

/// File type of the `j`-th FILE element (WAVE, MP3, AIFF, BINARY,
/// MOTOROLA, ... passed through verbatim); "" when `j` is out of range.
pub fn cue_file_type(c: &Cue, j: Int) -> Str {
  let i = _nth_kind(c, EK_FILE, j);
  if i < 0 {
    return "";
  }
  let v: Str = c.texts2[i];
  return v;
}

// --------------------------------------------------
//  Public API -- typed accessors: tracks
// --------------------------------------------------

/// Number of TRACK elements.
pub fn cue_track_count(c: &Cue) -> Int {
  return _count_kind(c, EK_TRACK);
}

/// Element index of the `t`-th TRACK element; -1 when `t` is out of range.
pub fn cue_track_element(c: &Cue, t: Int) -> Int {
  return _nth_kind(c, EK_TRACK, t);
}

/// Track number (1..99) of track `t`; -1 when `t` is out of range.
pub fn cue_track_number(c: &Cue, t: Int) -> Int {
  let i = _nth_kind(c, EK_TRACK, t);
  if i < 0 {
    return -1;
  }
  let v: Int = c.nums[i];
  return v;
}

/// Track type of track `t` (AUDIO, MODE1/2352, MODE2/2352, ... passed
/// through verbatim); "" when `t` is out of range.
pub fn cue_track_type(c: &Cue, t: Int) -> Str {
  let i = _nth_kind(c, EK_TRACK, t);
  if i < 0 {
    return "";
  }
  let v: Str = c.texts2[i];
  return v;
}

/// Ordinal of the FILE element that track `t` belongs to; -1 when track `t`
/// has no preceding FILE or `t` is out of range.
pub fn cue_track_file(c: &Cue, t: Int) -> Int {
  let i = _nth_kind(c, EK_TRACK, t);
  if i < 0 {
    return -1;
  }
  let v: Int = c.files[i];
  return v;
}

/// Number of INDEX elements belonging to track `t`; 0 when `t` is out of
/// range or the track has no indices.
pub fn cue_track_index_count(c: &Cue, t: Int) -> Int {
  if _nth_kind(c, EK_TRACK, t) < 0 {
    return 0;
  }
  var count = 0;
  var i = 0;
  while i < c.kinds.len() {
    let k: Int = c.kinds[i];
    let tr: Int = c.tracks[i];
    if k == EK_INDEX && tr == t {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Global index ordinal (usable with the `cue_index_*` accessors) of the
/// `j`-th INDEX element belonging to track `t`; -1 when `t` or `j` is out of
/// range.
pub fn cue_track_index(c: &Cue, t: Int, j: Int) -> Int {
  if j < 0 {
    return -1;
  }
  if _nth_kind(c, EK_TRACK, t) < 0 {
    return -1;
  }
  var seen = 0;
  var idx = 0;
  var i = 0;
  while i < c.kinds.len() {
    let k: Int = c.kinds[i];
    if k == EK_INDEX {
      let tr: Int = c.tracks[i];
      if tr == t {
        if seen == j {
          return idx;
        }
        seen = seen + 1;
      }
      idx = idx + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// True when track `t` has an INDEX with number 1. Always true for a value
/// produced by `cue_parse` (a track without INDEX 01 is Err); useful for
/// hand-built Cue values. False when `t` is out of range.
pub fn cue_track_has_index01(c: &Cue, t: Int) -> Bool {
  if _nth_kind(c, EK_TRACK, t) < 0 {
    return false;
  }
  var i = 0;
  while i < c.kinds.len() {
    let k: Int = c.kinds[i];
    let tr: Int = c.tracks[i];
    let num: Int = c.nums[i];
    if k == EK_INDEX && tr == t && num == 1 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Public API -- typed accessors: indices
// --------------------------------------------------

/// Number of INDEX elements.
pub fn cue_index_count(c: &Cue) -> Int {
  return _count_kind(c, EK_INDEX);
}

/// Element index of the `k`-th INDEX element; -1 when `k` is out of range.
pub fn cue_index_element(c: &Cue, k: Int) -> Int {
  return _nth_kind(c, EK_INDEX, k);
}

/// Index number (0..99) of index `k`; -1 when `k` is out of range.
pub fn cue_index_number(c: &Cue, k: Int) -> Int {
  let i = _nth_kind(c, EK_INDEX, k);
  if i < 0 {
    return -1;
  }
  let v: Int = c.nums[i];
  return v;
}

/// Minute field (00..99) of index `k`; -1 when `k` is out of range.
pub fn cue_index_min(c: &Cue, k: Int) -> Int {
  let i = _nth_kind(c, EK_INDEX, k);
  if i < 0 {
    return -1;
  }
  let v: Int = c.mins[i];
  return v;
}

/// Second field (00..59) of index `k`; -1 when `k` is out of range.
pub fn cue_index_sec(c: &Cue, k: Int) -> Int {
  let i = _nth_kind(c, EK_INDEX, k);
  if i < 0 {
    return -1;
  }
  let v: Int = c.secs[i];
  return v;
}

/// Frame field (00..74) of index `k`; -1 when `k` is out of range.
pub fn cue_index_frame(c: &Cue, k: Int) -> Int {
  let i = _nth_kind(c, EK_INDEX, k);
  if i < 0 {
    return -1;
  }
  let v: Int = c.frames[i];
  return v;
}

/// Total CD frames of index `k` as (mm*60 + ss)*75 + ff; -1 when `k` is out
/// of range.
pub fn cue_index_frames(c: &Cue, k: Int) -> Int {
  return cue_element_frames(c, _nth_kind(c, EK_INDEX, k));
}

/// Ordinal of the TRACK element that index `k` belongs to; -1 when `k` is
/// out of range or the index has no governing track.
pub fn cue_index_track(c: &Cue, k: Int) -> Int {
  let i = _nth_kind(c, EK_INDEX, k);
  if i < 0 {
    return -1;
  }
  let v: Int = c.tracks[i];
  return v;
}
