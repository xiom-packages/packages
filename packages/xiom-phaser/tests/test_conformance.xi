// XIOM -- xiom.phaser conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.phaser state machine against its
// documented API (dynamic registration, parties/arrived/unarrived
// accounting, arrive / arriveAndAwaitAdvance / arriveAndDeregister, hook
// kinds and termination, last phase, tiered parent propagation, bounded
// progression helpers and the structural invariant).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: `==` on Str values can lower to
// a pointer comparison, so every message check below is routed through
// streq. Read-only operations are wrapped in small helpers that take `&mut`,
// so a `&local` read call is never followed by a `&mut local` call in the
// same function body (advisory E001); each helper calls the real `&`-based
// API. Classifiers turn Result outcomes into small Int codes so the tests
// stay branch-free.

module phaser_tests
use xiom.io; use xiom.test; use xiom.phaser;
use xiom.string.compare;

const _E_HANDLE: Str = "phaser: handle must be >= 0";
const _E_PARTIES: Str = "phaser: parties must be >= 0";
const _E_LIMIT: Str = "phaser: parties limit exceeded";
const _E_CHILDHDL: Str = "phaser: child handle must differ from parent";
const _E_CHILDPARTY: Str = "phaser: child parties must be >= 1";
const _E_TERM: Str = "phaser: terminated";
const _E_NOPARTY: Str = "phaser: no registered parties";
const _E_PARENTTERM: Str = "phaser: parent terminated";
const _E_NOTCHILD: Str = "phaser: not a child";
const _E_COUNT: Str = "phaser: count must be >= 0";
const _E_KIND: Str = "phaser: invalid hook kind";
const _E_HOOKLIM: Str = "phaser: hook limit must be >= 1";
const _E_NEGLIM: Str = "phaser: limit must be >= 0";
const _E_MAXLIM: Str = "phaser: limit exceeds maximum";
const _E_ARRIVALLIM: Str = "phaser: arrival limit reached";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bint(b: Bool) -> Int {
  if b { return 1; }
  return 0;
}

// Fixture: phaser_new rejects invalid inputs, so p_at falls back to a raw
// construction (mirroring the public struct layout) for the defensive tests.
fn p_at(handle: Int, parties: Int) -> Phaser {
  match phaser_new(handle, parties) {
    Ok(p) => { return p; },
    Err(_) => {
      return Phaser{
        handle: handle;
        parent: -1;
        parties: parties;
        arrived: 0;
        phase: 0;
        terminated: false;
        hook: PHASER_HOOK_DEFAULT;
        hook_param: 0;
        children: 0;
        arrivals_total: 0;
        registrations_total: 0;
        deregistrations_total: 0;
        advances_total: 0;
        last_phase_parties: -1;
      };
    },
  }
}

fn child_at(parent: &mut Phaser, handle: Int, parties: Int) -> Phaser {
  match phaser_new_child(parent, handle, parties) {
    Ok(c) => { return c; },
    Err(_) => { return p_at(handle, parties); },
  }
}

// Read-only accessors routed through `&mut` (advisory E001).

fn inv(p: &mut Phaser) -> Bool { return phaser_check_invariant(p); }
fn handle_of(p: &mut Phaser) -> Int { return phaser_handle(p); }
fn parent_of(p: &mut Phaser) -> Int { return phaser_parent(p); }
fn is_child_of(p: &mut Phaser) -> Bool { return phaser_is_child(p); }
fn children_of(p: &mut Phaser) -> Int { return phaser_child_count(p); }
fn parties_of(p: &mut Phaser) -> Int { return phaser_parties(p); }
fn arrived_of(p: &mut Phaser) -> Int { return phaser_arrived(p); }
fn unarrived_of(p: &mut Phaser) -> Int { return phaser_unarrived(p); }
fn phase_of(p: &mut Phaser) -> Int { return phaser_phase(p); }
fn term_of(p: &mut Phaser) -> Bool { return phaser_is_terminated(p); }
fn last_phase_of(p: &mut Phaser) -> Int { return phaser_last_phase(p); }
fn hook_of(p: &mut Phaser) -> Int { return phaser_hook_kind(p); }
fn hook_param_of(p: &mut Phaser) -> Int { return phaser_hook_param(p); }
fn arrivals_of(p: &mut Phaser) -> Int { return phaser_arrivals_total(p); }
fn regs_of(p: &mut Phaser) -> Int { return phaser_registration_total(p); }
fn deregs_of(p: &mut Phaser) -> Int { return phaser_deregistration_total(p); }
fn advances_of(p: &mut Phaser) -> Int { return phaser_advance_total(p); }
fn last_parties_of(p: &mut Phaser) -> Int { return phaser_last_phase_parties(p); }
fn state_of(p: &mut Phaser) -> Str { return phaser_state_str(p); }
fn released_of(p: &mut Phaser, ph: Int) -> Bool { return phaser_waiter_released(p, ph); }

// Classifiers: Int codes keep the tests readable.

fn new_err_is(handle: Int, parties: Int, want: Str) -> Bool {
  match phaser_new(handle, parties) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn child_err_is(parent: &mut Phaser, handle: Int, parties: Int, want: Str) -> Bool {
  match phaser_new_child(parent, handle, parties) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn reg_code(p: &mut Phaser) -> Int {
  match phaser_register(p) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -9;
}

fn reg_err_is(p: &mut Phaser, want: Str) -> Bool {
  match phaser_register(p) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn bulk_code(p: &mut Phaser, n: Int) -> Int {
  match phaser_bulk_register(p, n) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -9;
}

fn bulk_err_is(p: &mut Phaser, n: Int, want: Str) -> Bool {
  match phaser_bulk_register(p, n) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// 2 = advanced and terminated, 1 = advanced, 0 = recorded, -1 = error.
fn arrive_code(p: &mut Phaser) -> Int {
  match phaser_arrive(p) {
    Ok(o) => {
      if o.terminated { return 2; }
      if o.advanced { return 1; }
      return 0;
    },
    Err(_) => { return -1; },
  }
  return -9;
}

fn arrive_err_is(p: &mut Phaser, want: Str) -> Bool {
  match phaser_arrive(p) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn await_code(p: &mut Phaser) -> Int {
  match phaser_arrive_and_await(p) {
    Ok(o) => {
      if o.terminated { return 2; }
      if o.advanced { return 1; }
      return 0;
    },
    Err(_) => { return -1; },
  }
  return -9;
}

fn dereg_code(p: &mut Phaser) -> Int {
  match phaser_arrive_and_deregister(p) {
    Ok(o) => {
      if o.terminated { return 2; }
      if o.advanced { return 1; }
      return 0;
    },
    Err(_) => { return -1; },
  }
  return -9;
}

// Full-field outcome probe for arrive: 1 = all fields match, 0 = mismatch,
// -9 = unexpected error.
fn arrive_probe(p: &mut Phaser, ph: Int, np: Int, adv: Int, tm: Int, rel: Int, par: Int, arr: Int, un: Int) -> Int {
  match phaser_arrive(p) {
    Ok(o) => {
      var good = true;
      if o.phase != ph { good = false; }
      if o.new_phase != np { good = false; }
      if bint(o.advanced) != adv { good = false; }
      if bint(o.terminated) != tm { good = false; }
      if bint(o.released) != rel { good = false; }
      if o.parties != par { good = false; }
      if o.arrived != arr { good = false; }
      if o.unarrived != un { good = false; }
      if good { return 1; }
      return 0;
    },
    Err(_) => { return -9; },
  }
  return -9;
}

fn await_probe(p: &mut Phaser, ph: Int, np: Int, adv: Int, tm: Int, rel: Int, par: Int, arr: Int, un: Int) -> Int {
  match phaser_arrive_and_await(p) {
    Ok(o) => {
      var good = true;
      if o.phase != ph { good = false; }
      if o.new_phase != np { good = false; }
      if bint(o.advanced) != adv { good = false; }
      if bint(o.terminated) != tm { good = false; }
      if bint(o.released) != rel { good = false; }
      if o.parties != par { good = false; }
      if o.arrived != arr { good = false; }
      if o.unarrived != un { good = false; }
      if good { return 1; }
      return 0;
    },
    Err(_) => { return -9; },
  }
  return -9;
}

fn set_hook_code(p: &mut Phaser, kind: Int, param: Int) -> Int {
  match phaser_set_hook(p, kind, param) {
    Ok(k) => { return k; },
    Err(_) => { return -1; },
  }
  return -9;
}

fn set_hook_err_is(p: &mut Phaser, kind: Int, param: Int, want: Str) -> Bool {
  match phaser_set_hook(p, kind, param) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn complete_code(p: &mut Phaser, maxn: Int) -> Int {
  match phaser_complete_phase(p, maxn) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -9;
}

fn complete_err_is(p: &mut Phaser, maxn: Int, want: Str) -> Bool {
  match phaser_complete_phase(p, maxn) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn run_code(p: &mut Phaser, maxn: Int) -> Int {
  match phaser_run_to_termination(p, maxn) {
    Ok(n) => { return n; },
    Err(_) => { return -1; },
  }
  return -9;
}

fn run_err_is(p: &mut Phaser, maxn: Int, want: Str) -> Bool {
  match phaser_run_to_termination(p, maxn) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn tier_probe(child: &mut Phaser, parent: &mut Phaser, ca: Int, ct: Int, pa: Int, pt: Int, pp: Int, pph: Int) -> Int {
  match phaser_arrive_tiered(child, parent) {
    Ok(o) => {
      var good = true;
      if bint(o.child_advanced) != ca { good = false; }
      if bint(o.child_terminated) != ct { good = false; }
      if bint(o.parent_advanced) != pa { good = false; }
      if bint(o.parent_terminated) != pt { good = false; }
      if o.parent_parties != pp { good = false; }
      if o.parent_phase != pph { good = false; }
      if good { return 1; }
      return 0;
    },
    Err(_) => { return -9; },
  }
  return -9;
}

fn tier_err_is(child: &mut Phaser, parent: &mut Phaser, want: Str) -> Bool {
  match phaser_arrive_tiered(child, parent) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t1() -> TestResult {
  var p = p_at(7, 3);
  var ok = handle_of(&mut p) == 7;
  if parent_of(&mut p) != -1 { ok = false; }
  if is_child_of(&mut p) { ok = false; }
  if children_of(&mut p) != 0 { ok = false; }
  if parties_of(&mut p) != 3 { ok = false; }
  if arrived_of(&mut p) != 0 { ok = false; }
  if unarrived_of(&mut p) != 3 { ok = false; }
  if phase_of(&mut p) != 0 { ok = false; }
  if term_of(&mut p) { ok = false; }
  if last_phase_of(&mut p) != -1 { ok = false; }
  if hook_of(&mut p) != PHASER_HOOK_DEFAULT { ok = false; }
  if hook_param_of(&mut p) != 0 { ok = false; }
  if arrivals_of(&mut p) != 0 { ok = false; }
  if regs_of(&mut p) != 0 { ok = false; }
  if deregs_of(&mut p) != 0 { ok = false; }
  if advances_of(&mut p) != 0 { ok = false; }
  if last_parties_of(&mut p) != -1 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "phaser_new initializes handle, parties, phase 0 and zero stats");
}

fn t2() -> TestResult {
  var ok = new_err_is(-1, 3, _E_HANDLE);
  if !new_err_is(1, -1, _E_PARTIES) { ok = false; }
  if !new_err_is(1, 65536, _E_LIMIT) { ok = false; }
  var big = p_at(1, 65535);
  if parties_of(&mut big) != 65535 { ok = false; }
  if !inv(&mut big) { ok = false; }
  return assert(ok, "phaser_new rejects bad handles, bad counts and over-max parties");
}

fn t3() -> TestResult {
  var p = p_at(1, 0);
  var ok = reg_code(&mut p) == 1;
  if bulk_code(&mut p, 4) != 5 { ok = false; }
  if bulk_code(&mut p, 0) != 5 { ok = false; }
  if !bulk_err_is(&mut p, 65531, _E_LIMIT) { ok = false; }
  if !bulk_err_is(&mut p, -1, _E_COUNT) { ok = false; }
  if bulk_code(&mut p, 65530) != 65535 { ok = false; }
  if !reg_err_is(&mut p, _E_LIMIT) { ok = false; }
  if parties_of(&mut p) != 65535 { ok = false; }
  if arrived_of(&mut p) != 0 { ok = false; }
  if phase_of(&mut p) != 0 { ok = false; }
  if regs_of(&mut p) != 65535 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "register and bulk_register grow parties within the cap");
}

fn t4() -> TestResult {
  var p = p_at(1, 3);
  var ok = arrive_probe(&mut p, 0, 0, 0, 0, 0, 3, 1, 2) == 1;
  if arrive_probe(&mut p, 0, 0, 0, 0, 0, 3, 2, 1) != 1 { ok = false; }
  if arrive_probe(&mut p, 0, 1, 1, 0, 1, 3, 0, 3) != 1 { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if arrived_of(&mut p) != 0 { ok = false; }
  if unarrived_of(&mut p) != 3 { ok = false; }
  if arrivals_of(&mut p) != 3 { ok = false; }
  if advances_of(&mut p) != 1 { ok = false; }
  if last_parties_of(&mut p) != 3 { ok = false; }
  if term_of(&mut p) { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "the last unarrived arrival completes the phase with a full outcome");
}

fn t5() -> TestResult {
  var p = p_at(9, 0);
  var ok = arrive_err_is(&mut p, _E_NOPARTY);
  if parties_of(&mut p) != 0 { ok = false; }
  if phase_of(&mut p) != 0 { ok = false; }
  if arrivals_of(&mut p) != 0 { ok = false; }
  if !complete_err_is(&mut p, 5, _E_NOPARTY) { ok = false; }
  if !run_err_is(&mut p, 5, _E_NOPARTY) { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "a zero-party phaser refuses arrivals and progression");
}

fn t6() -> TestResult {
  var p = p_at(1, 2);
  var ok = await_probe(&mut p, 0, 0, 0, 0, 0, 2, 1, 1) == 1;
  if await_probe(&mut p, 0, 1, 1, 0, 1, 2, 0, 2) != 1 { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if await_probe(&mut p, 1, 1, 0, 0, 0, 2, 1, 1) != 1 { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if await_probe(&mut p, 1, 2, 1, 0, 1, 2, 0, 2) != 1 { ok = false; }
  if phase_of(&mut p) != 2 { ok = false; }
  if arrivals_of(&mut p) != 4 { ok = false; }
  if advances_of(&mut p) != 2 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "arrive_and_await reports joined phase, new phase and release");
}

fn t7() -> TestResult {
  var p = p_at(1, 2);
  var ok = await_code(&mut p) == 0;
  if released_of(&mut p, 0) { ok = false; }
  if !released_of(&mut p, -1) { ok = false; }
  if await_code(&mut p) != 1 { ok = false; }
  if !released_of(&mut p, 0) { ok = false; }
  if released_of(&mut p, 1) { ok = false; }
  if await_code(&mut p) != 0 { ok = false; }
  if released_of(&mut p, 1) { ok = false; }
  if await_code(&mut p) != 1 { ok = false; }
  if !released_of(&mut p, 1) { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "waiter_released tracks the joined phase across advances");
}

fn t8() -> TestResult {
  var p = p_at(1, 3);
  var ok = dereg_code(&mut p) == 0;
  if parties_of(&mut p) != 2 { ok = false; }
  if arrived_of(&mut p) != 0 { ok = false; }
  if unarrived_of(&mut p) != 2 { ok = false; }
  if phase_of(&mut p) != 0 { ok = false; }
  if deregs_of(&mut p) != 1 { ok = false; }
  if arrivals_of(&mut p) != 1 { ok = false; }
  if dereg_code(&mut p) != 0 { ok = false; }
  if parties_of(&mut p) != 1 { ok = false; }
  if unarrived_of(&mut p) != 1 { ok = false; }
  if dereg_code(&mut p) != 2 { ok = false; }
  if !term_of(&mut p) { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if last_phase_of(&mut p) != 1 { ok = false; }
  if last_parties_of(&mut p) != 1 { ok = false; }
  if parties_of(&mut p) != 0 { ok = false; }
  if deregs_of(&mut p) != 3 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "deregistering the last unarrived party completes and terminates");
}

fn t9() -> TestResult {
  var p = p_at(1, 2);
  var ok = dereg_code(&mut p) == 0;
  if parties_of(&mut p) != 1 { ok = false; }
  if arrived_of(&mut p) != 0 { ok = false; }
  if unarrived_of(&mut p) != 1 { ok = false; }
  if arrive_code(&mut p) != 1 { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if parties_of(&mut p) != 1 { ok = false; }
  if term_of(&mut p) { ok = false; }
  if last_parties_of(&mut p) != 1 { ok = false; }
  if arrive_code(&mut p) != 1 { ok = false; }
  if phase_of(&mut p) != 2 { ok = false; }
  if dereg_code(&mut p) != 2 { ok = false; }
  if phase_of(&mut p) != 3 { ok = false; }
  if !term_of(&mut p) { ok = false; }
  if last_phase_of(&mut p) != 3 { ok = false; }
  if deregs_of(&mut p) != 2 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "a surviving party keeps the phaser alive after a deregistration");
}

fn t10() -> TestResult {
  var ok = phaser_hook_default(0, 3) == PHASER_CONTINUE;
  if phaser_hook_default(5, 0) != PHASER_TERMINATE { ok = false; }
  if phaser_hook_until_phase(1, 3, 3) != PHASER_CONTINUE { ok = false; }
  if phaser_hook_until_phase(2, 3, 3) != PHASER_TERMINATE { ok = false; }
  if phaser_hook_until_phase(0, 0, 3) != PHASER_TERMINATE { ok = false; }
  if phaser_hook_always(0, 5) != PHASER_TERMINATE { ok = false; }
  if phaser_hook_never(9, 9) != PHASER_CONTINUE { ok = false; }
  if phaser_hook_eval(PHASER_HOOK_DEFAULT, 0, 0, 2) != PHASER_CONTINUE { ok = false; }
  if phaser_hook_eval(PHASER_HOOK_DEFAULT, 0, 0, 0) != PHASER_TERMINATE { ok = false; }
  if phaser_hook_eval(PHASER_HOOK_UNTIL_PHASE, 3, 2, 3) != PHASER_TERMINATE { ok = false; }
  if phaser_hook_eval(PHASER_HOOK_ALWAYS, 0, 0, 5) != PHASER_TERMINATE { ok = false; }
  if phaser_hook_eval(PHASER_HOOK_NEVER, 0, 9, 9) != PHASER_CONTINUE { ok = false; }
  if phaser_hook_eval(99, 0, 0, 2) != PHASER_CONTINUE { ok = false; }
  return assert(ok, "concrete hook specializations and case dispatch return continue/terminate");
}

fn t11() -> TestResult {
  var p = p_at(1, 2);
  var ok = set_hook_err_is(&mut p, -1, 0, _E_KIND);
  if !set_hook_err_is(&mut p, 4, 0, _E_KIND) { ok = false; }
  if !set_hook_err_is(&mut p, PHASER_HOOK_UNTIL_PHASE, 0, _E_HOOKLIM) { ok = false; }
  if set_hook_code(&mut p, PHASER_HOOK_UNTIL_PHASE, 2) != PHASER_HOOK_UNTIL_PHASE { ok = false; }
  if hook_of(&mut p) != PHASER_HOOK_UNTIL_PHASE { ok = false; }
  if hook_param_of(&mut p) != 2 { ok = false; }
  if set_hook_code(&mut p, PHASER_HOOK_ALWAYS, 0) != PHASER_HOOK_ALWAYS { ok = false; }
  if arrive_code(&mut p) != 0 { ok = false; }
  if arrive_code(&mut p) != 2 { ok = false; }
  if !set_hook_err_is(&mut p, PHASER_HOOK_DEFAULT, 0, _E_TERM) { ok = false; }
  return assert(ok, "set_hook validates kind and parameter and reflects the selection");
}

fn t12() -> TestResult {
  var p = p_at(1, 2);
  var ok = set_hook_code(&mut p, PHASER_HOOK_UNTIL_PHASE, 2) == PHASER_HOOK_UNTIL_PHASE;
  if arrive_code(&mut p) != 0 { ok = false; }
  if arrive_code(&mut p) != 1 { ok = false; }
  if term_of(&mut p) { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if arrive_code(&mut p) != 0 { ok = false; }
  if arrive_code(&mut p) != 2 { ok = false; }
  if phase_of(&mut p) != 2 { ok = false; }
  if last_phase_of(&mut p) != 2 { ok = false; }
  if last_parties_of(&mut p) != 2 { ok = false; }
  if arrivals_of(&mut p) != 4 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "until_phase hook terminates exactly after the requested phases");
}

fn t13() -> TestResult {
  var p = p_at(1, 1);
  var ok = set_hook_code(&mut p, PHASER_HOOK_NEVER, 0) == PHASER_HOOK_NEVER;
  if arrive_code(&mut p) != 1 { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if arrive_code(&mut p) != 1 { ok = false; }
  if phase_of(&mut p) != 2 { ok = false; }
  if !run_err_is(&mut p, 4, _E_ARRIVALLIM) { ok = false; }
  if term_of(&mut p) { ok = false; }
  if phase_of(&mut p) != 6 { ok = false; }
  if arrivals_of(&mut p) != 6 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "hook_never keeps advancing and the bounded driver stops cleanly");
}

fn t14() -> TestResult {
  var p = p_at(1, 1);
  var ok = set_hook_code(&mut p, PHASER_HOOK_ALWAYS, 0) == PHASER_HOOK_ALWAYS;
  if arrive_code(&mut p) != 2 { ok = false; }
  if !term_of(&mut p) { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if last_phase_of(&mut p) != 1 { ok = false; }
  if parties_of(&mut p) != 0 { ok = false; }
  if arrived_of(&mut p) != 0 { ok = false; }
  if unarrived_of(&mut p) != 0 { ok = false; }
  if last_parties_of(&mut p) != 1 { ok = false; }
  if !arrive_err_is(&mut p, _E_TERM) { ok = false; }
  if !reg_err_is(&mut p, _E_TERM) { ok = false; }
  if !bulk_err_is(&mut p, 2, _E_TERM) { ok = false; }
  if !set_hook_err_is(&mut p, PHASER_HOOK_DEFAULT, 0, _E_TERM) { ok = false; }
  if complete_code(&mut p, 4) != 0 { ok = false; }
  if run_code(&mut p, 4) != 0 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "termination is final: state clears and every operation refuses");
}

fn t15() -> TestResult {
  var p = p_at(1, 2);
  var ok = set_hook_code(&mut p, PHASER_HOOK_UNTIL_PHASE, 1) == PHASER_HOOK_UNTIL_PHASE;
  if arrive_code(&mut p) != 0 { ok = false; }
  if arrive_code(&mut p) != 2 { ok = false; }
  if !term_of(&mut p) { ok = false; }
  if parties_of(&mut p) != 0 { ok = false; }
  if arrived_of(&mut p) != 0 { ok = false; }
  if last_parties_of(&mut p) != 2 { ok = false; }
  if last_phase_of(&mut p) != 1 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "termination records the completing party count as last phase parties");
}

fn t16() -> TestResult {
  var p = p_at(1, 4);
  var ok = set_hook_code(&mut p, PHASER_HOOK_UNTIL_PHASE, 3) == PHASER_HOOK_UNTIL_PHASE;
  if complete_code(&mut p, 10) != 4 { ok = false; }
  if phase_of(&mut p) != 1 { ok = false; }
  if term_of(&mut p) { ok = false; }
  if complete_code(&mut p, 10) != 4 { ok = false; }
  if phase_of(&mut p) != 2 { ok = false; }
  if complete_code(&mut p, 10) != 4 { ok = false; }
  if !term_of(&mut p) { ok = false; }
  if phase_of(&mut p) != 3 { ok = false; }
  if last_parties_of(&mut p) != 4 { ok = false; }
  if complete_code(&mut p, 10) != 0 { ok = false; }
  var p2 = p_at(2, 2);
  if !complete_err_is(&mut p2, 0, _E_ARRIVALLIM) { ok = false; }
  if phase_of(&mut p2) != 0 { ok = false; }
  if arrivals_of(&mut p2) != 0 { ok = false; }
  if !complete_err_is(&mut p2, 1000001, _E_MAXLIM) { ok = false; }
  if !complete_err_is(&mut p2, -1, _E_NEGLIM) { ok = false; }
  var p3 = p_at(3, 0);
  if !complete_err_is(&mut p3, 5, _E_NOPARTY) { ok = false; }
  return assert(ok, "complete_phase drives one phase with a hard arrival budget");
}

fn t17() -> TestResult {
  var p = p_at(1, 3);
  var ok = set_hook_code(&mut p, PHASER_HOOK_UNTIL_PHASE, 2) == PHASER_HOOK_UNTIL_PHASE;
  if run_code(&mut p, 12) != 6 { ok = false; }
  if !term_of(&mut p) { ok = false; }
  if phase_of(&mut p) != 2 { ok = false; }
  if run_code(&mut p, 12) != 0 { ok = false; }
  if !run_err_is(&mut p, -1, _E_NEGLIM) { ok = false; }
  if !run_err_is(&mut p, 1000001, _E_MAXLIM) { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "run_to_termination drives phases to termination within budget");
}

fn t18() -> TestResult {
  var p = p_at(1, 2);
  var ok = run_err_is(&mut p, 10, _E_ARRIVALLIM);
  if phase_of(&mut p) != 5 { ok = false; }
  if arrivals_of(&mut p) != 10 { ok = false; }
  if term_of(&mut p) { ok = false; }
  if !inv(&mut p) { ok = false; }
  var p2 = p_at(2, 2);
  if !run_err_is(&mut p2, 1000001, _E_MAXLIM) { ok = false; }
  if !run_err_is(&mut p2, -1, _E_NEGLIM) { ok = false; }
  return assert(ok, "a never-terminating phaser fails at the budget, not by hanging");
}

fn t19() -> TestResult {
  var parent = p_at(1, 2);
  var child = child_at(&mut parent, 2, 1);
  var ok = parties_of(&mut parent) == 3;
  if children_of(&mut parent) != 1 { ok = false; }
  if handle_of(&mut child) != 2 { ok = false; }
  if parent_of(&mut child) != 1 { ok = false; }
  if !is_child_of(&mut child) { ok = false; }
  if tier_probe(&mut child, &mut parent, 1, 0, 0, 0, 3, 0) != 1 { ok = false; }
  if phase_of(&mut child) != 1 { ok = false; }
  if arrived_of(&mut parent) != 1 { ok = false; }
  if tier_probe(&mut child, &mut parent, 1, 0, 0, 0, 3, 0) != 1 { ok = false; }
  if arrived_of(&mut parent) != 2 { ok = false; }
  if arrive_code(&mut parent) != 1 { ok = false; }
  if phase_of(&mut parent) != 1 { ok = false; }
  if tier_probe(&mut child, &mut parent, 1, 0, 0, 0, 3, 1) != 1 { ok = false; }
  if phase_of(&mut child) != 3 { ok = false; }
  if arrived_of(&mut parent) != 1 { ok = false; }
  if !inv(&mut parent) { ok = false; }
  if !inv(&mut child) { ok = false; }
  return assert(ok, "child creation registers a credit and advances propagate to the parent");
}

fn t20() -> TestResult {
  var parent = p_at(1, 0);
  var child = child_at(&mut parent, 2, 1);
  var ok = parties_of(&mut parent) == 1;
  if children_of(&mut parent) != 1 { ok = false; }
  if tier_probe(&mut child, &mut parent, 1, 0, 1, 0, 1, 1) != 1 { ok = false; }
  if phase_of(&mut child) != 1 { ok = false; }
  if phase_of(&mut parent) != 1 { ok = false; }
  if arrived_of(&mut parent) != 0 { ok = false; }
  if tier_probe(&mut child, &mut parent, 1, 0, 1, 0, 1, 2) != 1 { ok = false; }
  if phase_of(&mut parent) != 2 { ok = false; }
  if !inv(&mut parent) { ok = false; }
  if !inv(&mut child) { ok = false; }
  return assert(ok, "a parent holding only the child credit advances per child phase");
}

fn t21() -> TestResult {
  var parent = p_at(1, 0);
  var child = child_at(&mut parent, 2, 1);
  var ok = set_hook_code(&mut child, PHASER_HOOK_ALWAYS, 0) == PHASER_HOOK_ALWAYS;
  if tier_probe(&mut child, &mut parent, 1, 1, 1, 1, 0, 1) != 1 { ok = false; }
  if !term_of(&mut child) { ok = false; }
  if !term_of(&mut parent) { ok = false; }
  if phase_of(&mut parent) != 1 { ok = false; }
  if last_phase_of(&mut parent) != 1 { ok = false; }
  if children_of(&mut parent) != 0 { ok = false; }
  if last_phase_of(&mut child) != 1 { ok = false; }
  if !tier_err_is(&mut child, &mut parent, _E_TERM) { ok = false; }
  if !inv(&mut parent) { ok = false; }
  if !inv(&mut child) { ok = false; }
  return assert(ok, "a terminal child deregisters its credit from the parent");
}

fn t22() -> TestResult {
  var root = p_at(1, 1);
  var fake = p_at(2, 1);
  var ok = tier_err_is(&mut fake, &mut root, _E_NOTCHILD);
  var root2 = p_at(1, 0);
  var child2 = child_at(&mut root2, 2, 1);
  if set_hook_code(&mut root2, PHASER_HOOK_ALWAYS, 0) != PHASER_HOOK_ALWAYS { ok = false; }
  if arrive_code(&mut root2) != 2 { ok = false; }
  if !tier_err_is(&mut child2, &mut root2, _E_PARENTTERM) { ok = false; }
  var root3 = p_at(3, 0);
  if !child_err_is(&mut root3, 3, 1, _E_CHILDHDL) { ok = false; }
  if !child_err_is(&mut root3, 4, 0, _E_CHILDPARTY) { ok = false; }
  if !child_err_is(&mut root3, 4, 65536, _E_LIMIT) { ok = false; }
  if !child_err_is(&mut root3, -1, 1, _E_HANDLE) { ok = false; }
  var root4 = p_at(4, 1);
  if set_hook_code(&mut root4, PHASER_HOOK_ALWAYS, 0) != PHASER_HOOK_ALWAYS { ok = false; }
  if arrive_code(&mut root4) != 2 { ok = false; }
  if !child_err_is(&mut root4, 5, 1, _E_TERM) { ok = false; }
  return assert(ok, "tiering validates the link and refuses terminated parents");
}

fn t23() -> TestResult {
  var p = p_at(1, 3);
  var ok = inv(&mut p);
  var i = 0;
  while i < 30 {
    let c: Int = arrive_code(&mut p);
    if c < 0 { ok = false; }
    if !inv(&mut p) { ok = false; }
    if (i % 5) == 4 {
      let rc: Int = reg_code(&mut p);
      if rc < 0 { ok = false; }
      if !inv(&mut p) { ok = false; }
    }
    if (i % 7) == 6 {
      let dc: Int = dereg_code(&mut p);
      if dc < 0 { ok = false; }
      if !inv(&mut p) { ok = false; }
    }
    i = i + 1;
  }
  if term_of(&mut p) { ok = false; }
  if phase_of(&mut p) != advances_of(&mut p) { ok = false; }
  if arrivals_of(&mut p) < 30 { ok = false; }
  if parties_of(&mut p) != 5 { ok = false; }
  if !inv(&mut p) { ok = false; }
  return assert(ok, "the invariant holds across mixed arrivals, registrations and deregistrations");
}

fn t24() -> TestResult {
  var p = p_at(1, 3);
  var ok = arrive_code(&mut p) == 0;
  if !streq(state_of(&mut p), "phase=0 parties=3 arrived=1 unarrived=2") { ok = false; }
  if is_child_of(&mut p) { ok = false; }
  if parent_of(&mut p) != -1 { ok = false; }
  if children_of(&mut p) != 0 { ok = false; }
  if handle_of(&mut p) != 1 { ok = false; }
  var p2 = p_at(2, 1);
  if set_hook_code(&mut p2, PHASER_HOOK_ALWAYS, 0) != PHASER_HOOK_ALWAYS { ok = false; }
  if arrive_code(&mut p2) != 2 { ok = false; }
  if !streq(state_of(&mut p2), "phase=1 parties=0 arrived=0 unarrived=0 terminated") { ok = false; }
  return assert(ok, "state_str renders the accounting snapshot including termination");
}

fn main() -> Int {
  io.println("=== xiom.phaser conformance tests ===");
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
    io.println("xiom.phaser: all tests passed");
  } else {
    io.println("xiom.phaser: tests failed");
  }
  return failed;
}
