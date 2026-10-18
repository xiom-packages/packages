// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fuzz probe (deterministic LCG): feeds random / mutated / truncated word
// streams to the payload codec, the HNSW graph codec, and WAL replay. The
// contract under fuzz: never crash; decode returns None or a value that
// satisfies its structural invariants; recovery keeps exactly the records
// that decode to valid same-dimension vectors/payloads. Exit = failed
// checks. (This probe found XVC-C-10: the inline pad loop in hnsw_decode
// segfaulted at larger m; see docs/repro/xv-decode-pad-loop/.)

module probe_fuzz_codecs

use xiom.vector.payload.payload;
use xiom.vector.index.hnsw;
use xiom.vector.durability.wal;
use xiom.vector.durability.recovery;
use xiom.vector.storage.vector_store;
use xiom.vector.query.search_service;
use xiom.vectors;
use xiom.io;

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

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn lcg_next(s: Int) -> Int {
  return (s * 1103515245 + 12345) % 2147483648;
}

fn main() -> Int {
  io.println("=== xvector probe: deterministic codec/WAL fuzz ===");
  var fails: Int = 0;
  var s: Int = 111;
  var it: Int = 0;

  // ---- Part A: payload_decode fuzz (random / mutated / truncated) ----
  var seed_p = payload_new();
  payload_set(&mut seed_p, "color", FieldValue.TextVal("red"));
  payload_set(&mut seed_p, "stock", FieldValue.IntVal(7));
  payload_set(&mut seed_p, "price", FieldValue.FloatVal(2.5));
  payload_set(&mut seed_p, "active", FieldValue.BoolVal(true));
  var pseed = payload_encode(&seed_p);
  var pay_none: Int = 0;
  var pay_some: Int = 0;
  var pay_bad: Int = 0;
  it = 0;
  while it < 400 {
    s = lcg_next(s);
    var mode = s % 3;
    var words = Vec[Int].new();
    if mode == 0 {
      s = lcg_next(s);
      var len = s % 33;
      var k = 0;
      while k < len {
        s = lcg_next(s);
        words.push(s % 1000);
        k = k + 1;
      }
    } elif mode == 1 {
      var k = 0;
      while k < pseed.len() {
        words.push(pseed[k]);
        k = k + 1;
      }
      s = lcg_next(s);
      var flips = 1 + (s % 3);
      var f = 0;
      while f < flips {
        s = lcg_next(s);
        if words.len() > 0 {
          var at = s % words.len();
          s = lcg_next(s);
          words[at] = s % 5000;
        }
        f = f + 1;
      }
    } else {
      s = lcg_next(s);
      var cut = s % (pseed.len() + 1);
      var k = 0;
      while k < cut {
        words.push(pseed[k]);
        k = k + 1;
      }
    }
    match payload_decode(&words) {
      Some(p) => {
        pay_some = pay_some + 1;
        var re = payload_encode(&p);
        match payload_decode(&re) {
          Some(p2) => {
            if payload_len(&p) != payload_len(&p2) { pay_bad = pay_bad + 1; }
          }
          None => { pay_bad = pay_bad + 1; }
        }
      }
      None => { pay_none = pay_none + 1; }
    }
    it = it + 1;
  }
  io.println("    diag payload fuzz: some=" + int_to_str(pay_some) + " none=" + int_to_str(pay_none)
    + " bad=" + int_to_str(pay_bad));
  fails = check(pay_none + pay_some == 400 && pay_bad == 0,
    "payload_decode fuzz: 400 inputs, no crash, re-encode stability holds", fails);

  // ---- Part B: hnsw_decode fuzz ----
  var gsmall = hnsw_new(4, 4.0);
  var i3: Int = 0;
  while i3 < 12 {
    var v3 = Vector.new(3);
    v3.set(0, (i3 % 5) as Float32);
    v3.set(1, (i3 % 3) as Float32);
    v3.set(2, ((i3 * 7) % 5) as Float32);
    hnsw_insert(&mut gsmall, i3 + 1, v3, DistanceMetric.Euclidean);
    i3 = i3 + 1;
  }
  var hseed = hnsw_encode(&gsmall);
  var hn_some: Int = 0;
  var hn_none: Int = 0;
  var hn_bad: Int = 0;
  it = 0;
  while it < 400 {
    s = lcg_next(s);
    var mode = s % 3;
    var words = Vec[Int].new();
    if mode == 0 {
      s = lcg_next(s);
      var len = s % 65;
      var k = 0;
      while k < len {
        s = lcg_next(s);
        words.push(s % 4000);
        k = k + 1;
      }
    } elif mode == 1 {
      var k = 0;
      while k < hseed.len() {
        words.push(hseed[k]);
        k = k + 1;
      }
      s = lcg_next(s);
      var flips = 1 + (s % 4);
      var f = 0;
      while f < flips {
        s = lcg_next(s);
        if words.len() > 0 {
          var at = s % words.len();
          s = lcg_next(s);
          words[at] = s % 8000;
        }
        f = f + 1;
      }
    } else {
      s = lcg_next(s);
      var cut = s % (hseed.len() + 1);
      var k = 0;
      while k < cut {
        words.push(hseed[k]);
        k = k + 1;
      }
    }
    match hnsw_decode(&words) {
      Some(g) => {
        hn_some = hn_some + 1;
        var cap = hnsw_layer_capacity();
        var okv: Bool = g.m > 0;
        if g.m0 < g.m || g.m0 > 1024 { okv = false; }
        if g.id_keys.len() != g.ids.len() { okv = false; }
        if g.id_vals.len() != g.ids.len() { okv = false; }
        if g.ids.len() > 0 {
          if g.entry < 0 || g.entry >= g.ids.len() { okv = false; }
        } else {
          if g.entry != -1 { okv = false; }
        }
        var n4: Int = 0;
        while n4 < g.ids.len() {
          var lv = g.levels[n4];
          if lv < 0 || lv >= cap { okv = false; }
          var l2: Int = 0;
          while l2 < cap {
            var row = n4 * cap + l2;
            var dg = g.deg[row];
            var dcap: Int = g.m;
            if l2 == 0 { dcap = g.m0; }
            if dg < 0 || dg > dcap { okv = false; }
            var sl: Int = 0;
            while sl < dg {
              var nb = g.adj[row * g.m0 + sl];
              if nb < 0 || nb >= g.ids.len() { okv = false; }
              sl = sl + 1;
            }
            l2 = l2 + 1;
          }
          n4 = n4 + 1;
        }
        var q3 = Vector.new(3);
        q3.set(0, 1.0);
        q3.set(1, 1.0);
        q3.set(2, 1.0);
        var rr = hnsw_search(&g, &q3, 3, 8, DistanceMetric.Euclidean);
        if rr.len() > 3 { okv = false; }
        if !okv { hn_bad = hn_bad + 1; }
      }
      None => { hn_none = hn_none + 1; }
    }
    it = it + 1;
  }
  io.println("    diag hnsw fuzz: some=" + int_to_str(hn_some) + " none=" + int_to_str(hn_none)
    + " bad=" + int_to_str(hn_bad));
  fails = check(hn_none + hn_some == 400 && hn_bad == 0,
    "hnsw_decode fuzz: 400 inputs, invariants hold on every Some", fails);

  // ---- Part C: WAL replay fuzz (valid / garbage inserts, updates, no-op deletes) ----
  var w = wal_writer_new();
  var expected: Int = 0;
  var expected_payloads: Int = 0;
  var n5: Int = 0;
  while n5 < 200 {
    s = lcg_next(s);
    var mode = s % 4;
    var key = n5 + 1;
    if mode == 0 {
      var v4 = Vector.new(4);
      v4.set(0, (n5 % 7) as Float32);
      v4.set(1, 0.5);
      v4.set(2, 1.5);
      v4.set(3, 2.5);
      var vw = vector_encode(&v4);
      wal_writer_append_payload(&mut w, WalOpKind.Insert, key, 0, vw);
      match vector_decode(&vw) {
        Some(dv) => { if dv.dimension == 4 { expected = expected + 1; } }
        None => {}
      }
    } elif mode == 1 {
      s = lcg_next(s);
      var len = 1 + (s % 8);
      var gw = Vec[Int].new();
      var k = 0;
      while k < len {
        s = lcg_next(s);
        gw.push(s % 100);
        k = k + 1;
      }
      wal_writer_append_payload(&mut w, WalOpKind.Insert, key, 0, gw);
      match vector_decode(&gw) {
        Some(dv2) => { if dv2.dimension == 4 { expected = expected + 1; } }
        None => {}
      }
    } elif mode == 2 {
      var pw = payload_encode(&seed_p);
      wal_writer_append_payload(&mut w, WalOpKind.Update, key, 0, pw);
      match payload_decode(&pw) {
        Some(_) => { expected_payloads = expected_payloads + 1; }
        None => {}
      }
    } else {
      wal_writer_append(&mut w, WalOpKind.Delete, 10000 + n5, 0);
    }
    n5 = n5 + 1;
  }
  var st = recover_state(&w, 4);
  fails = check(index_size(&st.store) == expected,
    "WAL fuzz: recovered size == records with valid dim-4 vectors", fails);
  var all_dim: Bool = true;
  var n6: Int = 0;
  while n6 < index_size(&st.store) {
    if st.store.vectors[n6].dimension != 4 { all_dim = false; }
    n6 = n6 + 1;
  }
  var q4 = Vector.new(4);
  q4.set(0, 1.0);
  q4.set(1, 0.0);
  q4.set(2, 0.0);
  q4.set(3, 0.0);
  var rr4 = search_knn(&st.store, &q4, 3, DistanceMetric.Euclidean);
  fails = check(all_dim && rr4.len() <= 3,
    "WAL fuzz: every recovered vector is dim 4, search bounded", fails);
  fails = check(payload_store_len(&st.payloads) == expected_payloads,
    "WAL fuzz: recovered payload count matches valid payload records", fails);
  var w2 = wal_writer_checkpoint_from(&w, &st.store, &st.payloads);
  var st2 = recover_state(&w2, 4);
  fails = check(index_size(&st2.store) == index_size(&st.store)
    && payload_store_len(&st2.payloads) == payload_store_len(&st.payloads),
    "WAL fuzz: chained checkpoint recovery preserves store + payloads", fails);

  io.println("");
  io.println("probe_fuzz_codecs: " + int_to_str(fails) + " failed checks");
  return fails;
}
