module xiom.core.txn.txn_state

// The transaction lifecycle state machine. Legal transitions:
//   Open      -> Prepared | Committed | Aborted
//   Prepared  -> Committed | Aborted
//   Recovered -> Committed | Aborted   (resolved during crash recovery)
//   Committed -> (terminal)
//   Aborted   -> (terminal)

pub enum TxnStateKind {
  Open,
  Prepared,
  Committed,
  Aborted,
  Recovered,
}

// A transaction may commit only from Open or Prepared.
pub fn txn_state_can_commit(s: &TxnStateKind) -> Bool {
  match s {
    Open => true,
    Prepared => true,
    Committed => false,
    Aborted => false,
    Recovered => false,
  }
}

// Committed and Aborted are terminal -- no further transitions are allowed.
pub fn txn_state_is_terminal(s: &TxnStateKind) -> Bool {
  match s {
    Open => false,
    Prepared => false,
    Committed => true,
    Aborted => true,
    Recovered => false,
  }
}
