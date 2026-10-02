// XIOM -- xiom.docker.resources: named volume and network sets
// Port task: replace the xiom.docker placeholder with a real, tested,
// pure-XIOM package (no FFI, no HTTP, no sockets, no daemon).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: volumes and networks as named sets. Every entry has a name, a
// driver and a removed flag; removal never releases the name, so ids stay
// stable and a removed entry can still be inspected (a second remove is an
// error, not a silent success). Live counts exclude removed entries.
//
// Names and drivers are stored as Str blobs with a monotone Vec[Int] offset
// table (never Vec[Str]); all four blobs and the two removed vectors are
// pushed in lockstep so parallel structures can never drift.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err only inside
// the _res_ok_int/_res_err_int leaf helpers; typed locals on every Vec[Int]
// element read; no `==` on Str (string.str_compare everywhere); no
// Vec[StructType]; bounded loops.

module xiom.docker.resources

use xiom.string;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Capacity guard: entries per volume set and per network set.
pub const DOCKER_STACK_MAX_RES: Int = 128;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// A named volume/network set: names and drivers as Str blobs, plus a
/// parallel removed flag per entry (1 = removed, names stay reserved).
/// Fields are implementation detail; use the resources_* accessors.
pub type DockerResources = {
  vol_data: Str;
  vol_off: Vec[Int];
  vol_driver_data: Str;
  vol_driver_off: Vec[Int];
  vol_removed: Vec[Int];
  net_data: Str;
  net_off: Vec[Int];
  net_driver_data: Str;
  net_driver_off: Vec[Int];
  net_removed: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _res_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _res_err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Blob helper (Str + monotone Vec[Int] offsets; no Vec[Str])
// ---------------------------------------------------------------------------

// Append `s` to a blob; offs must be non-empty with offs[last] ==
// string.str_len(data). Returns the extended data string.
fn _res_blob_append(data: Str, offs: &mut Vec[Int], s: Str) -> Str {
  let start: Int = offs[offs.len() - 1];
  offs.push(start + string.str_len(s));
  return data + s;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Empty volume/network set. Complexity: O(1).
pub fn resources_new() -> DockerResources {
  var vol_off = Vec[Int].new();
  vol_off.push(0);
  var vol_driver_off = Vec[Int].new();
  vol_driver_off.push(0);
  var net_off = Vec[Int].new();
  net_off.push(0);
  var net_driver_off = Vec[Int].new();
  net_driver_off.push(0);
  return DockerResources{
    vol_data: "";
    vol_off: vol_off;
    vol_driver_data: "";
    vol_driver_off: vol_driver_off;
    vol_removed: Vec[Int].new();
    net_data: "";
    net_off: net_off;
    net_driver_data: "";
    net_driver_off: net_driver_off;
    net_removed: Vec[Int].new();
  };
}

// Slot of volume `name`, or -1.
fn _res_vol_find(r: &DockerResources, name: Str) -> Int {
  var i = 0;
  let cnt = r.vol_off.len() - 1;
  while i < cnt {
    let a: Int = r.vol_off[i];
    let b: Int = r.vol_off[i + 1];
    let cur: Str = string.str_slice(r.vol_data, a, b);
    if string.str_compare(cur, name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// Slot of network `name`, or -1.
fn _res_net_find(r: &DockerResources, name: Str) -> Int {
  var i = 0;
  let cnt = r.net_off.len() - 1;
  while i < cnt {
    let a: Int = r.net_off[i];
    let b: Int = r.net_off[i + 1];
    let cur: Str = string.str_slice(r.net_data, a, b);
    if string.str_compare(cur, name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Volumes
// ---------------------------------------------------------------------------

/// Create a volume; the name must be non-empty and unique (removed names
/// stay reserved). Returns the dense index.
pub fn resources_add_volume(r: &mut DockerResources, name: Str, driver: Str) -> Result[Int, Str] {
  if string.str_len(name) == 0 { return _res_err_int("volume: name must not be empty"); }
  if string.str_len(driver) == 0 { return _res_err_int("volume: driver must not be empty"); }
  if _res_vol_find(r, name) >= 0 { return _res_err_int("volume: duplicate name"); }
  let cnt = r.vol_removed.len();
  if cnt >= DOCKER_STACK_MAX_RES { return _res_err_int("volume: limit exceeded"); }
  r.vol_data = _res_blob_append(r.vol_data, &mut r.vol_off, name);
  r.vol_driver_data = _res_blob_append(r.vol_driver_data, &mut r.vol_driver_off, driver);
  r.vol_removed.push(0);
  return _res_ok_int(cnt);
}

/// Remove a live volume by name; the name is never released. Returns the
/// live volume count.
pub fn resources_remove_volume(r: &mut DockerResources, name: Str) -> Result[Int, Str] {
  let idx = _res_vol_find(r, name);
  if idx < 0 { return _res_err_int("volume: not found"); }
  let rm: Int = r.vol_removed[idx];
  if rm == 1 { return _res_err_int("volume: already removed"); }
  r.vol_removed[idx] = 1;
  var live = 0;
  var i = 0;
  while i < r.vol_removed.len() {
    let v: Int = r.vol_removed[i];
    if v == 0 { live = live + 1; }
    i = i + 1;
  }
  return _res_ok_int(live);
}

/// True when a live volume with `name` exists.
pub fn resources_volume_exists(r: &DockerResources, name: Str) -> Bool {
  let idx = _res_vol_find(r, name);
  if idx < 0 { return false; }
  let rm: Int = r.vol_removed[idx];
  return rm == 0;
}

/// True when the volume slot exists and is removed.
pub fn resources_volume_removed(r: &DockerResources, name: Str) -> Bool {
  let idx = _res_vol_find(r, name);
  if idx < 0 { return false; }
  let rm: Int = r.vol_removed[idx];
  return rm == 1;
}

/// Live volume count. Complexity: O(n).
pub fn resources_volume_count(r: &DockerResources) -> Int {
  var k = 0;
  var i = 0;
  while i < r.vol_removed.len() {
    let v: Int = r.vol_removed[i];
    if v == 0 { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// Total volume slots (including removed). Complexity: O(1).
pub fn resources_volume_total(r: &DockerResources) -> Int { return r.vol_removed.len(); }

/// Volume name at `i`, or "" when out of range.
pub fn resources_volume_name(r: &DockerResources, i: Int) -> Str {
  if i < 0 || i >= r.vol_removed.len() { return ""; }
  let a: Int = r.vol_off[i];
  let b: Int = r.vol_off[i + 1];
  return string.str_slice(r.vol_data, a, b);
}

/// Volume driver at `i`, or "" when out of range.
pub fn resources_volume_driver(r: &DockerResources, i: Int) -> Str {
  if i < 0 || i >= r.vol_removed.len() { return ""; }
  let a: Int = r.vol_driver_off[i];
  let b: Int = r.vol_driver_off[i + 1];
  return string.str_slice(r.vol_driver_data, a, b);
}

// ---------------------------------------------------------------------------
// Networks
// ---------------------------------------------------------------------------

/// Create a network; the name must be non-empty and unique (removed names
/// stay reserved). Returns the dense index.
pub fn resources_add_network(r: &mut DockerResources, name: Str, driver: Str) -> Result[Int, Str] {
  if string.str_len(name) == 0 { return _res_err_int("network: name must not be empty"); }
  if string.str_len(driver) == 0 { return _res_err_int("network: driver must not be empty"); }
  if _res_net_find(r, name) >= 0 { return _res_err_int("network: duplicate name"); }
  let cnt = r.net_removed.len();
  if cnt >= DOCKER_STACK_MAX_RES { return _res_err_int("network: limit exceeded"); }
  r.net_data = _res_blob_append(r.net_data, &mut r.net_off, name);
  r.net_driver_data = _res_blob_append(r.net_driver_data, &mut r.net_driver_off, driver);
  r.net_removed.push(0);
  return _res_ok_int(cnt);
}

/// Remove a live network by name; the name is never released. Returns the
/// live network count.
pub fn resources_remove_network(r: &mut DockerResources, name: Str) -> Result[Int, Str] {
  let idx = _res_net_find(r, name);
  if idx < 0 { return _res_err_int("network: not found"); }
  let rm: Int = r.net_removed[idx];
  if rm == 1 { return _res_err_int("network: already removed"); }
  r.net_removed[idx] = 1;
  var live = 0;
  var i = 0;
  while i < r.net_removed.len() {
    let v: Int = r.net_removed[i];
    if v == 0 { live = live + 1; }
    i = i + 1;
  }
  return _res_ok_int(live);
}

/// True when a live network with `name` exists.
pub fn resources_network_exists(r: &DockerResources, name: Str) -> Bool {
  let idx = _res_net_find(r, name);
  if idx < 0 { return false; }
  let rm: Int = r.net_removed[idx];
  return rm == 0;
}

/// Live network count. Complexity: O(n).
pub fn resources_network_count(r: &DockerResources) -> Int {
  var k = 0;
  var i = 0;
  while i < r.net_removed.len() {
    let v: Int = r.net_removed[i];
    if v == 0 { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// Total network slots (including removed). Complexity: O(1).
pub fn resources_network_total(r: &DockerResources) -> Int { return r.net_removed.len(); }

/// Network name at `i`, or "" when out of range.
pub fn resources_network_name(r: &DockerResources, i: Int) -> Str {
  if i < 0 || i >= r.net_removed.len() { return ""; }
  let a: Int = r.net_off[i];
  let b: Int = r.net_off[i + 1];
  return string.str_slice(r.net_data, a, b);
}

/// Network driver at `i`, or "" when out of range.
pub fn resources_network_driver(r: &DockerResources, i: Int) -> Str {
  if i < 0 || i >= r.net_removed.len() { return ""; }
  let a: Int = r.net_driver_off[i];
  let b: Int = r.net_driver_off[i + 1];
  return string.str_slice(r.net_driver_data, a, b);
}
