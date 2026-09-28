// XIOM -- xiom.semaphore conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.semaphore state machine against its
// documented API (permit accounting, strict FIFO wakeups, over-release and
// validation errors, stats and fairness trace).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison, so every error-message
// check below is routed through streq. Vec[Int] element reads use a typed
// `let`. Read-only operations are wrapped in small helpers that take `&mut`,
// so a `&local` read call is never followed by a `&mut local` call in the
// same function body (advisory E001); each helper calls the real `&`-based
// API. Enum-ish helpers (try_code / rel_code / enq_pos / grant_id_of) turn
// Result/Option outcomes into small Int codes so tests stay branch-free.

module semaphore_tests
use xiom.io; use xiom.test; use xiom.semaphore;
use xiom.string.compare;

const _E_CAP: Str = "semaphore: capacity must be >= 0";
const _E_N: Str = "semaphore: n must be >= 1";
const _E_ID: Str = "semaphore: waiter id must be >= 0";
const _E_EXCEED: Str = "semaphore: request exceeds capacity";
const _E_DUP: Str = "semaphore: duplicate waiter id";
const _E_BLOCK: Str = "semaphore: would block";
const _E_OVER: Str = "semaphore: over-release (permits would exceed capacity)";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Fixture: the Err branch is unreachable for the non-negative capacities the
// tests pass, but the function must still return a Semaphore value.
fn sem_of(cap: Int) -> Semaphore {
  match sem_new(cap) {
    Ok(s) => { return s; },
    Err(_) => {
      return Semaphore{
        capacity: cap;
        permits: cap;
        waiters: Vec[Int].new();
        waiter_sizes: Vec[Int].new();
        grants: 0;
        blocks: 0;
        releases: 0;
        grant_order: Vec[Int].new();
      };
    },
  }
}

fn new_err_is(cap: Int, want: Str) -> Bool {
  match sem_new(cap) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Read-only accessors routed through `&mut` (advisory E001).

fn cap_of(s: &mut Semaphore) -> Int {
  return sem_capacity(s);
}

fn permits_of(s: &mut Semaphore) -> Int {
  return sem_permits(s);
}

fn q_len_of(s: &mut Semaphore) -> Int {
  return sem_queue_len(s);
}

fn q_id_of(s: &mut Semaphore, i: Int) -> Int {
  return sem_queue_id_at(s, i);
}

fn q_size_of(s: &mut Semaphore, i: Int) -> Int {
  return sem_queue_size_at(s, i);
}

fn queue_ids_of(s: &mut Semaphore) -> Vec[Int] {
  return sem_queue_ids(s);
}

fn grants_of(s: &mut Semaphore) -> Int {
  return sem_grant_count(s);
}

fn blocks_of(s: &mut Semaphore) -> Int {
  return sem_block_count(s);
}

fn releases_of(s: &mut Semaphore) -> Int {
  return sem_release_count(s);
}

fn order_len_of(s: &mut Semaphore) -> Int {
  return sem_grant_order_len(s);
}

fn order_ids_of(s: &mut Semaphore) -> Vec[Int] {
  return sem_grant_order(s);
}

fn trace_of(s: &mut Semaphore) -> Str {
  return sem_grant_trace(s);
}

fn invariant_of(s: &mut Semaphore) -> Bool {
  return sem_check_invariant(s);
}

// Outcome classifiers: Int codes keep the tests readable.

// 1 = granted, 0 = would block, -1 = invalid n, -2 = exceeds capacity,
// -9 = unexpected error.
fn try_code(s: &mut Semaphore, n: Int) -> Int {
  match sem_try_acquire(s, n) {
    Ok(_) => { return 1; },
    Err(e) => {
      if streq(e, _E_BLOCK) { return 0; }
      if streq(e, _E_N) { return -1; }
      if streq(e, _E_EXCEED) { return -2; }
      return -9;
    },
  }
  return -9;
}

// 1 = released, 0 = over-release, -1 = invalid n, -9 = unexpected error.
fn rel_code(s: &mut Semaphore, n: Int) -> Int {
  match sem_release(s, n) {
    Ok(_) => { return 1; },
    Err(e) => {
      if streq(e, _E_OVER) { return 0; }
      if streq(e, _E_N) { return -1; }
      return -9;
    },
  }
  return -9;
}

// Queue position on success, -1 on any error.
fn enq_pos(s: &mut Semaphore, id: Int, n: Int) -> Int {
  match sem_enqueue_waiter(s, id, n) {
    Ok(pos) => { return pos; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn enq_err_is(s: &mut Semaphore, id: Int, n: Int, want: Str) -> Bool {
  match sem_enqueue_waiter(s, id, n) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Woken waiter ID, or -1 when grant_next returns None.
fn grant_id_of(s: &mut Semaphore) -> Int {
  match sem_grant_next(s) {
    Some(id) => { return id; },
    None => { return -1; },
  }
  return -1;
}

// True when grant_next returns None (consumes no grant).
fn grant_none(s: &mut Semaphore) -> Bool {
  match sem_grant_next(s) {
    Some(_) => { return false; },
    None => { return true; },
  }
  return false;
}

fn t1() -> TestResult {
  var s = sem_of(3);
  var ok = cap_of(&mut s) == 3;
  if permits_of(&mut s) != 3 { ok = false; }
  if q_len_of(&mut s) != 0 { ok = false; }
  if grants_of(&mut s) != 0 { ok = false; }
  if blocks_of(&mut s) != 0 { ok = false; }
  if releases_of(&mut s) != 0 { ok = false; }
  if order_len_of(&mut s) != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "sem_new initializes capacity, permits, zero stats");
}

fn t2() -> TestResult {
  var ok = new_err_is(-1, _E_CAP);
  if !new_err_is(-100, _E_CAP) { ok = false; }
  return assert(ok, "sem_new rejects negative capacity with a stable error");
}

fn t3() -> TestResult {
  var s = sem_of(0);
  var ok = cap_of(&mut s) == 0;
  if permits_of(&mut s) != 0 { ok = false; }
  if try_code(&mut s, 1) != -2 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if grants_of(&mut s) != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "a zero-capacity semaphore is valid and refuses requests");
}

fn t4() -> TestResult {
  var s = sem_of(3);
  var ok = try_code(&mut s, 1) == 1;
  if permits_of(&mut s) != 2 { ok = false; }
  if grants_of(&mut s) != 1 { ok = false; }
  if try_code(&mut s, 2) != 1 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if grants_of(&mut s) != 2 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "try_acquire consumes permits and counts grants");
}

fn t5() -> TestResult {
  var s = sem_of(3);
  var ok = true;
  var i = 0;
  while i < 3 {
    if try_code(&mut s, 1) != 1 { ok = false; }
    i = i + 1;
  }
  if permits_of(&mut s) != 0 { ok = false; }
  if try_code(&mut s, 1) != 0 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if grants_of(&mut s) != 3 { ok = false; }
  return assert(ok, "try_acquire exhausts capacity then reports would block");
}

fn t6() -> TestResult {
  var s = sem_of(5);
  var ok = try_code(&mut s, 3) == 1;
  if permits_of(&mut s) != 2 { ok = false; }
  if try_code(&mut s, 3) != 0 { ok = false; }
  if permits_of(&mut s) != 2 { ok = false; }
  if grants_of(&mut s) != 1 { ok = false; }
  if try_code(&mut s, 2) != 1 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  return assert(ok, "a refused acquire leaves permits and stats unchanged");
}

fn t7() -> TestResult {
  var s = sem_of(3);
  var ok = try_code(&mut s, 0) == -1;
  if try_code(&mut s, -5) != -1 { ok = false; }
  if try_code(&mut s, 4) != -2 { ok = false; }
  if permits_of(&mut s) != 3 { ok = false; }
  if grants_of(&mut s) != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "try_acquire validates n: >= 1 and <= capacity");
}

fn t8() -> TestResult {
  var s = sem_of(4);
  var ok = try_code(&mut s, 4) == 1;
  if permits_of(&mut s) != 0 { ok = false; }
  if try_code(&mut s, 1) != 0 { ok = false; }
  if grants_of(&mut s) != 1 { ok = false; }
  return assert(ok, "a full-capacity request is granted exactly once");
}

fn t9() -> TestResult {
  var s = sem_of(3);
  var ok = q_len_of(&mut s) == 0;
  if enq_pos(&mut s, 101, 1) != 0 { ok = false; }
  if enq_pos(&mut s, 102, 2) != 1 { ok = false; }
  if enq_pos(&mut s, 103, 3) != 2 { ok = false; }
  if q_len_of(&mut s) != 3 { ok = false; }
  if q_id_of(&mut s, 0) != 101 { ok = false; }
  if q_id_of(&mut s, 1) != 102 { ok = false; }
  if q_id_of(&mut s, 2) != 103 { ok = false; }
  if q_size_of(&mut s, 0) != 1 { ok = false; }
  if q_size_of(&mut s, 1) != 2 { ok = false; }
  if q_size_of(&mut s, 2) != 3 { ok = false; }
  if blocks_of(&mut s) != 3 { ok = false; }
  if permits_of(&mut s) != 3 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "enqueue_waiter appends FIFO with mirrored request sizes");
}

fn t10() -> TestResult {
  var s = sem_of(2);
  var ok = enq_err_is(&mut s, -1, 1, _E_ID);
  if !enq_err_is(&mut s, 1, 0, _E_N) { ok = false; }
  if !enq_err_is(&mut s, 1, 3, _E_EXCEED) { ok = false; }
  if enq_pos(&mut s, 5, 1) != 0 { ok = false; }
  if !enq_err_is(&mut s, 5, 1, _E_DUP) { ok = false; }
  if q_len_of(&mut s) != 1 { ok = false; }
  if blocks_of(&mut s) != 1 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "enqueue_waiter validates id, n, capacity and uniqueness");
}

fn t11() -> TestResult {
  var s = sem_of(2);
  var ok = grant_none(&mut s);
  if grants_of(&mut s) != 0 { ok = false; }
  if order_len_of(&mut s) != 0 { ok = false; }
  if permits_of(&mut s) != 2 { ok = false; }
  return assert(ok, "grant_next on an empty queue returns None unchanged");
}

fn t12() -> TestResult {
  var s = sem_of(2);
  var ok = try_code(&mut s, 2) == 1;
  if enq_pos(&mut s, 9, 1) != 0 { ok = false; }
  if !grant_none(&mut s) { ok = false; }
  if q_len_of(&mut s) != 1 { ok = false; }
  if q_id_of(&mut s, 0) != 9 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if grants_of(&mut s) != 1 { ok = false; }
  return assert(ok, "grant_next waits while no permits are free");
}

fn t13() -> TestResult {
  var s = sem_of(1);
  var ok = try_code(&mut s, 1) == 1;
  if enq_pos(&mut s, 101, 1) != 0 { ok = false; }
  if enq_pos(&mut s, 102, 1) != 1 { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 101 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if !grant_none(&mut s) { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 102 { ok = false; }
  if q_len_of(&mut s) != 0 { ok = false; }
  if grants_of(&mut s) != 3 { ok = false; }
  if !streq(trace_of(&mut s), "101,102") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "grants wake queued waiters in FIFO order");
}

fn t14() -> TestResult {
  var s = sem_of(3);
  var ok = try_code(&mut s, 3) == 1;
  if enq_pos(&mut s, 7, 3) != 0 { ok = false; }
  if enq_pos(&mut s, 8, 1) != 1 { ok = false; }
  if rel_code(&mut s, 2) != 1 { ok = false; }
  if !grant_none(&mut s) { ok = false; }
  if q_len_of(&mut s) != 2 { ok = false; }
  if q_id_of(&mut s, 0) != 7 { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 7 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if !grant_none(&mut s) { ok = false; }
  if q_len_of(&mut s) != 1 { ok = false; }
  if q_id_of(&mut s, 0) != 8 { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 8 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if !streq(trace_of(&mut s), "7,8") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "strict FIFO: a large head blocks smaller followers");
}

fn t15() -> TestResult {
  var s = sem_of(3);
  var ok = try_code(&mut s, 3) == 1;
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if permits_of(&mut s) != 1 { ok = false; }
  if releases_of(&mut s) != 1 { ok = false; }
  if rel_code(&mut s, 2) != 1 { ok = false; }
  if permits_of(&mut s) != 3 { ok = false; }
  if releases_of(&mut s) != 2 { ok = false; }
  if rel_code(&mut s, 1) != 0 { ok = false; }
  if permits_of(&mut s) != 3 { ok = false; }
  if releases_of(&mut s) != 2 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "release returns permits and refuses over-release");
}

fn t16() -> TestResult {
  var s = sem_of(2);
  var ok = rel_code(&mut s, 0) == -1;
  if rel_code(&mut s, -2) != -1 { ok = false; }
  if rel_code(&mut s, 1) != 0 { ok = false; }
  if permits_of(&mut s) != 2 { ok = false; }
  if releases_of(&mut s) != 0 { ok = false; }
  if try_code(&mut s, 2) != 1 { ok = false; }
  if rel_code(&mut s, 2) != 1 { ok = false; }
  if permits_of(&mut s) != 2 { ok = false; }
  if releases_of(&mut s) != 1 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "release validates n and never lets permits exceed capacity");
}

fn t17() -> TestResult {
  var s = sem_of(3);
  var ok = try_code(&mut s, 3) == 1;
  if enq_pos(&mut s, 11, 1) != 0 { ok = false; }
  if enq_pos(&mut s, 12, 2) != 1 { ok = false; }
  if enq_pos(&mut s, 13, 3) != 2 { ok = false; }
  var ids = sem_drain(&mut s);
  if ids.len() != 3 { ok = false; }
  let i0: Int = ids[0];
  let i1: Int = ids[1];
  let i2: Int = ids[2];
  if i0 != 11 { ok = false; }
  if i1 != 12 { ok = false; }
  if i2 != 13 { ok = false; }
  if q_len_of(&mut s) != 0 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if blocks_of(&mut s) != 3 { ok = false; }
  if grants_of(&mut s) != 1 { ok = false; }
  if order_len_of(&mut s) != 0 { ok = false; }
  var again = sem_drain(&mut s);
  if again.len() != 0 { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "drain removes queued waiters in FIFO order without granting");
}

fn t18() -> TestResult {
  var s = sem_of(2);
  var ok = try_code(&mut s, 1) == 1;
  if enq_pos(&mut s, 21, 2) != 0 { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 21 { ok = false; }
  if grants_of(&mut s) != 2 { ok = false; }
  if blocks_of(&mut s) != 1 { ok = false; }
  if releases_of(&mut s) != 1 { ok = false; }
  if permits_of(&mut s) != 0 { ok = false; }
  if q_len_of(&mut s) != 0 { ok = false; }
  if !streq(trace_of(&mut s), "21") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "stats accumulate grants, blocks and releases");
}

fn t19() -> TestResult {
  var s = sem_of(1);
  var ok = streq(trace_of(&mut s), "");
  if order_len_of(&mut s) != 0 { ok = false; }
  if try_code(&mut s, 1) != 1 { ok = false; }
  if enq_pos(&mut s, 3, 1) != 0 { ok = false; }
  if enq_pos(&mut s, 4, 1) != 1 { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 3 { ok = false; }
  if !streq(trace_of(&mut s), "3") { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 4 { ok = false; }
  if !streq(trace_of(&mut s), "3,4") { ok = false; }
  if order_len_of(&mut s) != 2 { ok = false; }
  return assert(ok, "grant_trace renders the ordered wakeup log");
}

fn t20() -> TestResult {
  var s = sem_of(2);
  var ok = q_id_of(&mut s, -1) == -1;
  if q_id_of(&mut s, 0) != -1 { ok = false; }
  if q_size_of(&mut s, -1) != -1 { ok = false; }
  if q_size_of(&mut s, 5) != -1 { ok = false; }
  if enq_pos(&mut s, 1, 1) != 0 { ok = false; }
  if q_id_of(&mut s, 1) != -1 { ok = false; }
  if q_size_of(&mut s, 1) != -1 { ok = false; }
  if q_id_of(&mut s, 0) != 1 { ok = false; }
  if q_size_of(&mut s, 0) != 1 { ok = false; }
  return assert(ok, "queue accessors are safe out of range");
}

fn t21() -> TestResult {
  var s = sem_of(2);
  var ok = enq_pos(&mut s, 1, 1) == 0;
  var ids = queue_ids_of(&mut s);
  ids.push(999);
  if q_len_of(&mut s) != 1 { ok = false; }
  if q_id_of(&mut s, 0) != 1 { ok = false; }
  var order = order_ids_of(&mut s);
  order.push(777);
  if order_len_of(&mut s) != 0 { ok = false; }
  if permits_of(&mut s) != 2 { ok = false; }
  return assert(ok, "queue_ids and grant_order return copies");
}

fn t22() -> TestResult {
  var s = sem_of(3);
  var ok = true;
  var i = 0;
  while i < 40 {
    if try_code(&mut s, 1) < 0 { ok = false; }
    if enq_pos(&mut s, 1000 + i, 1 + i % 3) < 0 { ok = false; }
    let gid1: Int = grant_id_of(&mut s);
    if gid1 < -1 { ok = false; }
    if gid1 >= 0 && (gid1 < 1000 || gid1 > 1039) { ok = false; }
    if rel_code(&mut s, 1) < 0 { ok = false; }
    let gid2: Int = grant_id_of(&mut s);
    if gid2 < -1 { ok = false; }
    if gid2 >= 0 && (gid2 < 1000 || gid2 > 1039) { ok = false; }
    if !invariant_of(&mut s) { ok = false; }
    i = i + 1;
  }
  let g: Int = grants_of(&mut s);
  let b: Int = blocks_of(&mut s);
  if b != 40 { ok = false; }
  if g > 80 { ok = false; }
  if permits_of(&mut s) > cap_of(&mut s) { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "the invariant holds across 240 mixed transitions");
}

fn t23() -> TestResult {
  var s = sem_of(1);
  var ok = try_code(&mut s, 1) == 1;
  if enq_pos(&mut s, 42, 1) != 0 { ok = false; }
  if rel_code(&mut s, 1) != 1 { ok = false; }
  if grant_id_of(&mut s) != 42 { ok = false; }
  if enq_pos(&mut s, 42, 1) != 0 { ok = false; }
  if q_len_of(&mut s) != 1 { ok = false; }
  if blocks_of(&mut s) != 2 { ok = false; }
  if !streq(trace_of(&mut s), "42") { ok = false; }
  if !invariant_of(&mut s) { ok = false; }
  return assert(ok, "a granted waiter id may re-enqueue");
}

fn main() -> Int {
  io.println("=== xiom.semaphore conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.semaphore: all tests passed");
  } else {
    io.println("xiom.semaphore: tests failed");
  }
  return failed;
}
