// XIOM -- xiom.transaction: transaction lifecycle state machine with named savepoints
// Port task: replace the xiom.transaction placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure deterministic bookkeeping: no I/O, no clock access, no FFI, no global
// state. The caller owns the Txn value and drives every transition; the module
// only records the lifecycle state, the operation counter and the named
// savepoints. It performs no database work -- see README.md and SPEC.md for
// the full contract, the error catalog and the documented limitations.
//
// Lifecycle: state 0 idle, 1 active, 2 committed, 3 rolled_back.
//   * txn_begin is accepted from every non-active state and resets the op
//     count and the savepoints; while already active it is rejected (false,
//     no changes).
//   * txn_add_op counts operations only while active.
//   * txn_commit / txn_rollback are accepted only while active; they return
//     the final (commit) or discarded (rollback) op count.
//   * savepoints exist only while active: txn_savepoint anchors a name at the
//     current op count, txn_rollback_to rewinds to a mark, txn_release drops
//     a name while keeping the ops.
//
// Savepoint invariants (see SPEC.md):
//   * names and marks are parallel; marks are non-decreasing along the list;
//   * a duplicate name re-anchors the savepoint at the current op count (it
//     moves to the end of the list), so the ordering invariant is preserved;
//   * txn_rollback_to removes every savepoint after the target, so a mark can
//     never exceed the current op count and the call is repeatable;
//   * txn_commit and txn_rollback keep the savepoint records as inert
//     bookkeeping; the next txn_begin clears them.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the _ok_int/_err_int leaf helpers
//     (constructing Result values directly in other functions miscompiles);
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).

module xiom.transaction

use xiom.string.compare;

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Drop every savepoint, keeping state and ops untouched.
fn _clear_savepoints(t: &mut Txn) {
  while t.names.len() > 0 {
    t.names.pop();
  }
  while t.marks.len() > 0 {
    t.marks.pop();
  }
}

// Index of savepoint `name`, or -1. Str comparisons go through str_compare
// (BUG 17: `==` on Vec[Str] elements lowers to a pointer comparison).
fn _find(t: &Txn, name: Str) -> Int {
  var i = 0;
  while i < t.names.len() {
    if compare.str_compare(t.names[i], name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Remove the savepoint at index `at`, shifting later savepoints down.
fn _remove_at(t: &mut Txn, at: Int) {
  var i = at;
  while i + 1 < t.names.len() {
    let nm: Str = t.names[i + 1];
    let mk: Int = t.marks[i + 1];
    t.names[i] = nm;
    t.marks[i] = mk;
    i = i + 1;
  }
  t.names.pop();
  t.marks.pop();
}

// Drop every savepoint after index `keep` (the prefix up to and including
// `keep` stays).
fn _drop_after(t: &mut Txn, keep: Int) {
  while t.names.len() > keep + 1 {
    t.names.pop();
    t.marks.pop();
  }
}

/// Transaction bookkeeping value: a lifecycle state, an operation counter and
/// the named savepoints.
///
/// Every field is an internal implementation detail; callers must go through
/// the free functions below. Invariants: state is 0 (idle), 1 (active),
/// 2 (committed) or 3 (rolled_back); ops counts the txn_add_op calls since the
/// last successful txn_begin, less any tail discarded by txn_rollback_to;
/// names and marks are parallel (names[i] is anchored at marks[i]) and marks
/// are non-decreasing.
pub type Txn = {
  state: Int;
  ops: Int;
  names: Vec[Str];
  marks: Vec[Int];
}

/// Fresh record: idle, zero ops, no savepoints. No error path.
/// Complexity: O(1).
pub fn txn_new() -> Txn {
  return Txn{ state: 0; ops: 0; names: Vec[Str].new(); marks: Vec[Int].new(); };
}

/// Lifecycle state: 0 idle, 1 active, 2 committed, 3 rolled_back.
/// Complexity: O(1).
pub fn txn_state(t: &Txn) -> Int {
  return t.state;
}

/// Operations recorded by txn_add_op since the last txn_begin, less any tail
/// discarded by txn_rollback_to; 0 again after a rollback or a new begin.
/// Complexity: O(1).
pub fn txn_op_count(t: &Txn) -> Int {
  return t.ops;
}

/// Start a transaction: accepted from every non-active state (idle, committed,
/// rolled_back); resets the op count to 0 and clears every savepoint. While
/// already active the call is rejected and changes nothing.
/// Params: t - the record.
/// Returns: true when the transaction became active, false when it already
/// was. Complexity: O(n) in the number of savepoints (clearing), else O(1).
pub fn txn_begin(t: &mut Txn) -> Bool {
  if t.state == 1 {
    return false;
  }
  t.state = 1;
  t.ops = 0;
  _clear_savepoints(t);
  return true;
}

/// Record one operation.
/// Params: t - the record.
/// Returns: true and ops += 1 while active; false and no change otherwise.
/// Complexity: O(1).
pub fn txn_add_op(t: &mut Txn) -> Bool {
  if t.state != 1 {
    return false;
  }
  t.ops = t.ops + 1;
  return true;
}

/// Commit the active transaction.
/// Params: t - the record.
/// Returns: Ok(op count) after moving to committed; the op count is retained
/// and stays readable through txn_op_count. Err with
/// "transaction: commit requires an active transaction" when the transaction
/// is not active. Savepoints are kept as inert records until the next
/// txn_begin. Complexity: O(1).
pub fn txn_commit(t: &mut Txn) -> Result[Int, Str] {
  if t.state != 1 {
    return _err_int("transaction: commit requires an active transaction");
  }
  t.state = 2;
  let n: Int = t.ops;
  return _ok_int(n);
}

/// Roll back the active transaction.
/// Params: t - the record.
/// Returns: Ok(discarded op count) after moving to rolled_back; the op count
/// is reset to 0. Err with "transaction: rollback requires an active
/// transaction" when the transaction is not active. Savepoints are kept as
/// inert records until the next txn_begin. Complexity: O(1).
pub fn txn_rollback(t: &mut Txn) -> Result[Int, Str] {
  if t.state != 1 {
    return _err_int("transaction: rollback requires an active transaction");
  }
  let n: Int = t.ops;
  t.state = 3;
  t.ops = 0;
  return _ok_int(n);
}

/// Anchor a named savepoint at the current op count.
/// Params: t - the record; name - the savepoint name.
/// Returns: true while active with a non-empty name. A name that already
/// exists is re-anchored: the savepoint moves to the end of the list with the
/// current op count as its new mark (duplicates never nest). An empty name,
/// or a call while not active, returns false and changes nothing.
/// Complexity: O(n) in the number of savepoints.
pub fn txn_savepoint(t: &mut Txn, name: Str) -> Bool {
  if t.state != 1 {
    return false;
  }
  if name.len() == 0 {
    return false;
  }
  let idx = _find(t, name);
  if idx >= 0 {
    _remove_at(t, idx);
  }
  t.names.push(name);
  t.marks.push(t.ops);
  return true;
}

/// Rewind to a named savepoint.
/// Params: t - the record; name - the savepoint name.
/// Returns: Ok(mark) after resetting the op count to the mark; the named
/// savepoint is kept and every savepoint after it is removed, so the list
/// stays non-decreasing and the call is repeatable. Err when the transaction
/// is not active ("transaction: rollback_to requires an active transaction")
/// or when the name is unknown
/// ("transaction: unknown savepoint: <name>").
/// Complexity: O(n) in the number of savepoints.
pub fn txn_rollback_to(t: &mut Txn, name: Str) -> Result[Int, Str] {
  if t.state != 1 {
    return _err_int("transaction: rollback_to requires an active transaction");
  }
  let idx = _find(t, name);
  if idx < 0 {
    return _err_int("transaction: unknown savepoint: " + name);
  }
  let target: Int = t.marks[idx];
  t.ops = target;
  _drop_after(t, idx);
  return _ok_int(target);
}

/// Release a named savepoint; the op count is kept and later savepoints shift
/// down.
/// Params: t - the record; name - the savepoint name.
/// Returns: true when the savepoint existed and was removed; false when the
/// name is unknown or the transaction is not active.
/// Complexity: O(n) in the number of savepoints.
pub fn txn_release(t: &mut Txn, name: Str) -> Bool {
  if t.state != 1 {
    return false;
  }
  let idx = _find(t, name);
  if idx < 0 {
    return false;
  }
  _remove_at(t, idx);
  return true;
}

/// Number of savepoints. Complexity: O(1).
pub fn txn_savepoint_count(t: &Txn) -> Int {
  return t.names.len();
}

/// Savepoint name at index i (in order), or "" when i is out of range.
/// Complexity: O(1).
pub fn txn_savepoint_name(t: &Txn, i: Int) -> Str {
  if i < 0 || i >= t.names.len() {
    return "";
  }
  let nm: Str = t.names[i];
  return nm;
}

/// Op count anchored by `name`, or -1 when the name is unknown.
/// Complexity: O(n) in the number of savepoints.
pub fn txn_mark(t: &Txn, name: Str) -> Int {
  let idx = _find(t, name);
  if idx < 0 {
    return -1;
  }
  let mk: Int = t.marks[idx];
  return mk;
}
