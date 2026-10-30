// XIOM -- xiom.transport.rate: saturating byte-budget send window
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, pure token/byte-budget helper for deterministic pacing. It is a
// standalone value (no globals, no wall clock): the caller injects now_ms,
// refills explicitly, then asks can_send/consume. The window saturates at
// its capacity, refills fractionally by time (remainder carried in
// thousandths of a byte), and never exceeds capacity.
//
// This is deliberately basic rate limiting, not congestion control: it has
// no RTT estimate, no loss signal and no adaptive target. It is the additive
// seam a caller can wrap around session_send (see
// session_send_rate_limited) without changing the existing send path.
//
// Determinism: same (capacity, rate, now_ms sequence, consume sequence)
// yields the same budget and counters, byte for byte. A clock that moves
// backwards never refills and never rewinds last_ms.

module xiom.transport.rate

// RateError kinds (reserved for callers that prefer typed validation).
pub const RATE_ERR_CONFIG: Int = 1;
pub const RATE_ERR_BUDGET: Int = 2;

/// A byte-budget window: `available_bytes` is the current allowance,
/// `refill_bytes_per_sec` the refill rate, `remainder` the fractional
/// carry in thousandths, and `last_ms` the last refill timestamp.
pub type RateWindow = {
  capacity_bytes: Int;
  available_bytes: Int;
  refill_bytes_per_sec: Int;
  remainder: Int;
  last_ms: Int;
  sent_bytes: Int;
  sent_packets: Int;
  refilled_bytes: Int;
  refused: Int;
}

/// A fresh window: capacity clamped to >= 0, rate clamped to >= 0, and the
/// budget starts full.
pub fn rate_window_new(capacity_bytes: Int, refill_bytes_per_sec: Int, now_ms: Int) -> RateWindow {
  var cap = capacity_bytes;
  if cap < 0 { cap = 0; }
  var rate = refill_bytes_per_sec;
  if rate < 0 { rate = 0; }
  return RateWindow {
    capacity_bytes: cap;
    available_bytes: cap;
    refill_bytes_per_sec: rate;
    remainder: 0;
    last_ms: now_ms;
    sent_bytes: 0;
    sent_packets: 0;
    refilled_bytes: 0;
    refused: 0;
  };
}

/// Current allowance in bytes (does not refill; call rate_refill first when
/// time has advanced).
pub fn rate_window_bytes(w: &RateWindow) -> Int {
  return w.available_bytes;
}

/// Capacity in bytes.
pub fn rate_window_capacity(w: &RateWindow) -> Int {
  return w.capacity_bytes;
}

/// Refill by elapsed time and return the bytes actually added. Saturates at
/// capacity; a non-positive rate or a clock at/before last_ms adds nothing.
/// When the window is already full the fractional remainder is dropped.
pub fn rate_refill(w: &mut RateWindow, now_ms: Int) -> Int {
  if now_ms <= w.last_ms {
    return 0;
  }
  let elapsed = now_ms - w.last_ms;
  w.last_ms = now_ms;
  if w.refill_bytes_per_sec <= 0 {
    return 0;
  }
  if w.available_bytes >= w.capacity_bytes {
    w.remainder = 0;
    return 0;
  }
  let scaled = elapsed * w.refill_bytes_per_sec + w.remainder;
  var added = scaled / 1000;
  w.remainder = scaled % 1000;
  let room = w.capacity_bytes - w.available_bytes;
  if added > room {
    added = room;
    w.remainder = 0;
  }
  w.available_bytes = w.available_bytes + added;
  w.refilled_bytes = w.refilled_bytes + added;
  return added;
}

/// True when a send of `bytes` fits the current allowance. Negative sizes are
/// always refused.
pub fn rate_can_send(w: &RateWindow, bytes: Int) -> Bool {
  if bytes < 0 { return false; }
  if bytes <= w.available_bytes { return true; }
  return false;
}

/// Consume `bytes` from the window. Refuses (and counts the refusal) when the
/// request is negative or larger than the allowance; on success the budget is
/// reduced and the byte/packet counters advance.
pub fn rate_consume(w: &mut RateWindow, bytes: Int) -> Bool {
  if bytes < 0 {
    w.refused = w.refused + 1;
    return false;
  }
  if bytes > w.available_bytes {
    w.refused = w.refused + 1;
    return false;
  }
  w.available_bytes = w.available_bytes - bytes;
  w.sent_bytes = w.sent_bytes + bytes;
  w.sent_packets = w.sent_packets + 1;
  return true;
}

/// Human-readable one-line rendering (tests/diagnostics).
pub fn rate_window_to_str(w: &RateWindow) -> Str {
  return "RateWindow{capacity=" + w.capacity_bytes.to_str() +
    ", available=" + w.available_bytes.to_str() +
    ", refill_per_sec=" + w.refill_bytes_per_sec.to_str() +
    ", last_ms=" + w.last_ms.to_str() +
    ", sent_bytes=" + w.sent_bytes.to_str() +
    ", sent_packets=" + w.sent_packets.to_str() +
    ", refilled=" + w.refilled_bytes.to_str() +
    ", refused=" + w.refused.to_str() + "}";
}
