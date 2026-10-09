// XIOM -- xiom.coverage: gcov coverage-text codec and summary math
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no I/O (in-memory Str only).
//
// A parser, accessor set, canonical emitter and summary math for the text
// form of gcov coverage data (the ".gcov" files written by gcov). The exact
// grammar is in SPEC.md; section 8 there is the error catalog. In short:
//   * "-:    0:Source:<path>" and the other metadata records (Source, Graph,
//     Data, Runs, Programs) open a file section and carry its identity;
//   * "count:lineno:source" line records, where count is a run of digits
//     (executed), ##### (not executed), ===== (no code) or - (no line);
//   * "function <name> called <N> returned <P>% blocks executed <Q>%";
//   * "branch <N> taken <M>", "branch <N> taken never" and
//     "branch <N> never executed";
//   * "call <N> returned <tail>" and "unconditional <N> taken [<M>]".
// Blank (empty or SPACE/TAB-only) lines are ignored; one CR before the LF is
// dropped, so LF and CRLF inputs both work. The first malformed line aborts
// the parse with Err("coverage: <reason> at line L byte O"), where O is the
// 0-based byte offset of that line's first non-SPACE/TAB byte.
//
// NOT in scope: no .gcda / .gcno binary parsing, no gcov invocation, no
// coverage merging, no filtering, no report rendering. This module reads and
// writes the text form only; the numbers in the text are data, trusted as
// parsed. A GcovDoc describes text, not a running program.
//
// Model: one parsed stream is a GcovDoc with flat, index-aligned parallel
// vectors because XIOM v0.61.3 cannot hold Vec[StructType]. Each Source
// section owns ranges into six global record stores (lines, branches,
// functions, calls, unconditionals, events); every push on a store is
// mirrored on its per-file count array, so ranges never drift. The event
// store keeps the per-file record order, so the canonical emitter can
// reproduce the input stream order exactly. Every accessor clamps ranges to
// the shortest parallel arrays, so a hand-built document cannot read out of
// range either.
//
// Language notes (XIOM v0.61.3): free functions only; Str equality goes
// through xiom.string.compare.str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison); every Vec element
// read is bound to a typed local first; .len() is never trusted on Str
// values read from Vec[Str] elements, so per-file presence flags replace
// emptiness checks there; Ok/Err for Result[GcovDoc, Str] are constructed
// only in the leaf helpers _ok_doc/_err_doc because direct Result
// construction in other shapes miscompiles in this compiler; there is no
// Vec[Float64], so percentages are integers (floor) or integer basis points.

module xiom.coverage

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Record constants
// --------------------------------------------------

/// Event kind of a line record.
pub const GCOV_EV_LINE: Int = 0;
/// Event kind of a function summary record.
pub const GCOV_EV_FUNCTION: Int = 1;
/// Event kind of a branch record.
pub const GCOV_EV_BRANCH: Int = 2;
/// Event kind of a call record.
pub const GCOV_EV_CALL: Int = 3;
/// Event kind of an unconditional branch record.
pub const GCOV_EV_UNCONDITIONAL: Int = 4;

/// Line count sentinel for "#####" (line not executed).
pub const GCOV_NOT_EXECUTED: Int = -1;
/// Line count sentinel for "=====" (line has no code).
pub const GCOV_NO_CODE: Int = -2;
/// Line count sentinel for "-" (no line).
pub const GCOV_NO_LINE: Int = -3;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[GcovDoc, Str].
fn _ok_doc(d: GcovDoc) -> Result[GcovDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[GcovDoc, Str].
fn _err_doc(m: Str) -> Result[GcovDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (all ASCII, every comparison is with a byte < 128)
// --------------------------------------------------

const _GC_TAB: UInt8 = 9u8;
const _GC_LF: UInt8 = 10u8;
const _GC_CR: UInt8 = 13u8;
const _GC_SPACE: UInt8 = 32u8;
const _GC_HASH: UInt8 = 35u8;
const _GC_PCT: UInt8 = 37u8;
const _GC_DASH: UInt8 = 45u8;
const _GC_DIGIT_0: UInt8 = 48u8;
const _GC_DIGIT_9: UInt8 = 57u8;
const _GC_COLON: UInt8 = 58u8;
const _GC_EQ: UInt8 = 61u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed .gcov text stream, stored flat.
/// File section f (0-based, in stream order) is described by sf[f] (its
/// Source path) plus its metadata: graph[f]/data[f] with graph_has[f]/
/// data_has[f] flags (1 = the record was present) and runs[f]/programs[f]
/// (-1 = absent). Its records live in six global stores, addressed by the
/// range (off[f], n[f]) of that file:
///   * lines:          ln_no, ln_cnt, ln_src
///   * branches:       br_idx, br_taken (taken -1 = never executed)
///   * functions:      fn_name, fn_called, fn_ret, fn_blocks
///   * calls:          cl_idx, cl_tail
///   * unconditionals: un_idx, un_taken (taken -1 = count absent)
///   * events:         ev_kind, ev_ref (local record index into its store)
/// ln_cnt holds the printed count for digits, or GCOV_NOT_EXECUTED /
/// GCOV_NO_CODE / GCOV_NO_LINE for the three sentinels. All per-file arrays
/// are kept index-aligned by the parser; _file_count is their shortest
/// length and every range is clamped, so a hand-built doc cannot read out of
/// range.
pub type GcovDoc = {
  sf: Vec[Str];
  graph: Vec[Str];
  graph_has: Vec[Int];
  data: Vec[Str];
  data_has: Vec[Int];
  runs: Vec[Int];
  programs: Vec[Int];
  ln_off: Vec[Int];
  ln_n: Vec[Int];
  br_off: Vec[Int];
  br_n: Vec[Int];
  fn_off: Vec[Int];
  fn_n: Vec[Int];
  cl_off: Vec[Int];
  cl_n: Vec[Int];
  un_off: Vec[Int];
  un_n: Vec[Int];
  ev_off: Vec[Int];
  ev_n: Vec[Int];
  ln_no: Vec[Int];
  ln_cnt: Vec[Int];
  ln_src: Vec[Str];
  br_idx: Vec[Int];
  br_taken: Vec[Int];
  fn_name: Vec[Str];
  fn_called: Vec[Int];
  fn_ret: Vec[Int];
  fn_blocks: Vec[Int];
  cl_idx: Vec[Int];
  cl_tail: Vec[Str];
  un_idx: Vec[Int];
  un_taken: Vec[Int];
  ev_kind: Vec[Int];
  ev_ref: Vec[Int];
}

// --------------------------------------------------
//  Small text helpers
// --------------------------------------------------

// True when `s` is empty or holds only ASCII spaces and tabs.
fn _is_blank(s: Str) -> Bool {
  var i = 0;
  let n = s.len();
  while i < n {
    let b = string.byte_at(s, i);
    if b != _GC_SPACE && b != _GC_TAB {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the first non-SPACE/TAB byte at or after `from`, or `s.len()`.
fn _skip_ws(s: Str, from: Int) -> Int {
  let n = s.len();
  var i = from;
  if i < 0 {
    i = 0;
  }
  while i < n {
    let b = string.byte_at(s, i);
    if b != _GC_SPACE && b != _GC_TAB {
      return i;
    }
    i = i + 1;
  }
  return n;
}

// `s` without leading and trailing ASCII spaces and tabs.
fn _trim(s: Str) -> Str {
  let a = _skip_ws(s, 0);
  var b = s.len();
  while b > a {
    let b2 = string.byte_at(s, b - 1);
    if b2 != _GC_SPACE && b2 != _GC_TAB {
      break;
    }
    b = b - 1;
  }
  return string.str_slice(s, a, b);
}

// True when `b` is an ASCII decimal digit.
fn _is_digit(b: UInt8) -> Bool {
  return b >= _GC_DIGIT_0 && b <= _GC_DIGIT_9;
}

// Byte index just past the digit run starting at `from`.
fn _digits_end(s: Str, from: Int) -> Int {
  var i = from;
  let n = s.len();
  while i < n && _is_digit(string.byte_at(s, i)) {
    i = i + 1;
  }
  return i;
}

// Byte index of the first ':' at or after `from`, or -1 when there is none.
fn _colon_at(s: Str, from: Int) -> Int {
  var i = from;
  let n = s.len();
  while i < n {
    if string.byte_at(s, i) == _GC_COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when `a` and `b` are the same text (BUG 17-safe).
fn _eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Byte index of the first occurrence of `needle` at or after `from`, or -1.
fn _find_token(s: Str, needle: Str, from: Int) -> Int {
  let n = s.len();
  let m = needle.len();
  if m == 0 || m > n {
    return -1;
  }
  var i = from;
  if i < 0 {
    i = 0;
  }
  while i + m <= n {
    if compare.str_compare(string.str_slice(s, i, i + m), needle) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when `tok` starts at byte `p` of `s`.
fn _token_at(s: Str, p: Int, tok: Str) -> Bool {
  let n = s.len();
  let m = tok.len();
  if p < 0 || m == 0 || p + m > n {
    return false;
  }
  return compare.str_compare(string.str_slice(s, p, p + m), tok) == 0;
}

// Parse the decimal run s[from..to) into a non-negative Int.
// Returns: the value for a valid run (a run of zeros yields 0); -1 when the
// run is empty, carries a non-digit byte, has more than 10 digits (so no
// overflow is possible) or exceeds 1000000000; -2 when the run starts with
// '-' and has at least one more byte. Note: every conversion widens the
// UInt8 through (b as Int) & 0xFF before subtracting, so no signed-byte
// surprises exist even for non-ASCII content.
fn _parse_num(s: Str, from: Int, to: Int) -> Int {
  if from >= to {
    return -1;
  }
  if string.byte_at(s, from) == _GC_DASH {
    if from + 1 < to {
      return -2;
    }
    return -1;
  }
  if to - from > 10 {
    return -1;
  }
  var v = 0;
  var i = from;
  while i < to {
    let b = string.byte_at(s, i);
    if b < _GC_DIGIT_0 || b > _GC_DIGIT_9 {
      return -1;
    }
    v = v * 10 + (((b as Int) & 0xFF) - 48);
    if v > 1000000000 {
      return -1;
    }
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Range and arithmetic helpers
// --------------------------------------------------

// Smaller of two Ints.
fn _min2(a: Int, b: Int) -> Int
  ensures: a < b => result == a;
  ensures: a >= b => result == b;
{
  if a < b {
    return a;
  }
  return b;
}

// Smallest of three Ints.
fn _min3(a: Int, b: Int, c: Int) -> Int
  ensures: result == _min2(_min2(a, b), c);
{
  return _min2(_min2(a, b), c);
}

// Smallest of four Ints.
fn _min4(a: Int, b: Int, c: Int, d: Int) -> Int {
  return _min2(_min3(a, b, c), d);
}

// Count of range [off, off+count) inside an array of length `total`,
// clamped so the result is always a valid sub-range. 0 when the range is
// empty, negative or starts at or past the end.
fn _span(off: Int, count: Int, total: Int) -> Int
  ensures: off < 0 || count <= 0 || off >= total => result == 0;
  ensures: off >= 0 && count > 0 && off < total && count > total - off => result == total - off;
  ensures: off >= 0 && count > 0 && off < total && count <= total - off => result == count;
{
  if off < 0 || count <= 0 || off >= total {
    return 0;
  }
  let room = total - off;
  if count > room {
    return room;
  }
  return count;
}

// Integer percent of `part` in `whole`, floored, 0 when either is <= 0.
// Division truncates toward zero, which for non-negative values is floor.
fn _pct_floor(part: Int, whole: Int) -> Int
  ensures: part <= 0 || whole <= 0 => result == 0;
  ensures: part > 0 && whole > 0 => result == (part * 100) / whole;
{
  if part <= 0 || whole <= 0 {
    return 0;
  }
  return (part * 100) / whole;
}

// Integer basis points (hundredths of a percent) of `part` in `whole`,
// floored, 0 when either is <= 0.
fn _pct_bp(part: Int, whole: Int) -> Int
  ensures: part <= 0 || whole <= 0 => result == 0;
  ensures: part > 0 && whole > 0 => result == (part * 10000) / whole;
{
  if part <= 0 || whole <= 0 {
    return 0;
  }
  return (part * 10000) / whole;
}

// --------------------------------------------------
//  Error message builder (the catalog is in SPEC.md)
// --------------------------------------------------

// One catalog message: reason, 1-based line number, 0-based byte offset of
// the line's first non-SPACE/TAB byte.
fn _err_line(line_no: Int, off: Int, what: Str) -> Str {
  return "coverage: " + what + " at line " + int_to_string(line_no) + " byte " + int_to_string(off);
}

// --------------------------------------------------
//  File sections and record stores
// --------------------------------------------------

// Append one file section, opening its six empty record ranges.
// Params: d - the document to mutate; source - the Source path (non-empty;
// the parser enforces that).
// Returns: nothing.
// Complexity: O(1).
fn _file_push(d: &mut GcovDoc, source: Str) {
  d.sf.push(source);
  d.graph.push("");
  d.graph_has.push(0);
  d.data.push("");
  d.data_has.push(0);
  d.runs.push(-1);
  d.programs.push(-1);
  d.ln_off.push(d.ln_no.len());
  d.ln_n.push(0);
  d.br_off.push(d.br_idx.len());
  d.br_n.push(0);
  d.fn_off.push(d.fn_name.len());
  d.fn_n.push(0);
  d.cl_off.push(d.cl_idx.len());
  d.cl_n.push(0);
  d.un_off.push(d.un_idx.len());
  d.un_n.push(0);
  d.ev_off.push(d.ev_kind.len());
  d.ev_n.push(0);
}

// Store one Graph or Data metadata value on the open file section.
// Params: d - the document; v - the non-empty value; is_graph - 1 for Graph,
// 0 for Data.
// Returns: nothing.
// Complexity: O(1).
fn _set_meta_text(d: &mut GcovDoc, v: Str, is_graph: Int) {
  if d.sf.len() == 0 {
    return;
  }
  let f = d.sf.len() - 1;
  if is_graph == 1 {
    d.graph[f] = v;
    d.graph_has[f] = 1;
  } else {
    d.data[f] = v;
    d.data_has[f] = 1;
  }
}

// Store the Runs or Programs metadata value on the open file section.
// Params: d - the document; v - the non-negative value; is_runs - 1 for
// Runs, 0 for Programs.
// Returns: nothing.
// Complexity: O(1).
fn _set_meta_num(d: &mut GcovDoc, v: Int, is_runs: Int) {
  if d.sf.len() == 0 {
    return;
  }
  let f = d.sf.len() - 1;
  if is_runs == 1 {
    d.runs[f] = v;
  } else {
    d.programs[f] = v;
  }
}

// Append one line record (kind 0 = counted, 1 = #####, 2 = =====, 3 = -).
// Params: d - the document; ln - the 1-based source line number; cnt - the
// parsed count for kind 0; src - the source text (verbatim, may be empty);
// kind - the record kind.
// Returns: nothing.
// Complexity: O(1).
fn _push_line(d: &mut GcovDoc, ln: Int, cnt: Int, src: Str, kind: Int) {
  if d.sf.len() == 0 {
    return;
  }
  let f = d.sf.len() - 1;
  let li: Int = d.ln_n[f];
  var stored = cnt;
  if kind == 1 {
    stored = GCOV_NOT_EXECUTED;
  } elif kind == 2 {
    stored = GCOV_NO_CODE;
  } elif kind == 3 {
    stored = GCOV_NO_LINE;
  }
  d.ln_no.push(ln);
  d.ln_cnt.push(stored);
  d.ln_src.push(src);
  d.ln_n[f] = li + 1;
  d.ev_kind.push(GCOV_EV_LINE);
  d.ev_ref.push(li);
  d.ev_n[f] = d.ev_n[f] + 1;
}

// Append one branch record.
// Params: d - the document; idx - the branch index N; taken - the taken
// count, or -1 for "never executed" / "taken never".
// Returns: nothing.
// Complexity: O(1).
fn _push_branch(d: &mut GcovDoc, idx: Int, taken: Int) {
  if d.sf.len() == 0 {
    return;
  }
  let f = d.sf.len() - 1;
  let li: Int = d.br_n[f];
  d.br_idx.push(idx);
  d.br_taken.push(taken);
  d.br_n[f] = li + 1;
  d.ev_kind.push(GCOV_EV_BRANCH);
  d.ev_ref.push(li);
  d.ev_n[f] = d.ev_n[f] + 1;
}

// Append one function summary record.
// Params: d - the document; name - the function name (non-empty); called -
// the call count; ret - the returned percent (0..100); blocks - the blocks
// executed percent (0..100).
// Returns: nothing.
// Complexity: O(1).
fn _push_function(d: &mut GcovDoc, name: Str, called: Int, ret: Int, blocks: Int) {
  if d.sf.len() == 0 {
    return;
  }
  let f = d.sf.len() - 1;
  let li: Int = d.fn_n[f];
  d.fn_name.push(name);
  d.fn_called.push(called);
  d.fn_ret.push(ret);
  d.fn_blocks.push(blocks);
  d.fn_n[f] = li + 1;
  d.ev_kind.push(GCOV_EV_FUNCTION);
  d.ev_ref.push(li);
  d.ev_n[f] = d.ev_n[f] + 1;
}

// Append one call record.
// Params: d - the document; idx - the call index N; tail - the verbatim text
// after "returned " (non-blank).
// Returns: nothing.
// Complexity: O(1).
fn _push_call(d: &mut GcovDoc, idx: Int, tail: Str) {
  if d.sf.len() == 0 {
    return;
  }
  let f = d.sf.len() - 1;
  let li: Int = d.cl_n[f];
  d.cl_idx.push(idx);
  d.cl_tail.push(tail);
  d.cl_n[f] = li + 1;
  d.ev_kind.push(GCOV_EV_CALL);
  d.ev_ref.push(li);
  d.ev_n[f] = d.ev_n[f] + 1;
}

// Append one unconditional branch record.
// Params: d - the document; idx - the branch index N; taken - the taken
// count, or -1 when the record carried no count.
// Returns: nothing.
// Complexity: O(1).
fn _push_uncond(d: &mut GcovDoc, idx: Int, taken: Int) {
  if d.sf.len() == 0 {
    return;
  }
  let f = d.sf.len() - 1;
  let li: Int = d.un_n[f];
  d.un_idx.push(idx);
  d.un_taken.push(taken);
  d.un_n[f] = li + 1;
  d.ev_kind.push(GCOV_EV_UNCONDITIONAL);
  d.ev_ref.push(li);
  d.ev_n[f] = d.ev_n[f] + 1;
}

// --------------------------------------------------
//  Record parsers (each returns "" on success, else a catalog message)
// --------------------------------------------------

// Parse one line record (or one metadata record when lineno is 0).
// Params: d - the document; line - the whole line; line_no - the 1-based
// line number; off - the byte offset of its first non-SPACE/TAB byte.
// Returns: "" on success, else the catalog message.
// Complexity: O(line length).
fn _parse_line_record(d: &mut GcovDoc, line: Str, line_no: Int, off: Int) -> Str {
  let c1 = _colon_at(line, 0);
  if c1 < 0 {
    return _err_line(line_no, off, "malformed line record");
  }
  let c2 = _colon_at(line, c1 + 1);
  if c2 < 0 {
    return _err_line(line_no, off, "malformed line record");
  }
  let cnt_s = _trim(string.str_slice(line, 0, c1));
  let ln_s = _trim(string.str_slice(line, c1 + 1, c2));
  let src = string.str_slice(line, c2 + 1, line.len());
  if cnt_s.len() == 0 || ln_s.len() == 0 {
    return _err_line(line_no, off, "malformed line record");
  }
  let lineno = _parse_num(ln_s, 0, ln_s.len());
  if lineno < 0 {
    return _err_line(line_no, off, "malformed line record");
  }
  var kind = 0;
  var cnt = 0;
  if _eq(cnt_s, "-") {
    kind = 3;
  } elif _eq(cnt_s, "#####") {
    kind = 1;
  } elif _eq(cnt_s, "=====") {
    kind = 2;
  } else {
    let v = _parse_num(cnt_s, 0, cnt_s.len());
    if v < 0 {
      return _err_line(line_no, off, "malformed line record");
    }
    cnt = v;
  }
  if lineno == 0 {
    if kind != 3 {
      return _err_line(line_no, off, "malformed line record");
    }
    if string.str_starts_with(src, "Source:") {
      let v = string.str_slice(src, 7, src.len());
      if v.len() == 0 {
        return _err_line(line_no, off, "bad metadata value");
      }
      _file_push(d, v);
      return "";
    }
    if string.str_starts_with(src, "Graph:") {
      let v = string.str_slice(src, 6, src.len());
      if v.len() == 0 {
        return _err_line(line_no, off, "bad metadata value");
      }
      if d.sf.len() == 0 {
        return _err_line(line_no, off, "record before Source");
      }
      _set_meta_text(d, v, 1);
      return "";
    }
    if string.str_starts_with(src, "Data:") {
      let v = string.str_slice(src, 5, src.len());
      if v.len() == 0 {
        return _err_line(line_no, off, "bad metadata value");
      }
      if d.sf.len() == 0 {
        return _err_line(line_no, off, "record before Source");
      }
      _set_meta_text(d, v, 0);
      return "";
    }
    if string.str_starts_with(src, "Runs:") {
      let v = string.str_slice(src, 5, src.len());
      let num = _parse_num(v, 0, v.len());
      if num < 0 {
        return _err_line(line_no, off, "bad metadata value");
      }
      if d.sf.len() == 0 {
        return _err_line(line_no, off, "record before Source");
      }
      _set_meta_num(d, num, 1);
      return "";
    }
    if string.str_starts_with(src, "Programs:") {
      let v = string.str_slice(src, 9, src.len());
      let num = _parse_num(v, 0, v.len());
      if num < 0 {
        return _err_line(line_no, off, "bad metadata value");
      }
      if d.sf.len() == 0 {
        return _err_line(line_no, off, "record before Source");
      }
      _set_meta_num(d, num, 0);
      return "";
    }
    return _err_line(line_no, off, "unknown metadata");
  }
  if d.sf.len() == 0 {
    return _err_line(line_no, off, "record before Source");
  }
  _push_line(d, lineno, cnt, src, kind);
  return "";
}

// Parse one "function <name> called <N> returned <P>% blocks executed <Q>%"
// record.
// Params: d - the document; s - the line from its first record byte;
// line_no - the 1-based line number; off - the byte offset of `s`.
// Returns: "" on success, else the catalog message.
// Complexity: O(line length).
fn _parse_function(d: &mut GcovDoc, s: Str, line_no: Int, off: Int) -> Str {
  let n = s.len();
  let c = _find_token(s, " called ", 9);
  if c < 0 {
    return _err_line(line_no, off, "malformed function record");
  }
  let name = string.str_slice(s, 9, c);
  if name.len() == 0 {
    return _err_line(line_no, off, "malformed function record");
  }
  var p = c + 8;
  let de = _digits_end(s, p);
  if de == p {
    return _err_line(line_no, off, "malformed function record");
  }
  let called = _parse_num(s, p, de);
  if called < 0 {
    return _err_line(line_no, off, "malformed function record");
  }
  p = _skip_ws(s, de);
  if !_token_at(s, p, "returned") {
    return _err_line(line_no, off, "malformed function record");
  }
  p = _skip_ws(s, p + 8);
  let de2 = _digits_end(s, p);
  if de2 == p {
    return _err_line(line_no, off, "malformed function record");
  }
  let ret = _parse_num(s, p, de2);
  if ret < 0 || ret > 100 {
    return _err_line(line_no, off, "malformed function record");
  }
  if de2 >= n || string.byte_at(s, de2) != _GC_PCT {
    return _err_line(line_no, off, "malformed function record");
  }
  p = _skip_ws(s, de2 + 1);
  if !_token_at(s, p, "blocks") {
    return _err_line(line_no, off, "malformed function record");
  }
  p = _skip_ws(s, p + 6);
  if !_token_at(s, p, "executed") {
    return _err_line(line_no, off, "malformed function record");
  }
  p = _skip_ws(s, p + 8);
  let de3 = _digits_end(s, p);
  if de3 == p {
    return _err_line(line_no, off, "malformed function record");
  }
  let blocks = _parse_num(s, p, de3);
  if blocks < 0 || blocks > 100 {
    return _err_line(line_no, off, "malformed function record");
  }
  if de3 >= n || string.byte_at(s, de3) != _GC_PCT {
    return _err_line(line_no, off, "malformed function record");
  }
  let tail = string.str_slice(s, de3 + 1, n);
  if !_is_blank(tail) {
    return _err_line(line_no, off, "malformed function record");
  }
  if d.sf.len() == 0 {
    return _err_line(line_no, off, "record before Source");
  }
  _push_function(d, name, called, ret, blocks);
  return "";
}

// Parse one branch record. Accepted forms:
//   "branch <N> taken <M>"      -- count M (>= 0)
//   "branch <N> taken never"    -- never taken
//   "branch <N> never executed" -- never taken
// Params: d - the document; s - the line from its first record byte;
// line_no - the 1-based line number; off - the byte offset of `s`.
// Returns: "" on success, else the catalog message.
// Complexity: O(line length).
fn _parse_branch(d: &mut GcovDoc, s: Str, line_no: Int, off: Int) -> Str {
  let n = s.len();
  var p = _skip_ws(s, 6);
  let de = _digits_end(s, p);
  if de == p {
    return _err_line(line_no, off, "malformed branch record");
  }
  let idx = _parse_num(s, p, de);
  if idx < 0 {
    return _err_line(line_no, off, "malformed branch record");
  }
  p = _skip_ws(s, de);
  var taken = -1;
  if _token_at(s, p, "taken") {
    p = _skip_ws(s, p + 5);
    if _token_at(s, p, "never") {
      p = _skip_ws(s, p + 5);
      if _token_at(s, p, "executed") {
        p = p + 8;
      }
    } else {
      let de2 = _digits_end(s, p);
      if de2 == p {
        return _err_line(line_no, off, "malformed branch record");
      }
      taken = _parse_num(s, p, de2);
      if taken < 0 {
        return _err_line(line_no, off, "malformed branch record");
      }
      p = de2;
    }
  } elif _token_at(s, p, "never") {
    p = _skip_ws(s, p + 5);
    if !_token_at(s, p, "executed") {
      return _err_line(line_no, off, "malformed branch record");
    }
    p = p + 8;
  } else {
    return _err_line(line_no, off, "malformed branch record");
  }
  let tail = string.str_slice(s, p, n);
  if !_is_blank(tail) {
    return _err_line(line_no, off, "malformed branch record");
  }
  if d.sf.len() == 0 {
    return _err_line(line_no, off, "record before Source");
  }
  _push_branch(d, idx, taken);
  return "";
}

// Parse one "call <N> returned <tail>" record. The tail is verbatim text
// (non-blank): gcov writes a return count there, but the value is not
// interpreted.
// Params: d - the document; s - the line from its first record byte;
// line_no - the 1-based line number; off - the byte offset of `s`.
// Returns: "" on success, else the catalog message.
// Complexity: O(line length).
fn _parse_call(d: &mut GcovDoc, s: Str, line_no: Int, off: Int) -> Str {
  let n = s.len();
  var p = _skip_ws(s, 4);
  let de = _digits_end(s, p);
  if de == p {
    return _err_line(line_no, off, "malformed call record");
  }
  let idx = _parse_num(s, p, de);
  if idx < 0 {
    return _err_line(line_no, off, "malformed call record");
  }
  p = _skip_ws(s, de);
  if !_token_at(s, p, "returned") {
    return _err_line(line_no, off, "malformed call record");
  }
  p = _skip_ws(s, p + 8);
  let tail = string.str_slice(s, p, n);
  if _is_blank(tail) {
    return _err_line(line_no, off, "malformed call record");
  }
  if d.sf.len() == 0 {
    return _err_line(line_no, off, "record before Source");
  }
  _push_call(d, idx, tail);
  return "";
}

// Parse one "unconditional <N> taken [<M>]" record. The count is optional;
// when absent the stored value is -1.
// Params: d - the document; s - the line from its first record byte;
// line_no - the 1-based line number; off - the byte offset of `s`.
// Returns: "" on success, else the catalog message.
// Complexity: O(line length).
fn _parse_uncond(d: &mut GcovDoc, s: Str, line_no: Int, off: Int) -> Str {
  let n = s.len();
  var p = _skip_ws(s, 13);
  let de = _digits_end(s, p);
  if de == p {
    return _err_line(line_no, off, "malformed unconditional record");
  }
  let idx = _parse_num(s, p, de);
  if idx < 0 {
    return _err_line(line_no, off, "malformed unconditional record");
  }
  p = _skip_ws(s, de);
  if !_token_at(s, p, "taken") {
    return _err_line(line_no, off, "malformed unconditional record");
  }
  p = _skip_ws(s, p + 5);
  var taken = -1;
  if p < n {
    let de2 = _digits_end(s, p);
    if de2 == p {
      return _err_line(line_no, off, "malformed unconditional record");
    }
    taken = _parse_num(s, p, de2);
    if taken < 0 {
      return _err_line(line_no, off, "malformed unconditional record");
    }
    p = de2;
  }
  let tail = string.str_slice(s, p, n);
  if !_is_blank(tail) {
    return _err_line(line_no, off, "malformed unconditional record");
  }
  if d.sf.len() == 0 {
    return _err_line(line_no, off, "record before Source");
  }
  _push_uncond(d, idx, taken);
  return "";
}

// --------------------------------------------------
//  Construction
// --------------------------------------------------

/// A fresh, empty document: no file sections, no records.
/// Params: none.
/// Returns: an empty GcovDoc.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_doc_new() -> GcovDoc
  ensures: gcov_file_count(result) == 0;
{
  return GcovDoc{
    sf: Vec[Str].new();
    graph: Vec[Str].new();
    graph_has: Vec[Int].new();
    data: Vec[Str].new();
    data_has: Vec[Int].new();
    runs: Vec[Int].new();
    programs: Vec[Int].new();
    ln_off: Vec[Int].new();
    ln_n: Vec[Int].new();
    br_off: Vec[Int].new();
    br_n: Vec[Int].new();
    fn_off: Vec[Int].new();
    fn_n: Vec[Int].new();
    cl_off: Vec[Int].new();
    cl_n: Vec[Int].new();
    un_off: Vec[Int].new();
    un_n: Vec[Int].new();
    ev_off: Vec[Int].new();
    ev_n: Vec[Int].new();
    ln_no: Vec[Int].new();
    ln_cnt: Vec[Int].new();
    ln_src: Vec[Str].new();
    br_idx: Vec[Int].new();
    br_taken: Vec[Int].new();
    fn_name: Vec[Str].new();
    fn_called: Vec[Int].new();
    fn_ret: Vec[Int].new();
    fn_blocks: Vec[Int].new();
    cl_idx: Vec[Int].new();
    cl_tail: Vec[Str].new();
    un_idx: Vec[Int].new();
    un_taken: Vec[Int].new();
    ev_kind: Vec[Int].new();
    ev_ref: Vec[Int].new();
  };
}

// --------------------------------------------------
//  Per-file alignment
// --------------------------------------------------

// Number of index-aligned file sections: the shortest of the per-file
// parallel arrays, so a hand-built doc can never be read out of range.
fn _file_count(d: &GcovDoc) -> Int
  ensures: result >= 0;
  ensures: result <= d.sf.len();
  ensures: result <= d.ln_n.len();
  ensures: result <= d.ev_n.len();
{
  var n = d.sf.len();
  if d.graph.len() < n { n = d.graph.len(); }
  if d.graph_has.len() < n { n = d.graph_has.len(); }
  if d.data.len() < n { n = d.data.len(); }
  if d.data_has.len() < n { n = d.data_has.len(); }
  if d.runs.len() < n { n = d.runs.len(); }
  if d.programs.len() < n { n = d.programs.len(); }
  if d.ln_off.len() < n { n = d.ln_off.len(); }
  if d.ln_n.len() < n { n = d.ln_n.len(); }
  if d.br_off.len() < n { n = d.br_off.len(); }
  if d.br_n.len() < n { n = d.br_n.len(); }
  if d.fn_off.len() < n { n = d.fn_off.len(); }
  if d.fn_n.len() < n { n = d.fn_n.len(); }
  if d.cl_off.len() < n { n = d.cl_off.len(); }
  if d.cl_n.len() < n { n = d.cl_n.len(); }
  if d.un_off.len() < n { n = d.un_off.len(); }
  if d.un_n.len() < n { n = d.un_n.len(); }
  if d.ev_off.len() < n { n = d.ev_off.len(); }
  if d.ev_n.len() < n { n = d.ev_n.len(); }
  return n;
}

// --------------------------------------------------
//  File section accessors
// --------------------------------------------------

/// Number of Source file sections in `d`.
/// Params: d - the document.
/// Returns: the count (0 for an empty document).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_count(d: &GcovDoc) -> Int
  ensures: result == _file_count(d);
{
  return _file_count(d);
}

/// Source path of file section `f` (the Source metadata value).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the path; "" when `f` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_source(d: &GcovDoc, f: Int) -> Str {
  if f < 0 || f >= _file_count(d) {
    return "";
  }
  let v: Str = d.sf[f];
  return v;
}

/// Graph metadata value of file section `f` (the .gcno path).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the value; "" when absent or `f` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_graph(d: &GcovDoc, f: Int) -> Str {
  if f < 0 || f >= _file_count(d) {
    return "";
  }
  let v: Str = d.graph[f];
  return v;
}

/// True when file section `f` carried a Graph metadata record.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when present; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_has_graph(d: &GcovDoc, f: Int) -> Bool {
  if f < 0 || f >= _file_count(d) {
    return false;
  }
  let v: Int = d.graph_has[f];
  return v == 1;
}

/// Data metadata value of file section `f` (the .gcda path).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the value; "" when absent or `f` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_data(d: &GcovDoc, f: Int) -> Str {
  if f < 0 || f >= _file_count(d) {
    return "";
  }
  let v: Str = d.data[f];
  return v;
}

/// True when file section `f` carried a Data metadata record.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when present; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_has_data(d: &GcovDoc, f: Int) -> Bool {
  if f < 0 || f >= _file_count(d) {
    return false;
  }
  let v: Int = d.data_has[f];
  return v == 1;
}

/// Runs metadata value of file section `f` (the number of program runs).
/// A duplicate Runs record overwrites the previous one (last wins).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the value; -1 when absent or `f` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_runs(d: &GcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.runs[f];
  return v;
}

/// Programs metadata value of file section `f` (the number of programs).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the value; -1 when absent or `f` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_programs(d: &GcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.programs[f];
  return v;
}

// --------------------------------------------------
//  Line record accessors
// --------------------------------------------------

/// Number of line records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_line_count(d: &GcovDoc, f: Int) -> Int
  ensures: f < 0 || f >= gcov_file_count(d) => result == 0;
  ensures: result >= 0;
  ensures: result <= d.ln_no.len();
  ensures: result <= d.ln_src.len();
{
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.ln_off[f];
  let n: Int = d.ln_n[f];
  let total = _min3(d.ln_no.len(), d.ln_cnt.len(), d.ln_src.len());
  return _span(off, n, total);
}

/// Source line number of line record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the line number; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_line_number(d: &GcovDoc, f: Int, i: Int) -> Int
  ensures: i < 0 || i >= gcov_file_line_count(d, f) => result == -1;
  ensures: result != -1 => i >= 0 && i < gcov_file_line_count(d, f);
{
  let n = gcov_file_line_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.ln_off[f];
  let v: Int = d.ln_no[off + i];
  return v;
}

/// Printed count value of line record `i` in file section `f`: the execution
/// count for a digits record (>= 0, and note that 0 is executable but not
/// covered), or GCOV_NOT_EXECUTED / GCOV_NO_CODE / GCOV_NO_LINE.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the stored value; -1 when `i` is out of range (indistinguishable
/// from a "#####" record, so bounds-check with gcov_file_line_count first).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_line_count_value(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_line_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.ln_off[f];
  let v: Int = d.ln_cnt[off + i];
  return v;
}

/// Source text of line record `i` in file section `f` (verbatim, may be
/// empty; may contain any non-terminator bytes).
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the text; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_line_source(d: &GcovDoc, f: Int, i: Int) -> Str {
  let n = gcov_file_line_count(d, f);
  if i < 0 || i >= n {
    return "";
  }
  let off: Int = d.ln_off[f];
  let v: Str = d.ln_src[off + i];
  return v;
}

/// True when line record `i` in file section `f` is executable: a digits
/// count (including 0) or a "#####" record. "=====" and "-" are not.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: true for an executable line; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_line_executable(d: &GcovDoc, f: Int, i: Int) -> Bool {
  let n = gcov_file_line_count(d, f);
  if i < 0 || i >= n {
    return false;
  }
  let off: Int = d.ln_off[f];
  let v: Int = d.ln_cnt[off + i];
  if v == GCOV_NO_CODE || v == GCOV_NO_LINE {
    return false;
  }
  return true;
}

/// True when line record `i` in file section `f` was covered: its count is
/// at least 1. Both 0 and "#####" are uncovered.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: true for a covered line; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_line_covered(d: &GcovDoc, f: Int, i: Int) -> Bool
  ensures: i < 0 || i >= gcov_file_line_count(d, f) => result == false;
  ensures: result == true => i >= 0 && i < gcov_file_line_count(d, f);
{
  let n = gcov_file_line_count(d, f);
  if i < 0 || i >= n {
    return false;
  }
  let off: Int = d.ln_off[f];
  let v: Int = d.ln_cnt[off + i];
  return v >= 1;
}

// --------------------------------------------------
//  Per-file line summary
// --------------------------------------------------

/// Executable line records in file section `f` (digits or "#####").
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_executable_lines(d: &GcovDoc, f: Int) -> Int {
  let n = gcov_file_line_count(d, f);
  if n <= 0 {
    return 0;
  }
  let off: Int = d.ln_off[f];
  var c = 0;
  var i = 0;
  while i < n {
    let v: Int = d.ln_cnt[off + i];
    if v != GCOV_NO_CODE && v != GCOV_NO_LINE {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Covered line records in file section `f` (count >= 1).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_covered_lines(d: &GcovDoc, f: Int) -> Int {
  let n = gcov_file_line_count(d, f);
  if n <= 0 {
    return 0;
  }
  let off: Int = d.ln_off[f];
  var c = 0;
  var i = 0;
  while i < n {
    let v: Int = d.ln_cnt[off + i];
    if v >= 1 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Unexecuted executable line records in file section `f`:
/// max(0, executable - covered).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_unexecuted_lines(d: &GcovDoc, f: Int) -> Int
  ensures: gcov_file_covered_lines(d, f) >= gcov_file_executable_lines(d, f) => result == 0;
  ensures: gcov_file_covered_lines(d, f) < gcov_file_executable_lines(d, f) => result == gcov_file_executable_lines(d, f) - gcov_file_covered_lines(d, f);
{
  let e = gcov_file_executable_lines(d, f);
  let c = gcov_file_covered_lines(d, f);
  if c >= e {
    return 0;
  }
  return e - c;
}

/// Line coverage of file section `f` as an integer percent, floored:
/// floor(covered * 100 / executable). 0 when there are no executable lines.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the percent (0..100).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_line_percent(d: &GcovDoc, f: Int) -> Int
  ensures: result == _pct_floor(gcov_file_covered_lines(d, f), gcov_file_executable_lines(d, f));
  ensures: result >= 0 && result <= 100;
{
  return _pct_floor(gcov_file_covered_lines(d, f), gcov_file_executable_lines(d, f));
}

/// Line coverage of file section `f` in integer basis points (hundredths of
/// a percent), floored: floor(covered * 10000 / executable). 0 when there
/// are no executable lines.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the basis points (0..10000).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_line_basis_points(d: &GcovDoc, f: Int) -> Int {
  return _pct_bp(gcov_file_covered_lines(d, f), gcov_file_executable_lines(d, f));
}

// --------------------------------------------------
//  Branch record accessors and summary
// --------------------------------------------------

/// Number of branch records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_branch_count(d: &GcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.br_off[f];
  let n: Int = d.br_n[f];
  let total = _min2(d.br_idx.len(), d.br_taken.len());
  return _span(off, n, total);
}

/// Branch index N of branch record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the index; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_branch_index(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_branch_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.br_off[f];
  let v: Int = d.br_idx[off + i];
  return v;
}

/// Taken count of branch record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the count (>= 0); -1 for a "never executed" / "taken never"
/// record and for an out-of-range `i`.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_branch_taken_count(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_branch_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.br_off[f];
  let v: Int = d.br_taken[off + i];
  return v;
}

/// True when branch record `i` in file section `f` was taken at least once.
/// Both "taken 0" and "never executed" are not covered.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: true for a taken branch; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_branch_covered(d: &GcovDoc, f: Int, i: Int) -> Bool {
  return gcov_branch_taken_count(d, f, i) >= 1;
}

/// Branch records taken at least once in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_branches_taken(d: &GcovDoc, f: Int) -> Int {
  let n = gcov_file_branch_count(d, f);
  if n <= 0 {
    return 0;
  }
  let off: Int = d.br_off[f];
  var c = 0;
  var i = 0;
  while i < n {
    let v: Int = d.br_taken[off + i];
    if v >= 1 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Branch coverage of file section `f` as an integer percent, floored:
/// floor(taken * 100 / total). 0 when there are no branch records.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the percent (0..100).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_branch_percent(d: &GcovDoc, f: Int) -> Int {
  return _pct_floor(gcov_file_branches_taken(d, f), gcov_file_branch_count(d, f));
}

/// Branch coverage of file section `f` in integer basis points, floored.
/// 0 when there are no branch records.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the basis points (0..10000).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_branch_basis_points(d: &GcovDoc, f: Int) -> Int {
  return _pct_bp(gcov_file_branches_taken(d, f), gcov_file_branch_count(d, f));
}

// --------------------------------------------------
//  Function record accessors and summary
// --------------------------------------------------

/// Number of function summary records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_function_count(d: &GcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.fn_off[f];
  let n: Int = d.fn_n[f];
  let total = _min4(d.fn_name.len(), d.fn_called.len(), d.fn_ret.len(), d.fn_blocks.len());
  return _span(off, n, total);
}

/// Name of function record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the name; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_function_name(d: &GcovDoc, f: Int, i: Int) -> Str {
  let n = gcov_file_function_count(d, f);
  if i < 0 || i >= n {
    return "";
  }
  let off: Int = d.fn_off[f];
  let v: Str = d.fn_name[off + i];
  return v;
}

/// Call count of function record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the count; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_function_called_count(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_function_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.fn_off[f];
  let v: Int = d.fn_called[off + i];
  return v;
}

/// Returned percent of function record `i` in file section `f` (0..100).
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the percent; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_function_returned_percent(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_function_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.fn_off[f];
  let v: Int = d.fn_ret[off + i];
  return v;
}

/// Blocks executed percent of function record `i` in file section `f`
/// (0..100).
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the percent; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_function_blocks_percent(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_function_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.fn_off[f];
  let v: Int = d.fn_blocks[off + i];
  return v;
}

/// True when function record `i` in file section `f` was called at least
/// once.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: true for a called function; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_function_covered(d: &GcovDoc, f: Int, i: Int) -> Bool {
  return gcov_function_called_count(d, f, i) >= 1;
}

/// Function records called at least once in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_functions_called(d: &GcovDoc, f: Int) -> Int {
  let n = gcov_file_function_count(d, f);
  if n <= 0 {
    return 0;
  }
  let off: Int = d.fn_off[f];
  var c = 0;
  var i = 0;
  while i < n {
    let v: Int = d.fn_called[off + i];
    if v >= 1 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Function coverage of file section `f` as an integer percent, floored:
/// floor(called * 100 / total). 0 when there are no function records.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the percent (0..100).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_function_percent(d: &GcovDoc, f: Int) -> Int {
  return _pct_floor(gcov_file_functions_called(d, f), gcov_file_function_count(d, f));
}

/// Function coverage of file section `f` in integer basis points, floored.
/// 0 when there are no function records.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the basis points (0..10000).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_file_function_basis_points(d: &GcovDoc, f: Int) -> Int {
  return _pct_bp(gcov_file_functions_called(d, f), gcov_file_function_count(d, f));
}

// --------------------------------------------------
//  Call and unconditional record accessors
// --------------------------------------------------

/// Number of call records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_call_count(d: &GcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.cl_off[f];
  let n: Int = d.cl_n[f];
  let total = _min2(d.cl_idx.len(), d.cl_tail.len());
  return _span(off, n, total);
}

/// Call index N of call record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the index; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_call_index(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_call_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.cl_off[f];
  let v: Int = d.cl_idx[off + i];
  return v;
}

/// Verbatim tail of call record `i` in file section `f` (the text after
/// "returned ").
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the tail; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_call_tail(d: &GcovDoc, f: Int, i: Int) -> Str {
  let n = gcov_file_call_count(d, f);
  if i < 0 || i >= n {
    return "";
  }
  let off: Int = d.cl_off[f];
  let v: Str = d.cl_tail[off + i];
  return v;
}

/// Number of unconditional branch records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_unconditional_count(d: &GcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.un_off[f];
  let n: Int = d.un_n[f];
  let total = _min2(d.un_idx.len(), d.un_taken.len());
  return _span(off, n, total);
}

/// Branch index N of unconditional record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the index; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_unconditional_index(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_unconditional_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.un_off[f];
  let v: Int = d.un_idx[off + i];
  return v;
}

/// Taken count of unconditional record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the count (>= 0); -1 when the record carried no count, or `i`
/// is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_unconditional_taken(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_unconditional_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.un_off[f];
  let v: Int = d.un_taken[off + i];
  return v;
}

// --------------------------------------------------
//  Event accessors (per-file record order)
// --------------------------------------------------

/// Number of events (records of any kind) in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the event count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_file_event_count(d: &GcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.ev_off[f];
  let n: Int = d.ev_n[f];
  let total = _min2(d.ev_kind.len(), d.ev_ref.len());
  return _span(off, n, total);
}

/// Kind of event `i` in file section `f`: one of the GCOV_EV_* constants.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based event index within `f`.
/// Returns: the kind; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_event_kind(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_event_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.ev_off[f];
  let v: Int = d.ev_kind[off + i];
  return v;
}

/// Local record index of event `i` in file section `f`: for
/// GCOV_EV_LINE an index into gcov_file_line_* accessors, for
/// GCOV_EV_FUNCTION into gcov_function_*, for GCOV_EV_BRANCH into
/// gcov_branch_*, for GCOV_EV_CALL into gcov_call_* and for
/// GCOV_EV_UNCONDITIONAL into gcov_unconditional_*.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based event index within `f`.
/// Returns: the record index; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn gcov_event_ref(d: &GcovDoc, f: Int, i: Int) -> Int {
  let n = gcov_file_event_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.ev_off[f];
  let v: Int = d.ev_ref[off + i];
  return v;
}

// --------------------------------------------------
//  Overall (all-file) summary
// --------------------------------------------------

/// Executable line records across all file sections.
/// Params: d - the document.
/// Returns: the total count.
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_line_executable(d: &GcovDoc) -> Int {
  let nf = _file_count(d);
  var s = 0;
  var f = 0;
  while f < nf {
    s = s + gcov_file_executable_lines(d, f);
    f = f + 1;
  }
  return s;
}

/// Covered line records across all file sections.
/// Params: d - the document.
/// Returns: the total count.
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_line_covered(d: &GcovDoc) -> Int {
  let nf = _file_count(d);
  var s = 0;
  var f = 0;
  while f < nf {
    s = s + gcov_file_covered_lines(d, f);
    f = f + 1;
  }
  return s;
}

/// Pooled line coverage as an integer percent, floored:
/// floor(total covered * 100 / total executable). 0 when there are no
/// executable lines. Pooling is exact, not an average of per-file percents.
/// Params: d - the document.
/// Returns: the percent (0..100).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_line_percent(d: &GcovDoc) -> Int {
  return _pct_floor(gcov_total_line_covered(d), gcov_total_line_executable(d));
}

/// Pooled line coverage in integer basis points, floored. 0 when there are
/// no executable lines.
/// Params: d - the document.
/// Returns: the basis points (0..10000).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_line_basis_points(d: &GcovDoc) -> Int {
  return _pct_bp(gcov_total_line_covered(d), gcov_total_line_executable(d));
}

/// Branch records across all file sections.
/// Params: d - the document.
/// Returns: the total count.
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_branch_count(d: &GcovDoc) -> Int {
  let nf = _file_count(d);
  var s = 0;
  var f = 0;
  while f < nf {
    s = s + gcov_file_branch_count(d, f);
    f = f + 1;
  }
  return s;
}

/// Branch records taken at least once across all file sections.
/// Params: d - the document.
/// Returns: the total count.
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_branches_taken(d: &GcovDoc) -> Int {
  let nf = _file_count(d);
  var s = 0;
  var f = 0;
  while f < nf {
    s = s + gcov_file_branches_taken(d, f);
    f = f + 1;
  }
  return s;
}

/// Pooled branch coverage as an integer percent, floored. 0 when there are
/// no branch records.
/// Params: d - the document.
/// Returns: the percent (0..100).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_branch_percent(d: &GcovDoc) -> Int {
  return _pct_floor(gcov_total_branches_taken(d), gcov_total_branch_count(d));
}

/// Pooled branch coverage in integer basis points, floored. 0 when there
/// are no branch records.
/// Params: d - the document.
/// Returns: the basis points (0..10000).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_branch_basis_points(d: &GcovDoc) -> Int {
  return _pct_bp(gcov_total_branches_taken(d), gcov_total_branch_count(d));
}

/// Function summary records across all file sections.
/// Params: d - the document.
/// Returns: the total count.
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_function_count(d: &GcovDoc) -> Int {
  let nf = _file_count(d);
  var s = 0;
  var f = 0;
  while f < nf {
    s = s + gcov_file_function_count(d, f);
    f = f + 1;
  }
  return s;
}

/// Function summary records called at least once across all file sections.
/// Params: d - the document.
/// Returns: the total count.
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_functions_called(d: &GcovDoc) -> Int {
  let nf = _file_count(d);
  var s = 0;
  var f = 0;
  while f < nf {
    s = s + gcov_file_functions_called(d, f);
    f = f + 1;
  }
  return s;
}

/// Pooled function coverage as an integer percent, floored. 0 when there
/// are no function records.
/// Params: d - the document.
/// Returns: the percent (0..100).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_function_percent(d: &GcovDoc) -> Int {
  return _pct_floor(gcov_total_functions_called(d), gcov_total_function_count(d));
}

/// Pooled function coverage in integer basis points, floored. 0 when there
/// are no function records.
/// Params: d - the document.
/// Returns: the basis points (0..10000).
/// Error case: none.
/// Complexity: O(records).
pub fn gcov_total_function_basis_points(d: &GcovDoc) -> Int {
  return _pct_bp(gcov_total_functions_called(d), gcov_total_function_count(d));
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

// Append the event record kind `k`, local index `r` of file `f` to `out`.
// The accessors clamp every value, so a misaligned hand-built doc emits
// less instead of reading out of range.
fn _emit_event(out: Str, d: &GcovDoc, f: Int, k: Int, r: Int) -> Str {
  if k == GCOV_EV_LINE {
    let cnt: Int = gcov_file_line_count_value(d, f, r);
    var cs = "";
    if cnt == GCOV_NOT_EXECUTED {
      cs = "#####";
    } elif cnt == GCOV_NO_CODE {
      cs = "=====";
    } elif cnt == GCOV_NO_LINE {
      cs = "-";
    } else {
      cs = int_to_string(cnt);
    }
    let ln: Int = gcov_file_line_number(d, f, r);
    let src: Str = gcov_file_line_source(d, f, r);
    return out + cs + ":" + int_to_string(ln) + ":" + src + "\n";
  }
  if k == GCOV_EV_FUNCTION {
    let nm: Str = gcov_function_name(d, f, r);
    let called: Int = gcov_function_called_count(d, f, r);
    let ret: Int = gcov_function_returned_percent(d, f, r);
    let blocks: Int = gcov_function_blocks_percent(d, f, r);
    return out + "function " + nm + " called " + int_to_string(called) + " returned " + int_to_string(ret) + "% blocks executed " + int_to_string(blocks) + "%\n";
  }
  if k == GCOV_EV_BRANCH {
    let idx: Int = gcov_branch_index(d, f, r);
    let tk: Int = gcov_branch_taken_count(d, f, r);
    if tk >= 0 {
      return out + "branch " + int_to_string(idx) + " taken " + int_to_string(tk) + "\n";
    }
    return out + "branch " + int_to_string(idx) + " never executed\n";
  }
  if k == GCOV_EV_CALL {
    let idx: Int = gcov_call_index(d, f, r);
    let tail: Str = gcov_call_tail(d, f, r);
    return out + "call " + int_to_string(idx) + " returned " + tail + "\n";
  }
  if k == GCOV_EV_UNCONDITIONAL {
    let idx: Int = gcov_unconditional_index(d, f, r);
    let tk: Int = gcov_unconditional_taken(d, f, r);
    if tk >= 0 {
      return out + "unconditional " + int_to_string(idx) + " taken " + int_to_string(tk) + "\n";
    }
    return out + "unconditional " + int_to_string(idx) + " taken\n";
  }
  return out;
}

/// Canonical emission of a whole document.
/// Params: d - the document to serialize.
/// Returns: the canonical stream, every emitted line terminated by LF.
/// File sections are written in stored order. Each one starts with its
/// metadata records ("Source" always; "Graph", "Data", "Runs" and "Programs"
/// only when the input carried them) and then replays its records in the
/// original stream order (the event store). Line records are written as
/// "<count>:<lineno>:<source>" with the count canonicalized to digits /
/// "#####" / "=====" / "-"; branch records to "taken <M>" or
/// "never executed"; function records to the full summary form; call tails
/// and line source text are verbatim. An empty document emits "" (no bytes).
/// Re-parsing emitted text yields an equivalent document and emitting again
/// is byte-identical (canonicalization may change bytes once: padding,
/// "taken never" and "never executed" all normalize, two-field metadata
/// spacing is dropped).
/// Error case: none. Mismatched parallel arrays are clamped to their
/// shortest length; events referring to missing records are skipped.
/// Complexity: O(total output length).
pub fn gcov_emit(d: &GcovDoc) -> Str
  ensures: gcov_file_count(d) == 0 => result.len() == 0;
{
  var out = "";
  let nf = _file_count(d);
  var f = 0;
  while f < nf {
    let src: Str = d.sf[f];
    out = out + "-:0:Source:" + src + "\n";
    let gh: Int = d.graph_has[f];
    if gh == 1 {
      let g: Str = d.graph[f];
      out = out + "-:0:Graph:" + g + "\n";
    }
    let dh: Int = d.data_has[f];
    if dh == 1 {
      let dv: Str = d.data[f];
      out = out + "-:0:Data:" + dv + "\n";
    }
    let rv: Int = d.runs[f];
    if rv >= 0 {
      out = out + "-:0:Runs:" + int_to_string(rv) + "\n";
    }
    let pv: Int = d.programs[f];
    if pv >= 0 {
      out = out + "-:0:Programs:" + int_to_string(pv) + "\n";
    }
    let ec = gcov_file_event_count(d, f);
    let eo: Int = d.ev_off[f];
    var i = 0;
    while i < ec {
      let k: Int = d.ev_kind[eo + i];
      let r: Int = d.ev_ref[eo + i];
      out = _emit_event(out, d, f, k, r);
      i = i + 1;
    }
    f = f + 1;
  }
  return out;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one .gcov text stream.
/// Params: text - the whole text, LF or CRLF terminated (a single trailing
/// CR per line is dropped). Empty and SPACE/TAB-only lines are ignored;
/// every other line must be a record of the documented subset (SPEC.md).
/// Returns: Ok(GcovDoc) for a stream in the documented subset. Rules: a
/// Source metadata record opens a file section; Graph/Data/Runs/Programs
/// update the open section (last wins); line, branch, function, call and
/// unconditional records append to the open section in stream order.
/// Error case: Err("coverage: <reason> at line L byte O") for the first
/// malformed line; the catalog is in SPEC.md. Byte O is the 0-based offset
/// of the line's first non-SPACE/TAB byte.
/// Complexity: O(input length).
pub fn gcov_parse(text: Str) -> Result[GcovDoc, Str]
  ensures: text.len() == 0 => result is Ok;
{
  var d = gcov_doc_new();
  let len = text.len();
  var line_start = 0;
  var line_no = 1;
  var i = 0;
  while i <= len {
    if i == len || string.byte_at(text, i) == _GC_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _GC_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      if !_is_blank(line) {
        let p = _skip_ws(line, 0);
        let off = line_start + p;
        let rest = string.str_slice(line, p, line.len());
        var err = "";
        if string.str_starts_with(rest, "function ") {
          err = _parse_function(&mut d, rest, line_no, off);
        } elif string.str_starts_with(rest, "branch") {
          err = _parse_branch(&mut d, rest, line_no, off);
        } elif string.str_starts_with(rest, "call") {
          err = _parse_call(&mut d, rest, line_no, off);
        } elif string.str_starts_with(rest, "unconditional") {
          err = _parse_uncond(&mut d, rest, line_no, off);
        } else {
          let b = string.byte_at(line, p);
          if b == _GC_DASH || b == _GC_HASH || b == _GC_EQ || _is_digit(b) {
            err = _parse_line_record(&mut d, line, line_no, off);
          } else {
            err = _err_line(line_no, off, "unknown record");
          }
        }
        if compare.str_compare(err, "") != 0 {
          return _err_doc(err);
        }
      }
      line_start = i + 1;
      line_no = line_no + 1;
    }
    i = i + 1;
  }
  return _ok_doc(d);
}
