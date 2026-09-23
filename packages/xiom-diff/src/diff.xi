// XIOM -- xiom.diff: line diff with LCS edit scripts and unified output
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Module xiom.diff computes line-oriented diffs over Vec[Str] line slices.
// The longest-common-subsequence table is a single flat Vec[Int] of
// (n+1)*(m+1) cells (no Vec[Vec[Int]], no Vec[StructType]); diff_lines and
// diff_unified backtrack the same table to build the edit script. Str values
// read from Vec elements are compared only through str_compare (BUG 17:
// `==` on such values lowers to a pointer comparison).

module xiom.diff

use xiom.string;
use xiom.string.compare;
use xiom.convert.int;

// --- internal helpers -------------------------------------------------------

// Line equality. Uses str_compare, never `==` (BUG 17).
fn _lines_eq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

// Flat (n+1) x (m+1) LCS-length table over a and b, row-major with row width
// m+1: dp[i*(m+1)+j] is the LCS length of a[0..i) and b[0..j).
fn _lcs_table(a: &Vec[Str], b: &Vec[Str]) -> Vec[Int] {
  let n = a.len();
  let m = b.len();
  let width = m + 1;
  var dp = Vec[Int].new();
  let total = (n + 1) * width;
  var k = 0;
  while k < total {
    dp.push(0);
    k = k + 1;
  }
  var i = 1;
  while i <= n {
    var j = 1;
    while j <= m {
      if _lines_eq(a[i - 1], b[j - 1]) {
        dp[i * width + j] = dp[(i - 1) * width + (j - 1)] + 1;
      } elif dp[(i - 1) * width + j] >= dp[i * width + (j - 1)] {
        dp[i * width + j] = dp[(i - 1) * width + j];
      } else {
        dp[i * width + j] = dp[i * width + (j - 1)];
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return dp;
}

// Fresh copy of v with the element order reversed.
fn _reverse_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = v.len();
  while i > 0 {
    i = i - 1;
    out.push(v[i]);
  }
  return out;
}

// One backtrack decision at (i, j): 0 = keep, 1 = delete, 2 = insert.
// Flat ifs with early returns: comparing two flat-table index reads inside a
// nested `elif` mis-lowers in v0.61.3 (the Int operands become pointers and a
// byte load dereferences them -- an access violation), so the comparison
// lives in this helper instead of the backtrack loop.
fn _choose_kind(a: &Vec[Str], b: &Vec[Str], dp: &Vec[Int], width: Int, i: Int, j: Int) -> Int {
  if i > 0 && j > 0 {
    if _lines_eq(a[i - 1], b[j - 1]) {
      return 0;
    }
  }
  if j == 0 {
    return 1;
  }
  if i == 0 {
    return 2;
  }
  let left: Int = dp[i * width + (j - 1)];
  let up: Int = dp[(i - 1) * width + j];
  if left >= up {
    return 2;
  }
  return 1;
}

// Forward-ordered edit-script op kinds over a and b:
// 0 = keep (equal line), 1 = delete from a, 2 = insert from b.
// Built by backtracking the LCS table from (n, m); ties prefer the insert
// branch, so a replaced line comes out as a deletion followed by an
// insertion. No `&&` / `||` guard relies on short-circuiting: every index is
// excluded by a nested if before it is used.
fn _op_kinds(a: &Vec[Str], b: &Vec[Str]) -> Vec[Int] {
  let n = a.len();
  let m = b.len();
  var rev = Vec[Int].new();
  let dp = _lcs_table(a, b);
  let width = m + 1;
  var i = n;
  var j = m;
  while i > 0 || j > 0 {
    let kind = _choose_kind(a, b, &dp, width, i, j);
    rev.push(kind);
    if kind == 0 {
      i = i - 1;
      j = j - 1;
    } elif kind == 1 {
      i = i - 1;
    } else {
      j = j - 1;
    }
  }
  return _reverse_ints(&rev);
}

// Split s into lines on "\n": a trailing newline does not create a final
// empty line and the empty string is zero lines.
fn _split_lines(s: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = s.len();
  if n == 0 {
    return out;
  }
  var start = 0;
  var i = 0;
  while i < n {
    if (byte_at(s, i) as Int) == 10 {
      out.push(str_slice(s, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < n {
    out.push(str_slice(s, start, n));
  }
  return out;
}

// --- public API -------------------------------------------------------------

/// Element-wise line equality of `a` and `b`.
/// Two vectors are equal when they have the same length and every line pair
/// compares equal under str_compare.
/// Params: a, b - the line slices to compare.
/// Returns: true when the slices are equal, false otherwise.
/// Errors: none.
/// Complexity: O(min(n, m)) line comparisons.
pub fn diff_equal(a: &Vec[Str], b: &Vec[Str]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if !_lines_eq(a[i], b[i]) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Length of the longest common subsequence of `a` and `b`.
/// Params: a, b - the line slices to compare.
/// Returns: the LCS length (0 when either slice is empty).
/// Errors: none.
/// Complexity: O(n*m) time, O(n*m) memory (flat table).
pub fn diff_lcs_len(a: &Vec[Str], b: &Vec[Str]) -> Int {
  let n = a.len();
  let m = b.len();
  if n == 0 || m == 0 {
    return 0;
  }
  let dp = _lcs_table(a, b);
  let lcs: Int = dp[n * (m + 1) + m];
  return lcs;
}

/// Full edit script between `a` and `b`.
/// Every returned line is prefixed with two characters: "  " for a kept
/// line, "- " for a line deleted from `a`, "+ " for a line inserted from
/// `b`. The script is a shortest edit script for the LCS backtrack; a
/// replaced line is emitted as its "- " line followed by its "+ " line.
/// Params: a, b - the line slices to compare.
/// Returns: a fresh Vec[Str] with the prefixed script lines; empty when both
/// slices are empty.
/// Errors: none.
/// Complexity: O(n*m) time and memory.
pub fn diff_lines(a: &Vec[Str], b: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  let kinds = _op_kinds(a, b);
  var old_line = 0;
  var new_line = 0;
  var k = 0;
  while k < kinds.len() {
    let kind: Int = kinds[k];
    if kind == 0 {
      out.push("  " + a[old_line]);
      old_line = old_line + 1;
      new_line = new_line + 1;
    } elif kind == 1 {
      out.push("- " + a[old_line]);
      old_line = old_line + 1;
    } else {
      out.push("+ " + b[new_line]);
      new_line = new_line + 1;
    }
    k = k + 1;
  }
  return out;
}

/// Number of lines inserted to turn `a` into `b`.
/// Params: a, b - the line slices to compare.
/// Returns: b.len() - diff_lcs_len(a, b), always >= 0.
/// Errors: none.
/// Complexity: O(n*m) (delegates to diff_lcs_len).
pub fn diff_insertions(a: &Vec[Str], b: &Vec[Str]) -> Int {
  return b.len() - diff_lcs_len(a, b);
}

/// Number of lines deleted from `a` to turn it into `b`.
/// Params: a, b - the line slices to compare.
/// Returns: a.len() - diff_lcs_len(a, b), always >= 0.
/// Errors: none.
/// Complexity: O(n*m) (delegates to diff_lcs_len).
pub fn diff_deletions(a: &Vec[Str], b: &Vec[Str]) -> Int {
  return a.len() - diff_lcs_len(a, b);
}

/// Unified-style diff hunks between `a` and `b`.
/// Each hunk starts with "@@ -oldStart,oldCount +newStart,newCount @@" and is
/// followed by prefixed lines: " " for context, "-" for deletions, "+" for
/// insertions. Every emitted line ends with "\n". `context` is the number of
/// unchanged lines kept around each change (negative values clamp to 0);
/// changes separated by at most 2*context unchanged lines share one hunk.
/// Starts are 1-based line numbers; when a side's count is 0 the start is
/// the number of that side's lines before the insertion point (0 at the
/// beginning), matching GNU unified diff.
/// Params: a, b - the line slices to compare; context - unchanged lines
/// around each change.
/// Returns: the hunk text, or "" when a and b are equal.
/// Errors: none.
/// Complexity: O(n*m) time and memory; string building is O(payload^2).
pub fn diff_unified(a: &Vec[Str], b: &Vec[Str], context: Int) -> Str {
  var ctx = context;
  if ctx < 0 {
    ctx = 0;
  }
  let kinds = _op_kinds(a, b);
  let total = kinds.len();
  var run_start = Vec[Int].new();
  var run_end = Vec[Int].new();
  var k = 0;
  while k < total {
    let kind: Int = kinds[k];
    if kind == 0 {
      k = k + 1;
    } else {
      var e = k;
      while e + 1 < total {
        let next_kind: Int = kinds[e + 1];
        if next_kind == 0 {
          break;
        }
        e = e + 1;
      }
      run_start.push(k);
      run_end.push(e);
      k = e + 1;
    }
  }
  if run_start.len() == 0 {
    return "";
  }
  var old_before = Vec[Int].new();
  var new_before = Vec[Int].new();
  var old_line = 0;
  var new_line = 0;
  k = 0;
  while k < total {
    old_before.push(old_line);
    new_before.push(new_line);
    let kind: Int = kinds[k];
    if kind != 2 {
      old_line = old_line + 1;
    }
    if kind != 1 {
      new_line = new_line + 1;
    }
    k = k + 1;
  }
  var out = "";
  var h = 0;
  while h < run_start.len() {
    let first_change: Int = run_start[h];
    let last_change: Int = run_end[h];
    var hs = first_change - ctx;
    if hs < 0 {
      hs = 0;
    }
    var he = last_change + ctx;
    if he > total - 1 {
      he = total - 1;
    }
    var hh = h + 1;
    var merge_more = true;
    while merge_more {
      merge_more = false;
      if hh < run_start.len() {
        let next_start: Int = run_start[hh];
        let last_end: Int = run_end[hh - 1];
        if next_start - last_end - 1 <= 2 * ctx {
          let next_end: Int = run_end[hh];
          he = next_end + ctx;
          if he > total - 1 {
            he = total - 1;
          }
          hh = hh + 1;
          merge_more = true;
        }
      }
    }
    let old_lo: Int = old_before[hs];
    let new_lo: Int = new_before[hs];
    var old_hi: Int = old_before[he];
    let end_kind: Int = kinds[he];
    if end_kind != 2 {
      old_hi = old_hi + 1;
    }
    var new_hi: Int = new_before[he];
    if end_kind != 1 {
      new_hi = new_hi + 1;
    }
    let old_count: Int = old_hi - old_lo;
    let new_count: Int = new_hi - new_lo;
    var old_start = old_lo + 1;
    if old_count == 0 {
      old_start = old_lo;
    }
    var new_start = new_lo + 1;
    if new_count == 0 {
      new_start = new_lo;
    }
    out = out + "@@ -" + int_to_string(old_start) + "," + int_to_string(old_count);
    out = out + " +" + int_to_string(new_start) + "," + int_to_string(new_count) + " @@\n";
    var p = hs;
    while p <= he {
      let pk: Int = kinds[p];
      if pk == 0 {
        let ai: Int = old_before[p];
        out = out + " " + a[ai] + "\n";
      } elif pk == 1 {
        let di: Int = old_before[p];
        out = out + "-" + a[di] + "\n";
      } else {
        let bi: Int = new_before[p];
        out = out + "+" + b[bi] + "\n";
      }
      p = p + 1;
    }
    h = hh;
  }
  return out;
}

/// Split two texts into lines and diff them.
/// Text is split on "\n" byte 10; a final newline terminates the last line
/// without creating an extra empty one, and the empty text is zero lines.
/// The line diff is exactly diff_lines over the two line vectors.
/// Params: a, b - the texts to compare.
/// Returns: the prefixed edit script (see diff_lines).
/// Errors: none.
/// Complexity: O(lines(a) * lines(b)) time and memory.
pub fn diff_text(a: Str, b: Str) -> Vec[Str] {
  let al = _split_lines(a);
  let bl = _split_lines(b);
  return diff_lines(&al, &bl);
}
