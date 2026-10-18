// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// L-3 router probe (stateless two-shard router):
//   MAPPING: strict loader matrix (missing/garbage/bad shards/bad refs all
//   refuse; a valid v1 loads) + start refusal -> 503.
//   ROUTING: create/upsert/get/search/range/batch/stats/delete through the
//   router == direct to the owning shard (byte-equal bodies where the wire
//   is deterministic); wrong-shard isolation; unknown collection -> 404;
//   mapping-version surfacing (/health, /version, /cluster/mapping);
//   aggregate /stats + /cluster/stats.
//   STALE MAPPING: a REAL move (export on s1 -> attach on s2 -> drop from
//   s1 -> mapping v2) behind the router's cached v1: the forwarded 404
//   triggers reload + single retry to the new owner; a mapping referencing
//   a shard with no local context is refused (v2 kept, 404 unchanged).
//   AUTH: the router applies the service scope map; shards enforce their
//   own keys independently (defense in depth); the aggregate honors
//   internal_key (no key -> shard 401 -> reachable=false, honest).
//   FUZZ: bad paths/methods/framing/bodies stay well-formed 400/404/405/
//   413; hostile collection names never reach a shard.
// Exit = failed checks.
//
// "direct to the owning shard" == router_forward_direct (the transport
// seam) with the same shard context the router holds -- the router adds
// resolution only. Shard contexts are mutated through whole-record
// write-back helpers (the XVC-C-09/C-14 nested-mutation discipline).

module probe_router_2shards

use xiom.vector.api.router;
use xiom.vector.api.http_service;
use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.serialize.json;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
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

fn mk_req_key(method: Str, path: Str, body: Str, key: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nX-Api-Key: " + key
    + "\r\nContent-Length: " + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
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
  var p = json.json_parse(resp_body(resp));
  match p {
    Ok(v) => { return v; }
    Err(_) => {}
  }
  return json.json_null();
}

fn jnum(resp: &Vec[UInt8], key: Str) -> Float64 {
  var v = body_json(resp);
  var f = json.json_get(v, key);
  match f {
    Some(x) => {
      match x {
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
  var f = json.json_get(v, key);
  match f {
    Some(x) => {
      match x {
        String(s) => { return s; }
        _ => {}
      }
    }
    None => {}
  }
  return "";
}

fn jhas(resp: &Vec[UInt8], key: Str) -> Bool {
  var v = body_json(resp);
  var f = json.json_get(v, key);
  match f {
    Some(_) => { return true; }
    None => { return false; }
  }
  return false;
}

fn jarr_len(resp: &Vec[UInt8], key: Str) -> Int {
  var v = body_json(resp);
  var f = json.json_get(v, key);
  match f {
    Some(x) => {
      match x {
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
  var f = json.json_get(v, key);
  match f {
    Some(x) => {
      match x {
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

fn jhits_id(resp: &Vec[UInt8], idx: Int) -> Int {
  var v = body_json(resp);
  var f = json.json_get(v, "hits");
  match f {
    Some(x) => {
      match x {
        Array(items) => {
          if idx < items.len() {
            var g = json.json_get(items[idx], "id");
            match g {
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

// Nested object string: {"k1": {"k2": "..."}} -> value ("" when absent).
fn jpath_str(resp: &Vec[UInt8], k1: Str, k2: Str) -> Str {
  var v = body_json(resp);
  var path = Vec[Str].new();
  path.push(k1);
  path.push(k2);
  var g = json.json_get_path(v, &path);
  match g {
    Some(x) => {
      match x {
        String(s) => { return s; }
        _ => {}
      }
    }
    None => {}
  }
  return "";
}

// Array element field bool: {"key": [ ..., {field: true|false}, ... ]}.
fn jarr_bool(resp: &Vec[UInt8], key: Str, idx: Int, field: Str) -> Bool {
  var v = body_json(resp);
  var f = json.json_get(v, key);
  match f {
    Some(x) => {
      match x {
        Array(items) => {
          if idx < items.len() {
            var g = json.json_get(items[idx], field);
            match g {
              Some(nv) => {
                match nv {
                  Bool(b) => { return b; }
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
  return false;
}

// ---- mapping fixture helpers ----

fn write_text(path: Str, s: Str) -> Bool {
  var b = slice.str_bytes(s);
  var r = io.write_file_bytes(path, &b);
  match r {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Two shards (s1/s2) + optional extra shard entry; docs -> docs_shard.
fn mapping_text(ver: Int, docs_shard: Str, extra: Str) -> Str {
  return "{\"version\":" + convert.int_to_string(ver)
    + ",\"shards\":[{\"id\":\"s1\",\"url\":\"http://127.0.0.1:7711\"},{\"id\":\"s2\",\"url\":\"http://127.0.0.1:7712\"}"
    + extra + "],\"collections\":{\"docs\":\"" + docs_shard + "\",\"logs\":\"s2\"}}";
}

// ---- shard-context mutation via whole-record write-back ----

fn shard_state_get(shards: &mut Vec[RouterShard], idx: Int) -> ServiceState {
  return shards[idx].state;
}

fn shard_state_set(shards: &mut Vec[RouterShard], idx: Int, st: ServiceState) {
  var sh = shards[idx];
  sh.state = st;
  shards[idx] = sh;
}

fn shard_engine_get(shards: &mut Vec[RouterShard], idx: Int) -> VectorEngine {
  return shards[idx].engine;
}

fn shard_engine_set(shards: &mut Vec[RouterShard], idx: Int, e: VectorEngine) {
  var sh = shards[idx];
  sh.engine = e;
  shards[idx] = sh;
}

fn main() -> Int {
  io.println("=== xvector probe: router 2 shards (L-3) ===");
  var fails: Int = 0;

  var p_map = "out/router_probe_mapping.json";
  var p_map_bad = "out/router_probe_mapping_bad.json";
  var p_art = "out/router_probe_move.seg";
  let _c0 = io.remove_file(p_map);
  let _c1 = io.remove_file(p_map_bad);
  let _c2 = io.remove_file(p_art);

  // ---- mapping loader: refusals + one positive control ----
  var m_missing = router_mapping_load(p_map);
  fails = check(!m_missing.ok && m_missing.err.len() > 0, "mapping: missing file refused", fails);
  let _w0 = write_text(p_map, mapping_text(1, "s1", ""));
  var m1 = router_mapping_load(p_map);
  fails = check(m1.ok && m1.version == 1 && m1.shard_ids.len() == 2 && m1.coll_names.len() == 2,
    "mapping: valid v1 loads (2 shards, 2 collections)", fails);

  var bads = Vec[Str].new();
  var badn = Vec[Str].new();
  bads.push("not json at all"); badn.push("garbage refused");
  bads.push("{\"version\":1}"); badn.push("missing shards refused");
  bads.push("{\"version\":1,\"shards\":[],\"collections\":{}}"); badn.push("empty shards refused");
  bads.push("{\"version\":0,\"shards\":[{\"id\":\"a\",\"url\":\"u\"}],\"collections\":{}}"); badn.push("version 0 refused");
  bads.push("{\"version\":\"x\",\"shards\":[{\"id\":\"a\",\"url\":\"u\"}],\"collections\":{}}"); badn.push("non-numeric version refused");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"a\"}],\"collections\":{}}"); badn.push("shard without url refused");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"bad id\",\"url\":\"u\"}],\"collections\":{}}"); badn.push("bad shard id refused");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"a\",\"url\":\"u\"},{\"id\":\"a\",\"url\":\"v\"}],\"collections\":{}}"); badn.push("duplicate shard ids refused");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"a\",\"url\":\"u\"}],\"collections\":{\"docs\":\"zz\"}}"); badn.push("unknown shard ref refused");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"a\",\"url\":\"u\"}],\"collections\":{\"bad name\":\"a\"}}"); badn.push("bad collection name refused");
  bads.push("{\"version\":1,\"shards\":[{\"id\":\"a\",\"url\":\"u\"}],\"collections\":[]}"); badn.push("non-object collections refused");
  var bi: Int = 0;
  while bi < bads.len() {
    let _wb = write_text(p_map_bad, bads[bi]);
    var mb = router_mapping_load(p_map_bad);
    fails = check(!mb.ok, "mapping: " + badn[bi], fails);
    bi = bi + 1;
  }
  let _c3 = io.remove_file(p_map_bad);

  // ---- start refusal on a malformed mapping ----
  let _w1 = write_text(p_map_bad, "not json");
  var rt_bad = router_state_new(p_map_bad);
  var sh_empty = Vec[RouterShard].new();
  var bad_resp = router_handle(&mut rt_bad, &mut sh_empty, &mk_req("GET", "/health", ""));
  fails = check(!rt_bad.ok && status_of(&bad_resp) == 503,
    "start: malformed mapping -> ok=false, requests 503", fails);
  let _c4 = io.remove_file(p_map_bad);

  // ---- shard contexts + router ----
  var shards = Vec[RouterShard].new();
  var e1 = engine_new();
  var e2 = engine_new();
  var s1 = service_state_new();
  var s2 = service_state_new();
  shards.push(RouterShard{ id: "s1", engine: e1, state: s1 });
  shards.push(RouterShard{ id: "s2", engine: e2, state: s2 });
  var rt = router_state_new(p_map);
  fails = check(rt.ok && rt.mapping.version == 1 && rt.mapping.shard_ids.len() == 2,
    "router: starts on v1 mapping", fails);

  // ---- health / version ----
  var hh = router_handle(&mut rt, &mut shards, &mk_req("GET", "/health", ""));
  fails = check(status_of(&hh) == 200 && jstr(&hh, "service") == "xvector-lattice-router"
    && jnum(&hh, "mapping_version") == 1.0 && jnum(&hh, "shards") == 2.0,
    "health: router identity + mapping_version 1 + shard count 2", fails);
  var vv = router_handle(&mut rt, &mut shards, &mk_req("GET", "/version", ""));
  fails = check(status_of(&vv) == 200 && jstr(&vv, "name") == "xvector-lattice-router"
    && jnum(&vv, "mapping_version") == 1.0, "version: router name + mapping_version", fails);

  // ---- create through the router lands on the mapped shard ----
  var c_docs = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"docs\",\"dim\":4,\"metric\":\"cosine\"}"));
  fails = check(status_of(&c_docs) == 201, "create: docs via router -> 201", fails);
  var lr_s1 = router_forward_direct(&mut shards, "s1", &mk_req("GET", "/collections", ""));
  var lr_s2 = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/collections", ""));
  fails = check(jarr_has_str(&lr_s1, "collections", "docs") && !jarr_has_str(&lr_s2, "collections", "docs"),
    "create: docs landed on s1 only", fails);
  var c_logs = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"logs\",\"dim\":3,\"metric\":\"euclidean\"}"));
  fails = check(status_of(&c_logs) == 201, "create: logs via router -> 201", fails);
  var lr_s2b = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/collections", ""));
  fails = check(jarr_has_str(&lr_s2b, "collections", "logs"), "create: logs landed on s2", fails);
  var c_un = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"nomap\",\"dim\":4,\"metric\":\"cosine\"}"));
  fails = check(status_of(&c_un) == 404, "create: unmapped collection -> 404 (placement is mapping-owned)", fails);
  var c_bad = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"bad name\",\"dim\":4,\"metric\":\"cosine\"}"));
  fails = check(status_of(&c_bad) == 400 && jstr(&c_bad, "error") == "invalid name",
    "create: invalid name -> 400 invalid name (shard parity)", fails);

  // ---- data ops: router == direct ----
  var up_docs = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections/docs/points", "{\"ids\":[1,2,3],\"vectors\":[[1,0,0,0],[0.9,0.1,0,0],[0,1,0,0]]}"));
  fails = check(status_of(&up_docs) == 200 && jnum(&up_docs, "count") == 3.0,
    "upsert: docs x3 via router -> count 3", fails);
  var get_raw = mk_req("GET", "/collections/docs/points?id=2", "");
  var get_r = router_handle(&mut rt, &mut shards, &get_raw);
  var get_d = router_forward_direct(&mut shards, "s1", &get_raw);
  fails = check(status_of(&get_r) == 200 && resp_body(&get_r) == resp_body(&get_d),
    "get: docs id=2 via router byte-equal to direct s1", fails);
  var sr_raw = mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":2}");
  var sr_r = router_handle(&mut rt, &mut shards, &sr_raw);
  var sr_d = router_forward_direct(&mut shards, "s1", &sr_raw);
  fails = check(status_of(&sr_r) == 200 && resp_body(&sr_r) == resp_body(&sr_d) && jhits_id(&sr_r, 0) == 1,
    "search: knn via router byte-equal to direct s1 (id 1 first)", fails);
  var st_raw = mk_req("GET", "/stats?collection=docs", "");
  var st_r = router_handle(&mut rt, &mut shards, &st_raw);
  var st_d = router_forward_direct(&mut shards, "s1", &st_raw);
  fails = check(status_of(&st_r) == 200 && resp_body(&st_r) == resp_body(&st_d) && jnum(&st_r, "points") == 3.0,
    "stats: docs via router byte-equal to direct s1", fails);
  var rg_raw = mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[1,0,0,0],\"top_k\":5,\"mode\":\"range\",\"radius\":0.5}");
  var rg_r = router_handle(&mut rt, &mut shards, &rg_raw);
  var rg_d = router_forward_direct(&mut shards, "s1", &rg_raw);
  fails = check(status_of(&rg_r) == 200 && resp_body(&rg_r) == resp_body(&rg_d),
    "range: via router byte-equal to direct s1", fails);
  var bt_raw = mk_req("POST", "/search", "{\"collection\":\"docs\",\"requests\":[{\"vector\":[1,0,0,0],\"top_k\":1},{\"vector\":[1,0,0,0],\"top_k\":2}]}");
  var bt_r = router_handle(&mut rt, &mut shards, &bt_raw);
  var bt_d = router_forward_direct(&mut shards, "s1", &bt_raw);
  fails = check(status_of(&bt_r) == 200 && resp_body(&bt_r) == resp_body(&bt_d),
    "batch: via router byte-equal to direct s1", fails);
  var ws = router_forward_direct(&mut shards, "s2", &get_raw);
  fails = check(status_of(&ws) == 404, "isolation: docs absent on s2 (direct 404)", fails);
  var un_raw = mk_req("POST", "/search", "{\"collection\":\"nope\",\"vector\":[1,0,0,0],\"top_k\":1}");
  var un_resp = router_handle(&mut rt, &mut shards, &un_raw);
  fails = check(status_of(&un_resp) == 404 && jstr(&un_resp, "kind") == "not_found",
    "unknown: unmapped collection -> router 404 not_found", fails);
  var cl_resp = router_handle(&mut rt, &mut shards, &mk_req("GET", "/collections", ""));
  fails = check(status_of(&cl_resp) == 200 && jarr_len(&cl_resp, "collections") == 2
    && jarr_has_str(&cl_resp, "collections", "docs") && jarr_has_str(&cl_resp, "collections", "logs"),
    "list: router lists mapped collections (docs + logs)", fails);

  // ---- logs on s2 via router == direct ----
  var up_logs = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections/logs/points", "{\"ids\":[7],\"vectors\":[[0,0,1]]}"));
  fails = check(status_of(&up_logs) == 200 && jnum(&up_logs, "count") == 1.0,
    "upsert: logs via router -> count 1", fails);
  var get_logs_raw = mk_req("GET", "/collections/logs/points?id=7", "");
  var get_logs = router_handle(&mut rt, &mut shards, &get_logs_raw);
  var get_logs_d = router_forward_direct(&mut shards, "s2", &get_logs_raw);
  fails = check(status_of(&get_logs) == 200 && resp_body(&get_logs) == resp_body(&get_logs_d),
    "get: logs via router byte-equal to direct s2", fails);
  var del_logs = router_handle(&mut rt, &mut shards, &mk_req("DELETE", "/collections/logs/points?id=7", ""));
  fails = check(status_of(&del_logs) == 200 && jhas(&del_logs, "removed"),
    "delete: logs id=7 via router -> removed", fails);

  // ---- cluster views + aggregate ----
  var cm1 = router_handle(&mut rt, &mut shards, &mk_req("GET", "/cluster/mapping", ""));
  fails = check(status_of(&cm1) == 200 && jnum(&cm1, "mapping_version") == 1.0
    && jpath_str(&cm1, "collections", "docs") == "s1" && jpath_str(&cm1, "collections", "logs") == "s2",
    "cluster/mapping: placement surfaced (docs->s1, logs->s2)", fails);
  var cs1 = router_handle(&mut rt, &mut shards, &mk_req("GET", "/cluster/stats", ""));
  fails = check(status_of(&cs1) == 200 && jnum(&cs1, "points_total") == 3.0
    && jarr_bool(&cs1, "shards", 0, "reachable") && jarr_bool(&cs1, "shards", 1, "reachable"),
    "cluster/stats: aggregate points_total 3, both shards reachable", fails);
  var cs2b = router_handle(&mut rt, &mut shards, &mk_req("GET", "/stats", ""));
  fails = check(status_of(&cs2b) == 200 && jnum(&cs2b, "points_total") == 3.0,
    "stats (bare): aggregate alias of /cluster/stats", fails);

  // ---- delete via router reflects in the aggregate ----
  var del_docs = router_handle(&mut rt, &mut shards, &mk_req("DELETE", "/collections/docs/points?id=2", ""));
  fails = check(status_of(&del_docs) == 200 && jhas(&del_docs, "removed"),
    "delete: docs id=2 via router -> removed", fails);
  var del_gone = router_handle(&mut rt, &mut shards, &mk_req("GET", "/collections/docs/points?id=2", ""));
  fails = check(status_of(&del_gone) == 404, "delete: docs id=2 gone after router delete", fails);
  var cs3 = router_handle(&mut rt, &mut shards, &mk_req("GET", "/cluster/stats", ""));
  fails = check(status_of(&cs3) == 200 && jnum(&cs3, "points_total") == 2.0,
    "cluster/stats: points_total 2 after delete", fails);

  // ---- stale mapping: real move + retry-on-404 ----
  var em1 = shard_engine_get(&mut shards, 0);
  var ex_ok: Bool = false;
  match export_collection(&mut em1, "docs", p_art) {
    Ok(_) => { ex_ok = true; }
    Err(_) => {}
  }
  shard_engine_set(&mut shards, 0, em1);
  fails = check(ex_ok, "move: export docs from s1 -> segment artifact", fails);
  var em2 = shard_engine_get(&mut shards, 1);
  var cr_ok: Bool = false;
  match create_named_collection(&mut em2, "docs", 4, DistanceMetric.Cosine) {
    Ok(_) => { cr_ok = true; }
    Err(_) => {}
  }
  var at_ok: Bool = false;
  match attach_segment(&mut em2, p_art) {
    Ok(_) => { at_ok = true; }
    Err(_) => {}
  }
  shard_engine_set(&mut shards, 1, em2);
  var em1b = shard_engine_get(&mut shards, 0);
  var dr_ok: Bool = false;
  match drop_collection(&mut em1b, "docs") {
    Ok(_) => { dr_ok = true; }
    Err(_) => {}
  }
  shard_engine_set(&mut shards, 0, em1b);
  fails = check(cr_ok && at_ok && dr_ok, "move: attach docs on s2 + drop from s1", fails);
  var ws1 = router_forward_direct(&mut shards, "s1", &mk_req("GET", "/collections/docs/points?id=1", ""));
  var ws2 = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/collections/docs/points?id=1", ""));
  fails = check(status_of(&ws1) == 404 && status_of(&ws2) == 200,
    "move: docs gone from s1, live on s2 (direct)", fails);
  let _w2 = write_text(p_map, mapping_text(2, "s2", ""));
  var stra_raw = mk_req("GET", "/collections/docs/points?id=1", "");
  var stra = router_handle(&mut rt, &mut shards, &stra_raw);
  var stra_d = router_forward_direct(&mut shards, "s2", &stra_raw);
  fails = check(status_of(&stra) == 200 && resp_body(&stra) == resp_body(&stra_d),
    "stale: forwarded 404 -> reload + retry new owner -> 200 byte-equal", fails);
  fails = check(rt.mapping.version == 2 && rt.reloads == 1,
    "stale: mapping v2 installed (reloads == 1)", fails);
  var h2 = router_handle(&mut rt, &mut shards, &mk_req("GET", "/health", ""));
  fails = check(jnum(&h2, "mapping_version") == 2.0, "stale: /health surfaces mapping_version 2", fails);
  var cm2 = router_handle(&mut rt, &mut shards, &mk_req("GET", "/cluster/mapping", ""));
  fails = check(jpath_str(&cm2, "collections", "docs") == "s2", "stale: /cluster/mapping now docs->s2", fails);

  // ---- reload refusal: mapping needs a shard with no local context ----
  var em2b = shard_engine_get(&mut shards, 1);
  var dr2_ok: Bool = false;
  match drop_collection(&mut em2b, "docs") {
    Ok(_) => { dr2_ok = true; }
    Err(_) => {}
  }
  shard_engine_set(&mut shards, 1, em2b);
  let _w3 = write_text(p_map, mapping_text(3, "s3", ",{\"id\":\"s3\",\"url\":\"http://127.0.0.1:7713\"}"));
  var v3v = router_mapping_load(p_map);
  fails = check(dr2_ok && v3v.ok, "reload: v3 mapping itself valid (context coverage is the gate)", fails);
  var rr1 = router_handle(&mut rt, &mut shards, &mk_req("GET", "/collections/docs/points?id=1", ""));
  fails = check(status_of(&rr1) == 404 && rt.mapping.version == 2 && rt.reload_refusals == 1,
    "reload: owner shard lacks context -> reload refused, v2 kept, 404", fails);
  var v3f = router_mapping_load(p_map);
  fails = check(v3f.version == 3, "reload: file forged ahead (v3) while router kept v2", fails);

  // ---- auth: router scope map + shard defense in depth ----
  var st1 = shard_state_get(&mut shards, 0);
  let _k1 = service_auth_add_key(&mut st1.auth, "read-key-01", ApiScope.Read);
  let _k2 = service_auth_add_key(&mut st1.auth, "admin-key-01", ApiScope.Admin);
  shard_state_set(&mut shards, 0, st1);
  var st2 = shard_state_get(&mut shards, 1);
  let _k3 = service_auth_add_key(&mut st2.auth, "read-key-01", ApiScope.Read);
  let _k4 = service_auth_add_key(&mut st2.auth, "admin-key-01", ApiScope.Admin);
  shard_state_set(&mut shards, 1, st2);
  let _k5 = service_auth_add_key(&mut rt.auth, "read-key-01", ApiScope.Read);
  let _k6 = service_auth_add_key(&mut rt.auth, "admin-key-01", ApiScope.Admin);
  rt.internal_key = "admin-key-01";
  var a1 = router_handle(&mut rt, &mut shards, &mk_req("GET", "/collections", ""));
  fails = check(status_of(&a1) == 401, "auth: missing key at the router -> 401", fails);
  var a2 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/collections", "", "read-key-01"));
  fails = check(status_of(&a2) == 200, "auth: read key -> 200 (forwarded, shard re-checks)", fails);
  var a3 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/collections/logs/points", "{\"ids\":[9],\"vectors\":[[0,0,1]]}", "read-key-01"));
  fails = check(status_of(&a3) == 403, "auth: read key on write -> 403 at the router", fails);
  var a4 = router_forward_direct(&mut shards, "s1", &mk_req("GET", "/collections", ""));
  fails = check(status_of(&a4) == 401, "auth: shard enforces independently (direct, no key -> 401)", fails);
  var a5 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/cluster/mapping", "", "read-key-01"));
  fails = check(status_of(&a5) == 403, "auth: /cluster/mapping needs admin (read key -> 403)", fails);
  var a6 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/cluster/mapping", "", "admin-key-01"));
  fails = check(status_of(&a6) == 200, "auth: /cluster/mapping with admin key -> 200", fails);
  var a7 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/cluster/stats", "", "admin-key-01"));
  fails = check(status_of(&a7) == 200 && jnum(&a7, "mapping_version") == 2.0,
    "auth: /cluster/stats with admin + internal key -> 200", fails);
  rt.internal_key = "";
  var a8 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/cluster/stats", "", "admin-key-01"));
  fails = check(status_of(&a8) == 200 && !jarr_bool(&a8, "shards", 0, "reachable"),
    "auth: aggregate without internal key -> shard 401 -> reachable false", fails);
  rt.internal_key = "admin-key-01";

  // ---- routing fuzz ----
  var f0 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/collections//points", "", "read-key-01"));
  fails = check(status_of(&f0) == 404, "fuzz: /collections//points -> 404", fails);
  var f1 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/collections/docs/points/extra", "", "read-key-01"));
  fails = check(status_of(&f1) == 404, "fuzz: extra path segment -> 404", fails);
  var f2 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/metrics", "", "read-key-01"));
  fails = check(status_of(&f2) == 404, "fuzz: /metrics is per-shard (router 404)", fails);
  var f3 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/cluster/unknown", "", "admin-key-01"));
  fails = check(status_of(&f3) == 404, "fuzz: unknown /cluster route -> 404", fails);
  var f4 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/health", "", "read-key-01"));
  fails = check(status_of(&f4) == 405, "fuzz: POST /health -> 405", fails);
  var f5 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/search", "", "read-key-01"));
  fails = check(status_of(&f5) == 405, "fuzz: GET /search -> 405", fails);
  var f6 = router_handle(&mut rt, &mut shards, &slice.str_bytes("GET /health HTTP/1.1\r\nHost: t\r\n"));
  fails = check(status_of(&f6) == 400 && jstr(&f6, "error") == "incomplete request",
    "fuzz: head without terminator -> 400 incomplete", fails);
  var f7 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/search", "not json", "read-key-01"));
  fails = check(status_of(&f7) == 400 && jstr(&f7, "error") == "bad json",
    "fuzz: non-JSON search body -> 400 bad json", fails);
  var f8 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/search", "{\"vector\":[1,0,0,0]}", "read-key-01"));
  fails = check(status_of(&f8) == 400 && jstr(&f8, "error") == "missing collection",
    "fuzz: search without collection -> 400 missing collection", fails);
  var f9 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/search", "{\"collection\":\"../etc\",\"vector\":[1,0,0,0],\"top_k\":1}", "read-key-01"));
  fails = check(status_of(&f9) == 404, "fuzz: hostile collection name -> 404 (never forwarded)", fails);
  var deep = "";
  var di: Int = 0;
  while di < 70 { deep = deep + "["; di = di + 1; }
  di = 0;
  while di < 70 { deep = deep + "]"; di = di + 1; }
  var f10 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/search", deep, "read-key-01"));
  fails = check(status_of(&f10) == 400 && jstr(&f10, "error") == "json nesting exceeds service limit",
    "fuzz: deep JSON body -> depth guard 400", fails);
  var f11 = router_handle(&mut rt, &mut shards, &mk_req_key("GET", "/health/", "", "read-key-01"));
  fails = check(status_of(&f11) == 200, "fuzz: trailing slash /health/ -> 200 (segment semantics)", fails);
  var bigb = Vec[UInt8].new();
  var bi2: Int = 0;
  while bi2 < 70000 { bigb.push(97u8); bi2 = bi2 + 1; }
  var bigbody = Str::from_utf8(&bigb);
  var f12 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/search", bigbody, "read-key-01"));
  fails = check(status_of(&f12) == 413, "fuzz: oversized request -> 413 before parsing", fails);
  var f13 = router_handle(&mut rt, &mut shards, &mk_req_key("POST", "/collections", "{\"dim\":4,\"metric\":\"cosine\"}", "admin-key-01"));
  fails = check(status_of(&f13) == 400 && jstr(&f13, "error") == "missing name",
    "fuzz: create without name -> 400 missing name", fails);

  // cleanup (best effort)
  let _r0 = io.remove_file(p_map);
  let _r1 = io.remove_file(p_art);

  io.println("");
  io.println("probe_router_2shards: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
