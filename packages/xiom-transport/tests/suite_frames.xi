// XIOM -- xiom.transport conformance suite, part 1: wire codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Frame goldens (exact wire bytes), little-endian primitives, fragment
// metadata, truncation/garbage errors with exact byte offsets, and the
// hard size caps. Every fixture is hand-composed from the declared layout
// in SPEC.md section 4; no upstream bytes are read.

module xiom.transport.suite_frames

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.transport.caps;
use xiom.transport.frames;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn mk(vals: Vec[Int]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    let v: Int = vals[i];
    out.push((v & 255) as UInt8);
    i = i + 1;
  }
  return out;
}

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

fn zeros(n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

fn truncate(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    let b: UInt8 = v[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn concat2(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    out.push(x);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    let x: UInt8 = b[j];
    out.push(x);
    j = j + 1;
  }
  return out;
}

fn err_is(r: Result[Frame, FrameError], kind: Int, offset: Int) -> Bool {
  if r.is_ok { return false; }
  let e: FrameError = r.error;
  return e.kind == kind && e.offset == offset;
}

fn err_bytes_is(r: Result[Vec[UInt8], FrameError], kind: Int) -> Bool {
  if r.is_ok { return false; }
  let e: FrameError = r.error;
  return e.kind == kind;
}

// ---------------------------------------------------------------------------
// f1: data frame golden -- exact wire bytes + field roundtrip
// ---------------------------------------------------------------------------

fn f1() -> TestResult {
  var payload: Vec[UInt8] = Vec[UInt8].new();
  payload.push(222 as UInt8);
  payload.push(173 as UInt8);
  var f = frame_data(16909060, 3, 42, -1, 5, payload);
  let enc = frame_encode(&f);
  var ok = true;
  if !enc.is_ok { ok = false; } else {
    let got: Vec[UInt8] = enc.value;
    var expect: Vec[Int] = Vec[Int].new();
    expect.push(1);   // version
    expect.push(2);   // kind data
    expect.push(4); expect.push(3); expect.push(2); expect.push(1);  // conn_id LE
    expect.push(3);   // channel
    expect.push(42); expect.push(0); expect.push(0); expect.push(0); // seq LE
    expect.push(255); expect.push(255); expect.push(255); expect.push(255); // ack -1
    expect.push(5); expect.push(0); expect.push(0); expect.push(0); // ack_bits LE
    expect.push(222); expect.push(173); // payload
    let want = mk(expect);
    if got.len() != 21 { ok = false; }
    if !same_bytes(&got, &want) { ok = false; }
    // decode roundtrip
    let dec = frame_decode(&got, 0);
    if !dec.is_ok { ok = false; } else {
      let d: Frame = dec.value;
      if d.version != FRAME_VERSION { ok = false; }
      if d.kind != FRAME_KIND_DATA { ok = false; }
      if d.conn_id != 16909060 { ok = false; }
      if d.channel != 3 { ok = false; }
      if d.seq != 42 { ok = false; }
      if d.ack != -1 { ok = false; }
      if d.ack_bits != 5 { ok = false; }
      if d.fragment { ok = false; }
      if d.size != 21 { ok = false; }
      if !same_bytes(&d.payload, &payload) { ok = false; }
    }
  }
  return test.assert(ok, "frames: data frame golden bytes (21) and field roundtrip");
}

// ---------------------------------------------------------------------------
// f2: hello / hello_ack / fin goldens
// ---------------------------------------------------------------------------

fn f2() -> TestResult {
  var ok = true;
  // hello(conn 7, protocol version 1): 21 bytes
  let h = frame_encode(&frame_hello(7, 1));
  if !h.is_ok { ok = false; } else {
    var expect: Vec[Int] = Vec[Int].new();
    expect.push(1);
    expect.push(0); // kind hello
    expect.push(7); expect.push(0); expect.push(0); expect.push(0);
    expect.push(0); // channel
    expect.push(0); expect.push(0); expect.push(0); expect.push(0); // seq
    expect.push(255); expect.push(255); expect.push(255); expect.push(255); // ack -1
    expect.push(0); expect.push(0); expect.push(0); expect.push(0); // ack_bits
    expect.push(1); expect.push(0); // protocol version u16 LE
    let want = mk(expect);
    let got: Vec[UInt8] = h.value;
    if got.len() != 21 { ok = false; }
    if !same_bytes(&got, &want) { ok = false; }
    let dec = frame_decode(&got, 0);
    if !dec.is_ok { ok = false; } else {
      let d: Frame = dec.value;
      if d.kind != FRAME_KIND_HELLO { ok = false; }
      if d.protocol_version != 1 { ok = false; }
      if d.conn_id != 7 { ok = false; }
    }
  }
  // hello_ack(7, 1): second byte 1
  let ha = frame_encode(&frame_hello_ack(7, 1));
  if !ha.is_ok { ok = false; } else {
    let got2: Vec[UInt8] = ha.value;
    if got2.len() != 21 { ok = false; }
    let b1: UInt8 = got2[1];
    if (b1 as Int) != 1 { ok = false; }
    let dec2 = frame_decode(&got2, 0);
    if !dec2.is_ok { ok = false; } else {
      let d2: Frame = dec2.value;
      if d2.kind != FRAME_KIND_HELLO_ACK { ok = false; }
      if d2.protocol_version != 1 { ok = false; }
    }
  }
  // fin(conn 9, reason 1): 20 bytes
  let fin = frame_encode(&frame_fin(9, FIN_REASON_VERSION_MISMATCH));
  if !fin.is_ok { ok = false; } else {
    var expect3: Vec[Int] = Vec[Int].new();
    expect3.push(1);
    expect3.push(6); // kind fin
    expect3.push(9); expect3.push(0); expect3.push(0); expect3.push(0);
    expect3.push(0);
    expect3.push(0); expect3.push(0); expect3.push(0); expect3.push(0);
    expect3.push(255); expect3.push(255); expect3.push(255); expect3.push(255);
    expect3.push(0); expect3.push(0); expect3.push(0); expect3.push(0);
    expect3.push(1); // reason
    let want3 = mk(expect3);
    let got3: Vec<UInt8> = fin.value;
    if got3.len() != 20 { ok = false; }
    if !same_bytes(&got3, &want3) { ok = false; }
    let dec3 = frame_decode(&got3, 0);
    if !dec3.is_ok { ok = false; } else {
      let d3: Frame = dec3.value;
      if d3.kind != FRAME_KIND_FIN { ok = false; }
      if d3.fin_reason != FIN_REASON_VERSION_MISMATCH { ok = false; }
    }
  }
  return test.assert(ok, "frames: hello/hello_ack/fin goldens and decode");
}

// ---------------------------------------------------------------------------
// f3: fragment frame golden + metadata decode
// ---------------------------------------------------------------------------

fn f3() -> TestResult {
  var chunk: Vec[UInt8] = Vec[UInt8].new();
  chunk.push(7 as UInt8);
  chunk.push(8 as UInt8);
  var f = frame_data_fragment(1, 2, 5, -1, 0, 1, 3, 100, 250, chunk);
  let enc = frame_encode(&f);
  var ok = true;
  if !enc.is_ok { ok = false; } else {
    var expect: Vec[Int] = Vec[Int].new();
    expect.push(1);
    expect.push(18); // kind data (2) | FRAME_FLAG_FRAGMENT (16)
    expect.push(1); expect.push(0); expect.push(0); expect.push(0);
    expect.push(2);
    expect.push(5); expect.push(0); expect.push(0); expect.push(0);
    expect.push(255); expect.push(255); expect.push(255); expect.push(255);
    expect.push(0); expect.push(0); expect.push(0); expect.push(0);
    expect.push(1); expect.push(0);    // frag_index 1
    expect.push(3); expect.push(0);    // frag_count 3
    expect.push(100); expect.push(0); expect.push(0); expect.push(0); // frag_offset
    expect.push(250); expect.push(0); expect.push(0); expect.push(0); // frag_total
    expect.push(7); expect.push(8);    // chunk
    let want = mk(expect);
    let got: Vec[UInt8] = enc.value;
    if got.len() != 33 { ok = false; }
    if !same_bytes(&got, &want) { ok = false; }
    let dec = frame_decode(&got, 0);
    if !dec.is_ok { ok = false; } else {
      let d: Frame = dec.value;
      if !d.fragment { ok = false; }
      if d.frag_index != 1 { ok = false; }
      if d.frag_count != 3 { ok = false; }
      if d.frag_offset != 100 { ok = false; }
      if d.frag_total != 250 { ok = false; }
      if d.size != 33 { ok = false; }
      if d.payload.len() != 2 { ok = false; }
      if !same_bytes(&d.payload, &chunk) { ok = false; }
    }
  }
  return test.assert(ok, "frames: fragment frame golden (33) with index/count/offset/total");
}

// ---------------------------------------------------------------------------
// f4: little-endian primitives
// ---------------------------------------------------------------------------

fn f4() -> TestResult {
  var ok = true;
  var a: Vec[UInt8] = Vec[UInt8].new();
  put_u16_le(&mut a, 4660); // 0x1234
  var want_a: Vec[Int] = Vec[Int].new();
  want_a.push(52); want_a.push(18);
  if !same_bytes(&a, &mk(want_a)) { ok = false; }
  var b: Vec[UInt8] = Vec[UInt8].new();
  put_u32_le(&mut b, 16909060); // 0x01020304
  var want_b: Vec[Int] = Vec[Int].new();
  want_b.push(4); want_b.push(3); want_b.push(2); want_b.push(1);
  if !same_bytes(&b, &mk(want_b)) { ok = false; }
  // read back at an offset
  var buf: Vec[UInt8] = Vec[UInt8].new();
  buf.push(0 as UInt8);
  buf.push(0 as UInt8);
  put_u16_le(&mut buf, 48879); // 0xBEEF
  if read_u16_le(&buf, 2) != 48879 { ok = false; }
  if read_u16_le(&buf, 0) != 0 { ok = false; }
  if read_u32_le(&buf, 0) != 3203334144 { ok = false; } // 0xBEEF0000
  // total reads: out-of-range yields 0, never a crash
  if read_u16_le(&buf, 3) != 0 { ok = false; }
  if read_u32_le(&buf, 2) != 0 { ok = false; }
  if read_u16_le(&buf, -1) != 0 { ok = false; }
  if read_u32_le(&buf, 100) != 0 { ok = false; }
  // full u32 range
  var c: Vec[UInt8] = Vec[UInt8].new();
  put_u32_le(&mut c, 4294967295);
  var want_c: Vec[Int] = Vec[Int].new();
  want_c.push(255); want_c.push(255); want_c.push(255); want_c.push(255);
  if !same_bytes(&c, &mk(want_c)) { ok = false; }
  if read_u32_le(&c, 0) != 4294967295 { ok = false; }
  return test.assert(ok, "frames: little-endian primitives (u16/u32 put/read, offsets, totals)");
}

// ---------------------------------------------------------------------------
// f5: truncation errors carry exact byte offsets
// ---------------------------------------------------------------------------

fn f5() -> TestResult {
  var ok = true;
  var empty: Vec[UInt8] = Vec[UInt8].new();
  if !err_is(frame_decode(&empty, 0), FRAME_ERR_HEADER, 0) { ok = false; }
  let short_buf = zeros(10);
  if !err_is(frame_decode(&short_buf, 0), FRAME_ERR_HEADER, 0) { ok = false; }
  // hello truncated one byte short of protocol_version
  let h = frame_encode(&frame_hello(7, 1));
  if !h.is_ok { ok = false; } else {
    let cut = truncate(&h.value, 20);
    if !err_is(frame_decode(&cut, 0), FRAME_ERR_TRUNCATED, 19) { ok = false; }
  }
  // fin truncated to the bare header
  let fin = frame_encode(&frame_fin(9, 0));
  if !fin.is_ok { ok = false; } else {
    let cut2 = truncate(&fin.value, 19);
    if !err_is(frame_decode(&cut2, 0), FRAME_ERR_TRUNCATED, 19) { ok = false; }
  }
  // fragment frame with no metadata
  var frag_head: Vec[UInt8] = Vec[UInt8].new();
  frag_head.push(1 as UInt8);
  frag_head.push(18 as UInt8);
  var zpad = zeros(17);
  let frag19 = concat2(&frag_head, &zpad);
  if !err_is(frame_decode(&frag19, 0), FRAME_ERR_TRUNCATED, 19) { ok = false; }
  // decode at an offset: 2 junk bytes then a valid ack frame
  let ack = frame_encode(&frame_ack(1, 2, 0, 0));
  if !ack.is_ok { ok = false; } else {
    var pair: Vec[UInt8] = Vec[UInt8].new();
    pair.push(0 as UInt8);
    pair.push(0 as UInt8);
    let padded = concat2(&pair, &ack.value);
    let dec = frame_decode(&padded, 2);
    if !dec.is_ok { ok = false; } else {
      let d: Frame = dec.value;
      if d.kind != FRAME_KIND_ACK { ok = false; }
      if d.size != 19 { ok = false; }
    }
    // the same buffer at offset 0 is a version violation at byte 0
    if !err_is(frame_decode(&padded, 0), FRAME_ERR_VERSION, 0) { ok = false; }
  }
  // offset out of range (beyond end and negative) is typed
  let ok_ack = frame_encode(&frame_ack(1, 0, 0, 0));
  if ok_ack.is_ok {
    if !err_is(frame_decode(&ok_ack.value, 20), FRAME_ERR_OFFSET, 0) { ok = false; }
    if !err_is(frame_decode(&ok_ack.value, -1), FRAME_ERR_OFFSET, 0) { ok = false; }
  }
  return test.assert(ok, "frames: truncation and offset errors carry exact byte offsets");
}

// ---------------------------------------------------------------------------
// f6: garbage frames are typed (kind/flags/version/trailing bytes)
// ---------------------------------------------------------------------------

fn f6() -> TestResult {
  var ok = true;
  // unknown kind 9
  var k9: Vec[UInt8] = Vec[UInt8].new();
  k9.push(1 as UInt8);
  k9.push(9 as UInt8);
  let k9f = concat2(&k9, &zeros(17));
  if !err_is(frame_decode(&k9f, 0), FRAME_ERR_KIND, 1) { ok = false; }
  // unknown flag bits (0x20)
  var fx: Vec<UInt8] = Vec[UInt8].new();
  fx.push(1 as UInt8);
  fx.push(34 as UInt8);
  let fxf = concat2(&fx, &zeros(17));
  if !err_is(frame_decode(&fxf, 0), FRAME_ERR_FLAGS, 1) { ok = false; }
  // fragment flag on a non-data kind (ack = 3 | 16 = 19)
  var fa: Vec[UInt8] = Vec[UInt8].new();
  fa.push(1 as UInt8);
  fa.push(19 as UInt8);
  let faf = concat2(&fa, &zeros(17));
  if !err_is(frame_decode(&faf, 0), FRAME_ERR_FLAGS, 1) { ok = false; }
  // foreign wire version
  var v2: Vec[UInt8] = Vec[UInt8].new();
  v2.push(2 as UInt8);
  let v2f = concat2(&v2, &zeros(18));
  if !err_is(frame_decode(&v2f, 0), FRAME_ERR_VERSION, 0) { ok = false; }
  // trailing bytes after fixed-size kinds
  let ack = frame_encode(&frame_ack(1, 0, 0, 0));
  if !ack.is_ok { ok = false; } else {
    var extra: Vec[UInt8] = Vec[UInt8].new();
    extra.push(7 as UInt8);
    let padded = concat2(&ack.value, &extra);
    if !err_is(frame_decode(&padded, 0), FRAME_ERR_SIZE, 19) { ok = false; }
  }
  let hello = frame_encode(&frame_hello(1, 1));
  if !hello.is_ok { ok = false; } else {
    var extra2: Vec[UInt8] = Vec[UInt8].new();
    extra2.push(7 as UInt8);
    let padded2 = concat2(&hello.value, &extra2);
    if !err_is(frame_decode(&padded2, 0), FRAME_ERR_SIZE, 21) { ok = false; }
  }
  // encode-side refusals: unknown kind, negative seq, payload on fixed kind
  var bad = frame_new(99);
  if !err_bytes_is(frame_encode(&bad), FRAME_ERR_KIND) { ok = false; }
  var bad2 = frame_new(FRAME_KIND_DATA);
  bad2.seq = -5;
  if !err_bytes_is(frame_encode(&bad2), FRAME_ERR_SIZE) { ok = false; }
  var bad3 = frame_new(FRAME_KIND_ACK);
  var tiny: Vec[UInt8] = Vec[UInt8].new();
  tiny.push(1 as UInt8);
  bad3.payload = tiny;
  if !err_bytes_is(frame_encode(&bad3), FRAME_ERR_SIZE) { ok = false; }
  return test.assert(ok, "frames: garbage kind/flags/version/trailing are typed verdicts");
}

// ---------------------------------------------------------------------------
// f7: hard size caps and fragment consistency
// ---------------------------------------------------------------------------

fn f7() -> TestResult {
  var ok = true;
  // constants coherence with the shared caps module
  if FRAME_MAX_DATAGRAM != TX_CAP_MAX_DATAGRAM { ok = false; }
  if FRAME_HEADER_SIZE != TX_CAP_HEADER { ok = false; }
  if FRAME_FRAG_META_SIZE != TX_CAP_FRAG_META { ok = false; }
  if FRAME_MAX_PAYLOAD != TX_CAP_MAX_PAYLOAD { ok = false; }
  // oversize payload never encodes
  let big = zeros(FRAME_MAX_PAYLOAD + 1);
  var fbig = frame_data(1, 0, 0, -1, 0, big);
  if !err_bytes_is(frame_encode(&fbig), FRAME_ERR_SIZE) { ok = false; }
  // the cap-sized payload encodes and its frame fits one datagram
  let fit = zeros(FRAME_MAX_PAYLOAD);
  var ffit = frame_data(1, 0, 0, -1, 0, fit);
  let enc_fit = frame_encode(&ffit);
  if !enc_fit.is_ok { ok = false; } else {
    let got: Vec[UInt8] = enc_fit.value;
    if got.len() != FRAME_HEADER_SIZE + FRAME_MAX_PAYLOAD { ok = false; }
    if got.len() > FRAME_MAX_DATAGRAM { ok = false; }
  }
  // oversize datagram never decodes
  var over: Vec[UInt8] = Vec[UInt8].new();
  over.push(1 as UInt8);
  over.push(2 as UInt8);
  var zrest = zeros(FRAME_MAX_DATAGRAM + 1 - 2);
  let overf = concat2(&over, &zrest);
  if !err_is(frame_decode(&overf, 0), FRAME_ERR_SIZE, 0) { ok = false; }
  // fragment metadata consistency on decode
  var chunk: Vec[UInt8] = Vec[UInt8].new();
  chunk.push(7 as UInt8);
  chunk.push(8 as UInt8);
  let good = frame_encode(&frame_data_fragment(1, 0, 0, -1, 0, 1, 3, 100, 250, chunk));
  if !good.is_ok { ok = false; } else {
    let gb: Vec[UInt8] = good.value;
    // a) index >= count: patch index bytes (19,20) to 5,0
    var pa: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < gb.len() {
      var b: UInt8 = gb[i];
      if i == 19 { b = 5 as UInt8; }
      if i == 20 { b = 0 as UInt8; }
      pa.push(b);
      i = i + 1;
    }
    if !err_is(frame_decode(&pa, 0), FRAME_ERR_FRAG, 19) { ok = false; }
    // b) offset+chunk_len > total: patch total (28..31) to 100
    var pb: Vec<UInt8> = Vec[UInt8].new();
    var j = 0;
    while j < gb.len() {
      var b: UInt8 = gb[j];
      if j == 27 { b = 100 as UInt8; }
      if j == 28 { b = 0 as UInt8; }
      if j == 29 { b = 0 as UInt8; }
      if j == 30 { b = 0 as UInt8; }
      pb.push(b);
      j = j + 1;
    }
    if !err_is(frame_decode(&pb, 0), FRAME_ERR_FRAG, 23) { ok = false; }
    // c) frag_total above FRAME_MAX_MESSAGE: patch total to 0x00040001
    var pc: Vec<UInt8] = Vec[UInt8].new();
    var k = 0;
    while k < gb.len() {
      var b: UInt8 = gb[k];
      if k == 27 { b = 1 as UInt8; }
      if k == 28 { b = 0 as UInt8; }
      if k == 29 { b = 4 as UInt8; }
      if k == 30 { b = 0 as UInt8; }
      pc.push(b);
      k = k + 1;
    }
    if !err_is(frame_decode(&pc, 0), FRAME_ERR_FRAG, 27) { ok = false; }
  }
  // encode-side fragment refusals
  var bad1 = frame_data_fragment(1, 0, 0, -1, 0, 3, 3, 0, 10, chunk);
  if !err_bytes_is(frame_encode(&bad1), FRAME_ERR_FRAG) { ok = false; }
  var bad2 = frame_data_fragment(1, 0, 0, -1, 0, 0, 2, 5, 6, chunk);
  if !err_bytes_is(frame_encode(&bad2), FRAME_ERR_FRAG) { ok = false; }
  return test.assert(ok, "frames: hard caps (payload/datagram/message) and fragment consistency");
}

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r1 = f1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = f2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = f3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = f4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = f5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = f6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = f7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  return failed;
}
