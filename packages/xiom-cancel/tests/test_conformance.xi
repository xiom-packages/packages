// XIOM -- xiom.cancel conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.cancel token tree against its documented
// API (construction, parent/child links, strict and idempotent cancel,
// subtree propagation, logical-tick deadlines, counters, aggregation and the
// structural invariant).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison, so every name check below
// is routed through streq. Vec[Int] element reads use a typed `let`.
// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001); each helper calls the real `&`-based API.
// Int-code classifiers turn Result outcomes into small Int codes so the test
// bodies stay branch-free. Tests are called directly from main (no indexed
// Vec[fn] dispatch).

module cancel_tests
use xiom.io; use xiom.test; use xiom.cancel;
use xiom.string.compare;

const _E_TOKEN_ID: Str = "cancel: token id must be >= 0";
const _E_DUP_TOKEN: Str = "cancel: duplicate token id";
const _E_UNKNOWN_PARENT: Str = "cancel: unknown parent token id";
const _E_UNKNOWN_TOKEN: Str = "cancel: unknown token id";
const _E_ALREADY: Str = "cancel: already cancelled";
const _E_REASON_MIN: Str = "cancel: reason must be >= 1";
const _E_REASON_RESERVED: Str = "cancel: reason code is reserved";
const _E_CLOCK: Str = "cancel: clock cannot go backwards";
const _E_DEADLINE_MIN: Str = "cancel: deadline must be >= 0";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures and Result classifiers
// ---------------------------------------------------------------------------

// 1 -> 2 -> 4 and 1 -> 3; all ACTIVE.
fn tree_fixture() -> Canceller {
  var c = canceller_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2);
  add_child_ok(&mut c, 1, 3);
  add_child_ok(&mut c, 2, 4);
  return c;
}

// Added id on success, -1 on any error.
fn add_root_ok(c: &mut Canceller, id: Int) -> Int {
  match canceller_add_root(c, id) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn add_root_err_is(c: &mut Canceller, id: Int, want: Str) -> Bool {
  match canceller_add_root(c, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Added id on success, -1 on any error.
fn add_child_ok(c: &mut Canceller, parent: Int, id: Int) -> Int {
  match canceller_add_child(c, parent, id) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn add_child_err_is(c: &mut Canceller, parent: Int, id: Int, want: Str) -> Bool {
  match canceller_add_child(c, parent, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn cancel_ok(c: &mut Canceller, id: Int, reason: Int) -> Int {
  match canceller_cancel(c, id, reason) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn cancel_err_is(c: &mut Canceller, id: Int, reason: Int, want: Str) -> Bool {
  match canceller_cancel(c, id, reason) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn idem_ok(c: &mut Canceller, id: Int, reason: Int) -> Int {
  match canceller_cancel_idempotent(c, id, reason) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn idem_err_is(c: &mut Canceller, id: Int, reason: Int, want: Str) -> Bool {
  match canceller_cancel_idempotent(c, id, reason) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// New clock value on success, -1 on any error.
fn advance_ok(c: &mut Canceller, to: Int) -> Int {
  match canceller_advance(c, to) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn advance_err_is(c: &mut Canceller, to: Int, want: Str) -> Bool {
  match canceller_advance(c, to) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Set deadline on success, -1 on any error.
fn set_deadline_ok(c: &mut Canceller, id: Int, tick: Int) -> Int {
  match canceller_set_deadline(c, id, tick) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn set_deadline_err_is(c: &mut Canceller, id: Int, tick: Int, want: Str) -> Bool {
  match canceller_set_deadline(c, id, tick) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Clear deadline on success (-1), -2 on any error.
fn clear_deadline_ok(c: &mut Canceller, id: Int) -> Int {
  match canceller_clear_deadline(c, id) {
    Ok(v) => { return v; },
    Err(_) => { return -2; },
  }
  return -2;
}

fn clear_deadline_err_is(c: &mut Canceller, id: Int, want: Str) -> Bool {
  match canceller_clear_deadline(c, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn check_deadline_ok(c: &mut Canceller, id: Int) -> Int {
  match canceller_check_deadline(c, id) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn check_deadline_err_is(c: &mut Canceller, id: Int, want: Str) -> Bool {
  match canceller_check_deadline(c, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn tick_ok(c: &mut Canceller, to: Int) -> Int {
  match canceller_tick(c, to) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn tick_err_is(c: &mut Canceller, to: Int, want: Str) -> Bool {
  match canceller_tick(c, to) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Sweep count.
fn sweep_of(c: &mut Canceller) -> Int {
  return canceller_sweep(c);
}

// ---------------------------------------------------------------------------
// Read-only accessors routed through `&mut` (advisory E001).
// ---------------------------------------------------------------------------

fn token_count_of(c: &mut Canceller) -> Int {
  return canceller_token_count(c);
}

fn has_token_of(c: &mut Canceller, id: Int) -> Bool {
  return canceller_has_token(c, id);
}

fn state_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_state(c, id);
}

fn is_cancelled_of(c: &mut Canceller, id: Int) -> Bool {
  return canceller_is_cancelled(c, id);
}

fn is_active_of(c: &mut Canceller, id: Int) -> Bool {
  return canceller_is_active(c, id);
}

fn reason_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_reason(c, id);
}

fn source_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_source(c, id);
}

fn cancel_tick_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_cancel_tick(c, id);
}

fn parent_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_parent(c, id);
}

fn child_count_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_child_count(c, id);
}

fn children_of(c: &mut Canceller, id: Int) -> Vec[Int] {
  return canceller_children(c, id);
}

fn depth_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_depth(c, id);
}

fn root_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_root_of(c, id);
}

fn is_ancestor_of(c: &mut Canceller, ancestor: Int, id: Int) -> Bool {
  return canceller_is_ancestor(c, ancestor, id);
}

fn now_of(c: &mut Canceller) -> Int {
  return canceller_now(c);
}

fn deadline_of(c: &mut Canceller, id: Int) -> Int {
  return canceller_deadline(c, id);
}

fn has_deadline_of(c: &mut Canceller, id: Int) -> Bool {
  return canceller_has_deadline(c, id);
}

fn cancelled_count_of(c: &mut Canceller) -> Int {
  return canceller_cancelled_count(c);
}

fn active_count_of(c: &mut Canceller) -> Int {
  return canceller_active_count(c);
}

fn direct_of(c: &mut Canceller) -> Int {
  return canceller_direct_cancels(c);
}

fn deadline_count_of(c: &mut Canceller) -> Int {
  return canceller_deadline_cancels(c);
}

fn propagated_of(c: &mut Canceller) -> Int {
  return canceller_propagated_cancels(c);
}

fn invariant_of(c: &mut Canceller) -> Bool {
  return canceller_check_invariant(c);
}

fn aggregate_of(c: &mut Canceller, ids: &Vec[Int]) -> Int {
  return canceller_aggregate(c, ids);
}

fn any_of(c: &mut Canceller, ids: &Vec[Int]) -> Bool {
  return canceller_any_cancelled(c, ids);
}

fn all_of(c: &mut Canceller, ids: &Vec[Int]) -> Bool {
  return canceller_all_cancelled(c, ids);
}

fn count_cancelled_of(c: &mut Canceller, ids: &Vec[Int]) -> Int {
  return canceller_count_cancelled(c, ids);
}

fn first_cancelled_of(c: &mut Canceller, ids: &Vec[Int]) -> Int {
  return canceller_first_cancelled(c, ids);
}

fn worst_reason_of(c: &mut Canceller, ids: &Vec[Int]) -> Int {
  return canceller_worst_reason(c, ids);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var c = canceller_new();
  var ok = token_count_of(&mut c) == 0;
  if cancelled_count_of(&mut c) != 0 { ok = false; }
  if active_count_of(&mut c) != 0 { ok = false; }
  if now_of(&mut c) != 0 { ok = false; }
  if direct_of(&mut c) != 0 { ok = false; }
  if deadline_count_of(&mut c) != 0 { ok = false; }
  if propagated_of(&mut c) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "canceller_new starts empty with a zero clock and counters");
}

fn t2() -> TestResult {
  var c = canceller_new();
  var ok = add_root_err_is(&mut c, -1, _E_TOKEN_ID);
  if add_root_ok(&mut c, 1) != 1 { ok = false; }
  if add_root_ok(&mut c, 2) != 2 { ok = false; }
  if !add_root_err_is(&mut c, 2, _E_DUP_TOKEN) { ok = false; }
  if token_count_of(&mut c) != 2 { ok = false; }
  if parent_of(&mut c, 1) != CANCEL_NO_PARENT { ok = false; }
  if depth_of(&mut c, 1) != 0 { ok = false; }
  if root_of(&mut c, 1) != 1 { ok = false; }
  if child_count_of(&mut c, 1) != 0 { ok = false; }
  var kids = children_of(&mut c, 1);
  if kids.len() != 0 { ok = false; }
  if state_of(&mut c, 1) != CANCEL_STATE_ACTIVE { ok = false; }
  if !is_active_of(&mut c, 1) { ok = false; }
  if is_cancelled_of(&mut c, 1) { ok = false; }
  if reason_of(&mut c, 1) != CANCEL_REASON_NONE { ok = false; }
  if source_of(&mut c, 1) != CANCEL_NOT_FOUND { ok = false; }
  if cancel_tick_of(&mut c, 1) != CANCEL_NOT_FOUND { ok = false; }
  if deadline_of(&mut c, 1) != CANCEL_NO_DEADLINE { ok = false; }
  if has_deadline_of(&mut c, 1) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "add_root validates ids and creates ACTIVE parentless tokens");
}

fn t3() -> TestResult {
  var c = canceller_new();
  var ok = add_child_err_is(&mut c, 1, 2, _E_UNKNOWN_PARENT);
  if add_root_ok(&mut c, 1) != 1 { ok = false; }
  if !add_child_err_is(&mut c, 1, -5, _E_TOKEN_ID) { ok = false; }
  if add_child_ok(&mut c, 1, 2) != 2 { ok = false; }
  if add_child_ok(&mut c, 1, 3) != 3 { ok = false; }
  if add_child_ok(&mut c, 2, 4) != 4 { ok = false; }
  if !add_child_err_is(&mut c, 1, 2, _E_DUP_TOKEN) { ok = false; }
  if token_count_of(&mut c) != 4 { ok = false; }
  if parent_of(&mut c, 2) != 1 { ok = false; }
  if parent_of(&mut c, 3) != 1 { ok = false; }
  if parent_of(&mut c, 4) != 2 { ok = false; }
  if child_count_of(&mut c, 1) != 2 { ok = false; }
  if child_count_of(&mut c, 4) != 0 { ok = false; }
  var kids = children_of(&mut c, 1);
  if kids.len() != 2 { ok = false; }
  let first_kid: Int = kids[0];
  let second_kid: Int = kids[1];
  if first_kid != 2 { ok = false; }
  if second_kid != 3 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "add_child validates ids and links children in creation order");
}

fn t4() -> TestResult {
  var c = tree_fixture();
  var ok = depth_of(&mut c, 1) == 0;
  if depth_of(&mut c, 2) != 1 { ok = false; }
  if depth_of(&mut c, 3) != 1 { ok = false; }
  if depth_of(&mut c, 4) != 2 { ok = false; }
  if depth_of(&mut c, 99) != CANCEL_NOT_FOUND { ok = false; }
  if root_of(&mut c, 4) != 1 { ok = false; }
  if root_of(&mut c, 3) != 1 { ok = false; }
  if root_of(&mut c, 99) != CANCEL_NOT_FOUND { ok = false; }
  if !is_ancestor_of(&mut c, 1, 4) { ok = false; }
  if !is_ancestor_of(&mut c, 2, 4) { ok = false; }
  if is_ancestor_of(&mut c, 1, 1) { ok = false; }
  if is_ancestor_of(&mut c, 4, 1) { ok = false; }
  if is_ancestor_of(&mut c, 99, 1) { ok = false; }
  if is_ancestor_of(&mut c, 1, 99) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "parent/child links expose depth, roots and ancestor relations");
}

fn t5() -> TestResult {
  var c = tree_fixture();
  var ok = cancel_ok(&mut c, 4, CANCEL_REASON_USER) == 1;
  if state_of(&mut c, 4) != CANCEL_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 4) != CANCEL_REASON_USER { ok = false; }
  if source_of(&mut c, 4) != 4 { ok = false; }
  if cancel_tick_of(&mut c, 4) != 0 { ok = false; }
  if cancelled_count_of(&mut c) != 1 { ok = false; }
  if active_count_of(&mut c) != 3 { ok = false; }
  if direct_of(&mut c) != 1 { ok = false; }
  if propagated_of(&mut c) != 0 { ok = false; }
  if deadline_count_of(&mut c) != 0 { ok = false; }
  if !cancel_err_is(&mut c, 4, CANCEL_REASON_USER, _E_ALREADY) { ok = false; }
  if state_of(&mut c, 2) != CANCEL_STATE_ACTIVE { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "cancelling a leaf cancels exactly one token with its reason and tick");
}

fn t6() -> TestResult {
  var c = tree_fixture();
  var ok = cancel_ok(&mut c, 1, CANCEL_REASON_SHUTDOWN) == 4;
  if cancelled_count_of(&mut c) != 4 { ok = false; }
  if active_count_of(&mut c) != 0 { ok = false; }
  if reason_of(&mut c, 1) != CANCEL_REASON_SHUTDOWN { ok = false; }
  if source_of(&mut c, 1) != 1 { ok = false; }
  if reason_of(&mut c, 2) != CANCEL_REASON_PARENT { ok = false; }
  if reason_of(&mut c, 3) != CANCEL_REASON_PARENT { ok = false; }
  if reason_of(&mut c, 4) != CANCEL_REASON_PARENT { ok = false; }
  if source_of(&mut c, 2) != 1 { ok = false; }
  if source_of(&mut c, 3) != 1 { ok = false; }
  if source_of(&mut c, 4) != 1 { ok = false; }
  if cancel_tick_of(&mut c, 4) != 0 { ok = false; }
  if direct_of(&mut c) != 1 { ok = false; }
  if propagated_of(&mut c) != 3 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "cancelling a root propagates PARENT cancellation to every descendant");
}

fn t7() -> TestResult {
  var c = tree_fixture();
  var ok = cancel_ok(&mut c, 1, CANCEL_REASON_USER) == 4;
  if !cancel_err_is(&mut c, 1, CANCEL_REASON_USER, _E_ALREADY) { ok = false; }
  if !cancel_err_is(&mut c, 2, CANCEL_REASON_SHUTDOWN, _E_ALREADY) { ok = false; }
  if !cancel_err_is(&mut c, 4, CANCEL_REASON_USER, _E_ALREADY) { ok = false; }
  if direct_of(&mut c) != 1 { ok = false; }
  if !cancel_err_is(&mut c, 99, CANCEL_REASON_USER, _E_UNKNOWN_TOKEN) { ok = false; }
  if add_root_ok(&mut c, 9) != 9 { ok = false; }
  if cancel_ok(&mut c, 9, CANCEL_REASON_USER) != 1 { ok = false; }
  if direct_of(&mut c) != 2 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "strict cancel refuses repeats and unknown ids without changing state");
}

fn t8() -> TestResult {
  var c = tree_fixture();
  var ok = idem_ok(&mut c, 1, CANCEL_REASON_USER) == 4;
  if idem_ok(&mut c, 1, CANCEL_REASON_USER) != 0 { ok = false; }
  if direct_of(&mut c) != 1 { ok = false; }
  if propagated_of(&mut c) != 3 { ok = false; }
  if !idem_err_is(&mut c, 99, CANCEL_REASON_USER, _E_UNKNOWN_TOKEN) { ok = false; }
  if !idem_err_is(&mut c, 2, CANCEL_REASON_DEADLINE, _E_REASON_RESERVED) { ok = false; }
  if !idem_err_is(&mut c, 2, 0, _E_REASON_MIN) { ok = false; }
  if add_root_ok(&mut c, 9) != 9 { ok = false; }
  if idem_ok(&mut c, 9, CANCEL_REASON_SHUTDOWN) != 1 { ok = false; }
  if idem_ok(&mut c, 9, CANCEL_REASON_SHUTDOWN) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "cancel_idempotent is a no-op on repeat and still validates input");
}

fn t9() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if !cancel_err_is(&mut c, 1, 0, _E_REASON_MIN) { ok = false; }
  if !cancel_err_is(&mut c, 1, -3, _E_REASON_MIN) { ok = false; }
  if !cancel_err_is(&mut c, 1, CANCEL_REASON_DEADLINE, _E_REASON_RESERVED) { ok = false; }
  if !cancel_err_is(&mut c, 1, CANCEL_REASON_PARENT, _E_REASON_RESERVED) { ok = false; }
  if state_of(&mut c, 1) != CANCEL_STATE_ACTIVE { ok = false; }
  if add_root_ok(&mut c, 2) != 2 { ok = false; }
  if cancel_ok(&mut c, 2, CANCEL_REASON_SHUTDOWN) != 1 { ok = false; }
  if reason_of(&mut c, 2) != CANCEL_REASON_SHUTDOWN { ok = false; }
  if cancel_ok(&mut c, 1, 9) != 1 { ok = false; }
  if reason_of(&mut c, 1) != 9 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "cancel validates reason >= 1, reserves 2/3 and accepts custom codes");
}

fn t10() -> TestResult {
  var c = tree_fixture();
  var ok = state_of(&mut c, 99) == CANCEL_NOT_FOUND;
  if is_cancelled_of(&mut c, 99) { ok = false; }
  if is_active_of(&mut c, 99) { ok = false; }
  if reason_of(&mut c, 99) != CANCEL_NOT_FOUND { ok = false; }
  if source_of(&mut c, 99) != CANCEL_NOT_FOUND { ok = false; }
  if cancel_tick_of(&mut c, 99) != CANCEL_NOT_FOUND { ok = false; }
  if parent_of(&mut c, 99) != CANCEL_NO_PARENT { ok = false; }
  if child_count_of(&mut c, 99) != 0 { ok = false; }
  var kids = children_of(&mut c, 99);
  if kids.len() != 0 { ok = false; }
  if depth_of(&mut c, 99) != CANCEL_NOT_FOUND { ok = false; }
  if root_of(&mut c, 99) != CANCEL_NOT_FOUND { ok = false; }
  if has_token_of(&mut c, 99) { ok = false; }
  if !has_token_of(&mut c, 1) { ok = false; }
  if token_count_of(&mut c) != 4 { ok = false; }
  if deadline_of(&mut c, 99) != CANCEL_NO_DEADLINE { ok = false; }
  if has_deadline_of(&mut c, 99) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "unknown ids yield sentinels instead of errors");
}

fn t11() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if cancel_ok(&mut c, 1, CANCEL_REASON_USER) != 1 { ok = false; }
  if add_child_ok(&mut c, 1, 2) != 2 { ok = false; }
  if state_of(&mut c, 2) != CANCEL_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 2) != CANCEL_REASON_PARENT { ok = false; }
  if source_of(&mut c, 2) != 1 { ok = false; }
  if cancel_tick_of(&mut c, 2) != 0 { ok = false; }
  if add_child_ok(&mut c, 2, 3) != 3 { ok = false; }
  if state_of(&mut c, 3) != CANCEL_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 3) != CANCEL_REASON_PARENT { ok = false; }
  if source_of(&mut c, 3) != 1 { ok = false; }
  if direct_of(&mut c) != 1 { ok = false; }
  if propagated_of(&mut c) != 2 { ok = false; }
  if cancelled_count_of(&mut c) != 3 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "a child added under a cancelled parent is born cancelled with the origin source");
}

fn t12() -> TestResult {
  var c = tree_fixture();
  var ok = cancel_ok(&mut c, 2, CANCEL_REASON_USER) == 2;
  if !is_cancelled_of(&mut c, 4) { ok = false; }
  if add_child_ok(&mut c, 1, 5) != 5 { ok = false; }
  if state_of(&mut c, 5) != CANCEL_STATE_ACTIVE { ok = false; }
  if cancel_ok(&mut c, 1, CANCEL_REASON_USER) != 3 { ok = false; }
  if reason_of(&mut c, 5) != CANCEL_REASON_PARENT { ok = false; }
  if source_of(&mut c, 5) != 1 { ok = false; }
  if direct_of(&mut c) != 2 { ok = false; }
  if propagated_of(&mut c) != 3 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "children added under an active parent stay active until cancelled");
}

fn t13() -> TestResult {
  var c = tree_fixture();
  var ok = set_deadline_ok(&mut c, 1, 5) == 5;
  if deadline_of(&mut c, 1) != 5 { ok = false; }
  if !has_deadline_of(&mut c, 1) { ok = false; }
  if set_deadline_ok(&mut c, 1, 7) != 7 { ok = false; }
  if deadline_of(&mut c, 1) != 7 { ok = false; }
  if clear_deadline_ok(&mut c, 1) != CANCEL_NO_DEADLINE { ok = false; }
  if has_deadline_of(&mut c, 1) { ok = false; }
  if !set_deadline_err_is(&mut c, 99, 1, _E_UNKNOWN_TOKEN) { ok = false; }
  if !set_deadline_err_is(&mut c, 1, -1, _E_DEADLINE_MIN) { ok = false; }
  if !clear_deadline_err_is(&mut c, 99, _E_UNKNOWN_TOKEN) { ok = false; }
  if cancel_ok(&mut c, 1, CANCEL_REASON_USER) != 4 { ok = false; }
  if !set_deadline_err_is(&mut c, 1, 2, _E_ALREADY) { ok = false; }
  if !clear_deadline_err_is(&mut c, 1, _E_ALREADY) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "set/clear_deadline validate ids, ticks and token state");
}

fn t14() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if set_deadline_ok(&mut c, 1, 5) != 5 { ok = false; }
  if check_deadline_ok(&mut c, 1) != 0 { ok = false; }
  if !is_active_of(&mut c, 1) { ok = false; }
  if advance_ok(&mut c, 5) != 5 { ok = false; }
  if check_deadline_ok(&mut c, 1) != 1 { ok = false; }
  if state_of(&mut c, 1) != CANCEL_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 1) != CANCEL_REASON_DEADLINE { ok = false; }
  if source_of(&mut c, 1) != 1 { ok = false; }
  if cancel_tick_of(&mut c, 1) != 5 { ok = false; }
  if check_deadline_ok(&mut c, 1) != 0 { ok = false; }
  if deadline_count_of(&mut c) != 1 { ok = false; }
  if direct_of(&mut c) != 0 { ok = false; }
  if !check_deadline_err_is(&mut c, 99, _E_UNKNOWN_TOKEN) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "check_deadline cancels a due token exactly once with reason DEADLINE");
}

fn t15() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if add_child_ok(&mut c, 1, 2) != 2 { ok = false; }
  if add_child_ok(&mut c, 2, 3) != 3 { ok = false; }
  if set_deadline_ok(&mut c, 1, 3) != 3 { ok = false; }
  if advance_ok(&mut c, 3) != 3 { ok = false; }
  if check_deadline_ok(&mut c, 1) != 3 { ok = false; }
  if reason_of(&mut c, 1) != CANCEL_REASON_DEADLINE { ok = false; }
  if source_of(&mut c, 1) != 1 { ok = false; }
  if reason_of(&mut c, 2) != CANCEL_REASON_PARENT { ok = false; }
  if source_of(&mut c, 3) != 1 { ok = false; }
  if cancel_tick_of(&mut c, 3) != 3 { ok = false; }
  if deadline_count_of(&mut c) != 1 { ok = false; }
  if propagated_of(&mut c) != 2 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "a deadline cancel propagates to descendants like any other cancel");
}

fn t16() -> TestResult {
  var c = canceller_new();
  var ok = now_of(&mut c) == 0;
  if !advance_err_is(&mut c, -1, _E_CLOCK) { ok = false; }
  if advance_ok(&mut c, 4) != 4 { ok = false; }
  if now_of(&mut c) != 4 { ok = false; }
  if advance_ok(&mut c, 4) != 4 { ok = false; }
  if !advance_err_is(&mut c, 3, _E_CLOCK) { ok = false; }
  if add_root_ok(&mut c, 1) != 1 { ok = false; }
  if add_root_ok(&mut c, 2) != 2 { ok = false; }
  if set_deadline_ok(&mut c, 1, 10) != 10 { ok = false; }
  if set_deadline_ok(&mut c, 2, 5) != 5 { ok = false; }
  if sweep_of(&mut c) != 0 { ok = false; }
  if advance_ok(&mut c, 6) != 6 { ok = false; }
  if sweep_of(&mut c) != 1 { ok = false; }
  if !is_cancelled_of(&mut c, 2) { ok = false; }
  if !is_active_of(&mut c, 1) { ok = false; }
  if sweep_of(&mut c) != 0 { ok = false; }
  if !tick_err_is(&mut c, 5, _E_CLOCK) { ok = false; }
  if tick_ok(&mut c, 10) != 1 { ok = false; }
  if !is_cancelled_of(&mut c, 1) { ok = false; }
  if deadline_count_of(&mut c) != 2 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "the clock is monotonic and sweep cancels only due tokens");
}

fn t17() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if add_child_ok(&mut c, 1, 2) != 2 { ok = false; }
  if add_child_ok(&mut c, 2, 3) != 3 { ok = false; }
  if add_root_ok(&mut c, 4) != 4 { ok = false; }
  if set_deadline_ok(&mut c, 1, 2) != 2 { ok = false; }
  if set_deadline_ok(&mut c, 2, 2) != 2 { ok = false; }
  if set_deadline_ok(&mut c, 3, 2) != 2 { ok = false; }
  if set_deadline_ok(&mut c, 4, 9) != 9 { ok = false; }
  if tick_ok(&mut c, 2) != 3 { ok = false; }
  if reason_of(&mut c, 1) != CANCEL_REASON_DEADLINE { ok = false; }
  if reason_of(&mut c, 3) != CANCEL_REASON_PARENT { ok = false; }
  if deadline_count_of(&mut c) != 1 { ok = false; }
  if propagated_of(&mut c) != 2 { ok = false; }
  if !is_active_of(&mut c, 4) { ok = false; }
  if tick_ok(&mut c, 9) != 1 { ok = false; }
  if reason_of(&mut c, 4) != CANCEL_REASON_DEADLINE { ok = false; }
  if deadline_count_of(&mut c) != 2 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "tick advances and sweeps; cascading due deadlines cancel each token once");
}

fn t18() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if add_root_ok(&mut c, 2) != 2 { ok = false; }
  if add_root_ok(&mut c, 3) != 3 { ok = false; }
  if cancel_ok(&mut c, 2, CANCEL_REASON_USER) != 1 { ok = false; }
  var empty = Vec[Int].new();
  var some = Vec[Int].new();
  some.push(1);
  some.push(2);
  var all = Vec[Int].new();
  all.push(2);
  var none = Vec[Int].new();
  none.push(1);
  none.push(3);
  var unknown = Vec[Int].new();
  unknown.push(2);
  unknown.push(99);
  if aggregate_of(&mut c, &empty) != CANCEL_AGG_EMPTY { ok = false; }
  if aggregate_of(&mut c, &some) != CANCEL_AGG_SOME { ok = false; }
  if aggregate_of(&mut c, &all) != CANCEL_AGG_ALL { ok = false; }
  if aggregate_of(&mut c, &none) != CANCEL_AGG_NONE { ok = false; }
  if aggregate_of(&mut c, &unknown) != CANCEL_AGG_UNKNOWN { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "aggregate classifies EMPTY/NONE/SOME/ALL and flags unknown ids");
}

fn t19() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if add_root_ok(&mut c, 2) != 2 { ok = false; }
  if add_root_ok(&mut c, 3) != 3 { ok = false; }
  if add_root_ok(&mut c, 4) != 4 { ok = false; }
  if cancel_ok(&mut c, 1, CANCEL_REASON_USER) != 1 { ok = false; }
  if cancel_ok(&mut c, 3, CANCEL_REASON_SHUTDOWN) != 1 { ok = false; }
  if cancel_ok(&mut c, 4, CANCEL_REASON_USER) != 1 { ok = false; }
  var mixed = Vec[Int].new();
  mixed.push(1);
  mixed.push(2);
  mixed.push(3);
  var cancelled_only = Vec[Int].new();
  cancelled_only.push(1);
  cancelled_only.push(3);
  var active_only = Vec[Int].new();
  active_only.push(2);
  var with_unknown = Vec[Int].new();
  with_unknown.push(1);
  with_unknown.push(99);
  var reversed = Vec[Int].new();
  reversed.push(2);
  reversed.push(3);
  reversed.push(1);
  var empty = Vec[Int].new();
  if !any_of(&mut c, &mixed) { ok = false; }
  if any_of(&mut c, &active_only) { ok = false; }
  if any_of(&mut c, &empty) { ok = false; }
  if !all_of(&mut c, &cancelled_only) { ok = false; }
  if all_of(&mut c, &mixed) { ok = false; }
  if all_of(&mut c, &with_unknown) { ok = false; }
  if !all_of(&mut c, &empty) { ok = false; }
  if count_cancelled_of(&mut c, &mixed) != 2 { ok = false; }
  if count_cancelled_of(&mut c, &empty) != 0 { ok = false; }
  if first_cancelled_of(&mut c, &reversed) != 3 { ok = false; }
  if first_cancelled_of(&mut c, &active_only) != CANCEL_NOT_FOUND { ok = false; }
  if worst_reason_of(&mut c, &cancelled_only) != CANCEL_REASON_SHUTDOWN { ok = false; }
  if worst_reason_of(&mut c, &active_only) != CANCEL_REASON_NONE { ok = false; }
  if worst_reason_of(&mut c, &empty) != CANCEL_REASON_NONE { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "any/all/count/first/worst aggregate helpers are exact");
}

fn t20() -> TestResult {
  var c = tree_fixture();
  var ok = token_count_of(&mut c) == 4;
  if token_count_of(&mut c) != 4 { ok = false; }
  var kids = children_of(&mut c, 1);
  if kids.len() != 2 { ok = false; }
  kids.push(99);
  if child_count_of(&mut c, 1) != 2 { ok = false; }
  if token_count_of(&mut c) != 4 { ok = false; }
  var ids = Vec[Int].new();
  ids.push(1);
  ids.push(2);
  if aggregate_of(&mut c, &ids) != CANCEL_AGG_NONE { ok = false; }
  if ids.len() != 2 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "children copies are independent and aggregation does not consume its list");
}

fn t21() -> TestResult {
  var c = canceller_new();
  var ok = true;
  var i = 0;
  while i < 24 {
    let r = 100 + i;
    let ch = 200 + i;
    if add_root_ok(&mut c, r) != r { ok = false; }
    if add_child_ok(&mut c, r, ch) != ch { ok = false; }
    if set_deadline_ok(&mut c, ch, (i % 3) + 1) < 0 { ok = false; }
    if advance_ok(&mut c, i) < 0 { ok = false; }
    if sweep_of(&mut c) > 2 { ok = false; }
    if idem_ok(&mut c, r, CANCEL_REASON_USER) < 0 { ok = false; }
    if idem_ok(&mut c, ch, CANCEL_REASON_SHUTDOWN) < 0 { ok = false; }
    if !invariant_of(&mut c) { ok = false; }
    i = i + 1;
  }
  if token_count_of(&mut c) != 48 { ok = false; }
  if cancelled_count_of(&mut c) != 48 { ok = false; }
  if active_count_of(&mut c) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "the invariant holds across 24 deterministic add/cancel/sweep cycles");
}

fn t22() -> TestResult {
  var ok = streq(canceller_state_name(CANCEL_STATE_ACTIVE), "active");
  if !streq(canceller_state_name(CANCEL_STATE_CANCELLED), "cancelled") { ok = false; }
  if !streq(canceller_state_name(7), "unknown") { ok = false; }
  if !streq(cancel_reason_name(CANCEL_REASON_NONE), "none") { ok = false; }
  if !streq(cancel_reason_name(CANCEL_REASON_USER), "user") { ok = false; }
  if !streq(cancel_reason_name(CANCEL_REASON_DEADLINE), "deadline") { ok = false; }
  if !streq(cancel_reason_name(CANCEL_REASON_PARENT), "parent") { ok = false; }
  if !streq(cancel_reason_name(CANCEL_REASON_SHUTDOWN), "shutdown") { ok = false; }
  if !streq(cancel_reason_name(9), "custom") { ok = false; }
  if !streq(cancel_reason_name(-1), "unknown") { ok = false; }
  if !streq(canceller_aggregate_name(CANCEL_AGG_NONE), "none") { ok = false; }
  if !streq(canceller_aggregate_name(CANCEL_AGG_SOME), "some") { ok = false; }
  if !streq(canceller_aggregate_name(CANCEL_AGG_ALL), "all") { ok = false; }
  if !streq(canceller_aggregate_name(CANCEL_AGG_EMPTY), "empty") { ok = false; }
  if !streq(canceller_aggregate_name(CANCEL_AGG_UNKNOWN), "unknown") { ok = false; }
  if !streq(canceller_aggregate_name(9), "invalid") { ok = false; }
  return assert(ok, "state, reason and aggregate name helpers are stable");
}

fn t23() -> TestResult {
  var c = canceller_new();
  var ok = advance_ok(&mut c, 12) == 12;
  if add_root_ok(&mut c, 1) != 1 { ok = false; }
  if cancel_ok(&mut c, 1, CANCEL_REASON_USER) != 1 { ok = false; }
  if cancel_tick_of(&mut c, 1) != 12 { ok = false; }
  if add_child_ok(&mut c, 1, 2) != 2 { ok = false; }
  if cancel_tick_of(&mut c, 2) != 12 { ok = false; }
  if advance_ok(&mut c, 20) != 20 { ok = false; }
  if cancel_tick_of(&mut c, 1) != 12 { ok = false; }
  if now_of(&mut c) != 20 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "cancel ticks record the logical clock at cancellation time");
}

fn t24() -> TestResult {
  var c = canceller_new();
  var ok = add_root_ok(&mut c, 1) == 1;
  if add_child_ok(&mut c, 1, 2) != 2 { ok = false; }
  if add_child_ok(&mut c, 2, 3) != 3 { ok = false; }
  if add_child_ok(&mut c, 3, 4) != 4 { ok = false; }
  if add_child_ok(&mut c, 2, 5) != 5 { ok = false; }
  if add_child_ok(&mut c, 3, 6) != 6 { ok = false; }
  if add_child_ok(&mut c, 1, 7) != 7 { ok = false; }
  if token_count_of(&mut c) != 7 { ok = false; }
  if cancel_ok(&mut c, 1, CANCEL_REASON_SHUTDOWN) != 7 { ok = false; }
  if cancelled_count_of(&mut c) != 7 { ok = false; }
  if direct_of(&mut c) != 1 { ok = false; }
  if propagated_of(&mut c) != 6 { ok = false; }
  if reason_of(&mut c, 7) != CANCEL_REASON_PARENT { ok = false; }
  if source_of(&mut c, 6) != 1 { ok = false; }
  if !cancel_err_is(&mut c, 4, CANCEL_REASON_USER, _E_ALREADY) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "a 7-node tree cancels in one call with exact propagation counts");
}

fn main() -> Int {
  io.println("=== xiom.cancel conformance tests ===");
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
    io.println("xiom.cancel: all tests passed");
  } else {
    io.println("xiom.cancel: tests failed");
  }
  return failed;
}
