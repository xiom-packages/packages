// XIOM -- xiom.mechanics conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.mechanics module against its documented
// fixed-point contract (scale 1e-4, no floats, no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every expected value below is hand-computed from the SPEC.md recurrences at
// raw scale 10000 and pinned exactly (fixture-driven, no random inputs). All
// Str equality goes through compare.str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison on the pinned compiler, so
// every error-message check is routed through streq instead of `==`. No
// Vec[StructType], no fn tables: every test is called explicitly from main.

module mechanics_tests
use xiom.io; use xiom.test; use xiom.mechanics;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Raw fixed-point value: fx(2) is the raw encoding of 2.0 (2 * 10000).
fn fx(v: Int) -> Int {
  return v * MECH_SCALE;
}

fn p_of(r: Result[Particle, Str]) -> Particle {
  match r {
    Ok(p) => { return p; },
    Err(_) => { return Particle{ x: 0; v: 0 }; },
  }
  return Particle{ x: 0; v: 0 };
}

fn pair_of(r: Result[CollisionPair, Str]) -> CollisionPair {
  match r {
    Ok(p) => { return p; },
    Err(_) => { return CollisionPair{ u1: 0; u2: 0 }; },
  }
  return CollisionPair{ u1: 0; u2: 0 };
}

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn bool_of(r: Result[Bool, Str]) -> Bool {
  match r {
    Ok(b) => { return b; },
    Err(_) => { return false; },
  }
  return false;
}

fn p_err(r: Result[Particle, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn pair_err(r: Result[CollisionPair, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
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

fn bool_err(r: Result[Bool, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// -- Constants and particle state -------------------------------------------

fn t1() -> TestResult {
  var ok = MECH_SCALE == 10000;
  if MECH_BPS_ONE != 10000 { ok = false; }
  if MECH_MAX_TICKS != 1000000 { ok = false; }
  let p = mech_particle_new(fx(2), fx(0) - fx(1));
  if p.x != fx(2) { ok = false; }
  if p.v != fx(0) - fx(1) { ok = false; }
  return assert(ok, "scale is 1e-4; particle_new stores raw position and velocity");
}

// -- Integration exactness ---------------------------------------------------

fn t2() -> TestResult {
  // p = (0 m, 1 m/s), a = 2 m/s^2, dt = 0.5 s.
  // v1 = 10000 + mul(20000, 5000) = 20000; x1 = 0 + mul(20000, 5000) = 10000.
  // Explicit Euler would leave x1 = 5000: the tick uses the NEW velocity.
  let p0 = mech_particle_new(0, fx(1));
  let p1 = p_of(mech_particle_step(p0, fx(2), 5000));
  var ok = p1.v == fx(2);
  if p1.x != fx(1) { ok = false; }
  return assert(ok, "one semi-implicit tick: x = 1 m (not 0.5), v = 2 m/s");
}

fn t3() -> TestResult {
  // Second tick: v2 = 20000 + 10000 = 30000; x2 = 10000 + mul(30000, 5000)
  // = 25000 (2.5 m), the documented discrete drift from the analytic 2 m.
  let p0 = mech_particle_new(0, fx(1));
  let p1 = p_of(mech_particle_step(p0, fx(2), 5000));
  let p2 = p_of(mech_particle_step(p1, fx(2), 5000));
  var ok = p2.v == fx(3);
  if p2.x != fx(2) + 5000 { ok = false; }
  return assert(ok, "two semi-implicit ticks: x = 2.5 m, v = 3 m/s hand-computed");
}

fn t4() -> TestResult {
  let p0 = mech_particle_new(fx(1), fx(1));
  var ok = p_err(mech_particle_step(p0, fx(2), 0), "mechanics: dt must be positive");
  if !p_err(mech_particle_step(p0, fx(2), fx(0) - 5000), "mechanics: dt must be positive") { ok = false; }
  return assert(ok, "particle_step guards: dt <= 0 is rejected");
}

fn t5() -> TestResult {
  // step_n applies exactly the mech_particle_step recurrence n times.
  let p0 = mech_particle_new(0, fx(1));
  let p2 = p_of(mech_particle_step_n(p0, fx(2), 5000, 2));
  var ok = p2.x == 25000;
  if p2.v != fx(3) { ok = false; }
  let same = p_of(mech_particle_step_n(p0, fx(2), 5000, 0));
  if same.x != 0 { ok = false; }
  if same.v != fx(1) { ok = false; }
  if !p_err(mech_particle_step_n(p0, fx(2), 5000, 0 - 1), "mechanics: tick count out of range") { ok = false; }
  if !p_err(mech_particle_step_n(p0, fx(2), 5000, MECH_MAX_TICKS + 1), "mechanics: tick count out of range") { ok = false; }
  return assert(ok, "step_n: 2 ticks match two steps, 0 ticks is identity, out-of-range rejected");
}

fn t6() -> TestResult {
  // Free fall, g = 10 m/s^2, dt = 1 s, three ticks from rest:
  // v = 10, 20, 30; x = 10, 30, 60 m (a*dt^2*n*(n+1)/2 = 10*6).
  let p = p_of(mech_particle_step_n(mech_particle_new(0, 0), fx(10), fx(1), 3));
  var ok = p.v == fx(30);
  if p.x != fx(60) { ok = false; }
  return assert(ok, "free fall 3 ticks at g = 10: x = 60 m, v = 30 m/s");
}

// -- Projectile range and apex ----------------------------------------------

fn t7() -> TestResult {
  // v0y = 20 m/s, g = 10 m/s^2: apex rise = 400/20 = 20 m.
  let y0 = int_of(mech_projectile_apex(0, fx(20), fx(10)));
  let y1 = int_of(mech_projectile_apex(fx(5), fx(20), fx(10)));
  var ok = y0 == fx(20);
  if y1 != fx(25) { ok = false; }
  if !int_err(mech_projectile_apex(0, fx(20), 0), "mechanics: gravity must be positive") { ok = false; }
  if !int_err(mech_projectile_apex(0, fx(20), fx(0) - fx(10)), "mechanics: gravity must be positive") { ok = false; }
  return assert(ok, "apex: 20 m rise from 20 m/s at g = 10; launch height offset kept; g <= 0 rejected");
}

fn t8() -> TestResult {
  // v0x = 30 m/s, v0y = 20 m/s, g = 10 m/s^2: t_flight = 4 s, range = 120 m.
  let x0 = int_of(mech_projectile_range(0, fx(30), fx(20), fx(10)));
  let x1 = int_of(mech_projectile_range(fx(1), fx(30), fx(20), fx(10)));
  var ok = x0 == fx(120);
  if x1 != fx(121) { ok = false; }
  if !int_err(mech_projectile_range(0, fx(30), fx(20), 0), "mechanics: gravity must be positive") { ok = false; }
  return assert(ok, "range: t_flight = 4 s, 30 m/s * 4 s = 120 m; x0 offset kept");
}

// -- 1D collisions -----------------------------------------------------------

fn t9() -> TestResult {
  // Equal masses swap velocities elastically.
  let a = pair_of(mech_collide_elastic_1d(fx(1), fx(2), fx(1), fx(0) - fx(1)));
  var ok = a.u1 == fx(0) - fx(1);
  if a.u2 != fx(2) { ok = false; }
  let b = pair_of(mech_collide_elastic_1d(fx(2), fx(3), fx(2), fx(1)));
  if b.u1 != fx(1) { ok = false; }
  if b.u2 != fx(3) { ok = false; }
  return assert(ok, "elastic equal masses: (2, -1) -> (-1, 2) and (3, 1) -> (1, 3)");
}

fn t10() -> TestResult {
  // 3 kg at 2 m/s hits 1 kg at rest: u1 = (3-1)/4 * 2 = 1, u2 = 6/4 * 2 = 3.
  let c = pair_of(mech_collide_elastic_1d(fx(3), fx(2), fx(1), 0));
  var ok = c.u1 == fx(1);
  if c.u2 != fx(3) { ok = false; }
  return assert(ok, "elastic unequal masses: u1 = 1 m/s, u2 = 3 m/s hand-computed");
}

fn t11() -> TestResult {
  // Perfectly inelastic: both leave at the centre-of-mass velocity.
  // (1 kg, 2 m/s) with (1 kg, -1 m/s) -> 0.5 m/s each.
  // (1 kg, 1 m/s) with (3 kg, 2 m/s) -> 7/4 = 1.75 m/s each.
  let d = pair_of(mech_collide_inelastic_1d(fx(1), fx(2), fx(1), fx(0) - fx(1)));
  var ok = d.u1 == 5000;
  if d.u2 != 5000 { ok = false; }
  let e = pair_of(mech_collide_inelastic_1d(fx(1), fx(1), fx(3), fx(2)));
  if e.u1 != 17500 { ok = false; }
  if e.u2 != 17500 { ok = false; }
  return assert(ok, "inelastic: (2, -1) -> 0.5 m/s each; (1, 2) with 3 kg -> 1.75 m/s each");
}

fn t12() -> TestResult {
  // Equal masses, restitution 0.5 and 0.25, second body at rest:
  // e = 0.5: u1 = 0.5 m/s, u2 = 1.5 m/s; e = 0.25: u1 = 0.75, u2 = 1.25.
  let f = pair_of(mech_collide_1d(fx(1), fx(2), fx(1), 0, 5000));
  var ok = f.u1 == 5000;
  if f.u2 != 15000 { ok = false; }
  let g = pair_of(mech_collide_1d(fx(1), fx(2), fx(1), 0, 2500));
  if g.u1 != 7500 { ok = false; }
  if g.u2 != 12500 { ok = false; }
  return assert(ok, "restitution in bps: 5000 -> (0.5, 1.5), 2500 -> (0.75, 1.25) m/s");
}

fn t13() -> TestResult {
  var ok = pair_err(mech_collide_1d(0, fx(1), fx(1), 0, 10000), "mechanics: mass must be positive");
  if !pair_err(mech_collide_1d(fx(1), fx(1), 0 - 1, 0, 10000), "mechanics: mass must be positive") { ok = false; }
  if !pair_err(mech_collide_1d(fx(1), fx(1), fx(1), 0, 0 - 1), "mechanics: restitution must be in 0..10000 bps") { ok = false; }
  if !pair_err(mech_collide_1d(fx(1), fx(1), fx(1), 0, 10001), "mechanics: restitution must be in 0..10000 bps") { ok = false; }
  if !pair_err(mech_collide_elastic_1d(0, fx(1), fx(1), 0), "mechanics: mass must be positive") { ok = false; }
  return assert(ok, "collision guards: non-positive mass and restitution outside 0..10000 rejected");
}

// -- Momentum and energy accounting -----------------------------------------

fn t14() -> TestResult {
  var ok = mech_momentum(fx(2), fx(3)) == fx(6);
  if mech_momentum(fx(2), fx(0) - fx(3)) != fx(0) - fx(6) { ok = false; }
  if mech_momentum_total2(fx(1), fx(2), fx(1), fx(0) - fx(1)) != fx(1) { ok = false; }
  if !bool_of(mech_momentum_conserved(fx(1), fx(2), fx(1), fx(0) - fx(1), 10000)) { ok = false; }
  if !bool_of(mech_momentum_conserved(fx(1), fx(2), fx(1), fx(0) - fx(1), 5000)) { ok = false; }
  if !bool_err(mech_momentum_conserved(0, fx(1), fx(1), 0, 10000), "mechanics: mass must be positive") { ok = false; }
  return assert(ok, "momentum: p = m*v signed, total is conserved by elastic and 0.5 collisions");
}

fn t15() -> TestResult {
  var ok = int_of(mech_kinetic_energy(fx(2), fx(3))) == fx(9);
  if int_of(mech_kinetic_energy(fx(1), fx(0) - fx(2))) != fx(2) { ok = false; }
  if int_of(mech_kinetic_energy(0, fx(3))) != 0 { ok = false; }
  if !int_err(mech_kinetic_energy(fx(0) - fx(1), fx(3)), "mechanics: mass must be non-negative") { ok = false; }
  return assert(ok, "kinetic energy: 2 kg at 3 m/s = 9 J; v squared, signed v kept positive; m < 0 rejected");
}

fn t16() -> TestResult {
  var ok = mech_potential_energy(fx(2), fx(10), fx(3)) == fx(60);
  if mech_potential_energy(fx(1), fx(10), fx(0) - fx(2)) != fx(0) - fx(20) { ok = false; }
  if mech_work(fx(5), fx(0) - fx(2)) != fx(0) - fx(10) { ok = false; }
  if mech_work(fx(0) - fx(3), fx(2)) != fx(0) - fx(6) { ok = false; }
  if mech_energy_total(fx(9), fx(6)) != fx(15) { ok = false; }
  return assert(ok, "potential energy and work are signed; energy_total sums the accounts");
}

// -- Spring-damper -----------------------------------------------------------

fn t17() -> TestResult {
  // k = 4 N/m, m = 1 kg: omega^2 = 4, so the symplectic bound is dt <= 1 s.
  var ok = mech_spring_stable(fx(4), fx(1), 5000);
  if !mech_spring_stable(fx(4), fx(1), fx(1)) { ok = false; }
  if mech_spring_stable(fx(4), fx(1), 15000) { ok = false; }
  if !mech_spring_stable(0, fx(1), fx(1)) { ok = false; }
  if mech_spring_stable(fx(0) - fx(4), fx(1), fx(1)) { ok = false; }
  if mech_spring_stable(fx(4), 0, fx(1)) { ok = false; }
  if mech_spring_stable(fx(4), fx(1), 0) { ok = false; }
  return assert(ok, "stability guard: dt^2*k/m <= 4 accepted, boundary dt = 1 s stable, 1.5 s unstable");
}

fn t18() -> TestResult {
  // Undamped: x = 1 m, v = 0, k = 4, m = 1, dt = 0.5 s.
  // a = -4; v1 = -2; x1 = 1 + (-2)*0.5 = 0.
  let u = p_of(mech_spring_step(fx(1), 0, fx(4), 0, fx(1), 5000));
  var ok = u.x == 0;
  if u.v != fx(0) - fx(2) { ok = false; }
  // Damped: x = 1, v = 2, c = 1: force = -4 - 2 = -6, a = -6,
  // v1 = 2 - 3 = -1, x1 = 1 - 0.5 = 0.5 m.
  let w = p_of(mech_spring_step(fx(1), fx(2), fx(4), fx(1), fx(1), 5000));
  if w.x != 5000 { ok = false; }
  if w.v != fx(0) - fx(1) { ok = false; }
  if !p_err(mech_spring_step(fx(1), 0, fx(4), 0, 0, 5000), "mechanics: mass must be positive") { ok = false; }
  if !p_err(mech_spring_step(fx(1), 0, fx(0) - fx(4), 0, fx(1), 5000), "mechanics: stiffness must be non-negative") { ok = false; }
  if !p_err(mech_spring_step(fx(1), 0, fx(4), fx(0) - fx(1), fx(1), 5000), "mechanics: damping must be non-negative") { ok = false; }
  if !p_err(mech_spring_step(fx(1), 0, fx(4), 0, fx(1), 0), "mechanics: dt must be positive") { ok = false; }
  if !p_err(mech_spring_step(fx(1), 0, fx(4), 0, fx(1), 15000), "mechanics: unstable step: dt^2*k/m exceeds 4") { ok = false; }
  return assert(ok, "spring_step: undamped (0, -2), damped (0.5, -1) hand-computed; all five guards pinned");
}

fn t19() -> TestResult {
  // x = 1 m, v = 2 m/s, k = 4 N/m, m = 1 kg: PE = 2 J, KE = 2 J, total 4 J.
  var ok = int_of(mech_spring_energy(fx(1), fx(2), fx(4), fx(1))) == fx(4);
  if int_of(mech_spring_energy(fx(1), 0, fx(4), fx(1))) != fx(2) { ok = false; }
  if int_of(mech_spring_energy(fx(1), fx(2), fx(4), 0)) != fx(2) { ok = false; }
  if !int_err(mech_spring_energy(fx(1), fx(2), fx(0) - fx(4), fx(1)), "mechanics: stiffness must be non-negative") { ok = false; }
  if !int_err(mech_spring_energy(fx(1), fx(2), fx(4), fx(0) - fx(1)), "mechanics: mass must be non-negative") { ok = false; }
  return assert(ok, "spring energy: 1 m + 2 m/s at k = 4, m = 1 is 4 J (2 J + 2 J); negative k/m rejected");
}

fn t20() -> TestResult {
  // Energy across one undamped tick: E(1 m, 0) = 2 J and E(0, -2 m/s) = 2 J.
  // The damped tick leaves (0.5 m, -1 m/s): 0.5 J + 0.5 J = 1 J < 2 J.
  let e0 = int_of(mech_spring_energy(fx(1), 0, fx(4), fx(1)));
  let e1 = int_of(mech_spring_energy(0, fx(0) - fx(2), fx(4), fx(1)));
  let e2 = int_of(mech_spring_energy(5000, fx(0) - fx(1), fx(4), fx(1)));
  var ok = e0 == fx(2);
  if e1 != fx(2) { ok = false; }
  if e2 != fx(1) { ok = false; }
  if e2 >= e0 { ok = false; }
  return assert(ok, "undamped spring energy is invariant across the tick; damping dissipates it");
}

fn t21() -> TestResult {
  var ok = bool_of(mech_invariants_hold(fx(3), fx(2), fx(1), 0, 10000));
  if !bool_of(mech_invariants_hold(fx(1), fx(2), fx(1), fx(0) - fx(1), 0)) { ok = false; }
  if !bool_of(mech_invariants_hold(fx(1), fx(2), fx(1), 0, 5000)) { ok = false; }
  if !bool_err(mech_invariants_hold(fx(1), fx(2), fx(1), 0, 10001), "mechanics: restitution must be in 0..10000 bps") { ok = false; }
  return assert(ok, "invariants: momentum, energy and relative speed hold for elastic and inelastic collisions");
}

fn t22() -> TestResult {
  // Full audit of the 3 kg (2 m/s) vs 1 kg (0) elastic fixture:
  // u = (1, 3); p = 6 before and after; E_k = 6 J before and after.
  let c = pair_of(mech_collide_elastic_1d(fx(3), fx(2), fx(1), 0));
  let p_before = mech_momentum_total2(fx(3), fx(2), fx(1), 0);
  let p_after = mech_momentum_total2(fx(3), c.u1, fx(1), c.u2);
  let ke_before = int_of(mech_kinetic_energy(fx(3), fx(2)));
  let ke_after = mech_energy_total(int_of(mech_kinetic_energy(fx(3), fx(1))), int_of(mech_kinetic_energy(fx(1), fx(3))));
  var ok = c.u1 == fx(1);
  if c.u2 != fx(3) { ok = false; }
  if p_before != fx(6) { ok = false; }
  if p_after != p_before { ok = false; }
  if ke_before != fx(6) { ok = false; }
  if ke_after != ke_before { ok = false; }
  return assert(ok, "elastic audit: momentum 6 and kinetic energy 6 J are exactly conserved");
}

fn t23() -> TestResult {
  // Four free-fall ticks at g = 10, dt = 1: x = 10+20+30+40 = 100 m, v = 40.
  let p = p_of(mech_particle_step_n(mech_particle_new(0, 0), fx(10), fx(1), 4));
  var ok = p.x == fx(100);
  if p.v != fx(40) { ok = false; }
  return assert(ok, "four-tick free fall: x = 100 m, v = 40 m/s (n(n+1)/2 law)");
}

fn t24() -> TestResult {
  // The bps wrappers are exactly the generic collision at 10000 and 0 bps.
  let a = pair_of(mech_collide_1d(fx(2), fx(1), fx(3), fx(0) - fx(2), 10000));
  let b = pair_of(mech_collide_elastic_1d(fx(2), fx(1), fx(3), fx(0) - fx(2)));
  let c = pair_of(mech_collide_1d(fx(2), fx(1), fx(3), fx(0) - fx(2), 0));
  let d = pair_of(mech_collide_inelastic_1d(fx(2), fx(1), fx(3), fx(0) - fx(2)));
  var ok = a.u1 == b.u1;
  if a.u2 != b.u2 { ok = false; }
  if c.u1 != d.u1 { ok = false; }
  if c.u2 != d.u2 { ok = false; }
  return assert(ok, "elastic/inelastic wrappers equal the generic collision at 10000/0 bps");
}

fn main() -> Int {
  io.println("=== xiom.mechanics conformance tests ===");
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
    io.println("xiom.mechanics: all tests passed");
  } else {
    io.println("xiom.mechanics: tests failed");
  }
  return failed;
}
