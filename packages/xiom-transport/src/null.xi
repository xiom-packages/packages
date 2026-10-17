// XIOM -- xiom.transport.null: honest empty backend
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The null backend: everything is counted, nothing is delivered. It exists
// so a consumer can wire the transport seam in tests, tooling and
// capability-off configurations without a network; it never pretends a
// byte moved. Every accept is counted, every poll returns an empty result,
// and the delivered counters stay a provable zero.

module xiom.transport.null

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A null endpoint with honest counters.
pub type NullTransport = {
  open: Bool;
  sent: Int;
  bytes_sent: Int;
  polls: Int;
  sends_refused: Int;
}

/// Copy-out stats view of a null transport.
pub type NullStats = {
  open: Bool;
  sent: Int;
  bytes_sent: Int;
  polls: Int;
  sends_refused: Int;
  delivered: Int;
  bytes_delivered: Int;
}

pub fn null_new() -> NullTransport {
  return NullTransport {
    open: true;
    sent: 0;
    bytes_sent: 0;
    polls: 0;
    sends_refused: 0;
  };
}

/// Accept a datagram into the void: counted when open, refused (and
/// counted as refused) otherwise. Returns true when accepted.
pub fn null_send(t: &mut NullTransport, bytes: &Vec[UInt8]) -> Bool {
  if !t.open {
    t.sends_refused = t.sends_refused + 1;
    return false;
  }
  t.sent = t.sent + 1;
  t.bytes_sent = t.bytes_sent + bytes.len();
  return true;
}

/// Poll: always an empty result; the poll itself is counted. Delivered
/// counters are provably zero, now and forever.
pub fn null_poll(t: &mut NullTransport) -> Vec[Vec[UInt8]] {
  t.polls = t.polls + 1;
  return Vec[Vec[UInt8]].new();
}

pub fn null_stats(t: &NullTransport) -> NullStats {
  return NullStats {
    open: t.open;
    sent: t.sent;
    bytes_sent: t.bytes_sent;
    polls: t.polls;
    sends_refused: t.sends_refused;
    delivered: 0;
    bytes_delivered: 0;
  };
}

/// Close the null endpoint (idempotent).
pub fn null_close(t: &mut NullTransport) {
  t.open = false;
}

pub fn null_is_open(t: &NullTransport) -> Bool {
  return t.open;
}
