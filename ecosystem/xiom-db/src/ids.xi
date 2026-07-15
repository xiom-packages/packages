module xiom.db.ids

// Database-level strongly-typed identifiers. XIOM does not permit bare type
// aliases over a primitive, so each identity is a single-field struct wrapper.
// This blocks accidental cross-use of raw integers (e.g. passing a RowId where
// a TableId is expected) at compile time. Lower-level identities (PageId, Lsn,
// SegmentId, TxnId) live in `xiom.core.ids` and are re-used, not redefined.

pub type RowId = { value: Int; } derive[Clone, Eq]
pub type TableId = { value: Int; } derive[Clone, Eq]

// Local PageId wrapper for db-layer use, mirrors xiom.core.ids.PageId.
pub type PageId = { value: Int; } derive[Clone, Eq]

fn page_id(v: Int) -> PageId {
  return PageId{ value: v };
}

// --- RowId ---
pub fn row_id(v: Int) -> RowId {
  return RowId{ value: v };
}

pub fn row_id_value(id: &RowId) -> Int {
  return id.value;
}

pub fn row_id_eq(a: &RowId, b: &RowId) -> Bool {
  return a.value == b.value;
}

pub fn row_id_next(id: &RowId) -> RowId {
  return RowId{ value: id.value + 1 };
}

// --- TableId ---
pub fn table_id(v: Int) -> TableId {
  return TableId{ value: v };
}

pub fn table_id_value(id: &TableId) -> Int {
  return id.value;
}

pub fn table_id_eq(a: &TableId, b: &TableId) -> Bool {
  return a.value == b.value;
}

// Bridge helper: a RowId maps onto a core PageId when a row is materialised as
// the primary key of a heap page. Kept here so the storage layer never invents
// its own conversion.
pub fn row_id_to_page_id(id: &RowId) -> PageId {
  return page_id(id.value);
}
