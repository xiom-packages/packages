module xiom.core.storage.page

// A Page is the unit of buffered storage. In this in-memory phase `data` holds
// `size` zeroed slots; on disk it will map to a fixed-size block. `pin_count`
// tracks live borrows so a page is not evicted while in use, and `dirty` marks
// pages that must be written back before eviction.

pub type Page = {
  id: Int;
  data: Vec[Int];
  dirty: Bool;
  pin_count: Int;
}

pub fn page_new(id: Int, size: Int) -> Page {
  var data = Vec[Int].new();
  var i = 0;
  while i < size {
    data.push(0);
    i = i + 1;
  }
  return Page{ id: id, data: data, dirty: false, pin_count: 0 };
}

pub fn page_is_dirty(p: &Page) -> Bool {
  return p.dirty;
}

pub fn page_mark_dirty(p: &mut Page) {
  p.dirty = true;
}

pub fn page_pin(p: &mut Page) {
  p.pin_count = p.pin_count + 1;
}

pub fn page_unpin(p: &mut Page) {
  if p.pin_count > 0 {
    p.pin_count = p.pin_count - 1;
  }
}
