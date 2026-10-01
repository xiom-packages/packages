// XIOM -- xiom.chaincrypto: commitment and proof structures over opaque hashes
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Contract (full rules and error catalog in SPEC.md):
//   * Hash values are OPAQUE caller-supplied Ints in 0..2147483646
//     (2^31 - 2). This module does NOT hash: it models the STRUCTURE of
//     blockchain commitments (append-only accumulator, membership proofs,
//     threshold approvals, commit-reveal records). No cryptography.
//   * Internal tree nodes are derived with the deterministic, order-sensitive
//     integer mix combine(l, r) = (l + 31 * r + 7) % 2147483647, exported as
//     chaincrypto_node_combine. It is opaque bookkeeping, not a cryptographic
//     compression function.
//   * The tree shape is the iterative odd-promotion shape: pair nodes left to
//     right, carry a lone last node up unchanged (never duplicated). The empty
//     accumulator has leaf_count == 0 and root == -1 (chaincrypto_empty_root).
//   * Membership proofs are sibling values plus direction bits (0 = sibling on
//     the left, 1 = sibling on the right), bottom level first. Promoted levels
//     contribute no entry. Verification folds the caller-supplied leaf hash up
//     with the siblings and compares against the root.
//   * Threshold gates track approvals of member indices 0..member_count-1;
//     duplicate approvals are rejected. Execution requires m-of-n approvals,
//     a nonce equal to execution_nonce + 1, and can happen once.
//   * Commit-reveal records run commit -> reveal -> expiry: a reveal is
//     accepted only in [reveal_tick, expiry_tick), must match the committed
//     opaque value, and can happen once; a refund is accepted only at or after
//     expiry and can happen once.
//   * Pure XIOM, no FFI, no I/O, no global state. Free functions only; no
//     Vec[StructType]; vector fields are copied explicitly and mirror-pushed
//     in lockstep; every loop makes progress.

module xiom.chaincrypto

use xiom.convert;

// --------------------------------------------------
//  Constants and types
// --------------------------------------------------

// Valid opaque hashes are 0.._CC_HASH_MOD - 1; _CC_HASH_MOD is 2^31 - 1.
const _CC_HASH_MOD: Int = 2147483647;

// Root of the empty accumulator: no real hash, so -1 is unambiguous.
const _CC_EMPTY_ROOT: Int = -1;

// Commit-reveal phase codes returned by chaincrypto_commit_reveal_phase.
const _CC_PHASE_WAITING: Int = 0;
const _CC_PHASE_REVEAL: Int = 1;
const _CC_PHASE_EXPIRED: Int = 2;

/// A leaf count / root pair recorded in the accumulator's root history.
pub type ChainRootRecord = {
  leaf_count: Int;
  root: Int;
}

/// An append-only hash-tree accumulator over opaque leaf hashes.
///
/// `leaves[i]` is the opaque leaf hash of leaf `i`. `levels` stores every
/// level concatenated (level 0 = the leaves) and `level_sizes[l]` /
/// `level_starts[l]` are the mirror metadata: level `l` occupies
/// `levels[level_starts[l] .. level_starts[l] + level_sizes[l])`. The last
/// level holds the single root unless the accumulator is empty. History
/// vectors are mirror-pushed: `history_counts[i]` is the leaf count and
/// `history_roots[i]` the root after the (i + 1)-th append.
pub type ChainAccumulator = {
  leaf_count: Int;
  root: Int;
  leaves: Vec[Int];
  level_sizes: Vec[Int];
  level_starts: Vec[Int];
  levels: Vec[Int];
  history_counts: Vec[Int];
  history_roots: Vec[Int];
}

/// A membership proof for one accumulator leaf: the sibling values on the
/// path to the root (bottom level first) plus one direction bit per sibling
/// (0 = sibling on the left, 1 = sibling on the right). Promoted levels
/// contribute no entry, so both vectors have the same length.
pub type ChainProof = {
  leaf_index: Int;
  leaf_count: Int;
  root: Int;
  siblings: Vec[Int];
  directions: Vec[Int];
}

/// An m-of-n threshold approval gate. `approvals` holds the approved member
/// indices in approval order (at most one entry per member). `execution_nonce`
/// is 0 before execution; the first valid execution must present nonce 1.
pub type ChainThresholdGate = {
  threshold: Int;
  member_count: Int;
  approvals: Vec[Int];
  executed: Bool;
  execution_nonce: Int;
  executed_at: Int;
  approvals_digest: Int;
}

/// The receipt produced by a successful threshold execution.
pub type ChainExecutionReceipt = {
  nonce: Int;
  approval_count: Int;
  executed_at: Int;
  approvals_digest: Int;
}

/// A commit-reveal record over tick numbers. Ticks are caller-supplied integer
/// time units. `reveal_at` / `refund_at` stay -1 until set.
pub type ChainCommitReveal = {
  commit_hash: Int;
  commit_tick: Int;
  reveal_tick: Int;
  expiry_tick: Int;
  revealed: Bool;
  revealed_value: Int;
  reveal_at: Int;
  refunded: Bool;
  refund_at: Int;
}

// Internal level table returned by _cc_rebuild (single return value).
type _CcLevels = {
  sizes: Vec[Int];
  starts: Vec[Int];
  nodes: Vec[Int];
  root: Int;
}

// --------------------------------------------------
//  Result leaves
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _cc_ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _cc_err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _cc_ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _cc_err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[ChainAccumulator, Str].
fn _cc_ok_acc(v: ChainAccumulator) -> Result[ChainAccumulator, Str] {
  return Ok(v);
}

// Err(m) for Result[ChainAccumulator, Str].
fn _cc_err_acc(m: Str) -> Result[ChainAccumulator, Str] {
  return Err(m);
}

// Ok(v) for Result[ChainProof, Str].
fn _cc_ok_proof(v: ChainProof) -> Result[ChainProof, Str] {
  return Ok(v);
}

// Err(m) for Result[ChainProof, Str].
fn _cc_err_proof(m: Str) -> Result[ChainProof, Str] {
  return Err(m);
}

// Ok(v) for Result[ChainThresholdGate, Str].
fn _cc_ok_gate(v: ChainThresholdGate) -> Result[ChainThresholdGate, Str] {
  return Ok(v);
}

// Err(m) for Result[ChainThresholdGate, Str].
fn _cc_err_gate(m: Str) -> Result[ChainThresholdGate, Str] {
  return Err(m);
}

// Ok(v) for Result[ChainExecutionReceipt, Str].
fn _cc_ok_receipt(v: ChainExecutionReceipt) -> Result[ChainExecutionReceipt, Str] {
  return Ok(v);
}

// Err(m) for Result[ChainExecutionReceipt, Str].
fn _cc_err_receipt(m: Str) -> Result[ChainExecutionReceipt, Str] {
  return Err(m);
}

// Ok(v) for Result[ChainCommitReveal, Str].
fn _cc_ok_cr(v: ChainCommitReveal) -> Result[ChainCommitReveal, Str] {
  return Ok(v);
}

// Err(m) for Result[ChainCommitReveal, Str].
fn _cc_err_cr(m: Str) -> Result[ChainCommitReveal, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic and vector helpers
// --------------------------------------------------

// True when h is a valid opaque hash (0..2^31 - 2).
fn _cc_in_range(h: Int) -> Bool {
  return h >= 0 && h < _CC_HASH_MOD;
}

// Deterministic order-sensitive mix of two valid hashes; result in range.
fn _cc_combine(left: Int, right: Int) -> Int {
  return (left + right * 31 + 7) % _CC_HASH_MOD;
}

// Ceiling of a / b for a >= 0, b > 0 (explicit remainder form).
fn _cc_ceil_div(a: Int, b: Int) -> Int {
  var q = a / b;
  if a % b > 0 {
    q = q + 1;
  }
  return q;
}

// Fresh copy of an Int vector.
fn _cc_copy_ints(v: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Append every element of src to dst.
fn _cc_append_ints(dst: &mut Vec[Int], src: &Vec[Int]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

// Fold approvals into an opaque digest (seed 0).
fn _cc_digest(v: &Vec[Int]) -> Int {
  var d = 0;
  var i = 0;
  while i < v.len() {
    let x = v[i];
    d = _cc_combine(d, x);
    i = i + 1;
  }
  return d;
}

// --------------------------------------------------
//  Internal tree construction and access
// --------------------------------------------------

// Rebuild the whole level table from scratch for `leaves`. Level 0 is the
// leaves; each next level pairs nodes left to right and carries a lone last
// node up unchanged. O(n) combines per append.
fn _cc_rebuild(leaf_count: Int, leaves: &Vec[Int]) -> _CcLevels {
  var nodes = Vec[Int].new();
  var sizes = Vec[Int].new();
  var starts = Vec[Int].new();
  _cc_append_ints(&mut nodes, leaves);
  sizes.push(leaf_count);
  starts.push(0);
  var count = leaf_count;
  var start = 0;
  while count > 1 {
    var i = 0;
    while i + 1 < count {
      let left = nodes[start + i];
      let right = nodes[start + i + 1];
      nodes.push(_cc_combine(left, right));
      i = i + 2;
    }
    if i < count {
      // Promotion: copy the lone last node unchanged (never duplicated).
      let promo = nodes[start + i];
      nodes.push(promo);
    }
    start = start + count;
    count = _cc_ceil_div(count, 2);
    sizes.push(count);
    starts.push(start);
  }
  var root = _CC_EMPTY_ROOT;
  if leaf_count > 0 {
    root = nodes[nodes.len() - 1];
  }
  return _CcLevels{ sizes: sizes; starts: starts; nodes: nodes; root: root };
}

// --------------------------------------------------
//  Node combine (public, opaque)
// --------------------------------------------------

/// The deterministic, order-sensitive node mix used for internal tree nodes:
/// `combine(l, r) = (l + 31 * r + 7) % 2147483647`. This is opaque structural
/// bookkeeping, NOT a cryptographic compression function; callers that need
/// real commitments hash off-module and supply the resulting opaque values.
/// Params: left, right - opaque hashes in 0..2147483646.
/// Returns: Ok(mix) in 0..2147483646.
/// Error case: Err("chaincrypto: combine left hash L out of range
/// 0..2147483646") or the same for the right hash.
/// Complexity: O(1).
pub fn chaincrypto_node_combine(left: Int, right: Int) -> Result[Int, Str] {
  if !_cc_in_range(left) {
    return _cc_err_int("chaincrypto: combine left hash " + convert.int_to_string(left) + " out of range 0..2147483646");
  }
  if !_cc_in_range(right) {
    return _cc_err_int("chaincrypto: combine right hash " + convert.int_to_string(right) + " out of range 0..2147483646");
  }
  return _cc_ok_int(_cc_combine(left, right));
}

/// Root reported for the empty accumulator: -1 (no real hash).
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_empty_root() -> Int {
  return _CC_EMPTY_ROOT;
}

// --------------------------------------------------
//  Accumulator
// --------------------------------------------------

/// Create the empty accumulator: leaf_count 0, root -1, all vectors empty.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_accumulator_new() -> ChainAccumulator {
  var leaves = Vec[Int].new();
  var sizes = Vec[Int].new();
  var starts = Vec[Int].new();
  var nodes = Vec[Int].new();
  var counts = Vec[Int].new();
  var roots = Vec[Int].new();
  return ChainAccumulator{ leaf_count: 0; root: _CC_EMPTY_ROOT; leaves: leaves; level_sizes: sizes; level_starts: starts; levels: nodes; history_counts: counts; history_roots: roots };
}

/// Append one opaque leaf hash and return the new accumulator. The root and
/// all levels are rebuilt, and one (leaf_count, root) record is appended to
/// the root history. Inputs are not mutated.
/// Params: acc - the current accumulator; leaf_hash - opaque hash in
/// 0..2147483646.
/// Returns: Ok(accumulator) with leaf_count + 1 leaves.
/// Error case: Err("chaincrypto: leaf hash L out of range 0..2147483646").
/// Complexity: O(n) combines for n leaves.
pub fn chaincrypto_accumulator_append(acc: &ChainAccumulator, leaf_hash: Int) -> Result[ChainAccumulator, Str] {
  if !_cc_in_range(leaf_hash) {
    return _cc_err_acc("chaincrypto: leaf hash " + convert.int_to_string(leaf_hash) + " out of range 0..2147483646");
  }
  var leaves = _cc_copy_ints(&acc.leaves);
  leaves.push(leaf_hash);
  let count = acc.leaf_count + 1;
  let table = _cc_rebuild(count, &leaves);
  var counts = _cc_copy_ints(&acc.history_counts);
  var roots = _cc_copy_ints(&acc.history_roots);
  counts.push(count);
  roots.push(table.root);
  return _cc_ok_acc(ChainAccumulator{ leaf_count: count; root: table.root; leaves: leaves; level_sizes: table.sizes; level_starts: table.starts; levels: table.nodes; history_counts: counts; history_roots: roots });
}

/// Number of leaves (0 for the empty accumulator).
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_accumulator_leaf_count(acc: &ChainAccumulator) -> Int {
  return acc.leaf_count;
}

/// Current root; -1 for the empty accumulator.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_accumulator_root(acc: &ChainAccumulator) -> Int {
  return acc.root;
}

/// Current leaf count / root record.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_accumulator_record(acc: &ChainAccumulator) -> ChainRootRecord {
  return ChainRootRecord{ leaf_count: acc.leaf_count; root: acc.root };
}

/// Opaque leaf hash of leaf `i` (0-based, append order).
/// Params: acc - the accumulator; i - 0..leaf_count - 1.
/// Returns: Ok(hash), or Err naming the index.
/// Error case: Err("chaincrypto: leaf index I out of range 0..M").
/// Complexity: O(1).
pub fn chaincrypto_accumulator_leaf(acc: &ChainAccumulator, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= acc.leaf_count {
    return _cc_err_int("chaincrypto: leaf index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(acc.leaf_count - 1));
  }
  return _cc_ok_int(acc.leaves[i]);
}

/// Number of root-history records; equals leaf_count.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_accumulator_history_len(acc: &ChainAccumulator) -> Int {
  return acc.history_counts.len();
}

/// Leaf count recorded in root-history record `i` (always i + 1).
/// Params: acc - the accumulator; i - 0..history_len - 1.
/// Returns: Ok(count), or Err naming the index.
/// Error case: Err("chaincrypto: history index I out of range 0..M").
/// Complexity: O(1).
pub fn chaincrypto_accumulator_history_count(acc: &ChainAccumulator, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= acc.history_counts.len() {
    return _cc_err_int("chaincrypto: history index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(acc.history_counts.len() - 1));
  }
  return _cc_ok_int(acc.history_counts[i]);
}

/// Root recorded in root-history record `i` (the root after append i + 1).
/// Params: acc - the accumulator; i - 0..history_len - 1.
/// Returns: Ok(root), or Err naming the index.
/// Error case: Err("chaincrypto: history index I out of range 0..M").
/// Complexity: O(1).
pub fn chaincrypto_accumulator_history_root(acc: &ChainAccumulator, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= acc.history_roots.len() {
    return _cc_err_int("chaincrypto: history index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(acc.history_roots.len() - 1));
  }
  return _cc_ok_int(acc.history_roots[i]);
}

// --------------------------------------------------
//  Membership proofs
// --------------------------------------------------

/// Generate the membership proof for leaf `leaf_index`.
/// Walks from the leaf level to the level below the root; a node that has a
/// sibling records it (with direction bit 1 for a right sibling, 0 for a
/// left sibling); a promoted node records nothing.
/// Params: acc - the accumulator; leaf_index - 0..leaf_count - 1.
/// Returns: Ok(proof) with proof.leaf_count == acc.leaf_count and
/// proof.root == acc.root.
/// Error case: Err("chaincrypto: empty accumulator has no membership
/// proofs"); Err("chaincrypto: leaf index I out of range 0..M").
/// Complexity: O(log n) siblings, O(level_count) time.
pub fn chaincrypto_accumulator_proof(acc: &ChainAccumulator, leaf_index: Int) -> Result[ChainProof, Str] {
  if acc.leaf_count == 0 {
    return _cc_err_proof("chaincrypto: empty accumulator has no membership proofs");
  }
  if leaf_index < 0 || leaf_index >= acc.leaf_count {
    return _cc_err_proof("chaincrypto: leaf index " + convert.int_to_string(leaf_index) + " out of range 0.." + convert.int_to_string(acc.leaf_count - 1));
  }
  var siblings = Vec[Int].new();
  var directions = Vec[Int].new();
  var idx = leaf_index;
  var level = 0;
  while level < acc.level_sizes.len() - 1 {
    let size = acc.level_sizes[level];
    let start = acc.level_starts[level];
    if idx % 2 == 1 {
      let sib = acc.levels[start + idx - 1];
      siblings.push(sib);
      directions.push(0);
    } else {
      if idx + 1 < size {
        let sib = acc.levels[start + idx + 1];
        siblings.push(sib);
        directions.push(1);
      }
    }
    idx = idx / 2;
    level = level + 1;
  }
  return _cc_ok_proof(ChainProof{ leaf_index: leaf_index; leaf_count: acc.leaf_count; root: acc.root; siblings: siblings; directions: directions });
}

/// Verify a membership proof against a caller-supplied leaf hash and root.
/// Structural checks first (Err), then the fold: with the running index and
/// level size, a node with a sibling consumes the next sibling and direction
/// (direction 1: h = combine(h, sibling); direction 0: h = combine(sibling, h));
/// a promoted node consumes nothing. The proof is accepted when every sibling
/// is consumed and the folded value equals `root`.
/// Params: proof - the proof; leaf_hash - the claimed opaque leaf hash;
/// root - the claimed opaque root.
/// Returns: Ok(true) when the fold reproduces root; Ok(false) for any
/// mismatch (wrong leaf, sibling, direction, index, short proof) or a root
/// that is not a valid hash.
/// Error case: Err("chaincrypto: proof leaf count L must be positive");
/// Err("chaincrypto: proof leaf index I out of range 0..M");
/// Err("chaincrypto: proof sibling count C does not match direction count D");
/// Err("chaincrypto: proof direction K is V (must be 0 or 1)");
/// Err("chaincrypto: proof leaf hash L out of range 0..2147483646").
/// Complexity: O(log n) combines.
pub fn chaincrypto_proof_verify(proof: &ChainProof, leaf_hash: Int, root: Int) -> Result[Bool, Str] {
  let lc = proof.leaf_count;
  if lc <= 0 {
    return _cc_err_bool("chaincrypto: proof leaf count " + convert.int_to_string(lc) + " must be positive");
  }
  let li = proof.leaf_index;
  if li < 0 || li >= lc {
    return _cc_err_bool("chaincrypto: proof leaf index " + convert.int_to_string(li) + " out of range 0.." + convert.int_to_string(lc - 1));
  }
  let sc = proof.siblings.len();
  let dc = proof.directions.len();
  if sc != dc {
    return _cc_err_bool("chaincrypto: proof sibling count " + convert.int_to_string(sc) + " does not match direction count " + convert.int_to_string(dc));
  }
  var k = 0;
  while k < dc {
    let d = proof.directions[k];
    if d != 0 && d != 1 {
      return _cc_err_bool("chaincrypto: proof direction " + convert.int_to_string(k) + " is " + convert.int_to_string(d) + " (must be 0 or 1)");
    }
    k = k + 1;
  }
  if !_cc_in_range(leaf_hash) {
    return _cc_err_bool("chaincrypto: proof leaf hash " + convert.int_to_string(leaf_hash) + " out of range 0..2147483646");
  }
  if !_cc_in_range(root) {
    return _cc_ok_bool(false);
  }
  var h = leaf_hash;
  var idx = li;
  var size = lc;
  var consumed = 0;
  while size > 1 {
    var take = false;
    if idx % 2 == 1 {
      take = true;
    } else {
      if idx + 1 < size {
        take = true;
      }
    }
    if take {
      if consumed >= sc {
        return _cc_ok_bool(false);
      }
      let sib = proof.siblings[consumed];
      let dir = proof.directions[consumed];
      var nh = 0;
      if dir == 1 {
        nh = _cc_combine(h, sib);
      } else {
        nh = _cc_combine(sib, h);
      }
      h = nh;
      consumed = consumed + 1;
    }
    idx = idx / 2;
    size = _cc_ceil_div(size, 2);
  }
  if consumed != sc {
    return _cc_ok_bool(false);
  }
  return _cc_ok_bool(h == root);
}

/// Leaf index the proof was generated for.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_proof_leaf_index(proof: &ChainProof) -> Int {
  return proof.leaf_index;
}

/// Leaf count of the accumulator the proof was generated from.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_proof_leaf_count(proof: &ChainProof) -> Int {
  return proof.leaf_count;
}

/// Root the proof was generated against.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_proof_root(proof: &ChainProof) -> Int {
  return proof.root;
}

/// Number of siblings the proof carries.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_proof_sibling_count(proof: &ChainProof) -> Int {
  return proof.siblings.len();
}

/// Sibling `i` (0-based, bottom level first).
/// Params: proof - the proof; i - 0..sibling_count - 1.
/// Returns: Ok(value), or Err naming the index.
/// Error case: Err("chaincrypto: sibling index I out of range 0..M").
/// Complexity: O(1).
pub fn chaincrypto_proof_sibling(proof: &ChainProof, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= proof.siblings.len() {
    return _cc_err_int("chaincrypto: sibling index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(proof.siblings.len() - 1));
  }
  return _cc_ok_int(proof.siblings[i]);
}

/// Direction bit of sibling `i`: 0 = sibling on the left, 1 = on the right.
/// Params: proof - the proof; i - 0..sibling_count - 1.
/// Returns: Ok(0 or 1), or Err naming the index.
/// Error case: Err("chaincrypto: direction index I out of range 0..M").
/// Complexity: O(1).
pub fn chaincrypto_proof_direction(proof: &ChainProof, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= proof.directions.len() {
    return _cc_err_int("chaincrypto: direction index " + convert.int_to_string(i) + " out of range 0.." + convert.int_to_string(proof.directions.len() - 1));
  }
  return _cc_ok_int(proof.directions[i]);
}

// --------------------------------------------------
//  Threshold (m-of-n) approval gate
// --------------------------------------------------

/// Create a fresh m-of-n gate: no approvals, not executed, nonce 0.
/// Params: threshold - required approvals m; member_count - member count n.
/// Returns: Ok(gate) with member indices 0..n-1.
/// Error case: Err("chaincrypto: threshold must be at least 1 (got M)");
/// Err("chaincrypto: member count must be at least 1 (got N)");
/// Err("chaincrypto: threshold M exceeds member count N").
/// Complexity: O(1).
pub fn chaincrypto_threshold_new(threshold: Int, member_count: Int) -> Result[ChainThresholdGate, Str] {
  if threshold < 1 {
    return _cc_err_gate("chaincrypto: threshold must be at least 1 (got " + convert.int_to_string(threshold) + ")");
  }
  if member_count < 1 {
    return _cc_err_gate("chaincrypto: member count must be at least 1 (got " + convert.int_to_string(member_count) + ")");
  }
  if threshold > member_count {
    return _cc_err_gate("chaincrypto: threshold " + convert.int_to_string(threshold) + " exceeds member count " + convert.int_to_string(member_count));
  }
  var approvals = Vec[Int].new();
  return _cc_ok_gate(ChainThresholdGate{ threshold: threshold; member_count: member_count; approvals: approvals; executed: false; execution_nonce: 0; executed_at: -1; approvals_digest: -1 });
}

/// Whether member `member` has already approved.
/// Error case: none (out-of-range members are simply not approved).
/// Complexity: O(approvals).
pub fn chaincrypto_threshold_is_approved(gate: &ChainThresholdGate, member: Int) -> Bool {
  var i = 0;
  while i < gate.approvals.len() {
    let a = gate.approvals[i];
    if a == member {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Number of recorded approvals.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_threshold_approval_count(gate: &ChainThresholdGate) -> Int {
  return gate.approvals.len();
}

/// Copy of the approved member indices in approval order.
/// Error case: none. Complexity: O(approvals).
pub fn chaincrypto_threshold_approvals(gate: &ChainThresholdGate) -> Vec[Int] {
  return _cc_copy_ints(&gate.approvals);
}

/// Whether the approval count has reached the threshold.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_threshold_met(gate: &ChainThresholdGate) -> Bool {
  return gate.approvals.len() >= gate.threshold;
}

/// Record one approval by `member` and return the new gate. Duplicate
/// approvals and approvals on an executed gate are rejected; the approval
/// order is preserved. Inputs are not mutated.
/// Params: gate - the current gate; member - 0..member_count - 1.
/// Returns: Ok(new gate) with one more approval.
/// Error case: Err("chaincrypto: threshold gate already executed");
/// Err("chaincrypto: member index I out of range 0..M");
/// Err("chaincrypto: member I has already approved").
/// Complexity: O(approvals).
pub fn chaincrypto_threshold_approve(gate: &ChainThresholdGate, member: Int) -> Result[ChainThresholdGate, Str] {
  if gate.executed {
    return _cc_err_gate("chaincrypto: threshold gate already executed");
  }
  if member < 0 || member >= gate.member_count {
    return _cc_err_gate("chaincrypto: member index " + convert.int_to_string(member) + " out of range 0.." + convert.int_to_string(gate.member_count - 1));
  }
  if chaincrypto_threshold_is_approved(gate, member) {
    return _cc_err_gate("chaincrypto: member " + convert.int_to_string(member) + " has already approved");
  }
  var approvals = _cc_copy_ints(&gate.approvals);
  approvals.push(member);
  return _cc_ok_gate(ChainThresholdGate{ threshold: gate.threshold; member_count: gate.member_count; approvals: approvals; executed: false; execution_nonce: gate.execution_nonce; executed_at: gate.executed_at; approvals_digest: gate.approvals_digest });
}

/// Execution gate. Requires the threshold to be met, requires `nonce` to be
/// exactly execution_nonce + 1 (stale or skipped nonces are replay attempts),
/// and may run once; the returned gate carries executed == true and the
/// execution metadata.
/// Params: gate - the current gate; now - caller-supplied execution tick;
/// nonce - the expected next execution nonce (1 for the first execution).
/// Returns: Ok(new gate) ready for chaincrypto_threshold_receipt.
/// Error case: Err("chaincrypto: threshold gate already executed (replay
/// rejected)"); Err("chaincrypto: execution nonce N does not match expected E
/// (replay rejected)"); Err("chaincrypto: approval count C is below threshold
/// M").
/// Complexity: O(approvals).
pub fn chaincrypto_threshold_execute(gate: &ChainThresholdGate, now: Int, nonce: Int) -> Result[ChainThresholdGate, Str] {
  if gate.executed {
    return _cc_err_gate("chaincrypto: threshold gate already executed (replay rejected)");
  }
  let expected = gate.execution_nonce + 1;
  if nonce != expected {
    return _cc_err_gate("chaincrypto: execution nonce " + convert.int_to_string(nonce) + " does not match expected " + convert.int_to_string(expected) + " (replay rejected)");
  }
  let have = gate.approvals.len();
  if have < gate.threshold {
    return _cc_err_gate("chaincrypto: approval count " + convert.int_to_string(have) + " is below threshold " + convert.int_to_string(gate.threshold));
  }
  let digest = _cc_digest(&gate.approvals);
  var approvals = _cc_copy_ints(&gate.approvals);
  return _cc_ok_gate(ChainThresholdGate{ threshold: gate.threshold; member_count: gate.member_count; approvals: approvals; executed: true; execution_nonce: nonce; executed_at: now; approvals_digest: digest });
}

/// Receipt of an executed gate: execution nonce, approval count, execution
/// tick and the opaque approvals digest.
/// Params: gate - an executed gate.
/// Returns: Ok(receipt).
/// Error case: Err("chaincrypto: threshold gate has not executed").
/// Complexity: O(1).
pub fn chaincrypto_threshold_receipt(gate: &ChainThresholdGate) -> Result[ChainExecutionReceipt, Str] {
  if !gate.executed {
    return _cc_err_receipt("chaincrypto: threshold gate has not executed");
  }
  return _cc_ok_receipt(ChainExecutionReceipt{ nonce: gate.execution_nonce; approval_count: gate.approvals.len(); executed_at: gate.executed_at; approvals_digest: gate.approvals_digest });
}

// --------------------------------------------------
//  Commit-reveal with timelock ticks
// --------------------------------------------------

/// Create a commit-reveal record. Rules: commit_tick >= 0, reveal_tick >
/// commit_tick, expiry_tick > reveal_tick; commit_hash must be a valid opaque
/// hash. The reveal window is [reveal_tick, expiry_tick).
/// Params: commit_hash - opaque committed value; commit_tick - commit time;
/// reveal_tick - first reveal tick; expiry_tick - first expired tick.
/// Returns: Ok(record) with revealed == false and refunded == false.
/// Error case: Err("chaincrypto: commitment hash H out of range
/// 0..2147483646"); Err("chaincrypto: commit tick T must be non-negative");
/// Err("chaincrypto: reveal tick R must be after commit tick C");
/// Err("chaincrypto: expiry tick E must be after reveal tick R").
/// Complexity: O(1).
pub fn chaincrypto_commit_reveal_new(commit_hash: Int, commit_tick: Int, reveal_tick: Int, expiry_tick: Int) -> Result[ChainCommitReveal, Str] {
  if !_cc_in_range(commit_hash) {
    return _cc_err_cr("chaincrypto: commitment hash " + convert.int_to_string(commit_hash) + " out of range 0..2147483646");
  }
  if commit_tick < 0 {
    return _cc_err_cr("chaincrypto: commit tick " + convert.int_to_string(commit_tick) + " must be non-negative");
  }
  if reveal_tick <= commit_tick {
    return _cc_err_cr("chaincrypto: reveal tick " + convert.int_to_string(reveal_tick) + " must be after commit tick " + convert.int_to_string(commit_tick));
  }
  if expiry_tick <= reveal_tick {
    return _cc_err_cr("chaincrypto: expiry tick " + convert.int_to_string(expiry_tick) + " must be after reveal tick " + convert.int_to_string(reveal_tick));
  }
  return _cc_ok_cr(ChainCommitReveal{ commit_hash: commit_hash; commit_tick: commit_tick; reveal_tick: reveal_tick; expiry_tick: expiry_tick; revealed: false; revealed_value: -1; reveal_at: -1; refunded: false; refund_at: -1 });
}

/// Phase at `now`: 0 = waiting (before reveal_tick), 1 = reveal
/// (reveal_tick <= now < expiry_tick), 2 = expired (now >= expiry_tick).
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_commit_reveal_phase(cr: &ChainCommitReveal, now: Int) -> Int {
  if now < cr.reveal_tick {
    return _CC_PHASE_WAITING;
  }
  if now < cr.expiry_tick {
    return _CC_PHASE_REVEAL;
  }
  return _CC_PHASE_EXPIRED;
}

/// Whether `now` is at or after expiry_tick.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_commit_reveal_expired(cr: &ChainCommitReveal, now: Int) -> Bool {
  return now >= cr.expiry_tick;
}

/// Reveal the committed value. Accepted only while not revealed, not
/// refunded, within [reveal_tick, expiry_tick), and only when `value` equals
/// the committed opaque hash (the caller hashes off-module). Returns the
/// updated record; the input is not mutated.
/// Params: cr - the record; now - caller-supplied tick; value - the revealed
/// opaque value.
/// Returns: Ok(updated record) with revealed == true.
/// Error case: Err("chaincrypto: commitment already revealed (replay
/// rejected)"); Err("chaincrypto: commitment was refunded"); Err("chaincrypto:
/// tick T is before reveal tick R (waiting)"); Err("chaincrypto: tick T is at
/// or after expiry tick E"); Err("chaincrypto: revealed value V does not match
/// commitment H").
/// Complexity: O(1).
pub fn chaincrypto_commit_reveal_reveal(cr: &ChainCommitReveal, now: Int, value: Int) -> Result[ChainCommitReveal, Str] {
  if cr.revealed {
    return _cc_err_cr("chaincrypto: commitment already revealed (replay rejected)");
  }
  if cr.refunded {
    return _cc_err_cr("chaincrypto: commitment was refunded");
  }
  if now < cr.reveal_tick {
    return _cc_err_cr("chaincrypto: tick " + convert.int_to_string(now) + " is before reveal tick " + convert.int_to_string(cr.reveal_tick) + " (waiting)");
  }
  if now >= cr.expiry_tick {
    return _cc_err_cr("chaincrypto: tick " + convert.int_to_string(now) + " is at or after expiry tick " + convert.int_to_string(cr.expiry_tick));
  }
  if value != cr.commit_hash {
    return _cc_err_cr("chaincrypto: revealed value " + convert.int_to_string(value) + " does not match commitment " + convert.int_to_string(cr.commit_hash));
  }
  return _cc_ok_cr(ChainCommitReveal{ commit_hash: cr.commit_hash; commit_tick: cr.commit_tick; reveal_tick: cr.reveal_tick; expiry_tick: cr.expiry_tick; revealed: true; revealed_value: value; reveal_at: now; refunded: false; refund_at: -1 });
}

/// Refund the commitment. Accepted only when not refunded, not revealed, and
/// `now >= expiry_tick`. Returns the updated record; the input is not mutated.
/// Params: cr - the record; now - caller-supplied tick.
/// Returns: Ok(updated record) with refunded == true.
/// Error case: Err("chaincrypto: commitment already refunded (replay
/// rejected)"); Err("chaincrypto: commitment already revealed");
/// Err("chaincrypto: tick T is before expiry tick E (not refundable)").
/// Complexity: O(1).
pub fn chaincrypto_commit_reveal_refund(cr: &ChainCommitReveal, now: Int) -> Result[ChainCommitReveal, Str] {
  if cr.refunded {
    return _cc_err_cr("chaincrypto: commitment already refunded (replay rejected)");
  }
  if cr.revealed {
    return _cc_err_cr("chaincrypto: commitment already revealed");
  }
  if now < cr.expiry_tick {
    return _cc_err_cr("chaincrypto: tick " + convert.int_to_string(now) + " is before expiry tick " + convert.int_to_string(cr.expiry_tick) + " (not refundable)");
  }
  return _cc_ok_cr(ChainCommitReveal{ commit_hash: cr.commit_hash; commit_tick: cr.commit_tick; reveal_tick: cr.reveal_tick; expiry_tick: cr.expiry_tick; revealed: false; revealed_value: -1; reveal_at: -1; refunded: true; refund_at: now });
}

/// Committed opaque hash.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_commit_reveal_commit_hash(cr: &ChainCommitReveal) -> Int {
  return cr.commit_hash;
}

/// Whether the commitment has been revealed.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_commit_reveal_revealed(cr: &ChainCommitReveal) -> Bool {
  return cr.revealed;
}

/// Whether the commitment has been refunded.
/// Error case: none. Complexity: O(1).
pub fn chaincrypto_commit_reveal_refunded(cr: &ChainCommitReveal) -> Bool {
  return cr.refunded;
}

/// Revealed value.
/// Params: cr - the record.
/// Returns: Ok(value), or Err when the commitment was never revealed.
/// Error case: Err("chaincrypto: commitment has not been revealed").
/// Complexity: O(1).
pub fn chaincrypto_commit_reveal_value(cr: &ChainCommitReveal) -> Result[Int, Str] {
  if !cr.revealed {
    return _cc_err_int("chaincrypto: commitment has not been revealed");
  }
  return _cc_ok_int(cr.revealed_value);
}
