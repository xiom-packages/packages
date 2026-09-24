// XIOM -- xiom.particle conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.particle module against its documented
// fixed-capacity pool, integer kinematics and slot-lifetime API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module particle_tests
use xiom.io; use xiom.test; use xiom.particle;

// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001), matching the sibling packages' test style.
// ParticlePool keeps parallel Vec[Int] arenas, so no Vec[StructType] is used.

fn cap_of(p: &mut ParticlePool) -> Int {
  return particle_capacity(p);
}

fn alive_of(p: &mut ParticlePool) -> Int {
  return particle_alive_count(p);
}

fn alive_at(p: &mut ParticlePool, i: Int) -> Bool {
  return particle_is_alive(p, i);
}

fn x_of(p: &mut ParticlePool, i: Int) -> Int {
  return particle_x(p, i);
}

fn y_of(p: &mut ParticlePool, i: Int) -> Int {
  return particle_y(p, i);
}

fn life_of(p: &mut ParticlePool, i: Int) -> Int {
  return particle_life_ms(p, i);
}

fn t01_capacity_clamps_to_at_least_one() -> TestResult {
  var zero = particle_pool_new(0);
  var neg = particle_pool_new(-7);
  var five = particle_pool_new(5);
  var ok = cap_of(&mut zero) == 1;
  if cap_of(&mut neg) != 1 { ok = false; }
  if cap_of(&mut five) != 5 { ok = false; }
  return assert(ok, "capacity clamps to at least 1");
}

fn t02_fresh_pool_is_empty() -> TestResult {
  var p = particle_pool_new(4);
  var ok = cap_of(&mut p) == 4;
  if alive_of(&mut p) != 0 { ok = false; }
  var i = 0;
  while i < 4 {
    if alive_at(&mut p, i) { ok = false; }
    i = i + 1;
  }
  if alive_at(&mut p, -1) { ok = false; }
  if alive_at(&mut p, 4) { ok = false; }
  if x_of(&mut p, 0) != 0 { ok = false; }
  if y_of(&mut p, 0) != 0 { ok = false; }
  if life_of(&mut p, 0) != 0 { ok = false; }
  return assert(ok, "fresh pool has no live particles");
}

fn t03_spawn_writes_state_into_slots() -> TestResult {
  var p = particle_pool_new(4);
  let i0 = particle_spawn(&mut p, 100, 200, -30, 40, 500);
  let i1 = particle_spawn(&mut p, -5, 7, 0, 0, 1);
  var ok = i0 == 0;
  if i1 != 1 { ok = false; }
  if alive_of(&mut p) != 2 { ok = false; }
  if !alive_at(&mut p, i0) { ok = false; }
  if x_of(&mut p, i0) != 100 { ok = false; }
  if y_of(&mut p, i0) != 200 { ok = false; }
  if life_of(&mut p, i0) != 500 { ok = false; }
  if !alive_at(&mut p, i1) { ok = false; }
  if x_of(&mut p, i1) != -5 { ok = false; }
  if y_of(&mut p, i1) != 7 { ok = false; }
  if life_of(&mut p, i1) != 1 { ok = false; }
  return assert(ok, "spawn fills the first free slot and stores state");
}

fn t04_spawn_clamps_life_ms() -> TestResult {
  var p = particle_pool_new(2);
  let i = particle_spawn(&mut p, 0, 0, 0, 0, 0);
  var ok = i == 0;
  if life_of(&mut p, i) != 1 { ok = false; }
  particle_update(&mut p, 1);
  if alive_at(&mut p, i) { ok = false; }
  let j = particle_spawn(&mut p, 0, 0, 0, 0, -9);
  if j != 0 { ok = false; }
  if life_of(&mut p, j) != 1 { ok = false; }
  return assert(ok, "spawn clamps life_ms to at least 1");
}

fn t05_full_pool_reports_negative_one() -> TestResult {
  var p = particle_pool_new(2);
  let a = particle_spawn(&mut p, 1, 1, 0, 0, 100);
  let b = particle_spawn(&mut p, 2, 2, 0, 0, 100);
  var ok = a == 0;
  if b != 1 { ok = false; }
  let c = particle_spawn(&mut p, 3, 3, 0, 0, 100);
  if c != -1 { ok = false; }
  if alive_of(&mut p) != 2 { ok = false; }
  if x_of(&mut p, 0) != 1 { ok = false; }
  if x_of(&mut p, 1) != 2 { ok = false; }
  return assert(ok, "a full pool returns -1 and stores nothing");
}

fn t06_kill_live_and_dead_slots() -> TestResult {
  var p = particle_pool_new(2);
  particle_spawn(&mut p, 1, 1, 0, 0, 100);
  particle_spawn(&mut p, 2, 2, 0, 0, 100);
  var ok = particle_kill(&mut p, 0);
  if alive_at(&mut p, 0) { ok = false; }
  if alive_of(&mut p) != 1 { ok = false; }
  if life_of(&mut p, 0) != 0 { ok = false; }
  if particle_kill(&mut p, 0) { ok = false; }
  if alive_of(&mut p) != 1 { ok = false; }
  return assert(ok, "kill clears a live slot and is false on a dead one");
}

fn t07_kill_out_of_range() -> TestResult {
  var p = particle_pool_new(2);
  particle_spawn(&mut p, 1, 1, 0, 0, 100);
  var ok = !particle_kill(&mut p, -1);
  if particle_kill(&mut p, 2) { ok = false; }
  if particle_kill(&mut p, 99) { ok = false; }
  if alive_of(&mut p) != 1 { ok = false; }
  if !alive_at(&mut p, 0) { ok = false; }
  return assert(ok, "kill with an out-of-range index returns false");
}

fn t08_reuses_first_free_slot_after_kill() -> TestResult {
  var p = particle_pool_new(3);
  particle_spawn(&mut p, 1, 1, 0, 0, 100);
  particle_spawn(&mut p, 2, 2, 0, 0, 200);
  particle_spawn(&mut p, 3, 3, 0, 0, 300);
  var ok = particle_kill(&mut p, 1);
  let reused = particle_spawn(&mut p, 4, 4, 0, 0, 400);
  if reused != 1 { ok = false; }
  if x_of(&mut p, 1) != 4 { ok = false; }
  if life_of(&mut p, 1) != 400 { ok = false; }
  let full = particle_spawn(&mut p, 5, 5, 0, 0, 500);
  if full != -1 { ok = false; }
  if alive_of(&mut p) != 3 { ok = false; }
  return assert(ok, "spawn reuses the first killed slot, then reports full");
}

fn t09_reuses_slot_after_expiry() -> TestResult {
  var p = particle_pool_new(2);
  particle_spawn(&mut p, 10, 10, 0, 0, 25);
  particle_spawn(&mut p, 20, 20, 0, 0, 1000);
  particle_update(&mut p, 25);
  var ok = !alive_at(&mut p, 0);
  if !alive_at(&mut p, 1) { ok = false; }
  let reused = particle_spawn(&mut p, 30, 30, 0, 0, 75);
  if reused != 0 { ok = false; }
  if x_of(&mut p, 0) != 30 { ok = false; }
  if life_of(&mut p, 0) != 75 { ok = false; }
  if alive_of(&mut p) != 2 { ok = false; }
  return assert(ok, "an expired slot is reused by the next spawn");
}

fn t10_update_adds_velocity_scaled_by_dt() -> TestResult {
  var p = particle_pool_new(1);
  particle_spawn(&mut p, 1000, -2000, 1500, 2500, 10000);
  particle_update(&mut p, 1000);
  var ok = x_of(&mut p, 0) == 2500;
  if y_of(&mut p, 0) != 500 { ok = false; }
  if life_of(&mut p, 0) != 9000 { ok = false; }
  particle_update(&mut p, 500);
  if x_of(&mut p, 0) != 3250 { ok = false; }
  if y_of(&mut p, 0) != 1750 { ok = false; }
  if life_of(&mut p, 0) != 8500 { ok = false; }
  return assert(ok, "update adds v*dt/1000 to each coordinate");
}

fn t11_truncates_toward_zero() -> TestResult {
  var p = particle_pool_new(4);
  particle_spawn(&mut p, 0, 0, 999, -999, 1000);
  particle_spawn(&mut p, 0, 0, 1500, -1500, 1000);
  particle_spawn(&mut p, 0, 0, -1500, 1500, 1000);
  particle_spawn(&mut p, 0, 0, 2500, -2500, 1000);
  particle_update(&mut p, 1);
  var ok = x_of(&mut p, 0) == 0;
  if y_of(&mut p, 0) != 0 { ok = false; }
  if x_of(&mut p, 1) != 1 { ok = false; }
  if y_of(&mut p, 1) != -1 { ok = false; }
  if x_of(&mut p, 2) != -1 { ok = false; }
  if y_of(&mut p, 2) != 1 { ok = false; }
  if x_of(&mut p, 3) != 2 { ok = false; }
  if y_of(&mut p, 3) != -2 { ok = false; }
  return assert(ok, "v*dt/1000 truncates toward zero for both signs");
}

fn t12_fractional_steps_do_not_carry() -> TestResult {
  var p = particle_pool_new(1);
  particle_spawn(&mut p, 10, 20, 2599, -999, 1000);
  particle_update(&mut p, 3);
  var ok = x_of(&mut p, 0) == 17;
  if y_of(&mut p, 0) != 18 { ok = false; }
  particle_update(&mut p, 1);
  if x_of(&mut p, 0) != 19 { ok = false; }
  if y_of(&mut p, 0) != 18 { ok = false; }
  if life_of(&mut p, 0) != 996 { ok = false; }
  return assert(ok, "each step truncates independently (no fraction carry)");
}

fn t13_life_decrements_each_update() -> TestResult {
  var p = particle_pool_new(1);
  particle_spawn(&mut p, 0, 0, 0, 0, 100);
  particle_update(&mut p, 30);
  var ok = life_of(&mut p, 0) == 70;
  if !alive_at(&mut p, 0) { ok = false; }
  particle_update(&mut p, 40);
  if life_of(&mut p, 0) != 30 { ok = false; }
  particle_update(&mut p, 29);
  if life_of(&mut p, 0) != 1 { ok = false; }
  if !alive_at(&mut p, 0) { ok = false; }
  return assert(ok, "life_ms drops by dt on each update");
}

fn t14_expires_exactly_at_zero() -> TestResult {
  var p = particle_pool_new(1);
  particle_spawn(&mut p, 50, 60, 0, 0, 40);
  particle_update(&mut p, 39);
  var ok = alive_at(&mut p, 0);
  if life_of(&mut p, 0) != 1 { ok = false; }
  particle_update(&mut p, 1);
  if alive_at(&mut p, 0) { ok = false; }
  if life_of(&mut p, 0) != 0 { ok = false; }
  return assert(ok, "life reaches 0 and expires on that update");
}

fn t15_dead_slots_are_frozen() -> TestResult {
  var p = particle_pool_new(2);
  particle_spawn(&mut p, 100, 200, 1000, -1000, 5);
  particle_update(&mut p, 5);
  var ok = !alive_at(&mut p, 0);
  let frozen_x = x_of(&mut p, 0);
  let frozen_y = y_of(&mut p, 0);
  particle_update(&mut p, 50);
  if x_of(&mut p, 0) != frozen_x { ok = false; }
  if y_of(&mut p, 0) != frozen_y { ok = false; }
  if alive_of(&mut p) != 0 { ok = false; }
  return assert(ok, "a dead slot is not advanced by later updates");
}

fn t16_dt_zero_is_a_noop() -> TestResult {
  var p = particle_pool_new(2);
  particle_spawn(&mut p, 1000, -2000, 1500, -1500, 500);
  particle_update(&mut p, 0);
  var ok = x_of(&mut p, 0) == 1000;
  if y_of(&mut p, 0) != -2000 { ok = false; }
  if life_of(&mut p, 0) != 500 { ok = false; }
  if !alive_at(&mut p, 0) { ok = false; }
  particle_update(&mut p, -25);
  if x_of(&mut p, 0) != 1000 { ok = false; }
  if life_of(&mut p, 0) != 500 { ok = false; }
  return assert(ok, "dt <= 0 leaves every slot untouched");
}

fn t17_large_dt_moves_then_kills() -> TestResult {
  var p = particle_pool_new(3);
  particle_spawn(&mut p, 0, 0, 1000, 0, 10);
  particle_spawn(&mut p, 0, 0, 0, 2000, 20);
  particle_spawn(&mut p, 0, 0, 0, 0, 30);
  particle_update(&mut p, 100000);
  var ok = alive_of(&mut p) == 0;
  var i = 0;
  while i < 3 {
    if alive_at(&mut p, i) { ok = false; }
    i = i + 1;
  }
  if x_of(&mut p, 0) != 100000 { ok = false; }
  if y_of(&mut p, 1) != 200000 { ok = false; }
  if life_of(&mut p, 2) != 30 - 100000 { ok = false; }
  let reuse = particle_spawn(&mut p, 7, 8, 0, 0, 9);
  if reuse != 0 { ok = false; }
  return assert(ok, "a huge dt moves and then kills every live slot");
}

fn t18_clear_empties_the_pool() -> TestResult {
  var p = particle_pool_new(4);
  particle_spawn(&mut p, 1, 2, 3, 4, 500);
  particle_spawn(&mut p, 5, 6, 7, 8, 600);
  particle_spawn(&mut p, 9, 10, 11, 12, 700);
  particle_clear(&mut p);
  var ok = alive_of(&mut p) == 0;
  if alive_at(&mut p, 0) { ok = false; }
  if x_of(&mut p, 0) != 0 { ok = false; }
  if y_of(&mut p, 1) != 0 { ok = false; }
  if life_of(&mut p, 2) != 0 { ok = false; }
  let reuse = particle_spawn(&mut p, 1, 2, 3, 4, 5);
  if reuse != 0 { ok = false; }
  if alive_of(&mut p) != 1 { ok = false; }
  return assert(ok, "clear zeroes every slot and frees the whole pool");
}

fn t19_accessors_pin_and_range_check() -> TestResult {
  var p = particle_pool_new(2);
  particle_spawn(&mut p, 42, -43, 0, 0, 500);
  var ok = x_of(&mut p, 0) == 42;
  if y_of(&mut p, 0) != -43 { ok = false; }
  if life_of(&mut p, 0) != 500 { ok = false; }
  if x_of(&mut p, -1) != 0 { ok = false; }
  if y_of(&mut p, -9) != 0 { ok = false; }
  if life_of(&mut p, 2) != 0 { ok = false; }
  if x_of(&mut p, 99) != 0 { ok = false; }
  if life_of(&mut p, -1) != 0 { ok = false; }
  return assert(ok, "accessors pin stored values and read 0 out of range");
}

fn t20_hundred_particle_invariant() -> TestResult {
  var p = particle_pool_new(128);
  var i = 0;
  while i < 100 {
    let life = 1 + (i % 50);
    let vx = (i % 7) * 100;
    let vy = (i % 5) * 100 - 200;
    particle_spawn(&mut p, i * 10, i * 20, vx, vy, life);
    i = i + 1;
  }
  var ok = alive_of(&mut p) == 100;
  var expected = 100;
  var step = 0;
  while step < 60 {
    particle_update(&mut p, 1);
    var scanned = 0;
    var j = 0;
    while j < 128 {
      if alive_at(&mut p, j) { scanned = scanned + 1; }
      j = j + 1;
    }
    let reported = alive_of(&mut p);
    if reported != scanned { ok = false; }
    if reported > expected { ok = false; }
    expected = reported;
    step = step + 1;
  }
  if alive_of(&mut p) != 0 { ok = false; }
  let reuse = particle_spawn(&mut p, 1, 2, 3, 4, 5);
  if reuse != 0 { ok = false; }
  return assert(ok, "100-particle updates keep the alive count consistent");
}

fn t21_spawn_expired_then_killed_slots_in_order() -> TestResult {
  var p = particle_pool_new(3);
  particle_spawn(&mut p, 1, 0, 0, 0, 10);
  particle_spawn(&mut p, 2, 0, 0, 0, 100);
  particle_spawn(&mut p, 3, 0, 0, 0, 100);
  particle_update(&mut p, 10);
  var ok = !alive_at(&mut p, 0);
  if !particle_kill(&mut p, 1) { ok = false; }
  let a = particle_spawn(&mut p, 4, 0, 0, 0, 100);
  let b = particle_spawn(&mut p, 5, 0, 0, 0, 100);
  if a != 0 { ok = false; }
  if b != 1 { ok = false; }
  if alive_of(&mut p) != 3 { ok = false; }
  if x_of(&mut p, 2) != 3 { ok = false; }
  let c = particle_spawn(&mut p, 6, 0, 0, 0, 100);
  if c != -1 { ok = false; }
  return assert(ok, "dead slots are refilled left to right");
}

fn main() -> Int {
  io.println("=== xiom.particle conformance tests ===");
  var failed: Int = 0;
  let r1 = t01_capacity_clamps_to_at_least_one();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t02_fresh_pool_is_empty();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t03_spawn_writes_state_into_slots();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t04_spawn_clamps_life_ms();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t05_full_pool_reports_negative_one();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t06_kill_live_and_dead_slots();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t07_kill_out_of_range();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t08_reuses_first_free_slot_after_kill();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t09_reuses_slot_after_expiry();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10_update_adds_velocity_scaled_by_dt();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11_truncates_toward_zero();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12_fractional_steps_do_not_carry();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13_life_decrements_each_update();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14_expires_exactly_at_zero();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15_dead_slots_are_frozen();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16_dt_zero_is_a_noop();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17_large_dt_moves_then_kills();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18_clear_empties_the_pool();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19_accessors_pin_and_range_check();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20_hundred_particle_invariant();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21_spawn_expired_then_killed_slots_in_order();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.particle: all tests passed");
  } else {
    io.println("xiom.particle: tests failed");
  }
  return failed;
}
