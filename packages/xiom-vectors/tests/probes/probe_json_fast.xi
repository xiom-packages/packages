// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Probe: the lane-local fast upsert scanner (api.json_fast) is BEHAVIORALLY
// EQUIVALENT to the strict generic parser. Strategy: run the same request
// sequence twice -- once with cfg.fast_upsert=true, once false -- and assert
// byte-identical responses for every case (accept AND reject paths), over
// a hand-written matrix plus deterministic byte mutations of a canonical
// body. Also gates the fast-path latency on a 50,000-number body (the
// strict parser takes ~84 s there; the fast path must be < 2 s).
// Exit = failed checks.

use xiom.io;
use xiom.convert;
use xiom.time;
use xiom.string.slice;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;

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
    return fails;
  }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn lcg_next(state: Int) -> Int {
  var hi = state / 65536;
  var lo = state % 65536;
  var a = 36969 * (hi % 65536) + state / 2147483648;
  var b = 18000 * lo + state % 65536;
  return ((a % 65536) * 65536 + b % 65536) % 2147483648;
}

fn handle_body(eng: &mut VectorEngine, cfg: &ServiceConfig, path: Str, body: Str) -> Vec[UInt8] {
  // Build the request as BYTES (a Str round-trip would hit the stdlib
  // str_bytes quadratic and pollute the measurement).
  var raw = Vec[UInt8].new();
  push_str(&mut raw, "POST " + path + " HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: "
    + int_to_str(body.len()) + "\r\n\r\n");
  push_str(&mut raw, body);
  return http_service_handle_cfg(eng, &raw, cfg);
}

// One mode's run over the whole matrix: create the collection, then the
// cases in order. Responses land in `outs`.
fn run_matrix(cfg: &ServiceConfig, bodies: &Vec[Str], outs: &mut Vec[Vec[UInt8]]) {
  var eng = engine_new();
  let create = handle_body(&mut eng, cfg, "/collections", "{\"name\":\"p\",\"dim\":2,\"metric\":\"euclidean\"}");
  outs.push(create);
  var i: Int = 0;
  while i < bodies.len() {
    outs.push(handle_body(&mut eng, cfg, "/collections/p/points", bodies[i]));
    i = i + 1;
  }
}

fn main() -> Int {
  var fails: Int = 0;

  var bodies = Vec[Str].new();
  // canonical + variants the fast path should take
  bodies.push("{\"ids\":[1,2],\"vectors\":[[1,2],[3,4]]}");
  bodies.push("{\"vectors\":[[1,2]],\"ids\":[5]}");
  bodies.push("{ \"ids\" : [ 1 , 2 ] , \"vectors\" : [ [ 1.5 , 2 ] , [ 3 , 4e0 ] ] }");
  bodies.push("{\"ids\":[-1,2],\"vectors\":[[-1.5e1,2.25],[3,4]]}");
  bodies.push("{\"ids\":[1.9,2],\"vectors\":[[0,0],[1,1]]}");
  bodies.push("{\"ids\":[9007199254740992],\"vectors\":[[1,1]]}");
  bodies.push("{\"ids\":[9007199254740993],\"vectors\":[[1,1]]}");
  // rejects / fallbacks
  bodies.push("{\"ids\":[01,2],\"vectors\":[[1,2],[3,4]]}");
  bodies.push("{\"ids\":[+1],\"vectors\":[[1,2]]}");
  bodies.push("{\"ids\":[1.],\"vectors\":[[1,2]]}");
  bodies.push("{\"ids\":[1e],\"vectors\":[[1,2]]}");
  bodies.push("{\"ids\":[1]}");
  bodies.push("{\"ids\":[],\"vectors\":[]}");
  bodies.push("{\"ids\":[1],\"vectors\":[[1,2]],\"x\":1}");
  bodies.push("{\"ids\":[1],\"vectors\":[[1,2]],\"payloads\":[{}]}");
  bodies.push("{\"ids\":[1],\"ids\":[2],\"vectors\":[[1,2]]}");
  bodies.push("{\"ids\":[1],\"vectors\":[[1,2]]}x");
  bodies.push("{\"ids\":[1],\"vectors\":[[1,2]]} \r\n");
  bodies.push("{\"ids\":[1,2],\"vectors\":[[1,2],[3]]}");
  bodies.push("{\"ids\":[\"a\"],\"vectors\":[[1,2]]}");
  bodies.push("{\"ids\":[1],\"vectors\":[[true,2]]}");
  bodies.push("{\"ids\":[[1]],\"vectors\":[[1,2]]}");
  bodies.push("{\"ids\":[1],\"vectors\":[[]]}");
  bodies.push("{\"ids\":[1,],\"vectors\":[[1,2]]}");
  bodies.push("{\n\"ids\":[7],\n\"vectors\":[[2,1]]\n}");
  bodies.push("hello");
  bodies.push("");
  bodies.push("{}");

  // deterministic mutations of the canonical body (byte flips into the
  // printable range) -- 200 extra equivalence cases
  let canonical = "{\"ids\":[1,2],\"vectors\":[[1,2],[3,4]]}";
  var state: Int = 991001;
  var m: Int = 0;
  while m < 200 {
    var cb = slice.str_bytes(canonical);
    state = lcg_next(state);
    var pos: Int = state % cb.len();
    state = lcg_next(state);
    var ch: UInt8 = 32u8 + ((state % 95) as UInt8);
    cb[pos] = ch;
    bodies.push(Str::from_utf8(&cb));
    m = m + 1;
  }

  var cfg_fast = service_config_default();
  var cfg_strict = service_config_default();
  cfg_strict.fast_upsert = false;

  var outs_fast = Vec[Vec[UInt8]].new();
  var outs_strict = Vec[Vec[UInt8]].new();
  run_matrix(&cfg_fast, &bodies, &mut outs_fast);
  run_matrix(&cfg_strict, &bodies, &mut outs_strict);

  fails = check(outs_fast.len() == outs_strict.len() && outs_fast.len() == bodies.len() + 1,
    "modes ran the full matrix", fails);
  var equal: Bool = true;
  var first_bad: Int = -1;
  var i: Int = 0;
  while i < outs_fast.len() && i < outs_strict.len() {
    if !bytes_eq(&outs_fast[i], &outs_strict[i]) {
      equal = false;
      if first_bad < 0 { first_bad = i; }
    }
    i = i + 1;
  }
  io.println("    diag bytes-equality: cases=" + int_to_str(bodies.len()) + " first_mismatch=" + int_to_str(first_bad));
  fails = check(equal, "fast mode == strict mode, byte-for-byte, all cases", fails);

  // response shape spot checks (so a universally-wrong pair cannot pass)
  fails = check(bytes_contains(&outs_fast[1], "\"count\":2"), "canonical upsert -> count 2", fails);
  fails = check(bytes_contains(&outs_fast[8], "400"), "leading zero rejected (400) in fast mode", fails);
  fails = check(bytes_contains(&outs_fast[0], "201"), "collection create parity", fails);

  // fast-path latency on a 50,000-number body (strict takes ~84 s; the
  // fast path scans, so the gate is 2 s)
  var dim: Int = 25;
  var n: Int = 2000;
  var big = Vec[UInt8].new();
  push_str(&mut big, "{\"ids\":[");
  var k: Int = 0;
  while k < n {
    if k > 0 { big.push(44u8); }
    push_str(&mut big, int_to_str(k));
    k = k + 1;
  }
  push_str(&mut big, "],\"vectors\":[");
  k = 0;
  while k < n {
    if k > 0 { big.push(44u8); }
    big.push(91u8);
    var d: Int = 0;
    while d < dim {
      if d > 0 { big.push(44u8); }
      push_str(&mut big, int_to_str((k + d) % 97) + "." + int_to_str((k * 7 + d * 13) % 1000));
      d = d + 1;
    }
    big.push(93u8);
    k = k + 1;
  }
  push_str(&mut big, "]}");
  var big_cfg = service_config_default();
  big_cfg.max_batch = 5000;
  big_cfg.max_request_bytes = 33554432;
  var eng2 = engine_new();
  let c2 = handle_body(&mut eng2, &big_cfg, "/collections", "{\"name\":\"p\",\"dim\":25,\"metric\":\"euclidean\"}");
  var t0 = time.monotonic_ms();
  var big_resp = handle_bytes(&mut eng2, &big_cfg, "/collections/p/points", &big);
  var dt = time.monotonic_ms() - t0;
  io.println("    diag big body: bytes=" + int_to_str(big.len()) + " numbers=" + int_to_str(n * (dim + 1)) + " handle_ms=" + int_to_str(dt));
  fails = check(bytes_contains(&big_resp, "\"count\":2000") && dt < 5000,
    "50k-number body: fast path < 5s and count 2000 (strict ~84s)", fails);

  io.println("");
  io.println("probe_json_fast: exit=" + int_to_str(fails));
  return fails;
}

fn handle_bytes(eng: &mut VectorEngine, cfg: &ServiceConfig, path: Str, body: &Vec[UInt8]) -> Vec[UInt8] {
  var raw = Vec[UInt8].new();
  push_str(&mut raw, "POST " + path + " HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: "
    + int_to_str(body.len()) + "\r\n\r\n");
  var i: Int = 0;
  while i < body.len() {
    raw.push(body[i]);
    i = i + 1;
  }
  return http_service_handle_cfg(eng, &raw, cfg);
}

fn push_str(b: &mut Vec[UInt8], s: Str) {
  let sb = slice.str_bytes(s);
  var i: Int = 0;
  while i < sb.len() {
    b.push(sb[i]);
    i = i + 1;
  }
}

fn bytes_contains(b: &Vec[UInt8], s: Str) -> Bool {
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
