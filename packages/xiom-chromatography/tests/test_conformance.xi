// XIOM -- xiom.chromatography conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.chromatography data model against its
// SPEC: mirrored fixed-point peak tables (scale 1e-4), validation, total-area
// and cumulative-floor normalization to exactly 100 percent, half-height
// resolution, Kovats retention indices against caller-supplied alkane
// anchors, signal-to-noise, tailing/fronting QC flags, baseline segment
// interpolation and the canonical text codec (emit/parse round-trip and the
// error catalog).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected integer below is a pinned decimal result of the documented
// fixed-point formulas, recomputed by hand; there are no floating point
// values in this file. All Str comparisons go through
// xiom.string.compare.str_compare (BUG 17 discipline); direct calls only, no
// function tables, and every Vec element read is bound to a typed local.

module chromatography_tests
use xiom.io; use xiom.test;
use xiom.chromatography;
use xiom.string.compare;

// --------------------------------------------------
//  Fixtures and check helpers
// --------------------------------------------------

// Str equality via str_compare (BUG 17 discipline).
fn seq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// One-, two-, three- and four-element Int vectors.
fn v1(x: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  return v;
}

fn v2(x: Int, y: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  v.push(y);
  return v;
}

fn v3(x: Int, y: Int, z: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(x);
  v.push(y);
  v.push(z);
  return v;
}

fn v4(w: Int, x: Int, y: Int, z: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(w);
  v.push(x);
  v.push(y);
  v.push(z);
  return v;
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn vec_sum(a: &Vec[Int]) -> Int {
  var total = 0;
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    total = total + x;
    i = i + 1;
  }
  return total;
}

fn int_ok(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn unit_ok(r: Result[Unit, Str]) -> Bool {
  return r.is_ok;
}

fn unit_err(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn vec_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

fn str_ok(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let s: Str = r.value;
  return seq(s, want);
}

fn str_err(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return seq(r.error, want);
}

// Parse `text` expecting the exact error `want` and four output vectors left
// empty (the parser clears them first and only fills them on success).
fn parse_err(text: Str, want: Str) -> Bool {
  var t = Vec[Int].new();
  var a = Vec[Int].new();
  var h = Vec[Int].new();
  var w = Vec[Int].new();
  let r = chrom_table_parse(text, &mut t, &mut a, &mut h, &mut w);
  if r.is_ok {
    return false;
  }
  if !seq(r.error, want) {
    return false;
  }
  if t.len() != 0 || a.len() != 0 || h.len() != 0 || w.len() != 0 {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Validation and area math
// --------------------------------------------------

fn t01_validate_ok() -> TestResult {
  var ok = unit_ok(chrom_peak_validate(&v3(10000, 20000, 30000), &v3(100, 200, 300),
                                       &v3(50, 60, 70), &v3(100, 100, 100)));
  let empty = Vec[Int].new();
  if !unit_ok(chrom_peak_validate(&empty, &empty, &empty, &empty)) { ok = false; }
  if !unit_ok(chrom_peak_validate(&v1(0), &v1(1), &v1(1), &v1(1))) { ok = false; }
  return assert(ok, "validate: valid 3-peak table, empty table and t=0 boundary accepted");
}

fn t02_validate_len_mismatch() -> TestResult {
  var ok = unit_err(chrom_peak_validate(&v3(1, 2, 3), &v2(1, 2), &v3(1, 2, 3), &v3(1, 2, 3)),
                    "chrom: table length mismatch times=3 areas=2");
  if !unit_err(chrom_peak_validate(&v3(1, 2, 3), &v3(1, 2, 3), &v2(1, 2), &v3(1, 2, 3)),
               "chrom: table length mismatch times=3 heights=2") { ok = false; }
  if !unit_err(chrom_peak_validate(&v3(1, 2, 3), &v3(1, 2, 3), &v3(1, 2, 3), &v2(1, 2)),
               "chrom: table length mismatch times=3 widths=2") { ok = false; }
  return assert(ok, "validate: first unequal length is reported with both counts");
}

fn t03_validate_field_errors() -> TestResult {
  var ok = unit_err(chrom_peak_validate(&v2(10000, 10000), &v2(100, 100), &v2(50, 50), &v2(100, 100)),
                    "chrom: peak 1 time not increasing after peak 0");
  if !unit_err(chrom_peak_validate(&v2(10000, 20000), &v2(100, 0), &v2(50, 50), &v2(100, 100)),
               "chrom: peak 1 area must be positive") { ok = false; }
  if !unit_err(chrom_peak_validate(&v2(10000, 20000), &v2(100, 100), &v2(50, 0), &v2(100, 100)),
               "chrom: peak 1 height must be positive") { ok = false; }
  if !unit_err(chrom_peak_validate(&v2(10000, 20000), &v2(100, 100), &v2(50, 50), &v2(100, 0)),
               "chrom: peak 1 width must be positive") { ok = false; }
  if !unit_err(chrom_peak_validate(&v2(10000, 20000), &v2(100, -1), &v2(50, 50), &v2(100, 100)),
               "chrom: peak 1 area out of range 0..1000000000") { ok = false; }
  return assert(ok, "validate: positivity and order messages pinned per field");
}

fn t04_validate_range() -> TestResult {
  var ok = unit_err(chrom_peak_validate(&v1(1000000001), &v1(100), &v1(50), &v1(100)),
                    "chrom: peak 0 time out of range 0..1000000000");
  if !unit_err(chrom_peak_validate(&v1(100), &v1(1000000001), &v1(50), &v1(100)),
               "chrom: peak 0 area out of range 0..1000000000") { ok = false; }
  if !unit_err(chrom_peak_validate(&v1(100), &v1(100), &v1(1000000001), &v1(100)),
               "chrom: peak 0 height out of range 0..1000000000") { ok = false; }
  if !unit_err(chrom_peak_validate(&v1(100), &v1(100), &v1(50), &v1(1000000001)),
               "chrom: peak 0 width out of range 0..1000000000") { ok = false; }
  if !unit_err(chrom_peak_validate(&v1(-1), &v1(100), &v1(50), &v1(100)),
               "chrom: peak 0 time out of range 0..1000000000") { ok = false; }
  return assert(ok, "validate: range guard 0..1000000000 on every field");
}

fn t05_total_area() -> TestResult {
  var ok = int_ok(chrom_peak_total_area(&v3(10000, 20000, 30000)), 60000);
  if !int_ok(chrom_peak_total_area(&v1(0)), 0) { ok = false; }
  let empty = Vec[Int].new();
  if !int_err(chrom_peak_total_area(&empty), "chrom: no peaks") { ok = false; }
  if !int_err(chrom_peak_total_area(&v2(100, -50)), "chrom: negative area at index 1") { ok = false; }
  return assert(ok, "total area: sum, zero area and guard messages");
}

fn t06_normalize_two() -> TestResult {
  let r = chrom_peak_normalize_areas(&v2(30000, 10000));
  var ok = false;
  if r.is_ok {
    let out: Vec[Int] = r.value;
    ok = vec_eq(&out, &v2(750000, 250000));
    if vec_sum(&out) != 1000000 { ok = false; }
  }
  return assert(ok, "normalize 3:1 -> 75.0000 / 25.0000 percent, sum exactly 1000000");
}

fn t07_normalize_thirds_and_zero() -> TestResult {
  let r = chrom_peak_normalize_areas(&v3(10000, 10000, 10000));
  var ok = false;
  if r.is_ok {
    let out: Vec[Int] = r.value;
    ok = vec_eq(&out, &v3(333333, 333333, 333334));
    if vec_sum(&out) != 1000000 { ok = false; }
  }
  let r2 = chrom_peak_normalize_areas(&v3(10000, 0, 30000));
  if !r2.is_ok {
    ok = false;
  } else {
    let out2: Vec[Int] = r2.value;
    if !vec_eq(&out2, &v3(250000, 0, 750000)) { ok = false; }
    if vec_sum(&out2) != 1000000 { ok = false; }
  }
  return assert(ok, "normalize: thirds give the residual to the last peak; zero area stays 0");
}

fn t08_normalize_errors() -> TestResult {
  let empty = Vec[Int].new();
  var ok = vec_err(chrom_peak_normalize_areas(&empty), "chrom: no peaks to normalize");
  if !vec_err(chrom_peak_normalize_areas(&v2(100, -50)), "chrom: negative area at index 1") { ok = false; }
  if !vec_err(chrom_peak_normalize_areas(&v2(0, 0)), "chrom: total area is zero") { ok = false; }
  return assert(ok, "normalize: empty, negative and zero-total guards");
}

fn t09_normalize_overflow_guard() -> TestResult {
  var big = Vec[Int].new();
  var i = 0;
  while i < 1002 {
    big.push(1000000000);
    i = i + 1;
  }
  var ok = vec_err(chrom_peak_normalize_areas(&big), "chrom: total area exceeds 1000000000000");
  if !int_err(chrom_peak_total_area(&big), "chrom: total area exceeds 1000000000000") { ok = false; }
  return assert(ok, "area cap 1e12: 1002 peaks of 1e9 trip at the 1001st addition");
}

// --------------------------------------------------
//  Resolution
// --------------------------------------------------

fn t10_resolution_pinned() -> TestResult {
  var ok = int_ok(chrom_peak_resolution(10000, 1000, 15000, 1000), 29500);
  if !int_ok(chrom_peak_resolution(10000, 1000, 11000, 1000), 5900) { ok = false; }
  if !int_ok(chrom_peak_resolution(20000, 500, 30000, 1500), 59000) { ok = false; }
  if !int_ok(chrom_peak_resolution(10000, 1000, 25000, 1000), 88500) { ok = false; }
  return assert(ok, "resolution: R_fp = 11800*dT/(w1+w2) pinned at 2.9500, 0.5900, 5.9000, 8.8500");
}

fn t11_resolution_trunc_and_errors() -> TestResult {
  var ok = int_ok(chrom_peak_resolution(10000, 1000, 10101, 1000), 595);
  if !int_err(chrom_peak_resolution(10000, 1000, 10000, 1000),
              "chrom.resolution: t2 must be greater than t1") { ok = false; }
  if !int_err(chrom_peak_resolution(10001, 1000, 10000, 1000),
              "chrom.resolution: t2 must be greater than t1") { ok = false; }
  if !int_err(chrom_peak_resolution(-1, 1000, 10000, 1000),
              "chrom.resolution: t1 out of range 0..1000000000") { ok = false; }
  if !int_err(chrom_peak_resolution(10000, 1000, 1000000001, 1000),
              "chrom.resolution: t2 out of range 0..1000000000") { ok = false; }
  if !int_err(chrom_peak_resolution(10000, 0, 15000, 1000),
              "chrom.resolution: w1 out of range 1..1000000000") { ok = false; }
  if !int_err(chrom_peak_resolution(10000, 1000, 15000, 0),
              "chrom.resolution: w2 out of range 1..1000000000") { ok = false; }
  return assert(ok, "resolution: 118.59/200 truncates to 595; validation catalog pinned");
}

fn t12_adjacent_resolution() -> TestResult {
  var ok = int_ok(chrom_table_adjacent_resolution(&v3(10000, 15000, 22000), &v3(1000, 1000, 2000), 0), 29500);
  if !int_ok(chrom_table_adjacent_resolution(&v3(10000, 15000, 22000), &v3(1000, 1000, 2000), 1), 27533) { ok = false; }
  if !int_err(chrom_table_adjacent_resolution(&v3(10000, 15000, 22000), &v3(1000, 1000, 2000), -1),
              "chrom.resolution: adjacent index -1 out of range 0..1") { ok = false; }
  if !int_err(chrom_table_adjacent_resolution(&v3(10000, 15000, 22000), &v3(1000, 1000, 2000), 2),
              "chrom.resolution: adjacent index 2 out of range 0..1") { ok = false; }
  if !int_err(chrom_table_adjacent_resolution(&v2(10000, 20000), &v1(1000), 0),
              "chrom.resolution: table length mismatch times=2 widths=1") { ok = false; }
  if !int_err(chrom_table_adjacent_resolution(&v1(10000), &v1(1000), 0),
              "chrom.resolution: table needs at least 2 peaks") { ok = false; }
  return assert(ok, "adjacent resolution: pairs 0/1 and both guard messages");
}

// --------------------------------------------------
//  Kovats retention index
// --------------------------------------------------

fn t13_kovats_between() -> TestResult {
  var ok = int_ok(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 150000), 11000000);
  if !int_ok(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 200000), 12000000) { ok = false; }
  if !int_ok(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 250000), 13000000) { ok = false; }
  if !int_ok(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 105000), 10100000) { ok = false; }
  if !int_ok(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 100000), 10000000) { ok = false; }
  if !int_ok(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 300000), 14000000) { ok = false; }
  return assert(ok, "Kovats: 10/12/14 anchors pin exact hits and linear interpolation");
}

fn t14_kovats_consecutive_and_errors() -> TestResult {
  var ok = int_ok(chrom_kovats_index(&v2(7, 8), &v2(5000, 15000), 12500), 7750000);
  if !int_ok(chrom_kovats_index(&v2(7, 8), &v2(5000, 15000), 5000), 7000000) { ok = false; }
  if !int_ok(chrom_kovats_index(&v2(7, 8), &v2(5000, 15000), 15000), 8000000) { ok = false; }
  if !int_err(chrom_kovats_index(&v2(10, 12), &v1(100000), 100000),
              "chrom.kovats: anchor table length mismatch carbon=2 time=1") { ok = false; }
  if !int_err(chrom_kovats_index(&v1(10), &v1(100000), 100000),
              "chrom.kovats: anchors need at least 2 points") { ok = false; }
  if !int_err(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 50000),
              "chrom.kovats: retention time 50000 outside anchor range 100000..300000") { ok = false; }
  if !int_err(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), 400000),
              "chrom.kovats: retention time 400000 outside anchor range 100000..300000") { ok = false; }
  if !int_err(chrom_kovats_index(&v3(10, 10, 14), &v3(100000, 200000, 300000), 150000),
              "chrom.kovats: anchor carbon not increasing at 1") { ok = false; }
  if !int_err(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 100000, 300000), 150000),
              "chrom.kovats: anchor time not increasing at 1") { ok = false; }
  if !int_err(chrom_kovats_index(&v2(10, 1001), &v2(100000, 200000), 150000),
              "chrom.kovats: anchor 1 carbon out of range 0..1000") { ok = false; }
  if !int_err(chrom_kovats_index(&v3(10, 12, 14), &v3(100000, 200000, 300000), -1),
              "chrom.kovats: retention time out of range 0..1000000000") { ok = false; }
  return assert(ok, "Kovats: consecutive anchors pin RI 775; full anchor error catalog");
}

// --------------------------------------------------
//  Signal-to-noise and QC flags
// --------------------------------------------------

fn t15_sn_pinned_and_errors() -> TestResult {
  var ok = int_ok(chrom_signal_to_noise(100000000, 1000000), 1000000);
  if !int_ok(chrom_signal_to_noise(1, 1), 10000) { ok = false; }
  if !int_ok(chrom_signal_to_noise(0, 1), 0) { ok = false; }
  if !int_ok(chrom_signal_to_noise(1, 3), 3333) { ok = false; }
  if !int_err(chrom_signal_to_noise(1, 0), "chrom.sn: noise out of range 1..1000000000") { ok = false; }
  if !int_err(chrom_signal_to_noise(1, 1000000001), "chrom.sn: noise out of range 1..1000000000") { ok = false; }
  if !int_err(chrom_signal_to_noise(-1, 1), "chrom.sn: height out of range 0..1000000000") { ok = false; }
  return assert(ok, "S/N: 10000/1 is 10000.0000 and 10000/3 truncates to 3333");
}

fn t16_asymmetry_flags() -> TestResult {
  var ok = int_ok(chrom_asymmetry_flag(10000), CHROM_QC_OK);
  if !int_ok(chrom_asymmetry_flag(11000), CHROM_QC_OK) { ok = false; }
  if !int_ok(chrom_asymmetry_flag(11001), CHROM_QC_TAILING) { ok = false; }
  if !int_ok(chrom_asymmetry_flag(12500), CHROM_QC_TAILING) { ok = false; }
  if !int_ok(chrom_asymmetry_flag(9000), CHROM_QC_OK) { ok = false; }
  if !int_ok(chrom_asymmetry_flag(8999), CHROM_QC_FRONTING) { ok = false; }
  if !int_ok(chrom_asymmetry_flag(8000), CHROM_QC_FRONTING) { ok = false; }
  if !int_err(chrom_asymmetry_flag(0), "chrom.qc: asymmetry out of range 1..1000000000") { ok = false; }
  if !int_err(chrom_asymmetry_flag(1000000001), "chrom.qc: asymmetry out of range 1..1000000000") { ok = false; }
  return assert(ok, "asymmetry: 1.1000/0.9000 stay OK; 1.1001 tails, 0.8999 fronts");
}

fn t17_qc_flags() -> TestResult {
  var ok = int_ok(chrom_qc_flags(200000000, 1000000, 10000, 20000), 0);
  if !int_ok(chrom_qc_flags(10000, 1000000, 10000, 20000), CHROM_QC_LOW_SN) { ok = false; }
  if !int_ok(chrom_qc_flags(200000000, 1000000, 13000, 5000), CHROM_QC_TAILING | CHROM_QC_UNRESOLVED) { ok = false; }
  if !int_ok(chrom_qc_flags(200000000, 1000000, 8000, 10000), CHROM_QC_FRONTING) { ok = false; }
  if !int_ok(chrom_qc_flags(10000000, 1000000, 10000, 20000), 0) { ok = false; }
  if !int_ok(chrom_qc_flags(9999999, 1000000, 10000, 20000), CHROM_QC_LOW_SN) { ok = false; }
  if !int_err(chrom_qc_flags(1, 0, 10000, 10000), "chrom.sn: noise out of range 1..1000000000") { ok = false; }
  if !int_err(chrom_qc_flags(1, 1, 10000, -1), "chrom.qc: resolution out of range 0..1000000000") { ok = false; }
  return assert(ok, "QC bits: S/N boundary exactly 10.0000, tailing+unresolved combine as 1|8");
}

// --------------------------------------------------
//  Baseline segments
// --------------------------------------------------

fn t18_baseline_levels() -> TestResult {
  var ok = int_ok(chrom_baseline_level_at(&v2(0, 1000), &v2(1000, 3000),
                                          &v2(100, 200), &v2(200, 0), 0), 100);
  if !int_ok(chrom_baseline_level_at(&v2(0, 1000), &v2(1000, 3000),
                                     &v2(100, 200), &v2(200, 0), 500), 150) { ok = false; }
  if !int_ok(chrom_baseline_level_at(&v2(0, 1000), &v2(1000, 3000),
                                     &v2(100, 200), &v2(200, 0), 1000), 200) { ok = false; }
  if !int_ok(chrom_baseline_level_at(&v2(0, 1000), &v2(1000, 3000),
                                     &v2(100, 200), &v2(200, 0), 2000), 100) { ok = false; }
  if !int_ok(chrom_baseline_level_at(&v2(0, 1000), &v2(1000, 3000),
                                     &v2(100, 200), &v2(200, 0), 3000), 0) { ok = false; }
  if !int_ok(chrom_baseline_level_at(&v1(0), &v1(3), &v1(100), &v1(0), 1), 67) { ok = false; }
  if !int_ok(chrom_baseline_level_at(&v1(0), &v1(3), &v1(100), &v1(0), 2), 34) { ok = false; }
  return assert(ok, "baseline: two-segment interpolation and falling-slope truncation 67/34");
}

fn t19_baseline_errors() -> TestResult {
  let empty = Vec[Int].new();
  var ok = int_err(chrom_baseline_level_at(&empty, &empty, &empty, &empty, 0),
                   "chrom.baseline: no baseline segments");
  if !int_err(chrom_baseline_level_at(&v2(0, 1000), &v1(1000), &v2(100, 200), &v2(200, 0), 500),
              "chrom.baseline: segment tables length mismatch starts=2 ends=1") { ok = false; }
  if !int_err(chrom_baseline_level_at(&v1(0), &v2(1000, 2000), &v1(100), &v1(200), 500),
              "chrom.baseline: segment tables length mismatch starts=1 ends=2") { ok = false; }
  if !int_err(chrom_baseline_level_at(&v1(1000), &v1(1000), &v1(100), &v1(200), 1000),
              "chrom.baseline: segment 0 end not after start") { ok = false; }
  if !int_err(chrom_baseline_level_at(&v2(0, 500), &v2(1000, 1500), &v2(100, 100), &v2(200, 200), 700),
              "chrom.baseline: segment 1 overlaps previous") { ok = false; }
  if !int_err(chrom_baseline_level_at(&v2(0, 2000), &v2(1000, 3000), &v2(100, 100), &v2(200, 1000000001), 500),
              "chrom.baseline: segment 1 level1 out of range 0..1000000000") { ok = false; }
  if !int_err(chrom_baseline_level_at(&v1(0), &v1(1000), &v1(100), &v1(200), -1),
              "chrom.baseline: time out of range 0..1000000000") { ok = false; }
  if !int_err(chrom_baseline_level_at(&v2(0, 2000), &v2(1000, 3000), &v2(100, 100), &v2(200, 200), 1500),
              "chrom.baseline: time 1500 not covered by baseline segments") { ok = false; }
  return assert(ok, "baseline: length, order, overlap, range and coverage errors pinned");
}

fn t20_baseline_corrected() -> TestResult {
  var ok = int_ok(chrom_baseline_corrected(50000, 20000), 30000);
  if !int_ok(chrom_baseline_corrected(10000, 30000), -20000) { ok = false; }
  if !int_err(chrom_baseline_corrected(-1, 0), "chrom.baseline: signal out of range 0..1000000000") { ok = false; }
  if !int_err(chrom_baseline_corrected(0, 1000000001), "chrom.baseline: baseline out of range 0..1000000000") { ok = false; }
  return assert(ok, "baseline correction: 5.0000-2.0000=3.0000 and a negative result is allowed");
}

// --------------------------------------------------
//  Canonical text codec
// --------------------------------------------------

fn t21_codec_emit_pinned() -> TestResult {
  let want = "#chromatography peaks v1\npeak 1.0000 3.0000 0.5000 0.1000\npeak 1.5000 1.0000 0.4000 0.2000\n";
  var ok = str_ok(chrom_table_emit(&v2(10000, 15000), &v2(30000, 10000),
                                   &v2(5000, 4000), &v2(1000, 2000)), want);
  let empty = Vec[Int].new();
  if !str_ok(chrom_table_emit(&empty, &empty, &empty, &empty), "#chromatography peaks v1\n") { ok = false; }
  if !str_ok(chrom_table_emit(&v1(5), &v1(9999), &v1(10000), &v1(999999999)),
             "#chromatography peaks v1\npeak 0.0005 0.9999 1.0000 99999.9999\n") { ok = false; }
  if !str_err(chrom_table_emit(&v2(20000, 10000), &v2(100, 100), &v2(50, 50), &v2(100, 100)),
              "chrom: peak 1 time not increasing after peak 0") { ok = false; }
  return assert(ok, "codec emit: exact bytes, header-only table, zero padding, validation passthrough");
}

fn t22_codec_parse_flexible() -> TestResult {
  let text = "#chromatography peaks v1\r\npeak 1.5 3 0.5000 0.1\r\n  \tpeak 2.2500 1.0000 0.4000 0.2000\n\n";
  var t = Vec[Int].new();
  var a = Vec[Int].new();
  var h = Vec[Int].new();
  var w = Vec[Int].new();
  let r = chrom_table_parse(text, &mut t, &mut a, &mut h, &mut w);
  var ok = r.is_ok;
  if ok {
    if !vec_eq(&t, &v2(15000, 22500)) { ok = false; }
    if !vec_eq(&a, &v2(30000, 10000)) { ok = false; }
    if !vec_eq(&h, &v2(5000, 4000)) { ok = false; }
    if !vec_eq(&w, &v2(1000, 2000)) { ok = false; }
  }
  var t0 = Vec[Int].new();
  var a0 = Vec[Int].new();
  var h0 = Vec[Int].new();
  var w0 = Vec[Int].new();
  let r0 = chrom_table_parse(CHROM_TABLE_HEADER + "\n", &mut t0, &mut a0, &mut h0, &mut w0);
  if !r0.is_ok { ok = false; }
  if t0.len() != 0 || a0.len() != 0 || h0.len() != 0 || w0.len() != 0 { ok = false; }
  return assert(ok, "codec parse: CRLF, tabs, short decimals and header-only tables accepted");
}

fn t23_codec_parse_errors() -> TestResult {
  var ok = parse_err("", "chrom.codec: missing header");
  if !parse_err("peak 1 1 1 1\n", "chrom.codec: missing header") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\npeak x 1 1 1\n", "chrom.codec: line 2 field 1: bad value") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\npeak 1.23456 1 1 1\n",
                "chrom.codec: line 2 field 1: more than 4 decimal places") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\npeak 100001.0000 1 1 1\n",
                "chrom.codec: line 2 field 1: value out of range 0..1000000000") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\npeak 1 1\n",
                "chrom.codec: line 2: expected 4 fixed-point fields, got 2") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\npeak 1 1 1 1 extra\n",
                "chrom.codec: line 2: trailing text after 4 fields") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\nhello\n",
                "chrom.codec: line 2: expected 'peak' record") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\npeak 1 -1 1 1\n",
                "chrom: peak 0 area out of range 0..1000000000") { ok = false; }
  if !parse_err(CHROM_TABLE_HEADER + "\npeak 2.0000 1 1 1\npeak 1.0000 1 1 1\n",
                "chrom: peak 1 time not increasing after peak 0") { ok = false; }
  var t = v1(999);
  var a = v1(999);
  var h = v1(999);
  var w = v1(999);
  let r = chrom_table_parse("bad", &mut t, &mut a, &mut h, &mut w);
  if r.is_ok { ok = false; }
  if t.len() != 0 || a.len() != 0 || h.len() != 0 || w.len() != 0 { ok = false; }
  return assert(ok, "codec parse: header, shape, value and semantic errors; outputs cleared on Err");
}

fn t24_codec_roundtrip() -> TestResult {
  var t = v3(10000, 15000, 22000);
  var a = v3(30000, 10000, 5000);
  var h = v3(5000, 4000, 3000);
  var w = v3(1000, 2000, 1500);
  let er = chrom_table_emit(&t, &a, &h, &w);
  var ok = er.is_ok;
  if ok {
    let text: Str = er.value;
    var t2 = Vec[Int].new();
    var a2 = Vec[Int].new();
    var h2 = Vec[Int].new();
    var w2 = Vec[Int].new();
    let pr = chrom_table_parse(text, &mut t2, &mut a2, &mut h2, &mut w2);
    if !pr.is_ok {
      ok = false;
    } else {
      if !vec_eq(&t2, &t) { ok = false; }
      if !vec_eq(&a2, &a) { ok = false; }
      if !vec_eq(&h2, &h) { ok = false; }
      if !vec_eq(&w2, &w) { ok = false; }
      let er2 = chrom_table_emit(&t2, &a2, &h2, &w2);
      if !str_ok(er2, text) { ok = false; }
    }
  }
  return assert(ok, "codec round-trip: emit->parse recovers all four parallel vectors; emit is idempotent");
}

// --------------------------------------------------
//  Runner
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.chromatography conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_validate_ok();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_validate_len_mismatch();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_validate_field_errors();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_validate_range();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_total_area();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_normalize_two();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_normalize_thirds_and_zero();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_normalize_errors();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_normalize_overflow_guard();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_resolution_pinned();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_resolution_trunc_and_errors();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_adjacent_resolution();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_kovats_between();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_kovats_consecutive_and_errors();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_sn_pinned_and_errors();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_asymmetry_flags();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_qc_flags();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_baseline_levels();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_baseline_errors();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_baseline_corrected();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_codec_emit_pinned();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22_codec_parse_flexible();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23_codec_parse_errors();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24_codec_roundtrip();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.chromatography: all tests passed");
  } else {
    io.println("xiom.chromatography: tests failed");
  }
  return failed;
}
