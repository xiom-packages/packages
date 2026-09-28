// XIOM -- xiom.lockfree conformance tests (21 checks)
// Port task: prove the deterministic atomic-step models of the Treiber stack,
// the bounded MPMC ring queue and the atomic counter against their documented
// semantics (SPEC.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are built in-test: every test starts with stack_configure /
// queue_configure / counter_reset, and the configure calls are full resets
// (state, counters and CAS statistics), so tests are order-independent.
//
// Expected head tokens follow the packing
//   token = tag * (capacity + 1) + (index + 1)
// documented in SPEC.md section 3; tag is the number of successful head CAS
// steps since the reset. Str equality goes through compare.str_compare
// (BUG 17 discipline); every vec element read happens inside the module or
// through the typed helpers below.

module lockfree_tests
use xiom.io; use xiom.test; use xiom.lockfree;
use xiom.string;
use xiom.string.compare;

// 2^62 - 1, the counter upper bound pinned by the error tests.
const _TF_COUNTER_MAX: Int = 4611686018427387903;

// --------------------------------------------------
//  Result helpers (one consumption per Result value)
// --------------------------------------------------

// True when the Result is Err with exactly the (code, value, extra) triple.
fn err_is(r: Result[Int, LockfreeError], code: Int, value: Int, extra: Int) -> Bool {
  if r.is_ok { return false; }
  let e: LockfreeError = r.error;
  if e.code != code { return false; }
  if e.value != value { return false; }
  return e.extra == extra;
}

// True when the Result is Ok with the given value.
fn ok_is(r: Result[Int, LockfreeError], want: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: Int = r.value;
  return v == want;
}

// Ok value, or -999999 on Err (keeps a broken expectation failing loudly).
fn ok_val(r: Result[Int, LockfreeError]) -> Int {
  if !r.is_ok { return -999999; }
  let v: Int = r.value;
  return v;
}

// Byte-wise Str equality through str_compare (BUG 17 discipline).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when lockfree_error_message(code) equals `want` byte-wise.
fn msg_is(code: Int, want: Str) -> Bool {
  return streq(lockfree_error_message(code), want);
}

// --------------------------------------------------
//  Treiber stack
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = ok_is(stack_configure(4), 4);
  if stack_capacity() != 4 { ok = false; }
  if stack_count() != 0 { ok = false; }
  if stack_free_count() != 4 { ok = false; }
  if stack_head_token() != 0 { ok = false; }
  if stack_head_index() != -1 { ok = false; }
  if stack_head_tag() != 0 { ok = false; }
  if !ok_is(stack_push(11), 6) { ok = false; }   // tag 1, node 0
  if !ok_is(stack_push(22), 12) { ok = false; }  // tag 2, node 1
  if !ok_is(stack_push(33), 18) { ok = false; }  // tag 3, node 2
  if stack_count() != 3 { ok = false; }
  if stack_free_count() != 1 { ok = false; }
  if stack_head_index() != 2 { ok = false; }
  if stack_head_tag() != 3 { ok = false; }
  if !ok_is(stack_peek(), 33) { ok = false; }
  if !ok_is(stack_pop(), 33) { ok = false; }
  if !ok_is(stack_pop(), 22) { ok = false; }
  if !ok_is(stack_pop(), 11) { ok = false; }
  if stack_count() != 0 { ok = false; }
  if stack_head_token() != 30 { ok = false; }    // tag 6, empty
  if stack_head_index() != -1 { ok = false; }
  if stack_head_tag() != 6 { ok = false; }
  if stack_cas_successes() != 6 { ok = false; }
  if stack_cas_failures() != 0 { ok = false; }
  if stack_push_count() != 3 { ok = false; }
  if stack_pop_count() != 3 { ok = false; }
  return assert(ok, "stack LIFO order and packed head tokens");
}

fn t2() -> TestResult {
  var ok = ok_is(stack_configure(2), 2);
  if !err_is(stack_pop(), 2, -1, 2) { ok = false; }
  if !err_is(stack_peek(), 2, -1, 2) { ok = false; }
  if stack_count() != 0 { ok = false; }
  if stack_head_tag() != 0 { ok = false; }
  if !ok_is(stack_push(7), 4) { ok = false; }
  if !ok_is(stack_pop(), 7) { ok = false; }
  if !err_is(stack_pop(), 2, -1, 2) { ok = false; }
  if stack_pop_count() != 1 { ok = false; }
  if stack_push_count() != 1 { ok = false; }
  return assert(ok, "stack empty pop/peek errors and recovery");
}

fn t3() -> TestResult {
  var ok = ok_is(stack_configure(2), 2);
  if !ok_is(stack_push(10), 4) { ok = false; }   // tag 1, node 0
  if stack_head_index() != 0 { ok = false; }
  if stack_head_tag() != 1 { ok = false; }
  if !ok_is(stack_pop(), 10) { ok = false; }     // tag 2, empty
  if stack_head_index() != -1 { ok = false; }
  if stack_head_tag() != 2 { ok = false; }
  if !ok_is(stack_push(20), 10) { ok = false; }  // node 0 again, tag 3
  if stack_head_index() != 0 { ok = false; }
  if stack_head_tag() != 3 { ok = false; }
  if stack_head_token() == 4 { ok = false; }     // the stale ABA token
  if !ok_is(stack_pop(), 20) { ok = false; }
  if stack_cas_successes() != 4 { ok = false; }
  return assert(ok, "stack ABA: reused node carries a new tag");
}

fn t4() -> TestResult {
  var ok = ok_is(stack_configure(2), 2);
  if !ok_is(stack_push(1), 4) { ok = false; }
  if !ok_is(stack_push(2), 8) { ok = false; }
  if !err_is(stack_push(3), 3, 3, 2) { ok = false; }
  if stack_count() != 2 { ok = false; }
  if stack_free_count() != 0 { ok = false; }
  if !ok_is(stack_pop(), 2) { ok = false; }
  if !ok_is(stack_push(3), 14) { ok = false; }
  if stack_count() != 2 { ok = false; }
  if stack_free_count() != 0 { ok = false; }
  if !ok_is(stack_pop(), 3) { ok = false; }
  if !ok_is(stack_pop(), 1) { ok = false; }
  return assert(ok, "stack pool exhaustion at capacity and node reuse");
}

fn t5() -> TestResult {
  var ok = ok_is(stack_configure(2), 2);
  if stack_cas_step(999, 4) { ok = false; }
  if stack_cas_failures() != 1 { ok = false; }
  if stack_head_token() != 0 { ok = false; }
  if !stack_cas_step(0, 0) { ok = false; }
  if stack_cas_successes() != 1 { ok = false; }
  if stack_head_token() != 0 { ok = false; }
  if !ok_is(stack_push(5), 4) { ok = false; }
  if !ok_is(stack_pop(), 5) { ok = false; }
  if stack_cas_successes() != 3 { ok = false; }
  if stack_cas_failures() != 1 { ok = false; }
  if stack_head_tag() != 2 { ok = false; }
  return assert(ok, "stack cas step: stale expected fails, exact expected succeeds");
}

fn t6() -> TestResult {
  var ok = ok_is(stack_configure(3), 3);
  if !ok_is(stack_push(5), 5) { ok = false; }   // cap 3 -> stride 4, tag 1, node 0
  if !ok_is(stack_push(6), 10) { ok = false; }
  if !ok_is(stack_peek(), 6) { ok = false; }
  if !ok_is(stack_peek(), 6) { ok = false; }
  if stack_count() != 2 { ok = false; }
  if !ok_is(stack_pop(), 6) { ok = false; }
  if !ok_is(stack_peek(), 5) { ok = false; }
  if !ok_is(stack_pop(), 5) { ok = false; }
  if !err_is(stack_peek(), 2, -1, 3) { ok = false; }
  return assert(ok, "stack peek does not pop");
}

fn t20() -> TestResult {
  var ok = ok_is(stack_configure(4), 4);
  var round = 0;
  while round < 25 {
    var j = 0;
    while j < 4 {
      let pr = stack_push(round * 10 + j);
      if !pr.is_ok { ok = false; }
      j = j + 1;
    }
    if stack_count() != 4 { ok = false; }
    if stack_free_count() != 0 { ok = false; }
    j = 3;
    while j >= 0 {
      if ok_val(stack_pop()) != round * 10 + j { ok = false; }
      j = j - 1;
    }
    if stack_count() != 0 { ok = false; }
    round = round + 1;
  }
  if stack_push_count() != 100 { ok = false; }
  if stack_pop_count() != 100 { ok = false; }
  if stack_cas_successes() != 200 { ok = false; }
  if stack_cas_failures() != 0 { ok = false; }
  if stack_head_token() != 1000 { ok = false; }  // tag 200, empty
  if stack_head_tag() != 200 { ok = false; }
  return assert(ok, "stack stress: 100 reusing push/pop pairs, tags advance");
}

// --------------------------------------------------
//  Bounded MPMC ring queue
// --------------------------------------------------

fn t7() -> TestResult {
  var ok = ok_is(queue_configure(4), 4);
  if queue_capacity() != 4 { ok = false; }
  if queue_count() != 0 { ok = false; }
  if !queue_is_empty() { ok = false; }
  if queue_is_full() { ok = false; }
  if queue_head_counter() != 0 { ok = false; }
  if queue_tail_counter() != 0 { ok = false; }
  if !ok_is(queue_enqueue(10), 0) { ok = false; }
  if !ok_is(queue_enqueue(20), 1) { ok = false; }
  if !ok_is(queue_enqueue(30), 2) { ok = false; }
  if queue_count() != 3 { ok = false; }
  if queue_head_counter() != 0 { ok = false; }
  if queue_tail_counter() != 3 { ok = false; }
  if !ok_is(queue_dequeue(), 10) { ok = false; }
  if !ok_is(queue_dequeue(), 20) { ok = false; }
  if !ok_is(queue_dequeue(), 30) { ok = false; }
  if queue_count() != 0 { ok = false; }
  if queue_head_counter() != 3 { ok = false; }
  if queue_tail_counter() != 3 { ok = false; }
  if queue_enqueue_count() != 3 { ok = false; }
  if queue_dequeue_count() != 3 { ok = false; }
  if !err_is(queue_dequeue(), 5, -1, 4) { ok = false; }
  return assert(ok, "queue FIFO order and slot assignment");
}

fn t8() -> TestResult {
  var ok = ok_is(queue_configure(2), 2);
  if !err_is(queue_dequeue(), 5, -1, 2) { ok = false; }
  if !queue_is_empty() { ok = false; }
  if !ok_is(queue_enqueue(1), 0) { ok = false; }
  if !ok_is(queue_enqueue(2), 1) { ok = false; }
  if !queue_is_full() { ok = false; }
  if queue_count() != 2 { ok = false; }
  if !err_is(queue_enqueue(3), 6, 3, 2) { ok = false; }
  if !ok_is(queue_dequeue(), 1) { ok = false; }
  if queue_is_full() { ok = false; }
  if queue_is_empty() { ok = false; }
  if !ok_is(queue_enqueue(3), 0) { ok = false; }
  if !ok_is(queue_dequeue(), 2) { ok = false; }
  if !ok_is(queue_dequeue(), 3) { ok = false; }
  if queue_count() != 0 { ok = false; }
  if !queue_is_empty() { ok = false; }
  return assert(ok, "queue full/empty disambiguation by count");
}

fn t9() -> TestResult {
  var ok = ok_is(queue_configure(3), 3);
  if !ok_is(queue_enqueue(1), 0) { ok = false; }
  if !ok_is(queue_enqueue(2), 1) { ok = false; }
  if !ok_is(queue_enqueue(3), 2) { ok = false; }
  if queue_tail_counter() != 3 { ok = false; }
  if !ok_is(queue_dequeue(), 1) { ok = false; }
  if !ok_is(queue_enqueue(4), 0) { ok = false; }  // tail 3 wraps to slot 0
  if !ok_is(queue_dequeue(), 2) { ok = false; }
  if !ok_is(queue_enqueue(5), 1) { ok = false; }  // tail 4 wraps to slot 1
  if !ok_is(queue_dequeue(), 3) { ok = false; }
  if !ok_is(queue_dequeue(), 4) { ok = false; }
  if !ok_is(queue_dequeue(), 5) { ok = false; }
  if queue_head_counter() != 5 { ok = false; }
  if queue_tail_counter() != 5 { ok = false; }
  if queue_count() != 0 { ok = false; }
  if queue_enqueue_count() != 5 { ok = false; }
  if queue_dequeue_count() != 5 { ok = false; }
  return assert(ok, "queue wrap-around keeps monotonic counters");
}

fn t10() -> TestResult {
  var ok = ok_is(queue_configure(2), 2);
  if queue_cas_tail_step(1, 99) { ok = false; }
  if queue_tail_counter() != 0 { ok = false; }
  if queue_cas_failures() != 1 { ok = false; }
  if !queue_cas_tail_step(0, 0) { ok = false; }
  if queue_cas_successes() != 1 { ok = false; }
  if !ok_is(queue_enqueue(7), 0) { ok = false; }
  if queue_tail_counter() != 1 { ok = false; }
  if queue_cas_head_step(1, 99) { ok = false; }
  if queue_head_counter() != 0 { ok = false; }
  if queue_cas_failures() != 2 { ok = false; }
  if !queue_cas_head_step(0, 0) { ok = false; }
  if queue_cas_successes() != 3 { ok = false; }  // tail probe + enqueue + head probe
  if !ok_is(queue_dequeue(), 7) { ok = false; }
  if queue_cas_successes() != 4 { ok = false; }
  if queue_cas_failures() != 2 { ok = false; }
  return assert(ok, "queue cas steps: stale expected fails, exact expected succeeds");
}

fn t21() -> TestResult {
  var ok = ok_is(queue_configure(5), 5);
  var round = 0;
  while round < 12 {
    var j = 0;
    while j < 5 {
      let er = queue_enqueue(round * 5 + j);
      if !er.is_ok { ok = false; }
      j = j + 1;
    }
    if !queue_is_full() { ok = false; }
    if queue_count() != 5 { ok = false; }
    j = 0;
    while j < 5 {
      if ok_val(queue_dequeue()) != round * 5 + j { ok = false; }
      j = j + 1;
    }
    if !queue_is_empty() { ok = false; }
    round = round + 1;
  }
  if queue_head_counter() != 60 { ok = false; }
  if queue_tail_counter() != 60 { ok = false; }
  if queue_count() != 0 { ok = false; }
  if queue_enqueue_count() != 60 { ok = false; }
  if queue_dequeue_count() != 60 { ok = false; }
  if queue_cas_successes() != 120 { ok = false; }
  if queue_cas_failures() != 0 { ok = false; }
  return assert(ok, "queue stress: 60 FIFO elements through a 5-slot ring");
}

// --------------------------------------------------
//  Atomic counter
// --------------------------------------------------

fn t12() -> TestResult {
  counter_reset(5);
  var ok = counter_get() == 5;
  if !counter_cas_step(5, 9) { ok = false; }
  if counter_get() != 9 { ok = false; }
  if counter_cas_successes() != 1 { ok = false; }
  if counter_cas_failures() != 0 { ok = false; }
  if counter_min() != 0 { ok = false; }
  if counter_max() != _TF_COUNTER_MAX { ok = false; }
  return assert(ok, "counter cas step success path");
}

fn t13() -> TestResult {
  counter_reset(5);
  var ok = true;
  if counter_cas_step(6, 9) { ok = false; }
  if counter_get() != 5 { ok = false; }
  if counter_cas_failures() != 1 { ok = false; }
  if counter_cas_successes() != 0 { ok = false; }
  if !counter_cas_step(5, 9) { ok = false; }
  if counter_get() != 9 { ok = false; }
  if counter_cas_successes() != 1 { ok = false; }
  return assert(ok, "counter cas step failure path");
}

fn t14() -> TestResult {
  counter_reset(0);
  var ok = ok_is(counter_add(7), 7);
  if !ok_is(counter_add(5), 12) { ok = false; }
  if counter_get() != 12 { ok = false; }
  if !ok_is(counter_add(0), 12) { ok = false; }
  if counter_add_count() != 3 { ok = false; }
  if counter_cas_successes() != 3 { ok = false; }
  if counter_cas_failures() != 0 { ok = false; }
  return assert(ok, "counter add spins on cas and reports the new value");
}

fn t15() -> TestResult {
  counter_reset(3);
  var ok = err_is(counter_add(-5), 8, -5, 3);
  if counter_get() != 3 { ok = false; }
  if !ok_is(counter_add(-3), 0) { ok = false; }
  counter_reset(_TF_COUNTER_MAX);
  if !err_is(counter_add(1), 7, 1, _TF_COUNTER_MAX) { ok = false; }
  if counter_get() != _TF_COUNTER_MAX { ok = false; }
  if !err_is(counter_add(_TF_COUNTER_MAX), 7, _TF_COUNTER_MAX, _TF_COUNTER_MAX) { ok = false; }
  counter_reset(0);
  if !err_is(counter_add(0 - _TF_COUNTER_MAX), 8, 0 - _TF_COUNTER_MAX, 0) { ok = false; }
  if !ok_is(counter_add(2), 2) { ok = false; }
  if !ok_is(counter_add(_TF_COUNTER_MAX - 2), _TF_COUNTER_MAX) { ok = false; }
  if !err_is(counter_add(1), 7, 1, _TF_COUNTER_MAX) { ok = false; }
  if counter_add_count() != 2 { ok = false; }    // the reset before add(2) clears the count
  return assert(ok, "counter add overflow and underflow errors");
}

fn t16() -> TestResult {
  counter_reset(_TF_COUNTER_MAX - 2);
  var ok = counter_add_saturating(10) == _TF_COUNTER_MAX;
  counter_reset(2);
  if counter_add_saturating(0 - 10) != 0 { ok = false; }
  if counter_add_saturating(3) != 3 { ok = false; }
  if counter_add_saturating(0 - 1) != 2 { ok = false; }
  counter_reset(0);
  if counter_add_saturating(_TF_COUNTER_MAX) != _TF_COUNTER_MAX { ok = false; }
  if counter_add_saturating(_TF_COUNTER_MAX) != _TF_COUNTER_MAX { ok = false; }
  if counter_saturating_add_count() != 2 { ok = false; }  // last reset clears the earlier four
  if counter_cas_successes() != 2 { ok = false; }
  return assert(ok, "counter saturating add clamps at both bounds");
}

// --------------------------------------------------
//  Dumps, error catalog, independence
// --------------------------------------------------

fn t17() -> TestResult {
  var ok = ok_is(stack_configure(3), 3);
  if !ok_is(stack_push(7), 5) { ok = false; }   // cap 3 -> stride 4, tag 1, node 0
  if !ok_is(stack_push(8), 10) { ok = false; }
  let sd = stack_dump();
  if !str_contains(sd, "cap=3") { ok = false; }
  if !str_contains(sd, "count=2") { ok = false; }
  if !str_contains(sd, "head_idx=1") { ok = false; }
  if !str_contains(sd, "head_tag=2") { ok = false; }
  if !str_contains(sd, "free=1") { ok = false; }
  if !str_contains(sd, "top=8,7") { ok = false; }
  if !str_contains(sd, "cas_ok=2") { ok = false; }
  if !ok_is(queue_configure(2), 2) { ok = false; }
  if !ok_is(queue_enqueue(4), 0) { ok = false; }
  let qd = queue_dump();
  if !str_contains(qd, "cap=2") { ok = false; }
  if !str_contains(qd, "count=1") { ok = false; }
  if !str_contains(qd, "head=0") { ok = false; }
  if !str_contains(qd, "tail=1") { ok = false; }
  if !str_contains(qd, "full=0") { ok = false; }
  if !str_contains(qd, "empty=0") { ok = false; }
  if !str_contains(qd, "slots=4,0") { ok = false; }
  counter_reset(9);
  let cd = counter_dump();
  if !str_contains(cd, "value=9") { ok = false; }
  if !str_contains(cd, "max=4611686018427387903") { ok = false; }
  let ld = lockfree_dump();
  if !str_contains(ld, "stack[") { ok = false; }
  if !str_contains(ld, "queue[") { ok = false; }
  if !str_contains(ld, "counter[") { ok = false; }
  return assert(ok, "state dumps pin structure contents");
}

fn t18() -> TestResult {
  var ok = msg_is(1, "lockfree: stack capacity out of range");
  if !msg_is(2, "lockfree: stack is empty") { ok = false; }
  if !msg_is(3, "lockfree: stack node pool exhausted") { ok = false; }
  if !msg_is(4, "lockfree: queue capacity out of range") { ok = false; }
  if !msg_is(5, "lockfree: queue is empty") { ok = false; }
  if !msg_is(6, "lockfree: queue is full") { ok = false; }
  if !msg_is(7, "lockfree: counter overflow") { ok = false; }
  if !msg_is(8, "lockfree: counter underflow") { ok = false; }
  if !msg_is(99, "lockfree: unknown error") { ok = false; }
  if !msg_is(0, "lockfree: unknown error") { ok = false; }
  return assert(ok, "error catalog is pinned");
}

fn t11() -> TestResult {
  var ok = ok_is(stack_configure(3), 3);
  if !err_is(stack_configure(0), 1, 0, 4096) { ok = false; }
  if !err_is(stack_configure(4097), 1, 4097, 4096) { ok = false; }
  if stack_capacity() != 3 { ok = false; }
  if stack_count() != 0 { ok = false; }
  if !ok_is(stack_configure(1), 1) { ok = false; }
  if stack_capacity() != 1 { ok = false; }
  if !ok_is(stack_configure(4096), 4096) { ok = false; }
  if stack_max_capacity() != 4096 { ok = false; }
  if !ok_is(queue_configure(5), 5) { ok = false; }
  if !err_is(queue_configure(0), 4, 0, 65536) { ok = false; }
  if !err_is(queue_configure(65537), 4, 65537, 65536) { ok = false; }
  if queue_capacity() != 5 { ok = false; }
  if queue_count() != 0 { ok = false; }
  if !ok_is(queue_configure(1), 1) { ok = false; }
  if !ok_is(queue_configure(65536), 65536) { ok = false; }
  if queue_max_capacity() != 65536 { ok = false; }
  return assert(ok, "capacity validation for stack and queue");
}

fn t19() -> TestResult {
  var ok = ok_is(stack_configure(2), 2);
  if !ok_is(queue_configure(3), 3) { ok = false; }
  counter_reset(0);
  if !ok_is(stack_push(1), 4) { ok = false; }
  if !ok_is(stack_pop(), 1) { ok = false; }
  if !ok_is(queue_enqueue(5), 0) { ok = false; }
  if !ok_is(queue_dequeue(), 5) { ok = false; }
  if !ok_is(counter_add(2), 2) { ok = false; }
  if stack_push_count() != 1 { ok = false; }
  if stack_pop_count() != 1 { ok = false; }
  if stack_cas_successes() != 2 { ok = false; }
  if stack_count() != 0 { ok = false; }
  if queue_enqueue_count() != 1 { ok = false; }
  if queue_dequeue_count() != 1 { ok = false; }
  if queue_cas_successes() != 2 { ok = false; }
  if queue_count() != 0 { ok = false; }
  if queue_head_counter() != 1 { ok = false; }
  if queue_tail_counter() != 1 { ok = false; }
  if counter_get() != 2 { ok = false; }
  if counter_add_count() != 1 { ok = false; }
  if counter_cas_successes() != 1 { ok = false; }
  return assert(ok, "stack, queue and counter statistics are independent");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.lockfree conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.lockfree: all tests passed");
  } else {
    io.println("xiom.lockfree: tests failed");
  }
  return failed;
}
