// XIOM -- xiom.phaser: multi-party phaser as a deterministic state machine
// Port task: replace the xiom.phaser placeholder with a real, tested,
// pure-XIOM package (no FFI, no threads, no clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a java.util.concurrent.Phaser-like multi-party synchronization
// barrier as a pure, deterministic state machine -- the semantic core that
// a thread scheduler, atomics backend or blocking runtime would drive.
// There are no threads, no atomics, no clock and no I/O here: the caller
// (or a future backend) owns the concurrency and every function is a total
// transition over plain values.
//
// Semantics (Java Phaser compatible where it matters):
//   * `parties` is the number of registered parties, `arrived` counts the
//     registered parties that have arrived in the current phase and
//     `unarrived = parties - arrived`. The phase advances exactly when the
//     last unarrived party arrives (Java doArrive: unarrived reaches 0).
//   * `phaser_arrive` records one arrival without waiting;
//     `phaser_arrive_and_await` is the same transition (the caller's release
//     is observed through `phaser_waiter_released`);
//     `phaser_arrive_and_deregister` records the arrival and removes the
//     party. A deregistration that arrives as the last unarrived party still
//     completes the phase, and the hook observes the reduced party count
//     (Java's doArrive(ONE_DEREGISTER) semantics); otherwise the party count
//     drops by one and the arrived count is unchanged.
//   * On every phase completion the hook runs: `onAdvance`-style callbacks
//     return PHASER_CONTINUE or PHASER_TERMINATE. Termination is final: the
//     party count is cleared, `phaser_last_phase` reports the final phase and
//     every further arrive/register fails with a stable error. This model
//     normalizes Java's negative-phase termination encoding to
//     `terminated` + `last_phase`.
//   * Tiered phasers: `phaser_new_child` registers one party credit on the
//     parent; every child phase advance contributes one arrival to the
//     parent, and a terminal child advance deregisters the credit through a
//     parent arrive-and-deregister -- Java's child propagation rule.
//   * Progression helpers (`phaser_complete_phase`,
//     `phaser_run_to_termination`) are bounded by an explicit arrival cap, so
//     a phaser that can never terminate (HOOK_NEVER, or a default-hook
//     phaser whose party count never drops to zero) fails with
//     "phaser: arrival limit reached" instead of hanging.
//
// Error strings are stable and prefixed `phaser: `; every error leaves the
// state completely unchanged.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _ok_*/_err_* leaf helpers; no Vec fields are needed and no
// `&mut Int` scalar parameters are used (all state lives in the Phaser
// struct and is threaded through returns); hook kinds are dispatched with an
// explicit case chain (concrete specializations, no function tables).

module xiom.phaser

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum registered parties, mirroring java.util.concurrent.Phaser's
/// 16-bit party field (65535).
pub const PHASER_MAX_PARTIES: Int = 65535;

/// Maximum arrival budget accepted by the bounded progression helpers.
pub const PHASER_MAX_ARRIVALS: Int = 1000000;

/// Hook kind: terminate when the registered party count has become zero
/// after a phase completion (the Java default onAdvance).
pub const PHASER_HOOK_DEFAULT: Int = 0;

/// Hook kind: terminate after `hook_param` phases have completed.
pub const PHASER_HOOK_UNTIL_PHASE: Int = 1;

/// Hook kind: terminate on the first phase completion.
pub const PHASER_HOOK_ALWAYS: Int = 2;

/// Hook kind: never terminate (the bounded progression helpers still stop).
pub const PHASER_HOOK_NEVER: Int = 3;

/// Hook result: the phaser continues to the next phase.
pub const PHASER_CONTINUE: Int = 0;

/// Hook result: the phaser enters the final termination state.
pub const PHASER_TERMINATE: Int = 1;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Phaser state. Every field is an internal implementation detail; callers
/// must go through the phaser_* free functions.
///
/// `handle` is the caller-assigned identity used for parent linking (>= 0);
/// `parent` is the parent's handle (-1 for a root). `parties` is the number
/// of registered party credits, `arrived` the number of them that have
/// arrived in the current phase, and `unarrived` is always
/// `parties - arrived`. `phase` is the current phase index (0-based, one
/// increment per completed phase; it equals `advances_total`). `terminated`
/// is the final state; a terminated phaser has zero parties, zero arrivals
/// and `phase` == `last_phase_parties` >= 1. `hook`/`hook_param` select the
/// onAdvance-style callback (see the PHASER_HOOK_* constants). `children`
/// counts the child phasers currently registered with this one (each child
/// holds exactly one party credit here). `arrivals_total` counts successful
/// arrivals, `registrations_total` parties added by register/bulk_register,
/// `deregistrations_total` parties removed by arrive_and_deregister, and
/// `last_phase_parties` the number of party credits that completed the most
/// recent phase (-1 before the first completion).
pub type Phaser = {
  handle: Int;
  parent: Int;
  parties: Int;
  arrived: Int;
  phase: Int;
  terminated: Bool;
  hook: Int;
  hook_param: Int;
  children: Int;
  arrivals_total: Int;
  registrations_total: Int;
  deregistrations_total: Int;
  advances_total: Int;
  last_phase_parties: Int;
}

/// Outcome of one arrival (arrive / arrive_and_await /
/// arrive_and_deregister).
///
/// `phase` is the phase the arrival joined (the phase that just completed
/// when `advanced` is true); `new_phase` is the phase counter after the
/// call. `advanced` is true when this arrival completed the phase;
/// `terminated` is true when the completion terminated the phaser;
/// `released` is true when the phase joined is already complete or the
/// phaser terminated (a non-blocking arrive caller ignores it; an awaiting
/// caller that sees false parks until `phaser_waiter_released(p, phase)`).
/// `parties`, `arrived` and `unarrived` are the counts after the call.
pub type ArrivalOutcome = {
  phase: Int;
  new_phase: Int;
  advanced: Bool;
  terminated: Bool;
  released: Bool;
  parties: Int;
  arrived: Int;
  unarrived: Int;
}

/// Outcome of one tiered arrival (child advance propagation to the parent).
/// `child_advanced`/`child_terminated` describe the child transition;
/// `parent_advanced`/`parent_terminated` the parent transition caused by the
/// child's advance (false when the child did not advance). `parent_parties`
/// and `parent_phase` are the parent counts after the call.
pub type TierOutcome = {
  child_advanced: Bool;
  child_terminated: Bool;
  parent_advanced: Bool;
  parent_terminated: Bool;
  parent_parties: Int;
  parent_phase: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_phaser(v: Phaser) -> Result[Phaser, Str] { return Ok(v); }
fn _err_phaser(m: Str) -> Result[Phaser, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_arrival(v: ArrivalOutcome) -> Result[ArrivalOutcome, Str] { return Ok(v); }
fn _err_arrival(m: Str) -> Result[ArrivalOutcome, Str] { return Err(m); }
fn _ok_tier(v: TierOutcome) -> Result[TierOutcome, Str] { return Ok(v); }
fn _err_tier(m: Str) -> Result[TierOutcome, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// onAdvance-style hooks (concrete specializations returning continue/terminate)
// ---------------------------------------------------------------------------

/// Java's default onAdvance: terminate once no party remains registered.
/// Params: completed_phase - the phase that just completed; parties - the
/// registered party count the transition ends with.
/// Returns: PHASER_TERMINATE when parties <= 0, else PHASER_CONTINUE.
/// Complexity: O(1).
pub fn phaser_hook_default(completed_phase: Int, parties: Int) -> Int {
  if parties <= 0 { return PHASER_TERMINATE; }
  return PHASER_CONTINUE;
}

/// Terminate after `limit` phases have completed (Java's
/// `phase >= iterations - 1 || registeredParties == 0` idiom).
/// Params: completed_phase - the phase that just completed (0-based);
///         parties - the registered party count the transition ends with;
///         limit - total phases to run, >= 1.
/// Returns: PHASER_TERMINATE when parties <= 0 or completed_phase + 1 >=
/// limit, else PHASER_CONTINUE.
/// Complexity: O(1).
pub fn phaser_hook_until_phase(completed_phase: Int, parties: Int, limit: Int) -> Int {
  if parties <= 0 { return PHASER_TERMINATE; }
  if limit < 1 { return PHASER_TERMINATE; }
  if completed_phase + 1 >= limit { return PHASER_TERMINATE; }
  return PHASER_CONTINUE;
}

/// Terminate on the first completed phase (a one-shot barrier).
/// Complexity: O(1).
pub fn phaser_hook_always(completed_phase: Int, parties: Int) -> Int {
  return PHASER_TERMINATE;
}

/// Never terminate: the phaser keeps advancing phases until an external
/// bound stops the driver.
/// Complexity: O(1).
pub fn phaser_hook_never(completed_phase: Int, parties: Int) -> Int {
  return PHASER_CONTINUE;
}

/// Evaluate a hook by kind with an explicit case chain (concrete
/// specializations; unknown kinds fall back to the default hook).
/// Params: kind - a PHASER_HOOK_* constant; param - the kind's parameter;
///         completed_phase - the phase that just completed; parties - the
///         registered party count the transition ends with.
/// Returns: PHASER_CONTINUE or PHASER_TERMINATE.
/// Complexity: O(1).
pub fn phaser_hook_eval(kind: Int, param: Int, completed_phase: Int, parties: Int) -> Int {
  if kind == PHASER_HOOK_UNTIL_PHASE {
    return phaser_hook_until_phase(completed_phase, parties, param);
  }
  if kind == PHASER_HOOK_ALWAYS {
    return phaser_hook_always(completed_phase, parties);
  }
  if kind == PHASER_HOOK_NEVER {
    return phaser_hook_never(completed_phase, parties);
  }
  return phaser_hook_default(completed_phase, parties);
}

// ---------------------------------------------------------------------------
// Internal transition helpers
// ---------------------------------------------------------------------------

// Evaluate the phaser's configured hook for a completion.
fn _hook_code(p: &Phaser, completed_phase: Int, parties: Int) -> Int {
  let kind: Int = p.hook;
  let param: Int = p.hook_param;
  return phaser_hook_eval(kind, param, completed_phase, parties);
}

// Complete the current phase: publish the phase-parties count, advance the
// phase counter, run the hook and either continue or terminate. `phase_parties`
// is the number of party credits that completed the phase; `hook_parties` is
// the party count the hook observes (equal for a plain arrival, reduced by
// one for a completing deregistration).
fn _advance(p: &mut Phaser, completed_phase: Int, phase_parties: Int, hook_parties: Int) -> ArrivalOutcome {
  p.phase = completed_phase + 1;
  p.advances_total = p.advances_total + 1;
  p.arrived = 0;
  p.last_phase_parties = phase_parties;
  let code: Int = _hook_code(p, completed_phase, hook_parties);
  if code == PHASER_TERMINATE {
    p.terminated = true;
    p.parties = 0;
    p.children = 0;
    return ArrivalOutcome{
      phase: completed_phase;
      new_phase: p.phase;
      advanced: true;
      terminated: true;
      released: true;
      parties: 0;
      arrived: 0;
      unarrived: 0;
    };
  }
  p.parties = hook_parties;
  if hook_parties == 0 {
    // Reaching zero parties without termination (HOOK_NEVER) leaves an inert
    // phaser: the child credits cannot be backed by parties any more.
    p.children = 0;
  }
  return ArrivalOutcome{
    phase: completed_phase;
    new_phase: p.phase;
    advanced: true;
    terminated: false;
    released: true;
    parties: hook_parties;
    arrived: 0;
    unarrived: hook_parties;
  };
}

// Record one plain arrival.
fn _do_arrive(p: &mut Phaser) -> Result[ArrivalOutcome, Str] {
  if p.terminated { return _err_arrival("phaser: terminated"); }
  if p.parties < 1 { return _err_arrival("phaser: no registered parties"); }
  let before_parties: Int = p.parties;
  let before_unarrived: Int = p.parties - p.arrived;
  p.arrived = p.arrived + 1;
  p.arrivals_total = p.arrivals_total + 1;
  if before_unarrived == 1 {
    return _ok_arrival(_advance(p, p.phase, before_parties, before_parties));
  }
  return _ok_arrival(ArrivalOutcome{
    phase: p.phase;
    new_phase: p.phase;
    advanced: false;
    terminated: false;
    released: false;
    parties: p.parties;
    arrived: p.arrived;
    unarrived: p.parties - p.arrived;
  });
}

// Record one arrival and deregister the arriving party.
fn _do_arrive_and_deregister(p: &mut Phaser) -> Result[ArrivalOutcome, Str] {
  if p.terminated { return _err_arrival("phaser: terminated"); }
  if p.parties < 1 { return _err_arrival("phaser: no registered parties"); }
  let before_parties: Int = p.parties;
  let before_unarrived: Int = p.parties - p.arrived;
  p.arrivals_total = p.arrivals_total + 1;
  p.deregistrations_total = p.deregistrations_total + 1;
  if before_unarrived == 1 {
    return _ok_arrival(_advance(p, p.phase, before_parties, before_parties - 1));
  }
  p.parties = p.parties - 1;
  if p.children > p.parties {
    p.children = p.parties;
  }
  return _ok_arrival(ArrivalOutcome{
    phase: p.phase;
    new_phase: p.phase;
    advanced: false;
    terminated: false;
    released: false;
    parties: p.parties;
    arrived: p.arrived;
    unarrived: p.parties - p.arrived;
  });
}

// Perform a plain arrival and classify it: 2 = advanced and terminated,
// 1 = advanced, 0 = recorded without advancing, -9 = error.
fn _arrive_code(p: &mut Phaser) -> Int {
  match _do_arrive(p) {
    Ok(o) => {
      if o.terminated { return 2; }
      if o.advanced { return 1; }
      return 0;
    },
    Err(_) => { return -9; },
  }
  return -9;
}

// Assemble a TierOutcome (keeps the nested match arms branch-free).
fn _tier_make(ca: Bool, ct: Bool, pa: Bool, pt: Bool, pp: Int, pph: Int) -> TierOutcome {
  return TierOutcome{
    child_advanced: ca;
    child_terminated: ct;
    parent_advanced: pa;
    parent_terminated: pt;
    parent_parties: pp;
    parent_phase: pph;
  };
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Create a root phaser with `parties` registered parties, phase 0 and the
/// default hook. A phaser with zero parties is valid and inert until it is
/// registered with (Java `new Phaser(0)`), but it never advances by itself.
/// Params: handle - caller-assigned identity, must be >= 0; parties -
///         initially registered parties, 0 <= parties <= PHASER_MAX_PARTIES.
/// Returns: Ok(Phaser); Err("phaser: handle must be >= 0"),
/// Err("phaser: parties must be >= 0") or Err("phaser: parties limit
/// exceeded") otherwise (no state exists yet).
/// Complexity: O(1).
pub fn phaser_new(handle: Int, parties: Int) -> Result[Phaser, Str] {
  if handle < 0 {
    return _err_phaser("phaser: handle must be >= 0");
  }
  if parties < 0 {
    return _err_phaser("phaser: parties must be >= 0");
  }
  if parties > PHASER_MAX_PARTIES {
    return _err_phaser("phaser: parties limit exceeded");
  }
  return _ok_phaser(Phaser{
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
  });
}

/// Create a child phaser and register one party credit on its parent
/// (Java `new Phaser(parent, parties)`). Every later child phase advance
/// contributes one arrival to the parent; a terminal child advance
/// deregisters the credit again. The child starts in phase 0 with the
/// default hook.
/// Params: parent - the parent phaser (must not be terminated); handle -
///         caller-assigned child identity, >= 0 and different from the
///         parent's; parties - the child's registered parties, >= 1
///         (a zero-party child carries no parent credit and is not modelled).
/// Returns: Ok(Phaser); Err("phaser: terminated"),
/// Err("phaser: handle must be >= 0"),
/// Err("phaser: child handle must differ from parent"),
/// Err("phaser: child parties must be >= 1") or Err("phaser: parties limit
/// exceeded") otherwise -- in every Err case the parent is unchanged.
/// Complexity: O(1).
pub fn phaser_new_child(parent: &mut Phaser, handle: Int, parties: Int) -> Result[Phaser, Str] {
  if parent.terminated {
    return _err_phaser("phaser: terminated");
  }
  if handle < 0 {
    return _err_phaser("phaser: handle must be >= 0");
  }
  if handle == parent.handle {
    return _err_phaser("phaser: child handle must differ from parent");
  }
  if parties < 1 {
    return _err_phaser("phaser: child parties must be >= 1");
  }
  if parties > PHASER_MAX_PARTIES {
    return _err_phaser("phaser: parties limit exceeded");
  }
  if parent.parties + 1 > PHASER_MAX_PARTIES {
    return _err_phaser("phaser: parties limit exceeded");
  }
  let parent_handle: Int = parent.handle;
  parent.parties = parent.parties + 1;
  parent.children = parent.children + 1;
  return _ok_phaser(Phaser{
    handle: handle;
    parent: parent_handle;
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
  });
}

// ---------------------------------------------------------------------------
// Registration (dynamic party set)
// ---------------------------------------------------------------------------

/// Register exactly one new unarrived party (Java `register()`).
/// A registration during an active phase increases `parties` alone: the new
/// party must still arrive before the phase can complete.
/// Params: p - the phaser.
/// Returns: Ok(registered party count) or Err("phaser: terminated") /
/// Err("phaser: parties limit exceeded") -- in every Err case the state is
/// unchanged.
/// Complexity: O(1).
pub fn phaser_register(p: &mut Phaser) -> Result[Int, Str] {
  if p.terminated {
    return _err_int("phaser: terminated");
  }
  if p.parties + 1 > PHASER_MAX_PARTIES {
    return _err_int("phaser: parties limit exceeded");
  }
  p.parties = p.parties + 1;
  p.registrations_total = p.registrations_total + 1;
  return _ok_int(p.parties);
}

/// Register `n` new unarrived parties (Java `bulkRegister(n)`); `n == 0` is
/// a no-op returning the current party count.
/// Params: p - the phaser; n - parties to add, 0 <= n.
/// Returns: Ok(registered party count); Err("phaser: count must be >= 0"),
/// Err("phaser: terminated") or Err("phaser: parties limit exceeded") -- in
/// every Err case the state is unchanged.
/// Complexity: O(1).
pub fn phaser_bulk_register(p: &mut Phaser, n: Int) -> Result[Int, Str] {
  if n < 0 {
    return _err_int("phaser: count must be >= 0");
  }
  if p.terminated {
    return _err_int("phaser: terminated");
  }
  if n > PHASER_MAX_PARTIES - p.parties {
    return _err_int("phaser: parties limit exceeded");
  }
  p.parties = p.parties + n;
  p.registrations_total = p.registrations_total + n;
  return _ok_int(p.parties);
}

// ---------------------------------------------------------------------------
// Arrival (non-blocking core + await predicate)
// ---------------------------------------------------------------------------

/// Arrive at the phaser without waiting (Java `arrive()`).
/// The arrival is recorded; when it is the last unarrived party the phase
/// completes, the hook runs and the arrival outcome reports the completion.
/// Params: p - the phaser.
/// Returns: Ok(ArrivalOutcome); Err("phaser: terminated") or
/// Err("phaser: no registered parties") -- in every Err case the state is
/// unchanged.
/// Complexity: O(1).
pub fn phaser_arrive(p: &mut Phaser) -> Result[ArrivalOutcome, Str] {
  return _do_arrive(p);
}

/// Arrive and model `arriveAndAwaitAdvance()`: the recorded arrival is
/// identical to `phaser_arrive`; when `released` is false the caller must
/// park until `phaser_waiter_released(p, outcome.phase)` becomes true (the
/// phase advances or the phaser terminates). When this arrival completes the
/// phase the caller is released immediately (`released` is true).
/// Params: p - the phaser.
/// Returns: Ok(ArrivalOutcome); Err("phaser: terminated") or
/// Err("phaser: no registered parties") -- in every Err case the state is
/// unchanged.
/// Complexity: O(1).
pub fn phaser_arrive_and_await(p: &mut Phaser) -> Result[ArrivalOutcome, Str] {
  return _do_arrive(p);
}

/// Arrive and deregister (Java `arriveAndDeregister()`). When the arrival
/// completes the phase, the hook observes the reduced party count; otherwise
/// the party count drops by one and the arrived count is unchanged (the
/// party both arrived and left).
/// Params: p - the phaser.
/// Returns: Ok(ArrivalOutcome); Err("phaser: terminated") or
/// Err("phaser: no registered parties") -- in every Err case the state is
/// unchanged.
/// Complexity: O(1).
pub fn phaser_arrive_and_deregister(p: &mut Phaser) -> Result[ArrivalOutcome, Str] {
  return _do_arrive_and_deregister(p);
}

/// True when a caller that arrived in phase `joined_phase` has been
/// released: the phaser terminated, the phase counter moved past
/// `joined_phase`, or the argument is negative (always in the past).
/// Params: p - the phaser; joined_phase - the phase recorded at arrival.
/// Complexity: O(1).
pub fn phaser_waiter_released(p: &Phaser, joined_phase: Int) -> Bool {
  if joined_phase < 0 { return true; }
  if p.terminated { return true; }
  return p.phase > joined_phase;
}

// ---------------------------------------------------------------------------
// Termination hook configuration
// ---------------------------------------------------------------------------

/// Select the onAdvance-style hook (kind and parameter).
/// Params: p - the phaser; kind - a PHASER_HOOK_* constant; param - the
///         hook parameter (PHASER_HOOK_UNTIL_PHASE requires >= 1; ignored by
///         the other kinds).
/// Returns: Ok(kind); Err("phaser: terminated"),
/// Err("phaser: invalid hook kind") or Err("phaser: hook limit must be >= 1")
/// -- in every Err case the state is unchanged.
/// Complexity: O(1).
pub fn phaser_set_hook(p: &mut Phaser, kind: Int, param: Int) -> Result[Int, Str] {
  if p.terminated {
    return _err_int("phaser: terminated");
  }
  if kind < PHASER_HOOK_DEFAULT {
    return _err_int("phaser: invalid hook kind");
  }
  if kind > PHASER_HOOK_NEVER {
    return _err_int("phaser: invalid hook kind");
  }
  if kind == PHASER_HOOK_UNTIL_PHASE {
    if param < 1 {
      return _err_int("phaser: hook limit must be >= 1");
    }
  }
  p.hook = kind;
  p.hook_param = param;
  return _ok_int(kind);
}

// ---------------------------------------------------------------------------
// Bounded progression helpers (deadlock-safe drivers)
// ---------------------------------------------------------------------------

// Bounded-driver result constructors are shared with _ok_int/_err_int.

/// Drive arrivals until the current phase completes once, the phaser
/// terminates, or the arrival budget is exhausted.
/// Params: p - the phaser; max_arrivals - arrival budget for this call,
///         0 <= max_arrivals <= PHASER_MAX_ARRIVALS.
/// Returns: Ok(arrivals used) when the phase advanced or the phaser is/was
/// terminated (0 when already terminated); Err("phaser: limit must be >= 0"),
/// Err("phaser: limit exceeds maximum"), Err("phaser: no registered
/// parties") or Err("phaser: arrival limit reached") otherwise -- in every
/// Err case no arrival is recorded.
/// Complexity: O(max_arrivals).
pub fn phaser_complete_phase(p: &mut Phaser, max_arrivals: Int) -> Result[Int, Str] {
  if max_arrivals < 0 {
    return _err_int("phaser: limit must be >= 0");
  }
  if max_arrivals > PHASER_MAX_ARRIVALS {
    return _err_int("phaser: limit exceeds maximum");
  }
  if p.terminated {
    return _ok_int(0);
  }
  if p.parties < 1 {
    return _err_int("phaser: no registered parties");
  }
  let start_phase: Int = p.phase;
  var used: Int = 0;
  while !p.terminated {
    if p.phase != start_phase {
      return _ok_int(used);
    }
    if used >= max_arrivals {
      return _err_int("phaser: arrival limit reached");
    }
    match _do_arrive(p) {
      Ok(_) => { used = used + 1; },
      Err(e) => { return _err_int(e); },
    }
  }
  return _ok_int(used);
}

/// Drive complete phases until the phaser terminates, bounded by a total
/// arrival budget. A phaser that cannot terminate (HOOK_NEVER, or a
/// default-hook phaser whose party count never reaches zero) fails with
/// "phaser: arrival limit reached" instead of hanging.
/// Params: p - the phaser; max_arrivals - total arrival budget,
///         0 <= max_arrivals <= PHASER_MAX_ARRIVALS.
/// Returns: Ok(total arrivals) when the phaser terminates (0 when already
/// terminated); Err("phaser: limit must be >= 0"),
/// Err("phaser: limit exceeds maximum"), Err("phaser: no registered
/// parties") or Err("phaser: arrival limit reached") otherwise -- in every
/// Err case the budget is exhausted/blocked before any further transition.
/// Complexity: O(max_arrivals).
pub fn phaser_run_to_termination(p: &mut Phaser, max_arrivals: Int) -> Result[Int, Str] {
  if max_arrivals < 0 {
    return _err_int("phaser: limit must be >= 0");
  }
  if max_arrivals > PHASER_MAX_ARRIVALS {
    return _err_int("phaser: limit exceeds maximum");
  }
  var total: Int = 0;
  while !p.terminated {
    if p.parties < 1 {
      return _err_int("phaser: no registered parties");
    }
    let remaining: Int = max_arrivals - total;
    if remaining <= 0 {
      return _err_int("phaser: arrival limit reached");
    }
    match phaser_complete_phase(p, remaining) {
      Ok(n) => { total = total + n; },
      Err(e) => { return _err_int(e); },
    }
  }
  return _ok_int(total);
}

// ---------------------------------------------------------------------------
// Tiered phasers (child advance propagates to the parent)
// ---------------------------------------------------------------------------

/// Arrive at a child phaser through its parent link, propagating the child's
/// phase advance: when the child completes a phase it contributes one
/// arrival to the parent; when the child terminates on that advance it
/// deregisters its parent credit (a parent arrive-and-deregister). A child
/// that does not advance leaves the parent untouched.
/// Params: child - the child phaser; parent - the parent phaser (the pair
///         must be linked by phaser_new_child).
/// Returns: Ok(TierOutcome); Err("phaser: not a child"), Err("phaser:
/// terminated"), Err("phaser: parent terminated"),
/// Err("phaser: no registered parties") or Err("phaser: parent has no
/// registered parties") -- in every Err case neither state changes.
/// Complexity: O(1).
pub fn phaser_arrive_tiered(child: &mut Phaser, parent: &mut Phaser) -> Result[TierOutcome, Str] {
  if child.parent != parent.handle {
    return _err_tier("phaser: not a child");
  }
  if child.terminated {
    return _err_tier("phaser: terminated");
  }
  if parent.terminated {
    return _err_tier("phaser: parent terminated");
  }
  if child.parties < 1 {
    return _err_tier("phaser: no registered parties");
  }
  if parent.parties < 1 {
    return _err_tier("phaser: parent has no registered parties");
  }
  let code: Int = _arrive_code(child);
  if code < 0 {
    return _err_tier("phaser: terminated");
  }
  if code == 0 {
    return _ok_tier(_tier_make(false, false, false, false, parent.parties, parent.phase));
  }
  if code == 2 {
    match _do_arrive_and_deregister(parent) {
      Ok(po) => {
        if !po.terminated {
          if parent.children > 0 {
            parent.children = parent.children - 1;
          }
        }
        return _ok_tier(_tier_make(true, true, po.advanced, po.terminated, po.parties, po.new_phase));
      },
      Err(e) => { return _err_tier(e); },
    }
  }
  match _do_arrive(parent) {
    Ok(po2) => {
      return _ok_tier(_tier_make(true, false, po2.advanced, po2.terminated, po2.parties, po2.new_phase));
    },
    Err(e2) => { return _err_tier(e2); },
  }
  return _err_tier("phaser: unreachable");
}

// ---------------------------------------------------------------------------
// Accessors (read-only)
// ---------------------------------------------------------------------------

/// Caller-assigned identity handle. O(1).
pub fn phaser_handle(p: &Phaser) -> Int {
  return p.handle;
}

/// Parent handle (-1 for a root). O(1).
pub fn phaser_parent(p: &Phaser) -> Int {
  return p.parent;
}

/// True when the phaser was created with phaser_new_child. O(1).
pub fn phaser_is_child(p: &Phaser) -> Bool {
  return p.parent != -1;
}

/// Child phasers currently registered with this phaser. O(1).
pub fn phaser_child_count(p: &Phaser) -> Int {
  return p.children;
}

/// Registered party credits. O(1).
pub fn phaser_parties(p: &Phaser) -> Int {
  return p.parties;
}

/// Registered parties that have arrived in the current phase. O(1).
pub fn phaser_arrived(p: &Phaser) -> Int {
  return p.arrived;
}

/// Registered parties that have not yet arrived (parties - arrived). O(1).
pub fn phaser_unarrived(p: &Phaser) -> Int {
  return p.parties - p.arrived;
}

/// Current phase index (equals the number of completed phases). O(1).
pub fn phaser_phase(p: &Phaser) -> Int {
  return p.phase;
}

/// True once the phaser has entered the final termination state. O(1).
pub fn phaser_is_terminated(p: &Phaser) -> Bool {
  return p.terminated;
}

/// Phase at which the phaser terminated, or -1 while it is active. O(1).
pub fn phaser_last_phase(p: &Phaser) -> Int {
  if !p.terminated { return -1; }
  return p.phase;
}

/// Configured hook kind (a PHASER_HOOK_* constant). O(1).
pub fn phaser_hook_kind(p: &Phaser) -> Int {
  return p.hook;
}

/// Configured hook parameter. O(1).
pub fn phaser_hook_param(p: &Phaser) -> Int {
  return p.hook_param;
}

/// Successful arrivals since construction. O(1).
pub fn phaser_arrivals_total(p: &Phaser) -> Int {
  return p.arrivals_total;
}

/// Parties added through register/bulk_register since construction. O(1).
pub fn phaser_registration_total(p: &Phaser) -> Int {
  return p.registrations_total;
}

/// Parties removed through arrive_and_deregister since construction. O(1).
pub fn phaser_deregistration_total(p: &Phaser) -> Int {
  return p.deregistrations_total;
}

/// Completed phases since construction (equals the phase counter). O(1).
pub fn phaser_advance_total(p: &Phaser) -> Int {
  return p.advances_total;
}

/// Party credits that completed the most recent phase, or -1 before the
/// first completion. O(1).
pub fn phaser_last_phase_parties(p: &Phaser) -> Int {
  return p.last_phase_parties;
}

/// One-line state snapshot: `phase=P parties=R arrived=A unarrived=U` plus
/// a trailing ` terminated` when applicable. O(1).
pub fn phaser_state_str(p: &Phaser) -> Str {
  var out = "phase=";
  out = out + convert.int_to_string(p.phase);
  out = out + " parties=";
  out = out + convert.int_to_string(p.parties);
  out = out + " arrived=";
  out = out + convert.int_to_string(p.arrived);
  out = out + " unarrived=";
  out = out + convert.int_to_string(p.parties - p.arrived);
  if p.terminated {
    out = out + " terminated";
  }
  return out;
}

// ---------------------------------------------------------------------------
// Invariant check
// ---------------------------------------------------------------------------

/// Structural invariant of a phaser:
/// handle >= 0; parent >= -1 and different from handle; 0 <= parties <=
/// PHASER_MAX_PARTIES; 0 <= arrived <= parties (arrived < parties while
/// parties > 0); phase == advances_total >= 0; `last_phase_parties` is -1
/// before the first completion and >= 1 afterwards; 0 <= children <=
/// parties; hook is a PHASER_HOOK_* kind (UNTIL_PHASE needs param >= 1);
/// counters are non-negative and at least `arrived`/`phase`; a terminated
/// phaser has zero parties/arrivals/children, phase >= 1 and
/// last_phase_parties >= 1.
/// Complexity: O(1).
pub fn phaser_check_invariant(p: &Phaser) -> Bool {
  if p.handle < 0 { return false; }
  if p.parent < -1 { return false; }
  if p.parent == p.handle { return false; }
  if p.parties < 0 { return false; }
  if p.parties > PHASER_MAX_PARTIES { return false; }
  if p.arrived < 0 { return false; }
  if p.arrived > p.parties { return false; }
  if p.parties > 0 && p.arrived == p.parties { return false; }
  if p.phase < 0 { return false; }
  if p.phase != p.advances_total { return false; }
  if p.last_phase_parties < -1 { return false; }
  if p.phase == 0 && p.last_phase_parties != -1 { return false; }
  if p.phase > 0 && p.last_phase_parties < 1 { return false; }
  if p.children < 0 { return false; }
  if p.parties == 0 && p.children != 0 { return false; }
  if p.children > p.parties { return false; }
  if p.hook < PHASER_HOOK_DEFAULT { return false; }
  if p.hook > PHASER_HOOK_NEVER { return false; }
  if p.hook == PHASER_HOOK_UNTIL_PHASE && p.hook_param < 1 { return false; }
  if p.arrivals_total < 0 { return false; }
  if p.registrations_total < 0 { return false; }
  if p.deregistrations_total < 0 { return false; }
  if p.arrivals_total < p.arrived { return false; }
  if p.arrivals_total < p.phase { return false; }
  if p.terminated {
    if p.parties != 0 { return false; }
    if p.arrived != 0 { return false; }
    if p.children != 0 { return false; }
    if p.phase < 1 { return false; }
    if p.last_phase_parties < 1 { return false; }
  }
  return true;
}
