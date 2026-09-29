// XIOM -- xiom.barrier conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.barrier state machine against its
// documented API (generation accounting, trip/leader outcomes, duplicate and
// validation errors, sense reversal, reset semantics and stats).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec elements lowers to a pointer comparison, so every message check below
// is routed through streq. Vec[Int] element reads use a typed `let`.
// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001); each helper calls the real `&`-based API.
// Outcome classifiers (arrive_code / arrive_pos / arrive_gen / arrive_sense
// / leader_probe / arrival_probe / reset_code) turn Result outcomes into
// small Int codes so the tests stay branch-free.

module barrier_tests
use xiom.io; use xiom.test; use xiom.barrier;
use xiom.string.compare;

const _E_PARTIES: Str = "barrier: parties must be >= 1";
const _E_ID: Str = "barrier: party id must be >= 0";
const _E_DUP: Str = "barrier: duplicate party id in generation";
const _E_MID: Str = "barrier: cannot reset mid-generation";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Fixture: barrier_new rejects parties < 1, so bar_of(0) and bar_of(-2)
// construct the invalid value directly to exercise the defensive arrive
// check. Raw construction mirrors the public struct layout.
fn bar_of(parties: Int) -> Barrier {
  match barrier_new(parties) {
    Ok(b) => { return b; },
    Err(_) => {
      return Barrier{
        parties: parties;
        generation: 0;
        sense: 0;
        arrivals: Vec[Int].new();
        arrival_gens: Vec[Int].new();
        arrivals_total: 0;
        trips: 0;
        released: 0;
        last_trip_generation: -1;
        last_trip_leader: -1;
        last_trip_parties: Vec[Int].new();
      };
    },
  }
}

fn new_err_is(parties: Int, want: Str) -> Bool {
  match barrier_new(parties) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Read-only accessors routed through `&mut` (advisory E001).

fn parties_of(b: &mut Barrier) -> Int {
  return barrier_parties(b);
}

fn gen_of(b: &mut Barrier) -> Int {
  return barrier_generation(b);
}

fn sense_of(b: &mut Barrier) -> Int {
  return barrier_sense(b);
}

fn arrived_of(b: &mut Barrier) -> Int {
  return barrier_arrived_count(b);
}

fn aid_of(b: &mut Barrier, i: Int) -> Int {
  return barrier_arrived_id_at(b, i);
}

fn agen_of(b: &mut Barrier, i: Int) -> Int {
  return barrier_arrived_gen_at(b, i);
}

fn ids_of(b: &mut Barrier) -> Vec[Int] {
  return barrier_arrived_ids(b);
}

fn trace_of(b: &mut Barrier) -> Str {
  return barrier_wait_trace(b);
}

fn total_of(b: &mut Barrier) -> Int {
  return barrier_arrivals_total(b);
}

fn trips_of(b: &mut Barrier) -> Int {
  return barrier_trip_count(b);
}

fn released_of_count(b: &mut Barrier) -> Int {
  return barrier_released_count(b);
}

fn last_gen_of(b: &mut Barrier) -> Int {
  return barrier_last_trip_generation(b);
}

fn last_leader_of(b: &mut Barrier) -> Int {
  return barrier_last_trip_leader(b);
}

fn last_parties_of(b: &mut Barrier) -> Vec[Int] {
  return barrier_last_trip_parties(b);
}

fn released_waiter(b: &mut Barrier, g: Int) -> Bool {
  return barrier_waiter_released(b, g);
}

fn invariant_of(b: &mut Barrier) -> Bool {
  return barrier_check_invariant(b);
}

// Outcome classifiers: Int codes keep the tests readable.

// 1 = tripped (and leader), 0 = recorded without tripping, -1 = duplicate id,
// -2 = invalid id, -3 = invalid parties, -9 = unexpected error.
fn arrive_code(b: &mut Barrier, id: Int) -> Int {
  match barrier_arrive(b, id) {
    Ok(a) => {
      if a.tripped { return 1; }
      return 0;
    },
    Err(e) => {
      if streq(e, _E_DUP) { return -1; }
      if streq(e, _E_ID) { return -2; }
      if streq(e, _E_PARTIES) { return -3; }
      return -9;
    },
  }
  return -9;
}

fn arrive_err_is(b: &mut Barrier, id: Int, want: Str) -> Bool {
  match barrier_arrive(b, id) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Arrival position on success, -1 on any error.
fn arrive_pos(b: &mut Barrier, id: Int) -> Int {
  match barrier_arrive(b, id) {
    Ok(a) => { return a.position; },
    Err(_) => { return -1; },
  }
  return -1;
}

// Generation observed by the arrival, -9 on any error.
fn arrive_gen(b: &mut Barrier, id: Int) -> Int {
  match barrier_arrive(b, id) {
    Ok(a) => { return a.generation; },
    Err(_) => { return -9; },
  }
  return -9;
}

// Sense observed after the arrival, -9 on any error.
fn arrive_sense(b: &mut Barrier, id: Int) -> Int {
  match barrier_arrive(b, id) {
    Ok(a) => { return a.sense; },
    Err(_) => { return -9; },
  }
  return -9;
}

// 1 = leader, 0 = non-leader, -1 = error.
fn arrive_leader(b: &mut Barrier, id: Int) -> Int {
  match barrier_arrive(b, id) {
    Ok(a) => {
      if a.leader { return 1; }
      return 0;
    },
    Err(_) => { return -1; },
  }
  return -1;
}

// 1 when the arrival tripped as leader in generation `want_gen` at position
// `want_pos` with `want_sense` observed afterwards, 0 otherwise, -9 on error.
fn leader_probe(b: &mut Barrier, id: Int, want_gen: Int, want_pos: Int, want_sense: Int) -> Int {
  match barrier_arrive(b, id) {
    Ok(a) => {
      var good = a.tripped;
      if !a.leader { good = false; }
      if a.generation != want_gen { good = false; }
      if a.position != want_pos { good = false; }
      if a.sense != want_sense { good = false; }
      if good { return 1; }
      return 0;
    },
    Err(_) => { return -9; },
  }
  return -9;
}

// 1 when the arrival was recorded without tripping in generation `want_gen`
// at position `want_pos` with `want_sense` observed, 0 otherwise, -9 on error.
fn arrival_probe(b: &mut Barrier, id: Int, want_gen: Int, want_pos: Int, want_sense: Int) -> Int {
  match barrier_arrive(b, id) {
    Ok(a) => {
      var good = true;
      if a.tripped { good = false; }
      if a.leader { good = false; }
      if a.generation != want_gen { good = false; }
      if a.position != want_pos { good = false; }
      if a.sense != want_sense { good = false; }
      if good { return 1; }
      return 0;
    },
    Err(_) => { return -9; },
  }
  return -9;
}

// 1 = reset, 0 = mid-generation refusal, -9 = unexpected error.
fn reset_code(b: &mut Barrier) -> Int {
  match barrier_reset(b) {
    Ok(_) => { return 1; },
    Err(e) => {
      if streq(e, _E_MID) { return 0; }
      return -9;
    },
  }
  return -9;
}

fn reset_err_is(b: &mut Barrier, want: Str) -> Bool {
  match barrier_reset(b) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t1() -> TestResult {
  var b = bar_of(3);
  var ok = parties_of(&mut b) == 3;
  if gen_of(&mut b) != 0 { ok = false; }
  if sense_of(&mut b) != 0 { ok = false; }
  if arrived_of(&mut b) != 0 { ok = false; }
  if total_of(&mut b) != 0 { ok = false; }
  if trips_of(&mut b) != 0 { ok = false; }
  if released_of_count(&mut b) != 0 { ok = false; }
  if last_gen_of(&mut b) != -1 { ok = false; }
  if last_leader_of(&mut b) != -1 { ok = false; }
  var lp = last_parties_of(&mut b);
  if lp.len() != 0 { ok = false; }
  if !streq(trace_of(&mut b), "") { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "barrier_new initializes parties, generation 0 and zero stats");
}

fn t2() -> TestResult {
  var ok = new_err_is(0, _E_PARTIES);
  if !new_err_is(-1, _E_PARTIES) { ok = false; }
  if !new_err_is(-100, _E_PARTIES) { ok = false; }
  return assert(ok, "barrier_new rejects zero and negative parties with a stable error");
}

fn t3() -> TestResult {
  var b = bar_of(4);
  var ok = arrive_code(&mut b, 7) == 0;
  if arrive_code(&mut b, 9) != 0 { ok = false; }
  if arrive_pos(&mut b, 11) != 2 { ok = false; }
  if arrived_of(&mut b) != 3 { ok = false; }
  if aid_of(&mut b, 0) != 7 { ok = false; }
  if aid_of(&mut b, 1) != 9 { ok = false; }
  if aid_of(&mut b, 2) != 11 { ok = false; }
  if gen_of(&mut b) != 0 { ok = false; }
  if trips_of(&mut b) != 0 { ok = false; }
  if total_of(&mut b) != 3 { ok = false; }
  if !streq(trace_of(&mut b), "7@0,9@0,11@0") { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "arrivals accumulate in arrival order without tripping early");
}

fn t4() -> TestResult {
  var b = bar_of(3);
  var ok = arrive_code(&mut b, 10) == 0;
  if arrive_code(&mut b, 20) != 0 { ok = false; }
  if leader_probe(&mut b, 30, 0, 2, 1) != 1 { ok = false; }
  if gen_of(&mut b) != 1 { ok = false; }
  if arrived_of(&mut b) != 0 { ok = false; }
  if trips_of(&mut b) != 1 { ok = false; }
  if released_of_count(&mut b) != 3 { ok = false; }
  if total_of(&mut b) != 3 { ok = false; }
  if last_gen_of(&mut b) != 0 { ok = false; }
  if last_leader_of(&mut b) != 30 { ok = false; }
  var lp = last_parties_of(&mut b);
  if lp.len() != 3 { ok = false; }
  let p0: Int = lp[0];
  let p1: Int = lp[1];
  let p2: Int = lp[2];
  if p0 != 10 { ok = false; }
  if p1 != 20 { ok = false; }
  if p2 != 30 { ok = false; }
  if !streq(trace_of(&mut b), "") { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "the Nth arrival trips the barrier and publishes trip metadata");
}

fn t5() -> TestResult {
  var b = bar_of(3);
  var ok = arrive_code(&mut b, 2) == 0;
  if arrive_code(&mut b, 0) != 0 { ok = false; }
  if arrive_leader(&mut b, 1) != 1 { ok = false; }
  if last_leader_of(&mut b) != 1 { ok = false; }
  if last_gen_of(&mut b) != 0 { ok = false; }
  if arrive_code(&mut b, 1) != 0 { ok = false; }
  if arrive_code(&mut b, 2) != 0 { ok = false; }
  if arrive_leader(&mut b, 0) != 1 { ok = false; }
  if last_leader_of(&mut b) != 0 { ok = false; }
  if last_gen_of(&mut b) != 1 { ok = false; }
  if gen_of(&mut b) != 2 { ok = false; }
  if trips_of(&mut b) != 2 { ok = false; }
  if released_of_count(&mut b) != 6 { ok = false; }
  if total_of(&mut b) != 6 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "generations advance across reuses with per-generation leaders");
}

fn t6() -> TestResult {
  var b = bar_of(2);
  var ok = arrive_code(&mut b, 5) == 0;
  if !arrive_err_is(&mut b, 5, _E_DUP) { ok = false; }
  if arrived_of(&mut b) != 1 { ok = false; }
  if total_of(&mut b) != 1 { ok = false; }
  if arrive_code(&mut b, 4) != 1 { ok = false; }
  if trips_of(&mut b) != 1 { ok = false; }
  if arrive_code(&mut b, 5) != 0 { ok = false; }
  if arrived_of(&mut b) != 1 { ok = false; }
  if aid_of(&mut b, 0) != 5 { ok = false; }
  if agen_of(&mut b, 0) != 1 { ok = false; }
  if total_of(&mut b) != 3 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "duplicate id is refused in-generation but reusable next generation");
}

fn t7() -> TestResult {
  var b = bar_of(2);
  var ok = arrive_err_is(&mut b, -1, _E_ID);
  if !arrive_err_is(&mut b, -100, _E_ID) { ok = false; }
  if arrived_of(&mut b) != 0 { ok = false; }
  if total_of(&mut b) != 0 { ok = false; }
  if arrive_code(&mut b, 0) != 0 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "arrive rejects negative party ids without changing state");
}

fn t8() -> TestResult {
  var b = bar_of(0);
  var ok = arrive_err_is(&mut b, 1, _E_PARTIES);
  if arrived_of(&mut b) != 0 { ok = false; }
  if gen_of(&mut b) != 0 { ok = false; }
  if total_of(&mut b) != 0 { ok = false; }
  var bad = bar_of(-2);
  if !arrive_err_is(&mut bad, 1, _E_PARTIES) { ok = false; }
  return assert(ok, "arrive on a zero-parties barrier fails with the stable error");
}

fn t9() -> TestResult {
  var b = bar_of(3);
  var ok = aid_of(&mut b, -1) == -1;
  if aid_of(&mut b, 0) != -1 { ok = false; }
  if agen_of(&mut b, -1) != -1 { ok = false; }
  if agen_of(&mut b, 7) != -1 { ok = false; }
  if arrive_code(&mut b, 4) != 0 { ok = false; }
  if aid_of(&mut b, 1) != -1 { ok = false; }
  if agen_of(&mut b, 1) != -1 { ok = false; }
  if aid_of(&mut b, 0) != 4 { ok = false; }
  if agen_of(&mut b, 0) != 0 { ok = false; }
  var ids = ids_of(&mut b);
  ids.push(999);
  if arrived_of(&mut b) != 1 { ok = false; }
  if aid_of(&mut b, 0) != 4 { ok = false; }
  var lp = last_parties_of(&mut b);
  lp.push(777);
  var lp2 = last_parties_of(&mut b);
  if lp2.len() != 0 { ok = false; }
  return assert(ok, "arrival accessors are safe out of range and return copies");
}

fn t10() -> TestResult {
  var b = bar_of(2);
  var ok = arrival_probe(&mut b, 8, 0, 0, 0) == 1;
  if leader_probe(&mut b, 9, 0, 1, 1) != 1 { ok = false; }
  if arrival_probe(&mut b, 8, 1, 0, 1) != 1 { ok = false; }
  if leader_probe(&mut b, 9, 1, 1, 0) != 1 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "arrival outcomes report position, generation, sense and leadership");
}

fn t11() -> TestResult {
  var b = bar_of(2);
  var ok = arrive_sense(&mut b, 1) == 0;
  if arrive_sense(&mut b, 2) != 1 { ok = false; }
  if sense_of(&mut b) != 1 { ok = false; }
  if arrive_sense(&mut b, 1) != 1 { ok = false; }
  if arrive_sense(&mut b, 2) != 0 { ok = false; }
  if sense_of(&mut b) != 0 { ok = false; }
  if trips_of(&mut b) != 2 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "the sense flag flips on every trip and arrivals observe it");
}

fn t12() -> TestResult {
  var b = bar_of(2);
  var ok = !released_waiter(&mut b, 0);
  if !released_waiter(&mut b, -1) { ok = false; }
  if arrive_code(&mut b, 1) != 0 { ok = false; }
  if released_waiter(&mut b, 0) { ok = false; }
  if arrive_code(&mut b, 2) != 1 { ok = false; }
  if !released_waiter(&mut b, 0) { ok = false; }
  if released_waiter(&mut b, 1) { ok = false; }
  if arrive_code(&mut b, 3) != 0 { ok = false; }
  if arrive_code(&mut b, 4) != 1 { ok = false; }
  if !released_waiter(&mut b, 1) { ok = false; }
  if released_waiter(&mut b, 2) { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "waiter_released is true exactly when its generation has passed");
}

fn t13() -> TestResult {
  var b = bar_of(1);
  var ok = leader_probe(&mut b, 42, 0, 0, 1) == 1;
  if gen_of(&mut b) != 1 { ok = false; }
  if trips_of(&mut b) != 1 { ok = false; }
  if arrived_of(&mut b) != 0 { ok = false; }
  if leader_probe(&mut b, 42, 1, 0, 0) != 1 { ok = false; }
  if trips_of(&mut b) != 2 { ok = false; }
  if released_of_count(&mut b) != 2 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "a one-party barrier trips on every arrival");
}

fn t14() -> TestResult {
  var b = bar_of(3);
  var ok = arrive_code(&mut b, 1) == 0;
  if reset_code(&mut b) != 0 { ok = false; }
  if !reset_err_is(&mut b, _E_MID) { ok = false; }
  if arrived_of(&mut b) != 1 { ok = false; }
  if total_of(&mut b) != 1 { ok = false; }
  if gen_of(&mut b) != 0 { ok = false; }
  if !streq(trace_of(&mut b), "1@0") { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "reset refuses while parties are mid-generation");
}

fn t15() -> TestResult {
  var b = bar_of(2);
  var ok = arrive_code(&mut b, 1) == 0;
  if arrive_code(&mut b, 2) != 1 { ok = false; }
  if arrive_code(&mut b, 1) != 0 { ok = false; }
  if arrive_code(&mut b, 3) != 1 { ok = false; }
  if trips_of(&mut b) != 2 { ok = false; }
  if reset_code(&mut b) != 1 { ok = false; }
  if parties_of(&mut b) != 2 { ok = false; }
  if gen_of(&mut b) != 0 { ok = false; }
  if sense_of(&mut b) != 0 { ok = false; }
  if arrived_of(&mut b) != 0 { ok = false; }
  if total_of(&mut b) != 0 { ok = false; }
  if trips_of(&mut b) != 0 { ok = false; }
  if released_of_count(&mut b) != 0 { ok = false; }
  if last_gen_of(&mut b) != -1 { ok = false; }
  if last_leader_of(&mut b) != -1 { ok = false; }
  var lp = last_parties_of(&mut b);
  if lp.len() != 0 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  if arrive_code(&mut b, 1) != 0 { ok = false; }
  if leader_probe(&mut b, 2, 0, 1, 1) != 1 { ok = false; }
  if trips_of(&mut b) != 1 { ok = false; }
  return assert(ok, "reset when idle restores the initial state and reusability");
}

fn t16() -> TestResult {
  var b = bar_of(3);
  var ok = total_of(&mut b) == 0;
  if arrive_code(&mut b, 1) != 0 { ok = false; }
  if arrive_code(&mut b, 2) != 0 { ok = false; }
  if arrive_code(&mut b, 1) != -1 { ok = false; }
  if arrive_code(&mut b, -5) != -2 { ok = false; }
  if total_of(&mut b) != 2 { ok = false; }
  if arrive_code(&mut b, 3) != 1 { ok = false; }
  if total_of(&mut b) != 3 { ok = false; }
  if trips_of(&mut b) != 1 { ok = false; }
  if released_of_count(&mut b) != 3 { ok = false; }
  if arrive_code(&mut b, 3) != 0 { ok = false; }
  if total_of(&mut b) != 4 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "stats count successful arrivals, trips and released waiters only");
}

fn t17() -> TestResult {
  var b = bar_of(3);
  var ok = streq(trace_of(&mut b), "");
  if arrive_code(&mut b, 4) != 0 { ok = false; }
  if !streq(trace_of(&mut b), "4@0") { ok = false; }
  if arrive_code(&mut b, 2) != 0 { ok = false; }
  if !streq(trace_of(&mut b), "4@0,2@0") { ok = false; }
  if arrive_code(&mut b, 6) != 1 { ok = false; }
  if !streq(trace_of(&mut b), "") { ok = false; }
  if arrive_code(&mut b, 9) != 0 { ok = false; }
  if !streq(trace_of(&mut b), "9@1") { ok = false; }
  var ids = ids_of(&mut b);
  if ids.len() != 1 { ok = false; }
  let i0: Int = ids[0];
  if i0 != 9 { ok = false; }
  return assert(ok, "wait_trace renders the pending waiters as id@generation");
}

fn t18() -> TestResult {
  var b = bar_of(4);
  var ok = arrive_code(&mut b, 3) == 0;
  if arrive_code(&mut b, 1) != 0 { ok = false; }
  if arrive_code(&mut b, 0) != 0 { ok = false; }
  if arrive_code(&mut b, 2) != 1 { ok = false; }
  var lp = last_parties_of(&mut b);
  if lp.len() != 4 { ok = false; }
  let p0: Int = lp[0];
  let p1: Int = lp[1];
  let p2: Int = lp[2];
  let p3: Int = lp[3];
  if p0 != 3 { ok = false; }
  if p1 != 1 { ok = false; }
  if p2 != 0 { ok = false; }
  if p3 != 2 { ok = false; }
  lp.push(999);
  var lp2 = last_parties_of(&mut b);
  if lp2.len() != 4 { ok = false; }
  let q3: Int = lp2[3];
  if q3 != 2 { ok = false; }
  if last_leader_of(&mut b) != 2 { ok = false; }
  if last_gen_of(&mut b) != 0 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "last_trip_parties preserves arrival order and returns a copy");
}

fn t19() -> TestResult {
  var b = bar_of(2);
  var ok = last_gen_of(&mut b) == -1;
  if last_leader_of(&mut b) != -1 { ok = false; }
  if arrive_code(&mut b, 5) != 0 { ok = false; }
  if arrive_code(&mut b, 6) != 1 { ok = false; }
  if last_gen_of(&mut b) != 0 { ok = false; }
  if last_leader_of(&mut b) != 6 { ok = false; }
  if arrive_code(&mut b, 7) != 0 { ok = false; }
  if arrive_code(&mut b, 8) != 1 { ok = false; }
  if last_gen_of(&mut b) != 1 { ok = false; }
  if last_leader_of(&mut b) != 8 { ok = false; }
  var lp = last_parties_of(&mut b);
  if lp.len() != 2 { ok = false; }
  let a0: Int = lp[0];
  let a1: Int = lp[1];
  if a0 != 7 { ok = false; }
  if a1 != 8 { ok = false; }
  return assert(ok, "last-trip metadata tracks the most recent generation only");
}

fn t20() -> TestResult {
  var b = bar_of(3);
  var ok = true;
  var i = 0;
  while i < 40 {
    let code: Int = arrive_code(&mut b, 100 + (i % 3));
    if code < -1 { ok = false; }
    if arrive_code(&mut b, -1) != -2 { ok = false; }
    if !invariant_of(&mut b) { ok = false; }
    if (i % 7) == 0 {
      let rc: Int = reset_code(&mut b);
      if rc < 0 { ok = false; }
    }
    i = i + 1;
  }
  if !invariant_of(&mut b) { ok = false; }
  if gen_of(&mut b) != trips_of(&mut b) { ok = false; }
  if released_of_count(&mut b) != trips_of(&mut b) * 3 { ok = false; }
  if total_of(&mut b) != trips_of(&mut b) * 3 + arrived_of(&mut b) { ok = false; }
  return assert(ok, "the invariant holds across mixed arrivals and resets");
}

fn t21() -> TestResult {
  var b = bar_of(5);
  var ok = true;
  var i = 0;
  while i < 4 {
    if arrive_code(&mut b, i) != 0 { ok = false; }
    if arrived_of(&mut b) != i + 1 { ok = false; }
    if gen_of(&mut b) != 0 { ok = false; }
    if trips_of(&mut b) != 0 { ok = false; }
    i = i + 1;
  }
  if arrive_code(&mut b, 4) != 1 { ok = false; }
  if arrived_of(&mut b) != 0 { ok = false; }
  if gen_of(&mut b) != 1 { ok = false; }
  if trips_of(&mut b) != 1 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "the barrier never trips before parties arrivals");
}

fn t22() -> TestResult {
  var b = bar_of(2);
  var ok = arrive_code(&mut b, 0) == 0;
  if arrive_code(&mut b, 1000000) != 1 { ok = false; }
  if last_leader_of(&mut b) != 1000000 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "party id 0 and large ids are valid");
}

fn t23() -> TestResult {
  var b = bar_of(2);
  var ok = true;
  var g = 0;
  while g < 10 {
    if arrive_code(&mut b, 1) != 0 { ok = false; }
    if arrive_gen(&mut b, 2) != g { ok = false; }
    if gen_of(&mut b) != g + 1 { ok = false; }
    g = g + 1;
  }
  if trips_of(&mut b) != 10 { ok = false; }
  if gen_of(&mut b) != 10 { ok = false; }
  if total_of(&mut b) != 20 { ok = false; }
  if released_of_count(&mut b) != 20 { ok = false; }
  if sense_of(&mut b) != 0 { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "ten generations accumulate trips, releases and stats");
}

fn t24() -> TestResult {
  var b = bar_of(2);
  var ok = arrive_code(&mut b, 11) == 0;
  if reset_code(&mut b) != 0 { ok = false; }
  if !streq(trace_of(&mut b), "11@0") { ok = false; }
  if arrive_code(&mut b, 12) != 1 { ok = false; }
  if reset_code(&mut b) != 1 { ok = false; }
  if gen_of(&mut b) != 0 { ok = false; }
  if arrive_code(&mut b, 11) != 0 { ok = false; }
  if !streq(trace_of(&mut b), "11@0") { ok = false; }
  if !invariant_of(&mut b) { ok = false; }
  return assert(ok, "reset is refused mid-generation and accepted once the trip completes");
}

fn main() -> Int {
  io.println("=== xiom.barrier conformance tests ===");
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
    io.println("xiom.barrier: all tests passed");
  } else {
    io.println("xiom.barrier: tests failed");
  }
  return failed;
}
