// XIOM -- xiom.messaging: deterministic in-process message bus
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI, no threads, no sockets) model of a message broker:
// dotted topics with '+'/'#' wildcard subscriptions, publish fan-out to
// per-subscriber queues, acknowledgement accounting, deterministic
// redelivery with exponential backoff, dead-letter routing and strict
// per-key delivery ordering. Time is an explicit integer tick advanced by
// bus_tick; nothing here consults a wall clock or spawns threads, so a
// scenario replays identically on every run.
//
// Storage model: one append-only record per subscription, delivery and
// dead letter, held in parallel Vec arrays inside Bus. Deliveries are never
// physically removed; a delivery slot moves between the documented states
// (queued, in flight, settled/acked, dead-lettered, dropped) instead, so a
// delivery id is stable for the life of the bus and the parallel arrays
// cannot drift. Every push site is a single helper that mirrors all sibling
// arrays (see _push_delivery and _push_dead_letter).
//
// Language-trap discipline that shaped this module (v0.62.1):
//   * Str equality on strings that live in a Vec[Str] uses str_compare
//     (BUG 17); elements are always bound to typed locals first.
//   * filters are copied out of the subscription table with str_slice before
//     wildcard matching, so no length is ever taken from a stored element.
//   * every Vec[Int]/Vec[Bool] read is bound to a typed local before use.
//   * Ok/Err values are only constructed in the leaf helpers below.
//   * no bit shifts, no Vec[Float64], no Vec[struct] and no methods: the
//     module is plain free functions over values.

module xiom.messaging

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A deterministic in-process message bus. Every field is internal state:
/// build one with bus_new() and drive it through the bus_* API. `tick` is
/// the logical clock (non-decreasing), advanced only by bus_tick.
pub type Bus = {
  tick: Int;              // internal: logical clock
  backoff_base: Int;      // internal: first redelivery delay in ticks, >= 1
  backoff_cap: Int;       // internal: maximum redelivery delay in ticks
  next_sub_id: Int;       // internal: next subscription id, starts at 1
  next_msg_id: Int;       // internal: next message id, starts at 1
  n_published: Int;       // internal: messages published
  n_attempts: Int;        // internal: delivery attempts made
  n_acked: Int;           // internal: explicit acks accepted
  n_settled: Int;         // internal: QoS 0 deliveries settled on delivery
  n_redelivered: Int;     // internal: attempts after the first per delivery
  n_dead: Int;            // internal: dead letters written
  n_dropped: Int;         // internal: deliveries dropped by unsubscribe
  sub_id: Vec[Int];       // internal: subscription id
  sub_client: Vec[Str];   // internal: subscriber name
  sub_filter: Vec[Str];   // internal: validated wildcard filter
  sub_filter_len: Vec[Int]; // internal: filter byte length (computed from the
                          //          argument at subscribe time, never from a
                          //          stored element)
  sub_max_attempts: Vec[Int]; // internal: delivery attempts before dead letter, >= 1
  sub_max_qos: Vec[Int];  // internal: delivered QoS ceiling, 0..2
  sub_active: Vec[Bool];  // internal: false after bus_unsubscribe
  d_msg_id: Vec[Int];     // internal: delivery slot -> message id
  d_sub_index: Vec[Int];  // internal: delivery slot -> subscription slot
  d_sub_id: Vec[Int];     // internal: delivery slot -> subscription id
  d_client: Vec[Str];     // internal: delivery slot -> subscriber name
  d_topic: Vec[Str];      // internal: delivery slot -> topic
  d_payload: Vec[Str];    // internal: delivery slot -> payload
  d_key: Vec[Str];        // internal: delivery slot -> ordering key ("" none)
  d_qos: Vec[Int];        // internal: delivery slot -> delivered QoS (0..2)
  d_state: Vec[Int];      // internal: 0 queued, 1 in flight, 2 settled/acked,
                          //          3 dead-lettered, 4 dropped
  d_attempts: Vec[Int];   // internal: delivery attempts made so far
  d_visible: Vec[Int];    // internal: tick at which the slot is eligible
  dl_delivery_id: Vec[Int]; // internal: dead-letter log entries
  dl_msg_id: Vec[Int];
  dl_sub_id: Vec[Int];
  dl_client: Vec[Str];
  dl_topic: Vec[Str];
  dl_payload: Vec[Str];
  dl_reason: Vec[Str];
  dl_attempts: Vec[Int];
  dl_tick: Vec[Int];
}

/// One delivery attempt handed out by bus_deliver_next. `attempt` is 1 for
/// the first delivery and grows by one per redelivery. `delivery_id` 0 is
/// the sentinel returned when no delivery is eligible.
pub type Delivery = {
  delivery_id: Int;
  message_id: Int;
  subscription_id: Int;
  client: Str;
  topic: Str;
  payload: Str;
  key: Str;
  qos: Int;
  attempt: Int;
}

/// One dead-letter record: the delivery that failed, the message data it
/// carried and the stable reason. Reasons are "max attempts" or
/// "rejected: <reason>" as given to bus_reject.
pub type DeadLetter = {
  delivery_id: Int;
  message_id: Int;
  subscription_id: Int;
  client: Str;
  topic: Str;
  payload: Str;
  reason: Str;
  attempts: Int;
  tick: Int;              // logical tick at which it was dead-lettered
}

/// Counters over a Bus, all computed on demand. `pending` counts queued
/// deliveries, `inflight` counts deliveries awaiting an ack.
pub type BusStats = {
  subscriptions: Int;     // active subscriptions
  messages: Int;          // messages published
  deliveries: Int;        // delivery slots ever created
  attempts: Int;          // delivery attempts made
  acked: Int;             // explicit acks accepted
  settled: Int;           // QoS 0 deliveries settled on delivery
  redelivered: Int;       // attempts after the first per delivery
  dead_lettered: Int;     // dead letters written
  dropped: Int;           // deliveries dropped by unsubscribe
  pending: Int;           // queued deliveries now
  inflight: Int;          // in-flight deliveries now
}

// --------------------------------------------------
//  Result constructors (leaf helpers; see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[DeadLetter, Str].
fn _ok_dl(v: DeadLetter) -> Result[DeadLetter, Str] {
  return Ok(v);
}

// Err(m) for Result[DeadLetter, Str].
fn _err_dl(m: Str) -> Result[DeadLetter, Str] {
  return Err(m);
}

// The sentinel Delivery returned when nothing is eligible.
fn _empty_delivery() -> Delivery {
  return Delivery{
    delivery_id: 0;
    message_id: 0;
    subscription_id: 0;
    client: "";
    topic: "";
    payload: "";
    key: "";
    qos: 0;
    attempt: 0;
  };
}

// --------------------------------------------------
//  Topics and wildcard filters
// --------------------------------------------------

// Byte at `pos` of `s` widened to 0..255; callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// True when `s` contains byte `want` (46 '.', 35 '#', 43 '+' in this module).
fn _has_byte(s: Str, want: Int) -> Bool {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == want {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Index of the '.' that ends the segment starting at `start`, or the length
// of `s` when the segment runs to the end.
fn _segment_end(s: Str, start: Int) -> Int {
  var i = start;
  var res = s.len();
  var done = false;
  while i < s.len() && !done {
    if _byte(s, i) == 46 {
      res = i;
      done = true;
    }
    i = i + 1;
  }
  return res;
}

/// True when `topic` is a valid PUBLISH topic name: one or more dot-separated
/// non-empty segments with no '#' (0x23) and no '+' (0x2B) byte, i.e. no
/// leading, trailing or doubled '.'. Complexity: O(topic length).
pub fn topic_is_valid(topic: Str) -> Bool {
  let n = topic.len();
  if n == 0 {
    return false;
  }
  if _has_byte(topic, 35) || _has_byte(topic, 43) {
    return false;
  }
  var start = 0;
  var i = 0;
  while i <= n {
    let at_end = i == n;
    var is_dot = false;
    if !at_end {
      is_dot = _byte(topic, i) == 46;
    }
    if at_end || is_dot {
      if i - start == 0 {
        return false;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return true;
}

// True when one dot-separated filter segment is legal: non-empty; '#' only
// as the final segment (`at_end`); '+' alone in its segment; no other
// wildcard byte inside a literal segment. `seg` is a fresh string produced
// by str_slice in the caller.
fn _filter_segment_ok(seg: Str, at_end: Bool) -> Bool {
  if seg.len() == 0 {
    return false;
  }
  if compare.str_compare(seg, "#") == 0 {
    return at_end;
  }
  if compare.str_compare(seg, "+") == 0 {
    return true;
  }
  if _has_byte(seg, 35) || _has_byte(seg, 43) {
    return false;
  }
  return true;
}

/// True when `filter` is a valid wildcard subscription filter: one or more
/// dot-separated non-empty segments where '+' (single segment) may appear
/// anywhere and '#' (zero or more trailing segments) may appear only as the
/// final segment and alone in it. "#" alone matches every topic and is also
/// the only filter that matches a single-segment topic plus its tail.
/// Complexity: O(filter length).
pub fn filter_is_valid(filter: Str) -> Bool {
  let n = filter.len();
  if n == 0 {
    return false;
  }
  var start = 0;
  var i = 0;
  while i <= n {
    let at_end = i == n;
    var is_dot = false;
    if !at_end {
      is_dot = _byte(filter, i) == 46;
    }
    if at_end || is_dot {
      let seg = string.str_slice(filter, start, i);
      if !_filter_segment_ok(seg, at_end) {
        return false;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return true;
}

/// Wildcard match of a (valid) filter against a (valid) topic. A segment
/// matches an equal literal, '+' matches exactly one segment and '#' matches
/// zero or more trailing segments (so "a.#" matches both "a" and "a.b.c").
/// Complexity: O(filter + topic length).
pub fn topic_matches(filter: Str, topic: Str) -> Bool {
  var fp = 0;
  var tp = 0;
  var matched = false;
  var done = false;
  while !done {
    if fp >= filter.len() {
      if tp >= topic.len() {
        matched = true;
      }
      done = true;
    } else {
      let fend = _segment_end(filter, fp);
      let fseg = string.str_slice(filter, fp, fend);
      if compare.str_compare(fseg, "#") == 0 {
        matched = true;
        done = true;
      } else {
        if tp >= topic.len() {
          done = true;
        } else {
          let tend = _segment_end(topic, tp);
          let tseg = string.str_slice(topic, tp, tend);
          if compare.str_compare(fseg, "+") == 0 || compare.str_compare(fseg, tseg) == 0 {
            fp = fend + 1;
            tp = tend + 1;
          } else {
            done = true;
          }
        }
      }
    }
  }
  return matched;
}

// --------------------------------------------------
//  Construction and clock
// --------------------------------------------------

/// A fresh bus: logical clock 0, no subscriptions, redelivery backoff
/// base 1 tick and cap 64 ticks. Complexity: O(1).
pub fn bus_new() -> Bus {
  return Bus{
    tick: 0,
    backoff_base: 1,
    backoff_cap: 64,
    next_sub_id: 1,
    next_msg_id: 1,
    n_published: 0,
    n_attempts: 0,
    n_acked: 0,
    n_settled: 0,
    n_redelivered: 0,
    n_dead: 0,
    n_dropped: 0,
    sub_id: Vec[Int].new(),
    sub_client: Vec[Str].new(),
    sub_filter: Vec[Str].new(),
    sub_filter_len: Vec[Int].new(),
    sub_max_attempts: Vec[Int].new(),
    sub_max_qos: Vec[Int].new(),
    sub_active: Vec[Bool].new(),
    d_msg_id: Vec[Int].new(),
    d_sub_index: Vec[Int].new(),
    d_sub_id: Vec[Int].new(),
    d_client: Vec[Str].new(),
    d_topic: Vec[Str].new(),
    d_payload: Vec[Str].new(),
    d_key: Vec[Str].new(),
    d_qos: Vec[Int].new(),
    d_state: Vec[Int].new(),
    d_attempts: Vec[Int].new(),
    d_visible: Vec[Int].new(),
    dl_delivery_id: Vec[Int].new(),
    dl_msg_id: Vec[Int].new(),
    dl_sub_id: Vec[Int].new(),
    dl_client: Vec[Str].new(),
    dl_topic: Vec[Str].new(),
    dl_payload: Vec[Str].new(),
    dl_reason: Vec[Str].new(),
    dl_attempts: Vec[Int].new(),
    dl_tick: Vec[Int].new(),
  };
}

/// Advance the logical clock by `ticks` (>= 0).
/// Err("messaging: negative tick") when `ticks < 0`. Complexity: O(1).
pub fn bus_tick(b: &mut Bus, ticks: Int) -> Result[Unit, Str] {
  if ticks < 0 {
    return _err_unit("messaging: negative tick");
  }
  b.tick = b.tick + ticks;
  return _ok_unit();
}

/// Delay in ticks before attempt `attempt` (1 = first delivery) becomes
/// eligible: `min(cap, base * 2^(attempt-1))`, computed without bit shifts.
/// `attempt < 1` is treated as 1; `base < 1` yields 0. Complexity: O(attempt).
pub fn bus_backoff_ticks(base: Int, cap: Int, attempt: Int) -> Int {
  if base < 1 {
    return 0;
  }
  var v = base;
  var k = 1;
  while k < attempt {
    if v >= cap {
      return cap;
    }
    v = v * 2;
    k = k + 1;
  }
  if v > cap {
    return cap;
  }
  return v;
}

// Delay applied to a delivery slot on its next attempt.
fn _attempt_delay(b: &Bus, attempt: Int) -> Int {
  return bus_backoff_ticks(b.backoff_base, b.backoff_cap, attempt);
}

/// Set the redelivery backoff: `base` ticks for the first retry, doubling
/// per attempt up to `cap`.
/// Err("messaging: bad backoff") when `base < 1` or `cap < base`.
/// Complexity: O(1).
pub fn bus_set_backoff(b: &mut Bus, base: Int, cap: Int) -> Result[Unit, Str] {
  if base < 1 || cap < base {
    return _err_unit("messaging: bad backoff");
  }
  b.backoff_base = base;
  b.backoff_cap = cap;
  return _ok_unit();
}

// --------------------------------------------------
//  Subscriptions
// --------------------------------------------------

// Slot of the subscription with `sub_id`, or -1.
fn _find_sub(b: &Bus, sub_id: Int) -> Int {
  var i = 0;
  while i < b.sub_id.len() {
    let sid: Int = b.sub_id[i];
    if sid == sub_id {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Subscribe `client` to `filter`. `max_attempts` (>= 1) is the number of
/// delivery attempts before an unacknowledged delivery is dead-lettered;
/// `max_qos` (0..2) caps the delivered QoS (the delivered QoS is
/// min(published QoS, max_qos)). A client may hold several subscriptions;
/// fan-out does not deduplicate a message that matches more than one of
/// them. Returns the stable subscription id (1, 2, ...).
///
/// Err("messaging: bad client") for an empty client;
/// Err("messaging: bad filter") for an invalid filter;
/// Err("messaging: bad max attempts") when `max_attempts < 1`;
/// Err("messaging: bad qos") when `max_qos` is outside 0..2.
/// Complexity: O(filter length).
pub fn bus_subscribe(b: &mut Bus, client: Str, filter: Str, max_attempts: Int, max_qos: Int) -> Result[Int, Str] {
  if client.len() == 0 {
    return _err_int("messaging: bad client");
  }
  if !filter_is_valid(filter) {
    return _err_int("messaging: bad filter");
  }
  if max_attempts < 1 {
    return _err_int("messaging: bad max attempts");
  }
  if max_qos < 0 || max_qos > 2 {
    return _err_int("messaging: bad qos");
  }
  let id = b.next_sub_id;
  b.sub_id.push(id);
  b.sub_client.push(client);
  b.sub_filter.push(filter);
  b.sub_filter_len.push(filter.len());
  b.sub_max_attempts.push(max_attempts);
  b.sub_max_qos.push(max_qos);
  b.sub_active.push(true);
  b.next_sub_id = id + 1;
  return _ok_int(id);
}

/// Cancel a subscription. Its queued deliveries are dropped (counted in
/// `dropped`); deliveries already in flight stay in flight and may still be
/// acknowledged, but they can never be delivered again: a timed-out
/// in-flight delivery of an unsubscribed client is dropped instead of
/// redelivered.
///
/// Err("messaging: unknown subscription") for an id that was never issued;
/// Err("messaging: already unsubscribed") for a second unsubscribe.
/// Complexity: O(deliveries + subscriptions).
pub fn bus_unsubscribe(b: &mut Bus, sub_id: Int) -> Result[Unit, Str] {
  let sx = _find_sub(b, sub_id);
  if sx < 0 {
    return _err_unit("messaging: unknown subscription");
  }
  let active: Bool = b.sub_active[sx];
  if !active {
    return _err_unit("messaging: already unsubscribed");
  }
  b.sub_active[sx] = false;
  var i = 0;
  while i < b.d_state.len() {
    let st: Int = b.d_state[i];
    if st == 0 {
      let sj: Int = b.d_sub_index[i];
      if sj == sx {
        b.d_state[i] = 4;
        b.n_dropped = b.n_dropped + 1;
      }
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Number of currently active subscriptions. Complexity: O(subscriptions).
pub fn bus_subscription_count(b: &Bus) -> Int {
  var n = 0;
  var i = 0;
  while i < b.sub_active.len() {
    let act: Bool = b.sub_active[i];
    if act {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// --------------------------------------------------
//  Publish and fan-out
// --------------------------------------------------

// Append one delivery slot; every sibling array is pushed here so the
// parallel vectors cannot drift. Called only from bus_publish.
fn _push_delivery(b: &mut Bus, msg_id: Int, sub_index: Int, sub_id: Int, client: Str, topic: Str, payload: Str, key: Str, qos: Int) {
  b.d_msg_id.push(msg_id);
  b.d_sub_index.push(sub_index);
  b.d_sub_id.push(sub_id);
  b.d_client.push(client);
  b.d_topic.push(topic);
  b.d_payload.push(payload);
  b.d_key.push(key);
  b.d_qos.push(qos);
  b.d_state.push(0);
  b.d_attempts.push(0);
  b.d_visible.push(b.tick);
}

/// Publish `payload` on `topic` with an optional ordering `key` ("" means
/// unordered) and QoS 0..2. One delivery slot is queued for every active
/// subscription whose filter matches, in subscription order, so fan-out is
/// deterministic. The delivered QoS is min(QoS, subscription max_qos); a QoS
/// 0 delivery settles immediately on delivery and needs no ack. Returns the
/// stable message id (1, 2, ...).
///
/// Err("messaging: bad topic") for an invalid topic name;
/// Err("messaging: bad qos") when `qos` is outside 0..2.
/// Complexity: O(subscriptions * filter length).
pub fn bus_publish(b: &mut Bus, topic: Str, payload: Str, key: Str, qos: Int) -> Result[Int, Str] {
  if !topic_is_valid(topic) {
    return _err_int("messaging: bad topic");
  }
  if qos < 0 || qos > 2 {
    return _err_int("messaging: bad qos");
  }
  let mid = b.next_msg_id;
  b.next_msg_id = mid + 1;
  b.n_published = b.n_published + 1;
  var i = 0;
  while i < b.sub_active.len() {
    let act: Bool = b.sub_active[i];
    if act {
      // Copy the stored filter out of the Vec[Str] before matching (BUG 17
      // discipline: never measure a stored element).
      let filt: Str = b.sub_filter[i];
      let flen: Int = b.sub_filter_len[i];
      let fresh = string.str_slice(filt, 0, flen);
      if topic_matches(fresh, topic) {
        let sid: Int = b.sub_id[i];
        let client: Str = b.sub_client[i];
        let mq: Int = b.sub_max_qos[i];
        var dq = qos;
        if dq > mq {
          dq = mq;
        }
        _push_delivery(b, mid, i, sid, client, topic, payload, key, dq);
      }
    }
    i = i + 1;
  }
  return _ok_int(mid);
}

// --------------------------------------------------
//  Delivery, ack, redelivery
// --------------------------------------------------

// True when slot `i` may not be delivered yet because an earlier queued or
// in-flight delivery for the same subscription carries the same non-empty
// key. Empty keys are unordered. Callers guarantee `i` is a queued slot.
fn _key_blocked(b: &Bus, i: Int) -> Bool {
  let key: Str = b.d_key[i];
  if compare.str_compare(key, "") == 0 {
    return false;
  }
  let sx: Int = b.d_sub_index[i];
  var j = 0;
  while j < i {
    let st: Int = b.d_state[j];
    if st == 0 || st == 1 {
      let sj: Int = b.d_sub_index[j];
      if sj == sx {
        let kj: Str = b.d_key[j];
        if compare.str_compare(kj, key) == 0 {
          return true;
        }
      }
    }
    j = j + 1;
  }
  return false;
}

// Append one dead-letter record; every sibling array is pushed here. Called
// from _dead_letter_slot and bus_reject.
fn _push_dead_letter(b: &mut Bus, delivery_id: Int, msg_id: Int, sub_id: Int, client: Str, topic: Str, payload: Str, reason: Str, attempts: Int) {
  b.dl_delivery_id.push(delivery_id);
  b.dl_msg_id.push(msg_id);
  b.dl_sub_id.push(sub_id);
  b.dl_client.push(client);
  b.dl_topic.push(topic);
  b.dl_payload.push(payload);
  b.dl_reason.push(reason);
  b.dl_attempts.push(attempts);
  b.dl_tick.push(b.tick);
}

// Tombstone slot `i` as dead-lettered and log the record with `reason`.
fn _dead_letter_slot(b: &mut Bus, i: Int, reason: Str) {
  let mid: Int = b.d_msg_id[i];
  let sid: Int = b.d_sub_id[i];
  let client: Str = b.d_client[i];
  let topic: Str = b.d_topic[i];
  let payload: Str = b.d_payload[i];
  let att: Int = b.d_attempts[i];
  b.d_state[i] = 3;
  _push_dead_letter(b, i + 1, mid, sid, client, topic, payload, reason, att);
  b.n_dead = b.n_dead + 1;
}

// Make timed-out in-flight deliveries eligible again (state 1 -> 0). A
// timed-out in-flight delivery of an unsubscribed client is dropped instead.
fn _expire_inflight(b: &mut Bus) {
  var i = 0;
  while i < b.d_state.len() {
    let st: Int = b.d_state[i];
    if st == 1 {
      let vis: Int = b.d_visible[i];
      if vis <= b.tick {
        let sx: Int = b.d_sub_index[i];
        let act: Bool = b.sub_active[sx];
        if act {
          b.d_state[i] = 0;
        } else {
          b.d_state[i] = 4;
          b.n_dropped = b.n_dropped + 1;
        }
      }
    }
    i = i + 1;
  }
}

// Lowest eligible queued slot: visible, unsubscribed clients excluded, not
// blocked by an earlier same-key delivery, and not past max_attempts (those
// are dead-lettered in place). Returns -1 when nothing is eligible.
fn _select_slot(b: &mut Bus) -> Int {
  var found: Int = -1;
  var i = 0;
  while i < b.d_state.len() && found < 0 {
    let st: Int = b.d_state[i];
    if st == 0 {
      let vis: Int = b.d_visible[i];
      if vis <= b.tick {
        if !_key_blocked(b, i) {
          let sx: Int = b.d_sub_index[i];
          let act: Bool = b.sub_active[sx];
          let ma: Int = b.sub_max_attempts[sx];
          let att: Int = b.d_attempts[i];
          if act {
            if att >= ma {
              _dead_letter_slot(b, i, "max attempts");
            } else {
              found = i;
            }
          }
        }
      }
    }
    i = i + 1;
  }
  return found;
}

// Charge attempt `att+1` to slot `i` and return it as a Delivery. QoS 0
// deliveries settle immediately (state 2).
fn _make_delivery(b: &mut Bus, i: Int) -> Delivery {
  let dq: Int = b.d_qos[i];
  let att: Int = b.d_attempts[i] + 1;
  b.d_attempts[i] = att;
  b.d_visible[i] = b.tick + _attempt_delay(b, att);
  b.d_state[i] = 1;
  b.n_attempts = b.n_attempts + 1;
  if att > 1 {
    b.n_redelivered = b.n_redelivered + 1;
  }
  if dq == 0 {
    b.d_state[i] = 2;
    b.n_settled = b.n_settled + 1;
  }
  let mid: Int = b.d_msg_id[i];
  let sid: Int = b.d_sub_id[i];
  let client: Str = b.d_client[i];
  let topic: Str = b.d_topic[i];
  let payload: Str = b.d_payload[i];
  let key: Str = b.d_key[i];
  return Delivery{
    delivery_id: i + 1;
    message_id: mid;
    subscription_id: sid;
    client: client;
    topic: topic;
    payload: payload;
    key: key;
    qos: dq;
    attempt: att;
  };
}

/// Deliver the next eligible queued delivery, in deterministic order:
/// lowest delivery id wins. First, every in-flight delivery whose backoff
/// has elapsed becomes eligible again; then queued deliveries whose
/// max_attempts is exhausted are dead-lettered ("max attempts") and skipped.
/// A keyed delivery is eligible only when no earlier queued or in-flight
/// delivery for the same subscription shares its key, which gives strict
/// per-(subscription, key) publish-order delivery.
///
/// Returns the sentinel Delivery with `delivery_id` 0 when nothing is
/// eligible. Delivering charges one attempt and sets the next visibility to
/// `tick + bus_backoff_ticks(base, cap, attempt)`; QoS 0 deliveries settle on
/// delivery and are never redelivered. Complexity: O(deliveries^2).
pub fn bus_deliver_next(b: &mut Bus) -> Delivery {
  _expire_inflight(b);
  let idx = _select_slot(b);
  if idx < 0 {
    return _empty_delivery();
  }
  return _make_delivery(b, idx);
}

/// Acknowledge in-flight delivery `delivery_id`. A QoS 0 delivery settles on
/// delivery and can never be acked.
///
/// Err("messaging: unknown delivery") for an id never issued;
/// Err("messaging: delivery not in flight") when the delivery is queued,
/// settled, dead-lettered or dropped.
/// Complexity: O(1).
pub fn bus_ack(b: &mut Bus, delivery_id: Int) -> Result[Unit, Str] {
  if delivery_id < 1 || delivery_id > b.d_state.len() {
    return _err_unit("messaging: unknown delivery");
  }
  let i = delivery_id - 1;
  let st: Int = b.d_state[i];
  if st != 1 {
    return _err_unit("messaging: delivery not in flight");
  }
  b.d_state[i] = 2;
  b.n_acked = b.n_acked + 1;
  return _ok_unit();
}

/// Reject in-flight delivery `delivery_id`: it is dead-lettered immediately
/// with reason "rejected: " + `reason`.
///
/// Err("messaging: unknown delivery") for an id never issued;
/// Err("messaging: delivery not in flight") when the delivery is not in
/// flight; Err("messaging: empty reject reason") when `reason` is "".
/// Complexity: O(1).
pub fn bus_reject(b: &mut Bus, delivery_id: Int, reason: Str) -> Result[Unit, Str] {
  if delivery_id < 1 || delivery_id > b.d_state.len() {
    return _err_unit("messaging: unknown delivery");
  }
  let i = delivery_id - 1;
  let st: Int = b.d_state[i];
  if st != 1 {
    return _err_unit("messaging: delivery not in flight");
  }
  if reason.len() == 0 {
    return _err_unit("messaging: empty reject reason");
  }
  _dead_letter_slot(b, i, "rejected: " + reason);
  return _ok_unit();
}

// --------------------------------------------------
//  Queue and accounting views
// --------------------------------------------------

/// Number of queued (not yet delivered) delivery slots on the whole bus.
/// Complexity: O(deliveries).
pub fn bus_pending_count(b: &Bus) -> Int {
  var n = 0;
  var i = 0;
  while i < b.d_state.len() {
    let st: Int = b.d_state[i];
    if st == 0 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Number of in-flight (delivered, awaiting ack) delivery slots.
/// Complexity: O(deliveries).
pub fn bus_inflight_count(b: &Bus) -> Int {
  var n = 0;
  var i = 0;
  while i < b.d_state.len() {
    let st: Int = b.d_state[i];
    if st == 1 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Queued deliveries belonging to subscription `sub_id` (its per-subscriber
/// queue depth; in-flight deliveries are not counted).
/// Err("messaging: unknown subscription") for an id that was never issued.
/// Complexity: O(deliveries).
pub fn bus_queue_depth(b: &Bus, sub_id: Int) -> Result[Int, Str] {
  let sx = _find_sub(b, sub_id);
  if sx < 0 {
    return _err_int("messaging: unknown subscription");
  }
  var n = 0;
  var i = 0;
  while i < b.d_state.len() {
    let st: Int = b.d_state[i];
    if st == 0 {
      let sj: Int = b.d_sub_index[i];
      if sj == sx {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return _ok_int(n);
}

/// Number of dead-letter records. Complexity: O(1).
pub fn bus_dead_letter_count(b: &Bus) -> Int {
  return b.dl_reason.len();
}

/// Dead-letter record `index` (0-based, in dead-letter order).
/// Err("messaging: dead letter index out of range") when `index` is outside
/// 0..count. Complexity: O(1).
pub fn bus_dead_letter_at(b: &Bus, index: Int) -> Result[DeadLetter, Str] {
  if index < 0 || index >= b.dl_reason.len() {
    return _err_dl("messaging: dead letter index out of range");
  }
  let did: Int = b.dl_delivery_id[index];
  let mid: Int = b.dl_msg_id[index];
  let sid: Int = b.dl_sub_id[index];
  let client: Str = b.dl_client[index];
  let topic: Str = b.dl_topic[index];
  let payload: Str = b.dl_payload[index];
  let reason: Str = b.dl_reason[index];
  let att: Int = b.dl_attempts[index];
  let tk: Int = b.dl_tick[index];
  return _ok_dl(DeadLetter{
    delivery_id: did;
    message_id: mid;
    subscription_id: sid;
    client: client;
    topic: topic;
    payload: payload;
    reason: reason;
    attempts: att;
    tick: tk;
  });
}

/// Snapshot the counters; all values are derived from the bus state on
/// demand. Complexity: O(deliveries + subscriptions).
pub fn bus_stats(b: &Bus) -> BusStats {
  var subs = 0;
  var i = 0;
  while i < b.sub_active.len() {
    let act: Bool = b.sub_active[i];
    if act {
      subs = subs + 1;
    }
    i = i + 1;
  }
  var pending = 0;
  var inflight = 0;
  i = 0;
  while i < b.d_state.len() {
    let st: Int = b.d_state[i];
    if st == 0 {
      pending = pending + 1;
    }
    if st == 1 {
      inflight = inflight + 1;
    }
    i = i + 1;
  }
  return BusStats{
    subscriptions: subs;
    messages: b.next_msg_id - 1;
    deliveries: b.d_state.len();
    attempts: b.n_attempts;
    acked: b.n_acked;
    settled: b.n_settled;
    redelivered: b.n_redelivered;
    dead_lettered: b.n_dead;
    dropped: b.n_dropped;
    pending: pending;
    inflight: inflight;
  };
}
