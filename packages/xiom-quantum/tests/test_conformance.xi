// XIOM -- xiom.quantum conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.quantum module (introductory quantum
// formulas) against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected value is a pinned decimal result of the documented formulas
// (SPEC.md section 5), compared with a relative tolerance through q_close():
//
//   q_close(a, b) := fabs(a - b) <= 1e-9 * fabs(b)
//
// where b is the expected value. The tolerance is purely relative, with no
// absolute floor: expected 0.0 values must be exactly 0.0, which holds
// because every guard returns the literal 0.0, so a guard that stopped
// firing (or a formula that produced a tiny non-zero) would fail. The pinned
// decimals carry 13 or more significant digits, far wider than the ~1e-16
// relative rounding of one double formula but tight enough that a wrong
// constant, a wrong power or a dropped factor fails. fabs is
// xiom.math.abs_float (the raw libm fabs is module-private).
//
// No Str values are compared (only r.name is printed); no Vec at all (in
// particular no Vec[Float64]); no lambdas, structs or methods; every test is
// called explicitly from main (no Vec[fn] dispatch).

module quantum_tests
use xiom.io; use xiom.test; use xiom.quantum; use xiom.math;

// Relative approximate equality: fabs(a - b) <= 1e-9 * fabs(b).
// Expected 0.0 therefore requires an exact 0.0 (guards return 0.0).
fn q_close(a: Float64, b: Float64) -> Bool {
  return xiom.math.abs_float(a - b) <= 0.000000001 * xiom.math.abs_float(b);
}

// -- de Broglie wavelength --

fn t01_de_broglie_electron() -> TestResult {
  var ok = q_close(quantum_de_broglie_m(QUANTUM_M_E_KG, 1e6), 7.2738951032537087e-10);
  if !q_close(quantum_de_broglie_m(QUANTUM_M_E_KG, 2e6) * 2.0, quantum_de_broglie_m(QUANTUM_M_E_KG, 1e6)) { ok = false; }
  if !q_close(quantum_de_broglie_m(1.0, 1.0), 6.62607015e-34) { ok = false; }
  return assert(ok, "de Broglie: electron at 1e6 m/s -> 7.2738951e-10 m; 1 kg at 1 m/s -> h");
}

fn t02_de_broglie_guards() -> TestResult {
  var ok = q_close(quantum_de_broglie_m(0.0, 1e6), 0.0);
  if !q_close(quantum_de_broglie_m(-1.0, 1e6), 0.0) { ok = false; }
  if !q_close(quantum_de_broglie_m(QUANTUM_M_E_KG, 0.0), 0.0) { ok = false; }
  if !q_close(quantum_de_broglie_m(QUANTUM_M_E_KG, -1e6), 0.0) { ok = false; }
  if !q_close(quantum_de_broglie_m(0.0, 0.0), 0.0) { ok = false; }
  return assert(ok, "de Broglie guard G1: mass_kg <= 0 or velocity_m_s <= 0 returns 0.0");
}

// -- Photon momentum --

fn t03_photon_momentum_1ev() -> TestResult {
  var ok = q_close(quantum_photon_momentum(1.602176634e-19), 5.3442859926783079e-28);
  if !q_close(quantum_photon_momentum(2.0 * 1.602176634e-19), 2.0 * 5.3442859926783079e-28) { ok = false; }
  if !q_close(quantum_photon_momentum(3.0 * 1.602176634e-19) / 3.0, 5.3442859926783079e-28) { ok = false; }
  return assert(ok, "photon momentum: 1 eV -> 5.3442860e-28 kg*m/s; linear in energy");
}

fn t04_photon_momentum_guards() -> TestResult {
  var ok = q_close(quantum_photon_momentum(0.0), 0.0);
  if !q_close(quantum_photon_momentum(-1.602176634e-19), 0.0) { ok = false; }
  if !q_close(quantum_photon_momentum(-1.0), 0.0) { ok = false; }
  return assert(ok, "photon momentum guard G1: energy_j <= 0 returns 0.0");
}

// -- Hydrogen levels and transitions --

fn t05_hydrogen_levels() -> TestResult {
  var ok = q_close(quantum_hydrogen_energy_ev(1), -13.605693122994);
  if !q_close(quantum_hydrogen_energy_ev(2), -3.4014232807485) { ok = false; }
  if !q_close(quantum_hydrogen_energy_ev(3), -1.5117436803326667) { ok = false; }
  if !q_close(quantum_hydrogen_energy_ev(10), -0.13605693122994) { ok = false; }
  return assert(ok, "hydrogen levels: E1 = -13.605693 eV; E2 = -3.4014233 eV; E10 = -0.13605693 eV");
}

fn t06_hydrogen_energy_guards() -> TestResult {
  var ok = q_close(quantum_hydrogen_energy_ev(0), 0.0);
  if !q_close(quantum_hydrogen_energy_ev(-1), 0.0) { ok = false; }
  if !q_close(quantum_hydrogen_energy_ev(-100), 0.0) { ok = false; }
  return assert(ok, "hydrogen energy guard G2: n < 1 returns 0.0");
}

fn t07_transition_2to1() -> TestResult {
  var ok = q_close(quantum_hydrogen_transition_ev(2, 1), 10.2042698422455);
  if !q_close(quantum_hydrogen_transition_ev(3, 1), 12.093949442661332) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(3, 2), 1.8896796004158334) { ok = false; }
  return assert(ok, "transitions: 2->1 = 10.204270 eV; 3->1 = 12.093949 eV; 3->2 = 1.8896796 eV");
}

fn t08_transition_guards() -> TestResult {
  var ok = q_close(quantum_hydrogen_transition_ev(1, 1), 0.0);
  if !q_close(quantum_hydrogen_transition_ev(2, 2), 0.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(2, 3), 0.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(3, 5), 0.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(1, 0), 0.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(1, -2), 0.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(0, -1), 0.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(-3, -4), 0.0) { ok = false; }
  return assert(ok, "transition guard G2: n_to < 1 or n_from <= n_to returns 0.0");
}

// -- Balmer and Lyman wavelengths --

fn t09_balmer_halpha() -> TestResult {
  var ok = q_close(quantum_balmer_wavelength_nm(3), 656.1122764193188);
  if !q_close(quantum_balmer_wavelength_nm(4), 486.0090936439399) { ok = false; }
  if !q_close(quantum_balmer_wavelength_nm(5), 433.9366907535178) { ok = false; }
  return assert(ok, "Balmer: H-alpha (n = 3) = 656.11228 nm; H-beta 486.00909; H-gamma 433.93669");
}

fn t10_balmer_guards() -> TestResult {
  var ok = q_close(quantum_balmer_wavelength_nm(2), 0.0);
  if !q_close(quantum_balmer_wavelength_nm(1), 0.0) { ok = false; }
  if !q_close(quantum_balmer_wavelength_nm(0), 0.0) { ok = false; }
  if !q_close(quantum_balmer_wavelength_nm(-1), 0.0) { ok = false; }
  if !q_close(quantum_balmer_wavelength_nm(-10), 0.0) { ok = false; }
  return assert(ok, "Balmer guard G2: n <= 2 returns 0.0 (no Balmer line, no division by zero)");
}

fn t11_lyman_alpha() -> TestResult {
  var ok = q_close(quantum_lyman_wavelength_nm(2), 121.502273410985);
  if !q_close(quantum_lyman_wavelength_nm(3), 102.5175431905186) { ok = false; }
  if !q_close(quantum_lyman_wavelength_nm(4), 97.201818728788) { ok = false; }
  return assert(ok, "Lyman: Lyman-alpha (n = 2) = 121.50227 nm; n = 3 = 102.51754; n = 4 = 97.201819");
}

fn t12_lyman_guards() -> TestResult {
  var ok = q_close(quantum_lyman_wavelength_nm(1), 0.0);
  if !q_close(quantum_lyman_wavelength_nm(0), 0.0) { ok = false; }
  if !q_close(quantum_lyman_wavelength_nm(-1), 0.0) { ok = false; }
  if !q_close(quantum_lyman_wavelength_nm(-100), 0.0) { ok = false; }
  return assert(ok, "Lyman guard G2: n <= 1 returns 0.0 (no Lyman line, no division by zero)");
}

// -- Reference lengths and exported constants --

fn t13_reference_lengths() -> TestResult {
  var ok = q_close(quantum_compton_wavelength_m(), 2.42631023867e-12);
  if !q_close(quantum_rbohr_m(), 5.29177210903e-11) { ok = false; }
  return assert(ok, "Compton wavelength 2.42631023867e-12 m; Bohr radius 5.29177210903e-11 m");
}

fn t14_constants_pinned() -> TestResult {
  var ok = q_close(QUANTUM_H_J_S, 6.62607015e-34);
  if !q_close(QUANTUM_C_M_PER_S, 299792458.0) { ok = false; }
  if !q_close(QUANTUM_R_INF_PER_M, 1.0973731568160e7) { ok = false; }
  if !q_close(QUANTUM_E1_EV, 13.605693122994) { ok = false; }
  if !q_close(QUANTUM_M_E_KG, 9.1093837015e-31) { ok = false; }
  return assert(ok, "constants pinned: h, c, R_inf, E1 and m_e at their documented values");
}

// -- Identities --

fn t15_hydrogen_identity() -> TestResult {
  var ok = q_close(quantum_hydrogen_energy_ev(1), -13.605693122994 / 1.0);
  if !q_close(quantum_hydrogen_energy_ev(2), -13.605693122994 / 4.0) { ok = false; }
  if !q_close(quantum_hydrogen_energy_ev(3), -13.605693122994 / 9.0) { ok = false; }
  if !q_close(quantum_hydrogen_energy_ev(4), -13.605693122994 / 16.0) { ok = false; }
  if !q_close(quantum_hydrogen_energy_ev(5), -13.605693122994 / 25.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(2, 1), quantum_hydrogen_energy_ev(2) - quantum_hydrogen_energy_ev(1)) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(3, 2), quantum_hydrogen_energy_ev(3) - quantum_hydrogen_energy_ev(2)) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(4, 1), quantum_hydrogen_energy_ev(4) - quantum_hydrogen_energy_ev(1)) { ok = false; }
  return assert(ok, "identity: E_n = E1/n^2 for n = 1..5; transition = E(n_from) - E(n_to)");
}

fn t16_rydberg_consistency() -> TestResult {
  let h: Float64 = 6.62607015e-34;
  let c: Float64 = 299792458.0;
  let ev: Float64 = 1.602176634e-19;
  let r: Float64 = 1.0973731568160e7;
  let balmer3: Float64 = quantum_balmer_wavelength_nm(3);
  let lyman2: Float64 = quantum_lyman_wavelength_nm(2);
  var ok = q_close(1.0 / (balmer3 * 1e-9), r * 0.25 - r / 9.0);
  if !q_close(h * c / (balmer3 * 1e-9) / ev, quantum_hydrogen_transition_ev(3, 2)) { ok = false; }
  if !q_close(1.0 / (lyman2 * 1e-9), r - r / 4.0) { ok = false; }
  if !q_close(h * c / (lyman2 * 1e-9) / ev, quantum_hydrogen_transition_ev(2, 1)) { ok = false; }
  return assert(ok, "Rydberg consistency: 1/lambda = R*(...); h*c/lambda equals the transition energy");
}

fn t17_formula_identity() -> TestResult {
  let h: Float64 = 6.62607015e-34;
  let c: Float64 = 299792458.0;
  let r: Float64 = 1.0973731568160e7;
  let e1: Float64 = 13.605693122994;
  var ok = q_close(quantum_de_broglie_m(2.0, 3.0), h / (2.0 * 3.0));
  if !q_close(quantum_photon_momentum(2.5e-19), 2.5e-19 / c) { ok = false; }
  if !q_close(quantum_hydrogen_energy_ev(4), -e1 / 16.0) { ok = false; }
  if !q_close(quantum_hydrogen_transition_ev(4, 2), e1 * (1.0 / 4.0 - 1.0 / 16.0)) { ok = false; }
  if !q_close(quantum_balmer_wavelength_nm(4), 1e9 / (r * (0.25 - 1.0 / 16.0))) { ok = false; }
  if !q_close(quantum_lyman_wavelength_nm(3), 1e9 / (r * (1.0 - 1.0 / 9.0))) { ok = false; }
  return assert(ok, "formulas reproduced from h/c/R/E1 literals inside the test");
}

fn t18_series_ordering() -> TestResult {
  var ok = quantum_balmer_wavelength_nm(6) < quantum_balmer_wavelength_nm(5);
  if !(quantum_balmer_wavelength_nm(5) < quantum_balmer_wavelength_nm(4)) { ok = false; }
  if !(quantum_balmer_wavelength_nm(4) < quantum_balmer_wavelength_nm(3)) { ok = false; }
  if !(quantum_lyman_wavelength_nm(5) < quantum_lyman_wavelength_nm(4)) { ok = false; }
  if !(quantum_lyman_wavelength_nm(3) < quantum_lyman_wavelength_nm(2)) { ok = false; }
  if !(quantum_lyman_wavelength_nm(2) < quantum_balmer_wavelength_nm(3)) { ok = false; }
  return assert(ok, "series ordering: wavelength decreases with n; Lyman sits below Balmer");
}

fn main() -> Int {
  io.println("=== xiom.quantum conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_de_broglie_electron();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_de_broglie_guards();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_photon_momentum_1ev();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_photon_momentum_guards();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_hydrogen_levels();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_hydrogen_energy_guards();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_transition_2to1();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_transition_guards();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_balmer_halpha();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_balmer_guards();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_lyman_alpha();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_lyman_guards();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_reference_lengths();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_constants_pinned();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_hydrogen_identity();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_rydberg_consistency();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_formula_identity();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_series_ordering();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.quantum: all tests passed");
  } else {
    io.println("xiom.quantum: tests failed");
  }
  return failed;
}
