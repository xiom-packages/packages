module xiom.durable.ids

// Strongly-typed identifiers. XIOM does not support bare type aliases over a
// primitive (`pub type PageId = Int` does not compile), so each identity is a
// single-field struct wrapper. This prevents accidental cross-use of plain
// integers (e.g. passing a PageId where an Lsn is expected) at compile time.

pub type PageId = { value: Int; } derive[Clone, Eq]
pub type Lsn = { value: Int; } derive[Clone, Eq]
pub type SegmentId = { value: Int; } derive[Clone, Eq]
pub type TxnId = { value: Int; } derive[Clone, Eq]
pub type CollectionId = { value: Int; } derive[Clone, Eq]
pub type VectorId = { value: Int; } derive[Clone, Eq]
pub type ShardId = { value: Int; } derive[Clone, Eq]

// --- PageId ---
pub fn page_id(v: Int) -> PageId {
  return PageId{ value: v };
}

pub fn page_id_value(id: &PageId) -> Int {
  return id.value;
}

pub fn page_id_eq(a: &PageId, b: &PageId) -> Bool {
  return a.value == b.value;
}

// --- Lsn (log sequence number) ---
pub fn lsn(v: Int) -> Lsn {
  return Lsn{ value: v };
}

pub fn lsn_value(id: &Lsn) -> Int {
  return id.value;
}

pub fn lsn_next(id: &Lsn) -> Lsn {
  return Lsn{ value: id.value + 1 };
}

pub fn lsn_lt(a: &Lsn, b: &Lsn) -> Bool {
  return a.value < b.value;
}

pub fn lsn_eq(a: &Lsn, b: &Lsn) -> Bool {
  return a.value == b.value;
}

pub fn lsn_zero() -> Lsn {
  return Lsn{ value: 0 };
}

// --- SegmentId ---
pub fn segment_id(v: Int) -> SegmentId {
  return SegmentId{ value: v };
}

pub fn segment_id_value(id: &SegmentId) -> Int {
  return id.value;
}

pub fn segment_id_eq(a: &SegmentId, b: &SegmentId) -> Bool {
  return a.value == b.value;
}

// --- TxnId ---
pub fn txn_id(v: Int) -> TxnId {
  return TxnId{ value: v };
}

pub fn txn_id_value(id: &TxnId) -> Int {
  return id.value;
}

pub fn txn_id_eq(a: &TxnId, b: &TxnId) -> Bool {
  return a.value == b.value;
}

pub fn txn_id_next(id: &TxnId) -> TxnId {
  return TxnId{ value: id.value + 1 };
}

// --- CollectionId ---
pub fn collection_id(v: Int) -> CollectionId {
  return CollectionId{ value: v };
}

pub fn collection_id_value(id: &CollectionId) -> Int {
  return id.value;
}

pub fn collection_id_eq(a: &CollectionId, b: &CollectionId) -> Bool {
  return a.value == b.value;
}

// --- VectorId ---
pub fn vector_id(v: Int) -> VectorId {
  return VectorId{ value: v };
}

pub fn vector_id_value(id: &VectorId) -> Int {
  return id.value;
}

pub fn vector_id_eq(a: &VectorId, b: &VectorId) -> Bool {
  return a.value == b.value;
}

// --- ShardId ---
pub fn shard_id(v: Int) -> ShardId {
  return ShardId{ value: v };
}

pub fn shard_id_value(id: &ShardId) -> Int {
  return id.value;
}

pub fn shard_id_eq(a: &ShardId, b: &ShardId) -> Bool {
  return a.value == b.value;
}
