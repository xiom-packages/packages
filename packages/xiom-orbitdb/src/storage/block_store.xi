// XIOM ORBITDB -- byte-page block store v2 (M1.2 S2).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// File layout (blocks of 4096 bytes; see docs/BYTE-PAGE-FORMAT-V2.md):
//   block 0        header slot A
//   block 1        header slot B
//   block 2..N     page blocks (append order)
//
// Commit protocol: page appends are invisible until a header commit lands in
// the inactive slot with the highest generation so far; readers resolve each
// page as the newest generation <= the active header generation, latest
// occurrence per page_id wins. A torn write to the inactive slot leaves the
// previous active slot valid; the FIRST commit mirrors the header into both
// slots so a single torn slot still has a fallback.
//
// The page directory is rebuilt at open by scanning every valid page block
// (free blocks are skipped without CRC validation); an IO error anywhere
// leaves the store empty rather than half-built. All file IO goes through
// the byte-IO shim (O(file) fallbacks until the stdlib rows land).
//
// In-process semantics: pages put by THIS handle are visible to its own
// reads immediately (own-writes-visible, like a WAL handle); a reopened
// store only shows what the committed header covers.

module xiom.db.storage.block_store

use xiom.io;
use xiom.db.storage.block;
use xiom.db.storage.byte_io;

pub type BlockStore = {
  path: Str;
  ids: Vec[Int];
  blocks: Vec[Int];
  gens: Vec[Int];
  header: BlockHeader;
  active_slot: Int;
  committed: Bool;
  block_count: Int;
}

pub fn block_store_empty() -> BlockStore {
  return BlockStore{
    path: "",
    ids: Vec[Int].new(),
    blocks: Vec[Int].new(),
    gens: Vec[Int].new(),
    header: empty_header(),
    active_slot: 0,
    committed: false,
    block_count: 0,
  };
}

fn empty_header() -> BlockHeader {
  return BlockHeader{
    root: 0,
    order: 0,
    node_count: 0,
    checkpoint_lsn: 0,
    committed_generation: 0,
    block_count: 0,
    next_page_id: 0,
  };
}

fn header_copy(h: &BlockHeader) -> BlockHeader {
  return BlockHeader{
    root: h.root,
    order: h.order,
    node_count: h.node_count,
    checkpoint_lsn: h.checkpoint_lsn,
    committed_generation: h.committed_generation,
    block_count: h.block_count,
    next_page_id: h.next_page_id,
  };
}

fn find_id(bs: &BlockStore, page_id: Int) -> Int {
  var i = 0;
  while i < bs.ids.len() {
    if bs.ids[i] == page_id { return i; }
    i = i + 1;
  }
  return -1;
}

fn dir_set(bs: &mut BlockStore, page_id: Int, block_index: Int, gen: Int) {
  let idx = find_id(bs, page_id);
  if idx < 0 {
    bs.ids.push(page_id);
    bs.blocks.push(block_index);
    bs.gens.push(gen);
    return;
  }
  if gen >= bs.gens[idx] {
    bs.blocks[idx] = block_index;
    bs.gens[idx] = gen;
  }
}

// Rebuild the committed view from disk. Missing/short file -> empty store.
// One reused page buffer for block_store_put (m375 write-path fallback:
// no Vec[Int] page + bytes_to_u8 per dirty page). Single-threaded writer.
var g_block_buf: Vec[UInt8] = Vec[UInt8].new();

pub fn block_store_open(path: Str) -> BlockStore {
  var bs = BlockStore{
    path: path,
    ids: Vec[Int].new(),
    blocks: Vec[Int].new(),
    gens: Vec[Int].new(),
    header: empty_header(),
    active_slot: 0,
    committed: false,
    block_count: 0,
  };
  let size = byteio_file_size(path);
  if size <= 0 { return bs; }
  let total = size / block_size();
  bs.block_count = total;
  // One page buffer for the whole scan (m375 fallback: no per-block Vec).
  var rbuf = Vec[UInt8].new();

  // Header slots: pick the highest valid generation; a corrupt slot is
  // simply not a candidate (the other one wins).
  var gen_a = -1;
  var gen_b = -1;
  var h_a = empty_header();
  var h_b = empty_header();
  if total >= 1 {
    if byteio_read_at_into(path, 0, &mut rbuf, block_size()) {
      match block_decode_header_bytes(&rbuf) {
        Some(h) => { h_a = h; gen_a = h.committed_generation; }
        None => {}
      }
    }
  }
  if total >= 2 {
    if byteio_read_at_into(path, block_size(), &mut rbuf, block_size()) {
      match block_decode_header_bytes(&rbuf) {
        Some(h) => { h_b = h; gen_b = h.committed_generation; }
        None => {}
      }
    }
  }
  if gen_a < 0 && gen_b < 0 { return bs; }
  if gen_b > gen_a {
    bs.header = h_b;
    bs.active_slot = 1;
  } else {
    bs.header = h_a;
    bs.active_slot = 0;
  }
  bs.committed = true;

  // Page blocks (2..total): free and malformed blocks are skipped; pages
  // above the committed generation stay invisible.
  var i: Int = 2;
  while i < total {
    if byteio_read_at_into(path, i * block_size(), &mut rbuf, block_size()) {
      if !block_kind_is_free_bytes(&rbuf) {
        match block_decode_page_meta_bytes(&rbuf) {
          Some(meta) => {
            if meta.0 <= bs.header.committed_generation {
              dir_set(&mut bs, meta.1, i, meta.0);
            }
          }
          None => {}
        }
      }
    }
    i = i + 1;
  }
  return bs;
}

// Append one page version; returns its block index or -1. The first page
// always lands after the two header slots (blocks 0/1 stay reserved even on
// a fresh store).
pub fn block_store_put(bs: &mut BlockStore, generation: Int, page_id: Int, payload: &Vec[Int]) -> Int {
  if !block_encode_page_into(&mut g_block_buf, generation, page_id, payload) { return -1; }
  if bs.block_count < 2 { bs.block_count = 2; }
  let index = bs.block_count;
  if !byteio_write_at_bytes(bs.path, index * block_size(), &g_block_buf) { return -1; }
  dir_set(bs, page_id, index, generation);
  bs.block_count = bs.block_count + 1;
  return index;
}

// Commit a header. Rejects a non-increasing generation. The first commit
// mirrors both slots; later commits alternate so a torn inactive slot can
// never destroy the active one.
pub fn block_store_commit(bs: &mut BlockStore, h: &BlockHeader) -> Bool {
  if bs.committed && h.committed_generation <= bs.header.committed_generation {
    return false;
  }
  let bytes = block_encode_header(h);
  if bytes.len() != block_size() { return false; }
  if !bs.committed {
    if !byteio_write_at(bs.path, 0, &bytes) { return false; }
    if !byteio_write_at(bs.path, block_size(), &bytes) { return false; }
    bs.active_slot = 0;
    bs.committed = true;
    bs.header = header_copy(h);
    return true;
  }
  let slot = 1 - bs.active_slot;
  if !byteio_write_at(bs.path, slot * block_size(), &bytes) { return false; }
  bs.active_slot = slot;
  bs.header = header_copy(h);
  return true;
}

pub fn block_store_read(bs: &BlockStore, page_id: Int) -> Option[BlockPage] {
  let idx = find_id(bs, page_id);
  if idx < 0 { return None; }
  match byteio_read_at(bs.path, bs.blocks[idx] * block_size(), block_size()) {
    Some(bytes) => {
      match block_decode_page(&bytes) {
        Some(p) => {
          if p.page_id != page_id || p.generation != bs.gens[idx] { return None; }
          return Some(p);
        }
        None => { return None; }
      }
    }
    None => { return None; }
  }
}

pub fn block_store_has(bs: &BlockStore, page_id: Int) -> Bool {
  return find_id(bs, page_id) >= 0;
}

pub fn block_store_count(bs: &BlockStore) -> Int {
  return bs.ids.len();
}

// Page ids in directory (insertion) order; a stable copy.
pub fn block_store_pages(bs: &BlockStore) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < bs.ids.len() {
    out.push(bs.ids[i]);
    i = i + 1;
  }
  return out;
}

pub fn block_store_blocks(bs: &BlockStore) -> Int {
  return bs.block_count;
}

// Full compaction: one block per live page at a NEW generation, both header
// slots written in the temp file, then one atomic rename. Crash-safe by
// construction (the old file is untouched until the rename).
pub fn block_store_compact(bs: &mut BlockStore, generation: Int) -> Bool {
  if bs.committed && generation <= bs.header.committed_generation { return false; }
  let tmp = bs.path + ".tmp";
  match io.remove_file(tmp) { Ok(_) => {} Err(_) => {} }

  var h = header_copy(&bs.header);
  h.committed_generation = generation;
  h.block_count = 2 + bs.ids.len();
  let hb = block_encode_header(&h);
  if hb.len() != block_size() { return false; }
  if !byteio_write_at(tmp, 0, &hb) { return false; }
  if !byteio_write_at(tmp, block_size(), &hb) { return false; }

  var at: Int = 2 * block_size();
  var i: Int = 0;
  while i < bs.ids.len() {
    match block_store_read(bs, bs.ids[i]) {
      Some(p) => {
        let bytes = block_encode_page(generation, p.page_id, &p.payload);
        if bytes.len() != block_size() { return false; }
        if !byteio_write_at(tmp, at, &bytes) { return false; }
      }
      None => { return false; }
    }
    at = at + block_size();
    i = i + 1;
  }

  // Rename durability (P3, M1.2 S4): the fully-written temp must be synced
  // before publishing the new name, and the directory that received the
  // rename after.
  let _ = byteio_sync(tmp);
  match io.rename(tmp, bs.path) {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  let _ = byteio_sync_dir(bs.path);

  bs.header = h;
  bs.active_slot = 0;
  bs.committed = true;
  bs.block_count = 2 + bs.ids.len();
  var j = 0;
  while j < bs.blocks.len() {
    bs.blocks[j] = 2 + j;
    bs.gens[j] = generation;
    j = j + 1;
  }
  return true;
}

// Durability seam (no-op until the stdlib fsync row lands).
pub fn block_store_sync(bs: &BlockStore) -> Bool {
  return byteio_sync(bs.path);
}
