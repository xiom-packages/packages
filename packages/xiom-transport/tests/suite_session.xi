// XIOM -- xiom.transport conformance suite, part 3: session lifecycle
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic two-endpoint session checks (the wire is played by the
// suite itself): handshake and version refusal, channel open/close and
// unknown-channel verdicts, send/deliver/ack over the frames codec,
// fragmentation + reassembly byte-exactness (including out-of-order
// fragments and the no-ack-before-complete rule), retransmit under a drop,
// missing-fragment retransmission, draining/timeout verdicts, the
// handshake deadline predicate and ping/pong.

module xiom.transport.suite_session

use xiom.io;
use xiom.test;
use xiom.transport.caps;
use xiom.transport.frames;
use xiom.transport.reliable;
use xiom.transport.session;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type PairState = { a: Session; b: Session; }

type DeliveredInfo = { count: Int; channel: Int; seq: Int; payload: Vec[UInt8]; }

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

// Feed one frame through a session; returns the resulting frames.
fn feed(s: &mut Session, frame_bytes: &Vec[UInt8], now_ms: Int) -> Vec[Vec[UInt8]] {
  let r = session_on_packet(s, frame_bytes, now_ms);
  if !r.is_ok {
    return Vec[Vec[UInt8]].new();
  }
  let p: SessionPoll = r.value;
  return p.out;
}

// Count and capture EvDelivered events (borrows the poll).
fn delivered_info(p: &SessionPoll) -> DeliveredInfo {
  var count = 0;
  var channel = -1;
  var seq = -1;
  var payload: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < p.events.len() {
    let ev: SessionEvent = p.events[i];
    match ev {
      EvDelivered(ch, sq, pl) => {
        count = count + 1;
        channel = ch;
        seq = sq;
        payload = pl;
      },
      _ => {},
    }
    i = i + 1;
  }
  return DeliveredInfo { count: count; channel: channel; seq: seq; payload: payload; };
}

fn count_state_events(p: &SessionPoll, from: Int, to: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < p.events.len() {
    let ev: SessionEvent = p.events[i];
    match ev {
      EvStateChanged(f, t) => {
        if f == from && t == to { n = n + 1; }
      },
      _ => {},
    }
    i = i + 1;
  }
  return n;
}

fn count_events_kind(p: &SessionPoll, kind: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < p.events.len() {
    let ev: SessionEvent = p.events[i];
    match ev {
      EvFailure(k, c, s) => {
        if k == kind { n = n + 1; }
      },
      _ => {},
    }
    i = i + 1;
  }
  return n;
}

fn count_finish(p: &SessionPoll, reason: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < p.events.len() {
    let ev: SessionEvent = p.events[i];
    match ev {
      EvFinish(r) => {
        if r == reason { n = n + 1; }
      },
      _ => {},
    }
    i = i + 1;
  }
  return n;
}

fn first_frame(p: &SessionPoll) -> Vec[UInt8] {
  if p.out.len() == 0 {
    return Vec[UInt8].new();
  }
  return p.out[0];
}

// Run the full symmetric handshake for two sessions in one process.
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
  let ack_b = feed(&mut b, &ha, 0);   // b answers a's hello
  let ack_a = feed(&mut a, &hb, 0);   // a answers b's hello
  var ab: Vec[UInt8] = Vec[UInt8].new();
  var aa: Vec[UInt8] = Vec[UInt8].new();
  if ack_b.len() > 0 { ab = ack_b[0]; }
  if ack_a.len() > 0 { aa = ack_a[0]; }
  let done_a = feed(&mut a, &ab, 0);
  let done_b = feed(&mut b, &aa, 0);
  let _ = done_a;
  let _ = done_b;
  return PairState { a: a; b: b };
}

// ---------------------------------------------------------------------------
// s1: lifecycle start: Connecting -> Handshaking with a hello frame
// ---------------------------------------------------------------------------

fn s1() -> TestResult {
  var ok = true;
  var s = session_new(7, 1200);
  if session_state_code(session_state(&s)) != 0 { ok = false; }
  if session_state_name(session_state(&s)) != "connecting" { ok = false; }
  let r = session_start(&mut s, 0);
  if !r.is_ok { ok = false; } else {
    let p: SessionPoll = r.value;
    if p.out.len() != 1 { ok = false; } else {
      let dec = frame_decode(&p.out[0], 0);
      if !dec.is_ok { ok = false; } else {
        let f: Frame = dec.value;
        if f.kind != FRAME_KIND_HELLO { ok = false; }
        if f.protocol_version != TX_PROTOCOL_VERSION { ok = false; }
        if f.conn_id != 7 { ok = false; }
      }
    }
    if count_state_events(&p, 0, 1) != 1 { ok = false; }
  }
  if session_state_code(session_state(&s)) != 1 { ok = false; }
  if session_state_name(session_state(&s)) != "handshaking" { ok = false; }
  // starting twice is a typed state verdict
  let r2 = session_start(&mut s, 0);
  if r2.is_ok { ok = false; } else {
    let e2: SessionError = r2.error;
    if e2.kind != TX_ERR_STATE { ok = false; }
  }
  return test.assert(ok, "session: start emits hello, Connecting -> Handshaking, double start refused");
}

// ---------------------------------------------------------------------------
// s2: symmetric handshake -> Active on both ends
// ---------------------------------------------------------------------------

fn s2() -> TestResult {
  var ok = true;
  let pair = pair_active(11, 1200);
  if session_state_code(session_state(&pair.a)) != 2 { ok = false; }
  if session_state_code(session_state(&pair.b)) != 2 { ok = false; }
  if !session_is_active(&pair.a) { ok = false; }
  if !session_is_active(&pair.b) { ok = false; }
  let ra = session_reliable_stats(&pair.a);
  let rb = session_reliable_stats(&pair.b);
  if ra.sent != 0 { ok = false; }
  if rb.sent != 0 { ok = false; }
  return test.assert(ok, "session: symmetric hello/hello_ack handshake reaches Active twice");
}

// ---------------------------------------------------------------------------
// s3: version mismatch refuses with a report and a FIN
// ---------------------------------------------------------------------------

fn s3() -> TestResult {
  var ok = true;
  var a = session_new(21, 1200);
  let rs = session_start(&mut a, 0);
  if !rs.is_ok { ok = false; }
  // a peer (conn 21) claiming protocol version 2
  var hello2 = frame_hello(21, 2);
  let enc = frame_encode(&hello2);
  if !enc.is_ok { ok = false; } else {
    let r = session_on_packet(&mut a, &enc.value, 0);
    if !r.is_ok { ok = false; } else {
      let p: SessionPoll = r.value;
      if count_events_kind(&p, TX_ERR_VERSION) != 1 { ok = false; }
      if p.out.len() != 1 { ok = false; } else {
        let dec = frame_decode(&p.out[0], 0);
        if !dec.is_ok { ok = false; } else {
          let f: Frame = dec.value;
          if f.kind != FRAME_KIND_FIN { ok = false; }
          if f.fin_reason != FIN_REASON_VERSION_MISMATCH { ok = false; }
        }
      }
    }
  }
  if session_state_code(session_state(&a)) != 4 { ok = false; }
  let st = session_stats(&a);
  if st.refusals != 1 { ok = false; }
  // late packets after the refusal are refused too
  let ping = frame_encode(&frame_ping(21));
  if !ping.is_ok { ok = false; } else {
    let r2 = session_on_packet(&mut a, &ping.value, 0);
    if r2.is_ok { ok = false; }
  }
  return test.assert(ok, "session: protocol version mismatch refuses (event + FIN + Closed; late packets refused)");
}

// ---------------------------------------------------------------------------
// s4: channels: open/close semantics and unknown-channel verdicts
// ---------------------------------------------------------------------------

fn s4() -> TestResult {
  var ok = true;
  let pair = pair_active(31, 1200);
  var a: Session = pair.a;
  if session_state_code(session_state(&a)) != 2 { ok = false; }
  // open on both ends (symmetric configuration data)
  let o1 = session_open_channel(&mut a, 2, true, true, 1, 8);
  if !o1.is_ok { ok = false; } else {
    let p: SessionPoll = o1.value;
    var n = 0;
    var i = 0;
    while i < p.events.len() {
      let ev: SessionEvent = p.events[i];
      match ev {
        EvChannelOpened(ch, rel, ord, pr) => {
          n = n + 1;
          if ch != 2 { ok = false; }
          if !rel { ok = false; }
          if !ord { ok = false; }
          if pr != 1 { ok = false; }
        },
        _ => {},
      }
      i = i + 1;
    }
    if n != 1 { ok = false; }
  }
  // re-open: no event (already open)
  let o2 = session_open_channel(&mut a, 2, true, true, 1, 8);
  if !o2.is_ok { ok = false; } else {
    let p2: SessionPoll = o2.value;
    if p2.events.len() != 0 { ok = false; }
  }
  // close: event once; second close: no event
  let c1 = session_close_channel(&mut a, 2);
  if !c1.is_ok { ok = false; } else {
    let p3: SessionPoll = c1.value;
    if p3.events.len() != 1 { ok = false; }
  }
  let c2 = session_close_channel(&mut a, 2);
  if !c2.is_ok { ok = false; } else {
    let p4: SessionPoll = c2.value;
    if p4.events.len() != 0 { ok = false; }
  }
  // a data frame on an unknown channel is a typed verdict
  var okb = true;
  let pair2 = pair_active(32, 1200);
  var b: Session = pair2.b;
  var pld: Vec[UInt8] = Vec[UInt8].new();
  pld.push(1 as UInt8);
  var df = frame_data(32, 9, 0, -1, 0, pld);
  let enc = frame_encode(&df);
  if !enc.is_ok { fail_flag(&mut okb); } else {
    let r = session_on_packet(&mut b, &enc.value, 0);
    if r.is_ok { fail_flag(&mut okb); } else {
      let se: SessionError = r.error;
      if se.kind != TX_ERR_CHANNEL { fail_flag(&mut okb); }
    }
  }
  if !okb { ok = false; }
  return test.assert(ok, "session: channel open/close semantics and unknown-channel refusal");
}

fn fail_flag(flag: &mut Bool) {
  *flag = false;
}

// ---------------------------------------------------------------------------
// s5: send -> data frame -> deliver -> ack (byte-exact)
// ---------------------------------------------------------------------------

fn s5() -> TestResult {
  var ok = true;
  let pair = pair_active(41, 1200);
  var a: Session = pair.a;
  var b: Session = pair.b;
  let oa = session_open_channel(&mut a, 0, true, true, 0, 8);
  let ob = session_open_channel(&mut b, 0, true, true, 0, 8);
  if !oa.is_ok || !ob.is_ok { ok = false; }
  let hello = bytes_of("hello-transport");
  let snd = session_send(&mut a, 0, &hello, 0);
  if !snd.is_ok { ok = false; } else {
    let p: SessionPoll = snd.value;
    if p.out.len() != 1 { ok = false; } else {
      let dec = frame_decode(&p.out[0], 0);
      if !dec.is_ok { ok = false; } else {
        let f: Frame = dec.value;
        if f.kind != FRAME_KIND_DATA { ok = false; }
        if f.channel != 0 { ok = false; }
        if f.seq != 0 { ok = false; }
        if f.ack != -1 { ok = false; }
        if !same_bytes(&f.payload, &hello) { ok = false; }
      }
    }
    let rb = session_on_packet(&mut b, &p.out[0], 0);
    if !rb.is_ok { ok = false; } else {
      let pb: SessionPoll = rb.value;
      let di = delivered_info(&pb);
      if di.count != 1 { ok = false; }
      if di.channel != 0 { ok = false; }
      if di.seq != 0 { ok = false; }
      if !same_bytes(&di.payload, &hello) { ok = false; }
      if pb.out.len() != 1 { ok = false; } else {
        let adec = frame_decode(&pb.out[0], 0);
        if !adec.is_ok { ok = false; } else {
          let af: Frame = adec.value;
          if af.kind != FRAME_KIND_ACK { ok = false; }
          if af.ack != 0 { ok = false; }
        }
        let ra = session_on_packet(&mut a, &pb.out[0], 0);
        if !ra.is_ok { ok = false; }
      }
    }
  }
  let sa = session_stats(&a);
  let sb = session_stats(&b);
  if sa.messages_sent != 1 { ok = false; }
  if sb.messages_delivered != 1 { ok = false; }
  if sb.acks_sent != 1 { ok = false; }
  let rel = session_reliable_stats(&a);
  if rel.acked != 1 { ok = false; }
  if rel.sent != 1 { ok = false; }
  return test.assert(ok, "session: send/deliver/ack roundtrip with exact frame fields");
}

// ---------------------------------------------------------------------------
// s6: fragmentation and reassembly (out of order, no ack before complete)
// ---------------------------------------------------------------------------

fn s6() -> TestResult {
  var ok = true;
  let pair = pair_active(51, 80);   // chunk cap = 80 - 19 - 12 = 49
  var a: Session = pair.a;
  var b: Session = pair.b;
  let oa = session_open_channel(&mut a, 1, true, true, 0, 8);
  let ob = session_open_channel(&mut b, 1, true, true, 0, 8);
  if !oa.is_ok || !ob.is_ok { ok = false; }
  let msg = pattern_bytes(120);
  let snd = session_send(&mut a, 1, &msg, 0);
  if !snd.is_ok { ok = false; } else {
    let p: SessionPoll = snd.value;
    if p.out.len() != 3 { ok = false; }
    // fragment metadata: 3 pieces with offsets 0/49/98 and the same seq
    var i = 0;
    while i < p.out.len() {
      let dec = frame_decode(&p.out[i], 0);
      if !dec.is_ok { ok = false; } else {
        let f: Frame = dec.value;
        if !f.fragment { ok = false; }
        if f.frag_count != 3 { ok = false; }
        if f.frag_index != i { ok = false; }
        if f.frag_offset != i * 49 { ok = false; }
        if f.frag_total != 120 { ok = false; }
        if f.seq != 0 { ok = false; }
      }
      i = i + 1;
    }
    // feed fragment 2 and 0 first: no delivery, and no ack before complete
    let f2 = feed(&mut b, &p.out[2], 0);
    if f2.len() != 0 { ok = false; }
    let f0 = feed(&mut b, &p.out[0], 0);
    if f0.len() != 0 { ok = false; }
    if session_reasm_len(&b) != 1 { ok = false; }
    // fragment 1 completes the message: deliver byte-exact + ack
    let rb = session_on_packet(&mut b, &p.out[1], 0);
    if !rb.is_ok { ok = false; } else {
      let pb: SessionPoll = rb.value;
      let di = delivered_info(&pb);
      if di.count != 1 { ok = false; }
      if di.seq != 0 { ok = false; }
      if !same_bytes(&di.payload, &msg) { ok = false; }
      if pb.out.len() != 1 { ok = false; } else {
        let ra = session_on_packet(&mut a, &pb.out[0], 0);
        if !ra.is_ok { ok = false; }
      }
    }
    if session_reasm_len(&b) != 0 { ok = false; }
    let sb = session_stats(&b);
    if sb.reasm_completed != 1 { ok = false; }
    if sb.fragments_recv != 3 { ok = false; }
    let rel = session_reliable_stats(&a);
    if rel.acked != 1 { ok = false; }
  }
  return test.assert(ok, "session: 120-byte message fragments 3x and reassembles byte-exact out of order");
}

// ---------------------------------------------------------------------------
// s7: dropped data frame -> poll retransmits the identical bytes
// ---------------------------------------------------------------------------

fn s7() -> TestResult {
  var ok = true;
  let pair = pair_active(61, 1200);
  var a: Session = pair.a;
  var b: Session = pair.b;
  let oa = session_open_channel(&mut a, 0, true, true, 0, 8);
  let ob = session_open_channel(&mut b, 0, true, true, 0, 8);
  if !oa.is_ok || !ob.is_ok { ok = false; }
  let msg = bytes_of("reliable");
  let snd = session_send(&mut a, 0, &msg, 0);
  if !snd.is_ok { ok = false; } else {
    let p: SessionPoll = snd.value;
    // the frame is "dropped": b never sees it
    let early = session_poll(&mut a, 0);
    if !early.is_ok { ok = false; } else { if early.value.out.len() != 0 { ok = false; } }
    let due = session_poll(&mut a, 100);
    if !due.is_ok { ok = false; } else {
      let pd: SessionPoll = due.value;
      if pd.out.len() != 1 { ok = false; }
      if !same_bytes(&pd.out[0], &p.out[0]) { ok = false; }
      let rb = session_on_packet(&mut b, &pd.out[0], 100);
      if !rb.is_ok { ok = false; } else {
        let pb: SessionPoll = rb.value;
        let di = delivered_info(&pb);
        if di.count != 1 { ok = false; }
        if !same_bytes(&di.payload, &msg) { ok = false; }
        if pb.out.len() != 1 { ok = false; } else {
          let ra = session_on_packet(&mut a, &pb.out[0], 100);
          if !ra.is_ok { ok = false; }
        }
      }
    }
  }
  let rel = session_reliable_stats(&a);
  if rel.retransmits != 1 { ok = false; }
  if rel.acked != 1 { ok = false; }
  return test.assert(ok, "session: dropped frame retransmits identically at RTO and then delivers");
}

// ---------------------------------------------------------------------------
// s8: a missing fragment retransmits every fragment; duplicate pieces are
// suppressed; the message is delivered exactly once
// ---------------------------------------------------------------------------

fn s8() -> TestResult {
  var ok = true;
  let pair = pair_active(71, 80);
  var a: Session = pair.a;
  var b: Session = pair.b;
  let oa = session_open_channel(&mut a, 0, true, true, 0, 8);
  let ob = session_open_channel(&mut b, 0, true, true, 0, 8);
  if !oa.is_ok || !ob.is_ok { ok = false; }
  let msg = pattern_bytes(120);
  let snd = session_send(&mut a, 0, &msg, 0);
  if !snd.is_ok { ok = false; } else {
    let p: SessionPoll = snd.value;
    if p.out.len() != 3 { ok = false; }
    // fragment 0 arrives twice (the second copy is a fragment duplicate)
    let d1 = feed(&mut b, &p.out[0], 0);
    let d2 = feed(&mut b, &p.out[0], 0);
    if d2.len() != 0 { ok = false; }
    let d3 = feed(&mut b, &p.out[1], 0);
    if d3.len() != 0 { ok = false; }
    let sb1 = session_stats(&b);
    if sb1.reasm_duplicates != 1 { ok = false; }
    // the missing fragment triggers a full retransmission of the message
    let due = session_poll(&mut a, 100);
    if !due.is_ok { ok = false; } else {
      let pd: SessionPoll = due.value;
      if pd.out.len() != 3 { ok = false; }
    }
    // the original fragment 2 completes it: exactly one delivery
    let rb = session_on_packet(&mut b, &p.out[2], 100);
    if !rb.is_ok { ok = false; } else {
      let pb: SessionPoll = rb.value;
      let di = delivered_info(&pb);
      if di.count != 1 { ok = false; }
      if !same_bytes(&di.payload, &msg) { ok = false; }
      if pb.out.len() != 1 { ok = false; } else {
        let ra = session_on_packet(&mut a, &pb.out[0], 100);
        if !ra.is_ok { ok = false; }
      }
    }
  }
  let rel = session_reliable_stats(&a);
  if rel.retransmits != 1 { ok = false; }
  if rel.acked != 1 { ok = false; }
  let sast = session_stats(&a);
  if sast.fragments_sent != 6 { ok = false; }
  let sb = session_stats(&b);
  if sb.messages_delivered != 1 { ok = false; }
  if session_reasm_len(&b) != 0 { ok = false; }
  return test.assert(ok, "session: missing fragment retransmits all pieces; duplicates suppressed; one delivery");
}

// ---------------------------------------------------------------------------
// s9: draining/close handshake, reliability timeout verdict, deadline
// ---------------------------------------------------------------------------

fn s9() -> TestResult {
  var ok = true;
  // part 1: orderly close
  let pair = pair_active(81, 1200);
  var a: Session = pair.a;
  var b: Session = pair.b;
  let cl = session_close(&mut a, FIN_REASON_SHUTDOWN, 0);
  if !cl.is_ok { ok = false; } else {
    let p: SessionPoll = cl.value;
    if p.out.len() != 1 { ok = false; } else {
      let dec = frame_decode(&p.out[0], 0);
      if !dec.is_ok { ok = false; } else {
        let f: Frame = dec.value;
        if f.kind != FRAME_KIND_FIN { ok = false; }
        if f.fin_reason != FIN_REASON_SHUTDOWN { ok = false; }
      }
    }
    if count_state_events(&p, 2, 3) != 1 { ok = false; }
    // b receives FIN: Closed + EvFinish + echo FIN
    let rb = session_on_packet(&mut b, &p.out[0], 0);
    if !rb.is_ok { ok = false; } else {
      let pb: SessionPoll = rb.value;
      if count_finish(&pb, FIN_REASON_SHUTDOWN) != 1 { ok = false; }
      if pb.out.len() != 1 { ok = false; } else {
        let ra = session_on_packet(&mut a, &pb.out[0], 0);
        if !ra.is_ok { ok = false; }
      }
    }
    if session_state_code(session_state(&a)) != 4 { ok = false; }
    if session_state_code(session_state(&b)) != 4 { ok = false; }
    // sends after close are typed refusals
    let late = session_send(&mut a, 0, &bytes_of("x"), 0);
    if late.is_ok { ok = false; }
  }
  // part 2: no ack -> bounded retransmits -> failure verdict + drain
  let pair2 = pair_active(82, 1200);
  var a2: Session = pair2.a;
  let oa = session_open_channel(&mut a2, 0, true, true, 0, 8);
  if !oa.is_ok { ok = false; }
  let snd = session_send(&mut a2, 0, &bytes_of("void"), 0);
  if !snd.is_ok { ok = false; }
  var failures = 0;
  var fin_timeout = false;
  var ticks: Vec[Int] = Vec[Int].new();
  ticks.push(100); ticks.push(300); ticks.push(700); ticks.push(1500); ticks.push(3100);
  var ti = 0;
  while ti < ticks.len() {
    let t: Int = ticks[ti];
    let pr = session_poll(&mut a2, t);
    if !pr.is_ok { ok = false; } else {
      let pp: SessionPoll = pr.value;
      failures = failures + count_events_kind(&pp, RL_ERR_RETRIES);
      var fi = 0;
      while fi < pp.out.len() {
        let dec = frame_decode(&pp.out[fi], 0);
        if dec.is_ok {
          let f: Frame = dec.value;
          if f.kind == FRAME_KIND_FIN && f.fin_reason == FIN_REASON_TIMEOUT { fin_timeout = true; }
        }
        fi = fi + 1;
      }
    }
    ti = ti + 1;
  }
  if failures != 1 { ok = false; }
  if !fin_timeout { ok = false; }
  if session_state_code(session_state(&a2)) != 3 { ok = false; }
  let st2 = session_stats(&a2);
  if st2.failures != 1 { ok = false; }
  // part 3: the handshake deadline predicate (caller-owned verdict)
  var fresh = session_new(91, 1200);
  let rs = session_start(&mut fresh, 0);
  if !rs.is_ok { ok = false; }
  let d1 = session_handshake_deadline(&fresh, 0, 5000, 3000);
  if !d1.is_ok { ok = false; } else { if !d1.value { ok = false; } }
  let d2 = session_handshake_deadline(&fresh, 0, 1000, 3000);
  if !d2.is_ok { ok = false; } else { if d2.value { ok = false; } }
  let d3 = session_handshake_deadline(&b, 0, 9000, 3000);
  if !d3.is_ok { ok = false; } else { if d3.value { ok = false; } }
  return test.assert(ok, "session: orderly drain; exhausted retries drain with FIN(TIMEOUT); deadline predicate");
}

// ---------------------------------------------------------------------------
// s10: ping/pong
// ---------------------------------------------------------------------------

fn s10() -> TestResult {
  var ok = true;
  let pair = pair_active(101, 1200);
  var a: Session = pair.a;
  var b: Session = pair.b;
  let ping = frame_encode(&frame_ping(101));
  if !ping.is_ok { ok = false; } else {
    let rb = session_on_packet(&mut b, &ping.value, 0);
    if !rb.is_ok { ok = false; } else {
      let pb: SessionPoll = rb.value;
      var ping_seen = 0;
      var i = 0;
      while i < pb.events.len() {
        let ev: SessionEvent = pb.events[i];
        match ev {
          EvPing => { ping_seen = ping_seen + 1; },
          _ => {},
        }
        i = i + 1;
      }
      if ping_seen != 1 { ok = false; }
      if pb.out.len() != 1 { ok = false; } else {
        let dec = frame_decode(&pb.out[0], 0);
        if !dec.is_ok { ok = false; } else {
          let f: Frame = dec.value;
          if f.kind != FRAME_KIND_PONG { ok = false; }
        }
        let ra = session_on_packet(&mut a, &pb.out[0], 0);
        if !ra.is_ok { ok = false; } else {
          let pa: SessionPoll = ra.value;
          var pong_seen = 0;
          var j = 0;
          while j < pa.events.len() {
            let ev2: SessionEvent = pa.events[j];
            match ev2 {
              EvPong => { pong_seen = pong_seen + 1; },
              _ => {},
            }
            j = j + 1;
          }
          if pong_seen != 1 { ok = false; }
        }
      }
    }
  }
  let sb = session_stats(&b);
  if sb.pings != 1 { ok = false; }
  let sa = session_stats(&a);
  if sa.pongs != 1 { ok = false; }
  return test.assert(ok, "session: ping answers with pong and both sides count");
}

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = s1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = s2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = s3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = s4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = s5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = s6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = s7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = s8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = s9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = s10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  return failed;
}
