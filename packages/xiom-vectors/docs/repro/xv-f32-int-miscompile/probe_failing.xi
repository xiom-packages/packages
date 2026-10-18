// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Critical-primitive probe (bootstrap gate): durable vector store lifecycle
// on the REAL engine module (src/engine.xi, imported via xiom.toml roots):
//   create -> write (WAL payload) -> search -> reopen/recover -> search
//   identical -> delete -> reopen again -> delete stays gone -> LSN
//   continuity. Exit code = number of failed checks (0 = green).

module probe_failing

use xiom.vector.engine;
use xiom.vector.engine.core;
use xiom.vectors;
use xiom.vector.query.search_service;
use xiom.io;
use xiom.num.float;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = ""; var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  if neg { out = "-" + out; }
  return out;
}

fn mk_vec3(a: Float32, b: Float32, c: Float32) -> Vector {
  var v = Vector.new(3);
  v.set(0, a); v.set(1, b); v.set(2, c);
  return v;
}

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn f32_approx(a: Float32, b: Float32, eps: Float32) -> Bool {
  var diff = a - b;
  if diff < 0.0 { diff = -diff; }
  return diff < eps;
}

fn main() -> Int {
  io.println("=== xvector critical-primitive probe: durable lifecycle ===");
  var fails: Int = 0;

  // 1. create
  var eng = engine_new();
  var cid = create_collection(&mut eng, 3, DistanceMetric.Cosine);
  match cid {
    Ok(_) => { fails = check(true, "create_collection(3, Cosine)", fails); }
    Err(_) => { fails = check(false, "create_collection(3, Cosine)", fails); }
  }

  // 2. write (WAL-before-ack; payload-encoded vectors)
  var w1 = upsert(&mut eng, 1, mk_vec3(1.0, 0.0, 0.0));
  var w2 = upsert(&mut eng, 2, mk_vec3(0.9, 0.1, 0.0));
  var w3 = upsert(&mut eng, 3, mk_vec3(0.0, 0.0, 1.0));
  var wrote: Bool = false;
  match w1 { Ok(ok) => { wrote = ok; } Err(_) => {} }
  match w2 { Ok(ok) => { wrote = wrote && ok; } Err(_) => {} }
  match w3 { Ok(ok) => { wrote = wrote && ok; } Err(_) => {} }
  fails = check(wrote && engine_size(&eng) == 3, "upsert x3 (WAL payload, size=3)", fails);

  // 3. search before reopen
  var query = mk_vec3(1.0, 0.0, 0.0);
  match get_point(&eng, 2) {
    Some(p2) => {
      io.println("    diag p2 bits=" + int_to_str(float.float_bits(p2.data[0] as Float64)) + "," +
                 int_to_str(float.float_bits(p2.data[1] as Float64)) + "," +
                 int_to_str(float.float_bits(p2.data[2] as Float64)));
      io.println("    diag p2 dot=" + int_to_str(float.float_bits(vector_dot(&p2, &query) as Float64)) +
                 " cos=" + int_to_str(float.float_bits(cosine_distance(&p2, &query) as Float64)));
      var local = mk_vec3(0.9, 0.1, 0.0);
      io.println("    diag local dot=" + int_to_str(float.float_bits(vector_dot(&local, &query) as Float64)) +
                 " cos=" + int_to_str(float.float_bits(cosine_distance(&local, &query) as Float64)));
    }
    None => { io.println("    diag p2 missing"); }
  }
  var before = Vec[SearchResult].new();
  var before_ok: Bool = false;
  match search(&eng, &query, 2) {
    Ok(h) => { before = h.items; }
    Err(_) => {}
  }
  before_ok = before.len() == 2 && before[0].id == 1 && before[1].id == 2
    && f32_approx(before[0].distance, 0.0, 0.001) && f32_approx(before[1].distance, 0.00614, 0.001);
  io.println("    diag before len=" + int_to_str(before.len()) +
             " id0=" + int_to_str(before[0].id) + " id1=" + int_to_str(before[1].id) +
             " d0_bits=" + int_to_str(float.float_bits(before[0].distance as Float64)) +
             " d1_bits=" + int_to_str(float.float_bits(before[1].distance as Float64)));
  fails = check(before_ok, "search top-2 -> {1, 2} with distances", fails);
  let lsn_before = engine_durable_lsn(&eng);

  // 4. reopen/recover from the WAL
  var recovered = engine_recover(&eng.wal, 3, DistanceMetric.Cosine);
  fails = check(engine_size(&recovered) == 3, "reopen: store rebuilt from WAL (size=3)", fails);
  fails = check(engine_durable_lsn(&recovered) >= lsn_before, "reopen: LSN monotonic", fails);

  // 5. search after reopen identical
  var after = Vec[SearchResult].new();
  match search(&recovered, &query, 2) {
    Ok(h) => { after = h.items; }
    Err(_) => {}
  }
  var after_ok: Bool = after.len() == 2 && after[0].id == 1 && after[1].id == 2
    && f32_approx(after[0].distance, 0.0, 0.001) && f32_approx(after[1].distance, 0.00614, 0.001);
  fails = check(after_ok, "reopen: search identical {1, 2} with distances", fails);

  // 6. delete after reopen, then reopen AGAIN: delete must persist in the WAL
  var del = delete_point(&mut recovered, 1);
  var del_ok: Bool = false;
  match del { Ok(ok) => { del_ok = ok; } Err(_) => {} }
  fails = check(del_ok && engine_size(&recovered) == 2, "delete point 1 after reopen (size=2)", fails);

  var reopened2 = engine_recover(&recovered.wal, 3, DistanceMetric.Cosine);
  var gone: Bool = true;
  match get_point(&reopened2, 1) { Some(_) => { gone = false; } None => {} }
  io.println("    diag: reopened2 size=" + int_to_str(engine_size(&reopened2)) +
             " point1_gone=" + (if gone { "true" } else { "false" }));
  fails = check(gone && engine_size(&reopened2) == 2, "second reopen: delete still applied", fails);

  // 7. post-reopen writes continue the LSN sequence
  let lsn_before_w4 = engine_durable_lsn(&reopened2);
  var w4 = upsert(&mut reopened2, 4, mk_vec3(0.0, 1.0, 0.0));
  var w4_ok: Bool = false;
  match w4 { Ok(ok) => { w4_ok = ok; } Err(_) => {} }
  io.println("    diag: after upsert size=" + int_to_str(engine_size(&reopened2)) +
             " lsn=" + int_to_str(engine_durable_lsn(&reopened2)));
  fails = check(w4_ok && engine_size(&reopened2) == 3, "post-reopen write accepted (size=3)", fails);
  fails = check(engine_durable_lsn(&reopened2) == lsn_before_w4 + 1, "post-reopen write advances LSN by 1", fails);

  io.println("");
  io.println("probe_vector_store: " + int_to_str(fails) + " failed checks");
  return fails;
}
