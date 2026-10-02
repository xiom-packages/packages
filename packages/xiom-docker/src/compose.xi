// XIOM -- xiom.docker.compose: compose services and dependency graph
// Port task: replace the xiom.docker placeholder with a real, tested,
// pure-XIOM package (no FFI, no HTTP, no sockets, no daemon).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a compose stack as a pure value. Services carry a name, an image
// reference and a replica count; dependencies are stored as two parallel
// Vec[Int] edge fields. An edge dep -> svc means "dep must start before
// svc". compose_topo_order runs Kahn's algorithm scanning for the smallest
// ready index, so the start order is deterministic; a stalled pass means a
// cycle. Adding a cycle-closing edge is allowed (detection is explicit),
// while self-edges and duplicate edges are rejected.
//
// Network and volume attachments are per-service name references stored as
// Str blobs with an owner Vec[Int] parallel to the offset table (never
// Vec[Str]).
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err only inside
// the _s_ok_*/_s_err_* leaf helpers; typed locals on every Vec element
// read; no `==` on Str (string.str_compare everywhere); no
// Vec[StructType]; every graph walk is bounded by
// DOCKER_STACK_MAX_SERVICES and DOCKER_STACK_MAX_EDGES.

module xiom.docker.compose

use xiom.string;
use xiom.docker.image;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Capacity guard: services per compose model.
pub const DOCKER_STACK_MAX_SERVICES: Int = 64;

/// Capacity guard: dependency edges per compose model.
pub const DOCKER_STACK_MAX_EDGES: Int = 512;

/// Capacity guard: network references attached to one service.
pub const DOCKER_STACK_MAX_REFS: Int = 128;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A compose model: service names/images as Str blobs, replicas, the
/// dependency edge list (edge_from[i] must start before edge_to[i]) and the
/// per-service network/volume name references. Fields are implementation
/// detail; use the compose_* accessors.
pub type DockerCompose = {
  svc_data: Str;
  svc_off: Vec[Int];
  img_data: Str;
  img_off: Vec[Int];
  replicas: Vec[Int];
  edge_from: Vec[Int];
  edge_to: Vec[Int];
  net_svc: Vec[Int];
  net_data: Str;
  net_off: Vec[Int];
  vol_svc: Vec[Int];
  vol_data: Str;
  vol_off: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _s_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _s_err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _s_ok_order(v: Vec[Int]) -> Result[Vec[Int], Str] { return Ok(v); }
fn _s_err_order(m: Str) -> Result[Vec[Int], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Blob helper (Str + monotone Vec[Int] offsets; no Vec[Str])
// ---------------------------------------------------------------------------

// Append `s` to a blob; offs must be non-empty with offs[last] ==
// string.str_len(data). Returns the extended data string.
fn _s_blob_append(data: Str, offs: &mut Vec[Int], s: Str) -> Str {
  let start: Int = offs[offs.len() - 1];
  offs.push(start + string.str_len(s));
  return data + s;
}

// ---------------------------------------------------------------------------
// Compose services
// ---------------------------------------------------------------------------

/// Empty compose model. Complexity: O(1).
pub fn compose_new() -> DockerCompose {
  var svc_off = Vec[Int].new();
  svc_off.push(0);
  var img_off = Vec[Int].new();
  img_off.push(0);
  var net_off = Vec[Int].new();
  net_off.push(0);
  var vol_off = Vec[Int].new();
  vol_off.push(0);
  return DockerCompose{
    svc_data: "";
    svc_off: svc_off;
    img_data: "";
    img_off: img_off;
    replicas: Vec[Int].new();
    edge_from: Vec[Int].new();
    edge_to: Vec[Int].new();
    net_svc: Vec[Int].new();
    net_data: "";
    net_off: net_off;
    vol_svc: Vec[Int].new();
    vol_data: "";
    vol_off: vol_off;
  };
}

// Slot of service `name`, or -1.
fn _s_find_service(c: &DockerCompose, name: Str) -> Int {
  var i = 0;
  let cnt = c.svc_off.len() - 1;
  while i < cnt {
    let a: Int = c.svc_off[i];
    let b: Int = c.svc_off[i + 1];
    let cur: Str = string.str_slice(c.svc_data, a, b);
    if string.str_compare(cur, name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Add a service (replicas default 1). The name must be non-empty and
/// unique; the image must parse as a valid reference (the exact image error
/// is propagated). Returns the dense service index.
pub fn compose_add_service(c: &mut DockerCompose, name: Str, image: Str) -> Result[Int, Str] {
  if string.str_len(name) == 0 { return _s_err_int("compose: service name must not be empty"); }
  if _s_find_service(c, name) >= 0 { return _s_err_int("compose: duplicate service name"); }
  match image_ref_parse(image) {
    Ok(_) => {},
    Err(emsg) => { return _s_err_int(emsg); },
  }
  let cnt = c.replicas.len();
  if cnt >= DOCKER_STACK_MAX_SERVICES { return _s_err_int("compose: service limit exceeded"); }
  c.svc_data = _s_blob_append(c.svc_data, &mut c.svc_off, name);
  c.img_data = _s_blob_append(c.img_data, &mut c.img_off, image);
  c.replicas.push(1);
  return _s_ok_int(cnt);
}

/// Service count. Complexity: O(1).
pub fn compose_service_count(c: &DockerCompose) -> Int { return c.replicas.len(); }

/// Service name at `i`, or "" when out of range. Complexity: O(1).
pub fn compose_service_name(c: &DockerCompose, i: Int) -> Str {
  if i < 0 || i >= c.replicas.len() { return ""; }
  let a: Int = c.svc_off[i];
  let b: Int = c.svc_off[i + 1];
  return string.str_slice(c.svc_data, a, b);
}

/// Service image reference at `i`, or "" when out of range.
pub fn compose_service_image(c: &DockerCompose, i: Int) -> Str {
  if i < 0 || i >= c.replicas.len() { return ""; }
  let a: Int = c.img_off[i];
  let b: Int = c.img_off[i + 1];
  return string.str_slice(c.img_data, a, b);
}

/// Service index of `name`, or DOCKER_NOT_FOUND (-1). Complexity: O(n).
pub fn compose_service_index(c: &DockerCompose, name: Str) -> Int {
  return _s_find_service(c, name);
}

/// Replicas of service `i`, or DOCKER_NOT_FOUND (-1) when out of range.
pub fn compose_service_replicas(c: &DockerCompose, i: Int) -> Int {
  if i < 0 || i >= c.replicas.len() { return image.DOCKER_NOT_FOUND; }
  let r: Int = c.replicas[i];
  return r;
}

/// Set replicas of service `i` (must be >= 1). Returns the new value.
pub fn compose_set_replicas(c: &mut DockerCompose, i: Int, reps: Int) -> Result[Int, Str] {
  if i < 0 || i >= c.replicas.len() { return _s_err_int("compose: unknown service"); }
  if reps < 1 { return _s_err_int("compose: replicas must be >= 1"); }
  c.replicas[i] = reps;
  return _s_ok_int(reps);
}

// ---------------------------------------------------------------------------
// Dependency graph
// ---------------------------------------------------------------------------

// True when the edge from -> to is already stored.
fn _s_edge_exists(c: &DockerCompose, from: Int, to: Int) -> Bool {
  var i = 0;
  while i < c.edge_from.len() {
    let f: Int = c.edge_from[i];
    let t: Int = c.edge_to[i];
    if f == from && t == to { return true; }
    i = i + 1;
  }
  return false;
}

/// Declare that service `svc` depends on service `dep` (start order
/// dep -> svc). Rejects unknown services, self-dependencies and duplicate
/// edges; a cycle-closing edge is accepted and later rejected by
/// compose_topo_order. Returns the new edge count.
pub fn compose_add_dep(c: &mut DockerCompose, svc: Int, dep: Int) -> Result[Int, Str] {
  if svc < 0 || svc >= c.replicas.len() { return _s_err_int("compose: unknown service"); }
  if dep < 0 || dep >= c.replicas.len() { return _s_err_int("compose: unknown service"); }
  if svc == dep { return _s_err_int("compose: service cannot depend on itself"); }
  if _s_edge_exists(c, dep, svc) { return _s_err_int("compose: duplicate dependency"); }
  if c.edge_from.len() >= DOCKER_STACK_MAX_EDGES { return _s_err_int("compose: dependency limit exceeded"); }
  c.edge_from.push(dep);
  c.edge_to.push(svc);
  return _s_ok_int(c.edge_from.len());
}

/// Number of dependencies declared by service `svc`, or DOCKER_NOT_FOUND
/// (-1) when out of range. Complexity: O(edges).
pub fn compose_dep_count(c: &DockerCompose, svc: Int) -> Int {
  if svc < 0 || svc >= c.replicas.len() { return image.DOCKER_NOT_FOUND; }
  var k = 0;
  var i = 0;
  while i < c.edge_to.len() {
    let t: Int = c.edge_to[i];
    if t == svc { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// Index of the k-th dependency of service `svc` in declaration order, or
/// DOCKER_NOT_FOUND (-1). Complexity: O(edges).
pub fn compose_dep_at(c: &DockerCompose, svc: Int, k: Int) -> Int {
  if svc < 0 || svc >= c.replicas.len() { return image.DOCKER_NOT_FOUND; }
  if k < 0 { return image.DOCKER_NOT_FOUND; }
  var seen = 0;
  var i = 0;
  while i < c.edge_to.len() {
    let t: Int = c.edge_to[i];
    if t == svc {
      if seen == k {
        let f: Int = c.edge_from[i];
        return f;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return image.DOCKER_NOT_FOUND;
}

/// True when service `svc` directly depends on service `dep`.
pub fn compose_depends_on(c: &DockerCompose, svc: Int, dep: Int) -> Bool {
  if svc < 0 || svc >= c.replicas.len() { return false; }
  if dep < 0 || dep >= c.replicas.len() { return false; }
  return _s_edge_exists(c, dep, svc);
}

// Count of not-yet-started dependencies of `v` (edges from a service whose
// done flag is 0). Kahn's frontier test, recomputed each pass.
fn _s_waiting_deps(c: &DockerCompose, done: &Vec[Int], v: Int) -> Int {
  var k = 0;
  var i = 0;
  while i < c.edge_to.len() {
    let t: Int = c.edge_to[i];
    if t == v {
      let f: Int = c.edge_from[i];
      let d: Int = done[f];
      if d == 0 { k = k + 1; }
    }
    i = i + 1;
  }
  return k;
}

/// Deterministic topological start order (Kahn's algorithm, smallest ready
/// index first). Returns Err("compose: dependency cycle") when the graph
/// contains a cycle. Complexity: O(services * edges), bounded by the caps.
pub fn compose_topo_order(c: &DockerCompose) -> Result[Vec[Int], Str] {
  let n = c.replicas.len();
  var out = Vec[Int].new();
  var done = Vec[Int].new();
  var i = 0;
  while i < n {
    done.push(0);
    i = i + 1;
  }
  var emitted = 0;
  while emitted < n {
    var pick = -1;
    i = 0;
    while i < n {
      let d: Int = done[i];
      if d == 0 {
        let wait = _s_waiting_deps(c, &done, i);
        if wait == 0 {
          pick = i;
          break;
        }
      }
      i = i + 1;
    }
    if pick < 0 { return _s_err_order("compose: dependency cycle"); }
    done[pick] = 1;
    out.push(pick);
    emitted = emitted + 1;
  }
  return _s_ok_order(out);
}

/// True when the dependency graph contains a cycle. Complexity: bounded by
/// compose_topo_order.
pub fn compose_has_cycle(c: &DockerCompose) -> Bool {
  match compose_topo_order(c) {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return false;
}

/// Comma-separated service names in topological start order, or "cycle"
/// when the graph is cyclic. Complexity: bounded by compose_topo_order.
pub fn compose_order_text(c: &DockerCompose) -> Str {
  match compose_topo_order(c) {
    Ok(v) => {
      var out = "";
      var i = 0;
      while i < v.len() {
        let idx: Int = v[i];
        let nm: Str = compose_service_name(c, idx);
        if i > 0 { out = out + ","; }
        out = out + nm;
        i = i + 1;
      }
      return out;
    },
    Err(_) => { return "cycle"; },
  }
  return "cycle";
}

// ---------------------------------------------------------------------------
// Network/volume references (concrete helpers keep field access local; never
// `&struct.field` into a `&Vec` parameter, trap 4)
// ---------------------------------------------------------------------------

fn _s_net_exists(c: &DockerCompose, svc: Int, name: Str) -> Bool {
  var i = 0;
  while i < c.net_svc.len() {
    let o: Int = c.net_svc[i];
    if o == svc {
      let a: Int = c.net_off[i];
      let b: Int = c.net_off[i + 1];
      let cur: Str = string.str_slice(c.net_data, a, b);
      if string.str_compare(cur, name) == 0 { return true; }
    }
    i = i + 1;
  }
  return false;
}

fn _s_net_count(c: &DockerCompose, svc: Int) -> Int {
  var k = 0;
  var i = 0;
  while i < c.net_svc.len() {
    let o: Int = c.net_svc[i];
    if o == svc { k = k + 1; }
    i = i + 1;
  }
  return k;
}

fn _s_net_at(c: &DockerCompose, svc: Int, k: Int) -> Str {
  if k < 0 { return ""; }
  var seen = 0;
  var i = 0;
  while i < c.net_svc.len() {
    let o: Int = c.net_svc[i];
    if o == svc {
      if seen == k {
        let a: Int = c.net_off[i];
        let b: Int = c.net_off[i + 1];
        return string.str_slice(c.net_data, a, b);
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

fn _s_vol_exists(c: &DockerCompose, svc: Int, name: Str) -> Bool {
  var i = 0;
  while i < c.vol_svc.len() {
    let o: Int = c.vol_svc[i];
    if o == svc {
      let a: Int = c.vol_off[i];
      let b: Int = c.vol_off[i + 1];
      let cur: Str = string.str_slice(c.vol_data, a, b);
      if string.str_compare(cur, name) == 0 { return true; }
    }
    i = i + 1;
  }
  return false;
}

fn _s_vol_count(c: &DockerCompose, svc: Int) -> Int {
  var k = 0;
  var i = 0;
  while i < c.vol_svc.len() {
    let o: Int = c.vol_svc[i];
    if o == svc { k = k + 1; }
    i = i + 1;
  }
  return k;
}

fn _s_vol_at(c: &DockerCompose, svc: Int, k: Int) -> Str {
  if k < 0 { return ""; }
  var seen = 0;
  var i = 0;
  while i < c.vol_svc.len() {
    let o: Int = c.vol_svc[i];
    if o == svc {
      if seen == k {
        let a: Int = c.vol_off[i];
        let b: Int = c.vol_off[i + 1];
        return string.str_slice(c.vol_data, a, b);
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

/// Attach network `name` to service `svc` (empty names and duplicates are
/// rejected). Returns the total attachment count.
pub fn compose_attach_network(c: &mut DockerCompose, svc: Int, name: Str) -> Result[Int, Str] {
  if svc < 0 || svc >= c.replicas.len() { return _s_err_int("compose: unknown service"); }
  if string.str_len(name) == 0 { return _s_err_int("compose: network name must not be empty"); }
  if _s_net_exists(c, svc, name) { return _s_err_int("compose: duplicate network"); }
  if c.net_svc.len() >= DOCKER_STACK_MAX_REFS * DOCKER_STACK_MAX_SERVICES {
    return _s_err_int("compose: network limit exceeded");
  }
  c.net_svc.push(svc);
  c.net_data = _s_blob_append(c.net_data, &mut c.net_off, name);
  return _s_ok_int(c.net_svc.len());
}

/// Number of networks attached to service `svc`, or DOCKER_NOT_FOUND (-1).
pub fn compose_network_count(c: &DockerCompose, svc: Int) -> Int {
  if svc < 0 || svc >= c.replicas.len() { return image.DOCKER_NOT_FOUND; }
  return _s_net_count(c, svc);
}

/// k-th network name of service `svc`, or "" when out of range.
pub fn compose_network_at(c: &DockerCompose, svc: Int, k: Int) -> Str {
  if svc < 0 || svc >= c.replicas.len() { return ""; }
  return _s_net_at(c, svc, k);
}

/// Attach volume `name` to service `svc` (empty names and duplicates are
/// rejected). Returns the total attachment count.
pub fn compose_attach_volume(c: &mut DockerCompose, svc: Int, name: Str) -> Result[Int, Str] {
  if svc < 0 || svc >= c.replicas.len() { return _s_err_int("compose: unknown service"); }
  if string.str_len(name) == 0 { return _s_err_int("compose: volume name must not be empty"); }
  if _s_vol_exists(c, svc, name) { return _s_err_int("compose: duplicate volume"); }
  if c.vol_svc.len() >= DOCKER_STACK_MAX_REFS * DOCKER_STACK_MAX_SERVICES {
    return _s_err_int("compose: volume limit exceeded");
  }
  c.vol_svc.push(svc);
  c.vol_data = _s_blob_append(c.vol_data, &mut c.vol_off, name);
  return _s_ok_int(c.vol_svc.len());
}

/// Number of volumes attached to service `svc`, or DOCKER_NOT_FOUND (-1).
pub fn compose_volume_count(c: &DockerCompose, svc: Int) -> Int {
  if svc < 0 || svc >= c.replicas.len() { return image.DOCKER_NOT_FOUND; }
  return _s_vol_count(c, svc);
}

/// k-th volume name of service `svc`, or "" when out of range.
pub fn compose_volume_at(c: &DockerCompose, svc: Int, k: Int) -> Str {
  if svc < 0 || svc >= c.replicas.len() { return ""; }
  return _s_vol_at(c, svc, k);
}
