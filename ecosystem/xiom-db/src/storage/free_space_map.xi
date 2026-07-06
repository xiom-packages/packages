module xiom.db.storage.free_space_map
use xiom.core.ids;

// SCAFFOLD (Phase 1). The free-space map tracks how many free bytes remain on
// each heap page so the tuple inserter can place a new row without a full scan.
// This is a placeholder: the real implementation will be a compact, on-disk
// bitmap / FSM tree keyed by PageId. For now it is an in-memory parallel array.

pub type FreeSpaceMap = {
  page_free: Vec[Int];
}

pub fn free_space_map_new() -> FreeSpaceMap {
  var page_free = Vec[Int].new();
  return FreeSpaceMap{ page_free: page_free };
}

// Register a newly allocated page with its full capacity of free bytes.
// TODO(Phase 1): allocate the slot at the page's real PageId rather than
// appending, and persist alongside the pager's page table.
pub fn fsm_register_page(fsm: &mut FreeSpaceMap, free_bytes: Int) -> PageId {
  var id = fsm.page_free.len();
  fsm.page_free.push(free_bytes);
  return page_id(id);
}

// Record that `used` bytes were consumed on a page.
// TODO(Phase 1): clamp, validate the page exists, and mark the page dirty.
pub fn fsm_record_used(fsm: &mut FreeSpaceMap, page: &PageId, used: Int) {
  var idx = page_id_value(page);
  if idx < 0 { return; }
  if idx >= fsm.page_free.len() { return; }
  fsm.page_free[idx] = fsm.page_free[idx] - used;
}

// Find the first page with at least `needed` free bytes.
// TODO(Phase 1): use an FSM tree for O(log n) best-fit placement instead of a
// linear scan, and return a real allocation cursor.
pub fn fsm_find_page(fsm: &FreeSpaceMap, needed: Int) -> Option[PageId] {
  var i = 0;
  while i < fsm.page_free.len() {
    if fsm.page_free[i] >= needed {
      return Some(page_id(i));
    }
    i = i + 1;
  }
  return None;
}

pub fn fsm_page_count(fsm: &FreeSpaceMap) -> Int {
  return fsm.page_free.len();
}
