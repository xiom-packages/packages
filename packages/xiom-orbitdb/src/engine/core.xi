// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.engine.core

// In-memory engine core, extracted move-only from engine.xi (R1 split):
// WAL records/buffer, the Query builder + planner, the legacy Engine API, and
// the private DBFile helpers shared by the facade/snapshot/txn modules.

use xiom.io;
use xiom.db.wal_file;
use xiom.db.index.btree;
use xiom.db.storage.tuple;
use xiom.db.secondary_index;
use xiom.db.engine;

// ============================================================================
// WAL RECORD (from xiom.db.wal.wal_record)
// ============================================================================

pub enum WALOpType {
  InsertOp,
  UpdateOp,
  DeleteOp,
}

pub type WALEntry = {
  op: WALOpType;
  key: Int;
  value: Int;
  timestamp: Int;
}

pub fn wal_entry_new(op: WALOpType, key: Int, value: Int, timestamp: Int) -> WALEntry
  requires: timestamp >= 0
{
  return WALEntry{ op: op, key: key, value: value, timestamp: timestamp };
}

// ============================================================================
// WAL (from xiom.db.wal.wal)
// ============================================================================

pub type WAL = {
  entries: Vec[WALEntry];
}

pub fn wal_new() -> WAL {
  var entries = Vec[WALEntry].new();
  return WAL{ entries: entries };
}

pub fn wal_append(wal: &mut WAL, entry: WALEntry) {
  wal.entries.push(entry);
}

pub fn wal_replay(wal: &WAL, target: &mut BTree) -> Bool {
  var i = 0;
  var success = true;
  while i < wal.entries.len() {
    var entry = wal.entries[i];
    match entry.op {
      InsertOp => {
        var result = btree_insert(target, entry.key, entry.value);
        if !result { success = false; }
      }
      UpdateOp => {
        var found = btree_search(target, entry.key);
        match found {
          Some(_) => {
            var del = btree_delete(target, entry.key);
            if del {
              var ins = btree_insert(target, entry.key, entry.value);
              if !ins { success = false; }
            } else {
              success = false;
            }
          }
          None => { success = false; }
        }
      }
      DeleteOp => {
        var result = btree_delete(target, entry.key);
        if !result { success = false; }
      }
    }
    i = i + 1;
  }
  return success;
}

pub fn wal_clear(wal: &mut WAL) {
  var empty = Vec[WALEntry].new();
  wal.entries = empty;
}

pub fn wal_truncate(wal: &mut WAL, before_timestamp: Int)
  requires: before_timestamp >= 0
{
  var kept = Vec[WALEntry].new();
  var i = 0;
  while i < wal.entries.len() {
    if wal.entries[i].timestamp >= before_timestamp {
      kept.push(wal.entries[i]);
    }
    i = i + 1;
  }
  wal.entries = kept;
}

pub fn wal_len(wal: &WAL) -> Int {
  return wal.entries.len();
}

pub fn wal_is_empty(wal: &WAL) -> Bool {
  return wal.entries.len() == 0;
}

pub fn wal_entry_count(wal: &WAL, op_filter: WALOpType) -> Int {
  var count = 0;
  var i = 0;
  while i < wal.entries.len() {
    if wal.entries[i].op == op_filter {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}
// ============================================================================
// QUERY (from xiom.db.query.query)
// ============================================================================

pub enum QueryOp {
  Eq,
  Neq,
  Lt,
  Lte,
  Gt,
  Gte,
}

pub type QueryCondition = {
  op: QueryOp;
  value: Int;
}

pub type Query = {
  conditions: Vec[QueryCondition];
  limit: Int;
  offset: Int;
  // Optional additive key bounds (M4.1): when has_bounds, the scan is
  // restricted to keys in [low, high] BEFORE value conditions/offset/limit.
  // Conditions still filter VALUES -- bounds are the key-range extension.
  has_bounds: Bool;
  low: Int;
  high: Int;
  // Result order (M4.2): 0 = key ascending (default; the scan order),
  // 1 = value ascending, 2 = value descending. Ties keep key order
  // (stable). offset/limit always apply AFTER ordering.
  order: Int;
}

pub fn query_new() -> Query {
  var conditions = Vec[QueryCondition].new();
  return Query{
    conditions: conditions, limit: 0, offset: 0,
    has_bounds: false, low: 0, high: 0,
    order: 0,
  };
}

// Restrict the scan to keys in [low, high] (inclusive). Additive API: the
// value-condition semantics are unchanged; this only narrows the key range
// the planner can push down (M4.1 semantics decision, docs/query-pipeline.md).
pub fn query_key_range(q: &mut Query, low: Int, high: Int)
  requires: low <= high
{
  q.has_bounds = true;
  q.low = low;
  q.high = high;
}

pub fn query_has_bounds(q: &Query) -> Bool {
  return q.has_bounds;
}

pub fn query_where(q: &mut Query, op: QueryOp, value: Int) {
  var cond = QueryCondition{ op: op, value: value };
  q.conditions.push(cond);
}

pub fn query_limit(q: &mut Query, limit: Int)
  requires: limit > 0
{
  q.limit = limit;
}

pub fn query_offset(q: &mut Query, offset: Int)
  requires: offset >= 0
{
  q.offset = offset;
}

pub fn query_execute(q: &Query, tree: &BTree) -> Vec[Int] {
  var all_values = btree_to_vec(tree);
  return apply_filter_values(&all_values, q);
}

// Value conditions -> ordering -> offset -> limit over an already-scanned
// value slice. Shared by the full scan and the key-range scan so both paths
// have identical semantics (M4.2: ordering happens before offset/limit).
fn apply_filter_values(values: &Vec[Int], q: &Query) -> Vec[Int] {
  var results = Vec[Int].new();
  var i = 0;
  while i < values.len() {
    if matches_all_conditions(values[i], q.conditions) {
      results.push(values[i]);
    }
    i = i + 1;
  }

  if q.order == 1 || q.order == 2 {
    // Stable value sort; the scan order (key ascending) breaks ties, exactly
    // like the index executor's (value, pk) order.
    var pks = Vec[Int].new();
    var j = 0;
    while j < results.len() {
      pks.push(j);
      j = j + 1;
    }
    secidx_sort_pairs(&mut results, &mut pks, q.order == 2);
  }

  var out = Vec[Int].new();
  var start = q.offset;
  var end = results.len();
  if q.limit > 0 && start + q.limit < end {
    end = start + q.limit;
  }
  var k = start;
  while k < end {
    out.push(results[k]);
    k = k + 1;
  }
  return out;
}

fn matches_all_conditions(value: Int, conditions: &Vec[QueryCondition]) -> Bool {
  var i = 0;
  while i < conditions.len() {
    if !test_condition(value, conditions[i].op, conditions[i].value) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn test_condition(value: Int, op: QueryOp, target: Int) -> Bool {
  match op {
    Eq => value == target,
    Neq => value != target,
    Lt => value < target,
    Lte => value <= target,
    Gt => value > target,
    Gte => value >= target,
  }
}

pub fn query_condition_count(q: &Query) -> Int {
  return q.conditions.len();
}

pub fn query_has_limit(q: &Query) -> Bool {
  return q.limit > 0;
}

pub fn query_has_offset(q: &Query) -> Bool {
  return q.offset > 0;
}
// ============================================================================
// TYPED QUERIES (M5-S4): predicates over decoded row columns
// ============================================================================

// One condition: `value_at(row, column) OP literal`. `column` indexes the
// decoded row's values; column -1 addresses the row id (pk). Comparisons
// use the codec's total order (tuple2_compare): Null < numeric (Int/Float,
// numeric) < Text (bytewise) < Blob (bytewise). No SQL three-valued logic:
// every condition is true or false against that order.
pub type TypedCond = {
  column: Int;
  op: QueryOp;
  value: TValue;
}

pub type TypedQuery = {
  conditions: Vec[TypedCond];
  limit: Int;
  offset: Int;
}

pub fn typed_query_new() -> TypedQuery {
  var conditions = Vec[TypedCond].new();
  return TypedQuery{ conditions: conditions, limit: 0, offset: 0 };
}

pub fn typed_query_where(q: &mut TypedQuery, column: Int, op: QueryOp, value: TValue) {
  var cond = TypedCond{ column: column, op: op, value: value };
  q.conditions.push(cond);
}

pub fn typed_query_limit(q: &mut TypedQuery, limit: Int)
  requires: limit > 0
{
  q.limit = limit;
}

pub fn typed_query_offset(q: &mut TypedQuery, offset: Int)
  requires: offset >= 0
{
  q.offset = offset;
}

fn typed_op_matches(cmp: Int, op: QueryOp) -> Bool {
  match op {
    Eq => cmp == 0,
    Neq => cmp != 0,
    Lt => cmp < 0,
    Lte => cmp <= 0,
    Gt => cmp > 0,
    Gte => cmp >= 0,
  }
}

pub fn typed_row_matches(row: &TypedRow, conditions: &Vec[TypedCond]) -> Bool {
  var i = 0;
  while i < conditions.len() {
    let c = conditions[i];
    var v = TValue.VNull;
    if c.column == -1 {
      v = TValue.VInt(row.id);
    } else {
      if c.column < 0 { return false; }
      if c.column >= row.values.len() { return false; }
      v = row.values[c.column];
    }
    if !typed_op_matches(tuple2_compare(v, c.value), c.op) { return false; }
    i = i + 1;
  }
  return true;
}
// ============================================================================
// QUERY PLANNER (from xiom.db.query.planner)
// ============================================================================

pub enum PlanKind {
  FullScan,
  IndexRange,
  PointLookup,
  IndexValue,
}

pub type QueryPlan = {
  kind: PlanKind;
  low: Int;
  high: Int;
  has_bounds: Bool;
  estimated_rows: Int;
}

pub fn query_plan_full_scan() -> QueryPlan {
  return QueryPlan{
    kind: PlanKind.FullScan,
    low: 0, high: 0, has_bounds: false,
    estimated_rows: 0,
  };
}

// Bounds-aware planning (M4.1): key bounds choose an index plan -- a point
// lookup when low == high, a key-range scan otherwise -- and the estimate is
// the clamped range width; without bounds it is a full scan estimated at the
// tree size. The executor applies the value conditions after the key scan.
pub fn plan_query(q: &Query, tree: &BTree) -> QueryPlan {
  return plan_query_with_index(q, tree, false);
}

fn min_i64() -> Int {
  return -9223372036854775807 - 1;
}

fn max_i64() -> Int {
  return 9223372036854775807;
}

// Index-aware planning (M4.2): with a secondary index available and no key
// bounds, the first usable VALUE condition (anything but Neq) becomes an
// IndexValue plan over [low, high] (saturated; an empty range still yields
// an empty result). `low`/`high` mean value bounds under IndexValue and key
// bounds under IndexRange/PointLookup. Key bounds keep precedence.
pub fn plan_query_with_index(q: &Query, tree: &BTree, has_index: Bool) -> QueryPlan {
  var plan = query_plan_full_scan();
  let size = btree_size(tree);
  plan.estimated_rows = size;
  if q.has_bounds {
    plan.low = q.low;
    plan.high = q.high;
    plan.has_bounds = true;
    var width = q.high - q.low + 1;
    if width < 0 { width = 0; } // extreme-bound overflow guard
    var est = width;
    if est > size { est = size; }
    plan.estimated_rows = est;
    if q.low == q.high {
      plan.kind = PlanKind.PointLookup;
    } else {
      plan.kind = PlanKind.IndexRange;
    }
    return plan;
  }

  if has_index {
    var i = 0;
    while i < q.conditions.len() {
      let c = q.conditions[i];
      var lo = 0;
      var hi = 0;
      var usable = true;
      match c.op {
        Eq => {
          lo = c.value;
          hi = c.value;
        }
        Lt => {
          if c.value == min_i64() { usable = false; }
          lo = min_i64();
          hi = c.value - 1;
        }
        Lte => {
          lo = min_i64();
          hi = c.value;
        }
        Gt => {
          if c.value == max_i64() { usable = false; }
          lo = c.value + 1;
          hi = max_i64();
        }
        Gte => {
          lo = c.value;
          hi = max_i64();
        }
        Neq => { usable = false; }
      }
      if usable {
        plan.kind = PlanKind.IndexValue;
        plan.low = lo;
        plan.high = hi;
        plan.has_bounds = false;
        plan.estimated_rows = size;
        if c.op == QueryOp.Eq {
          plan.estimated_rows = 1;
          if size < 1 { plan.estimated_rows = 0; }
        }
        return plan;
      }
      i = i + 1;
    }
  }
  return plan;
}

// IndexValue executor: candidates from the (value, pk) entries in
// [plan.low, plan.high], re-filtered by ALL conditions (the plan only used
// the first usable one to bound the probe), then ordered and sliced exactly
// like the scan path.
pub fn execute_index_value(idx: &SecondaryIndex, plan: &QueryPlan, q: &Query) -> Vec[Int] {
  var vals = Vec[Int].new();
  var pks = Vec[Int].new();
  if plan.low <= plan.high {
    var pos = secidx_lower_bound(idx, plan.low);
    while pos < idx.vals.len() && idx.vals[pos] <= plan.high {
      if matches_all_conditions(idx.vals[pos], q.conditions) {
        vals.push(idx.vals[pos]);
        pks.push(idx.pks[pos]);
      }
      pos = pos + 1;
    }
  }

  if q.order == 0 {
    secidx_sort_pairs_by_pk(&mut vals, &mut pks);
  } else if q.order == 2 {
    secidx_sort_pairs(&mut vals, &mut pks, true);
  }
  // order 1: (value asc, pk asc) is already the index order.

  var out = Vec[Int].new();
  var start = q.offset;
  var end = vals.len();
  if q.limit > 0 && start + q.limit < end {
    end = start + q.limit;
  }
  var k = start;
  while k < end {
    out.push(vals[k]);
    k = k + 1;
  }
  return out;
}

pub fn execute_plan(plan: &QueryPlan, q: &Query, tree: &BTree) -> Vec[Int] {
  match plan.kind {
    FullScan => query_execute(q, tree)
    IndexRange => {
      let values = btree_range_query(tree, plan.low, plan.high);
      apply_filter_values(&values, q)
    }
    PointLookup => {
      let values = btree_range_query(tree, plan.low, plan.low);
      apply_filter_values(&values, q)
    }
    // The file layer routes IndexValue through execute_index_value (it owns
    // the index); when called without one, degrade to the full scan -- the
    // result set is identical, only the probe is missing.
    IndexValue => query_execute(q, tree)
  }
}
// ============================================================================
// ENGINE (from xiom.db.engine)
// ============================================================================

pub type Engine = {
  tree: BTree;
  wal: WAL;
  timestamp_counter: Int;
}

pub fn engine_new(order: Int) -> Engine
  requires: order >= 3
{
  var tree = btree_new(order);
  var wal = wal_new();
  return Engine{ tree: tree, wal: wal, timestamp_counter: 0 };
}

fn next_timestamp(eng: &mut Engine) -> Int {
  eng.timestamp_counter = eng.timestamp_counter + 1;
  return eng.timestamp_counter;
}

pub fn engine_insert(eng: &mut Engine, key: Int, value: Int) -> Bool {
  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.InsertOp, key: key, value: value, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  return btree_insert(&mut eng.tree, key, value);
}

pub fn engine_get(eng: &Engine, key: Int) -> Option[Int] {
  return btree_search(&eng.tree, key);
}

pub fn engine_delete(eng: &mut Engine, key: Int) -> Bool {
  var found = btree_search(&eng.tree, key);
  match found {
    None => return false,
    Some(v) => {}
  }

  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.DeleteOp, key: key, value: 0, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  return btree_delete(&mut eng.tree, key);
}

pub fn engine_update(eng: &mut Engine, key: Int, value: Int) -> Bool {
  var found = btree_search(&eng.tree, key);
  match found {
    None => return false,
    Some(_) => {}
  }

  var ts = next_timestamp(eng);
  var entry = WALEntry{
    op: WALOpType.UpdateOp, key: key, value: value, timestamp: ts,
  };
  wal_append(&mut eng.wal, entry);

  var del = btree_delete(&mut eng.tree, key);
  if !del { return false; }
  return btree_insert(&mut eng.tree, key, value);
}

pub fn engine_query(eng: &Engine, query: &Query) -> Vec[Int] {
  return query_execute(query, &eng.tree);
}

pub fn engine_recover(eng: &mut Engine) -> Bool {
  var fresh = btree_new(eng.tree.order);
  eng.tree = fresh;
  eng.timestamp_counter = 0;
  return wal_replay(&eng.wal, &mut eng.tree);
}

pub fn engine_range_query(eng: &Engine, low: Int, high: Int) -> Vec[Int]
  requires: low <= high
{
  return btree_range_query(&eng.tree, low, high);
}

pub fn engine_size(eng: &Engine) -> Int {
  return btree_size(&eng.tree);
}

pub fn engine_wal_size(eng: &Engine) -> Int {
  return wal_len(&eng.wal);
}

pub fn engine_flush_wal(eng: &mut Engine) {
  wal_clear(&mut eng.wal);
}

pub fn engine_truncate_wal(eng: &mut Engine, before_timestamp: Int)
  requires: before_timestamp >= 0
{
  wal_truncate(&mut eng.wal, before_timestamp);
}
// Apply one replayed record. Maps by op code so cross-module enum patterns
// stay out of this module (1 Insert, 2 Update, 3 Delete). Tagged payloads
// with subtype 1 are typed rows (tuple codec v2 bytes); any other non-empty
// subtype is an unknown future format and the record is SKIPPED (fail closed
// -- applying the int value alone would resurrect wrong data).
pub fn db_file_apply_record(tree: &mut BTree, rec: WALRecord) {
  let code = wal_op_code(rec.op);
  if code == 2 { let _ = btree_delete(tree, rec.key); }
  if code == 3 {
    let _ = btree_delete(tree, rec.key);
    return;
  }
  if code == 1 || code == 2 {
    if rec.payload.len() > 0 {
      if rec.payload[0] != 1 { return; }
      var row = Vec[Int].new();
      var i = 1;
      while i < rec.payload.len() {
        if rec.payload[i] < 0 { return; }   // byte convention: fail closed
        if rec.payload[i] > 255 { return; }
        row.push(rec.payload[i]);
        i = i + 1;
      }
      let _ = btree_insert_payload(tree, rec.key, rec.value, row);
      return;
    }
    let _ = btree_insert(tree, rec.key, rec.value);
  }
}
// Stale-handle guard (multi-handle safety): every handle remembers the WAL
// segment size at its last own write. Another handle appending changes the
// size, so this handle's next write is refused instead of interleaving LSNs
// and corrupting the segment. Optimistic and stateless -- no lock files, so a
// crash cannot leave a stale lock. See docs/ISOLATION.md for the single-writer
// model this enforces.
pub fn db_wal_size(path: Str) -> Int {
  let r = io.file_size(path);
  match r {
    None => { return 0; }
    Some(n) => {
      let size: Int = n;
      return size;
    }
  }
}

pub fn db_file_guard(db: &DBFile) -> Bool {
  return db_wal_size(db.path) == db.wal_bytes;
}
// In-order (key, value) pair collection for index builds.
pub fn btree_collect_pairs(tree: &BTree, node_idx: Int, keys: &mut Vec[Int], vals: &mut Vec[Int]) {
  var node = ns_get(&tree.store, node_idx);
  if node.is_leaf {
    var i = 0;
    while i < node.keys.len() {
      keys.push(node.keys[i]);
      vals.push(node.values[i]);
      i = i + 1;
    }
    return;
  }
  var i = 0;
  while i < node.keys.len() {
    btree_collect_pairs(tree, node.children[i], keys, vals);
    keys.push(node.keys[i]);
    vals.push(node.values[i]);
    i = i + 1;
  }
  btree_collect_pairs(tree, node.children[node.keys.len()], keys, vals);
}

// Mirror one logical value change (old -> new, has_new=false for a delete)
// into every index. Write-back via element assignment per C-ORBIT-03.
pub fn db_file_note_value_change(db: &mut DBFile, key: Int, old: Option[Int], new_value: Int, has_new: Bool) {
  var i = 0;
  while i < db.indexes.len() {
    var idx = db.indexes[i];
    match old {
      Some(v) => { let _ = secidx_remove(&mut idx, v, key); }
      None => {}
    }
    if has_new { secidx_add(&mut idx, new_value, key); }
    db.indexes[i] = idx;
    i = i + 1;
  }
}