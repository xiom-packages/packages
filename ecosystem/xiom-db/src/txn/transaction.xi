module xiom.db.txn.transaction

// Transaction identity and lifecycle. A `Transaction` accumulates the logical
// operations it intends to perform and moves through a strict Active → Committed
// / Aborted state machine (see docs/transaction-model.md). This phase provides
// the state bookkeeping only; MVCC isolation and lock management arrive in
// Phase 3. `WALOp` is the coarse operation tag recorded per transaction.

pub enum WALOp {
  Insert,
  Update,
  Delete,
}

pub enum TxState {
  Active,
  Committed,
  Aborted,
}

pub type Transaction = {
  id: UInt64;
  state: TxState;
  operations: Vec[WALOp];
}

pub fn Transaction.new(id: UInt64) -> Transaction {
  return Transaction{ id: id, state: TxState.Active, operations: [] };
}

pub fn Transaction.commit() -> Transaction {
  return Transaction{ id: id, state: TxState.Committed, operations: operations };
}

pub fn Transaction.abort() -> Transaction {
  return Transaction{ id: id, state: TxState.Aborted, operations: operations };
}

pub fn Transaction.add_op(op: WALOp) -> Transaction {
  var new_ops = operations;
  new_ops.push(op);
  return Transaction{ id: id, state: state, operations: new_ops };
}

pub fn Transaction.is_active() -> Bool {
  return state == TxState.Active;
}
