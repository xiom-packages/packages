// XIOM -- xiom.gcp.compute: Compute Engine model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the GCE surface: the instance lifecycle state machine,
// machine-type name decomposition, instance naming and the metadata
// key/value shape. No network, no FFI, no clocks.
//
// Documented subset:
//   * statuses: PROVISIONING -> STAGING -> RUNNING; RUNNING -> STOPPING /
//     SUSPENDING / REPAIRING; STOPPING -> TERMINATED; SUSPENDING -> SUSPENDED;
//     SUSPENDED -> RUNNING; REPAIRING -> RUNNING / TERMINATED;
//     TERMINATED -> PROVISIONING (restart). All other pairs are false.
//   * machine types: `{family}-{series}-{size}` with the family drawn from a
//     fixed list (e2, n1, n2, n2d, c2, c2d, c3, c3d, t2d, t2a, m1, m2, m3, a2,
//     a3, g2, custom); missing segments stay "".
//   * instance names: DNS-1035 labels (1..63, lowercase letter first, letter
//     or digit last, lowercase letters/digits/hyphens inside).
//   * metadata keys: 1..128, lowercase letter first, lowercase
//     letters/digits/hyphens, letter or digit last, not starting with
//     "google" or "ssh-keys"; values up to 262144 bytes.
//
// v0.62.2 discipline: free functions only; Str equality via
// xiom.string.compare; bounded loops.

module xiom.gcp.compute

use xiom.gcp.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Instance statuses
// --------------------------------------------------

/// Unspecified status (0).
pub const GCE_STATUS_UNSPECIFIED: Int = 0;

/// PROVISIONING (1).
pub const GCE_STATUS_PROVISIONING: Int = 1;

/// STAGING (2).
pub const GCE_STATUS_STAGING: Int = 2;

/// RUNNING (3).
pub const GCE_STATUS_RUNNING: Int = 3;

/// STOPPING (4).
pub const GCE_STATUS_STOPPING: Int = 4;

/// SUSPENDING (5).
pub const GCE_STATUS_SUSPENDING: Int = 5;

/// SUSPENDED (6).
pub const GCE_STATUS_SUSPENDED: Int = 6;

/// REPAIRING (7).
pub const GCE_STATUS_REPAIRING: Int = 7;

/// TERMINATED (8).
pub const GCE_STATUS_TERMINATED: Int = 8;

/// Highest modeled status code (8).
pub const GCE_STATUS_MAX: Int = 8;

/// Maximum metadata key length (128).
pub const GCE_METADATA_KEY_MAX: Int = 128;

/// Maximum metadata value length in bytes (262144).
pub const GCE_METADATA_VALUE_MAX: Int = 262144;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// A machine type decomposed as `{family}-{series}-{size}`; absent segments
/// are "".
pub type GceMachineType = {
  family: Str;
  series: Str;
  size: Str;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_mt(v: GceMachineType) -> Result[GceMachineType, Str] {
  return Ok(v);
}

fn _err_mt(m: Str) -> Result[GceMachineType, Str] {
  return Err(m);
}

// --------------------------------------------------
//  State machine
// --------------------------------------------------

/// Map a status name to its GCE_STATUS_* code (0 = unspecified/unknown).
/// Params: name - the status name. Complexity O(name.len()).
pub fn gce_status_code(name: Str) -> Int {
  if core.gcp_str_eq(name, "PROVISIONING") {
    return GCE_STATUS_PROVISIONING;
  }
  if core.gcp_str_eq(name, "STAGING") {
    return GCE_STATUS_STAGING;
  }
  if core.gcp_str_eq(name, "RUNNING") {
    return GCE_STATUS_RUNNING;
  }
  if core.gcp_str_eq(name, "STOPPING") {
    return GCE_STATUS_STOPPING;
  }
  if core.gcp_str_eq(name, "SUSPENDING") {
    return GCE_STATUS_SUSPENDING;
  }
  if core.gcp_str_eq(name, "SUSPENDED") {
    return GCE_STATUS_SUSPENDED;
  }
  if core.gcp_str_eq(name, "REPAIRING") {
    return GCE_STATUS_REPAIRING;
  }
  if core.gcp_str_eq(name, "TERMINATED") {
    return GCE_STATUS_TERMINATED;
  }
  return GCE_STATUS_UNSPECIFIED;
}

/// Canonical status name for a code. Params: code - a GCE_STATUS_* code.
/// Returns the name or an "unknown status code" error. Complexity O(1).
pub fn gce_status_name(code: Int) -> Result[Str, Str] {
  if code == GCE_STATUS_PROVISIONING {
    return _ok_str("PROVISIONING");
  }
  if code == GCE_STATUS_STAGING {
    return _ok_str("STAGING");
  }
  if code == GCE_STATUS_RUNNING {
    return _ok_str("RUNNING");
  }
  if code == GCE_STATUS_STOPPING {
    return _ok_str("STOPPING");
  }
  if code == GCE_STATUS_SUSPENDING {
    return _ok_str("SUSPENDING");
  }
  if code == GCE_STATUS_SUSPENDED {
    return _ok_str("SUSPENDED");
  }
  if code == GCE_STATUS_REPAIRING {
    return _ok_str("REPAIRING");
  }
  if code == GCE_STATUS_TERMINATED {
    return _ok_str("TERMINATED");
  }
  if code == GCE_STATUS_UNSPECIFIED {
    return _ok_str("UNSPECIFIED");
  }
  return _err_str("gcp: unknown instance status code: " + core.gcp_int_str(code));
}

/// True when the modeled GCE lifecycle allows `from -> to`. Params: from, to -
/// GCE_STATUS_* codes. Complexity O(1).
pub fn gce_transition_allowed(from: Int, to: Int) -> Bool {
  if from == GCE_STATUS_PROVISIONING && to == GCE_STATUS_STAGING {
    return true;
  }
  if from == GCE_STATUS_STAGING && to == GCE_STATUS_RUNNING {
    return true;
  }
  if from == GCE_STATUS_RUNNING && to == GCE_STATUS_STOPPING {
    return true;
  }
  if from == GCE_STATUS_RUNNING && to == GCE_STATUS_SUSPENDING {
    return true;
  }
  if from == GCE_STATUS_RUNNING && to == GCE_STATUS_REPAIRING {
    return true;
  }
  if from == GCE_STATUS_STOPPING && to == GCE_STATUS_TERMINATED {
    return true;
  }
  if from == GCE_STATUS_SUSPENDING && to == GCE_STATUS_SUSPENDED {
    return true;
  }
  if from == GCE_STATUS_SUSPENDED && to == GCE_STATUS_RUNNING {
    return true;
  }
  if from == GCE_STATUS_REPAIRING && to == GCE_STATUS_RUNNING {
    return true;
  }
  if from == GCE_STATUS_REPAIRING && to == GCE_STATUS_TERMINATED {
    return true;
  }
  if from == GCE_STATUS_TERMINATED && to == GCE_STATUS_PROVISIONING {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Machine types
// --------------------------------------------------

/// True for a family in the modeled machine-type list. Params: family - the
/// candidate family. Complexity O(family.len()).
pub fn gce_machine_family_is_known(family: Str) -> Bool {
  if core.gcp_str_eq(family, "e2") {
    return true;
  }
  if core.gcp_str_eq(family, "n1") {
    return true;
  }
  if core.gcp_str_eq(family, "n2") {
    return true;
  }
  if core.gcp_str_eq(family, "n2d") {
    return true;
  }
  if core.gcp_str_eq(family, "c2") {
    return true;
  }
  if core.gcp_str_eq(family, "c2d") {
    return true;
  }
  if core.gcp_str_eq(family, "c3") {
    return true;
  }
  if core.gcp_str_eq(family, "c3d") {
    return true;
  }
  if core.gcp_str_eq(family, "t2d") {
    return true;
  }
  if core.gcp_str_eq(family, "t2a") {
    return true;
  }
  if core.gcp_str_eq(family, "m1") {
    return true;
  }
  if core.gcp_str_eq(family, "m2") {
    return true;
  }
  if core.gcp_str_eq(family, "m3") {
    return true;
  }
  if core.gcp_str_eq(family, "a2") {
    return true;
  }
  if core.gcp_str_eq(family, "a3") {
    return true;
  }
  if core.gcp_str_eq(family, "g2") {
    return true;
  }
  if core.gcp_str_eq(family, "custom") {
    return true;
  }
  return false;
}

/// True for a documented-subset machine type: 1..64 characters, a known family
/// before the first dash, lowercase letters/digits/hyphens only, no leading or
/// trailing dash. Params: machine_type - the candidate. Complexity O(len).
pub fn gce_machine_type_is_valid(machine_type: Str) -> Bool {
  let n = machine_type.len();
  if n < 1 {
    return false;
  }
  if n > 64 {
    return false;
  }
  let first = core.gcp_byte(machine_type, 0);
  if !core.gcp_is_alnum_lower(first) {
    return false;
  }
  let last = core.gcp_byte(machine_type, n - 1);
  if !core.gcp_is_alnum_lower(last) {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(machine_type, i);
    if !core.gcp_is_alnum_lower(c) {
      if c != 45 {
        return false;
      }
    }
    i = i + 1;
  }
  let dash = core.gcp_index_of_char(machine_type, 0, n, 45);
  if dash < 0 {
    return gce_machine_family_is_known(machine_type);
  }
  let family = core.gcp_substr(machine_type, 0, dash);
  return gce_machine_family_is_known(family);
}

/// Decompose a machine type into family / series / size. Params: machine_type
/// - the type name. Returns the GceMachineType or an "invalid machine type"
/// error. Complexity O(machine_type.len()).
pub fn gce_machine_type_parse(machine_type: Str) -> Result[GceMachineType, Str] {
  if !gce_machine_type_is_valid(machine_type) {
    return _err_mt("gcp: invalid machine type: " + machine_type);
  }
  let n = machine_type.len();
  let d1 = core.gcp_index_of_char(machine_type, 0, n, 45);
  if d1 < 0 {
    let whole = GceMachineType{ family: machine_type; series: ""; size: ""; };
    return _ok_mt(whole);
  }
  let family = core.gcp_substr(machine_type, 0, d1);
  let d2 = core.gcp_index_of_char(machine_type, d1 + 1, n, 45);
  if d2 < 0 {
    let two = GceMachineType{ family: family; series: core.gcp_substr(machine_type, d1 + 1, n); size: ""; };
    return _ok_mt(two);
  }
  let three = GceMachineType{
    family: family;
    series: core.gcp_substr(machine_type, d1 + 1, d2);
    size: core.gcp_substr(machine_type, d2 + 1, n);
  };
  return _ok_mt(three);
}

// Path leaf check: non-empty, 1..63, no '/'.
fn _gce_path_segment_is_valid(seg: Str) -> Bool {
  let n = seg.len();
  if n < 1 {
    return false;
  }
  if n > 63 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(seg, i);
    if c == 47 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// `projects/{project}/zones/{zone}/machineTypes/{machine_type}`. Params:
/// project, zone, machine_type - the path parts. Returns the path or the first
/// validation error. Complexity O(total length).
pub fn gce_machine_type_path(project: Str, zone: Str, machine_type: Str) -> Result[Str, Str] {
  if !_gce_path_segment_is_valid(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !_gce_path_segment_is_valid(zone) {
    return _err_str("gcp: invalid zone: " + zone);
  }
  if !gce_machine_type_is_valid(machine_type) {
    return _err_str("gcp: invalid machine type: " + machine_type);
  }
  return _ok_str("projects/" + project + "/zones/" + zone + "/machineTypes/" + machine_type);
}

// --------------------------------------------------
//  Instances and metadata
// --------------------------------------------------

/// True for a documented-subset instance name (a DNS-1035 label). Params: name
/// - the candidate. Complexity O(name.len()).
pub fn gce_instance_name_is_valid(name: Str) -> Bool {
  return core.gcp_is_rfc1035_label(name);
}

/// `projects/{project}/zones/{zone}/instances/{name}`. Params: project - the
/// project id; zone - the zone; name - the instance name. Returns the path or
/// the first validation error. Complexity O(total length).
pub fn gce_instance_path(project: Str, zone: Str, name: Str) -> Result[Str, Str] {
  if !_gce_path_segment_is_valid(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !_gce_path_segment_is_valid(zone) {
    return _err_str("gcp: invalid zone: " + zone);
  }
  if !gce_instance_name_is_valid(name) {
    return _err_str("gcp: invalid instance name: " + name);
  }
  return _ok_str("projects/" + project + "/zones/" + zone + "/instances/" + name);
}

/// True for a documented-subset GCE metadata key. Params: key - the candidate.
/// Complexity O(key.len()).
pub fn gce_metadata_key_is_valid(key: Str) -> Bool {
  let n = key.len();
  if n < 1 {
    return false;
  }
  if n > GCE_METADATA_KEY_MAX {
    return false;
  }
  let first = core.gcp_byte(key, 0);
  if !core.gcp_is_lower_alpha(first) {
    return false;
  }
  let last = core.gcp_byte(key, n - 1);
  if !core.gcp_is_alnum_lower(last) {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(key, i);
    if !core.gcp_is_alnum_lower(c) {
      if c != 45 {
        return false;
      }
    }
    i = i + 1;
  }
  if core.gcp_starts_with(key, "google") {
    return false;
  }
  if core.gcp_starts_with(key, "ssh-keys") {
    return false;
  }
  return true;
}

/// Validate one metadata key/value pair. Params: key - the metadata key;
/// value - the metadata value. Returns Ok("") or the first error. Complexity
/// O(key.len()+value.len()).
pub fn gce_metadata_validate(key: Str, value: Str) -> Result[Str, Str] {
  if !gce_metadata_key_is_valid(key) {
    return _err_str("gcp: invalid metadata key: " + key);
  }
  if value.len() > GCE_METADATA_VALUE_MAX {
    return _err_str("gcp: metadata value too long: " + key);
  }
  return _ok_str("");
}
