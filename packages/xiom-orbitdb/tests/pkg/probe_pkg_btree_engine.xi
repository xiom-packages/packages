// XIOM ORBITDB engine-side companion for the xiom.btree 0.1.1 two-way pass.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The IDENTICAL stream to probe_pkg_btree.xi (order 3, keyspace 16, seed 777,
// 2000 ops, same LCG) driven through ORBITDB's own B-tree. Both programs
// print `pkg-btree digest: <values in key order>`; the two digests being
// equal (and both equal to the independent model) is the dual-stream
// equivalence -- they cannot be imported into one program because both
// modules export BTreeNode/NodeStore/BTree (docs/repro/same-named-struct-compose/).
//
// Exit: 0 = digest == model, 1 = mismatch.

module orbitdb_probe_pkg_btree_engine

use xiom.io;
use xiom.convert;
use xiom.db.engine;

fn model_new(n: Int) -> Vec[Int] {
  var m = Vec[Int].new();
  var i = 0;
  while i <= n {
    m.push(-1);
    i = i + 1;
  }
  return m;
}

fn model_expected(m: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 1;
  while i < m.len() {
    if m[i] >= 0 { out.push(m[i]); }
    i = i + 1;
  }
  return out;
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

fn main() -> Int {
  io.println("pkg-btree engine companion: identical stream through xiom.db.engine");
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
      // Contract: btree_insert REFUSES an existing key (no upsert).
      let ok = btree_insert(&mut t, key, v);
      if ok { m[key] = v; }
    }
    op = op + 1;
  }
  let got = btree_to_vec(&t);
  let want = model_expected(&m);
  io.println("pkg-btree digest: " + digest(&got));
  if vec_eq(&got, &want) {
    io.println("pkg-btree engine: GREEN");
    return 0;
  }
  io.println("pkg-btree engine: RED");
  return 1;
}
