// XIOM -- xiom.transport.loopback: in-memory semantic reference backend
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The loopback reference (NETCODE.md sec. 2): a deterministic, zero-latency
// in-memory link between endpoint A and endpoint B. Byte-exact payload
// roundtrip, strict FIFO ordering per direction, no window, no loss, no
// duplication, no wall clock. Everything deterministic is provable here
// before a socket exists; backends may express less, never something else.
//
// One Link owns both directions; a caller steps it explicitly:
//   link = loopback_new();
//   loopback_send_a(&mut link, &bytes);          // A -> B
//   let in_b = loopback_poll_b(&mut link);       // drains A -> B
//   loopback_send_b(&mut link, &bytes);          // B -> A
//   let in_a = loopback_poll_a(&mut link);       // drains B -> A
//
// Bytes are copied on send and on drain, so payloads never alias.

module xiom.transport.loopback

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// One in-memory link: two FIFO queues plus honest counters.
pub type LoopbackLink = {
  open: Bool;
  a_to_b: Vec[Vec[UInt8]];
  b_to_a: Vec[Vec[UInt8]];
  sent_a: Int;
  sent_b: Int;
  delivered_a: Int;
  delivered_b: Int;
  bytes_sent: Int;
  bytes_delivered: Int;
  refused: Int;
}

/// A copy-out stats view.
pub type LoopbackStats = {
  sent_a: Int;
  sent_b: Int;
  delivered_a: Int;
  delivered_b: Int;
  bytes_sent: Int;
  bytes_delivered: Int;
  pending_a_to_b: Int;
  pending_b_to_a: Int;
  refused: Int;
  open: Bool;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Surface
// ---------------------------------------------------------------------------

pub fn loopback_new() -> LoopbackLink {
  var ab: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  var ba: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  return LoopbackLink {
    open: true;
    a_to_b: ab;
    b_to_a: ba;
    sent_a: 0;
    sent_b: 0;
    delivered_a: 0;
    delivered_b: 0;
    bytes_sent: 0;
    bytes_delivered: 0;
    refused: 0;
  };
}

/// A -> B send; returns the packet's zero-based id, or -1 when the link
/// is closed (the attempt is counted in refused).
pub fn loopback_send_a(l: &mut LoopbackLink, bytes: &Vec[UInt8]) -> Int {
  if !l.open {
    l.refused = l.refused + 1;
    return -1;
  }
  let id = l.sent_a + l.sent_b;
  l.a_to_b.push(_copy_bytes(bytes));
  l.sent_a = l.sent_a + 1;
  l.bytes_sent = l.bytes_sent + bytes.len();
  return id;
}

/// B -> A send; same conventions as loopback_send_a.
pub fn loopback_send_b(l: &mut LoopbackLink, bytes: &Vec[UInt8]) -> Int {
  if !l.open {
    l.refused = l.refused + 1;
    return -1;
  }
  let id = l.sent_a + l.sent_b;
  l.b_to_a.push(_copy_bytes(bytes));
  l.sent_b = l.sent_b + 1;
  l.bytes_sent = l.bytes_sent + bytes.len();
  return id;
}

/// Drain everything A has received (the B -> A queue), in FIFO order.
pub fn loopback_poll_a(l: &mut LoopbackLink) -> Vec[Vec[UInt8]] {
  var out: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < l.b_to_a.len() {
    let p: Vec[UInt8] = l.b_to_a[i];
    l.delivered_a = l.delivered_a + 1;
    l.bytes_delivered = l.bytes_delivered + p.len();
    out.push(p);
    i = i + 1;
  }
  l.b_to_a = Vec[Vec[UInt8]].new();
  return out;
}

/// Drain everything B has received (the A -> B queue), in FIFO order.
pub fn loopback_poll_b(l: &mut LoopbackLink) -> Vec[Vec[UInt8]] {
  var out: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < l.a_to_b.len() {
    let p: Vec[UInt8] = l.a_to_b[i];
    l.delivered_b = l.delivered_b + 1;
    l.bytes_delivered = l.bytes_delivered + p.len();
    out.push(p);
    i = i + 1;
  }
  l.a_to_b = Vec[Vec[UInt8]].new();
  return out;
}

/// Pending datagram count toward B.
pub fn loopback_pending_b(l: &LoopbackLink) -> Int {
  return l.a_to_b.len();
}

/// Pending datagram count toward A.
pub fn loopback_pending_a(l: &LoopbackLink) -> Int {
  return l.b_to_a.len();
}

pub fn loopback_stats(l: &LoopbackLink) -> LoopbackStats {
  return LoopbackStats {
    sent_a: l.sent_a;
    sent_b: l.sent_b;
    delivered_a: l.delivered_a;
    delivered_b: l.delivered_b;
    bytes_sent: l.bytes_sent;
    bytes_delivered: l.bytes_delivered;
    pending_a_to_b: l.a_to_b.len();
    pending_b_to_a: l.b_to_a.len();
    refused: l.refused;
    open: l.open;
  };
}

/// Close the link (idempotent; further sends are refused and counted).
pub fn loopback_close(l: &mut LoopbackLink) {
  l.open = false;
}

pub fn loopback_is_open(l: &LoopbackLink) -> Bool {
  return l.open;
}
