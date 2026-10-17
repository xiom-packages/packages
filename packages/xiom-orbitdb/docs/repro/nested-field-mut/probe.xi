// XIOM ORBITDB repro -- nested field method call drops &mut receiver writes.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// StorageEngine.cache_page(eng: &mut StorageEngine, page) calls
// `eng.buffer_pool.put(page)`; the page never reaches the pool (suite:
// storage_engine cache/lookup FAIL) while a direct `pool.put(page)` works.
//
// Matrix:
//   A: outer.bump() where bump does `o.inner.bump()`
//   B: outer.bump2() where bump2 does `Inner.bump(&mut o.inner)`
//   C: main calls `o.inner.bump()` directly (nested receiver in a caller)
//   D: outer.bump3() copies the field, mutates, writes back via local

module orbitdb_repro_nested_field

use xiom.io;
use xiom.convert;

type Inner = {
  n: Int;
}

pub fn Inner.bump(x: &mut Inner) {
  x.n = x.n + 1;
}

type Outer = {
  inner: Inner;
}

pub fn Outer.bump(o: &mut Outer) {
  o.inner.bump();
}

pub fn Outer.bump2(o: &mut Outer) {
  Inner.bump(&mut o.inner);
}

pub fn Outer.bump3(o: &mut Outer) {
  var copy = o.inner;
  copy.bump();
  o.inner = copy;
}

fn show(label: Str, n: Int) {
  io.println(label + "=" + convert.int_to_string(n));
}

fn main() -> Int {
  // A
  var a = Outer{ inner: Inner{ n: 0 } };
  a.bump();
  show("A", a.inner.n);

  // B
  var b = Outer{ inner: Inner{ n: 0 } };
  b.bump2();
  show("B", b.inner.n);

  // C
  var c = Outer{ inner: Inner{ n: 0 } };
  c.inner.bump();
  show("C", c.inner.n);

  // D
  var d = Outer{ inner: Inner{ n: 0 } };
  d.bump3();
  show("D", d.inner.n);

  io.println("nested-field probe done");
  return 0;
}
