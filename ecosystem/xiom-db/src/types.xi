module xiom.db.types

pub type PageId = UInt64;

pub type Key = Vec[UInt8];

pub type Page = {
  id: PageId;
  data: Vec[UInt8];
  checksum: UInt32;
  invariant: data.len() <= 4096;
} derive[Clone]

pub fn Page.new(id: PageId, data: Vec[UInt8], checksum: UInt32) -> Page
  requires: data.len() <= 4096
{
  return Page{ id: id, data: data, checksum: checksum };
}

pub type BTreeNode = {
  keys: Vec[Key];
  children: Vec[PageId];
  is_leaf: Bool;
  invariant: keys.is_sorted();
  invariant: keys.len() <= 256;
}

pub fn BTreeNode.new() -> BTreeNode {
  return BTreeNode{ keys: [], children: [], is_leaf: true };
}

pub fn BTreeNode.key_count() -> Int {
  return keys.len();
}

pub fn BTreeNode.is_full() -> Bool {
  return keys.len() == 256;
}

pub fn BTreeNode.child_count() -> Int {
  return children.len();
}

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
