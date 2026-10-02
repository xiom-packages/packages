// XIOM -- xiom.docker: container lifecycle state machine
// Port task: replace the xiom.docker placeholder with a real, tested,
// pure-XIOM package (no FFI, no HTTP, no sockets, no daemon).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A strict create/start/stop/restart/remove state machine over four states:
//
//   CREATED --start--> RUNNING --stop--> STOPPED --start--> RUNNING
//      |                   |                  |
//      +-------remove------+------remove------+        (RUNNING refuses
//      |                   |                  |         remove: stop first)
//      v                   v                  v
//   REMOVED  <--------------------------------+
//
// restart is RUNNING -> RUNNING or STOPPED -> RUNNING. Every invalid
// transition returns Err and leaves both the state and the counters
// unchanged; ids are dense (0-based) and never reused, so removed slots stay
// addressable for inspection.
//
// Container names and image references are stored as Str blobs with a
// monotone Vec[Int] offset table (never Vec[Str]); image references are
// validated through xiom.docker.image.image_ref_parse at creation time, and
// the exact image error is propagated.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err only inside
// the _c_ok_int/_c_err_int leaf helpers; typed locals on every Vec[Int]
// element read; no `==` on Str (string.str_compare everywhere); no
// Vec[StructType]; bounded loops.

module xiom.docker

use xiom.string;
use xiom.docker.image;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Container state: created but never started.
pub const DOCKER_CT_CREATED: Int = 0;

/// Container state: running.
pub const DOCKER_CT_RUNNING: Int = 1;

/// Container state: stopped (after start).
pub const DOCKER_CT_STOPPED: Int = 2;

/// Container state: removed (terminal; the slot stays reserved).
pub const DOCKER_CT_REMOVED: Int = 3;

/// Transition action code: start.
pub const DOCKER_ACTION_START: Int = 1;

/// Transition action code: stop.
pub const DOCKER_ACTION_STOP: Int = 2;

/// Transition action code: restart.
pub const DOCKER_ACTION_RESTART: Int = 3;

/// Transition action code: remove.
pub const DOCKER_ACTION_REMOVE: Int = 4;

/// Capacity guard: containers per model.
pub const DOCKER_MAX_CONTAINERS: Int = 64;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A container model: parallel fields indexed by dense container id (0-based,
/// ids never reused). Names and image references are stored as Str blobs
/// with monotone offset tables; states[i] is a DOCKER_CT_* code and the
/// three counters record successful transitions. Fields are implementation
/// detail; use the container_* accessors.
pub type ContainerModel = {
  names_data: Str;
  names_off: Vec[Int];
  images_data: Str;
  images_off: Vec[Int];
  states: Vec[Int];
  starts: Vec[Int];
  stops: Vec[Int];
  restarts: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _c_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _c_err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Blob helper (Str + monotone Vec[Int] offsets; no Vec[Str])
// ---------------------------------------------------------------------------

// Append `s` to the blob `data`/`offs`; offs must be non-empty with its last
// entry equal to string.str_len(data). Returns the extended data string.
fn _c_blob_append(data: Str, offs: &mut Vec[Int], s: Str) -> Str {
  let start: Int = offs[offs.len() - 1];
  offs.push(start + string.str_len(s));
  return data + s;
}

// ---------------------------------------------------------------------------
// Construction and accessors
// ---------------------------------------------------------------------------

/// Empty container model. Complexity: O(1).
pub fn container_model_new() -> ContainerModel {
  var names_off = Vec[Int].new();
  names_off.push(0);
  var images_off = Vec[Int].new();
  images_off.push(0);
  return ContainerModel{
    names_data: "";
    names_off: names_off;
    images_data: "";
    images_off: images_off;
    states: Vec[Int].new();
    starts: Vec[Int].new();
    stops: Vec[Int].new();
    restarts: Vec[Int].new();
  };
}

// Slot of container `name`, or -1. Byte-exact case-sensitive search.
fn _container_find(m: &ContainerModel, name: Str) -> Int {
  var i = 0;
  let cnt = m.names_off.len() - 1;
  while i < cnt {
    let a: Int = m.names_off[i];
    let b: Int = m.names_off[i + 1];
    let cur: Str = string.str_slice(m.names_data, a, b);
    if string.str_compare(cur, name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Create a container in the CREATED state. The name must be non-empty and
/// unique; the image must parse as a valid reference (the exact image error
/// is propagated). Returns the dense container id.
pub fn container_create(m: &mut ContainerModel, name: Str, image: Str) -> Result[Int, Str] {
  if string.str_len(name) == 0 { return _c_err_int("container: name must not be empty"); }
  if _container_find(m, name) >= 0 { return _c_err_int("container: duplicate name"); }
  match image_ref_parse(image) {
    Ok(_) => {},
    Err(emsg) => { return _c_err_int(emsg); },
  }
  let cnt = m.states.len();
  if cnt >= DOCKER_MAX_CONTAINERS { return _c_err_int("container: container limit exceeded"); }
  m.names_data = _c_blob_append(m.names_data, &mut m.names_off, name);
  m.images_data = _c_blob_append(m.images_data, &mut m.images_off, image);
  m.states.push(DOCKER_CT_CREATED);
  m.starts.push(0);
  m.stops.push(0);
  m.restarts.push(0);
  return _c_ok_int(cnt);
}

/// Number of container slots (including removed ones). Complexity: O(1).
pub fn container_count(m: &ContainerModel) -> Int { return m.states.len(); }

/// Number of live (non-removed) containers. Complexity: O(n).
pub fn container_live_count(m: &ContainerModel) -> Int {
  var k = 0;
  var i = 0;
  while i < m.states.len() {
    let st: Int = m.states[i];
    if st != DOCKER_CT_REMOVED { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// Container name, or "" when the id is out of range. Complexity: O(1).
pub fn container_name(m: &ContainerModel, id: Int) -> Str {
  if id < 0 || id >= m.states.len() { return ""; }
  let a: Int = m.names_off[id];
  let b: Int = m.names_off[id + 1];
  return string.str_slice(m.names_data, a, b);
}

/// Image reference the container was created from, or "" when out of range.
pub fn container_image(m: &ContainerModel, id: Int) -> Str {
  if id < 0 || id >= m.states.len() { return ""; }
  let a: Int = m.images_off[id];
  let b: Int = m.images_off[id + 1];
  return string.str_slice(m.images_data, a, b);
}

/// Container index of `name`, or DOCKER_NOT_FOUND (-1). Complexity: O(n).
pub fn container_index(m: &ContainerModel, name: Str) -> Int {
  return _container_find(m, name);
}

/// State code of container `id`, or DOCKER_NOT_FOUND (-1).
pub fn container_state(m: &ContainerModel, id: Int) -> Int {
  if id < 0 || id >= m.states.len() { return DOCKER_NOT_FOUND; }
  let st: Int = m.states[id];
  return st;
}

/// Human-readable state name ("created", "running", "stopped", "removed",
/// "unknown"). Complexity: O(1).
pub fn container_state_name(state: Int) -> Str {
  if state == DOCKER_CT_CREATED { return "created"; }
  if state == DOCKER_CT_RUNNING { return "running"; }
  if state == DOCKER_CT_STOPPED { return "stopped"; }
  if state == DOCKER_CT_REMOVED { return "removed"; }
  return "unknown";
}

/// True when the state-level transition from -> to is legal:
/// CREATED -> RUNNING | REMOVED; RUNNING -> STOPPED | RUNNING (restart);
/// STOPPED -> RUNNING | REMOVED; REMOVED -> (nothing). Complexity: O(1).
pub fn container_can_transition(from: Int, to: Int) -> Bool {
  if from == DOCKER_CT_CREATED {
    return to == DOCKER_CT_RUNNING || to == DOCKER_CT_REMOVED;
  }
  if from == DOCKER_CT_RUNNING {
    return to == DOCKER_CT_STOPPED || to == DOCKER_CT_RUNNING;
  }
  if from == DOCKER_CT_STOPPED {
    return to == DOCKER_CT_RUNNING || to == DOCKER_CT_REMOVED;
  }
  return false;
}

/// Start a CREATED or STOPPED container. Returns the new state code
/// (DOCKER_CT_RUNNING); an invalid transition returns Err and leaves the
/// state and counters unchanged.
pub fn container_start(m: &mut ContainerModel, id: Int) -> Result[Int, Str] {
  if id < 0 || id >= m.states.len() { return _c_err_int("container: unknown id"); }
  let st: Int = m.states[id];
  if st == DOCKER_CT_REMOVED { return _c_err_int("container: container removed"); }
  if st == DOCKER_CT_RUNNING { return _c_err_int("container: already running"); }
  m.states[id] = DOCKER_CT_RUNNING;
  let c: Int = m.starts[id];
  m.starts[id] = c + 1;
  return _c_ok_int(DOCKER_CT_RUNNING);
}

/// Stop a RUNNING container. Returns DOCKER_CT_STOPPED.
pub fn container_stop(m: &mut ContainerModel, id: Int) -> Result[Int, Str] {
  if id < 0 || id >= m.states.len() { return _c_err_int("container: unknown id"); }
  let st: Int = m.states[id];
  if st == DOCKER_CT_REMOVED { return _c_err_int("container: container removed"); }
  if st == DOCKER_CT_CREATED { return _c_err_int("container: not running"); }
  if st == DOCKER_CT_STOPPED { return _c_err_int("container: already stopped"); }
  m.states[id] = DOCKER_CT_STOPPED;
  let c: Int = m.stops[id];
  m.stops[id] = c + 1;
  return _c_ok_int(DOCKER_CT_STOPPED);
}

/// Restart a RUNNING or STOPPED container: the state becomes RUNNING and the
/// restart counter increments. Returns DOCKER_CT_RUNNING.
pub fn container_restart(m: &mut ContainerModel, id: Int) -> Result[Int, Str] {
  if id < 0 || id >= m.states.len() { return _c_err_int("container: unknown id"); }
  let st: Int = m.states[id];
  if st == DOCKER_CT_REMOVED { return _c_err_int("container: container removed"); }
  if st == DOCKER_CT_CREATED { return _c_err_int("container: not started"); }
  m.states[id] = DOCKER_CT_RUNNING;
  let c: Int = m.restarts[id];
  m.restarts[id] = c + 1;
  return _c_ok_int(DOCKER_CT_RUNNING);
}

/// Remove a CREATED or STOPPED container (terminal state). A running
/// container must be stopped first.
pub fn container_remove(m: &mut ContainerModel, id: Int) -> Result[Int, Str] {
  if id < 0 || id >= m.states.len() { return _c_err_int("container: unknown id"); }
  let st: Int = m.states[id];
  if st == DOCKER_CT_REMOVED { return _c_err_int("container: container removed"); }
  if st == DOCKER_CT_RUNNING { return _c_err_int("container: stop before removing"); }
  m.states[id] = DOCKER_CT_REMOVED;
  return _c_ok_int(DOCKER_CT_REMOVED);
}

/// Action dispatch over DOCKER_ACTION_START/STOP/RESTART/REMOVE. Returns the
/// resulting state code or the action's Err unchanged; an unknown action
/// code returns Err("container: unknown action").
pub fn container_transition(m: &mut ContainerModel, id: Int, action: Int) -> Result[Int, Str] {
  if action == DOCKER_ACTION_START { return container_start(m, id); }
  if action == DOCKER_ACTION_STOP { return container_stop(m, id); }
  if action == DOCKER_ACTION_RESTART { return container_restart(m, id); }
  if action == DOCKER_ACTION_REMOVE { return container_remove(m, id); }
  return _c_err_int("container: unknown action");
}

/// Successful start count of container `id`, or DOCKER_NOT_FOUND (-1).
pub fn container_start_count(m: &ContainerModel, id: Int) -> Int {
  if id < 0 || id >= m.starts.len() { return DOCKER_NOT_FOUND; }
  let v: Int = m.starts[id];
  return v;
}

/// Successful stop count of container `id`, or DOCKER_NOT_FOUND (-1).
pub fn container_stop_count(m: &ContainerModel, id: Int) -> Int {
  if id < 0 || id >= m.stops.len() { return DOCKER_NOT_FOUND; }
  let v: Int = m.stops[id];
  return v;
}

/// Successful restart count of container `id`, or DOCKER_NOT_FOUND (-1).
pub fn container_restart_count(m: &ContainerModel, id: Int) -> Int {
  if id < 0 || id >= m.restarts.len() { return DOCKER_NOT_FOUND; }
  let v: Int = m.restarts[id];
  return v;
}
