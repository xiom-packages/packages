// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: service auth + rate limiting (M-S3). Verifies key validation,
// the scope lattice (read < write < admin), constant-time key lookup via
// http_service_handle_state, env key loading (XVECTOR_API_KEYS),
// auth-disabled embedded default, /health public, 401/403 kinds, the
// token-bucket math (explicit clocks) and the end-to-end 429 path.
// Exit = failed checks.

module probe_service_auth

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;
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

fn mk_req(method: Str, path: Str, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nContent-Length: "
    + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn mk_req_key(method: Str, path: Str, body: Str, header: Str, key: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\n" + header + ": " + key
    + "\r\nContent-Length: " + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
}

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
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

fn body_json(resp: &Vec[UInt8]) -> JsonValue {
  match json.json_parse(resp_body(resp)) {
    Ok(v) => { return v; }
    Err(_) => {}
  }
  return json.json_null();
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

fn main() -> Int {
  io.println("=== xvector probe: service auth + rate limiting (M-S3) ===");
  var fails: Int = 0;

  // ---- key validation + registration ----
  fails = check(api_key_valid("a_read_00001") && api_key_valid("k.1-2_3xyz")
    && !api_key_valid("short") && !api_key_valid("bad key!")  ,
    "keys: validation rules (8..128, charset)", fails);
  var auth = service_auth_new();
  var add1 = service_auth_add_key(&mut auth, "a_read_00001", ApiScope.Read);
  var dup = service_auth_add_key(&mut auth, "a_read_00001", ApiScope.Admin);
  var bad = service_auth_add_key(&mut auth, "no", ApiScope.Read);
  fails = check(add1 && !dup && !bad && auth.enabled && auth.keys.len() == 1,
    "keys: add valid, reject duplicate/invalid, enables auth", fails);
  fails = check(service_auth_add_key(&mut auth, "a_write_0001", ApiScope.Write) &&
    service_auth_add_key(&mut auth, "a_admin_0001", ApiScope.Admin),
    "keys: write + admin registered", fails);

  // ---- list parsing + env loading ----
  var auth2 = service_auth_new();
  var added = service_auth_parse_list(&mut auth2, "b_read_00001:read,b_admin_0001:admin,bad:scope,short:read");
  fails = check(added == 2 && auth2.keys.len() == 2 && auth2.enabled,
    "list: key:scope parsing skips malformed entries", fails);
  env.set_var("XVECTOR_API_KEYS", "env_admin_0001:admin,env_read_00001:read");
  var auth3 = service_auth_new();
  var eadded = service_auth_from_env(&mut auth3);
  env.remove_var("XVECTOR_API_KEYS");
  var auth4 = service_auth_new();
  var emissing = service_auth_from_env(&mut auth4);
  fails = check(eadded == 2 && auth3.enabled && emissing == 0 && !auth4.enabled,
    "env: XVECTOR_API_KEYS loads keys; missing var adds none", fails);

  // ---- auth-disabled embedded default ----
  var eng = engine_new();
  var st0 = service_state_new();
  var open_create = http_service_handle_state(&mut eng,
    &mk_req("POST", "/collections", "{\"name\":\"sec\",\"dim\":2,\"metric\":\"euclidean\"}"), &mut st0);
  var open_search = http_service_handle_state(&mut eng,
    &mk_req("POST", "/search", "{\"collection\":\"sec\",\"vector\":[1,0],\"top_k\":1}"), &mut st0);
  fails = check(status_of(&open_create) == 201 && status_of(&open_search) == 200,
    "embedded default: auth disabled, requests pass without keys", fails);

  // ---- auth enabled: scopes ----
  var eng2 = engine_new();
  var st = service_state_new();
  service_auth_add_key(&mut st.auth, "a_read_00001", ApiScope.Read);
  service_auth_add_key(&mut st.auth, "a_write_0001", ApiScope.Write);
  service_auth_add_key(&mut st.auth, "a_admin_0001", ApiScope.Admin);

  var h1 = http_service_handle_state(&mut eng2, &mk_req("GET", "/health", ""), &mut st);
  fails = check(status_of(&h1) == 200, "auth: /health stays public", fails);

  var nokey = http_service_handle_state(&mut eng2, &mk_req("GET", "/collections", ""), &mut st);
  fails = check(status_of(&nokey) == 401 && jstr(&nokey, "kind") == "unauthorized"
    && jstr(&nokey, "error") == "missing api key",
    "auth: missing key -> 401 unauthorized", fails);
  var wrongkey = http_service_handle_state(&mut eng2,
    &mk_req_key("GET", "/collections", "", "X-Api-Key", "wrong_key_001"), &mut st);
  fails = check(status_of(&wrongkey) == 401 && jstr(&wrongkey, "error") == "invalid api key",
    "auth: wrong key -> 401 invalid api key", fails);
  var nokeyunknown = http_service_handle_state(&mut eng2, &mk_req("GET", "/nope", ""), &mut st);
  fails = check(status_of(&nokeyunknown) == 401, "auth: unknown route still requires a key", fails);

  // admin creates; write mutates; read only reads.
  var c_admin = http_service_handle_state(&mut eng2,
    &mk_req_key("POST", "/collections", "{\"name\":\"sec\",\"dim\":2,\"metric\":\"euclidean\"}", "X-Api-Key", "a_admin_0001"), &mut st);
  fails = check(status_of(&c_admin) == 201, "scope: admin creates a collection", fails);
  var c_read = http_service_handle_state(&mut eng2,
    &mk_req_key("POST", "/collections", "{\"name\":\"two\",\"dim\":2,\"metric\":\"euclidean\"}", "X-Api-Key", "a_read_00001"), &mut st);
  fails = check(status_of(&c_read) == 403 && jstr(&c_read, "kind") == "forbidden"
    && jstr(&c_read, "error") == "insufficient scope",
    "scope: read key cannot create (403 forbidden)", fails);
  var c_write = http_service_handle_state(&mut eng2,
    &mk_req_key("POST", "/collections", "{\"name\":\"two\",\"dim\":2,\"metric\":\"euclidean\"}", "X-Api-Key", "a_write_0001"), &mut st);
  fails = check(status_of(&c_write) == 403, "scope: write key cannot create (403)", fails);

  var up_write = http_service_handle_state(&mut eng2,
    &mk_req_key("POST", "/collections/sec/points", "{\"ids\":[1,2],\"vectors\":[[1,0],[0,1]]}", "X-Api-Key", "a_write_0001"), &mut st);
  fails = check(status_of(&up_write) == 200, "scope: write upserts points", fails);
  var up_read = http_service_handle_state(&mut eng2,
    &mk_req_key("POST", "/collections/sec/points", "{\"ids\":[3],\"vectors\":[[0,0]]}", "X-Api-Key", "a_read_00001"), &mut st);
  fails = check(status_of(&up_read) == 403, "scope: read cannot upsert (403)", fails);

  var s_read = http_service_handle_state(&mut eng2,
    &mk_req_key("POST", "/search", "{\"collection\":\"sec\",\"vector\":[1,0],\"top_k\":2}", "X-Api-Key", "a_read_00001"), &mut st);
  fails = check(status_of(&s_read) == 200, "scope: read key searches", fails);
  var g_read = http_service_handle_state(&mut eng2,
    &mk_req_key("GET", "/collections/sec/points?id=1", "", "X-Api-Key", "a_read_00001"), &mut st);
  fails = check(status_of(&g_read) == 200, "scope: read key gets points", fails);
  var st_read = http_service_handle_state(&mut eng2,
    &mk_req_key("GET", "/stats?collection=sec", "", "X-Api-Key", "a_read_00001"), &mut st);
  fails = check(status_of(&st_read) == 200, "scope: read key reads stats", fails);
  var d_read = http_service_handle_state(&mut eng2,
    &mk_req_key("DELETE", "/collections/sec/points?id=2", "", "X-Api-Key", "a_read_00001"), &mut st);
  fails = check(status_of(&d_read) == 403, "scope: read cannot delete (403)", fails);
  var d_write = http_service_handle_state(&mut eng2,
    &mk_req_key("DELETE", "/collections/sec/points?id=2", "", "X-Api-Key", "a_write_0001"), &mut st);
  fails = check(status_of(&d_write) == 200, "scope: write deletes points", fails);
  var admin_search = http_service_handle_state(&mut eng2,
    &mk_req_key("POST", "/search", "{\"collection\":\"sec\",\"vector\":[1,0],\"top_k\":1}", "x-api-key", "a_admin_0001"), &mut st);
  fails = check(status_of(&admin_search) == 200, "scope: admin satisfies read (lowercase header)", fails);

  // ---- rate limiter math (explicit clock) ----
  var rl = rate_limiter_new(2, 0);
  var a1 = rate_limiter_allow(&mut rl, 0);
  var a2 = rate_limiter_allow(&mut rl, 0);
  var a3 = rate_limiter_allow(&mut rl, 0);
  var a4 = rate_limiter_allow(&mut rl, 5000);
  fails = check(a1 && a2 && !a3 && !a4, "rate: capacity 2, no refill (burst then blocked)", fails);
  var rl2 = rate_limiter_new(2, 1);
  var b1 = rate_limiter_allow(&mut rl2, 0);
  var b2 = rate_limiter_allow(&mut rl2, 0);
  var b3 = rate_limiter_allow(&mut rl2, 0);
  var b4 = rate_limiter_allow(&mut rl2, 1000);
  var b5 = rate_limiter_allow(&mut rl2, 1000);
  fails = check(b1 && b2 && !b3 && b4 && !b5, "rate: 1/s refill (one token per second)", fails);

  // ---- end-to-end 429 ----
  var eng3 = engine_new();
  var st3 = service_state_new();
  st3.rate = rate_limiter_new(2, 0);
  var r1 = http_service_handle_state(&mut eng3, &mk_req("GET", "/health", ""), &mut st3);
  var r2 = http_service_handle_state(&mut eng3, &mk_req("GET", "/health", ""), &mut st3);
  var r3 = http_service_handle_state(&mut eng3, &mk_req("GET", "/health", ""), &mut st3);
  fails = check(status_of(&r1) == 200 && status_of(&r2) == 200 && status_of(&r3) == 429
    && jstr(&r3, "kind") == "rate_limited",
    "rate: service returns 429 rate_limited after the bucket empties", fails);

  io.println("");
  io.println("probe_service_auth: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
