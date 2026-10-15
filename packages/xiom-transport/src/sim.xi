// XIOM -- xiom.transport.sim: deterministic simulated network (seam
// injection harness)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Simulated latency/loss lives at the transport seam (NETCODE.md sec. 2):
// this module injects a deterministic adversarial network between two
// endpoints of one process. It owns a VIRTUAL CLOCK (advanced only by
// sim_advance), fixed one-way delay, and three schedule tables:
//
//   * drop table     -- packet ids that vanish on the wire;
//   * duplicate table-- packet ids that arrive twice (the copy arrives 1 ms
//                       after the original, deterministically);
//   * reorder        -- every reorder_every-th packet id gets an extra
//                       displacement of 1..reorder_distance ms, chosen by
//                       the link's seeded xorshift64 stream.
//
// Identical seed + identical call sequence => identical transcript
// (sim_capture / sim_digest), byte for byte. There is no wall clock and no
// randomness beyond the caller-supplied seed. Packet ids are one shared
// zero-based counter across both directions, assigned at send time.

module xiom.transport.sim

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// One packet's send decision, recorded for the transcript.
pub type SimPacket = {
  id: Int;
  from_a: Bool;
  due_ms: Int;
  dropped: Bool;
  duplicated: Bool;
  displaced_ms: Int;
  bytes: Vec[UInt8];
}

/// The schedule tables (plain data).
pub type SimSchedule = {
  delay_ms: Int;
  drop: Vec[Int];
  dup: Vec[Int];
  reorder_every: Int;
  reorder_distance: Int;
  seed: Int;
}

/// The link: schedule + virtual clock + both in-flight queues + capture.
pub type SimLink = {
  schedule: SimSchedule;
  clock_ms: Int;
  next_id: Int;
  rng: Int;
  q_ab: Vec[SimPacket];
  q_ba: Vec[SimPacket];
  capture: Vec[SimPacket];
  sent: Int;
  delivered: Int;
  dropped: Int;
  duplicated: Int;
  displaced: Int;
}

/// Copy-out stats view.
pub type SimStats = {
  clock_ms: Int;
  sent: Int;
  delivered: Int;
  dropped: Int;
  duplicated: Int;
  displaced: Int;
  pending_a_to_b: Int;
  pending_b_to_a: Int;
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

fn _in_list(list: &Vec[Int], v: Int) -> Bool {
  var i = 0;
  while i < list.len() {
    let x: Int = list[i];
    if x == v { return true; }
    i = i + 1;
  }
  return false;
}

// xorshift64: the deterministic seeded stream (no wall clock, no OS
// entropy). State 0 is remapped to the fixed seed 0x2545F4914F6CDD1D.
fn _rng_next(state: Int) -> Int {
  var x = state;
  if x == 0 { x = 2685821657736338717; }
  x = x ^ (x << 13);
  x = x ^ (x >> 7);
  x = x ^ (x << 17);
  x = x & 9223372036854775807;
  return x;
}

fn _copy_packet(p: &SimPacket) -> SimPacket {
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < p.bytes.len() {
    let b: UInt8 = p.bytes[i];
    bytes.push(b);
    i = i + 1;
  }
  return SimPacket {
    id: p.id;
    from_a: p.from_a;
    due_ms: p.due_ms;
    dropped: p.dropped;
    duplicated: p.duplicated;
    displaced_ms: p.displaced_ms;
    bytes: bytes;
  };
}

// ---------------------------------------------------------------------------
// Surface
// ---------------------------------------------------------------------------

/// A link with the given seed and fixed one-way delay; no tables set
/// (everything arrives, in order).
pub fn sim_new(seed: Int, delay_ms: Int) -> SimLink {
  var drop: Vec[Int] = Vec[Int].new();
  var dup: Vec[Int] = Vec[Int].new();
  var d = delay_ms;
  if d < 0 { d = 0; }
  var s = SimSchedule {
    delay_ms: d;
    drop: drop;
    dup: dup;
    reorder_every: 0;
    reorder_distance: 0;
    seed: seed;
  };
  var ab: Vec[SimPacket] = Vec[SimPacket].new();
  var ba: Vec[SimPacket] = Vec[SimPacket].new();
  var cap: Vec[SimPacket] = Vec[SimPacket].new();
  return SimLink {
    schedule: s;
    clock_ms: 0;
    next_id: 0;
    rng: seed;
    q_ab: ab;
    q_ba: ba;
    capture: cap;
    sent: 0;
    delivered: 0;
    dropped: 0;
    duplicated: 0;
    displaced: 0;
  };
}

/// Replace the schedule tables (drop/dup ids, reorder cadence + max
/// distance).
pub fn sim_set_tables(l: &mut SimLink, drop: &Vec[Int], dup: &Vec[Int], reorder_every: Int, reorder_distance: Int) {
  var d: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < drop.len() {
    let x: Int = drop[i];
    d.push(x);
    i = i + 1;
  }
  var u: Vec[Int] = Vec[Int].new();
  var j = 0;
  while j < dup.len() {
    let x: Int = dup[j];
    u.push(x);
    j = j + 1;
  }
  l.schedule.drop = d;
  l.schedule.dup = u;
  var re = reorder_every;
  if re < 0 { re = 0; }
  var rd = reorder_distance;
  if rd < 0 { rd = 0; }
  l.schedule.reorder_every = re;
  l.schedule.reorder_distance = rd;
}

pub fn sim_now(l: &SimLink) -> Int {
  return l.clock_ms;
}

/// Advance the virtual clock (monotone; negative deltas are a refused
/// no-op returning the unchanged clock).
pub fn sim_advance(l: &mut SimLink, delta_ms: Int) -> Int {
  if delta_ms > 0 {
    l.clock_ms = l.clock_ms + delta_ms;
  }
  return l.clock_ms;
}

/// One send decision (a struct: the toolchain miscompiles mixed-element
/// tuples, so no tuple crosses a function boundary anywhere in this
/// package).
pub type SimDecision = {
  due_ms: Int;
  displaced_ms: Int;
  dropped: Bool;
  duplicated: Bool;
}

// Compute the due time and displacement for one send decision.
fn _schedule_one(l: &mut SimLink, id: Int) -> SimDecision {
  var displaced = 0;
  let every = l.schedule.reorder_every;
  if every > 0 && id % every == 0 {
    let r = _rng_next(l.rng);
    l.rng = r;
    var span = l.schedule.reorder_distance;
    if span < 1 { span = 1; }
    displaced = 1 + (r % span);
    l.displaced = l.displaced + 1;
  }
  let due = l.clock_ms + l.schedule.delay_ms + displaced;
  let is_drop = _in_list(&l.schedule.drop, id);
  let is_dup = _in_list(&l.schedule.dup, id);
  return SimDecision { due_ms: due; displaced_ms: displaced; dropped: is_drop; duplicated: is_dup };
}

fn _enqueue(l: &mut SimLink, p: SimPacket, from_a: Bool) {
  if from_a {
    l.q_ab.push(p);
  } else {
    l.q_ba.push(p);
  }
}

/// Send from endpoint A; returns the packet id. Dropped packets are
/// counted + captured but never queued.
pub fn sim_send_a(l: &mut SimLink, bytes: &Vec[UInt8]) -> Int {
  let id = l.next_id;
  l.next_id = id + 1;
  l.sent = l.sent + 1;
  let decision = _schedule_one(l, id);
  let due = decision.due_ms;
  let displaced = decision.displaced_ms;
  let is_drop = decision.dropped;
  let is_dup = decision.duplicated;
  var p = SimPacket {
    id: id;
    from_a: true;
    due_ms: due;
    dropped: is_drop;
    duplicated: is_dup;
    displaced_ms: displaced;
    bytes: _copy_bytes(bytes);
  };
  l.capture.push(_copy_packet(&p));
  if is_drop {
    l.dropped = l.dropped + 1;
    return id;
  }
  _enqueue(l, p, true);
  if is_dup {
    var p2 = SimPacket {
      id: id;
      from_a: true;
      due_ms: due + 1;
      dropped: false;
      duplicated: true;
      displaced_ms: displaced;
      bytes: _copy_bytes(bytes);
    };
    l.duplicated = l.duplicated + 1;
    _enqueue(l, p2, true);
  }
  return id;
}

/// Send from endpoint B; same conventions as sim_send_a.
pub fn sim_send_b(l: &mut SimLink, bytes: &Vec[UInt8]) -> Int {
  let id = l.next_id;
  l.next_id = id + 1;
  l.sent = l.sent + 1;
  let decision = _schedule_one(l, id);
  let due = decision.due_ms;
  let displaced = decision.displaced_ms;
  let is_drop = decision.dropped;
  let is_dup = decision.duplicated;
  var p = SimPacket {
    id: id;
    from_a: false;
    due_ms: due;
    dropped: is_drop;
    duplicated: is_dup;
    displaced_ms: displaced;
    bytes: _copy_bytes(bytes);
  };
  l.capture.push(_copy_packet(&p));
  if is_drop {
    l.dropped = l.dropped + 1;
    return id;
  }
  _enqueue(l, p, false);
  if is_dup {
    var p2 = SimPacket {
      id: id;
      from_a: false;
      due_ms: due + 1;
      dropped: false;
      duplicated: true;
      displaced_ms: displaced;
      bytes: _copy_bytes(bytes);
    };
    l.duplicated = l.duplicated + 1;
    _enqueue(l, p2, false);
  }
  return id;
}

// Release result: the released payloads plus their count (a plain struct
// keeps the direction explicit; no out-parameters).
pub type SimRelease = {
  packets: Vec[Vec[UInt8]];
  taken: Int;
}

// Take every packet with due_ms <= clock, ordered by (due_ms, insertion
// order) -- a stable deterministic release order. Rebuilds the queue
// without the taken packets.
fn _release(q: &mut Vec[SimPacket], now: Int) -> SimRelease {
  var out: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  var remaining: Vec[SimPacket] = Vec[SimPacket].new();
  var progress = true;
  var taken = 0;
  while progress {
    progress = false;
    var best = -1;
    var best_due = 0;
    var i = 0;
    while i < q.len() {
      let p: SimPacket = q[i];
      if p.due_ms <= now && (best < 0 || p.due_ms < best_due) {
        best = i;
        best_due = p.due_ms;
      }
      i = i + 1;
    }
    if best >= 0 {
      var j = 0;
      while j < q.len() {
        if j != best {
          let p: SimPacket = q[j];
          remaining.push(p);
        }
        j = j + 1;
      }
      let p: SimPacket = q[best];
      out.push(p.bytes);
      taken = taken + 1;
      q = remaining;
      remaining = Vec[SimPacket].new();
      progress = true;
    }
  }
  return SimRelease { packets: out; taken: taken };
}

/// Everything endpoint A has received by now (min due first), removed
/// from the wire.
pub fn sim_recv_a(l: &mut SimLink) -> Vec[Vec[UInt8]] {
  let rel = _release(&mut l.q_ba, l.clock_ms);
  l.delivered = l.delivered + rel.taken;
  return rel.packets;
}

/// Everything endpoint B has received by now, removed from the wire.
pub fn sim_recv_b(l: &mut SimLink) -> Vec[Vec[UInt8]] {
  let rel = _release(&mut l.q_ab, l.clock_ms);
  l.delivered = l.delivered + rel.taken;
  return rel.packets;
}

/// The full send-decision transcript (copy).
pub fn sim_capture(l: &SimLink) -> Vec[SimPacket] {
  var out: Vec[SimPacket] = Vec[SimPacket].new();
  var i = 0;
  while i < l.capture.len() {
    let p: SimPacket = l.capture[i];
    out.push(p);
    i = i + 1;
  }
  return out;
}

pub fn sim_stats(l: &SimLink) -> SimStats {
  return SimStats {
    clock_ms: l.clock_ms;
    sent: l.sent;
    delivered: l.delivered;
    dropped: l.dropped;
    duplicated: l.duplicated;
    displaced: l.displaced;
    pending_a_to_b: l.q_ab.len();
    pending_b_to_a: l.q_ba.len();
  };
}

/// A deterministic transcript digest: one line per captured packet
/// (id, direction, due, flags, length, byte checksum). Same seed + same
/// call sequence => identical digest.
pub fn sim_digest(l: &SimLink) -> Str {
  var out = "";
  var i = 0;
  while i < l.capture.len() {
    let p: SimPacket = l.capture[i];
    var dir = "a";
    if !p.from_a { dir = "b"; }
    var dropped = "0";
    if p.dropped { dropped = "1"; }
    var dup = "0";
    if p.duplicated { dup = "1"; }
    var sum = 0;
    var j = 0;
    while j < p.bytes.len() {
      let b: UInt8 = p.bytes[j];
      sum = (sum + (b as Int)) & 255;
      j = j + 1;
    }
    if i > 0 { out = out + ";"; }
    out = out + p.id.to_str() + ":" + dir + ":" + p.due_ms.to_str() + ":" + dropped + ":" + dup + ":" + p.bytes.len().to_str() + ":" + sum.to_str();
    i = i + 1;
  }
  return out;
}
