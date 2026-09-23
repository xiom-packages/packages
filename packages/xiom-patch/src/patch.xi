// XIOM -- xiom.patch: unified diff parsing and application
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Task: replace the xiom.patch placeholder with a pure-XIOM (no FFI) engine
// for single-file unified diffs: hunk-header parsing, hunk counting,
// added/removed line extraction, and hunk application with a bounded +-20
// line fuzz window. See SPEC.md for the accepted grammar, the apply
// algorithm, the error strings, and the known limitations (no binary patches,
// no rename/copy headers, no multi-file application).
//
// Language notes (XIOM v0.61.3): free functions only, no Vec[StructType];
// Str values read from Vec[Str] elements are compared with str_compare
// (BUG 17: `==` on such elements lowers to a pointer comparison). Results are
// built through the _ok_*/_err_* helpers so Ok/Err construction never happens
// in a struct-returning body (compiler bug workaround, see SPEC.md).

module xiom.patch

use xiom.string;
use xiom.string.compare;
use xiom.string.join;
use xiom.convert;

// -- internal helpers --------------------------------------------------------

// Parse a run of ASCII digits at `pos` in `s` (no sign, no overflow check).
// Returns Some((value, next_pos)); None when no digit starts at `pos`.
fn _parse_uint_at(s: Str, pos: Int) -> Option[(Int, Int)] {
  let n = s.len();
  if pos < 0 || pos >= n {
    return None;
  }
  var i = pos;
  var value: Int = 0;
  var digits: Int = 0;
  while i < n {
    let b = byte_at(s, i) as Int;
    if b < 48 || b > 57 {
      break;
    }
    value = value * 10 + (b - 48);
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 {
    return None;
  }
  return Some((value, i));
}

// Advance past ASCII space bytes only (tabs are not separators).
fn _skip_spaces(s: Str, at: Int) -> Int {
  var i = at;
  let n = s.len();
  while i < n {
    if (byte_at(s, i) as Int) != 32 {
      break;
    }
    i = i + 1;
  }
  return i;
}

// Parse one hunk range: a '-' or '+' sign, then start[,count].
// Returns Some((start, count, next_pos)); an omitted ",count" defaults to 1;
// None when malformed (wrong sign, missing digits, dangling comma).
fn _parse_range(s: Str, at: Int) -> Option[(Int, Int, Int)] {
  let n = s.len();
  if at < 0 || at >= n {
    return None;
  }
  let sign = byte_at(s, at) as Int;
  if sign != 45 && sign != 43 {
    return None;
  }
  var start: Int = 0;
  var pos: Int = 0;
  var bad = false;
  match _parse_uint_at(s, at + 1) {
    Some((v, j)) => { start = v; pos = j; },
    None => { bad = true; },
  }
  if bad {
    return None;
  }
  var count: Int = 1;
  if pos < n {
    if (byte_at(s, pos) as Int) == 44 {
      var cval: Int = 0;
      var cpos: Int = 0;
      var cbad = false;
      match _parse_uint_at(s, pos + 1) {
        Some((v, j)) => { cval = v; cpos = j; },
        None => { cbad = true; },
      }
      if cbad {
        return None;
      }
      count = cval;
      pos = cpos;
    }
  }
  return Some((start, count, pos));
}

// Strip one trailing carriage return so CRLF patch text parses like LF.
fn _strip_cr(line: Str) -> Str {
  if str_ends_with(line, "\r") {
    return str_slice(line, 0, line.len() - 1);
  }
  return line;
}

// Copy a vector of lines.
fn _copy_vec(src: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

// Element-wise Str equality of `pat` against `work` starting at index `at`.
// Uses str_compare because `==` on Vec[Str] elements is BUG 17.
fn _lines_match_at(work: &Vec[Str], pat: &Vec[Str], at: Int) -> Bool {
  if at < 0 {
    return false;
  }
  if at + pat.len() > work.len() {
    return false;
  }
  var i = 0;
  while i < pat.len() {
    let a = work[at + i];
    let b = pat[i];
    if str_compare(a, b) != 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Locate a hunk: the exact candidate index `want` first, then outward to
// want+-fuzz. Returns the 0-based line index, or -1 when no position matches.
fn _find_apply_pos(work: &Vec[Str], pat: &Vec[Str], want: Int, fuzz: Int) -> Int {
  if _lines_match_at(work, pat, want) {
    return want;
  }
  var d = 1;
  while d <= fuzz {
    if _lines_match_at(work, pat, want + d) {
      return want + d;
    }
    if _lines_match_at(work, pat, want - d) {
      return want - d;
    }
    d = d + 1;
  }
  return -1;
}

// Replace `old_len` lines at `at` with `repl`; returns a fresh vector.
fn _splice(work: &Vec[Str], at: Int, old_len: Int, repl: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < at {
    out.push(work[i]);
    i = i + 1;
  }
  i = 0;
  while i < repl.len() {
    out.push(repl[i]);
    i = i + 1;
  }
  i = at + old_len;
  while i < work.len() {
    out.push(work[i]);
    i = i + 1;
  }
  return out;
}

// Result constructors. XIOM v0.61.3 miscompiles direct Ok/Err construction in
// struct-returning functions; these helpers keep construction in a plain
// Result-returning function (SPEC.md: compiler workarounds).
fn _ok_vec(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

fn _err_vec(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

fn _ok_str(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Build "patch: hunk N failed to apply at line L".
fn _apply_error(hunk: Int, line: Int) -> Str {
  return "patch: hunk " + int_to_string(hunk) + " failed to apply at line " + int_to_string(line);
}

// -- public API --------------------------------------------------------------

/// Parse a unified hunk header line.
/// Accepted grammar (spaces between tokens are optional; spaces are the only
/// separator): "@@" then "-start[,count]" then "+start[,count]" then an
/// optional canonical " @@" terminator; anything after the terminator is
/// ignored (git function context). An omitted ",count" defaults to 1. All
/// numbers are non-negative decimal integers.
/// Params: line -- one line of patch text (CR stripped by callers).
/// Returns: Some((oldStart, oldCount, newStart, newCount)) when the line is a
/// well-formed header; None for malformed input.
/// Error case: none (failure is None).
/// Complexity: O(len(line)).
pub fn patch_parse_hunk_header(line: Str) -> Option[(Int, Int, Int, Int)] {
  let n = line.len();
  if n < 5 {
    return None;
  }
  if !str_starts_with(line, "@@") {
    return None;
  }
  var i = _skip_spaces(line, 2);
  var old_start: Int = 0;
  var old_count: Int = 0;
  var pos: Int = 0;
  var bad_old = false;
  match _parse_range(line, i) {
    Some((a, b, c)) => { old_start = a; old_count = b; pos = c; },
    None => { bad_old = true; },
  }
  if bad_old {
    return None;
  }
  i = _skip_spaces(line, pos);
  if i >= n {
    return None;
  }
  if (byte_at(line, i) as Int) != 43 {
    return None;
  }
  var new_start: Int = 0;
  var new_count: Int = 0;
  var bad_new = false;
  match _parse_range(line, i) {
    Some((a, b, c)) => { new_start = a; new_count = b; pos = c; },
    None => { bad_new = true; },
  }
  if bad_new {
    return None;
  }
  i = _skip_spaces(line, pos);
  if i < n {
    if (byte_at(line, i) as Int) != 64 {
      return None;
    }
    if i + 1 >= n {
      return None;
    }
    if (byte_at(line, i + 1) as Int) != 64 {
      return None;
    }
  }
  return Some((old_start, old_count, new_start, new_count));
}

/// Count hunk headers in patch text.
/// A hunk header is any line whose first two bytes are "@@" (a malformed
/// "@@..." line is counted; patch_apply rejects it later).
/// Returns: the number of hunk headers (0 for empty text).
/// Complexity: O(len(text)).
pub fn patch_count_hunks(text: Str) -> Int {
  let lines = str_split(text, "\n");
  var count = 0;
  var i = 0;
  while i < lines.len() {
    let line = _strip_cr(lines[i]);
    if str_starts_with(line, "@@") {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Extract the removed lines of a patch: every '-' body line with the sign
/// stripped, in file order. File headers ("--- ...") are excluded; "\ No
/// newline at end of file" markers are ignored.
/// Returns: a fresh Vec[Str] of line contents (empty when none).
/// Complexity: O(len(text)).
pub fn patch_extract_removed(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let lines = str_split(text, "\n");
  var i = 0;
  while i < lines.len() {
    let line = _strip_cr(lines[i]);
    if line.len() > 0 {
      if (byte_at(line, 0) as Int) == 45 && !str_starts_with(line, "---") {
        out.push(str_slice(line, 1, line.len()));
      }
    }
    i = i + 1;
  }
  return out;
}

/// Extract the added lines of a patch: every '+' body line with the sign
/// stripped, in file order. File headers ("+++ ...") are excluded; "\ No
/// newline at end of file" markers are ignored.
/// Returns: a fresh Vec[Str] of line contents (empty when none).
/// Complexity: O(len(text)).
pub fn patch_extract_added(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let lines = str_split(text, "\n");
  var i = 0;
  while i < lines.len() {
    let line = _strip_cr(lines[i]);
    if line.len() > 0 {
      if (byte_at(line, 0) as Int) == 43 && !str_starts_with(line, "+++") {
        out.push(str_slice(line, 1, line.len()));
      }
    }
    i = i + 1;
  }
  return out;
}

/// Apply a single-file unified diff to `source`.
/// Hunks are processed in file order. Each hunk matches its full old side
/// (context plus removed lines; context lines are never dropped) against the
/// working lines at 0-based index oldStart-1, adjusted by the accumulated line
/// delta of previously applied hunks. A hunk with oldCount == 0 (pure
/// insertion) anchors at 0-based index oldStart instead, following git's -U0
/// convention. When the anchor does not match, positions anchor+-1..anchor+-20
/// are tried; the first match wins (nearest first, lower index before higher
/// within the same distance). On no match the call fails and the returned
/// vector is discarded.
/// Params: source -- current file lines (no trailing newline elements);
///         patch -- LF or CRLF unified patch text.
/// Returns: Ok(new lines) on success; Err("patch: malformed hunk header") for
///          a malformed "@@" line; Err("patch: hunk N failed to apply at line
///          L") for an unapplicable hunk (N is 1-based, L is the hunk's
///          oldStart); Ok(source copy) for empty text or text without hunks.
/// Complexity: O(|source| + |patch| + hunks * fuzz * hunk size).
pub fn patch_apply(source: &Vec[Str], patch: Str) -> Result[Vec[Str], Str] {
  var work = _copy_vec(source);
  let plines = str_split(patch, "\n");
  var i = 0;
  var hunk_no = 0;
  var offset = 0;
  while i < plines.len() {
    let raw = _strip_cr(plines[i]);
    if !str_starts_with(raw, "@@") {
      i = i + 1;
    } else {
      hunk_no = hunk_no + 1;
      var old_start: Int = 0;
      var old_count: Int = 0;
      var bad = false;
      match patch_parse_hunk_header(raw) {
        Some((a, b, _, _)) => { old_start = a; old_count = b; },
        None => { bad = true; },
      }
      if bad {
        return _err_vec("patch: malformed hunk header");
      }
      var old_lines = Vec[Str].new();
      var new_lines = Vec[Str].new();
      i = i + 1;
      while i < plines.len() {
        let bl = _strip_cr(plines[i]);
        if bl.len() == 0 {
          i = i + 1;
        } elif str_starts_with(bl, "@@") {
          break;
        } elif str_starts_with(bl, "---") {
          break;
        } elif str_starts_with(bl, "+++") {
          break;
        } else {
          let c = byte_at(bl, 0) as Int;
          if c == 32 {
            let content = str_slice(bl, 1, bl.len());
            old_lines.push(content);
            new_lines.push(content);
            i = i + 1;
          } elif c == 45 {
            old_lines.push(str_slice(bl, 1, bl.len()));
            i = i + 1;
          } elif c == 43 {
            new_lines.push(str_slice(bl, 1, bl.len()));
            i = i + 1;
          } elif c == 92 {
            i = i + 1;
          } else {
            break;
          }
        }
      }
      var anchor = old_start - 1;
      if old_count == 0 {
        anchor = old_start;
      }
      let pos = _find_apply_pos(&work, &old_lines, anchor + offset, 20);
      if pos < 0 {
        return _err_vec(_apply_error(hunk_no, old_start));
      }
      work = _splice(&work, pos, old_lines.len(), &new_lines);
      offset = offset + new_lines.len() - old_lines.len();
    }
  }
  return _ok_vec(work);
}

/// Apply a unified diff to LF-separated source text.
/// Splits `source` on '\n', applies the hunks with patch_apply, and joins the
/// result with '\n', so a trailing newline in `source` is preserved as a
/// trailing empty element. Errors are returned unchanged from patch_apply.
/// Params: source -- whole file text; patch -- LF or CRLF unified patch text.
/// Returns: Ok(new text) or the patch_apply error.
/// Complexity: O(|source| + |patch| + hunks * fuzz * hunk size).
pub fn patch_apply_text(source: Str, patch: Str) -> Result[Str, Str] {
  let src_lines = str_split(source, "\n");
  let applied = patch_apply(&src_lines, patch);
  var ok = false;
  var text = "";
  var message = "";
  match applied {
    Ok(v) => { ok = true; text = str_join(&v, "\n"); },
    Err(e) => { message = e; },
  }
  if ok {
    return _ok_str(text);
  }
  return _err_str(message);
}
