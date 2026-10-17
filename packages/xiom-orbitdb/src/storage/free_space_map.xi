// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.storage.free_space_map

// Free-space map: tracks per-page free capacity so tuple placement can pick a
// page without scanning the heap. v1 is an in-memory parallel array with
// BEST-FIT placement (tightest page that still fits, lowest PageId on ties)
// and hard invariants (0 <= free <= capacity, aligned arrays). The FSM
// tree/bitmap and persistence land with the pager (Phase 1); this module owns
// the semantics and is model-soaked in tests/probes/probe_fsm.xi.
//
// Maintenance contract:
//   fsm_register_page(fsm, capacity) -> PageId   (appends, full free)
//   fsm_record_used(fsm, page, used) -> Bool     (false = over-use/unknown)
//   fsm_record_free(fsm, page, freed) -> Bool    (clamps at capacity)
//   fsm_find_page(fsm, needed) -> Option[PageId] (best-fit)
//   fsm_validate(fsm) -> Bool                    (invariants hold)
// Pages are append-only ids; a free-list/cursor arrives with the pager.

pub type PageId = { value: Int; }

fn page_id(v: Int) -> PageId {
  return PageId{ value: v };
}

fn page_id_value(id: &PageId) -> Int {
  return id.value;
}

pub type FreeSpaceMap = {
  page_free: Vec[Int];
  page_capacity: Vec[Int];
}

pub fn free_space_map_new() -> FreeSpaceMap {
  var page_free = Vec[Int].new();
  var page_capacity = Vec[Int].new();
  return FreeSpaceMap{ page_free: page_free, page_capacity: page_capacity };
}

// Register a newly allocated page with its full capacity of free bytes.
pub fn fsm_register_page(fsm: &mut FreeSpaceMap, capacity: Int) -> PageId
  requires: capacity >= 0
{
  var id = fsm.page_free.len();
  fsm.page_free.push(capacity);
  fsm.page_capacity.push(capacity);
  return page_id(id);
}

// Record that `used` bytes were consumed on a page. Returns false for unknown
// pages, negative `used`, or over-use (free clamps to 0 -- the caller must
// treat false as a placement error, never as success).
pub fn fsm_record_used(fsm: &mut FreeSpaceMap, page: &PageId, used: Int) -> Bool {
  var idx = page_id_value(page);
  if idx < 0 { return false; }
  if idx >= fsm.page_free.len() { return false; }
  if used < 0 { return false; }
  if used > fsm.page_free[idx] {
    fsm.page_free[idx] = 0;
    return false;
  }
  fsm.page_free[idx] = fsm.page_free[idx] - used;
  return true;
}

// Release `freed` bytes back to a page (in-place delete/update path). Clamps
// at the page's capacity; false for unknown pages or negative `freed`.
pub fn fsm_record_free(fsm: &mut FreeSpaceMap, page: &PageId, freed: Int) -> Bool {
  var idx = page_id_value(page);
  if idx < 0 { return false; }
  if idx >= fsm.page_free.len() { return false; }
  if freed < 0 { return false; }
  var next = fsm.page_free[idx] + freed;
  if next > fsm.page_capacity[idx] { next = fsm.page_capacity[idx]; }
  fsm.page_free[idx] = next;
  return true;
}

pub fn fsm_free_bytes(fsm: &FreeSpaceMap, page: &PageId) -> Int {
  var idx = page_id_value(page);
  if idx < 0 { return -1; }
  if idx >= fsm.page_free.len() { return -1; }
  return fsm.page_free[idx];
}

pub fn fsm_capacity_of(fsm: &FreeSpaceMap, page: &PageId) -> Int {
  var idx = page_id_value(page);
  if idx < 0 { return -1; }
  if idx >= fsm.page_capacity.len() { return -1; }
  return fsm.page_capacity[idx];
}

// Best-fit placement: the page with the SMALLEST free byte count that still
// satisfies `needed` (lowest PageId wins ties). Deterministic; O(n) on the
// array until the FSM tree/bitmap replaces it.
pub fn fsm_find_page(fsm: &FreeSpaceMap, needed: Int) -> Option[PageId]
  requires: needed >= 0
{
  var best = -1;
  var best_free = 0;
  var i = 0;
  while i < fsm.page_free.len() {
    if fsm.page_free[i] >= needed {
      if best < 0 || fsm.page_free[i] < best_free {
        best = i;
        best_free = fsm.page_free[i];
      }
    }
    i = i + 1;
  }
  if best < 0 { return None; }
  return Some(page_id(best));
}

pub fn fsm_page_count(fsm: &FreeSpaceMap) -> Int {
  return fsm.page_free.len();
}

pub fn fsm_total_free(fsm: &FreeSpaceMap) -> Int {
  var sum = 0;
  var i = 0;
  while i < fsm.page_free.len() {
    sum = sum + fsm.page_free[i];
    i = i + 1;
  }
  return sum;
}

// Invariant checker: arrays aligned and 0 <= free <= capacity on every page.
pub fn fsm_validate(fsm: &FreeSpaceMap) -> Bool {
  if fsm.page_free.len() != fsm.page_capacity.len() { return false; }
  var i = 0;
  while i < fsm.page_free.len() {
    if fsm.page_free[i] < 0 { return false; }
    if fsm.page_free[i] > fsm.page_capacity[i] { return false; }
    i = i + 1;
  }
  return true;
}
