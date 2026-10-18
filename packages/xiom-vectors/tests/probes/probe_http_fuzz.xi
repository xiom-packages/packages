// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: HTTP input fuzzing + resource exhaustion (M-S4). Deterministic,
// seeded fuzz: ~1200 byte-level mutations of a valid request plus ~1300
// random byte streams must ALL yield a well-formed HTTP response (status
// line + terminator + byte-exact Content-Length) with no crash; targeted
// abuse cases (lying Content-Length, header floods, 30 KB header lines,
// unbalanced/deep JSON, NUL bytes, 500-segment paths, 300-request bursts,
// over-limit bodies) must stay bounded and well-formed; the service must
// still serve correctly afterwards. Exit = failed checks.

module probe_http_fuzz

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;
use xiom.vectors;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

// Crash forensics: rewrite the mark file each phase (survives abnormal
// exit; the t-* marks pinpoint the abuse case if a future fuzz run dies).
fn mark(tag: Str) {
  var b = slice.str_bytes(tag);
  var res = io.write_file_bytes("out/fuzz_mark.txt", &b);
  match res {
    Ok(_) => {}
    Err(_) => {}
  }
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn mk_req_cl(method: Str, path: Str, body: Str, cl: Int) -> Vec[UInt8] {
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nContent-Length: "
    + convert.int_to_string(cl) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn mk_req(method: Str, path: Str, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  return mk_req_cl(method, path, body, bb.len());
}

fn find_term(b: &Vec[UInt8]) -> Int {
  var i: Int = 0;
  while i + 3 < b.len() {
    if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
}

// CL header equals the actual body byte count.
fn cl_matches(resp: &Vec[UInt8]) -> Bool {
  var t = find_term(resp);
  if t < 0 { return false; }
  var actual = resp.len() - (t + 4);
  var needle = slice.str_bytes("Content-Length: ");
  var i: Int = 0;
  var val: Int = -1;
  while i + needle.len() <= t {
    var j: Int = 0;
    var ok: Bool = true;
    while j < needle.len() {
      if resp[i + j] != needle[j] {
        ok = false;
        j = needle.len();
      } else {
        j = j + 1;
      }
    }
    if ok {
      var p: Int = i + needle.len();
      var v: Int = 0;
      var digits: Int = 0;
      while p < t {
        var d = (resp[p] as Int) - 48;
        if d < 0 || d > 9 {
          p = t;
        } else {
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

fn well_formed(resp: &Vec<UInt8>) -> Bool {
  if resp.len() < 12 { return false; }
  var st = status_of(resp);
  if st < 100 || st > 599 { return false; }
  if find_term(resp) < 0 { return false; }
  return cl_matches(resp);
}

// Copy `base` into `out` then apply one seeded mutation.
fn mutate_once(base: &Vec[UInt8], seed: Int, out: &mut Vec[UInt8]) -> Int {
  var s = seed;
  var i: Int = 0;
  while i < base.len() {
    out.push(base[i]);
    i = i + 1;
  }
  s = lcg_next(s);
  var kind = s % 5;
  if out.len() > 0 {
    s = lcg_next(s);
    var idx = s % out.len();
    if kind == 0 {
      s = lcg_next(s);
      out[idx] = (s % 256) as UInt8;
    } elif kind == 1 {
      while out.len() > idx {
        out.pop();
      }
    } elif kind == 2 {
      out[idx] = (255 - (out[idx] as Int)) as UInt8;
    } elif kind == 3 {
      out.push(out[idx]);
    } else {
      // duplicate a byte region at the tail
      s = lcg_next(s);
      var take = s % 16;
      var j: Int = 0;
      while j < take && j + idx < out.len() {
        out.push(out[idx + j]);
        j = j + 1;
      }
    }
  }
  return s;
}

fn main() -> Int {
  io.println("=== xvector probe: HTTP fuzz + abuse (M-S4) ===");
  var fails: Int = 0;
  var eng = engine_new();

  // Seed a collection so search mutations reach deep paths.
  var seed_create = http_service_handle(&mut eng,
    &mk_req("POST", "/collections", "{\"name\":\"fz\",\"dim\":2,\"metric\":\"euclidean\"}"));
  var seed_up = http_service_handle(&mut eng,
    &mk_req("POST", "/collections/fz/points", "{\"ids\":[1,2],\"vectors\":[[1,0],[0,1]]}"));
  fails = check(status_of(&seed_create) == 201 && status_of(&seed_up) == 200, "fuzz: seed collection", fails);

  // ---- seeded byte-level mutations of a valid request ----
  var base = mk_req("POST", "/search", "{\"collection\":\"fz\",\"vector\":[1,0],\"top_k\":2}");
  var bad_mut: Int = 0;
  var s: Int = 424242;
  var it: Int = 0;
  mark("seeded-start");
  while it < 1200 {
    var m = Vec[UInt8].new();
    s = mutate_once(&base, s, &mut m);
    if !well_formed(&http_service_handle(&mut eng, &m)) { bad_mut = bad_mut + 1; }
    it = it + 1;
  }
  fails = check(bad_mut == 0, "fuzz: 1200 seeded mutations -> well-formed responses", fails);
  mark("seeded-done");

  // ---- random byte streams ----
  var bad_rnd: Int = 0;
  it = 0;
  mark("random-start");
  while it < 1300 {
    var m2 = Vec[UInt8].new();
    s = lcg_next(s);
    var n = s % 200;
    var j: Int = 0;
    while j < n {
      s = lcg_next(s);
      m2.push((s % 256) as UInt8);
      j = j + 1;
    }
    if !well_formed(&http_service_handle(&mut eng, &m2)) { bad_rnd = bad_rnd + 1; }
    it = it + 1;
  }
  fails = check(bad_rnd == 0, "fuzz: 1300 random streams -> well-formed responses", fails);
  mark("random-done");

  // ---- targeted abuse ----
  var empty = Vec[UInt8].new();
  mark("t-empty");
  fails = check(well_formed(&http_service_handle(&mut eng, &empty))
    && status_of(&http_service_handle(&mut eng, &empty)) == 400,
    "abuse: empty request -> well-formed 400", fails);

  var lying_cl = mk_req_cl("POST", "/search", "{}", 100000);
  mark("t-cl");
  var rcl = http_service_handle(&mut eng, &lying_cl);
  fails = check(well_formed(&rcl) && status_of(&rcl) == 400,
    "abuse: huge declared Content-Length, small body -> 400", fails);

  var flood_s = "GET /health HTTP/1.1\r\n";
  var hi: Int = 0;
  while hi < 2000 {
    flood_s = flood_s + "X-H" + convert.int_to_string(hi) + ": v\r\n";
    hi = hi + 1;
  }
  flood_s = flood_s + "\r\n";
  mark("t-flood");
  var rflood = http_service_handle(&mut eng, &slice.str_bytes(flood_s));
  fails = check(well_formed(&rflood) && status_of(&rflood) == 200,
    "abuse: 2000-header flood -> well-formed 200", fails);

  var longval = "";
  var li: Int = 0;
  while li < 30000 {
    longval = longval + "a";
    li = li + 1;
  }
  mark("t-long");
  var rlong = http_service_handle(&mut eng,
    &slice.str_bytes("GET /health HTTP/1.1\r\nX-Long: " + longval + "\r\nContent-Length: 0\r\n\r\n"));
  fails = check(well_formed(&rlong) && status_of(&rlong) == 200,
    "abuse: 30 KB header value -> well-formed 200", fails);

  var opens = "";
  var oi: Int = 0;
  while oi < 60000 {
    opens = opens + "[";
    oi = oi + 1;
  }
  mark("t-unbalanced");
  var rdeep = http_service_handle(&mut eng, &mk_req("POST", "/search", opens));
  fails = check(well_formed(&rdeep) && status_of(&rdeep) == 400,
    "abuse: 60 KB unbalanced JSON -> well-formed 400", fails);

  var deep = "";
  var di: Int = 0;
  while di < 8000 {
    deep = deep + "[";
    di = di + 1;
  }
  di = 0;
  while di < 8000 {
    deep = deep + "]";
    di = di + 1;
  }
  mark("t-nest");
  var rnest = http_service_handle(&mut eng, &mk_req("POST", "/search", deep));
  var rnest_st = status_of(&rnest);
  fails = check(well_formed(&rnest) && (rnest_st == 200 || rnest_st == 400),
    "abuse: 8000-deep nested JSON -> bounded response", fails);

  var nulreq = Vec[UInt8].new();
  var prefix = slice.str_bytes("GET /he");
  var xi: Int = 0;
  while xi < prefix.len() {
    nulreq.push(prefix[xi]);
    xi = xi + 1;
  }
  nulreq.push(0);
  nulreq.push(0);
  var tail = slice.str_bytes("alth HTTP/1.1\r\nContent-Length: 0\r\n\r\n");
  xi = 0;
  while xi < tail.len() {
    nulreq.push(tail[xi]);
    xi = xi + 1;
  }
  mark("t-nul");
  fails = check(well_formed(&http_service_handle(&mut eng, &nulreq)),
    "abuse: NUL bytes in the request -> bounded response", fails);

  var segs = "/";
  var si: Int = 0;
  while si < 500 {
    segs = segs + "a/";
    si = si + 1;
  }
  mark("t-segs");
  var rsegs = http_service_handle(&mut eng, &mk_req("GET", segs, ""));
  fails = check(well_formed(&rsegs) && status_of(&rsegs) == 404,
    "abuse: 500-segment path -> well-formed 404", fails);

  // ---- burst + post-fuzz sanity ----
  var burst_bad: Int = 0;
  mark("t-burst");
  var bi: Int = 0;
  while bi < 300 {
    var rb = http_service_handle(&mut eng, &mk_req("GET", "/health", ""));
    if status_of(&rb) != 200 || !well_formed(&rb) { burst_bad = burst_bad + 1; }
    bi = bi + 1;
  }
  fails = check(burst_bad == 0, "abuse: 300-request burst -> all well-formed 200", fails);

  mark("t-post");
  var post_search = http_service_handle(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"fz\",\"vector\":[1,0],\"top_k\":2}"));
  fails = check(status_of(&post_search) == 200 && well_formed(&post_search),
    "abuse: service intact after the fuzz campaign", fails);

  io.println("");
  io.println("probe_http_fuzz: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
