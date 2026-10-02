// XIOM -- xiom.azure.compute: pure-XIOM Azure VM model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Models the virtual-machine surface the caller drives over its own
// transport:
//
//   * A pinned subset of documented VM sizes (name, vCPU count, memory MiB,
//     max data disks) with forward and reverse lookup.
//   * The ARM "PowerState/<state>" machine: parse, name, legal transitions,
//     start/deallocate predicates.
//   * Azure location names: display form ("West Europe") normalized to the
//     canonical form ("westeurope") against a pinned region subset.
//   * Resource tags as parallel name/value vectors: shape validation,
//     case-insensitive uniqueness and lookup.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure.compute

use xiom.azure.base;
use xiom.string;
use xiom.string.builder;

// VM power states (ARM instanceView status "PowerState/...").
pub const AZURE_VM_POWER_UNKNOWN: Int = -1;
pub const AZURE_VM_POWER_STARTING: Int = 0;
pub const AZURE_VM_POWER_RUNNING: Int = 1;
pub const AZURE_VM_POWER_STOPPING: Int = 2;
pub const AZURE_VM_POWER_STOPPED: Int = 3;
pub const AZURE_VM_POWER_DEALLOCATING: Int = 4;
pub const AZURE_VM_POWER_DEALLOCATED: Int = 5;
pub const AZURE_VM_POWER_RESTARTING: Int = 6;

/// One documented VM size.
pub type AzureVmSize = {
  name: Str;
  vcpus: Int;
  memory_mb: Int;
  max_data_disks: Int;
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

fn _ok_size(v: AzureVmSize) -> Result[AzureVmSize, Str] {
  return Ok(v);
}

fn _err_size(m: Str) -> Result[AzureVmSize, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Local helpers
// --------------------------------------------------

fn _streq(a: Str, b: Str) -> Bool {
  return base.azure_streq(a, b);
}

fn _streq_ci(a: Str, b: Str) -> Bool {
  return base.azure_streq_ignore_case(a, b);
}

// --------------------------------------------------
//  VM sizes (pinned documented subset)
// --------------------------------------------------

/// Look up a documented VM size by name (case-insensitive). Covers
/// Standard_B1s, Standard_B2s, Standard_D2s_v5, Standard_D4s_v5,
/// Standard_E2s_v5 and Standard_F2s_v2.
pub fn azure_vm_size_lookup(name: Str) -> Result[AzureVmSize, Str] {
  if _streq_ci(name, "Standard_B1s") {
    return _ok_size(AzureVmSize{ name: "Standard_B1s"; vcpus: 1; memory_mb: 1024; max_data_disks: 2; });
  }
  if _streq_ci(name, "Standard_B2s") {
    return _ok_size(AzureVmSize{ name: "Standard_B2s"; vcpus: 2; memory_mb: 4096; max_data_disks: 4; });
  }
  if _streq_ci(name, "Standard_D2s_v5") {
    return _ok_size(AzureVmSize{ name: "Standard_D2s_v5"; vcpus: 2; memory_mb: 8192; max_data_disks: 4; });
  }
  if _streq_ci(name, "Standard_D4s_v5") {
    return _ok_size(AzureVmSize{ name: "Standard_D4s_v5"; vcpus: 4; memory_mb: 16384; max_data_disks: 8; });
  }
  if _streq_ci(name, "Standard_E2s_v5") {
    return _ok_size(AzureVmSize{ name: "Standard_E2s_v5"; vcpus: 2; memory_mb: 16384; max_data_disks: 4; });
  }
  if _streq_ci(name, "Standard_F2s_v2") {
    return _ok_size(AzureVmSize{ name: "Standard_F2s_v2"; vcpus: 2; memory_mb: 4096; max_data_disks: 4; });
  }
  return _err_size("azure: unknown VM size: " + name);
}

/// Reverse lookup: first documented size whose shape matches, or "".
pub fn azure_vm_size_name_by_shape(vcpus: Int, memory_mb: Int) -> Str {
  if vcpus == 1 && memory_mb == 1024 {
    return "Standard_B1s";
  }
  if vcpus == 2 && memory_mb == 4096 {
    return "Standard_B2s";
  }
  if vcpus == 2 && memory_mb == 8192 {
    return "Standard_D2s_v5";
  }
  if vcpus == 4 && memory_mb == 16384 {
    return "Standard_D4s_v5";
  }
  if vcpus == 2 && memory_mb == 16384 {
    return "Standard_E2s_v5";
  }
  return "";
}

// --------------------------------------------------
//  Power-state machine
// --------------------------------------------------

/// Parse "PowerState/running" (prefix optional, case-insensitive) into an
/// AZURE_VM_POWER_* constant; an unrecognized state maps to UNKNOWN.
pub fn azure_vm_power_parse(s: Str) -> Int {
  let n = s.len();
  var start = 0;
  if n > 11 {
    let p = base.azure_substr(s, 0, 11);
    if _streq_ci(p, "PowerState/") {
      start = 11;
    }
  }
  let tail = base.azure_substr(s, start, n);
  if _streq_ci(tail, "starting") {
    return AZURE_VM_POWER_STARTING;
  }
  if _streq_ci(tail, "running") {
    return AZURE_VM_POWER_RUNNING;
  }
  if _streq_ci(tail, "stopping") {
    return AZURE_VM_POWER_STOPPING;
  }
  if _streq_ci(tail, "stopped") {
    return AZURE_VM_POWER_STOPPED;
  }
  if _streq_ci(tail, "deallocating") {
    return AZURE_VM_POWER_DEALLOCATING;
  }
  if _streq_ci(tail, "deallocated") {
    return AZURE_VM_POWER_DEALLOCATED;
  }
  if _streq_ci(tail, "restarting") {
    return AZURE_VM_POWER_RESTARTING;
  }
  return AZURE_VM_POWER_UNKNOWN;
}

/// Lowercase state name (UNKNOWN -> "unknown").
pub fn azure_vm_power_name(state: Int) -> Str {
  if state == AZURE_VM_POWER_STARTING {
    return "starting";
  }
  if state == AZURE_VM_POWER_RUNNING {
    return "running";
  }
  if state == AZURE_VM_POWER_STOPPING {
    return "stopping";
  }
  if state == AZURE_VM_POWER_STOPPED {
    return "stopped";
  }
  if state == AZURE_VM_POWER_DEALLOCATING {
    return "deallocating";
  }
  if state == AZURE_VM_POWER_DEALLOCATED {
    return "deallocated";
  }
  if state == AZURE_VM_POWER_RESTARTING {
    return "restarting";
  }
  return "unknown";
}

/// Legal state change. Equal states are an idempotent observation; a state of
/// UNKNOWN may move anywhere (and any state may be observed as UNKNOWN while
/// the platform reports transitional status).
pub fn azure_vm_power_transition(from: Int, to: Int) -> Bool {
  if from == to {
    return true;
  }
  if from == AZURE_VM_POWER_UNKNOWN || to == AZURE_VM_POWER_UNKNOWN {
    return true;
  }
  if from == AZURE_VM_POWER_STARTING {
    return to == AZURE_VM_POWER_RUNNING || to == AZURE_VM_POWER_STOPPED;
  }
  if from == AZURE_VM_POWER_RUNNING {
    return to == AZURE_VM_POWER_STOPPING || to == AZURE_VM_POWER_DEALLOCATING || to == AZURE_VM_POWER_RESTARTING;
  }
  if from == AZURE_VM_POWER_STOPPING {
    return to == AZURE_VM_POWER_STOPPED;
  }
  if from == AZURE_VM_POWER_STOPPED {
    return to == AZURE_VM_POWER_STARTING || to == AZURE_VM_POWER_DEALLOCATING;
  }
  if from == AZURE_VM_POWER_DEALLOCATING {
    return to == AZURE_VM_POWER_DEALLOCATED;
  }
  if from == AZURE_VM_POWER_DEALLOCATED {
    return to == AZURE_VM_POWER_STARTING;
  }
  if from == AZURE_VM_POWER_RESTARTING {
    return to == AZURE_VM_POWER_RUNNING;
  }
  return false;
}

/// True when a start request is meaningful (stopped or deallocated).
pub fn azure_vm_power_can_start(state: Int) -> Bool {
  if state == AZURE_VM_POWER_STOPPED {
    return true;
  }
  if state == AZURE_VM_POWER_DEALLOCATED {
    return true;
  }
  return false;
}

/// True when a deallocate request is meaningful (running or stopped).
pub fn azure_vm_power_can_deallocate(state: Int) -> Bool {
  if state == AZURE_VM_POWER_RUNNING {
    return true;
  }
  if state == AZURE_VM_POWER_STOPPED {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Locations
// --------------------------------------------------

/// Canonical location: ASCII lowercase with spaces, hyphens and underscores
/// removed ("West Europe" -> "westeurope").
pub fn azure_location_canonical(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    let is_gap = b == 32 || b == 45 || b == 95;
    if !is_gap {
      if b >= 65 && b <= 90 {
        out.push((b + 32) as UInt8);
      } else {
        out.push((b & 0xFF) as UInt8);
      }
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// True for the pinned region subset (canonical or display spelling).
pub fn azure_location_valid(s: Str) -> Bool {
  let c: Str = azure_location_canonical(s);
  if _streq(c, "eastus") {
    return true;
  }
  if _streq(c, "eastus2") {
    return true;
  }
  if _streq(c, "westus") {
    return true;
  }
  if _streq(c, "westus2") {
    return true;
  }
  if _streq(c, "westus3") {
    return true;
  }
  if _streq(c, "centralus") {
    return true;
  }
  if _streq(c, "northcentralus") {
    return true;
  }
  if _streq(c, "southcentralus") {
    return true;
  }
  if _streq(c, "northeurope") {
    return true;
  }
  if _streq(c, "westeurope") {
    return true;
  }
  if _streq(c, "uksouth") {
    return true;
  }
  if _streq(c, "germanywestcentral") {
    return true;
  }
  if _streq(c, "eastasia") {
    return true;
  }
  if _streq(c, "southeastasia") {
    return true;
  }
  if _streq(c, "japaneast") {
    return true;
  }
  if _streq(c, "australiaeast") {
    return true;
  }
  if _streq(c, "brazilsouth") {
    return true;
  }
  if _streq(c, "canadacentral") {
    return true;
  }
  if _streq(c, "centralindia") {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Tags
// --------------------------------------------------

// Tag name: 1..512 printable bytes without the Azure-reserved set.
fn _tag_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 512 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 32 || b == 127 {
      return false;
    }
    if b == 60 || b == 62 || b == 37 || b == 38 {
      return false;
    }
    if b == 92 || b == 63 || b == 47 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Validate parallel tag vectors: equal arity, valid names (1..512),
/// values up to 256 bytes and case-insensitively unique names.
pub fn azure_tags_valid(names: &Vec[Str], values: &Vec[Str]) -> Bool {
  if names.len() != values.len() {
    return false;
  }
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let vl: Str = values[i];
    if !_tag_name_valid(nm) {
      return false;
    }
    if vl.len() > 256 {
      return false;
    }
    var j = 0;
    while j < i {
      let other: Str = names[j];
      if _streq_ci(other, nm) {
        return false;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

/// Case-insensitive tag lookup; Err("azure: tag not found: <key>") when
/// absent (or "azure: tag vectors arity mismatch" for broken parallel lists).
pub fn azure_tags_get(names: &Vec[Str], values: &Vec[Str], key: Str) -> Result[Str, Str] {
  if names.len() != values.len() {
    return _err_str("azure: tag vectors arity mismatch");
  }
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    if _streq_ci(nm, key) {
      let v: Str = values[i];
      return _ok_str(v);
    }
    i = i + 1;
  }
  return _err_str("azure: tag not found: " + key);
}
