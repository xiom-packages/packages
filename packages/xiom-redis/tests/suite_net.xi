// XIOM -- xiom.redis conformance suite, part 2: client over loopback TCP
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Deterministic offline client tests over loopback TCP: the suite starts a
// scripted in-process RESP server (stdlib xiom.net.socket on a fixed
// candidate port) that pre-sends scripted replies; the client package runs
// real commands against it and the suite then reads the socket to assert
// the exact request bytes. Covered: PING roundtrip, SET/GET/ECHO, null
// bulk, integers and arrays (MGET), server error replies (raw + checked),
// pipeline, pub/sub SUBSCRIBE + read_push (+ push deadline), a stalled
// server read timeout, and a truncated reply classified as a protocol
// error. Real-network outcomes (refused connect, live server) live in
// tests/suite_live.xi.

module xiom.redis.suite_net

use xiom.io;
use xiom.test;
use xiom.string.compare;
use xiom.net.socket;
use xiom.redis;
use xiom.redis.value;
use xiom.redis.client;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

fn err_kind_of_str(r: Result[Str, RedisError], kind: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: RedisError = r.error;
  return e.kind == kind;
}

fn err_str_of(r: Result[Str, RedisError], kind: Int, code: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: RedisError = r.error;
  return e.kind == kind && e.code == code;
}

fn err_kind_of(r: Result[RedisValue, RedisError], kind: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: RedisError = r.error;
  return e.kind == kind;
}

fn kind_of_res(r: Result[RedisValue, RedisError], k: Int) -> Bool {
  if !r.is_ok { return false; }
  let v: RedisValue = r.value;
  return value_kind(&v) == k;
}

fn opt_is(r: Result[RedisText, RedisError], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let t: RedisText = r.value;
  match t {
    Missing => { return false; },
    Text(s) => { return streq(s, want); },
  }
}

fn opt_missing(r: Result[RedisText, RedisError]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let t: RedisText = r.value;
  match t {
    Missing => { return true; },
    Text(_) => { return false; },
  }
}

// ---------------------------------------------------------------------------
// Scripted in-process RESP server (loopback, deterministic, no threads: the
// server pre-sends a scripted reply; the client runs; the suite then reads
// the buffered request bytes and compares them exactly)
// ---------------------------------------------------------------------------

type SrvHandle = {
  fd: Int;
  port: Int;
}

fn ok_srv(v: SrvHandle) -> Result[SrvHandle, Str] { return Ok(v); }
fn err_srv(e: Str) -> Result[SrvHandle, Str] { return Err(e); }
fn ok_int_str(v: Int) -> Result[Int, Str] { return Ok(v); }
fn err_int_str(e: Str) -> Result[Int, Str] { return Err(e); }
fn ok_str_str(v: Str) -> Result[Str, Str] { return Ok(v); }
fn err_str_str(e: Str) -> Result[Str, Str] { return Err(e); }
fn ok_unit_str() -> Result[Unit, Str] { return Ok(()); }
fn err_unit_str(e: Str) -> Result[Unit, Str] { return Err(e); }

// Try a small set of fixed high ports until one binds+listens.
fn srv_start() -> Result[SrvHandle, Str] {
  var ports: Vec[Int] = Vec[Int].new();
  ports.push(46381);
  ports.push(46383);
  ports.push(46385);
  ports.push(46387);
  ports.push(46389);
  ports.push(46391);
  ports.push(46393);
  ports.push(46395);
  var i = 0;
  while i < ports.len() {
    let port: Int = ports[i];
    let t = socket_tcp();
    if t.is_ok {
      let fd: Int = t.value;
      let b = socket_bind(fd, "127.0.0.1", port);
      if b.is_ok {
        let l = socket_listen(fd, 4);
        if l.is_ok {
          return ok_srv(SrvHandle { fd: fd, port: port });
        }
      }
      socket_close(fd);
    }
    i = i + 1;
  }
  return err_srv("no free loopback port in the candidate set");
}

fn srv_accept(fd: Int) -> Result[Int, Str] {
  let r = socket_accept(fd);
  if !r.is_ok {
    return err_int_str(r.error);
  }
  return ok_int_str(r.value);
}

fn srv_send(fd: Int, s: Str) -> Result[Unit, Str] {
  let b = bytes_of(s);
  let r = socket_send_all(fd, &b);
  if !r.is_ok {
    return err_unit_str(r.error);
  }
  return ok_unit_str();
}

// Collect at least `want` bytes from the socket (bounded recv loop).
fn srv_recv_for(fd: Int, want: Int, timeout_ms: Int) -> Result[Str, Str] {
  var acc: Vec[UInt8] = Vec[UInt8].new();
  var guard = 0;
  while acc.len() < want && guard < 64 {
    guard = guard + 1;
    let r = socket_recv_timeout(fd, 65536, timeout_ms);
    if !r.is_ok {
      return err_str_str(r.error);
    }
    let chunk: Vec[UInt8] = r.value;
    if chunk.len() == 0 {
      break;
    }
    var i = 0;
    while i < chunk.len() {
      let b: UInt8 = chunk[i];
      acc.push(b);
      i = i + 1;
    }
  }
  return ok_str_str(Str::from_utf8(acc));
}

fn srv_close(fd: Int) {
  socket_close(fd);
}

// ---------------------------------------------------------------------------
// n8: offline server -- PING command roundtrip with exact request bytes
// ---------------------------------------------------------------------------

fn n8() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: PING roundtrip (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: PING roundtrip (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: PING roundtrip (accept failed)");
  }
  let afd: Int = ar.value;
  let snd = srv_send(afd, "+PONG\r\n");
  var ok = true;
  if !snd.is_ok { ok = false; }
  let pr = ping(&mut conn);
  if !pr.is_ok { ok = false; } else { if !streq(pr.value, "PONG") { ok = false; } }
  let expect = "*1\r\n$4\r\nPING\r\n";
  let rr = srv_recv_for(afd, expect.len(), 2000);
  if !rr.is_ok { ok = false; } else { if !streq(rr.value, expect) { ok = false; } }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: PING roundtrip -- typed reply and exact request bytes");
}

// ---------------------------------------------------------------------------
// n9: offline server -- SET/GET/ECHO with exact request bytes
// ---------------------------------------------------------------------------

fn n9() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: SET/GET/ECHO (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: SET/GET/ECHO (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: SET/GET/ECHO (accept failed)");
  }
  let afd: Int = ar.value;
  let snd = srv_send(afd, "+OK\r\n$5\r\nhello\r\n$2\r\nhi\r\n");
  var ok = true;
  if !snd.is_ok { ok = false; }

  let sr = set(&mut conn, "foo", "bar");
  if !sr.is_ok { ok = false; } else { if !sr.value { ok = false; } }
  let gr = get(&mut conn, "foo");
  if !opt_is(gr, "hello") { ok = false; }
  let er = echo(&mut conn, "yo");
  if !er.is_ok { ok = false; } else { if !streq(er.value, "hi") { ok = false; } }

  let expect = "*3\r\n$3\r\nSET\r\n$3\r\nfoo\r\n$3\r\nbar\r\n" +
    "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n" +
    "*2\r\n$4\r\nECHO\r\n$2\r\nyo\r\n";
  let rr = srv_recv_for(afd, expect.len(), 2000);
  if !rr.is_ok { ok = false; } else { if !streq(rr.value, expect) { ok = false; } }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: SET/GET/ECHO roundtrip -- typed results and exact request bytes");
}

// ---------------------------------------------------------------------------
// n10: offline server -- null bulk is Missing (not an error)
// ---------------------------------------------------------------------------

fn n10() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: null bulk (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: null bulk (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: null bulk (accept failed)");
  }
  let afd: Int = ar.value;
  let snd = srv_send(afd, "$-1\r\n");
  var ok = true;
  if !snd.is_ok { ok = false; }
  let gr = get(&mut conn, "missing");
  if !opt_missing(gr) { ok = false; }
  let expect = "*2\r\n$3\r\nGET\r\n$7\r\nmissing\r\n";
  let rr = srv_recv_for(afd, expect.len(), 2000);
  if !rr.is_ok { ok = false; } else { if !streq(rr.value, expect) { ok = false; } }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: null bulk reply maps to RedisText::Missing");
}

// ---------------------------------------------------------------------------
// n11: offline server -- integer verbs (INCR/TTL), integer arrays (MGET)
// ---------------------------------------------------------------------------

fn n11() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: integer/array verbs (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: integer/array verbs (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: integer/array verbs (accept failed)");
  }
  let afd: Int = ar.value;
  let snd = srv_send(afd, ":7\r\n:-1\r\n*3\r\n$1\r\na\r\n$-1\r\n$1\r\nb\r\n");
  var ok = true;
  if !snd.is_ok { ok = false; }

  let ir = incr(&mut conn, "cnt");
  if !ir.is_ok { ok = false; } else { if ir.value != 7 { ok = false; } }
  let tr = ttl(&mut conn, "cnt");
  if !tr.is_ok { ok = false; } else { if tr.value != -1 { ok = false; } }

  var keys: Vec[Str] = Vec[Str].new();
  keys.push("k1");
  keys.push("k2");
  keys.push("k3");
  let mr = mget(&mut conn, &keys);
  if !mr.is_ok { ok = false; } else {
    let items: Vec[RedisText] = mr.value;
    if items.len() != 3 { ok = false; } else {
      let t0: RedisText = items[0];
      match t0 {
        Missing => { ok = false; },
        Text(s0) => { if !streq(s0, "a") { ok = false; } },
      };
      let t1: RedisText = items[1];
      match t1 {
        Missing => {},
        Text(_) => { ok = false; },
      };
      let t2: RedisText = items[2];
      match t2 {
        Missing => { ok = false; },
        Text(s2) => { if !streq(s2, "b") { ok = false; } },
      };
    }
  }

  let expect = "*2\r\n$4\r\nINCR\r\n$3\r\ncnt\r\n" +
    "*2\r\n$3\r\nTTL\r\n$3\r\ncnt\r\n" +
    "*4\r\n$4\r\nMGET\r\n$2\r\nk1\r\n$2\r\nk2\r\n$2\r\nk3\r\n";
  let rr = srv_recv_for(afd, expect.len(), 2000);
  if !rr.is_ok { ok = false; } else { if !streq(rr.value, expect) { ok = false; } }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: INCR/TTL integers and MGET array with null element");
}

// ---------------------------------------------------------------------------
// n12: offline server -- server error reply (raw Error value and checked Err)
// ---------------------------------------------------------------------------

fn n12() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: server error reply (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: server error reply (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: server error reply (accept failed)");
  }
  let afd: Int = ar.value;
  let msg = "-WRONGTYPE Operation against a key holding the wrong kind of value\r\n";
  let snd = srv_send(afd, msg + msg + msg);
  var ok = true;
  if !snd.is_ok { ok = false; }

  var get_args: Vec[Str] = Vec[Str].new();
  get_args.push("GET");
  get_args.push("foo");
  let raw = command(&mut conn, &get_args);
  if !kind_of_res(raw, REDIS_VALUE_ERROR) { ok = false; }
  if raw.is_ok {
    let rv: RedisValue = raw.value;
    if !streq(value_error_message(&rv), "WRONGTYPE Operation against a key holding the wrong kind of value") { ok = false; }
  } else { ok = false; }

  get_args = Vec[Str].new();
  get_args.push("GET");
  get_args.push("foo");
  let checked = command_checked(&mut conn, &get_args);
  if checked.is_ok {
    ok = false;
  } else {
    let e: RedisError = checked.error;
    if e.kind != REDIS_ERR_SERVER { ok = false; }
    if !streq(e.message, "WRONGTYPE Operation against a key holding the wrong kind of value") { ok = false; }
  }

  // The verb wrapper routes the server error through the same path.
  let gr = get(&mut conn, "foo");
  if gr.is_ok { ok = false; } else {
    let ge: RedisError = gr.error;
    if ge.kind != REDIS_ERR_SERVER { ok = false; }
    if !streq(ge.message, "WRONGTYPE Operation against a key holding the wrong kind of value") { ok = false; }
  }

  let expect = "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n" +
    "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n" +
    "*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n";
  let rr = srv_recv_for(afd, expect.len(), 2000);
  if !rr.is_ok { ok = false; } else { if !streq(rr.value, expect) { ok = false; } }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: server error reply is a raw Error value and a checked REDIS_ERR_SERVER");
}

// ---------------------------------------------------------------------------
// n13: offline server -- pipeline of 4 commands reads 4 ordered replies
// ---------------------------------------------------------------------------

fn n13() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: pipeline (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: pipeline (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: pipeline (accept failed)");
  }
  let afd: Int = ar.value;
  let snd = srv_send(afd, "+PONG\r\n:3\r\n$2\r\nhi\r\n-ERR nope\r\n");
  var ok = true;
  if !snd.is_ok { ok = false; }

  var cmds: Vec[Vec[Str]] = Vec[Vec[Str]].new();
  var c1: Vec[Str] = Vec[Str].new();
  c1.push("PING");
  cmds.push(c1);
  var c2: Vec[Str] = Vec[Str].new();
  c2.push("INCR");
  c2.push("c");
  cmds.push(c2);
  var c3: Vec[Str] = Vec[Str].new();
  c3.push("GET");
  c3.push("k");
  cmds.push(c3);
  var c4: Vec[Str] = Vec[Str].new();
  c4.push("BADCMD");
  cmds.push(c4);

  let pr = pipeline(&mut conn, &cmds);
  if !pr.is_ok { ok = false; } else {
    let vals: Vec[RedisValue] = pr.value;
    if vals.len() != 4 { ok = false; } else {
      let v0: RedisValue = vals[0];
      if value_kind(&v0) != REDIS_VALUE_SIMPLE { ok = false; }
      let v1: RedisValue = vals[1];
      if value_kind(&v1) != REDIS_VALUE_INTEGER { ok = false; }
      let v2: RedisValue = vals[2];
      if value_kind(&v2) != REDIS_VALUE_BULK { ok = false; }
      let v3: RedisValue = vals[3];
      if value_kind(&v3) != REDIS_VALUE_ERROR { ok = false; }
      if !streq(value_error_message(&v3), "ERR nope") { ok = false; }
    }
  }

  let expect = "*1\r\n$4\r\nPING\r\n" +
    "*2\r\n$4\r\nINCR\r\n$1\r\nc\r\n" +
    "*2\r\n$3\r\nGET\r\n$1\r\nk\r\n" +
    "*1\r\n$6\r\nBADCMD\r\n";
  let rr = srv_recv_for(afd, expect.len(), 2000);
  if !rr.is_ok { ok = false; } else { if !streq(rr.value, expect) { ok = false; } }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: pipeline sends N commands and reads N ordered replies");
}

// ---------------------------------------------------------------------------
// n14: offline server -- pub/sub subscribe, read_push and push timeout
// ---------------------------------------------------------------------------

fn n14() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: pub/sub (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: pub/sub (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: pub/sub (accept failed)");
  }
  let afd: Int = ar.value;
  let snd = srv_send(afd,
    "*3\r\n$9\r\nsubscribe\r\n$4\r\nchan\r\n:1\r\n" +
    "*3\r\n$7\r\nmessage\r\n$4\r\nchan\r\n$5\r\nhello\r\n");
  var ok = true;
  if !snd.is_ok { ok = false; }

  let sr = subscribe(&mut conn, "chan");
  if !sr.is_ok { ok = false; } else { if sr.value != 1 { ok = false; } }

  let push = read_push(&mut conn, 500);
  if !kind_of_res(push, REDIS_VALUE_ARRAY) { ok = false; }
  if push.is_ok {
    let pv: RedisValue = push.value;
    if value_array_len(&pv) != 3 { ok = false; }
    let kind0 = value_at(&pv, 0);
    if !kind0.is_ok { ok = false; } else {
      let k0: RedisValue = kind0.value;
      let t0 = value_text(&k0);
      if !t0.is_ok { ok = false; } else { if !streq(t0.value, "message") { ok = false; } }
    }
    let payload = value_at(&pv, 2);
    if !payload.is_ok { ok = false; } else {
      let p0: RedisValue = payload.value;
      let t2 = value_text(&p0);
      if !t2.is_ok { ok = false; } else { if !streq(t2.value, "hello") { ok = false; } }
    }
  } else { ok = false; }

  // Nothing else is scripted: an explicit push deadline must expire.
  let timeout = read_push(&mut conn, 250);
  if !err_kind_of(timeout, REDIS_ERR_TIMEOUT) { ok = false; }

  let expect = "*2\r\n$9\r\nSUBSCRIBE\r\n$4\r\nchan\r\n";
  let rr = srv_recv_for(afd, expect.len(), 2000);
  if !rr.is_ok { ok = false; } else { if !streq(rr.value, expect) { ok = false; } }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: subscribe confirmation, read_push message and push deadline timeout");
}

// ---------------------------------------------------------------------------
// n15: offline server -- stalled server produces a typed TIMEOUT
// ---------------------------------------------------------------------------

fn n15() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: read timeout (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 0.25);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: read timeout (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: read timeout (accept failed)");
  }
  let afd: Int = ar.value;
  // The server stalls: it accepts but never replies.
  var ok = true;
  if read_timeout(&conn) != 250 { ok = false; }
  let pr = ping(&mut conn);
  if !err_kind_of_str(pr, REDIS_ERR_TIMEOUT) { ok = false; }
  if !pr.is_ok {
    let e: RedisError = pr.error;
    if e.code != 0 { ok = false; }
  }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: stalled server read fails with kind REDIS_ERR_TIMEOUT");
}

// ---------------------------------------------------------------------------
// n16: offline server -- truncated reply (peer closes mid-reply)
// ---------------------------------------------------------------------------

fn n16() -> TestResult {
  let s = srv_start();
  if !s.is_ok {
    return assert(false, "srv: truncated reply (no free loopback port)");
  }
  let srv: SrvHandle = s.value;
  let cr = connect_timeout("127.0.0.1", srv.port, 5.0);
  if !cr.is_ok {
    srv_close(srv.fd);
    return assert(false, "srv: truncated reply (client connect failed)");
  }
  var conn: RedisConn = cr.value;
  let ar = srv_accept(srv.fd);
  if !ar.is_ok {
    disconnect(&mut conn);
    srv_close(srv.fd);
    return assert(false, "srv: truncated reply (accept failed)");
  }
  let afd: Int = ar.value;
  let snd = srv_send(afd, "$5\r\nab");
  var ok = true;
  if !snd.is_ok { ok = false; }
  // Send FIN without closing so the client sees a clean EOF mid-reply (a
  // close() with the request still unread would trigger an RST instead).
  let sh = socket_shutdown(afd, 1);
  if !sh.is_ok { ok = false; }
  let pr = ping(&mut conn);
  if !err_str_of(pr, REDIS_ERR_PROTOCOL, RESP_ERR_TRUNCATED) { ok = false; }
  // Drain the request now that the client is done, then close cleanly.
  let dr = srv_recv_for(afd, 14, 2000);
  if !dr.is_ok { ok = false; }
  disconnect(&mut conn);
  srv_close(afd);
  srv_close(srv.fd);
  return assert(ok, "srv: peer closing mid-reply is a typed truncation error");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r8 = n8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = n9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = n10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = n11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = n12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = n13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = n14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = n15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = n16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  return failed;
}
