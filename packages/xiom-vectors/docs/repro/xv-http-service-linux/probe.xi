// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XVC-C-16 repro: on v0.64.5 linux-x64 (WSL), the HTTP service's /search
// path miscompiles -- search requests return 404 {"error":"not found"} (or
// a bogus "range mode does not support pagination" 400) even though the
// collection exists and every ingredient works when called directly.
//
// Run (from the repo root):
//   . .\scripts\dev-env.ps1
//   .\scripts\build.ps1 docs\repro\xv-http-service-linux\probe.xi -Name repro_service_search
//   .\out\repro_service_search.exe
//   WSL: bash scripts/build.sh docs/repro/xv-http-service-linux/probe.xi repro_service_search
//        ./out/repro_service_search
//
// Expected (v0.64.4 linux / v0.64.5 windows): exit 0 -- 3 wire checks pass
// (knn hits, range hits, empty collection) + the direct-API controls pass.
// Observed (v0.64.5 linux): the three wire checks fail (404/400 bodies),
// while the direct controls (select_collection / search_request_new +
// search_with_request / json extraction) stay GREEN -- the failure is
// context-sensitive to the service module's search handler lowering.

module repro_service_search

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;
use xiom.vectors;
use xiom.serialize.json;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn mk_vec4(a: Float32, b: Float32, c: Float32, d: Float32) -> Vector {
  var v = Vector.new(4);
  v.set(0, a); v.set(1, b); v.set(2, c); v.set(3, d);
  return v;
}

fn mk_req(method: Str, path: Str, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nContent-Length: "
    + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn find_term(b: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i + 3 < b.len() {
    if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

fn resp_body(resp: &Vec[UInt8]) -> Str {
  var t = find_term(resp);
  if t < 0 { return ""; }
  var acc = Vec[UInt8].new();
  var i: Int = t + 4;
  while i < resp.len() {
    acc.push(resp[i]);
    i = i + 1;
  }
  return Str::from_utf8(&acc);
}

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
}

// Minimal "hits" inspection over the raw response text: counts the id
// fields and returns the first id (-1 when absent).
fn first_hit_id(body: Str) -> Int {
  var b = slice.str_bytes(body);
  var needle = slice.str_bytes("\"id\":");
  var i: Int = 0;
  while i + needle.len() + 1 < b.len() {
    var j: Int = 0;
    var ok: Bool = true;
    while j < needle.len() {
      if b[i + j] != needle[j] { ok = false; j = needle.len(); } else { j = j + 1; }
    }
    if ok {
      var k: Int = i + needle.len();
      var end = k;
      while end < b.len() && b[end] != 44 && b[end] != 125 { end = end + 1; }
      // Local digit parse: self-contained so the repro does not depend on
      // the stdlib parse surface (it moved between waves; v0.64.6 rebuild).
      var v: Int = 0;
      var got: Bool = false;
      while k < end {
        var c = b[k];
        if c >= 48 && c <= 57 {
          v = v * 10 + ((c as Int) - 48);
          got = true;
          k = k + 1;
        } else {
          k = end;
        }
      }
      if got { return v; }
      return -1;
    }
    i = i + 1;
  }
  return -1;
}

fn count_hits(body: Str) -> Int {
  var b = slice.str_bytes(body);
  var needle = slice.str_bytes("\"id\":");
  var n: Int = 0;
  var i: Int = 0;
  while i + needle.len() <= b.len() {
    var j: Int = 0;
    var ok: Bool = true;
    while j < needle.len() {
      if b[i + j] != needle[j] { ok = false; j = needle.len(); } else { j = j + 1; }
    }
    if ok { n = n + 1; i = i + needle.len(); } else { i = i + 1; }
  }
  return n;
}

fn main() -> Int {
  io.println("=== xvector probe: HTTP service search path (XVC-C-16 repro) ===");
  var fails: Int = 0;
  var eng = engine_new();

  var c1 = http_service_handle(&mut eng,
    &mk_req("POST", "/collections", "{\"name\":\"docs\",\"dim\":4,\"metric\":\"cosine\"}"));
  fails = check(status_of(&c1) == 201, "collections: create docs -> 201", fails);

  var up = http_service_handle(&mut eng,
    &mk_req("POST", "/collections/docs/points",
      "{\"ids\":[1,2,3],\"vectors\":[[1,0,0,0],[0.9,0.1,0,0],[0,1,0,0]]}"));
  fails = check(status_of(&up) == 200, "points: upsert 1,2,3 -> 200", fails);

  // Wire check 1: knn search through the service.
  var s1 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":2}"));
  var s1b = resp_body(&s1);
  io.println("  s1: status=" + convert.int_to_string(status_of(&s1)) + " body=" + s1b);
  fails = check(status_of(&s1) == 200 && count_hits(s1b) == 2 && first_hit_id(s1b) == 1,
    "wire: knn top-2 -> 200, 2 hits, id 1 first", fails);

  // Wire check 2: range search (top_k is the limit; no pagination fields).
  var s4 = http_service_handle(&mut eng,
    &mk_req("POST", "/search",
      "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":5,\"mode\":\"range\",\"radius\":0.5}"));
  var s4b = resp_body(&s4);
  io.println("  s4: status=" + convert.int_to_string(status_of(&s4)) + " body=" + s4b);
  fails = check(status_of(&s4) == 200 && count_hits(s4b) == 2,
    "wire: range r=0.5 -> 200, 2 hits", fails);

  // Wire check 3: empty collection search.
  var c2 = http_service_handle(&mut eng,
    &mk_req("POST", "/collections", "{\"name\":\"two\",\"dim\":3,\"metric\":\"euclidean\"}"));
  fails = check(status_of(&c2) == 201, "collections: create two -> 201", fails);
  var s6 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"two\",\"vector\":[1,0,0],\"top_k\":2}"));
  var s6b = resp_body(&s6);
  io.println("  s6: status=" + convert.int_to_string(status_of(&s6)) + " body=" + s6b);
  fails = check(status_of(&s6) == 200 && count_hits(s6b) == 0,
    "wire: empty collection -> 200, 0 hits", fails);

  // Control 1: direct collection select (same call the handler makes).
  var sel_ok: Bool = false;
  match select_collection(&mut eng, "docs") {
    Ok(_) => { sel_ok = true; }
    Err(e) => { io.println("  select docs Err " + e); }
  }
  fails = check(sel_ok, "control: select_collection(docs) -> Ok", fails);

  // Control 2: request built + executed directly (same public API).
  var req = search_request_new(mk_vec4(1.0, 0.0, 0.0, 0.0), 2, DistanceMetric.Cosine);
  io.println("  req: top_k=" + convert.int_to_string(req.top_k) + " offset="
    + convert.int_to_string(req.offset) + " after_id=" + convert.int_to_string(req.after_id));
  var direct_n: Int = -1;
  match search_with_request(&eng, &req) {
    Ok(h) => { direct_n = h.items.len(); }
    Err(e) => { io.println("  direct req Err " + e); }
  }
  fails = check(direct_n == 2, "control: search_with_request direct -> 2 hits", fails);

  // Control 3: collection-name extraction from the same body shape.
  var body = "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":2}";
  var coll_ok: Bool = false;
  match json.json_parse(body) {
    Ok(jv) => {
      match json.json_get(jv, "collection") {
        Some(f) => {
          match f {
            String(s) => { coll_ok = s == "docs"; }
            _ => {}
          }
        }
        None => {}
      }
    }
    Err(_) => {}
  }
  fails = check(coll_ok, "control: json collection extraction -> docs", fails);

  io.println("");
  io.println("repro_service_search: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
