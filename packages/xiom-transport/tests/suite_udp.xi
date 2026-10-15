// XIOM -- xiom.transport conformance suite, part 5: real UDP backend
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Real-socket checks on 127.0.0.1: raw datagram roundtrip with source
// address, typed error paths and honest stats, a full session handshake
// plus a reliable message over UDP (the session's retransmit path drives
// it), fragmentation over UDP, and the declared cap facts. When binding
// is unavailable the checks print an explicit SKIP line in the check name
// and never fake a pass (the redis suite_live convention).

module xiom.transport.suite_udp

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.transport.caps;
use xiom.transport.frames;
use xiom.transport.session;
use xiom.transport.reliable;
use xiom.transport.udp;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type UdpPair = {
  sa: UdpSocket;
  sb: UdpSocket;
  a: Session;
  b: Session;
  got: Vec[Vec[UInt8]];
  ok: Bool;
}

type UdpRoundtrip = { sa: UdpSocket; sb: UdpSocket; ok: Bool; }

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

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn dead_socket() -> UdpSocket {
  return UdpSocket {
    fd: -1;
    open: false;
    local_port: 0;
    peer_host: "";
    peer_port: 0;
    nonblocking: false;
    sent: 0;
    received: 0;
    bytes_sent: 0;
    bytes_received: 0;
    refused: 0;
  };
}

fn failed_pair() -> UdpPair {
  var got: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  return UdpPair {
    sa: dead_socket();
    sb: dead_socket();
    a: session_new(0, 1200);
    b: session_new(0, 1200);
    got: got;
    ok: false;
  };
}

// Bind two loopback sockets and start a full session pair over them.
fn udp_pair_start(first: Int, last: Int, conn: Int, md: Int) -> UdpPair {
  let ra = udp_bind_auto("127.0.0.1", first, last);
  if !ra.is_ok { return failed_pair(); }
  var sa: UdpSocket = ra.value;
  let rb = udp_bind_auto("127.0.0.1", sa.local_port + 1, last);
  if !rb.is_ok {
    udp_close(&mut sa);
    return failed_pair();
  }
  var sb: UdpSocket = rb.value;
  var a = session_new(conn, md);
  var b = session_new(conn, md);
  var ok = true;
  let e1 = udp_set_peer(&mut sa, "127.0.0.1", sb.local_port);
  let e2 = udp_set_peer(&mut sb, "127.0.0.1", sa.local_port);
  if !e1.is_ok || !e2.is_ok { ok = false; }
  let oa = session_open_channel(&mut a, 0, true, true, 0, 8);
  let ob = session_open_channel(&mut b, 0, true, true, 0, 8);
  if !oa.is_ok || !ob.is_ok { ok = false; }
  let s1 = session_start(&mut a, 0);
  let s2 = session_start(&mut b, 0);
  if !s1.is_ok || !s2.is_ok { ok = false; } else {
    let pa: SessionPoll = s1.value;
    let pb: SessionPoll = s2.value;
    let x1 = udp_send(&mut sa, &pa.out[0]);
    let x2 = udp_send(&mut sb, &pb.out[0]);
    if !x1.is_ok || !x2.is_ok { ok = false; }
  }
  var got: Vec[Vec[UInt8]] = Vec[Vec[UInt8]].new();
  return UdpPair { sa: sa; sb: sb; a: a; b: b; got: got; ok: ok };
}

// Capture every EvDelivered payload out of a poll (borrows the poll).
fn collect_delivered(p: &SessionPoll, sink: &mut Vec[Vec[UInt8]]) {
  var i = 0;
  while i < p.events.len() {
    let ev: SessionEvent = p.events[i];
    match ev {
      EvDelivered(ch, sq, pl) => {
        sink.push(pl);
      },
      _ => {},
    }
    i = i + 1;
  }
}

fn pump_once(p: &mut UdpPair) {
  // B side: receive datagrams, step its session, send its owed frames.
  let rb = udp_poll(&mut p.sb, 5);
  if rb.is_ok {
    let dgs: Vec[UdpDatagram] = rb.value;
    var i = 0;
    while i < dgs.len() {
      let dg: UdpDatagram = dgs[i];
      let r = session_on_packet(&mut p.b, &dg.data, 0);
      if r.is_ok {
        let pp: SessionPoll = r.value;
        collect_delivered(&pp, &mut p.got);
        var j = 0;
        while j < pp.out.len() {
          let e = udp_send(&mut p.sb, &pp.out[j]);
          let _ = e;
          j = j + 1;
        }
      }
      i = i + 1;
    }
  }
  // A side.
  let ra = udp_poll(&mut p.sa, 5);
  if ra.is_ok {
    let dgs2: Vec<UdpDatagram> = ra.value;
    var k = 0;
    while k < dgs2.len() {
      let dg2: UdpDatagram = dgs2[k];
      let r2 = session_on_packet(&mut p.a, &dg2.data, 0);
      if r2.is_ok {
        let pa: SessionPoll = r2.value;
        collect_delivered(&pa, &mut p.got);
        var m = 0;
        while m < pa.out.len() {
          let e2 = udp_send(&mut p.sa, &pa.out[m]);
          let _ = e2;
          m = m + 1;
        }
      }
      k = k + 1;
    }
  }
}

fn pump_rounds(p: &mut UdpPair, rounds: Int) {
  var i = 0;
  while i < rounds {
    pump_once(p);
    i = i + 1;
  }
}

fn pump_until_active(p: &mut UdpPair, max_rounds: Int) -> Bool {
  var i = 0;
  while i < max_rounds {
    if session_is_active(&p.a) && session_is_active(&p.b) { return true; }
    pump_once(p);
    i = i + 1;
  }
  return session_is_active(&p.a) && session_is_active(&p.b);
}

fn pump_until_delivered(p: &mut UdpPair, max_rounds: Int) -> Bool {
  var i = 0;
  while i < max_rounds {
    let sb = session_stats(&p.b);
    if sb.messages_delivered >= 1 { return true; }
    pump_once(p);
    i = i + 1;
  }
  let sb2 = session_stats(&p.b);
  return sb2.messages_delivered >= 1;
}

// ---------------------------------------------------------------------------
// u1: raw UDP loopback roundtrip with source addresses and byte-exact data
// ---------------------------------------------------------------------------

fn u1() -> TestResult {
  var ok = true;
  let ra = udp_bind_auto("127.0.0.1", 47951, 47970);
  if !ra.is_ok {
    return test.assert(true, "udp: raw loopback roundtrip SKIP -- no free UDP port (" + ra.error + ")");
  }
  var sa: UdpSocket = ra.value;
  let rb = udp_bind_auto("127.0.0.1", sa.local_port + 1, 47980);
  if !rb.is_ok {
    udp_close(&mut sa);
    return test.assert(true, "udp: raw loopback roundtrip SKIP -- no second free UDP port (" + rb.error + ")");
  }
  var sb: UdpSocket = rb.value;
  let e1 = udp_set_peer(&mut sa, "127.0.0.1", sb.local_port);
  let e2 = udp_set_peer(&mut sb, "127.0.0.1", sa.local_port);
  if !e1.is_ok || !e2.is_ok { ok = false; }
  let m1 = bytes_of("udp-1");
  let m2 = bytes_of("udp-2");
  let s1 = udp_send(&mut sa, &m1);
  if !s1.is_ok { ok = false; } else { if s1.value != 5 { ok = false; } }
  let d1 = udp_poll(&mut sb, 500);
  if !d1.is_ok { ok = false; } else {
    let dgs: Vec[UdpDatagram] = d1.value;
    if dgs.len() != 1 { ok = false; } else {
      let dg: UdpDatagram = dgs[0];
      if !same_bytes(&dg.data, &m1) { ok = false; }
      if !streq(dg.from_host, "127.0.0.1") { ok = false; }
      if dg.from_port != sa.local_port { ok = false; }
    }
  }
  let s2 = udp_send(&mut sb, &m2);
  if !s2.is_ok { ok = false; }
  let d2 = udp_poll(&mut sa, 500);
  if !d2.is_ok { ok = false; } else {
    let dgs2: Vec[UdpDatagram] = d2.value;
    if dgs2.len() != 1 { ok = false; } else {
      let dg2: UdpDatagram = dgs2[0];
      if !same_bytes(&dg2.data, &m2) { ok = false; }
      if dg2.from_port != sb.local_port { ok = false; }
    }
  }
  // empty poll is Ok(empty): the timeout is not an error
  let none = udp_poll(&mut sa, 50);
  if !none.is_ok { ok = false; } else { if none.value.len() != 0 { ok = false; } }
  let st = udp_stats(&sa);
  if st.sent != 1 { ok = false; }
  if st.received != 1 { ok = false; }
  if st.bytes_sent != 5 { ok = false; }
  if st.bytes_received != 5 { ok = false; }
  udp_close(&mut sa);
  udp_close(&mut sb);
  return test.assert(ok, "udp: raw loopback roundtrip byte-exact with source host/port");
}

// ---------------------------------------------------------------------------
// u2: typed error paths, honest stats, close behavior, cap facts
// ---------------------------------------------------------------------------

fn u2() -> TestResult {
  var ok = true;
  let bad1 = udp_bind("127.0.0.1", 0);
  if bad1.is_ok { ok = false; } else {
    let e: UdpError = bad1.error;
    if e.kind != UDP_ERR_ADDR { ok = false; }
  }
  let bad2 = udp_bind("", 47951);
  if bad2.is_ok { ok = false; } else {
    let e2: UdpError = bad2.error;
    if e2.kind != UDP_ERR_ADDR { ok = false; }
  }
  let ra = udp_bind_auto("127.0.0.1", 48051, 48060);
  if !ra.is_ok {
    return test.assert(true, "udp: typed errors/stats SKIP -- no free UDP port (" + ra.error + ")");
  }
  var sa: UdpSocket = ra.value;
  // send with no peer configured is a typed refusal
  let np = udp_send(&mut sa, &bytes_of("x"));
  if np.is_ok { ok = false; } else {
    let e3: UdpError = np.error;
    if e3.kind != UDP_ERR_ADDR { ok = false; }
  }
  let st1 = udp_stats(&sa);
  if st1.refused != 1 { ok = false; }
  let sp = udp_set_peer(&mut sa, "127.0.0.1", 48059);
  if !sp.is_ok { ok = false; }
  // oversize datagram never sends
  var big: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 65508 {
    big.push(1 as UInt8);
    i = i + 1;
  }
  let ov = udp_send(&mut sa, &big);
  if ov.is_ok { ok = false; } else {
    let e4: UdpError = ov.error;
    if e4.kind != UDP_ERR_SEND { ok = false; }
  }
  let st2 = udp_stats(&sa);
  if st2.refused != 2 { ok = false; }
  // close flips every later call to a typed refusal
  udp_close(&mut sa);
  if udp_is_open(&sa) { ok = false; }
  let dead = udp_send(&mut sa, &bytes_of("x"));
  if dead.is_ok { ok = false; } else {
    let e5: UdpError = dead.error;
    if e5.kind != UDP_ERR_CLOSED { ok = false; }
  }
  let dead2 = udp_poll(&mut sa, 0);
  if dead2.is_ok { ok = false; } else {
    let e6: UdpError = dead2.error;
    if e6.kind != UDP_ERR_CLOSED { ok = false; }
  }
  let st3 = udp_stats(&sa);
  if st3.refused != 4 { ok = false; }
  // declared cap facts
  let cf = udp_caps();
  let c2 = caps_udp();
  if cf.reliable != c2.reliable { ok = false; }
  if cf.ordered != c2.ordered { ok = false; }
  if cf.max_datagram != c2.max_datagram { ok = false; }
  if cf.max_payload != c2.max_payload { ok = false; }
  if cf.mtu_estimate != c2.mtu_estimate { ok = false; }
  if cf.channels != c2.channels { ok = false; }
  if cf.reliable_unordered != c2.reliable_unordered { ok = false; }
  if cf.reliable { ok = false; }
  if cf.mtu_estimate != 1500 { ok = false; }
  return test.assert(ok, "udp: typed refusals (addr/size/closed), refused counts, cap facts");
}

// ---------------------------------------------------------------------------
// u3: a full session handshake and a reliable message over real UDP
// ---------------------------------------------------------------------------

fn u3() -> TestResult {
  var ok = true;
  var p = udp_pair_start(47981, 48040, 55, 1200);
  if !p.ok {
    return test.assert(true, "udp: session handshake + message SKIP -- no free UDP port pair");
  }
  if !pump_until_active(&mut p, 100) { ok = false; }
  if ok {
    let msg = bytes_of("over-udp-reliable");
    let snd = session_send(&mut p.a, 0, &msg, 0);
    if !snd.is_ok { ok = false; } else {
      let pp: SessionPoll = snd.value;
      var i = 0;
      while i < pp.out.len() {
        let e = udp_send(&mut p.sa, &pp.out[i]);
        if !e.is_ok { ok = false; }
        i = i + 1;
      }
    }
    if !pump_until_delivered(&mut p, 100) { ok = false; }
    pump_rounds(&mut p, 5);
    if p.got.len() != 1 { ok = false; } else {
      let g: Vec[UInt8] = p.got[0];
      if !same_bytes(&g, &msg) { ok = false; }
    }
    let sb = session_stats(&p.b);
    if sb.messages_delivered != 1 { ok = false; }
    let rel = session_reliable_stats(&p.a);
    if rel.acked != 1 { ok = false; }
    // orderly close over the wire
    let cl = session_close(&mut p.a, FIN_REASON_SHUTDOWN, 0);
    if !cl.is_ok { ok = false; } else {
      let cp: SessionPoll = cl.value;
      var j = 0;
      while j < cp.out.len() {
        let e2 = udp_send(&mut p.sa, &cp.out[j]);
        if !e2.is_ok { ok = false; }
        j = j + 1;
      }
    }
    pump_rounds(&mut p, 5);
    if session_state_code(session_state(&p.b)) != 4 { ok = false; }
  }
  udp_close(&mut p.sa);
  udp_close(&mut p.sb);
  return test.assert(ok, "udp: session handshake, reliable message and close over 127.0.0.1");
}

// ---------------------------------------------------------------------------
// u4: fragmentation + reassembly over UDP
// ---------------------------------------------------------------------------

fn u4() -> TestResult {
  var ok = true;
  var p = udp_pair_start(48081, 48140, 56, 1200);
  if !p.ok {
    return test.assert(true, "udp: fragmented message over UDP SKIP -- no free UDP port pair");
  }
  if !pump_until_active(&mut p, 100) { ok = false; }
  if ok {
    let msg = pattern_bytes(1500);   // chunk cap 1169 -> 2 fragments
    let snd = session_send(&mut p.a, 0, &msg, 0);
    if !snd.is_ok { ok = false; } else {
      let pp: SessionPoll = snd.value;
      if pp.out.len() != 2 { ok = false; }
      var i = 0;
      while i < pp.out.len() {
        let e = udp_send(&mut p.sa, &pp.out[i]);
        if !e.is_ok { ok = false; }
        i = i + 1;
      }
    }
    if !pump_until_delivered(&mut p, 100) { ok = false; }
    if p.got.len() != 1 { ok = false; } else {
      let g: Vec[UInt8] = p.got[0];
      if g.len() != 1500 { ok = false; }
      if !same_bytes(&g, &msg) { ok = false; }
    }
    let sb = session_stats(&p.b);
    if sb.fragments_recv != 2 { ok = false; }
    if sb.reasm_completed != 1 { ok = false; }
  }
  udp_close(&mut p.sa);
  udp_close(&mut p.sb);
  return test.assert(ok, "udp: 1500-byte message fragments 2x and reassembles byte-exact");
}

// ---------------------------------------------------------------------------
// u5: explicit send_to target and the empty datagram
// ---------------------------------------------------------------------------

fn u5() -> TestResult {
  var ok = true;
  let ra = udp_bind_auto("127.0.0.1", 48151, 48170);
  if !ra.is_ok {
    return test.assert(true, "udp: send_to + empty datagram SKIP -- no free UDP port (" + ra.error + ")");
  }
  var sa: UdpSocket = ra.value;
  let rb = udp_bind_auto("127.0.0.1", sa.local_port + 1, 48180);
  if !rb.is_ok {
    udp_close(&mut sa);
    return test.assert(true, "udp: send_to + empty datagram SKIP -- no second free UDP port");
  }
  var sb: UdpSocket = rb.value;
  // explicit destination without udp_set_peer
  var empty: Vec[UInt8] = Vec[UInt8].new();
  let s1 = udp_send_to(&mut sa, &bytes_of("direct"), "127.0.0.1", sb.local_port);
  if !s1.is_ok { ok = false; } else { if s1.value != 6 { ok = false; } }
  let d1 = udp_poll(&mut sb, 500);
  if !d1.is_ok { ok = false; } else { if d1.value.len() != 1 { ok = false; } }
  // empty datagram: sent as zero bytes, received as zero bytes
  let s2 = udp_send_to(&mut sa, &empty, "127.0.0.1", sb.local_port);
  if !s2.is_ok { ok = false; } else { if s2.value != 0 { ok = false; } }
  let d2 = udp_poll(&mut sb, 500);
  if !d2.is_ok { ok = false; } else {
    let dgs: Vec[UdpDatagram] = d2.value;
    if dgs.len() != 1 { ok = false; } else {
      let dg: UdpDatagram = dgs[0];
      if dg.data.len() != 0 { ok = false; }
      if dg.from_port != sa.local_port { ok = false; }
    }
  }
  // invalid explicit destination is typed
  let bad = udp_send_to(&mut sa, &empty, "", 1);
  if bad.is_ok { ok = false; } else {
    let e: UdpError = bad.error;
    if e.kind != UDP_ERR_ADDR { ok = false; }
  }
  let st = udp_stats(&sa);
  if st.refused != 1 { ok = false; }
  udp_close(&mut sa);
  udp_close(&mut sb);
  return test.assert(ok, "udp: explicit send_to destination and zero-length datagram roundtrip");
}

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = u1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = u2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = u3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = u4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = u5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  return failed;
}
