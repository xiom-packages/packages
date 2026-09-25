// XIOM -- xiom.edl: CMX EDL parsing and canonical emitting (documented subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, in-memory Str only: no FFI, no file I/O, no media inspection, no
// drop-frame conversion, no pull-down and no duration arithmetic. The codec
// covers a strict, documented subset of the CMX 3600 edit decision list:
//
//   line    = title / comment / event
//   title   = "TITLE" (SP | TAB)+ text
//   comment = ("*" / ";") *( char )        ; stored raw, marker included
//   event   = 3DIGIT ws reel ws track ws trans [ ws dur ] ws tc x4
//   ws      = SP | TAB
//   reel    = 1..8( ALPHA / DIGIT / "_" )  ; "BL" is black (documented)
//   track   = "V" | "A" | "A2" | "AA" | "B" | "A3" | "A4"
//   trans   = "C" | "D" | "W" 3DIGIT
//   dur     = 1..3DIGIT                    ; dissolve length, 1..999 frames
//   tc      = 2DIGIT ":" 2DIGIT ":" 2DIGIT ":" 2DIGIT
//
// Keywords and field tokens are case-sensitive uppercase. Every document is
// parsed into one flat line stream; there is no Vec[StructType] (unsupported
// in this compiler), so an Edl is twelve parallel Vecs plus the frame base,
// with exactly one slot per non-blank source line:
//
//   LK_TITLE    texts = title text after "TITLE"
//   LK_COMMENT  texts = the whole trimmed comment line, marker included
//   LK_EVENT    nums = event number, reels/tracks = reel/track tokens,
//               trans = TR_* code, durs = dissolve frames (0 for C/W),
//               wipes = wipe code (0 for C/D), and one packed timecode per
//               field: src_ins, src_outs, rec_ins, rec_outs hold
//               hh*1000000 + mm*10000 + ss*100 + ff
//
// Policies, all documented in SPEC.md:
//   * Event numbers are exactly three digits in 001..999 and must be strictly
//     increasing in document order; gaps are allowed, duplicates and
//     out-of-order numbers are Err.
//   * The frame base is a parse-time argument, one of 24, 25 or 30; it is
//     stored in the Edl and every ff field must be < base. Drop-frame
//     timecodes ("hh:mm:ss;ff") are outside the subset and are Err.
//   * "C" takes no duration; "D" requires a 1..999 frame duration; "Wnnn"
//     carries a wipe code 001..999 and is passed through without further
//     semantics.
//   * Comments and TITLE lines may appear anywhere and keep their document
//     order; blank lines are dropped.
//
// v0.61.3 notes that shaped this module (SPEC.md section 8):
//   * Free functions only; no methods, lambdas, match or Vec[StructType].
//   * Ok/Err for Result[Edl, Str] are constructed only in the leaf helpers
//     _ok_edl/_err_edl; the Edl literal itself is built only by _make_edl.
//   * Every input byte is read through _byte() as an Int, so no UInt8
//     constant >= 128 is ever involved in a comparison.
//   * Str values never go through `==`; keyword dispatch uses
//     xiom.string.compare.str_compare, and every Vec element read binds a
//     typed local first.
//   * `&mut Vec` arguments are written as `&mut` at every call site.
//   * Parallel Vecs are pushed only through _push_meta/_push_strs/_push_tcs,
//     so every slot appends to all twelve arrays in lockstep.
//   * Input containing a NUL byte is rejected before any slicing, so
//     xiom.string.builder.sb_to_str is never handed a NUL-containing buffer.
//
// See SPEC.md for the exact grammar, tables, error catalog, round-trip rules
// and test matrix.

module xiom.edl

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Line kinds (public, stable codes)
// --------------------------------------------------

/// Line kind: `TITLE <text>`.
pub const LK_TITLE: Int = 1;
/// Line kind: comment line starting with `*` or `;`, stored raw.
pub const LK_COMMENT: Int = 2;
/// Line kind: one CMX event line.
pub const LK_EVENT: Int = 3;

// --------------------------------------------------
//  Transition kinds (public, stable codes)
// --------------------------------------------------

/// Transition kind: `C`, a cut; carries no duration.
pub const TR_CUT: Int = 1;
/// Transition kind: `D nnn`, a dissolve of 1..999 frames.
pub const TR_DISSOLVE: Int = 2;
/// Transition kind: `Wnnn`, a wipe; the code 001..999 is passed through.
pub const TR_WIPE: Int = 3;

// --------------------------------------------------
//  Timecode positions and components (public codes)
// --------------------------------------------------

/// Timecode selector for `edl_event_timecode*`: source in point.
pub const TC_SRC_IN: Int = 1;
/// Timecode selector for `edl_event_timecode*`: source out point.
pub const TC_SRC_OUT: Int = 2;
/// Timecode selector for `edl_event_timecode*`: record in point.
pub const TC_REC_IN: Int = 3;
/// Timecode selector for `edl_event_timecode*`: record out point.
pub const TC_REC_OUT: Int = 4;

/// Timecode component for `edl_timecode_part`: hours.
pub const TCF_HH: Int = 1;
/// Timecode component for `edl_timecode_part`: minutes.
pub const TCF_MM: Int = 2;
/// Timecode component for `edl_timecode_part`: seconds.
pub const TCF_SS: Int = 3;
/// Timecode component for `edl_timecode_part`: frames.
pub const TCF_FF: Int = 4;

// --------------------------------------------------
//  Frame bases (public, stable values)
// --------------------------------------------------

/// Supported frame base: 24 fps (film).
pub const EDL_FPS_24: Int = 24;
/// Supported frame base: 25 fps (PAL).
pub const EDL_FPS_25: Int = 25;
/// Supported frame base: 30 fps (NTSC non-drop).
pub const EDL_FPS_30: Int = 30;

// --------------------------------------------------
//  Byte constants (Int; see the module header)
// --------------------------------------------------

const _TAB: Int = 9;
const _LF: Int = 10;
const _CR: Int = 13;
const _SP: Int = 32;
const _STAR: Int = 42;
const _ZERO: Int = 48;
const _NINE: Int = 57;
const _COLON: Int = 58;
const _SEMI: Int = 59;
const _UPPER_W: Int = 87;
const _UNDERSCORE: Int = 95;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed EDL: twelve index-aligned Vecs with one slot per non-blank line,
/// plus the frame base. For a value produced by `edl_parse`, all twelve Vecs
/// have length `edl_line_count(e)`, `kinds[i]` is one of the `LK_*` codes,
/// and the remaining arrays carry meaning per kind as documented in the
/// module header (all other slots are 0 or ""). Timecodes are packed as
/// hh*1000000 + mm*10000 + ss*100 + ff.
pub type Edl = {
  kinds: Vec[Int];
  nums: Vec[Int];
  reels: Vec[Str];
  tracks: Vec[Str];
  trans: Vec[Int];
  durs: Vec[Int];
  wipes: Vec[Int];
  src_ins: Vec[Int];
  src_outs: Vec[Int];
  rec_ins: Vec[Int];
  rec_outs: Vec[Int];
  texts: Vec[Str];
  fps: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// The one place an Edl value is assembled from the parallel Vecs.
fn _make_edl(kinds: Vec[Int], nums: Vec[Int], reels: Vec[Str],
             tracks: Vec[Str], trans: Vec[Int], durs: Vec[Int],
             wipes: Vec[Int], src_ins: Vec[Int], src_outs: Vec[Int],
             rec_ins: Vec[Int], rec_outs: Vec[Int], texts: Vec[Str],
             fps: Int) -> Edl {
  return Edl{
    kinds: kinds;
    nums: nums;
    reels: reels;
    tracks: tracks;
    trans: trans;
    durs: durs;
    wipes: wipes;
    src_ins: src_ins;
    src_outs: src_outs;
    rec_ins: rec_ins;
    rec_outs: rec_outs;
    texts: texts;
    fps: fps;
  };
}

// Ok(e) for Result[Edl, Str].
fn _ok_edl(e: Edl) -> Result[Edl, Str] {
  return Ok(e);
}

// Err(m) for Result[Edl, Str].
fn _err_edl(m: Str) -> Result[Edl, Str] {
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

// True when `b` continues a reel name (letter, digit or underscore).
fn _is_reel_byte(b: Int) -> Bool {
  return _is_upper(b) || _is_lower(b) || _is_digit(b) || b == _UNDERSCORE;
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

// End (exclusive) of the whitespace-delimited token starting at `start`.
// Every field of an EDL line is such a token.
fn _scan_token(s: Str, start: Int) -> Int {
  var i = start;
  while i < s.len() && !_is_ws_byte(_byte(s, i)) {
    i = i + 1;
  }
  return i;
}

// Split `line` into whitespace-separated tokens, skipping runs of space/tab.
fn _split_tokens(line: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  let n = line.len();
  while i < n {
    i = _skip_ws(line, i);
    if i < n {
      let end = _scan_token(line, i);
      out.push(string.str_slice(line, i, end));
      i = end;
    }
  }
  return out;
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

// Parse an event number: exactly three digits, value 001..999; -1 otherwise.
fn _parse_event_number(s: Str) -> Int {
  if s.len() != 3 {
    return -1;
  }
  let d1 = _byte(s, 0);
  let d2 = _byte(s, 1);
  let d3 = _byte(s, 2);
  if !_is_digit(d1) || !_is_digit(d2) || !_is_digit(d3) {
    return -1;
  }
  let v = (d1 - _ZERO) * 100 + (d2 - _ZERO) * 10 + (d3 - _ZERO);
  if v < 1 {
    return -1;
  }
  return v;
}

// True when `s` is a reel name: 1..8 bytes from [A-Za-z0-9_].
fn _is_reel(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 8 {
    return false;
  }
  var i = 0;
  while i < n {
    if !_is_reel_byte(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `s` is one of the seven documented CMX track tokens.
fn _is_track(s: Str) -> Bool {
  if compare.str_compare(s, "V") == 0 { return true; }
  if compare.str_compare(s, "A") == 0 { return true; }
  if compare.str_compare(s, "A2") == 0 { return true; }
  if compare.str_compare(s, "AA") == 0 { return true; }
  if compare.str_compare(s, "B") == 0 { return true; }
  if compare.str_compare(s, "A3") == 0 { return true; }
  if compare.str_compare(s, "A4") == 0 { return true; }
  return false;
}

// Transition kind of the token `s`: TR_CUT for "C", TR_DISSOLVE for "D",
// TR_WIPE for any token starting with "W" (the code itself is validated by
// _wipe_code), 0 for anything else.
fn _transition_kind(s: Str) -> Int {
  if compare.str_compare(s, "C") == 0 { return TR_CUT; }
  if compare.str_compare(s, "D") == 0 { return TR_DISSOLVE; }
  if s.len() > 0 && _byte(s, 0) == _UPPER_W { return TR_WIPE; }
  return 0;
}

// Wipe code of a "W" + three digit token, or -1 when `s` is not exactly
// "W" followed by three digits with a value in 001..999.
fn _wipe_code(s: Str) -> Int {
  if s.len() != 4 {
    return -1;
  }
  if _byte(s, 0) != _UPPER_W {
    return -1;
  }
  let d1 = _byte(s, 1);
  let d2 = _byte(s, 2);
  let d3 = _byte(s, 3);
  if !_is_digit(d1) || !_is_digit(d2) || !_is_digit(d3) {
    return -1;
  }
  let v = (d1 - _ZERO) * 100 + (d2 - _ZERO) * 10 + (d3 - _ZERO);
  if v < 1 {
    return -1;
  }
  return v;
}

// Dissolve duration: 1..3 ASCII digits with a value in 1..999; -1 otherwise.
fn _parse_duration(s: Str) -> Int {
  let n = s.len();
  if n < 1 || n > 3 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if !_is_digit(b) {
      return -1;
    }
    v = v * 10 + (b - _ZERO);
    i = i + 1;
  }
  if v < 1 {
    return -1;
  }
  return v;
}

// Parse a complete non-drop timecode "hh:mm:ss:ff" (exactly 11 bytes).
// Returns the packed value hh*1000000 + mm*10000 + ss*100 + ff, or:
//   -1 bad shape, non-digit field, mm > 59 or ss > 59
//   -2 ff >= fps (frame out of range for the document's frame base)
// A ";" drop-frame separator fails the colon checks and is reported as -1.
fn _parse_tc(s: Str, fps: Int) -> Int {
  if s.len() != 11 {
    return -1;
  }
  if _byte(s, 2) != _COLON || _byte(s, 5) != _COLON || _byte(s, 8) != _COLON {
    return -1;
  }
  let hh = _parse_two(s, 0);
  let mm = _parse_two(s, 3);
  let ss = _parse_two(s, 6);
  let ff = _parse_two(s, 9);
  if hh < 0 || mm < 0 || ss < 0 || ff < 0 {
    return -1;
  }
  if mm > 59 || ss > 59 {
    return -1;
  }
  if ff >= fps {
    return -2;
  }
  return hh * 1000000 + mm * 10000 + ss * 100 + ff;
}

// Append two zero-padded ASCII digits for `v`, clamped to 0..99.
fn _push_two_digits(out: &mut Vec[UInt8], v: Int) {
  var n = v;
  if n < 0 { n = 0; }
  if n > 99 { n = 99; }
  out.push((_ZERO + n / 10) as UInt8);
  out.push((_ZERO + n % 10) as UInt8);
}

// Append three zero-padded ASCII digits for `v`, clamped to 0..999.
fn _push_three_digits(out: &mut Vec[UInt8], v: Int) {
  var n = v;
  if n < 0 { n = 0; }
  if n > 999 { n = 999; }
  out.push((_ZERO + n / 100) as UInt8);
  out.push((_ZERO + (n / 10) % 10) as UInt8);
  out.push((_ZERO + n % 10) as UInt8);
}

// Canonical "hh:mm:ss:ff" text for a packed timecode value; each component is
// clamped to two digits. The result is NUL-free ASCII.
fn _tc_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  _push_two_digits(&mut out, (v / 1000000) % 100);
  out.push(58u8);
  _push_two_digits(&mut out, (v / 10000) % 100);
  out.push(58u8);
  _push_two_digits(&mut out, (v / 100) % 100);
  out.push(58u8);
  _push_two_digits(&mut out, v % 100);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Parallel-Vec assembly (one append site per kind)
// --------------------------------------------------

// Append one slot to the five integer metadata Vecs. Every slot of the stream
// goes through this helper, so the arrays can never drift.
fn _push_meta(kinds: &mut Vec[Int], nums: &mut Vec[Int], trans: &mut Vec[Int],
              durs: &mut Vec[Int], wipes: &mut Vec[Int], kind: Int, num: Int,
              tr: Int, dur: Int, wipe: Int) {
  kinds.push(kind);
  nums.push(num);
  trans.push(tr);
  durs.push(dur);
  wipes.push(wipe);
}

// Append one slot to the three string Vecs.
fn _push_strs(reels: &mut Vec[Str], tracks: &mut Vec[Str],
              texts: &mut Vec[Str], reel: Str, track: Str, text: Str) {
  reels.push(reel);
  tracks.push(track);
  texts.push(text);
}

// Append one slot to the four packed-timecode Vecs.
fn _push_tcs(src_ins: &mut Vec[Int], src_outs: &mut Vec[Int],
             rec_ins: &mut Vec[Int], rec_outs: &mut Vec[Int],
             src_in: Int, src_out: Int, rec_in: Int, rec_out: Int) {
  src_ins.push(src_in);
  src_outs.push(src_out);
  rec_ins.push(rec_in);
  rec_outs.push(rec_out);
}

// --------------------------------------------------
//  Public API -- parse and emit
// --------------------------------------------------

/// Parse one CMX EDL document.
/// Params: text - the whole file contents (LF or CRLF line endings);
///         fps  - the document frame base, one of 24, 25 or 30.
/// Returns: Ok(Edl) for a structurally valid document (including an empty
/// one); Err with an "edl: ..." message otherwise. See SPEC.md for the full
/// error catalog. Lines are trimmed of surrounding space/tab, so indentation
/// is insignificant; blank lines are skipped. A line whose first byte is `*`
/// or `;` is a comment stored verbatim (marker included); a line starting
/// with the uppercase keyword `TITLE` is a title line; a line whose first
/// byte is a digit is an event line; anything else is Err. Event numbers are
/// exactly three digits in 001..999 and must be strictly increasing (gaps
/// allowed). Reels are 1..8 letters/digits/underscores, tracks one of
/// V/A/A2/AA/B/A3/A4, transitions one of C, D or Wnnn (nnn = 001..999), and
/// dissolves carry a 1..999 frame duration. Timecodes are hh:mm:ss:ff with
/// mm/ss 00..59 and ff < fps; the `;` drop-frame separator is rejected.
/// Input containing a NUL byte is rejected.
/// Complexity: O(input length).
pub fn edl_parse(text: Str, fps: Int) -> Result[Edl, Str] {
  if _find_byte(text, 0) >= 0 {
    return _err_edl("edl: NUL byte in input");
  }
  if fps != EDL_FPS_24 && fps != EDL_FPS_25 && fps != EDL_FPS_30 {
    return _err_edl("edl: unsupported frame base: " + int_to_string(fps));
  }
  var kinds = Vec[Int].new();
  var nums = Vec[Int].new();
  var reels = Vec[Str].new();
  var tracks = Vec[Str].new();
  var trans = Vec[Int].new();
  var durs = Vec[Int].new();
  var wipes = Vec[Int].new();
  var src_ins = Vec[Int].new();
  var src_outs = Vec[Int].new();
  var rec_ins = Vec[Int].new();
  var rec_outs = Vec[Int].new();
  var texts = Vec[Str].new();
  var prev_num = 0;
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
        if b0 == _STAR || b0 == _SEMI {
          _push_meta(&mut kinds, &mut nums, &mut trans, &mut durs, &mut wipes,
                     LK_COMMENT, 0, 0, 0, 0);
          _push_tcs(&mut src_ins, &mut src_outs, &mut rec_ins, &mut rec_outs,
                    0, 0, 0, 0);
          _push_strs(&mut reels, &mut tracks, &mut texts, "", "", line);
        } elif _is_digit(b0) {
          let toks = _split_tokens(line);
          let nt = toks.len();
          if nt < 4 {
            return _err_edl("edl: missing field: " + line);
          }
          let ntok: Str = toks[0];
          let num = _parse_event_number(ntok);
          if num < 0 {
            return _err_edl("edl: bad event number: " + line);
          }
          if num <= prev_num {
            return _err_edl("edl: event number out of order: " + line);
          }
          let reel: Str = toks[1];
          if !_is_reel(reel) {
            return _err_edl("edl: bad reel: " + line);
          }
          let track: Str = toks[2];
          if !_is_track(track) {
            return _err_edl("edl: unknown track: " + line);
          }
          let ttok: Str = toks[3];
          let tk = _transition_kind(ttok);
          if tk == 0 {
            return _err_edl("edl: bad transition: " + line);
          }
          var dur = 0;
          var wipe = 0;
          var first = 4;
          var need = 8;
          if tk == TR_DISSOLVE {
            if nt < 5 {
              return _err_edl("edl: missing dissolve duration: " + line);
            }
            let dtok: Str = toks[4];
            dur = _parse_duration(dtok);
            if dur < 0 {
              return _err_edl("edl: bad dissolve duration: " + line);
            }
            first = 5;
            need = 9;
          } elif tk == TR_WIPE {
            wipe = _wipe_code(ttok);
            if wipe < 0 {
              return _err_edl("edl: bad transition: " + line);
            }
          }
          if nt < need {
            return _err_edl("edl: missing field: " + line);
          }
          if nt > need {
            return _err_edl("edl: trailing text: " + line);
          }
          let t1: Str = toks[first];
          let s_in = _parse_tc(t1, fps);
          if s_in == -1 {
            return _err_edl("edl: bad timecode: " + line);
          }
          if s_in == -2 {
            return _err_edl("edl: frame out of range: " + line);
          }
          let t2: Str = toks[first + 1];
          let s_out = _parse_tc(t2, fps);
          if s_out == -1 {
            return _err_edl("edl: bad timecode: " + line);
          }
          if s_out == -2 {
            return _err_edl("edl: frame out of range: " + line);
          }
          let t3: Str = toks[first + 2];
          let r_in = _parse_tc(t3, fps);
          if r_in == -1 {
            return _err_edl("edl: bad timecode: " + line);
          }
          if r_in == -2 {
            return _err_edl("edl: frame out of range: " + line);
          }
          let t4: Str = toks[first + 3];
          let r_out = _parse_tc(t4, fps);
          if r_out == -1 {
            return _err_edl("edl: bad timecode: " + line);
          }
          if r_out == -2 {
            return _err_edl("edl: frame out of range: " + line);
          }
          _push_meta(&mut kinds, &mut nums, &mut trans, &mut durs, &mut wipes,
                     LK_EVENT, num, tk, dur, wipe);
          _push_tcs(&mut src_ins, &mut src_outs, &mut rec_ins, &mut rec_outs,
                    s_in, s_out, r_in, r_out);
          _push_strs(&mut reels, &mut tracks, &mut texts, reel, track, "");
          prev_num = num;
        } else {
          let tok_end = _scan_token(line, 0);
          let tok = string.str_slice(line, 0, tok_end);
          if compare.str_compare(tok, "TITLE") != 0 {
            return _err_edl("edl: unexpected line: " + line);
          }
          if tok_end >= ll {
            return _err_edl("edl: bad TITLE: " + line);
          }
          let pos = _skip_ws(line, tok_end);
          if pos >= ll {
            return _err_edl("edl: bad TITLE: " + line);
          }
          let ttxt = string.str_slice(line, pos, ll);
          _push_meta(&mut kinds, &mut nums, &mut trans, &mut durs, &mut wipes,
                     LK_TITLE, 0, 0, 0, 0);
          _push_tcs(&mut src_ins, &mut src_outs, &mut rec_ins, &mut rec_outs,
                    0, 0, 0, 0);
          _push_strs(&mut reels, &mut tracks, &mut texts, "", "", ttxt);
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return _ok_edl(_make_edl(kinds, nums, reels, tracks, trans, durs, wipes,
                           src_ins, src_outs, rec_ins, rec_outs, texts, fps));
}

// --------------------------------------------------
//  Internal lookup and emission helpers
// --------------------------------------------------

// Number of lines of kind `kind`.
fn _count_kind(e: &Edl, kind: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < e.kinds.len() {
    let k: Int = e.kinds[i];
    if k == kind {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// Stream index of the `n`-th line of kind `kind` (0-based), or -1.
fn _nth_kind(e: &Edl, kind: Int, n: Int) -> Int {
  if n < 0 {
    return -1;
  }
  var seen = 0;
  var i = 0;
  while i < e.kinds.len() {
    let k: Int = e.kinds[i];
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

// The shortest length among the twelve parallel Vecs. Emission and guarded
// accessors never index past it, so a hand-built Edl with unequal arrays
// cannot cause an out-of-bounds read.
fn _common_len(e: &Edl) -> Int {
  var n = e.kinds.len();
  if e.nums.len() < n { n = e.nums.len(); }
  if e.reels.len() < n { n = e.reels.len(); }
  if e.tracks.len() < n { n = e.tracks.len(); }
  if e.trans.len() < n { n = e.trans.len(); }
  if e.durs.len() < n { n = e.durs.len(); }
  if e.wipes.len() < n { n = e.wipes.len(); }
  if e.src_ins.len() < n { n = e.src_ins.len(); }
  if e.src_outs.len() < n { n = e.src_outs.len(); }
  if e.rec_ins.len() < n { n = e.rec_ins.len(); }
  if e.rec_outs.len() < n { n = e.rec_outs.len(); }
  if e.texts.len() < n { n = e.texts.len(); }
  return n;
}

// Packed value of timecode `which` of stream slot `i`; -1 when `i` or
// `which` is out of range.
fn _tc_value(e: &Edl, i: Int, which: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if which == TC_SRC_IN {
    if i >= e.src_ins.len() { return -1; }
    let v: Int = e.src_ins[i];
    return v;
  }
  if which == TC_SRC_OUT {
    if i >= e.src_outs.len() { return -1; }
    let v: Int = e.src_outs[i];
    return v;
  }
  if which == TC_REC_IN {
    if i >= e.rec_ins.len() { return -1; }
    let v: Int = e.rec_ins[i];
    return v;
  }
  if which == TC_REC_OUT {
    if i >= e.rec_outs.len() { return -1; }
    let v: Int = e.rec_outs[i];
    return v;
  }
  return -1;
}

// Append " <hh:mm:ss:ff>" for timecode `which` of stream slot `i`; a stale or
// absent slot appends zeroes.
fn _push_tc_field(out: &mut Vec[UInt8], e: &Edl, i: Int, which: Int) {
  let v = _tc_value(e, i, which);
  out.push(32u8);
  if v < 0 {
    builder.sb_push_str(out, "00:00:00:00");
  } else {
    builder.sb_push_str(out, _tc_str(v));
  }
}

// --------------------------------------------------
//  Public API -- emit
// --------------------------------------------------

/// Emit one EDL in canonical form.
/// Params: e - the document to serialize (a value produced by `edl_parse`, or
/// a hand-built Edl whose twelve Vecs all have the same length, whose Str
/// fields contain no NUL bytes and whose transition codes are `TR_*`).
/// Returns: every non-blank line on its own LF-terminated line, in stored
/// order: `TITLE <text>`, comment lines verbatim (marker included), and
/// event lines as `NNN <reel> <track> <trans> [<dur>] <tc> <tc> <tc> <tc>`
/// with single spaces, the event number, dissolve duration and wipe code
/// zero-padded to three digits, and each timecode as hh:mm:ss:ff. Emission
/// is total; slots beyond the shortest parallel Vec are ignored, and an
/// unknown transition code emits `?`. An empty document emits "".
/// Error case: none.
/// Complexity: O(total output length).
pub fn edl_emit(e: &Edl) -> Str {
  var out = Vec[UInt8].new();
  let n = _common_len(e);
  var i = 0;
  while i < n {
    let k: Int = e.kinds[i];
    if k == LK_TITLE {
      let txt: Str = e.texts[i];
      builder.sb_push_str(&mut out, "TITLE ");
      builder.sb_push_str(&mut out, txt);
      out.push(10u8);
    } elif k == LK_COMMENT {
      let txt: Str = e.texts[i];
      builder.sb_push_str(&mut out, txt);
      out.push(10u8);
    } elif k == LK_EVENT {
      let num: Int = e.nums[i];
      let reel: Str = e.reels[i];
      let track: Str = e.tracks[i];
      let tr: Int = e.trans[i];
      _push_three_digits(&mut out, num);
      out.push(32u8);
      builder.sb_push_str(&mut out, reel);
      out.push(32u8);
      builder.sb_push_str(&mut out, track);
      out.push(32u8);
      if tr == TR_CUT {
        out.push(67u8);
      } elif tr == TR_DISSOLVE {
        out.push(68u8);
        out.push(32u8);
        let dur: Int = e.durs[i];
        _push_three_digits(&mut out, dur);
      } elif tr == TR_WIPE {
        out.push(87u8);
        let wc: Int = e.wipes[i];
        _push_three_digits(&mut out, wc);
      } else {
        out.push(63u8);
      }
      _push_tc_field(&mut out, e, i, TC_SRC_IN);
      _push_tc_field(&mut out, e, i, TC_SRC_OUT);
      _push_tc_field(&mut out, e, i, TC_REC_IN);
      _push_tc_field(&mut out, e, i, TC_REC_OUT);
      out.push(10u8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Public API -- line accessors
// --------------------------------------------------

/// Number of stored lines (the length of the flat line stream).
pub fn edl_line_count(e: &Edl) -> Int {
  return e.kinds.len();
}

/// Kind (`LK_*`) of stream line `i`; -1 when `i` is out of range.
pub fn edl_line_kind(e: &Edl, i: Int) -> Int {
  if i < 0 || i >= e.kinds.len() {
    return -1;
  }
  let v: Int = e.kinds[i];
  return v;
}

/// Text of stream line `i`: the value after `TITLE` for `LK_TITLE`, the raw
/// comment line (marker included) for `LK_COMMENT`, and "" for `LK_EVENT` or
/// an out-of-range index.
pub fn edl_line_text(e: &Edl, i: Int) -> Str {
  if i < 0 || i >= e.kinds.len() {
    return "";
  }
  let k: Int = e.kinds[i];
  if (k == LK_TITLE || k == LK_COMMENT) && i < e.texts.len() {
    let v: Str = e.texts[i];
    return v;
  }
  return "";
}

/// Text of the first `TITLE` line; "" when the document has no title.
pub fn edl_title(e: &Edl) -> Str {
  let i = _nth_kind(e, LK_TITLE, 0);
  if i < 0 || i >= e.texts.len() {
    return "";
  }
  let v: Str = e.texts[i];
  return v;
}

/// Number of `TITLE` lines.
pub fn edl_title_count(e: &Edl) -> Int {
  return _count_kind(e, LK_TITLE);
}

/// Number of comment lines (kinds `LK_COMMENT`).
pub fn edl_comment_count(e: &Edl) -> Int {
  return _count_kind(e, LK_COMMENT);
}

/// Frame base the document was parsed with (24, 25 or 30).
pub fn edl_frame_base(e: &Edl) -> Int {
  return e.fps;
}

// --------------------------------------------------
//  Public API -- event accessors
// --------------------------------------------------

/// Number of event lines.
pub fn edl_event_count(e: &Edl) -> Int {
  return _count_kind(e, LK_EVENT);
}

/// Stream index (usable with the `edl_line_*` accessors) of event `i`; -1
/// when `i` is out of range.
pub fn edl_event_line(e: &Edl, i: Int) -> Int {
  return _nth_kind(e, LK_EVENT, i);
}

/// Event number (001..999) of event `i`; -1 when `i` is out of range.
pub fn edl_event_number(e: &Edl, i: Int) -> Int {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 || idx >= e.nums.len() {
    return -1;
  }
  let v: Int = e.nums[idx];
  return v;
}

/// Reel token of event `i` (1..8 letters/digits/underscores; `BL` is black);
/// "" when `i` is out of range.
pub fn edl_event_reel(e: &Edl, i: Int) -> Str {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 || idx >= e.reels.len() {
    return "";
  }
  let v: Str = e.reels[idx];
  return v;
}

/// Track token of event `i` (V/A/A2/AA/B/A3/A4); "" when `i` is out of range.
pub fn edl_event_track(e: &Edl, i: Int) -> Str {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 || idx >= e.tracks.len() {
    return "";
  }
  let v: Str = e.tracks[idx];
  return v;
}

/// Transition kind of event `i`: `TR_CUT`, `TR_DISSOLVE` or `TR_WIPE`; -1
/// when `i` is out of range.
pub fn edl_event_transition(e: &Edl, i: Int) -> Int {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 || idx >= e.trans.len() {
    return -1;
  }
  let v: Int = e.trans[idx];
  return v;
}

/// Dissolve duration in frames (1..999) for a `D` event, 0 for a cut or
/// wipe; -1 when `i` is out of range.
pub fn edl_event_duration(e: &Edl, i: Int) -> Int {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 || idx >= e.durs.len() {
    return -1;
  }
  let v: Int = e.durs[idx];
  return v;
}

/// Wipe code (001..999) for a `W` event, 0 for a cut or dissolve; -1 when
/// `i` is out of range.
pub fn edl_event_wipe(e: &Edl, i: Int) -> Int {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 || idx >= e.wipes.len() {
    return -1;
  }
  let v: Int = e.wipes[idx];
  return v;
}

/// Packed integer of timecode `which` (`TC_SRC_IN`, `TC_SRC_OUT`,
/// `TC_REC_IN` or `TC_REC_OUT`) of event `i`, as hh*1000000 + mm*10000 +
/// ss*100 + ff; -1 when `i` or `which` is out of range. Use
/// `edl_timecode_part` to read a single component.
pub fn edl_event_timecode_value(e: &Edl, i: Int, which: Int) -> Int {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 {
    return -1;
  }
  return _tc_value(e, idx, which);
}

/// Canonical "hh:mm:ss:ff" text of timecode `which` of event `i` (same
/// selectors as `edl_event_timecode_value`); "" when `i` or `which` is out of
/// range.
pub fn edl_event_timecode(e: &Edl, i: Int, which: Int) -> Str {
  let idx = _nth_kind(e, LK_EVENT, i);
  if idx < 0 {
    return "";
  }
  let v = _tc_value(e, idx, which);
  if v < 0 {
    return "";
  }
  return _tc_str(v);
}

/// Source-in timecode of event `i` as canonical "hh:mm:ss:ff"; "" when `i`
/// is out of range.
pub fn edl_event_src_in(e: &Edl, i: Int) -> Str {
  return edl_event_timecode(e, i, TC_SRC_IN);
}

/// Source-out timecode of event `i` as canonical "hh:mm:ss:ff"; "" when `i`
/// is out of range.
pub fn edl_event_src_out(e: &Edl, i: Int) -> Str {
  return edl_event_timecode(e, i, TC_SRC_OUT);
}

/// Record-in timecode of event `i` as canonical "hh:mm:ss:ff"; "" when `i`
/// is out of range.
pub fn edl_event_rec_in(e: &Edl, i: Int) -> Str {
  return edl_event_timecode(e, i, TC_REC_IN);
}

/// Record-out timecode of event `i` as canonical "hh:mm:ss:ff"; "" when `i`
/// is out of range.
pub fn edl_event_rec_out(e: &Edl, i: Int) -> Str {
  return edl_event_timecode(e, i, TC_REC_OUT);
}

// --------------------------------------------------
//  Public API -- timecode helpers
// --------------------------------------------------

/// One component (`TCF_HH`, `TCF_MM`, `TCF_SS` or `TCF_FF`) of a packed
/// timecode value; -1 for a negative value or an unknown component code.
/// Hours are returned as stored (00..99 for parsed documents).
pub fn edl_timecode_part(value: Int, part: Int) -> Int {
  if value < 0 {
    return -1;
  }
  if part == TCF_HH {
    return value / 1000000;
  }
  if part == TCF_MM {
    return (value / 10000) % 100;
  }
  if part == TCF_SS {
    return (value / 100) % 100;
  }
  if part == TCF_FF {
    return value % 100;
  }
  return -1;
}

/// Canonical "hh:mm:ss:ff" text built from four components, each clamped to
/// two digits (0..99). No validation and no arithmetic: the components are
/// rendered as given.
pub fn edl_timecode(hh: Int, mm: Int, ss: Int, ff: Int) -> Str {
  var out = Vec[UInt8].new();
  _push_two_digits(&mut out, hh);
  out.push(58u8);
  _push_two_digits(&mut out, mm);
  out.push(58u8);
  _push_two_digits(&mut out, ss);
  out.push(58u8);
  _push_two_digits(&mut out, ff);
  return builder.sb_to_str(&out);
}
