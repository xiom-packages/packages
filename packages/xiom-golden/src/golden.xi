// XIOM -- xiom.golden: golden-file comparison helpers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no filesystem I/O. Every function
// works on in-memory byte buffers (Vec[UInt8]) so the module can be used by
// any test harness and stays trivially testable itself.
//
// What it provides:
//   * exact byte comparison with a first-difference offset and a difference
//     kind (equal / content / actual shorter / actual longer);
//   * text comparison that first normalizes both buffers (CRLF and lone CR
//     become LF), then optionally ignores trailing spaces/tabs on each line
//     (flag bit 0) and trailing newlines at end of file (flag bit 1);
//   * a bounded line-diff summary that renders the first N differing lines
//     with escape-rendered content and a terminator marker, and counts all
//     differing lines without rendering them;
//   * hex and escape rendering that maps every byte deterministically and
//     renders NUL as the four characters `\x00` -- it never builds a Str
//     from raw bytes, so no NUL truncation is possible (v0.61.3 note);
//   * update-mode flag parsing for a command-line style argument vector
//     (`-u`/`--update`, `-t`/`--text`, `-b`/`--bytes`,
//     `--ignore-trailing-space`, `--ignore-trailing-newline`,
//     `--max-lines=N`, `-q`/`--quiet`), returning a GoldenOptions struct or
//     a deterministic error string;
//   * golden path convention helpers: `tests/golden/<slug>.golden` default
//     paths, `.actual` / `.new` update siblings, and test-name sanitising.
//
// Language notes (XIOM v0.61.3) that shaped this module:
//   * free functions only, no self methods; no Vec[StructType] anywhere.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * Str values read out of a Vec[Str] are bound to a typed local and
//     compared with str_compare, never with `==` (BUG-17 lowering).
//   * every UInt8 is widened with `(b as Int) & 0xFF` before arithmetic;
//     comparisons use Int constants.
//   * escape rendering pushes bytes and hex text only, so a 0x00 in the
//     input becomes the text `\x00` and never reaches sb_to_str as a NUL.

module xiom.golden

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _G_LF: Int = 10;
const _G_CR: Int = 13;
const _G_TAB: Int = 9;
const _G_SPACE: Int = 32;
const _G_QUOTE: Int = 34;
const _G_BACKSLASH: Int = 92;
const _G_SLASH: Int = 47;
const _G_DIGIT_0: Int = 48;
const _G_DIGIT_9: Int = 57;
const _G_FLAG_SPACE: Int = 1;
const _G_FLAG_NEWLINE: Int = 2;
const _G_DEFAULT_MAX_LINES: Int = 8;
const _G_MAX_LINES_LIMIT: Int = 1000000;
const _G_RENDER_MAX: Int = 120;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Result of one comparison, byte or normalized text.
///
/// `equal` is 1 when no difference exists. `kind` is 0 (equal), 1 (content
/// differs), 2 (actual is a proper prefix of expected, i.e. actual shorter)
/// or 3 (expected is a proper prefix of actual, i.e. actual longer).
/// `first_diff` is the byte offset of the first differing byte in the
/// compared buffers (after normalization for text compares), or the length
/// of the shorter buffer when one is a prefix of the other; -1 when equal.
/// `diff_line` is the 1-based line number holding `first_diff` for text
/// compares and -1 for byte compares or when equal. `expected_len` /
/// `actual_len` are compared lengths. `expected_lines` / `actual_lines` are
/// line counts for text compares and -1 for byte compares.
pub type GoldenResult = {
  equal: Int;
  kind: Int;
  first_diff: Int;
  diff_line: Int;
  expected_len: Int;
  actual_len: Int;
  expected_lines: Int;
  actual_lines: Int;
}

/// Parsed options for a golden comparison run.
///
/// `update` is 1 when regeneration was requested, `text` is 1 for text
/// comparison (the default) and 0 for bytes, `flags` carries the tolerance
/// bits (see golden_flag_ignore_trailing_space and
/// golden_flag_ignore_trailing_newline), `max_lines` bounds the rendered
/// line-diff summary (default 8) and `quiet` is 1 when output was
/// suppressed.
pub type GoldenOptions = {
  update: Int;
  text: Int;
  flags: Int;
  max_lines: Int;
  quiet: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[GoldenOptions, Str].
fn _ok_opts(v: GoldenOptions) -> Result[GoldenOptions, Str] {
  return Ok(v);
}

// Err(m) for Result[GoldenOptions, Str].
fn _err_opts(m: Str) -> Result[GoldenOptions, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Small text helpers
// --------------------------------------------------

// Byte `pos` of `buf` widened to 0..255.
fn _byte_at(buf: &Vec[UInt8], pos: Int) -> Int {
  let raw: UInt8 = buf[pos];
  return (raw as Int) & 0xFF;
}

// True when `s` equals `want` (BUG-17 safe).
fn _str_is(s: Str, want: Str) -> Bool {
  return compare.str_compare(s, want) == 0;
}

// True when `s` starts with `prefix`.
fn _starts_with(s: Str, prefix: Str) -> Bool {
  let n = string.str_len(s);
  let p = string.str_len(prefix);
  if p > n {
    return false;
  }
  if p == 0 {
    return true;
  }
  let head = string.str_slice(s, 0, p);
  return _str_is(head, prefix);
}

// True when `s` ends with `suffix`.
fn _ends_with(s: Str, suffix: Str) -> Bool {
  let n = string.str_len(s);
  let p = string.str_len(suffix);
  if p > n {
    return false;
  }
  if p == 0 {
    return true;
  }
  let tail = string.str_slice(s, n - p, n);
  return _str_is(tail, suffix);
}

// `s` from byte `k` to its end (empty when `k` is past the end).
fn _slice_from(s: Str, k: Int) -> Str {
  let n = string.str_len(s);
  if k >= n {
    return "";
  }
  if k < 0 {
    return s;
  }
  return string.str_slice(s, k, n);
}

// Decimal digits only; bounded so the accumulator cannot overflow.
fn _parse_uint(s: Str) -> Result[Int, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_int("golden: max-lines needs a number");
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let c = (b as Int) & 0xFF;
    if c < _G_DIGIT_0 || c > _G_DIGIT_9 {
      return _err_int("golden: max-lines must be a number");
    }
    v = v * 10 + (c - _G_DIGIT_0);
    if v > _G_MAX_LINES_LIMIT {
      return _err_int("golden: max-lines out of range");
    }
    i = i + 1;
  }
  return _ok_int(v);
}

// True when `bit` (1, 2, 4, ...) is set in the non-negative `flags` mask.
fn _flag_on(flags: Int, bit: Int) -> Bool {
  let q = flags / bit;
  return q % 2 == 1;
}

// --------------------------------------------------
//  Text normalization
// --------------------------------------------------

// CRLF and lone CR both become LF; every other byte is preserved.
fn _crlf_to_lf(buf: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  let n = buf.len();
  while i < n {
    let b = _byte_at(buf, i);
    if b == _G_CR {
      out.push((_G_LF as UInt8));
      if i + 1 < n {
        let nb = _byte_at(buf, i + 1);
        if nb == _G_LF {
          i = i + 1;
        }
      }
    } else {
      out.push((b as UInt8));
    }
    i = i + 1;
  }
  return out;
}

// Runs of spaces/tabs immediately before an LF (or at EOF) are dropped;
// interior runs are preserved byte for byte.
fn _strip_trailing_spaces(buf: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  let n = buf.len();
  var run_start = 0;
  var run_len = 0;
  while i < n {
    let b = _byte_at(buf, i);
    if b == _G_SPACE || b == _G_TAB {
      if run_len == 0 {
        run_start = i;
      }
      run_len = run_len + 1;
    } else if b == _G_LF {
      run_len = 0;
      out.push((_G_LF as UInt8));
    } else {
      if run_len > 0 {
        var k = 0;
        while k < run_len {
          out.push((_byte_at(buf, run_start + k) as UInt8));
          k = k + 1;
        }
        run_len = 0;
      }
      out.push((b as UInt8));
    }
    i = i + 1;
  }
  return out;
}

// All trailing LF bytes are dropped.
fn _drop_trailing_lf(buf: &Vec[UInt8]) -> Vec[UInt8] {
  var end = buf.len();
  var go = 1;
  if end == 0 {
    go = 0;
  }
  while go == 1 {
    let b = _byte_at(buf, end - 1);
    if b == _G_LF {
      end = end - 1;
      if end == 0 {
        go = 0;
      }
    } else {
      go = 0;
    }
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < end {
    out.push((_byte_at(buf, i) as UInt8));
    i = i + 1;
  }
  return out;
}

/// Normalize a text buffer for comparison.
///
/// Step 1 (always): CRLF and lone CR become LF.
/// Step 2 (flag bit 0, golden_flag_ignore_trailing_space): trailing
/// spaces/tabs before every LF and at EOF are removed.
/// Step 3 (flag bit 1, golden_flag_ignore_trailing_newline): all trailing
/// LF bytes at EOF are removed.
pub fn golden_normalize_text(buf: &Vec[UInt8], flags: Int) -> Vec[UInt8] {
  let stage = _crlf_to_lf(buf);
  var cur = stage;
  if _flag_on(flags, _G_FLAG_SPACE) {
    let next = _strip_trailing_spaces(&cur);
    cur = next;
  }
  if _flag_on(flags, _G_FLAG_NEWLINE) {
    let next = _drop_trailing_lf(&cur);
    cur = next;
  }
  return cur;
}

// --------------------------------------------------
//  Line helpers
// --------------------------------------------------

/// Number of LF-terminated segments plus a final segment when the buffer
/// does not end with LF. Empty buffer = 0 lines; "a\n" = 1; "a\nb" = 2;
/// "a\n\n" = 2.
pub fn golden_count_lines(buf: &Vec[UInt8]) -> Int {
  let n = buf.len();
  if n == 0 {
    return 0;
  }
  var lines = 0;
  var i = 0;
  while i < n {
    let b = _byte_at(buf, i);
    if b == _G_LF {
      lines = lines + 1;
    }
    i = i + 1;
  }
  let last = _byte_at(buf, n - 1);
  if last != _G_LF {
    lines = lines + 1;
  }
  return lines;
}

// 1-based line number of byte offset `off` (clamped to the buffer end).
fn _line_of_offset(buf: &Vec[UInt8], off: Int) -> Int {
  let n = buf.len();
  var o = off;
  if o > n {
    o = n;
  }
  if o < 0 {
    o = 0;
  }
  var line = 1;
  var i = 0;
  while i < o {
    let b = _byte_at(buf, i);
    if b == _G_LF {
      line = line + 1;
    }
    i = i + 1;
  }
  return line;
}

// End of the line starting at `start`: index of the next LF, or the buffer
// end when the line has no terminator.
fn _line_end(buf: &Vec[UInt8], start: Int) -> Int {
  var i = start;
  let n = buf.len();
  while i < n {
    let b = _byte_at(buf, i);
    if b == _G_LF {
      return i;
    }
    i = i + 1;
  }
  return n;
}

// True when a[start .. start+an) equals b[b0 .. b0+bn).
fn _ranges_equal(a: &Vec[UInt8], a0: Int, an: Int, b: &Vec[UInt8], b0: Int, bn: Int) -> Bool {
  if an != bn {
    return false;
  }
  var i = 0;
  while i < an {
    let x: UInt8 = a[a0 + i];
    let y: UInt8 = b[b0 + i];
    if (x as Int) != (y as Int) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Comparison
// --------------------------------------------------

/// Exact byte comparison. See GoldenResult for the field semantics.
pub fn golden_compare_bytes(expected: &Vec[UInt8], actual: &Vec[UInt8]) -> GoldenResult {
  let el = expected.len();
  let al = actual.len();
  var n = el;
  if al < n {
    n = al;
  }
  var i = 0;
  var diff = -1;
  while i < n {
    if diff < 0 {
      let eb: UInt8 = expected[i];
      let ab: UInt8 = actual[i];
      if (eb as Int) != (ab as Int) {
        diff = i;
      }
    }
    i = i + 1;
  }
  var eq = 0;
  var kind = 0;
  var fd = -1;
  if diff >= 0 {
    kind = 1;
    fd = diff;
  } else if el == al {
    eq = 1;
  } else if al < el {
    kind = 2;
    fd = n;
  } else {
    kind = 3;
    fd = n;
  }
  return GoldenResult{
    equal: eq;
    kind: kind;
    first_diff: fd;
    diff_line: -1;
    expected_len: el;
    actual_len: al;
    expected_lines: -1;
    actual_lines: -1;
  };
}

/// Normalized text comparison: both buffers go through
/// golden_normalize_text first, then compare byte for byte. `first_diff`
/// and lengths refer to the normalized buffers; `diff_line` is the 1-based
/// line holding the first difference.
pub fn golden_compare_text(expected: &Vec[UInt8], actual: &Vec[UInt8], flags: Int) -> GoldenResult {
  let ne = golden_normalize_text(expected, flags);
  let na = golden_normalize_text(actual, flags);
  let base = golden_compare_bytes(&ne, &na);
  var diff_line = -1;
  if base.first_diff >= 0 {
    diff_line = _line_of_offset(&ne, base.first_diff);
  }
  return GoldenResult{
    equal: base.equal;
    kind: base.kind;
    first_diff: base.first_diff;
    diff_line: diff_line;
    expected_len: base.expected_len;
    actual_len: base.actual_len;
    expected_lines: golden_count_lines(&ne);
    actual_lines: golden_count_lines(&na);
  };
}

// --------------------------------------------------
//  Result accessors
// --------------------------------------------------

/// True when the comparison found no difference.
pub fn golden_equal(r: &GoldenResult) -> Bool {
  return r.equal == 1;
}

/// Difference kind: 0 equal, 1 content, 2 actual shorter, 3 actual longer.
pub fn golden_kind(r: &GoldenResult) -> Int {
  return r.kind;
}

/// Byte offset of the first difference (-1 when equal).
pub fn golden_first_diff(r: &GoldenResult) -> Int {
  return r.first_diff;
}

/// 1-based line of the first difference for text compares (-1 otherwise).
pub fn golden_diff_line(r: &GoldenResult) -> Int {
  return r.diff_line;
}

/// Compared (normalized) length of the expected buffer.
pub fn golden_expected_len(r: &GoldenResult) -> Int {
  return r.expected_len;
}

/// Compared (normalized) length of the actual buffer.
pub fn golden_actual_len(r: &GoldenResult) -> Int {
  return r.actual_len;
}

/// Line count of the normalized expected buffer, -1 for byte compares.
pub fn golden_expected_lines(r: &GoldenResult) -> Int {
  return r.expected_lines;
}

/// Line count of the normalized actual buffer, -1 for byte compares.
pub fn golden_actual_lines(r: &GoldenResult) -> Int {
  return r.actual_lines;
}

/// Human-readable kind name ("equal", "content", "actual-shorter",
/// "actual-longer" or "unknown").
pub fn golden_kind_name(kind: Int) -> Str {
  if kind == 0 {
    return "equal";
  }
  if kind == 1 {
    return "content";
  }
  if kind == 2 {
    return "actual-shorter";
  }
  if kind == 3 {
    return "actual-longer";
  }
  return "unknown";
}

// --------------------------------------------------
//  Hex and escape rendering
// --------------------------------------------------

// One byte as two lowercase hex digits.
fn _hex2(v: Int) -> Str {
  var digits = "0123456789abcdef";
  let hi = v / 16;
  let lo = v % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

/// Whole buffer as lowercase hex, two characters per byte ("" when empty).
/// A NUL byte renders as "00" -- the result never contains a raw 0x00.
pub fn golden_hex(buf: &Vec[UInt8]) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  let n = buf.len();
  while i < n {
    builder.sb_push_str(&mut sb, _hex2(_byte_at(buf, i)));
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// Like golden_hex, but stops after `max_bytes` bytes (negative = no
/// bound) and appends "...(<k> more bytes)" when truncated.
pub fn golden_hex_bounded(buf: &Vec[UInt8], max_bytes: Int) -> Str {
  let n = buf.len();
  var limit = n;
  var truncated = 0;
  if max_bytes >= 0 {
    if max_bytes < n {
      limit = max_bytes;
      truncated = 1;
    }
  }
  var sb = builder.sb_new();
  var i = 0;
  while i < limit {
    builder.sb_push_str(&mut sb, _hex2(_byte_at(buf, i)));
    i = i + 1;
  }
  if truncated == 1 {
    builder.sb_push_str(&mut sb, "...(");
    builder.sb_push_int(&mut sb, n - limit);
    builder.sb_push_str(&mut sb, " more bytes)");
  }
  return builder.sb_to_str(&sb);
}

/// Escape-render `buf[start..end)` (clamped): printable ASCII 0x20..0x7E is
/// kept except `"` and `\` (rendered `\"` / `\\`), LF/CR/TAB become `\n`
/// /`\r`/`\t`, and every other byte (including 0x00) becomes `\xNN`. With
/// `max_bytes >= 0` at most that many input bytes are rendered, followed by
/// "...(<k> more bytes)" when truncated.
pub fn golden_escape_range(buf: &Vec[UInt8], start: Int, end: Int, max_bytes: Int) -> Str {
  let n = buf.len();
  var s = start;
  if s < 0 {
    s = 0;
  }
  if s > n {
    s = n;
  }
  var e = end;
  if e < s {
    e = s;
  }
  if e > n {
    e = n;
  }
  var limit = e;
  var truncated = 0;
  if max_bytes >= 0 {
    if s + max_bytes < e {
      limit = s + max_bytes;
      truncated = 1;
    }
  }
  var sb = builder.sb_new();
  var i = s;
  while i < limit {
    let b = _byte_at(buf, i);
    if b == _G_BACKSLASH {
      builder.sb_push_byte(&mut sb, (_G_BACKSLASH as UInt8));
      builder.sb_push_byte(&mut sb, (_G_BACKSLASH as UInt8));
    } else if b == _G_QUOTE {
      builder.sb_push_byte(&mut sb, (_G_BACKSLASH as UInt8));
      builder.sb_push_byte(&mut sb, (_G_QUOTE as UInt8));
    } else if b == _G_LF {
      builder.sb_push_byte(&mut sb, (_G_BACKSLASH as UInt8));
      builder.sb_push_byte(&mut sb, (110 as UInt8));
    } else if b == _G_CR {
      builder.sb_push_byte(&mut sb, (_G_BACKSLASH as UInt8));
      builder.sb_push_byte(&mut sb, (114 as UInt8));
    } else if b == _G_TAB {
      builder.sb_push_byte(&mut sb, (_G_BACKSLASH as UInt8));
      builder.sb_push_byte(&mut sb, (116 as UInt8));
    } else if b >= 32 && b <= 126 {
      builder.sb_push_byte(&mut sb, (b as UInt8));
    } else {
      builder.sb_push_byte(&mut sb, (_G_BACKSLASH as UInt8));
      builder.sb_push_byte(&mut sb, (120 as UInt8));
      builder.sb_push_str(&mut sb, _hex2(b));
    }
    i = i + 1;
  }
  if truncated == 1 {
    builder.sb_push_str(&mut sb, "...(");
    builder.sb_push_int(&mut sb, e - limit);
    builder.sb_push_str(&mut sb, " more bytes)");
  }
  return builder.sb_to_str(&sb);
}

/// Whole-buffer escape rendering (see golden_escape_range).
pub fn golden_escape(buf: &Vec[UInt8]) -> Str {
  return golden_escape_range(buf, 0, buf.len(), -1);
}

/// Bounded whole-buffer escape rendering (see golden_escape_range).
pub fn golden_escape_bounded(buf: &Vec[UInt8], max_bytes: Int) -> Str {
  return golden_escape_range(buf, 0, buf.len(), max_bytes);
}

// --------------------------------------------------
//  Bounded line-diff summary
// --------------------------------------------------

// Append one rendered line to a builder: `<none>` when absent, otherwise
// the escaped content in double quotes plus a `\n` marker when the line
// carried a terminator.
fn _push_line_render(sb: &mut Vec[UInt8], buf: &Vec[UInt8], start: Int, stop: Int, present: Int) {
  if present == 0 {
    builder.sb_push_str(sb, "<none>");
    return;
  }
  builder.sb_push_byte(sb, (_G_QUOTE as UInt8));
  builder.sb_push_str(sb, golden_escape_range(buf, start, stop, _G_RENDER_MAX));
  builder.sb_push_byte(sb, (_G_QUOTE as UInt8));
  let n = buf.len();
  if stop < n {
    builder.sb_push_byte(sb, (_G_BACKSLASH as UInt8));
    builder.sb_push_byte(sb, (110 as UInt8));
  }
}

/// Bounded line-diff summary of two text buffers.
///
/// Both buffers are normalized with golden_normalize_text first. Lines are
/// compared by content and by whether they carried a terminator, so a
/// missing final newline and a missing line are both reported on the line
/// where they occur. At most `max_entries` differing lines are rendered
/// (negative clamps to 0); all differing lines are counted. The result is
/// "golden: equal\n" when no line differs, otherwise a header
/// "golden: <n> line(s) differ\n", the rendered lines and, when truncated,
/// "  ... (<k> more differing line(s))\n".
pub fn golden_diff_summary(expected: &Vec[UInt8], actual: &Vec[UInt8], flags: Int, max_entries: Int) -> Str {
  let ne = golden_normalize_text(expected, flags);
  let na = golden_normalize_text(actual, flags);
  let elen = ne.len();
  let alen = na.len();
  var cap = max_entries;
  if cap < 0 {
    cap = 0;
  }
  var body = builder.sb_new();
  var pe = 0;
  var pa = 0;
  var line = 0;
  var differing = 0;
  while pe < elen || pa < alen {
    line = line + 1;
    var has_e = 0;
    if pe < elen {
      has_e = 1;
    }
    var has_a = 0;
    if pa < alen {
      has_a = 1;
    }
    var ee = pe;
    if has_e == 1 {
      ee = _line_end(&ne, pe);
    }
    var ea = pa;
    if has_a == 1 {
      ea = _line_end(&na, pa);
    }
    var same = 0;
    if has_e == 1 && has_a == 1 {
      let ceq = _ranges_equal(&ne, pe, ee - pe, &na, pa, ea - pa);
      var te = 0;
      if ee < elen {
        te = 1;
      }
      var ta = 0;
      if ea < alen {
        ta = 1;
      }
      if ceq && te == ta {
        same = 1;
      }
    }
    if same == 0 {
      differing = differing + 1;
      if differing <= cap {
        builder.sb_push_str(&mut body, "  line ");
        builder.sb_push_int(&mut body, line);
        builder.sb_push_str(&mut body, ": expected=");
        _push_line_render(&mut body, &ne, pe, ee, has_e);
        builder.sb_push_str(&mut body, " actual=");
        _push_line_render(&mut body, &na, pa, ea, has_a);
        builder.sb_push_str(&mut body, "\n");
      }
    }
    if has_e == 1 {
      if ee < elen {
        pe = ee + 1;
      } else {
        pe = elen;
      }
    }
    if has_a == 1 {
      if ea < alen {
        pa = ea + 1;
      } else {
        pa = alen;
      }
    }
  }
  if differing == 0 {
    return "golden: equal\n";
  }
  var out = builder.sb_new();
  builder.sb_push_str(&mut out, "golden: ");
  builder.sb_push_int(&mut out, differing);
  builder.sb_push_str(&mut out, " line(s) differ\n");
  builder.sb_push_str(&mut out, builder.sb_to_str(&body));
  if differing > cap {
    builder.sb_push_str(&mut out, "  ... (");
    builder.sb_push_int(&mut out, differing - cap);
    builder.sb_push_str(&mut out, " more differing line(s))\n");
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Flag parsing (update mode and tolerance bits)
// --------------------------------------------------

/// Tolerance bit: ignore trailing spaces/tabs on each line.
pub fn golden_flag_ignore_trailing_space() -> Int {
  return _G_FLAG_SPACE;
}

/// Tolerance bit: ignore trailing newlines at end of file.
pub fn golden_flag_ignore_trailing_newline() -> Int {
  return _G_FLAG_NEWLINE;
}

/// Default options: no update, text mode, no tolerance flags, max_lines 8.
pub fn golden_options_default() -> GoldenOptions {
  return GoldenOptions{
    update: 0;
    text: 1;
    flags: 0;
    max_lines: _G_DEFAULT_MAX_LINES;
    quiet: 0;
  };
}

/// Parse a command-line style argument vector.
///
/// Recognized: `-u`/`--update`, `-t`/`--text`, `-b`/`--bytes`,
/// `--ignore-trailing-space`, `--ignore-trailing-newline`,
/// `--max-lines=N` (N in 1..=1000000), `-q`/`--quiet`. Anything else is
/// Err("golden: unknown flag: <token>"); a malformed `--max-lines` value is
/// Err("golden: max-lines needs a number" / "must be a number" /
/// "out of range").
pub fn golden_parse_options(args: &Vec[Str]) -> Result[GoldenOptions, Str] {
  var opts = golden_options_default();
  let n = args.len();
  var i = 0;
  while i < n {
    let raw: Vec[Str] = args;
    let a: Str = raw[i];
    if _str_is(a, "-u") {
      opts.update = 1;
    } else if _str_is(a, "--update") {
      opts.update = 1;
    } else if _str_is(a, "-t") {
      opts.text = 1;
    } else if _str_is(a, "--text") {
      opts.text = 1;
    } else if _str_is(a, "-b") {
      opts.text = 0;
    } else if _str_is(a, "--bytes") {
      opts.text = 0;
    } else if _str_is(a, "--ignore-trailing-space") {
      opts.flags = opts.flags + _G_FLAG_SPACE;
    } else if _str_is(a, "--ignore-trailing-newline") {
      opts.flags = opts.flags + _G_FLAG_NEWLINE;
    } else if _str_is(a, "-q") {
      opts.quiet = 1;
    } else if _str_is(a, "--quiet") {
      opts.quiet = 1;
    } else if _starts_with(a, "--max-lines=") {
      let tail = _slice_from(a, 12);
      let vr = _parse_uint(tail);
      if !vr.is_ok {
        return _err_opts(vr.error);
      }
      let v = vr.value;
      if v < 1 {
        return _err_opts("golden: max-lines out of range");
      }
      opts.max_lines = v;
    } else {
      return _err_opts("golden: unknown flag: " + a);
    }
    i = i + 1;
  }
  return _ok_opts(opts);
}

/// True when update mode was requested.
pub fn golden_option_update(o: &GoldenOptions) -> Bool {
  return o.update == 1;
}

/// True when text comparison (the default) is selected.
pub fn golden_option_text(o: &GoldenOptions) -> Bool {
  return o.text == 1;
}

/// Tolerance flag bits.
pub fn golden_option_flags(o: &GoldenOptions) -> Int {
  return o.flags;
}

/// Summary bound in lines.
pub fn golden_option_max_lines(o: &GoldenOptions) -> Int {
  return o.max_lines;
}

/// True when quiet mode was requested.
pub fn golden_option_quiet(o: &GoldenOptions) -> Bool {
  return o.quiet == 1;
}

// --------------------------------------------------
//  Path conventions
// --------------------------------------------------

/// Join `dir` and `name` with `/`, tolerating empty parts and a trailing
/// `/` or `\` on `dir`.
pub fn golden_join(dir: Str, name: Str) -> Str {
  let dl = string.str_len(dir);
  let nl = string.str_len(name);
  if dl == 0 {
    return name;
  }
  if nl == 0 {
    return dir;
  }
  let last = string.byte_at(dir, dl - 1);
  let c = (last as Int) & 0xFF;
  if c == _G_SLASH || c == _G_BACKSLASH {
    return dir + name;
  }
  return dir + "/" + name;
}

/// Replace every byte outside [A-Za-z0-9._-] with `_`, collapsing runs and
/// dropping leading/trailing separators. An empty result becomes "golden".
pub fn golden_slug(s: Str) -> Str {
  var sb = builder.sb_new();
  let n = string.str_len(s);
  var i = 0;
  var pending = 0;
  var wrote = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let c = (b as Int) & 0xFF;
    if _is_slug_char(c) {
      if pending == 1 && wrote == 1 {
        builder.sb_push_byte(&mut sb, (95 as UInt8));
      }
      pending = 0;
      builder.sb_push_byte(&mut sb, b);
      wrote = 1;
    } else {
      pending = 1;
    }
    i = i + 1;
  }
  if wrote == 0 {
    return "golden";
  }
  return builder.sb_to_str(&sb);
}

// [A-Za-z0-9._-]
fn _is_slug_char(c: Int) -> Bool {
  if c >= _G_DIGIT_0 && c <= _G_DIGIT_9 {
    return true;
  }
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  if c == 46 || c == 45 || c == 95 {
    return true;
  }
  return false;
}

/// Default golden path for a test name: "tests/golden/<slug>.golden".
pub fn golden_default_path(name: Str) -> Str {
  return golden_join("tests/golden", golden_slug(name) + ".golden");
}

/// Sibling path used to write the failing actual output: `<path>.actual`.
pub fn golden_actual_path(path: Str) -> Str {
  return path + ".actual";
}

/// Sibling path used by update mode for the regenerated file: `<path>.new`.
pub fn golden_new_path(path: Str) -> Str {
  return path + ".new";
}

/// True when `path` ends with ".golden".
pub fn golden_is_golden_path(path: Str) -> Bool {
  return _ends_with(path, ".golden");
}
