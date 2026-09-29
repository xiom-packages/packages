// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.stm: deterministic software-transactional-memory primitives.
// Port task: replace the xiom.stm placeholder with a real, tested, pure-XIOM
// package. No threads, no atomics, no clock, no FFI: this module is a
// single-threaded, deterministic model of optimistic STM. Interleavings are
// driven explicitly by the caller (begin A, read A, begin B, commit B,
// commit A...), so every conflict and retry outcome is reproducible.
//
// Model (full rules in SPEC.md):
//   * A shared version clock (_stm_clock) starts at 0 and increments by
//     exactly one on every successful commit.
//   * A cell (TVar-like) holds a committed value and the version of the
//     commit that last wrote it (0 = initial value, never committed).
//   * A transaction is an explicit state machine: Active -> Committed or
//     Aborted. Reads record the cell's version on first read (read set);
//     writes buffer values (write set, read-your-writes). Commit validates
//     every read-set version and then every write-set version against the
//     current cell versions; the first stale entry aborts the transaction
//     with a reason code and nothing is applied. On success every buffered
//     write is applied with one shared commit version.
//   * Retry is explicit and deterministic: stm_retry restarts an aborted
//     transaction as a fresh attempt (new epoch, empty logical sets) while
//     the per-transaction retry budget lasts; there is no spinning.
//
// Language notes (XIOM v0.62.1) that shaped this module:
//   * free functions only; module-level parallel Vec[Int] state, no
//     Vec[StructType], no struct out-parameters;
//   * every Vec[Int] element read is bound with a typed `let`;
//   * Ok/Err for the struct payload are constructed only inside the leaf
//     helpers _stm_ok / _stm_err;
//   * retried attempts are isolated with a per-transaction epoch counter,
//     so stale read/write set entries can never be mistaken for live ones
//     (no table compaction, no vector reassignment);
//   * no bitwise operators, no `as`, no floats.

module xiom.stm

use xiom.convert;
use xiom.convert.int;

// --------------------------------------------------
//  Limits
// --------------------------------------------------

// Maximum number of cells per reset.
const _STM_MAX_CELLS: Int = 1024;

// Maximum number of transactions per reset.
const _STM_MAX_TXNS: Int = 1024;

// Per-transaction caps on the read set and the write set.
const _STM_MAX_RS_PER_TXN: Int = 64;
const _STM_MAX_WS_PER_TXN: Int = 64;

// Global caps on the flattened read/write set tables.
const _STM_MAX_RS_ENTRIES: Int = 8192;
const _STM_MAX_WS_ENTRIES: Int = 8192;

// Retries stm_retry grants per transaction before Err code 8.
const _STM_MAX_RETRIES: Int = 4;

// "Not applicable" filler for StmError and dump fields.
const _STM_NONE: Int = -1;

// --------------------------------------------------
//  Transaction states
// --------------------------------------------------

const _STM_STATE_ACTIVE: Int = 1;
const _STM_STATE_COMMITTED: Int = 2;
const _STM_STATE_ABORTED: Int = 3;

// --------------------------------------------------
//  StmError codes (pinned messages in stm_error_message)
// --------------------------------------------------

const _STM_ERR_CELL_CAPACITY: Int = 1;
const _STM_ERR_CELL_INVALID: Int = 2;
const _STM_ERR_TXN_INVALID: Int = 3;
const _STM_ERR_TXN_STATE: Int = 4;
const _STM_ERR_RS_FULL: Int = 5;
const _STM_ERR_WS_FULL: Int = 6;
const _STM_ERR_CONFLICT: Int = 7;
const _STM_ERR_RETRY_LIMIT: Int = 8;
const _STM_ERR_TXN_CAPACITY: Int = 9;

// --------------------------------------------------
//  Abort reasons (pinned messages in stm_abort_reason_message)
// --------------------------------------------------

const _STM_ABORT_NONE: Int = 0;
const _STM_ABORT_READ_CONFLICT: Int = 1;
const _STM_ABORT_WRITE_CONFLICT: Int = 2;
const _STM_ABORT_USER: Int = 3;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// Typed error carried by every fallible STM operation. `code` identifies
/// the failure (see stm_error_message); `txn` is the transaction handle or
/// -1; `cell` is the cell id or -1; `extra` is the bound, state or reason
/// context (-1 when none).
pub type StmError = {
  code: Int;
  txn: Int;
  cell: Int;
  extra: Int;
}

// --------------------------------------------------
//  Result leaves (Ok/Err construction is confined here)
// --------------------------------------------------

// Ok(v) for Result[Int, StmError].
fn _stm_ok(v: Int) -> Result[Int, StmError] {
  return Ok(v);
}

// Err quad for Result[Int, StmError].
fn _stm_err(code: Int, txn: Int, cell: Int, extra: Int) -> Result[Int, StmError] {
  let e = StmError{ code: code; txn: txn; cell: cell; extra: extra; };
  return Err(e);
}

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Decimal text for a possibly negative Int (int_to_base is exact across the
// full Int range, sign included).
fn _stm_dec(n: Int) -> Str {
  return int_to_base(n, 10);
}

// --------------------------------------------------
//  Module state: clock, cells, transactions, sets, stats
// --------------------------------------------------

// Shared version clock: 0 before the first commit, +1 per successful commit.
var _stm_clock: Int = 0;

// Cells: committed value, last-committing version, commit count.
var _stm_cell_value: Vec[Int] = Vec[Int].new();
var _stm_cell_version: Vec[Int] = Vec[Int].new();
var _stm_cell_commits: Vec[Int] = Vec[Int].new();

// Transactions: state, attempt epoch, start version, attempt number, retry
// count, abort reason, conflicting cell.
var _stm_tx_state: Vec[Int] = Vec[Int].new();
var _stm_tx_epoch: Vec[Int] = Vec[Int].new();
var _stm_tx_start_version: Vec[Int] = Vec[Int].new();
var _stm_tx_attempt: Vec[Int] = Vec[Int].new();
var _stm_tx_retries: Vec[Int] = Vec[Int].new();
var _stm_tx_abort_reason: Vec[Int] = Vec[Int].new();
var _stm_tx_conflict_cell: Vec[Int] = Vec[Int].new();

// Flattened read set: (txn, epoch, cell, version recorded at first read).
var _stm_rs_txn: Vec[Int] = Vec[Int].new();
var _stm_rs_epoch: Vec[Int] = Vec[Int].new();
var _stm_rs_cell: Vec[Int] = Vec[Int].new();
var _stm_rs_version: Vec[Int] = Vec[Int].new();

// Flattened write set: (txn, epoch, cell, buffered value, version recorded
// at first write).
var _stm_ws_txn: Vec[Int] = Vec[Int].new();
var _stm_ws_epoch: Vec[Int] = Vec[Int].new();
var _stm_ws_cell: Vec[Int] = Vec[Int].new();
var _stm_ws_value: Vec[Int] = Vec[Int].new();
var _stm_ws_version: Vec[Int] = Vec[Int].new();

// Statistics since the last stm_reset.
var _stm_stat_commits: Int = 0;
var _stm_stat_aborts: Int = 0;
var _stm_stat_conflicts: Int = 0;
var _stm_stat_retries: Int = 0;
var _stm_stat_reads: Int = 0;
var _stm_stat_writes: Int = 0;
var _stm_stat_user_aborts: Int = 0;

// --------------------------------------------------
//  Internal validation helpers
// --------------------------------------------------

// True when `cell` names a cell created since the last stm_reset.
fn _stm_cell_valid(cell: Int) -> Bool {
  return cell >= 0 && cell < _stm_cell_value.len();
}

// True when `txn` names a transaction begun since the last stm_reset.
fn _stm_txn_valid(txn: Int) -> Bool {
  return txn >= 0 && txn < _stm_tx_state.len();
}

// Index of the (txn, epoch, cell) read-set entry, -1 when absent.
fn _stm_rs_find(txn: Int, epoch: Int, cell: Int) -> Int {
  var i = 0;
  while i < _stm_rs_txn.len() {
    let t: Int = _stm_rs_txn[i];
    if t == txn {
      let e: Int = _stm_rs_epoch[i];
      if e == epoch {
        let c: Int = _stm_rs_cell[i];
        if c == cell {
          return i;
        }
      }
    }
    i = i + 1;
  }
  return _STM_NONE;
}

// Number of live (current-epoch) read-set entries for `txn`.
fn _stm_rs_count(txn: Int, epoch: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < _stm_rs_txn.len() {
    let t: Int = _stm_rs_txn[i];
    if t == txn {
      let e: Int = _stm_rs_epoch[i];
      if e == epoch {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// Record a first read of (cell) at `version`. Returns 0 on success, or the
// read-set-full error code when a per-transaction or global cap is hit.
fn _stm_rs_push(txn: Int, epoch: Int, cell: Int, version: Int) -> Int {
  if _stm_rs_count(txn, epoch) >= _STM_MAX_RS_PER_TXN {
    return _STM_ERR_RS_FULL;
  }
  if _stm_rs_txn.len() >= _STM_MAX_RS_ENTRIES {
    return _STM_ERR_RS_FULL;
  }
  _stm_rs_txn.push(txn);
  _stm_rs_epoch.push(epoch);
  _stm_rs_cell.push(cell);
  _stm_rs_version.push(version);
  return 0;
}

// Index of the (txn, epoch, cell) write-set entry, -1 when absent.
fn _stm_ws_find(txn: Int, epoch: Int, cell: Int) -> Int {
  var i = 0;
  while i < _stm_ws_txn.len() {
    let t: Int = _stm_ws_txn[i];
    if t == txn {
      let e: Int = _stm_ws_epoch[i];
      if e == epoch {
        let c: Int = _stm_ws_cell[i];
        if c == cell {
          return i;
        }
      }
    }
    i = i + 1;
  }
  return _STM_NONE;
}

// Number of live (current-epoch) write-set entries for `txn`.
fn _stm_ws_count(txn: Int, epoch: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < _stm_ws_txn.len() {
    let t: Int = _stm_ws_txn[i];
    if t == txn {
      let e: Int = _stm_ws_epoch[i];
      if e == epoch {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// Buffer a first write of (cell) with `value`, recording the cell version
// seen at write time. Returns 0 on success, or the write-set-full error code
// when a per-transaction or global cap is hit.
fn _stm_ws_push(txn: Int, epoch: Int, cell: Int, value: Int, version: Int) -> Int {
  if _stm_ws_count(txn, epoch) >= _STM_MAX_WS_PER_TXN {
    return _STM_ERR_WS_FULL;
  }
  if _stm_ws_txn.len() >= _STM_MAX_WS_ENTRIES {
    return _STM_ERR_WS_FULL;
  }
  _stm_ws_txn.push(txn);
  _stm_ws_epoch.push(epoch);
  _stm_ws_cell.push(cell);
  _stm_ws_value.push(value);
  _stm_ws_version.push(version);
  return 0;
}

// First read-set entry of `txn` whose recorded version no longer matches the
// cell, in insertion order; -1 when every recorded version still matches.
fn _stm_first_read_conflict(txn: Int, epoch: Int) -> Int {
  var i = 0;
  while i < _stm_rs_txn.len() {
    let t: Int = _stm_rs_txn[i];
    if t == txn {
      let e: Int = _stm_rs_epoch[i];
      if e == epoch {
        let c: Int = _stm_rs_cell[i];
        let rec: Int = _stm_rs_version[i];
        let cur: Int = _stm_cell_version[c];
        if cur != rec {
          return c;
        }
      }
    }
    i = i + 1;
  }
  return _STM_NONE;
}

// First write-set entry of `txn` whose recorded version no longer matches the
// cell, in insertion order; -1 when every recorded version still matches.
// This is the blind-write (write-write) conflict detector.
fn _stm_first_write_conflict(txn: Int, epoch: Int) -> Int {
  var i = 0;
  while i < _stm_ws_txn.len() {
    let t: Int = _stm_ws_txn[i];
    if t == txn {
      let e: Int = _stm_ws_epoch[i];
      if e == epoch {
        let c: Int = _stm_ws_cell[i];
        let rec: Int = _stm_ws_version[i];
        let cur: Int = _stm_cell_version[c];
        if cur != rec {
          return c;
        }
      }
    }
    i = i + 1;
  }
  return _STM_NONE;
}

// --------------------------------------------------
//  Lifecycle
// --------------------------------------------------

/// Reset every cell, transaction, read/write set entry and statistic, and
/// set the version clock back to 0. This is a full reset, not a resize.
/// Complexity: O(state).
pub fn stm_reset() {
  _stm_clock = 0;
  _stm_cell_value.clear();
  _stm_cell_version.clear();
  _stm_cell_commits.clear();
  _stm_tx_state.clear();
  _stm_tx_epoch.clear();
  _stm_tx_start_version.clear();
  _stm_tx_attempt.clear();
  _stm_tx_retries.clear();
  _stm_tx_abort_reason.clear();
  _stm_tx_conflict_cell.clear();
  _stm_rs_txn.clear();
  _stm_rs_epoch.clear();
  _stm_rs_cell.clear();
  _stm_rs_version.clear();
  _stm_ws_txn.clear();
  _stm_ws_epoch.clear();
  _stm_ws_cell.clear();
  _stm_ws_value.clear();
  _stm_ws_version.clear();
  _stm_stat_commits = 0;
  _stm_stat_aborts = 0;
  _stm_stat_conflicts = 0;
  _stm_stat_retries = 0;
  _stm_stat_reads = 0;
  _stm_stat_writes = 0;
  _stm_stat_user_aborts = 0;
}

/// Current version clock: the version of the most recent successful commit,
/// 0 before the first commit. Complexity: O(1).
pub fn stm_clock() -> Int {
  return _stm_clock;
}

/// Number of cells created since the last stm_reset. Complexity: O(1).
pub fn stm_cell_count() -> Int {
  return _stm_cell_value.len();
}

/// Number of transactions begun since the last stm_reset. Complexity: O(1).
pub fn stm_txn_count() -> Int {
  return _stm_tx_state.len();
}

/// Largest number of cells stm_cell_new accepts per reset: 1024.
/// Complexity: O(1).
pub fn stm_max_cells() -> Int {
  return _STM_MAX_CELLS;
}

/// Largest number of transactions stm_txn_begin accepts per reset: 1024.
/// Complexity: O(1).
pub fn stm_max_txns() -> Int {
  return _STM_MAX_TXNS;
}

/// Per-transaction read-set cap: 64 entries. Complexity: O(1).
pub fn stm_max_read_set_entries() -> Int {
  return _STM_MAX_RS_PER_TXN;
}

/// Per-transaction write-set cap: 64 entries. Complexity: O(1).
pub fn stm_max_write_set_entries() -> Int {
  return _STM_MAX_WS_PER_TXN;
}

/// Retries stm_retry grants per transaction: 4. Complexity: O(1).
pub fn stm_max_retries() -> Int {
  return _STM_MAX_RETRIES;
}

// --------------------------------------------------
//  Cells (TVar-like)
// --------------------------------------------------

/// Create a cell holding `initial_value` at version 0 (never committed).
/// Returns: Ok(cell id) - ids are dense from 0 in creation order.
/// Error case: 1 cell capacity exceeded (txn = -1, cell = -1, extra =
/// stm_max_cells()); nothing is created.
/// Complexity: O(1).
pub fn stm_cell_new(initial_value: Int) -> Result[Int, StmError] {
  if _stm_cell_value.len() >= _STM_MAX_CELLS {
    return _stm_err(_STM_ERR_CELL_CAPACITY, _STM_NONE, _STM_NONE, _STM_MAX_CELLS);
  }
  _stm_cell_value.push(initial_value);
  _stm_cell_version.push(0);
  _stm_cell_commits.push(0);
  let id: Int = _stm_cell_value.len() - 1;
  return _stm_ok(id);
}

/// Committed value of `cell` (writes buffered in active transactions are not
/// visible here).
/// Returns: Ok(value).
/// Error case: 2 invalid cell (txn = -1, cell = cell, extra = -1).
/// Complexity: O(1).
pub fn stm_cell_value(cell: Int) -> Result[Int, StmError] {
  if !_stm_cell_valid(cell) {
    return _stm_err(_STM_ERR_CELL_INVALID, _STM_NONE, cell, _STM_NONE);
  }
  let v: Int = _stm_cell_value[cell];
  return _stm_ok(v);
}

/// Version of the last commit that wrote `cell`; 0 until the first such
/// commit. Complexity: O(1).
pub fn stm_cell_version(cell: Int) -> Result[Int, StmError] {
  if !_stm_cell_valid(cell) {
    return _stm_err(_STM_ERR_CELL_INVALID, _STM_NONE, cell, _STM_NONE);
  }
  let v: Int = _stm_cell_version[cell];
  return _stm_ok(v);
}

/// Number of commits that wrote `cell`. Complexity: O(1).
pub fn stm_cell_commit_count(cell: Int) -> Result[Int, StmError] {
  if !_stm_cell_valid(cell) {
    return _stm_err(_STM_ERR_CELL_INVALID, _STM_NONE, cell, _STM_NONE);
  }
  let v: Int = _stm_cell_commits[cell];
  return _stm_ok(v);
}

// --------------------------------------------------
//  Transactions
// --------------------------------------------------

/// Begin a transaction in the Active state with attempt 1, zero retries and
/// the current clock as its start version.
/// Returns: Ok(txn) - dense handles from 0 in begin order.
/// Error case: 9 transaction capacity exceeded (txn = -1, cell = -1,
/// extra = stm_max_txns()); nothing is created.
/// Complexity: O(1).
pub fn stm_txn_begin() -> Result[Int, StmError] {
  if _stm_tx_state.len() >= _STM_MAX_TXNS {
    return _stm_err(_STM_ERR_TXN_CAPACITY, _STM_NONE, _STM_NONE, _STM_MAX_TXNS);
  }
  let id: Int = _stm_tx_state.len();
  _stm_tx_state.push(_STM_STATE_ACTIVE);
  _stm_tx_epoch.push(0);
  _stm_tx_start_version.push(_stm_clock);
  _stm_tx_attempt.push(1);
  _stm_tx_retries.push(0);
  _stm_tx_abort_reason.push(_STM_ABORT_NONE);
  _stm_tx_conflict_cell.push(_STM_NONE);
  return _stm_ok(id);
}

/// State of `txn`: 1 = Active, 2 = Committed, 3 = Aborted.
/// Error case: 3 invalid transaction (cell = -1, extra = -1).
/// Complexity: O(1).
pub fn stm_txn_state(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let s: Int = _stm_tx_state[txn];
  return _stm_ok(s);
}

/// Version clock observed when the current attempt began. Complexity: O(1).
pub fn stm_txn_start_version(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let v: Int = _stm_tx_start_version[txn];
  return _stm_ok(v);
}

/// 1-based attempt number: 1 after begin, +1 per successful stm_retry.
/// Complexity: O(1).
pub fn stm_txn_attempt(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let v: Int = _stm_tx_attempt[txn];
  return _stm_ok(v);
}

/// Retries granted to `txn` so far (0..stm_max_retries()). Complexity: O(1).
pub fn stm_txn_retry_count(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let v: Int = _stm_tx_retries[txn];
  return _stm_ok(v);
}

/// Abort reason of `txn` since the last begin or retry: 0 none, 1 read
/// conflict, 2 write conflict, 3 user abort (stm_abort).
/// Complexity: O(1).
pub fn stm_txn_abort_reason(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let v: Int = _stm_tx_abort_reason[txn];
  return _stm_ok(v);
}

/// Cell that caused the last conflict abort of `txn`, -1 when the last
/// attempt did not abort on a conflict. Complexity: O(1).
pub fn stm_txn_conflict_cell(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let v: Int = _stm_tx_conflict_cell[txn];
  return _stm_ok(v);
}

/// Live (current-attempt) read-set entries of `txn`. Entries of earlier,
/// retried attempts are inert and not counted; entries persist after commit
/// or abort for introspection until stm_reset. Complexity: O(entries).
pub fn stm_txn_read_set_size(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let epoch: Int = _stm_tx_epoch[txn];
  return _stm_ok(_stm_rs_count(txn, epoch));
}

/// Live (current-attempt) write-set entries of `txn`; see
/// stm_txn_read_set_size for the persistence rule. Complexity: O(entries).
pub fn stm_txn_write_set_size(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let epoch: Int = _stm_tx_epoch[txn];
  return _stm_ok(_stm_ws_count(txn, epoch));
}

// --------------------------------------------------
//  Transactional operations
// --------------------------------------------------

/// Read `cell` inside `txn`. Read-your-writes: a buffered write wins. On the
/// first read of a cell the cell's current version is recorded in the read
/// set; later reads of the same cell do not add entries. Reads observe the
/// latest committed value (validation still compares the version recorded at
/// the first read).
/// Returns: Ok(value).
/// Error cases: 2 invalid cell; 3 invalid transaction; 4 transaction is not
/// active (extra = current state, cell = cell); 5 read set is full
/// (extra = stm_max_read_set_entries()).
/// Complexity: O(read set entries).
pub fn stm_read(txn: Int, cell: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, cell, _STM_NONE);
  }
  if !_stm_cell_valid(cell) {
    return _stm_err(_STM_ERR_CELL_INVALID, txn, cell, _STM_NONE);
  }
  let state: Int = _stm_tx_state[txn];
  if state != _STM_STATE_ACTIVE {
    return _stm_err(_STM_ERR_TXN_STATE, txn, cell, state);
  }
  let epoch: Int = _stm_tx_epoch[txn];
  let wi = _stm_ws_find(txn, epoch, cell);
  if wi >= 0 {
    let wv: Int = _stm_ws_value[wi];
    _stm_stat_reads = _stm_stat_reads + 1;
    return _stm_ok(wv);
  }
  let ri = _stm_rs_find(txn, epoch, cell);
  if ri < 0 {
    let cv: Int = _stm_cell_version[cell];
    let rc = _stm_rs_push(txn, epoch, cell, cv);
    if rc != 0 {
      return _stm_err(rc, txn, cell, _STM_MAX_RS_PER_TXN);
    }
  }
  let value: Int = _stm_cell_value[cell];
  _stm_stat_reads = _stm_stat_reads + 1;
  return _stm_ok(value);
}

/// Buffer the write `value` to `cell` inside `txn` (invisible until the
/// transaction commits). The first write of a cell records the cell version
/// seen at write time; later writes overwrite the buffered value and keep
/// that version.
/// Returns: Ok(write-set size after the call, >= 1).
/// Error cases: 2 invalid cell; 3 invalid transaction; 4 transaction is not
/// active (extra = current state, cell = cell); 6 write set is full
/// (extra = stm_max_write_set_entries()).
/// Complexity: O(write set entries).
pub fn stm_write(txn: Int, cell: Int, value: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, cell, _STM_NONE);
  }
  if !_stm_cell_valid(cell) {
    return _stm_err(_STM_ERR_CELL_INVALID, txn, cell, _STM_NONE);
  }
  let state: Int = _stm_tx_state[txn];
  if state != _STM_STATE_ACTIVE {
    return _stm_err(_STM_ERR_TXN_STATE, txn, cell, state);
  }
  let epoch: Int = _stm_tx_epoch[txn];
  let wi = _stm_ws_find(txn, epoch, cell);
  if wi >= 0 {
    _stm_ws_value[wi] = value;
    _stm_stat_writes = _stm_stat_writes + 1;
    return _stm_ok(_stm_ws_count(txn, epoch));
  }
  let cv: Int = _stm_cell_version[cell];
  let rc = _stm_ws_push(txn, epoch, cell, value, cv);
  if rc != 0 {
    return _stm_err(rc, txn, cell, _STM_MAX_WS_PER_TXN);
  }
  _stm_stat_writes = _stm_stat_writes + 1;
  return _stm_ok(_stm_ws_count(txn, epoch));
}

/// Optimistic commit of `txn`. Validation order is deterministic: read-set
/// entries in insertion order first (reason 1), then write-set entries in
/// insertion order (reason 2); the first stale version found aborts the
/// transaction, applies nothing and returns Err code 7. On success every
/// buffered write is applied atomically with one shared version
/// (clock + 1), the clock advances by exactly one and the transaction
/// becomes Committed.
/// Returns: Ok(new version = old clock + 1).
/// Error cases: 3 invalid transaction; 4 transaction is not active
/// (extra = current state); 7 conflict (cell = first conflicting cell,
/// extra = abort reason).
/// Complexity: O(read set + write set entries).
pub fn stm_commit(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let state: Int = _stm_tx_state[txn];
  if state != _STM_STATE_ACTIVE {
    return _stm_err(_STM_ERR_TXN_STATE, txn, _STM_NONE, state);
  }
  let epoch: Int = _stm_tx_epoch[txn];
  var conflict = _STM_NONE;
  var reason = _STM_ABORT_NONE;
  let rc = _stm_first_read_conflict(txn, epoch);
  if rc != _STM_NONE {
    conflict = rc;
    reason = _STM_ABORT_READ_CONFLICT;
  }
  if conflict == _STM_NONE {
    let wc = _stm_first_write_conflict(txn, epoch);
    if wc != _STM_NONE {
      conflict = wc;
      reason = _STM_ABORT_WRITE_CONFLICT;
    }
  }
  if conflict != _STM_NONE {
    _stm_tx_state[txn] = _STM_STATE_ABORTED;
    _stm_tx_abort_reason[txn] = reason;
    _stm_tx_conflict_cell[txn] = conflict;
    _stm_stat_aborts = _stm_stat_aborts + 1;
    _stm_stat_conflicts = _stm_stat_conflicts + 1;
    return _stm_err(_STM_ERR_CONFLICT, txn, conflict, reason);
  }
  let new_version: Int = _stm_clock + 1;
  var i = 0;
  while i < _stm_ws_txn.len() {
    let t: Int = _stm_ws_txn[i];
    if t == txn {
      let e: Int = _stm_ws_epoch[i];
      if e == epoch {
        let c: Int = _stm_ws_cell[i];
        let v: Int = _stm_ws_value[i];
        _stm_cell_value[c] = v;
        _stm_cell_version[c] = new_version;
        let cc: Int = _stm_cell_commits[c];
        _stm_cell_commits[c] = cc + 1;
      }
    }
    i = i + 1;
  }
  _stm_clock = new_version;
  _stm_tx_state[txn] = _STM_STATE_COMMITTED;
  _stm_stat_commits = _stm_stat_commits + 1;
  return _stm_ok(new_version);
}

/// Abort `txn` explicitly with abort reason 3 (user abort). The read and
/// write sets become inert and nothing is applied.
/// Returns: Ok(3) - the pinned user abort reason.
/// Error cases: 3 invalid transaction; 4 transaction is not active
/// (extra = current state).
/// Complexity: O(1).
pub fn stm_abort(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let state: Int = _stm_tx_state[txn];
  if state != _STM_STATE_ACTIVE {
    return _stm_err(_STM_ERR_TXN_STATE, txn, _STM_NONE, state);
  }
  _stm_tx_state[txn] = _STM_STATE_ABORTED;
  _stm_tx_abort_reason[txn] = _STM_ABORT_USER;
  _stm_tx_conflict_cell[txn] = _STM_NONE;
  _stm_stat_aborts = _stm_stat_aborts + 1;
  _stm_stat_user_aborts = _stm_stat_user_aborts + 1;
  return _stm_ok(_STM_ABORT_USER);
}

/// Restart an aborted `txn` as a fresh attempt: state Active, attempt + 1,
/// retry count + 1, start version = current clock, empty logical read/write
/// sets (the new epoch makes earlier entries inert).
/// Returns: Ok(attempt number, >= 2).
/// Error cases: 3 invalid transaction; 4 transaction is not active, i.e.
/// not Aborted (extra = current state); 8 retry limit reached
/// (extra = stm_max_retries()); the transaction stays Aborted.
/// Complexity: O(1).
pub fn stm_retry(txn: Int) -> Result[Int, StmError] {
  if !_stm_txn_valid(txn) {
    return _stm_err(_STM_ERR_TXN_INVALID, txn, _STM_NONE, _STM_NONE);
  }
  let state: Int = _stm_tx_state[txn];
  if state != _STM_STATE_ABORTED {
    return _stm_err(_STM_ERR_TXN_STATE, txn, _STM_NONE, state);
  }
  let retries: Int = _stm_tx_retries[txn];
  if retries >= _STM_MAX_RETRIES {
    return _stm_err(_STM_ERR_RETRY_LIMIT, txn, _STM_NONE, _STM_MAX_RETRIES);
  }
  let epoch: Int = _stm_tx_epoch[txn];
  let attempt: Int = _stm_tx_attempt[txn];
  _stm_tx_epoch[txn] = epoch + 1;
  _stm_tx_attempt[txn] = attempt + 1;
  _stm_tx_retries[txn] = retries + 1;
  _stm_tx_start_version[txn] = _stm_clock;
  _stm_tx_abort_reason[txn] = _STM_ABORT_NONE;
  _stm_tx_conflict_cell[txn] = _STM_NONE;
  _stm_tx_state[txn] = _STM_STATE_ACTIVE;
  _stm_stat_retries = _stm_stat_retries + 1;
  return _stm_ok(attempt + 1);
}

// --------------------------------------------------
//  Statistics
// --------------------------------------------------

/// Successful commits since the last stm_reset. Complexity: O(1).
pub fn stm_commits() -> Int {
  return _stm_stat_commits;
}

/// Aborts (conflict or user) since the last stm_reset. Complexity: O(1).
pub fn stm_aborts() -> Int {
  return _stm_stat_aborts;
}

/// Conflict aborts since the last stm_reset. Complexity: O(1).
pub fn stm_conflicts() -> Int {
  return _stm_stat_conflicts;
}

/// Retries granted since the last stm_reset. Complexity: O(1).
pub fn stm_retries() -> Int {
  return _stm_stat_retries;
}

/// Successful reads since the last stm_reset. Complexity: O(1).
pub fn stm_reads() -> Int {
  return _stm_stat_reads;
}

/// Successful writes since the last stm_reset. Complexity: O(1).
pub fn stm_writes() -> Int {
  return _stm_stat_writes;
}

/// User aborts (stm_abort) since the last stm_reset. Complexity: O(1).
pub fn stm_user_aborts() -> Int {
  return _stm_stat_user_aborts;
}

// --------------------------------------------------
//  Dumps and error catalogs
// --------------------------------------------------

/// One-line cell dump for tests. Format:
/// cells[n=.. clock=..] c<id>[v=.. ver=.. commits=..] ...
/// Complexity: O(cells).
pub fn stm_cell_dump() -> Str {
  var out = "cells[n=" + _stm_dec(_stm_cell_value.len());
  out = out + " clock=" + _stm_dec(_stm_clock) + "]";
  var i = 0;
  while i < _stm_cell_value.len() {
    let v: Int = _stm_cell_value[i];
    let ver: Int = _stm_cell_version[i];
    let cc: Int = _stm_cell_commits[i];
    out = out + " c" + _stm_dec(i);
    out = out + "[v=" + _stm_dec(v);
    out = out + " ver=" + _stm_dec(ver);
    out = out + " commits=" + _stm_dec(cc) + "]";
    i = i + 1;
  }
  return out;
}

/// One-line transaction dump for tests. Format:
/// txn[<id> state=.. attempt=.. retries=.. start=.. rs=.. ws=.. abort=.. conflict=..]
/// Invalid handles print "txn[invalid]".
/// Complexity: O(read set + write set entries).
pub fn stm_txn_dump(txn: Int) -> Str {
  if !_stm_txn_valid(txn) {
    return "txn[invalid]";
  }
  let state: Int = _stm_tx_state[txn];
  let epoch: Int = _stm_tx_epoch[txn];
  var out = "txn[" + _stm_dec(txn);
  out = out + " state=" + _stm_dec(state);
  let attempt: Int = _stm_tx_attempt[txn];
  out = out + " attempt=" + _stm_dec(attempt);
  let retries: Int = _stm_tx_retries[txn];
  out = out + " retries=" + _stm_dec(retries);
  let start: Int = _stm_tx_start_version[txn];
  out = out + " start=" + _stm_dec(start);
  out = out + " rs=" + _stm_dec(_stm_rs_count(txn, epoch));
  out = out + " ws=" + _stm_dec(_stm_ws_count(txn, epoch));
  let reason: Int = _stm_tx_abort_reason[txn];
  out = out + " abort=" + _stm_dec(reason);
  let conflict: Int = _stm_tx_conflict_cell[txn];
  out = out + " conflict=" + _stm_dec(conflict) + "]";
  return out;
}

/// One-line statistics dump for tests. Format:
/// stats[commits=.. aborts=.. conflicts=.. retries=.. reads=.. writes=.. user_aborts=..]
/// Complexity: O(1).
pub fn stm_stats_dump() -> Str {
  var out = "stats[commits=" + _stm_dec(_stm_stat_commits);
  out = out + " aborts=" + _stm_dec(_stm_stat_aborts);
  out = out + " conflicts=" + _stm_dec(_stm_stat_conflicts);
  out = out + " retries=" + _stm_dec(_stm_stat_retries);
  out = out + " reads=" + _stm_dec(_stm_stat_reads);
  out = out + " writes=" + _stm_dec(_stm_stat_writes);
  out = out + " user_aborts=" + _stm_dec(_stm_stat_user_aborts) + "]";
  return out;
}

/// Combined multi-line state dump for tests: stm_cell_dump() and
/// stm_stats_dump() joined with a newline separator.
/// Complexity: O(cells).
pub fn stm_dump() -> Str {
  return stm_cell_dump() + "\n" + stm_stats_dump();
}

/// Pinned message for an StmError code; "stm: unknown error" for codes
/// outside the catalog. Complexity: O(1).
pub fn stm_error_message(code: Int) -> Str {
  if code == _STM_ERR_CELL_CAPACITY {
    return "stm: cell capacity exceeded";
  }
  if code == _STM_ERR_CELL_INVALID {
    return "stm: invalid cell id";
  }
  if code == _STM_ERR_TXN_INVALID {
    return "stm: invalid transaction id";
  }
  if code == _STM_ERR_TXN_STATE {
    return "stm: transaction is not active";
  }
  if code == _STM_ERR_RS_FULL {
    return "stm: read set is full";
  }
  if code == _STM_ERR_WS_FULL {
    return "stm: write set is full";
  }
  if code == _STM_ERR_CONFLICT {
    return "stm: transaction conflict";
  }
  if code == _STM_ERR_RETRY_LIMIT {
    return "stm: retry limit reached";
  }
  if code == _STM_ERR_TXN_CAPACITY {
    return "stm: transaction capacity exceeded";
  }
  return "stm: unknown error";
}

/// Pinned message for an abort reason; "stm: unknown abort reason" outside
/// the catalog. Complexity: O(1).
pub fn stm_abort_reason_message(reason: Int) -> Str {
  if reason == _STM_ABORT_NONE {
    return "stm: no abort";
  }
  if reason == _STM_ABORT_READ_CONFLICT {
    return "stm: read conflict";
  }
  if reason == _STM_ABORT_WRITE_CONFLICT {
    return "stm: write conflict";
  }
  if reason == _STM_ABORT_USER {
    return "stm: user abort";
  }
  return "stm: unknown abort reason";
}
