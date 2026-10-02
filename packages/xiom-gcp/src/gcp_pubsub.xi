// XIOM -- xiom.gcp.pubsub: Pub/Sub model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the Pub/Sub surface: topic/subscription resource names,
// publish-message validation over caller-owned parallel vectors (including the
// reserved "goog" attribute prefix), ack-id shape, the 10..600 s ack deadline
// with clamping/extension, and the pull/push subscription configuration.
// No network, no FFI, no clocks.
//
// Documented subset:
//   * topic/subscription names: 3..255 characters, a letter first, then
//     ASCII letters/digits/'-'/'_'/'.'/'~'/'+'/'%'.
//   * message data: 1 byte .. 10000000 bytes; at most 100 attributes, names
//     1..256 bytes not starting (case-insensitively) with "goog", values up
//     to 1024 bytes; ordering keys up to 1024 bytes without the reserved
//     prefix.
//   * ack ids: 1..1024 printable non-space ASCII bytes.
//   * ack deadline: 10..600 s, clamped into range; extension adds to the
//     current deadline and caps at 600 s.
//   * subscriptions: PULL (no push endpoint) or PUSH (https endpoint),
//     retention 600..604800 s (10 min .. 7 days).
//
// v0.62.2 discipline: free functions only; Str equality via
// xiom.string.compare; bounded loops.

module xiom.gcp.pubsub

use xiom.gcp.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Minimum resource-name length (3).
pub const PS_NAME_MIN: Int = 3;

/// Maximum resource-name length (255).
pub const PS_NAME_MAX: Int = 255;

/// Maximum message payload size in bytes (10000000).
pub const PS_DATA_MAX: Int = 10000000;

/// Maximum number of message attributes (100).
pub const PS_ATTR_MAX_COUNT: Int = 100;

/// Maximum attribute-name length (256).
pub const PS_ATTR_NAME_MAX: Int = 256;

/// Maximum attribute-value length (1024).
pub const PS_ATTR_VALUE_MAX: Int = 1024;

/// Maximum ordering-key length (1024).
pub const PS_ORDERING_KEY_MAX: Int = 1024;

/// Maximum ack-id length (1024).
pub const PS_ACK_ID_MAX: Int = 1024;

/// Minimum ack deadline in seconds (10).
pub const PS_ACK_DEADLINE_MIN: Int = 10;

/// Maximum ack deadline in seconds (600).
pub const PS_ACK_DEADLINE_MAX: Int = 600;

/// Minimum subscription retention in seconds (600 = 10 minutes).
pub const PS_RETENTION_MIN: Int = 600;

/// Maximum subscription retention in seconds (604800 = 7 days).
pub const PS_RETENTION_MAX: Int = 604800;

/// Pull subscription kind (1).
pub const PS_SUB_KIND_PULL: Int = 1;

/// Push subscription kind (2).
pub const PS_SUB_KIND_PUSH: Int = 2;

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Resource names
// --------------------------------------------------

/// True for a documented-subset Pub/Sub topic/subscription name. Params: name
/// - the candidate. Complexity O(name.len()).
pub fn ps_resource_name_is_valid(name: Str) -> Bool {
  let n = name.len();
  if n < PS_NAME_MIN {
    return false;
  }
  if n > PS_NAME_MAX {
    return false;
  }
  if !core.gcp_is_alpha(core.gcp_byte(name, 0)) {
    return false;
  }
  var i = 1;
  while i < n {
    let c = core.gcp_byte(name, i);
    if !core.gcp_is_alnum(c) {
      var ok = false;
      if c == 45 || c == 95 || c == 46 || c == 126 {
        ok = true;
      }
      if c == 43 || c == 37 {
        ok = true;
      }
      if !ok {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// Project leaf: non-empty, 1..63, no '/'.
fn _ps_project_ok(project: Str) -> Bool {
  let n = project.len();
  if n < 1 {
    return false;
  }
  if n > 63 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(project, i);
    if c == 47 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// `projects/{project}/topics/{topic}`. Params: project - the project id;
/// topic - the topic name. Returns the path or the first validation error.
/// Complexity O(total length).
pub fn ps_topic_path(project: Str, topic: Str) -> Result[Str, Str] {
  if !_ps_project_ok(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !ps_resource_name_is_valid(topic) {
    return _err_str("gcp: invalid topic name: " + topic);
  }
  return _ok_str("projects/" + project + "/topics/" + topic);
}

/// `projects/{project}/subscriptions/{subscription}`. Params: project - the
/// project id; subscription - the subscription name. Returns the path or the
/// first validation error. Complexity O(total length).
pub fn ps_subscription_path(project: Str, subscription: Str) -> Result[Str, Str] {
  if !_ps_project_ok(project) {
    return _err_str("gcp: invalid project id: " + project);
  }
  if !ps_resource_name_is_valid(subscription) {
    return _err_str("gcp: invalid subscription name: " + subscription);
  }
  return _ok_str("projects/" + project + "/subscriptions/" + subscription);
}

// --------------------------------------------------
//  Publishing
// --------------------------------------------------

/// True when an attribute or ordering-key name uses the reserved "goog" prefix
/// (case-insensitive). Params: name - the candidate. Complexity O(name.len()).
pub fn ps_attr_name_is_reserved(name: Str) -> Bool {
  if name.len() < 4 {
    return false;
  }
  let head = core.gcp_substr(name, 0, 4);
  return compare.str_compare_ignore_case(head, "goog") == 0;
}

/// Validate a publish request: non-empty data within the size limit, parallel
/// attribute vectors with equal lengths and valid entries, and a valid
/// ordering key. Params: data - the message payload; attr_names - attribute
/// names; attr_values - attribute values; ordering_key - "" or the key.
/// Returns Ok("") or the first error. Complexity O(total length).
pub fn ps_publish_validate(data: &Vec[UInt8], attr_names: &Vec[Str], attr_values: &Vec[Str], ordering_key: Str) -> Result[Str, Str] {
  if data.len() < 1 {
    return _err_str("gcp: empty message data");
  }
  if data.len() > PS_DATA_MAX {
    return _err_str("gcp: message data above 10000000 bytes");
  }
  if attr_names.len() != attr_values.len() {
    return _err_str("gcp: attribute name/value count mismatch");
  }
  if attr_names.len() > PS_ATTR_MAX_COUNT {
    return _err_str("gcp: more than 100 attributes");
  }
  var i = 0;
  while i < attr_names.len() {
    let nm: Str = attr_names[i];
    let vl: Str = attr_values[i];
    if nm.len() < 1 {
      return _err_str("gcp: empty attribute name");
    }
    if nm.len() > PS_ATTR_NAME_MAX {
      return _err_str("gcp: attribute name above 256 bytes: " + nm);
    }
    if ps_attr_name_is_reserved(nm) {
      return _err_str("gcp: reserved attribute prefix: " + nm);
    }
    if vl.len() > PS_ATTR_VALUE_MAX {
      return _err_str("gcp: attribute value above 1024 bytes: " + nm);
    }
    i = i + 1;
  }
  if ordering_key.len() > PS_ORDERING_KEY_MAX {
    return _err_str("gcp: ordering key above 1024 bytes");
  }
  if ps_attr_name_is_reserved(ordering_key) {
    return _err_str("gcp: reserved ordering key prefix: " + ordering_key);
  }
  return _ok_str("");
}

// --------------------------------------------------
//  Ack and subscriptions
// --------------------------------------------------

/// True for a modeled ack id: 1..1024 printable non-space ASCII bytes. Params:
/// ack_id - the candidate. Complexity O(ack_id.len()).
pub fn ps_ack_id_is_valid(ack_id: Str) -> Bool {
  let n = ack_id.len();
  if n < 1 {
    return false;
  }
  if n > PS_ACK_ID_MAX {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.gcp_byte(ack_id, i);
    if c < 33 || c > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// True for a valid ack deadline in seconds (10..600). Params: seconds - the
/// candidate. Complexity O(1).
pub fn ps_ack_deadline_is_valid(seconds: Int) -> Bool {
  if seconds < PS_ACK_DEADLINE_MIN {
    return false;
  }
  if seconds > PS_ACK_DEADLINE_MAX {
    return false;
  }
  return true;
}

/// Clamp an ack deadline into 10..600. Params: seconds - the raw value.
/// Complexity O(1).
pub fn ps_ack_deadline_clamp(seconds: Int) -> Int {
  if seconds < PS_ACK_DEADLINE_MIN {
    return PS_ACK_DEADLINE_MIN;
  }
  if seconds > PS_ACK_DEADLINE_MAX {
    return PS_ACK_DEADLINE_MAX;
  }
  return seconds;
}

/// Extend an ack deadline: received + extension, capped at 600 s. Params:
/// received - the current deadline (0..600); extension - the requested
/// extension (0..600). Returns the new deadline or a range error. Complexity
/// O(1).
pub fn ps_ack_deadline_extend(received: Int, extension: Int) -> Result[Int, Str] {
  if received < 0 || received > PS_ACK_DEADLINE_MAX {
    return _err_int("gcp: received deadline out of 0..600: " + core.gcp_int_str(received));
  }
  if extension < 0 || extension > PS_ACK_DEADLINE_MAX {
    return _err_int("gcp: extension out of 0..600: " + core.gcp_int_str(extension));
  }
  let total = received + extension;
  return _ok_int(ps_ack_deadline_clamp(total));
}

/// Validate a subscription configuration. Params: kind - PS_SUB_KIND_*;
/// ack_deadline - seconds; retention_sec - retention seconds; push_endpoint -
/// "" for PULL or the https endpoint for PUSH. Returns Ok("") or the first
/// error. Complexity O(endpoint length).
pub fn ps_subscription_validate(kind: Int, ack_deadline: Int, retention_sec: Int, push_endpoint: Str) -> Result[Str, Str] {
  if kind == PS_SUB_KIND_PULL {
    if push_endpoint.len() != 0 {
      return _err_str("gcp: pull subscription must not carry a push endpoint");
    }
  } else {
    if kind == PS_SUB_KIND_PUSH {
      if push_endpoint.len() == 0 {
        return _err_str("gcp: push subscription requires a push endpoint");
      }
      if !core.gcp_starts_with(push_endpoint, "https://") {
        return _err_str("gcp: push endpoint must be https");
      }
    } else {
      return _err_str("gcp: unknown subscription kind: " + core.gcp_int_str(kind));
    }
  }
  if !ps_ack_deadline_is_valid(ack_deadline) {
    return _err_str("gcp: ack deadline out of 10..600: " + core.gcp_int_str(ack_deadline));
  }
  if retention_sec < PS_RETENTION_MIN {
    return _err_str("gcp: retention below 600 s");
  }
  if retention_sec > PS_RETENTION_MAX {
    return _err_str("gcp: retention above 604800 s");
  }
  return _ok_str("");
}
