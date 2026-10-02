// XIOM -- xiom.nuclear conformance tests (27 checks)
// Port task: prove the pure-XIOM xiom.nuclear module (decay, fission/fusion
// Q-values, isotope table, cross sections, radiation dose) against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected value is an exact integer result of the documented formulas
// and stored dataset (SPEC.md sections 4-9), pinned independently of the
// module. The primary decay fixture is a 1 mg pure U-235 sample
// (10^6 ng, M = 235 g/mol, t1/2 = 22216550400000000 s), which exercises the
// whole decay chain: atoms -> activity -> remaining fraction. All Str equality
// goes through str_compare (BUG-17 discipline); no Vec[fn] dispatch -- every
// test is called explicitly from main.

module nuclear_tests
use xiom.io; use xiom.test; use xiom.nuclear;
use xiom.string;
use xiom.string.compare;

// BUG-17 discipline: compare Str results via xiom.string.compare.
fn streql(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Fixture: 1 mg of U-235 (10^6 ng, M = 235).
//   atoms    = 2562613089361000000
//   half-life = 22216550400000000 s (7.04e8 a x 31557600 s/a)
//   activity  = 79 Bq (N / t1/2 = 115, x ln2)

fn t1() -> TestResult {
  var ok = nuc_permille() == 1000;
  if nuc_scale_x1e4() != 10000 { ok = false; }
  if nuc_ln2_x1e6() != 693147 { ok = false; }
  if nuc_avogadro_x1e15() != 602214076 { ok = false; }
  if nuc_seconds_per_year() != 31557600 { ok = false; }
  if nuc_neutron_excess_kev() != 8071 { ok = false; }
  if nuc_fission_energy_per_event_kev() != 202500 { ok = false; }
  return assert(ok, "scale constants: permille, 1e4, ln2, N_A, Julian year, neutron excess, fission energy");
}

fn t2() -> TestResult {
  var ok = nuc_halflives_elapsed(10, 35) == 3;
  if nuc_halflives_elapsed(10, 10) != 1 { ok = false; }
  if nuc_halflives_elapsed(10, 9) != 0 { ok = false; }
  if nuc_halflives_elapsed(10, 0) != 0 { ok = false; }
  if nuc_halflives_elapsed(10, -5) != 0 { ok = false; }
  if nuc_halflives_elapsed(0, 100) != 0 { ok = false; }
  if nuc_halflives_elapsed(-3, 100) != 0 { ok = false; }
  return assert(ok, "halflives elapsed: truncating floor with non-positive guards");
}

fn t3() -> TestResult {
  var ok = nuc_decay_factor_permille(10, 35) == 125;
  if nuc_decay_factor_permille(10, 10) != 500 { ok = false; }
  if nuc_decay_factor_permille(10, 0) != 1000 { ok = false; }
  if nuc_decay_factor_permille(10, -5) != 1000 { ok = false; }
  if nuc_decay_factor_permille(0, 100) != 1000 { ok = false; }
  if nuc_decay_factor_permille(10, 100) != 0 { ok = false; }
  return assert(ok, "decay factor permille: stepwise halving, no-time guard, 0 at 10 half-lives");
}

fn t4() -> TestResult {
  var ok = nuc_remaining_atoms(1000000, 10, 35) == 125000;
  if nuc_remaining_atoms(0, 10, 35) != 0 { ok = false; }
  if nuc_remaining_atoms(-5, 10, 35) != 0 { ok = false; }
  if nuc_remaining_activity_bq(1000, 10, 20) != 250 { ok = false; }
  if nuc_remaining_activity_bq(1000, 10, 0) != 1000 { ok = false; }
  if nuc_remaining_activity_bq(0, 10, 20) != 0 { ok = false; }
  return assert(ok, "remaining atoms/activity: 1e6 -> 125000 after 3.5 half-lives; guards");
}

fn t5() -> TestResult {
  var ok = nuc_decay_constant_per_s_x1e18(1000) == 693147000000000;
  if nuc_decay_constant_per_s_x1e18(0) != 0 { ok = false; }
  if nuc_decay_constant_per_s_x1e18(-1) != 0 { ok = false; }
  if nuc_mean_lifetime_s(1000) != 1442 { ok = false; }
  if nuc_mean_lifetime_s(0) != 0 { ok = false; }
  return assert(ok, "decay constant x1e18 and mean lifetime: 693147e12/t and t/ln2");
}

fn t6() -> TestResult {
  var ok = nuc_atoms_from_mass(1000000, 235) == 2562613089361000000;
  if nuc_atoms_from_mass(0, 235) != 0 { ok = false; }
  if nuc_atoms_from_mass(1000000, 0) != 0 { ok = false; }
  if nuc_atoms_from_mass(-1, 235) != 0 { ok = false; }
  return assert(ok, "atoms from mass: 1 mg U-235 -> 2.562613089361e18 atoms; guards");
}

fn t7() -> TestResult {
  var ok = nuc_mass_from_atoms(2562613089361000000, 235) == 999999;
  if nuc_mass_from_atoms(0, 235) != 0 { ok = false; }
  if nuc_mass_from_atoms(1000000, 0) != 0 { ok = false; }
  return assert(ok, "mass from atoms: inverse recovers 1 mg within the documented 1 ng truncation");
}

fn t8() -> TestResult {
  var ok = nuc_activity_bq(2562613089361000000, 22216550400000000) == 79;
  if nuc_activity_bq(1000000000000, 1000) != 693147000 { ok = false; }
  if nuc_activity_bq(0, 1000) != 0 { ok = false; }
  if nuc_activity_bq(1000, 0) != 0 { ok = false; }
  return assert(ok, "activity: 1 mg U-235 -> 79 Bq; 1e12 atoms at 1000 s -> 693147000 Bq");
}

fn t9() -> TestResult {
  var ok = nuc_q_value_kev(48986, -124299) == 173285;
  if nuc_q_value_kev(100, 100) != 0 { ok = false; }
  if nuc_q_value_kev(50, 80) != -30 { ok = false; }
  return assert(ok, "U-235 fission Q-value: 49 MeV products minus -124.299 MeV -> 173285 keV");
}

fn t10() -> TestResult {
  var ok = nuc_fission_energy_total_kev(3, 202500) == 607500;
  if nuc_fission_energy_total_kev(0, 202500) != 0 { ok = false; }
  if nuc_fission_energy_total_kev(-1, 202500) != 0 { ok = false; }
  if nuc_fission_energy_total_kev(4000000000, 4000000000) != -1 { ok = false; }
  if nuc_fission_energy_per_event_kev() != 202500 { ok = false; }
  return assert(ok, "fission energy total: 3 events -> 607500 keV; overflow guard returns -1");
}

fn t11() -> TestResult {
  var ok = nuc_kev_to_aj(1) == 160;
  if nuc_kev_to_aj(202500) != 32444076 { ok = false; }
  if nuc_kev_to_aj(0) != 0 { ok = false; }
  if nuc_kev_to_aj(-5) != 0 { ok = false; }
  return assert(ok, "keV -> attojoule: 1 keV -> 160 aJ, 202500 keV -> 32444076 aJ (truncated)");
}

fn t12() -> TestResult {
  var ok = nuc_q_value_kev(28086, 10496) == 17590;
  if nuc_q_value_kev(28086, 10496) <= 0 { ok = false; }
  return assert(ok, "D-T fusion Q-value: 28086 - 10496 = 17590 keV (17.59 MeV)");
}

fn t13() -> TestResult {
  var ok = nuc_coulomb_barrier_kev(1, 1, 5) == 288;
  if nuc_coulomb_barrier_kev(2, 1, 5) != 576 { ok = false; }
  if nuc_coulomb_barrier_kev(0, 1, 5) != 0 { ok = false; }
  if nuc_coulomb_barrier_kev(1, 1, 0) != -1 { ok = false; }
  if nuc_coulomb_barrier_kev(-1, 1, 5) != -1 { ok = false; }
  return assert(ok, "Coulomb barrier: 1440 Z1 Z2 / r fm; 288 keV for D-T at 5 fm");
}

fn t14() -> TestResult {
  var ok = nuc_fusion_feasible(1, 1, 5, 288);
  if nuc_fusion_feasible(1, 1, 5, 287) { ok = false; }
  if nuc_fusion_feasible(1, 1, 0, 1000) { ok = false; }
  if !nuc_fusion_feasible(2, 1, 5, 1000) { ok = false; }
  return assert(ok, "fusion feasibility: inclusive barrier boundary; undefined geometry false");
}

fn t15() -> TestResult {
  var ok = nuc_fusion_gain_x1e4(17590, 300) == 586333;
  if nuc_fusion_gain_x1e4(17590, 0) != -1 { ok = false; }
  if nuc_fusion_gain_x1e4(17590, -5) != -1 { ok = false; }
  if nuc_fusion_gain_x1e4(-100, 100) != -10000 { ok = false; }
  return assert(ok, "fusion gain x1e4: 17590/300 -> 586333; non-positive input -1; negative gain");
}

fn t16() -> TestResult {
  var ok = nuc_reaction_feasible_kev(17590);
  if nuc_reaction_feasible_kev(0) { ok = false; }
  if nuc_reaction_feasible_kev(-1) { ok = false; }
  return assert(ok, "reaction feasibility: strict Q > 0, zero is not feasible");
}

fn t17() -> TestResult {
  var ok = streql(nuc_element_symbol(1), "H");
  if !streql(nuc_element_symbol(92), "U") { ok = false; }
  if !streql(nuc_element_symbol(200), "X") { ok = false; }
  if !streql(nuc_isotope_symbol(92, 235), "U-235") { ok = false; }
  if !streql(nuc_isotope_symbol(6, 14), "C-14") { ok = false; }
  if !streql(nuc_isotope_symbol(200, 300), "X-300") { ok = false; }
  return assert(ok, "nuclear notation: element symbols, El-A rendering, X fallback");
}

fn t18() -> TestResult {
  var ok = nuc_isotope_half_life_s(1, 1) == 0;
  if nuc_isotope_half_life_s(6, 14) != 180825048000 { ok = false; }
  if nuc_isotope_half_life_s(92, 235) != 22216550400000000 { ok = false; }
  if nuc_isotope_half_life_s(94, 239) != 760853736000 { ok = false; }
  if nuc_isotope_half_life_s(99, 999) != -1 { ok = false; }
  return assert(ok, "isotope half-lives: stable 0, C-14, U-235, Pu-239 pinned; unknown -1");
}

fn t19() -> TestResult {
  var ok = streql(nuc_isotope_decay_mode(1, 1), "stable");
  if !streql(nuc_isotope_decay_mode(6, 14), "beta-") { ok = false; }
  if !streql(nuc_isotope_decay_mode(92, 235), "alpha") { ok = false; }
  if !streql(nuc_isotope_decay_mode(27, 60), "beta-") { ok = false; }
  if !streql(nuc_isotope_decay_mode(99, 999), "unknown") { ok = false; }
  return assert(ok, "decay modes: stable, beta-, alpha and unknown from the built-in table");
}

fn t20() -> TestResult {
  var ok = nuc_is_fissile(92, 235);
  if nuc_is_fissile(92, 238) { ok = false; }
  if !nuc_is_fissile(92, 233) { ok = false; }
  if !nuc_is_fissile(94, 239) { ok = false; }
  if nuc_is_fissile(94, 240) { ok = false; }
  return assert(ok, "fissile set: U-233/U-235/Pu-239 yes; U-238/Pu-240 no");
}

fn t21() -> TestResult {
  var ok = nuc_neutron_number(92, 235) == 143;
  if nuc_neutron_number(1, 2) != 1 { ok = false; }
  if nuc_neutron_number(2, 4) != 2 { ok = false; }
  if nuc_neutron_number(5, 3) != 0 { ok = false; }
  return assert(ok, "neutron number N = A - Z; invalid A < Z clamps to 0");
}

fn t22() -> TestResult {
  var ok = nuc_xs_channel_capture() == 1;
  if nuc_xs_channel_fission() != 2 { ok = false; }
  if nuc_xs_channel_scatter() != 3 { ok = false; }
  if nuc_xs_millibarns(5, 10, 1) != 3837000 { ok = false; }
  if nuc_xs_millibarns(1, 1, 1) != 332 { ok = false; }
  if nuc_xs_millibarns(92, 235, 2) != 585000 { ok = false; }
  if nuc_xs_millibarns(92, 238, 3) != 9000 { ok = false; }
  if nuc_xs_millibarns(92, 238, 2) != 0 { ok = false; }
  return assert(ok, "cross sections: channels 1/2/3; B-10, H-1, U-235/U-238 pinned values");
}

fn t23() -> TestResult {
  var ok = nuc_xs_millibarns(99, 999, 1) == -1;
  if nuc_xs_millibarns(5, 10, 9) != -1 { ok = false; }
  if nuc_xs_millibarns(92, 235, 0) != -1 { ok = false; }
  if nuc_xs_millibarns(48, 113, 2) != -1 { ok = false; }
  return assert(ok, "cross sections: unknown isotope/channel sentinel -1 (distinct from tabulated 0)");
}

fn t24() -> TestResult {
  var ok = nuc_macro_xs_per_cm_x1e6(49, 585000) == 28665000;
  if nuc_macro_xs_per_cm_x1e6(0, 585000) != 0 { ok = false; }
  if nuc_macro_xs_per_cm_x1e6(49, 0) != 0 { ok = false; }
  if nuc_macro_xs_per_cm_x1e6(-1, 5) != 0 { ok = false; }
  return assert(ok, "macroscopic cross-section: 4.9e22 /cm3 x 585 b -> 28.665e6 in 1e-6/cm");
}

fn t25() -> TestResult {
  var ok = nuc_mean_free_path_nm(28665000) == 348857;
  if nuc_mean_free_path_nm(0) != -1 { ok = false; }
  if nuc_mean_free_path_nm(-5) != -1 { ok = false; }
  return assert(ok, "mean free path: 1e13 / Sigma -> 348857 nm (~0.35 mm) in U-235");
}

fn t26() -> TestResult {
  var ok = nuc_dose_microgy(1000000, 1, 1000, 3600, 1000) == 576;
  if nuc_dose_microgy(0, 1, 1000, 3600, 1000) != 0 { ok = false; }
  if nuc_dose_microgy(1000000, 1, 0, 3600, 1000) != 0 { ok = false; }
  if nuc_dose_microgy(1000000, 1, 1000, 3600, 0) != -1 { ok = false; }
  if nuc_dose_rate_microgy_per_h(1000000, 1, 1000, 1000) != 576 { ok = false; }
  return assert(ok, "dose: 1 MBq x 1 MeV x 1 h over 1 kg -> 576 uGy; mass guard -1");
}

fn t27() -> TestResult {
  var ok = nuc_hvl_attenuation_permille(10, 25) == 250;
  if nuc_hvl_attenuation_permille(10, 15) != 500 { ok = false; }
  if nuc_hvl_attenuation_permille(10, 0) != 1000 { ok = false; }
  if nuc_hvl_attenuation_permille(0, 5) != 1000 { ok = false; }
  if nuc_hvl_attenuation_permille(10, 100) != 0 { ok = false; }
  return assert(ok, "HVL attenuation: stepwise halves, no-attenuation guards, 0 at 10 HVLs");
}

fn main() -> Int {
  io.println("=== xiom.nuclear conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.nuclear: all tests passed");
  } else {
    io.println("xiom.nuclear: tests failed");
  }
  return failed;
}
