// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// L-4 probe (replica v1 -- WAL file-ship catch-up + manual promotion):
//   SHIP: the follower joins by shipping the leader's checkpoint +
//   segment (snapshot), continues delta-only (checkpoint unchanged),
//   re-snapshots after a leader checkpoint swap; the follower home
//   (`open_durable`) reads byte-equal to the leader (get/search).
//   LAG: `replica_lag_estimate` sees unsynced writes, the value rides
//   ServiceState.replica_lag into the /stats `replica_lag` field and the
//   `xvector_replica_lag` gauge, and returns to 0 after a ship; three
//   steady-state write+ship rounds all end at lag 0.
//   KILL + PROMOTION: the writer is "killed" (router points at an empty
//   node); the follower home reopens with every acked point; the mapping
//   flips docs -> replica (v2) and the stale router retries onto it
//   (one reload); post-promotion writes are acked on the promoted home
//   and survive a reopen (no live memory carried -- reads come from
//   files only).
//   FAILURE: a ship that cannot write the follower home reports
//   ok=false (never a partial home).
// Exit = failed checks.

module probe_replica

use xiom.vector.api.replica;
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

// ---- request builders / response extraction ----

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

fn contains_str(hay: Str, needle: Str) -> Bool {
  var h = slice.str_bytes(hay);
  var n = slice.str_bytes(needle);
  if n.len() == 0 || n.len() > h.len() { return false; }
  var i: Int = 0;
  while i + n.len() <= h.len() {
    var match_here: Bool = true;
    var j: Int = 0;
    while j < n.len() {
      if h[i + j] != n[j] { match_here = false; j = n.len(); } else { j = j + 1; }
    }
    if match_here { return true; }
    i = i + 1;
  }
  return false;
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

fn mapping_text(ver: Int, target: Str) -> Str {
  return "{\"version\":" + convert.int_to_string(ver)
    + ",\"shards\":[{\"id\":\"s1\",\"url\":\"http://127.0.0.1:7711\"},{\"id\":\"s1r\",\"url\":\"http://127.0.0.1:7712\"}],\"collections\":{\"docs\":\"" + target + "\"}}";
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

fn main() -> Int {
  io.println("=== xvector probe: replica v1 (L-4) ===");
  var fails: Int = 0;

  var p_lckpt = "out/repl_leader.db";
  var p_lseg = "out/repl_leader.db.seg";
  var p_fckpt = "out/repl_follower.db";
  var p_fseg = "out/repl_follower.db.seg";
  var p_map = "out/repl_mapping.json";
  let _c0 = io.remove_file(p_lckpt);
  let _c1 = io.remove_file(p_lseg);
  let _c2 = io.remove_file(p_fckpt);
  let _c3 = io.remove_file(p_fseg);
  let _c4 = io.remove_file(p_map);
  let _c5 = io.remove_file(p_fckpt + ".ack");
  let _c6 = io.remove_file(p_fckpt + ".ack.tmp");
  let _w0 = write_text(p_map, mapping_text(1, "s1"));

  var st_l = service_state_new();
  var eng_l = open_durable(p_lckpt, p_lseg, "", 4, DistanceMetric.Euclidean);
  fails = check(status_of(&http_service_handle_state(&mut eng_l, &mk_req("GET", "/collections", ""), &mut st_l)) == 200,
    "leader: durable home opens (empty)", fails);
  var c_docs = http_service_handle_state(&mut eng_l, &mk_req("POST", "/collections", "{\"name\":\"docs\",\"dim\":4,\"metric\":\"euclidean\"}"), &mut st_l);
  var up1 = http_service_handle_state(&mut eng_l, &mk_req("POST", "/collections/docs/points", upsert_body(1, 10)), &mut st_l);
  fails = check(status_of(&c_docs) == 201 && status_of(&up1) == 200 && jnum(&up1, "count") == 10.0,
    "leader: docs created + 10 acked writes (durable segment)", fails);
  var swap1: Bool = false;
  match checkpoint_swap(&mut eng_l) {
    Ok(_) => { swap1 = true; }
    Err(_) => {}
  }
  fails = check(swap1, "leader: checkpoint swap #1 (segment rotates)", fails);

  // ---- join: snapshot ship ----
  var r1 = replica_ship(p_lckpt, p_lseg, p_fckpt, p_fseg);
  fails = check(r1.ok && r1.snapshot && r1.frontier > 0 && r1.ckpt_bytes > 0,
    "join: snapshot ship (checkpoint + segment copied)", fails);
  fails = check(replica_lag_estimate(p_lckpt, p_lseg, p_fckpt) == 0,
    "join: frontier acked (lag 0)", fails);
  var eng_f = open_durable(p_fckpt, p_fseg, "", 4, DistanceMetric.Euclidean);
  var st_f = service_state_new();
  var rq1 = mk_req("GET", "/collections/docs/points?id=5", "");
  var a1 = http_service_handle_state(&mut eng_l, &rq1, &mut st_l);
  var b1 = http_service_handle_state(&mut eng_f, &rq1, &mut st_f);
  fails = check(status_of(&a1) == 200 && resp_body(&a1) == resp_body(&b1),
    "join: get id=5 follower home == leader (byte-equal)", fails);
  var sq = mk_req("POST", "/search", "{\"collection\":\"docs\",\"vector\":[7,0,0,0],\"top_k\":2}");
  var a2 = http_service_handle_state(&mut eng_l, &sq, &mut st_l);
  var b2 = http_service_handle_state(&mut eng_f, &sq, &mut st_f);
  fails = check(status_of(&a2) == 200 && resp_body(&a2) == resp_body(&b2),
    "join: search follower home == leader (byte-equal)", fails);

  // ---- delta ship: leader advances without a swap ----
  var up2 = http_service_handle_state(&mut eng_l, &mk_req("POST", "/collections/docs/points", upsert_body(11, 20)), &mut st_l);
  fails = check(status_of(&up2) == 200 && jnum(&up2, "count") == 10.0, "tail: leader writes 11..20", fails);
  var r2 = replica_ship(p_lckpt, p_lseg, p_fckpt, p_fseg);
  fails = check(r2.ok && !r2.snapshot && r2.seg_bytes > 0 && r2.frontier > r1.frontier,
    "tail: delta-only ship (checkpoint unchanged)", fails);
  var eng_f2 = open_durable(p_fckpt, p_fseg, "", 4, DistanceMetric.Euclidean);
  var st_f2 = service_state_new();
  var g15 = http_service_handle_state(&mut eng_f2, &mk_req("GET", "/collections/docs/points?id=15", ""), &mut st_f2);
  fails = check(status_of(&g15) == 200, "tail: follower home serves id=15 after the delta", fails);

  // ---- second swap: snapshot again ----
  var swap2: Bool = false;
  match checkpoint_swap(&mut eng_l) {
    Ok(_) => { swap2 = true; }
    Err(_) => {}
  }
  var r3 = replica_ship(p_lckpt, p_lseg, p_fckpt, p_fseg);
  fails = check(swap2 && r3.ok && r3.snapshot && r3.ckpt_bytes > 0,
    "swap #2: checkpoint size changed -> re-snapshot ship", fails);

  // ---- lag visibility before/after a ship ----
  var up3 = http_service_handle_state(&mut eng_l, &mk_req("POST", "/collections/docs/points", upsert_body(21, 30)), &mut st_l);
  fails = check(status_of(&up3) == 200 && jnum(&up3, "count") == 10.0, "lag: leader writes 21..30 unsynced", fails);
  var expected_lag = replica_lag_estimate(p_lckpt, p_lseg, p_fckpt);
  fails = check(expected_lag > 0, "lag: estimate sees the unsynced writes", fails);
  var eng_f4 = open_durable(p_fckpt, p_fseg, "", 4, DistanceMetric.Euclidean);
  var st_f4 = service_state_new();
  st_f4.replica_lag = expected_lag;
  var lp = http_service_handle_state(&mut eng_f4, &mk_req("GET", "/stats?collection=docs", ""), &mut st_f4);
  fails = check(status_of(&lp) == 200 && jnum(&lp, "replica_lag") == expected_lag as Float64,
    "lag: /stats surfaces the pre-ship replica_lag", fails);
  var mp = http_service_handle_state(&mut eng_f4, &mk_req("GET", "/metrics", ""), &mut st_f4);
  fails = check(status_of(&mp) == 200 && contains_str(resp_body(&mp), "xvector_replica_lag"),
    "lag: /metrics carries the xvector_replica_lag gauge", fails);
  var r4 = replica_ship(p_lckpt, p_lseg, p_fckpt, p_fseg);
  fails = check(r4.ok && replica_lag_estimate(p_lckpt, p_lseg, p_fckpt) == 0,
    "lag: ship returns the estimate to 0", fails);

  // ---- steady state: three rounds, every one ends at lag 0 ----
  var steady_ok: Bool = true;
  var rounds: Int = 0;
  while rounds < 3 {
    var rid = 101 + rounds;
    var uw = http_service_handle_state(&mut eng_l, &mk_req("POST", "/collections/docs/points", upsert_body(rid, rid)), &mut st_l);
    if status_of(&uw) != 200 { steady_ok = false; }
    var rr = replica_ship(p_lckpt, p_lseg, p_fckpt, p_fseg);
    if !rr.ok || replica_lag_estimate(p_lckpt, p_lseg, p_fckpt) != 0 { steady_ok = false; }
    rounds = rounds + 1;
  }
  fails = check(steady_ok, "steady: three write+ship rounds all end at lag 0", fails);

  // ---- kill the writer + promotion ----
  var eng_p = open_durable(p_fckpt, p_fseg, "", 4, DistanceMetric.Euclidean);
  var st_p = service_state_new();
  var sweep_a: Int = 0;
  var k: Int = 1;
  while k <= 30 {
    var gg = http_service_handle_state(&mut eng_p, &mk_req("GET", "/collections/docs/points?id=" + convert.int_to_string(k), ""), &mut st_p);
    if status_of(&gg) == 200 { sweep_a = sweep_a + 1; }
    k = k + 1;
  }
  k = 101;
  while k <= 103 {
    var gg2 = http_service_handle_state(&mut eng_p, &mk_req("GET", "/collections/docs/points?id=" + convert.int_to_string(k), ""), &mut st_p);
    if status_of(&gg2) == 200 { sweep_a = sweep_a + 1; }
    k = k + 1;
  }
  fails = check(sweep_a == 33, "kill: follower home reopens with every acked id (1..30 + 101..103)", fails);

  var shards = Vec[RouterShard].new();
  var e_dead = engine_new();
  var e_rep = eng_p;
  var s_dead = service_state_new();
  var s_rep = service_state_new();
  shards.push(RouterShard{ id: "s1", engine: e_dead, state: s_dead });
  shards.push(RouterShard{ id: "s1r", engine: e_rep, state: s_rep });
  var rt = router_state_new(p_map);
  fails = check(rt.ok && rt.mapping.version == 1, "promotion: router cached on v1 (docs -> s1, dead)", fails);
  let _w1 = write_text(p_map, mapping_text(2, "s1r"));
  var promo_raw = mk_req("GET", "/collections/docs/points?id=1", "");
  var promo = router_handle(&mut rt, &mut shards, &promo_raw);
  var promo_d = router_forward_direct(&mut shards, "s1r", &promo_raw);
  fails = check(status_of(&promo) == 200 && resp_body(&promo) == resp_body(&promo_d),
    "promotion: stale router 404 -> reload v2 -> retry replica (byte-equal)", fails);
  fails = check(rt.reloads == 1 && rt.mapping.version == 2, "promotion: mapping flipped to s1r (v2)", fails);

  // ---- post-promotion writes + a second kill (reopen from files) ----
  var pw = router_handle(&mut rt, &mut shards, &mk_req("POST", "/collections/docs/points", upsert_body(41, 45)));
  fails = check(status_of(&pw) == 200 && jnum(&pw, "count") == 5.0, "promotion: 5 writes acked on the promoted node", fails);
  var eng_p2 = open_durable(p_fckpt, p_fseg, "", 4, DistanceMetric.Euclidean);
  var st_p2 = service_state_new();
  var sweep_b: Int = 0;
  k = 41;
  while k <= 45 {
    var g2 = http_service_handle_state(&mut eng_p2, &mk_req("GET", "/collections/docs/points?id=" + convert.int_to_string(k), ""), &mut st_p2);
    if status_of(&g2) == 200 { sweep_b = sweep_b + 1; }
    k = k + 1;
  }
  var gfirst = http_service_handle_state(&mut eng_p2, &mk_req("GET", "/collections/docs/points?id=1", ""), &mut st_p2);
  fails = check(sweep_b == 5 && status_of(&gfirst) == 200,
    "kill x2: acked post-promotion writes survive a reopen (files only)", fails);

  // ---- failure path: unwritable follower home ----
  var rbad = replica_ship(p_lckpt, p_lseg, "out/no_such_dir/repl.db", "out/no_such_dir/repl.db.seg");
  fails = check(!rbad.ok && rbad.err.len() > 0, "failure: unwritable follower home -> ok=false", fails);

  // cleanup (best effort)
  let _r0 = io.remove_file(p_lckpt);
  let _r1 = io.remove_file(p_lseg);
  let _r2 = io.remove_file(p_fckpt);
  let _r3 = io.remove_file(p_fseg);
  let _r4 = io.remove_file(p_map);
  let _r5 = io.remove_file(p_fckpt + ".ack");
  let _r6 = io.remove_file(p_fckpt + ".ack.tmp");

  io.println("");
  io.println("probe_replica: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
