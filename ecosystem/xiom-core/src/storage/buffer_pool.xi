module xiom.core.storage.buffer_pool

// In-memory frame cache with hit/miss accounting. `frames` holds resident
// pages; lookups are linear for now (a hash map index lands with the real
// storage layer). `capacity` bounds residency; the current eviction policy is
// a placeholder FIFO-over-slot-0 until the clock/LRU replacer is implemented.

pub type BufferPool = {
  frames: Vec[Page];
  capacity: Int;
  hits: Int;
  misses: Int;
}

pub fn buffer_pool_new(capacity: Int) -> BufferPool {
  var frames = Vec[Page].new();
  return BufferPool{ frames: frames, capacity: capacity, hits: 0, misses: 0 };
}

pub fn buffer_pool_get(bp: &mut BufferPool, page_id: Int) -> Option[Page] {
  var i = 0;
  while i < bp.frames.len() {
    if bp.frames[i].id == page_id {
      bp.hits = bp.hits + 1;
      var pg = bp.frames[i];
      return Some(pg);
    }
    i = i + 1;
  }
  bp.misses = bp.misses + 1;
  return None;
}

pub fn buffer_pool_put(bp: &mut BufferPool, page: Page) {
  var i = 0;
  while i < bp.frames.len() {
    if bp.frames[i].id == page.id {
      bp.frames[i] = page;
      return;
    }
    i = i + 1;
  }
  if bp.frames.len() < bp.capacity {
    bp.frames.push(page);
  } else {
    // TODO(Phase 1): replace naive slot-0 eviction with clock/LRU replacer.
    bp.frames[0] = page;
  }
}

// Hit ratio as an integer percentage in [0, 100].
pub fn buffer_pool_hit_ratio(bp: &BufferPool) -> Int {
  var total = bp.hits + bp.misses;
  if total == 0 { return 0; }
  return (bp.hits * 100) / total;
}
