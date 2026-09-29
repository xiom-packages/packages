// XIOM -- xiom.forkjoin: fork/join task modeling as a deterministic state machine
// Port task: promote the xiom.forkjoin placeholder to a real, tested,
// pure-XIOM package (no FFI, no threads, no clock).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: the semantic core that a fork/join scheduler would drive. There is
// no parallelism here: a work range [0, n) is split by a fixed threshold into
// a task tree (parallel Vec fields, one slot per node), leaf results are
// combined in order (sum, max, concatenation), and a work-stealing deque
// records owner LIFO push/pop and thief FIFO steals as a deterministic trace.
// A real runtime owns threads, atomics, parking and wakeups; this module owns
// the *semantics* in a form that can be tested exactly, without sleeps or
// races.
//
// Split rule: a node over range [lo, hi) is a leaf when hi - lo <= t;
// otherwise it splits at mid = lo + (hi - lo) / 2 into [lo, mid) and
// [mid, hi). Node 0 is the root [0, n); children are appended in left, right
// order, so node indices are a BFS (level) order. Leaves enumerated by an
// explicit left-first DFS are exactly the leaf ranges in ascending order:
// first lo = 0, each leaf's hi equals the next leaf's lo, last hi = n, and no
// range is empty or exceeds t (see SPEC.md section 2).
//
// Deque rule: `items` is laid out tail-to-head. Index 0 is the tail (oldest
// item, the thief end); the back of the Vec is the head (the owner end).
// The owner pushes and pops at the head (LIFO, so pop returns the newest
// item); a thief pops from the tail (FIFO, so successive steals return the
// oldest remaining items). Every successful steal appends (thief id, item)
// to the mirrored trace Vecs, so the steal order is fully deterministic.
//
// Language notes (XIOM v0.62.1): free functions only; Ok/Err are constructed
// only inside the _ok_*/_err_* leaf helpers; Vec[Int] element reads are bound
// with a typed `let`; all parallel Vec fields of a node are appended by one
// _push_node helper so they can never skew; Str values read from Vec[Str]
// elements are compared with str_compare; no Vec[StructType], no FFI, no
// threads, no indexed Vec[fn] dispatch and no function named `log`.

module xiom.forkjoin

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Leaf ranges of a split, as two parallel Vec[Int] fields.
/// `lo[i]` is the inclusive start and `hi[i]` the exclusive end of leaf i,
/// ordered by ascending range (leaf 0 is the leftmost range). The two fields
/// are always the same length; `fdj_leaf_count` reads `lo.len()`.
pub type LeafRanges = {
  lo: Vec[Int];
  hi: Vec[Int];
}

/// Fork/join task tree over the work range [0, n). All node data lives in
/// parallel Vec fields indexed by node id: `parent[i]`, `depth[i]` (root 0),
/// `lo[i]`/`hi[i]` (the [lo, hi) range), `weight[i]` (= hi - lo), `result[i]`
/// (the result slot), `is_leaf[i]` (1 = leaf, 0 = internal), and `left[i]` /
/// `right[i]` child ids (-1 at leaves). Node 0 is the root; children are
/// appended in left, right order, so ids are a BFS order. `node_count`,
/// `leaf_count` and `max_depth` cache the derived counts.
pub type ForkTree = {
  n: Int;
  threshold: Int;
  node_count: Int;
  leaf_count: Int;
  max_depth: Int;
  parent: Vec[Int];
  depth: Vec[Int];
  lo: Vec[Int];
  hi: Vec[Int];
  weight: Vec[Int];
  result: Vec[Int];
  is_leaf: Vec[Int];
  left: Vec[Int];
  right: Vec[Int];
}

/// Work-stealing deque model. `items` is tail-to-head: index 0 is the tail
/// (oldest, thief end), the back is the head (owner end). `thief_ids` and
/// `stolen_items` are mirrored trace Vecs recording every successful steal in
/// order; `pushes`, `owner_pops` and `steals` count the transitions. The
/// conservation invariant pushes == items.len() + owner_pops + steals always
/// holds (see fdj_deque_check).
pub type StealDeque = {
  items: Vec[Int];
  thief_ids: Vec[Int];
  stolen_items: Vec[Int];
  pushes: Int;
  owner_pops: Int;
  steals: Int;
}

/// Derived fork/join statistics: tree node count, leaf count and maximum
/// depth, plus the steal count observed on a deque.
pub type ForkStats = {
  nodes: Int;
  leaves: Int;
  max_depth: Int;
  steals: Int;
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only; see the header comment)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _ok_ranges(v: LeafRanges) -> Result[LeafRanges, Str] { return Ok(v); }
fn _err_ranges(m: Str) -> Result[LeafRanges, Str] { return Err(m); }
fn _ok_tree(v: ForkTree) -> Result[ForkTree, Str] { return Ok(v); }
fn _err_tree(m: Str) -> Result[ForkTree, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Shared parameter validation for the split entry points. Returns the stable
// error message, or "" when (n, t) is acceptable.
fn _arg_error(n: Int, t: Int) -> Str {
  if n < 1 { return "forkjoin: n must be >= 1"; }
  if t < 1 { return "forkjoin: threshold must be >= 1"; }
  return "";
}

// Append one node to every parallel Vec field in the same function, so the
// fields can never drift (parallel-Vec rule). is_leaf is derived from the
// node size: a node is a leaf exactly when hi - lo <= threshold.
fn _push_node(t: &mut ForkTree, parent: Int, depth: Int, lo: Int, hi: Int) {
  let w = hi - lo;
  let th = t.threshold;
  var leaf = 0;
  if w <= th { leaf = 1; }
  t.parent.push(parent);
  t.depth.push(depth);
  t.lo.push(lo);
  t.hi.push(hi);
  t.weight.push(w);
  t.result.push(0);
  t.is_leaf.push(leaf);
  t.left.push(-1);
  t.right.push(-1);
}

// Build the split tree. When limited == 1 the natural split may not exceed
// max_depth; when limited == 0 max_depth is ignored. Nodes are processed in
// increasing index order, which is BFS: appending a node's children never
// disturbs the pending nodes.
fn _build_tree(n: Int, t: Int, max_depth: Int, limited: Int) -> Result[ForkTree, Str] {
  let bad = _arg_error(n, t);
  if bad.len() > 0 { return _err_tree(bad); }
  if limited == 1 {
    if max_depth < 0 { return _err_tree("forkjoin: max_depth must be >= 0"); }
  }
  var tree = ForkTree{
    n: n;
    threshold: t;
    node_count: 0;
    leaf_count: 0;
    max_depth: 0;
    parent: Vec[Int].new();
    depth: Vec[Int].new();
    lo: Vec[Int].new();
    hi: Vec[Int].new();
    weight: Vec[Int].new();
    result: Vec[Int].new();
    is_leaf: Vec[Int].new();
    left: Vec[Int].new();
    right: Vec[Int].new();
  };
  _push_node(&mut tree, -1, 0, 0, n);
  var i = 0;
  while i < tree.parent.len() {
    let leaf: Int = tree.is_leaf[i];
    if leaf == 0 {
      let lo: Int = tree.lo[i];
      let hi: Int = tree.hi[i];
      let d: Int = tree.depth[i];
      if limited == 1 {
        if d >= max_depth { return _err_tree("forkjoin: depth limit exceeded"); }
      }
      let mid = lo + (hi - lo) / 2;
      let li = tree.parent.len();
      _push_node(&mut tree, i, d + 1, lo, mid);
      _push_node(&mut tree, i, d + 1, mid, hi);
      tree.left[i] = li;
      tree.right[i] = li + 1;
    }
    i = i + 1;
  }
  tree.node_count = tree.parent.len();
  var leaves = 0;
  var deepest = 0;
  var j = 0;
  while j < tree.parent.len() {
    let lf: Int = tree.is_leaf[j];
    let dj: Int = tree.depth[j];
    if lf == 1 { leaves = leaves + 1; }
    if dj > deepest { deepest = dj; }
    j = j + 1;
  }
  tree.leaf_count = leaves;
  tree.max_depth = deepest;
  return _ok_tree(tree);
}

// Node ids of every leaf, ordered by ascending range (left to right). The
// explicit LIFO stack visits the left child first, so the output is exactly
// the leaf order.
fn _leaf_nodes(t: &ForkTree) -> Vec[Int] {
  var out = Vec[Int].new();
  let count = t.parent.len();
  if count == 0 { return out; }
  var stack = Vec[Int].new();
  stack.push(0);
  while stack.len() > 0 {
    let top = stack.len() - 1;
    let node: Int = stack[top];
    stack.pop();
    let leaf: Int = t.is_leaf[node];
    if leaf == 1 {
      out.push(node);
    } else {
      let l: Int = t.left[node];
      let r: Int = t.right[node];
      stack.push(r);
      stack.push(l);
    }
  }
  return out;
}

// Drop items[0] (the tail), rebuilding the Vec; the owner end stays at the
// back. Only the steal path uses this (a thief always takes the oldest item).
fn _drop_tail(d: &mut StealDeque) {
  var kept = Vec[Int].new();
  var i = 1;
  while i < d.items.len() {
    let x: Int = d.items[i];
    kept.push(x);
    i = i + 1;
  }
  d.items = kept;
}

// ---------------------------------------------------------------------------
// Splitting
// ---------------------------------------------------------------------------

/// Build the fork/join task tree for work range [0, n) with threshold `t`.
/// A node splits while its size exceeds `t` (children [lo, mid) and
/// [mid, hi), mid = lo + (hi - lo) / 2); the tree therefore covers [0, n)
/// exactly with leaves of size <= t, and no depth limit applies.
/// Params: n - work items, must be >= 1; t - threshold, must be >= 1.
/// Returns: Ok(ForkTree); Err("forkjoin: n must be >= 1") or
/// Err("forkjoin: threshold must be >= 1") otherwise.
/// Complexity: O(nodes) = O(n / t * 2) nodes.
pub fn fdj_tree_build(n: Int, t: Int) -> Result[ForkTree, Str] {
  return _build_tree(n, t, 0, 0);
}

/// Like fdj_tree_build, but the natural split must fit in `max_depth`
/// (a leaf at depth max_depth is fine; an internal node at that depth is not,
/// because it would need children at depth max_depth + 1).
/// Params: n - work items, >= 1; t - threshold, >= 1; max_depth - 0-based
/// depth bound, >= 0 (root is depth 0).
/// Returns: Ok(ForkTree); Err("forkjoin: n must be >= 1"),
/// Err("forkjoin: threshold must be >= 1"),
/// Err("forkjoin: max_depth must be >= 0") or
/// Err("forkjoin: depth limit exceeded"). No partial tree is produced.
/// Complexity: O(nodes) when within the limit.
pub fn fdj_tree_build_limited(n: Int, t: Int, max_depth: Int) -> Result[ForkTree, Str] {
  return _build_tree(n, t, max_depth, 1);
}

/// Leaf ranges of the split of [0, n) with threshold `t`, in ascending range
/// order: leaf i is [lo[i], hi[i]), lo[0] = 0, hi[last] = n, each leaf's hi
/// equals the next leaf's lo, and every leaf has size in [1, t] -- an exact,
/// non-overlapping cover of [0, n).
/// Params: n - work items, must be >= 1; t - threshold, must be >= 1.
/// Returns: Ok(LeafRanges); the same validation errors as fdj_tree_build.
/// Complexity: O(nodes + leaves).
pub fn fdj_split_leaves(n: Int, t: Int) -> Result[LeafRanges, Str] {
  let built = _build_tree(n, t, 0, 0);
  match built {
    Ok(tree) => {
      var lo = Vec[Int].new();
      var hi = Vec[Int].new();
      let nodes = _leaf_nodes(&tree);
      var i = 0;
      while i < nodes.len() {
        let nd: Int = nodes[i];
        let a: Int = tree.lo[nd];
        let b: Int = tree.hi[nd];
        lo.push(a);
        hi.push(b);
        i = i + 1;
      }
      return _ok_ranges(LeafRanges{ lo: lo; hi: hi; });
    },
    Err(e) => { return _err_ranges(e); },
  }
  return _err_ranges("forkjoin: split failed");
}

// ---------------------------------------------------------------------------
// Leaf range accessors
// ---------------------------------------------------------------------------

/// Number of leaf ranges. Complexity: O(1).
pub fn fdj_leaf_count(r: &LeafRanges) -> Int {
  return r.lo.len();
}

/// Inclusive start of leaf `i` in ascending range order, or -1 when out of
/// range. Complexity: O(1).
pub fn fdj_leaf_lo(r: &LeafRanges, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.lo.len() { return -1; }
  let v: Int = r.lo[i];
  return v;
}

/// Exclusive end of leaf `i` in ascending range order, or -1 when out of
/// range. Complexity: O(1).
pub fn fdj_leaf_hi(r: &LeafRanges, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= r.hi.len() { return -1; }
  let v: Int = r.hi[i];
  return v;
}

/// Ranges rendered as comma-separated "lo-hi" pairs in leaf order, e.g.
/// "0-2,2-5,5-10" ("" for an empty range set). Deterministic witness for
/// ordering tests. Complexity: O(leaves).
pub fn fdj_ranges_str(r: &LeafRanges) -> Str {
  var out = "";
  var i = 0;
  while i < r.lo.len() {
    let a: Int = r.lo[i];
    let b: Int = r.hi[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(a) + "-" + convert.int_to_string(b);
    i = i + 1;
  }
  return out;
}

/// True when the leaf ranges exactly cover [0, n) without overlap, in
/// ascending order: first lo = 0, each hi equals the next lo, last hi = n,
/// and every range is non-empty. `n` is the work size the ranges claim to
/// cover, so the caller can detect both gaps and bad claims.
/// Complexity: O(leaves).
pub fn fdj_leaves_cover(r: &LeafRanges, n: Int) -> Bool {
  let count = r.lo.len();
  if count != r.hi.len() { return false; }
  if count == 0 { return false; }
  var prev = 0;
  var i = 0;
  while i < count {
    let a: Int = r.lo[i];
    let b: Int = r.hi[i];
    if a != prev { return false; }
    if b <= a { return false; }
    prev = b;
    i = i + 1;
  }
  if prev != n { return false; }
  return true;
}

/// True when every leaf range is non-empty and no larger than threshold `t`.
/// Complexity: O(leaves).
pub fn fdj_leaves_within(r: &LeafRanges, t: Int) -> Bool {
  if t < 1 { return false; }
  if r.lo.len() != r.hi.len() { return false; }
  var i = 0;
  while i < r.lo.len() {
    let a: Int = r.lo[i];
    let b: Int = r.hi[i];
    let w = b - a;
    if w < 1 { return false; }
    if w > t { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Tree accessors
// ---------------------------------------------------------------------------

/// Work range size the tree was built for. Complexity: O(1).
pub fn fdj_tree_n(t: &ForkTree) -> Int { return t.n; }

/// Split threshold the tree was built with. Complexity: O(1).
pub fn fdj_tree_threshold(t: &ForkTree) -> Int { return t.threshold; }

/// Number of nodes. Complexity: O(1).
pub fn fdj_tree_node_count(t: &ForkTree) -> Int { return t.node_count; }

/// Number of leaves. Complexity: O(1).
pub fn fdj_tree_leaf_count(t: &ForkTree) -> Int { return t.leaf_count; }

/// Depth of the deepest node (root is depth 0). Complexity: O(1).
pub fn fdj_tree_max_depth(t: &ForkTree) -> Int { return t.max_depth; }

/// Node id of leaf `i` in ascending range order, or -1 when out of range.
/// Complexity: O(nodes) (the leaf scan).
pub fn fdj_tree_leaf_node(t: &ForkTree, i: Int) -> Int {
  if i < 0 { return -1; }
  let nodes = _leaf_nodes(t);
  if i >= nodes.len() { return -1; }
  let nd: Int = nodes[i];
  return nd;
}

/// Inclusive start of leaf `i` in ascending range order, or -1 when out of
/// range. Complexity: O(nodes).
pub fn fdj_tree_leaf_lo(t: &ForkTree, i: Int) -> Int {
  let nd = fdj_tree_leaf_node(t, i);
  if nd < 0 { return -1; }
  let v: Int = t.lo[nd];
  return v;
}

/// Exclusive end of leaf `i` in ascending range order, or -1 when out of
/// range. Complexity: O(nodes).
pub fn fdj_tree_leaf_hi(t: &ForkTree, i: Int) -> Int {
  let nd = fdj_tree_leaf_node(t, i);
  if nd < 0 { return -1; }
  let v: Int = t.hi[nd];
  return v;
}

/// Write `value` into the result slot of `node`.
/// Params: t - the tree; node - the node id; value - the result to store.
/// Returns: Ok(value); Err("forkjoin: node index out of range") otherwise
/// (the tree is unchanged).
/// Complexity: O(1).
pub fn fdj_tree_set_result(t: &mut ForkTree, node: Int, value: Int) -> Result[Int, Str] {
  if node < 0 { return _err_int("forkjoin: node index out of range"); }
  if node >= t.parent.len() { return _err_int("forkjoin: node index out of range"); }
  t.result[node] = value;
  return _ok_int(value);
}

/// Read the result slot of `node`.
/// Params: t - the tree; node - the node id.
/// Returns: Ok(value); Err("forkjoin: node index out of range") otherwise.
/// Complexity: O(1).
pub fn fdj_tree_result(t: &ForkTree, node: Int) -> Result[Int, Str] {
  if node < 0 { return _err_int("forkjoin: node index out of range"); }
  if node >= t.parent.len() { return _err_int("forkjoin: node index out of range"); }
  let v: Int = t.result[node];
  return _ok_int(v);
}

/// Copy of the leaf result slots in ascending range order (leaf i's slot at
/// position i), ready to feed the combine reducers.
/// Complexity: O(nodes + leaves).
pub fn fdj_tree_leaf_results(t: &ForkTree) -> Vec[Int] {
  var out = Vec[Int].new();
  let nodes = _leaf_nodes(t);
  var i = 0;
  while i < nodes.len() {
    let nd: Int = nodes[i];
    let v: Int = t.result[nd];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Structural invariant of a tree built by fdj_tree_build(_limited): all
/// node Vecs have equal length, node 0 is the root [0, n) with parent -1 and
/// depth 0, every node has 0 <= lo < hi <= n and weight == hi - lo, is_leaf
/// is exactly size <= threshold, child ids are valid and consistent with
/// parent/depth/range, parents precede children, the cached node/leaf/depth
/// counts are right, and the leaves in left-to-right order exactly cover
/// [0, n). The empty tree is invalid.
/// Complexity: O(nodes + leaves).
pub fn fdj_tree_check(t: &ForkTree) -> Bool {
  let count = t.parent.len();
  if t.depth.len() != count { return false; }
  if t.lo.len() != count { return false; }
  if t.hi.len() != count { return false; }
  if t.weight.len() != count { return false; }
  if t.result.len() != count { return false; }
  if t.is_leaf.len() != count { return false; }
  if t.left.len() != count { return false; }
  if t.right.len() != count { return false; }
  if count == 0 { return false; }
  if t.n < 1 { return false; }
  if t.threshold < 1 { return false; }
  if t.node_count != count { return false; }
  let p0: Int = t.parent[0];
  let d0: Int = t.depth[0];
  let lo0: Int = t.lo[0];
  let hi0: Int = t.hi[0];
  let w0: Int = t.weight[0];
  let lf0: Int = t.is_leaf[0];
  if p0 != -1 { return false; }
  if d0 != 0 { return false; }
  if lo0 != 0 { return false; }
  if hi0 != t.n { return false; }
  if w0 != hi0 - lo0 { return false; }
  if w0 <= t.threshold {
    if lf0 != 1 { return false; }
  } else {
    if lf0 != 0 { return false; }
  }
  var leaves = 0;
  var deepest = 0;
  var i = 0;
  while i < count {
    let lo: Int = t.lo[i];
    let hi: Int = t.hi[i];
    let w: Int = t.weight[i];
    let dep: Int = t.depth[i];
    let lf: Int = t.is_leaf[i];
    let lc: Int = t.left[i];
    let rc: Int = t.right[i];
    if lo < 0 { return false; }
    if lo >= hi { return false; }
    if hi > t.n { return false; }
    if w != hi - lo { return false; }
    if dep < 0 { return false; }
    if dep > deepest { deepest = dep; }
    if lf == 1 { leaves = leaves + 1; }
    if w <= t.threshold {
      if lf != 1 { return false; }
      if lc != -1 { return false; }
      if rc != -1 { return false; }
    } else {
      if lf != 0 { return false; }
      if lc < 0 { return false; }
      if rc < 0 { return false; }
      if lc >= count { return false; }
      if rc >= count { return false; }
      if lc == rc { return false; }
      let clp: Int = t.parent[lc];
      let crp: Int = t.parent[rc];
      if clp != i { return false; }
      if crp != i { return false; }
      let cld: Int = t.depth[lc];
      let crd: Int = t.depth[rc];
      if cld != dep + 1 { return false; }
      if crd != dep + 1 { return false; }
      let cllo: Int = t.lo[lc];
      let clhi: Int = t.hi[lc];
      let crlo: Int = t.lo[rc];
      let crhi: Int = t.hi[rc];
      if cllo != lo { return false; }
      if clhi != crlo { return false; }
      if crhi != hi { return false; }
    }
    if i > 0 {
      let par: Int = t.parent[i];
      if par < 0 { return false; }
      if par >= i { return false; }
    }
    i = i + 1;
  }
  if leaves != t.leaf_count { return false; }
  if deepest != t.max_depth { return false; }
  let seq = _leaf_nodes(t);
  if seq.len() != t.leaf_count { return false; }
  var prev = 0;
  var j = 0;
  while j < seq.len() {
    let nd: Int = seq[j];
    let slo: Int = t.lo[nd];
    let shi: Int = t.hi[nd];
    if slo != prev { return false; }
    prev = shi;
    j = j + 1;
  }
  if prev != t.n { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Join / combine
// ---------------------------------------------------------------------------

/// Ordered sum reducer over per-leaf results (leaf 0 first). The sum of an
/// empty result vector is 0 (empty range identity), so the reducer is total.
/// Params: results - per-leaf results in leaf order.
/// Returns: the sum.
/// Complexity: O(leaves).
pub fn fdj_combine_sum(results: &Vec[Int]) -> Int {
  var acc = 0;
  var i = 0;
  while i < results.len() {
    let x: Int = results[i];
    acc = acc + x;
    i = i + 1;
  }
  return acc;
}

/// Ordered max reducer over per-leaf results. The max of an empty result
/// vector does not exist, so it is None rather than a sentinel.
/// Params: results - per-leaf results in leaf order.
/// Returns: Some(maximum); None when there are no results.
/// Complexity: O(leaves).
pub fn fdj_combine_max(results: &Vec[Int]) -> Option[Int] {
  if results.len() == 0 { return None; }
  let first: Int = results[0];
  var best = first;
  var i = 1;
  while i < results.len() {
    let x: Int = results[i];
    if x > best { best = x; }
    i = i + 1;
  }
  return Some(best);
}

/// Concatenate per-leaf result vectors in leaf order (chunk 0 first). This is
/// the join reducer for leaves whose output is itself a vector: the result is
/// the ordered concat of all chunks; empty chunks contribute nothing and the
/// relative order of every element is preserved.
/// Params: chunks - per-leaf result vectors in leaf order.
/// Returns: the concatenated vector (empty for zero chunks).
/// Complexity: O(total elements).
pub fn fdj_concat(chunks: &Vec[Vec[Int]]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < chunks.len() {
    let chunk: Vec[Int] = chunks[i];
    var j = 0;
    while j < chunk.len() {
      let x: Int = chunk[j];
      out.push(x);
      j = j + 1;
    }
    i = i + 1;
  }
  return out;
}

/// Combine the tree bottom-up with the sum reducer: every internal node's
/// result slot becomes the sum of its two children's slots; leaf slots are
/// the inputs and are left untouched. Children always have higher ids than
/// their parent, so one reverse sweep is enough.
/// Params: t - the tree whose leaf result slots were filled by the caller.
/// Returns: Ok(root result); Err("forkjoin: tree is empty") when the tree
/// has no nodes.
/// Complexity: O(nodes).
pub fn fdj_tree_reduce_sum(t: &mut ForkTree) -> Result[Int, Str] {
  let count = t.parent.len();
  if count == 0 { return _err_int("forkjoin: tree is empty"); }
  var i = count;
  while i > 0 {
    i = i - 1;
    let leaf: Int = t.is_leaf[i];
    if leaf == 0 {
      let l: Int = t.left[i];
      let r: Int = t.right[i];
      let a: Int = t.result[l];
      let b: Int = t.result[r];
      t.result[i] = a + b;
    }
  }
  let root: Int = t.result[0];
  return _ok_int(root);
}

/// Combine the tree bottom-up with the max reducer: every internal node's
/// result slot becomes the max of its two children's slots; leaf slots are
/// the inputs and are left untouched. An empty tree has no max.
/// Params: t - the tree whose leaf result slots were filled by the caller.
/// Returns: Ok(root result); Err("forkjoin: tree is empty") when the tree
/// has no nodes.
/// Complexity: O(nodes).
pub fn fdj_tree_reduce_max(t: &mut ForkTree) -> Result[Int, Str] {
  let count = t.parent.len();
  if count == 0 { return _err_int("forkjoin: tree is empty"); }
  var i = count;
  while i > 0 {
    i = i - 1;
    let leaf: Int = t.is_leaf[i];
    if leaf == 0 {
      let l: Int = t.left[i];
      let r: Int = t.right[i];
      let a: Int = t.result[l];
      let b: Int = t.result[r];
      if b > a { t.result[i] = b; } else { t.result[i] = a; }
    }
  }
  let root: Int = t.result[0];
  return _ok_int(root);
}

// ---------------------------------------------------------------------------
// Work-stealing deque
// ---------------------------------------------------------------------------

/// Create an empty deque. Complexity: O(1).
pub fn fdj_deque_new() -> StealDeque {
  return StealDeque{
    items: Vec[Int].new();
    thief_ids: Vec[Int].new();
    stolen_items: Vec[Int].new();
    pushes: 0;
    owner_pops: 0;
    steals: 0;
  };
}

/// Owner push: append `item` at the head (the back of `items`).
/// Params: d - the deque; item - the item to push.
/// Returns: the new deque length.
/// Complexity: O(1).
pub fn fdj_deque_push(d: &mut StealDeque, item: Int) -> Int {
  d.items.push(item);
  d.pushes = d.pushes + 1;
  return d.items.len();
}

/// Owner pop: remove the newest item (the head, back of `items`, LIFO).
/// Params: d - the deque.
/// Returns: Some(newest item); None when the deque is empty (no state
/// change). A successful pop increments the owner_pops counter.
/// Complexity: O(1).
pub fn fdj_deque_pop(d: &mut StealDeque) -> Option[Int] {
  match d.items.pop() {
    Some(x) => {
      d.owner_pops = d.owner_pops + 1;
      return Some(x);
    },
    None => { return None; },
  }
  return None;
}

/// Thief steal: remove the oldest item (the tail, index 0, FIFO), so
/// successive steals return items in the order they were pushed. On success
/// the (thief, item) pair is appended to both trace Vecs in the same
/// function and the steals counter is incremented.
/// Params: d - the deque; thief - caller-assigned thief id, must be >= 0.
/// Returns: Ok(stolen item); Err("forkjoin: thief id must be >= 0") for a
/// negative thief (state unchanged); Err("forkjoin: deque is empty") when
/// there is nothing to steal (state unchanged).
/// Complexity: O(deque length) (tail removal rebuilds the Vec).
pub fn fdj_deque_steal(d: &mut StealDeque, thief: Int) -> Result[Int, Str] {
  if thief < 0 { return _err_int("forkjoin: thief id must be >= 0"); }
  if d.items.len() == 0 { return _err_int("forkjoin: deque is empty"); }
  let item: Int = d.items[0];
  _drop_tail(d);
  d.thief_ids.push(thief);
  d.stolen_items.push(item);
  d.steals = d.steals + 1;
  return _ok_int(item);
}

/// Copy every leaf node id of `t` onto the deque, in ascending range order,
/// as owner pushes (one per leaf). A runtime would let one worker seed the
/// deque and let thieves steal from the tail. Returns the number of pushes.
/// Complexity: O(nodes + leaves).
pub fn fdj_tree_push_leaves(t: &ForkTree, d: &mut StealDeque) -> Int {
  let nodes = _leaf_nodes(t);
  var i = 0;
  while i < nodes.len() {
    let nd: Int = nodes[i];
    fdj_deque_push(d, nd);
    i = i + 1;
  }
  return nodes.len();
}

// ---------------------------------------------------------------------------
// Deque accessors and trace
// ---------------------------------------------------------------------------

/// Number of items currently in the deque. Complexity: O(1).
pub fn fdj_deque_len(d: &StealDeque) -> Int { return d.items.len(); }

/// Owner pushes so far. Complexity: O(1).
pub fn fdj_deque_push_count(d: &StealDeque) -> Int { return d.pushes; }

/// Owner pops so far. Complexity: O(1).
pub fn fdj_deque_pop_count(d: &StealDeque) -> Int { return d.owner_pops; }

/// Successful steals so far (== trace length). Complexity: O(1).
pub fn fdj_deque_steal_count(d: &StealDeque) -> Int { return d.steals; }

/// Steal trace length. Complexity: O(1).
pub fn fdj_deque_trace_len(d: &StealDeque) -> Int { return d.thief_ids.len(); }

/// Thief id of trace entry `i` (0 = first steal), or -1 when out of range.
/// Complexity: O(1).
pub fn fdj_deque_trace_thief(d: &StealDeque, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= d.thief_ids.len() { return -1; }
  let v: Int = d.thief_ids[i];
  return v;
}

/// Item of trace entry `i` (0 = first steal), or -1 when out of range.
/// Complexity: O(1).
pub fn fdj_deque_trace_item(d: &StealDeque, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= d.stolen_items.len() { return -1; }
  let v: Int = d.stolen_items[i];
  return v;
}

/// Steal trace rendered as comma-separated "thief:item" pairs in steal
/// order, e.g. "7:3,9:4" ("" when nothing was stolen). This is the
/// deterministic witness a backend test asserts on.
/// Complexity: O(trace length).
pub fn fdj_deque_trace_str(d: &StealDeque) -> Str {
  var out = "";
  var i = 0;
  while i < d.thief_ids.len() {
    let th: Int = d.thief_ids[i];
    let it: Int = d.stolen_items[i];
    if i > 0 { out = out + ","; }
    out = out + convert.int_to_string(th) + ":" + convert.int_to_string(it);
    i = i + 1;
  }
  return out;
}

/// True when the steal trace string equals `want` (str_compare, never `==`
/// on built strings).
/// Complexity: O(trace length + |want|).
pub fn fdj_deque_trace_is(d: &StealDeque, want: Str) -> Bool {
  return string.str_compare(fdj_deque_trace_str(d), want) == 0;
}

/// Structural invariant of a deque: both trace Vecs are mirrored, the steal
/// counter equals the trace length, and every push is accounted for exactly
/// once by the current items plus the owner pops plus the steals
/// (push conservation). An empty deque is valid.
/// Complexity: O(1).
pub fn fdj_deque_check(d: &StealDeque) -> Bool {
  if d.pushes < 0 { return false; }
  if d.owner_pops < 0 { return false; }
  if d.steals < 0 { return false; }
  if d.thief_ids.len() != d.stolen_items.len() { return false; }
  if d.steals != d.thief_ids.len() { return false; }
  if d.pushes != d.items.len() + d.owner_pops + d.steals { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

/// Fork/join statistics: the tree's node count, leaf count and max depth,
/// plus the deque's steal count.
/// Params: t - a tree built by fdj_tree_build; d - a deque.
/// Returns: ForkStats{ nodes, leaves, max_depth, steals }.
/// Complexity: O(1).
pub fn fdj_stats(t: &ForkTree, d: &StealDeque) -> ForkStats {
  return ForkStats{
    nodes: t.node_count;
    leaves: t.leaf_count;
    max_depth: t.max_depth;
    steals: d.steals;
  };
}
