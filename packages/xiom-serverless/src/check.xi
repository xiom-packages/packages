// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.serverless.check: structural invariant of a ServerlessSystem
// (as defined by xiom.serverless, including the invocation/runtime fields
// owned by xiom.serverless.invoke). Read-only and pure; module-local copies of
// the private index/validity helpers keep this module independent of the
// private surface of its siblings. Language notes (XIOM v0.62.2): free
// functions only; typed `let` for Vec[Int] element reads; no Vec[StructType],
// no Vec[Str], no indexed Vec[fn] dispatch, no generic callbacks, no
// Vec[Float64], no `mut` patterns.

module xiom.serverless.check

use xiom.serverless;

// Private table selectors (same values as xiom.serverless).
const _TBL_FN: Int = 0;
const _TBL_TRIGGER: Int = 1;
const _TBL_DEPLOY: Int = 2;
const _TBL_INVOCATION: Int = 3;
const _TBL_INSTANCE: Int = 4;

// ---------------------------------------------------------------------------
// Internal helpers (module-local copies)
// ---------------------------------------------------------------------------

fn _is_valid_handler(h: Int) -> Bool {
  if h == SV_HANDLER_ECHO { return true; }
  if h == SV_HANDLER_DOUBLE { return true; }
  if h == SV_HANDLER_FAIL { return true; }
  return false;
}

fn _is_valid_trigger_kind(k: Int) -> Bool {
  if k == SV_TRIGGER_TIMER { return true; }
  if k == SV_TRIGGER_HTTP { return true; }
  if k == SV_TRIGGER_QUEUE { return true; }
  return false;
}

fn _is_valid_fn_state(st: Int) -> Bool {
  if st == SV_FN_DRAFT { return true; }
  if st == SV_FN_ACTIVE { return true; }
  if st == SV_FN_DISABLED { return true; }
  return false;
}

fn _is_valid_deploy_state(st: Int) -> Bool {
  if st == SV_DEPLOY_PENDING { return true; }
  if st == SV_DEPLOY_IN_PROGRESS { return true; }
  if st == SV_DEPLOY_READY { return true; }
  if st == SV_DEPLOY_FAILED { return true; }
  if st == SV_DEPLOY_ROLLED_BACK { return true; }
  return false;
}

fn _is_valid_inv_state(st: Int) -> Bool {
  if st == SV_INV_QUEUED { return true; }
  if st == SV_INV_RUNNING { return true; }
  if st == SV_INV_DONE { return true; }
  if st == SV_INV_FAILED { return true; }
  return false;
}

fn _is_valid_inst_state(st: Int) -> Bool {
  if st == SV_RT_COLD { return true; }
  if st == SV_RT_WARM { return true; }
  if st == SV_RT_BUSY { return true; }
  return false;
}

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

fn _dup_ids(s: &ServerlessSystem, which: Int) -> Bool {
  var n = 0;
  if which == _TBL_FN { n = s.function_ids.len(); }
  if which == _TBL_TRIGGER { n = s.trigger_ids.len(); }
  if which == _TBL_DEPLOY { n = s.deploy_ids.len(); }
  if which == _TBL_INVOCATION { n = s.invocation_ids.len(); }
  if which == _TBL_INSTANCE { n = s.instance_ids.len(); }
  var i = 0;
  while i < n {
    var a = 0;
    if which == _TBL_FN { a = s.function_ids[i]; }
    if which == _TBL_TRIGGER { a = s.trigger_ids[i]; }
    if which == _TBL_DEPLOY { a = s.deploy_ids[i]; }
    if which == _TBL_INVOCATION { a = s.invocation_ids[i]; }
    if which == _TBL_INSTANCE { a = s.instance_ids[i]; }
    var j = i + 1;
    while j < n {
      var b = 0;
      if which == _TBL_FN { b = s.function_ids[j]; }
      if which == _TBL_TRIGGER { b = s.trigger_ids[j]; }
      if which == _TBL_DEPLOY { b = s.deploy_ids[j]; }
      if which == _TBL_INVOCATION { b = s.invocation_ids[j]; }
      if which == _TBL_INSTANCE { b = s.instance_ids[j]; }
      if a == b { return true; }
      j = j + 1;
    }
    i = i + 1;
  }
  return false;
}

fn _queue_has(s: &ServerlessSystem, id: Int) -> Bool {
  var i = 0;
  while i < s.queue.len() {
    let cur: Int = s.queue[i];
    if cur == id { return true; }
    i = i + 1;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Structural invariant
// ---------------------------------------------------------------------------

/// Structural invariant of a system, true exactly when:
/// 1. every entity table has equal-length parallel vectors and unique ids;
/// 2. function states/versions/handlers/memory/timeouts are valid; version 0
///    implies DRAFT, ACTIVE/DISABLED imply version >= 1;
/// 3. trigger functions exist; kinds/enable flags are valid; fires >= 0;
/// 4. deploy functions exist; states valid; 1 <= steps_total and
///    0 <= steps_done <= steps_total; versions >= 1; READY implies all steps
///    done; FAILED carries code >= 1; every other state carries code 0,
///    except ROLLED_BACK, which keeps the failure code of a sealed FAILED
///    rollout;
/// 5. invocation functions exist; states valid; DONE implies code == 0 and
///    FAILED implies code != 0;
/// 6. the queue holds exactly the QUEUED invocations, each exactly once;
/// 7. instance functions exist; states valid; served >= 0;
/// 8. running equals the RUNNING count and is within max_concurrency;
///    completed + failed equals the terminal count; the trace lists each
///    terminal invocation exactly once; cold_invocations + warm_invocations +
///    aborted == completed + failed; cold_start_ms == cold_starts * boot_ms.
/// Complexity: O(n^2) over each entity table.
pub fn serverless_check_invariant(s: &ServerlessSystem) -> Bool {
  let nf = s.function_ids.len();
  if s.function_states.len() != nf || s.function_versions.len() != nf || s.function_handlers.len() != nf { return false; }
  if s.function_memory_mb.len() != nf || s.function_timeout_ms.len() != nf { return false; }
  if _dup_ids(s, _TBL_FN) { return false; }
  var f = 0;
  while f < nf {
    let st: Int = s.function_states[f];
    let ver: Int = s.function_versions[f];
    let h: Int = s.function_handlers[f];
    let mem: Int = s.function_memory_mb[f];
    let tmo: Int = s.function_timeout_ms[f];
    if !_is_valid_fn_state(st) { return false; }
    if !_is_valid_handler(h) { return false; }
    if ver < 0 { return false; }
    if mem < 1 { return false; }
    if tmo < 1 { return false; }
    if ver == 0 && st != SV_FN_DRAFT { return false; }
    if st != SV_FN_DRAFT && ver < 1 { return false; }
    f = f + 1;
  }
  let nt = s.trigger_ids.len();
  if s.trigger_functions.len() != nt || s.trigger_kinds.len() != nt { return false; }
  if s.trigger_enabled.len() != nt || s.trigger_fires.len() != nt { return false; }
  if _dup_ids(s, _TBL_TRIGGER) { return false; }
  var t = 0;
  while t < nt {
    let fid: Int = s.trigger_functions[t];
    let k: Int = s.trigger_kinds[t];
    let en: Int = s.trigger_enabled[t];
    let fires: Int = s.trigger_fires[t];
    if _slot_in(s, _TBL_FN, fid) < 0 { return false; }
    if !_is_valid_trigger_kind(k) { return false; }
    if en != 0 && en != 1 { return false; }
    if fires < 0 { return false; }
    t = t + 1;
  }
  let nd = s.deploy_ids.len();
  if s.deploy_functions.len() != nd || s.deploy_states.len() != nd || s.deploy_versions.len() != nd { return false; }
  if s.deploy_steps_total.len() != nd || s.deploy_steps_done.len() != nd || s.deploy_codes.len() != nd { return false; }
  if s.deploy_prev_versions.len() != nd { return false; }
  if _dup_ids(s, _TBL_DEPLOY) { return false; }
  var d = 0;
  while d < nd {
    let fid: Int = s.deploy_functions[d];
    let st: Int = s.deploy_states[d];
    let ver: Int = s.deploy_versions[d];
    let total: Int = s.deploy_steps_total[d];
    let done: Int = s.deploy_steps_done[d];
    let code: Int = s.deploy_codes[d];
    if _slot_in(s, _TBL_FN, fid) < 0 { return false; }
    if !_is_valid_deploy_state(st) { return false; }
    if ver < 1 { return false; }
    if total < 1 { return false; }
    if done < 0 || done > total { return false; }
    if st == SV_DEPLOY_READY && done != total { return false; }
    if code < 0 { return false; }
    if st == SV_DEPLOY_FAILED && code < 1 { return false; }
    if st != SV_DEPLOY_FAILED && st != SV_DEPLOY_ROLLED_BACK && code != SV_CODE_OK { return false; }
    d = d + 1;
  }
  let ni = s.invocation_ids.len();
  if s.invocation_functions.len() != ni || s.invocation_states.len() != ni || s.invocation_payloads.len() != ni { return false; }
  if s.invocation_outputs.len() != ni || s.invocation_codes.len() != ni { return false; }
  if s.invocation_instances.len() != ni || s.invocation_colds.len() != ni { return false; }
  if _dup_ids(s, _TBL_INVOCATION) { return false; }
  var queued = 0;
  var running = 0;
  var terminal = 0;
  var i = 0;
  while i < ni {
    let fid: Int = s.invocation_functions[i];
    let st: Int = s.invocation_states[i];
    let code: Int = s.invocation_codes[i];
    if _slot_in(s, _TBL_FN, fid) < 0 { return false; }
    if !_is_valid_inv_state(st) { return false; }
    if st == SV_INV_QUEUED {
      queued = queued + 1;
      let iid: Int = s.invocation_ids[i];
      if !_queue_has(s, iid) { return false; }
    }
    if st == SV_INV_RUNNING { running = running + 1; }
    if st == SV_INV_DONE && code != SV_CODE_OK { return false; }
    if st == SV_INV_FAILED && code == SV_CODE_OK { return false; }
    if st == SV_INV_DONE || st == SV_INV_FAILED { terminal = terminal + 1; }
    i = i + 1;
  }
  if queued != s.queue.len() { return false; }
  var q = 0;
  while q < s.queue.len() {
    let qid: Int = s.queue[q];
    let qslot = _slot_in(s, _TBL_INVOCATION, qid);
    if qslot < 0 { return false; }
    let qst: Int = s.invocation_states[qslot];
    if qst != SV_INV_QUEUED { return false; }
    q = q + 1;
  }
  let nr = s.instance_ids.len();
  if s.instance_functions.len() != nr || s.instance_states.len() != nr || s.instance_served.len() != nr { return false; }
  if _dup_ids(s, _TBL_INSTANCE) { return false; }
  var r = 0;
  while r < nr {
    let fid: Int = s.instance_functions[r];
    let st: Int = s.instance_states[r];
    let served: Int = s.instance_served[r];
    if _slot_in(s, _TBL_FN, fid) < 0 { return false; }
    if !_is_valid_inst_state(st) { return false; }
    if served < 0 { return false; }
    r = r + 1;
  }
  if s.running != running { return false; }
  if s.running > s.max_concurrency { return false; }
  if s.completed + s.failed != terminal { return false; }
  if s.completion_order.len() != terminal { return false; }
  var c = 0;
  while c < s.completion_order.len() {
    let cid: Int = s.completion_order[c];
    let cslot = _slot_in(s, _TBL_INVOCATION, cid);
    if cslot < 0 { return false; }
    let cst: Int = s.invocation_states[cslot];
    if cst != SV_INV_DONE && cst != SV_INV_FAILED { return false; }
    var c2 = c + 1;
    while c2 < s.completion_order.len() {
      let other: Int = s.completion_order[c2];
      if other == cid { return false; }
      c2 = c2 + 1;
    }
    c = c + 1;
  }
  if s.cold_invocations + s.warm_invocations + s.aborted != s.completed + s.failed { return false; }
  if s.cold_start_ms != s.cold_starts * s.boot_ms { return false; }
  if s.next_instance_id < 0 { return false; }
  return true;
}
