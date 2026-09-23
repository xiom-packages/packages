module xiom.durable.txn.txn_manager

use xiom.durable.txn.txn_state;

// Coordinates the small set of write transactions in flight. Intentionally
// narrower than a relational transaction manager: it tracks identity, state,
// and the LSN a transaction started at, which is enough for WAL ordering and
// collection-level write consistency.

pub type Txn = {
  id: Int;
  state: TxnStateKind;
  start_lsn: Int;
}

pub type TxnManager = {
  active: Vec[Txn];
  next_id: Int;
}

pub fn txn_manager_new() -> TxnManager {
  var active = Vec[Txn].new();
  return TxnManager{ active: active, next_id: 1 };
}

// Begin a transaction in the Open state and return its id.
pub fn txn_begin(m: &mut TxnManager, start_lsn: Int) -> Int {
  var id = m.next_id;
  var t = Txn{ id: id, state: TxnStateKind.Open, start_lsn: start_lsn };
  m.active.push(t);
  m.next_id = m.next_id + 1;
  return id;
}

// Mark a transaction Committed. Returns false if the id is unknown.
pub fn txn_commit(m: &mut TxnManager, txn_id: Int) -> Bool {
  var i = 0;
  while i < m.active.len() {
    if m.active[i].id == txn_id {
      var t = m.active[i];
      m.active[i] = Txn{ id: t.id, state: TxnStateKind.Committed, start_lsn: t.start_lsn };
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Mark a transaction Aborted. Returns false if the id is unknown.
pub fn txn_abort(m: &mut TxnManager, txn_id: Int) -> Bool {
  var i = 0;
  while i < m.active.len() {
    if m.active[i].id == txn_id {
      var t = m.active[i];
      m.active[i] = Txn{ id: t.id, state: TxnStateKind.Aborted, start_lsn: t.start_lsn };
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn txn_active_count(m: &TxnManager) -> Int {
  return m.active.len();
}
