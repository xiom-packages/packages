// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.serverless conformance tests (23 checks).
// Deterministic, no external files: every fixture is built in-test through
// serverless_new. All Str equality goes through compare.str_compare (BUG-17:
// `==` on Str lowers to a pointer comparison); Vec[Int] element reads use a
// typed `let`; read-only accessor calls are routed through small `&mut`
// wrappers so a `&local` read is never followed by a `&mut local` call in the
// same body (advisory E001). Result outcomes are classified into Int/Bool
// codes so the test bodies stay branch-light.

module serverless_tests
use xiom.io; use xiom.test;
use xiom.serverless; use xiom.serverless.deploy; use xiom.serverless.invoke; use xiom.serverless.check;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Stable error messages
// ---------------------------------------------------------------------------

const _E_MAXC: Str = "serverless: max_concurrency must be >= 1";
const _E_BOOT: Str = "serverless: boot_ms must be >= 0";
const _E_FN_ID: Str = "serverless: function id must be >= 0";
const _E_DUP_FN: Str = "serverless: duplicate function id";
const _E_HANDLER_UNKNOWN: Str = "serverless: unknown handler";
const _E_MEM: Str = "serverless: memory must be >= 1";
const _E_TMO_DEF: Str = "serverless: timeout must be >= 1";
const _E_UNKNOWN_FN: Str = "serverless: unknown function id";
const _E_FN_INACTIVE: Str = "serverless: function is not active";
const _E_FN_ACTIVE: Str = "serverless: function is already active";
const _E_FN_DISABLED: Str = "serverless: function is already disabled";
const _E_NO_DEPLOY: Str = "serverless: function has no deployment";
const _E_FN_IS_DISABLED: Str = "serverless: function is disabled";
const _E_DEPLOY_ID: Str = "serverless: deploy id must be >= 0";
const _E_DUP_DEPLOY: Str = "serverless: duplicate deploy id";
const _E_STEPS: Str = "serverless: steps must be >= 1";
const _E_VERSION: Str = "serverless: version must be current + 1";
const _E_UNKNOWN_DEPLOY: Str = "serverless: unknown deploy id";
const _E_DEPLOY_READY: Str = "serverless: deploy already ready";
const _E_DEPLOY_FAILED: Str = "serverless: deploy already failed";
const _E_DEPLOY_ROLLED: Str = "serverless: deploy already rolled back";
const _E_NOT_ROLLBACKABLE: Str = "serverless: deploy is not rollbackable";
const _E_FAIL_CODE: Str = "serverless: failure code must be >= 1";
const _E_TRIG_ID: Str = "serverless: trigger id must be >= 0";
const _E_DUP_TRIG: Str = "serverless: duplicate trigger id";
const _E_TRIG_KIND: Str = "serverless: unknown trigger kind";
const _E_ENABLED: Str = "serverless: enabled must be 0 or 1";
const _E_UNKNOWN_TRIG: Str = "serverless: unknown trigger id";
const _E_TRIG_DISABLED: Str = "serverless: trigger is disabled";
const _E_TRIG_ENABLED: Str = "serverless: trigger is already enabled";
const _E_TRIG_DISABLED_ALREADY: Str = "serverless: trigger is already disabled";
const _E_INV_ID: Str = "serverless: invocation id must be >= 0";
const _E_DUP_INV: Str = "serverless: duplicate invocation id";
const _E_UNKNOWN_INV: Str = "serverless: unknown invocation id";
const _E_INV_DONE: Str = "serverless: invocation already complete";
const _E_INV_FAILED: Str = "serverless: invocation already failed";
const _E_INV_NOT_RUNNING: Str = "serverless: invocation is not running";
const _E_TIMEOUT: Str = "serverless: invocation timed out";
const _E_HANDLER_FAILED: Str = "serverless: handler failed";
const _E_ELAPSED: Str = "serverless: elapsed_ms must be >= 0";
const _E_NO_QUEUED: Str = "serverless: no queued invocations";
const _E_CONCURRENCY: Str = "serverless: concurrency limit reached";
const _E_MAXSTEPS: Str = "serverless: max_steps must be >= 0";
const _E_STEP_LIMIT: Str = "serverless: step limit exceeded";
const _E_INST_ID: Str = "serverless: instance id must be >= 0";
const _E_DUP_INST: Str = "serverless: duplicate instance id";
const _E_UNKNOWN_INST: Str = "serverless: unknown instance id";
const _E_INST_WARM: Str = "serverless: instance already warm";
const _E_INST_BUSY: Str = "serverless: instance is busy";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

fn empty_sys(maxc: Int, boot: Int) -> ServerlessSystem {
  return ServerlessSystem{
    function_ids: Vec[Int].new();
    function_states: Vec[Int].new();
    function_versions: Vec[Int].new();
    function_handlers: Vec[Int].new();
    function_memory_mb: Vec[Int].new();
    function_timeout_ms: Vec[Int].new();
    trigger_ids: Vec[Int].new();
    trigger_functions: Vec[Int].new();
    trigger_kinds: Vec[Int].new();
    trigger_enabled: Vec[Int].new();
    trigger_fires: Vec[Int].new();
    deploy_ids: Vec[Int].new();
    deploy_functions: Vec[Int].new();
    deploy_states: Vec[Int].new();
    deploy_versions: Vec[Int].new();
    deploy_steps_total: Vec[Int].new();
    deploy_steps_done: Vec[Int].new();
    deploy_codes: Vec[Int].new();
    deploy_prev_versions: Vec[Int].new();
    invocation_ids: Vec[Int].new();
    invocation_functions: Vec[Int].new();
    invocation_states: Vec[Int].new();
    invocation_payloads: Vec[Int].new();
    invocation_outputs: Vec[Int].new();
    invocation_codes: Vec[Int].new();
    invocation_instances: Vec[Int].new();
    invocation_colds: Vec[Int].new();
    queue: Vec[Int].new();
    instance_ids: Vec[Int].new();
    instance_functions: Vec[Int].new();
    instance_states: Vec[Int].new();
    instance_served: Vec[Int].new();
    boot_ms: boot;
    max_concurrency: maxc;
    next_instance_id: 0;
    running: 0;
    completed: 0;
    failed: 0;
    timed_out: 0;
    aborted: 0;
    cold_starts: 0;
    cold_start_ms: 0;
    cold_invocations: 0;
    warm_invocations: 0;
    completion_order: Vec[Int].new();
  };
}

fn sys_of(maxc: Int, boot: Int) -> ServerlessSystem {
  match serverless_new(maxc, boot) {
    Ok(s) => { return s; },
    Err(_) => { return empty_sys(maxc, boot); },
  }
  return empty_sys(maxc, boot);
}

fn new_err_is(maxc: Int, boot: Int, want: Str) -> Bool {
  match serverless_new(maxc, boot) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Read-only accessor wrappers (advisory E001)
// ---------------------------------------------------------------------------

fn maxc_of(s: &mut ServerlessSystem) -> Int { return serverless_max_concurrency(s); }
fn queued_of(s: &mut ServerlessSystem) -> Int { return serverless_queued(s); }
fn running_of(s: &mut ServerlessSystem) -> Int { return serverless_running(s); }
fn completed_of(s: &mut ServerlessSystem) -> Int { return serverless_completed(s); }
fn failed_of(s: &mut ServerlessSystem) -> Int { return serverless_failed(s); }
fn timedout_of(s: &mut ServerlessSystem) -> Int { return serverless_timed_out(s); }
fn aborted_of(s: &mut ServerlessSystem) -> Int { return serverless_aborted(s); }
fn cold_starts_of(s: &mut ServerlessSystem) -> Int { return serverless_cold_starts(s); }
fn cold_ms_of(s: &mut ServerlessSystem) -> Int { return serverless_cold_start_ms(s); }
fn cold_inv_of(s: &mut ServerlessSystem) -> Int { return serverless_cold_invocations(s); }
fn warm_inv_of(s: &mut ServerlessSystem) -> Int { return serverless_warm_invocations(s); }
fn inv_ok(s: &mut ServerlessSystem) -> Bool { return serverless_check_invariant(s); }

fn fc_of(s: &mut ServerlessSystem) -> Int { return function_count(s); }
fn fst_of(s: &mut ServerlessSystem, id: Int) -> Int { return function_state(s, id); }
fn fver_of(s: &mut ServerlessSystem, id: Int) -> Int { return function_version(s, id); }
fn fhd_of(s: &mut ServerlessSystem, id: Int) -> Int { return function_handler(s, id); }
fn fmem_of(s: &mut ServerlessSystem, id: Int) -> Int { return function_memory_mb(s, id); }
fn ftmo_of(s: &mut ServerlessSystem, id: Int) -> Int { return function_timeout_ms(s, id); }

fn tc_of(s: &mut ServerlessSystem) -> Int { return trigger_count(s); }
fn tk_of(s: &mut ServerlessSystem, id: Int) -> Int { return trigger_kind(s, id); }
fn ten_of(s: &mut ServerlessSystem, id: Int) -> Bool { return trigger_is_enabled(s, id); }
fn tfr_of(s: &mut ServerlessSystem, id: Int) -> Int { return trigger_fires(s, id); }

fn dc_of(s: &mut ServerlessSystem) -> Int { return deploy_count(s); }
fn dst_of(s: &mut ServerlessSystem, id: Int) -> Int { return deploy_state(s, id); }
fn ddn_of(s: &mut ServerlessSystem, id: Int) -> Int { return deploy_steps_done(s, id); }
fn dtot_of(s: &mut ServerlessSystem, id: Int) -> Int { return deploy_steps_total(s, id); }
fn dcd_of(s: &mut ServerlessSystem, id: Int) -> Int { return deploy_code(s, id); }

fn ic_of(s: &mut ServerlessSystem) -> Int { return invocation_count(s); }
fn ist_of(s: &mut ServerlessSystem, id: Int) -> Int { return invocation_state(s, id); }
fn ipay_of(s: &mut ServerlessSystem, id: Int) -> Int { return invocation_payload(s, id); }
fn iout_of(s: &mut ServerlessSystem, id: Int) -> Int { return invocation_output(s, id); }
fn icd_of(s: &mut ServerlessSystem, id: Int) -> Int { return invocation_code(s, id); }
fn iinst_of(s: &mut ServerlessSystem, id: Int) -> Int { return invocation_instance(s, id); }
fn itrlen_of(s: &mut ServerlessSystem) -> Int { return invocation_trace_len(s); }
fn itrtxt_of(s: &mut ServerlessSystem) -> Str { return invocation_trace_text(s); }

fn rc_of(s: &mut ServerlessSystem) -> Int { return runtime_count(s); }
fn rst_of(s: &mut ServerlessSystem, id: Int) -> Int { return runtime_state(s, id); }
fn rsv_of(s: &mut ServerlessSystem, id: Int) -> Int { return runtime_served(s, id); }

// ---------------------------------------------------------------------------
// Outcome classifiers
// ---------------------------------------------------------------------------

fn fn_new_ok(s: &mut ServerlessSystem, id: Int, h: Int, mem: Int, tmo: Int) -> Int {
  match function_new(s, id, h, mem, tmo) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn fn_new_err_is(s: &mut ServerlessSystem, id: Int, h: Int, mem: Int, tmo: Int, want: Str) -> Bool {
  match function_new(s, id, h, mem, tmo) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn fn_dis_ok(s: &mut ServerlessSystem, id: Int) -> Int {
  match function_disable(s, id) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn fn_dis_err_is(s: &mut ServerlessSystem, id: Int, want: Str) -> Bool {
  match function_disable(s, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn fn_ena_ok(s: &mut ServerlessSystem, id: Int) -> Int {
  match function_enable(s, id) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn fn_ena_err_is(s: &mut ServerlessSystem, id: Int, want: Str) -> Bool {
  match function_enable(s, id) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn dep_begin_ok(s: &mut ServerlessSystem, did: Int, fid: Int, ver: Int, steps: Int) -> Int {
  match deploy_begin(s, did, fid, ver, steps) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn dep_begin_err_is(s: &mut ServerlessSystem, did: Int, fid: Int, ver: Int, steps: Int, want: Str) -> Bool {
  match deploy_begin(s, did, fid, ver, steps) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn dep_step_ok(s: &mut ServerlessSystem, did: Int) -> Int {
  match deploy_step(s, did) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn dep_step_err_is(s: &mut ServerlessSystem, did: Int, want: Str) -> Bool {
  match deploy_step(s, did) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn dep_fail_ok(s: &mut ServerlessSystem, did: Int, code: Int) -> Int {
  match deploy_fail(s, did, code) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn dep_fail_err_is(s: &mut ServerlessSystem, did: Int, code: Int, want: Str) -> Bool {
  match deploy_fail(s, did, code) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn dep_rb_ok(s: &mut ServerlessSystem, did: Int) -> Int {
  match deploy_rollback(s, did) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn dep_rb_err_is(s: &mut ServerlessSystem, did: Int, want: Str) -> Bool {
  match deploy_rollback(s, did) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn trg_new_ok(s: &mut ServerlessSystem, tid: Int, fid: Int, kind: Int, en: Int) -> Int {
  match trigger_new(s, tid, fid, kind, en) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn trg_new_err_is(s: &mut ServerlessSystem, tid: Int, fid: Int, kind: Int, en: Int, want: Str) -> Bool {
  match trigger_new(s, tid, fid, kind, en) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn trg_ena_ok(s: &mut ServerlessSystem, tid: Int) -> Int {
  match trigger_enable(s, tid) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn trg_ena_err_is(s: &mut ServerlessSystem, tid: Int, want: Str) -> Bool {
  match trigger_enable(s, tid) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn trg_dis_ok(s: &mut ServerlessSystem, tid: Int) -> Int {
  match trigger_disable(s, tid) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn trg_dis_err_is(s: &mut ServerlessSystem, tid: Int, want: Str) -> Bool {
  match trigger_disable(s, tid) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn trg_fire_ok(s: &mut ServerlessSystem, tid: Int, iid: Int, payload: Int) -> Int {
  match trigger_fire(s, tid, iid, payload) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn trg_fire_err_is(s: &mut ServerlessSystem, tid: Int, iid: Int, payload: Int, want: Str) -> Bool {
  match trigger_fire(s, tid, iid, payload) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn inv_sync_ok(s: &mut ServerlessSystem, iid: Int, fid: Int, payload: Int, elapsed: Int) -> Int {
  match invoke_sync(s, iid, fid, payload, elapsed) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn inv_sync_err_is(s: &mut ServerlessSystem, iid: Int, fid: Int, payload: Int, elapsed: Int, want: Str) -> Bool {
  match invoke_sync(s, iid, fid, payload, elapsed) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn inv_async_ok(s: &mut ServerlessSystem, iid: Int, fid: Int, payload: Int) -> Int {
  match invoke_async(s, iid, fid, payload) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn inv_async_err_is(s: &mut ServerlessSystem, iid: Int, fid: Int, payload: Int, want: Str) -> Bool {
  match invoke_async(s, iid, fid, payload) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn inv_disp_ok(s: &mut ServerlessSystem) -> Int {
  match invoke_dispatch(s) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn inv_disp_err_is(s: &mut ServerlessSystem, want: Str) -> Bool {
  match invoke_dispatch(s) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn inv_finish_ok(s: &mut ServerlessSystem, iid: Int, elapsed: Int) -> Int {
  match invoke_finish(s, iid, elapsed) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn inv_finish_err_is(s: &mut ServerlessSystem, iid: Int, elapsed: Int, want: Str) -> Bool {
  match invoke_finish(s, iid, elapsed) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn run_all_len(s: &mut ServerlessSystem, max_steps: Int, elapsed: Int) -> Int {
  match invoke_run_all(s, max_steps, elapsed) {
    Ok(tr) => { return tr.len(); },
    Err(_) => { return -1; },
  }
  return -1;
}

fn run_all_err_is(s: &mut ServerlessSystem, max_steps: Int, elapsed: Int, want: Str) -> Bool {
  match invoke_run_all(s, max_steps, elapsed) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn rt_alloc_ok(s: &mut ServerlessSystem, iid: Int, fid: Int) -> Int {
  match runtime_alloc(s, iid, fid) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn rt_alloc_err_is(s: &mut ServerlessSystem, iid: Int, fid: Int, want: Str) -> Bool {
  match runtime_alloc(s, iid, fid) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

fn rt_init_ok(s: &mut ServerlessSystem, iid: Int) -> Int {
  match runtime_init(s, iid) {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn rt_init_err_is(s: &mut ServerlessSystem, iid: Int, want: Str) -> Bool {
  match runtime_init(s, iid) {
    Ok(_) => { return false; },
    Err(m) => { return streq(m, want); },
  }
  return false;
}

// Activate function `id` with a one-step v1 rollout. Returns false when any
// step of the fixture setup fails.
fn activate(s: &mut ServerlessSystem, id: Int, h: Int, mem: Int, tmo: Int) -> Bool {
  if fn_new_ok(s, id, h, mem, tmo) != id { return false; }
  let did = 1000 + id;
  if dep_begin_ok(s, did, id, 1, 1) != did { return false; }
  if dep_step_ok(s, did) != 1 { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = new_err_is(0, 10, _E_MAXC);
  if !new_err_is(-1, 10, _E_MAXC) { ok = false; }
  if !new_err_is(1, -1, _E_BOOT) { ok = false; }
  var s = sys_of(3, 20);
  if maxc_of(&mut s) != 3 { ok = false; }
  if fc_of(&mut s) != 0 { ok = false; }
  if tc_of(&mut s) != 0 { ok = false; }
  if dc_of(&mut s) != 0 { ok = false; }
  if ic_of(&mut s) != 0 { ok = false; }
  if rc_of(&mut s) != 0 { ok = false; }
  if queued_of(&mut s) != 0 { ok = false; }
  if running_of(&mut s) != 0 { ok = false; }
  if completed_of(&mut s) != 0 { ok = false; }
  if failed_of(&mut s) != 0 { ok = false; }
  if timedout_of(&mut s) != 0 { ok = false; }
  if aborted_of(&mut s) != 0 { ok = false; }
  if cold_starts_of(&mut s) != 0 { ok = false; }
  if cold_ms_of(&mut s) != 0 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "serverless_new validates config and initializes empty state");
}

fn t2() -> TestResult {
  var s = sys_of(2, 5);
  var ok = fn_new_err_is(&mut s, -1, SV_HANDLER_ECHO, 128, 1000, _E_FN_ID);
  if !fn_new_err_is(&mut s, 1, 9, 128, 1000, _E_HANDLER_UNKNOWN) { ok = false; }
  if !fn_new_err_is(&mut s, 1, SV_HANDLER_ECHO, 0, 1000, _E_MEM) { ok = false; }
  if !fn_new_err_is(&mut s, 1, SV_HANDLER_ECHO, 128, 0, _E_TMO_DEF) { ok = false; }
  if fn_new_ok(&mut s, 1, SV_HANDLER_DOUBLE, 256, 500) != 1 { ok = false; }
  if !fn_new_err_is(&mut s, 1, SV_HANDLER_ECHO, 128, 1000, _E_DUP_FN) { ok = false; }
  if fc_of(&mut s) != 1 { ok = false; }
  if fst_of(&mut s, 1) != SV_FN_DRAFT { ok = false; }
  if fver_of(&mut s, 1) != 0 { ok = false; }
  if fhd_of(&mut s, 1) != SV_HANDLER_DOUBLE { ok = false; }
  if fmem_of(&mut s, 1) != 256 { ok = false; }
  if ftmo_of(&mut s, 1) != 500 { ok = false; }
  if fst_of(&mut s, 99) != SV_NOT_FOUND { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "function_new validates metadata and starts DRAFT v0");
}

fn t3() -> TestResult {
  var s = sys_of(2, 5);
  var ok = fn_dis_err_is(&mut s, 9, _E_UNKNOWN_FN);
  if fn_new_ok(&mut s, 1, SV_HANDLER_ECHO, 128, 100) != 1 { ok = false; }
  if !fn_dis_err_is(&mut s, 1, _E_FN_INACTIVE) { ok = false; }
  if !fn_ena_err_is(&mut s, 1, _E_NO_DEPLOY) { ok = false; }
  if dep_begin_ok(&mut s, 101, 1, 1, 1) != 101 { ok = false; }
  if dep_step_ok(&mut s, 101) != 1 { ok = false; }
  if fst_of(&mut s, 1) != SV_FN_ACTIVE { ok = false; }
  if fver_of(&mut s, 1) != 1 { ok = false; }
  if !fn_ena_err_is(&mut s, 1, _E_FN_ACTIVE) { ok = false; }
  if fn_dis_ok(&mut s, 1) != 1 { ok = false; }
  if fst_of(&mut s, 1) != SV_FN_DISABLED { ok = false; }
  if !fn_dis_err_is(&mut s, 1, _E_FN_DISABLED) { ok = false; }
  if fn_ena_ok(&mut s, 1) != 1 { ok = false; }
  if fst_of(&mut s, 1) != SV_FN_ACTIVE { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "function_disable/enable drive the ACTIVE <-> DISABLED lifecycle");
}

fn t4() -> TestResult {
  var s = sys_of(2, 5);
  if fn_new_ok(&mut s, 1, SV_HANDLER_ECHO, 128, 100) != 1 { return assert(false, "fixture failed"); }
  var ok = dep_begin_err_is(&mut s, -1, 1, 1, 1, _E_DEPLOY_ID);
  if dep_begin_ok(&mut s, 7, 1, 1, 2) != 7 { ok = false; }
  if !dep_begin_err_is(&mut s, 7, 1, 1, 2, _E_DUP_DEPLOY) { ok = false; }
  if !dep_begin_err_is(&mut s, 8, 9, 1, 2, _E_UNKNOWN_FN) { ok = false; }
  if !dep_begin_err_is(&mut s, 8, 1, 1, 0, _E_STEPS) { ok = false; }
  if !dep_begin_err_is(&mut s, 8, 1, 2, 2, _E_VERSION) { ok = false; }
  if dst_of(&mut s, 7) != SV_DEPLOY_PENDING { ok = false; }
  if ddn_of(&mut s, 7) != 0 { ok = false; }
  if dtot_of(&mut s, 7) != 2 { ok = false; }
  if dc_of(&mut s) != 1 { ok = false; }
  if dst_of(&mut s, 99) != SV_NOT_FOUND { ok = false; }
  if fn_new_ok(&mut s, 2, SV_HANDLER_ECHO, 128, 100) != 2 { ok = false; }
  if dep_begin_ok(&mut s, 20, 2, 1, 1) != 20 { ok = false; }
  if dep_step_ok(&mut s, 20) != 1 { ok = false; }
  if fn_dis_ok(&mut s, 2) != 2 { ok = false; }
  if !dep_begin_err_is(&mut s, 21, 2, 2, 1, _E_FN_IS_DISABLED) { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "deploy_begin validates ids, function, steps and version");
}

fn t5() -> TestResult {
  var s = sys_of(2, 5);
  if fn_new_ok(&mut s, 1, SV_HANDLER_ECHO, 128, 100) != 1 { return assert(false, "fixture failed"); }
  if dep_begin_ok(&mut s, 5, 1, 1, 3) != 5 { return assert(false, "fixture failed"); }
  var ok = dep_step_ok(&mut s, 5) == 1;
  if dst_of(&mut s, 5) != SV_DEPLOY_IN_PROGRESS { ok = false; }
  if dep_step_ok(&mut s, 5) != 2 { ok = false; }
  if dep_step_ok(&mut s, 5) != 3 { ok = false; }
  if dst_of(&mut s, 5) != SV_DEPLOY_READY { ok = false; }
  if fst_of(&mut s, 1) != SV_FN_ACTIVE { ok = false; }
  if fver_of(&mut s, 1) != 1 { ok = false; }
  if ddn_of(&mut s, 5) != 3 { ok = false; }
  if dtot_of(&mut s, 5) != 3 { ok = false; }
  if !dep_step_err_is(&mut s, 5, _E_DEPLOY_READY) { ok = false; }
  if !dep_step_err_is(&mut s, 6, _E_UNKNOWN_DEPLOY) { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "deploy_step progresses to READY and activates the version");
}

fn t6() -> TestResult {
  var s = sys_of(2, 5);
  if fn_new_ok(&mut s, 1, SV_HANDLER_ECHO, 128, 100) != 1 { return assert(false, "fixture failed"); }
  if dep_begin_ok(&mut s, 5, 1, 1, 2) != 5 { return assert(false, "fixture failed"); }
  if dep_step_ok(&mut s, 5) != 1 { return assert(false, "fixture failed"); }
  var ok = dep_fail_err_is(&mut s, 5, 0, _E_FAIL_CODE);
  if dep_fail_ok(&mut s, 5, 7) != 7 { ok = false; }
  if dst_of(&mut s, 5) != SV_DEPLOY_FAILED { ok = false; }
  if dcd_of(&mut s, 5) != 7 { ok = false; }
  if !dep_fail_err_is(&mut s, 5, 9, _E_DEPLOY_FAILED) { ok = false; }
  if !dep_step_err_is(&mut s, 5, _E_DEPLOY_FAILED) { ok = false; }
  if dep_rb_ok(&mut s, 5) != 5 { ok = false; }
  if dst_of(&mut s, 5) != SV_DEPLOY_ROLLED_BACK { ok = false; }
  if !dep_rb_err_is(&mut s, 5, _E_DEPLOY_ROLLED) { ok = false; }
  if fst_of(&mut s, 1) != SV_FN_DRAFT { ok = false; }
  if fver_of(&mut s, 1) != 0 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "deploy_fail and rollback seal a failed rollout");
}

fn t7() -> TestResult {
  var s = sys_of(2, 5);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  if dep_begin_ok(&mut s, 6, 1, 2, 1) != 6 { return assert(false, "fixture failed"); }
  if dep_step_ok(&mut s, 6) != 1 { return assert(false, "fixture failed"); }
  var ok = fver_of(&mut s, 1) == 2;
  if dep_begin_ok(&mut s, 8, 1, 3, 1) != 8 { ok = false; }
  if !dep_rb_err_is(&mut s, 8, _E_NOT_ROLLBACKABLE) { ok = false; }
  if dep_rb_ok(&mut s, 6) != 6 { ok = false; }
  if fver_of(&mut s, 1) != 1 { ok = false; }
  if fst_of(&mut s, 1) != SV_FN_ACTIVE { ok = false; }
  if dep_begin_ok(&mut s, 9, 1, 2, 1) != 9 { ok = false; }
  if dep_step_ok(&mut s, 9) != 1 { ok = false; }
  if fver_of(&mut s, 1) != 2 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "rollback of READY restores the previous version and keeps vN+1 deployable");
}

fn t8() -> TestResult {
  var s = sys_of(2, 5);
  if fn_new_ok(&mut s, 1, SV_HANDLER_ECHO, 128, 100) != 1 { return assert(false, "fixture failed"); }
  var ok = trg_new_err_is(&mut s, -1, 1, SV_TRIGGER_TIMER, 1, _E_TRIG_ID);
  if !trg_new_err_is(&mut s, 1, 9, SV_TRIGGER_TIMER, 1, _E_UNKNOWN_FN) { ok = false; }
  if !trg_new_err_is(&mut s, 1, 1, 9, 1, _E_TRIG_KIND) { ok = false; }
  if !trg_new_err_is(&mut s, 1, 1, SV_TRIGGER_TIMER, 2, _E_ENABLED) { ok = false; }
  if trg_new_ok(&mut s, 1, 1, SV_TRIGGER_HTTP, 1) != 1 { ok = false; }
  if !trg_new_err_is(&mut s, 1, 1, SV_TRIGGER_TIMER, 1, _E_DUP_TRIG) { ok = false; }
  if tc_of(&mut s) != 1 { ok = false; }
  if tk_of(&mut s, 1) != SV_TRIGGER_HTTP { ok = false; }
  if !ten_of(&mut s, 1) { ok = false; }
  if tfr_of(&mut s, 1) != 0 { ok = false; }
  if tk_of(&mut s, 99) != SV_NOT_FOUND { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "trigger_new validates wiring and stores kind/enabled/fires");
}

fn t9() -> TestResult {
  var s = sys_of(2, 5);
  if fn_new_ok(&mut s, 1, SV_HANDLER_ECHO, 128, 100) != 1 { return assert(false, "fixture failed"); }
  if trg_new_ok(&mut s, 1, 1, SV_TRIGGER_QUEUE, 0) != 1 { return assert(false, "fixture failed"); }
  var ok = trg_ena_err_is(&mut s, 9, _E_UNKNOWN_TRIG);
  if !trg_dis_err_is(&mut s, 1, _E_TRIG_DISABLED_ALREADY) { ok = false; }
  if trg_ena_ok(&mut s, 1) != 1 { ok = false; }
  if !ten_of(&mut s, 1) { ok = false; }
  if !trg_ena_err_is(&mut s, 1, _E_TRIG_ENABLED) { ok = false; }
  if trg_dis_ok(&mut s, 1) != 1 { ok = false; }
  if ten_of(&mut s, 1) { ok = false; }
  if tfr_of(&mut s, 1) != 0 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "trigger enable/disable validate the flag lifecycle");
}

fn t10() -> TestResult {
  var s = sys_of(2, 5);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  if trg_new_ok(&mut s, 1, 1, SV_TRIGGER_TIMER, 1) != 1 { return assert(false, "fixture failed"); }
  var ok = trg_fire_err_is(&mut s, 9, 1, 5, _E_UNKNOWN_TRIG);
  if trg_fire_ok(&mut s, 1, 10, 5) != 10 { ok = false; }
  if ist_of(&mut s, 10) != SV_INV_QUEUED { ok = false; }
  if ipay_of(&mut s, 10) != 5 { ok = false; }
  if queued_of(&mut s) != 1 { ok = false; }
  if tfr_of(&mut s, 1) != 1 { ok = false; }
  if !trg_fire_err_is(&mut s, 1, 10, 6, _E_DUP_INV) { ok = false; }
  if trg_fire_ok(&mut s, 1, 11, 6) != 11 { ok = false; }
  if queued_of(&mut s) != 2 { ok = false; }
  if tfr_of(&mut s, 1) != 2 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "trigger_fire enqueues invocations and counts fires");
}

fn t11() -> TestResult {
  var s = sys_of(2, 5);
  if fn_new_ok(&mut s, 1, SV_HANDLER_ECHO, 128, 100) != 1 { return assert(false, "fixture failed"); }
  if trg_new_ok(&mut s, 1, 1, SV_TRIGGER_TIMER, 1) != 1 { return assert(false, "fixture failed"); }
  var ok = trg_fire_err_is(&mut s, 1, 5, 1, _E_FN_INACTIVE);
  if dep_begin_ok(&mut s, 1001, 1, 1, 1) != 1001 { ok = false; }
  if dep_step_ok(&mut s, 1001) != 1 { ok = false; }
  if trg_new_ok(&mut s, 2, 1, SV_TRIGGER_HTTP, 0) != 2 { ok = false; }
  if !trg_fire_err_is(&mut s, 2, 6, 1, _E_TRIG_DISABLED) { ok = false; }
  if fn_dis_ok(&mut s, 1) != 1 { ok = false; }
  if !trg_fire_err_is(&mut s, 1, 7, 1, _E_FN_INACTIVE) { ok = false; }
  if queued_of(&mut s) != 0 { ok = false; }
  if tfr_of(&mut s, 1) != 0 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "trigger_fire refuses disabled triggers and inactive functions");
}

fn t12() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  if fn_new_ok(&mut s, 2, SV_HANDLER_ECHO, 128, 100) != 2 { return assert(false, "fixture failed"); }
  if fn_new_ok(&mut s, 3, SV_HANDLER_DOUBLE, 128, 100) != 3 { return assert(false, "fixture failed"); }
  if dep_begin_ok(&mut s, 103, 3, 1, 1) != 103 { return assert(false, "fixture failed"); }
  if dep_step_ok(&mut s, 103) != 1 { return assert(false, "fixture failed"); }
  var ok = inv_sync_ok(&mut s, 1, 1, 21, 5) == 21;
  if iout_of(&mut s, 1) != 21 { ok = false; }
  if icd_of(&mut s, 1) != SV_CODE_OK { ok = false; }
  if ist_of(&mut s, 1) != SV_INV_DONE { ok = false; }
  if completed_of(&mut s) != 1 { ok = false; }
  if cold_inv_of(&mut s) != 1 { ok = false; }
  if warm_inv_of(&mut s) != 0 { ok = false; }
  if cold_starts_of(&mut s) != 1 { ok = false; }
  if cold_ms_of(&mut s) != 10 { ok = false; }
  if inv_sync_ok(&mut s, 2, 1, 7, 6) != 7 { ok = false; }
  if warm_inv_of(&mut s) != 1 { ok = false; }
  if cold_starts_of(&mut s) != 1 { ok = false; }
  if rsv_of(&mut s, 0) != 2 { ok = false; }
  if iinst_of(&mut s, 1) != 0 { ok = false; }
  if iinst_of(&mut s, 1) != iinst_of(&mut s, 2) { ok = false; }
  if inv_sync_ok(&mut s, 3, 3, 21, 5) != 42 { ok = false; }
  if !inv_sync_err_is(&mut s, -1, 1, 0, 0, _E_INV_ID) { ok = false; }
  if !inv_sync_err_is(&mut s, 1, 1, 0, 0, _E_DUP_INV) { ok = false; }
  if !inv_sync_err_is(&mut s, 4, 9, 0, 0, _E_UNKNOWN_FN) { ok = false; }
  if !inv_sync_err_is(&mut s, 4, 2, 0, 0, _E_FN_INACTIVE) { ok = false; }
  if !inv_sync_err_is(&mut s, 4, 1, 0, -1, _E_ELAPSED) { ok = false; }
  if ipay_of(&mut s, 1) != 21 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "invoke_sync evaluates handlers, validates and reuses warm instances");
}

fn t13() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  var ok = inv_sync_ok(&mut s, 1, 1, 5, 100) == 5;
  if !inv_sync_err_is(&mut s, 2, 1, 5, 101, _E_TIMEOUT) { ok = false; }
  if ist_of(&mut s, 2) != SV_INV_FAILED { ok = false; }
  if icd_of(&mut s, 2) != SV_CODE_TIMEOUT { ok = false; }
  if timedout_of(&mut s) != 1 { ok = false; }
  if failed_of(&mut s) != 1 { ok = false; }
  if completed_of(&mut s) != 1 { ok = false; }
  if iout_of(&mut s, 2) != 0 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "invoke_sync succeeds at the timeout boundary and fails past it");
}

fn t14() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_FAIL, 128, 100) { return assert(false, "fixture failed"); }
  var ok = inv_sync_err_is(&mut s, 1, 1, 5, 10, _E_HANDLER_FAILED);
  if icd_of(&mut s, 1) != SV_CODE_HANDLER { ok = false; }
  if failed_of(&mut s) != 1 { ok = false; }
  if timedout_of(&mut s) != 0 { ok = false; }
  if !inv_sync_err_is(&mut s, 2, 1, 5, 101, _E_TIMEOUT) { ok = false; }
  if icd_of(&mut s, 2) != SV_CODE_TIMEOUT { ok = false; }
  if timedout_of(&mut s) != 1 { ok = false; }
  if failed_of(&mut s) != 2 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "handler failure is reported with its code and timeout wins over it");
}

fn t15() -> TestResult {
  var s = sys_of(1, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  var ok = inv_async_ok(&mut s, 1, 1, 5) == 1;
  if inv_async_ok(&mut s, 2, 1, 6) != 2 { ok = false; }
  if queued_of(&mut s) != 2 { ok = false; }
  if running_of(&mut s) != 0 { ok = false; }
  if inv_disp_ok(&mut s) != 1 { ok = false; }
  if running_of(&mut s) != 1 { ok = false; }
  if ist_of(&mut s, 1) != SV_INV_RUNNING { ok = false; }
  if queued_of(&mut s) != 1 { ok = false; }
  if ist_of(&mut s, 2) != SV_INV_QUEUED { ok = false; }
  if !inv_disp_err_is(&mut s, _E_CONCURRENCY) { ok = false; }
  if inv_finish_ok(&mut s, 1, 3) != 5 { ok = false; }
  if running_of(&mut s) != 0 { ok = false; }
  if completed_of(&mut s) != 1 { ok = false; }
  if ist_of(&mut s, 1) != SV_INV_DONE { ok = false; }
  if inv_disp_ok(&mut s) != 2 { ok = false; }
  if inv_finish_ok(&mut s, 2, 4) != 6 { ok = false; }
  if completed_of(&mut s) != 2 { ok = false; }
  if !inv_disp_err_is(&mut s, _E_NO_QUEUED) { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "async dispatch enforces max_concurrency and the FIFO order");
}

fn t16() -> TestResult {
  var s = sys_of(2, 10);
  var ok = inv_disp_err_is(&mut s, _E_NO_QUEUED);
  if !inv_finish_err_is(&mut s, 99, 0, _E_UNKNOWN_INV) { ok = false; }
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 50) { ok = false; }
  if inv_async_ok(&mut s, 1, 1, 5) != 1 { ok = false; }
  if !inv_finish_err_is(&mut s, 1, 0, _E_INV_NOT_RUNNING) { ok = false; }
  if inv_disp_ok(&mut s) != 1 { ok = false; }
  if !inv_finish_err_is(&mut s, 1, -1, _E_ELAPSED) { ok = false; }
  if inv_finish_ok(&mut s, 1, 20) != 5 { ok = false; }
  if !inv_finish_err_is(&mut s, 1, 20, _E_INV_DONE) { ok = false; }
  if inv_async_ok(&mut s, 2, 1, 6) != 2 { ok = false; }
  if inv_disp_ok(&mut s) != 2 { ok = false; }
  if !inv_finish_err_is(&mut s, 2, 60, _E_TIMEOUT) { ok = false; }
  if ist_of(&mut s, 2) != SV_INV_FAILED { ok = false; }
  if !inv_finish_err_is(&mut s, 2, 0, _E_INV_FAILED) { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "dispatch/finish reject an invalid invocation lifecycle");
}

fn t17() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 50) { return assert(false, "fixture failed"); }
  var ok = rt_alloc_err_is(&mut s, -1, 1, _E_INST_ID);
  if !rt_alloc_err_is(&mut s, 1, 9, _E_UNKNOWN_FN) { ok = false; }
  if rt_alloc_ok(&mut s, 7, 1) != 7 { ok = false; }
  if !rt_alloc_err_is(&mut s, 7, 1, _E_DUP_INST) { ok = false; }
  if rst_of(&mut s, 7) != SV_RT_COLD { ok = false; }
  if rt_init_ok(&mut s, 7) != 1 { ok = false; }
  if rst_of(&mut s, 7) != SV_RT_WARM { ok = false; }
  if cold_starts_of(&mut s) != 1 { ok = false; }
  if cold_ms_of(&mut s) != 10 { ok = false; }
  if !rt_init_err_is(&mut s, 7, _E_INST_WARM) { ok = false; }
  if !rt_init_err_is(&mut s, 99, _E_UNKNOWN_INST) { ok = false; }
  if inv_async_ok(&mut s, 1, 1, 5) != 1 { ok = false; }
  if inv_disp_ok(&mut s) != 1 { ok = false; }
  if rst_of(&mut s, 7) != SV_RT_BUSY { ok = false; }
  if !rt_init_err_is(&mut s, 7, _E_INST_BUSY) { ok = false; }
  if inv_finish_ok(&mut s, 1, 5) != 5 { ok = false; }
  if rst_of(&mut s, 7) != SV_RT_WARM { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "runtime_alloc/runtime_init drive COLD -> WARM and reject busy re-init");
}

fn t18() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  if rt_alloc_ok(&mut s, 7, 1) != 7 { return assert(false, "fixture failed"); }
  if rt_init_ok(&mut s, 7) != 1 { return assert(false, "fixture failed"); }
  var ok = inv_sync_ok(&mut s, 1, 1, 3, 5) == 3;
  if warm_inv_of(&mut s) != 1 { ok = false; }
  if cold_starts_of(&mut s) != 1 { ok = false; }
  if rc_of(&mut s) != 1 { ok = false; }
  if rsv_of(&mut s, 7) != 1 { ok = false; }
  if rst_of(&mut s, 7) != SV_RT_WARM { ok = false; }
  if inv_sync_ok(&mut s, 2, 1, 4, 5) != 4 { ok = false; }
  if warm_inv_of(&mut s) != 2 { ok = false; }
  if rsv_of(&mut s, 7) != 2 { ok = false; }
  if !activate(&mut s, 2, SV_HANDLER_ECHO, 128, 100) { ok = false; }
  if inv_sync_ok(&mut s, 3, 2, 5, 5) != 5 { ok = false; }
  if cold_inv_of(&mut s) != 1 { ok = false; }
  if cold_starts_of(&mut s) != 2 { ok = false; }
  if cold_ms_of(&mut s) != 20 { ok = false; }
  if rc_of(&mut s) != 2 { ok = false; }
  if cold_inv_of(&mut s) + warm_inv_of(&mut s) != completed_of(&mut s) { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "cold/warm accounting follows instance reuse and fresh allocation");
}

fn t19() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  if inv_async_ok(&mut s, 1, 1, 10) != 1 { return assert(false, "fixture failed"); }
  if inv_async_ok(&mut s, 2, 1, 20) != 2 { return assert(false, "fixture failed"); }
  if inv_async_ok(&mut s, 3, 1, 30) != 3 { return assert(false, "fixture failed"); }
  var ok = run_all_len(&mut s, 10, 5) == 3;
  if completed_of(&mut s) != 3 { ok = false; }
  if queued_of(&mut s) != 0 { ok = false; }
  if itrlen_of(&mut s) != 3 { ok = false; }
  if !streq(itrtxt_of(&mut s), "1,2,3") { ok = false; }
  if !run_all_err_is(&mut s, -1, 5, _E_MAXSTEPS) { ok = false; }
  if !run_all_err_is(&mut s, 1, -1, _E_ELAPSED) { ok = false; }
  if run_all_len(&mut s, 0, 5) != 0 { ok = false; }
  if inv_async_ok(&mut s, 4, 1, 40) != 4 { ok = false; }
  if inv_async_ok(&mut s, 5, 1, 50) != 5 { ok = false; }
  if inv_async_ok(&mut s, 6, 1, 60) != 6 { ok = false; }
  if !run_all_err_is(&mut s, 2, 5, _E_STEP_LIMIT) { ok = false; }
  if completed_of(&mut s) != 5 { ok = false; }
  if queued_of(&mut s) != 1 { ok = false; }
  if run_all_len(&mut s, 1, 5) != 1 { ok = false; }
  if completed_of(&mut s) != 6 { ok = false; }
  if queued_of(&mut s) != 0 { ok = false; }
  if !streq(itrtxt_of(&mut s), "1,2,3,4,5,6") { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "run_all drains FIFO with a trace and enforces max_steps");
}

fn t20() -> TestResult {
  var s = sys_of(1, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  if inv_async_ok(&mut s, 1, 1, 5) != 1 { return assert(false, "fixture failed"); }
  if inv_async_ok(&mut s, 2, 1, 6) != 2 { return assert(false, "fixture failed"); }
  if fn_dis_ok(&mut s, 1) != 1 { return assert(false, "fixture failed"); }
  var ok = inv_disp_err_is(&mut s, _E_FN_INACTIVE);
  if ist_of(&mut s, 1) != SV_INV_FAILED { ok = false; }
  if icd_of(&mut s, 1) != SV_CODE_ABORTED { ok = false; }
  if queued_of(&mut s) != 1 { ok = false; }
  if failed_of(&mut s) != 1 { ok = false; }
  if aborted_of(&mut s) != 1 { ok = false; }
  if fn_ena_ok(&mut s, 1) != 1 { ok = false; }
  if inv_disp_ok(&mut s) != 2 { ok = false; }
  if inv_finish_ok(&mut s, 2, 5) != 6 { ok = false; }
  if queued_of(&mut s) != 0 { ok = false; }
  if completed_of(&mut s) != 1 { ok = false; }
  if failed_of(&mut s) != 1 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "dispatch after disable aborts the invocation with SV_CODE_ABORTED");
}

fn t21() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_DOUBLE, 128, 100) { return assert(false, "fixture failed"); }
  if trg_new_ok(&mut s, 1, 1, SV_TRIGGER_TIMER, 1) != 1 { return assert(false, "fixture failed"); }
  if trg_fire_ok(&mut s, 1, 7, 21) != 7 { return assert(false, "fixture failed"); }
  if trg_fire_ok(&mut s, 1, 8, 5) != 8 { return assert(false, "fixture failed"); }
  var ok = queued_of(&mut s) == 2;
  if run_all_len(&mut s, 10, 3) != 2 { ok = false; }
  if iout_of(&mut s, 7) != 42 { ok = false; }
  if iout_of(&mut s, 8) != 10 { ok = false; }
  if tfr_of(&mut s, 1) != 2 { ok = false; }
  if completed_of(&mut s) != 2 { ok = false; }
  if !streq(itrtxt_of(&mut s), "7,8") { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "trigger -> queue -> run_all integrates the full pipeline");
}

fn t22() -> TestResult {
  var s = sys_of(2, 10);
  if !activate(&mut s, 1, SV_HANDLER_ECHO, 128, 100) { return assert(false, "fixture failed"); }
  var ok = true;
  var i = 0;
  while i < 20 {
    if inv_async_ok(&mut s, 100 + i, 1, i) != 100 + i { ok = false; }
    if run_all_len(&mut s, 1, 1) != 1 { ok = false; }
    if !inv_ok(&mut s) { ok = false; }
    i = i + 1;
  }
  if completed_of(&mut s) != 20 { ok = false; }
  if cold_starts_of(&mut s) != 1 { ok = false; }
  if cold_inv_of(&mut s) != 1 { ok = false; }
  if warm_inv_of(&mut s) != 19 { ok = false; }
  if itrlen_of(&mut s) != 20 { ok = false; }
  if !inv_ok(&mut s) { ok = false; }
  return assert(ok, "invariant holds across 20 dispatch/finish cycles on one warm instance");
}

fn t23() -> TestResult {
  var ok = streq(serverless_handler_name(SV_HANDLER_ECHO), "echo");
  if !streq(serverless_handler_name(SV_HANDLER_DOUBLE), "double") { ok = false; }
  if !streq(serverless_handler_name(SV_HANDLER_FAIL), "fail") { ok = false; }
  if !streq(serverless_handler_name(9), "unknown") { ok = false; }
  if !streq(function_state_name(SV_FN_DRAFT), "draft") { ok = false; }
  if !streq(function_state_name(SV_FN_ACTIVE), "active") { ok = false; }
  if !streq(function_state_name(SV_FN_DISABLED), "disabled") { ok = false; }
  if !streq(deploy_state_name(SV_DEPLOY_PENDING), "pending") { ok = false; }
  if !streq(deploy_state_name(SV_DEPLOY_IN_PROGRESS), "in-progress") { ok = false; }
  if !streq(deploy_state_name(SV_DEPLOY_READY), "ready") { ok = false; }
  if !streq(deploy_state_name(SV_DEPLOY_FAILED), "failed") { ok = false; }
  if !streq(deploy_state_name(SV_DEPLOY_ROLLED_BACK), "rolled-back") { ok = false; }
  if !streq(invocation_state_name(SV_INV_QUEUED), "queued") { ok = false; }
  if !streq(invocation_state_name(SV_INV_RUNNING), "running") { ok = false; }
  if !streq(invocation_state_name(SV_INV_DONE), "done") { ok = false; }
  if !streq(invocation_state_name(SV_INV_FAILED), "failed") { ok = false; }
  if !streq(trigger_kind_name(SV_TRIGGER_TIMER), "timer") { ok = false; }
  if !streq(trigger_kind_name(SV_TRIGGER_HTTP), "http") { ok = false; }
  if !streq(trigger_kind_name(SV_TRIGGER_QUEUE), "queue") { ok = false; }
  if !streq(runtime_state_name(SV_RT_COLD), "cold") { ok = false; }
  if !streq(runtime_state_name(SV_RT_WARM), "warm") { ok = false; }
  if !streq(runtime_state_name(SV_RT_BUSY), "busy") { ok = false; }
  if !streq(function_state_name(7), "unknown") { ok = false; }
  if !streq(deploy_state_name(7), "unknown") { ok = false; }
  if !streq(invocation_state_name(7), "unknown") { ok = false; }
  if !streq(trigger_kind_name(7), "unknown") { ok = false; }
  if !streq(runtime_state_name(7), "unknown") { ok = false; }
  return assert(ok, "state and kind name helpers are stable");
}

fn main() -> Int {
  io.println("=== xiom.serverless conformance tests ===");
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
    io.println("xiom.serverless: all tests passed");
  } else {
    io.println("xiom.serverless: tests failed");
  }
  return failed;
}
