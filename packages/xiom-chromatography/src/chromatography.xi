// XIOM -- xiom.chromatography: pure deterministic chromatography data model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md carries the formulas, rounding rules, codec grammar and the
// full error catalog):
//   * fixed-point integers only, scale 1e-4 (CHROM_FP_SCALE = 10000): every
//     retention time, area, height, width, baseline level and QC quantity is
//     an Int in these units. There is no Float64 and no Vec[Float64];
//   * the data model is flat and mirrored: a peak table is four parallel
//     Vec[Int] (times, areas, heights, widths) with equal length; baseline
//     segment records are four parallel Vec[Int] (starts, ends, levels0,
//     levels1). There is no Vec[StructType] and no struct type at all;
//   * Kovats retention indices are computed against a caller-supplied alkane
//     anchor table (carbon numbers and retention times, two parallel
//     Vec[Int]), linearly interpolated between the bracketing anchors and
//     returned in 1e-4 index units;
//   * QC flags are a bitmask derived from signal-to-noise, peak asymmetry
//     (tailing/fronting) and resolution;
//   * area normalization to 100 percent is exact: values are cumulative-floor
//     percentages in 1e-4 percent units and always sum to CHROM_AREA_100;
//   * the canonical text codec is line-based: an exact header line followed by
//     one `peak` record per row (grammar in SPEC.md section 8).
//
// v0.62.2 notes that shaped this module:
//   * free functions only: no methods, lambdas, fn tables or struct types;
//   * Ok/Err are constructed only in the tiny leaf helpers `_ok_*` / `_err_*`
//     below;
//   * every Str comparison goes through xiom.string.compare.str_compare; a Str
//     is never compared with `==` (BUG 17);
//   * every byte read is widened with `(string.byte_at(s, pos) as Int) & 0xFF`;
//   * `Vec[Str].push` is never used: the parser scans line ranges in place and
//     the emitter concatenates Str values;
//   * every Vec element read is bound to a typed local before use;
//   * every written Vec parameter is an explicit `&mut`;
//   * division truncates toward zero and the remainder keeps the dividend
//     sign (verified: -7 / 2 = -3). Baseline interpolation is the only place
//     a negative quotient can occur and is documented as truncating toward
//     zero;
//   * products are guarded by documented input bounds (CHROM_FP_MAX for one
//     quantity, CHROM_TOTAL_MAX for a summed area, CHROM_CARBON_MAX for
//     alkane carbon numbers), so no Int multiplication overflows.

module xiom.chromatography

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Fixed-point scale: every stored quantity is an Int in units of 1e-4.
pub const CHROM_FP_SCALE: Int = 10000;

/// Largest accepted magnitude of one fixed-point quantity (1e9, i.e.
/// 100000.0000 in real units); all inputs outside 0..CHROM_FP_MAX are
/// rejected.
pub const CHROM_FP_MAX: Int = 1000000000;

/// Largest accepted total area of a peak table (1e12 fixed-point units); it
/// bounds the normalization product `cumulative * CHROM_AREA_100`.
pub const CHROM_TOTAL_MAX: Int = 1000000000000;

/// 100 percent in normalized-area units: normalization returns values in
/// 1e-4 percent units, so every successful normalization sums to exactly
/// this value.
pub const CHROM_AREA_100: Int = 1000000;

/// Largest accepted alkane carbon number in a Kovats anchor table.
pub const CHROM_CARBON_MAX: Int = 1000;

/// Asymmetry strictly above this value (1.1000) flags tailing.
pub const CHROM_ASYM_TAIL_MIN: Int = 11000;

/// Asymmetry strictly below this value (0.9000) flags fronting.
pub const CHROM_ASYM_FRONT_MAX: Int = 9000;

/// Signal-to-noise strictly below this value (10.0000) flags a low-S/N peak.
pub const CHROM_SN_MIN: Int = 100000;

/// Resolution at or above this value (1.5000) is baseline separated.
pub const CHROM_RES_BASELINE: Int = 15000;

/// Resolution strictly below this value (1.0000) flags an unresolved pair.
pub const CHROM_RES_CRITICAL: Int = 10000;

/// QC flag value 0: no flag raised.
pub const CHROM_QC_OK: Int = 0;

/// QC bit: asymmetry above CHROM_ASYM_TAIL_MIN (tailing).
pub const CHROM_QC_TAILING: Int = 1;

/// QC bit: asymmetry below CHROM_ASYM_FRONT_MAX (fronting).
pub const CHROM_QC_FRONTING: Int = 2;

/// QC bit: signal-to-noise below CHROM_SN_MIN.
pub const CHROM_QC_LOW_SN: Int = 4;

/// QC bit: resolution below CHROM_RES_CRITICAL.
pub const CHROM_QC_UNRESOLVED: Int = 8;

/// Exact first non-blank line of the canonical peak-table text codec.
pub const CHROM_TABLE_HEADER: Str = "#chromatography peaks v1";

// --------------------------------------------------
//  Result constructors (leaf helpers; see the header)
// --------------------------------------------------

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_vec_int(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_vec_int(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// Byte `pos` of `s` widened to 0..255 (0 when out of bounds).
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// True when v lies in 0..CHROM_FP_MAX.
fn _in_fp_range(v: Int) -> Bool {
  return v >= 0 && v <= CHROM_FP_MAX;
}

// First position at or after `from` in [from, to) that is not a space or tab.
fn _skip_ws_range(s: Str, from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    let b: Int = _byte(s, i);
    if b == 32 || b == 9 {
      i = i + 1;
    } else {
      break;
    }
  }
  return i;
}

// First position at or after `from` in [from, to) that is a space or tab, or
// `to` when the token runs to the end of the range.
fn _token_end(s: Str, from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    let b: Int = _byte(s, i);
    if b == 32 || b == 9 {
      break;
    }
    i = i + 1;
  }
  return i;
}

// True when s[from, to) equals `want` (Str equality via str_compare, BUG 17
// discipline).
fn _range_equals(s: Str, from: Int, to: Int, want: Str) -> Bool {
  return compare.str_compare(string.str_slice(s, from, to), want) == 0;
}

// Parse one canonical fixed-point token:
//   token := ["-"] digit+ ["." digit{1,4}]
// Exact decimal conversion, no float: value = int_part*10000 + frac_padded.
// Errors (callers wrap them with line/field context):
//   "empty value" | "bad value" | "more than 4 decimal places" |
//   "value out of range 0..1000000000"
fn _parse_fp(tok: Str) -> Result[Int, Str] {
  let n = tok.len();
  if n == 0 {
    return _err_int("empty value");
  }
  var i = 0;
  var neg = false;
  let b0: Int = _byte(tok, 0);
  if b0 == 45 {
    neg = true;
    i = 1;
  }
  var ip = 0;
  var idig = 0;
  while i < n {
    let b: Int = _byte(tok, i);
    if b < 48 || b > 57 {
      break;
    }
    ip = ip * 10 + (b - 48);
    if ip > 1000000 {
      return _err_int("value out of range 0..1000000000");
    }
    idig = idig + 1;
    i = i + 1;
  }
  if idig == 0 {
    return _err_int("bad value");
  }
  var frac = 0;
  var fdig = 0;
  if i < n {
    let bdot: Int = _byte(tok, i);
    if bdot != 46 {
      return _err_int("bad value");
    }
    i = i + 1;
    while i < n {
      let b2: Int = _byte(tok, i);
      if b2 < 48 || b2 > 57 {
        return _err_int("bad value");
      }
      if fdig == 4 {
        return _err_int("more than 4 decimal places");
      }
      frac = frac * 10 + (b2 - 48);
      fdig = fdig + 1;
      i = i + 1;
    }
    if fdig == 0 {
      return _err_int("bad value");
    }
    while fdig < 4 {
      frac = frac * 10;
      fdig = fdig + 1;
    }
  }
  var v = ip * CHROM_FP_SCALE + frac;
  if v > CHROM_FP_MAX {
    return _err_int("value out of range 0..1000000000");
  }
  if neg {
    v = 0 - v;
  }
  return _ok_int(v);
}

// Canonical fixed-point text for a non-negative value: int part, dot, exactly
// four fraction digits (zero padded); e.g. 12345 -> "1.2345", 5 -> "0.0005".
fn _emit_fp(v: Int) -> Str {
  let ip = v / CHROM_FP_SCALE;
  let fr = v % CHROM_FP_SCALE;
  return convert.int_to_string(ip) + "." + _pad4(fr);
}

// Decimal digits of n (0..9999) zero padded to exactly four characters.
fn _pad4(n: Int) -> Str {
  if n < 10 {
    return "000" + convert.int_to_string(n);
  }
  if n < 100 {
    return "00" + convert.int_to_string(n);
  }
  if n < 1000 {
    return "0" + convert.int_to_string(n);
  }
  return convert.int_to_string(n);
}

// Parse one non-blank line range [from, to) as a `peak` record in canonical
// order time area height width. Returns the four parsed fixed-point values.
// Errors carry the 1-based line number:
//   "chrom.codec: line L: expected 'peak' record"
//   "chrom.codec: line L: expected 4 fixed-point fields, got K"
//   "chrom.codec: line L: trailing text after 4 fields"
//   "chrom.codec: line L field F: <value error>"
fn _parse_record_range(text: Str, from: Int, to: Int, line_no: Int) -> Result[Vec[Int], Str] {
  let head = "chrom.codec: line " + convert.int_to_string(line_no);
  var pos = _skip_ws_range(text, from, to);
  let e1 = _token_end(text, pos, to);
  if !_range_equals(text, pos, e1, "peak") {
    return _err_vec_int(head + ": expected 'peak' record");
  }
  pos = e1;
  var vals = Vec[Int].new();
  var f = 1;
  while f <= 4 {
    pos = _skip_ws_range(text, pos, to);
    let e = _token_end(text, pos, to);
    if e == pos {
      return _err_vec_int(head + ": expected 4 fixed-point fields, got " +
                          convert.int_to_string(f - 1));
    }
    let tok = string.str_slice(text, pos, e);
    let pr = _parse_fp(tok);
    if !pr.is_ok {
      return _err_vec_int(head + " field " + convert.int_to_string(f) + ": " + pr.error);
    }
    let v: Int = pr.value;
    vals.push(v);
    pos = e;
    f = f + 1;
  }
  pos = _skip_ws_range(text, pos, to);
  if pos < to {
    return _err_vec_int(head + ": trailing text after 4 fields");
  }
  return _ok_vec_int(vals);
}

// Kovats value between two anchors with t0 <= tx <= t1:
//   base = c0*100*SCALE
//   RI   = base + 100*SCALE*(c1-c0)*(tx-t0) / (t1-t0)
// The division truncates toward zero. Inputs are pre-validated by
// chrom_kovats_index, so the numerator is at most 1e18.
fn _kovats_between(c0: Int, c1: Int, t0: Int, t1: Int, tx: Int) -> Int {
  let base = c0 * 100 * CHROM_FP_SCALE;
  if tx <= t0 {
    return base;
  }
  let top = c1 * 100 * CHROM_FP_SCALE;
  if tx >= t1 {
    return top;
  }
  let num = 100 * CHROM_FP_SCALE * (c1 - c0) * (tx - t0);
  return base + num / (t1 - t0);
}

// --------------------------------------------------
//  Peak-table validation and area math
// --------------------------------------------------

/// Validate a mirrored peak table: times/areas/heights/widths must have the
/// same length; every value must lie in 0..CHROM_FP_MAX; area, height and
/// width must be strictly positive; times must be strictly increasing.
/// Checks run per peak in table order and, within a peak, in the order time,
/// area, height, width, positivity, order; the first violation is returned.
///
/// Errors: "chrom: table length mismatch times=N <field>=M" for the first
/// unequal length, then the per-peak messages
/// "chrom: peak I <field> out of range 0..1000000000",
/// "chrom: peak I <field> must be positive",
/// "chrom: peak I time not increasing after peak P".
/// An empty table (all lengths 0) is valid. Complexity: O(n).
pub fn chrom_peak_validate(times: &Vec[Int], areas: &Vec[Int],
                           heights: &Vec[Int], widths: &Vec[Int]) -> Result[Unit, Str] {
  let n = times.len();
  if areas.len() != n {
    return _err_unit("chrom: table length mismatch times=" + convert.int_to_string(n) +
                     " areas=" + convert.int_to_string(areas.len()));
  }
  if heights.len() != n {
    return _err_unit("chrom: table length mismatch times=" + convert.int_to_string(n) +
                     " heights=" + convert.int_to_string(heights.len()));
  }
  if widths.len() != n {
    return _err_unit("chrom: table length mismatch times=" + convert.int_to_string(n) +
                     " widths=" + convert.int_to_string(widths.len()));
  }
  var i = 0;
  while i < n {
    let t: Int = times[i];
    let a: Int = areas[i];
    let h: Int = heights[i];
    let w: Int = widths[i];
    if !_in_fp_range(t) {
      return _err_unit("chrom: peak " + convert.int_to_string(i) +
                       " time out of range 0..1000000000");
    }
    if !_in_fp_range(a) {
      return _err_unit("chrom: peak " + convert.int_to_string(i) +
                       " area out of range 0..1000000000");
    }
    if !_in_fp_range(h) {
      return _err_unit("chrom: peak " + convert.int_to_string(i) +
                       " height out of range 0..1000000000");
    }
    if !_in_fp_range(w) {
      return _err_unit("chrom: peak " + convert.int_to_string(i) +
                       " width out of range 0..1000000000");
    }
    if a <= 0 {
      return _err_unit("chrom: peak " + convert.int_to_string(i) +
                       " area must be positive");
    }
    if h <= 0 {
      return _err_unit("chrom: peak " + convert.int_to_string(i) +
                       " height must be positive");
    }
    if w <= 0 {
      return _err_unit("chrom: peak " + convert.int_to_string(i) +
                       " width must be positive");
    }
    if i > 0 {
      let prev: Int = times[i - 1];
      if t <= prev {
        return _err_unit("chrom: peak " + convert.int_to_string(i) +
                         " time not increasing after peak " + convert.int_to_string(i - 1));
      }
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Total area of a non-empty area vector; the sum must not exceed
/// CHROM_TOTAL_MAX.
///
/// Errors: "chrom: no peaks" for an empty vector, "chrom: negative area at
/// index I" and "chrom: total area exceeds 1000000000000".
/// Complexity: O(n).
pub fn chrom_peak_total_area(areas: &Vec[Int]) -> Result[Int, Str] {
  let n = areas.len();
  if n == 0 {
    return _err_int("chrom: no peaks");
  }
  var total = 0;
  var i = 0;
  while i < n {
    let a: Int = areas[i];
    if a < 0 {
      return _err_int("chrom: negative area at index " + convert.int_to_string(i));
    }
    total = total + a;
    if total > CHROM_TOTAL_MAX {
      return _err_int("chrom: total area exceeds 1000000000000");
    }
    i = i + 1;
  }
  return _ok_int(total);
}

/// Normalize peak areas to 100 percent in fixed-point: the result has the
/// same length as `areas`, each value is in 1e-4 percent units and the values
/// sum to exactly CHROM_AREA_100 (100.0000 percent) for any positive total.
///
/// Method (cumulative floor, deterministic and exact): with cum_i the running
/// sum of areas and total the full sum,
///   norm_i = floor(cum_i * 1000000 / total) - floor(cum_{i-1} * 1000000 / total)
/// so earlier peaks keep the truncated share and the last nonzero peak
/// absorbs the residual; the sum telescopes to 1000000. A zero area
/// normalizes to 0. Because total <= CHROM_TOTAL_MAX, the product
/// cum * 1000000 is at most 1e18 and does not overflow.
///
/// Errors: "chrom: no peaks to normalize" for an empty vector,
/// "chrom: negative area at index I", "chrom: total area exceeds
/// 1000000000000" and "chrom: total area is zero".
/// Complexity: O(n).
pub fn chrom_peak_normalize_areas(areas: &Vec[Int]) -> Result[Vec[Int], Str] {
  let n = areas.len();
  if n == 0 {
    return _err_vec_int("chrom: no peaks to normalize");
  }
  var total = 0;
  var i = 0;
  while i < n {
    let a: Int = areas[i];
    if a < 0 {
      return _err_vec_int("chrom: negative area at index " + convert.int_to_string(i));
    }
    total = total + a;
    if total > CHROM_TOTAL_MAX {
      return _err_vec_int("chrom: total area exceeds 1000000000000");
    }
    i = i + 1;
  }
  if total == 0 {
    return _err_vec_int("chrom: total area is zero");
  }
  var out = Vec[Int].new();
  var cum = 0;
  var prev_scaled = 0;
  i = 0;
  while i < n {
    let a2: Int = areas[i];
    cum = cum + a2;
    let scaled = (cum * CHROM_AREA_100) / total;
    out.push(scaled - prev_scaled);
    prev_scaled = scaled;
    i = i + 1;
  }
  return _ok_vec_int(out);
}

// --------------------------------------------------
//  Resolution
// --------------------------------------------------

/// Resolution between two peaks at half-height, in 1e-4 units:
///   R = 1.18 * (t2 - t1) / (w1 + w2)
/// (the classic half-height formula; w1/w2 are widths at half height).
/// In fixed point: R_fp = 11800 * (t2 - t1) / (w1 + w2), one division that
/// truncates toward zero. 11800 * 1e9 = 1.18e13 does not overflow.
///
/// All four inputs are validated in order t1, t2, w1, w2 with ranges
/// 0..CHROM_FP_MAX (widths 1..CHROM_FP_MAX); t2 must be strictly greater
/// than t1. Errors: "chrom.resolution: t1 out of range 0..1000000000",
/// "chrom.resolution: t2 out of range 0..1000000000",
/// "chrom.resolution: w1 out of range 1..1000000000",
/// "chrom.resolution: w2 out of range 1..1000000000",
/// "chrom.resolution: t2 must be greater than t1".
/// Complexity: O(1).
pub fn chrom_peak_resolution(t1: Int, w1: Int, t2: Int, w2: Int) -> Result[Int, Str] {
  if !_in_fp_range(t1) {
    return _err_int("chrom.resolution: t1 out of range 0..1000000000");
  }
  if !_in_fp_range(t2) {
    return _err_int("chrom.resolution: t2 out of range 0..1000000000");
  }
  if w1 <= 0 || w1 > CHROM_FP_MAX {
    return _err_int("chrom.resolution: w1 out of range 1..1000000000");
  }
  if w2 <= 0 || w2 > CHROM_FP_MAX {
    return _err_int("chrom.resolution: w2 out of range 1..1000000000");
  }
  if t2 <= t1 {
    return _err_int("chrom.resolution: t2 must be greater than t1");
  }
  return _ok_int((11800 * (t2 - t1)) / (w1 + w2));
}

/// Resolution of the adjacent peak pair (pair_index, pair_index+1) of a
/// mirrored table. The two vectors must have equal length and at least two
/// entries; the pair index must satisfy 0 <= pair_index <= len-2. Delegates
/// the arithmetic and its errors to chrom_peak_resolution.
///
/// Errors: "chrom.resolution: table length mismatch times=N widths=M",
/// "chrom.resolution: table needs at least 2 peaks",
/// "chrom.resolution: adjacent index I out of range 0..K".
/// Complexity: O(1).
pub fn chrom_table_adjacent_resolution(times: &Vec[Int], widths: &Vec[Int],
                                       pair_index: Int) -> Result[Int, Str] {
  if times.len() != widths.len() {
    return _err_int("chrom.resolution: table length mismatch times=" +
                    convert.int_to_string(times.len()) + " widths=" +
                    convert.int_to_string(widths.len()));
  }
  let n = times.len();
  if n < 2 {
    return _err_int("chrom.resolution: table needs at least 2 peaks");
  }
  if pair_index < 0 || pair_index + 1 >= n {
    return _err_int("chrom.resolution: adjacent index " + convert.int_to_string(pair_index) +
                    " out of range 0.." + convert.int_to_string(n - 2));
  }
  let t1: Int = times[pair_index];
  let w1: Int = widths[pair_index];
  let t2: Int = times[pair_index + 1];
  let w2: Int = widths[pair_index + 1];
  return chrom_peak_resolution(t1, w1, t2, w2);
}

// --------------------------------------------------
//  Kovats retention index
// --------------------------------------------------

/// Kovats retention index of a retention time `tx` against a caller-supplied
/// alkane anchor table given as two parallel vectors: `anchor_carbon[i]` is
/// the carbon number of anchor `i` and `anchor_time[i]` its retention time in
/// fixed point. Both must have the same length >= 2 and be strictly
/// increasing; carbon numbers must lie in 0..CHROM_CARBON_MAX and times in
/// 0..CHROM_FP_MAX, and tx must lie inside [anchor_time[0],
/// anchor_time[last]].
///
/// Between the bracketing anchors (c0,t0) and (c1,t1):
///   RI = 100*c0 + 100*(c1-c0)*(tx-t0)/(t1-t0)
/// returned in 1e-4 index units; the division truncates toward zero and an
/// exact anchor hit returns that anchor's index exactly. With consecutive
/// anchors (c1 = c0+1) this is the standard Kovats formula. The largest
/// numerator is 100*SCALE*CHROM_CARBON_MAX*CHROM_FP_MAX = 1e18, so no
/// overflow occurs.
///
/// Errors, in check order: "chrom.kovats: anchor table length mismatch
/// carbon=N time=M", "chrom.kovats: anchors need at least 2 points",
/// "chrom.kovats: retention time out of range 0..1000000000", per anchor
/// "chrom.kovats: anchor I carbon out of range 0..1000" / "anchor I time out
/// of range 0..1000000000" / "anchor carbon not increasing at I" / "anchor
/// time not increasing at I" (carbon checks before time at each index), then
/// "chrom.kovats: retention time T outside anchor range A..B".
/// Complexity: O(n) for n anchors.
pub fn chrom_kovats_index(anchor_carbon: &Vec[Int], anchor_time: &Vec[Int],
                          tx: Int) -> Result[Int, Str] {
  let nc = anchor_carbon.len();
  let nt = anchor_time.len();
  if nc != nt {
    return _err_int("chrom.kovats: anchor table length mismatch carbon=" +
                    convert.int_to_string(nc) + " time=" + convert.int_to_string(nt));
  }
  if nc < 2 {
    return _err_int("chrom.kovats: anchors need at least 2 points");
  }
  if !_in_fp_range(tx) {
    return _err_int("chrom.kovats: retention time out of range 0..1000000000");
  }
  var i = 0;
  while i < nc {
    let c: Int = anchor_carbon[i];
    let t: Int = anchor_time[i];
    if c < 0 || c > CHROM_CARBON_MAX {
      return _err_int("chrom.kovats: anchor " + convert.int_to_string(i) +
                      " carbon out of range 0..1000");
    }
    if !_in_fp_range(t) {
      return _err_int("chrom.kovats: anchor " + convert.int_to_string(i) +
                      " time out of range 0..1000000000");
    }
    if i > 0 {
      let cp: Int = anchor_carbon[i - 1];
      let tp: Int = anchor_time[i - 1];
      if c <= cp {
        return _err_int("chrom.kovats: anchor carbon not increasing at " +
                        convert.int_to_string(i));
      }
      if t <= tp {
        return _err_int("chrom.kovats: anchor time not increasing at " +
                        convert.int_to_string(i));
      }
    }
    i = i + 1;
  }
  let t0: Int = anchor_time[0];
  let tlast: Int = anchor_time[nc - 1];
  if tx < t0 || tx > tlast {
    return _err_int("chrom.kovats: retention time " + convert.int_to_string(tx) +
                    " outside anchor range " + convert.int_to_string(t0) + ".." +
                    convert.int_to_string(tlast));
  }
  var k = 0;
  while k + 1 < nc {
    let ta: Int = anchor_time[k];
    let tb: Int = anchor_time[k + 1];
    if tx >= ta && tx <= tb {
      let ca: Int = anchor_carbon[k];
      let cb: Int = anchor_carbon[k + 1];
      return _ok_int(_kovats_between(ca, cb, ta, tb, tx));
    }
    k = k + 1;
  }
  return _err_int("chrom.kovats: retention time " + convert.int_to_string(tx) +
                  " outside anchor range " + convert.int_to_string(t0) + ".." +
                  convert.int_to_string(tlast));
}

// --------------------------------------------------
//  Signal-to-noise and QC flags
// --------------------------------------------------

/// Signal-to-noise ratio of a peak height against a noise level, in 1e-4
/// units: S/N = height / noise, i.e. S/N_fp = height * CHROM_FP_SCALE / noise,
/// one division that truncates toward zero (height * 10000 <= 1e13).
/// `height` must lie in 0..CHROM_FP_MAX and `noise` in 1..CHROM_FP_MAX.
///
/// Errors: "chrom.sn: height out of range 0..1000000000",
/// "chrom.sn: noise out of range 1..1000000000".
/// Complexity: O(1).
pub fn chrom_signal_to_noise(height: Int, noise: Int) -> Result[Int, Str] {
  if !_in_fp_range(height) {
    return _err_int("chrom.sn: height out of range 0..1000000000");
  }
  if noise <= 0 || noise > CHROM_FP_MAX {
    return _err_int("chrom.sn: noise out of range 1..1000000000");
  }
  return _ok_int((height * CHROM_FP_SCALE) / noise);
}

/// Asymmetry flag for a peak: CHROM_QC_TAILING when the asymmetry factor is
/// strictly above CHROM_ASYM_TAIL_MIN (1.1000), CHROM_QC_FRONTING when it is
/// strictly below CHROM_ASYM_FRONT_MAX (0.9000), CHROM_QC_OK otherwise (the
/// boundaries 0.9000 and 1.1000 themselves are symmetric).
/// `asymmetry` must lie in 1..CHROM_FP_MAX.
///
/// Errors: "chrom.qc: asymmetry out of range 1..1000000000".
/// Complexity: O(1).
pub fn chrom_asymmetry_flag(asymmetry: Int) -> Result[Int, Str] {
  if asymmetry <= 0 || asymmetry > CHROM_FP_MAX {
    return _err_int("chrom.qc: asymmetry out of range 1..1000000000");
  }
  if asymmetry > CHROM_ASYM_TAIL_MIN {
    return _ok_int(CHROM_QC_TAILING);
  }
  if asymmetry < CHROM_ASYM_FRONT_MAX {
    return _ok_int(CHROM_QC_FRONTING);
  }
  return _ok_int(CHROM_QC_OK);
}

/// Combined QC bitmask for one peak: signal-to-noise, asymmetry and
/// resolution are validated through their component functions and the raised
/// bits are OR-ed together:
///   CHROM_QC_LOW_SN     (4) when S/N < CHROM_SN_MIN (10.0000)
///   CHROM_QC_TAILING    (1) when asymmetry > 1.1000
///   CHROM_QC_FRONTING   (2) when asymmetry < 0.9000
///   CHROM_QC_UNRESOLVED (8) when resolution < CHROM_RES_CRITICAL (1.0000)
/// `resolution` must lie in 0..CHROM_FP_MAX; height/noise/asymmetry are
/// validated by the component calls (S/N first, then asymmetry).
///
/// Errors: "chrom.qc: resolution out of range 0..1000000000", then the
/// chrom.sn / chrom.qc messages of the component calls.
/// Complexity: O(1).
pub fn chrom_qc_flags(height: Int, noise: Int, asymmetry: Int,
                      resolution: Int) -> Result[Int, Str] {
  if !_in_fp_range(resolution) {
    return _err_int("chrom.qc: resolution out of range 0..1000000000");
  }
  let snr = chrom_signal_to_noise(height, noise);
  if !snr.is_ok {
    return _err_int(snr.error);
  }
  let af = chrom_asymmetry_flag(asymmetry);
  if !af.is_ok {
    return _err_int(af.error);
  }
  let sn: Int = snr.value;
  let flag: Int = af.value;
  var flags = 0;
  if sn < CHROM_SN_MIN {
    flags = flags | CHROM_QC_LOW_SN;
  }
  if flag == CHROM_QC_TAILING {
    flags = flags | CHROM_QC_TAILING;
  }
  if flag == CHROM_QC_FRONTING {
    flags = flags | CHROM_QC_FRONTING;
  }
  if resolution < CHROM_RES_CRITICAL {
    flags = flags | CHROM_QC_UNRESOLVED;
  }
  return _ok_int(flags);
}

// --------------------------------------------------
//  Baseline segments
// --------------------------------------------------

/// Baseline level at time `t` from mirrored baseline segment records: segment
/// i covers [starts[i], ends[i]] (inclusive at both ends, so touching
/// segments share their boundary and the earlier segment wins there) with
/// levels linearly interpolated from levels0[i] to levels1[i]:
///   level(t) = l0 + (l1 - l0) * (t - start) / (end - start)
/// The product is at most 1e18 and the single division truncates toward zero,
/// so a falling segment can round toward the segment start (documented: with
/// l0=100, l1=0, span=3 and t=1 the result is 100 + (-100/3) = 67).
///
/// All segments are validated before any lookup, in table order: equal
/// lengths, then per segment start range (0..CHROM_FP_MAX), end range
/// (1..CHROM_FP_MAX), end strictly after start, levels0/levels1 range, and
/// start at or after the previous end (no overlap). `t` must lie in
/// 0..CHROM_FP_MAX and be covered by some segment.
///
/// Errors: "chrom.baseline: segment tables length mismatch starts=N <field>=M",
/// "chrom.baseline: no baseline segments",
/// "chrom.baseline: time out of range 0..1000000000",
/// "chrom.baseline: segment I start out of range 0..1000000000",
/// "chrom.baseline: segment I end out of range 0..1000000000",
/// "chrom.baseline: segment I end not after start",
/// "chrom.baseline: segment I level0 out of range 0..1000000000",
/// "chrom.baseline: segment I level1 out of range 0..1000000000",
/// "chrom.baseline: segment I overlaps previous",
/// "chrom.baseline: time T not covered by baseline segments".
/// Complexity: O(n).
pub fn chrom_baseline_level_at(starts: &Vec[Int], ends: &Vec[Int],
                               levels0: &Vec[Int], levels1: &Vec[Int],
                               t: Int) -> Result[Int, Str] {
  let n = starts.len();
  if ends.len() != n {
    return _err_int("chrom.baseline: segment tables length mismatch starts=" +
                    convert.int_to_string(n) + " ends=" + convert.int_to_string(ends.len()));
  }
  if levels0.len() != n {
    return _err_int("chrom.baseline: segment tables length mismatch starts=" +
                    convert.int_to_string(n) + " levels0=" + convert.int_to_string(levels0.len()));
  }
  if levels1.len() != n {
    return _err_int("chrom.baseline: segment tables length mismatch starts=" +
                    convert.int_to_string(n) + " levels1=" + convert.int_to_string(levels1.len()));
  }
  if n == 0 {
    return _err_int("chrom.baseline: no baseline segments");
  }
  if !_in_fp_range(t) {
    return _err_int("chrom.baseline: time out of range 0..1000000000");
  }
  var i = 0;
  while i < n {
    let s: Int = starts[i];
    let e: Int = ends[i];
    let l0: Int = levels0[i];
    let l1: Int = levels1[i];
    if !_in_fp_range(s) {
      return _err_int("chrom.baseline: segment " + convert.int_to_string(i) +
                      " start out of range 0..1000000000");
    }
    if e < 1 || e > CHROM_FP_MAX {
      return _err_int("chrom.baseline: segment " + convert.int_to_string(i) +
                      " end out of range 0..1000000000");
    }
    if e <= s {
      return _err_int("chrom.baseline: segment " + convert.int_to_string(i) +
                      " end not after start");
    }
    if !_in_fp_range(l0) {
      return _err_int("chrom.baseline: segment " + convert.int_to_string(i) +
                      " level0 out of range 0..1000000000");
    }
    if !_in_fp_range(l1) {
      return _err_int("chrom.baseline: segment " + convert.int_to_string(i) +
                      " level1 out of range 0..1000000000");
    }
    if i > 0 {
      let pe: Int = ends[i - 1];
      if s < pe {
        return _err_int("chrom.baseline: segment " + convert.int_to_string(i) +
                        " overlaps previous");
      }
    }
    i = i + 1;
  }
  var k = 0;
  while k < n {
    let s2: Int = starts[k];
    let e2: Int = ends[k];
    if t >= s2 && t <= e2 {
      if t == s2 {
        let lo: Int = levels0[k];
        return _ok_int(lo);
      }
      if t == e2 {
        let hi: Int = levels1[k];
        return _ok_int(hi);
      }
      let lo2: Int = levels0[k];
      let hi2: Int = levels1[k];
      let span = e2 - s2;
      let frac = t - s2;
      return _ok_int(lo2 + ((hi2 - lo2) * frac) / span);
    }
    k = k + 1;
  }
  return _err_int("chrom.baseline: time " + convert.int_to_string(t) +
                  " not covered by baseline segments");
}

/// Baseline-corrected signal: signal - baseline, in fixed point. Both inputs
/// must lie in 0..CHROM_FP_MAX; the result may be negative (the baseline
/// exceeds the signal).
///
/// Errors: "chrom.baseline: signal out of range 0..1000000000",
/// "chrom.baseline: baseline out of range 0..1000000000".
/// Complexity: O(1).
pub fn chrom_baseline_corrected(signal: Int, baseline: Int) -> Result[Int, Str] {
  if !_in_fp_range(signal) {
    return _err_int("chrom.baseline: signal out of range 0..1000000000");
  }
  if !_in_fp_range(baseline) {
    return _err_int("chrom.baseline: baseline out of range 0..1000000000");
  }
  return _ok_int(signal - baseline);
}

// --------------------------------------------------
//  Canonical text codec
// --------------------------------------------------

/// Emit the canonical text codec for a peak table: the exact header line
/// CHROM_TABLE_HEADER followed by one record per peak,
///   "peak T A H W\n"
/// with each value formatted in fixed point as int.decimals with exactly four
/// fraction digits (zero padded). Every line, the last included, ends with
/// LF, so an empty table emits exactly the header plus LF.
///
/// The table is validated with chrom_peak_validate first and its error is
/// returned unchanged on Err.
/// Complexity: O(total output length).
pub fn chrom_table_emit(times: &Vec[Int], areas: &Vec[Int],
                        heights: &Vec[Int], widths: &Vec[Int]) -> Result[Str, Str] {
  let vr = chrom_peak_validate(times, areas, heights, widths);
  if !vr.is_ok {
    return _err_str(vr.error);
  }
  var out = CHROM_TABLE_HEADER;
  out = out + "\n";
  var i = 0;
  while i < times.len() {
    let t: Int = times[i];
    let a: Int = areas[i];
    let h: Int = heights[i];
    let w: Int = widths[i];
    out = out + "peak " + _emit_fp(t) + " " + _emit_fp(a) + " " + _emit_fp(h) +
          " " + _emit_fp(w) + "\n";
    i = i + 1;
  }
  return _ok_str(out);
}

/// Parse canonical peak-table text into four parallel output vectors, which
/// are cleared first and filled only on success (on Err they stay empty).
///
/// Grammar (SPEC.md section 8): the first non-blank line must equal
/// CHROM_TABLE_HEADER exactly; every later non-blank line is a record
/// "peak T A H W" with four fixed-point tokens
/// `["-"] digit+ ["." digit{1,4}]`; leading/trailing spaces and tabs and a
/// CR before LF are ignored, empty lines are skipped, and an empty table
/// (header only) is valid. After parsing, chrom_peak_validate is applied, so
/// semantically invalid tables (non-positive widths, non-increasing times,
/// negative or oversized values, ...) are rejected with its messages.
///
/// Errors: "chrom.codec: missing header", the _parse_record_range messages
/// (with 1-based line numbers), then the chrom_peak_validate catalog.
/// Complexity: O(total input length).
pub fn chrom_table_parse(text: Str, times: &mut Vec[Int], areas: &mut Vec[Int],
                         heights: &mut Vec[Int], widths: &mut Vec[Int]) -> Result[Unit, Str] {
  times.clear();
  areas.clear();
  heights.clear();
  widths.clear();
  var lt = Vec[Int].new();
  var la = Vec[Int].new();
  var lh = Vec[Int].new();
  var lw = Vec[Int].new();
  let n = text.len();
  var start = 0;
  var i = 0;
  var seen_header = false;
  var line_no = 0;
  while i <= n {
    var at_end = i == n;
    var at_lf = false;
    if !at_end {
      if _byte(text, i) == 10 {
        at_lf = true;
      }
    }
    if at_end || at_lf {
      var end = i;
      if end > start {
        if _byte(text, end - 1) == 13 {
          end = end - 1;
        }
      }
      line_no = line_no + 1;
      let a = _skip_ws_range(text, start, end);
      if a < end {
        var b = end;
        while b > a {
          let bb: Int = _byte(text, b - 1);
          if bb == 32 || bb == 9 {
            b = b - 1;
          } else {
            break;
          }
        }
        if !seen_header {
          if _range_equals(text, a, b, CHROM_TABLE_HEADER) {
            seen_header = true;
          } else {
            return _err_unit("chrom.codec: missing header");
          }
        } else {
          let rr = _parse_record_range(text, a, b, line_no);
          if !rr.is_ok {
            return _err_unit(rr.error);
          }
          let row: Vec[Int] = rr.value;
          let tv: Int = row[0];
          let av: Int = row[1];
          let hv: Int = row[2];
          let wv: Int = row[3];
          lt.push(tv);
          la.push(av);
          lh.push(hv);
          lw.push(wv);
        }
      }
      start = i + 1;
    }
    i = i + 1;
  }
  if !seen_header {
    return _err_unit("chrom.codec: missing header");
  }
  let vr = chrom_peak_validate(&lt, &la, &lh, &lw);
  if !vr.is_ok {
    return _err_unit(vr.error);
  }
  var q = 0;
  while q < lt.len() {
    let tv2: Int = lt[q];
    let av2: Int = la[q];
    let hv2: Int = lh[q];
    let wv2: Int = lw[q];
    times.push(tv2);
    areas.push(av2);
    heights.push(hv2);
    widths.push(wv2);
    q = q + 1;
  }
  return _ok_unit();
}
