// XIOM -- xiom.spectroscopy conformance tests (16 checks)
// Port task: prove the pure-XIOM xiom.spectroscopy module (electromagnetic
// spectrum conversions) against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected value is a pinned decimal result of the documented formulas
// (SPEC.md section 6), compared with the task-mandated relative-with-floor
// tolerance through close():
//
//   close(a, b) := fabs(a - b) <= 1e-6 * max(1, fabs(b))
//
// where b is the expected value. The max(1, |b|) floor keeps the bound
// absolute (1e-6) for expected magnitudes <= 1 and scales it to 1e-6
// relative for larger ones (e.g. 1239.841984 nm allows 0.00124 nm; 1e8 cm^-1
// allows 100), so a single helper covers the THz, eV, nm and cm^-1 ranges
// without weakening any assertion. fabs is xiom.math.abs_float (the raw libm
// fabs is module-private) and max is xiom.math.max_float.
//
// All Str equality goes through str_compare (xiom.string.compare): BUG 17
// lowers `==` on some Str values to a pointer comparison, so the band-name
// checks are routed through seq()/band_is() instead of `==`.
//
// Boundary convention pinned here: 750 nm belongs to "visible" (matching
// spec_is_visible, 380..750 inclusive); "near-IR" starts strictly above
// 750 nm, "IR" at 2500 nm and "far-IR" at 1e6 nm (both inclusive).

module spectroscopy_tests
use xiom.io; use xiom.test; use xiom.spectroscopy; use xiom.math;
use xiom.string.compare;

// Relative-with-floor approximate equality: fabs(a - b) <= 1e-6*max(1, |b|).
fn close(a: Float64, b: Float64) -> Bool {
  let d: Float64 = xiom.math.abs_float(a - b);
  let scale: Float64 = xiom.math.max_float(1.0, xiom.math.abs_float(b));
  return d <= 0.000001 * scale;
}

// Str equality via str_compare (BUG 17 discipline).
fn seq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn band_is(nm: Float64, want: Str) -> Bool {
  return seq(spec_band_name(nm), want);
}

// -- Wavelength <-> frequency --

fn t01_nm_to_thz_500() -> TestResult {
  var ok = close(spec_nm_to_thz(500.0), 599.584916);
  if !close(spec_nm_to_thz(1000.0), 299.792458) { ok = false; }
  if !close(spec_nm_to_thz(250.0), 1199.169832) { ok = false; }
  return assert(ok, "nm->THz: 500 nm is 599.584916 THz (pinned); half wavelength doubles f");
}

fn t02_nm_to_ev_500() -> TestResult {
  var ok = close(spec_nm_to_ev(500.0), 2.4796837);
  if !close(spec_nm_to_ev(1000.0), 1.23984185) { ok = false; }
  if !close(spec_nm_to_ev(250.0), 4.9593679) { ok = false; }
  return assert(ok, "nm->eV: 500 nm is 2.4796837 eV (pinned); half wavelength doubles E");
}

fn t03_roundtrip_nm_thz() -> TestResult {
  var ok = close(spec_thz_to_nm(spec_nm_to_thz(250.0)), 250.0);
  if !close(spec_thz_to_nm(spec_nm_to_thz(500.0)), 500.0) { ok = false; }
  if !close(spec_thz_to_nm(spec_nm_to_thz(1064.0)), 1064.0) { ok = false; }
  if !close(spec_thz_to_nm(spec_nm_to_thz(10000.0)), 10000.0) { ok = false; }
  return assert(ok, "round-trip nm->THz->nm is identity for 250/500/1064/10000 nm");
}

// -- Wavelength <-> photon energy --

fn t04_roundtrip_nm_ev() -> TestResult {
  var ok = close(spec_ev_to_nm(spec_nm_to_ev(200.0)), 200.0);
  if !close(spec_ev_to_nm(spec_nm_to_ev(500.0)), 500.0) { ok = false; }
  if !close(spec_ev_to_nm(spec_nm_to_ev(1064.0)), 1064.0) { ok = false; }
  return assert(ok, "round-trip nm->eV->nm is identity for 200/500/1064 nm");
}

fn t07_ev_to_nm() -> TestResult {
  var ok = close(spec_ev_to_nm(1.0), 1239.841984);
  if !close(spec_ev_to_nm(2.0), 619.920992) { ok = false; }
  if !close(spec_ev_to_nm(10.0), 123.9841984) { ok = false; }
  return assert(ok, "eV->nm: 1 eV is 1239.841984 nm (pinned); 2 eV halves it");
}

// -- Wavelength <-> wavenumber --

fn t05_roundtrip_nm_cm_inv() -> TestResult {
  var ok = close(spec_cm_inv_to_nm(spec_nm_to_cm_inv(500.0)), 500.0);
  if !close(spec_cm_inv_to_nm(spec_nm_to_cm_inv(1064.0)), 1064.0) { ok = false; }
  if !close(spec_cm_inv_to_nm(spec_nm_to_cm_inv(10000.0)), 10000.0) { ok = false; }
  return assert(ok, "round-trip nm->cm^-1->nm is identity for 500/1064/10000 nm");
}

fn t06_cm_inv_to_nm() -> TestResult {
  var ok = close(spec_cm_inv_to_nm(1000.0), 10000.0);
  if !close(spec_cm_inv_to_nm(5000.0), 2000.0) { ok = false; }
  if !close(spec_cm_inv_to_nm(1.0), 1e7) { ok = false; }
  if !close(spec_nm_to_cm_inv(10000.0), 1000.0) { ok = false; }
  return assert(ok, "cm^-1->nm: 1000 cm^-1 is 10000 nm (10 um); 1 cm^-1 is 1e7 nm");
}

// -- Visible range and band names --

fn t08_is_visible_bounds() -> TestResult {
  var ok = !spec_is_visible(379.9);
  if !spec_is_visible(380.0) { ok = false; }
  if !spec_is_visible(500.0) { ok = false; }
  if !spec_is_visible(750.0) { ok = false; }
  if spec_is_visible(750.1) { ok = false; }
  return assert(ok, "visible bounds: 379.9 false, 380 true, 500 true, 750 true, 750.1 false");
}

fn t09_band_names() -> TestResult {
  var ok = band_is(10.0, "UV");
  if !band_is(300.0, "UV") { ok = false; }
  if !band_is(379.9, "UV") { ok = false; }
  if !band_is(380.0, "visible") { ok = false; }
  if !band_is(500.0, "visible") { ok = false; }
  if !band_is(750.0, "visible") { ok = false; }
  if !band_is(750.1, "near-IR") { ok = false; }
  if !band_is(1000.0, "near-IR") { ok = false; }
  if !band_is(2499.9, "near-IR") { ok = false; }
  if !band_is(2500.0, "IR") { ok = false; }
  if !band_is(5000.0, "IR") { ok = false; }
  if !band_is(999999.0, "IR") { ok = false; }
  if !band_is(1e6, "far-IR") { ok = false; }
  if !band_is(1e7, "far-IR") { ok = false; }
  return assert(ok, "band names pinned at every UV/visible/near-IR/IR/far-IR boundary");
}

fn t10_band_guard_zero_negative() -> TestResult {
  var ok = seq(spec_band_name(0.0), "");
  if !seq(spec_band_name(-5.0), "") { ok = false; }
  if !seq(spec_band_name(-0.001), "") { ok = false; }
  return assert(ok, "band name guard: nm <= 0 returns the empty string");
}

// -- Guards and round-trips across routes --

fn t11_guard_nonpositive_all() -> TestResult {
  var ok = close(spec_nm_to_thz(0.0), 0.0);
  if !close(spec_nm_to_thz(-1.0), 0.0) { ok = false; }
  if !close(spec_thz_to_nm(0.0), 0.0) { ok = false; }
  if !close(spec_thz_to_nm(-2.0), 0.0) { ok = false; }
  if !close(spec_nm_to_ev(0.0), 0.0) { ok = false; }
  if !close(spec_nm_to_ev(-500.0), 0.0) { ok = false; }
  if !close(spec_ev_to_nm(0.0), 0.0) { ok = false; }
  if !close(spec_ev_to_nm(-1.0), 0.0) { ok = false; }
  if !close(spec_nm_to_cm_inv(0.0), 0.0) { ok = false; }
  if !close(spec_nm_to_cm_inv(-10.0), 0.0) { ok = false; }
  if !close(spec_cm_inv_to_nm(0.0), 0.0) { ok = false; }
  if !close(spec_cm_inv_to_nm(-10.0), 0.0) { ok = false; }
  if !close(spec_ev_to_thz(0.0), 0.0) { ok = false; }
  if !close(spec_ev_to_thz(-3.0), 0.0) { ok = false; }
  if !close(spec_thz_to_ev(0.0), 0.0) { ok = false; }
  if !close(spec_thz_to_ev(-3.0), 0.0) { ok = false; }
  if spec_is_visible(0.0) { ok = false; }
  if spec_is_visible(-400.0) { ok = false; }
  return assert(ok, "guard G1: input <= 0 returns 0.0 in all 8 conversions; not visible");
}

fn t12_ev_thz_roundtrip() -> TestResult {
  var ok = close(spec_thz_to_ev(spec_ev_to_thz(1.0)), 1.0);
  if !close(spec_thz_to_ev(spec_ev_to_thz(2.5)), 2.5) { ok = false; }
  if !close(spec_thz_to_ev(spec_ev_to_thz(0.5)), 0.5) { ok = false; }
  if !close(spec_ev_to_thz(spec_thz_to_ev(604.4973105)), 604.4973105) { ok = false; }
  return assert(ok, "round-trip eV->THz->eV is identity for 0.5/1/2.5 eV");
}

fn t13_ev_to_thz_pinned() -> TestResult {
  var ok = close(spec_ev_to_thz(1.0), 241.7989242);
  if !close(spec_ev_to_thz(2.5), 604.4973105) { ok = false; }
  if !close(spec_ev_to_thz(0.5), 120.8994621) { ok = false; }
  if !close(spec_thz_to_ev(241.7989242), 1.0) { ok = false; }
  return assert(ok, "eV->THz pinned: 1 eV is 241.7989242 THz; THz->eV is the inverse");
}

fn t14_cross_paths_500nm() -> TestResult {
  var ok = close(spec_thz_to_ev(spec_nm_to_thz(500.0)), 2.4796837);
  if !close(spec_ev_to_thz(spec_nm_to_ev(500.0)), 599.584916) { ok = false; }
  if !close(spec_thz_to_nm(spec_nm_to_thz(500.0)), 500.0) { ok = false; }
  if !close(spec_ev_to_nm(spec_nm_to_ev(500.0)), 500.0) { ok = false; }
  return assert(ok, "500 nm: the THz, eV and cm^-1 conversion paths agree");
}

fn t15_xray_0p1nm() -> TestResult {
  var ok = close(spec_nm_to_thz(0.1), 2997924.58);
  if !close(spec_nm_to_ev(0.1), 12398.419843) { ok = false; }
  if !close(spec_nm_to_cm_inv(0.1), 1e8) { ok = false; }
  if !band_is(0.1, "UV") { ok = false; }
  return assert(ok, "0.1 nm (X-ray): 2997924.58 THz, 12398.419843 eV, 1e8 cm^-1, UV");
}

fn t16_formula_identity() -> TestResult {
  let c: Float64 = 299792458.0;
  let h: Float64 = 6.62607015e-34;
  let ev_j: Float64 = 1.602176634e-19;
  var ok = close(spec_nm_to_thz(500.0), c / (500.0 * 1e-9) / 1e12);
  if !close(spec_nm_to_ev(500.0), h * c / (500.0 * 1e-9) / ev_j) { ok = false; }
  if !close(spec_ev_to_nm(1.0), h * c / (1.0 * ev_j) / 1e-9) { ok = false; }
  if !close(spec_ev_to_thz(1.0), 1.0 * ev_j / h / 1e12) { ok = false; }
  if !close(spec_thz_to_ev(241.7989242), 241.7989242 * 1e12 * h / ev_j) { ok = false; }
  return assert(ok, "formulas reproduced from c/h/eV literals inside the test");
}

fn main() -> Int {
  io.println("=== xiom.spectroscopy conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_nm_to_thz_500();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_nm_to_ev_500();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_roundtrip_nm_thz();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_roundtrip_nm_ev();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_roundtrip_nm_cm_inv();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_cm_inv_to_nm();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_ev_to_nm();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_is_visible_bounds();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_band_names();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_band_guard_zero_negative();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_guard_nonpositive_all();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_ev_thz_roundtrip();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_ev_to_thz_pinned();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_cross_paths_500nm();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_xray_0p1nm();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_formula_identity();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.spectroscopy: all tests passed");
  } else {
    io.println("xiom.spectroscopy: tests failed");
  }
  return failed;
}
