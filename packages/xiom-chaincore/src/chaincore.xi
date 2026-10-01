// XIOM -- xiom.chaincore: pure deterministic blockchain core model
// Port task: promote the xiom.chaincore placeholder to a real, tested,
// pure-XIOM package (block headers, transaction records, a chain store with
// append/validation, cumulative-work fork choice, reorg undo/redo, an orphan
// pool with parent-arrival promotion and finality-depth tracking).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope and purity: no crypto, no networking, no clocks, no I/O, no FFI and
// no global state. Block tags, parent tags and state roots are opaque
// caller-supplied integers; this module never computes a hash. The caller
// owns the store and drives every insertion; the model is deterministic.
//
// Conventions (v0.62.2):
//   * the genesis block is tag 1 (chain_genesis_tag), parent tag 0, height 0,
//     own work 1 and the caller's genesis state root;
//   * a valid child declares height == parent.height + 1 and work > 0; the
//     store tracks cumulative work = parent.cumulative + own;
//   * every store-taking function takes `&mut ChainStore` (uniform borrow
//     discipline: a shared-then-mutable reborrow pattern is never emitted);
//   * Result construction is confined to the _ok_int/_err_int leaf helpers;
//   * all data lives in parallel Vec[Int] arrays (no Vec[StructType]) and
//     every Vec element read goes through a typed local;
//   * every loop makes strict progress (index walks, shrinking pools, or
//     strictly decreasing heights), so every call terminates.
//
// Fork choice: the best tip is the block with the greatest cumulative work;
// ties are broken by the lower tag (deterministic). A best-tip change is a
// branch reorg only when the previous tip is not an ancestor of the new tip;
// plain extensions of the current best chain update the tip silently. A reorg
// records the common ancestor, the removed suffix (undo, tip-first) and the
// added suffix (redo, ancestor-first); chain_reorg_undo/chain_reorg_redo
// replay the last switch.
//
// Finality: a depth is pure bookkeeping. The finalized height is
// max(0, best height - depth); genesis is always at the finalized height.

module xiom.chaincore

use xiom.convert;

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

/// Immutable block header: parent tag, height, own work and an opaque state
/// root tag. The caller chooses every value; the module checks consistency
/// against the parent it links to and never interprets the root.
pub type BlockHeader = {
  parent: Int;
  height: Int;
  work: Int;
  root: Int;
}

/// Chain store: all inserted blocks (tags/parents/heights/own/cumulative
/// work/state roots), the orphan pool (same shape), flat transaction records
/// (block tag/id/fee), the best-tip tag, the finality depth and the record of
/// the last branch switch (undo/redo tags, common ancestor).
///
/// All lists are parallel Vec[Int] arrays addressed by index. Fields are
/// public for inspection; every state transition must go through the
/// chain_* functions, which maintain the invariants checked by
/// chain_violations.
pub type ChainStore = {
  tags: Vec[Int];
  parents: Vec[Int];
  heights: Vec[Int];
  own: Vec[Int];
  works: Vec[Int];
  roots: Vec[Int];
  otags: Vec[Int];
  oparents: Vec[Int];
  oheights: Vec[Int];
  oown: Vec[Int];
  oroots: Vec[Int];
  tx_block: Vec[Int];
  txids: Vec[Int];
  txfees: Vec[Int];
  best: Int;
  finality: Int;
  last_promoted: Int;
  reorg_events: Int;
  reorg_state: Int;
  reorg_old: Int;
  reorg_new: Int;
  reorg_common: Int;
  undo: Vec[Int];
  redo: Vec[Int];
}

// ============================================================================
// Internal helpers
// ============================================================================

// Index of inserted block `tag`, or -1. Parallel-array scan (the model is
// deliberately allocation-free apart from the Vecs; stores are small).
fn _block_index(chain: &mut ChainStore, tag: Int) -> Int {
  var i: Int = 0;
  while i < chain.tags.len() {
    let t: Int = chain.tags[i];
    if t == tag {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of orphan `tag`, or -1.
fn _orphan_index(chain: &mut ChainStore, tag: Int) -> Int {
  var i: Int = 0;
  while i < chain.otags.len() {
    let t: Int = chain.otags[i];
    if t == tag {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of transaction `id`, or -1.
fn _tx_index(chain: &mut ChainStore, id: Int) -> Int {
  var i: Int = 0;
  while i < chain.txids.len() {
    let t: Int = chain.txids[i];
    if t == id {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Height of inserted block `tag`, or -1.
fn _height_of(chain: &mut ChainStore, tag: Int) -> Int {
  let i: Int = _block_index(chain, tag);
  if i < 0 {
    return -1;
  }
  return chain.heights[i];
}

// Parent tag of inserted block `tag`, or -1.
fn _parent_of(chain: &mut ChainStore, tag: Int) -> Int {
  let i: Int = _block_index(chain, tag);
  if i < 0 {
    return -1;
  }
  return chain.parents[i];
}

// Cumulative work of inserted block `tag`, or -1.
fn _work_of(chain: &mut ChainStore, tag: Int) -> Int {
  let i: Int = _block_index(chain, tag);
  if i < 0 {
    return -1;
  }
  return chain.works[i];
}

// Append one inserted block (arrays stay parallel).
fn _push_block(chain: &mut ChainStore, tag: Int, parent: Int, height: Int, own: Int, cum: Int, root: Int) {
  chain.tags.push(tag);
  chain.parents.push(parent);
  chain.heights.push(height);
  chain.own.push(own);
  chain.works.push(cum);
  chain.roots.push(root);
}

// Append one orphan pool entry (arrays stay parallel).
fn _push_orphan(chain: &mut ChainStore, tag: Int, parent: Int, height: Int, own: Int, root: Int) {
  chain.otags.push(tag);
  chain.oparents.push(parent);
  chain.oheights.push(height);
  chain.oown.push(own);
  chain.oroots.push(root);
}

// Swap-remove orphan at index `at`; every parallel array shrinks by one.
fn _remove_orphan_at(chain: &mut ChainStore, at: Int) {
  let last: Int = chain.otags.len() - 1;
  let t: Int = chain.otags[last];
  let p: Int = chain.oparents[last];
  let h: Int = chain.oheights[last];
  let w: Int = chain.oown[last];
  let r: Int = chain.oroots[last];
  chain.otags[at] = t;
  chain.oparents[at] = p;
  chain.oheights[at] = h;
  chain.oown[at] = w;
  chain.oroots[at] = r;
  chain.otags.pop();
  chain.oparents.pop();
  chain.oheights.pop();
  chain.oown.pop();
  chain.oroots.pop();
}

// Index of the fork-choice winner among inserted blocks: greatest cumulative
// work, ties broken by the lower tag. The store always has genesis (index 0).
fn _best_index(chain: &mut ChainStore) -> Int {
  var bi: Int = 0;
  var i: Int = 1;
  while i < chain.tags.len() {
    let w: Int = chain.works[i];
    let bw: Int = chain.works[bi];
    if w > bw {
      bi = i;
    } else if w == bw {
      let t: Int = chain.tags[i];
      let bt: Int = chain.tags[bi];
      if t < bt {
        bi = i;
      }
    }
    i = i + 1;
  }
  return bi;
}

// True when inserted block `a` is `b` itself or one of its ancestors. The
// walk is bounded by the number of inserted blocks, so it terminates even if
// the store was corrupted by direct field writes.
fn _is_ancestor(chain: &mut ChainStore, a: Int, b: Int) -> Bool {
  if a == b {
    return true;
  }
  var w: Int = b;
  var steps: Int = 0;
  while w != 0 && steps <= chain.tags.len() {
    if w == a {
      return true;
    }
    w = _parent_of(chain, w);
    steps = steps + 1;
  }
  return false;
}

// Deepest common ancestor of two inserted blocks. Each step strictly lowers
// the height of the deeper side, so the walk terminates in at most
// max(height) steps.
fn _common_ancestor(chain: &mut ChainStore, a: Int, b: Int) -> Int {
  var x: Int = a;
  var y: Int = b;
  while x != y {
    let hx: Int = _height_of(chain, x);
    let hy: Int = _height_of(chain, y);
    if hx > hy {
      x = _parent_of(chain, x);
    } else if hy > hx {
      y = _parent_of(chain, y);
    } else {
      x = _parent_of(chain, x);
      y = _parent_of(chain, y);
    }
  }
  return x;
}

// Record a branch switch: common ancestor, removed suffix (undo, tip-first)
// and added suffix (redo, ancestor-first, reversed after collection).
// Complexity: O(chain length).
fn _record_reorg(chain: &mut ChainStore, old_tip: Int, new_tip: Int) {
  chain.reorg_old = old_tip;
  chain.reorg_new = new_tip;
  chain.reorg_common = _common_ancestor(chain, old_tip, new_tip);
  chain.reorg_state = 1;
  chain.reorg_events = chain.reorg_events + 1;
  while chain.undo.len() > 0 {
    chain.undo.pop();
  }
  while chain.redo.len() > 0 {
    chain.redo.pop();
  }
  var t: Int = old_tip;
  while t != chain.reorg_common {
    chain.undo.push(t);
    t = _parent_of(chain, t);
  }
  var u: Int = new_tip;
  while u != chain.reorg_common {
    chain.redo.push(u);
    u = _parent_of(chain, u);
  }
  var lo: Int = 0;
  var hi: Int = chain.redo.len() - 1;
  while lo < hi {
    let x: Int = chain.redo[lo];
    let y: Int = chain.redo[hi];
    chain.redo[lo] = y;
    chain.redo[hi] = x;
    lo = lo + 1;
    hi = hi - 1;
  }
}

// Recompute the fork-choice winner and update the best tip. A change is a
// recorded reorg only when the previous tip is not an ancestor of the new
// tip; extending the best chain is not a reorg.
fn _recompute_best(chain: &mut ChainStore) {
  let bi: Int = _best_index(chain);
  let nt: Int = chain.tags[bi];
  let ot: Int = chain.best;
  if nt != ot {
    if !_is_ancestor(chain, ot, nt) {
      _record_reorg(chain, ot, nt);
    }
    chain.best = nt;
  }
}

// Attach every orphan whose parent is now an inserted block, re-validating
// the height rule. An orphan that fails validation is dropped. Each pass
// removes at least one orphan or stops, so the pool shrinks monotonically and
// the loop terminates. Returns the number of promoted blocks.
fn _promote_orphans(chain: &mut ChainStore) -> Int {
  var promoted: Int = 0;
  var progressed: Bool = true;
  while progressed {
    progressed = false;
    var i: Int = 0;
    while i < chain.otags.len() {
      let t: Int = chain.otags[i];
      let p: Int = chain.oparents[i];
      let hh: Int = chain.oheights[i];
      let ww: Int = chain.oown[i];
      let rr: Int = chain.oroots[i];
      let pi: Int = _block_index(chain, p);
      if pi >= 0 {
        let phe: Int = chain.heights[pi];
        let pwo: Int = chain.works[pi];
        if hh == phe + 1 {
          _push_block(chain, t, p, hh, ww, pwo + ww, rr);
          promoted = promoted + 1;
        }
        _remove_orphan_at(chain, i);
        progressed = true;
      } else {
        i = i + 1;
      }
    }
  }
  return promoted;
}

// ============================================================================
// Constants
// ============================================================================

/// The tag reserved for the genesis block created by chain_new. Complexity: O(1).
pub fn chain_genesis_tag() -> Int {
  return 1;
}

/// Complete status of chain_append: the block is on the best chain. Complexity: O(1).
pub fn chain_status_added() -> Int {
  return 2;
}

/// Complete status of chain_append: the block is attached to a side branch.
/// Complexity: O(1).
pub fn chain_status_side() -> Int {
  return 1;
}

/// Complete status of chain_append: the block was parked in the orphan pool.
/// Complexity: O(1).
pub fn chain_status_orphan() -> Int {
  return 0;
}

/// Default finality depth of a fresh store. Complexity: O(1).
pub fn chain_default_finality_depth() -> Int {
  return 6;
}

// Invariant bit: genesis shape (tag 1 at index 0, parent 0, height 0,
// cumulative work == own work > 0). Complexity: O(1).
pub fn chain_violation_genesis() -> Int {
  return 1;
}

// Invariant bit: parent linkage (parent exists, height == parent height + 1).
// Complexity: O(1).
pub fn chain_violation_linkage() -> Int {
  return 2;
}

// Invariant bit: work accumulation (cumulative == parent cumulative + own and
// own > 0). Complexity: O(1).
pub fn chain_violation_work() -> Int {
  return 4;
}

// Invariant bit: no duplicate inserted tags. Complexity: O(1).
pub fn chain_violation_duplicate() -> Int {
  return 8;
}

// Invariant bit: best tip is the max-work/min-tag block. Complexity: O(1).
pub fn chain_violation_best() -> Int {
  return 16;
}

// Invariant bit: the best chain walks back to genesis. Complexity: O(1).
pub fn chain_violation_best_chain() -> Int {
  return 32;
}

// Invariant bit: orphan pool shape (tags not inserted, parents still unknown,
// positive height and own work). Complexity: O(1).
pub fn chain_violation_orphans() -> Int {
  return 64;
}

// Invariant bit: transaction records (known block, non-negative fee, unique
// id). Complexity: O(1).
pub fn chain_violation_transactions() -> Int {
  return 128;
}

// ============================================================================
// Construction
// ============================================================================

/// Build a block header value. No validation happens here; chain_append
/// validates the header against the parent it declares.
/// Complexity: O(1).
pub fn chain_header(parent: Int, height: Int, work: Int, root: Int) -> BlockHeader {
  return BlockHeader{ parent: parent; height: height; work: work; root: root; };
}

/// Fresh store with only the genesis block: tag 1, parent 0, height 0, own
/// work 1, cumulative work 1, state root `genesis_root`. The best tip is the
/// genesis block, the finality depth is 6 and every list is empty except the
/// genesis entry. No error path.
/// Complexity: O(1).
pub fn chain_new(genesis_root: Int) -> ChainStore {
  var c = ChainStore{
    tags: Vec[Int].new();
    parents: Vec[Int].new();
    heights: Vec[Int].new();
    own: Vec[Int].new();
    works: Vec[Int].new();
    roots: Vec[Int].new();
    otags: Vec[Int].new();
    oparents: Vec[Int].new();
    oheights: Vec[Int].new();
    oown: Vec[Int].new();
    oroots: Vec[Int].new();
    tx_block: Vec[Int].new();
    txids: Vec[Int].new();
    txfees: Vec[Int].new();
    best: 1;
    finality: 6;
    last_promoted: 0;
    reorg_events: 0;
    reorg_state: 0;
    reorg_old: 0;
    reorg_new: 0;
    reorg_common: 0;
    undo: Vec[Int].new();
    redo: Vec[Int].new();
  };
  c.tags.push(1);
  c.parents.push(0);
  c.heights.push(0);
  c.own.push(1);
  c.works.push(1);
  c.roots.push(genesis_root);
  return c;
}

// ============================================================================
// Append and validation
// ============================================================================

/// Append block `tag` with header `h`.
///
/// Rejection order and error catalog (all messages prefixed "chaincore: "):
///   1. tag <= 0                     -> "tag must be positive"
///   2. tag == genesis tag           -> "genesis tag is reserved"
///   3. parent <= 0                  -> "parent tag must be positive"
///   4. parent == tag                -> "block cannot parent itself"
///   5. height <= 0                  -> "height must be positive"
///   6. work <= 0                    -> "work must be positive"
///   7. tag already inserted or parked -> "duplicate block tag: <tag>"
///   8. unknown parent               -> parked as orphan, Ok(0)
///   9. height != parent height + 1  -> "height must be parent height + 1"
///
/// On success the block is inserted with cumulative work
/// parent.works + h.work, all orphans that can now attach are promoted
/// (chain_last_promoted reports how many), the fork choice is recomputed and
/// the status is Ok(2) when the tag is on the best chain, Ok(1) otherwise.
/// Complexity: O(n^2) worst case in the number of stored blocks (fork-choice
/// and promotion rescans), O(n) for a single extension.
pub fn chain_append(chain: &mut ChainStore, tag: Int, h: BlockHeader) -> Result[Int, Str] {
  if tag <= 0 {
    return _err_int("chaincore: tag must be positive");
  }
  if tag == 1 {
    return _err_int("chaincore: genesis tag is reserved");
  }
  if h.parent <= 0 {
    return _err_int("chaincore: parent tag must be positive");
  }
  if h.parent == tag {
    return _err_int("chaincore: block cannot parent itself");
  }
  if h.height <= 0 {
    return _err_int("chaincore: height must be positive");
  }
  if h.work <= 0 {
    return _err_int("chaincore: work must be positive");
  }
  if _block_index(chain, tag) >= 0 {
    return _err_int("chaincore: duplicate block tag: " + convert.int_to_string(tag));
  }
  if _orphan_index(chain, tag) >= 0 {
    return _err_int("chaincore: duplicate block tag: " + convert.int_to_string(tag));
  }
  chain.last_promoted = 0;
  let pi: Int = _block_index(chain, h.parent);
  if pi < 0 {
    _push_orphan(chain, tag, h.parent, h.height, h.work, h.root);
    return _ok_int(0);
  }
  let phe: Int = chain.heights[pi];
  if h.height != phe + 1 {
    return _err_int("chaincore: height must be parent height + 1");
  }
  let pwo: Int = chain.works[pi];
  _push_block(chain, tag, h.parent, h.height, h.work, pwo + h.work, h.root);
  chain.last_promoted = _promote_orphans(chain);
  _recompute_best(chain);
  if chain_on_best(chain, tag) {
    return _ok_int(2);
  }
  return _ok_int(1);
}

// ============================================================================
// Fork choice, best chain and reorg
// ============================================================================

/// Best-tip tag (fork-choice winner: greatest cumulative work, ties broken by
/// the lower tag). Complexity: O(1).
pub fn chain_best_tag(chain: &mut ChainStore) -> Int {
  return chain.best;
}

/// Height of the best tip. Complexity: O(n).
pub fn chain_best_height(chain: &mut ChainStore) -> Int {
  return _height_of(chain, chain.best);
}

/// Cumulative work of the best tip. Complexity: O(n).
pub fn chain_best_work(chain: &mut ChainStore) -> Int {
  return _work_of(chain, chain.best);
}

/// Number of blocks on the best chain, genesis included. Complexity: O(n).
pub fn chain_best_chain_len(chain: &mut ChainStore) -> Int {
  var n: Int = 0;
  var w: Int = chain.best;
  var steps: Int = 0;
  while w != 0 && steps <= chain.tags.len() {
    n = n + 1;
    w = _parent_of(chain, w);
    steps = steps + 1;
  }
  return n;
}

/// True when `tag` is an inserted block on the current best chain (genesis
/// included). Unknown tags and parked orphans are false. Complexity: O(n).
pub fn chain_on_best(chain: &mut ChainStore, tag: Int) -> Bool {
  var w: Int = chain.best;
  var steps: Int = 0;
  while w != 0 && steps <= chain.tags.len() {
    if w == tag {
      return true;
    }
    w = _parent_of(chain, w);
    steps = steps + 1;
  }
  return false;
}

/// Number of branch reorgs recorded since chain_new. Extending the current
/// best chain does not count; switching to a different branch does.
/// Complexity: O(1).
pub fn chain_reorg_events(chain: &mut ChainStore) -> Int {
  return chain.reorg_events;
}

/// Last branch-switch state: 0 no reorg yet, 1 applied (redo available),
/// 2 undone (undo applied last). Complexity: O(1).
pub fn chain_reorg_state(chain: &mut ChainStore) -> Int {
  return chain.reorg_state;
}

/// Number of blocks removed from the old best chain by the last branch
/// switch (undo suffix length). Complexity: O(1).
pub fn chain_reorg_undo_count(chain: &mut ChainStore) -> Int {
  return chain.undo.len();
}

/// Number of blocks added on the new best chain by the last branch switch
/// (redo suffix length). Complexity: O(1).
pub fn chain_reorg_redo_count(chain: &mut ChainStore) -> Int {
  return chain.redo.len();
}

/// Tag of the i-th removed block (undo, tip-first), or -1 out of range.
/// Complexity: O(1).
pub fn chain_reorg_undo_tag(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.undo.len() {
    return -1;
  }
  let t: Int = chain.undo[i];
  return t;
}

/// Tag of the i-th added block (redo, ancestor-first), or -1 out of range.
/// Complexity: O(1).
pub fn chain_reorg_redo_tag(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.redo.len() {
    return -1;
  }
  let t: Int = chain.redo[i];
  return t;
}

/// Common ancestor tag of the last branch switch, or 0 when none was
/// recorded. Complexity: O(1).
pub fn chain_reorg_common(chain: &mut ChainStore) -> Int {
  return chain.reorg_common;
}

/// Old best-tip tag of the last branch switch, or 0 when none was recorded.
/// Complexity: O(1).
pub fn chain_reorg_old_tag(chain: &mut ChainStore) -> Int {
  return chain.reorg_old;
}

/// New best-tip tag of the last branch switch, or 0 when none was recorded.
/// Complexity: O(1).
pub fn chain_reorg_new_tag(chain: &mut ChainStore) -> Int {
  return chain.reorg_new;
}

/// Undo the last branch switch: restore the old tip as best and mark the
/// record undone. Returns false when no applied switch is available. The view
/// is restored until the next chain_append recomputes the fork choice.
/// Complexity: O(1).
pub fn chain_reorg_undo(chain: &mut ChainStore) -> Bool {
  if chain.reorg_state != 1 {
    return false;
  }
  chain.best = chain.reorg_old;
  chain.reorg_state = 2;
  return true;
}

/// Redo the last branch switch: restore the new tip as best and mark the
/// record applied. Returns false when the last switch is not undone.
/// Complexity: O(1).
pub fn chain_reorg_redo(chain: &mut ChainStore) -> Bool {
  if chain.reorg_state != 2 {
    return false;
  }
  chain.best = chain.reorg_new;
  chain.reorg_state = 1;
  return true;
}

// ============================================================================
// Orphan pool
// ============================================================================

/// Number of blocks parked in the orphan pool. Complexity: O(1).
pub fn chain_orphan_count(chain: &mut ChainStore) -> Int {
  return chain.otags.len();
}

/// Tag of orphan i, or -1 out of range. Complexity: O(1).
pub fn chain_orphan_tag(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.otags.len() {
    return -1;
  }
  let t: Int = chain.otags[i];
  return t;
}

/// Parent tag declared by orphan i, or -1 out of range. Complexity: O(1).
pub fn chain_orphan_parent(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.oparents.len() {
    return -1;
  }
  let t: Int = chain.oparents[i];
  return t;
}

/// Height declared by orphan i, or -1 out of range. Complexity: O(1).
pub fn chain_orphan_height(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.oheights.len() {
    return -1;
  }
  let t: Int = chain.oheights[i];
  return t;
}

/// Own work declared by orphan i, or -1 out of range. Complexity: O(1).
pub fn chain_orphan_work(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.oown.len() {
    return -1;
  }
  let t: Int = chain.oown[i];
  return t;
}

/// State root declared by orphan i, or -1 out of range (the sentinel collides
/// with a root of -1; caller roots are expected non-negative). Complexity: O(1).
pub fn chain_orphan_root(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.oroots.len() {
    return -1;
  }
  let t: Int = chain.oroots[i];
  return t;
}

/// Number of orphans promoted into the store by the most recent
/// chain_append, or 0. Complexity: O(1).
pub fn chain_last_promoted(chain: &mut ChainStore) -> Int {
  return chain.last_promoted;
}

// ============================================================================
// Inserted-block queries
// ============================================================================

/// True when `tag` is an inserted block (genesis included); parked orphans and
/// unknown tags are false. Complexity: O(n).
pub fn chain_known(chain: &mut ChainStore, tag: Int) -> Bool {
  return _block_index(chain, tag) >= 0;
}

/// Number of inserted blocks, genesis included. Complexity: O(1).
pub fn chain_block_count(chain: &mut ChainStore) -> Int {
  return chain.tags.len();
}

/// Tag of inserted block i, or -1 out of range. Complexity: O(1).
pub fn chain_tag_at(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.tags.len() {
    return -1;
  }
  let t: Int = chain.tags[i];
  return t;
}

/// Declared height of inserted block `tag`, or -1 when unknown. Complexity: O(n).
pub fn chain_block_height(chain: &mut ChainStore, tag: Int) -> Int {
  return _height_of(chain, tag);
}

/// Declared parent tag of inserted block `tag`, or -1 when unknown.
/// Complexity: O(n).
pub fn chain_block_parent(chain: &mut ChainStore, tag: Int) -> Int {
  return _parent_of(chain, tag);
}

/// Cumulative work of inserted block `tag`, or -1 when unknown. Complexity: O(n).
pub fn chain_block_work(chain: &mut ChainStore, tag: Int) -> Int {
  return _work_of(chain, tag);
}

/// Own work declared by inserted block `tag`, or -1 when unknown.
/// Complexity: O(n).
pub fn chain_block_own_work(chain: &mut ChainStore, tag: Int) -> Int {
  let i: Int = _block_index(chain, tag);
  if i < 0 {
    return -1;
  }
  return chain.own[i];
}

/// State root of inserted block `tag`, or -1 when unknown. Complexity: O(n).
pub fn chain_block_root(chain: &mut ChainStore, tag: Int) -> Int {
  let i: Int = _block_index(chain, tag);
  if i < 0 {
    return -1;
  }
  return chain.roots[i];
}

// ============================================================================
// Transaction records
// ============================================================================

/// Record transaction `tx_id` with fee `fee` against inserted block
/// `block_tag`.
///
/// Errors: "chaincore: unknown block: <tag>" when the block is not inserted
/// (parked orphans included), "chaincore: fee must be non-negative" when
/// fee < 0, and "chaincore: duplicate transaction id: <id>" when the id
/// already exists anywhere in the store (ids are globally unique).
/// Returns Ok(number of transactions recorded for that block).
/// Complexity: O(n) in the number of recorded transactions.
pub fn chain_add_tx(chain: &mut ChainStore, block_tag: Int, tx_id: Int, fee: Int) -> Result[Int, Str] {
  if _block_index(chain, block_tag) < 0 {
    return _err_int("chaincore: unknown block: " + convert.int_to_string(block_tag));
  }
  if fee < 0 {
    return _err_int("chaincore: fee must be non-negative");
  }
  if _tx_index(chain, tx_id) >= 0 {
    return _err_int("chaincore: duplicate transaction id: " + convert.int_to_string(tx_id));
  }
  chain.tx_block.push(block_tag);
  chain.txids.push(tx_id);
  chain.txfees.push(fee);
  return _ok_int(chain_block_tx_count(chain, block_tag));
}

/// Total number of recorded transactions. Complexity: O(1).
pub fn chain_tx_count(chain: &mut ChainStore) -> Int {
  return chain.txids.len();
}

/// Id of transaction record i, or -1 out of range. Complexity: O(1).
pub fn chain_tx_id_at(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.txids.len() {
    return -1;
  }
  let t: Int = chain.txids[i];
  return t;
}

/// Block tag of transaction record i, or -1 out of range. Complexity: O(1).
pub fn chain_tx_block_at(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.tx_block.len() {
    return -1;
  }
  let t: Int = chain.tx_block[i];
  return t;
}

/// Fee of transaction record i, or -1 out of range. Complexity: O(1).
pub fn chain_tx_fee_at(chain: &mut ChainStore, i: Int) -> Int {
  if i < 0 || i >= chain.txfees.len() {
    return -1;
  }
  let t: Int = chain.txfees[i];
  return t;
}

/// Number of transactions recorded for `block_tag` (0 when unknown).
/// Complexity: O(n) in the number of recorded transactions.
pub fn chain_block_tx_count(chain: &mut ChainStore, block_tag: Int) -> Int {
  var n: Int = 0;
  var i: Int = 0;
  while i < chain.tx_block.len() {
    let b: Int = chain.tx_block[i];
    if b == block_tag {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Sum of the fees recorded for `block_tag` (0 when none). Complexity: O(n).
pub fn chain_block_fees(chain: &mut ChainStore, block_tag: Int) -> Int {
  var s: Int = 0;
  var i: Int = 0;
  while i < chain.tx_block.len() {
    let b: Int = chain.tx_block[i];
    if b == block_tag {
      let f: Int = chain.txfees[i];
      s = s + f;
    }
    i = i + 1;
  }
  return s;
}

/// Sum of every recorded fee. Complexity: O(n).
pub fn chain_total_fees(chain: &mut ChainStore) -> Int {
  var s: Int = 0;
  var i: Int = 0;
  while i < chain.txfees.len() {
    let f: Int = chain.txfees[i];
    s = s + f;
    i = i + 1;
  }
  return s;
}

// ============================================================================
// Finality
// ============================================================================

/// Current finality depth. Complexity: O(1).
pub fn chain_finality_depth(chain: &mut ChainStore) -> Int {
  return chain.finality;
}

/// Set the finality depth. Negative depths are rejected (false, unchanged).
/// Complexity: O(1).
pub fn chain_set_finality_depth(chain: &mut ChainStore, depth: Int) -> Bool {
  if depth < 0 {
    return false;
  }
  chain.finality = depth;
  return true;
}

/// Highest height considered final: max(0, best height - depth). The genesis
/// block (height 0) is therefore always final. Complexity: O(n).
pub fn chain_finalized_height(chain: &mut ChainStore) -> Int {
  let bh: Int = _height_of(chain, chain.best);
  if bh <= chain.finality {
    return 0;
  }
  return bh - chain.finality;
}

/// True when `tag` is an inserted block at or below the finalized height.
/// Unknown tags and parked orphans are false. Complexity: O(n).
pub fn chain_is_final(chain: &mut ChainStore, tag: Int) -> Bool {
  let i: Int = _block_index(chain, tag);
  if i < 0 {
    return false;
  }
  let fh: Int = chain_finalized_height(chain);
  return chain.heights[i] <= fh;
}

// ============================================================================
// Structural invariants
// ============================================================================

/// Bitmask of structural-invariant violations; 0 means clean. Bits:
/// 1 genesis shape, 2 parent linkage, 4 work accumulation, 8 duplicate
/// inserted tags, 16 best-tip choice, 32 best chain reaches genesis,
/// 64 orphan-pool shape, 128 transaction records. Complexity: O(n^2) worst
/// case (duplicate scans), O(n) otherwise.
pub fn chain_violations(chain: &mut ChainStore) -> Int {
  // One boolean per invariant category, composed into the bitmask at the
  // end, so several violations of the same category still set a single bit.
  var v_genesis: Bool = false;
  var v_linkage: Bool = false;
  var v_work: Bool = false;
  var v_dup: Bool = false;
  var v_best: Bool = false;
  var v_best_chain: Bool = false;
  var v_orphans: Bool = false;
  var v_tx: Bool = false;

  // Genesis shape.
  if chain.tags.len() == 0 {
    return 1;
  }
  let g0: Int = chain.tags[0];
  if g0 != 1 {
    v_genesis = true;
  }
  let gp: Int = chain.parents[0];
  if gp != 0 {
    v_genesis = true;
  }
  let gh: Int = chain.heights[0];
  if gh != 0 {
    v_genesis = true;
  }
  let go: Int = chain.own[0];
  if go <= 0 {
    v_work = true;
  }
  let gw: Int = chain.works[0];
  if gw != go {
    v_work = true;
  }

  // Parent linkage and work accumulation for every non-genesis block.
  var i: Int = 1;
  while i < chain.tags.len() {
    let p: Int = chain.parents[i];
    let pi: Int = _block_index(chain, p);
    if pi < 0 {
      v_linkage = true;
      v_work = true;
    } else {
      let phe: Int = chain.heights[pi];
      let cur: Int = chain.heights[i];
      if cur != phe + 1 {
        v_linkage = true;
      }
      let pwo: Int = chain.works[pi];
      let owo: Int = chain.own[i];
      let cum: Int = chain.works[i];
      if owo <= 0 {
        v_work = true;
      }
      if cum != pwo + owo {
        v_work = true;
      }
    }
    i = i + 1;
  }

  // Duplicate inserted tags.
  var a: Int = 0;
  while a < chain.tags.len() {
    var b: Int = a + 1;
    while b < chain.tags.len() {
      let ta: Int = chain.tags[a];
      let tb: Int = chain.tags[b];
      if ta == tb {
        v_dup = true;
      }
      b = b + 1;
    }
    a = a + 1;
  }

  // Best-tip choice and best-chain walk.
  let bi: Int = _block_index(chain, chain.best);
  if bi < 0 {
    v_best = true;
  } else {
    var j: Int = 0;
    while j < chain.tags.len() {
      let wj: Int = chain.works[j];
      let wb: Int = chain.works[bi];
      if wj > wb {
        v_best = true;
      } else if wj == wb {
        let tj: Int = chain.tags[j];
        let tb: Int = chain.tags[bi];
        if tj < tb {
          v_best = true;
        }
      }
      j = j + 1;
    }
    var w: Int = chain.best;
    var steps: Int = 0;
    while w != 0 && steps <= chain.tags.len() {
      w = _parent_of(chain, w);
      steps = steps + 1;
    }
    if w != 0 {
      v_best_chain = true;
    }
  }

  // Orphan pool shape.
  var k: Int = 0;
  while k < chain.otags.len() {
    let ot: Int = chain.otags[k];
    if _block_index(chain, ot) >= 0 {
      v_orphans = true;
    }
    let op: Int = chain.oparents[k];
    if _block_index(chain, op) >= 0 {
      v_orphans = true;
    }
    let oh: Int = chain.oheights[k];
    let ow: Int = chain.oown[k];
    if oh <= 0 {
      v_orphans = true;
    }
    if ow <= 0 {
      v_orphans = true;
    }
    var m: Int = k + 1;
    while m < chain.otags.len() {
      let om: Int = chain.otags[m];
      if om == ot {
        v_orphans = true;
      }
      m = m + 1;
    }
    k = k + 1;
  }

  // Transaction records.
  var x: Int = 0;
  while x < chain.txids.len() {
    let bt: Int = chain.tx_block[x];
    if _block_index(chain, bt) < 0 {
      v_tx = true;
    }
    let ft: Int = chain.txfees[x];
    if ft < 0 {
      v_tx = true;
    }
    var y: Int = x + 1;
    while y < chain.txids.len() {
      let ida: Int = chain.txids[x];
      let idb: Int = chain.txids[y];
      if ida == idb {
        v_tx = true;
      }
      y = y + 1;
    }
    x = x + 1;
  }

  var mask: Int = 0;
  if v_genesis {
    mask = mask + chain_violation_genesis();
  }
  if v_linkage {
    mask = mask + chain_violation_linkage();
  }
  if v_work {
    mask = mask + chain_violation_work();
  }
  if v_dup {
    mask = mask + chain_violation_duplicate();
  }
  if v_best {
    mask = mask + chain_violation_best();
  }
  if v_best_chain {
    mask = mask + chain_violation_best_chain();
  }
  if v_orphans {
    mask = mask + chain_violation_orphans();
  }
  if v_tx {
    mask = mask + chain_violation_transactions();
  }
  return mask;
}

/// True when chain_violations reports no violation. Complexity: O(n^2) worst
/// case, O(n) otherwise.
pub fn chain_invariants(chain: &mut ChainStore) -> Bool {
  return chain_violations(chain) == 0;
}
