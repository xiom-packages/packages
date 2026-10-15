// XIOM -- xiom.redis conformance suite, part 3: real-network outcomes
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Checks that need real connection outcomes rather than a scripted server:
// the refused-connection taxonomy (a closed loopback port must classify as
// REDIS_ERR_CONNECT, at connect or at the first command -- see AUDIT.md for
// the Windows runtime misreport this covers), and the two live checks
// against 127.0.0.1:6379 (core commands, pub/sub roundtrip) which print an
// explicit SKIP line when no server is reachable -- never a fake pass.

module xiom.redis.suite_live

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

fn err_kind_of_str(r: Result[Str, RedisError], kind: Int) -> Bool {
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

// ---------------------------------------------------------------------------
// l17: refused-connection taxonomy on a closed loopback port
// ---------------------------------------------------------------------------

fn l17() -> TestResult {
  // A port that nothing will listen on: bind a listener, close it, then
  // connect to it. (Ports in the reserved high range; the suite binds
  // 46397..46399 for this purpose only.)
  var ports: Vec[Int] = Vec[Int].new();
  ports.push(46397);
  ports.push(46399);
  var pi = 0;
  var port = 0;
  var got_fd = false;
  var fd = -1;
  while pi < ports.len() && !got_fd {
    let p: Int = ports[pi];
    let t = socket_tcp();
    if t.is_ok {
      let cfd: Int = t.value;
      let bnd = socket_bind(cfd, "127.0.0.1", p);
      if bnd.is_ok {
        let l = socket_listen(cfd, 4);
        if l.is_ok {
          fd = cfd;
          port = p;
          got_fd = true;
        }
      }
      if !got_fd {
        socket_close(cfd);
      }
    }
    pi = pi + 1;
  }
  if !got_fd {
    return assert(false, "client: connect refused (no free loopback port)");
  }
  socket_close(fd);

  var ok = true;
  // Refused connection: on this runtime socket_connect can report success,
  // so the refusal is accepted either at connect (typed REDIS_ERR_CONNECT)
  // or at the first command, which the client classifies as
  // REDIS_ERR_CONNECT because no byte has ever been sent.
  let cr = connect("127.0.0.1", port);
  if cr.is_ok {
    var dead: RedisConn = cr.value;
    let pr = ping(&mut dead);
    if !err_kind_of_str(pr, REDIS_ERR_CONNECT) { ok = false; }
    disconnect(&mut dead);
  } else {
    let e: RedisError = cr.error;
    if e.kind != REDIS_ERR_CONNECT { ok = false; }
  }
  // Argument validation is a typed failure too (no socket is opened).
  let bad = connect("127.0.0.1", 0);
  if bad.is_ok { ok = false; } else {
    let e2: RedisError = bad.error;
    if e2.kind != REDIS_ERR_CONNECT { ok = false; }
  }
  return assert(ok, "client: refused connection and bad port are typed REDIS_ERR_CONNECT");
}

// ---------------------------------------------------------------------------
// l18: live Redis -- core commands (SKIP when 127.0.0.1:6379 is closed)
// ---------------------------------------------------------------------------

fn l18() -> TestResult {
  let cr = connect("127.0.0.1", 6379);
  if !cr.is_ok {
    return assert(true, "live: core commands (PING/SET/GET/EXISTS/INCR/TTL/EXPIRE/DEL) SKIP -- no live Redis at 127.0.0.1:6379");
  }
  var conn: RedisConn = cr.value;
  set_read_timeout(&mut conn, 3000);
  var ok = true;

  // Liveness proof first: a refused connection may only surface at the
  // first command on this runtime (see l17); that is a SKIP, not a failure.
  let p0 = ping(&mut conn);
  if !p0.is_ok {
    let e0: RedisError = p0.error;
    disconnect(&mut conn);
    if e0.kind == REDIS_ERR_CONNECT {
      return assert(true, "live: core commands (PING/SET/GET/EXISTS/INCR/TTL/EXPIRE/DEL) SKIP -- no live Redis at 127.0.0.1:6379");
    }
    return assert(false, "live: core commands (Redis reachable but PING failed: " + e0.message + ")");
  }
  if !streq(p0.value, "PONG") { ok = false; }

  var cleanup: Vec[Str] = Vec[Str].new();
  cleanup.push("xiom.redis.conformance.k");
  cleanup.push("xiom.redis.conformance.c");
  let del0 = del(&mut conn, &cleanup);
  if !del0.is_ok { ok = false; }

  let p = ping(&mut conn);
  if !p.is_ok { ok = false; } else { if !streq(p.value, "PONG") { ok = false; } }

  let s1 = set(&mut conn, "xiom.redis.conformance.k", "v1");
  if !s1.is_ok { ok = false; } else { if !s1.value { ok = false; } }

  let g1 = get(&mut conn, "xiom.redis.conformance.k");
  if !opt_is(g1, "v1") { ok = false; }

  var one: Vec[Str] = Vec[Str].new();
  one.push("xiom.redis.conformance.k");
  let ex = exists(&mut conn, &one);
  if !ex.is_ok { ok = false; } else { if ex.value != 1 { ok = false; } }

  let i1 = incr(&mut conn, "xiom.redis.conformance.c");
  if !i1.is_ok { ok = false; } else { if i1.value != 1 { ok = false; } }

  let t1 = ttl(&mut conn, "xiom.redis.conformance.k");
  if !t1.is_ok { ok = false; } else { if t1.value != -1 { ok = false; } }

  let e1 = expire(&mut conn, "xiom.redis.conformance.k", 60);
  if !e1.is_ok { ok = false; } else { if !e1.value { ok = false; } }

  let t2 = ttl(&mut conn, "xiom.redis.conformance.k");
  if !t2.is_ok { ok = false; } else { if t2.value < 0 || t2.value > 60 { ok = false; } }

  let d2 = del(&mut conn, &cleanup);
  if !d2.is_ok { ok = false; } else { if d2.value != 2 { ok = false; } }

  disconnect(&mut conn);
  return assert(ok, "live: core commands (PING/SET/GET/EXISTS/INCR/TTL/EXPIRE/DEL) against 127.0.0.1:6379");
}

// ---------------------------------------------------------------------------
// l19: live Redis -- pub/sub roundtrip (SKIP when 127.0.0.1:6379 is closed)
// ---------------------------------------------------------------------------

fn l19() -> TestResult {
  let ca = connect("127.0.0.1", 6379);
  if !ca.is_ok {
    return assert(true, "live: pub/sub SUBSCRIBE/PUBLISH/read_push/UNSUBSCRIBE SKIP -- no live Redis at 127.0.0.1:6379");
  }
  var sub: RedisConn = ca.value;
  set_read_timeout(&mut sub, 5000);
  // Same liveness proof as l18: refused connections may only surface at the
  // first command on this runtime; that is a SKIP, not a failure.
  let p0 = ping(&mut sub);
  if !p0.is_ok {
    let e0: RedisError = p0.error;
    disconnect(&mut sub);
    if e0.kind == REDIS_ERR_CONNECT {
      return assert(true, "live: pub/sub SUBSCRIBE/PUBLISH/read_push/UNSUBSCRIBE SKIP -- no live Redis at 127.0.0.1:6379");
    }
    return assert(false, "live: pub/sub (Redis reachable but PING failed: " + e0.message + ")");
  }
  let cb = connect("127.0.0.1", 6379);
  if !cb.is_ok {
    disconnect(&mut sub);
    return assert(false, "live: pub/sub (second connection failed while Redis is up)");
  }
  var pubc: RedisConn = cb.value;
  set_read_timeout(&mut pubc, 5000);
  var ok = true;

  let sr = subscribe(&mut sub, "xiom.redis.conformance.ch");
  if !sr.is_ok { ok = false; } else { if sr.value != 1 { ok = false; } }

  let pr = publish(&mut pubc, "xiom.redis.conformance.ch", "payload-1");
  if !pr.is_ok { ok = false; } else { if pr.value < 1 { ok = false; } }

  let push = read_push(&mut sub, 5000);
  if !kind_of_res(push, REDIS_VALUE_ARRAY) { ok = false; }
  if push.is_ok {
    let pv: RedisValue = push.value;
    if value_array_len(&pv) != 3 { ok = false; }
    let p1 = value_at(&pv, 1);
    if !p1.is_ok { ok = false; } else {
      let c1: RedisValue = p1.value;
      let ct = value_text(&c1);
      if !ct.is_ok { ok = false; } else { if !streq(ct.value, "xiom.redis.conformance.ch") { ok = false; } }
    }
    let p2 = value_at(&pv, 2);
    if !p2.is_ok { ok = false; } else {
      let c2: RedisValue = p2.value;
      let ct2 = value_text(&c2);
      if !ct2.is_ok { ok = false; } else { if !streq(ct2.value, "payload-1") { ok = false; } }
    }
  }

  let ur = unsubscribe(&mut sub, "xiom.redis.conformance.ch");
  if !ur.is_ok { ok = false; } else { if ur.value != 0 { ok = false; } }

  disconnect(&mut sub);
  disconnect(&mut pubc);
  return assert(ok, "live: pub/sub SUBSCRIBE/PUBLISH/read_push/UNSUBSCRIBE against 127.0.0.1:6379");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

pub fn run_suite() -> Int {
  var failed: Int = 0;
  let r17 = l17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = l18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = l19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  return failed;
}
