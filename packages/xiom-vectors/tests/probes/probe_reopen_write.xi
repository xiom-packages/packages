// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Reopen-write regression (found by L-4 probe_replica's promotion leg):
// a durable home that is REOPENED and then written must keep those
// writes across the next reopen. The first cut failed because
// engine_enable_durable adopted max(segment file frontier, in-memory
// log current LSN) as the durable frontier -- after engine_recover
// renumbers the checkpoint records upward, the in-memory cursor sits
// ABOVE the file, so the first commit skipped the whole renumbered
// block and appended beyond it: the segment developed a gap and the
// next merge stopped there (post-reopen writes lost).
//
// Scenario: create -> 5 writes -> checkpoint swap (normalized home) ->
// 3 writes (session 1) -> REOPEN (session 2) -> 1 write -> REOPEN
// (session 3): every acked id must be readable, ids 1..8 (sessions 1)
// and id 9 (the post-reopen write).
// Exit = failed checks.

module probe_reopen_write

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vector.api.http_service;
use xiom.serialize.json;
use xiom.string.slice;
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

fn status_of(resp: &Vec[UInt8]) -> Int {
  if resp.len() < 12 { return -1; }
  var d1 = (resp[9] as Int) - 48;
  var d2 = (resp[10] as Int) - 48;
  var d3 = (resp[11] as Int) - 48;
  if d1 < 0 || d1 > 9 || d2 < 0 || d2 > 9 || d3 < 0 || d3 > 9 { return -1; }
  return d1 * 100 + d2 * 10 + d3;
}

fn jnum(resp: &Vec[UInt8], key: Str) -> Float64 {
  var t = -1;
  var i: Int = 0;
  while i + 3 < resp.len() {
    if resp[i] == 13 && resp[i + 1] == 10 && resp[i + 2] == 13 && resp[i + 3] == 10 { t = i; i = resp.len(); } else { i = i + 1; }
  }
  if t < 0 { return -999999.0; }
  var acc = Vec[UInt8].new();
  var j: Int = t + 4;
  while j < resp.len() {
    acc.push(resp[j]);
    j = j + 1;
  }
  var parsed = json.json_parse(Str::from_utf8(&acc));
  var doc = json.json_null();
  match parsed {
    Ok(v) => { doc = v; }
    Err(_) => { return -999999.0; }
  }
  var f = json.json_get(doc, key);
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
  io.println("=== xvector probe: reopen-then-write durability ===");
  var fails: Int = 0;
  var p_ck = "out/reopen_write.db";
  var p_sg = "out/reopen_write.db.seg";
  let _c0 = io.remove_file(p_ck);
  let _c1 = io.remove_file(p_sg);

  var st1 = service_state_new();
  var eng1 = open_durable(p_ck, p_sg, "", 4, DistanceMetric.Euclidean);
  let _cr = http_service_handle_state(&mut eng1, &mk_req("POST", "/collections", "{\"name\":\"docs\",\"dim\":4,\"metric\":\"euclidean\"}"), &mut st1);
  let _u1 = http_service_handle_state(&mut eng1, &mk_req("POST", "/collections/docs/points", upsert_body(1, 5)), &mut st1);
  var sw1: Bool = false;
  match checkpoint_swap(&mut eng1) {
    Ok(_) => { sw1 = true; }
    Err(_) => {}
  }
  fails = check(sw1, "session 1: home normalized (swap -> ckpt + empty segment)", fails);
  var u2 = http_service_handle_state(&mut eng1, &mk_req("POST", "/collections/docs/points", upsert_body(6, 8)), &mut st1);
  fails = check(status_of(&u2) == 200, "session 1: 3 post-swap acked writes", fails);

  // Restart 1: reopen the same home and write.
  var st2 = service_state_new();
  var eng2 = open_durable(p_ck, p_sg, "", 4, DistanceMetric.Euclidean);
  var ctl8 = http_service_handle_state(&mut eng2, &mk_req("GET", "/collections/docs/points?id=8", ""), &mut st2);
  fails = check(status_of(&ctl8) == 200, "session 2: pre-restart write (id 8) visible after reopen", fails);
  var u3 = http_service_handle_state(&mut eng2, &mk_req("POST", "/collections/docs/points", upsert_body(9, 9)), &mut st2);
  fails = check(status_of(&u3) == 200 && jnum(&u3, "count") == 1.0, "session 2: post-reopen write (id 9) acked", fails);

  // Restart 2: the post-reopen write must survive.
  var st3 = service_state_new();
  var eng3 = open_durable(p_ck, p_sg, "", 4, DistanceMetric.Euclidean);
  var g9 = http_service_handle_state(&mut eng3, &mk_req("GET", "/collections/docs/points?id=9", ""), &mut st3);
  fails = check(status_of(&g9) == 200, "session 3: post-reopen write (id 9) survives the reopen", fails);
  var live: Int = 0;
  var i: Int = 1;
  while i <= 8 {
    var gg = http_service_handle_state(&mut eng3, &mk_req("GET", "/collections/docs/points?id=" + convert.int_to_string(i), ""), &mut st3);
    if status_of(&gg) == 200 { live = live + 1; }
    i = i + 1;
  }
  fails = check(live == 8, "session 3: every acked id (1..8) still live", fails);

  let _r0 = io.remove_file(p_ck);
  let _r1 = io.remove_file(p_sg);

  io.println("");
  io.println("probe_reopen_write: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
