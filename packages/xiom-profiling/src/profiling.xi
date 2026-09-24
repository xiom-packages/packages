// XIOM -- xiom.profiling: folded-stack sampling profile analysis
// Port task: replace the xiom.profiling placeholder with a real, tested,
// pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A folded stack line is "<stack> <count>": the stack is a ';'-separated
// frame list with the leaf (innermost frame) LAST, exactly as emitted by
// `perf script | stackcollapse-perf.pl`; the count is a run of ASCII digits
// preceded by one or more ASCII spaces. Lines are separated by LF and a
// single trailing CR per line is stripped, so CRLF input parses; blank lines
// (length zero after the CR strip) are skipped. Anything else is malformed
// and aborts the whole parse with Err("profiling: line N: ...") naming the
// 1-based physical line number (blank lines included in the count).
//
// The sample data model is two index-aligned vectors rather than a vector of
// records: XIOM v0.61.3 miscompiles Vec[StructType]. ProfData is a struct
// holding two Vecs; the aggregation functions never nest it in a Vec.
//
// XIOM v0.61.3 constraints honored: free functions only (no methods, no
// lambdas), no Vec[StructType], no Vec[fn], every match exhaustive, no `mut`
// patterns, Str equality through compare.str_compare with typed Vec reads,
// byte_at comparisons through UInt8 constants, and Ok/Err constructed only
// inside the _prof_ok/_prof_err leaf helpers.

module xiom.profiling

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _PROF_SPACE: UInt8 = 32u8;
const _PROF_ZERO: UInt8 = 48u8;
const _PROF_NINE: UInt8 = 57u8;
const _PROF_CR: UInt8 = 13u8;
const _PROF_LF: UInt8 = 10u8;
const _PROF_SEMI: UInt8 = 59u8;
const _PROF_INT_MAX_DIV10: Int = 922337203685477580;
const _PROF_INT_MAX_LAST: Int = 7;

/// Folded stack table: `stacks[i]` is a ';'-separated frame list (leaf last)
/// and `counts[i]` is its sample count; the vectors are index-aligned.
/// Fields are public so callers can read them, but build a ProfData through
/// prof_parse (or the aggregation functions) so the invariant holds.
pub type ProfData = {
  stacks: Vec[Str];
  counts: Vec[Int];
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _prof_ok(v: ProfData) -> Result[ProfData, Str] { return Ok(v); }
fn _prof_err(m: Str) -> Result[ProfData, Str] { return Err(m); }

// An empty, well-formed table (zero entries; the invariant holds vacuously).
fn _prof_empty() -> ProfData {
  return ProfData{ stacks: Vec[Str].new(); counts: Vec[Int].new(); };
}

fn _is_digit(b: UInt8) -> Bool {
  return b >= _PROF_ZERO && b <= _PROF_NINE;
}

// Index of the first element equal to `s` (str_compare), or -1. Takes &mut
// per the E001 advisory (audit/test precedent): a caller never mixes a
// `&local` read call with a later mutating call on the same local.
fn _prof_index_of(stacks: &mut Vec[Str], s: Str) -> Int {
  var i = 0;
  while i < stacks.len() {
    let cur: Str = stacks[i];
    if compare.str_compare(cur, s) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Leaf frame of a folded stack: the text after the last ';', or the whole
// stack when it has none. An empty stack yields "".
fn _prof_leaf_of(stack: Str) -> Str {
  var i = stack.len() - 1;
  while i >= 0 {
    if string.byte_at(stack, i) == _PROF_SEMI {
      return string.str_slice(stack, i + 1, stack.len());
    }
    i = i - 1;
  }
  return stack;
}

// Last `depth` (>= 1) frames of `stack`: drop everything up to the `depth`-th
// ';' counted from the end. The stack is returned unchanged when it has at
// most `depth` frames (frames are counted as ';'-separated segments, so a
// stack without ';' is one frame).
fn _prof_tail_frames(stack: Str, depth: Int) -> Str {
  let n = stack.len();
  var semis = 0;
  var i = n - 1;
  while i >= 0 {
    if string.byte_at(stack, i) == _PROF_SEMI {
      semis = semis + 1;
      if semis == depth {
        return string.str_slice(stack, i + 1, n);
      }
    }
    i = i - 1;
  }
  return stack;
}

// Parse one already CR-stripped line into a one-entry ProfData.
// Grammar: STACK 1*SP 1*DIGIT, STACK non-empty (see SPEC.md).
// Errors (always "profiling: line N: ..."):
//   missing count      -- the line does not end in an ASCII digit run
//   missing separator  -- digits are not preceded by an ASCII space
//   empty stack        -- only spaces precede the count
//   count out of range -- the digit run does not fit a signed 64-bit Int
fn _prof_parse_line(line: Str, line_no: Int) -> Result[ProfData, Str] {
  let n = line.len();
  var digits_start = n;
  while digits_start > 0 {
    if !_is_digit(string.byte_at(line, digits_start - 1)) { break; }
    digits_start = digits_start - 1;
  }
  if digits_start == n {
    return _prof_err("profiling: line " + convert.int_to_string(line_no) + ": missing count");
  }
  var stack_end = digits_start;
  while stack_end > 0 {
    if string.byte_at(line, stack_end - 1) != _PROF_SPACE { break; }
    stack_end = stack_end - 1;
  }
  if stack_end == digits_start {
    return _prof_err("profiling: line " + convert.int_to_string(line_no) + ": missing separator");
  }
  if stack_end == 0 {
    return _prof_err("profiling: line " + convert.int_to_string(line_no) + ": empty stack");
  }
  var count = 0;
  var i = digits_start;
  while i < n {
    let d = (string.byte_at(line, i) as Int) - 48;
    if count > _PROF_INT_MAX_DIV10 {
      return _prof_err("profiling: line " + convert.int_to_string(line_no) + ": count out of range");
    }
    if count == _PROF_INT_MAX_DIV10 && d > _PROF_INT_MAX_LAST {
      return _prof_err("profiling: line " + convert.int_to_string(line_no) + ": count out of range");
    }
    count = count * 10 + d;
    i = i + 1;
  }
  var stack_vec = Vec[Str].new();
  stack_vec.push(string.str_slice(line, 0, stack_end));
  var count_vec = Vec[Int].new();
  count_vec.push(count);
  return _prof_ok(ProfData{ stacks: stack_vec; counts: count_vec; });
}

/// Parse folded-stack text into a ProfData.
/// Grammar: one entry per non-blank line, "<stack> <count>", where <stack> is
/// the non-empty text before the final run of one or more ASCII spaces and
/// <count> is the trailing decimal run of one or more ASCII digits
/// (non-negative, must fit a signed 64-bit Int). Lines end at LF; one
/// trailing CR per line is stripped (CRLF input parses); a line that is empty
/// after the CR strip is skipped and still advances the line number. Bytes
/// are otherwise preserved verbatim: no trimming, no frame validation.
/// Params: text - the whole folded file (empty allowed).
/// Returns: Ok(table) with entries in first-seen order; Err("profiling:
/// line N: ...") on the first malformed line (N counts every physical line,
/// blank lines included).
/// Complexity: O(text length).
pub fn prof_parse(text: Str) -> Result[ProfData, Str] {
  let len = text.len();
  var stacks = Vec[Str].new();
  var counts = Vec[Int].new();
  var line_no = 1;
  var start = 0;
  while start < len {
    var end = start;
    while end < len {
      if string.byte_at(text, end) == _PROF_LF { break; }
      end = end + 1;
    }
    var line_end = end;
    if line_end > start && string.byte_at(text, line_end - 1) == _PROF_CR {
      line_end = line_end - 1;
    }
    if line_end > start {
      let line = string.str_slice(text, start, line_end);
      let parsed = _prof_parse_line(line, line_no);
      match parsed {
        Ok(p) => {
          let s: Str = p.stacks[0];
          let c: Int = p.counts[0];
          stacks.push(s);
          counts.push(c);
        },
        Err(e) => { return _prof_err(e); },
      }
    }
    start = end + 1;
    line_no = line_no + 1;
  }
  return _prof_ok(ProfData{ stacks: stacks; counts: counts; });
}

/// Total sample count: the sum of every entry's count. An empty table is 0.
/// Params: data - the table (not merged; duplicates are each summed).
/// Returns: the total. Complexity: O(entries).
pub fn prof_total(data: &ProfData) -> Int {
  var total = 0;
  var i = 0;
  while i < data.counts.len() {
    let c: Int = data.counts[i];
    total = total + c;
    i = i + 1;
  }
  return total;
}

/// Number of folded stack entries (lines), not frames. Complexity: O(1).
pub fn prof_stack_count(data: &ProfData) -> Int {
  return data.stacks.len();
}

/// Count stored for exactly `stack`, or 0 when the stack is absent.
/// Comparison is byte-exact (str_compare). On unmerged duplicate stacks the
/// first match's count is returned; call prof_merge_same to combine first.
/// Params: data - the table; stack - the whole ';'-joined stack text.
/// Returns: the count, or 0 when absent. Complexity: O(entries).
pub fn prof_count_for(data: &ProfData, stack: Str) -> Int {
  var i = 0;
  while i < data.stacks.len() {
    let s: Str = data.stacks[i];
    if compare.str_compare(s, stack) == 0 {
      let c: Int = data.counts[i];
      return c;
    }
    i = i + 1;
  }
  return 0;
}

/// Sum duplicate stacks into one entry each, keeping first-seen order.
/// Entries whose stack text is byte-equal are merged into the entry at the
/// position where the stack was first seen; counts add. Complexities:
/// O(entries * distinct stacks).
/// Params: data - the table to compact.
/// Returns: a new table with distinct stacks (empty for empty input).
pub fn prof_merge_same(data: &ProfData) -> ProfData {
  var out_stacks = Vec[Str].new();
  var out_counts = Vec[Int].new();
  var i = 0;
  while i < data.stacks.len() {
    let s: Str = data.stacks[i];
    let c: Int = data.counts[i];
    let at = _prof_index_of(&mut out_stacks, s);
    if at < 0 {
      out_stacks.push(s);
      out_counts.push(c);
    } else {
      let prev: Int = out_counts[at];
      out_counts[at] = prev + c;
    }
    i = i + 1;
  }
  return ProfData{ stacks: out_stacks; counts: out_counts; };
}

/// Distinct leaf (innermost, last) frame names in first-seen order.
/// The leaf of a stack is the text after its last ';'; single-frame stacks
/// yield themselves. Comparison is byte-exact. Empty for empty input.
/// Params: data - the table.
/// Returns: one leaf name per distinct leaf, in first-seen order.
/// Complexity: O(entries * distinct leaves).
pub fn prof_leaf(data: &ProfData) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < data.stacks.len() {
    let s: Str = data.stacks[i];
    let leaf = _prof_leaf_of(s);
    if _prof_index_of(&mut out, leaf) < 0 {
      out.push(leaf);
    }
    i = i + 1;
  }
  return out;
}

/// Leaf totals: one entry per distinct leaf (count summed), first-seen
/// order. The returned table's `stacks` hold leaf NAMES, not full stacks.
/// Empty for empty input. Params: data - the table.
/// Returns: a new table keyed by leaf. Complexity:
/// O(entries * distinct leaves).
pub fn prof_leaf_totals(data: &ProfData) -> ProfData {
  var out_stacks = Vec[Str].new();
  var out_counts = Vec[Int].new();
  var i = 0;
  while i < data.stacks.len() {
    let s: Str = data.stacks[i];
    let c: Int = data.counts[i];
    let leaf = _prof_leaf_of(s);
    let at = _prof_index_of(&mut out_stacks, leaf);
    if at < 0 {
      out_stacks.push(leaf);
      out_counts.push(c);
    } else {
      let prev: Int = out_counts[at];
      out_counts[at] = prev + c;
    }
    i = i + 1;
  }
  return ProfData{ stacks: out_stacks; counts: out_counts; };
}

/// Format the `k` heaviest stacks as "<stack> <count>" lines (folded format
/// again): count descending, ties in first-seen order. `k` is clamped:
/// k <= 0 yields no lines, k >= prof_stack_count yields every entry. The
/// input is used as-is (not merged); call prof_merge_same first when
/// duplicate stacks must be combined before ranking.
/// Params: data - the table; k - how many lines to emit.
/// Returns: up to min(k, size) lines; empty for empty input or k <= 0.
/// Complexity: O(entries^2) worst case (stable insertion sort).
pub fn prof_top(data: &ProfData, k: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = data.stacks.len();
  var limit = k;
  if limit > n { limit = n; }
  if limit <= 0 { return out; }
  var work_stacks = Vec[Str].new();
  var work_counts = Vec[Int].new();
  var i = 0;
  while i < n {
    let s: Str = data.stacks[i];
    let c: Int = data.counts[i];
    work_stacks.push(s);
    work_counts.push(c);
    i = i + 1;
  }
  var pos = 0;
  // Stable insertion sort by count descending: an entry moves left only past
  // strictly smaller counts, so equal counts keep their first-seen order.
  while pos < n {
    let cur_s: Str = work_stacks[pos];
    let cur_c: Int = work_counts[pos];
    var j = pos;
    while j > 0 {
      let prev_c: Int = work_counts[j - 1];
      if prev_c >= cur_c { break; }
      let prev_s: Str = work_stacks[j - 1];
      work_stacks[j] = prev_s;
      work_counts[j] = prev_c;
      j = j - 1;
    }
    work_stacks[j] = cur_s;
    work_counts[j] = cur_c;
    pos = pos + 1;
  }
  var emit = 0;
  while emit < limit {
    let ss: Str = work_stacks[emit];
    let cc: Int = work_counts[emit];
    out.push(ss + " " + convert.int_to_string(cc));
    emit = emit + 1;
  }
  return out;
}

/// Truncate every stack to its last `depth` frames, dropping leading frames
/// (collapse-by-depth, the opposite end of a flame graph's root). depth < 1
/// yields an empty table; depth >= a stack's frame count keeps that stack
/// unchanged. Duplicates are preserved as separate entries (not merged).
/// Params: data - the table; depth - frames to keep from the leaf end.
/// Returns: a new table with the same counts. Complexity: O(total length).
pub fn prof_collapse_depth(data: &ProfData, depth: Int) -> ProfData {
  var out_stacks = Vec[Str].new();
  var out_counts = Vec[Int].new();
  if depth < 1 {
    return ProfData{ stacks: out_stacks; counts: out_counts; };
  }
  var i = 0;
  while i < data.stacks.len() {
    let s: Str = data.stacks[i];
    let c: Int = data.counts[i];
    out_stacks.push(_prof_tail_frames(s, depth));
    out_counts.push(c);
    i = i + 1;
  }
  return ProfData{ stacks: out_stacks; counts: out_counts; };
}
