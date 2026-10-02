// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.serverless.deploy: rollout state machine of xiom.serverless.
// PENDING -> IN_PROGRESS -> READY, plus FAILED and ROLLED_BACK; READY
// activates the target version on the function; rollback of a READY deploy
// restores the previous version and lifecycle, rollback of a FAILED deploy
// just seals the rollout. Pure and deterministic: free functions only; Ok/Err
// constructed only inside _ok_*/_err_* leaf helpers; typed `let` for Vec[Int]
// element reads; no Vec[StructType], no Vec[Str], no indexed Vec[fn] dispatch.

module xiom.serverless.deploy

use xiom.serverless;

// Private table selectors (same values as xiom.serverless).
const _TBL_FN: Int = 0;
const _TBL_TRIGGER: Int = 1;
const _TBL_DEPLOY: Int = 2;
const _TBL_INVOCATION: Int = 3;
const _TBL_INSTANCE: Int = 4;

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helper (module-local copy)
// ---------------------------------------------------------------------------

// Slot of entity `id` in table `which`, or -1 when unknown.
fn _slot_in(s: &ServerlessSystem, which: Int, id: Int) -> Int {
  var n = 0;
  if which == _TBL_FN { n = s.function_ids.len(); }
  if which == _TBL_TRIGGER { n = s.trigger_ids.len(); }
  if which == _TBL_DEPLOY { n = s.deploy_ids.len(); }
  if which == _TBL_INVOCATION { n = s.invocation_ids.len(); }
  if which == _TBL_INSTANCE { n = s.instance_ids.len(); }
  var i = 0;
  while i < n {
    var cur = 0;
    if which == _TBL_FN { cur = s.function_ids[i]; }
    if which == _TBL_TRIGGER { cur = s.trigger_ids[i]; }
    if which == _TBL_DEPLOY { cur = s.deploy_ids[i]; }
    if which == _TBL_INVOCATION { cur = s.invocation_ids[i]; }
    if which == _TBL_INSTANCE { cur = s.instance_ids[i]; }
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Rollout state machine
// ---------------------------------------------------------------------------

/// Begin a rollout of `version` for a function. The target version must be the
/// current version plus one (monotonic, no gaps); a DRAFT function starts at
/// version 0 and a rollout targets version 1.
/// Params: s - the system; deploy_id - unique deploy id, >= 0; function_id -
///         the target function; version - target version, = current + 1;
///         steps_total - rollout steps, >= 1.
/// Returns: Ok(deploy_id) in PENDING; Err("serverless: deploy id must be
///          >= 0"), Err("serverless: duplicate deploy id"),
///          Err("serverless: unknown function id"),
///          Err("serverless: function is disabled"),
///          Err("serverless: steps must be >= 1") or
///          Err("serverless: version must be current + 1") -- unchanged.
/// Complexity: O(function count + deploy count).
pub fn deploy_begin(s: &mut ServerlessSystem, deploy_id: Int, function_id: Int, version: Int, steps_total: Int) -> Result[Int, Str] {
  if deploy_id < 0 { return _err_int("serverless: deploy id must be >= 0"); }
  if _slot_in(s, _TBL_DEPLOY, deploy_id) >= 0 { return _err_int("serverless: duplicate deploy id"); }
  let fslot = _slot_in(s, _TBL_FN, function_id);
  if fslot < 0 { return _err_int("serverless: unknown function id"); }
  let fst: Int = s.function_states[fslot];
  if fst == SV_FN_DISABLED { return _err_int("serverless: function is disabled"); }
  if steps_total < 1 { return _err_int("serverless: steps must be >= 1"); }
  let cur: Int = s.function_versions[fslot];
  if version != cur + 1 { return _err_int("serverless: version must be current + 1"); }
  s.deploy_ids.push(deploy_id);
  s.deploy_functions.push(function_id);
  s.deploy_states.push(SV_DEPLOY_PENDING);
  s.deploy_versions.push(version);
  s.deploy_steps_total.push(steps_total);
  s.deploy_steps_done.push(0);
  s.deploy_codes.push(SV_CODE_OK);
  s.deploy_prev_versions.push(cur);
  return _ok_int(deploy_id);
}

/// Execute one rollout step. The first step moves PENDING -> IN_PROGRESS; the
/// step that reaches steps_total moves the deploy to READY and activates the
/// target version on the function.
/// Params: s - the system; deploy_id - the deploy.
/// Returns: Ok(steps_done); Err("serverless: unknown deploy id"),
///          Err("serverless: deploy already ready"),
///          Err("serverless: deploy already failed") or
///          Err("serverless: deploy already rolled back") -- unchanged.
/// Complexity: O(function count + deploy count).
pub fn deploy_step(s: &mut ServerlessSystem, deploy_id: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_DEPLOY, deploy_id);
  if slot < 0 { return _err_int("serverless: unknown deploy id"); }
  let st: Int = s.deploy_states[slot];
  if st == SV_DEPLOY_READY { return _err_int("serverless: deploy already ready"); }
  if st == SV_DEPLOY_FAILED { return _err_int("serverless: deploy already failed"); }
  if st == SV_DEPLOY_ROLLED_BACK { return _err_int("serverless: deploy already rolled back"); }
  let done: Int = s.deploy_steps_done[slot] + 1;
  s.deploy_steps_done[slot] = done;
  s.deploy_states[slot] = SV_DEPLOY_IN_PROGRESS;
  let total: Int = s.deploy_steps_total[slot];
  if done >= total {
    s.deploy_states[slot] = SV_DEPLOY_READY;
    let fid: Int = s.deploy_functions[slot];
    let fslot = _slot_in(s, _TBL_FN, fid);
    let ver: Int = s.deploy_versions[slot];
    s.function_versions[fslot] = ver;
    s.function_states[fslot] = SV_FN_ACTIVE;
  }
  return _ok_int(done);
}

/// Abort a rollout with a failure code (PENDING/IN_PROGRESS -> FAILED).
/// Params: s - the system; deploy_id - the deploy; code - failure code, >= 1.
/// Returns: Ok(code); Err("serverless: unknown deploy id"),
///          Err("serverless: deploy already ready"),
///          Err("serverless: deploy already failed"),
///          Err("serverless: deploy already rolled back") or
///          Err("serverless: failure code must be >= 1") -- unchanged.
/// Complexity: O(deploy count).
pub fn deploy_fail(s: &mut ServerlessSystem, deploy_id: Int, code: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_DEPLOY, deploy_id);
  if slot < 0 { return _err_int("serverless: unknown deploy id"); }
  let st: Int = s.deploy_states[slot];
  if st == SV_DEPLOY_READY { return _err_int("serverless: deploy already ready"); }
  if st == SV_DEPLOY_FAILED { return _err_int("serverless: deploy already failed"); }
  if st == SV_DEPLOY_ROLLED_BACK { return _err_int("serverless: deploy already rolled back"); }
  if code < 1 { return _err_int("serverless: failure code must be >= 1"); }
  s.deploy_states[slot] = SV_DEPLOY_FAILED;
  s.deploy_codes[slot] = code;
  return _ok_int(code);
}

/// Roll back a FAILED or READY deploy (-> ROLLED_BACK). Rolling back a READY
/// deploy restores the function version recorded at deploy_begin and sets the
/// function ACTIVE when that version was >= 1, DRAFT when it was 0.
/// Params: s - the system; deploy_id - the deploy.
/// Returns: Ok(deploy_id); Err("serverless: unknown deploy id"),
///          Err("serverless: deploy already rolled back") or
///          Err("serverless: deploy is not rollbackable") for a PENDING or
///          IN_PROGRESS deploy -- unchanged.
/// Complexity: O(function count + deploy count).
pub fn deploy_rollback(s: &mut ServerlessSystem, deploy_id: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_DEPLOY, deploy_id);
  if slot < 0 { return _err_int("serverless: unknown deploy id"); }
  let st: Int = s.deploy_states[slot];
  if st == SV_DEPLOY_ROLLED_BACK { return _err_int("serverless: deploy already rolled back"); }
  if st == SV_DEPLOY_READY {
    let fid: Int = s.deploy_functions[slot];
    let fslot = _slot_in(s, _TBL_FN, fid);
    let prev: Int = s.deploy_prev_versions[slot];
    s.function_versions[fslot] = prev;
    if prev >= 1 { s.function_states[fslot] = SV_FN_ACTIVE; } else { s.function_states[fslot] = SV_FN_DRAFT; }
    s.deploy_states[slot] = SV_DEPLOY_ROLLED_BACK;
    return _ok_int(deploy_id);
  }
  if st == SV_DEPLOY_FAILED {
    s.deploy_states[slot] = SV_DEPLOY_ROLLED_BACK;
    return _ok_int(deploy_id);
  }
  return _err_int("serverless: deploy is not rollbackable");
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Number of deploys. Complexity: O(1).
pub fn deploy_count(s: &ServerlessSystem) -> Int {
  return s.deploy_ids.len();
}

/// Rollout state of deploy `id` (SV_DEPLOY_*), or SV_NOT_FOUND (-1).
/// Complexity: O(deploy count).
pub fn deploy_state(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_DEPLOY, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let st: Int = s.deploy_states[slot];
  return st;
}

/// Rollout steps executed by deploy `id`, or SV_NOT_FOUND (-1).
/// Complexity: O(deploy count).
pub fn deploy_steps_done(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_DEPLOY, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let n: Int = s.deploy_steps_done[slot];
  return n;
}

/// Rollout step budget of deploy `id`, or SV_NOT_FOUND (-1).
/// Complexity: O(deploy count).
pub fn deploy_steps_total(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_DEPLOY, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let n: Int = s.deploy_steps_total[slot];
  return n;
}

/// Failure code of deploy `id` (0 while not FAILED), or SV_NOT_FOUND (-1).
/// Complexity: O(deploy count).
pub fn deploy_code(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_DEPLOY, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let c: Int = s.deploy_codes[slot];
  return c;
}
