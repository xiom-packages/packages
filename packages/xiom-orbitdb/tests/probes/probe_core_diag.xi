// XIOM ORBITDB -- core diagnostics probe (bootstrap triage).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Prints internals of the BufferPool and B-tree to localize the 5 suite
// failures found on v0.64.0 (buffer_pool put/get, storage_engine
// cache/lookup, btree large insert, query value-vs-key semantics).

module orbitdb_probe_core_diag

use xiom.io;
use xiom.convert;
use xiom.db.engine;
use xiom.db.storage.page;

fn show(label: Str, n: Int) {
  io.println(label + "=" + convert.int_to_string(n));
}

fn main() -> Int {
  // --- BufferPool put/get (frame table + clock) --------------------------
  var bp = BufferPool.new(4);
  var data = Vec[Int].new();
  data.push(42);
  var cs = page_compute_checksum(&data);
  let page = Page.new(7, data, cs);
  if !bp.put(page) { io.println("bp.put(7)=false"); }
  show("bp.capacity", bp.capacity);
  show("bp.hits", bp.hits);
  show("bp.misses", bp.misses);
  var f = 0;
  while f < bp.capacity {
    if bp.present[f] { show("bp.frame_id", bp.frame_ids[f]); }
    f = f + 1;
  }
  let found = bp.get(7);
  match found {
    None => { io.println("bp.get(7)=None"); }
    Some(p) => { show("bp.get(7).id", p.id); }
  }
  let found2 = BufferPool.get(&mut bp, 7);
  match found2 {
    None => { io.println("BufferPool.get(&mut bp,7)=None"); }
    Some(p) => { show("BufferPool.get(&mut bp,7).id", p.id); }
  }

  // --- B-tree large insert -----------------------------------------------
  var tree = btree_new(5);
  var i = 0;
  while i < 100 {
    let ins = btree_insert(&mut tree, i, i * 10);
    if !ins { show("btree.insert.failed.at", i); }
    i = i + 1;
  }
  show("btree.size", btree_size(&tree));
  let v50 = btree_search(&tree, 50);
  match v50 {
    None => { io.println("btree.search(50)=None"); }
    Some(v) => { show("btree.search(50)", v); }
  }
  let v99 = btree_search(&tree, 99);
  match v99 {
    None => { io.println("btree.search(99)=None"); }
    Some(v) => { show("btree.search(99)", v); }
  }
  show("btree.to_vec.len", btree_to_vec(&tree).len());
  return 0;
}
