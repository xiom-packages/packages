// XIOM -- xiom.context: immutable context propagation as a deterministic chain
// Port task: replace the xiom.context placeholder with a real, tested,
// pure-XIOM package (no FFI, no threads, no wall clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: context propagation as a pure, deterministic state machine -- the
// semantic core an async runtime, request pipeline or task executor would
// drive. The library owns the *semantics* of context values; it contains no
// threads, no atomics, no locks, no wall clock and no I/O. Time is a logical
// integer clock advanced explicitly by the caller.
//
// A Context holds a forest of nodes stored as parallel vectors:
//   * ids[i]            caller-assigned node id (unique, >= 0)
//   * parents[i]        parent node id, or -1 for a root; a parent always
//                       precedes its child (forest, no cycles)
//   * text              one immutable byte buffer with every key and value
//   * key_off[i]        key start offset in `text`; key_len[i] its length
//   * val_off[i]        value start offset; val_len[i] its length
//   * deadlines[i]      absolute logical tick, or -1 when none; the EFFECTIVE
//                       (earliest) deadline of the node's own chain
//   * cancelled[i]      CTX_STATE_ACTIVE or CTX_STATE_CANCELLED
//   * cancel_reasons[i] CTX_REASON_* code: why this node is cancelled
//   * cancel_sources[i] the node that initiated the cancellation (self for a
//                       direct or deadline cancel, the origin ancestor for a
//                       propagated PARENT cancel)
//   * cancel_ticks[i]   logical clock value at the cancellation, or -1
//   * now               monotonic logical clock, starts at 0
//
// Semantics (all deterministic, all total):
//   * a context value is an immutable node identified by its id; the parent
//     chain is fixed at creation, so a node's view of the world never
//     changes under it;
//   * lookup walks from the queried node up to the root and returns the
//     value of the FIRST (nearest/deepest) binding for the key: nearer
//     bindings shadow farther ones; a node with an empty key is not a
//     binding;
//   * a node's effective deadline is the earliest (minimum) deadline along
//     its own chain: a child inherits the parent's effective deadline when
//     it declares none, and can only move it earlier, never later (monotone
//     deadlines);
//   * deadlines are absolute logical ticks: a node is due when
//     now >= deadline. ctx_check_deadline checks one node and ctx_tick
//     advances the clock then expires every due node in creation order; an
//     expired node is cancelled with reason CTX_REASON_DEADLINE and source =
//     itself, and its ACTIVE descendants are cancelled by propagation with
//     reason CTX_REASON_PARENT and source = the initiating node;
//   * cancellation is a one-way ACTIVE -> CANCELLED transition: a repeat
//     cancel is refused by ctx_cancel ("already cancelled") and is a no-op
//     returning Ok(0) by ctx_cancel_idempotent; a child created under an
//     already-cancelled parent is born CANCELLED with reason PARENT and the
//     parent's origin source, so the propagation closure always holds;
//   * ctx_flatten materialises the effective key-value listing visible from
//     a node: keys in root-to-leaf first-appearance order with the nearest
//     binding's value (a shadowed value is replaced, never duplicated);
//   * ctx_path renders the node's id chain as "root/child/.../node";
//   * ctx_check_invariant validates the structural invariants: equal vector
//     lengths, valid stored ranges, unique ids, an acyclic parent chain,
//     monotone deadlines, well-formed cancellation records, the propagation
//     closure and cancel ticks within the clock.
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _ok_int/_err_int leaf helpers; every element read is bound
// with a typed `let`; all parallel vectors are pushed together so they can
// never skew; no Vec[StructType], no indexed Vec[fn] dispatch, no generic
// callbacks, no `mut` in match patterns, no FFI, no threads. Str values are
// compared only with string.str_compare. Dynamic Vec[Str] growth is avoided
// entirely: keys and values live in one Str buffer addressed by parallel
// Vec[Int] offset/length pairs, and lst_key/lst_val copy a slice out with
// string.str_slice.

module xiom.context

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Public constants
// ---------------------------------------------------------------------------

/// Node state: live; its deadline and cancellation checks apply.
pub const CTX_STATE_ACTIVE: Int = 0;

/// Node state: cancelled (terminal; never leaves this state).
pub const CTX_STATE_CANCELLED: Int = 1;

/// Reason code of an active node (reserved: ctx_cancel rejects it).
pub const CTX_REASON_NONE: Int = 0;

/// Well-known reason: an explicit caller request.
pub const CTX_REASON_USER: Int = 1;

/// Well-known reason: a logical-tick deadline expired. Reserved: only the
/// deadline check functions may set it.
pub const CTX_REASON_DEADLINE: Int = 2;

/// Well-known reason: an ancestor was cancelled. Reserved: only propagation
/// sets it.
pub const CTX_REASON_PARENT: Int = 3;

/// Well-known reason: the owning resource is shutting down.
pub const CTX_REASON_SHUTDOWN: Int = 4;

/// Sentinel: node has no parent (a root).
pub const CTX_NO_PARENT: Int = -1;

/// Sentinel: node has no deadline.
pub const CTX_NO_DEADLINE: Int = -1;

/// Sentinel: unknown node id / out-of-range accessor result.
pub const CTX_NOT_FOUND: Int = -1;

/// Context registry. Every field is an internal implementation detail;
/// callers must go through the ctx_*/lst_* free functions. The eleven node
/// vectors are parallel and always share one length: ids[i], parents[i],
/// key_off[i], key_len[i], val_off[i], val_len[i], deadlines[i], cancelled[i],
/// cancel_reasons[i], cancel_sources[i], cancel_ticks[i]. `text` is the shared
/// immutable key/value byte buffer; `now` is the logical clock (monotonic,
/// starts at 0).
pub type Context = {
  ids: Vec[Int];
  parents: Vec[Int];
  text: Str;
  key_off: Vec[Int];
  key_len: Vec[Int];
  val_off: Vec[Int];
  val_len: Vec[Int];
  deadlines: Vec[Int];
  cancelled: Vec[Int];
  cancel_reasons: Vec[Int];
  cancel_sources: Vec[Int];
  cancel_ticks: Vec[Int];
  now: Int;
}

/// Materialised key-value listing returned by ctx_flatten: the distinct keys
/// visible from a node, in root-to-leaf first-appearance order, each paired
/// with the value of its nearest (deepest) binding. `text` is the listing's
/// own byte buffer; the four vectors address slices of it exactly like the
/// Context fields do. `count` is the number of pairs.
pub type Listing = {
  text: Str;
  key_off: Vec[Int];
  key_len: Vec[Int];
  val_off: Vec[Int];
  val_len: Vec[Int];
  count: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers: node table and pair storage
// ---------------------------------------------------------------------------

// Slot of node `id` in the node vectors, or -1 when unknown.
fn _index(c: &Context, id: Int) -> Int {
  var i = 0;
  while i < c.ids.len() {
    let cur: Int = c.ids[i];
    if cur == id { return i; }
    i = i + 1;
  }
  return -1;
}

// Append one key/value pair to the tail of a context's shared text buffer,
// pushing all four addressing vectors in step. The key bytes land first, the
// value bytes immediately after it, so val_off is always key_off + key_len.
fn _push_pair(c: &mut Context, key: Str, value: Str) {
  c.key_off.push(c.text.len());
  c.key_len.push(key.len());
  let t1 = c.text + key;
  c.text = t1;
  c.val_off.push(c.text.len());
  c.val_len.push(value.len());
  let t2 = c.text + value;
  c.text = t2;
}

// The stored key of node slot `slot` ([] when the node has no key).
fn _ctx_key(c: &Context, slot: Int) -> Str {
  let off: Int = c.key_off[slot];
  let len: Int = c.key_len[slot];
  return str_slice(c.text, off, off + len);
}

// The stored value of node slot `slot`.
fn _ctx_value(c: &Context, slot: Int) -> Str {
  let off: Int = c.val_off[slot];
  let len: Int = c.val_len[slot];
  return str_slice(c.text, off, off + len);
}

// Number of parent hops from node slot `slot` to its root (root = 0).
fn _slot_depth(c: &Context, slot: Int) -> Int {
  var depth = 0;
  var cur = slot;
  var alive = true;
  while alive {
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      depth = depth + 1;
      cur = _index(c, p);
    }
  }
  return depth;
}

// Slot of the nearest binding for `key` on the chain from `slot` up to the
// root, or -1 when no node on the chain stores a non-empty key equal to
// `key`. Shadowing: walk starts at the queried node, so nearer wins.
fn _find_binding_slot(c: &Context, slot: Int, key: Str) -> Int {
  var cur = slot;
  var alive = true;
  while alive {
    let klen: Int = c.key_len[cur];
    if klen > 0 {
      let stored = _ctx_key(c, cur);
      if string.str_compare(stored, key) == 0 { return cur; }
    }
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      cur = _index(c, p);
    }
  }
  return -1;
}

// True when node slot `slot` is a proper descendant of node slot `anc_slot`.
fn _is_descendant(c: &Context, slot: Int, anc_slot: Int) -> Bool {
  let anc_id: Int = c.ids[anc_slot];
  var cur = slot;
  var alive = true;
  while alive {
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      if p == anc_id { return true; }
      cur = _index(c, p);
    }
  }
  return false;
}

// Cancel the ACTIVE node at `slot` with `reason` and origin `source_id`, then
// cancel every ACTIVE descendant with reason CTX_REASON_PARENT and the same
// origin. Returns the number of newly cancelled nodes (the target plus its
// descendants). The caller validates the reason and the ACTIVE state.
fn _apply_cancel(c: &mut Context, slot: Int, reason: Int, source_id: Int) -> Int {
  c.cancelled[slot] = CTX_STATE_CANCELLED;
  c.cancel_reasons[slot] = reason;
  c.cancel_sources[slot] = source_id;
  c.cancel_ticks[slot] = c.now;
  var n = 1;
  var j = 0;
  while j < c.ids.len() {
    let st: Int = c.cancelled[j];
    if st == CTX_STATE_ACTIVE {
      if _is_descendant(c, j, slot) {
        c.cancelled[j] = CTX_STATE_CANCELLED;
        c.cancel_reasons[j] = CTX_REASON_PARENT;
        c.cancel_sources[j] = source_id;
        c.cancel_ticks[j] = c.now;
        n = n + 1;
      }
    }
    j = j + 1;
  }
  return n;
}

// Scan every node in creation order and cancel the due ACTIVE ones with
// reason CTX_REASON_DEADLINE (propagation included). A node already cancelled
// -- including one cancelled earlier in this same scan by a due ancestor --
// is skipped, so no node is cancelled twice. Returns the number newly
// cancelled by this scan.
fn _expire_due(c: &mut Context) -> Int {
  var total = 0;
  var i = 0;
  while i < c.ids.len() {
    let st: Int = c.cancelled[i];
    if st == CTX_STATE_ACTIVE {
      let d: Int = c.deadlines[i];
      if d >= 0 && c.now >= d {
        let tid: Int = c.ids[i];
        let n = _apply_cancel(c, i, CTX_REASON_DEADLINE, tid);
        total = total + n;
      }
    }
    i = i + 1;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Internal helpers: listing storage
// ---------------------------------------------------------------------------

// Append a new key/value pair to a listing's tail.
fn _lst_append(l: &mut Listing, key: Str, value: Str) {
  l.key_off.push(l.text.len());
  l.key_len.push(key.len());
  let t1 = l.text + key;
  l.text = t1;
  l.val_off.push(l.text.len());
  l.val_len.push(value.len());
  let t2 = l.text + value;
  l.text = t2;
  l.count = l.count + 1;
}

// Replace the value of the pair at index `i` (the key stays in place; the new
// value bytes are appended at the tail of the listing buffer).
fn _lst_overwrite(l: &mut Listing, i: Int, value: Str) {
  let at = l.text.len();
  let t1 = l.text + value;
  l.text = t1;
  l.val_off[i] = at;
  l.val_len[i] = value.len();
}

// Index of `key` in the listing, or -1 when absent (byte-wise str_compare).
fn _lst_find(l: &Listing, key: Str) -> Int {
  var i = 0;
  while i < l.count {
    let off: Int = l.key_off[i];
    let len: Int = l.key_len[i];
    let stored = str_slice(l.text, off, off + len);
    if string.str_compare(stored, key) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// Insert a new pair, or replace the value of an existing key in place.
fn _lst_set(l: &mut Listing, key: Str, value: Str) {
  let idx = _lst_find(l, key);
  if idx < 0 {
    _lst_append(l, key, value);
  } else {
    _lst_overwrite(l, idx, value);
  }
}

// The key at listing index `i` ([] when out of range).
fn _lst_key(l: &Listing, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= l.count { return ""; }
  let off: Int = l.key_off[i];
  let len: Int = l.key_len[i];
  return str_slice(l.text, off, off + len);
}

// The value at listing index `i` ([] when out of range).
fn _lst_val(l: &Listing, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= l.count { return ""; }
  let off: Int = l.val_off[i];
  let len: Int = l.val_len[i];
  return str_slice(l.text, off, off + len);
}

// ---------------------------------------------------------------------------
// Construction and the context tree
// ---------------------------------------------------------------------------

/// Create an empty context registry: no nodes, clock at 0.
/// Complexity: O(1).
pub fn ctx_new() -> Context {
  return Context{
    ids: Vec[Int].new();
    parents: Vec[Int].new();
    text: "";
    key_off: Vec[Int].new();
    key_len: Vec[Int].new();
    val_off: Vec[Int].new();
    val_len: Vec[Int].new();
    deadlines: Vec[Int].new();
    cancelled: Vec[Int].new();
    cancel_reasons: Vec[Int].new();
    cancel_sources: Vec[Int].new();
    cancel_ticks: Vec[Int].new();
    now: 0;
  };
}

/// Add a root node (no parent, no key, no value, no deadline) in the ACTIVE
/// state.
/// Params: c - the registry; id - caller-assigned node id, unique, >= 0.
/// Returns: Ok(id); Err("context: id must be >= 0") or
/// Err("context: duplicate id") -- in every Err case the state is unchanged.
/// Complexity: O(node count).
pub fn ctx_add_root(c: &mut Context, id: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("context: id must be >= 0");
  }
  if _index(c, id) >= 0 {
    return _err_int("context: duplicate id");
  }
  c.ids.push(id);
  c.parents.push(CTX_NO_PARENT);
  _push_pair(c, "", "");
  c.deadlines.push(CTX_NO_DEADLINE);
  c.cancelled.push(CTX_STATE_ACTIVE);
  c.cancel_reasons.push(CTX_REASON_NONE);
  c.cancel_sources.push(CTX_NOT_FOUND);
  c.cancel_ticks.push(CTX_NOT_FOUND);
  return _ok_int(id);
}

/// Add a child node under an existing parent, carrying one key/value binding
/// and an optional explicit deadline. The child's effective deadline is the
/// earliest of the parent's effective deadline and its own: it inherits the
/// parent's when it declares none, and can only move the deadline earlier,
/// never later. When the parent is already CANCELLED the child is born
/// CANCELLED with reason PARENT and the parent's origin source.
/// Params: c - the registry; parent - id of an existing node; id - the new
///         node id, unique, >= 0; key - the binding key (empty key = no
///         binding); value - the binding value; deadline - absolute logical
///         tick >= 0, or CTX_NO_DEADLINE (-1) for none.
/// Returns: Ok(id); Err("context: id must be >= 0"),
/// Err("context: duplicate id"), Err("context: unknown parent id") or
/// Err("context: deadline must be >= -1") -- in every Err case the state is
/// unchanged.
/// Complexity: O(node count).
pub fn ctx_add_child(c: &mut Context, parent: Int, id: Int, key: Str,
                     value: Str, deadline: Int) -> Result[Int, Str] {
  if id < 0 {
    return _err_int("context: id must be >= 0");
  }
  if _index(c, id) >= 0 {
    return _err_int("context: duplicate id");
  }
  let pslot = _index(c, parent);
  if pslot < 0 {
    return _err_int("context: unknown parent id");
  }
  if deadline < CTX_NO_DEADLINE {
    return _err_int("context: deadline must be >= -1");
  }
  let pdl: Int = c.deadlines[pslot];
  var eff = deadline;
  if pdl != CTX_NO_DEADLINE {
    if eff == CTX_NO_DEADLINE {
      eff = pdl;
    } else {
      if pdl < eff { eff = pdl; }
    }
  }
  let pst: Int = c.cancelled[pslot];
  let psrc: Int = c.cancel_sources[pslot];
  c.ids.push(id);
  c.parents.push(parent);
  _push_pair(c, key, value);
  c.deadlines.push(eff);
  if pst == CTX_STATE_CANCELLED {
    c.cancelled.push(CTX_STATE_CANCELLED);
    c.cancel_reasons.push(CTX_REASON_PARENT);
    c.cancel_sources.push(psrc);
    c.cancel_ticks.push(c.now);
  } else {
    c.cancelled.push(CTX_STATE_ACTIVE);
    c.cancel_reasons.push(CTX_REASON_NONE);
    c.cancel_sources.push(CTX_NOT_FOUND);
    c.cancel_ticks.push(CTX_NOT_FOUND);
  }
  return _ok_int(id);
}

/// True when a node with `id` exists. Complexity: O(node count).
pub fn ctx_has(c: &Context, id: Int) -> Bool {
  return _index(c, id) >= 0;
}

/// Number of nodes in the registry (nodes are never removed).
/// Complexity: O(1).
pub fn ctx_count(c: &Context) -> Int {
  return c.ids.len();
}

/// Parent id of node `id`, or CTX_NO_PARENT (-1) for a root or an unknown id
/// (use ctx_has to distinguish). Complexity: O(node count).
pub fn ctx_parent(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NO_PARENT; }
  let p: Int = c.parents[slot];
  return p;
}

/// Depth of node `id`: 0 for a root, 1 for its children, and so on; -1 for an
/// unknown id. Complexity: O(depth).
pub fn ctx_depth(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  return _slot_depth(c, slot);
}

/// Root (topmost ancestor) of node `id`, or CTX_NOT_FOUND (-1) when unknown.
/// Complexity: O(depth).
pub fn ctx_root_of(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  var cur = slot;
  var alive = true;
  while alive {
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      cur = _index(c, p);
    }
  }
  let rid: Int = c.ids[cur];
  return rid;
}

/// True when node `ancestor` is a proper ancestor of node `id` (strict: false
/// when they are equal or either id is unknown). Complexity: O(depth).
pub fn ctx_is_ancestor(c: &Context, ancestor: Int, id: Int) -> Bool {
  let a = _index(c, ancestor);
  if a < 0 { return false; }
  let d = _index(c, id);
  if d < 0 { return false; }
  return _is_descendant(c, d, a);
}

/// Render the id chain of node `id` as "root/child/.../node" (the node
/// included); "" for an unknown id. Complexity: O(depth^2) bytes.
pub fn ctx_path(c: &Context, id: Int) -> Str {
  let slot = _index(c, id);
  if slot < 0 { return ""; }
  var chain = Vec[Int].new();
  var cur = slot;
  var alive = true;
  while alive {
    chain.push(cur);
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      cur = _index(c, p);
    }
  }
  let top_slot: Int = chain[chain.len() - 1];
  let top_id: Int = c.ids[top_slot];
  var out = convert.int_to_string(top_id);
  var i = chain.len() - 2;
  while i >= 0 {
    let sidx: Int = chain[i];
    let sid: Int = c.ids[sidx];
    out = out + "/" + convert.int_to_string(sid);
    i = i - 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Lookup and shadowing
// ---------------------------------------------------------------------------

/// Nearest value bound to `key` on the chain from node `id` up to its root:
/// the first (deepest) binding wins, so nearer bindings shadow farther ones.
/// Nodes with an empty key never match. Returns "" when the key is unbound
/// or the id is unknown.
/// Complexity: O(depth * key length).
pub fn ctx_lookup(c: &Context, id: Int, key: Str) -> Str {
  let slot = _index(c, id);
  if slot < 0 { return ""; }
  let found = _find_binding_slot(c, slot, key);
  if found < 0 { return ""; }
  return _ctx_value(c, found);
}

/// True when `key` resolves to a binding on the chain from node `id`.
/// Complexity: O(depth * key length).
pub fn ctx_has_key(c: &Context, id: Int, key: Str) -> Bool {
  let slot = _index(c, id);
  if slot < 0 { return false; }
  return _find_binding_slot(c, slot, key) >= 0;
}

/// Id of the node that owns the nearest binding for `key` (the shadowing
/// winner), or CTX_NOT_FOUND (-1) when unbound or unknown.
/// Complexity: O(depth * key length).
pub fn ctx_lookup_owner(c: &Context, id: Int, key: Str) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  let found = _find_binding_slot(c, slot, key);
  if found < 0 { return CTX_NOT_FOUND; }
  let oid: Int = c.ids[found];
  return oid;
}

/// Depth of the node that owns the nearest binding for `key`, or
/// CTX_NOT_FOUND (-1) when unbound or unknown.
/// Complexity: O(depth * key length).
pub fn ctx_lookup_depth(c: &Context, id: Int, key: Str) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  let found = _find_binding_slot(c, slot, key);
  if found < 0 { return CTX_NOT_FOUND; }
  return _slot_depth(c, found);
}

// ---------------------------------------------------------------------------
// Logical clock and deadlines
// ---------------------------------------------------------------------------

/// Current logical clock value (starts at 0, only moves forward).
/// Complexity: O(1).
pub fn ctx_now(c: &Context) -> Int {
  return c.now;
}

/// Effective (earliest) deadline of node `id` as an absolute logical tick,
/// or CTX_NO_DEADLINE (-1) when the chain declares none or the id is unknown.
/// Complexity: O(node count).
pub fn ctx_deadline(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NO_DEADLINE; }
  let d: Int = c.deadlines[slot];
  return d;
}

/// True when node `id` exists and its effective deadline is set.
/// Complexity: O(node count).
pub fn ctx_has_deadline(c: &Context, id: Int) -> Bool {
  return ctx_deadline(c, id) >= 0;
}

/// Advance the logical clock without checking deadlines.
/// Params: c - the registry; to - the new clock value, >= the current one.
/// Returns: Ok(to); Err("context: clock cannot go backwards") when
/// `to < c.now` (state unchanged). Deadlines are only evaluated by
/// ctx_check_deadline and ctx_tick.
/// Complexity: O(1).
pub fn ctx_advance(c: &mut Context, to: Int) -> Result[Int, Str] {
  if to < c.now {
    return _err_int("context: clock cannot go backwards");
  }
  c.now = to;
  return _ok_int(to);
}

/// Check one node against the current logical clock: when it is ACTIVE, has
/// an effective deadline and `now >= deadline`, cancel it (and its ACTIVE
/// descendants) with reason CTX_REASON_DEADLINE and source = its own id.
/// Params: c - the registry; id - the node to check.
/// Returns: Ok(count) with the number of nodes newly cancelled by this call
/// (0 when the node has no deadline, is not due, or is already CANCELLED);
/// Err("context: unknown id") when unknown (state unchanged).
/// Complexity: O(node count^2).
pub fn ctx_check_deadline(c: &mut Context, id: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("context: unknown id");
  }
  let st: Int = c.cancelled[slot];
  if st != CTX_STATE_ACTIVE {
    return _ok_int(0);
  }
  let d: Int = c.deadlines[slot];
  if d < 0 {
    return _ok_int(0);
  }
  if c.now < d {
    return _ok_int(0);
  }
  let n = _apply_cancel(c, slot, CTX_REASON_DEADLINE, id);
  return _ok_int(n);
}

/// Advance the logical clock to `to` and expire every due node: ctx_advance
/// followed by a creation-order scan that cancels each ACTIVE node with
/// `now >= deadline` (reason CTX_REASON_DEADLINE, source = itself,
/// propagation included). A node already cancelled -- including one just
/// cancelled by a due ancestor in the same scan -- is skipped.
/// Params: c - the registry; to - the new clock value, >= the current one.
/// Returns: Ok(count) with the number of nodes newly cancelled by the scan;
/// Err("context: clock cannot go backwards") when `to < c.now` (state
/// unchanged; nothing expires).
/// Complexity: O(node count^2).
pub fn ctx_tick(c: &mut Context, to: Int) -> Result[Int, Str] {
  if to < c.now {
    return _err_int("context: clock cannot go backwards");
  }
  c.now = to;
  return _ok_int(_expire_due(c));
}

// ---------------------------------------------------------------------------
// Cancellation
// ---------------------------------------------------------------------------

/// Cancel one ACTIVE node and, transitively, every ACTIVE descendant.
/// Validation order: unknown id -> Err("context: unknown id"); `reason < 1`
/// -> Err("context: reason must be >= 1"); `reason` equal to
/// CTX_REASON_DEADLINE or CTX_REASON_PARENT -> Err("context: reason code is
/// reserved"); node already CANCELLED -> Err("context: already cancelled").
/// On success the target is CANCELLED with `reason`, `source` = its own id
/// and `cancel_tick` = the current logical clock; every ACTIVE descendant is
/// CANCELLED with reason PARENT and `source` = the target id. Descendants
/// already cancelled (for example by their own deadline) keep their original
/// reason/source/tick.
/// Returns: Ok(count) with the number of newly cancelled nodes (target plus
/// descendants); the Err cases above leave the state unchanged.
/// Complexity: O(node count^2).
pub fn ctx_cancel(c: &mut Context, id: Int, reason: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("context: unknown id");
  }
  if reason < 1 {
    return _err_int("context: reason must be >= 1");
  }
  if reason == CTX_REASON_DEADLINE || reason == CTX_REASON_PARENT {
    return _err_int("context: reason code is reserved");
  }
  let st: Int = c.cancelled[slot];
  if st == CTX_STATE_CANCELLED {
    return _err_int("context: already cancelled");
  }
  let n = _apply_cancel(c, slot, reason, id);
  return _ok_int(n);
}

/// Idempotent cancel: the strict ctx_cancel contract, except that a node
/// already CANCELLED is a no-op.
/// Validation order: unknown id -> Err("context: unknown id"); `reason < 1`
/// -> Err("context: reason must be >= 1"); reserved reason (DEADLINE/PARENT)
/// -> Err("context: reason code is reserved"); already CANCELLED -> Ok(0)
/// with the state (and the original reason/source/tick) unchanged.
/// Returns: Ok(count) with the number of newly cancelled nodes: 0 for a
/// repeat call, otherwise as ctx_cancel.
/// Complexity: O(node count^2).
pub fn ctx_cancel_idempotent(c: &mut Context, id: Int, reason: Int) -> Result[Int, Str] {
  let slot = _index(c, id);
  if slot < 0 {
    return _err_int("context: unknown id");
  }
  if reason < 1 {
    return _err_int("context: reason must be >= 1");
  }
  if reason == CTX_REASON_DEADLINE || reason == CTX_REASON_PARENT {
    return _err_int("context: reason code is reserved");
  }
  let st: Int = c.cancelled[slot];
  if st == CTX_STATE_CANCELLED {
    return _ok_int(0);
  }
  let n = _apply_cancel(c, slot, reason, id);
  return _ok_int(n);
}

// ---------------------------------------------------------------------------
// State accessors (read-only)
// ---------------------------------------------------------------------------

/// State code of node `id` (a CTX_STATE_* value), or CTX_NOT_FOUND (-1) when
/// unknown. Complexity: O(node count).
pub fn ctx_state(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  let st: Int = c.cancelled[slot];
  return st;
}

/// True when node `id` exists and is CANCELLED. Complexity: O(node count).
pub fn ctx_is_cancelled(c: &Context, id: Int) -> Bool {
  return ctx_state(c, id) == CTX_STATE_CANCELLED;
}

/// True when node `id` exists and is ACTIVE. Complexity: O(node count).
pub fn ctx_is_active(c: &Context, id: Int) -> Bool {
  return ctx_state(c, id) == CTX_STATE_ACTIVE;
}

/// Reason code of node `id`: CTX_REASON_NONE (0) while ACTIVE, a
/// CTX_REASON_* (or custom) code while CANCELLED, CTX_NOT_FOUND (-1) when
/// unknown. Complexity: O(node count).
pub fn ctx_cancel_reason(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  let r: Int = c.cancel_reasons[slot];
  return r;
}

/// Origin node of the cancellation of `id`: the node itself for a direct or
/// deadline cancel, the originating ancestor for a propagated (PARENT)
/// cancel; CTX_NOT_FOUND (-1) while ACTIVE or when unknown.
/// Complexity: O(node count).
pub fn ctx_cancel_source(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  let s: Int = c.cancel_sources[slot];
  return s;
}

/// Logical clock value at the cancellation of node `id`, or CTX_NOT_FOUND
/// (-1) while ACTIVE or when unknown. Complexity: O(node count).
pub fn ctx_cancel_tick(c: &Context, id: Int) -> Int {
  let slot = _index(c, id);
  if slot < 0 { return CTX_NOT_FOUND; }
  let t: Int = c.cancel_ticks[slot];
  return t;
}

/// Number of nodes in the CANCELLED state. Complexity: O(node count).
pub fn ctx_cancelled_count(c: &Context) -> Int {
  var n = 0;
  var i = 0;
  while i < c.cancelled.len() {
    let st: Int = c.cancelled[i];
    if st == CTX_STATE_CANCELLED { n = n + 1; }
    i = i + 1;
  }
  return n;
}

/// Number of nodes in the ACTIVE state. Complexity: O(node count).
pub fn ctx_active_count(c: &Context) -> Int {
  var n = 0;
  var i = 0;
  while i < c.cancelled.len() {
    let st: Int = c.cancelled[i];
    if st == CTX_STATE_ACTIVE { n = n + 1; }
    i = i + 1;
  }
  return n;
}

// ---------------------------------------------------------------------------
// Flattening and listings
// ---------------------------------------------------------------------------

/// Create an empty listing. Complexity: O(1).
pub fn lst_new() -> Listing {
  return Listing{
    text: "";
    key_off: Vec[Int].new();
    key_len: Vec[Int].new();
    val_off: Vec[Int].new();
    val_len: Vec[Int].new();
    count: 0;
  };
}

/// Number of pairs in the listing. Complexity: O(1).
pub fn lst_count(l: &Listing) -> Int {
  return l.count;
}

/// Materialise the effective key-value listing visible from node `id`: walk
/// the chain root-to-node, keep every distinct key in first-appearance order
/// and overwrite its value with the nearest (deepest) binding, so shadowed
/// values are replaced, never duplicated. An unknown id yields an empty
/// listing.
/// Complexity: O(depth^2 * key length).
pub fn ctx_flatten(c: &Context, id: Int) -> Listing {
  var l = lst_new();
  let slot = _index(c, id);
  if slot < 0 { return l; }
  var chain = Vec[Int].new();
  var cur = slot;
  var alive = true;
  while alive {
    chain.push(cur);
    let p: Int = c.parents[cur];
    if p < 0 {
      alive = false;
    } else {
      cur = _index(c, p);
    }
  }
  var k = chain.len() - 1;
  while k >= 0 {
    let s: Int = chain[k];
    let klen: Int = c.key_len[s];
    if klen > 0 {
      let key = _ctx_key(c, s);
      let value = _ctx_value(c, s);
      _lst_set(&mut l, key, value);
    }
    k = k - 1;
  }
  return l;
}

/// Key at listing index `i`, or "" when out of range. Complexity: O(key length).
pub fn lst_key(l: &Listing, i: Int) -> Str {
  return _lst_key(l, i);
}

/// Value at listing index `i`, or "" when out of range.
/// Complexity: O(value length).
pub fn lst_val(l: &Listing, i: Int) -> Str {
  return _lst_val(l, i);
}

/// Index of `key` in the listing, or CTX_NOT_FOUND (-1) when absent.
/// Complexity: O(count * key length).
pub fn lst_find(l: &Listing, key: Str) -> Int {
  return _lst_find(l, key);
}

/// True when the listing contains `key`. Complexity: O(count * key length).
pub fn lst_has(l: &Listing, key: Str) -> Bool {
  return _lst_find(l, key) >= 0;
}

/// Value bound to `key` in the listing, or "" when absent.
/// Complexity: O(count * key length).
pub fn lst_value_of(l: &Listing, key: Str) -> Str {
  let idx = _lst_find(l, key);
  if idx < 0 { return ""; }
  return _lst_val(l, idx);
}

/// Deterministic serialization: one "key=value" line per pair, joined by
/// newlines ("\n"); an empty listing renders as "". Keys and values are
/// emitted verbatim (no escaping).
/// Complexity: O(total bytes).
pub fn lst_to_str(l: &Listing) -> Str {
  var out = "";
  var i = 0;
  while i < l.count {
    if i > 0 { out = out + "\n"; }
    let k = _lst_key(l, i);
    let v = _lst_val(l, i);
    out = out + k + "=" + v;
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Names and invariants
// ---------------------------------------------------------------------------

/// Human-readable state name: "active", "cancelled" or "unknown".
/// Complexity: O(1).
pub fn ctx_state_name(state: Int) -> Str {
  if state == CTX_STATE_ACTIVE { return "active"; }
  if state == CTX_STATE_CANCELLED { return "cancelled"; }
  return "unknown";
}

/// Human-readable reason name: "none", "user", "deadline", "parent",
/// "shutdown", "custom" for any code >= 5, or "unknown" for a negative code.
/// Complexity: O(1).
pub fn ctx_reason_name(code: Int) -> Str {
  if code == CTX_REASON_NONE { return "none"; }
  if code == CTX_REASON_USER { return "user"; }
  if code == CTX_REASON_DEADLINE { return "deadline"; }
  if code == CTX_REASON_PARENT { return "parent"; }
  if code == CTX_REASON_SHUTDOWN { return "shutdown"; }
  if code < 1 { return "unknown"; }
  return "custom";
}

/// Acyclic-chain predicate: true exactly when every parent link is -1 or
/// names an existing node at a strictly smaller slot. Because a node is
/// always appended after its parent, a smaller-slot parent cannot be part of
/// a cycle, so the whole parent graph is a forest.
/// Complexity: O(node count^2).
pub fn ctx_chain_acyclic(c: &Context) -> Bool {
  var i = 0;
  while i < c.ids.len() {
    let p: Int = c.parents[i];
    if p >= 0 {
      let pslot = _index(c, p);
      if pslot < 0 { return false; }
      if pslot >= i { return false; }
    }
    i = i + 1;
  }
  return true;
}

/// Monotone-deadline predicate: for every child, when the parent's effective
/// deadline is set the child's is set too and is no later (child <= parent).
/// A chain can therefore only move a deadline earlier, never later.
/// Complexity: O(node count^2).
pub fn ctx_deadlines_monotone(c: &Context) -> Bool {
  var i = 0;
  while i < c.ids.len() {
    let p: Int = c.parents[i];
    if p >= 0 {
      let pslot = _index(c, p);
      if pslot >= 0 {
        let pdl: Int = c.deadlines[pslot];
        let cdl: Int = c.deadlines[i];
        if pdl != CTX_NO_DEADLINE {
          if cdl == CTX_NO_DEADLINE { return false; }
          if cdl > pdl { return false; }
        }
      }
    }
    i = i + 1;
  }
  return true;
}

/// Structural invariant of a context registry, true exactly when:
/// 1. the eleven node vectors have equal length, `now` is >= 0 and the parent
///    chain is acyclic (ctx_chain_acyclic);
/// 2. every node id is >= 0 and unique; every deadline is >= -1 and the
///    deadlines are monotone (ctx_deadlines_monotone);
/// 3. every stored range is well-formed: 0 <= key_off, 0 <= key_len,
///    key_off + key_len <= text.len(), val_off == key_off + key_len,
///    0 <= val_len and val_off + val_len <= text.len();
/// 4. every state is a CTX_STATE_* code; an ACTIVE node has reason NONE (0),
///    source -1 and cancel_tick -1; a CANCELLED node has reason >= 1, source
///    >= 0 naming an existing node, and 0 <= cancel_tick <= now; when the
///    reason is PARENT the source is a proper ancestor whose own reason is
///    not PARENT, otherwise the source is the node itself;
/// 5. propagation closure: a node whose parent is CANCELLED is itself
///    CANCELLED.
/// Complexity: O(node count^2).
pub fn ctx_check_invariant(c: &Context) -> Bool {
  let n = c.ids.len();
  if c.parents.len() != n { return false; }
  if c.key_off.len() != n { return false; }
  if c.key_len.len() != n { return false; }
  if c.val_off.len() != n { return false; }
  if c.val_len.len() != n { return false; }
  if c.deadlines.len() != n { return false; }
  if c.cancelled.len() != n { return false; }
  if c.cancel_reasons.len() != n { return false; }
  if c.cancel_sources.len() != n { return false; }
  if c.cancel_ticks.len() != n { return false; }
  if c.now < 0 { return false; }
  if !ctx_chain_acyclic(c) { return false; }
  if !ctx_deadlines_monotone(c) { return false; }
  var i = 0;
  while i < n {
    let id: Int = c.ids[i];
    let ko: Int = c.key_off[i];
    let kl: Int = c.key_len[i];
    let vo: Int = c.val_off[i];
    let vl: Int = c.val_len[i];
    let dl: Int = c.deadlines[i];
    let st: Int = c.cancelled[i];
    let rs: Int = c.cancel_reasons[i];
    let src: Int = c.cancel_sources[i];
    let tick: Int = c.cancel_ticks[i];
    if id < 0 { return false; }
    if ko < 0 { return false; }
    if kl < 0 { return false; }
    if ko + kl > c.text.len() { return false; }
    if vo != ko + kl { return false; }
    if vl < 0 { return false; }
    if vo + vl > c.text.len() { return false; }
    if dl < CTX_NO_DEADLINE { return false; }
    if st < CTX_STATE_ACTIVE { return false; }
    if st > CTX_STATE_CANCELLED { return false; }
    var dup = false;
    var j = 0;
    while j < n {
      if j != i {
        let other: Int = c.ids[j];
        if other == id { dup = true; }
      }
      j = j + 1;
    }
    if dup { return false; }
    if st == CTX_STATE_ACTIVE {
      if rs != CTX_REASON_NONE { return false; }
      if src != CTX_NOT_FOUND { return false; }
      if tick != CTX_NOT_FOUND { return false; }
    } else {
      if rs < 1 { return false; }
      if src < 0 { return false; }
      let sslot = _index(c, src);
      if sslot < 0 { return false; }
      if tick < 0 { return false; }
      if tick > c.now { return false; }
      if rs == CTX_REASON_PARENT {
        if sslot >= i { return false; }
        if !_is_descendant(c, i, sslot) { return false; }
        let srs: Int = c.cancel_reasons[sslot];
        if srs == CTX_REASON_PARENT { return false; }
      } else {
        if src != id { return false; }
      }
    }
    i = i + 1;
  }
  var k = 0;
  while k < n {
    let p: Int = c.parents[k];
    if p >= 0 {
      let pslot = _index(c, p);
      let pst: Int = c.cancelled[pslot];
      if pst == CTX_STATE_CANCELLED {
        let kst: Int = c.cancelled[k];
        if kst != CTX_STATE_CANCELLED { return false; }
      }
    }
    k = k + 1;
  }
  return true;
}
