// XIOM -- xiom.docker.registry: registry login state and push/pull plans
// Port task: replace the xiom.docker placeholder with a real, tested,
// pure-XIOM package (no FFI, no HTTP, no sockets, no daemon).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a registry session as a pure value. registry_login validates the
// user and password and then discards the password -- it is never stored.
// A pull plan needs no session in this model; a push plan requires an
// active login and a tagged reference. Plans carry a fixed, ordered step
// list, stored as a Str blob with a monotone Vec[Int] offset table.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err only inside
// the _r_ok_*/_r_err_* leaf helpers; typed locals on every Vec[Int] element
// read; no `==` on Str (string.str_compare everywhere); no Vec[Str]; no
// Vec[StructType]; image references are validated by
// xiom.docker.image.image_ref_parse (imported from the core module).

module xiom.docker.registry

use xiom.string;
use xiom.docker.image;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Plan operation: pull.
pub const DOCKER_PLAN_PULL: Int = 0;

/// Plan operation: push.
pub const DOCKER_PLAN_PUSH: Int = 1;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A registry login state. The password is validated and then discarded: it
/// is never stored in the model. Fields are implementation detail; use the
/// registry_* accessors.
pub type DockerRegistry = {
  host: Str;
  user: Str;
  logged_in: Bool;
  logins: Int;
  logouts: Int;
}

/// A deterministic push/pull plan: the operation, the parsed reference
/// fields and an ordered list of step descriptions. Fields are
/// implementation detail; use the plan_* accessors.
pub type DockerPlan = {
  op: Int;
  registry: Str;
  repository: Str;
  tag: Str;
  digest: Str;
  needs_auth: Bool;
  steps_data: Str;
  steps_off: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _r_ok_reg(v: DockerRegistry) -> Result[DockerRegistry, Str] { return Ok(v); }
fn _r_err_reg(m: Str) -> Result[DockerRegistry, Str] { return Err(m); }
fn _r_ok_plan(v: DockerPlan) -> Result[DockerPlan, Str] { return Ok(v); }
fn _r_err_plan(m: Str) -> Result[DockerPlan, Str] { return Err(m); }
fn _r_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _r_err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Blob helper (Str + monotone Vec[Int] offsets; no Vec[Str])
// ---------------------------------------------------------------------------

// Append `s` to the blob `data`/`offs`; offs must be non-empty with its last
// entry equal to string.str_len(data). Returns the extended data string.
fn _r_blob_append(data: Str, offs: &mut Vec[Int], s: Str) -> Str {
  let start: Int = offs[offs.len() - 1];
  offs.push(start + string.str_len(s));
  return data + s;
}

// ---------------------------------------------------------------------------
// Login state
// ---------------------------------------------------------------------------

/// New logged-out registry with the given host. Err when host is empty.
pub fn registry_new(host: Str) -> Result[DockerRegistry, Str] {
  if string.str_len(host) == 0 { return _r_err_reg("registry: host must not be empty"); }
  return _r_ok_reg(DockerRegistry{
    host: host;
    user: "";
    logged_in: false;
    logins: 0;
    logouts: 0;
  });
}

/// Log in (or re-login, updating the user). The password is checked
/// non-empty and then discarded -- it is never stored. Returns the login
/// count.
pub fn registry_login(reg: &mut DockerRegistry, user: Str, password: Str) -> Result[Int, Str] {
  if string.str_len(user) == 0 { return _r_err_int("registry: user must not be empty"); }
  if string.str_len(password) == 0 { return _r_err_int("registry: password must not be empty"); }
  reg.user = user;
  reg.logged_in = true;
  reg.logins = reg.logins + 1;
  return _r_ok_int(reg.logins);
}

/// Log out. Returns the logout count; Err("registry: not logged in") when
/// no session is active (state unchanged).
pub fn registry_logout(reg: &mut DockerRegistry) -> Result[Int, Str] {
  if !reg.logged_in { return _r_err_int("registry: not logged in"); }
  reg.logged_in = false;
  reg.logouts = reg.logouts + 1;
  return _r_ok_int(reg.logouts);
}

pub fn registry_host(reg: &DockerRegistry) -> Str { return reg.host; }
pub fn registry_user(reg: &DockerRegistry) -> Str { return reg.user; }
pub fn registry_logged_in(reg: &DockerRegistry) -> Bool { return reg.logged_in; }
pub fn registry_login_count(reg: &DockerRegistry) -> Int { return reg.logins; }
pub fn registry_logout_count(reg: &DockerRegistry) -> Int { return reg.logouts; }

// ---------------------------------------------------------------------------
// Push/pull plans
// ---------------------------------------------------------------------------

// Build a plan from parsed reference `r` and the fixed step list for `op`.
fn _r_make_plan(op: Int, r: &ImageRef, needs_auth: Bool) -> DockerPlan {
  var steps_data = "";
  var steps_off = Vec[Int].new();
  steps_off.push(0);
  if op == DOCKER_PLAN_PULL {
    steps_data = _r_blob_append(steps_data, &mut steps_off, "resolve manifest");
    steps_data = _r_blob_append(steps_data, &mut steps_off, "fetch config");
    steps_data = _r_blob_append(steps_data, &mut steps_off, "fetch layers");
  } else {
    steps_data = _r_blob_append(steps_data, &mut steps_off, "authenticate");
    steps_data = _r_blob_append(steps_data, &mut steps_off, "check tag");
    steps_data = _r_blob_append(steps_data, &mut steps_off, "upload layers");
    steps_data = _r_blob_append(steps_data, &mut steps_off, "push manifest");
  }
  return DockerPlan{
    op: op;
    registry: r.registry;
    repository: r.repository;
    tag: r.tag;
    digest: r.digest;
    needs_auth: needs_auth;
    steps_data: steps_data;
    steps_off: steps_off;
  };
}

/// Plan a pull. Pulls never require auth in this model (public
/// registries); needs_auth records whether a session happens to be active.
/// Returns: Ok(DockerPlan); Err with the image parse error for a malformed
/// reference.
pub fn registry_plan_pull(reg: &DockerRegistry, ref: Str) -> Result[DockerPlan, Str] {
  match image_ref_parse(ref) {
    Ok(r) => {
      return _r_ok_plan(_r_make_plan(DOCKER_PLAN_PULL, &r, reg.logged_in));
    },
    Err(emsg) => { return _r_err_plan(emsg); },
  }
  return _r_err_plan("image: empty reference");
}

/// Plan a push. Requires an active login and a reference carrying a tag.
/// Returns: Ok(DockerPlan); Err("registry: login required for push"),
/// Err("registry: push requires a tag") or the image parse error.
pub fn registry_plan_push(reg: &DockerRegistry, ref: Str) -> Result[DockerPlan, Str] {
  if !reg.logged_in { return _r_err_plan("registry: login required for push"); }
  match image_ref_parse(ref) {
    Ok(r) => {
      if string.str_len(r.tag) == 0 { return _r_err_plan("registry: push requires a tag"); }
      return _r_ok_plan(_r_make_plan(DOCKER_PLAN_PUSH, &r, true));
    },
    Err(emsg) => { return _r_err_plan(emsg); },
  }
  return _r_err_plan("image: empty reference");
}

/// Operation code (DOCKER_PLAN_PULL or DOCKER_PLAN_PUSH).
pub fn plan_op(p: &DockerPlan) -> Int { return p.op; }

/// Operation name ("pull", "push", "unknown").
pub fn plan_operation_name(op: Int) -> Str {
  if op == DOCKER_PLAN_PULL { return "pull"; }
  if op == DOCKER_PLAN_PUSH { return "push"; }
  return "unknown";
}

/// True when the plan needs an authenticated session.
pub fn plan_needs_auth(p: &DockerPlan) -> Bool { return p.needs_auth; }

/// Number of plan steps.
pub fn plan_step_count(p: &DockerPlan) -> Int {
  if p.steps_off.len() == 0 { return 0; }
  return p.steps_off.len() - 1;
}

/// Step description at `i`, or "" when out of range.
pub fn plan_step_at(p: &DockerPlan, i: Int) -> Str {
  if i < 0 || i >= plan_step_count(p) { return ""; }
  let a: Int = p.steps_off[i];
  let b: Int = p.steps_off[i + 1];
  return string.str_slice(p.steps_data, a, b);
}

pub fn plan_registry(p: &DockerPlan) -> Str { return p.registry; }
pub fn plan_repository(p: &DockerPlan) -> Str { return p.repository; }
pub fn plan_tag(p: &DockerPlan) -> Str { return p.tag; }
pub fn plan_digest(p: &DockerPlan) -> Str { return p.digest; }
