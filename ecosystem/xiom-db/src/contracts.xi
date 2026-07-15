module xiom.db.contracts

// Shared predicate helpers for the database layer. These encode xiom-db's
// correctness rules as reusable boolean checks so that `requires:` / `ensures:`
// clauses and runtime validation stay in sync. Lower-level predicates
// (page-size, dimension, LSN ordering) are re-used from `xiom.core.contracts`.

fn is_sorted_ints(v: &Vec[Int]) -> Bool {
  var i = 1;
  while i < v.len() {
    if v[i] < v[i - 1] { return false; }
    i = i + 1;
  }
  return true;
}

// The minimum branching factor for a B-tree. Below 3 a node cannot split into
// two non-empty children with a separator key, so the balancing invariants fail.
pub fn valid_btree_order(order: Int) -> Bool {
  return order >= 3;
}

// A key is admissible for the integer-keyed index. Integer keys have no size
// bound, so every value is currently valid; the predicate is the single hook a
// future variable-length key encoding will tighten.
pub fn valid_key(key: Int) -> Bool {
  return true;
}

// Keys must be strictly ascending inside a B-tree node (no duplicates), which
// is a stronger condition than the non-decreasing `is_sorted_ints` check.
pub fn sorted_keys(keys: &Vec[Int]) -> Bool {
  var i = 1;
  while i < keys.len() {
    if keys[i] <= keys[i - 1] { return false; }
    i = i + 1;
  }
  return true;
}

// A range scan is well-formed only when the lower bound does not exceed the
// upper bound.
pub fn valid_range(low: Int, high: Int) -> Bool {
  return low <= high;
}

// Non-decreasing order check delegated to the core predicate, re-exported here
// so index/query code depends on a single db-layer contracts module.
pub fn non_decreasing(values: &Vec[Int]) -> Bool {
  return is_sorted_ints(values);
}
