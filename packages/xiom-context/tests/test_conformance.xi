// XIOM -- xiom.context conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.context parent-chain model against its
// documented API (construction, lookup shadowing, path rendering, deadline
// inheritance and expiry, cancellation propagation, flattening and the
// structural invariants).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare (streq): `==` on Str values read
// from buffers lowers to a pointer comparison, so every name/key/value check
// below is routed through streq. Vec[Int] element reads use a typed `let`.
// Read-only operations are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001); each helper calls the real `&`-based API.
// Int-code classifiers turn Result outcomes into small Int codes so the test
// bodies stay branch-free. Tests are called directly from main (no indexed
// Vec[fn] dispatch). Keys and values are passed as Str values only; no
// Vec[Str] is constructed anywhere (dynamic Vec[Str].push is avoided).

module context_tests
use xiom.io; use xiom.test; use xiom.context;
use xiom.string.compare; use xiom.convert;

const _E_ID: Str = "context: id must be >= 0";
const _E_DUP: Str = "context: duplicate id";
const _E_PARENT: Str = "context: unknown parent id";
const _E_DL: Str = "context: deadline must be >= -1";
const _E_UNKNOWN: Str = "context: unknown id";
const _E_REASON_MIN: Str = "context: reason must be >= 1";
const _E_REASON_RESERVED: Str = "context: reason code is reserved";
const _E_ALREADY: Str = "context: already cancelled";
const _E_CLOCK: Str = "context: clock cannot go backwards";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// 1 -> 2 (tenant/acme) -> 3 (route//v1); no deadlines.
fn chain3() -> Context {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "tenant", "acme", -1);
  add_child_ok(&mut c, 2, 3, "route", "/v1", -1);
  return c;
}

// 1 -> 2, 1 -> 3, 2 -> 4; no keys.
fn tree_fixture() -> Context {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "a", "A", -1);
  add_child_ok(&mut c, 1, 3, "b", "B", -1);
  add_child_ok(&mut c, 2, 4, "c", "C", -1);
  return c;
}

// 1 -> 2 (org/acme-corp) -> 3 (tenant/acme) -> 4 (tenant/beta)
// -> 5 (tenant/gamma): tenant shadows three times along the chain.
fn shadow_fixture() -> Context {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "org", "acme-corp", -1);
  add_child_ok(&mut c, 2, 3, "tenant", "acme", -1);
  add_child_ok(&mut c, 3, 4, "tenant", "beta", -1);
  add_child_ok(&mut c, 4, 5, "tenant", "gamma", -1);
  return c;
}

// 10 (none) -> 11 (50) -> 12 (30) -> 13 (inherit 30); 11 -> 14 (90 => 50).
fn deadline_fixture() -> Context {
  var c = ctx_new();
  add_root_ok(&mut c, 10);
  add_child_ok(&mut c, 10, 11, "a", "A", 50);
  add_child_ok(&mut c, 11, 12, "b", "B", 30);
  add_child_ok(&mut c, 12, 13, "c", "C", -1);
  add_child_ok(&mut c, 11, 14, "d", "D", 90);
  return c;
}

// 20 -> 21 -> 23 and 20 -> 22; all ACTIVE.
fn cancel_fixture() -> Context {
  var c = ctx_new();
  add_root_ok(&mut c, 20);
  add_child_ok(&mut c, 20, 21, "a", "A", -1);
  add_child_ok(&mut c, 20, 22, "b", "B", -1);
  add_child_ok(&mut c, 21, 23, "c", "C", -1);
  return c;
}

// 1 -> 2 (tenant/acme) -> 3 (route//v1) -> 4 (tenant/beta).
fn flat_fixture() -> Context {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "tenant", "acme", -1);
  add_child_ok(&mut c, 2, 3, "route", "/v1", -1);
  add_child_ok(&mut c, 3, 4, "tenant", "beta", -1);
  return c;
}

// 1 -> 2 (a/1) -> 3 (b/2); 1 -> 4 (a/3).
fn branch_fixture() -> Context {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "a", "1", -1);
  add_child_ok(&mut c, 2, 3, "b", "2", -1);
  add_child_ok(&mut c, 1, 4, "a", "3", -1);
  return c;
}

// ---------------------------------------------------------------------------
// Result classifiers
// ---------------------------------------------------------------------------

// Added id on success, -1 on any error.
fn add_root_ok(c: &mut Context, id: Int) -> Int {
  match ctx_add_root(c, id) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn add_root_err_is(c: &mut Context, id: Int, want: Str) -> Bool {
  match ctx_add_root(c, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Added id on success, -1 on any error.
fn add_child_ok(c: &mut Context, parent: Int, id: Int, key: Str,
                value: Str, deadline: Int) -> Int {
  match ctx_add_child(c, parent, id, key, value, deadline) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn add_child_err_is(c: &mut Context, parent: Int, id: Int, key: Str,
                    value: Str, deadline: Int, want: Str) -> Bool {
  match ctx_add_child(c, parent, id, key, value, deadline) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// New clock value on success, -1 on any error.
fn advance_ok(c: &mut Context, to: Int) -> Int {
  match ctx_advance(c, to) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn advance_err_is(c: &mut Context, to: Int, want: Str) -> Bool {
  match ctx_advance(c, to) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn tick_ok(c: &mut Context, to: Int) -> Int {
  match ctx_tick(c, to) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn tick_err_is(c: &mut Context, to: Int, want: Str) -> Bool {
  match ctx_tick(c, to) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn check_ok(c: &mut Context, id: Int) -> Int {
  match ctx_check_deadline(c, id) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn check_err_is(c: &mut Context, id: Int, want: Str) -> Bool {
  match ctx_check_deadline(c, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn cancel_ok(c: &mut Context, id: Int, reason: Int) -> Int {
  match ctx_cancel(c, id, reason) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn cancel_err_is(c: &mut Context, id: Int, reason: Int, want: Str) -> Bool {
  match ctx_cancel(c, id, reason) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Newly cancelled count on success, -1 on any error.
fn idem_ok(c: &mut Context, id: Int, reason: Int) -> Int {
  match ctx_cancel_idempotent(c, id, reason) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn idem_err_is(c: &mut Context, id: Int, reason: Int, want: Str) -> Bool {
  match ctx_cancel_idempotent(c, id, reason) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Read-only accessors routed through `&mut` (advisory E001).
// ---------------------------------------------------------------------------

fn count_of(c: &mut Context) -> Int {
  return ctx_count(c);
}

fn has_of(c: &mut Context, id: Int) -> Bool {
  return ctx_has(c, id);
}

fn parent_of(c: &mut Context, id: Int) -> Int {
  return ctx_parent(c, id);
}

fn depth_of(c: &mut Context, id: Int) -> Int {
  return ctx_depth(c, id);
}

fn root_of(c: &mut Context, id: Int) -> Int {
  return ctx_root_of(c, id);
}

fn is_ancestor_of(c: &mut Context, ancestor: Int, id: Int) -> Bool {
  return ctx_is_ancestor(c, ancestor, id);
}

fn path_of(c: &mut Context, id: Int) -> Str {
  return ctx_path(c, id);
}

fn lookup_of(c: &mut Context, id: Int, key: Str) -> Str {
  return ctx_lookup(c, id, key);
}

fn has_key_of(c: &mut Context, id: Int, key: Str) -> Bool {
  return ctx_has_key(c, id, key);
}

fn owner_of(c: &mut Context, id: Int, key: Str) -> Int {
  return ctx_lookup_owner(c, id, key);
}

fn lookup_depth_of(c: &mut Context, id: Int, key: Str) -> Int {
  return ctx_lookup_depth(c, id, key);
}

fn deadline_of(c: &mut Context, id: Int) -> Int {
  return ctx_deadline(c, id);
}

fn has_deadline_of(c: &mut Context, id: Int) -> Bool {
  return ctx_has_deadline(c, id);
}

fn now_of(c: &mut Context) -> Int {
  return ctx_now(c);
}

fn state_of(c: &mut Context, id: Int) -> Int {
  return ctx_state(c, id);
}

fn is_cancelled_of(c: &mut Context, id: Int) -> Bool {
  return ctx_is_cancelled(c, id);
}

fn is_active_of(c: &mut Context, id: Int) -> Bool {
  return ctx_is_active(c, id);
}

fn reason_of(c: &mut Context, id: Int) -> Int {
  return ctx_cancel_reason(c, id);
}

fn source_of(c: &mut Context, id: Int) -> Int {
  return ctx_cancel_source(c, id);
}

fn cancel_tick_of(c: &mut Context, id: Int) -> Int {
  return ctx_cancel_tick(c, id);
}

fn cancelled_count_of(c: &mut Context) -> Int {
  return ctx_cancelled_count(c);
}

fn active_count_of(c: &mut Context) -> Int {
  return ctx_active_count(c);
}

fn invariant_of(c: &mut Context) -> Bool {
  return ctx_check_invariant(c);
}

fn acyclic_of(c: &mut Context) -> Bool {
  return ctx_chain_acyclic(c);
}

fn monotone_of(c: &mut Context) -> Bool {
  return ctx_deadlines_monotone(c);
}

fn flatten_of(c: &mut Context, id: Int) -> Listing {
  return ctx_flatten(c, id);
}

fn lcount_of(l: &mut Listing) -> Int {
  return lst_count(l);
}

fn lkey_of(l: &mut Listing, i: Int) -> Str {
  return lst_key(l, i);
}

fn lval_of(l: &mut Listing, i: Int) -> Str {
  return lst_val(l, i);
}

fn lfind_of(l: &mut Listing, key: Str) -> Int {
  return lst_find(l, key);
}

fn lhas_of(l: &mut Listing, key: Str) -> Bool {
  return lst_has(l, key);
}

fn lvalue_of(l: &mut Listing, key: Str) -> Str {
  return lst_value_of(l, key);
}

fn lto_str_of(l: &mut Listing) -> Str {
  return lst_to_str(l);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var c = ctx_new();
  var ok = count_of(&mut c) == 0;
  if has_of(&mut c, 1) { ok = false; }
  if parent_of(&mut c, 1) != CTX_NO_PARENT { ok = false; }
  if depth_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if root_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if !streq(path_of(&mut c, 1), "") { ok = false; }
  if !streq(lookup_of(&mut c, 1, "k"), "") { ok = false; }
  if has_key_of(&mut c, 1, "k") { ok = false; }
  if owner_of(&mut c, 1, "k") != CTX_NOT_FOUND { ok = false; }
  if lookup_depth_of(&mut c, 1, "k") != CTX_NOT_FOUND { ok = false; }
  if deadline_of(&mut c, 1) != CTX_NO_DEADLINE { ok = false; }
  if has_deadline_of(&mut c, 1) { ok = false; }
  if now_of(&mut c) != 0 { ok = false; }
  if state_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if is_cancelled_of(&mut c, 1) { ok = false; }
  if is_active_of(&mut c, 1) { ok = false; }
  if reason_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if source_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if cancel_tick_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if cancelled_count_of(&mut c) != 0 { ok = false; }
  if active_count_of(&mut c) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  if !acyclic_of(&mut c) { ok = false; }
  if !monotone_of(&mut c) { ok = false; }
  return assert(ok, "ctx_new starts empty: every accessor yields its sentinel");
}

fn t2() -> TestResult {
  var c = ctx_new();
  var ok = add_root_err_is(&mut c, -1, _E_ID);
  if add_root_ok(&mut c, 1) != 1 { ok = false; }
  if !add_root_err_is(&mut c, 1, _E_DUP) { ok = false; }
  if count_of(&mut c) != 1 { ok = false; }
  if !has_of(&mut c, 1) { ok = false; }
  if parent_of(&mut c, 1) != CTX_NO_PARENT { ok = false; }
  if depth_of(&mut c, 1) != 0 { ok = false; }
  if root_of(&mut c, 1) != 1 { ok = false; }
  if !streq(path_of(&mut c, 1), "1") { ok = false; }
  if deadline_of(&mut c, 1) != CTX_NO_DEADLINE { ok = false; }
  if has_deadline_of(&mut c, 1) { ok = false; }
  if state_of(&mut c, 1) != CTX_STATE_ACTIVE { ok = false; }
  if !is_active_of(&mut c, 1) { ok = false; }
  if is_cancelled_of(&mut c, 1) { ok = false; }
  if reason_of(&mut c, 1) != CTX_REASON_NONE { ok = false; }
  if source_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if cancel_tick_of(&mut c, 1) != CTX_NOT_FOUND { ok = false; }
  if is_ancestor_of(&mut c, 1, 1) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "add_root validates ids and creates an ACTIVE parentless node");
}

fn t3() -> TestResult {
  var c = ctx_new();
  var ok = add_child_err_is(&mut c, 1, 2, "k", "v", -1, _E_PARENT);
  if add_root_ok(&mut c, 1) != 1 { ok = false; }
  if !add_child_err_is(&mut c, 1, -5, "k", "v", -1, _E_ID) { ok = false; }
  if add_child_ok(&mut c, 1, 2, "tenant", "acme", -1) != 2 { ok = false; }
  if !add_child_err_is(&mut c, 1, 2, "k", "v", -1, _E_DUP) { ok = false; }
  if add_child_ok(&mut c, 1, 3, "route", "/v1", -1) != 3 { ok = false; }
  if count_of(&mut c) != 3 { ok = false; }
  if parent_of(&mut c, 2) != 1 { ok = false; }
  if parent_of(&mut c, 3) != 1 { ok = false; }
  if depth_of(&mut c, 3) != 1 { ok = false; }
  if !streq(path_of(&mut c, 2), "1/2") { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "add_child validates ids and links the child to its parent");
}

fn t4() -> TestResult {
  var c = chain3();
  var ok = streq(lookup_of(&mut c, 3, "tenant"), "acme");
  if !streq(lookup_of(&mut c, 3, "route"), "/v1") { ok = false; }
  if !streq(lookup_of(&mut c, 2, "route"), "") { ok = false; }
  if !has_key_of(&mut c, 3, "tenant") { ok = false; }
  if has_key_of(&mut c, 3, "missing") { ok = false; }
  if owner_of(&mut c, 3, "tenant") != 2 { ok = false; }
  if owner_of(&mut c, 3, "route") != 3 { ok = false; }
  if lookup_depth_of(&mut c, 3, "tenant") != 1 { ok = false; }
  if lookup_depth_of(&mut c, 3, "route") != 2 { ok = false; }
  if !streq(lookup_of(&mut c, 99, "tenant"), "") { ok = false; }
  if has_key_of(&mut c, 99, "tenant") { ok = false; }
  if owner_of(&mut c, 99, "tenant") != CTX_NOT_FOUND { ok = false; }
  if lookup_depth_of(&mut c, 99, "tenant") != CTX_NOT_FOUND { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "lookup resolves found keys, misses and unknown ids");
}

fn t5() -> TestResult {
  var c = shadow_fixture();
  var ok = streq(lookup_of(&mut c, 3, "tenant"), "acme");
  if !streq(lookup_of(&mut c, 4, "tenant"), "beta") { ok = false; }
  if !streq(lookup_of(&mut c, 5, "tenant"), "gamma") { ok = false; }
  if !streq(lookup_of(&mut c, 2, "tenant"), "") { ok = false; }
  if owner_of(&mut c, 5, "tenant") != 5 { ok = false; }
  if lookup_depth_of(&mut c, 5, "tenant") != 4 { ok = false; }
  if !streq(lookup_of(&mut c, 5, "org"), "acme-corp") { ok = false; }
  if !streq(lookup_of(&mut c, 2, "org"), "acme-corp") { ok = false; }
  if owner_of(&mut c, 5, "org") != 2 { ok = false; }
  if lookup_depth_of(&mut c, 5, "org") != 1 { ok = false; }
  if lookup_depth_of(&mut c, 4, "tenant") != 3 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "nearer bindings shadow farther ones and keys stay scoped to their subtree");
}

fn t6() -> TestResult {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "a", "A", -1);
  add_child_ok(&mut c, 2, 3, "b", "B", -1);
  add_child_ok(&mut c, 1, 4, "c", "C", -1);
  var ok = streq(path_of(&mut c, 3), "1/2/3");
  if !streq(path_of(&mut c, 1), "1") { ok = false; }
  if !streq(path_of(&mut c, 2), "1/2") { ok = false; }
  if !streq(path_of(&mut c, 4), "1/4") { ok = false; }
  if !streq(path_of(&mut c, 99), "") { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "ctx_path renders the whole root-to-node id chain");
}

fn t7() -> TestResult {
  var c = tree_fixture();
  var ok = depth_of(&mut c, 1) == 0;
  if depth_of(&mut c, 2) != 1 { ok = false; }
  if depth_of(&mut c, 3) != 1 { ok = false; }
  if depth_of(&mut c, 4) != 2 { ok = false; }
  if depth_of(&mut c, 99) != CTX_NOT_FOUND { ok = false; }
  if root_of(&mut c, 4) != 1 { ok = false; }
  if root_of(&mut c, 3) != 1 { ok = false; }
  if root_of(&mut c, 99) != CTX_NOT_FOUND { ok = false; }
  if !is_ancestor_of(&mut c, 1, 4) { ok = false; }
  if !is_ancestor_of(&mut c, 2, 4) { ok = false; }
  if is_ancestor_of(&mut c, 1, 1) { ok = false; }
  if is_ancestor_of(&mut c, 4, 1) { ok = false; }
  if is_ancestor_of(&mut c, 3, 4) { ok = false; }
  if is_ancestor_of(&mut c, 99, 1) { ok = false; }
  if is_ancestor_of(&mut c, 1, 99) { ok = false; }
  if count_of(&mut c) != 4 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "depth, roots and strict ancestor relations follow the parent chain");
}

fn t8() -> TestResult {
  var c = deadline_fixture();
  var ok = deadline_of(&mut c, 10) == CTX_NO_DEADLINE;
  if has_deadline_of(&mut c, 10) { ok = false; }
  if deadline_of(&mut c, 11) != 50 { ok = false; }
  if deadline_of(&mut c, 12) != 30 { ok = false; }
  if deadline_of(&mut c, 13) != 30 { ok = false; }
  if deadline_of(&mut c, 14) != 50 { ok = false; }
  if !has_deadline_of(&mut c, 11) { ok = false; }
  if !has_deadline_of(&mut c, 13) { ok = false; }
  if !has_deadline_of(&mut c, 14) { ok = false; }
  if deadline_of(&mut c, 99) != CTX_NO_DEADLINE { ok = false; }
  if !monotone_of(&mut c) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "a child inherits the earliest deadline of its chain");
}

fn t9() -> TestResult {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  var ok = add_child_err_is(&mut c, 1, 2, "k", "v", -2, _E_DL);
  if !add_child_err_is(&mut c, 99, 3, "k", "v", 5, _E_PARENT) { ok = false; }
  if add_child_ok(&mut c, 1, 2, "k", "v", 7) != 2 { ok = false; }
  if deadline_of(&mut c, 2) != 7 { ok = false; }
  if add_root_ok(&mut c, 3) != 3 { ok = false; }
  if add_child_ok(&mut c, 3, 4, "m", "n", -1) != 4 { ok = false; }
  if deadline_of(&mut c, 4) != CTX_NO_DEADLINE { ok = false; }
  if has_deadline_of(&mut c, 4) { ok = false; }
  if add_child_ok(&mut c, 2, 5, "x", "y", 3) != 5 { ok = false; }
  if deadline_of(&mut c, 5) != 3 { ok = false; }
  if !monotone_of(&mut c) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "deadline validation accepts >= -1 and an explicit tick can only tighten");
}

fn t10() -> TestResult {
  var c = chain3();
  var ok = now_of(&mut c) == 0;
  if !advance_err_is(&mut c, -1, _E_CLOCK) { ok = false; }
  if advance_ok(&mut c, 4) != 4 { ok = false; }
  if now_of(&mut c) != 4 { ok = false; }
  if advance_ok(&mut c, 4) != 4 { ok = false; }
  if !advance_err_is(&mut c, 3, _E_CLOCK) { ok = false; }
  if now_of(&mut c) != 4 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "the logical clock only moves forward (no deadline evaluation)");
}

fn t11() -> TestResult {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "k", "v", 7);
  var ok = check_ok(&mut c, 1) == 0;
  if check_ok(&mut c, 2) != 0 { ok = false; }
  if advance_ok(&mut c, 6) != 6 { ok = false; }
  if check_ok(&mut c, 2) != 0 { ok = false; }
  if tick_ok(&mut c, 7) != 1 { ok = false; }
  if state_of(&mut c, 2) != CTX_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 2) != CTX_REASON_DEADLINE { ok = false; }
  if source_of(&mut c, 2) != 2 { ok = false; }
  if cancel_tick_of(&mut c, 2) != 7 { ok = false; }
  if check_ok(&mut c, 2) != 0 { ok = false; }
  if !check_err_is(&mut c, 99, _E_UNKNOWN) { ok = false; }
  if cancelled_count_of(&mut c) != 1 { ok = false; }
  if !is_active_of(&mut c, 1) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "check_deadline cancels a due node exactly once with reason DEADLINE");
}

fn t12() -> TestResult {
  var c = ctx_new();
  add_root_ok(&mut c, 10);
  add_child_ok(&mut c, 10, 11, "a", "A", 5);
  add_child_ok(&mut c, 11, 12, "b", "B", -1);
  var ok = deadline_of(&mut c, 11) == 5;
  if deadline_of(&mut c, 12) != 5 { ok = false; }
  if tick_ok(&mut c, 4) != 0 { ok = false; }
  if active_count_of(&mut c) != 3 { ok = false; }
  if tick_ok(&mut c, 5) != 2 { ok = false; }
  if state_of(&mut c, 10) != CTX_STATE_ACTIVE { ok = false; }
  if reason_of(&mut c, 10) != CTX_REASON_NONE { ok = false; }
  if source_of(&mut c, 10) != CTX_NOT_FOUND { ok = false; }
  if reason_of(&mut c, 11) != CTX_REASON_DEADLINE { ok = false; }
  if source_of(&mut c, 11) != 11 { ok = false; }
  if cancel_tick_of(&mut c, 11) != 5 { ok = false; }
  if reason_of(&mut c, 12) != CTX_REASON_PARENT { ok = false; }
  if source_of(&mut c, 12) != 11 { ok = false; }
  if cancel_tick_of(&mut c, 12) != 5 { ok = false; }
  if cancelled_count_of(&mut c) != 2 { ok = false; }
  if active_count_of(&mut c) != 1 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "ctx_tick expires the inherited deadline and cascades to the subtree");
}

fn t13() -> TestResult {
  var c = cancel_fixture();
  var ok = cancel_ok(&mut c, 21, CTX_REASON_USER) == 2;
  if state_of(&mut c, 21) != CTX_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 21) != CTX_REASON_USER { ok = false; }
  if source_of(&mut c, 21) != 21 { ok = false; }
  if cancel_tick_of(&mut c, 21) != 0 { ok = false; }
  if state_of(&mut c, 23) != CTX_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 23) != CTX_REASON_PARENT { ok = false; }
  if source_of(&mut c, 23) != 21 { ok = false; }
  if !is_active_of(&mut c, 20) { ok = false; }
  if !is_active_of(&mut c, 22) { ok = false; }
  if advance_ok(&mut c, 8) != 8 { ok = false; }
  if cancel_ok(&mut c, 20, CTX_REASON_SHUTDOWN) != 2 { ok = false; }
  if reason_of(&mut c, 20) != CTX_REASON_SHUTDOWN { ok = false; }
  if source_of(&mut c, 20) != 20 { ok = false; }
  if cancel_tick_of(&mut c, 20) != 8 { ok = false; }
  if reason_of(&mut c, 22) != CTX_REASON_PARENT { ok = false; }
  if source_of(&mut c, 22) != 20 { ok = false; }
  if reason_of(&mut c, 21) != CTX_REASON_USER { ok = false; }
  if cancel_tick_of(&mut c, 21) != 0 { ok = false; }
  if cancelled_count_of(&mut c) != 4 { ok = false; }
  if active_count_of(&mut c) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "cancelling a node propagates PARENT to ACTIVE descendants only");
}

fn t14() -> TestResult {
  var c = ctx_new();
  add_root_ok(&mut c, 20);
  add_child_ok(&mut c, 20, 21, "k", "v", -1);
  var ok = cancel_err_is(&mut c, 20, 0, _E_REASON_MIN);
  if !cancel_err_is(&mut c, 20, CTX_REASON_DEADLINE, _E_REASON_RESERVED) { ok = false; }
  if !cancel_err_is(&mut c, 20, CTX_REASON_PARENT, _E_REASON_RESERVED) { ok = false; }
  if !cancel_err_is(&mut c, 99, CTX_REASON_USER, _E_UNKNOWN) { ok = false; }
  if idem_ok(&mut c, 20, CTX_REASON_SHUTDOWN) != 2 { ok = false; }
  if idem_ok(&mut c, 20, CTX_REASON_SHUTDOWN) != 0 { ok = false; }
  if !cancel_err_is(&mut c, 20, CTX_REASON_USER, _E_ALREADY) { ok = false; }
  if reason_of(&mut c, 20) != CTX_REASON_SHUTDOWN { ok = false; }
  if source_of(&mut c, 20) != 20 { ok = false; }
  if add_root_ok(&mut c, 30) != 30 { ok = false; }
  if cancel_ok(&mut c, 30, 9) != 1 { ok = false; }
  if reason_of(&mut c, 30) != 9 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "strict cancel refuses repeats, idempotent returns Ok(0), custom reasons pass");
}

fn t15() -> TestResult {
  var c = ctx_new();
  add_root_ok(&mut c, 1);
  add_child_ok(&mut c, 1, 2, "k", "v", -1);
  add_child_ok(&mut c, 2, 3, "x", "y", -1);
  cancel_ok(&mut c, 1, CTX_REASON_USER);
  var ok = add_child_ok(&mut c, 1, 4, "n", "w", -1) == 4;
  if state_of(&mut c, 4) != CTX_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 4) != CTX_REASON_PARENT { ok = false; }
  if source_of(&mut c, 4) != 1 { ok = false; }
  if cancel_tick_of(&mut c, 4) != 0 { ok = false; }
  if add_child_ok(&mut c, 4, 5, "m", "q", -1) != 5 { ok = false; }
  if state_of(&mut c, 5) != CTX_STATE_CANCELLED { ok = false; }
  if reason_of(&mut c, 5) != CTX_REASON_PARENT { ok = false; }
  if source_of(&mut c, 5) != 1 { ok = false; }
  if add_child_ok(&mut c, 3, 6, "p", "r", -1) != 6 { ok = false; }
  if state_of(&mut c, 6) != CTX_STATE_CANCELLED { ok = false; }
  if source_of(&mut c, 6) != 1 { ok = false; }
  if cancelled_count_of(&mut c) != 6 { ok = false; }
  if active_count_of(&mut c) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "a child of a cancelled node is born cancelled with the origin source");
}

fn t16() -> TestResult {
  var c = flat_fixture();
  var l = flatten_of(&mut c, 4);
  var ok = lcount_of(&mut l) == 2;
  if !streq(lkey_of(&mut l, 0), "tenant") { ok = false; }
  if !streq(lval_of(&mut l, 0), "beta") { ok = false; }
  if !streq(lkey_of(&mut l, 1), "route") { ok = false; }
  if !streq(lval_of(&mut l, 1), "/v1") { ok = false; }
  if lfind_of(&mut l, "tenant") != 0 { ok = false; }
  if lfind_of(&mut l, "route") != 1 { ok = false; }
  if lfind_of(&mut l, "missing") != CTX_NOT_FOUND { ok = false; }
  if !lhas_of(&mut l, "tenant") { ok = false; }
  if lhas_of(&mut l, "missing") { ok = false; }
  if !streq(lvalue_of(&mut l, "tenant"), "beta") { ok = false; }
  if !streq(lvalue_of(&mut l, "missing"), "") { ok = false; }
  if !streq(lto_str_of(&mut l), "tenant=beta\nroute=/v1") { ok = false; }
  var l2 = flatten_of(&mut c, 2);
  if lcount_of(&mut l2) != 1 { ok = false; }
  if !streq(lto_str_of(&mut l2), "tenant=acme") { ok = false; }
  var l3 = flatten_of(&mut c, 1);
  if lcount_of(&mut l3) != 0 { ok = false; }
  if !streq(lto_str_of(&mut l3), "") { ok = false; }
  var l4 = flatten_of(&mut c, 99);
  if lcount_of(&mut l4) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "flatten lists distinct keys with the nearest shadowing value");
}

fn t17() -> TestResult {
  var c = branch_fixture();
  var l3 = flatten_of(&mut c, 3);
  var ok = lcount_of(&mut l3) == 2;
  if !streq(lto_str_of(&mut l3), "a=1\nb=2") { ok = false; }
  var l4 = flatten_of(&mut c, 4);
  if lcount_of(&mut l4) != 1 { ok = false; }
  if !streq(lto_str_of(&mut l4), "a=3") { ok = false; }
  if !streq(lookup_of(&mut c, 3, "a"), "1") { ok = false; }
  if !streq(lookup_of(&mut c, 3, "b"), "2") { ok = false; }
  var again = flatten_of(&mut c, 3);
  if !streq(lto_str_of(&mut again), "a=1\nb=2") { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "flatten is a per-node snapshot: sibling subtrees do not leak");
}

fn t18() -> TestResult {
  var c = chain3();
  var ok = state_of(&mut c, 99) == CTX_NOT_FOUND;
  if is_cancelled_of(&mut c, 99) { ok = false; }
  if is_active_of(&mut c, 99) { ok = false; }
  if reason_of(&mut c, 99) != CTX_NOT_FOUND { ok = false; }
  if source_of(&mut c, 99) != CTX_NOT_FOUND { ok = false; }
  if cancel_tick_of(&mut c, 99) != CTX_NOT_FOUND { ok = false; }
  if parent_of(&mut c, 99) != CTX_NO_PARENT { ok = false; }
  if depth_of(&mut c, 99) != CTX_NOT_FOUND { ok = false; }
  if root_of(&mut c, 99) != CTX_NOT_FOUND { ok = false; }
  if is_ancestor_of(&mut c, 99, 1) { ok = false; }
  if is_ancestor_of(&mut c, 1, 99) { ok = false; }
  if !streq(path_of(&mut c, 99), "") { ok = false; }
  if !streq(lookup_of(&mut c, 99, "tenant"), "") { ok = false; }
  if has_key_of(&mut c, 99, "tenant") { ok = false; }
  if owner_of(&mut c, 99, "tenant") != CTX_NOT_FOUND { ok = false; }
  if lookup_depth_of(&mut c, 99, "tenant") != CTX_NOT_FOUND { ok = false; }
  if deadline_of(&mut c, 99) != CTX_NO_DEADLINE { ok = false; }
  if has_deadline_of(&mut c, 99) { ok = false; }
  if !check_err_is(&mut c, 99, _E_UNKNOWN) { ok = false; }
  if !cancel_err_is(&mut c, 99, CTX_REASON_USER, _E_UNKNOWN) { ok = false; }
  if !idem_err_is(&mut c, 99, CTX_REASON_USER, _E_UNKNOWN) { ok = false; }
  if count_of(&mut c) != 3 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "unknown ids yield sentinels instead of errors everywhere");
}

fn t19() -> TestResult {
  var c = ctx_new();
  var ok = true;
  var i = 0;
  while i < 16 {
    let r = 100 + i;
    let ch = 200 + i;
    if add_root_ok(&mut c, r) != r { ok = false; }
    if add_child_ok(&mut c, r, ch, "k" + convert.int_to_string(i), "v", i % 3) != ch { ok = false; }
    if advance_ok(&mut c, i) < 0 { ok = false; }
    if tick_ok(&mut c, i + 1) < 0 { ok = false; }
    if idem_ok(&mut c, r, CTX_REASON_USER) < 0 { ok = false; }
    if idem_ok(&mut c, ch, CTX_REASON_SHUTDOWN) < 0 { ok = false; }
    if !invariant_of(&mut c) { ok = false; }
    i = i + 1;
  }
  if count_of(&mut c) != 32 { ok = false; }
  if cancelled_count_of(&mut c) != 32 { ok = false; }
  if active_count_of(&mut c) != 0 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "the invariant holds across 16 deterministic add/tick/cancel cycles");
}

fn t20() -> TestResult {
  var c = deadline_fixture();
  var ok = acyclic_of(&mut c);
  if !monotone_of(&mut c) { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  var c2 = ctx_new();
  add_root_ok(&mut c2, 1);
  add_child_ok(&mut c2, 1, 2, "a", "b", 5);
  add_child_ok(&mut c2, 2, 3, "c", "d", 9);
  if deadline_of(&mut c2, 3) != 5 { ok = false; }
  if !monotone_of(&mut c2) { ok = false; }
  add_root_ok(&mut c2, 7);
  add_child_ok(&mut c2, 7, 8, "e", "f", -1);
  if deadline_of(&mut c2, 8) != CTX_NO_DEADLINE { ok = false; }
  if !acyclic_of(&mut c2) { ok = false; }
  if !monotone_of(&mut c2) { ok = false; }
  if !invariant_of(&mut c2) { ok = false; }
  return assert(ok, "chain acyclicity and deadline monotonicity hold on mixed trees");
}

fn t21() -> TestResult {
  var ok = streq(ctx_state_name(CTX_STATE_ACTIVE), "active");
  if !streq(ctx_state_name(CTX_STATE_CANCELLED), "cancelled") { ok = false; }
  if !streq(ctx_state_name(7), "unknown") { ok = false; }
  if !streq(ctx_reason_name(CTX_REASON_NONE), "none") { ok = false; }
  if !streq(ctx_reason_name(CTX_REASON_USER), "user") { ok = false; }
  if !streq(ctx_reason_name(CTX_REASON_DEADLINE), "deadline") { ok = false; }
  if !streq(ctx_reason_name(CTX_REASON_PARENT), "parent") { ok = false; }
  if !streq(ctx_reason_name(CTX_REASON_SHUTDOWN), "shutdown") { ok = false; }
  if !streq(ctx_reason_name(9), "custom") { ok = false; }
  if !streq(ctx_reason_name(-1), "unknown") { ok = false; }
  return assert(ok, "state and reason name helpers are stable");
}

fn t22() -> TestResult {
  var c = chain3();
  var l = flatten_of(&mut c, 3);
  var ok = streq(lkey_of(&mut l, -1), "");
  if !streq(lkey_of(&mut l, 9), "") { ok = false; }
  if !streq(lval_of(&mut l, -1), "") { ok = false; }
  if !streq(lval_of(&mut l, 9), "") { ok = false; }
  if lfind_of(&mut l, "") != CTX_NOT_FOUND { ok = false; }
  var empty = flatten_of(&mut c, 1);
  if lcount_of(&mut empty) != 0 { ok = false; }
  if !streq(lto_str_of(&mut empty), "") { ok = false; }
  if lfind_of(&mut empty, "a") != CTX_NOT_FOUND { ok = false; }
  if !streq(lvalue_of(&mut empty, "a"), "") { ok = false; }
  return assert(ok, "listing accessors are total: out-of-range and empty cases are safe");
}

fn t23() -> TestResult {
  var c = flat_fixture();
  var a = flatten_of(&mut c, 4);
  var b = flatten_of(&mut c, 4);
  var ok = streq(lto_str_of(&mut a), lto_str_of(&mut b));
  a.text = a.text + "XX";
  if !streq(lvalue_of(&mut a, "tenant"), "beta") { ok = false; }
  if !streq(lookup_of(&mut c, 4, "tenant"), "beta") { ok = false; }
  if advance_ok(&mut c, 3) != 3 { ok = false; }
  if tick_ok(&mut c, 5) != 0 { ok = false; }
  if !streq(lookup_of(&mut c, 4, "route"), "/v1") { ok = false; }
  if count_of(&mut c) != 4 { ok = false; }
  if !invariant_of(&mut c) { ok = false; }
  return assert(ok, "listings are independent snapshots and ticking leaves values intact");
}

fn main() -> Int {
  io.println("=== xiom.context conformance tests ===");
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
    io.println("xiom.context: all tests passed");
  } else {
    io.println("xiom.context: tests failed");
  }
  return failed;
}
