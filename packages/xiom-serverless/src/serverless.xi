// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.serverless: serverless compute abstractions as a pure,
// deterministic model. This is the core: the ServerlessSystem value,
// construction, functions and triggers. Sibling modules complete the model:
//   * xiom.serverless.deploy  -- the rollout state machine (PENDING ->
//     IN_PROGRESS -> READY, FAILED, ROLLED_BACK; READY activates the target
//     version; rollback restores the previous version and lifecycle);
//   * xiom.serverless.invoke  -- the execution plane (sync/async invocation,
//     the FIFO dispatch queue, runtime instances, cold-start accounting);
//   * xiom.serverless.check   -- the structural invariant over all tables.
// No networking, no threads, no clock, no FFI, no I/O: every function is a
// total transition over plain values and the caller (or a future backend)
// supplies time as `elapsed_ms`.
//
// The model owns five entity tables -- each a set of parallel Vec[Int] fields,
// never Vec[StructType] -- plus configuration and counters:
//   * functions: DRAFT -> ACTIVE <-> DISABLED lifecycle, monotonic versions,
//     handler code, memory and timeout metadata;
//   * triggers: event sources (timer / HTTP / queue) bound to a function, with
//     an enable flag and a fire counter; firing enqueues an invocation;
//   * invocations and runtime instances: owned by xiom.serverless.invoke, but
//     stored in the same ServerlessSystem value (see the type doc below).
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err constructed only
// inside _ok_*/_err_* leaf helpers; Vec[Int] element reads bound with typed
// `let`; no Vec[StructType], no Vec[Str], no indexed Vec[fn] dispatch (handler
// codes use explicit case dispatch), no generic callbacks, no Vec[Float64],
// no `mut` patterns, no `log`-named function, no FFI. Imports nothing.

module xiom.serverless

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Function lifecycle: defined but never deployed (version 0).
pub const SV_FN_DRAFT: Int = 0;
/// Function lifecycle: deployed and accepting invocations (version >= 1).
pub const SV_FN_ACTIVE: Int = 1;
/// Function lifecycle: deployed but refusing invocations.
pub const SV_FN_DISABLED: Int = 2;

/// Handler code: return the invocation payload unchanged.
pub const SV_HANDLER_ECHO: Int = 0;
/// Handler code: return the invocation payload doubled.
pub const SV_HANDLER_DOUBLE: Int = 1;
/// Handler code: always fail (deterministic fault injection).
pub const SV_HANDLER_FAIL: Int = 2;

/// Trigger kind: timer schedule.
pub const SV_TRIGGER_TIMER: Int = 0;
/// Trigger kind: inbound HTTP request.
pub const SV_TRIGGER_HTTP: Int = 1;
/// Trigger kind: queue message.
pub const SV_TRIGGER_QUEUE: Int = 2;

/// Deploy state: created, no rollout step executed yet.
pub const SV_DEPLOY_PENDING: Int = 0;
/// Deploy state: at least one rollout step executed.
pub const SV_DEPLOY_IN_PROGRESS: Int = 1;
/// Deploy state: all steps executed; the target version is live.
pub const SV_DEPLOY_READY: Int = 2;
/// Deploy state: rollout aborted with a failure code.
pub const SV_DEPLOY_FAILED: Int = 3;
/// Deploy state: terminal; the rollout was undone.
pub const SV_DEPLOY_ROLLED_BACK: Int = 4;

/// Invocation state: accepted, waiting in the async FIFO queue.
pub const SV_INV_QUEUED: Int = 0;
/// Invocation state: dispatched to a runtime instance.
pub const SV_INV_RUNNING: Int = 1;
/// Invocation state: finished successfully.
pub const SV_INV_DONE: Int = 2;
/// Invocation state: finished with a failure code.
pub const SV_INV_FAILED: Int = 3;

/// Invocation success code.
pub const SV_CODE_OK: Int = 0;
/// Invocation failure code: the handler reported a failure.
pub const SV_CODE_HANDLER: Int = 1;
/// Invocation failure code: elapsed time exceeded the function timeout.
pub const SV_CODE_TIMEOUT: Int = 2;
/// Invocation failure code: the function was not ACTIVE at dispatch.
pub const SV_CODE_ABORTED: Int = 3;

/// Runtime instance state: allocated, never initialized (cold).
pub const SV_RT_COLD: Int = 0;
/// Runtime instance state: initialized and idle (warm).
pub const SV_RT_WARM: Int = 1;
/// Runtime instance state: executing an invocation.
pub const SV_RT_BUSY: Int = 2;

/// Sentinel: unknown id / out of range accessor result.
pub const SV_NOT_FOUND: Int = -1;
/// Sentinel: a runtime instance slot that is not attached.
pub const SV_NO_INSTANCE: Int = -1;

// Private table selectors for the shared index/duplicate helpers.
const _TBL_FN: Int = 0;
const _TBL_TRIGGER: Int = 1;
const _TBL_DEPLOY: Int = 2;
const _TBL_INVOCATION: Int = 3;
const _TBL_INSTANCE: Int = 4;

/// Complete serverless system state. Every field is an internal
/// implementation detail; callers must go through the free functions of
/// xiom.serverless (control plane) and xiom.serverless.invoke (execution).
///
/// Entity tables are parallel Vec[Int] fields indexed by slot:
///   functions:   function_ids (unique, >= 0), function_states (SV_FN_*),
///                function_versions (>= 0), function_handlers (SV_HANDLER_*),
///                function_memory_mb (>= 1), function_timeout_ms (>= 1);
///   triggers:    trigger_ids (unique), trigger_functions, trigger_kinds
///                (SV_TRIGGER_*), trigger_enabled (0/1), trigger_fires;
///   deploys:     deploy_ids (unique), deploy_functions, deploy_states
///                (SV_DEPLOY_*), deploy_versions (>= 1), deploy_steps_total
///                (>= 1), deploy_steps_done, deploy_codes,
///                deploy_prev_versions (the function version before READY);
///   invocations: invocation_ids (unique), invocation_functions,
///                invocation_states (SV_INV_*), invocation_payloads,
///                invocation_outputs, invocation_codes, invocation_instances,
///                invocation_colds (1 = the run paid a cold start);
///   instances:   instance_ids (unique), instance_functions, instance_states
///                (SV_RT_*), instance_served (invocations served);
/// plus the FIFO `queue` of QUEUED invocation ids, the `completion_order`
/// trace of terminal invocation ids, the auto-allocation cursor
/// `next_instance_id`, the `boot_ms` cold-start cost, the `max_concurrency`
/// async cap, the `running` gauge and the accounting counters (completed,
/// failed, timed_out, aborted, cold_starts, cold_start_ms, cold_invocations,
/// warm_invocations).
pub type ServerlessSystem = {
  function_ids: Vec[Int];
  function_states: Vec[Int];
  function_versions: Vec[Int];
  function_handlers: Vec[Int];
  function_memory_mb: Vec[Int];
  function_timeout_ms: Vec[Int];
  trigger_ids: Vec[Int];
  trigger_functions: Vec[Int];
  trigger_kinds: Vec[Int];
  trigger_enabled: Vec[Int];
  trigger_fires: Vec[Int];
  deploy_ids: Vec[Int];
  deploy_functions: Vec[Int];
  deploy_states: Vec[Int];
  deploy_versions: Vec[Int];
  deploy_steps_total: Vec[Int];
  deploy_steps_done: Vec[Int];
  deploy_codes: Vec[Int];
  deploy_prev_versions: Vec[Int];
  invocation_ids: Vec[Int];
  invocation_functions: Vec[Int];
  invocation_states: Vec[Int];
  invocation_payloads: Vec[Int];
  invocation_outputs: Vec[Int];
  invocation_codes: Vec[Int];
  invocation_instances: Vec[Int];
  invocation_colds: Vec[Int];
  queue: Vec[Int];
  instance_ids: Vec[Int];
  instance_functions: Vec[Int];
  instance_states: Vec[Int];
  instance_served: Vec[Int];
  boot_ms: Int;
  max_concurrency: Int;
  next_instance_id: Int;
  running: Int;
  completed: Int;
  failed: Int;
  timed_out: Int;
  aborted: Int;
  cold_starts: Int;
  cold_start_ms: Int;
  cold_invocations: Int;
  warm_invocations: Int;
  completion_order: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _ok_sys(v: ServerlessSystem) -> Result[ServerlessSystem, Str] { return Ok(v); }
fn _err_sys(m: Str) -> Result[ServerlessSystem, Str] { return Err(m); }
fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
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

// Slot of entity `id` in table `which`, or -1 when unknown. Element reads use
// typed `let` bindings (BUG-17 family); no indexed fn dispatch is involved.
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
// Construction
// ---------------------------------------------------------------------------

/// Create an empty serverless system.
/// Params: max_concurrency - async dispatch cap, >= 1; boot_ms - cold start
///         cost charged per COLD -> WARM transition, >= 0.
/// Returns: Ok(System); Err("serverless: max_concurrency must be >= 1") or
///          Err("serverless: boot_ms must be >= 0"). Complexity: O(1).
pub fn serverless_new(max_concurrency: Int, boot_ms: Int) -> Result[ServerlessSystem, Str] {
  if max_concurrency < 1 {
    return _err_sys("serverless: max_concurrency must be >= 1");
  }
  if boot_ms < 0 {
    return _err_sys("serverless: boot_ms must be >= 0");
  }
  return _ok_sys(ServerlessSystem{
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
    boot_ms: boot_ms;
    max_concurrency: max_concurrency;
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
  });
}

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

/// Register a function in DRAFT state with version 0.
/// Params: s - the system; id - unique function id, >= 0; handler - an
///         SV_HANDLER_* code; memory_mb - memory limit, >= 1; timeout_ms -
///         execution timeout, >= 1.
/// Returns: Ok(id); Err("serverless: function id must be >= 0"),
///          Err("serverless: duplicate function id"),
///          Err("serverless: unknown handler"),
///          Err("serverless: memory must be >= 1") or
///          Err("serverless: timeout must be >= 1") -- unchanged. Complexity: O(function count).
pub fn function_new(s: &mut ServerlessSystem, id: Int, handler: Int, memory_mb: Int, timeout_ms: Int) -> Result[Int, Str] {
  if id < 0 { return _err_int("serverless: function id must be >= 0"); }
  if _slot_in(s, _TBL_FN, id) >= 0 { return _err_int("serverless: duplicate function id"); }
  if !_is_valid_handler(handler) { return _err_int("serverless: unknown handler"); }
  if memory_mb < 1 { return _err_int("serverless: memory must be >= 1"); }
  if timeout_ms < 1 { return _err_int("serverless: timeout must be >= 1"); }
  s.function_ids.push(id);
  s.function_states.push(SV_FN_DRAFT);
  s.function_versions.push(0);
  s.function_handlers.push(handler);
  s.function_memory_mb.push(memory_mb);
  s.function_timeout_ms.push(timeout_ms);
  return _ok_int(id);
}

/// Disable an ACTIVE function (ACTIVE -> DISABLED).
/// Params: s - the system; id - function id.
/// Returns: Ok(id); Err("serverless: unknown function id"),
///          Err("serverless: function is not active") for a DRAFT function,
///          Err("serverless: function is already disabled") -- unchanged.
///          Complexity: O(function count).
pub fn function_disable(s: &mut ServerlessSystem, id: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_FN, id);
  if slot < 0 { return _err_int("serverless: unknown function id"); }
  let st: Int = s.function_states[slot];
  if st == SV_FN_DISABLED { return _err_int("serverless: function is already disabled"); }
  if st != SV_FN_ACTIVE { return _err_int("serverless: function is not active"); }
  s.function_states[slot] = SV_FN_DISABLED;
  return _ok_int(id);
}

/// Re-enable a DISABLED function (DISABLED -> ACTIVE). A DRAFT function has no
/// deployment to enable.
/// Params: s - the system; id - function id.
/// Returns: Ok(id); Err("serverless: unknown function id"),
///          Err("serverless: function is already active"),
///          Err("serverless: function has no deployment") -- unchanged. Complexity: O(function count).
pub fn function_enable(s: &mut ServerlessSystem, id: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_FN, id);
  if slot < 0 { return _err_int("serverless: unknown function id"); }
  let st: Int = s.function_states[slot];
  if st == SV_FN_ACTIVE { return _err_int("serverless: function is already active"); }
  if st == SV_FN_DRAFT { return _err_int("serverless: function has no deployment"); }
  s.function_states[slot] = SV_FN_ACTIVE;
  return _ok_int(id);
}

// ---------------------------------------------------------------------------
// Triggers (event-source wiring)
// ---------------------------------------------------------------------------

/// Wire an event source to a function.
/// Params: s - the system; trigger_id - unique trigger id, >= 0; function_id -
///         the target function; kind - an SV_TRIGGER_* code; enabled - 1 to
///         start enabled, 0 to start disabled.
/// Returns: Ok(trigger_id); Err("serverless: trigger id must be >= 0"),
///          Err("serverless: duplicate trigger id"),
///          Err("serverless: unknown function id"),
///          Err("serverless: unknown trigger kind") or
///          Err("serverless: enabled must be 0 or 1") -- unchanged.
/// Complexity: O(function count + trigger count).
pub fn trigger_new(s: &mut ServerlessSystem, trigger_id: Int, function_id: Int, kind: Int, enabled: Int) -> Result[Int, Str] {
  if trigger_id < 0 { return _err_int("serverless: trigger id must be >= 0"); }
  if _slot_in(s, _TBL_TRIGGER, trigger_id) >= 0 { return _err_int("serverless: duplicate trigger id"); }
  if _slot_in(s, _TBL_FN, function_id) < 0 { return _err_int("serverless: unknown function id"); }
  if !_is_valid_trigger_kind(kind) { return _err_int("serverless: unknown trigger kind"); }
  if enabled != 0 && enabled != 1 { return _err_int("serverless: enabled must be 0 or 1"); }
  s.trigger_ids.push(trigger_id);
  s.trigger_functions.push(function_id);
  s.trigger_kinds.push(kind);
  s.trigger_enabled.push(enabled);
  s.trigger_fires.push(0);
  return _ok_int(trigger_id);
}

/// Enable a trigger.
/// Params: s - the system; id - trigger id.
/// Returns: Ok(id); Err("serverless: unknown trigger id") or
///          Err("serverless: trigger is already enabled") -- unchanged.
/// Complexity: O(trigger count).
pub fn trigger_enable(s: &mut ServerlessSystem, id: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_TRIGGER, id);
  if slot < 0 { return _err_int("serverless: unknown trigger id"); }
  let en: Int = s.trigger_enabled[slot];
  if en == 1 { return _err_int("serverless: trigger is already enabled"); }
  s.trigger_enabled[slot] = 1;
  return _ok_int(id);
}

/// Disable a trigger.
/// Params: s - the system; id - trigger id.
/// Returns: Ok(id); Err("serverless: unknown trigger id") or
///          Err("serverless: trigger is already disabled") -- unchanged.
/// Complexity: O(trigger count).
pub fn trigger_disable(s: &mut ServerlessSystem, id: Int) -> Result[Int, Str] {
  let slot = _slot_in(s, _TBL_TRIGGER, id);
  if slot < 0 { return _err_int("serverless: unknown trigger id"); }
  let en: Int = s.trigger_enabled[slot];
  if en == 0 { return _err_int("serverless: trigger is already disabled"); }
  s.trigger_enabled[slot] = 0;
  return _ok_int(id);
}

/// Fire a trigger: enqueue an invocation of the bound function (async path,
/// consumed via xiom.serverless.invoke). The invocation is accepted only while
/// the trigger is enabled and the bound function is ACTIVE; the trigger fire
/// counter increments on success.
/// Params: s - the system; trigger_id - the trigger; invocation_id - unique
///         invocation id, >= 0; payload - the event payload.
/// Returns: Ok(invocation_id) with the invocation QUEUED;
///          Err("serverless: unknown trigger id"),
///          Err("serverless: trigger is disabled"),
///          Err("serverless: function is not active"),
///          Err("serverless: invocation id must be >= 0") or
///          Err("serverless: duplicate invocation id") -- unchanged.
/// Complexity: O(trigger count + invocation count).
pub fn trigger_fire(s: &mut ServerlessSystem, trigger_id: Int, invocation_id: Int, payload: Int) -> Result[Int, Str] {
  let tslot = _slot_in(s, _TBL_TRIGGER, trigger_id);
  if tslot < 0 { return _err_int("serverless: unknown trigger id"); }
  let en: Int = s.trigger_enabled[tslot];
  if en != 1 { return _err_int("serverless: trigger is disabled"); }
  let fid: Int = s.trigger_functions[tslot];
  let fslot = _slot_in(s, _TBL_FN, fid);
  let fst: Int = s.function_states[fslot];
  if fst != SV_FN_ACTIVE { return _err_int("serverless: function is not active"); }
  if invocation_id < 0 { return _err_int("serverless: invocation id must be >= 0"); }
  if _slot_in(s, _TBL_INVOCATION, invocation_id) >= 0 { return _err_int("serverless: duplicate invocation id"); }
  s.invocation_ids.push(invocation_id);
  s.invocation_functions.push(fid);
  s.invocation_states.push(SV_INV_QUEUED);
  s.invocation_payloads.push(payload);
  s.invocation_outputs.push(0);
  s.invocation_codes.push(SV_CODE_OK);
  s.invocation_instances.push(SV_NO_INSTANCE);
  s.invocation_colds.push(0);
  s.queue.push(invocation_id);
  s.trigger_fires[tslot] = s.trigger_fires[tslot] + 1;
  return _ok_int(invocation_id);
}

// ---------------------------------------------------------------------------
// Accessors: functions
// ---------------------------------------------------------------------------

/// Number of registered functions. Complexity: O(1).
pub fn function_count(s: &ServerlessSystem) -> Int {
  return s.function_ids.len();
}

/// Lifecycle state of function `id` (SV_FN_*), or SV_NOT_FOUND (-1).
/// Complexity: O(function count).
pub fn function_state(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_FN, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let st: Int = s.function_states[slot];
  return st;
}

/// Active version of function `id` (0 while DRAFT), or SV_NOT_FOUND (-1).
/// Complexity: O(function count).
pub fn function_version(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_FN, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let v: Int = s.function_versions[slot];
  return v;
}

/// Handler code of function `id` (SV_HANDLER_*), or SV_NOT_FOUND (-1).
/// Complexity: O(function count).
pub fn function_handler(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_FN, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let h: Int = s.function_handlers[slot];
  return h;
}

/// Memory limit of function `id` in MB, or SV_NOT_FOUND (-1).
/// Complexity: O(function count).
pub fn function_memory_mb(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_FN, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let m: Int = s.function_memory_mb[slot];
  return m;
}

/// Timeout of function `id` in ms, or SV_NOT_FOUND (-1).
/// Complexity: O(function count).
pub fn function_timeout_ms(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_FN, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let t: Int = s.function_timeout_ms[slot];
  return t;
}

// ---------------------------------------------------------------------------
// Accessors: triggers
// ---------------------------------------------------------------------------

/// Number of wired triggers. Complexity: O(1).
pub fn trigger_count(s: &ServerlessSystem) -> Int {
  return s.trigger_ids.len();
}

/// Event-source kind of trigger `id` (SV_TRIGGER_*), or SV_NOT_FOUND (-1).
/// Complexity: O(trigger count).
pub fn trigger_kind(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_TRIGGER, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let k: Int = s.trigger_kinds[slot];
  return k;
}

/// True when trigger `id` exists and is enabled. Complexity: O(trigger count).
pub fn trigger_is_enabled(s: &ServerlessSystem, id: Int) -> Bool {
  let slot = _slot_in(s, _TBL_TRIGGER, id);
  if slot < 0 { return false; }
  let en: Int = s.trigger_enabled[slot];
  return en == 1;
}

/// Successful fire count of trigger `id`, or SV_NOT_FOUND (-1) when unknown.
/// Complexity: O(trigger count).
pub fn trigger_fires(s: &ServerlessSystem, id: Int) -> Int {
  let slot = _slot_in(s, _TBL_TRIGGER, id);
  if slot < 0 { return SV_NOT_FOUND; }
  let n: Int = s.trigger_fires[slot];
  return n;
}

// ---------------------------------------------------------------------------
// Names
// ---------------------------------------------------------------------------

/// Human-readable handler name, or "unknown".
/// Complexity: O(1).
pub fn serverless_handler_name(h: Int) -> Str {
  if h == SV_HANDLER_ECHO { return "echo"; }
  if h == SV_HANDLER_DOUBLE { return "double"; }
  if h == SV_HANDLER_FAIL { return "fail"; }
  return "unknown";
}

/// Human-readable function state name, or "unknown".
/// Complexity: O(1).
pub fn function_state_name(st: Int) -> Str {
  if st == SV_FN_DRAFT { return "draft"; }
  if st == SV_FN_ACTIVE { return "active"; }
  if st == SV_FN_DISABLED { return "disabled"; }
  return "unknown";
}

/// Human-readable deploy state name, or "unknown".
/// Complexity: O(1).
pub fn deploy_state_name(st: Int) -> Str {
  if st == SV_DEPLOY_PENDING { return "pending"; }
  if st == SV_DEPLOY_IN_PROGRESS { return "in-progress"; }
  if st == SV_DEPLOY_READY { return "ready"; }
  if st == SV_DEPLOY_FAILED { return "failed"; }
  if st == SV_DEPLOY_ROLLED_BACK { return "rolled-back"; }
  return "unknown";
}

/// Human-readable invocation state name, or "unknown".
/// Complexity: O(1).
pub fn invocation_state_name(st: Int) -> Str {
  if st == SV_INV_QUEUED { return "queued"; }
  if st == SV_INV_RUNNING { return "running"; }
  if st == SV_INV_DONE { return "done"; }
  if st == SV_INV_FAILED { return "failed"; }
  return "unknown";
}

/// Human-readable trigger kind name, or "unknown".
/// Complexity: O(1).
pub fn trigger_kind_name(k: Int) -> Str {
  if k == SV_TRIGGER_TIMER { return "timer"; }
  if k == SV_TRIGGER_HTTP { return "http"; }
  if k == SV_TRIGGER_QUEUE { return "queue"; }
  return "unknown";
}

/// Human-readable runtime instance state name, or "unknown".
/// Complexity: O(1).
pub fn runtime_state_name(st: Int) -> Str {
  if st == SV_RT_COLD { return "cold"; }
  if st == SV_RT_WARM { return "warm"; }
  if st == SV_RT_BUSY { return "busy"; }
  return "unknown";
}


