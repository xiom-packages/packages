// XIOM -- xiom.transport conformance suite, part 6: handler chain + rate
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Additive extension checks: deterministic outbound/inbound handler order,
// both transform directions, per-entry/whole-chain disable and clear, the
// saturating byte-budget window (refill, fractional carry, saturation,
// refusal counters), the additive session send wrapper, and the unchanged
// default path (empty chain and plain session_send).

module xiom.transport.suite_extensions

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.transport.frames;
use xiom.transport.handlers;
use xiom.transport.rate;
use xiom.transport.session;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type PairState = { a: Session; b: Session; }

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

fn pattern_bytes(n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push((i % 251) as UInt8);
    i = i + 1;
  }
  return out;
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

fn feed(s: &mut Session, frame_bytes: &Vec[UInt8], now_ms: Int) -> Vec[Vec[UInt8]] {
  let r = session_on_packet(s, frame_bytes, now_ms);
  if !r.is_ok {
    return Vec[Vec[UInt8]].new();
  }
  let p: SessionPoll = r.value;
  return p.out;
}

fn first_frame(p: &SessionPoll) -> Vec[UInt8] {
  if p.out.len() == 0 {
    return Vec[UInt8].new();
  }
  return p.out[0];
}

fn pair_active(conn: Int, md: Int) -> PairState {
  var a = session_new(conn, md);
  var b = session_new(conn, md);
  let ra = session_start(&mut a, 0);
  let rb = session_start(&mut b, 0);
  var ha: Vec[UInt8] = Vec[UInt8].new();
  var hb: Vec[UInt8] = Vec[UInt8].new();
  if ra.is_ok {
    let pa: SessionPoll = ra.value;
    ha = first_frame(&pa);
  }
  if rb.is_ok {
    let pb: SessionPoll = rb.value;
    hb = first_frame(&pb);
  }
  let ack_b = feed(&mut b, &ha, 0);
  let ack_a = feed(&mut a, &hb, 0);
  var ab: Vec[UInt8] = Vec[UInt8].new();
  var aa: Vec[UInt8] = Vec[UInt8].new();
  if ack_b.len() > 0 { ab = ack_b[0]; }
  if ack_a.len() > 0 { aa = ack_a[0]; }
  let done_a = feed(&mut a, &ab, 0);
  let done_b = feed(&mut b, &aa, 0);
  let _ = done_a;
  let _ = done_b;
  return PairState { a: a; b: b; };
}

// ---------------------------------------------------------------------------
// x1: deterministic outbound order, reverse inbound unwind, explicit insert
// ---------------------------------------------------------------------------

fn x1() -> TestResult {
  var ok = true;
  var c = handlers_new();
  if !handlers_is_enabled(&c) { ok = false; }
  if handlers_outbound_len(&c) != 0 { ok = false; }
  if handlers_inbound_len(&c) != 0 { ok = false; }
  let a1 = handlers_prefix(1, bytes_of("A"));
  let b1 = handlers_prefix(2, bytes_of("B"));
  let ia = handlers_register_outbound(&mut c, a1);
  let ib = handlers_register_outbound(&mut c, b1);
  if ia != 0 { ok = false; }
  if ib != 1 { ok = false; }
  let a2 = handlers_prefix(1, bytes_of("A"));
  let b2 = handlers_prefix(2, bytes_of("B"));
  let ja = handlers_register_inbound(&mut c, a2);
  let jb = handlers_register_inbound(&mut c, b2);
  if ja != 0 { ok = false; }
  if jb != 1 { ok = false; }
  let plain = bytes_of("p");
  let out = handlers_apply_outbound(&c, &plain);
  if !out.ok { ok = false; }
  if out.code != 0 { ok = false; }
  if out.failed_id != -1 { ok = false; }
  // outbound: A then B, each prepending => "BAp"
  if !same_bytes(&out.bytes, &bytes_of("BAp")) { ok = false; }
  // inbound: reverse registration => B strips first, then A => "p"
  let back = handlers_apply_inbound(&c, &out.bytes);
  if !back.ok { ok = false; }
  if !same_bytes(&back.bytes, &plain) { ok = false; }
  // explicit insert at index 0 makes C run first: "BACp"
  let ins = handlers_insert_outbound(&mut c, 0, handlers_prefix(3, bytes_of("C")));
  if !ins { ok = false; }
  let with_c = handlers_apply_outbound(&c, &plain);
  if !same_bytes(&with_c.bytes, &bytes_of("BACp")) { ok = false; }
  return test.assert(ok, "handlers: outbound registration order, reverse inbound unwind, explicit insert");
}

// ---------------------------------------------------------------------------
// x2: outbound/inbound transformations + unknown-kind refusal
// ---------------------------------------------------------------------------

fn x2() -> TestResult {
  var ok = true;
  var c = handlers_new();
  var key_out: Vec[UInt8] = Vec[UInt8].new();
  key_out.push(7);
  key_out.push(11);
  key_out.push(3);
  let hx = handlers_xor(7, key_out);
  let _ = handlers_register_outbound(&mut c, hx);
  var key_in: Vec[UInt8] = Vec[UInt8].new();
  key_in.push(7);
  key_in.push(11);
  key_in.push(3);
  let hxi = handlers_xor(7, key_in);
  let _ = handlers_register_inbound(&mut c, hxi);
  let plain = bytes_of("hello world");
  let enc = handlers_apply_outbound(&c, &plain);
  if !enc.ok { ok = false; }
  if same_bytes(&enc.bytes, &plain) { ok = false; }
  let dec = handlers_apply_inbound(&c, &enc.bytes);
  if !dec.ok { ok = false; }
  if !same_bytes(&dec.bytes, &plain) { ok = false; }
  // prefix transformation both ways
  var pc = handlers_new();
  let p1 = handlers_prefix(4, bytes_of("xy"));
  let p2 = handlers_prefix(4, bytes_of("xy"));
  let _ = handlers_register_outbound(&mut pc, p1);
  let _ = handlers_register_inbound(&mut pc, p2);
  let prefixed = handlers_apply_outbound(&pc, &bytes_of("data"));
  if !prefixed.ok { ok = false; }
  if !same_bytes(&prefixed.bytes, &bytes_of("xydata")) { ok = false; }
  let stripped = handlers_apply_inbound(&pc, &prefixed.bytes);
  if !stripped.ok { ok = false; }
  if !same_bytes(&stripped.bytes, &bytes_of("data")) { ok = false; }
  // an unknown handler kind is a typed refusal, input unchanged
  var bad = PacketHandler { id: 90; kind: 99; enabled: true; tag: Vec[UInt8].new(); key: Vec[UInt8].new(); };
  var bc = handlers_new();
  let _ = handlers_register_outbound(&mut bc, bad);
  let refused = handlers_apply_outbound(&bc, &plain);
  if refused.ok { ok = false; }
  if refused.code != HANDLER_ERR_KIND { ok = false; }
  if refused.failed_id != 90 { ok = false; }
  if !same_bytes(&refused.bytes, &plain) { ok = false; }
  return test.assert(ok, "handlers: outbound/inbound transforms roundtrip; unknown kind is typed refusal");
}

// ---------------------------------------------------------------------------
// x3: whole-chain disable, per-entry disable, clear, no-op default
// ---------------------------------------------------------------------------

fn x3() -> TestResult {
  var ok = true;
  var c = handlers_new();
  let _ = handlers_register_outbound(&mut c, handlers_prefix(1, bytes_of("A")));
  let plain = bytes_of("z");
  let on = handlers_apply_outbound(&c, &plain);
  if !same_bytes(&on.bytes, &bytes_of("Az")) { ok = false; }
  handlers_set_enabled(&mut c, false);
  let off = handlers_apply_outbound(&c, &plain);
  if !off.ok { ok = false; }
  if !same_bytes(&off.bytes, &plain) { ok = false; }
  handlers_set_enabled(&mut c, true);
  if !handlers_set_handler_enabled(&mut c, HANDLER_STAGE_OUTBOUND, 0, false) { ok = false; }
  let entry_off = handlers_apply_outbound(&c, &plain);
  if !same_bytes(&entry_off.bytes, &plain) { ok = false; }
  if !handlers_set_handler_enabled(&mut c, HANDLER_STAGE_OUTBOUND, 0, true) { ok = false; }
  let entry_on = handlers_apply_outbound(&c, &plain);
  if !same_bytes(&entry_on.bytes, &bytes_of("Az")) { ok = false; }
  if handlers_set_handler_enabled(&mut c, 77, 0, false) { ok = false; }
  handlers_clear_outbound(&mut c);
  if handlers_outbound_len(&c) != 0 { ok = false; }
  let cleared = handlers_apply_outbound(&c, &plain);
  if !same_bytes(&cleared.bytes, &plain) { ok = false; }
  let _ = handlers_register_outbound(&mut c, handlers_noop(5));
  let _ = handlers_register_inbound(&mut c, handlers_noop(5));
  handlers_clear(&mut c);
  if handlers_outbound_len(&c) != 0 { ok = false; }
  if handlers_inbound_len(&c) != 0 { ok = false; }
  if !handlers_is_enabled(&c) { ok = false; }
  let defaulted = handlers_apply(&c, HANDLER_STAGE_OUTBOUND, &plain);
  if !defaulted.ok { ok = false; }
  if !same_bytes(&defaulted.bytes, &plain) { ok = false; }
  let bad_stage = handlers_apply(&c, 99, &plain);
  if bad_stage.ok { ok = false; }
  if bad_stage.code != HANDLER_ERR_STAGE { ok = false; }
  return test.assert(ok, "handlers: whole-chain/per-entry disable, clear, and no-op default are byte-exact");
}

// ---------------------------------------------------------------------------
// x4: rate window refill, fractional carry, saturation, refusal counters
// ---------------------------------------------------------------------------

fn x4() -> TestResult {
  var ok = true;
  var w = rate_window_new(100, 10, 0);
  if rate_window_capacity(&w) != 100 { ok = false; }
  if rate_window_bytes(&w) != 100 { ok = false; }
  if !rate_can_send(&w, 100) { ok = false; }
  if rate_can_send(&w, 101) { ok = false; }
  if !rate_consume(&mut w, 60) { ok = false; }
  if rate_window_bytes(&w) != 40 { ok = false; }
  if w.sent_bytes != 60 { ok = false; }
  if w.sent_packets != 1 { ok = false; }
  if rate_can_send(&w, 50) { ok = false; }
  if rate_consume(&mut w, 50) { ok = false; }
  if w.refused != 1 { ok = false; }
  if rate_window_bytes(&w) != 40 { ok = false; }
  // 10 bytes/sec: 2 s adds 20, 1 s adds 10, then saturation at 100
  if rate_refill(&mut w, 2000) != 20 { ok = false; }
  if rate_window_bytes(&w) != 60 { ok = false; }
  if rate_refill(&mut w, 2000) != 0 { ok = false; }
  if rate_refill(&mut w, 3000) != 10 { ok = false; }
  if rate_window_bytes(&w) != 70 { ok = false; }
  if rate_refill(&mut w, 10000) != 30 { ok = false; }
  if rate_window_bytes(&w) != 100 { ok = false; }
  if w.refilled_bytes != 60 { ok = false; }
  if rate_refill(&mut w, 20000) != 0 { ok = false; }
  if !rate_consume(&mut w, 100) { ok = false; }
  if rate_window_bytes(&w) != 0 { ok = false; }
  if rate_consume(&mut w, 1) { ok = false; }
  if w.refused != 2 { ok = false; }
  // fractional refill: 1 byte/sec, 500 ms is carried, the next 500 ms yields 1
  var f = rate_window_new(10, 1, 1000);
  if !rate_consume(&mut f, 1) { ok = false; }
  if rate_refill(&mut f, 1500) != 0 { ok = false; }
  if rate_refill(&mut f, 2000) != 1 { ok = false; }
  if rate_window_bytes(&f) != 10 { ok = false; }
  // a backwards clock never refills or rewinds
  if rate_refill(&mut f, 500) != 0 { ok = false; }
  if f.last_ms != 2000 { ok = false; }
  if rate_window_bytes(&f) != 10 { ok = false; }
  return test.assert(ok, "rate: time refill with fractional carry, saturation, backwards clock, refusal counters");
}

// ---------------------------------------------------------------------------
// x5: additive session send wrapper (consume on success, typed refusal)
// ---------------------------------------------------------------------------

fn x5() -> TestResult {
  var ok = true;
  let pair = pair_active(51, 1200);
  var a: Session = pair.a;
  let oc = session_open_channel(&mut a, 1, true, true, 0, 8);
  if !oc.is_ok { ok = false; }
  let payload = pattern_bytes(10);
  var w = rate_window_new(10, 0, 0);
  let r1 = session_send_rate_limited(&mut a, 1, &payload, 0, &w);
  if !r1.is_ok { ok = false; } else {
    let p1: SessionPoll = r1.value;
    if p1.out.len() != 1 { ok = false; } else {
      let dec = frame_decode(&p1.out[0], 0);
      if !dec.is_ok { ok = false; } else {
        let f: Frame = dec.value;
        if f.kind != FRAME_KIND_DATA { ok = false; }
        if f.seq != 0 { ok = false; }
        if !same_bytes(&f.payload, &payload) { ok = false; }
      }
    }
  }
  if w.sent_bytes != 10 { ok = false; }
  if w.sent_packets != 1 { ok = false; }
  // the budget is now empty: the wrapper refuses before touching the session
  let r2 = session_send_rate_limited(&mut a, 1, &payload, 0, &w);
  if r2.is_ok { ok = false; } else {
    let e2: SessionError = r2.error;
    if e2.kind != TX_ERR_RATE { ok = false; }
  }
  if w.refused != 1 { ok = false; }
  if w.sent_bytes != 10 { ok = false; }
  // the plain path still works and uses the untouched next sequence
  let r3 = session_send(&mut a, 1, &payload, 0);
  if !r3.is_ok { ok = false; } else {
    let p3: SessionPoll = r3.value;
    if p3.out.len() != 1 { ok = false; } else {
      let dec3 = frame_decode(&p3.out[0], 0);
      if !dec3.is_ok { ok = false; } else {
        let f3: Frame = dec3.value;
        if f3.seq != 1 { ok = false; }
      }
    }
  }
  return test.assert(ok, "rate: additive session wrapper consumes on success, refuses typed, leaves plain send intact");
}

// ---------------------------------------------------------------------------
// x6: the default path is unchanged (empty chain, plain session_send parity)
// ---------------------------------------------------------------------------

fn x6() -> TestResult {
  var ok = true;
  let payload = pattern_bytes(32);
  let empty = handlers_new();
  let identity = handlers_apply_outbound(&empty, &payload);
  if !identity.ok { ok = false; }
  if !same_bytes(&identity.bytes, &payload) { ok = false; }
  let identity_in = handlers_apply_inbound(&empty, &payload);
  if !identity_in.ok { ok = false; }
  if !same_bytes(&identity_in.bytes, &payload) { ok = false; }
  // twin sessions: plain send vs rate-limited send with an ample budget
  let p1 = pair_active(61, 1200);
  let p2 = pair_active(61, 1200);
  var a1: Session = p1.a;
  var a2: Session = p2.a;
  let o1 = session_open_channel(&mut a1, 1, true, true, 0, 8);
  let o2 = session_open_channel(&mut a2, 1, true, true, 0, 8);
  if !o1.is_ok { ok = false; }
  if !o2.is_ok { ok = false; }
  let plain = session_send(&mut a1, 1, &payload, 0);
  var w = rate_window_new(1000, 0, 0);
  let limited = session_send_rate_limited(&mut a2, 1, &payload, 0, &w);
  if !plain.is_ok { ok = false; } else {
    if !limited.is_ok { ok = false; } else {
      let pp: SessionPoll = plain.value;
      let lp: SessionPoll = limited.value;
      if pp.out.len() != 1 { ok = false; }
      if lp.out.len() != 1 { ok = false; }
      if pp.out.len() == 1 && lp.out.len() == 1 {
        let b1: Vec[UInt8] = pp.out[0];
        let b2: Vec[UInt8] = lp.out[0];
        if !same_bytes(&b1, &b2) { ok = false; }
      }
    }
  }
  if w.sent_bytes != 32 { ok = false; }
  return test.assert(ok, "default: empty handler chain is identity; rate wrapper wires the same frame as plain send");
}

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = x1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = x2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = x3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = x4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = x5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = x6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  return failed;
}
