// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Minimizer: which struct/Vec shape makes a Bool field read back true after
// local var initialization `var have: Bool = false;` (never assigned true)?
// Each variant builds Vec[Elem] with two elements whose flag must be false
// and counts reads of true. Expected: all variants report 0.

module probe_variants

use xiom.io;

pub type Node = {
  key: Str;
  value: Int;
}

pub type Wrap = {
  nodes: Vec[Node];
}

// V1: all scalar.
pub type Elem1 = {
  id: Int;
  flag: Bool;
}

// V2: scalar + Bool BEFORE the Vec.
pub type Elem2 = {
  id: Int;
  flag: Bool;
  nodes: Vec[Node];
}

// V3: bare Vec BEFORE the Bool.
pub type Elem3 = {
  id: Int;
  nodes: Vec[Node];
  flag: Bool;
}

// V4: wrapped Vec BEFORE the Bool.
pub type Elem4 = {
  id: Int;
  wrap: Wrap;
  flag: Bool;
}

fn bad1() -> Int {
  var out = Vec[Elem1].new();
  var i: Int = 0;
  while i < 2 {
    var have: Bool = false;
    out.push(Elem1{ id: i + 1, flag: have });
    i = i + 1;
  }
  var n: Int = 0;
  i = 0;
  while i < out.len() {
    if out[i].flag { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn bad2() -> Int {
  var out = Vec[Elem2].new();
  var i: Int = 0;
  while i < 2 {
    var have: Bool = false;
    var nodes = Vec[Node].new();
    out.push(Elem2{ id: i + 1, flag: have, nodes: nodes });
    i = i + 1;
  }
  var n: Int = 0;
  i = 0;
  while i < out.len() {
    if out[i].flag { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn bad3() -> Int {
  var out = Vec[Elem3].new();
  var i: Int = 0;
  while i < 2 {
    var have: Bool = false;
    var nodes = Vec[Node].new();
    out.push(Elem3{ id: i + 1, nodes: nodes, flag: have });
    i = i + 1;
  }
  var n: Int = 0;
  i = 0;
  while i < out.len() {
    if out[i].flag { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn bad4() -> Int {
  var out = Vec[Elem4].new();
  var i: Int = 0;
  while i < 2 {
    var have: Bool = false;
    var w = Wrap{ nodes: Vec[Node].new() };
    out.push(Elem4{ id: i + 1, wrap: w, flag: have });
    i = i + 1;
  }
  var n: Int = 0;
  i = 0;
  while i < out.len() {
    if out[i].flag { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn main() -> Int {
  var n1 = bad1();
  var n2 = bad2();
  var n3 = bad3();
  var n4 = bad4();
  var n5 = bad5();
  var n6 = bad6();
  var n7 = bad7();
  var n8 = bad8();
  var n10 = bad10();
  var n11 = bad11();
  var n12 = bad12();
  var n13 = bad13();
  var n14 = bad14();
  io.println("v1-scalar bad=" + str_of(n1));
  io.println("v2-bool-first bad=" + str_of(n2));
  io.println("v3-vec-first bad=" + str_of(n3));
  io.println("v4-wrap-first bad=" + str_of(n4));
  io.println("v5-hydrate-off bad=" + str_of(n5));
  io.println("v6-shape-only bad=" + str_of(n6));
  io.println("v7-hydrate-wrapped bad=" + str_of(n7));
  io.println("v8-simple-if bad=" + str_of(n8));
  io.println("v10-branch-split bad=" + str_of(n10));
  io.println("v11-index-lookup bad=" + str_of(n11));
  io.println("v12-two-phase bad=" + str_of(n12));
  io.println("v13-flag-first bad=" + str_of(n13));
  io.println("v14-int-flag bad=" + str_of(n14));
  if n1 != 0 { return 1; }
  if n2 != 0 { return 2; }
  if n3 != 0 { return 3; }
  if n4 != 0 { return 4; }
  if n5 != 0 { return 5; }
  if n6 != 0 { return 6; }
  if n7 != 0 { return 7; }
  if n8 != 0 { return 8; }
  if n10 != 0 { return 10; }
  if n11 != 0 { return 11; }
  if n12 != 0 { return 12; }
  if n13 != 0 { return 13; }
  if n14 != 0 { return 14; }
  io.println("variants: all green");
  return 0;
}

fn str_of(n: Int) -> Str {
  if n == 0 { return "0"; }
  if n == 1 { return "1"; }
  if n == 2 { return "2"; }
  if n == 3 { return "3"; }
  return "?";
}

// V5: exact hydrate_hits shape (dead `if with_payload` + Option-match copy),
// called with with_payload=false; counts wrongly-true flags.
pub type Res5 = {
  id: Int;
  distance: Float32;
}

pub type StoreEntry5 = {
  id: Int;
  payload: Vec[Node];
}

pub type Store5 = {
  entries: Vec[StoreEntry5];
}

pub type Elem5 = {
  id: Int;
  distance: Float32;
  payload: Vec[Node];
  flag: Bool;
}

fn store_get5(s: &Store5, id: Int) -> Option[Vec[Node]] {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return Some(s.entries[i].payload); }
    i = i + 1;
  }
  return None;
}

fn build5(items: &Vec[Res5], store: &Store5, with_payload: Bool) -> Vec[Elem5] {
  var out = Vec[Elem5].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = Vec[Node].new();
    var have: Bool = false;
    if with_payload {
      match store_get5(store, items[i].id) {
        Some(found) => { pl = found; have = true; }
        None => {}
      }
    }
    out.push(Elem5{ id: items[i].id, distance: items[i].distance, payload: pl, flag: have });
    i = i + 1;
  }
  return out;
}

fn bad5() -> Int {
  var store = Store5{ entries: Vec[StoreEntry5].new() };
  var items = Vec[Res5].new();
  items.push(Res5{ id: 1, distance: 0.0 });
  items.push(Res5{ id: 2, distance: 0.5 });
  var off = build5(&items, &store, false);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V6: shape-only (no dead if/match): 4 fields with bare Vec payload.
pub type Res6 = {
  id: Int;
  distance: Float32;
}

pub type Elem6 = {
  id: Int;
  distance: Float32;
  nodes: Vec[Node];
  flag: Bool;
}

fn build6(items: &Vec[Res6]) -> Vec[Elem6] {
  var out = Vec[Elem6].new();
  var i: Int = 0;
  while i < items.len() {
    var have: Bool = false;
    var nodes = Vec[Node].new();
    out.push(Elem6{ id: items[i].id, distance: items[i].distance, nodes: nodes, flag: have });
    i = i + 1;
  }
  return out;
}

fn bad6() -> Int {
  var items = Vec[Res6].new();
  items.push(Res6{ id: 1, distance: 0.0 });
  items.push(Res6{ id: 2, distance: 0.5 });
  var off = build6(&items);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V7: full hydrate flow with the payload WRAPPED in a struct.
pub type Wrap7 = {
  nodes: Vec[Node];
}

pub type Res7 = {
  id: Int;
  distance: Float32;
}

pub type StoreEntry7 = {
  id: Int;
  payload: Wrap7;
}

pub type Store7 = {
  entries: Vec[StoreEntry7];
}

pub type Elem7 = {
  id: Int;
  distance: Float32;
  payload: Wrap7;
  flag: Bool;
}

fn store_get7(s: &Store7, id: Int) -> Option[Wrap7] {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return Some(s.entries[i].payload); }
    i = i + 1;
  }
  return None;
}

fn build7(items: &Vec[Res7], store: &Store7, with_payload: Bool) -> Vec[Elem7] {
  var out = Vec[Elem7].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = Wrap7{ nodes: Vec[Node].new() };
    var have: Bool = false;
    if with_payload {
      match store_get7(store, items[i].id) {
        Some(found) => { pl = found; have = true; }
        None => {}
      }
    }
    out.push(Elem7{ id: items[i].id, distance: items[i].distance, payload: pl, flag: have });
    i = i + 1;
  }
  return out;
}

fn bad7() -> Int {
  var store = Store7{ entries: Vec[StoreEntry7].new() };
  var items = Vec[Res7].new();
  items.push(Res7{ id: 1, distance: 0.0 });
  items.push(Res7{ id: 2, distance: 0.5 });
  var off = build7(&items, &store, false);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V8: `var have=false; if with_payload { have=true; }` + push (no match).
fn build8(items: &Vec[Res6], with_payload: Bool) -> Vec[Elem6] {
  var out = Vec[Elem6].new();
  var i: Int = 0;
  while i < items.len() {
    var have: Bool = false;
    var nodes = Vec[Node].new();
    if with_payload { have = true; }
    out.push(Elem6{ id: items[i].id, distance: items[i].distance, nodes: nodes, flag: have });
    i = i + 1;
  }
  return out;
}

fn bad8() -> Int {
  var items = Vec[Res6].new();
  items.push(Res6{ id: 1, distance: 0.0 });
  items.push(Res6{ id: 2, distance: 0.5 });
  var off = build8(&items, false);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V10: candidate workaround -- branch-specific pushes (no Bool variable
// mutated in a conditional and read later).
fn build10(items: &Vec[Res5], store: &Store5, with_payload: Bool) -> Vec[Elem5] {
  var out = Vec[Elem5].new();
  var i: Int = 0;
  while i < items.len() {
    if with_payload {
      match store_get5(store, items[i].id) {
        Some(found) => {
          out.push(Elem5{ id: items[i].id, distance: items[i].distance, payload: found, flag: true });
        }
        None => {
          out.push(Elem5{ id: items[i].id, distance: items[i].distance, payload: Vec[Node].new(), flag: false });
        }
      }
    } else {
      out.push(Elem5{ id: items[i].id, distance: items[i].distance, payload: Vec[Node].new(), flag: false });
    }
    i = i + 1;
  }
  return out;
}

fn bad10() -> Int {
  var store = Store5{ entries: Vec[StoreEntry5].new() };
  var items = Vec[Res5].new();
  items.push(Res5{ id: 1, distance: 0.0 });
  items.push(Res5{ id: 2, distance: 0.5 });
  var off = build10(&items, &store, false);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V11: index-based lookup (no Option/match in the loop).
fn store_pos5(s: &Store5, id: Int) -> Int {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return i; }
    i = i + 1;
  }
  return -1;
}

fn build11(items: &Vec[Res5], store: &Store5, with_payload: Bool) -> Vec[Elem5] {
  var out = Vec[Elem5].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = Vec[Node].new();
    var have: Bool = false;
    if with_payload {
      var pos = store_pos5(store, items[i].id);
      if pos >= 0 {
        pl = store.entries[pos].payload;
        have = true;
      }
    }
    out.push(Elem5{ id: items[i].id, distance: items[i].distance, payload: pl, flag: have });
    i = i + 1;
  }
  return out;
}

fn bad11() -> Int {
  var store = Store5{ entries: Vec[StoreEntry5].new() };
  var items = Vec[Res5].new();
  items.push(Res5{ id: 1, distance: 0.0 });
  items.push(Res5{ id: 2, distance: 0.5 });
  var off = build11(&items, &store, false);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V12: two-phase hydration (push plain hits, then attach in a second loop).
fn build12(items: &Vec[Res5], store: &Store5, with_payload: Bool) -> Vec[Elem5] {
  var out = Vec[Elem5].new();
  var i: Int = 0;
  while i < items.len() {
    out.push(Elem5{ id: items[i].id, distance: items[i].distance, payload: Vec[Node].new(), flag: false });
    i = i + 1;
  }
  if with_payload {
    i = 0;
    while i < out.len() {
      var pos = store_pos5(store, out[i].id);
      if pos >= 0 {
        var found = store.entries[pos].payload;
        out[i].payload = found;
        out[i].flag = true;
      }
      i = i + 1;
    }
  }
  return out;
}

fn bad12() -> Int {
  var store = Store5{ entries: Vec[StoreEntry5].new() };
  var items = Vec[Res5].new();
  items.push(Res5{ id: 1, distance: 0.0 });
  items.push(Res5{ id: 2, distance: 0.5 });
  var off = build12(&items, &store, false);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V13: same hydrate flow, but the Bool is declared BEFORE the payload field.
pub type Elem13 = {
  id: Int;
  distance: Float32;
  flag: Bool;
  payload: Vec[Node];
}

fn build13(items: &Vec<Res5>, store: &Store5, with_payload: Bool) -> Vec[Elem13] {
  var out = Vec[Elem13].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = Vec[Node].new();
    var have: Bool = false;
    if with_payload {
      match store_get5(store, items[i].id) {
        Some(found) => { pl = found; have = true; }
        None => {}
      }
    }
    out.push(Elem13{ id: items[i].id, distance: items[i].distance, flag: have, payload: pl });
    i = i + 1;
  }
  return out;
}

fn bad13() -> Int {
  var store = Store5{ entries: Vec<StoreEntry5>.new() };
  var items = Vec[Res5].new();
  items.push(Res5{ id: 1, distance: 0.0 });
  items.push(Res5{ id: 2, distance: 0.5 });
  var off = build13(&items, &store, false);
  var code: Int = 0;
  if off[0].flag { code = code + 1; }
  if off[1].flag { code = code + 2; }
  return code;
}

// V14: same hydrate flow, flag stored as Int (0/1).
pub type Elem14 = {
  id: Int;
  distance: Float32;
  payload: Vec[Node];
  flag: Int;
}

fn build14(items: &Vec[Res5], store: &Store5, with_payload: Bool) -> Vec[Elem14] {
  var out = Vec[Elem14].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = Vec[Node].new();
    var have: Int = 0;
    if with_payload {
      match store_get5(store, items[i].id) {
        Some(found) => { pl = found; have = 1; }
        None => {}
      }
    }
    out.push(Elem14{ id: items[i].id, distance: items[i].distance, payload: pl, flag: have });
    i = i + 1;
  }
  return out;
}

fn bad14() -> Int {
  var store = Store5{ entries: Vec<StoreEntry5>.new() };
  var items = Vec[Res5].new();
  items.push(Res5{ id: 1, distance: 0.0 });
  items.push(Res5{ id: 2, distance: 0.5 });
  var off = build14(&items, &store, false);
  var code: Int = 0;
  if off[0].flag != 0 { code = code + 1; }
  if off[1].flag != 0 { code = code + 2; }
  return code;
}
