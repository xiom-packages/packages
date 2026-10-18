// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Probe: xvectord socket adapter (Q-serve). One process drives the full
// loop over REAL sockets: an ephemeral listener, a client that connects to
// it, and the exact per-connection path the serve loop uses
// (`httpd_once` -> `http_service_handle`). Asserts status lines + bodies
// for health/collections/points/stats/search, 404/409 honesty, the
// read-request framing (Content-Length body), and the quit header.
// Exit = failed checks.

use xiom.io;
use xiom.convert;
use xiom.string.slice;
use xiom.net;
use xiom.net.socket;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.httpd;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn check(passed: Bool, name: Str, fails: Int) -> Int {
  if passed {
    io.println("  [PASS] " + name);
  } else {
    io.println("  [FAIL] " + name);
  }
  io.flush_stdout();
  if passed {
    return fails;
  }
  return fails + 1;
}

// Case-sensitive substring over bytes.
fn has(b: &Vec[UInt8], s: Str) -> Bool {
  let t = slice.str_bytes(s);
  if t.len() == 0 || b.len() < t.len() { return false; }
  var i: Int = 0;
  while i + t.len() <= b.len() {
    var j: Int = 0;
    var hit: Bool = true;
    while j < t.len() {
      if b[i + j] != t[j] { hit = false; }
      j = j + 1;
    }
    if hit { return true; }
    i = i + 1;
  }
  return false;
}

fn send_str(fd: Int, s: Str) -> Bool {
  let b = slice.str_bytes(s);
  var ts = TcpStream{ fd: fd };
  let r = ts.write_all(&b);
  return r.is_ok;
}

// Read until EOF (the server closes after responding) or a socket error
// (the client timeout keeps failures from hanging).
fn recv_all(fd: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var done: Bool = false;
  var rounds: Int = 0;
  while !done && rounds < 64 {
    let rr = socket.socket_recv(fd, 65536);
    if rr.is_err {
      done = true;
    } else {
      let chunk = rr.value;
      if chunk.len() == 0 {
        done = true;
      } else {
        var i: Int = 0;
        while i < chunk.len() {
          out.push(chunk[i]);
          i = i + 1;
        }
      }
    }
    rounds = rounds + 1;
  }
  return out;
}

// One client<->server round trip: connect, accept, send, serve, collect.
// Returns the httpd_once code; the response bytes land in `out`.
fn roundtrip(lfd: Int, port: Int, eng: &mut VectorEngine, req: Str, out: &mut Vec[UInt8]) -> Int {
  let cs = socket.socket_tcp();
  if cs.is_err { return -2; }
  let cfd = cs.value;
  let _t = socket.socket_set_timeout(cfd, 3000);
  let cr = socket.socket_connect(cfd, "127.0.0.1", port);
  if cr.is_err {
    socket.socket_close(cfd);
    return -2;
  }
  let ar = socket.socket_accept(lfd);
  if ar.is_err {
    socket.socket_close(cfd);
    return -2;
  }
  let sfd = ar.value;
  let _w = send_str(cfd, req);
  let rc = httpd_once(eng, sfd);   // reads sfd, responds, closes sfd
  out = recv_all(cfd);
  socket.socket_close(cfd);
  return rc;
}

fn req_get(path: Str) -> Str {
  return "GET " + path + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";
}

fn req_with_body(method: Str, path: Str, body: Str) -> Str {
  return method + " " + path + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: "
    + int_to_str(body.len()) + "\r\n\r\n" + body;
}

fn main() -> Int {
  var fails: Int = 0;
  var eng = engine_new();

  let ls = socket.socket_tcp();
  if ls.is_err {
    io.println("  [FAIL] socket create");
    return 1;
  }
  let lfd = ls.value;
  let _ra = socket.socket_reuse_addr(lfd, true);
  // The stdlib bind rejects port 0 ("port out of range"), so walk a
  // deterministic high band until one binds (previous runs may linger).
  var port: Int = -1;
  var tryp: Int = 18700;
  while port < 0 && tryp < 18800 {
    let br = socket.socket_bind(lfd, "127.0.0.1", tryp);
    match br {
      Ok(_) => { port = tryp; }
      Err(_) => {}
    }
    tryp = tryp + 1;
  }
  let lr = socket.socket_listen(lfd, 8);
  match lr {
    Ok(_) => {}
    Err(e) => { io.println("  [FAIL] listen: " + e); }
  }
  fails = check(port > 0, "listener bound (deterministic band 18700+)", fails);
  if port <= 0 { return fails; }

  var out = Vec[UInt8].new();

  // health
  let rc1 = roundtrip(lfd, port, &mut eng, req_get("/health"), &mut out);
  fails = check(rc1 == 0 && has(&out, "200 OK") && has(&out, "\"status\":\"ok\""),
    "socket: GET /health -> 200 ok over real sockets", fails);

  // collections create + duplicate
  let b1 = "{\"name\":\"docs\",\"dim\":4,\"metric\":\"cosine\"}";
  let _rc2 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/collections", b1), &mut out);
  fails = check(has(&out, "201 Created") && has(&out, "\"name\":\"docs\""),
    "socket: POST /collections -> 201 (Content-Length body honored)", fails);
  let _rc3 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/collections", b1), &mut out);
  fails = check(has(&out, "409"), "socket: duplicate collection -> 409", fails);

  // upsert two points (known geometry: id 1 near the query)
  let b2 = "{\"ids\":[1,2],\"vectors\":[[1,0,0,0],[0,1,0,0]]}";
  let _rc4 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/collections/docs/points", b2), &mut out);
  fails = check(has(&out, "200 OK"), "socket: upsert points -> 200", fails);

  // stats
  let _rc5 = roundtrip(lfd, port, &mut eng, req_get("/stats?collection=docs"), &mut out);
  fails = check(has(&out, "200 OK") && has(&out, "\"points\":2"),
    "socket: /stats reflects the collection (2 points)", fails);

  // search: nearest to [1,0,0,0] must be id 1
  let b3 = "{\"collection\":\"docs\",\"k\":1,\"vector\":[1,0,0,0]}";
  let _rc6 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/search", b3), &mut out);
  fails = check(has(&out, "200 OK") && has(&out, "\"id\":1"),
    "socket: POST /search -> nearest id 1", fails);

  // version endpoint (public)
  let _rcv = roundtrip(lfd, port, &mut eng, req_get("/version"), &mut out);
  fails = check(has(&out, "200 OK") && has(&out, "\"version\":\"1.0.0-rc.1\""),
    "socket: GET /version -> 200 with the lane version", fails);

  // per-request ef_search override: valid beam -> same nearest; out of
  // range -> 400
  let b4 = "{\"collection\":\"docs\",\"k\":1,\"vector\":[1,0,0,0],\"ef_search\":4}";
  let _rc10 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/search", b4), &mut out);
  fails = check(has(&out, "200 OK") && has(&out, "\"id\":1"),
    "socket: POST /search with ef_search 4 -> nearest id 1", fails);
  let b5 = "{\"collection\":\"docs\",\"k\":1,\"vector\":[1,0,0,0],\"ef_search\":99999}";
  let _rc11 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/search", b5), &mut out);
  fails = check(has(&out, "400"), "socket: ef_search out of range -> 400", fails);

  // index configuration at create: an hnsw collection end to end
  let b6 = "{\"name\":\"ann\",\"dim\":4,\"metric\":\"euclidean\",\"index\":\"hnsw\",\"m\":8,\"ef_construction\":32,\"ef_search\":16}";
  let _rc12 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/collections", b6), &mut out);
  fails = check(has(&out, "201 Created") && has(&out, "\"index\":\"hnsw\""),
    "socket: create with index hnsw -> 201", fails);
  let b7 = "{\"ids\":[7,8],\"vectors\":[[0,0,0,0],[1,1,1,1]]}";
  let _rc13 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/collections/ann/points", b7), &mut out);
  let b8 = "{\"collection\":\"ann\",\"k\":1,\"vector\":[1,1,1,1],\"ef_search\":8}";
  let _rc14 = roundtrip(lfd, port, &mut eng, req_with_body("POST", "/search", b8), &mut out);
  fails = check(has(&out, "200 OK") && has(&out, "\"id\":8"),
    "socket: hnsw collection search -> nearest id 8", fails);

  // 404 honesty
  let _rc7 = roundtrip(lfd, port, &mut eng, req_get("/nope"), &mut out);
  fails = check(has(&out, "404"), "socket: unknown route -> 404", fails);

  // quit header: the serve loop stops on rc == 1
  let quit_req = "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nX-Xvector-Quit: 1\r\n\r\n";
  let rc8 = roundtrip(lfd, port, &mut eng, quit_req, &mut out);
  fails = check(rc8 == 1 && has(&out, "200 OK"), "socket: quit header -> rc 1 + response served", fails);

  // empty connection (connect, close, then accept) -> rc -1, no crash
  let cs2 = socket.socket_tcp();
  if !cs2.is_err {
    let cfd2 = cs2.value;
    let _t2 = socket.socket_set_timeout(cfd2, 3000);
    let cr2 = socket.socket_connect(cfd2, "127.0.0.1", port);
    if !cr2.is_err {
      socket.socket_close(cfd2);   // peer goes away before sending anything
      let ar2 = socket.socket_accept(lfd);
      if !ar2.is_err {
        let rc9 = httpd_once(&mut eng, ar2.value);
        fails = check(rc9 == -1, "socket: empty connection -> rc -1 (close, no crash)", fails);
      }
    }
  }

  socket.socket_close(lfd);
  io.println("");
  io.println("probe_http_server: exit=" + int_to_str(fails));
  return fails;
}
