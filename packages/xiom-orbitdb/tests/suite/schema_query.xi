// XIOM ORBITDB -- conformance suite split: schema_query (R2, 2026-10-18).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom_db_conformance_schema_query

use xiom.io;
use xiom.convert;
use xiom.os.env;
use xiom.test;
use xiom.db.engine;
use xiom.db.wal_file;
use xiom.db.error;
use xiom.db.ids;
use xiom.db.config;
use xiom.db.contracts;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.fault;
use xiom.db.storage.tuple;
use xiom.db.storage.free_space_map;
use xiom.db.catalog.schema;
use xiom.db.catalog.schema_row;
use xiom.db.catalog.schema_validator;
use xiom.db.txn.transaction;
use xiom_db_suite_common;

fn run_schema_column_def_new() -> Int {
  let col = ColumnDef.new("id", ColumnType.IntType);
  if col.name != "id" { return 1; }
  return 0;
}

fn test_schema_column_def_new() -> TestResult {
  let rc = run_schema_column_def_new();
  if rc == 0 { return assert(true, "schema: ColumnDef.new stores name+type"); }
  return assert(false, "schema: ColumnDef.new failed");
}

fn run_schema_column_def_optional() -> Int {
  let col = ColumnDef.optional("email", ColumnType.StringType, None);
  if col.name != "email" { return 1; }
  if !col.nullable { return 1; }
  return 0;
}

fn test_schema_column_def_optional() -> TestResult {
  let rc = run_schema_column_def_optional();
  if rc == 0 { return assert(true, "schema: ColumnDef.optional sets nullable=true"); }
  return assert(false, "schema: ColumnDef.optional failed");
}

fn run_schema_new_and_accessors() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.new("name", ColumnType.StringType));
  cols.push(ColumnDef.new("age", ColumnType.IntType));
  let schema = Schema.new("users", cols, 0);
  if schema.table_name != "users" { return 1; }
  if schema.column_count() != 3 { return 1; }
  return 0;
}

fn test_schema_new_and_accessors() -> TestResult {
  let rc = run_schema_new_and_accessors();
  if rc == 0 { return assert(true, "schema: Schema.new stores table + columns"); }
  return assert(false, "schema: Schema.new failed");
}

fn run_schema_column_index() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  cols.push(ColumnDef.new("name", ColumnType.StringType));
  let schema = Schema.new("t", cols, 0);
  let idx = schema.column_index("name");
  match idx { None => return 1; Some(i) => { if i != 1 { return 1; } } }
  let missing = schema.column_index("nonexistent");
  match missing { Some(_) => return 1; None => {} }
  return 0;
}

fn test_schema_column_index() -> TestResult {
  let rc = run_schema_column_index();
  if rc == 0 { return assert(true, "schema: column_index find + not-found"); }
  return assert(false, "schema: column_index failed");
}

fn run_index_def_new() -> Int {
  let idx = IndexDef.new("idx_users_name", "users", 1, false);
  if idx.name != "idx_users_name" { return 1; }
  if idx.table != "users" { return 1; }
  if idx.column != 1 { return 1; }
  if idx.unique { return 1; }
  return 0;
}

fn test_index_def_new() -> TestResult {
  let rc = run_index_def_new();
  if rc == 0 { return assert(true, "schema: IndexDef.new fields correct"); }
  return assert(false, "schema: IndexDef.new failed");
}

fn run_validate_schema_valid() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  let schema = Schema.new("t", cols, 0);
  let r = validate_schema(&schema);
  match r {
    Ok(v) => { if !v { return 1; } return 0; }
    Err(_) => return 1,
  }
}

fn test_validate_schema_valid() -> TestResult {
  let rc = run_validate_schema_valid();
  if rc == 0 { return assert(true, "schema_validator: valid schema passes"); }
  return assert(false, "schema_validator: valid schema rejected");
}

fn run_validate_schema_no_columns() -> Int {
  var cols = Vec[ColumnDef].new();
  let schema = Schema.new("t", cols, 0);
  let r = validate_schema(&schema);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_validate_schema_no_columns() -> TestResult {
  let rc = run_validate_schema_no_columns();
  if rc == 0 { return assert(true, "schema_validator: zero columns rejected"); }
  return assert(false, "schema_validator: zero columns accepted");
}

fn run_validate_schema_pk_out_of_range() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("id", ColumnType.IntType));
  let schema = Schema.new("t", cols, 5);
  let r = validate_schema(&schema);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_validate_schema_pk_out_of_range() -> TestResult {
  let rc = run_validate_schema_pk_out_of_range();
  if rc == 0 { return assert(true, "schema_validator: out-of-range PK rejected"); }
  return assert(false, "schema_validator: bad PK accepted");
}

fn run_validate_column_valid() -> Int {
  let col = ColumnDef.new("x", ColumnType.IntType);
  let r = validate_column(&col);
  match r {
    Ok(v) => { if !v { return 1; } return 0; }
    Err(_) => return 1,
  }
}

fn test_validate_column_valid() -> TestResult {
  let rc = run_validate_column_valid();
  if rc == 0 { return assert(true, "schema_validator: named column passes"); }
  return assert(false, "schema_validator: named column rejected");
}

fn run_validate_index_valid() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("a", ColumnType.IntType));
  cols.push(ColumnDef.new("b", ColumnType.StringType));
  let schema = Schema.new("t", cols, 0);
  let idx = IndexDef.new("my_idx", "t", 1, true);
  let r = validate_index(&idx, &schema);
  match r {
    Ok(v) => { if !v { return 1; } return 0; }
    Err(_) => return 1,
  }
}

fn test_validate_index_valid() -> TestResult {
  let rc = run_validate_index_valid();
  if rc == 0 { return assert(true, "schema_validator: valid index passes"); }
  return assert(false, "schema_validator: valid index rejected");
}

fn run_validate_index_wrong_table() -> Int {
  var cols = Vec[ColumnDef].new();
  cols.push(ColumnDef.new("a", ColumnType.IntType));
  let schema = Schema.new("t", cols, 0);
  let idx = IndexDef.new("idx", "other_table", 0, false);
  let r = validate_index(&idx, &schema);
  match r {
    Ok(_) => return 1,
    Err(_) => return 0,
  }
}

fn test_validate_index_wrong_table() -> TestResult {
  let rc = run_validate_index_wrong_table();
  if rc == 0 { return assert(true, "schema_validator: mismatched table rejected"); }
  return assert(false, "schema_validator: wrong table accepted");
}

// ===========================================================================
// 11. Query planner stubs
// ===========================================================================

fn run_query_new() -> Int {
  let q = query_new();
  if query_condition_count(&q) != 0 { return 1; }
  if query_has_limit(&q) { return 1; }
  if query_has_offset(&q) { return 1; }
  return 0;
}

fn test_query_new() -> TestResult {
  let rc = run_query_new();
  if rc == 0 { return assert(true, "query: query_new has zero conditions/limit/offset"); }
  return assert(false, "query: query_new failed");
}

fn run_query_where_limit_offset() -> Int {
  var q = query_new();
  query_where(&mut q, QueryOp.Eq, 42);
  query_where(&mut q, QueryOp.Gt, 0);
  query_limit(&mut q, 10);
  query_offset(&mut q, 5);
  if query_condition_count(&q) != 2 { return 1; }
  if !query_has_limit(&q) { return 1; }
  if !query_has_offset(&q) { return 1; }
  return 0;
}

fn test_query_where_limit_offset() -> TestResult {
  let rc = run_query_where_limit_offset();
  if rc == 0 { return assert(true, "query: where/limit/offset builder"); }
  return assert(false, "query: query builder failed");
}

fn run_query_reset() -> Int {
  var q = query_new();
  query_where(&mut q, QueryOp.Eq, 1);
  query_limit(&mut q, 5);
  query_offset(&mut q, 3);
  query_reset(&mut q);
  if query_condition_count(&q) != 0 { return 1; }
  if query_has_limit(&q) { return 1; }
  if query_has_offset(&q) { return 1; }
  return 0;
}

fn test_query_reset() -> TestResult {
  let rc = run_query_reset();
  if rc == 0 { return assert(true, "query: reset clears conditions/limit/offset"); }
  return assert(false, "query: reset failed");
}

fn run_query_execute_simple() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 10, 100);
  btree_insert(&mut tree, 20, 200);
  btree_insert(&mut tree, 30, 300);
  var q = query_new();
  // Phase 0 semantics: conditions filter VALUES, not keys (docs/query-pipeline.md).
  // Values are [100,200,300]; Gte 150 must yield [200,300].
  query_where(&mut q, QueryOp.Gte, 150);
  let results = query_execute(&q, &tree);
  if results.len() != 2 { return 1; }
  return 0;
}

fn test_query_execute_simple() -> TestResult {
  let rc = run_query_execute_simple();
  if rc == 0 { return assert(true, "query: execute applies filter condition"); }
  return assert(false, "query: execute failed");
}

fn run_plan_query_defaults_to_full_scan() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 1, 10);
  btree_insert(&mut tree, 2, 20);
  var q = query_new();
  let plan = plan_query(&q, &tree);
  if plan.estimated_rows != 2 { return 1; }
  return 0;
}

fn test_plan_query_defaults_to_full_scan() -> TestResult {
  let rc = run_plan_query_defaults_to_full_scan();
  if rc == 0 { return assert(true, "planner: plan_query sets estimated_rows"); }
  return assert(false, "planner: plan_query failed");
}

fn run_execute_plan_full_scan() -> Int {
  var tree = btree_new(4);
  btree_insert(&mut tree, 1, 11);
  btree_insert(&mut tree, 2, 22);
  btree_insert(&mut tree, 3, 33);
  var q = query_new();
  query_where(&mut q, QueryOp.Gt, 0);
  let plan = plan_query(&q, &tree);
  let results = execute_plan(&plan, &q, &tree);
  if results.len() != 3 { return 1; }
  return 0;
}

fn test_execute_plan_full_scan() -> TestResult {
  let rc = run_execute_plan_full_scan();
  if rc == 0 { return assert(true, "planner: execute_plan runs full scan"); }
  return assert(false, "planner: execute_plan failed");
}

fn run_query_planner_kinds() -> Int {
  var tree = btree_new(4);
  var i = 1;
  while i <= 20 {
    if !btree_insert(&mut tree, i, i * 3 - 7) { return 1; }
    i = i + 1;
  }

  // No bounds -> full scan, estimate = tree size.
  var q = query_new();
  let p1 = plan_query(&q, &tree);
  match p1.kind {
    PlanKind.FullScan => {}
    PlanKind.IndexRange => { return 1; }
    PlanKind.PointLookup => { return 1; }
  }
  if p1.estimated_rows != 20 { return 1; }

  // Point bounds -> point lookup with a 1-row estimate.
  var qp = query_new();
  query_key_range(&mut qp, 7, 7);
  if !query_has_bounds(&qp) { return 1; }
  let p2 = plan_query(&qp, &tree);
  match p2.kind {
    PlanKind.PointLookup => {}
    PlanKind.FullScan => { return 1; }
    PlanKind.IndexRange => { return 1; }
  }
  if p2.estimated_rows != 1 { return 1; }
  if p2.low != 7 { return 1; }
  if p2.high != 7 { return 1; }
  query_where(&mut qp, QueryOp.Gt, 0);
  let r2 = execute_plan(&p2, &qp, &tree);
  if r2.len() != 1 { return 1; }
  if r2[0] != 14 { return 1; } // key 7 -> 7*3-7 = 14

  // Range bounds -> index range, estimate = clamped width.
  var qr = query_new();
  query_key_range(&mut qr, 3, 9);
  let p3 = plan_query(&qr, &tree);
  match p3.kind {
    PlanKind.IndexRange => {}
    PlanKind.FullScan => { return 1; }
    PlanKind.PointLookup => { return 1; }
  }
  if p3.estimated_rows != 7 { return 1; }
  query_where(&mut qr, QueryOp.Gte, 10);
  let r3 = execute_plan(&p3, &qr, &tree);
  // keys 3..9 -> values 2,5,8,11,14,17,20; >= 10 -> 11,14,17,20
  if r3.len() != 4 { return 1; }
  if r3[0] != 11 { return 1; }

  // Width clamp: estimate never exceeds the tree size.
  var qc = query_new();
  query_key_range(&mut qc, -100, 100);
  let p4 = plan_query(&qc, &tree);
  if p4.estimated_rows != 20 { return 1; }

  // Reset clears the bounds again.
  query_reset(&mut qr);
  if query_has_bounds(&qr) { return 1; }
  let p5 = plan_query(&qr, &tree);
  match p5.kind {
    PlanKind.FullScan => {}
    PlanKind.IndexRange => { return 1; }
    PlanKind.PointLookup => { return 1; }
  }
  return 0;
}

fn test_query_planner_kinds() -> TestResult {
  let rc = run_query_planner_kinds();
  if rc == 0 { return assert(true, "planner: point/range/full selection + clamped estimate"); }
  return assert(false, "planner: plan kinds failed");
}

fn query_model_condition(value: Int, op: QueryOp, target: Int) -> Bool {
  match op {
    QueryOp.Eq => value == target,
    QueryOp.Neq => value != target,
    QueryOp.Lt => value < target,
    QueryOp.Lte => value <= target,
    QueryOp.Gt => value > target,
    QueryOp.Gte => value >= target,
  }
}

fn run_query_planner_property() -> Int {
  var tree = btree_new(4);
  var i = 1;
  while i <= 64 {
    if !btree_insert(&mut tree, i, i * 3 - 7) { return 1; }
    i = i + 1;
  }

  var state = 4242;
  var it = 0;
  while it < 200 {
    state = (state * 1103515245 + 12345) % 2147483648;
    let mode = (state / 65536) % 3; // 0 full, 1 range, 2 point
    var q = query_new();
    var lo = -10;
    var hi = 80;
    if mode == 1 {
      lo = ((state / 65536) % 100) - 10;
      state = (state * 1103515245 + 12345) % 2147483648;
      hi = lo + ((state / 65536) % 40);
      query_key_range(&mut q, lo, hi);
    } elif mode == 2 {
      lo = ((state / 65536) % 100) - 10;
      hi = lo;
      query_key_range(&mut q, lo, hi);
    }

    state = (state * 1103515245 + 12345) % 2147483648;
    let has_cond = (state / 65536) % 2 == 0;
    var op = QueryOp.Gte;
    var target = 0;
    if has_cond {
      state = (state * 1103515245 + 12345) % 2147483648;
      let opk = (state / 65536) % 6;
      match opk {
        0 => { op = QueryOp.Eq; }
        1 => { op = QueryOp.Neq; }
        2 => { op = QueryOp.Lt; }
        3 => { op = QueryOp.Lte; }
        4 => { op = QueryOp.Gt; }
        _ => { op = QueryOp.Gte; }
      }
      state = (state * 1103515245 + 12345) % 2147483648;
      target = ((state / 65536) % 160) - 20;
      query_where(&mut q, op, target);
    }

    state = (state * 1103515245 + 12345) % 2147483648;
    let off = (state / 65536) % 5;
    query_offset(&mut q, off);
    state = (state * 1103515245 + 12345) % 2147483648;
    let lim = (state / 65536) % 8; // 0 = no limit
    if lim > 0 { query_limit(&mut q, lim); }

    // Brute-force model: key range -> values -> conditions -> offset -> limit.
    var want = Vec[Int].new();
    var count = 0;
    var klo = lo;
    var khi = hi;
    if mode == 0 {
      klo = 1;
      khi = 64;
    }
    var k = klo;
    while k <= khi {
      if k >= 1 && k <= 64 {
        let v = k * 3 - 7;
        var keep = true;
        if has_cond { keep = query_model_condition(v, op, target); }
        if keep {
          if count >= off { want.push(v); }
          count = count + 1;
        }
      }
      k = k + 1;
    }
    if lim > 0 && want.len() > lim {
      var cut = Vec[Int].new();
      var j = 0;
      while j < lim {
        cut.push(want[j]);
        j = j + 1;
      }
      want = cut;
    }

    let plan = plan_query(&q, &tree);
    let got = execute_plan(&plan, &q, &tree);
    if got.len() != want.len() {
      io.println("query planner property: len got=" + convert.int_to_string(got.len())
        + " want=" + convert.int_to_string(want.len()) + " it=" + convert.int_to_string(it));
      return 1;
    }
    var vi = 0;
    while vi < got.len() {
      if got[vi] != want[vi] {
        io.println("query planner property: value mismatch it=" + convert.int_to_string(it));
        return 2;
      }
      vi = vi + 1;
    }
    it = it + 1;
  }
  return 0;
}

fn test_query_planner_property() -> TestResult {
  let rc = run_query_planner_property();
  if rc == 0 { return assert(true, "planner: property vs brute force (200 seeded cases)"); }
  return assert(false, "planner: property failed");
}

// ===========================================================================
// 12. B-tree node structure and operations
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM DB Conformance: schema_query ===");
  var failed: Int = 0;
  var total: Int = 0;
  let r50 = test_schema_column_def_new();
  total = total + 1; failed = failed + report(r50.passed, r50.name);
  let r51 = test_schema_column_def_optional();
  total = total + 1; failed = failed + report(r51.passed, r51.name);
  let r52 = test_schema_new_and_accessors();
  total = total + 1; failed = failed + report(r52.passed, r52.name);
  let r53 = test_schema_column_index();
  total = total + 1; failed = failed + report(r53.passed, r53.name);
  let r54 = test_index_def_new();
  total = total + 1; failed = failed + report(r54.passed, r54.name);
  let r55 = test_validate_schema_valid();
  total = total + 1; failed = failed + report(r55.passed, r55.name);
  let r56 = test_validate_schema_no_columns();
  total = total + 1; failed = failed + report(r56.passed, r56.name);
  let r57 = test_validate_schema_pk_out_of_range();
  total = total + 1; failed = failed + report(r57.passed, r57.name);
  let r58 = test_validate_column_valid();
  total = total + 1; failed = failed + report(r58.passed, r58.name);
  let r59 = test_validate_index_valid();
  total = total + 1; failed = failed + report(r59.passed, r59.name);
  let r60 = test_validate_index_wrong_table();
  total = total + 1; failed = failed + report(r60.passed, r60.name);
  let r61 = test_query_new();
  total = total + 1; failed = failed + report(r61.passed, r61.name);
  let r62 = test_query_where_limit_offset();
  total = total + 1; failed = failed + report(r62.passed, r62.name);
  let r63 = test_query_reset();
  total = total + 1; failed = failed + report(r63.passed, r63.name);
  let r64 = test_query_execute_simple();
  total = total + 1; failed = failed + report(r64.passed, r64.name);
  let r65 = test_plan_query_defaults_to_full_scan();
  total = total + 1; failed = failed + report(r65.passed, r65.name);
  let r66 = test_execute_plan_full_scan();
  total = total + 1; failed = failed + report(r66.passed, r66.name);
  let r66a = test_query_planner_kinds();
  total = total + 1; failed = failed + report(r66a.passed, r66a.name);
  let r66b = test_query_planner_property();
  total = total + 1; failed = failed + report(r66b.passed, r66b.name);
  let passed = total - failed;
  io.println("XIOM DB Conformance [schema_query]: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}