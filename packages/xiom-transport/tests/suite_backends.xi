// XIOM -- xiom.transport conformance suite, part 4: backends + facade
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Loopback byte-exactness/FIFO and honest counters; the null backend's
// provably-empty honesty; sim determinism (same seed => same transcript);
// the sim loss/duplicate/reorder tables; the virtual clock; and the root
// facade (open/close/send/peer-send/poll/advance, cap facts, stats,
// reconnect policy interpreter).

module xiom.transport.suite_backends

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.transport;
use xiom.transport.caps;
use xiom.transport.session;
use xiom.transport.loopback;
use xiom.transport.null;
use xiom.transport.sim;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  let n = s.len();
  while i < n {
    let b: UInt8 = s.byte_at(i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn bytes_to_str(b: &Vec[UInt8]) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < b.len() {
    let x: UInt8 = b[i];
    out.push(x);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

fn same_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// b1: loopback byte-exact FIFO roundtrip + counters + close refusal
// ---------------------------------------------------------------------------

fn b1() -> TestResult {
  var ok = true;
  var l = loopback_new();
  let alpha = bytes_of("alpha");
  let beta = bytes_of("beta");
  let gamma = bytes_of("gamma");
  let i0 = loopback_send_a(&mut l, &alpha);
  let i1 = loopback_send_a(&mut l, &beta);
  let i2 = loopback_send_b(&mut l, &gamma);
  if i0 != 0 { ok = false; }
  if i1 != 1 { ok = false; }
  if i2 != 2 { ok = false; }
  if loopback_pending_b(&l) != 2 { ok = false; }
  if loopback_pending_a(&l) != 1 { ok = false; }
  let ra = loopback_poll_a(&mut l);
  if ra.len() != 1 { ok = false; } else {
    let g: Vec[UInt8] = ra[0];
    if !same_bytes(&g, &gamma) { ok = false; }
  }
  let rb = loopback_poll_b(&mut l);
  if rb.len() != 2 { ok = false; } else {
    let a0: Vec[UInt8] = rb[0];
    let a1: Vec[UInt8] = rb[1];
    if !same_bytes(&a0, &alpha) { ok = false; }
    if !same_bytes(&a1, &beta) { ok = false; }
  }
  let r2 = loopback_poll_b(&mut l);
  if r2.len() != 0 { ok = false; }
  let st = loopback_stats(&l);
  if st.sent_a != 2 { ok = false; }
  if st.sent_b != 1 { ok = false; }
  if st.delivered_a != 1 { ok = false; }
  if st.delivered_b != 2 { ok = false; }
  if st.bytes_sent != 14 { ok = false; }
  if st.bytes_delivered != 14 { ok = false; }
  if st.refused != 0 { ok = false; }
  if !st.open { ok = false; }
  loopback_close(&mut l);
  if loopback_is_open(&l) { ok = false; }
  let dead = loopback_send_a(&mut l, &alpha);
  if dead != -1 { ok = false; }
  let st2 = loopback_stats(&l);
  if st2.refused != 1 { ok = false; }
  return test.assert(ok, "loopback: byte-exact FIFO both directions, counters, close refusal");
}

// ---------------------------------------------------------------------------
// b2: null honesty -- everything counted, nothing delivered
// ---------------------------------------------------------------------------

fn b2() -> TestResult {
  var ok = true;
  var t = null_new();
  let x = bytes_of("xx");
  let y = bytes_of("yyy");
  if !null_send(&mut t, &x) { ok = false; }
  if !null_send(&mut t, &y) { ok = false; }
  let p = null_poll(&mut t);
  if p.len() != 0 { ok = false; }
  let p2 = null_poll(&mut t);
  if p2.len() != 0 { ok = false; }
  let st = null_stats(&t);
  if st.sent != 2 { ok = false; }
  if st.bytes_sent != 5 { ok = false; }
  if st.polls != 2 { ok = false; }
  if st.delivered != 0 { ok = false; }
  if st.bytes_delivered != 0 { ok = false; }
  if st.sends_refused != 0 { ok = false; }
  if !st.open { ok = false; }
  null_close(&mut t);
  if null_is_open(&t) { ok = false; }
  if null_send(&mut t, &x) { ok = false; }
  let st2 = null_stats(&t);
  if st2.sends_refused != 1 { ok = false; }
  if st2.delivered != 0 { ok = false; }
  return test.assert(ok, "null: sends/polls/bytes counted, delivered stays a provable zero");
}

// ---------------------------------------------------------------------------
// b3: sim determinism -- same seed => same transcript
// ---------------------------------------------------------------------------

fn sim_script() -> Str {
  var l = sim_new(1234, 5);
  var drop: Vec[Int] = Vec[Int].new();
  drop.push(1);
  var dup: Vec[Int] = Vec[Int].new();
  dup.push(3);
  sim_set_tables(&mut l, &drop, &dup, 2, 7);
  sim_send_a(&mut l, &bytes_of("p0"));
  sim_send_b(&mut l, &bytes_of("p1"));
  sim_send_a(&mut l, &bytes_of("p2"));
  sim_send_b(&mut l, &bytes_of("p3"));
  sim_send_a(&mut l, &bytes_of("p4"));
  sim_advance(&mut l, 3);
  let r1 = sim_recv_a(&mut l);
  let r2 = sim_recv_b(&mut l);
  sim_advance(&mut l, 50);
  let r3 = sim_recv_a(&mut l);
  let r4 = sim_recv_b(&mut l);
  let st = sim_stats(&l);
  var tail = "|a=" + r1.len().to_str() + ",b=" + r2.len().to_str() + ",a2=" + r3.len().to_str() + ",b2=" + r4.len().to_str();
  tail = tail + "|sent=" + st.sent.to_str() + ",delivered=" + st.delivered.to_str();
  tail = tail + ",dropped=" + st.dropped.to_str() + ",duplicated=" + st.duplicated.to_str() + ",displaced=" + st.displaced.to_str();
  return sim_digest(&l) + tail;
}

fn b3() -> TestResult {
  var ok = true;
  let t1 = sim_script();
  let t2 = sim_script();
  if !streq(t1, t2) { ok = false; }
  if t1.len() == 0 { ok = false; }
  // the transcript reflects the schedule exactly: 5 sends, 1 drop, 1 dup
  if !string.str_contains(t1, "sent=5") { ok = false; }
  if !string.str_contains(t1, "dropped=1") { ok = false; }
  if !string.str_contains(t1, "duplicated=1") { ok = false; }
  return test.assert(ok, "sim: same seed + same call sequence => identical transcript digest");
}

// ---------------------------------------------------------------------------
// b4: sim drop / duplicate / reorder tables behave exactly
// ---------------------------------------------------------------------------

fn b4() -> TestResult {
  var ok = true;
  var l = sim_new(99, 10);
  var drop: Vec[Int] = Vec[Int].new();
  drop.push(3);
  var dup: Vec[Int] = Vec[Int].new();
  dup.push(2);
  sim_set_tables(&mut l, &drop, &dup, 2, 1000);
  sim_send_a(&mut l, &bytes_of("k0"));
  sim_send_a(&mut l, &bytes_of("k1"));
  sim_send_a(&mut l, &bytes_of("k2"));
  sim_send_a(&mut l, &bytes_of("k3"));
  let st0 = sim_stats(&l);
  if st0.sent != 4 { ok = false; }
  if st0.dropped != 1 { ok = false; }
  if st0.duplicated != 1 { ok = false; }
  if st0.displaced != 2 { ok = false; }
  if st0.pending_a_to_b != 4 { ok = false; }   // k0, k1, k2 + k2's copy; k3 was dropped
  sim_advance(&mut l, 10);
  let r1 = sim_recv_b(&mut l);
  if r1.len() != 1 { ok = false; } else {
    let only: Vec[UInt8] = r1[0];
    if !streq(bytes_to_str(&only), "k1") { ok = false; }
  }
  sim_advance(&mut l, 5000);
  let r2 = sim_recv_b(&mut l);
  if r2.len() != 3 { ok = false; } else {
    var k0 = 0;
    var k2 = 0;
    var i = 0;
    while i < r2.len() {
      let p: Vec[UInt8] = r2[i];
      let s = bytes_to_str(&p);
      if streq(s, "k0") { k0 = k0 + 1; }
      if streq(s, "k2") { k2 = k2 + 1; }
      i = i + 1;
    }
    if k0 != 1 { ok = false; }
    if k2 != 2 { ok = false; }
  }
  let st1 = sim_stats(&l);
  if st1.delivered != 4 { ok = false; }
  if st1.pending_a_to_b != 0 { ok = false; }
  return test.assert(ok, "sim: drop table drops, dup table duplicates (+1ms), reorder displaces deterministically");
}

// ---------------------------------------------------------------------------
// b5: sim virtual clock -- nothing arrives before due time
// ---------------------------------------------------------------------------

fn b5() -> TestResult {
  var ok = true;
  var l = sim_new(5, 10);
  if sim_now(&l) != 0 { ok = false; }
  if sim_advance(&mut l, 50) != 50 { ok = false; }
  if sim_advance(&mut l, -5) != 50 { ok = false; }
  sim_send_a(&mut l, &bytes_of("z"));
  if sim_stats(&l).pending_a_to_b != 1 { ok = false; }
  let r0 = sim_recv_b(&mut l);
  if r0.len() != 0 { ok = false; }
  sim_advance(&mut l, 9);
  let r1 = sim_recv_b(&mut l);
  if r1.len() != 0 { ok = false; }
  sim_advance(&mut l, 1);
  let r2 = sim_recv_b(&mut l);
  if r2.len() != 1 { ok = false; } else {
    let p: Vec[UInt8] = r2[0];
    if !streq(bytes_to_str(&p), "z") { ok = false; }
  }
  let st = sim_stats(&l);
  if st.pending_a_to_b != 0 { ok = false; }
  if st.delivered != 1 { ok = false; }
  return test.assert(ok, "sim: virtual clock releases packets exactly at due time");
}

// ---------------------------------------------------------------------------
// b6: root facade -- lifecycle, byte paths, cap facts, reconnect policy
// ---------------------------------------------------------------------------

fn b6() -> TestResult {
  var ok = true;
  // loopback facade
  let ro = transport_open(TX_KIND_LOOPBACK);
  if !ro.is_ok { ok = false; } else {
    var h: TransportHandle = ro.value;
    if session_state_code(transport_state(&h)) != 2 { ok = false; }
    if session_state_code(transport_state(&h)) != 2 { ok = false; }
    if !transport_is_open(&h) { ok = false; }
    if !streq(transport_state_name(&h), "active") { ok = false; }
    if !streq(transport_kind_name(TX_KIND_LOOPBACK), "loopback") { ok = false; }
    let cf = transport_caps(&h);
    if !cf.reliable { ok = false; }
    if !cf.ordered { ok = false; }
    if cf.max_datagram != TX_CAP_MAX_DATAGRAM { ok = false; }
    if cf.max_payload != TX_CAP_MAX_PAYLOAD { ok = false; }
    if cf.mtu_estimate != 65535 { ok = false; }
    if !cf.channels { ok = false; }
    if !cf.reliable_unordered { ok = false; }
    let ping = bytes_of("ping");
    let s1 = transport_send(&mut h, &ping);
    if !s1.is_ok { ok = false; } else { if s1.value != 0 { ok = false; } }
    if transport_pending_out(&h) != 1 { ok = false; }
    let e1 = transport_poll(&mut h);
    if !e1.is_ok { ok = false; } else { if e1.value.len() != 0 { ok = false; } }
    let pong = bytes_of("pong");
    let ps = transport_peer_send(&mut h, &pong);
    if !ps.is_ok { ok = false; }
    if transport_pending_in(&h) != 1 { ok = false; }
    let p1 = transport_poll(&mut h);
    if !p1.is_ok { ok = false; } else {
      let got: Vec[Vec[UInt8]] = p1.value;
      if got.len() != 1 { ok = false; } else {
        let g: Vec[UInt8] = got[0];
        if !same_bytes(&g, &pong) { ok = false; }
      }
    }
    let st = transport_stats(&h);
    if st.sent != 1 { ok = false; }
    if st.received != 1 { ok = false; }
    if st.bytes_sent != 4 { ok = false; }
    if st.bytes_received != 4 { ok = false; }
    transport_close(&mut h);
    if transport_is_open(&h) { ok = false; }
    let dead = transport_send(&mut h, &ping);
    if dead.is_ok { ok = false; } else {
      let de: TxError = dead.error;
      if de.kind != TXE_CLOSED { ok = false; }
    }
    let st2 = transport_stats(&h);
    if st2.refused != 1 { ok = false; }
    // reconnect policy interpreter (data, deterministic jitter)
    let pol = transport_reconnect(&h);
    if pol.max_attempts != 5 { ok = false; }
    if reconnect_delay_ms(&pol, 1) != 287 { ok = false; }
    if reconnect_delay_ms(&pol, 2) != 521 { ok = false; }
    if reconnect_delay_ms(&pol, 5) != 4026 { ok = false; }
    if reconnect_delay_ms(&pol, 6) != -1 { ok = false; }
    var constpol = ReconnectPolicy { max_attempts: 3; base_delay_ms: 100; max_delay_ms: 1000; backoff: RECONNECT_BACKOFF_CONSTANT; jitter: false; };
    if reconnect_delay_ms(&constpol, 1) != 100 { ok = false; }
    if reconnect_delay_ms(&constpol, 3) != 100 { ok = false; }
    if reconnect_delay_ms(&constpol, 4) != -1 { ok = false; }
    var linpol = ReconnectPolicy { max_attempts: 4; base_delay_ms: 100; max_delay_ms: 1000; backoff: RECONNECT_BACKOFF_LINEAR; jitter: false; };
    if reconnect_delay_ms(&linpol, 3) != 300 { ok = false; }
  }
  // null facade: counted, never delivered
  let rn = transport_open(TX_KIND_NULL);
  if !rn.is_ok { ok = false; } else {
    var hn: TransportHandle = rn.value;
    let cf2 = transport_caps(&hn);
    if cf2.reliable { ok = false; }
    if cf2.max_datagram != 0 { ok = false; }
    if cf2.channels { ok = false; }
    let x = bytes_of("x");
    let sn = transport_send(&mut hn, &x);
    if !sn.is_ok { ok = false; }
    let pn = transport_peer_send(&mut hn, &x);
    if !pn.is_ok { ok = false; }
    let en = transport_poll(&mut hn);
    if !en.is_ok { ok = false; } else { if en.value.len() != 0 { ok = false; } }
    let stn = transport_stats(&hn);
    if stn.sent != 1 { ok = false; }
    if stn.received != 1 { ok = false; }
    transport_close(&mut hn);
  }
  // sim facade: virtual clock through the facade
  let rs = transport_open_sim(3, 4);
  if !rs.is_ok { ok = false; } else {
    var hs: TransportHandle = rs.value;
    let t = bytes_of("t");
    let pts = transport_peer_send(&mut hs, &t);
    if !pts.is_ok { ok = false; }
    let es = transport_poll(&mut hs);
    if !es.is_ok { ok = false; } else { if es.value.len() != 0 { ok = false; } }
    let now = transport_advance(&mut hs, 4);
    if !now.is_ok { ok = false; } else { if now.value != 4 { ok = false; } }
    let es2 = transport_poll(&mut hs);
    if !es2.is_ok { ok = false; } else { if es2.value.len() != 1 { ok = false; } }
    transport_close(&mut hs);
  }
  // unsupported opens are typed
  let ru = transport_open(TX_KIND_UDP);
  if ru.is_ok { ok = false; } else {
    let ue: TxError = ru.error;
    if ue.kind != TXE_KIND { ok = false; }
  }
  let rx = transport_open(77);
  if rx.is_ok { ok = false; } else {
    let xe: TxError = rx.error;
    if xe.kind != TXE_KIND { ok = false; }
  }
  // cap facts for every backend kind
  if !caps_known_kind(TX_KIND_UDP) { ok = false; }
  if caps_known_kind(77) { ok = false; }
  let cs = caps_for_kind(TX_KIND_SIM);
  if cs.reliable { ok = false; }
  if cs.mtu_estimate != 1500 { ok = false; }
  let cu = caps_for_kind(TX_KIND_UDP);
  if cu.max_payload != TX_CAP_MAX_PAYLOAD { ok = false; }
  if !cu.reliable_unordered { ok = false; }
  let cn = caps_for_kind(77);
  if cn.max_datagram != 0 { ok = false; }
  return test.assert(ok, "facade: open/state/send/peer/poll/close, caps matrix, reconnect policy math");
}

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = b1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = b2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = b3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = b4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = b5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = b6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  return failed;
}
