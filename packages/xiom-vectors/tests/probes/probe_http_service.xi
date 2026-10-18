// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: HTTP service skeleton (M-S1). Feeds raw HTTP/1.1 request bytes
// through `http_service_handle` (transport-agnostic pipeline) and verifies
// parsing (framing, Content-Length strictness), routing (/health,
// /collections, points, /search, /stats), the JSON wire shapes, honest
// status codes (200/201/400/404/405/409), multi-collection routing,
// pagination/range/batch search dispatch, and response framing
// (Content-Type/Content-Length). Exit = failed checks.

module probe_http_service

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

fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}

// ---- request builders ----

fn mk_req_cl(method: Str, path: Str, body: Str, cl: Int) -> Vec[UInt8] {
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nContent-Length: "
    + convert.int_to_string(cl) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn mk_req(method: Str, path: Str, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  return mk_req_cl(method, path, body, bb.len());
}

// ---- response extraction ----

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

fn resp_head_contains(resp: &Vec[UInt8], s: Str) -> Bool {
  var t = find_term(resp);
  if t < 0 { return false; }
  var needle = slice.str_bytes(s);
  if needle.len() == 0 { return false; }
  var i: Int = 0;
  while i + needle.len() <= t + 4 {
    var j: Int = 0;
    var ok: Bool = true;
    while j < needle.len() {
      if resp[i + j] != needle[j] { ok = false; j = needle.len(); } else { j = j + 1; }
    }
    if ok { return true; }
    i = i + 1;
  }
  return false;
}

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
}

fn body_json(resp: &Vec[UInt8]) -> JsonValue {
  match json_parse(resp_body(resp)) {
    Ok(v) => { return v; }
    Err(_) => {}
  }
  return json_null();
}

fn jnum(resp: &Vec[UInt8], key: Str) -> Float64 {
  var v = body_json(resp);
  match json_get(v, key) {
    Some(f) => {
      match f {
        Number(n) => { return n; }
        _ => {}
      }
    }
    None => {}
  }
  return -999999.0;
}

fn jstr(resp: &Vec[UInt8], key: Str) -> Str {
  var v = body_json(resp);
  match json_get(v, key) {
    Some(f) => {
      match f {
        String(s) => { return s; }
        _ => {}
      }
    }
    None => {}
  }
  return "";
}

fn jonly(resp: &Vec[UInt8], key: Str, want: Str) -> Bool {
  return jstr(resp, key) == want;
}

fn jhas(resp: &Vec[UInt8], key: Str) -> Bool {
  var v = body_json(resp);
  match json_get(v, key) {
    Some(_) => { return true; }
    None => { return false; }
  }
  return false;
}

fn jarr_len(resp: &Vec[UInt8], key: Str) -> Int {
  var v = body_json(resp);
  match json_get(v, key) {
    Some(f) => {
      match f {
        Array(items) => { return items.len(); }
        _ => {}
      }
    }
    None => {}
  }
  return -1;
}

fn jarr_has_str(resp: &Vec[UInt8], key: Str, want: Str) -> Bool {
  var v = body_json(resp);
  match json_get(v, key) {
    Some(f) => {
      match f {
        Array(items) => {
          var i: Int = 0;
          while i < items.len() {
            match items[i] {
              String(s) => { if s == want { return true; } }
              _ => {}
            }
            i = i + 1;
          }
        }
        _ => {}
      }
    }
    None => {}
  }
  return false;
}

// hits array element access: element i, field key.
fn jhits_id(resp: &Vec[UInt8], idx: Int) -> Int {
  var v = body_json(resp);
  match json_get(v, "hits") {
    Some(f) => {
      match f {
        Array(items) => {
          if idx < items.len() {
            match json_get(items[idx], "id") {
              Some(nv) => {
                match nv {
                  Number(n) => { return n as Int; }
                  _ => {}
                }
              }
              None => {}
            }
          }
        }
        _ => {}
      }
    }
    None => {}
  }
  return -1;
}

fn jresults_len(resp: &Vec[UInt8]) -> Int {
  var v = body_json(resp);
  match json_get(v, "results") {
    Some(f) => {
      match f {
        Array(items) => { return items.len(); }
        _ => {}
      }
    }
    None => {}
  }
  return -1;
}

fn jresults_set_len(resp: &Vec[UInt8], idx: Int) -> Int {
  var v = body_json(resp);
  match json_get(v, "results") {
    Some(f) => {
      match f {
        Array(items) => {
          if idx < items.len() {
            match items[idx] {
              Array(set) => { return set.len(); }
              _ => {}
            }
          }
        }
        _ => {}
      }
    }
    None => {}
  }
  return -1;
}

// The declared Content-Length equals the actual body byte count.
fn cl_matches(resp: &Vec[UInt8]) -> Bool {
  var t = find_term(resp);
  if t < 0 { return false; }
  var actual = resp.len() - (t + 4);
  // find header value: search "Content-Length: " then digits
  var needle = slice.str_bytes("Content-Length: ");
  var i: Int = 0;
  var val: Int = -1;
  while i + needle.len() <= t {
    var j: Int = 0;
    var ok: Bool = true;
    while j < needle.len() {
      if resp[i + j] != needle[j] { ok = false; j = needle.len(); } else { j = j + 1; }
    }
    if ok {
      var p: Int = i + needle.len();
      var v: Int = 0;
      var digits: Int = 0;
      while p < t {
        var d = (resp[p] as Int) - 48;
        if d < 0 || d > 9 { p = t; } else {
          v = v * 10 + d;
          digits = digits + 1;
          p = p + 1;
        }
      }
      if digits > 0 { val = v; }
      i = t;
    } else {
      i = i + 1;
    }
  }
  return val == actual;
}

fn main() -> Int {
  io.println("=== xvector probe: HTTP service (M-S1) ===");
  var fails: Int = 0;
  var eng = engine_new();

  // ---- health + framing ----
  var h = http_service_handle(&mut eng, &mk_req("GET", "/health", ""));
  fails = check(status_of(&h) == 200 && jonly(&h, "status", "ok") && jonly(&h, "service", "xvector"),
    "health: 200 with status/service JSON", fails);
  fails = check(resp_head_contains(&h, "Content-Type: application/json")
    && resp_head_contains(&h, "Connection: close") && cl_matches(&h),
    "health: response framing (content-type, close, content-length exact)", fails);

  // ---- parse / routing refusals ----
  var garbage = slice.str_bytes("GARBAGE\r\n\r\n");
  fails = check(status_of(&http_service_handle(&mut eng, &garbage)) == 400,
    "parse: invalid method -> 400", fails);
  var truncated = slice.str_bytes("GET /health HTTP/1.1\r\nHost: t\r\n");
  var tr = http_service_handle(&mut eng, &truncated);
  fails = check(status_of(&tr) == 400 && jonly(&tr, "error", "incomplete request"),
    "parse: head without terminator -> 400 incomplete", fails);
  var shortbody = mk_req_cl("POST", "/search", "{}", 10);
  var sb = http_service_handle(&mut eng, &shortbody);
  fails = check(status_of(&sb) == 400 && jonly(&sb, "error", "incomplete request"),
    "parse: body shorter than Content-Length -> 400 incomplete", fails);
  var longextra = mk_req_cl("POST", "/search", "{\"x\":1}", 3);
  fails = check(status_of(&http_service_handle(&mut eng, &longextra)) == 400,
    "parse: trailing bytes after body -> 400", fails);

  var r404 = http_service_handle(&mut eng, &mk_req("GET", "/nope", ""));
  fails = check(status_of(&r404) == 404 && jonly(&r404, "error", "unknown route"),
    "routing: unknown route -> 404", fails);
  var r405 = http_service_handle(&mut eng, &mk_req("DELETE", "/health", ""));
  fails = check(status_of(&r405) == 405, "routing: wrong method -> 405", fails);

  // ---- collections ----
  var c1 = http_service_handle(&mut eng, &mk_req("POST", "/collections", "{\"name\":\"docs\",\"dim\":4,\"metric\":\"cosine\"}"));
  fails = check(status_of(&c1) == 201 && jonly(&c1, "name", "docs"), "collections: create -> 201", fails);
  var l1 = http_service_handle(&mut eng, &mk_req("GET", "/collections", ""));
  fails = check(status_of(&l1) == 200 && jarr_len(&l1, "collections") == 1 && jarr_has_str(&l1, "collections", "docs"),
    "collections: list contains docs", fails);
  var cdup = http_service_handle(&mut eng, &mk_req("POST", "/collections", "{\"name\":\"docs\",\"dim\":4,\"metric\":\"cosine\"}"));
  fails = check(status_of(&cdup) == 409, "collections: duplicate -> 409", fails);
  var cdim = http_service_handle(&mut eng, &mk_req("POST", "/collections", "{\"name\":\"x\",\"dim\":0,\"metric\":\"cosine\"}"));
  fails = check(status_of(&cdim) == 400, "collections: dim 0 -> 400", fails);
  var cname = http_service_handle(&mut eng, &mk_req("POST", "/collections", "{\"name\":\"bad name\",\"dim\":4,\"metric\":\"cosine\"}"));
  fails = check(status_of(&cname) == 400, "collections: invalid name -> 400", fails);
  var cmet = http_service_handle(&mut eng, &mk_req("POST", "/collections", "{\"name\":\"x\",\"dim\":4,\"metric\":\"manhattan\"}"));
  fails = check(status_of(&cmet) == 400, "collections: unknown metric -> 400", fails);

  // ---- points: upsert / get / delete ----
  var up = http_service_handle(&mut eng,
    &mk_req("POST", "/collections/docs/points",
      "{\"ids\":[1,2,3],\"vectors\":[[1,0,0,0],[0.9,0.1,0,0],[0,1,0,0]]}"));
  fails = check(status_of(&up) == 200 && jnum(&up, "count") == 3.0, "points: batch upsert -> count 3", fails);
  var gp = http_service_handle(&mut eng, &mk_req("GET", "/collections/docs/points?id=2", ""));
  fails = check(status_of(&gp) == 200 && jnum(&gp, "id") == 2.0 && jarr_len(&gp, "vector") == 4,
    "points: get id=2 -> vector of dim 4", fails);
  var gpm = http_service_handle(&mut eng, &mk_req("GET", "/collections/docs/points?id=99", ""));
  fails = check(status_of(&gpm) == 404, "points: missing id -> 404", fails);
  var gpno = http_service_handle(&mut eng, &mk_req("GET", "/collections/docs/points", ""));
  fails = check(status_of(&gpno) == 400, "points: missing id param -> 400", fails);
  var upunk = http_service_handle(&mut eng, &mk_req("POST", "/collections/nope/points", "{\"ids\":[1],\"vectors\":[[1,0,0,0]]}"));
  fails = check(status_of(&upunk) == 404, "points: unknown collection -> 404", fails);
  var upbad = http_service_handle(&mut eng, &mk_req("POST", "/collections/docs/points", "{\"ids\":[1,2],\"vectors\":[[1,0,0,0]]}"));
  fails = check(status_of(&upbad) == 400, "points: length mismatch -> 400", fails);

  // ---- search: knn / page / cursor / range / batch ----
  var s1 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":2}"));
  fails = check(status_of(&s1) == 200 && jarr_len(&s1, "hits") == 2 && jhits_id(&s1, 0) == 1,
    "search: knn top-2 -> id 1 first", fails);
  var s2 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":2,\"offset\":1}"));
  fails = check(status_of(&s2) == 200 && jhits_id(&s2, 0) == 2 && jhits_id(&s2, 1) == 3,
    "search: offset 1 k=2 -> ranks 1..2", fails);
  var s3 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":2,\"after_id\":1}"));
  fails = check(status_of(&s3) == 200 && jhits_id(&s3, 0) == 2 && jhits_id(&s3, 1) == 3,
    "search: after_id 1 k=2 -> ranks after 1", fails);
  var s4 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":5,\"mode\":\"range\",\"radius\":0.5}"));
  fails = check(status_of(&s4) == 200 && jarr_len(&s4, "hits") == 2 && jhits_id(&s4, 0) == 1 && jhits_id(&s4, 1) == 2,
    "search: range r=0.5 -> {1,2}", fails);
  var su = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"nope\",\"vector\":[1,0,0,0],\"top_k\":1}"));
  fails = check(status_of(&su) == 404, "search: unknown collection -> 404", fails);
  var sd = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0],\"top_k\":1}"));
  fails = check(status_of(&sd) == 400, "search: dim mismatch -> 400", fails);
  var sk = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":0}"));
  fails = check(status_of(&sk) == 400, "search: top_k 0 -> 400", fails);
  var sb2 = http_service_handle(&mut eng,
    &mk_req("POST", "/search",
      "{\"collection\":\"docs\",\"requests\":[{\"vector\":[1,0,0,0],\"top_k\":1},{\"vector\":[1,0,0,0],\"top_k\":2}]}"));
  fails = check(status_of(&sb2) == 200 && jresults_len(&sb2) == 2
    && jresults_set_len(&sb2, 0) == 1 && jresults_set_len(&sb2, 1) == 2,
    "search: batch -> two sets (1,2)", fails);
  var sbe = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"requests\":[]}"));
  fails = check(status_of(&sbe) == 400, "search: empty batch -> 400", fails);

  // ---- stats ----
  var st = http_service_handle(&mut eng, &mk_req("GET", "/stats?collection=docs&x=1", ""));
  fails = check(status_of(&st) == 200 && jnum(&st, "points") == 3.0 && jnum(&st, "dim") == 4.0
    && jonly(&st, "metric", "cosine") && jonly(&st, "index", "flat") && jnum(&st, "lsn") > 0.0,
    "stats: docs -> points 3, dim 4, cosine flat, lsn > 0", fails);
  var stu = http_service_handle(&mut eng, &mk_req("GET", "/stats?collection=nope", ""));
  fails = check(status_of(&stu) == 404, "stats: unknown collection -> 404", fails);

  // ---- delete + multi-collection routing ----
  var dp = http_service_handle(&mut eng, &mk_req("DELETE", "/collections/docs/points?id=2", ""));
  fails = check(status_of(&dp) == 200 && jhas(&dp, "removed"), "points: delete id=2 -> removed", fails);
  var gp2 = http_service_handle(&mut eng, &mk_req("GET", "/collections/docs/points?id=2", ""));
  fails = check(status_of(&gp2) == 404, "points: deleted id -> 404", fails);
  var s5 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":3}"));
  fails = check(status_of(&s5) == 200 && jarr_len(&s5, "hits") == 2 && jhits_id(&s5, 0) == 1,
    "search: after delete -> 2 hits, id 1 first", fails);

  var c2 = http_service_handle(&mut eng, &mk_req("POST", "/collections", "{\"name\":\"two\",\"dim\":3,\"metric\":\"euclidean\"}"));
  fails = check(status_of(&c2) == 201, "collections: create second collection -> 201", fails);
  var s6 = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"two\",\"vector\":[1,0,0],\"top_k\":2}"));
  fails = check(status_of(&s6) == 200 && jarr_len(&s6, "hits") == 0,
    "search: second collection (empty) -> 0 hits", fails);
  var l2 = http_service_handle(&mut eng, &mk_req("GET", "/collections", ""));
  fails = check(jarr_len(&l2, "collections") == 2, "collections: list has both", fails);

  // ---- body parsing edge cases ----
  var bj = http_service_handle(&mut eng, &mk_req("POST", "/search", "not json"));
  fails = check(status_of(&bj) == 400, "body: non-JSON -> 400", fails);
  var bty = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":\"two\"}"));
  fails = check(status_of(&bty) == 400, "body: wrong field type -> 400", fails);
  var bcl = http_service_handle(&mut eng, &mk_req_cl("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":1}", 0));
  fails = check(status_of(&bcl) == 400, "body: missing content-length with body -> 400", fails);

  // ---- status reason phrases (xiom.http adoption, 2026-10-10) ----
  // The reason text is wire contract; http_response(507) must keep the
  // lane's "Insufficient Storage" (xiom.http.status has no 507 entry and
  // its fallback is "Unknown" -- the lane adapter covers both).
  var doc0 = json.json_parse("{}");
  match doc0 {
    Ok(dv) => {
      var r507 = http_response(507, dv);
      fails = check(resp_head_contains(&r507, "HTTP/1.1 507 Insufficient Storage"),
        "status line: 507 -> 'Insufficient Storage' (lane text kept via xiom.http adapter)", fails);
    }
    Err(_) => {
      fails = check(false, "status line: 507 fixture parse", fails);
    }
  }

  io.println("");
  io.println("probe_http_service: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
