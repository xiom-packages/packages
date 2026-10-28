// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.db.engine.snapshot

// Checkpoint/snapshot machinery (v1 page log + v2 block store) and the M3
// snapshot-pin read views, extracted move-only from engine.xi (R1 split).
// The DBFile type + public API stay in xiom.db.engine and are re-exported.

use xiom.io;
use xiom.env;
use xiom.db.wal_file;
use xiom.db.index.node_page;
use xiom.db.index.btree;
use xiom.db.storage.page;
use xiom.db.storage.page_file;
use xiom.db.storage.block;
use xiom.db.storage.block_store;
use xiom.db.storage.byte_io;
use xiom.db.storage.tuple;
use xiom.db.engine.core;
use xiom.db.engine.txn;
use xiom.db.engine;

// ===========================================================================
// CHECKPOINT / SNAPSHOT (Phase 1/C): persist the B-tree node set into the
// durable page file; recovery loads the snapshot and replays only the tail.
// ===========================================================================
// Snapshot layout (append-only page log, storage/page_file.xi):
//   page 0                  header: root, order, node_count, lsn, generation
//   page g*STRIDE + i + 1   B-tree node i as of generation g
// A checkpoint appends new versions of ONLY the nodes that changed since the
// last committed generation, then appends the header page LAST: its generation
// commits the snapshot (every page of that generation is already in the log).
// Readers resolve, per node, the newest generation <= the committed header
// generation -- pages from an uncommitted later generation are ignored, so a
// crash mid-checkpoint leaves the previous snapshot fully valid. When the log
// grows past node_count + 64 entries, compaction rewrites one version of every
// page through page_file_write_batch (single atomic rename).
//
// Crash ordering (each step leaves a recoverable state):
//   1. node appends (generation g)       -> crash: g uncommitted, old header
//   2. header append (generation g)      -> snapshot committed at g
//   3. WAL anchor append + truncate      -> anchor kept, next_lsn resumes
//
// Durability honesty (M2.1 second half, M1.2 S4): the snapshot rides on
// byteio_sync/byteio_sync_dir (REAL fsync since stdlib waves 115/118): a
// checkpoint syncs the WAL (two_phase pre-sync), writes the generation,
// publishes the anchor, and syncs the file + directory -- power-loss honest
// up to those seams.

const SNAP_MAGIC: Int = 0x4F;       // 'O' -- snapshot page codec
const SNAP_VERSION: Int = 1;        // header page version (unchanged)
const SNAP_KIND_HEADER: Int = 0x48; // 'H'
const SNAP_HEADER_BYTES: Int = 44;
const SNAP_PAGE_MAX_BYTES: Int = 4096;
// 2^32: page id = generation*STRIDE + node_idx + 1. The stride bounds a
// generation's node ids; ids never collide across generations, so older
// generations stay valid until a compaction rewrites the file atomically.
pub const SNAP_PAGE_STRIDE: Int = 4294967296;
// Compact once the raw log grows past node_count + this slack.
const SNAP_COMPACT_SLACK: Int = 64;
// M1.1b pager: node cache frames kept decoded per handle (4096-B pages).
const SNAP_PAGER_CAPACITY: Int = 256;

// Pager cache frames. The default is deliberately small; production/soak
// runs can raise it (ORBITDB_PAGER_CAPACITY) to trade memory for cold-read
// syscalls. Every frame is one decoded node.
fn pager_capacity() -> Int {
  let raw = env.var_or("ORBITDB_PAGER_CAPACITY", "");
  if raw.len() == 0 { return SNAP_PAGER_CAPACITY; }
  match io.parse_int(raw) {
    Ok(v) => {
      if v >= 1 && v <= 262144 { return v; }
      return SNAP_PAGER_CAPACITY;
    }
    Err(_) => { return SNAP_PAGER_CAPACITY; }
  }
}

fn snap_page_id_for(gen: Int, node_idx: Int) -> Int {
  return gen * SNAP_PAGE_STRIDE + node_idx + 1;
}

type SnapshotMeta = {
  root: Int;
  order: Int;
  node_count: Int;
  checkpoint_lsn: Int;
  generation: Int;
}

pub type Snapshot = {
  tree: BTree;
  checkpoint_lsn: Int;
  generation: Int;
}

fn snap_header_page_bytes(root: Int, order: Int, node_count: Int,
                          checkpoint_lsn: Int, generation: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  out.push(SNAP_MAGIC);
  out.push(SNAP_VERSION);
  out.push(SNAP_KIND_HEADER);
  out.push(0);
  tuple_push_int_le(&mut out, root);
  tuple_push_int_le(&mut out, order);
  tuple_push_int_le(&mut out, node_count);
  tuple_push_int_le(&mut out, checkpoint_lsn);
  tuple_push_int_le(&mut out, generation);
  return out;
}


fn snap_decode_header(data: &Vec[Int]) -> Option[SnapshotMeta] {
  if data.len() < SNAP_HEADER_BYTES { return None; }
  if data[0] != SNAP_MAGIC { return None; }
  if data[1] != SNAP_VERSION { return None; }
  if data[2] != SNAP_KIND_HEADER { return None; }
  return Some(SnapshotMeta{
    root: tuple_read_int_le(data, 4),
    order: tuple_read_int_le(data, 12),
    node_count: tuple_read_int_le(data, 20),
    checkpoint_lsn: tuple_read_int_le(data, 28),
    generation: tuple_read_int_le(data, 36),
  });
}

// Header selection: a committed checkpoint appends its header page LAST, so
// among valid header pages (id 0) the highest generation is the active one.
fn snap_read_meta(pages: &Vec[Page]) -> Option[SnapshotMeta] {
  var best = SnapshotMeta{ root: 0, order: 3, node_count: 0, checkpoint_lsn: 0, generation: -1 };
  var found = false;
  var i = 0;
  while i < pages.len() {
    let pg = pages[i];
    if pg.id == 0 {
      let dec = snap_decode_header(&pg.data);
      match dec {
        None => {}
        Some(m) => {
          let mm: SnapshotMeta = m;
          if mm.generation > best.generation {
            best = mm;
            found = true;
          }
        }
      }
    }
    i = i + 1;
  }
  if !found { return None; }
  return Some(best);
}

// One committed page per node: the newest generation <= active_gen. Returns
// None when any node has no committed page (the snapshot is then unusable).
fn snap_resolve_pages(pages: &Vec[Page], node_count: Int,
                       active_gen: Int) -> Option[Vec[Page]] {
  var best_gen = Vec[Int].new();
  var best = Vec[Page].new();
  var i = 0;
  while i < node_count {
    var empty = Vec[Int].new();
    best_gen.push(-1);
    best.push(Page.new(0, empty, 0));
    i = i + 1;
  }

  var p = 0;
  while p < pages.len() {
    let pg = pages[p];
    if pg.id > 0 {
      let zero = pg.id - 1;
      let idx = zero % SNAP_PAGE_STRIDE;
      let gen = zero / SNAP_PAGE_STRIDE;
      if idx < node_count && gen <= active_gen {
        if gen > best_gen[idx] {
          best_gen[idx] = gen;
          best[idx] = pg;
        }
      }
    }
    p = p + 1;
  }

  i = 0;
  while i < node_count {
    if best_gen[i] < 0 { return None; }
    i = i + 1;
  }
  return Some(best);
}

// Atomic compaction: one page per node + the header at generation `gen`,
// installed through page_file_write_batch (single rename). Used when the log
// has grown past node_count + slack.
fn snap_compact(path: Str, tree: &mut BTree, checkpoint_lsn: Int, gen: Int) -> Bool {
  var pages = Vec[Page].new();
  var i = 0;
  while i < ns_len(&tree.store) {
    let node = ns_get(&tree.store, i);
    let data = node_page_bytes(&node);
    if data.len() > SNAP_PAGE_MAX_BYTES { return false; }
    pages.push(Page.new(snap_page_id_for(gen, i), data, page_compute_checksum(&data)));
    i = i + 1;
  }
  let hdr = snap_header_page_bytes(tree.root, tree.order, ns_len(&tree.store),
                                   checkpoint_lsn, gen);
  if hdr.len() > SNAP_PAGE_MAX_BYTES { return false; }
  pages.push(Page.new(0, hdr, page_compute_checksum(&hdr)));
  let pf = page_file_open(path);
  let wrote = page_file_write_batch(&pf, pages);
  if wrote { ns_mark_clean(&mut tree.store); }
  return wrote;
}

// Commit a checkpoint incrementally: append new versions of only the DIRTY
// nodes (tracked by the NodeStore), then append the header page (id 0,
// generation = prior + 1) LAST as the commit point. Forces a full write when
// there is no valid prior snapshot or when pages of an uncommitted crashed
// generation linger (they must never become the only version of a node).
// Returns the committed generation, or -1 when nothing was committed; the
// previous snapshot stays valid in every failure mode. `allow_compact` is
// false while a snapshot pin is live (M3): the compaction branch is deferred
// (counted) and the incremental append continues.
fn snap_flush(path: Str, tree: &mut BTree, checkpoint_lsn: Int, allow_compact: Bool) -> Int {
  let pf = page_file_open(path);
  let pages = page_log_read_all(&pf);
  let meta_found = snap_read_meta(&pages);
  var prior_gen = 0;
  var have_prior = false;
  match meta_found {
    None => {}
    Some(m) => {
      let mm: SnapshotMeta = m;
      prior_gen = mm.generation;
      have_prior = true;
    }
  }

  var has_uncommitted = false;
  var q = 0;
  while q < pages.len() {
    let pg2 = pages[q];
    if pg2.id > 0 {
      let z = pg2.id - 1;
      let g2 = z / SNAP_PAGE_STRIDE;
      if g2 == prior_gen + 1 { has_uncommitted = true; }
    }
    q = q + 1;
  }
  let write_all = !have_prior || has_uncommitted;

  let gen = prior_gen + 1;
  let entries = page_log_len(&pf);
  if entries > ns_len(&tree.store) + SNAP_COMPACT_SLACK {
    if !allow_compact {
      // M3: compaction would rewrite one version per node, dropping the older
      // generations a live pin may still need. Defer; the next checkpoint
      // after the pin is released compacts.
      tree.store.compaction_deferred = tree.store.compaction_deferred + 1;
    } else {
      if snap_compact(path, tree, checkpoint_lsn, gen) { return gen; }
      return -1;
    }
  }

  var i = 0;
  while i < ns_len(&tree.store) {
    var should_write = write_all;
    if !should_write { should_write = tree.store.dirty[i]; }
    if should_write {
      let node = ns_get(&tree.store, i);
      let data = node_page_bytes(&node);
      if data.len() > SNAP_PAGE_MAX_BYTES { return -1; }
      let pg = Page.new(snap_page_id_for(gen, i), data, page_compute_checksum(&data));
      if !page_log_append(&pf, pg) { return -1; }
    }
    i = i + 1;
  }

  let hdr = snap_header_page_bytes(tree.root, tree.order, ns_len(&tree.store),
                                   checkpoint_lsn, gen);
  if hdr.len() > SNAP_PAGE_MAX_BYTES { return -1; }
  let hp = Page.new(0, hdr, page_compute_checksum(&hdr));
  if page_log_append(&pf, hp) {
    ns_mark_clean(&mut tree.store);
    return gen;
  }
  return -1;
}

// Load a snapshot; None when absent or invalid at ANY level (page checksum,
// header, node codec, node count, child-pointer range). The caller then
// falls back to full WAL replay.
fn snap_load(path: Str) -> Option[Snapshot] {
  let pf = page_file_open(path);
  let pages = page_log_read_all(&pf);
  let meta_found = snap_read_meta(&pages);
  var meta = SnapshotMeta{ root: 0, order: 3, node_count: 0, checkpoint_lsn: 0, generation: -1 };
  match meta_found {
    None => { return None; }
    Some(m) => {
      let mm: SnapshotMeta = m;
      meta = mm;
    }
  }
  if meta.order < 3 { return None; }
  if meta.node_count < 1 { return None; }
  if meta.node_count >= SNAP_PAGE_STRIDE { return None; }
  if meta.root < 0 { return None; }
  if meta.root >= meta.node_count { return None; }

  let resolved = snap_resolve_pages(&pages, meta.node_count, meta.generation);
  var best = Vec[Page].new();
  match resolved {
    None => { return None; }
    Some(v) => {
      let vv: Vec[Page] = v;
      best = vv;
    }
  }

  var nodes = Vec[BTreeNode].new();
  var i = 0;
  while i < meta.node_count {
    let pg = best[i];
    let dec = node_page_decode(&pg.data);
    match dec {
      None => { return None; }
      Some(n) => {
        let nd: BTreeNode = n;
        nodes.push(nd);
      }
    }
    i = i + 1;
  }

  // Child pointers must address loaded nodes: a CRC-valid but semantically
  // corrupt snapshot must not reach search/traverse as a dangling pointer.
  var j = 0;
  while j < nodes.len() {
    let nd = nodes[j];
    var c = 0;
    while c < nd.children.len() {
      if nd.children[c] < 0 { return None; }
      if nd.children[c] >= meta.node_count { return None; }
      c = c + 1;
    }
    j = j + 1;
  }

  // Loaded nodes are clean: their pages are already committed.
  var dirty = Vec[Bool].new();
  var births = Vec[Int].new();
  var di = 0;
  while di < nodes.len() {
    dirty.push(false);
    births.push(0);
    di = di + 1;
  }
  var store = ns_new_resident(nodes, dirty, births);
  var tree = BTree{ root: meta.root, order: meta.order, store: store };
  return Some(Snapshot{ tree: tree, checkpoint_lsn: meta.checkpoint_lsn, generation: meta.generation });
}

// --- v2 snapshot container (byte blocks; M1.2 S3) --------------------------
// The node payload codec is unchanged (`node_page_bytes`, node_page module); only the
// container changes: node index = block page_id, snapshot generation = block
// generation, and the block store's header slot carries the meta (root,
// order, node_count, checkpoint_lsn). Reads auto-detect by first byte.

fn snap_format_v2(path: Str) -> Bool {
  match byteio_read_at(path, 0, 1) {
    Some(b) => {
      if b.len() == 1 && b[0] == 0x4F { return true; }
      return false;
    }
    None => { return false; }
  }
}

pub fn snap_load_auto(path: Str) -> Option[Snapshot] {
  if snap_format_v2(path) { return snap_load_v2(path); }
  let pf = page_file_open(path);
  let _ = page_log_heal_tail(&pf);
  return snap_load(path);
}

// Read a v2 snapshot through the block store: the committed header carries
// the meta, one committed block per node index carries the node payload.
// Same strictness as v1: any gap/codec/range violation is None.
fn snap_load_v2(path: Str) -> Option[Snapshot] {
  let bs = block_store_open(path);
  if !bs.committed { return None; }
  let node_count = bs.header.node_count;
  let order = bs.header.order;
  let root = bs.header.root;
  if order < 3 { return None; }
  if node_count < 1 { return None; }
  if node_count >= SNAP_PAGE_STRIDE { return None; }
  if root < 0 { return None; }
  if root >= node_count { return None; }

  // Strict validation pass: every node page must decode and every child
  // pointer must be in range. Nodes are discarded -- the pager decodes on
  // demand (M1.1b); only the block directory and O(n) metadata stay.
  var i = 0;
  while i < node_count {
    match block_store_read(&bs, i) {
      Some(p) => {
        match node_page_decode(&p.payload) {
          Some(nd) => {
            var c = 0;
            while c < nd.children.len() {
              if nd.children[c] < 0 { return None; }
              if nd.children[c] >= node_count { return None; }
              c = c + 1;
            }
          }
          None => { return None; }
        }
      }
      None => { return None; }
    }
    i = i + 1;
  }
  let store = ns_new_paged(bs, node_count, pager_capacity());
  var tree = BTree{ root: root, order: order, store: store };
  return Some(Snapshot{ tree: tree, checkpoint_lsn: bs.header.checkpoint_lsn,
                        generation: bs.header.committed_generation });
}

// Full v2 write from the TREE into a temp file, then one atomic rename. Used
// for migration (v1 -> v2), format flips, and compaction. For a paged tree
// with no pins this is a GC compaction: only nodes reachable from the live
// root are written, with dense ids (retired/abandoned nodes are dropped);
// the pager is reset to the new id space. Resident trees keep the all-node
// rewrite (v1 legacy handles; the next reopen loads a paged store).
fn v2_rewrite_all(path: Str, tree: &mut BTree, gen: Int, checkpoint_lsn: Int) -> Bool {
  let tmp = path + ".rw";
  match io.remove_file(tmp) { Ok(_) => {} Err(_) => {} }
  var bs = block_store_open(tmp);
  let n = ns_len(&tree.store);
  let do_gc = tree.store.paged && tree.store.pins.len() == 0;
  var new_root = tree.root;
  var new_count = n;
  var i = 0;
  // Reused node-page payload buffer for both v2 write loops (m375 fallback).
  var data = Vec[Int].new();

  if do_gc {
    var reach = Vec[Bool].new();
    i = 0;
    while i < n {
      reach.push(false);
      i = i + 1;
    }
    // BFS from the live root (a growing stack + cursor; Vec.pop is Option).
    var stack = Vec[Int].new();
    stack.push(tree.root);
    var si = 0;
    while si < stack.len() {
      let idx = stack[si];
      si = si + 1;
      if idx < 0 || idx >= n { return false; }
      if !reach[idx] {
        reach[idx] = true;
        let node = ns_get(&tree.store, idx);
        var c = 0;
        while c < node.children.len() {
          stack.push(node.children[c]);
          c = c + 1;
        }
      }
    }
    var remap = Vec[Int].new();
    i = 0;
    while i < n {
      remap.push(-1);
      i = i + 1;
    }
    new_count = 0;
    i = 0;
    while i < n {
      if reach[i] {
        remap[i] = new_count;
        new_count = new_count + 1;
      }
      i = i + 1;
    }
    if new_count < 1 { return false; }
    new_root = remap[tree.root];
    if new_root < 0 { return false; }
    i = 0;
    while i < n {
      if reach[i] {
        var node = ns_get(&tree.store, i);
        var c = 0;
        while c < node.children.len() {
          node.children[c] = remap[node.children[c]];
          c = c + 1;
        }
        node_page_bytes_into(&mut data, &node);
        if block_store_put(&mut bs, gen, remap[i], &data) < 0 { return false; }
      }
      i = i + 1;
    }
  } else {
    i = 0;
    while i < n {
      let node = ns_get(&tree.store, i);
      node_page_bytes_into(&mut data, &node);
      if block_store_put(&mut bs, gen, i, &data) < 0 { return false; }
      i = i + 1;
    }
  }

  let h = BlockHeader{
    root: new_root,
    order: tree.order,
    node_count: new_count,
    checkpoint_lsn: checkpoint_lsn,
    committed_generation: gen,
    block_count: bs.block_count,
    next_page_id: 0,
  };
  if !block_store_commit(&mut bs, &h) { return false; }
  match io.rename(tmp, path) {
    Ok(_) => {}
    Err(_) => { return false; }
  }
  if do_gc {
    // Replace the whole store with a fresh paged value. Do NOT hand a local
    // BlockStore to an in-place reset helper: the local owner can be reclaimed
    // while the store still encodes its vectors (post-GC reads then hang).
    let fresh = block_store_open(path);
    let cap = tree.store.capacity;
    tree.store = ns_new_paged(fresh, new_count, cap);
    tree.root = new_root;
  } else if tree.store.paged {
    // A paged tree read its nodes from THIS path; the rename replaced the
    // inode, so rebind the pager to the fresh directory (same ids, new gen).
    let fresh = block_store_open(path);
    tree.store.bs = fresh;
    tree.store.write_gen = fresh.header.committed_generation + 1;
  }
  return true;
}

// v2 incremental flush: append new versions of only the DIRTY nodes at
// gen = committed + 1, then commit the header slot. A v1 (or absent) file is
// rewritten whole (migration-on-write). Crashed partial generations are
// overwritten by the same-gen rewrites on the next attempt, so they can
// never become the only version of a node. `allow_compact` is false while a
// snapshot pin is live (M3): the block-count rewrite (compaction) is deferred
// (counted) and the incremental append continues. Returns the committed
// generation, or -1 (the previous snapshot stays valid in every failure
// mode).
fn snap_flush_v2(path: Str, tree: &mut BTree, checkpoint_lsn: Int, allow_compact: Bool) -> Int {
  let is_v2 = snap_format_v2(path);
  if !is_v2 {
    let gen = 1;
    if v2_rewrite_all(path, tree, gen, checkpoint_lsn) {
      ns_mark_clean(&mut tree.store);
      return gen;
    }
    return -1;
  }

  // M1.1b paged tree: the NodeStore owns the v2 container handle, so spills
  // and checkpoint appends share one block_count (no dual-handle overwrite).
  if tree.store.paged {
    var pgen = 0;
    if tree.store.bs.committed { pgen = tree.store.bs.header.committed_generation; }
    let gen = pgen + 1;
    if tree.store.bs.block_count > ns_len(&tree.store) + SNAP_COMPACT_SLACK {
      if !allow_compact {
        tree.store.compaction_deferred = tree.store.compaction_deferred + 1;
      } else {
        if v2_rewrite_all(path, tree, gen, checkpoint_lsn) {
          ns_mark_clean(&mut tree.store);
          return gen;
        }
        return -1;
      }
    }
    // Every append goes through the store's REAL BlockStore: cache evictions
    // during this loop spill and bump the same block_count, so the
    // checkpoint's header and blocks stay consistent. C-ORBIT-13 (3-level
    // `&mut` copies) is fixed in v0.64.8; the natural nested `&mut` is used.
    var pdata = Vec[Int].new();
    var pi = 0;
    while pi < ns_len(&tree.store) {
      if tree.store.dirty[pi] {
        let pnode = ns_get(&tree.store, pi);
        node_page_bytes_into(&mut pdata, &pnode);
        if block_store_put(&mut tree.store.bs, gen, pi, &pdata) < 0 { return -1; }
      }
      pi = pi + 1;
    }
    let ph = BlockHeader{
      root: tree.root,
      order: tree.order,
      node_count: ns_len(&tree.store),
      checkpoint_lsn: checkpoint_lsn,
      committed_generation: gen,
      block_count: tree.store.bs.block_count,
      next_page_id: 0,
    };
    if !block_store_commit(&mut tree.store.bs, &ph) { return -1; }
    ns_mark_clean(&mut tree.store);
    ns_release_pending(&mut tree.store);
    return gen;
  }

  var bs = block_store_open(path);
  var prior_gen = 0;
  var have_prior = false;
  if bs.committed {
    prior_gen = bs.header.committed_generation;
    have_prior = true;
  }
  let gen = prior_gen + 1;

  if !have_prior || bs.block_count > ns_len(&tree.store) + SNAP_COMPACT_SLACK {
    if have_prior && !allow_compact {
      // M3: the whole-file rewrite drops older block generations a live pin
      // may still need. Defer; append incrementally instead.
      tree.store.compaction_deferred = tree.store.compaction_deferred + 1;
    } else {
      if v2_rewrite_all(path, tree, gen, checkpoint_lsn) {
        ns_mark_clean(&mut tree.store);
        return gen;
      }
      return -1;
    }
  }

  var i = 0;
  var data = Vec[Int].new();
  while i < ns_len(&tree.store) {
    if tree.store.dirty[i] {
      let node = ns_get(&tree.store, i);
      node_page_bytes_into(&mut data, &node);
      if block_store_put(&mut bs, gen, i, &data) < 0 { return -1; }
    }
    i = i + 1;
  }
  let h = BlockHeader{
    root: tree.root,
    order: tree.order,
    node_count: ns_len(&tree.store),
    checkpoint_lsn: checkpoint_lsn,
    committed_generation: gen,
    block_count: bs.block_count,
    next_page_id: 0,
  };
  if !block_store_commit(&mut bs, &h) { return -1; }
  ns_mark_clean(&mut tree.store);
  ns_release_pending(&mut tree.store);
  return gen;
}

// Migrate an existing v1 text snapshot to v2 in place (idempotent; absent
// or already-v2 snapshots are a no-op success). Reads through the same
// auto-detect loader, writes a fresh v2 store via temp+rename.
pub fn db_file_migrate_snapshot(path: Str) -> Bool {
  let snap_path = path + ".snap";
  if snap_format_v2(snap_path) { return true; }
  match snap_load(snap_path) {
    None => { return true; }
    Some(s) => {
      let snap: Snapshot = s;
      var tree = snap.tree;
      return v2_rewrite_all(snap_path, &mut tree, snap.generation + 1, snap.checkpoint_lsn);
    }
  }
}

// Checkpoint: commit an incremental snapshot of the current tree (only the
// nodes that changed since the last committed generation are appended; the
// header page commits the generation), append the Checkpoint anchor record,
// then truncate the segment to keep the anchor and everything after it.
// Returns the anchor LSN, or -1 when the snapshot could not be committed (the
// WAL is untouched in that case).
pub fn db_file_checkpoint(db: &mut DBFile) -> Int {
  // A pending transaction's records must not be truncated: truncation keeps
  // records >= the anchor, and the checkpoint_lsn gate would skip a later
  // commit record's ops. Reject while a transaction is active.
  if db.txn_active { return -1; }
  // A held append fd becomes stale across the WAL truncate below; close it
  // (puts reopen lazily). The txn window owns its fd only while active.
  db_close_append_fd(db);
  // A stale handle must not snapshot its older tree over a newer WAL.
  if !db_file_guard(db) { return -1; }
  if db.failed { return -1; }
  let snap_path = db.path + ".snap";
  let snap_lsn = wal_file_next_lsn(&db.wal) - 1;
  // Two-phase (immediate mode): the WAL must be durable BEFORE the snapshot
  // publishes its header, so a crash can never leave a snapshot that runs
  // ahead of the log (docs/REFERENCE-STUDY.md; redb 2PC).
  if db.durability == 1 && db.two_phase {
    if !byteio_sync(db.path) {
      db.failed = true;
      return -1;
    }
  }
  var gen = -1;
  // M3: while a snapshot pin is live the compaction branch defers (counted);
  // incremental appends, the anchor and the WAL truncate are unaffected.
  let allow_compact = db.tree.store.pins.len() == 0;
  if db.page_format == 2 {
    gen = snap_flush_v2(snap_path, &mut db.tree, snap_lsn, allow_compact);
  } else if snap_format_v2(snap_path) {
    // Handle writes v1 while the file is v2: rewrite whole via the batch
    // path (single rename), keeping the format on-disk authoritative. That
    // rewrite is compaction-class: defer the checkpoint while pinned.
    if !allow_compact {
      db.tree.store.compaction_deferred = db.tree.store.compaction_deferred + 1;
      return -1;
    }
    var pgen = 0;
    let bs = block_store_open(snap_path);
    if bs.committed { pgen = bs.header.committed_generation; }
    if snap_compact(snap_path, &mut db.tree, snap_lsn, pgen + 1) { gen = pgen + 1; }
  } else {
    let pf = page_file_open(snap_path);
    // A torn trailing append must not merge with this checkpoint's entries.
    let _ = page_log_heal_tail(&pf);
    gen = snap_flush(snap_path, &mut db.tree, snap_lsn, allow_compact);
  }
  if gen < 0 { return -1; }
  db.snap_generation = gen;

  var payload = Vec[Int].new();
  payload.push(gen);
  payload.push(ns_len(&db.tree.store));
  payload.push(db.tree.order);
  let anchor = wal_file_append_tagged(&mut db.wal, WALOpKind.Checkpoint,
                                      snap_lsn, db.tree.root, payload, 0);
  if anchor < 0 { return -1; }

  // Best-effort compaction: keeping lsn >= anchor retains the anchor itself,
  // so next_lsn still resumes correctly. A failed truncate leaves older
  // records that `db_file_open` skips via the snapshot's checkpoint_lsn gate.
  let _ = wal_file_truncate(db.path, anchor);
  db.wal_bytes = db_wal_size(db.path);
  db.records_since_ckpt = 0;
  // Post-commit flush (immediate mode): a failure latches the handle; the
  // checkpoint itself may still have committed (the caller can inspect
  // db_file_failed). WAL first, then the snapshot.
  if db.durability == 1 {
    if !byteio_sync(db.path) {
      db.failed = true;
      return -1;
    }
    if !byteio_sync(snap_path) {
      db.failed = true;
      return -1;
    }
  }
  return anchor;
}

// Policy hook: checkpoint when at least `limit` records were logged since the
// last checkpoint. Returns the anchor LSN when a checkpoint ran, or -1 when
// the threshold is not reached (or the checkpoint failed).
pub fn db_file_maybe_checkpoint(db: &mut DBFile, limit: Int) -> Int
  requires: limit >= 1
{
  if db.records_since_ckpt < limit { return -1; }
  return db_file_checkpoint(db);
}

// ===========================================================================
// M3 MINIMAL SUBSET: SNAPSHOT PINS (docs/MVCC.md)
// ===========================================================================
// A snapshot pin captures {root, lsn, generation} and makes it stable: while
// pins exist, every write path copy-on-writes the nodes it touches
// (`cow_shadow`), so a pinned root keeps reading the exact state at capture.
// No per-page version chains: old versions stay in the arena reachable only
// from pins. Pins are handle-local; a reopen starts with none.
// Savepoints are txn-scoped rollback markers: restore trims the buffered ops
// and splices the WAL window (Abort + Begin + re-log of the kept ops) so
// replay reconstructs exactly the surviving set after any crash.

fn db_file_pin_index(db: &DBFile, id: Int) -> Int {
  var i = 0;
  while i < db.tree.store.pins.len() {
    if db.tree.store.pins[i].id == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Capture the current committed state as a stable read view (id 0 would mean
// failure; ids are monotone and never reused). Buffered transaction ops are
// NOT visible in the pinned view (read-committed).
pub fn db_file_snapshot_begin(db: &mut DBFile) -> DBSnapshot {
  db.tree.store.pin_clock = db.tree.store.pin_clock + 1;
  var pin = DBSnapshot{ id: db.tree.store.pin_clock, root: db.tree.root,
                        pin_epoch: db.tree.store.pin_clock,
                        lsn: wal_file_next_lsn(&db.wal) - 1,
                        generation: db.snap_generation };
  db.tree.store.pins.push(pin);
  return pin;
}

// Release a pin (false for an unknown id). Retired versions may now be
// released; a later checkpoint GC-compacts them out of the v2 file.
pub fn db_file_snapshot_end(db: &mut DBFile, id: Int) -> Bool {
  let at = db_file_pin_index(db, id);
  if at < 0 { return false; }
  var i = at;
  while i < db.tree.store.pins.len() - 1 {
    db.tree.store.pins[i] = db.tree.store.pins[i + 1];
    i = i + 1;
  }
  db.tree.store.pins.pop();
  ns_release_pending(&mut db.tree.store);
  return true;
}

pub fn db_file_snapshot_pins(db: &DBFile) -> Int {
  return db.tree.store.pins.len();
}

// Oldest pinned WAL LSN, or -1 when none. Deferred-free hook for the M1.1b
// pager: once a free list exists, pages are allocatable only below this LSN.
pub fn db_file_min_pinned_lsn(db: &DBFile) -> Int {
  if db.tree.store.pins.len() == 0 { return -1; }
  var best = db.tree.store.pins[0].lsn;
  var i = 1;
  while i < db.tree.store.pins.len() {
    if db.tree.store.pins[i].lsn < best { best = db.tree.store.pins[i].lsn; }
    i = i + 1;
  }
  return best;
}

// Snapshot reads: exactly the state at `db_file_snapshot_begin`. None /
// empty / -1 for an id that is not a live pin.
pub fn db_file_snapshot_get(db: &DBFile, id: Int, key: Int) -> Option[Int] {
  let at = db_file_pin_index(db, id);
  if at < 0 { return None; }
  return search_node(&db.tree, db.tree.store.pins[at].root, key);
}

pub fn db_file_snapshot_get_typed(db: &DBFile, id: Int, key: Int) -> Option[Vec[Int]] {
  let at = db_file_pin_index(db, id);
  if at < 0 { return None; }
  return search_payload_node(&db.tree, db.tree.store.pins[at].root, key);
}

pub fn db_file_snapshot_range(db: &DBFile, id: Int, low: Int, high: Int) -> Vec[Int] {
  var results = Vec[Int].new();
  let at = db_file_pin_index(db, id);
  if at < 0 { return results; }
  if low > high { return results; }
  collect_range(&db.tree, db.tree.store.pins[at].root, low, high, &mut results);
  return results;
}

pub fn db_file_snapshot_count(db: &DBFile, id: Int) -> Int {
  let at = db_file_pin_index(db, id);
  if at < 0 { return -1; }
  return count_keys(&db.tree, db.tree.store.pins[at].root);
}

// Last committed snapshot generation for this handle (0 = none), set on open
// and after every committed checkpoint.
pub fn db_file_snap_generation(db: &DBFile) -> Int {
  return db.snap_generation;
}

// Checkpoints that would have compacted but were deferred because a snapshot
// pin was live.
pub fn db_file_compaction_deferrals(db: &DBFile) -> Int {
  return db.tree.store.compaction_deferred;
}