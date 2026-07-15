module xiom.core.storage.pager

use xiom.core.storage.page;

// The Pager owns the flat array of pages and hands out monotonically
// increasing page ids. This phase is fully in-memory; the disk-backed path
// (preallocation, fsync, torn-page recovery) arrives in Phase 2 behind FFI.

pub type Pager = {
  page_size: Int;
  page_count: Int;
  pages: Vec[Page];
}

pub fn pager_new(page_size: Int) -> Pager {
  var pages = Vec[Page].new();
  return Pager{ page_size: page_size, page_count: 0, pages: pages };
}

// Allocate and append a fresh zeroed page, returning its id.
pub fn pager_alloc_page(p: &mut Pager) -> Int {
  var id = p.page_count;
  var pg = page_new(id, p.page_size);
  p.pages.push(pg);
  p.page_count = p.page_count + 1;
  return id;
}

pub fn pager_read_page(p: &Pager, id: Int) -> Option[Page] {
  if id < 0 { return None; }
  if id >= p.pages.len() { return None; }
  var pg = p.pages[id];
  return Some(pg);
}

pub fn pager_page_count(p: &Pager) -> Int {
  return p.page_count;
}

pub fn pager_flush(p: &Pager) -> Bool {
  // TODO(Phase 2): disk flush needs FFI (fsync via core/ffi/os_file). An
  // in-memory pager has no durable backing store, so every page is already
  // "flushed"; return true so callers can treat the API uniformly.
  return true;
}
