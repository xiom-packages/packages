// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: service config + limits + errors + shutdown (M-S2). Verifies the
// ServiceConfig surface (defaults, apply, env overrides, key=value config
// file incl. malformed handling), limit enforcement through
// http_service_handle_cfg (request size 413, top_k/dim 400, batch 413,
// exact-boundary acceptance), the JSON error model (`kind`/`status`
// fields), CoreError mapping, and the graceful-shutdown checkpoint
// (wal_persist -> wal_load -> engine_recover roundtrip + failure path).
// Exit = failed checks.

module probe_service_limits

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;
use xiom.vector.durability.wal_file;
use xiom.vectors;
use xiom.serialize.json;
use xiom.string.slice;
use xiom.os.env;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

// ---- request builders (as in probe_http_service) ----

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

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
}

fn body_json(resp: &Vec[UInt8]) -> JsonValue {
  match json.json_parse(resp_body(resp)) {
    Ok(v) => { return v; }
    Err(_) => {}
  }
  return json.json_null();
}

fn jnum(resp: &Vec[UInt8], key: Str) -> Float64 {
  var v = body_json(resp);
  match json.json_get(v, key) {
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
  match json.json_get(v, key) {
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

fn jarr_len(resp: &Vec[UInt8], key: Str) -> Int {
  var v = body_json(resp);
  match json.json_get(v, key) {
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

fn write_file_str(path: Str, s: Str) -> Bool {
  var b = slice.str_bytes(s);
  var res = io.write_file_bytes(path, &b);
  match res {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn main() -> Int {
  io.println("=== xvector probe: service config + limits + errors (M-S2) ===");
  var fails: Int = 0;

  // ---- config defaults + apply ----
  var d = service_config_default();
  fails = check(d.max_request_bytes == 65536 && d.max_top_k == 1000 && d.max_batch == 256 && d.max_dim == 1024,
    "config: defaults exact", fails);
  var cfg = service_config_default();
  var ok1 = service_config_apply(&mut cfg, "max_top_k", 7);
  var ok2 = !service_config_apply(&mut cfg, "nope_key", 7);
  var ok3 = !service_config_apply(&mut cfg, "max_top_k", 0);
  fails = check(ok1 && ok2 && ok3 && cfg.max_top_k == 7 && cfg.max_batch == 256,
    "config: apply known/unknown/zero", fails);

  // ---- env overrides ----
  env.set_var("XVECTOR_MAX_TOP_K", "5");
  env.set_var("XVECTOR_MAX_DIM", "9");
  env.set_var("XVECTOR_MAX_BATCH", "not_a_number");
  var ecfg = service_config_default();
  var applied = service_config_from_env(&mut ecfg);
  env.remove_var("XVECTOR_MAX_TOP_K");
  env.remove_var("XVECTOR_MAX_DIM");
  env.remove_var("XVECTOR_MAX_BATCH");
  fails = check(applied == 2 && ecfg.max_top_k == 5 && ecfg.max_dim == 9 && ecfg.max_batch == 256,
    "config: env overrides applied (malformed ignored)", fails);

  // ---- config file ----
  var pcfg = "out/service_config_probe.cfg";
  fails = check(write_file_str(pcfg, "max_top_k=7\nmax_batch=3\n# comment\nunknown_key=9\n\n"),
    "config file: seed", fails);
  var lc = service_config_load(pcfg);
  fails = check(lc.loaded && lc.valid && lc.cfg.max_top_k == 7 && lc.cfg.max_batch == 3
    && lc.cfg.max_request_bytes == 65536,
    "config file: key=value applied, comments/unknown ignored", fails);
  fails = check(write_file_str(pcfg, "max_top_k=7\nbogus line\n") &&
    service_config_load(pcfg).valid == false && service_config_load(pcfg).cfg.max_top_k == 7,
    "config file: malformed line -> valid=false, good lines kept", fails);
  var lmiss = service_config_load("out/service_config_missing.cfg");
  fails = check(!lmiss.loaded && !lmiss.valid && lmiss.cfg.max_top_k == 1000,
    "config file: missing -> defaults, loaded=false", fails);
  fails = check(write_file_str(pcfg, "") && !service_config_load(pcfg).loaded,
    "config file: empty -> loaded=false", fails);

  // ---- limits through the config-aware handler ----
  var small = ServiceConfig{ max_request_bytes: 512, max_top_k: 5, max_batch: 2, max_dim: 4, fast_upsert: true };
  var eng = engine_new();

  // request size: pad past the limit, then exactly at the limit.
  var big = mk_req("GET", "/health", "");
  var pad: Int = 0;
  while big.len() <= 512 {
    big.push(97);
    pad = pad + 1;
  }
  var rbig = http_service_handle_cfg(&mut eng, &big, &small);
  fails = check(status_of(&rbig) == 413 && jstr(&rbig, "kind") == "too_large" && jnum(&rbig, "status") == 413.0,
    "limits: request over max_request_bytes -> 413 too_large", fails);

  // A request exactly at the limit is accepted (long unknown header pad).
  var s2base = "GET /health HTTP/1.1\r\nX-Pad: \r\nContent-Length: 0\r\n\r\n";
  var padlen: Int = 512 - slice.str_bytes(s2base).len();
  var padstr = "";
  var pi: Int = 0;
  while pi < padlen {
    padstr = padstr + "a";
    pi = pi + 1;
  }
  var s2 = "GET /health HTTP/1.1\r\nX-Pad: " + padstr + "\r\nContent-Length: 0\r\n\r\n";
  var rb2 = slice.str_bytes(s2);
  var rex2 = http_service_handle_cfg(&mut eng, &rb2, &small);
  fails = check(rb2.len() == 512 && status_of(&rex2) == 200,
    "limits: request exactly at max_request_bytes accepted", fails);

  // create a collection within max_dim, then limit checks.
  var c1 = http_service_handle_cfg(&mut eng, &mk_req("POST", "/collections",
    "{\"name\":\"d4\",\"dim\":4,\"metric\":\"euclidean\"}"), &small);
  fails = check(status_of(&c1) == 201, "limits: dim 4 at max_dim accepted", fails);
  var cb = http_service_handle_cfg(&mut eng, &mk_req("POST", "/collections",
    "{\"name\":\"d5\",\"dim\":5,\"metric\":\"euclidean\"}"), &small);
  fails = check(status_of(&cb) == 400 && jstr(&cb, "error") == "dimension exceeds service limit",
    "limits: dim over max_dim -> 400", fails);

  // upsert within batch limit (2 per call), then top_k checks.
  var up = http_service_handle_cfg(&mut eng, &mk_req("POST", "/collections/d4/points",
    "{\"ids\":[1,2],\"vectors\":[[1,0,0,0],[0,1,0,0]]}"), &small);
  var up2 = http_service_handle_cfg(&mut eng, &mk_req("POST", "/collections/d4/points",
    "{\"ids\":[3],\"vectors\":[[0,0,1,0]]}"), &small);
  fails = check(status_of(&up) == 200 && status_of(&up2) == 200, "limits: upserts within batch limit", fails);
  var upb = http_service_handle_cfg(&mut eng, &mk_req("POST", "/collections/d4/points",
    "{\"ids\":[4,5,6],\"vectors\":[[1,0,0,0],[1,0,0,0],[1,0,0,0]]}"), &small);
  fails = check(status_of(&upb) == 413 && jstr(&upb, "kind") == "too_large",
    "limits: points batch over max_batch -> 413", fails);

  var s5 = http_service_handle_cfg(&mut eng, &mk_req("POST", "/search",
    "{\"collection\":\"d4\",\"vector\":[1,0,0,0],\"top_k\":5}"), &small);
  fails = check(status_of(&s5) == 200 && jarr_len(&s5, "hits") == 3,
    "limits: top_k at max_top_k accepted", fails);
  var s6 = http_service_handle_cfg(&mut eng, &mk_req("POST", "/search",
    "{\"collection\":\"d4\",\"vector\":[1,0,0,0],\"top_k\":6}"), &small);
  fails = check(status_of(&s6) == 400 && jstr(&s6, "error") == "top_k exceeds service limit",
    "limits: top_k over max_top_k -> 400", fails);

  var batched = http_service_handle_cfg(&mut eng, &mk_req("POST", "/search",
    "{\"collection\":\"d4\",\"requests\":[{\"vector\":[1,0,0,0],\"top_k\":1},{\"vector\":[0,1,0,0],\"top_k\":1}]}"), &small);
  fails = check(status_of(&batched) == 200 && jarr_len(&batched, "results") == 2,
    "limits: search batch at max_batch accepted", fails);
  var batchb = http_service_handle_cfg(&mut eng, &mk_req("POST", "/search",
    "{\"collection\":\"d4\",\"requests\":[{\"vector\":[1,0,0,0],\"top_k\":1},{\"vector\":[0,1,0,0],\"top_k\":1},{\"vector\":[0,0,1,0],\"top_k\":1}]}"), &small);
  fails = check(status_of(&batchb) == 413 && jstr(&batchb, "kind") == "too_large",
    "limits: search batch over max_batch -> 413", fails);

  // default-config path: engine-level k ceiling (1000) enforced.
  var eng2 = engine_new();
  var dc = http_service_handle(&mut eng2, &mk_req("POST", "/collections",
    "{\"name\":\"d2\",\"dim\":2,\"metric\":\"euclidean\"}"));
  var dk = http_service_handle(&mut eng2, &mk_req("POST", "/search",
    "{\"collection\":\"d2\",\"vector\":[1,0],\"top_k\":1001}"));
  var dk2 = http_service_handle(&mut eng2, &mk_req("POST", "/search",
    "{\"collection\":\"d2\",\"vector\":[1,0],\"top_k\":1000}"));
  fails = check(status_of(&dc) == 201 && status_of(&dk) == 400 && status_of(&dk2) == 200,
    "limits: default config top_k ceiling (1000)", fails);
  var big2 = mk_req("GET", "/health", "");
  var pb: Int = 0;
  while big2.len() <= 65536 {
    big2.push(98);
    pb = pb + 1;
  }
  fails = check(status_of(&http_service_handle(&mut eng2, &big2)) == 413,
    "limits: default request size ceiling (64 KiB)", fails);

  // ---- error model kinds ----
  var e404 = http_service_handle(&mut eng2, &mk_req("GET", "/nope", ""));
  var e405 = http_service_handle(&mut eng2, &mk_req("DELETE", "/health", ""));
  var e409 = http_service_handle(&mut eng2, &mk_req("POST", "/collections",
    "{\"name\":\"d2\",\"dim\":2,\"metric\":\"euclidean\"}"));
  var e400 = http_service_handle(&mut eng2, &mk_req("POST", "/search", "not json"));
  fails = check(jstr(&e404, "kind") == "not_found" && jnum(&e404, "status") == 404.0,
    "errors: 404 -> kind not_found + status field", fails);
  fails = check(jstr(&e405, "kind") == "method_not_allowed", "errors: 405 -> kind method_not_allowed", fails);
  fails = check(jstr(&e409, "kind") == "conflict", "errors: 409 -> kind conflict", fails);
  fails = check(jstr(&e400, "kind") == "invalid_input", "errors: 400 -> kind invalid_input", fails);

  // ---- graceful shutdown (drain + checkpoint) ----
  var eng3 = engine_new();
  create_collection(&mut eng3, 3, DistanceMetric.Cosine);
  upsert(&mut eng3, 1, mk3(1.0, 0.0, 0.0));
  upsert(&mut eng3, 2, mk3(0.0, 1.0, 0.0));
  upsert(&mut eng3, 3, mk3(0.0, 0.0, 1.0));
  var pshut = "out/service_shutdown_probe.wal";
  fails = check(http_service_shutdown(&eng3, pshut) && io.file_exists(pshut),
    "shutdown: checkpoint written", fails);
  var lr = wal_load(pshut);
  var rec = engine_recover(&lr, 3, DistanceMetric.Cosine);
  var rec_ok: Bool = engine_size(&rec) == 3;
  var q = mk3(0.9, 0.1, 0.0);
  match search(&rec, &q, 1) {
    Ok(h) => { if h.items.len() == 1 && h.items[0].id == 1 { } else { rec_ok = false; } }
    Err(_) => { rec_ok = false; }
  }
  fails = check(rec_ok, "shutdown: wal_load + recover restores the state", fails);
  var bad = http_service_shutdown(&eng3, "out/no_such_dir_xyz/x.wal");
  fails = check(!bad, "shutdown: unwritable path -> false", fails);

  io.remove_file(pcfg);
  io.remove_file(pshut);
  io.println("");
  io.println("probe_service_limits: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}

fn mk3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}
