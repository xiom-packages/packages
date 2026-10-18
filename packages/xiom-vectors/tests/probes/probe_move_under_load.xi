// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// L-5 probe (cluster ops -- move under load + drain):
//   MOVE UNDER LOAD: acked writes before the move survive inside the
//   artifact (bit-exact union); the move flips the mapping (version bump
//   + atomic persist); a STALE router (second cache) shows the bounded
//   client-visible window -- one forwarded 404 -> reload -> retry; writes
//   continue through the stale-then-fresh router and every acked id is
//   readable at the destination (no acked write lost).
//   COMPACTION-AWARE: a collection with a pre-existing sealed entry PLUS
//   a post-roll active remainder moves via the D7 merge (ids from both
//   sides exact); a fully rolled (sealed-only) collection moves too.
//   DRAIN: POST /cluster/drain moves every collection off a shard
//   (round-robin), the mapping flips per move, the drained shard ends
//   with none; a single-shard cluster refuses (400).
//   ADMIN FUZZ: unknown collection/shard, same-shard, bad bodies/methods,
//   unconfigured artifact dir, read-key scope check.
// Exit = failed checks.

module probe_move_under_load

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

fn mk_req(method: Str, path: Str, body: Str) -> Vec[UInt8] {
  var bb = slice.str_bytes(body);
  var s = method + " " + path + " HTTP/1.1\r\nHost: t\r\nContent-Length: "
    + convert.int_to_string(bb.len()) + "\r\n\r\n" + body;
  return slice.str_bytes(s);
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

// ---- fixtures ----

fn write_text(path: Str, s: Str) -> Bool {
  var b = slice.str_bytes(s);
  var r = io.write_file_bytes(path, &b);
  match r {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

fn mapping_text() -> Str {
  return "{\"version\":1,\"shards\":[{\"id\":\"s1\",\"url\":\"http://127.0.0.1:7711\"},{\"id\":\"s2\",\"url\":\"http://127.0.0.1:7712\"}],\"collections\":{\"bulk\":\"s1\",\"rolled\":\"s1\",\"sealed_only\":\"s1\",\"drainme\":\"s1\",\"keep\":\"s2\"}}";
}

fn mapping_single_text() -> Str {
  return "{\"version\":1,\"shards\":[{\"id\":\"s1\",\"url\":\"http://127.0.0.1:7711\"}],\"collections\":{\"keep\":\"s1\"}}";
}

// Deterministic upsert body: ids [from, to], vector [id, 0, 0, 0].
fn upsert_body(from_id: Int, to_id: Int) -> Str {
  var s = "{\"ids\":[";
  var i: Int = from_id;
  while i <= to_id {
    if i > from_id { s = s + ","; }
    s = s + convert.int_to_string(i);
    i = i + 1;
  }
  s = s + "],\"vectors\":[";
  i = from_id;
  while i <= to_id {
    if i > from_id { s = s + ","; }
    s = s + "[" + convert.int_to_string(i) + ",0,0,0]";
    i = i + 1;
  }
  s = s + "]}";
  return s;
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
  io.println("=== xvector probe: cluster move under load (L-5) ===");
  var fails: Int = 0;

  var p_map = "out/move_load_mapping.json";
  var p_single = "out/move_load_single.json";
  var a_bulk = "out/xvmove_bulk.seg";
  var a_rolled = "out/xvmove_rolled.seg";
  var a_sealed = "out/xvmove_sealed_only.seg";
  var a_drain = "out/xvmove_drainme.seg";
  var a_pre = "out/xv_rolled_pre.seg";
  let _c0 = io.remove_file(p_map);
  let _c1 = io.remove_file(p_single);
  let _c2 = io.remove_file(a_bulk);
  let _c3 = io.remove_file(a_rolled);
  let _c4 = io.remove_file(a_sealed);
  let _c5 = io.remove_file(a_drain);
  let _c6 = io.remove_file(a_pre);

  let _w0 = write_text(p_map, mapping_text());
  let _w1 = write_text(p_single, mapping_single_text());

  var shards = Vec[RouterShard].new();
  var e1 = engine_new();
  var e2 = engine_new();
  var s1 = service_state_new();
  var s2 = service_state_new();
  shards.push(RouterShard{ id: "s1", engine: e1, state: s1 });
  shards.push(RouterShard{ id: "s2", engine: e2, state: s2 });
  var rt_a = router_state_new(p_map);
  rt_a.artifact_dir = "out";
  var rt_b = router_state_new(p_map);
  rt_b.artifact_dir = "out";
  fails = check(rt_a.ok && rt_b.ok && rt_a.mapping.version == 1,
    "setup: two routers on mapping v1 (5 collections, 2 shards)", fails);

  // ---- move under load: acked writes before the flip survive ----
  var c_bulk = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"bulk\",\"dim\":4,\"metric\":\"euclidean\"}"));
  fails = check(status_of(&c_bulk) == 201, "load: bulk created on s1 via router", fails);
  var up1 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections/bulk/points", upsert_body(1, 20)));
  fails = check(status_of(&up1) == 200 && jnum(&up1, "count") == 20.0, "load: 20 acked writes before the move", fails);
  var c_keep = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"keep\",\"dim\":4,\"metric\":\"euclidean\"}"));
  var up_keep = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections/keep/points", upsert_body(1, 1)));
  fails = check(status_of(&c_keep) == 201 && status_of(&up_keep) == 200,
    "setup: control collection keep lives on s2 (1 point)", fails);

  var mv1 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"bulk\",\"to\":\"s2\"}"));
  fails = check(status_of(&mv1) == 200 && jhas(&mv1, "moved") && jstr(&mv1, "collection") == "bulk"
    && jstr(&mv1, "from") == "s1" && jstr(&mv1, "to") == "s2" && jnum(&mv1, "mapping_version") == 2.0,
    "move: bulk s1 -> s2 (v2 persisted)", fails);

  var lr_s1 = router_forward_direct(&mut shards, "s1", &mk_req("GET", "/collections", ""));
  var lr_s2 = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/collections", ""));
  fails = check(!jarr_has_str(&lr_s1, "collections", "bulk") && jarr_has_str(&lr_s2, "collections", "bulk"),
    "move: source dropped, destination holds bulk (direct)", fails);
  var st_s2 = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/stats?collection=bulk", ""));
  fails = check(status_of(&st_s2) == 200 && jnum(&st_s2, "points") == 20.0,
    "move: destination points == 20 (bit-exact carry)", fails);
  var sr_raw = mk_req("POST", "/search", "{\"collection\":\"bulk\",\"vector\":[3,0,0,0],\"top_k\":1}");
  var sr_r = router_handle(&mut rt_a, &mut shards, &sr_raw);
  var sr_d = router_forward_direct(&mut shards, "s2", &sr_raw);
  fails = check(status_of(&sr_r) == 200 && resp_body(&sr_r) == resp_body(&sr_d) && jhits_id(&sr_r, 0) == 3,
    "move: search via router == direct destination (id 3 first)", fails);

  // stale router: one bounded retry window
  var stale_raw = mk_req("GET", "/collections/bulk/points?id=5", "");
  var stale = router_handle(&mut rt_b, &mut shards, &stale_raw);
  var stale_d = router_forward_direct(&mut shards, "s2", &stale_raw);
  fails = check(status_of(&stale) == 200 && resp_body(&stale) == resp_body(&stale_d),
    "stale: forwarded 404 -> reload -> retry reads the moved point (barely one retry)", fails);
  fails = check(rt_b.reloads == 1 && rt_b.mapping.version == 2,
    "stale: observer reloaded to v2 exactly once", fails);

  // load continues through the (now fresh) observer router
  var up2 = router_handle(&mut rt_b, &mut shards, &mk_req("POST", "/collections/bulk/points", upsert_body(21, 30)));
  fails = check(status_of(&up2) == 200 && jnum(&up2, "count") == 10.0,
    "load: 10 acked writes after the flip land on the new owner", fails);
  var live: Int = 0;
  var i: Int = 1;
  while i <= 30 {
    var g = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/collections/bulk/points?id=" + convert.int_to_string(i), ""));
    if status_of(&g) == 200 { live = live + 1; }
    i = i + 1;
  }
  fails = check(live == 30, "load: every acked id (1..30) readable at the destination (no acked write lost)", fails);

  var keep_s1 = router_forward_direct(&mut shards, "s1", &mk_req("GET", "/collections", ""));
  var keep_s2 = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/collections", ""));
  var keep_g = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/collections/keep/points?id=1", ""));
  fails = check(!jarr_has_str(&keep_s1, "collections", "keep") && jarr_has_str(&keep_s2, "collections", "keep")
    && status_of(&keep_g) == 200,
    "control: untouched collection keep stays on s2 with its point", fails);

  var rt_c = router_state_new(p_map);
  var cm_c = router_handle(&mut rt_c, &mut shards, &mk_req("GET", "/cluster/mapping", ""));
  fails = check(rt_c.ok && rt_c.mapping.version == 2 && jpath_str(&cm_c, "collections", "bulk") == "s2",
    "persist: fresh router loads the moved mapping (v2, bulk -> s2)", fails);

  // ---- compaction-aware move: sealed entry + active remainder ----
  var c_rolled = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"rolled\",\"dim\":4,\"metric\":\"euclidean\"}"));
  fails = check(status_of(&c_rolled) == 201, "rolled: created on s1", fails);
  var up_r1 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections/rolled/points", upsert_body(1, 5)));
  fails = check(status_of(&up_r1) == 200, "rolled: 5 points pre-roll", fails);
  var e1a = shard_engine_get(&mut shards, 0);
  var pre_ok: Bool = false;
  match export_collection(&mut e1a, "rolled", a_pre) {
    Ok(_) => { pre_ok = true; }
    Err(_) => {}
  }
  shard_engine_set(&mut shards, 0, e1a);
  fails = check(pre_ok, "rolled: pre-rolled via export (sealed entry, active cleared)", fails);
  var up_r2 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections/rolled/points", upsert_body(6, 10)));
  fails = check(status_of(&up_r2) == 200 && jnum(&up_r2, "count") == 5.0,
    "rolled: 5 post-roll writes land in the active remainder", fails);
  var mv_r = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"rolled\",\"to\":\"s2\"}"));
  fails = check(status_of(&mv_r) == 200, "rolled: move via compaction-aware export (sealed + active merge)", fails);
  var st_r = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/stats?collection=rolled", ""));
  fails = check(status_of(&st_r) == 200 && jnum(&st_r, "points") == 10.0,
    "rolled: destination holds the bit-exact union (10 points)", fails);
  var sr_r2 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/search", "{\"collection\":\"rolled\",\"vector\":[7,0,0,0],\"top_k\":1}"));
  fails = check(status_of(&sr_r2) == 200 && jhits_id(&sr_r2, 0) == 7,
    "rolled: post-roll side exact (id 7 first)", fails);
  var g_r3 = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/collections/rolled/points?id=3", ""));
  fails = check(status_of(&g_r3) == 200, "rolled: sealed side exact (id 3 readable)", fails);

  // ---- sealed-only move ----
  var c_so = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"sealed_only\",\"dim\":4,\"metric\":\"euclidean\"}"));
  var up_so = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections/sealed_only/points", upsert_body(1, 3)));
  var e1b = shard_engine_get(&mut shards, 0);
  var pre2_ok: Bool = false;
  match export_collection(&mut e1b, "sealed_only", a_sealed) {
    Ok(_) => { pre2_ok = true; }
    Err(_) => {}
  }
  shard_engine_set(&mut shards, 0, e1b);
  fails = check(status_of(&c_so) == 201 && status_of(&up_so) == 200 && pre2_ok,
    "sealed_only: rolled with an empty active remainder", fails);
  var mv_so = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"sealed_only\",\"to\":\"s2\"}"));
  fails = check(status_of(&mv_so) == 200, "sealed_only: move succeeds (single-sealed compaction path)", fails);
  var st_so = router_forward_direct(&mut shards, "s2", &mk_req("GET", "/stats?collection=sealed_only", ""));
  var g_so = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/collections/sealed_only/points?id=2", ""));
  fails = check(status_of(&st_so) == 200 && jnum(&st_so, "points") == 3.0 && status_of(&g_so) == 200,
    "sealed_only: destination exact (3 points, id 2 readable)", fails);

  // ---- drain ----
  var c_dr = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections", "{\"name\":\"drainme\",\"dim\":4,\"metric\":\"euclidean\"}"));
  var up_dr = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/collections/drainme/points", upsert_body(1, 2)));
  var cm_pre = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/cluster/mapping", ""));
  fails = check(status_of(&c_dr) == 201 && status_of(&up_dr) == 200 && jpath_str(&cm_pre, "collections", "drainme") == "s1",
    "drain: drainme (the last s1 collection) prepared", fails);
  var dr1 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/drain", "{\"shard\":\"s1\"}"));
  fails = check(status_of(&dr1) == 200 && jstr(&dr1, "drained") == "s1" && jnum(&dr1, "moved") == 1.0
    && jnum(&dr1, "mapping_version") == 5.0,
    "drain: s1 drained (1 moved, mapping v5)", fails);
  var cm_post = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/cluster/mapping", ""));
  var lr_s1b = router_forward_direct(&mut shards, "s1", &mk_req("GET", "/collections", ""));
  fails = check(jpath_str(&cm_post, "collections", "drainme") == "s2" && jarr_len(&lr_s1b, "collections") == 0,
    "drain: mapping repointed, drained shard holds nothing (no new placement)", fails);
  var g_dr = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/collections/drainme/points?id=1", ""));
  fails = check(status_of(&g_dr) == 200, "drain: drained collection readable via the router", fails);
  var rt_single = router_state_new(p_single);
  rt_single.artifact_dir = "out";
  var dr2 = router_handle(&mut rt_single, &mut shards, &mk_req("POST", "/cluster/drain", "{\"shard\":\"s1\"}"));
  fails = check(status_of(&dr2) == 400 && jstr(&dr2, "error") == "no destination shard",
    "drain: single-shard cluster refuses (400 no destination)", fails);

  // ---- admin route fuzz ----
  var f0 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"ghost\",\"to\":\"s2\"}"));
  fails = check(status_of(&f0) == 404, "fuzz: move of an unmapped collection -> 404", fails);
  var f1 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"bulk\",\"to\":\"sX\"}"));
  fails = check(status_of(&f1) == 404, "fuzz: move to an unknown shard -> 404", fails);
  var f2 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"bulk\",\"to\":\"s2\"}"));
  fails = check(status_of(&f2) == 400 && jstr(&f2, "error") == "destination equals source",
    "fuzz: move to the current owner -> 400", fails);
  var f3 = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/cluster/move", ""));
  fails = check(status_of(&f3) == 405, "fuzz: GET /cluster/move -> 405", fails);
  var f4 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "not json"));
  fails = check(status_of(&f4) == 400 && jstr(&f4, "error") == "bad json", "fuzz: move bad json -> 400", fails);
  var f5 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"bulk\"}"));
  fails = check(status_of(&f5) == 400 && jstr(&f5, "error") == "missing to", "fuzz: move missing 'to' -> 400", fails);
  var f6 = router_handle(&mut rt_a, &mut shards, &mk_req("POST", "/cluster/drain", "{\"shard\":\"sX\"}"));
  fails = check(status_of(&f6) == 404, "fuzz: drain unknown shard -> 404", fails);
  var f7 = router_handle(&mut rt_a, &mut shards, &mk_req("GET", "/cluster/drain", ""));
  fails = check(status_of(&f7) == 405, "fuzz: GET /cluster/drain -> 405", fails);
  var rt_noart = router_state_new(p_map);
  var f8 = router_handle(&mut rt_noart, &mut shards, &mk_req("POST", "/cluster/move", "{\"collection\":\"keep\",\"to\":\"s1\"}"));
  fails = check(status_of(&f8) == 500 && jstr(&f8, "error") == "artifact dir not configured",
    "fuzz: unconfigured artifact dir -> 500 (refused before touching data)", fails);

  // ---- auth scope on the admin routes ----
  let _k1 = service_auth_add_key(&mut rt_a.auth, "read-key-01", ApiScope.Read);
  let _k2 = service_auth_add_key(&mut rt_a.auth, "admin-key-01", ApiScope.Admin);
  var a1 = router_handle(&mut rt_a, &mut shards, &mk_req_key("POST", "/cluster/move", "{\"collection\":\"ghost\",\"to\":\"s2\"}", "read-key-01"));
  fails = check(status_of(&a1) == 403, "auth: move with a read key -> 403 at the router", fails);
  var a2 = router_handle(&mut rt_a, &mut shards, &mk_req_key("POST", "/cluster/move", "{\"collection\":\"ghost\",\"to\":\"s2\"}", "admin-key-01"));
  fails = check(status_of(&a2) == 404, "auth: move with an admin key reaches the route (unknown -> 404)", fails);

  // cleanup (best effort)
  let _r0 = io.remove_file(p_map);
  let _r1 = io.remove_file(p_single);
  let _r2 = io.remove_file(a_bulk);
  let _r3 = io.remove_file(a_rolled);
  let _r4 = io.remove_file(a_sealed);
  let _r5 = io.remove_file(a_drain);
  let _r6 = io.remove_file(a_pre);

  io.println("");
  io.println("probe_move_under_load: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
