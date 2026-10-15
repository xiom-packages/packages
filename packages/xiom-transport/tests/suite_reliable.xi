// XIOM -- xiom.transport conformance suite, part 2: reliability engine
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic checks of the pure reliability engine against an injected
// clock: window bounds, ack + bitfield processing, RTO/backoff and the
// exhausted-retries verdict, duplicate suppression, ordered vs unordered
// delivery under reorder, stale/out-of-window refusals, the explicit
// gap-skip recovery and exact stats math. No wall clock, no sockets.

module xiom.transport.suite_reliable

use xiom.io;
use xiom.test;
use xiom.transport.reliable;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn payload1(seed: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  out.push((seed & 255) as UInt8);
  return out;
}

fn open_ok(e: &mut RlEngine, id: Int, rel: Bool, ord: Bool, win: Int) -> Bool {
  let r = rl_open_channel(e, id, rel, ord, 0, win);
  if !r.is_ok { return false; }
  return r.value;
}

fn seqs_are(r: Result[Vec[Int], RlError], want: Vec[Int]) -> Bool {
  if !r.is_ok { return false; }
  let got: Vec[Int] = r.value;
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    let g: Int = got[i];
    let w: Int = want[i];
    if g != w { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// r1: bounded send window and unacked map
// ---------------------------------------------------------------------------

fn r1() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 4, true, true, 3) { ok = false; }
  let re = rl_open_channel(&mut e, 4, true, true, 0, 3);
  if !re.is_ok { ok = false; } else { if re.value { ok = false; } }
  var p = payload1(1);
  var i = 0;
  while i < 3 {
    let s = rl_send(&mut e, 4, &p, 0);
    if !s.is_ok { ok = false; } else { if s.value.seq != i { ok = false; } }
    i = i + 1;
  }
  let s4 = rl_send(&mut e, 4, &p, 0);
  if s4.is_ok { ok = false; } else {
    let e4: RlError = s4.error;
    if e4.kind != RL_ERR_WINDOW { ok = false; }
  }
  let il = rl_inflight_len(&e, 4);
  if !il.is_ok { ok = false; } else { if il.value != 3 { ok = false; } }
  var want1: Vec[Int] = Vec[Int].new();
  want1.push(0); want1.push(1); want1.push(2);
  if !seqs_are(rl_unacked_seqs(&e, 4), want1) { ok = false; }
  // ack seq 0 only -> window slot frees, next send takes seq 3
  let a = rl_on_ack(&mut e, 4, 0, 0);
  if !a.is_ok { ok = false; } else { if a.value != 1 { ok = false; } }
  var want2: Vec[Int] = Vec[Int].new();
  want2.push(1); want2.push(2);
  if !seqs_are(rl_unacked_seqs(&e, 4), want2) { ok = false; }
  let s5 = rl_send(&mut e, 4, &p, 0);
  if !s5.is_ok { ok = false; } else { if s5.value.seq != 3 { ok = false; } }
  // window 500 clamps to RL_MAX_WINDOW (32)
  if !open_ok(&mut e, 5, true, true, 500) { ok = false; }
  var k = 0;
  while k < RL_MAX_WINDOW {
    let s = rl_send(&mut e, 5, &p, 0);
    if !s.is_ok { ok = false; }
    k = k + 1;
  }
  let over = rl_send(&mut e, 5, &p, 0);
  if over.is_ok { ok = false; } else {
    let eo: RlError = over.error;
    if eo.kind != RL_ERR_WINDOW { ok = false; }
  }
  return test.assert(ok, "reliable: bounded send window, unacked map and ack slot reuse");
}

// ---------------------------------------------------------------------------
// r2: ack + ack-bitfield processing
// ---------------------------------------------------------------------------

fn r2() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 0, true, true, 32) { ok = false; }
  var p = payload1(2);
  var i = 0;
  while i < 6 {
    let s = rl_send(&mut e, 0, &p, 0);
    if !s.is_ok { ok = false; }
    i = i + 1;
  }
  // ack = 5 with bits {0,1,3,4} (27) marks seq 2 missing
  let a = rl_on_ack(&mut e, 0, 5, 27);
  if !a.is_ok { ok = false; } else { if a.value != 5 { ok = false; } }
  var want: Vec[Int] = Vec[Int].new();
  want.push(2);
  if !seqs_are(rl_unacked_seqs(&e, 0), want) { ok = false; }
  // the pure coverage predicate
  if !rl_seq_acked(5, 5, 0) { ok = false; }
  if !rl_seq_acked(0, 5, 27) { ok = false; }
  if !rl_seq_acked(3, 5, 27) { ok = false; }
  if rl_seq_acked(2, 5, 27) { ok = false; }
  if rl_seq_acked(6, 5, 27) { ok = false; }
  if rl_seq_acked(0, -1, 0) { ok = false; }
  if rl_seq_acked(-5, 5, 27) { ok = false; }
  // ack -1 (nothing received) never acks anything
  let a2 = rl_on_ack(&mut e, 0, -1, 4294967295);
  if !a2.is_ok { ok = false; } else { if a2.value != 0 { ok = false; } }
  var want2: Vec[Int] = Vec[Int].new();
  want2.push(2);
  if !seqs_are(rl_unacked_seqs(&e, 0), want2) { ok = false; }
  // unknown channel is a typed verdict
  let a3 = rl_on_ack(&mut e, 99, 0, 0);
  if a3.is_ok { ok = false; } else {
    let e3: RlError = a3.error;
    if e3.kind != RL_ERR_CHANNEL { ok = false; }
  }
  return test.assert(ok, "reliable: ack + 32-bit ack-bitfield processing");
}

// ---------------------------------------------------------------------------
// r3: RTO with bounded exponential backoff + exhausted-retries verdict
// ---------------------------------------------------------------------------

fn r3() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 0, true, true, 32) { ok = false; }
  var p = payload1(3);
  let s = rl_send(&mut e, 0, &p, 0);
  if !s.is_ok { ok = false; }
  // the backoff ladder: 100, 200, 400, 800, 1600, 3200 (capped)
  if rl_rto_ms(0) != 100 { ok = false; }
  if rl_rto_ms(1) != 200 { ok = false; }
  if rl_rto_ms(2) != 400 { ok = false; }
  if rl_rto_ms(3) != 800 { ok = false; }
  if rl_rto_ms(4) != 1600 { ok = false; }
  if rl_rto_ms(5) != 3200 { ok = false; }
  if rl_rto_ms(9) != 3200 { ok = false; }
  let p0 = rl_poll_rtx(&mut e, 99);
  if !p0.is_ok { ok = false; } else { if p0.value.len() != 0 { ok = false; } }
  // retries at the exact due times 100, 300, 700, 1500
  var due: Vec[Int] = Vec[Int].new();
  due.push(100); due.push(300); due.push(700); due.push(1500);
  var ri = 0;
  while ri < due.len() {
    let t: Int = due[ri];
    let rtx = rl_poll_rtx(&mut e, t);
    if !rtx.is_ok { ok = false; } else {
      let outs: Vec[RlOutbound] = rtx.value;
      if outs.len() != 1 { ok = false; } else {
        let ob: RlOutbound = outs[0];
        if ob.seq != 0 { ok = false; }
        if ob.payload.len() != 1 { ok = false; }
      }
    }
    ri = ri + 1;
  }
  // between the rungs nothing is due
  let p295 = rl_poll_rtx(&mut e, 299);
  if !p295.is_ok { ok = false; } else { if p295.value.len() != 0 { ok = false; } }
  // the sixth rung is the verdict: failure, not another retransmit
  let p3100 = rl_poll_rtx(&mut e, 3100);
  if !p3100.is_ok { ok = false; } else { if p3100.value.len() != 0 { ok = false; } }
  let fails = rl_take_failures(&mut e);
  if fails.len() != 1 { ok = false; } else {
    let f: RlFailure = fails[0];
    if f.kind != RL_ERR_RETRIES { ok = false; }
    if f.channel != 0 { ok = false; }
    if f.seq != 0 { ok = false; }
  }
  let il = rl_inflight_len(&e, 0);
  if !il.is_ok { ok = false; } else { if il.value != 0 { ok = false; } }
  let cs = rl_channel_stats(&e, 0);
  if !cs.is_ok { ok = false; } else {
    let c: RlChannelStats = cs.value;
    if c.retransmits != 4 { ok = false; }
    if c.timeouts != 1 { ok = false; }
  }
  // draining the verdict twice never double-reports
  let again = rl_take_failures(&mut e);
  if again.len() != 0 { ok = false; }
  return test.assert(ok, "reliable: RTO ladder (100..3200) and exhausted-retries verdict");
}

// ---------------------------------------------------------------------------
// r4: duplicate suppression (stale below recv_next; in-window bit duplicates)
// ---------------------------------------------------------------------------

fn r4() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 1, true, true, 32) { ok = false; }
  let a = rl_on_packet(&mut e, 1, 0, &payload1(10), 0);
  if !a.is_ok { ok = false; } else {
    let ra: RlRecvResult = a.value;
    if ra.delivered.len() != 1 { ok = false; }
    if ra.ack != 0 { ok = false; }
  }
  // a resend of seq 0 is stale (below recv_next)
  let b = rl_on_packet(&mut e, 1, 0, &payload1(10), 0);
  if !b.is_ok { ok = false; } else {
    let rb: RlRecvResult = b.value;
    if !rb.stale { ok = false; }
    if rb.delivered.len() != 0 { ok = false; }
    if rb.ack != 0 { ok = false; }
  }
  // seq 2 first (held), then seq 2 again: in-window duplicate
  let c = rl_on_packet(&mut e, 1, 2, &payload1(12), 0);
  if !c.is_ok { ok = false; } else {
    let rc: RlRecvResult = c.value;
    if !rc.held { ok = false; }
    if rc.delivered.len() != 0 { ok = false; }
  }
  let d = rl_on_packet(&mut e, 1, 2, &payload1(12), 0);
  if !d.is_ok { ok = false; } else {
    let rd: RlRecvResult = d.value;
    if !rd.duplicate { ok = false; }
    if rd.held { ok = false; }
  }
  // seq 1 closes the gap: 1 then 2 are delivered in order
  let f = rl_on_packet(&mut e, 1, 1, &payload1(11), 0);
  if !f.is_ok { ok = false; } else {
    let rf: RlRecvResult = f.value;
    if rf.delivered.len() != 2 { ok = false; } else {
      let m0: RlMessage = rf.delivered[0];
      let m1: RlMessage = rf.delivered[1];
      if m0.seq != 1 { ok = false; }
      if m1.seq != 2 { ok = false; }
    }
    if rf.ack != 2 { ok = false; }
  }
  let cs = rl_channel_stats(&e, 1);
  if !cs.is_ok { ok = false; } else {
    let cstat: RlChannelStats = cs.value;
    if cstat.dup_dropped != 2 { ok = false; }
    if cstat.stale != 1 { ok = false; }
    if cstat.delivered != 3 { ok = false; }
    if cstat.held != 1 { ok = false; }
  }
  return test.assert(ok, "reliable: duplicate suppression (stale + in-window bit) and gap flush");
}

// ---------------------------------------------------------------------------
// r5: ordered buffering vs unordered immediate flush under reorder
// ---------------------------------------------------------------------------

fn r5() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 0, true, true, 32) { ok = false; }
  if !open_ok(&mut e, 1, true, false, 32) { ok = false; }
  // ordered channel: 2,1,0 arrive; nothing delivers until 0 closes the gap
  let a2 = rl_on_packet(&mut e, 0, 2, &payload1(12), 0);
  if !a2.is_ok { ok = false; } else { if a2.value.delivered.len() != 0 { ok = false; } }
  let a1 = rl_on_packet(&mut e, 0, 1, &payload1(11), 0);
  if !a1.is_ok { ok = false; } else { if a1.value.delivered.len() != 0 { ok = false; } }
  let a0 = rl_on_packet(&mut e, 0, 0, &payload1(10), 0);
  if !a0.is_ok { ok = false; } else {
    let ra: RlRecvResult = a0.value;
    if ra.delivered.len() != 3 { ok = false; } else {
      let m0: RlMessage = ra.delivered[0];
      let m1: RlMessage = ra.delivered[1];
      let m2: RlMessage = ra.delivered[2];
      if m0.seq != 0 { ok = false; }
      if m1.seq != 1 { ok = false; }
      if m2.seq != 2 { ok = false; }
      let b0: UInt8 = m0.payload[0];
      let b1: UInt8 = m1.payload[0];
      let b2: UInt8 = m2.payload[0];
      if (b0 as Int) != 10 { ok = false; }
      if (b1 as Int) != 11 { ok = false; }
      if (b2 as Int) != 12 { ok = false; }
    }
    if ra.ack != 2 { ok = false; }
  }
  // unordered channel: same arrival order, immediate flush in arrival order
  let u2 = rl_on_packet(&mut e, 1, 2, &payload1(22), 0);
  if !u2.is_ok { ok = false; } else {
    let ru: RlRecvResult = u2.value;
    if ru.delivered.len() != 1 { ok = false; }
    if ru.held { ok = false; }
  }
  let u0 = rl_on_packet(&mut e, 1, 0, &payload1(20), 0);
  if !u0.is_ok { ok = false; } else { if u0.value.delivered.len() != 1 { ok = false; } }
  let u1 = rl_on_packet(&mut e, 1, 1, &payload1(21), 0);
  if !u1.is_ok { ok = false; } else { if u1.value.delivered.len() != 1 { ok = false; } }
  let rn = rl_recv_next(&e, 1);
  if !rn.is_ok { ok = false; } else { if rn.value != 3 { ok = false; } }
  let hl = rl_held_len(&e, 0);
  if !hl.is_ok { ok = false; } else { if hl.value != 0 { ok = false; } }
  return test.assert(ok, "reliable: ordered buffer flushes in order; unordered flushes on arrival");
}

// ---------------------------------------------------------------------------
// r6: stale and out-of-window refusals at the window edge
// ---------------------------------------------------------------------------

fn r6() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 0, true, true, 32) { ok = false; }
  var i = 0;
  while i < 3 {
    let r = rl_on_packet(&mut e, 0, i, &payload1(i), 0);
    if !r.is_ok { ok = false; }
    i = i + 1;
  }
  // seq 1 is below recv_next (3): stale
  let st = rl_on_packet(&mut e, 0, 1, &payload1(1), 0);
  if !st.is_ok { ok = false; } else { if !st.value.stale { ok = false; } }
  // seq 66 = recv_next + 63: the last in-window slot, accepted and held
  let edge = rl_on_packet(&mut e, 0, 66, &payload1(66), 0);
  if !edge.is_ok { ok = false; } else {
    let re: RlRecvResult = edge.value;
    if !re.held { ok = false; }
    if re.out_of_window { ok = false; }
  }
  let hl = rl_held_len(&e, 0);
  if !hl.is_ok { ok = false; } else { if hl.value != 1 { ok = false; } }
  // seq 67 = recv_next + 64: beyond the window, refused
  let far = rl_on_packet(&mut e, 0, 67, &payload1(67), 0);
  if !far.is_ok { ok = false; } else {
    let rf: RlRecvResult = far.value;
    if !rf.out_of_window { ok = false; }
    if rf.delivered.len() != 0 { ok = false; }
  }
  let cs = rl_channel_stats(&e, 0);
  if !cs.is_ok { ok = false; } else {
    let c: RlChannelStats = cs.value;
    if c.stale != 1 { ok = false; }
    if c.out_of_window != 1 { ok = false; }
  }
  return test.assert(ok, "reliable: stale below recv_next and out-of-window beyond +63 are refused");
}

// ---------------------------------------------------------------------------
// r7: explicit gap skip (unreliable-ordered recovery)
// ---------------------------------------------------------------------------

fn r7() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 2, false, true, 8) { ok = false; }
  let h = rl_on_packet(&mut e, 2, 4, &payload1(44), 0);
  if !h.is_ok { ok = false; } else { if !h.value.held { ok = false; } }
  // skipping past the held seq delivers it in order
  let sg = rl_skip_gap(&mut e, 2, 4);
  if !sg.is_ok { ok = false; } else {
    let msgs: Vec[RlMessage] = sg.value;
    if msgs.len() != 1 { ok = false; } else {
      let m: RlMessage = msgs[0];
      if m.seq != 4 { ok = false; }
    }
  }
  let rn = rl_recv_next(&e, 2);
  if !rn.is_ok { ok = false; } else { if rn.value != 5 { ok = false; } }
  let hl = rl_held_len(&e, 2);
  if !hl.is_ok { ok = false; } else { if hl.value != 0 { ok = false; } }
  // a skip below recv_next is a no-op
  let sg2 = rl_skip_gap(&mut e, 2, 3);
  if !sg2.is_ok { ok = false; } else { if sg2.value.len() != 0 { ok = false; } }
  // unknown channel is typed
  let sg3 = rl_skip_gap(&mut e, 9, 0);
  if sg3.is_ok { ok = false; } else {
    let e3: RlError = sg3.error;
    if e3.kind != RL_ERR_CHANNEL { ok = false; }
  }
  return test.assert(ok, "reliable: rl_skip_gap closes an unreliable-ordered gap explicitly");
}

// ---------------------------------------------------------------------------
// r8: stats math is exact (aggregate == sum over channels)
// ---------------------------------------------------------------------------

fn r8() -> TestResult {
  var e = rl_new();
  var ok = true;
  if !open_ok(&mut e, 0, true, true, 32) { ok = false; }
  if !open_ok(&mut e, 3, false, false, 32) { ok = false; }
  let s1 = rl_send(&mut e, 0, &payload1(1), 0);
  if !s1.is_ok { ok = false; }
  let s2 = rl_send(&mut e, 0, &payload1(2), 0);
  if !s2.is_ok { ok = false; }
  let s3 = rl_send(&mut e, 3, &payload1(3), 0);
  if !s3.is_ok { ok = false; }
  let a = rl_on_packet(&mut e, 0, 0, &payload1(1), 0);
  if !a.is_ok { ok = false; }
  let b = rl_on_packet(&mut e, 0, 1, &payload1(2), 0);
  if !b.is_ok { ok = false; }
  let c = rl_on_packet(&mut e, 3, 0, &payload1(3), 0);
  if !c.is_ok { ok = false; }
  let d = rl_on_packet(&mut e, 3, 1, &payload1(4), 0);
  if !d.is_ok { ok = false; }
  let st = rl_on_packet(&mut e, 3, 0, &payload1(1), 0);
  if !st.is_ok { ok = false; } else { if !st.value.stale { ok = false; } }
  let ack = rl_on_ack(&mut e, 0, 1, 1);
  if !ack.is_ok { ok = false; } else { if ack.value != 2 { ok = false; } }
  let s = rl_stats(&e);
  if s.sent != 3 { ok = false; }
  if s.recv != 4 { ok = false; }
  if s.delivered != 4 { ok = false; }
  if s.acked != 2 { ok = false; }
  if s.retransmits != 0 { ok = false; }
  if s.dup_dropped != 1 { ok = false; }
  if s.stale != 1 { ok = false; }
  if s.out_of_window != 0 { ok = false; }
  if s.timeouts != 0 { ok = false; }
  if s.held != 0 { ok = false; }
  // per-channel views agree with the aggregate
  let c0 = rl_channel_stats(&e, 0);
  if !c0.is_ok { ok = false; } else {
    let cs0: RlChannelStats = c0.value;
    if cs0.sent != 2 { ok = false; }
    if cs0.delivered != 2 { ok = false; }
    if cs0.acked != 2 { ok = false; }
  }
  let c3 = rl_channel_stats(&e, 3);
  if !c3.is_ok { ok = false; } else {
    let cs3: RlChannelStats = c3.value;
    if cs3.sent != 1 { ok = false; }
    if cs3.delivered != 2 { ok = false; }
    if cs3.stale != 1 { ok = false; }
  }
  if rl_channel_count(&e) != 2 { ok = false; }
  if !rl_channel_exists(&e, 0) { ok = false; }
  if rl_channel_exists(&e, 7) { ok = false; }
  if !rl_close_channel(&mut e, 3) { ok = false; }
  if rl_close_channel(&mut e, 3) { ok = false; }
  if rl_channel_count(&e) != 1 { ok = false; }
  return test.assert(ok, "reliable: exact stats math (aggregate == per-channel sums)");
}

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = r1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = r2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = r3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = r4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = r5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = r6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = r7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = r8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  return failed;
}
