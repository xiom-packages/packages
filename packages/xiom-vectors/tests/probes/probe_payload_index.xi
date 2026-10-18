// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: sorted payload key index on the REAL payload module (Phase 3
// refinement). Verifies maintenance (put/overwrite/remove), the sorted-row
// queries (eq/exists/count/range) and their consistency with the store.
// Exit code = number of failed checks.

module probe_payload_index

use xiom.vector.payload.payload;
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

fn ids_empty(ids: &Vec[Int]) -> Bool {
  return ids.len() == 0;
}

fn ids_one(ids: &Vec[Int], a: Int) -> Bool {
  return ids.len() == 1 && ids[0] == a;
}

fn ids_two(ids: &Vec[Int], a: Int, b: Int) -> Bool {
  return ids.len() == 2 && ids[0] == a && ids[1] == b;
}

fn main() -> Int {
  io.println("=== xvector probe: sorted payload key index ===");
  var fails: Int = 0;

  var st = payload_store_new();
  fails = check(payload_store_index_len(&st) == 0, "new store: 0 index rows", fails);

  var p1 = payload_new();
  payload_set(&mut p1, "color", FieldValue.TextVal("red"));
  payload_set(&mut p1, "stock", FieldValue.IntVal(7));
  payload_set(&mut p1, "active", FieldValue.BoolVal(true));
  var p2 = payload_new();
  payload_set(&mut p2, "color", FieldValue.TextVal("blue"));
  payload_set(&mut p2, "price", FieldValue.FloatVal(2.5));
  var p3 = payload_new();
  payload_set(&mut p3, "color", FieldValue.TextVal("red"));
  payload_set(&mut p3, "stock", FieldValue.IntVal(9));
  payload_store_put(&mut st, 1, p1);
  payload_store_put(&mut st, 2, p2);
  payload_store_put(&mut st, 3, p3);
  fails = check(payload_store_index_len(&st) == 7, "put x3: 3+2+2 = 7 index rows", fails);

  fails = check(payload_store_index_exists(&st, "color")
    && payload_store_index_exists(&st, "stock")
    && payload_store_index_exists(&st, "active")
    && payload_store_index_exists(&st, "price")
    && !payload_store_index_exists(&st, "nope"), "exists: color/stock/active/price yes, nope no", fails);

  fails = check(payload_store_index_field_count(&st, "color") == 3
    && payload_store_index_field_count(&st, "stock") == 2
    && payload_store_index_field_count(&st, "active") == 1
    && payload_store_index_field_count(&st, "nope") == 0, "field_count: color=3 stock=2 active=1 nope=0", fails);

  fails = check(ids_two(&payload_store_index_eq(&st, "color", FieldValue.TextVal("red")), 1, 3),
    "eq color=red -> {1,3}", fails);
  fails = check(ids_one(&payload_store_index_eq(&st, "color", FieldValue.TextVal("blue")), 2),
    "eq color=blue -> {2}", fails);
  fails = check(ids_one(&payload_store_index_eq(&st, "stock", FieldValue.IntVal(7)), 1),
    "eq stock=7 -> {1}", fails);
  fails = check(ids_one(&payload_store_index_eq(&st, "active", FieldValue.BoolVal(true)), 1),
    "eq active=true -> {1}", fails);
  fails = check(ids_empty(&payload_store_index_eq(&st, "active", FieldValue.BoolVal(false))),
    "eq active=false -> {}", fails);
  fails = check(ids_one(&payload_store_index_eq(&st, "price", FieldValue.FloatVal(2.5)), 2),
    "eq price=2.5 -> {2}", fails);
  fails = check(ids_empty(&payload_store_index_eq(&st, "price", FieldValue.FloatVal(2.4))),
    "eq price=2.4 -> {}", fails);
  fails = check(ids_empty(&payload_store_index_eq(&st, "nope", FieldValue.IntVal(1))),
    "eq missing field -> {}", fails);

  fails = check(ids_one(&payload_store_index_range(&st, "stock", 8.0, 10.0), 3),
    "range stock 8..10 -> {3}", fails);
  fails = check(ids_two(&payload_store_index_range(&st, "stock", 0.0, 100.0), 1, 3),
    "range stock 0..100 -> {1,3}", fails);
  fails = check(ids_one(&payload_store_index_range(&st, "price", 2.0, 3.0), 2),
    "range price 2..3 -> {2}", fails);
  fails = check(ids_empty(&payload_store_index_range(&st, "color", 0.0, 100.0)),
    "range on text field -> {} (non-numeric skipped)", fails);
  fails = check(ids_empty(&payload_store_index_range(&st, "nope", 0.0, 100.0)),
    "range on missing field -> {}", fails);

  fails = check(payload_store_index_count_eq(&st, "color", FieldValue.TextVal("red")) == 2
    && payload_store_index_count_eq(&st, "stock", FieldValue.IntVal(7)) == 1
    && payload_store_index_count_eq(&st, "price", FieldValue.FloatVal(2.5)) == 1
    && payload_store_index_count_eq(&st, "price", FieldValue.FloatVal(2.4)) == 0,
    "count_eq agrees with eq (text/int/float)", fails);
  fails = check(payload_store_index_count_range(&st, "stock", 0.0, 100.0) == 2
    && payload_store_index_count_range(&st, "stock", 8.0, 10.0) == 1
    && payload_store_index_count_range(&st, "color", 0.0, 100.0) == 0,
    "count_range agrees with range", fails);

  // Overwrite: id 1 drops active, changes color; rows must match the payload.
  var p1b = payload_new();
  payload_set(&mut p1b, "color", FieldValue.TextVal("green"));
  payload_set(&mut p1b, "stock", FieldValue.IntVal(7));
  payload_store_put(&mut st, 1, p1b);
  fails = check(payload_store_index_len(&st) == 6, "overwrite id1: 2+2+2 = 6 index rows", fails);
  fails = check(!payload_store_index_exists(&st, "active")
    && payload_store_index_field_count(&st, "active") == 0, "overwrite drops active field rows", fails);
  fails = check(ids_one(&payload_store_index_eq(&st, "color", FieldValue.TextVal("red")), 3)
    && ids_one(&payload_store_index_eq(&st, "color", FieldValue.TextVal("green")), 1),
    "overwrite: red -> {3}, green -> {1}", fails);

  // Remove: rows and entry go together.
  var removed = payload_store_remove(&mut st, 3);
  fails = check(removed && payload_store_index_len(&st) == 4, "remove id3: 4 index rows left", fails);
  fails = check(ids_empty(&payload_store_index_eq(&st, "color", FieldValue.TextVal("red"))),
    "remove id3: eq red -> {}", fails);
  fails = check(payload_store_index_field_count(&st, "color") == 2, "remove id3: color count=2", fails);
  fails = check(ids_one(&payload_store_index_range(&st, "stock", 0.0, 100.0), 1),
    "remove id3: range stock -> {1}", fails);
  var miss = payload_store_remove(&mut st, 99);
  fails = check(!miss && payload_store_index_len(&st) == 4, "remove missing id: false, rows unchanged", fails);

  // Text ordering with spaces + negative ints + false bool.
  var p4 = payload_new();
  payload_set(&mut p4, "name", FieldValue.TextVal("hello world"));
  payload_set(&mut p4, "stock", FieldValue.IntVal(-3));
  payload_set(&mut p4, "flag", FieldValue.BoolVal(false));
  payload_store_put(&mut st, 4, p4);
  fails = check(ids_one(&payload_store_index_eq(&st, "name", FieldValue.TextVal("hello world")), 4)
    && ids_empty(&payload_store_index_eq(&st, "name", FieldValue.TextVal("helloworld"))),
    "text with space matches exactly, no prefix match", fails);
  fails = check(ids_one(&payload_store_index_eq(&st, "stock", FieldValue.IntVal(-3)), 4),
    "eq stock=-3 -> {4}", fails);
  fails = check(ids_one(&payload_store_index_range(&st, "stock", -5.0, 0.0), 4),
    "range stock -5..0 -> {4}", fails);
  fails = check(ids_empty(&payload_store_index_eq(&st, "flag", FieldValue.BoolVal(true)))
    && ids_one(&payload_store_index_eq(&st, "flag", FieldValue.BoolVal(false)), 4),
    "false bool distinct from true", fails);

  // Field-window scan stops at the field boundary; rows come in index
  // (value) order, so -3 (id4) precedes 7 (id1).
  fails = check(ids_two(&payload_store_index_range(&st, "stock", -100.0, 100.0), 4, 1),
    "field window bounded: stock rows {4,1} in value order", fails);

  payload_store_remove(&mut st, 4);
  fails = check(!payload_store_index_exists(&st, "name") && payload_store_index_len(&st) == 4,
    "remove id4: name gone, 4 rows left (id1+id2)", fails);

  io.println("");
  io.println("probe_payload_index: " + int_to_str(fails) + " failed checks");
  return fails;
}
