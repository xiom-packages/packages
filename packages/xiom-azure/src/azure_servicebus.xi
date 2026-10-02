// XIOM -- xiom.azure.servicebus: pure-XIOM Azure Service Bus model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Models the Service Bus messaging surface the caller drives over its own
// transport:
//
//   * Entity names (queues, topics, subscriptions, rules) and the queue
//     shape with the documented lock-duration / max-delivery-count bounds.
//   * Namespace names and queue / subscription URLs.
//   * A message state machine: active, deferred, scheduled, dead-letter and
//     completed, with the settle actions complete, abandon, dead-letter,
//     defer, lock-expiry and scheduled due.
//   * Lock expiry, delivery-count exhaustion, dead-letter reasons, scheduled
//     enqueue delays and SQL/correlation rule filter shape.
//
// Documented subset: sessions and transactions are modeled as flags, not as
// protocol flows; settle results are states, not server acknowledgements.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure.servicebus

use xiom.azure.base;
use xiom.string;

// Receive modes.
pub const AZURE_SB_MODE_PEEK_LOCK: Int = 0;
pub const AZURE_SB_MODE_RECEIVE_AND_DELETE: Int = 1;

// Message states.
pub const AZURE_SB_STATE_ACTIVE: Int = 0;
pub const AZURE_SB_STATE_DEFERRED: Int = 1;
pub const AZURE_SB_STATE_SCHEDULED: Int = 2;
pub const AZURE_SB_STATE_DEAD_LETTER: Int = 3;
pub const AZURE_SB_STATE_COMPLETED: Int = 4;

// Settle / lifecycle actions.
pub const AZURE_SB_ACTION_COMPLETE: Int = 0;
pub const AZURE_SB_ACTION_ABANDON: Int = 1;
pub const AZURE_SB_ACTION_DEAD_LETTER: Int = 2;
pub const AZURE_SB_ACTION_DEFER: Int = 3;
pub const AZURE_SB_ACTION_LOCK_EXPIRE: Int = 4;
pub const AZURE_SB_ACTION_SCHEDULED_DUE: Int = 5;
pub const AZURE_SB_ACTION_RECEIVE: Int = 6;

// Queue defaults and bounds.
pub const AZURE_SB_LOCK_MIN_SEC: Int = 5;
pub const AZURE_SB_LOCK_MAX_SEC: Int = 300;
pub const AZURE_SB_LOCK_DEFAULT_SEC: Int = 30;
pub const AZURE_SB_MAX_DELIVERY_MIN: Int = 1;
pub const AZURE_SB_MAX_DELIVERY_MAX: Int = 2000;
pub const AZURE_SB_MAX_DELIVERY_DEFAULT: Int = 10;

// Scheduled-enqueue bound: seven days.
pub const AZURE_SB_SCHEDULE_MAX_SEC: Int = 604800;

/// One queue definition.
pub type AzureSbQueue = {
  name: Str;
  lock_duration_sec: Int;
  max_delivery_count: Int;
  requires_session: Bool;
  dead_lettering: Bool;
}

/// One message projection.
pub type AzureSbMessage = {
  message_id: Str;
  state: Int;
  delivery_count: Int;
  lock_expires_at: Int;
  session_id: Str;
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

fn _ok_queue(v: AzureSbQueue) -> Result[AzureSbQueue, Str] {
  return Ok(v);
}

fn _err_queue(m: Str) -> Result[AzureSbQueue, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Local helpers
// --------------------------------------------------

fn _streq_ci(a: Str, b: Str) -> Bool {
  return base.azure_streq_ignore_case(a, b);
}

fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _is_alnum(b: Int) -> Bool {
  return base.azure_is_alpha(b) || base.azure_is_digit(b);
}

// --------------------------------------------------
//  Names and endpoints
// --------------------------------------------------

/// Service Bus entity name: 1..260 chars, starts/ends alphanumeric, otherwise
/// letters, digits, '.', '-' and '_' without ".." or "--" runs.
pub fn azure_sb_entity_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 260 {
    return false;
  }
  let b0: Int = _byte_at(s, 0);
  let bl: Int = _byte_at(s, n - 1);
  if !_is_alnum(b0) || !_is_alnum(bl) {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(s, i);
    if !_is_alnum(b) && b != 46 && b != 45 && b != 95 {
      return false;
    }
    if i > 0 {
      let prev: Int = _byte_at(s, i - 1);
      if b == 46 && prev == 46 {
        return false;
      }
      if b == 45 && prev == 45 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// Namespace name: 6..50 chars, letters/digits/hyphens, starting and ending
/// with a letter or digit.
pub fn azure_sb_namespace_valid(ns: Str) -> Bool {
  let n = ns.len();
  if n < 6 || n > 50 {
    return false;
  }
  var i = 0;
  var prev_dash = false;
  while i < n {
    let b: Int = _byte_at(ns, i);
    if _is_alnum(b) {
      prev_dash = false;
    } else if b == 45 {
      if i == 0 || prev_dash {
        return false;
      }
      prev_dash = true;
    } else {
      return false;
    }
    i = i + 1;
  }
  if prev_dash {
    return false;
  }
  return true;
}

/// Validate a queue definition: entity name, lock duration 5..300 s and
/// max delivery count 1..2000.
pub fn azure_sb_queue(name: Str, lock_duration_sec: Int, max_delivery_count: Int, requires_session: Bool, dead_lettering: Bool) -> Result[AzureSbQueue, Str] {
  if !azure_sb_entity_name_valid(name) {
    return _err_queue("azure: invalid entity name");
  }
  if lock_duration_sec < AZURE_SB_LOCK_MIN_SEC || lock_duration_sec > AZURE_SB_LOCK_MAX_SEC {
    return _err_queue("azure: invalid lock duration");
  }
  if max_delivery_count < AZURE_SB_MAX_DELIVERY_MIN || max_delivery_count > AZURE_SB_MAX_DELIVERY_MAX {
    return _err_queue("azure: invalid max delivery count");
  }
  return _ok_queue(AzureSbQueue{
    name: name;
    lock_duration_sec: lock_duration_sec;
    max_delivery_count: max_delivery_count;
    requires_session: requires_session;
    dead_lettering: dead_lettering;
  });
}

/// Queue URL "https://{ns}.servicebus.windows.net/{queue}".
pub fn azure_sb_queue_url(namespace: Str, queue: Str) -> Result[Str, Str] {
  if !azure_sb_namespace_valid(namespace) {
    return _err_str("azure: invalid namespace");
  }
  if !azure_sb_entity_name_valid(queue) {
    return _err_str("azure: invalid entity name");
  }
  return _ok_str("https://" + namespace + ".servicebus.windows.net/" + queue);
}

/// Subscription path "{topic}/subscriptions/{subscription}".
pub fn azure_sb_subscription_path(topic: Str, subscription: Str) -> Result[Str, Str] {
  if !azure_sb_entity_name_valid(topic) {
    return _err_str("azure: invalid entity name");
  }
  if !azure_sb_entity_name_valid(subscription) {
    return _err_str("azure: invalid subscription name");
  }
  return _ok_str(topic + "/subscriptions/" + subscription);
}

/// Receive-mode name (unknown -> "unknown").
pub fn azure_sb_delivery_mode_name(mode: Int) -> Str {
  if mode == AZURE_SB_MODE_PEEK_LOCK {
    return "peek_lock";
  }
  if mode == AZURE_SB_MODE_RECEIVE_AND_DELETE {
    return "receive_and_delete";
  }
  return "unknown";
}

// --------------------------------------------------
//  Message state machine
// --------------------------------------------------

/// Message-state name (unknown -> "unknown").
pub fn azure_sb_state_name(state: Int) -> Str {
  if state == AZURE_SB_STATE_ACTIVE {
    return "active";
  }
  if state == AZURE_SB_STATE_DEFERRED {
    return "deferred";
  }
  if state == AZURE_SB_STATE_SCHEDULED {
    return "scheduled";
  }
  if state == AZURE_SB_STATE_DEAD_LETTER {
    return "dead_letter";
  }
  if state == AZURE_SB_STATE_COMPLETED {
    return "completed";
  }
  return "unknown";
}

/// Next state for `action` applied to `state`, or -1 when the action is not
/// legal there. Complete settles to COMPLETED, dead-letter to DEAD_LETTER;
/// abandon and lock-expiry return an active message to ACTIVE. The caller
/// owns delivery-count increments.
pub fn azure_sb_message_transition(state: Int, action: Int) -> Int {
  if state == AZURE_SB_STATE_ACTIVE {
    if action == AZURE_SB_ACTION_COMPLETE {
      return AZURE_SB_STATE_COMPLETED;
    }
    if action == AZURE_SB_ACTION_ABANDON {
      return AZURE_SB_STATE_ACTIVE;
    }
    if action == AZURE_SB_ACTION_DEAD_LETTER {
      return AZURE_SB_STATE_DEAD_LETTER;
    }
    if action == AZURE_SB_ACTION_DEFER {
      return AZURE_SB_STATE_DEFERRED;
    }
    if action == AZURE_SB_ACTION_LOCK_EXPIRE {
      return AZURE_SB_STATE_ACTIVE;
    }
    return -1;
  }
  if state == AZURE_SB_STATE_DEFERRED {
    if action == AZURE_SB_ACTION_RECEIVE {
      return AZURE_SB_STATE_ACTIVE;
    }
    if action == AZURE_SB_ACTION_DEAD_LETTER {
      return AZURE_SB_STATE_DEAD_LETTER;
    }
    return -1;
  }
  if state == AZURE_SB_STATE_SCHEDULED {
    if action == AZURE_SB_ACTION_SCHEDULED_DUE {
      return AZURE_SB_STATE_ACTIVE;
    }
    return -1;
  }
  return -1;
}

/// True when a PEEK_LOCK message's lock is held at `now` (lock_expires_at 0
/// means "no lock held").
pub fn azure_sb_lock_expired(lock_expires_at: Int, now: Int) -> Bool {
  if lock_expires_at <= 0 {
    return false;
  }
  return now >= lock_expires_at;
}

/// True when the delivery count has exhausted max_delivery_count (Azure
/// dead-letters when the count exceeds the maximum).
pub fn azure_sb_delivery_count_exceeded(delivery_count: Int, max_delivery_count: Int) -> Bool {
  if max_delivery_count < 1 {
    return true;
  }
  return delivery_count > max_delivery_count;
}

/// True for the three canonical dead-letter reasons.
pub fn azure_sb_deadletter_reason_valid(reason: Str) -> Bool {
  if _streq_ci(reason, "MaxDeliveryCountExceeded") {
    return true;
  }
  if _streq_ci(reason, "TTLExpiredException") {
    return true;
  }
  if _streq_ci(reason, "HeaderSizeExceeded") {
    return true;
  }
  return false;
}

/// Scheduled enqueue delay: 1..604800 seconds (seven days).
pub fn azure_sb_scheduled_delay_valid(secs: Int) -> Bool {
  if secs < 1 {
    return false;
  }
  if secs > AZURE_SB_SCHEDULE_MAX_SEC {
    return false;
  }
  return true;
}

/// Rule-filter shape: the built-in "$Default" or a 1..1024-byte printable
/// non-empty SQL/correlation expression.
pub fn azure_sb_rule_filter_valid(filter: Str) -> Bool {
  if _streq_ci(filter, "$Default") {
    return true;
  }
  let n = filter.len();
  if n < 1 || n > 1024 {
    return false;
  }
  return base.azure_is_printable_ascii(filter);
}

/// Message shape: 1..128-byte id, known state, non-negative delivery count
/// and lock expiry, optional session id.
pub fn azure_sb_message_valid(m: &AzureSbMessage) -> Bool {
  let mid: Str = m.message_id;
  let state: Int = m.state;
  let count: Int = m.delivery_count;
  let lock_at: Int = m.lock_expires_at;
  let sid: Str = m.session_id;
  if mid.len() < 1 || mid.len() > 128 {
    return false;
  }
  if !base.azure_is_printable_ascii(mid) {
    return false;
  }
  if state < AZURE_SB_STATE_ACTIVE || state > AZURE_SB_STATE_COMPLETED {
    return false;
  }
  if count < 0 || lock_at < 0 {
    return false;
  }
  if sid.len() > 128 {
    return false;
  }
  return true;
}
