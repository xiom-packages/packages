// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.storage.page
use xiom.db.config;

// Low-level buffered-storage primitives. A `Page` is a fixed-capacity byte
// block guarded by a CRC32C checksum; the `BufferPool` is a frame-table page
// cache with a clock (second-chance) replacement policy and pin counts; the
// `StorageEngine` binds a configuration to a pool. This layer is currently
// in-memory: pages live in the pool's frames, not on disk. Phase 1 swaps this
// checksum for xiom.hash.crc once byte packs land and routes the frames
// through xiom.core.storage.pager (the policy lives here already).

pub type Page = {
  id: Int;
  data: Vec[Int];
  checksum: Int;
} derive[Clone]

pub fn Page.new(id: Int, data: Vec[Int], checksum: Int) -> Page
  requires: data.len() <= 4096
{
  return Page{ id: id, data: data, checksum: checksum };
}

// A page is valid iff its stored checksum matches a fresh checksum of its data.
// This is the on-read integrity gate that surfaces torn or corrupted pages.
pub fn Page.is_valid() -> Bool {
  return checksum == page_checksum(data);
}

// CRC32C (Castagnoli, reflected poly 0x82F63B78) over the page's byte view:
// each element contributes its low byte. Bitwise (no table, no module state);
// canonical check value: CRC32C("123456789") == 0xE3069283. The stdlib
// equivalent is xiom.hash.crc.crc32c(&Vec[UInt8]) -- adopted here once the
// byte-packed codec lands (stdlib byte-IO row); this keeps the integrity gate
// byte-true today without the Vec[UInt8] conversion gap.
fn page_checksum(data: &Vec[Int]) -> Int {
  var crc = 0xFFFFFFFF;
  var i = 0;
  while i < data.len() {
    let byte = data[i] & 0xFF;
    crc = crc ^ byte;
    var b = 0;
    while b < 8 {
      if (crc & 1) == 1 {
        crc = (crc >> 1) ^ 0x82F63B78;
      } else {
        crc = crc >> 1;
      }
      b = b + 1;
    }
    i = i + 1;
  }
  return crc ^ 0xFFFFFFFF;
}

// Compute the canonical CRC32C for a byte-valued buffer (empty -> 0). Exposed
// so writers can seal a page before caching it.
pub fn page_compute_checksum(data: &Vec[Int]) -> Int {
  return page_checksum(data);
}

// CRC32C over a slice of a raw byte buffer (same polynomial as page_checksum).
// Lets the block codec validate a page without converting bytes to Vec[Int].
pub fn page_checksum_bytes(data: &Vec[UInt8], start: Int, len: Int) -> Int {
  var crc = 0xFFFFFFFF;
  var i = 0;
  while i < len {
    let byte = data[start + i] as Int;
    crc = crc ^ byte;
    var b = 0;
    while b < 8 {
      if (crc & 1) == 1 {
        crc = (crc >> 1) ^ 0x82F63B78;
      } else {
        crc = crc >> 1;
      }
      b = b + 1;
    }
    i = i + 1;
  }
  return crc ^ 0xFFFFFFFF;
}

// Frame-table cache with a clock (second-chance) replacer. Frames are
// parallel vectors (Page / id / present / reference bit / pin count) so that
// no Option is ever element-assigned into a Vec (C-ORBIT-02); pages are
// addressed associatively by id, not by id % capacity.
//
// Statistics: `hits`/`misses` are get()-side; `evictions` counts clock
// victims; `rejects` counts put() calls that found no victim because every
// frame was pinned (the page is then NOT cached -- get() returns None).
pub type BufferPool = {
  frames: Vec[Page];
  frame_ids: Vec[Int];
  present: Vec[Bool];
  ref_bits: Vec[Bool];
  pins: Vec[Int];
  capacity: Int;
  hand: Int;
  hits: Int;
  misses: Int;
  evictions: Int;
  rejects: Int;
}

pub fn BufferPool.new(capacity: Int) -> BufferPool
  requires: capacity >= 1
{
  var frames = Vec[Page].new();
  var ids = Vec[Int].new();
  var present = Vec[Bool].new();
  var refs = Vec[Bool].new();
  var pins = Vec[Int].new();
  var i = 0;
  while i < capacity {
    var empty = Vec[Int].new();
    frames.push(Page.new(0, empty, 0));
    ids.push(-1);
    present.push(false);
    refs.push(false);
    pins.push(0);
    i = i + 1;
  }
  return BufferPool{ frames: frames, frame_ids: ids, present: present,
                     ref_bits: refs, pins: pins, capacity: capacity, hand: 0,
                     hits: 0, misses: 0, evictions: 0, rejects: 0 };
}

// Frame index holding `page_id`, or -1.
fn bp_find_frame(pool: &BufferPool, page_id: Int) -> Int {
  var i = 0;
  while i < pool.capacity {
    if pool.present[i] {
      if pool.frame_ids[i] == page_id { return i; }
    }
    i = i + 1;
  }
  return -1;
}

// Insert or update a page. When the pool is full a frame is chosen by clock:
// pinned frames are never evicted, a referenced frame gets its reference bit
// cleared and is revisited on the next sweep. Returns false only when every
// frame is pinned (nothing cached; `rejects` incremented).
pub fn BufferPool.put(pool: &mut BufferPool, page: Page) -> Bool {
  let existing = bp_find_frame(pool, page.id);
  if existing >= 0 {
    pool.frames[existing] = page;
    pool.ref_bits[existing] = true;
    return true;
  }
  var f = 0;
  while f < pool.capacity {
    if !pool.present[f] {
      pool.frames[f] = page;
      pool.frame_ids[f] = page.id;
      pool.present[f] = true;
      pool.ref_bits[f] = true;
      return true;
    }
    f = f + 1;
  }
  // Clock sweep: at most two full turns (first clears reference bits, second
  // picks the first unpinned, unreferenced frame).
  var steps = 0;
  while steps < 2 * pool.capacity {
    let c = pool.hand;
    if pool.pins[c] == 0 {
      if !pool.ref_bits[c] {
        pool.frames[c] = page;
        pool.frame_ids[c] = page.id;
        pool.present[c] = true;
        pool.ref_bits[c] = true;
        pool.evictions = pool.evictions + 1;
        pool.hand = (c + 1) % pool.capacity;
        return true;
      }
      pool.ref_bits[c] = false;
    }
    pool.hand = (c + 1) % pool.capacity;
    steps = steps + 1;
  }
  // Every frame is pinned: do not evict anything.
  pool.rejects = pool.rejects + 1;
  return false;
}

// Lookup: a hit counts `hits` and grants a second chance (reference bit set);
// a miss counts `misses`.
pub fn BufferPool.get(pool: &mut BufferPool, page_id: Int) -> Option[Page] {
  let f = bp_find_frame(pool, page_id);
  if f < 0 {
    pool.misses = pool.misses + 1;
    return None;
  }
  pool.hits = pool.hits + 1;
  pool.ref_bits[f] = true;
  return Some(pool.frames[f]);
}

// Pinning: a pinned frame is never chosen by the clock replacer. Pin the same
// page twice and it needs two unpins before it becomes evictable again.
pub fn BufferPool.pin_page(pool: &mut BufferPool, page_id: Int) -> Bool {
  let f = bp_find_frame(pool, page_id);
  if f < 0 { return false; }
  pool.pins[f] = pool.pins[f] + 1;
  pool.ref_bits[f] = true;
  return true;
}

pub fn BufferPool.unpin_page(pool: &mut BufferPool, page_id: Int) -> Bool {
  let f = bp_find_frame(pool, page_id);
  if f < 0 { return false; }
  if pool.pins[f] == 0 { return false; }
  pool.pins[f] = pool.pins[f] - 1;
  return true;
}

pub fn BufferPool.pin_count(pool: &BufferPool, page_id: Int) -> Int {
  let f = bp_find_frame(pool, page_id);
  if f < 0 { return 0; }
  return pool.pins[f];
}

pub fn BufferPool.hit_ratio(pool: &BufferPool) -> Float64 {
  var total = pool.hits + pool.misses;
  if total == 0 { return 0.0; }
  return (pool.hits as Float64) / (total as Float64);
}

pub type StorageEngine = {
  config: DatabaseConfig;
  buffer_pool: BufferPool;
}

pub fn StorageEngine.new(config: DatabaseConfig) -> StorageEngine {
  var bp = BufferPool.new(config.buffer_pool_capacity);
  return StorageEngine{ config: config, buffer_pool: bp };
}

// Returns what put() returned: false when every frame is pinned and the page
// could not be cached. The nested receiver writes through (C-ORBIT-03/m224
// fixed in v0.64.2); repro docs/repro/nested-field-mut/probe.xi.
pub fn StorageEngine.cache_page(eng: &mut StorageEngine, page: Page) -> Bool {
  return eng.buffer_pool.put(page);
}

// &mut because a lookup updates the reference bit and hit/miss statistics;
// the nested receiver writes through (C-ORBIT-03/m224 fixed in v0.64.2).
pub fn StorageEngine.lookup_page(eng: &mut StorageEngine, page_id: Int) -> Option[Page] {
  return eng.buffer_pool.get(page_id);
}
