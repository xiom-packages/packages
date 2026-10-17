// XIOM ORBITDB -- write-drop isolation probe for BufferPool.put.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// BufferPool.put observes the slot as None even after writing it:
//   misses increments (plain field write through &mut persists)
//   pages[idx] = Some(page) does not persist, OR idx is wrong.
// This probe isolates: (a) inline Vec index write in main, (b) index write
// through a &mut struct param (method), (c) index write through a plain
// &mut Vec param, (d) modulo value itself.

module orbitdb_probe_write_drop

use xiom.io;
use xiom.convert;

type Box = {
  slots: Vec[Int];
  misses: Int;
}

fn Box.put(b: &mut Box, idx: Int, v: Int) {
  var current = b.slots[idx];
  if current == 0 { b.misses = b.misses + 1; }
  b.slots[idx] = v;
}

fn set_slot(p: &mut Vec[Int], idx: Int, v: Int) {
  p[idx] = v;
}

fn show(label: Str, n: Int) {
  io.println(label + "=" + convert.int_to_string(n));
}

fn main() -> Int {
  // (d) modulo sanity
  var m = 7 % 4;
  show("7%4", m);

  // (a) inline index write in main
  var v = Vec[Int].new();
  v.push(0);
  v.push(0);
  v[0] = 111;
  show("inline.v[0]", v[0]);

  // (c) index write through &mut Vec param
  set_slot(&mut v, 1, 222);
  show("param.v[1]", v[1]);

  // (b) index write through &mut struct param (method)
  var b = Box{ slots: v, misses: 0 };
  Box.put(&mut b, 0, 333);
  show("method.slots[0]", b.slots[0]);
  show("method.misses", b.misses);

  // (e) direct method call form on a var binding
  var b2 = Box{ slots: Vec[Int].new(), misses: 0 };
  b2.slots.push(0);
  b2.put(0, 444);
  show("var.method.slots[0]", b2.slots[0]);
  show("var.method.misses", b2.misses);
  return 0;
}
