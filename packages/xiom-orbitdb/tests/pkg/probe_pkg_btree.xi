// XIOM ORBITDB consumer probe -- xiom.btree 0.1.1 (registry, eco-v0.1.141).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Two-way consumer pass for the re-extracted B-tree (our order-3 fix,
// upstream commit c017165, published as 5be4adeb / xiom.btree 0.1.1, sha256
// ba4b1782...). Checks:
//   1. package basics: insert/search/size/min/max/range/delete/to_vec;
//   2. the order-3 regression reproducer verbatim: keyspace 16, seed 777,
//      2000 ops vs an independent model (pre-fix first divergence op 67);
//   3. empty-terminal-leaf edges: min/max None after deleting everything,
//      reuse afterwards (the old btree_min/max OOB class);
//   4. final-state digest printed for the dual-stream check: the IDENTICAL
//      stream runs through ORBITDB's own engine in probe_pkg_btree_engine.xi
//      (same seed/keyspace/op count) and must print the same key order and
//      values;
//   5. seeded churn at orders 4/5/6 vs the model (matrix re-expansion).
//
// NOTE (2026-10-12): the two modules CANNOT be imported into ONE program --
// `xiom.btree` and `xiom.db.engine` both export BTreeNode/NodeStore/BTree and
// the composed catalog fails codegen with unresolved method symbols on the
// wrong same-named struct type (bundle docs/repro/same-named-struct-compose/,
// bus item filed). Hence the two-program digest equality.
//
// Composition: tests/pkg/xiom.toml (this dir + ../../src + registry
// dependency xiom.btree = 0.1.1).
// Env: ORBITDB_PKG_BTREE -- unused; kept for symmetry. Exit: 0 = all checks,
// 1 = failed.

module orbitdb_probe_pkg_btree

use xiom.io;
use xiom.convert;
use xiom.btree;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name);
  return fails + 1;
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

// Model lookup table: slot k holds key k's value, -1 = absent.
fn model_new(n: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  var i = 0;
  while i <= n {
    m.push(-1);
    i = i + 1;
  }
  return m;
}

// Expected VALUES for keys [1, n] in key order, from a model table.
fn model_expected(m: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < m.len() {
    if m[i] >= 0 { out.push(m[i]); }
    i = i + 1;
  }
  return out;
}

fn run_basics() -> Int {
  var fails = 0;
  var t = btree_new(4);
  var i = 1;
  while i <= 20 {
    if !btree_insert(&mut t, i, i * 100) { return fails + 1; }
    i = i + 1;
  }
  fails = check(btree_size(&t) == 20, "pkg: size 20 after inserts", fails);
  match btree_search(&t, 7) {
    None => { fails = check(false, "pkg: search hit 7", fails); }
    Some(v) => { fails = check(v == 700, "pkg: search hit 7", fails); }
  }
  match btree_min(&t) {
    None => { fails = check(false, "pkg: min is 1", fails); }
    Some(v) => { fails = check(v == 100, "pkg: min is 1", fails); }
  }
  match btree_max(&t) {
    None => { fails = check(false, "pkg: max is 20", fails); }
    Some(v) => { fails = check(v == 2000, "pkg: max is 20", fails); }
  }
  let r = btree_range_query(&t, 5, 9);
  fails = check(r.len() == 5 && r[0] == 500 && r[4] == 900, "pkg: inclusive range 5..9", fails);
  fails = check(btree_delete(&mut t, 10), "pkg: delete 10", fails);
  fails = check(!btree_delete(&mut t, 10), "pkg: second delete 10 refuses", fails);
  match btree_search(&t, 10) {
    None => { fails = check(true, "pkg: 10 gone", fails); }
    Some(_) => { fails = check(false, "pkg: 10 gone", fails); }
  }
  let all = btree_to_vec(&t);
  fails = check(all.len() == 19 && all[0] == 100 && all[18] == 2000, "pkg: to_vec in order, 19 keys", fails);
  return fails;
}

fn run_order3_reproducer() -> Int {
  var fails = 0;
  var t = btree_new(3);
  var m = model_new(16);
  var r = 777;
  var op = 0;
  while op < 2000 {
    r = (r * 1103515245 + 12345) % 2147483648;
    let key = (r % 16) + 1;
    let roll = (r / 16) % 4;
    if roll == 0 {
      let _ = btree_delete(&mut t, key);
      m[key] = -1;
    } else {
      let v = r % 1000;
      // Contract: btree_insert REFUSES an existing key (no upsert); the
      // model only follows successful inserts.
      let ok = btree_insert(&mut t, key, v);
      if ok { m[key] = v; }
    }
    if !vec_eq(&btree_to_vec(&t), &model_expected(&m)) {
      io.println("  [INFO] order-3 divergence at op=" + convert.int_to_string(op));
      return fails + 1;
    }
    op = op + 1;
  }
  fails = check(btree_size(&t) == model_expected(&m).len(), "pkg: order-3 reproducer final size", fails);
  io.println("pkg-btree digest: " + digest(&btree_to_vec(&t)));
  return fails;
}

fn run_empty_leaf_edges() -> Int {
  var fails = 0;
  var t = btree_new(3);
  var i = 1;
  while i <= 8 {
    let _ = btree_insert(&mut t, i, i);
    i = i + 1;
  }
  i = 1;
  while i <= 8 {
    let _ = btree_delete(&mut t, i);
    i = i + 1;
  }
  match btree_min(&t) {
    None => { fails = check(true, "pkg: min None on emptied tree", fails); }
    Some(_) => { fails = check(false, "pkg: min None on emptied tree", fails); }
  }
  match btree_max(&t) {
    None => { fails = check(true, "pkg: max None on emptied tree", fails); }
    Some(_) => { fails = check(false, "pkg: max None on emptied tree", fails); }
  }
  fails = check(btree_size(&t) == 0, "pkg: size 0 after full delete", fails);
  let _ = btree_insert(&mut t, 42, 4200);
  match btree_search(&t, 42) {
    None => { fails = check(false, "pkg: reuse after empty", fails); }
    Some(v) => { fails = check(v == 4200, "pkg: reuse after empty", fails); }
  }
  return fails;
}

// Final key-order + values digest for the two-program dual-stream check.
fn digest(v: &Vec[Int]) -> Str {
  var s = "";
  var i = 0;
  while i < v.len() {
    if i > 0 { s = s + ","; }
    s = s + convert.int_to_string(v[i]);
    i = i + 1;
  }
  return s;
}

fn run_orders_matrix() -> Int {
  var fails = 0;
  var order = 4;
  while order <= 6 {
    var t = btree_new(order);
    var m = model_new(64);
    var r = 1000 + order;
    var op = 0;
    while op < 1000 {
      r = (r * 1103515245 + 12345) % 2147483648;
      let key = (r % 64) + 1;
      let roll = (r / 64) % 4;
      if roll == 0 {
        let _ = btree_delete(&mut t, key);
        m[key] = -1;
      } else {
        let v = r % 700;
        let ok = btree_insert(&mut t, key, v);
        if ok { m[key] = v; }
      }
      op = op + 1;
    }
    fails = check(vec_eq(&btree_to_vec(&t), &model_expected(&m)),
                  "pkg: order " + convert.int_to_string(order) + " churn == model", fails);
    order = order + 1;
  }
  return fails;
}

fn main() -> Int {
  io.println("pkg-btree probe: xiom.btree 0.1.1 two-way consumer pass");
  var fails: Int = 0;
  fails = fails + run_basics();
  fails = fails + run_order3_reproducer();
  fails = fails + run_empty_leaf_edges();
  fails = fails + run_orders_matrix();
  if fails == 0 { io.println("pkg-btree: GREEN"); return 0; }
  io.println("pkg-btree: RED fails=" + convert.int_to_string(fails));
  return 1;
}
