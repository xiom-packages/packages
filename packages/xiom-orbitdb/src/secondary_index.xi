// XIOM ORBITDB -- secondary index over VALUES (M4.2).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// An in-memory secondary access path for the flat (Int -> Int) store: entries
// sorted by (value, primary key), so value equality/range probes narrow the
// candidate set without a full scan. Parallel vectors keep the hot cache
// element-write-safe (see COMPILER-FINDINGS C-ORBIT-02: never index-assign an
// Option into a Vec slot; Int slots are fine).
//
// Persistence: indexes are rebuilt on open via `db_file_create_index` (a
// durable catalog representation is a later slice); lifetime is handle-scoped.

module xiom.db.secondary_index

pub type SecondaryIndex = {
  name: Str;
  vals: Vec[Int];
  pks: Vec[Int];
}

pub fn secidx_new(name: Str) -> SecondaryIndex {
  return SecondaryIndex{ name: name, vals: Vec[Int].new(), pks: Vec[Int].new() };
}

pub fn secidx_name(idx: &SecondaryIndex) -> Str {
  return idx.name;
}

pub fn secidx_len(idx: &SecondaryIndex) -> Int {
  return idx.vals.len();
}

// First position with vals[i] >= val (entries sorted by (val, pk)).
pub fn secidx_lower_bound(idx: &SecondaryIndex, val: Int) -> Int {
  var lo = 0;
  var hi = idx.vals.len();
  while lo < hi {
    let mid = lo + (hi - lo) / 2;
    if idx.vals[mid] < val {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

// Insert (val, pk) keeping (val, pk) order. The caller guarantees the exact
// pair is not already present (maintenance tracks value changes).
pub fn secidx_add(idx: &mut SecondaryIndex, val: Int, pk: Int) {
  var pos = secidx_lower_bound(idx, val);
  while pos < idx.vals.len() && idx.vals[pos] == val && idx.pks[pos] < pk {
    pos = pos + 1;
  }
  idx.vals.push(0);
  idx.pks.push(0);
  var i = idx.vals.len() - 1;
  while i > pos {
    idx.vals[i] = idx.vals[i - 1];
    idx.pks[i] = idx.pks[i - 1];
    i = i - 1;
  }
  idx.vals[pos] = val;
  idx.pks[pos] = pk;
}

// Remove the exact pair; false when absent.
pub fn secidx_remove(idx: &mut SecondaryIndex, val: Int, pk: Int) -> Bool {
  var pos = secidx_lower_bound(idx, val);
  while pos < idx.vals.len() && idx.vals[pos] == val {
    if idx.pks[pos] == pk {
      var i = pos;
      while i < idx.vals.len() - 1 {
        idx.vals[i] = idx.vals[i + 1];
        idx.pks[i] = idx.pks[i + 1];
        i = i + 1;
      }
      idx.vals.pop();
      idx.pks.pop();
      return true;
    }
    pos = pos + 1;
  }
  return false;
}

// Primary keys for values in [lo, hi], in (value, pk) order.
pub fn secidx_range_pks(idx: &SecondaryIndex, lo: Int, hi: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if lo > hi { return out; }
  var pos = secidx_lower_bound(idx, lo);
  while pos < idx.vals.len() && idx.vals[pos] <= hi {
    out.push(idx.pks[pos]);
    pos = pos + 1;
  }
  return out;
}

// Stable insertion sort of the pair arrays by value (desc = false ascending,
// true descending); equal values keep their incoming order (pk ascending, as
// the index and the pair collectors produce).
pub fn secidx_sort_pairs(vals: &mut Vec[Int], pks: &mut Vec[Int], desc: Bool) {
  var i = 1;
  while i < vals.len() {
    let v = vals[i];
    let p = pks[i];
    var j = i;
    while j > 0 {
      var move = false;
      if desc {
        move = vals[j - 1] < v;
      } else {
        move = vals[j - 1] > v;
      }
      if !move { break; }
      vals[j] = vals[j - 1];
      pks[j] = pks[j - 1];
      j = j - 1;
    }
    vals[j] = v;
    pks[j] = p;
    i = i + 1;
  }
}

// Stable insertion sort of the pair arrays by PRIMARY KEY ascending (the
// default result order: key order).
pub fn secidx_sort_pairs_by_pk(vals: &mut Vec[Int], pks: &mut Vec[Int]) {
  var i = 1;
  while i < pks.len() {
    let v = vals[i];
    let p = pks[i];
    var j = i;
    while j > 0 && pks[j - 1] > p {
      vals[j] = vals[j - 1];
      pks[j] = pks[j - 1];
      j = j - 1;
    }
    vals[j] = v;
    pks[j] = p;
    i = i + 1;
  }
}
