// XIOM -- xiom.nats conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: kind ids and direction sets, subject filter and
// literal validation ('.' token structure, '*'/'>' wildcards, NUL/control
// rejection), wildcard matching, pinned PUB/HPUB/SUB/UNSUB/MSG/HMSG/PING/
// PONG/+OK/-ERR parsing with binary payloads built in-test (embedded NULs,
// CR, LF and bytes >= 128), CRLF framing errors, the 4096-byte control-line
// boundary, consumed-count streams, pinned encoders, encode -> parse ->
// encode round-trips and the INFO/CONNECT JSON key lookups.
//
// Str values are compared with str_compare (BUG 17 discipline), every Vec
// read is bound to a typed local, and Result values are unwrapped through
// .is_ok/.value or match-free helpers.

module nats_tests
use xiom.io; use xiom.test;
use xiom.nats;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; a caller's byte
// comparison then fails).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn addb(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Concatenate the parts in order (byte-exact, binary safe).
fn cat(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < parts.len() {
    let p: Vec[UInt8] = parts[i];
    addb(&mut out, &p);
    i = i + 1;
  }
  return out;
}

// Deterministic binary stream of n bytes; n >= 220 includes a NUL byte and
// bytes >= 128.
fn bin(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 7 + 3) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn enc_ok(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_op_is(r: Result[NatsOp, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Unwrap a successful parse (kind -1 sentinel makes the caller's field checks
// fail deterministically).
fn parse_ok(data: Vec[UInt8], off: Int) -> NatsOp {
  let r = nats_parse_op(&data, off);
  if r.is_ok {
    return r.value;
  }
  return NatsOp{
    kind: -1;
    subject: Vec[UInt8].new();
    reply: Vec[UInt8].new();
    queue: Vec[UInt8].new();
    sid: 0;
    max_msgs: 0;
    header_size: 0;
    total_size: 0;
    payload: Vec[UInt8].new();
    headers: Vec[UInt8].new();
    text: Vec[UInt8].new();
    consumed: 0;
  };
}

// Field helpers borrow the op (call sites pass &op): the checker flags a
// whole-op pass by value followed by field reads, so helpers never take the
// op by value.
fn op_subject_is(v: &NatsOp, want: Str) -> Bool {
  if v.subject.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.subject[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn op_reply_is(v: &NatsOp, want: Str) -> Bool {
  if v.reply.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.reply[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn op_queue_is(v: &NatsOp, want: Str) -> Bool {
  if v.queue.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.queue[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn op_text_is(v: &NatsOp, want: Str) -> Bool {
  if v.text.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.text[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn op_payload_is(v: &NatsOp, want: Vec[UInt8]) -> Bool {
  if v.payload.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.payload[i] != want[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn op_headers_is(v: &NatsOp, want: Str) -> Bool {
  if v.headers.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if v.headers[i] != string.byte_at(want, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = nats_kind_connect() == 1;
  if nats_kind_pub() != 2 { ok = false; }
  if nats_kind_hpub() != 3 { ok = false; }
  if nats_kind_sub() != 4 { ok = false; }
  if nats_kind_unsub() != 5 { ok = false; }
  if nats_kind_ping() != 6 { ok = false; }
  if nats_kind_pong() != 7 { ok = false; }
  if nats_kind_info() != 8 { ok = false; }
  if nats_kind_msg() != 9 { ok = false; }
  if nats_kind_hmsg() != 10 { ok = false; }
  if nats_kind_ok() != 11 { ok = false; }
  if nats_kind_err() != 12 { ok = false; }
  if !str_eq(nats_kind_name(nats_kind_connect()), "CONNECT") { ok = false; }
  if !str_eq(nats_kind_name(nats_kind_hmsg()), "HMSG") { ok = false; }
  if !str_eq(nats_kind_name(nats_kind_ok()), "+OK") { ok = false; }
  if !str_eq(nats_kind_name(nats_kind_err()), "-ERR") { ok = false; }
  if !str_eq(nats_kind_name(99), "UNKNOWN") { ok = false; }
  if !nats_is_client_kind(nats_kind_pub()) { ok = false; }
  if nats_is_client_kind(nats_kind_msg()) { ok = false; }
  if !nats_is_server_kind(nats_kind_msg()) { ok = false; }
  if nats_is_server_kind(nats_kind_sub()) { ok = false; }
  if !nats_is_client_kind(nats_kind_pong()) { ok = false; }
  if !nats_is_server_kind(nats_kind_ping()) { ok = false; }
  if nats_max_control_line() != 4096 { ok = false; }
  if nats_max_payload_size() != 2147483647 { ok = false; }
  return assert(ok, "kind ids, names, direction sets and protocol limits");
}

fn t2() -> TestResult {
  var ok = nats_subject_is_valid(&bytes_of("foo"));
  if !nats_subject_is_valid(&bytes_of("foo.bar")) { ok = false; }
  if !nats_subject_is_valid(&bytes_of("*")) { ok = false; }
  if !nats_subject_is_valid(&bytes_of(">")) { ok = false; }
  if !nats_subject_is_valid(&bytes_of("foo.*")) { ok = false; }
  if !nats_subject_is_valid(&bytes_of("foo.>")) { ok = false; }
  if !nats_subject_is_valid(&bytes_of("*.foo.bar")) { ok = false; }
  if !nats_subject_is_valid(&bytes_of("foo.*.bar")) { ok = false; }
  if !nats_subject_is_valid(&bytes_of("a-b_c.1")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("")) { ok = false; }
  if nats_subject_is_valid(&bytes_of(".")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("foo.")) { ok = false; }
  if nats_subject_is_valid(&bytes_of(".foo")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("foo..bar")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("foo.>.bar")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("foo*")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("*foo")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("a.*b")) { ok = false; }
  if nats_subject_is_valid(&bytes_of("fo o")) { ok = false; }
  var nul = Vec[UInt8].new();
  nul.push(102 as UInt8);
  nul.push(0 as UInt8);
  nul.push(111 as UInt8);
  if nats_subject_is_valid(&nul) { ok = false; }
  if !nats_publish_subject_is_valid(&bytes_of("foo.bar_1-a")) { ok = false; }
  if nats_publish_subject_is_valid(&bytes_of("foo.*")) { ok = false; }
  if nats_publish_subject_is_valid(&bytes_of(">")) { ok = false; }
  if nats_publish_subject_is_valid(&bytes_of("foo..bar")) { ok = false; }
  return assert(ok, "filter and literal subject validation incl. wildcards and NUL");
}

fn t3() -> TestResult {
  var ok = nats_subject_matches(&bytes_of("foo.bar"), &bytes_of("foo.bar"));
  if nats_subject_matches(&bytes_of("foo.bar"), &bytes_of("foo.baz")) { ok = false; }
  if !nats_subject_matches(&bytes_of("foo.*"), &bytes_of("foo.bar")) { ok = false; }
  if nats_subject_matches(&bytes_of("foo.*"), &bytes_of("foo")) { ok = false; }
  if nats_subject_matches(&bytes_of("foo.*"), &bytes_of("foo.a.b")) { ok = false; }
  if !nats_subject_matches(&bytes_of("foo.>"), &bytes_of("foo.a.b")) { ok = false; }
  if !nats_subject_matches(&bytes_of("foo.>"), &bytes_of("foo.a")) { ok = false; }
  if nats_subject_matches(&bytes_of("foo.>"), &bytes_of("foo")) { ok = false; }
  if !nats_subject_matches(&bytes_of(">"), &bytes_of("anything.at.all")) { ok = false; }
  if !nats_subject_matches(&bytes_of("*"), &bytes_of("single")) { ok = false; }
  if nats_subject_matches(&bytes_of("*"), &bytes_of("two.tokens")) { ok = false; }
  if !nats_subject_matches(&bytes_of("*.svc.*"), &bytes_of("us.svc.east")) { ok = false; }
  if nats_subject_matches(&bytes_of("*.svc.*"), &bytes_of("us.svc")) { ok = false; }
  if nats_subject_matches(&bytes_of("bad.."), &bytes_of("bad..")) { ok = false; }
  if nats_subject_matches(&bytes_of("foo.*"), &bytes_of("foo.*")) { ok = false; }
  return assert(ok, "wildcard filter matching against literal subjects");
}

fn t4() -> TestResult {
  let buf = bytes_of("PUB foo 5\r\nhello\r\n");
  let r = nats_parse_op(&buf, 0);
  var ok = r.is_ok;
  if r.is_ok {
    let op: NatsOp = r.value;
    if op.kind != nats_kind_pub() { ok = false; }
    if !op_subject_is(&op, "foo") { ok = false; }
    let rl: Vec[UInt8] = op.reply;
    if rl.len() != 0 { ok = false; }
    if op.total_size != 5 { ok = false; }
    if !op_payload_is(&op, bytes_of("hello")) { ok = false; }
    if op.consumed != 18 { ok = false; }
  }
  return assert(ok, "PUB parse pinned: subject, size, payload and consumed");
}

fn t5() -> TestResult {
  var pl = Vec[UInt8].new();
  pl.push(0 as UInt8);
  pl.push(255 as UInt8);
  pl.push(128 as UInt8);
  pl.push(13 as UInt8);
  pl.push(10 as UInt8);
  pl.push(66 as UInt8);
  var parts = Vec[Vec[UInt8]].new();
  parts.push(bytes_of("PUB jobs done 6\r\n"));
  parts.push(pl);
  parts.push(bytes_of("\r\n"));
  let buf = cat(&parts);
  var expected = Vec[UInt8].new();
  expected.push(0 as UInt8);
  expected.push(255 as UInt8);
  expected.push(128 as UInt8);
  expected.push(13 as UInt8);
  expected.push(10 as UInt8);
  expected.push(66 as UInt8);
  let r = nats_parse_op(&buf, 0);
  var ok = r.is_ok;
  if r.is_ok {
    let op: NatsOp = r.value;
    if op.kind != nats_kind_pub() { ok = false; }
    if !op_subject_is(&op, "jobs") { ok = false; }
    if !op_reply_is(&op, "done") { ok = false; }
    if op.total_size != 6 { ok = false; }
    if !op_payload_is(&op, expected) { ok = false; }
    if op.consumed != buf.len() { ok = false; }
  }
  return assert(ok, "PUB reply + binary payload with NUL, CR, LF and >= 128 bytes");
}

fn t6() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(bytes_of("HPUB hdr subj 12 17\r\n"));
  parts.push(bytes_of("NATS/1.0\r\n\r\n"));
  parts.push(bytes_of("hello"));
  parts.push(bytes_of("\r\n"));
  let buf = cat(&parts);
  let r = nats_parse_op(&buf, 0);
  var ok = r.is_ok;
  if r.is_ok {
    let op: NatsOp = r.value;
    if op.kind != nats_kind_hpub() { ok = false; }
    if !op_subject_is(&op, "hdr") { ok = false; }
    if op.header_size != 12 { ok = false; }
    if op.total_size != 17 { ok = false; }
    if !op_headers_is(&op, "NATS/1.0\r\n\r\n") { ok = false; }
    if !op_payload_is(&op, bytes_of("hello")) { ok = false; }
    if op.consumed != buf.len() { ok = false; }
  }
  let rep = bytes_of("HPUB hdr done 12 17\r\nNATS/1.0\r\n\r\nhello\r\n");
  let r2 = nats_parse_op(&rep, 0);
  if !r2.is_ok { ok = false; } else {
    let op2: NatsOp = r2.value;
    if !op_reply_is(&op2, "done") { ok = false; }
    if op2.header_size != 12 { ok = false; }
  }
  return assert(ok, "HPUB parse pinned with and without reply");
}

fn t7() -> TestResult {
  let m = bytes_of("MSG foo 1 5\r\nhello\r\n");
  let rm = nats_parse_op(&m, 0);
  var ok = rm.is_ok;
  if rm.is_ok {
    let op: NatsOp = rm.value;
    if op.kind != nats_kind_msg() { ok = false; }
    if !op_subject_is(&op, "foo") { ok = false; }
    if op.sid != 1 { ok = false; }
    if op.total_size != 5 { ok = false; }
    if !op_payload_is(&op, bytes_of("hello")) { ok = false; }
    if op.consumed != m.len() { ok = false; }
  }
  let mr = bytes_of("MSG foo 1 reply 5\r\nhello\r\n");
  let rmr = nats_parse_op(&mr, 0);
  if !rmr.is_ok { ok = false; } else {
    let op2: NatsOp = rmr.value;
    if !op_reply_is(&op2, "reply") { ok = false; }
  }
  let h = bytes_of("HMSG foo 1 12 17\r\nNATS/1.0\r\n\r\nhello\r\n");
  let rh = nats_parse_op(&h, 0);
  if !rh.is_ok { ok = false; } else {
    let op3: NatsOp = rh.value;
    if op3.kind != nats_kind_hmsg() { ok = false; }
    if op3.sid != 1 { ok = false; }
    if op3.header_size != 12 { ok = false; }
    if op3.total_size != 17 { ok = false; }
    if !op_headers_is(&op3, "NATS/1.0\r\n\r\n") { ok = false; }
    if !op_payload_is(&op3, bytes_of("hello")) { ok = false; }
    if op3.consumed != h.len() { ok = false; }
  }
  let hr = bytes_of("HMSG foo 1 bar 12 17\r\nNATS/1.0\r\n\r\nhello\r\n");
  let rhr = nats_parse_op(&hr, 0);
  if !rhr.is_ok { ok = false; } else {
    let op4: NatsOp = rhr.value;
    if !op_reply_is(&op4, "bar") { ok = false; }
  }
  return assert(ok, "MSG/HMSG parse pinned with and without reply");
}

fn t8() -> TestResult {
  let s = bytes_of("SUB foo.* 1\r\n");
  let rs = nats_parse_op(&s, 0);
  var ok = rs.is_ok;
  if rs.is_ok {
    let op: NatsOp = rs.value;
    if op.kind != nats_kind_sub() { ok = false; }
    if !op_subject_is(&op, "foo.*") { ok = false; }
    let ql: Vec[UInt8] = op.queue;
    if ql.len() != 0 { ok = false; }
    if op.sid != 1 { ok = false; }
    if op.consumed != s.len() { ok = false; }
  }
  let sq = bytes_of("SUB foo workers 2\r\n");
  let rsq = nats_parse_op(&sq, 0);
  if !rsq.is_ok { ok = false; } else {
    let op2: NatsOp = rsq.value;
    if !op_queue_is(&op2, "workers") { ok = false; }
    if op2.sid != 2 { ok = false; }
  }
  let u = bytes_of("UNSUB 3\r\n");
  let ru = nats_parse_op(&u, 0);
  if !ru.is_ok { ok = false; } else {
    let op3: NatsOp = ru.value;
    if op3.kind != nats_kind_unsub() { ok = false; }
    if op3.sid != 3 { ok = false; }
    if op3.max_msgs != 0 { ok = false; }
    if op3.consumed != u.len() { ok = false; }
  }
  let um = bytes_of("UNSUB 3 7\r\n");
  let rum = nats_parse_op(&um, 0);
  if !rum.is_ok { ok = false; } else {
    let op4: NatsOp = rum.value;
    if op4.max_msgs != 7 { ok = false; }
  }
  return assert(ok, "SUB/UNSUB parse pinned incl. queue group and max_msgs");
}

fn t9() -> TestResult {
  let p = bytes_of("PING\r\n");
  let rp = nats_parse_op(&p, 0);
  var ok = rp.is_ok;
  if rp.is_ok {
    let op: NatsOp = rp.value;
    if op.kind != nats_kind_ping() { ok = false; }
    if op.consumed != 6 { ok = false; }
  }
  let q = bytes_of("PONG\r\n");
  let rq = nats_parse_op(&q, 0);
  if !rq.is_ok { ok = false; } else {
    let op2: NatsOp = rq.value;
    if op2.kind != nats_kind_pong() { ok = false; }
    if op2.consumed != 6 { ok = false; }
  }
  let k = bytes_of("+OK\r\n");
  let rk = nats_parse_op(&k, 0);
  if !rk.is_ok { ok = false; } else {
    let op3: NatsOp = rk.value;
    if op3.kind != nats_kind_ok() { ok = false; }
    if op3.consumed != 5 { ok = false; }
  }
  let e = bytes_of("-ERR Unknown Protocol Operation\r\n");
  let re = nats_parse_op(&e, 0);
  if !re.is_ok { ok = false; } else {
    let op4: NatsOp = re.value;
    if op4.kind != nats_kind_err() { ok = false; }
    if !op_text_is(&op4, "Unknown Protocol Operation") { ok = false; }
    if op4.consumed != e.len() { ok = false; }
  }
  if !err_op_is(nats_parse_op(&bytes_of("PING x\r\n"), 0), "nats: bad args at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("+OK x\r\n"), 0), "nats: bad args at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("-ERR\r\n"), 0), "nats: bad args at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("BOGUS\r\n"), 0), "nats: unknown op at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PINGX\r\n"), 0), "nats: unknown op at 0") { ok = false; }
  return assert(ok, "PING/PONG/+OK/-ERR parse pinned and no-arg errors");
}

fn t10() -> TestResult {
  let c = bytes_of("CONNECT {\"verbose\":false,\"name\":\"c1\"}\r\n");
  let rc = nats_parse_op(&c, 0);
  var ok = rc.is_ok;
  if rc.is_ok {
    let op: NatsOp = rc.value;
    if op.kind != nats_kind_connect() { ok = false; }
    if !op_text_is(&op, "{\"verbose\":false,\"name\":\"c1\"}") { ok = false; }
    if op.consumed != c.len() { ok = false; }
  }
  let i = bytes_of("INFO {\"server_id\":\"ND1\",\"max_payload\":1048576}\r\n");
  let ri = nats_parse_op(&i, 0);
  if !ri.is_ok { ok = false; } else {
    let op2: NatsOp = ri.value;
    if op2.kind != nats_kind_info() { ok = false; }
    if !op_text_is(&op2, "{\"server_id\":\"ND1\",\"max_payload\":1048576}") { ok = false; }
  }
  let e = bytes_of("INFO {}\r\n");
  let re = nats_parse_op(&e, 0);
  if !re.is_ok { ok = false; } else {
    let op3: NatsOp = re.value;
    if !op_text_is(&op3, "{}") { ok = false; }
  }
  if !err_op_is(nats_parse_op(&bytes_of("CONNECT nope\r\n"), 0), "nats: bad json at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("CONNECT\r\n"), 0), "nats: bad args at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("INFO {\r\n"), 0), "nats: bad json at 0") { ok = false; }
  return assert(ok, "CONNECT/INFO JSON object parse pinned and shape errors");
}

fn t11() -> TestResult {
  var ok = err_op_is(nats_parse_op(&bytes_of("PUB foo\r\n"), 0), "nats: bad args at 0");
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo bar baz 5\r\n"), 0), "nats: bad args at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo x5\r\n"), 0), "nats: bad size at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo -1\r\n"), 0), "nats: bad size at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo 99999999999999999999\r\n"), 0), "nats: bad size at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo.* 1\r\nh\r\n"), 0), "nats: bad subject at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo..bar 1\r\nh\r\n"), 0), "nats: bad subject at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo bad..reply 1\r\nh\r\n"), 0), "nats: bad reply at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo bar.* 1\r\nh\r\n"), 0), "nats: bad reply at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("xx PUB foo\r\n"), 3), "nats: bad args at 3") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PING\r\n"), -1), "nats: negative offset at -1") { ok = false; }
  let lz = bytes_of("PUB foo 007\r\nabcdefg\r\n");
  let rlz = nats_parse_op(&lz, 0);
  if !rlz.is_ok { ok = false; } else {
    let opl: NatsOp = rlz.value;
    if opl.total_size != 7 { ok = false; }
  }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo 7\r\nabcdefgX\r\n"), 0), "nats: bad payload terminator at 0") { ok = false; }
  return assert(ok, "PUB argument, size, subject and reply parse errors with offsets");
}

fn t12() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = err_op_is(nats_parse_op(&empty, 0), "nats: truncated op at 0");
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo 5"), 0), "nats: truncated op at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo 5\r\nhel"), 0), "nats: truncated payload at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo 5\r\nhelloXX\r\n"), 0), "nats: bad payload terminator at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("PUB foo 5\r\n"), 0), "nats: truncated payload at 0") { ok = false; }
  let ping6 = bytes_of("PING\r\n");
  if !err_op_is(nats_parse_op(&ping6, ping6.len()), "nats: truncated op at 6") { ok = false; }
  var long4 = Vec[UInt8].new();
  var i = 0;
  while i < 4094 {
    long4.push(97 as UInt8);
    i = i + 1;
  }
  long4.push(13 as UInt8);
  long4.push(10 as UInt8);
  if !err_op_is(nats_parse_op(&long4, 0), "nats: unknown op at 0") { ok = false; }
  var long5 = Vec[UInt8].new();
  i = 0;
  while i < 4095 {
    long5.push(97 as UInt8);
    i = i + 1;
  }
  long5.push(13 as UInt8);
  long5.push(10 as UInt8);
  if !err_op_is(nats_parse_op(&long5, 0), "nats: control line too long at 0") { ok = false; }
  return assert(ok, "CRLF framing errors and the 4096-byte control-line boundary");
}

fn t13() -> TestResult {
  var ok = err_op_is(nats_parse_op(&bytes_of("HPUB s 20 12\r\n"), 0), "nats: bad size at 0");
  if !err_op_is(nats_parse_op(&bytes_of("HPUB s 12 17\r\nABCDEFGHIJKLhello\r\n"), 0), "nats: bad headers at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("HPUB s 12 100\r\nNATS/1.0\r\n\r\n"), 0), "nats: truncated payload at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("HPUB s 12 17\r\nNATS/1.0\r\n\r\nhelloXX\r\n"), 0), "nats: bad payload terminator at 0") { ok = false; }
  let sp = bytes_of("HPUB s 16 17\r\nNATS/1.0 100\r\n\r\np\r\n");
  let rsp = nats_parse_op(&sp, 0);
  if !rsp.is_ok { ok = false; } else {
    let ops: NatsOp = rsp.value;
    if ops.header_size != 16 { ok = false; }
    if ops.total_size != 17 { ok = false; }
  }
  if !err_op_is(nats_parse_op(&bytes_of("HMSG foo 1 20 12\r\n"), 0), "nats: bad size at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("HMSG foo 1 12 17\r\nABCDEFGHIJKLhello\r\n"), 0), "nats: bad headers at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("HMSG foo 1 12 100\r\nNATS/1.0\r\n\r\n"), 0), "nats: truncated payload at 0") { ok = false; }
  return assert(ok, "HPUB/HMSG size, header, truncation and terminator errors");
}

fn t14() -> TestResult {
  var ok = err_op_is(nats_parse_op(&bytes_of("SUB foo 0\r\n"), 0), "nats: bad sid at 0");
  if !err_op_is(nats_parse_op(&bytes_of("SUB foo bar\r\n"), 0), "nats: bad sid at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("SUB foo.>.bar 1\r\n"), 0), "nats: bad subject at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("SUB foo 1 2 3\r\n"), 0), "nats: bad args at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("SUB foo b..q 2\r\n"), 0), "nats: bad queue at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("SUB foo q.* 2\r\n"), 0), "nats: bad queue at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("UNSUB 0\r\n"), 0), "nats: bad sid at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("UNSUB 3 0\r\n"), 0), "nats: bad max at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("UNSUB 3 x\r\n"), 0), "nats: bad max at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("UNSUB 3 7 9\r\n"), 0), "nats: bad args at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("MSG foo 0 5\r\n"), 0), "nats: bad sid at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("MSG foo.* 1 5\r\n"), 0), "nats: bad subject at 0") { ok = false; }
  if !err_op_is(nats_parse_op(&bytes_of("MSG foo 1 bad..reply 5\r\n"), 0), "nats: bad reply at 0") { ok = false; }
  return assert(ok, "SUB/UNSUB/MSG validation errors");
}

fn t15() -> TestResult {
  let z = bytes_of("PUB e 0\r\n\r\n");
  let rz = nats_parse_op(&z, 0);
  var ok = rz.is_ok;
  if rz.is_ok {
    let op: NatsOp = rz.value;
    if op.total_size != 0 { ok = false; }
    let pl: Vec[UInt8] = op.payload;
    if pl.len() != 0 { ok = false; }
    if op.consumed != 11 { ok = false; }
  }
  var payload = Vec[UInt8].new();
  payload.push(65 as UInt8);
  payload.push(13 as UInt8);
  payload.push(10 as UInt8);
  payload.push(66 as UInt8);
  payload.push(0 as UInt8);
  payload.push(255 as UInt8);
  payload.push(67 as UInt8);
  var parts = Vec[Vec[UInt8]].new();
  parts.push(bytes_of("PUB z 7\r\n"));
  parts.push(payload);
  parts.push(bytes_of("\r\nPING\r\n"));
  let buf = cat(&parts);
  var expected = Vec[UInt8].new();
  expected.push(65 as UInt8);
  expected.push(13 as UInt8);
  expected.push(10 as UInt8);
  expected.push(66 as UInt8);
  expected.push(0 as UInt8);
  expected.push(255 as UInt8);
  expected.push(67 as UInt8);
  let r = nats_parse_op(&buf, 0);
  if !r.is_ok { ok = false; } else {
    let op2: NatsOp = r.value;
    if !op_payload_is(&op2, expected) { ok = false; }
    if op2.consumed != 18 { ok = false; }
    let next = nats_parse_op(&buf, op2.consumed);
    if !next.is_ok { ok = false; } else {
      let op3: NatsOp = next.value;
      if op3.kind != nats_kind_ping() { ok = false; }
    }
  }
  return assert(ok, "byte-count framing: empty payload, embedded CRLF and resync to next op");
}

fn t16() -> TestResult {
  var parts = Vec[Vec[UInt8]].new();
  parts.push(bytes_of("PING\r\n"));
  parts.push(bytes_of("CONNECT {\"lang\":\"xiom\"}\r\n"));
  parts.push(bytes_of("PUB a 3\r\nxyz\r\n"));
  parts.push(bytes_of("SUB x.* 9\r\n"));
  parts.push(bytes_of("+OK\r\n"));
  let buf = cat(&parts);
  var ok = true;
  var off = 0;
  let o1 = nats_parse_op(&buf, off);
  if !o1.is_ok { ok = false; } else {
    let op1: NatsOp = o1.value;
    if op1.kind != nats_kind_ping() { ok = false; }
    off = off + op1.consumed;
  }
  let o2 = nats_parse_op(&buf, off);
  if !o2.is_ok { ok = false; } else {
    let op2: NatsOp = o2.value;
    if op2.kind != nats_kind_connect() { ok = false; }
    if off != 6 { ok = false; }
    off = off + op2.consumed;
  }
  let o3 = nats_parse_op(&buf, off);
  if !o3.is_ok { ok = false; } else {
    let op3: NatsOp = o3.value;
    if op3.kind != nats_kind_pub() { ok = false; }
    if !op_payload_is(&op3, bytes_of("xyz")) { ok = false; }
    off = off + op3.consumed;
  }
  let o4 = nats_parse_op(&buf, off);
  if !o4.is_ok { ok = false; } else {
    let op4: NatsOp = o4.value;
    if op4.kind != nats_kind_sub() { ok = false; }
    if !op_subject_is(&op4, "x.*") { ok = false; }
    off = off + op4.consumed;
  }
  let o5 = nats_parse_op(&buf, off);
  if !o5.is_ok { ok = false; } else {
    let op5: NatsOp = o5.value;
    if op5.kind != nats_kind_ok() { ok = false; }
    off = off + op5.consumed;
  }
  if off != buf.len() { ok = false; }
  if !err_op_is(nats_parse_op(&buf, 2), "nats: unknown op at 2") { ok = false; }
  return assert(ok, "one-op-at-a-time consumed counts walk a five-op stream");
}

fn t17() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = bytes_equal(enc_ok(nats_encode_pub(&bytes_of("foo"), &empty, &bytes_of("hello"))), bytes_of("PUB foo 5\r\nhello\r\n"));
  if !bytes_equal(enc_ok(nats_encode_pub(&bytes_of("foo"), &bytes_of("bar"), &bytes_of("hello"))), bytes_of("PUB foo bar 5\r\nhello\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_pub(&bytes_of("x"), &empty, &hb("00ff80"))), hb("505542207820330d0a00ff800d0a")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_sub(&bytes_of("foo.*"), &empty, 1)), bytes_of("SUB foo.* 1\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_sub(&bytes_of("foo"), &bytes_of("workers"), 2)), bytes_of("SUB foo workers 2\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_unsub(3, 0)), bytes_of("UNSUB 3\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_unsub(3, 7)), bytes_of("UNSUB 3 7\r\n")) { ok = false; }
  if !bytes_equal(nats_encode_ping(), bytes_of("PING\r\n")) { ok = false; }
  if !bytes_equal(nats_encode_pong(), bytes_of("PONG\r\n")) { ok = false; }
  if !bytes_equal(nats_encode_ok(), bytes_of("+OK\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_err(&bytes_of("slow consumer"))), bytes_of("-ERR slow consumer\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_connect(&bytes_of("{}"))), bytes_of("CONNECT {}\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_info(&bytes_of("{}"))), bytes_of("INFO {}\r\n")) { ok = false; }
  if !err_bytes_is(nats_encode_pub(&bytes_of("foo.*"), &empty, &empty), "nats: bad subject") { ok = false; }
  if !err_bytes_is(nats_encode_pub(&bytes_of("foo"), &bytes_of("bad..r"), &empty), "nats: bad reply") { ok = false; }
  if !err_bytes_is(nats_encode_sub(&bytes_of("a..b"), &empty, 1), "nats: bad subject") { ok = false; }
  if !err_bytes_is(nats_encode_sub(&bytes_of("a"), &bytes_of("q.*"), 1), "nats: bad queue") { ok = false; }
  if !err_bytes_is(nats_encode_sub(&bytes_of("a"), &empty, 0), "nats: bad sid") { ok = false; }
  if !err_bytes_is(nats_encode_unsub(-1, 0), "nats: bad sid") { ok = false; }
  if !err_bytes_is(nats_encode_unsub(1, -1), "nats: bad max") { ok = false; }
  if !err_bytes_is(nats_encode_hpub(&bytes_of("s"), &empty, &bytes_of("no"), &empty), "nats: bad headers") { ok = false; }
  if !err_bytes_is(nats_encode_err(&empty), "nats: bad error text") { ok = false; }
  if !err_bytes_is(nats_encode_connect(&bytes_of("nope")), "nats: bad json") { ok = false; }
  if !err_bytes_is(nats_encode_msg(&bytes_of("s"), 0, &empty, &empty), "nats: bad sid") { ok = false; }
  return assert(ok, "encoders pinned byte-exact and validation errors");
}

fn t18() -> TestResult {
  let empty = Vec[UInt8].new();
  let headers = bytes_of("NATS/1.0\r\n\r\n");
  var ok = bytes_equal(enc_ok(nats_encode_hpub(&bytes_of("s"), &empty, &headers, &bytes_of("p"))), bytes_of("HPUB s 12 13\r\nNATS/1.0\r\n\r\np\r\n"));
  if !bytes_equal(enc_ok(nats_encode_hpub(&bytes_of("s"), &bytes_of("r"), &headers, &bytes_of("p"))), bytes_of("HPUB s r 12 13\r\nNATS/1.0\r\n\r\np\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_msg(&bytes_of("foo"), 1, &empty, &bytes_of("hi"))), bytes_of("MSG foo 1 2\r\nhi\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_msg(&bytes_of("foo"), 1, &bytes_of("bar"), &bytes_of("hi"))), bytes_of("MSG foo 1 bar 2\r\nhi\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_hmsg(&bytes_of("foo"), 1, &empty, &headers, &bytes_of("hi"))), bytes_of("HMSG foo 1 12 14\r\nNATS/1.0\r\n\r\nhi\r\n")) { ok = false; }
  if !bytes_equal(enc_ok(nats_encode_hmsg(&bytes_of("foo"), 1, &bytes_of("bar"), &headers, &bytes_of("hi"))), bytes_of("HMSG foo 1 bar 12 14\r\nNATS/1.0\r\n\r\nhi\r\n")) { ok = false; }
  return assert(ok, "HPUB/MSG/HMSG encoders pinned byte-exact");
}

fn t19() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = true;
  let big = bin(260);
  let pe1 = enc_ok(nats_encode_pub(&bytes_of("bin.subj"), &bytes_of("d"), &big));
  let pr = nats_parse_op(&pe1, 0);
  if !pr.is_ok { ok = false; } else {
    let op: NatsOp = pr.value;
    if !op_payload_is(&op, big) { ok = false; }
    if op.consumed != pe1.len() { ok = false; }
    if !bytes_equal(enc_ok(nats_encode_pub(&op.subject, &op.reply, &op.payload)), pe1) { ok = false; }
  }
  let headers = bytes_of("NATS/1.0\r\nX-Test: 1\r\n\r\n");
  let hb1 = bin(90);
  let he1 = enc_ok(nats_encode_hpub(&bytes_of("h.subj"), &empty, &headers, &hb1));
  let hr = nats_parse_op(&he1, 0);
  if !hr.is_ok { ok = false; } else {
    let op2: NatsOp = hr.value;
    if op2.header_size != headers.len() { ok = false; }
    if !op_payload_is(&op2, hb1) { ok = false; }
    if !bytes_equal(enc_ok(nats_encode_hpub(&op2.subject, &op2.reply, &op2.headers, &op2.payload)), he1) { ok = false; }
  }
  let se1 = enc_ok(nats_encode_sub(&bytes_of("a.*.b"), &bytes_of("q1"), 42));
  let sr = nats_parse_op(&se1, 0);
  if !sr.is_ok { ok = false; } else {
    let op3: NatsOp = sr.value;
    if op3.sid != 42 { ok = false; }
    if !op_queue_is(&op3, "q1") { ok = false; }
    if !bytes_equal(enc_ok(nats_encode_sub(&op3.subject, &op3.queue, op3.sid)), se1) { ok = false; }
  }
  let ue1 = enc_ok(nats_encode_unsub(5, 3));
  let ur = nats_parse_op(&ue1, 0);
  if !ur.is_ok { ok = false; } else {
    let op4: NatsOp = ur.value;
    if !bytes_equal(enc_ok(nats_encode_unsub(op4.sid, op4.max_msgs)), ue1) { ok = false; }
  }
  let me1 = enc_ok(nats_encode_msg(&bytes_of("m.in"), 7, &bytes_of("r"), &bin(120)));
  let mr = nats_parse_op(&me1, 0);
  if !mr.is_ok { ok = false; } else {
    let op5: NatsOp = mr.value;
    if !bytes_equal(enc_ok(nats_encode_msg(&op5.subject, op5.sid, &op5.reply, &op5.payload)), me1) { ok = false; }
  }
  let hme1 = enc_ok(nats_encode_hmsg(&bytes_of("m.hin"), 8, &bytes_of("r2"), &headers, &bin(60)));
  let hmr = nats_parse_op(&hme1, 0);
  if !hmr.is_ok { ok = false; } else {
    let op6: NatsOp = hmr.value;
    if !bytes_equal(enc_ok(nats_encode_hmsg(&op6.subject, op6.sid, &op6.reply, &op6.headers, &op6.payload)), hme1) { ok = false; }
  }
  let ce1 = enc_ok(nats_encode_connect(&bytes_of("{\"lang\":\"xiom\",\"protocol\":1}")));
  let cr = nats_parse_op(&ce1, 0);
  if !cr.is_ok { ok = false; } else {
    let op7: NatsOp = cr.value;
    if !bytes_equal(enc_ok(nats_encode_connect(&op7.text)), ce1) { ok = false; }
  }
  let ie1 = enc_ok(nats_encode_info(&bytes_of("{\"proto\":1,\"headers\":true}")));
  let ir = nats_parse_op(&ie1, 0);
  if !ir.is_ok { ok = false; } else {
    let op8: NatsOp = ir.value;
    if !bytes_equal(enc_ok(nats_encode_info(&op8.text)), ie1) { ok = false; }
  }
  return assert(ok, "encode -> parse -> encode round-trips for every payload op");
}

fn t20() -> TestResult {
  let info = bytes_of("{\"server_id\":\"ND123\",\"server_name\":\"n1\",\"version\":\"2.10.7\",\"proto\":1,\"port\":4222,\"headers\":true,\"max_payload\":1048576,\"auth_required\":false,\"name\":\"inner_key\"}");
  var ok = bytes_equal(enc_ok(nats_json_str(&info, "server_id")), bytes_of("ND123"));
  if !bytes_equal(enc_ok(nats_json_str(&info, "server_name")), bytes_of("n1")) { ok = false; }
  if !bytes_equal(enc_ok(nats_json_str(&info, "version")), bytes_of("2.10.7")) { ok = false; }
  let ri = nats_json_int(&info, "proto");
  if !ri.is_ok { ok = false; } else {
    let v1: Int = ri.value;
    if v1 != 1 { ok = false; }
  }
  let rp = nats_json_int(&info, "port");
  if !rp.is_ok { ok = false; } else {
    let v2: Int = rp.value;
    if v2 != 4222 { ok = false; }
  }
  let rm = nats_json_int(&info, "max_payload");
  if !rm.is_ok { ok = false; } else {
    let v3: Int = rm.value;
    if v3 != 1048576 { ok = false; }
  }
  let rh = nats_json_bool(&info, "headers");
  if !rh.is_ok { ok = false; } else {
    let b1: Bool = rh.value;
    if !b1 { ok = false; }
  }
  let ra = nats_json_bool(&info, "auth_required");
  if !ra.is_ok { ok = false; } else {
    let b2: Bool = ra.value;
    if b2 { ok = false; }
  }
  if !nats_json_has(&info, "name") { ok = false; }
  if nats_json_has(&info, "inner_key") { ok = false; }
  if nats_json_has(&info, "absent") { ok = false; }
  let sp = bytes_of("{\"a\": \"x\", \"b\" : 2, \"c\":true}");
  if !bytes_equal(enc_ok(nats_json_str(&sp, "a")), bytes_of("x")) { ok = false; }
  let rsp = nats_json_int(&sp, "b");
  if !rsp.is_ok { ok = false; } else {
    let v4: Int = rsp.value;
    if v4 != 2 { ok = false; }
  }
  let rsc = nats_json_bool(&sp, "c");
  if !rsc.is_ok { ok = false; } else {
    let b3: Bool = rsc.value;
    if !b3 { ok = false; }
  }
  let cj = bytes_of("{\"verbose\":false,\"pedantic\":false,\"lang\":\"xiom\",\"version\":\"0.1.0\",\"protocol\":1,\"echo\":true,\"headers\":true}");
  let rv = nats_json_bool(&cj, "verbose");
  if !rv.is_ok { ok = false; } else {
    let b4: Bool = rv.value;
    if b4 { ok = false; }
  }
  let re = nats_json_bool(&cj, "echo");
  if !re.is_ok { ok = false; } else {
    let b5: Bool = re.value;
    if !b5 { ok = false; }
  }
  let rl = nats_json_str(&cj, "lang");
  if !rl.is_ok { ok = false; } else {
    if !bytes_equal(rl.value, bytes_of("xiom")) { ok = false; }
  }
  let rpr = nats_json_int(&cj, "protocol");
  if !rpr.is_ok { ok = false; } else {
    let v5: Int = rpr.value;
    if v5 != 1 { ok = false; }
  }
  return assert(ok, "INFO/CONNECT JSON key lookups: string, int, bool, has, spacing");
}

fn t21() -> TestResult {
  let info = bytes_of("{\"server_id\":\"ND123\",\"port\":4222,\"headers\":true}");
  var ok = err_bytes_is(nats_json_str(&info, "nope"), "nats: json key not found: nope");
  if !err_bytes_is(nats_json_str(&info, "port"), "nats: json bad value: port") { ok = false; }
  if !err_int_is(nats_json_int(&info, "server_id"), "nats: json bad value: server_id") { ok = false; }
  if !err_bool_is(nats_json_bool(&info, "port"), "nats: json bad value: port") { ok = false; }
  if !err_bytes_is(nats_json_str(&info, ""), "nats: json empty key") { ok = false; }
  if !err_bytes_is(nats_json_str(&bytes_of("{\"a\":\"x"), "a"), "nats: json bad value: a") { ok = false; }
  if !err_bytes_is(nats_json_str(&bytes_of("{\"a\":{\"b\":1}}"), "a"), "nats: json bad value: a") { ok = false; }
  if !err_int_is(nats_json_int(&bytes_of("{\"n\":99999999999}"), "n"), "nats: json bad value: n") { ok = false; }
  let esc = bytes_of("{\"a\":\"x\\\"y\",\"b\":1}");
  if !bytes_equal(enc_ok(nats_json_str(&esc, "a")), hb("785c2279")) { ok = false; }
  let reb = nats_json_int(&esc, "b");
  if !reb.is_ok { ok = false; } else {
    let v1: Int = reb.value;
    if v1 != 1 { ok = false; }
  }
  let neg = bytes_of("{\"n\":-5,\"m\":7}");
  let rn = nats_json_int(&neg, "n");
  if !rn.is_ok { ok = false; } else {
    let v2: Int = rn.value;
    if v2 != -5 { ok = false; }
  }
  let rm = nats_json_int(&neg, "m");
  if !rm.is_ok { ok = false; } else {
    let v3: Int = rm.value;
    if v3 != 7 { ok = false; }
  }
  return assert(ok, "JSON lookup errors, escapes, negative and bounded scalars");
}

fn main() -> Int {
  io.println("=== xiom.nats conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.nats: all tests passed");
  } else {
    io.println("xiom.nats: tests failed");
  }
  return failed;
}
