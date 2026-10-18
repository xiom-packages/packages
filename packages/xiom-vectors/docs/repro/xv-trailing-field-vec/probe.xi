// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Candidate repro: `hydrate_hits`-shaped loop (Option-match copy of a nested
// Vec payload into a local, then a struct literal reading a Bool that was
// assigned inside the match branch) reports has_payload=true where it must be
// false. Shapes mirror tests/test_conformance.xi's local mirrors:
//   - with_payload=false: no hit may carry a payload
//   - with_payload=true: only the id present in the store may carry one
// Expected: always exit 0. A nonzero exit names the failing case.

module probe_hydration_guard

use xiom.io;

pub enum Val {
  I(v: Int),
  T(v: Str),
}

pub type Node = {
  key: Str;
  value: Val;
}

pub type Entry = {
  id: Int;
  payload: Vec[Node];
}

pub type PayloadStore = {
  entries: Vec[Entry];
}

pub type Result0 = {
  id: Int;
  distance: Float32;
}

pub type Hit = {
  id: Int;
  distance: Float32;
  payload: Vec[Node];
  has_payload: Bool;
}

pub type Hits = {
  items: Vec[Hit];
}

fn store_get(s: &PayloadStore, id: Int) -> Option[Vec[Node]] {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id { return Some(s.entries[i].payload); }
    i = i + 1;
  }
  return None;
}

fn hydrate_hits(items: &Vec[Result0], payloads: &PayloadStore, with_payload: Bool) -> Vec[Hit] {
  var out = Vec[Hit].new();
  var i: Int = 0;
  while i < items.len() {
    var pl = Vec[Node].new();
    var have: Bool = false;
    if with_payload {
      match store_get(payloads, items[i].id) {
        Some(found) => { pl = found; have = true; }
        None => {}
      }
    }
    out.push(Hit{ id: items[i].id, distance: items[i].distance, payload: pl, has_payload: have });
    i = i + 1;
  }
  return out;
}

fn count_payload_bearing(items: &Vec[Hit]) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < items.len() {
    if items[i].has_payload { n = n + 1; }
    i = i + 1;
  }
  return n;
}

fn main() -> Int {
  var store = PayloadStore{ entries: Vec[Entry].new() };
  var nodes = Vec[Node].new();
  nodes.push(Node{ key: "color", value: Val.T("red") });
  store.entries.push(Entry{ id: 1, payload: nodes });

  var results = Vec[Result0].new();
  results.push(Result0{ id: 1, distance: 0.0 });
  results.push(Result0{ id: 2, distance: 0.5 });

  // Case A: hydration OFF -> no hit may carry a payload.
  var off = hydrate_hits(&results, &store, false);
  var off_n = count_payload_bearing(&off);
  if off_n != 0 { io.println("BAD detach count"); return 1; }

  // Case B: hydration ON -> only id 1 carries one; id 2 must stay false.
  var on = hydrate_hits(&results, &store, true);
  var on_n = count_payload_bearing(&on);
  if on_n != 1 { io.println("BAD attach count"); return 2; }
  if on[1].has_payload { io.println("BAD hit2 payload"); return 3; }
  if !on[0].has_payload { io.println("BAD hit1 payload"); return 4; }
  io.println("hydration-guard: green");
  return 0;
}
