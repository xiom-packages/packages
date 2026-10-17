// XIOM ORBITDB -- write-drop isolation probe #2: Option payloads.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// probe_write_drop evidenced that plain Int writes into Vec[Int] through
// &mut params persist. BufferPool.pages is Vec[Option[Page]] (Page carries a
// Vec[Int]); this probe isolates the Option payload and the exact
// BufferPool.put path, printing every slot to catch a wrong-index write.

module orbitdb_probe_write_drop2

use xiom.io;
use xiom.convert;
use xiom.db.storage.page;

type BoxO = {
  slots: Vec[Option[Int]];
  misses: Int;
}

pub fn BoxO.put(b: &mut BoxO, idx: Int, v: Int) {
  var cur = b.slots[idx];
  match cur {
    None => { b.misses = b.misses + 1; }
    Some(_) => {}
  }
  b.slots[idx] = Some(v);
}

type Pg = {
  id: Int;
  data: Vec[Int];
}

type BoxP = {
  slots: Vec[Option[Pg]];
}

pub fn BoxP.put(b: &mut BoxP, idx: Int, p: Pg) {
  b.slots[idx] = Some(p);
}

fn show(label: Str, n: Int) {
  io.println(label + "=" + convert.int_to_string(n));
}

fn main() -> Int {
  // 1. Vec[Option[Int]] through a method on a &mut struct param
  var bo = BoxO{ slots: Vec[Option[Int]].new(), misses: 0 };
  bo.slots.push(None);
  bo.slots.push(None);
  BoxO.put(&mut bo, 1, 42);
  match bo.slots[1] {
    None => { io.println("opt.method=FAIL(None)"); }
    Some(v) => { show("opt.method", v); }
  }
  show("opt.method.misses", bo.misses);

  // 2. Vec[Option[Pg]] through a method, index 2 of 4 (BufferPool shape)
  var bp = BoxP{ slots: Vec[Option[Pg]].new() };
  var i = 0;
  while i < 4 {
    bp.slots.push(None);
    i = i + 1;
  }
  var d = Vec[Int].new();
  d.push(9);
  let p = Pg{ id: 7, data: d };
  BoxP.put(&mut bp, 2, p);
  var j = 0;
  while j < 4 {
    match bp.slots[j] {
      None => { io.println("pg.slot" + convert.int_to_string(j) + "=None"); }
      Some(q) => { show("pg.slot" + convert.int_to_string(j), q.id); }
    }
    j = j + 1;
  }

  // 3. BufferPool smoke (frame table + clock; was direct-mapped)
  var pool = BufferPool.new(4);
  var k = 1;
  while k <= 3 {
    var dd = Vec[Int].new();
    dd.push(k);
    var ck = page_compute_checksum(&dd);
    let pg = Page.new(k, dd, ck);
    let _ = pool.put(pg);
    k = k + 1;
  }
  var s = 0;
  while s < 4 {
    if pool.present[s] {
      show("bp.frame" + convert.int_to_string(s), pool.frame_ids[s]);
    } else {
      io.println("bp.frame" + convert.int_to_string(s) + "=empty");
    }
    s = s + 1;
  }
  show("bp.evictions", pool.evictions);
  return 0;
}
