// XIOM -- xiom.azure.arm: pure-XIOM Azure Resource Manager resource-id model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Parses and builds canonical ARM resource ids:
//
//   /subscriptions/{sub}
//   /subscriptions/{sub}/resourceGroups/{rg}
//   /subscriptions/{sub}/resourceGroups/{rg}/providers/{ns}/{type}/{name}
//   .../{type}/{name}/{childType}/{childName}...
//
// The keywords `subscriptions`, `resourceGroups` and `providers` are matched
// case-insensitively (ARM ids are case-insensitive); names keep their original
// casing. Type/name pairs are position-dependent: the odd segments after the
// namespace form the type path, the even segments the resource name. A
// provider root (namespace only) is not a resource and is rejected.
//
// Scope subset: subscription, resource group and named resource (the model
// does not cover extension resources or tenant-level ids).
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure.arm

use xiom.azure.base;
use xiom.string;

// Scope kinds (ArmResourceId.scope).
pub const AZURE_ARM_SCOPE_SUBSCRIPTION: Int = 0;
pub const AZURE_ARM_SCOPE_RESOURCE_GROUP: Int = 1;
pub const AZURE_ARM_SCOPE_RESOURCE: Int = 2;

/// One parsed ARM resource id. `namespace`, `type_path`, `resource_name` and
/// `parent_id` are "" for subscription / resource-group scopes. `type_path`
/// and `resource_name` each join their slash-separated segments with '/'.
pub type ArmResourceId = {
  subscription: Str;
  resource_group: Str;
  namespace: Str;
  type_path: Str;
  resource_name: Str;
  parent_id: Str;
  scope: Int;
  raw: Str;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_rid(v: ArmResourceId) -> Result[ArmResourceId, Str] {
  return Ok(v);
}

fn _err_rid(m: Str) -> Result[ArmResourceId, Str] {
  return Err(m);
}

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
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

// One ARM name segment: 1..260 printable ASCII bytes, without the reserved
// characters '/', '\', '?', '#', '%', '&', '<', '>', '*', ':', '|', '=',
// '"', '\''. Dots and hyphens are allowed (namespaces, child types).
fn _arm_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n == 0 || n > 260 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 33 || b > 126 {
      return false;
    }
    if b == 47 || b == 92 || b == 63 || b == 35 || b == 37 {
      return false;
    }
    if b == 38 || b == 60 || b == 62 || b == 42 || b == 58 {
      return false;
    }
    if b == 124 || b == 61 || b == 34 || b == 39 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Split `body` (no leading '/') on '/'; false when any segment is empty.
fn _segments(body: Str, out: &mut Vec[Str]) -> Bool {
  let n = body.len();
  var start = 0;
  var i = 0;
  while i <= n {
    var boundary = false;
    if i == n {
      boundary = true;
    } else {
      let b: Int = (string.byte_at(body, i) as Int) & 0xFF;
      if b == 47 {
        boundary = true;
      }
    }
    if boundary {
      if i == start {
        return false;
      }
      out.push(base.azure_substr(body, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
  return true;
}

// Join `count` segments starting at `from`, taking every `stride`-th one.
fn _join_sub(segs: &Vec[Str], from: Int, count: Int, stride: Int, sep: Str) -> Str {
  var out = "";
  var i = 0;
  while i < count {
    let s: Str = segs[from + i * stride];
    if i > 0 {
      out = out + sep;
    }
    out = out + s;
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Parse
// --------------------------------------------------

/// Parse a canonical ARM resource id. Returns Err("azure: ...") for a missing
/// leading '/', empty segments, an unexpected keyword, a provider root or a
/// dangling type without a name.
pub fn azure_arm_parse(id: Str) -> Result[ArmResourceId, Str] {
  if id.len() == 0 {
    return _err_rid("azure: empty resource id");
  }
  if id.len() > 1024 {
    return _err_rid("azure: resource id too long");
  }
  let lead: Int = (string.byte_at(id, 0) as Int) & 0xFF;
  if lead != 47 {
    return _err_rid("azure: resource id must start with '/'");
  }
  let body = base.azure_substr(id, 1, id.len());
  var segs = Vec[Str].new();
  let ok_segs = _segments(body, &mut segs);
  if !ok_segs {
    return _err_rid("azure: empty path segment");
  }
  let n = segs.len();
  if n < 2 {
    return _err_rid("azure: expected /subscriptions/{id}");
  }
  let s0: Str = segs[0];
  if !_streq_ci(s0, "subscriptions") {
    return _err_rid("azure: expected /subscriptions/{id}");
  }
  let sub: Str = segs[1];
  if !_arm_name_valid(sub) {
    return _err_rid("azure: invalid subscription id");
  }
  var i = 2;
  var rg = "";
  var scope = AZURE_ARM_SCOPE_SUBSCRIPTION;
  if i < n {
    let key: Str = segs[i];
    if _streq_ci(key, "resourcegroups") {
      if i + 2 > n {
        return _err_rid("azure: resourceGroups requires a name");
      }
      let rgn: Str = segs[i + 1];
      if !_arm_name_valid(rgn) {
        return _err_rid("azure: invalid resource group name");
      }
      rg = rgn;
      scope = AZURE_ARM_SCOPE_RESOURCE_GROUP;
      i = i + 2;
    }
  }
  if i == n {
    return _ok_rid(ArmResourceId{
      subscription: sub;
      resource_group: rg;
      namespace: "";
      type_path: "";
      resource_name: "";
      parent_id: "";
      scope: scope;
      raw: id;
    });
  }
  let pk: Str = segs[i];
  if !_streq_ci(pk, "providers") {
    return _err_rid("azure: expected providers segment");
  }
  if i + 2 > n {
    return _err_rid("azure: providers requires a namespace");
  }
  let ns: Str = segs[i + 1];
  if !_arm_name_valid(ns) {
    return _err_rid("azure: invalid provider namespace");
  }
  let base_i = i + 2;
  let rem = n - base_i;
  if rem == 0 {
    return _err_rid("azure: provider scope has no resource type");
  }
  if rem % 2 != 0 {
    return _err_rid("azure: resource id must end with a name");
  }
  let pairs = rem / 2;
  var j = 0;
  while j < rem {
    let segv: Str = segs[base_i + j];
    if !_arm_name_valid(segv) {
      return _err_rid("azure: invalid resource segment: " + segv);
    }
    j = j + 1;
  }
  let tp = _join_sub(&segs, base_i, pairs, 2, "/");
  let rn = _join_sub(&segs, base_i + 1, pairs, 2, "/");
  var parent = "/subscriptions/" + sub + "/resourceGroups/" + rg + "/providers/" + ns;
  if pairs > 1 {
    parent = parent + "/" + _join_sub(&segs, base_i, pairs - 1, 2, "/") + "/" + _join_sub(&segs, base_i + 1, pairs - 1, 2, "/");
  }
  return _ok_rid(ArmResourceId{
    subscription: sub;
    resource_group: rg;
    namespace: ns;
    type_path: tp;
    resource_name: rn;
    parent_id: parent;
    scope: AZURE_ARM_SCOPE_RESOURCE;
    raw: id;
  });
}

// --------------------------------------------------
//  Build
// --------------------------------------------------

/// Build a canonical resource id from its parts. `type_path` and
/// `resource_name` must have the same number of slash-separated segments
/// (>= 1) and every segment must be a valid ARM name.
pub fn azure_arm_resource_id(subscription: Str, resource_group: Str, namespace: Str, type_path: Str, resource_name: Str) -> Result[Str, Str] {
  if !_arm_name_valid(subscription) {
    return _err_str("azure: invalid subscription id");
  }
  if !_arm_name_valid(resource_group) {
    return _err_str("azure: invalid resource group name");
  }
  if !_arm_name_valid(namespace) {
    return _err_str("azure: invalid provider namespace");
  }
  var types = Vec[Str].new();
  let ok_types = _segments(type_path, &mut types);
  if !ok_types {
    return _err_str("azure: invalid type path");
  }
  var names = Vec[Str].new();
  let ok_names = _segments(resource_name, &mut names);
  if !ok_names {
    return _err_str("azure: invalid resource name");
  }
  if types.len() != names.len() {
    return _err_str("azure: type/name segment count mismatch");
  }
  var i = 0;
  while i < types.len() {
    let tv: Str = types[i];
    let nv: Str = names[i];
    if !_arm_name_valid(tv) {
      return _err_str("azure: invalid type segment: " + tv);
    }
    if !_arm_name_valid(nv) {
      return _err_str("azure: invalid name segment: " + nv);
    }
    i = i + 1;
  }
  i = 0;
  var path = "";
  while i < types.len() {
    let tv: Str = types[i];
    let nv: Str = names[i];
    path = path + "/" + tv + "/" + nv;
    i = i + 1;
  }
  return _ok_str("/subscriptions/" + subscription + "/resourceGroups/" + resource_group + "/providers/" + namespace + path);
}

// --------------------------------------------------
//  Scope helpers
// --------------------------------------------------

/// Human-readable scope name: subscription / resource_group / resource.
pub fn azure_arm_scope_name(scope: Int) -> Str {
  if scope == AZURE_ARM_SCOPE_SUBSCRIPTION {
    return "subscription";
  }
  if scope == AZURE_ARM_SCOPE_RESOURCE_GROUP {
    return "resource_group";
  }
  if scope == AZURE_ARM_SCOPE_RESOURCE {
    return "resource";
  }
  return "unknown";
}

/// "/subscriptions/{sub}" scope string, or Err for an invalid subscription.
pub fn azure_arm_subscription_scope(subscription: Str) -> Result[Str, Str] {
  if !_arm_name_valid(subscription) {
    return _err_str("azure: invalid subscription id");
  }
  return _ok_str("/subscriptions/" + subscription);
}

/// "/subscriptions/{sub}/resourceGroups/{rg}" scope string, or Err.
pub fn azure_arm_resource_group_scope(subscription: Str, resource_group: Str) -> Result[Str, Str] {
  if !_arm_name_valid(subscription) {
    return _err_str("azure: invalid subscription id");
  }
  if !_arm_name_valid(resource_group) {
    return _err_str("azure: invalid resource group name");
  }
  return _ok_str("/subscriptions/" + subscription + "/resourceGroups/" + resource_group);
}
