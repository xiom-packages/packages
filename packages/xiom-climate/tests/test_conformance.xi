// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.climate conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.climate module against its documented
// integer fixed-point contract (no floats, no FFI, no I/O in the library).
//
// These tests pin THIS package's documented algorithms, not a GCM or a
// reference dataset: the CO2 response uses the module's 16-segment integer
// log2, the paleotemperature relation is the simplified linear one, and
// every expected value below was computed by hand from the formulas in
// src/climate.xi and SPEC.md with floor semantics, then checked against the
// implementation. All Str equality goes through str_compare, every Vec[Int]
// element read binds a typed local first, and tests are called directly
// from main (no indexed function dispatch).

module climate_tests
use xiom.io; use xiom.test; use xiom.climate;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn int_ok(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn str_ok(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn str_err(r: Result[Str, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn v6(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn empty_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn t1() -> TestResult {
  var ok = climate_solar_const_wm2() == 1361;
  if !int_ok(climate_absorbed_wm2(300), 952) { ok = false; }
  if !int_ok(climate_absorbed_wm2(0), 1361) { ok = false; }
  if !int_ok(climate_absorbed_wm2(1000), 0) { ok = false; }
  if !int_ok(climate_absorbed_wm2(290), 966) { ok = false; }
  return assert(ok, "solar constant 1361 W/m2; absorbed = floor(1361*(1000-albedo)/1000)");
}

fn t2() -> TestResult {
  var ok = int_err(climate_absorbed_wm2(-1), "climate: albedo out of range: -1 permille");
  if !int_err(climate_absorbed_wm2(1001), "climate: albedo out of range: 1001 permille") { ok = false; }
  return assert(ok, "albedo outside 0..1000 is rejected with the exact message");
}

fn t3() -> TestResult {
  var ok = int_ok(climate_equilibrium_warming_centi(560, 280, 300), 300);
  if !int_ok(climate_equilibrium_warming_centi(1120, 280, 300), 600) { ok = false; }
  if !int_ok(climate_equilibrium_warming_centi(140, 280, 300), -300) { ok = false; }
  if !int_ok(climate_equilibrium_warming_centi(280, 280, 300), 0) { ok = false; }
  return assert(ok, "warming is 3.00 degC per CO2 doubling and -3.00 degC per halving");
}

fn t4() -> TestResult {
  var ok = int_ok(climate_equilibrium_warming_centi(420, 280, 300), 175);
  if !int_ok(climate_equilibrium_warming_centi(400, 280, 300), 154) { ok = false; }
  if !int_ok(climate_equilibrium_warming_centi(700, 280, 300), 396) { ok = false; }
  if !int_ok(climate_equilibrium_warming_centi(240, 280, 300), -67) { ok = false; }
  return assert(ok, "piecewise-linear log2 warming: 1.5x -> 175, 400/280 -> 154, 2.5x -> 396, 240/280 -> -67");
}

fn t5() -> TestResult {
  var ok = int_ok(climate_forcing_milli_wm2(560, 280), 3710);
  if !int_ok(climate_forcing_milli_wm2(420, 280), 2170) { ok = false; }
  if !int_ok(climate_forcing_milli_wm2(400, 280), 1906) { ok = false; }
  if !int_ok(climate_forcing_milli_wm2(280, 280), 0) { ok = false; }
  if !int_ok(climate_forcing_milli_wm2(140, 280), -3710) { ok = false; }
  return assert(ok, "forcing = floor(3710*log2(C/C0)/1000) milli-W/m2");
}

fn t6() -> TestResult {
  var ok = int_err(climate_forcing_milli_wm2(0, 280), "climate: co2 out of range: 0 ppm");
  if !int_err(climate_forcing_milli_wm2(560, 0), "climate: base co2 out of range: 0 ppm") { ok = false; }
  if !int_err(climate_equilibrium_warming_centi(560, 280, -1), "climate: ecs out of range: -1 centi-celsius") { ok = false; }
  if !int_err(climate_equilibrium_warming_centi(1000001, 280, 300), "climate: co2 out of range: 1000001 ppm") { ok = false; }
  return assert(ok, "forcing/warming reject out-of-range co2, base and ecs with exact messages");
}

fn t7() -> TestResult {
  var ok = int_ok(climate_relax_step_centi(0, 300, 100), 30);
  if !int_ok(climate_relax_step_centi(300, 0, 500), 150) { ok = false; }
  if !int_ok(climate_relax_step_centi(100, 100, 1000), 100) { ok = false; }
  if !int_ok(climate_relax_step_centi(0, 300, 0), 0) { ok = false; }
  if !int_err(climate_relax_step_centi(0, 300, -1), "climate: relaxation rate out of range: -1 permille") { ok = false; }
  if !int_err(climate_relax_step_centi(0, 300, 1001), "climate: relaxation rate out of range: 1001 permille") { ok = false; }
  if !int_err(climate_relax_step_centi(100001, 0, 100), "climate: temperature out of range: 100001 centi-celsius") { ok = false; }
  return assert(ok, "relax step = current + floor((target-current)*rate/1000); rate and temp validated");
}

fn t8() -> TestResult {
  var ok = int_ok(climate_simulate_centi(0, 300, 100, 5), 121);
  if !int_ok(climate_simulate_centi(300, 300, 100, 10), 300) { ok = false; }
  if !int_ok(climate_simulate_centi(300, 0, 500, 2), 75) { ok = false; }
  if !int_ok(climate_simulate_centi(100, 300, 100, 0), 100) { ok = false; }
  return assert(ok, "simulated relaxation trajectory 0->121 in 5 steps; cooling 300->75 in 2 steps");
}

fn t9() -> TestResult {
  var ok = int_err(climate_simulate_centi(0, 300, 100, -1), "climate: step count out of range: -1");
  if !int_err(climate_simulate_centi(0, 300, 100, 10001), "climate: step count out of range: 10001") { ok = false; }
  if !int_err(climate_simulate_centi(0, 300, 1001, 5), "climate: relaxation rate out of range: 1001 permille") { ok = false; }
  return assert(ok, "step count and rate envelopes are enforced");
}

fn t10() -> TestResult {
  var ok = int_ok(paleo_temp_from_d18o_centi(0), 1690);
  if !int_ok(paleo_temp_from_d18o_centi(100), 1252) { ok = false; }
  if !int_ok(paleo_temp_from_d18o_centi(-100), 2128) { ok = false; }
  if !int_ok(paleo_temp_from_d18o_centi(50), 1471) { ok = false; }
  if !int_ok(paleo_temp_from_d18o_centi(-51), 1914) { ok = false; }
  if !int_ok(paleo_temp_from_d18o_centi(200), 814) { ok = false; }
  return assert(ok, "paleotemperature T = 16.90 - 4.38*d18O with floor rounding (-51 -> 1914)");
}

fn t11() -> TestResult {
  var ok = int_err(paleo_temp_from_d18o_centi(-1001), "climate: d18o out of range: -1001 centi-permille");
  if !int_err(paleo_temp_from_d18o_centi(1001), "climate: d18o out of range: 1001 centi-permille") { ok = false; }
  return assert(ok, "d18O is limited to +-10.00 permille");
}

fn t12() -> TestResult {
  var ok = int_ok(paleo_d18o_from_temp_centi(1690), 0);
  if !int_ok(paleo_d18o_from_temp_centi(1252), 100) { ok = false; }
  if !int_ok(paleo_d18o_from_temp_centi(2128), -100) { ok = false; }
  if !int_ok(paleo_d18o_from_temp_centi(1500), 43) { ok = false; }
  if !int_ok(paleo_d18o_from_temp_centi(3000), -300) { ok = false; }
  if !int_ok(paleo_temp_from_d18o_centi(43), 1502) { ok = false; }
  if !int_ok(paleo_temp_from_d18o_centi(-300), 3004) { ok = false; }
  if !int_err(paleo_d18o_from_temp_centi(5001), "climate: temperature out of range: 5001 centi-celsius") { ok = false; }
  return assert(ok, "inverse paleotemperature floors asymmetrically (1500 -> 43 -> 1502, 3000 -> -300 -> 3004)");
}

fn t13() -> TestResult {
  var ok = int_ok(paleo_age_ka(500, 50), 100);
  if !int_ok(paleo_age_ka(123, 40), 30) { ok = false; }
  if !int_ok(paleo_age_ka(0, 50), 0) { ok = false; }
  if !int_err(paleo_age_ka(-1, 50), "climate: depth out of range: -1 cm") { ok = false; }
  if !int_err(paleo_age_ka(100, 0), "climate: accumulation rate must be positive: 0 mm/ka") { ok = false; }
  if !int_err(paleo_age_ka(100, -5), "climate: accumulation rate must be positive: -5 mm/ka") { ok = false; }
  return assert(ok, "age_ka = floor(depth_cm*10/rate); negative depth and non-positive rates are rejected");
}

fn t14() -> TestResult {
  var ok = str_ok(paleo_climate_phase(-151), "warm interglacial");
  if !str_ok(paleo_climate_phase(-150), "warm interglacial") { ok = false; }
  if !str_ok(paleo_climate_phase(-149), "transitional") { ok = false; }
  if !str_ok(paleo_climate_phase(0), "transitional") { ok = false; }
  if !str_ok(paleo_climate_phase(149), "transitional") { ok = false; }
  if !str_ok(paleo_climate_phase(150), "cold glacial") { ok = false; }
  if !str_ok(paleo_climate_phase(151), "cold glacial") { ok = false; }
  if !str_err(paleo_climate_phase(1001), "climate: d18o out of range: 1001 centi-permille") { ok = false; }
  return assert(ok, "phase boundaries at -150 and +150 centi-permille are inclusive");
}

fn t15() -> TestResult {
  var ok = int_ok(scenarios_co2_linear(280, 2500, 10), 305);
  if !int_ok(scenarios_co2_linear(280, -1000, 10), 270) { ok = false; }
  if !int_ok(scenarios_co2_linear(280, 1234, 3), 283) { ok = false; }
  if !int_err(scenarios_co2_linear(100, -60000, 2), "climate: projected co2 non-positive: -20 ppm") { ok = false; }
  return assert(ok, "linear scenario = start + floor(growth*years/1000), with non-positive projections rejected");
}

fn t16() -> TestResult {
  var ok = int_err(scenarios_co2_linear(0, 1000, 10), "climate: co2 start must be positive: 0 ppm");
  if !int_err(scenarios_co2_linear(280, 1000, -1), "climate: year count out of range: -1") { ok = false; }
  if !int_err(scenarios_co2_linear(280, 1000, 1001), "climate: year count out of range: 1001") { ok = false; }
  if !int_err(scenarios_co2_linear(280, 100001, 10), "climate: growth rate out of range: 100001 milli-ppm/year") { ok = false; }
  return assert(ok, "linear scenario validates start, year count and growth envelope");
}

fn t17() -> TestResult {
  var ok = int_ok(scenarios_co2_compound(280, 100, 10), 300);
  if !int_ok(scenarios_co2_compound(280, 0, 100), 280) { ok = false; }
  if !int_ok(scenarios_co2_compound(1000, -100, 1), 990) { ok = false; }
  if !int_ok(scenarios_co2_compound(500, 10000, 1), 1000) { ok = false; }
  return assert(ok, "compound 1%/year from 280 floors to 300 after 10 years; +100% doubles in one year");
}

fn t18() -> TestResult {
  var ok = int_err(scenarios_co2_compound(0, 100, 10), "climate: co2 start must be positive: 0 ppm");
  if !int_err(scenarios_co2_compound(280, -10000, 10), "climate: growth rate out of range: -10000 bps") { ok = false; }
  if !int_err(scenarios_co2_compound(280, 100, 501), "climate: year count out of range: 501") { ok = false; }
  if !int_err(scenarios_co2_compound(1000000, 100000, 500), "climate: projected co2 exceeds limit: 121000000 ppm") { ok = false; }
  return assert(ok, "compound scenario rejects full-decay rates and stops above the 100M ppm overflow guard");
}

fn t19() -> TestResult {
  var ok = int_ok(scenarios_warming_centi(280, 100, 10, 300), 29);
  if !int_ok(scenarios_warming_centi(280, 100, 10, 0), 0) { ok = false; }
  if !int_ok(scenarios_warming_centi(280, 0, 10, 300), 0) { ok = false; }
  if !int_ok(scenarios_warming_centi(280, -1000, 10, 300), -474) { ok = false; }
  if !int_err(scenarios_warming_centi(280, 100, 10, -1), "climate: ecs out of range: -1 centi-celsius") { ok = false; }
  return assert(ok, "scenario warming floors: 280->300 ppm gives 29 centi-degC; 1%/yr decay gives -474");
}

fn t20() -> TestResult {
  var ok = str_ok(zones_classify(-1, 500000), "EF");
  if !str_ok(zones_classify(0, 500000), "ET") { ok = false; }
  if !str_ok(zones_classify(999, 0), "ET") { ok = false; }
  if !str_ok(zones_classify(1000, 10000), "BW") { ok = false; }
  if !str_ok(zones_classify(1500, 30000), "BS") { ok = false; }
  if !str_ok(zones_classify(1799, 30000), "BS") { ok = false; }
  if !str_ok(zones_classify(1800, 30000), "BW") { ok = false; }
  if !str_ok(zones_classify(2000, 50000), "Aw") { ok = false; }
  if !str_ok(zones_classify(2000, 99999), "Aw") { ok = false; }
  if !str_ok(zones_classify(2000, 100000), "Am") { ok = false; }
  if !str_ok(zones_classify(2000, 199999), "Am") { ok = false; }
  if !str_ok(zones_classify(2000, 200000), "Af") { ok = false; }
  if !str_ok(zones_classify(1799, 99999), "Cs") { ok = false; }
  if !str_ok(zones_classify(1799, 100000), "Cf") { ok = false; }
  return assert(ok, "zone precedence: polar, tropical thresholds at 18.00 degC, arid/temperate precipitation boundaries");
}

fn t21() -> TestResult {
  var ok = str_ok(zones_description("Af"), "tropical rainforest");
  if !str_ok(zones_description("EF"), "polar frost") { ok = false; }
  if !str_ok(zones_description("Cs"), "seasonal temperate") { ok = false; }
  if !str_err(zones_description("Zz"), "climate: unknown zone code: Zz") { ok = false; }
  if !zones_is_arid("BW") { ok = false; }
  if !zones_is_arid("BS") { ok = false; }
  if zones_is_arid("Af") { ok = false; }
  if zones_is_arid("Zz") { ok = false; }
  return assert(ok, "zone descriptions cover all nine codes; only BW/BS are arid");
}

fn t22() -> TestResult {
  var ok = int_ok(trends_mean_centi(&v3(100, 200, 300)), 200);
  if !int_ok(trends_mean_centi(&v2(1, 2)), 1) { ok = false; }
  if !int_ok(trends_mean_centi(&v2(-1, -2)), -2) { ok = false; }
  if !int_ok(trends_mean_centi(&v3(5, 5, 5)), 5) { ok = false; }
  if !int_err(trends_mean_centi(&empty_ints()), "climate: empty series") { ok = false; }
  return assert(ok, "mean floors toward negative infinity ([1,2] -> 1, [-1,-2] -> -2) and rejects empty series");
}

fn t23() -> TestResult {
  var ok = int_ok(trends_linear_trend_centi_per_decade(&v3(100, 110, 120)), 100);
  if !int_ok(trends_linear_trend_centi_per_decade(&v3(300, 200, 100)), -1000) { ok = false; }
  if !int_ok(trends_linear_trend_centi_per_decade(&v4(100, 120, 90, 130)), 60) { ok = false; }
  if !int_ok(trends_linear_trend_centi_per_decade(&v6(0, 0, 1, 0, 0, 0)), -1) { ok = false; }
  if !int_ok(trends_linear_trend_centi_per_decade(&v6(0, 0, 0, 0, 0, 1)), 1) { ok = false; }
  if !int_err(trends_linear_trend_centi_per_decade(&v1(100)), "climate: trend requires at least 2 values") { ok = false; }
  if !int_err(trends_linear_trend_centi_per_decade(&v2(0, 2000000)), "climate: series value out of range: 2000000") { ok = false; }
  return assert(ok, "least-squares slope per decade floors negatives away from zero (-0.29 -> -1) and validates series");
}

fn t24() -> TestResult {
  var ok = int_ok(trends_extrapolate_centi(&v3(100, 110, 120), 5), 170);
  if !int_ok(trends_extrapolate_centi(&v3(100, 110, 120), 0), 120) { ok = false; }
  if !int_ok(trends_extrapolate_centi(&v3(100, 110, 120), 3), 150) { ok = false; }
  if !int_err(trends_extrapolate_centi(&v2(100, 110), 10001), "climate: step count out of range: 10001") { ok = false; }
  if !int_err(trends_extrapolate_centi(&v1(100), 5), "climate: trend requires at least 2 values") { ok = false; }
  if !int_ok(trends_count_above(&v3(100, 200, 150), 150), 1) { ok = false; }
  if !int_ok(trends_count_above(&v4(1, 5, 3, 5), 4), 2) { ok = false; }
  if !int_ok(trends_count_above(&v3(1, 2, 3), 10), 0) { ok = false; }
  if !int_err(trends_count_above(&empty_ints(), 0), "climate: empty series") { ok = false; }
  if !int_ok(trends_precip_anomaly_permille(120000, 100000), 200) { ok = false; }
  if !int_ok(trends_precip_anomaly_permille(80000, 100000), -200) { ok = false; }
  if !int_ok(trends_precip_anomaly_permille(1000, 3000), -667) { ok = false; }
  if !int_ok(trends_precip_anomaly_permille(0, 100000), -1000) { ok = false; }
  if !int_err(trends_precip_anomaly_permille(1000, 0), "climate: normal precipitation must be positive: 0 centi-mm") { ok = false; }
  if !int_err(trends_precip_anomaly_permille(-1, 1000), "climate: observed precipitation out of range: -1 centi-mm") { ok = false; }
  return assert(ok, "extrapolation, strict threshold counts and floored precipitation anomalies (-666.6 -> -667)");
}

fn main() -> Int {
  io.println("=== xiom.climate conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.climate: all tests passed");
  } else {
    io.println("xiom.climate: tests failed");
  }
  return failed;
}
