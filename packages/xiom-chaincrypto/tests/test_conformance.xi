// XIOM -- xiom.chaincrypto conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers: the deterministic node mix and its range rules; the empty
// accumulator; append growth of count, root and root history; pinned roots
// for shapes 1..8 over the fixture leaves 1000 + 37*i; membership proof
// round-trips for all 7 leaves with pinned sibling counts; tampered leaf,
// root, sibling, direction, length and index rejection; structural proof
// errors; proof accessors against independently recomputed node values;
// m-of-n gate construction, duplicate-approval rejection, approval sets,
// threshold met; the execution gate (below-threshold, replay nonce, single
// execution, receipt); commit-reveal construction, phases, reveal timing and
// replay, refund timing and replay; determinism and order sensitivity; the
// error catalog with pinned messages.
//
// All inputs are built in-test; nothing reads files or the environment. Str
// comparisons go through compare.str_compare on typed locals; chain elements
// are bound to typed locals before use.

module chaincrypto_tests
use xiom.io; use xiom.test; use xiom.chaincrypto;
use xiom.string.compare;

// --------------------------------------------------
//  Result helpers
// --------------------------------------------------

fn str_is(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_acc_is(r: Result[ChainAccumulator, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_proof_is(r: Result[ChainProof, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_gate_is(r: Result[ChainThresholdGate, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_receipt_is(r: Result[ChainExecutionReceipt, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

fn err_cr_is(r: Result[ChainCommitReveal, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got = r.error;
  return str_is(got, want);
}

// --------------------------------------------------
//  Fixtures and builders
// --------------------------------------------------

// Fixture leaves: 1000, 1037, 1074, ... (1000 + 37 * i).
fn fixture_leaves(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(1000 + i * 37);
    i = i + 1;
  }
  return v;
}

// Append every leaf of `leaves` in order; on an unexpected Err the partial
// accumulator is returned so the following assertions fail loudly.
fn acc_of(leaves: &Vec[Int]) -> ChainAccumulator {
  var acc = chaincrypto_accumulator_new();
  var i = 0;
  while i < leaves.len() {
    let x = leaves[i];
    let step = chaincrypto_accumulator_append(&acc, x);
    if step.is_ok {
      acc = step.value;
    } else {
      return acc;
    }
    i = i + 1;
  }
  return acc;
}

// Public mix, unwrapped for independent recomputation.
fn combine_of(left: Int, right: Int) -> Int {
  let res = chaincrypto_node_combine(left, right);
  if res.is_ok {
    return res.value;
  }
  return -1;
}

// Independent promotion-tree root recomputation through the public mix.
fn mirror_root(leaves: &Vec[Int]) -> Int {
  let n = leaves.len();
  if n == 0 {
    return -1;
  }
  var nodes = Vec[Int].new();
  var i = 0;
  while i < n {
    let x = leaves[i];
    nodes.push(x);
    i = i + 1;
  }
  var count = n;
  var start = 0;
  while count > 1 {
    var j = 0;
    while j + 1 < count {
      let a = nodes[start + j];
      let b = nodes[start + j + 1];
      nodes.push(combine_of(a, b));
      j = j + 2;
    }
    if j < count {
      let lone = nodes[start + j];
      nodes.push(lone);
    }
    start = start + count;
    if count % 2 == 0 {
      count = count / 2;
    } else {
      count = count / 2 + 1;
    }
  }
  return nodes[nodes.len() - 1];
}

fn proof_of(acc: &ChainAccumulator, idx: Int) -> ChainProof {
  let res = chaincrypto_accumulator_proof(acc, idx);
  if res.is_ok {
    return res.value;
  }
  var empty = Vec[Int].new();
  return proof_literal(0, 1, -1, empty, Vec[Int].new());
}

fn proof_literal(li: Int, lc: Int, root: Int, sibs: Vec[Int], dirs: Vec[Int]) -> ChainProof {
  return ChainProof{ leaf_index: li; leaf_count: lc; root: root; siblings: sibs; directions: dirs };
}

fn verifies(p: &ChainProof, leaf_hash: Int, root: Int) -> Bool {
  let res = chaincrypto_proof_verify(p, leaf_hash, root);
  if !res.is_ok {
    return false;
  }
  return res.value;
}

fn verify_err(p: &ChainProof, leaf_hash: Int, root: Int, want: Str) -> Bool {
  let res = chaincrypto_proof_verify(p, leaf_hash, root);
  if res.is_ok {
    return false;
  }
  let got = res.error;
  return str_is(got, want);
}

fn sibs_of(p: &ChainProof) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = chaincrypto_proof_sibling_count(p);
  var i = 0;
  while i < n {
    let s = chaincrypto_proof_sibling(p, i);
    if s.is_ok {
      out.push(s.value);
    }
    i = i + 1;
  }
  return out;
}

fn dirs_of(p: &ChainProof) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = chaincrypto_proof_sibling_count(p);
  var i = 0;
  while i < n {
    let d = chaincrypto_proof_direction(p, i);
    if d.is_ok {
      out.push(d.value);
    }
    i = i + 1;
  }
  return out;
}

fn take_ints(v: &Vec[Int], n: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < n {
    let x = v[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

fn set_int(v: Vec[Int], pos: Int, x: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(x);
    } else {
      let old = v[i];
      out.push(old);
    }
    i = i + 1;
  }
  return out;
}

fn gate_of(m: Int, n: Int) -> ChainThresholdGate {
  let res = chaincrypto_threshold_new(m, n);
  if res.is_ok {
    return res.value;
  }
  var empty = Vec[Int].new();
  return ChainThresholdGate{ threshold: m; member_count: n; approvals: empty; executed: false; execution_nonce: 0; executed_at: -1; approvals_digest: -1 };
}

fn approve_or(g: &ChainThresholdGate, member: Int) -> ChainThresholdGate {
  let res = chaincrypto_threshold_approve(g, member);
  if res.is_ok {
    return res.value;
  }
  return gate_of(g.threshold, g.member_count);
}

fn cr_of(hash: Int, commit_tick: Int, reveal_tick: Int, expiry_tick: Int) -> ChainCommitReveal {
  let res = chaincrypto_commit_reveal_new(hash, commit_tick, reveal_tick, expiry_tick);
  if res.is_ok {
    return res.value;
  }
  return ChainCommitReveal{ commit_hash: hash; commit_tick: commit_tick; reveal_tick: reveal_tick; expiry_tick: expiry_tick; revealed: false; revealed_value: -1; reveal_at: -1; refunded: false; refund_at: -1 };
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = chaincrypto_empty_root() == -1;
  if combine_of(1, 2) != 70 { ok = false; }
  if combine_of(2, 1) != 40 { ok = false; }
  if combine_of(1, 2) == combine_of(2, 1) { ok = false; }
  if !err_int_is(chaincrypto_node_combine(-1, 5), "chaincrypto: combine left hash -1 out of range 0..2147483646") { ok = false; }
  if !err_int_is(chaincrypto_node_combine(5, 2147483647), "chaincrypto: combine right hash 2147483647 out of range 0..2147483646") { ok = false; }
  return assert(ok, "node mix is deterministic, order-sensitive and range-checked");
}

fn t2() -> TestResult {
  let acc = chaincrypto_accumulator_new();
  var ok = chaincrypto_accumulator_leaf_count(&acc) == 0;
  if chaincrypto_accumulator_root(&acc) != -1 { ok = false; }
  let rec = chaincrypto_accumulator_record(&acc);
  if rec.leaf_count != 0 { ok = false; }
  if rec.root != -1 { ok = false; }
  if chaincrypto_accumulator_history_len(&acc) != 0 { ok = false; }
  if !err_proof_is(chaincrypto_accumulator_proof(&acc, 0), "chaincrypto: empty accumulator has no membership proofs") { ok = false; }
  if !err_int_is(chaincrypto_accumulator_leaf(&acc, 0), "chaincrypto: leaf index 0 out of range 0..-1") { ok = false; }
  if !err_int_is(chaincrypto_accumulator_history_count(&acc, 0), "chaincrypto: history index 0 out of range 0..-1") { ok = false; }
  if !err_int_is(chaincrypto_accumulator_history_root(&acc, 0), "chaincrypto: history index 0 out of range 0..-1") { ok = false; }
  return assert(ok, "empty accumulator: root -1, no history, no proofs");
}

fn t3() -> TestResult {
  let acc0 = chaincrypto_accumulator_new();
  var ok = err_acc_is(chaincrypto_accumulator_append(&acc0, -1), "chaincrypto: leaf hash -1 out of range 0..2147483646");
  if !err_acc_is(chaincrypto_accumulator_append(&acc0, 2147483647), "chaincrypto: leaf hash 2147483647 out of range 0..2147483646") { ok = false; }
  let leaves = fixture_leaves(3);
  let acc = acc_of(&leaves);
  if chaincrypto_accumulator_leaf_count(&acc) != 3 { ok = false; }
  if chaincrypto_accumulator_root(&acc) != mirror_root(&leaves) { ok = false; }
  if chaincrypto_accumulator_history_len(&acc) != 3 { ok = false; }
  let c0 = chaincrypto_accumulator_history_count(&acc, 0);
  if !c0.is_ok { ok = false; } else { if c0.value != 1 { ok = false; } }
  let c1 = chaincrypto_accumulator_history_count(&acc, 1);
  if !c1.is_ok { ok = false; } else { if c1.value != 2 { ok = false; } }
  let c2 = chaincrypto_accumulator_history_count(&acc, 2);
  if !c2.is_ok { ok = false; } else { if c2.value != 3 { ok = false; } }
  let r2 = chaincrypto_accumulator_history_root(&acc, 2);
  if !r2.is_ok { ok = false; } else { if r2.value != chaincrypto_accumulator_root(&acc) { ok = false; } }
  let l0 = chaincrypto_accumulator_leaf(&acc, 0);
  if !l0.is_ok { ok = false; } else { if l0.value != 1000 { ok = false; } }
  let l2 = chaincrypto_accumulator_leaf(&acc, 2);
  if !l2.is_ok { ok = false; } else { if l2.value != 1074 { ok = false; } }
  if !err_int_is(chaincrypto_accumulator_leaf(&acc, 3), "chaincrypto: leaf index 3 out of range 0..2") { ok = false; }
  if !err_int_is(chaincrypto_accumulator_history_count(&acc, -1), "chaincrypto: history index -1 out of range 0..2") { ok = false; }
  if !err_int_is(chaincrypto_accumulator_history_root(&acc, 3), "chaincrypto: history index 3 out of range 0..2") { ok = false; }
  return assert(ok, "append grows count, root history and range-checked accessors");
}

fn t4() -> TestResult {
  var want = Vec[Int].new();
  want.push(-1);
  want.push(1000);
  want.push(33154);
  want.push(66455);
  want.push(1134343);
  want.push(1169938);
  want.push(2308940);
  want.push(3483499);
  want.push(40997095);
  var ok = true;
  var n = 0;
  while n <= 8 {
    let leaves = fixture_leaves(n);
    let acc = acc_of(&leaves);
    if chaincrypto_accumulator_leaf_count(&acc) != n { ok = false; }
    let expected = want[n];
    if chaincrypto_accumulator_root(&acc) != expected { ok = false; }
    if mirror_root(&leaves) != expected { ok = false; }
    n = n + 1;
  }
  return assert(ok, "pinned roots for sizes 0..8 over fixture leaves 1000+37i");
}

fn t5() -> TestResult {
  let leaves = fixture_leaves(7);
  let acc = acc_of(&leaves);
  let root = chaincrypto_accumulator_root(&acc);
  var want = Vec[Int].new();
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(3);
  want.push(2);
  var ok = true;
  var i = 0;
  while i < 7 {
    let p = proof_of(&acc, i);
    let expected = want[i];
    if chaincrypto_proof_sibling_count(&p) != expected { ok = false; }
    if chaincrypto_proof_leaf_index(&p) != i { ok = false; }
    if chaincrypto_proof_leaf_count(&p) != 7 { ok = false; }
    if chaincrypto_proof_root(&p) != root { ok = false; }
    let leaf = leaves[i];
    if !verifies(&p, leaf, root) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "membership proofs round-trip for all 7 leaves with pinned shapes");
}

fn t6() -> TestResult {
  let leaves = fixture_leaves(7);
  let acc = acc_of(&leaves);
  let root = chaincrypto_accumulator_root(&acc);
  let p = proof_of(&acc, 3);
  let leaf3 = leaves[3];
  var ok = verifies(&p, leaf3, root);
  if verifies(&p, leaf3 + 1, root) { ok = false; }
  if verifies(&p, leaf3, root + 1) { ok = false; }
  var sibs = sibs_of(&p);
  var dirs = dirs_of(&p);
  let leaf0 = leaves[0];
  let tampered = proof_literal(3, 7, root, set_int(sibs, 0, leaf0), dirs);
  if verifies(&tampered, leaf3, root) { ok = false; }
  let d0 = dirs[0];
  let flipped = proof_literal(3, 7, root, sibs, set_int(dirs, 0, 1 - d0));
  if verifies(&flipped, leaf3, root) { ok = false; }
  let short = proof_literal(3, 7, root, take_ints(sibs, 1), take_ints(dirs, 1));
  if verifies(&short, leaf3, root) { ok = false; }
  var extra_s = take_ints(sibs, 3);
  extra_s.push(7);
  var extra_d = take_ints(dirs, 3);
  extra_d.push(1);
  let stretched = proof_literal(3, 7, root, extra_s, extra_d);
  if verifies(&stretched, leaf3, root) { ok = false; }
  let leaf4 = leaves[4];
  if verifies(&p, leaf4, root) { ok = false; }
  if verifies(&p, leaf3, -1) { ok = false; }
  if !verify_err(&p, -1, root, "chaincrypto: proof leaf hash -1 out of range 0..2147483646") { ok = false; }
  let bad_dir = proof_literal(3, 7, root, sibs, set_int(dirs, 0, 2));
  if !verify_err(&bad_dir, leaf3, root, "chaincrypto: proof direction 0 is 2 (must be 0 or 1)") { ok = false; }
  let mismatch = proof_literal(3, 7, root, sibs, take_ints(dirs, 2));
  if !verify_err(&mismatch, leaf3, root, "chaincrypto: proof sibling count 3 does not match direction count 2") { ok = false; }
  return assert(ok, "tampered leaf, root, sibling, direction, length and index are rejected");
}

fn t7() -> TestResult {
  let leaves = fixture_leaves(7);
  let acc = acc_of(&leaves);
  let root = chaincrypto_accumulator_root(&acc);
  var ok = true;
  let pzero = proof_literal(0, 0, root, Vec[Int].new(), Vec[Int].new());
  if !verify_err(&pzero, 1000, root, "chaincrypto: proof leaf count 0 must be positive") { ok = false; }
  let pneg = proof_literal(0, -2, root, Vec[Int].new(), Vec[Int].new());
  if !verify_err(&pneg, 1000, root, "chaincrypto: proof leaf count -2 must be positive") { ok = false; }
  let pidx = proof_literal(7, 7, root, Vec[Int].new(), Vec[Int].new());
  if !verify_err(&pidx, 1000, root, "chaincrypto: proof leaf index 7 out of range 0..6") { ok = false; }
  let pnegidx = proof_literal(-1, 7, root, Vec[Int].new(), Vec[Int].new());
  if !verify_err(&pnegidx, 1000, root, "chaincrypto: proof leaf index -1 out of range 0..6") { ok = false; }
  let pshort = proof_literal(0, 7, root, Vec[Int].new(), Vec[Int].new());
  if verifies(&pshort, 1000, root) { ok = false; }
  return assert(ok, "structural proof errors are Err; missing siblings are Ok(false)");
}

fn t8() -> TestResult {
  let leaves = fixture_leaves(7);
  let acc = acc_of(&leaves);
  let p0 = proof_of(&acc, 0);
  var ok = chaincrypto_proof_sibling_count(&p0) == 3;
  let l1 = leaves[1];
  let c23 = combine_of(leaves[2], leaves[3]);
  let c45 = combine_of(leaves[4], leaves[5]);
  let c456 = combine_of(c45, leaves[6]);
  let s0 = chaincrypto_proof_sibling(&p0, 0);
  if !s0.is_ok { ok = false; } else { if s0.value != l1 { ok = false; } }
  let s1 = chaincrypto_proof_sibling(&p0, 1);
  if !s1.is_ok { ok = false; } else { if s1.value != c23 { ok = false; } }
  let s2 = chaincrypto_proof_sibling(&p0, 2);
  if !s2.is_ok { ok = false; } else { if s2.value != c456 { ok = false; } }
  let d0 = chaincrypto_proof_direction(&p0, 0);
  if !d0.is_ok { ok = false; } else { if d0.value != 1 { ok = false; } }
  let d2 = chaincrypto_proof_direction(&p0, 2);
  if !d2.is_ok { ok = false; } else { if d2.value != 1 { ok = false; } }
  let p6 = proof_of(&acc, 6);
  if chaincrypto_proof_sibling_count(&p6) != 2 { ok = false; }
  let c01 = combine_of(leaves[0], leaves[1]);
  let c0123 = combine_of(c01, c23);
  let t0 = chaincrypto_proof_sibling(&p6, 0);
  if !t0.is_ok { ok = false; } else { if t0.value != c45 { ok = false; } }
  let t1 = chaincrypto_proof_sibling(&p6, 1);
  if !t1.is_ok { ok = false; } else { if t1.value != c0123 { ok = false; } }
  let e0 = chaincrypto_proof_direction(&p6, 0);
  if !e0.is_ok { ok = false; } else { if e0.value != 0 { ok = false; } }
  if !err_int_is(chaincrypto_proof_sibling(&p0, -1), "chaincrypto: sibling index -1 out of range 0..2") { ok = false; }
  if !err_int_is(chaincrypto_proof_sibling(&p0, 3), "chaincrypto: sibling index 3 out of range 0..2") { ok = false; }
  if !err_int_is(chaincrypto_proof_direction(&p0, 3), "chaincrypto: direction index 3 out of range 0..2") { ok = false; }
  return assert(ok, "proof accessors match independently recomputed node values");
}

fn t9() -> TestResult {
  var ok = err_gate_is(chaincrypto_threshold_new(0, 3), "chaincrypto: threshold must be at least 1 (got 0)");
  if !err_gate_is(chaincrypto_threshold_new(3, 0), "chaincrypto: member count must be at least 1 (got 0)") { ok = false; }
  if !err_gate_is(chaincrypto_threshold_new(4, 3), "chaincrypto: threshold 4 exceeds member count 3") { ok = false; }
  let g = gate_of(2, 3);
  if g.threshold != 2 { ok = false; }
  if g.member_count != 3 { ok = false; }
  if chaincrypto_threshold_approval_count(&g) != 0 { ok = false; }
  if chaincrypto_threshold_is_approved(&g, 0) { ok = false; }
  if chaincrypto_threshold_met(&g) { ok = false; }
  if g.executed { ok = false; }
  if g.execution_nonce != 0 { ok = false; }
  if g.executed_at != -1 { ok = false; }
  if g.approvals_digest != -1 { ok = false; }
  let approvals = chaincrypto_threshold_approvals(&g);
  if approvals.len() != 0 { ok = false; }
  return assert(ok, "threshold gate construction validates m-of-n and starts fresh");
}

fn t10() -> TestResult {
  let g0 = gate_of(2, 3);
  let g1 = approve_or(&g0, 2);
  let g2 = approve_or(&g1, 0);
  var ok = chaincrypto_threshold_approval_count(&g2) == 2;
  if !chaincrypto_threshold_is_approved(&g2, 2) { ok = false; }
  if !chaincrypto_threshold_is_approved(&g2, 0) { ok = false; }
  if chaincrypto_threshold_is_approved(&g2, 1) { ok = false; }
  if !chaincrypto_threshold_met(&g2) { ok = false; }
  if !err_gate_is(chaincrypto_threshold_approve(&g2, 2), "chaincrypto: member 2 has already approved") { ok = false; }
  if !err_gate_is(chaincrypto_threshold_approve(&g2, 3), "chaincrypto: member index 3 out of range 0..2") { ok = false; }
  if !err_gate_is(chaincrypto_threshold_approve(&g2, -1), "chaincrypto: member index -1 out of range 0..2") { ok = false; }
  let approvals = chaincrypto_threshold_approvals(&g2);
  if approvals.len() != 2 { ok = false; } else {
    let a0 = approvals[0];
    let a1 = approvals[1];
    if a0 != 2 { ok = false; }
    if a1 != 0 { ok = false; }
  }
  let g3 = approve_or(&g0, 0);
  if chaincrypto_threshold_met(&g3) { ok = false; }
  let g4 = approve_or(&g3, 1);
  if !chaincrypto_threshold_met(&g4) { ok = false; }
  return assert(ok, "duplicate approvals rejected; approval set and met gate");
}

fn t11() -> TestResult {
  let g0 = gate_of(2, 3);
  let g1 = approve_or(&g0, 0);
  var ok = err_gate_is(chaincrypto_threshold_execute(&g1, 50, 1), "chaincrypto: approval count 1 is below threshold 2");
  let g2 = approve_or(&g1, 2);
  if !err_gate_is(chaincrypto_threshold_execute(&g2, 50, 2), "chaincrypto: execution nonce 2 does not match expected 1 (replay rejected)") { ok = false; }
  let res = chaincrypto_threshold_execute(&g2, 50, 1);
  if !res.is_ok {
    return assert(false, "execution gate: threshold, nonce, single execution and receipt");
  }
  let done = res.value;
  if !done.executed { ok = false; }
  if done.execution_nonce != 1 { ok = false; }
  if done.executed_at != 50 { ok = false; }
  if done.approvals_digest != 76 { ok = false; }
  if !err_gate_is(chaincrypto_threshold_execute(&done, 60, 2), "chaincrypto: threshold gate already executed (replay rejected)") { ok = false; }
  if !err_gate_is(chaincrypto_threshold_approve(&done, 1), "chaincrypto: threshold gate already executed") { ok = false; }
  let receipt_res = chaincrypto_threshold_receipt(&done);
  if !receipt_res.is_ok { ok = false; } else {
    let r = receipt_res.value;
    if r.nonce != 1 { ok = false; }
    if r.approval_count != 2 { ok = false; }
    if r.executed_at != 50 { ok = false; }
    if r.approvals_digest != 76 { ok = false; }
  }
  if !err_receipt_is(chaincrypto_threshold_receipt(&g2), "chaincrypto: threshold gate has not executed") { ok = false; }
  return assert(ok, "execution gate: threshold, nonce, single execution and receipt");
}

fn t12() -> TestResult {
  var ok = err_cr_is(chaincrypto_commit_reveal_new(-1, 0, 10, 20), "chaincrypto: commitment hash -1 out of range 0..2147483646");
  if !err_cr_is(chaincrypto_commit_reveal_new(5, -1, 10, 20), "chaincrypto: commit tick -1 must be non-negative") { ok = false; }
  if !err_cr_is(chaincrypto_commit_reveal_new(5, 10, 10, 20), "chaincrypto: reveal tick 10 must be after commit tick 10") { ok = false; }
  if !err_cr_is(chaincrypto_commit_reveal_new(5, 10, 20, 20), "chaincrypto: expiry tick 20 must be after reveal tick 20") { ok = false; }
  let cr = cr_of(12345, 0, 10, 20);
  if chaincrypto_commit_reveal_commit_hash(&cr) != 12345 { ok = false; }
  if chaincrypto_commit_reveal_revealed(&cr) { ok = false; }
  if chaincrypto_commit_reveal_refunded(&cr) { ok = false; }
  if chaincrypto_commit_reveal_expired(&cr, 19) { ok = false; }
  if !err_int_is(chaincrypto_commit_reveal_value(&cr), "chaincrypto: commitment has not been revealed") { ok = false; }
  return assert(ok, "commit-reveal construction validates hash and tick ordering");
}

fn t13() -> TestResult {
  let cr = cr_of(12345, 0, 10, 20);
  var ok = chaincrypto_commit_reveal_phase(&cr, 0) == 0;
  if chaincrypto_commit_reveal_phase(&cr, 9) != 0 { ok = false; }
  if chaincrypto_commit_reveal_phase(&cr, 10) != 1 { ok = false; }
  if chaincrypto_commit_reveal_phase(&cr, 19) != 1 { ok = false; }
  if chaincrypto_commit_reveal_phase(&cr, 20) != 2 { ok = false; }
  if chaincrypto_commit_reveal_phase(&cr, 999) != 2 { ok = false; }
  if chaincrypto_commit_reveal_expired(&cr, 19) { ok = false; }
  if !chaincrypto_commit_reveal_expired(&cr, 20) { ok = false; }
  return assert(ok, "commit phase, reveal window and expiry boundaries");
}

fn t14() -> TestResult {
  let cr = cr_of(12345, 0, 10, 20);
  var ok = err_cr_is(chaincrypto_commit_reveal_reveal(&cr, 9, 12345), "chaincrypto: tick 9 is before reveal tick 10 (waiting)");
  if !err_cr_is(chaincrypto_commit_reveal_reveal(&cr, 10, 999), "chaincrypto: revealed value 999 does not match commitment 12345") { ok = false; }
  let opened = chaincrypto_commit_reveal_reveal(&cr, 10, 12345);
  if !opened.is_ok {
    return assert(false, "reveal timing: waiting, mismatch, success, replay and expiry");
  }
  let rv = opened.value;
  if !rv.revealed { ok = false; }
  let val = chaincrypto_commit_reveal_value(&rv);
  if !val.is_ok { ok = false; } else { if val.value != 12345 { ok = false; } }
  if !err_cr_is(chaincrypto_commit_reveal_reveal(&rv, 11, 12345), "chaincrypto: commitment already revealed (replay rejected)") { ok = false; }
  let cr2 = cr_of(777, 0, 10, 20);
  if !err_cr_is(chaincrypto_commit_reveal_reveal(&cr2, 20, 777), "chaincrypto: tick 20 is at or after expiry tick 20") { ok = false; }
  let late = chaincrypto_commit_reveal_reveal(&cr2, 19, 777);
  if !late.is_ok { ok = false; } else {
    let lv = late.value;
    if !lv.revealed { ok = false; }
  }
  return assert(ok, "reveal timing: waiting, mismatch, success, replay and expiry");
}

fn t15() -> TestResult {
  let cr = cr_of(12345, 0, 10, 20);
  var ok = err_cr_is(chaincrypto_commit_reveal_refund(&cr, 19), "chaincrypto: tick 19 is before expiry tick 20 (not refundable)");
  let refunded = chaincrypto_commit_reveal_refund(&cr, 20);
  if !refunded.is_ok {
    return assert(false, "refund only after expiry, once, and never after a reveal");
  }
  let rf = refunded.value;
  if !rf.refunded { ok = false; }
  if !chaincrypto_commit_reveal_refunded(&rf) { ok = false; }
  if !err_cr_is(chaincrypto_commit_reveal_refund(&rf, 21), "chaincrypto: commitment already refunded (replay rejected)") { ok = false; }
  if !err_cr_is(chaincrypto_commit_reveal_reveal(&rf, 20, 12345), "chaincrypto: commitment was refunded") { ok = false; }
  let revealed = chaincrypto_commit_reveal_reveal(&cr, 10, 12345);
  if !revealed.is_ok { ok = false; } else {
    let rv = revealed.value;
    if !err_cr_is(chaincrypto_commit_reveal_refund(&rv, 20), "chaincrypto: commitment already revealed") { ok = false; }
  }
  return assert(ok, "refund only after expiry, once, and never after a reveal");
}

fn t16() -> TestResult {
  let leaves = fixture_leaves(5);
  let a = acc_of(&leaves);
  let b = acc_of(&leaves);
  var ok = chaincrypto_accumulator_root(&a) == chaincrypto_accumulator_root(&b);
  var i = 0;
  while i < 5 {
    let ra = chaincrypto_accumulator_history_root(&a, i);
    let rb = chaincrypto_accumulator_history_root(&b, i);
    if !ra.is_ok { ok = false; } else {
      if !rb.is_ok { ok = false; } else { if ra.value != rb.value { ok = false; } }
    }
    let prefix = fixture_leaves(i + 1);
    let pa = acc_of(&prefix);
    if !ra.is_ok { ok = false; } else { if ra.value != chaincrypto_accumulator_root(&pa) { ok = false; } }
    i = i + 1;
  }
  var swapped = fixture_leaves(5);
  swapped = set_int(swapped, 0, 1185);
  swapped = set_int(swapped, 4, 1000);
  let c = acc_of(&swapped);
  if chaincrypto_accumulator_root(&c) == chaincrypto_accumulator_root(&a) { ok = false; }
  let p1 = proof_of(&a, 2);
  let p2 = proof_of(&b, 2);
  let s1 = sibs_of(&p1);
  let s2 = sibs_of(&p2);
  if s1.len() != s2.len() { ok = false; } else {
    var j = 0;
    while j < s1.len() {
      let x = s1[j];
      let y = s2[j];
      if x != y { ok = false; }
      j = j + 1;
    }
  }
  return assert(ok, "roots are deterministic, history tracks prefixes, leaf order matters");
}

fn t17() -> TestResult {
  var ok = true;
  var n = 1;
  while n <= 8 {
    let leaves = fixture_leaves(n);
    let acc = acc_of(&leaves);
    if chaincrypto_accumulator_leaf_count(&acc) != n { ok = false; }
    if chaincrypto_accumulator_history_len(&acc) != n { ok = false; }
    if chaincrypto_accumulator_root(&acc) != mirror_root(&leaves) { ok = false; }
    let last = chaincrypto_accumulator_history_root(&acc, n - 1);
    if !last.is_ok { ok = false; } else { if last.value != chaincrypto_accumulator_root(&acc) { ok = false; } }
    let ln = chaincrypto_accumulator_leaf(&acc, n - 1);
    if !ln.is_ok { ok = false; } else { if ln.value != 1000 + 37 * (n - 1) { ok = false; } }
    n = n + 1;
  }
  let l5 = fixture_leaves(5);
  let a5 = acc_of(&l5);
  if chaincrypto_proof_sibling_count(&proof_of(&a5, 4)) != 1 { ok = false; }
  let l3 = fixture_leaves(3);
  let a3 = acc_of(&l3);
  if chaincrypto_proof_sibling_count(&proof_of(&a3, 2)) != 1 { ok = false; }
  let l6 = fixture_leaves(6);
  let a6 = acc_of(&l6);
  if chaincrypto_proof_sibling_count(&proof_of(&a6, 5)) != 2 { ok = false; }
  return assert(ok, "shapes 1..8 plus promoted-leaf proof sizes");
}

fn t18() -> TestResult {
  let empty = chaincrypto_accumulator_new();
  var ok = err_acc_is(chaincrypto_accumulator_append(&empty, 2147483647), "chaincrypto: leaf hash 2147483647 out of range 0..2147483646");
  if !err_int_is(chaincrypto_node_combine(2147483647, 0), "chaincrypto: combine left hash 2147483647 out of range 0..2147483646") { ok = false; }
  if !err_proof_is(chaincrypto_accumulator_proof(&empty, 0), "chaincrypto: empty accumulator has no membership proofs") { ok = false; }
  if !err_gate_is(chaincrypto_threshold_new(4, 3), "chaincrypto: threshold 4 exceeds member count 3") { ok = false; }
  if !err_cr_is(chaincrypto_commit_reveal_new(5, 10, 10, 20), "chaincrypto: reveal tick 10 must be after commit tick 10") { ok = false; }
  let cr = cr_of(777, 0, 10, 20);
  if !err_cr_is(chaincrypto_commit_reveal_reveal(&cr, 10, 778), "chaincrypto: revealed value 778 does not match commitment 777") { ok = false; }
  return assert(ok, "error catalog messages are pinned");
}

fn t19() -> TestResult {
  let g0 = gate_of(1, 2);
  let a0 = approve_or(&g0, 0);
  let e0 = chaincrypto_threshold_execute(&a0, 5, 1);
  var ok = true;
  if !e0.is_ok { ok = false; } else {
    let done0 = e0.value;
    if done0.approvals_digest != 7 { ok = false; }
  }
  let g1 = gate_of(1, 2);
  let a1 = approve_or(&g1, 1);
  let e1 = chaincrypto_threshold_execute(&a1, 6, 1);
  if !e1.is_ok { ok = false; } else {
    let done1 = e1.value;
    if done1.approvals_digest != 38 { ok = false; }
  }
  return assert(ok, "approval identity changes the opaque execution digest");
}

fn main() -> Int {
  io.println("=== xiom.chaincrypto conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.chaincrypto: all tests passed");
  } else {
    io.println("xiom.chaincrypto: tests failed");
  }
  return failed;
}
