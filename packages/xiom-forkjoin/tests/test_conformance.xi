// XIOM -- xiom.forkjoin conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.forkjoin deterministic fork/join model
// against its documented split, combine, deque and error semantics.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are built in-test. All Str equality goes through str_compare
// (`==` on Str values read from Vec[Str] elements lowers to a pointer
// comparison). Vec[Int] element reads use a typed `let`. Read-only operations
// on mutable fixtures are wrapped in small helpers that take `&mut`, so a
// `&local` read call is never followed by a `&mut local` call in the same
// function body (advisory E001); each wrapper calls the real `&`-based API.
// Outcome classifiers (int_ok_is / int_err_is / pop_of / steal_of) turn
// Result/Option outcomes into small values so the checks stay branch-free.
//
// Worked split expectations used below (rule: split at mid = lo + (hi-lo)/2
// while size > t; leaves enumerated left to right):
//   n=9,  t=4 -> [0,4) [4,6) [6,9)          nodes 5, leaves 3, depth 2
//   n=10, t=3 -> [0,2) [2,5) [5,7) [7,10)   nodes 7, leaves 4, depth 2
//   n=16, t=1 -> sixteen singletons         nodes 31, leaves 16, depth 4
//   n=8,  t=3 -> [0,2) [2,4) [4,6) [6,8)    nodes 7, leaves 4, depth 2
//   n=5,  t=2 -> [0,2) [2,3) [3,5)          nodes 5, leaves 3, depth 2
// Leaf node ids (BFS numbering): n=9/t=4 -> 1,3,4 ; n=10/t=3 -> 3,4,5,6.

module forkjoin_tests
use xiom.io; use xiom.test; use xiom.forkjoin;
use xiom.string.compare;

const _NO_MAX: Int = -999999;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn int_at(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let x: Int = v[i];
  return x == want;
}

fn vec_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

fn empty_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn vec1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn vec2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn vec4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn chunks_of(a: Vec[Int], b: Vec[Int], c: Vec[Int], d: Vec[Int]) -> Vec[Vec[Int]] {
  var out = Vec[Vec[Int]].new();
  out.push(a);
  out.push(b);
  out.push(c);
  out.push(d);
  return out;
}

// Fixtures: the Err branch is unreachable for the valid inputs the tests
// pass, but the functions must still return a value.

fn empty_tree() -> ForkTree {
  return ForkTree{
    n: 0;
    threshold: 0;
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
}

fn tree_of(n: Int, t: Int) -> ForkTree {
  match fdj_tree_build(n, t) {
    Ok(tr) => { return tr; },
    Err(_) => { return empty_tree(); },
  }
}

fn empty_ranges() -> LeafRanges {
  return LeafRanges{ lo: Vec[Int].new(); hi: Vec[Int].new(); };
}

fn ranges_of(n: Int, t: Int) -> LeafRanges {
  match fdj_split_leaves(n, t) {
    Ok(r) => { return r; },
    Err(_) => { return empty_ranges(); },
  }
}

fn build_err_is(n: Int, t: Int, want: Str) -> Bool {
  match fdj_tree_build(n, t) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn limited_err_is(n: Int, t: Int, md: Int, want: Str) -> Bool {
  match fdj_tree_build_limited(n, t, md) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn split_err_is(n: Int, t: Int, want: Str) -> Bool {
  match fdj_split_leaves(n, t) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Result[Int, Str] classifiers.

fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn int_err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn max_of(results: &Vec[Int]) -> Int {
  match fdj_combine_max(results) {
    Some(x) => { return x; },
    None => { return _NO_MAX; },
  }
  return _NO_MAX;
}

fn max_none(results: &Vec[Int]) -> Bool {
  match fdj_combine_max(results) {
    Some(_) => { return false; },
    None => { return true; },
  }
  return false;
}

// Read-only tree/ranges/deque accessors routed through `&mut` (advisory E001).

fn tcheck_of(t: &mut ForkTree) -> Bool { return fdj_tree_check(t); }
fn tn_of(t: &mut ForkTree) -> Int { return fdj_tree_n(t); }
fn tthreshold_of(t: &mut ForkTree) -> Int { return fdj_tree_threshold(t); }
fn tnodes_of(t: &mut ForkTree) -> Int { return fdj_tree_node_count(t); }
fn tleaves_of(t: &mut ForkTree) -> Int { return fdj_tree_leaf_count(t); }
fn tdepth_of(t: &mut ForkTree) -> Int { return fdj_tree_max_depth(t); }
fn tleaf_node_of(t: &mut ForkTree, i: Int) -> Int { return fdj_tree_leaf_node(t, i); }
fn tleaf_lo_of(t: &mut ForkTree, i: Int) -> Int { return fdj_tree_leaf_lo(t, i); }
fn tleaf_hi_of(t: &mut ForkTree, i: Int) -> Int { return fdj_tree_leaf_hi(t, i); }
fn tresult_of(t: &mut ForkTree, node: Int) -> Result[Int, Str] { return fdj_tree_result(t, node); }
fn tset_result_of(t: &mut ForkTree, node: Int, v: Int) -> Result[Int, Str] { return fdj_tree_set_result(t, node, v); }
fn tleaf_results_of(t: &mut ForkTree) -> Vec[Int] { return fdj_tree_leaf_results(t); }
fn treduce_sum_of(t: &mut ForkTree) -> Result[Int, Str] { return fdj_tree_reduce_sum(t); }
fn treduce_max_of(t: &mut ForkTree) -> Result[Int, Str] { return fdj_tree_reduce_max(t); }

fn rcount_of(r: &mut LeafRanges) -> Int { return fdj_leaf_count(r); }
fn rlo_of(r: &mut LeafRanges, i: Int) -> Int { return fdj_leaf_lo(r, i); }
fn rhi_of(r: &mut LeafRanges, i: Int) -> Int { return fdj_leaf_hi(r, i); }
fn rstr_of(r: &mut LeafRanges) -> Str { return fdj_ranges_str(r); }
fn rcover_of(r: &mut LeafRanges, n: Int) -> Bool { return fdj_leaves_cover(r, n); }
fn rwithin_of(r: &mut LeafRanges, t: Int) -> Bool { return fdj_leaves_within(r, t); }

fn dlen_of(d: &mut StealDeque) -> Int { return fdj_deque_len(d); }
fn dpushes_of(d: &mut StealDeque) -> Int { return fdj_deque_push_count(d); }
fn dpops_of(d: &mut StealDeque) -> Int { return fdj_deque_pop_count(d); }
fn dsteals_of(d: &mut StealDeque) -> Int { return fdj_deque_steal_count(d); }
fn dtrace_len_of(d: &mut StealDeque) -> Int { return fdj_deque_trace_len(d); }
fn dtrace_thief_of(d: &mut StealDeque, i: Int) -> Int { return fdj_deque_trace_thief(d, i); }
fn dtrace_item_of(d: &mut StealDeque, i: Int) -> Int { return fdj_deque_trace_item(d, i); }
fn dtrace_of(d: &mut StealDeque) -> Str { return fdj_deque_trace_str(d); }
fn dtrace_is(d: &mut StealDeque, want: Str) -> Bool { return fdj_deque_trace_is(d, want); }
fn dcheck_of(d: &mut StealDeque) -> Bool { return fdj_deque_check(d); }

// Option/Result outcome helpers for the deque.

fn pop_of(d: &mut StealDeque) -> Int {
  match fdj_deque_pop(d) {
    Some(x) => { return x; },
    None => { return -1; },
  }
  return -1;
}

fn steal_of(d: &mut StealDeque, thief: Int) -> Int {
  match fdj_deque_steal(d, thief) {
    Ok(x) => { return x; },
    Err(_) => { return -1; },
  }
  return -1;
}

fn steal_err_is(d: &mut StealDeque, thief: Int, want: Str) -> Bool {
  match fdj_deque_steal(d, thief) {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Split / tree tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var t = tree_of(3, 4);
  var ok = tnodes_of(&mut t) == 1;
  if tleaves_of(&mut t) != 1 { ok = false; }
  if tdepth_of(&mut t) != 0 { ok = false; }
  if tn_of(&mut t) != 3 { ok = false; }
  if tthreshold_of(&mut t) != 4 { ok = false; }
  let p0: Int = t.parent[0];
  let d0: Int = t.depth[0];
  let lo0: Int = t.lo[0];
  let hi0: Int = t.hi[0];
  let w0: Int = t.weight[0];
  let lf0: Int = t.is_leaf[0];
  let lc0: Int = t.left[0];
  let rc0: Int = t.right[0];
  if p0 != -1 { ok = false; }
  if d0 != 0 { ok = false; }
  if lo0 != 0 { ok = false; }
  if hi0 != 3 { ok = false; }
  if w0 != 3 { ok = false; }
  if lf0 != 1 { ok = false; }
  if lc0 != -1 { ok = false; }
  if rc0 != -1 { ok = false; }
  if tleaf_node_of(&mut t, 0) != 0 { ok = false; }
  if tleaf_lo_of(&mut t, 0) != 0 { ok = false; }
  if tleaf_hi_of(&mut t, 0) != 3 { ok = false; }
  if !tcheck_of(&mut t) { ok = false; }
  return assert(ok, "a range not larger than the threshold is a single leaf root");
}

fn t2() -> TestResult {
  var t = tree_of(9, 4);
  var ok = tnodes_of(&mut t) == 5;
  if tleaves_of(&mut t) != 3 { ok = false; }
  if tdepth_of(&mut t) != 2 { ok = false; }
  let lo1: Int = t.lo[1];
  let hi1: Int = t.hi[1];
  let w2: Int = t.weight[2];
  let lc0: Int = t.left[0];
  let rc0: Int = t.right[0];
  let lc2: Int = t.left[2];
  let rc2: Int = t.right[2];
  let lf1: Int = t.is_leaf[1];
  let lf2: Int = t.is_leaf[2];
  let dep4: Int = t.depth[4];
  let par4: Int = t.parent[4];
  if lo1 != 0 { ok = false; }
  if hi1 != 4 { ok = false; }
  if w2 != 5 { ok = false; }
  if lc0 != 1 { ok = false; }
  if rc0 != 2 { ok = false; }
  if lc2 != 3 { ok = false; }
  if rc2 != 4 { ok = false; }
  if lf1 != 1 { ok = false; }
  if lf2 != 0 { ok = false; }
  if dep4 != 2 { ok = false; }
  if par4 != 2 { ok = false; }
  if tleaf_node_of(&mut t, 0) != 1 { ok = false; }
  if tleaf_node_of(&mut t, 1) != 3 { ok = false; }
  if tleaf_node_of(&mut t, 2) != 4 { ok = false; }
  if tleaf_lo_of(&mut t, 1) != 4 { ok = false; }
  if tleaf_hi_of(&mut t, 2) != 9 { ok = false; }
  if !tcheck_of(&mut t) { ok = false; }
  return assert(ok, "n=9 t=4 splits into [0,4) [4,6) [6,9) with BFS node ids");
}

fn t3() -> TestResult {
  var r = ranges_of(10, 3);
  var ok = rcount_of(&mut r) == 4;
  if rlo_of(&mut r, 0) != 0 { ok = false; }
  if rhi_of(&mut r, 0) != 2 { ok = false; }
  if rlo_of(&mut r, 1) != 2 { ok = false; }
  if rhi_of(&mut r, 1) != 5 { ok = false; }
  if rlo_of(&mut r, 2) != 5 { ok = false; }
  if rhi_of(&mut r, 2) != 7 { ok = false; }
  if rlo_of(&mut r, 3) != 7 { ok = false; }
  if rhi_of(&mut r, 3) != 10 { ok = false; }
  if !streq(rstr_of(&mut r), "0-2,2-5,5-7,7-10") { ok = false; }
  if !rcover_of(&mut r, 10) { ok = false; }
  if !rwithin_of(&mut r, 3) { ok = false; }
  return assert(ok, "leaf ranges cover [0,n) exactly in ascending order");
}

fn t4() -> TestResult {
  var ok = true;
  var n = 1;
  while n <= 20 {
    var t = 1;
    while t <= 5 {
      var r = ranges_of(n, t);
      if !rcover_of(&mut r, n) { ok = false; }
      if !rwithin_of(&mut r, t) { ok = false; }
      if rcount_of(&mut r) < 1 { ok = false; }
      let first = rlo_of(&mut r, 0);
      let last_index = rcount_of(&mut r) - 1;
      let last = rhi_of(&mut r, last_index);
      if first != 0 { ok = false; }
      if last != n { ok = false; }
      t = t + 1;
    }
    n = n + 1;
  }
  var gap = LeafRanges{ lo: vec2(0, 0); hi: vec2(1, 2); };
  if rcover_of(&mut gap, 2) { ok = false; }
  var overlap = LeafRanges{ lo: vec2(0, 2); hi: vec2(3, 4); };
  if rcover_of(&mut overlap, 4) { ok = false; }
  var none = empty_ranges();
  if rcover_of(&mut none, 0) { ok = false; }
  return assert(ok, "coverage holds for n<=20, t<=5 and a gap/overlap is rejected");
}

fn t5() -> TestResult {
  var ok = build_err_is(0, 4, "forkjoin: n must be >= 1");
  if !build_err_is(-3, 4, "forkjoin: n must be >= 1") { ok = false; }
  if !build_err_is(4, 0, "forkjoin: threshold must be >= 1") { ok = false; }
  if !build_err_is(4, -1, "forkjoin: threshold must be >= 1") { ok = false; }
  if !split_err_is(0, 1, "forkjoin: n must be >= 1") { ok = false; }
  if !split_err_is(5, 0, "forkjoin: threshold must be >= 1") { ok = false; }
  if !limited_err_is(1, 1, -1, "forkjoin: max_depth must be >= 0") { ok = false; }
  if !limited_err_is(2, 1, -2, "forkjoin: max_depth must be >= 0") { ok = false; }
  return assert(ok, "n, threshold and max_depth are validated with stable errors");
}

fn t6() -> TestResult {
  var r1 = ranges_of(5, 100);
  var ok = rcount_of(&mut r1) == 1;
  if rlo_of(&mut r1, 0) != 0 { ok = false; }
  if rhi_of(&mut r1, 0) != 5 { ok = false; }
  if !rwithin_of(&mut r1, 100) { ok = false; }
  var r2 = ranges_of(6, 6);
  if rcount_of(&mut r2) != 1 { ok = false; }
  if rhi_of(&mut r2, 0) != 6 { ok = false; }
  var r3 = ranges_of(4, 1);
  if rcount_of(&mut r3) != 4 { ok = false; }
  if !streq(rstr_of(&mut r3), "0-1,1-2,2-3,3-4") { ok = false; }
  if !rwithin_of(&mut r3, 1) { ok = false; }
  var r4 = ranges_of(1, 1);
  if rcount_of(&mut r4) != 1 { ok = false; }
  if rhi_of(&mut r4, 0) != 1 { ok = false; }
  var t1 = tree_of(5, 100);
  if tdepth_of(&mut t1) != 0 { ok = false; }
  return assert(ok, "threshold edges: t>n, t=n, t=1 and n=t=1");
}

fn t7() -> TestResult {
  var t = tree_of(16, 1);
  var ok = tnodes_of(&mut t) == 31;
  if tleaves_of(&mut t) != 16 { ok = false; }
  if tdepth_of(&mut t) != 4 { ok = false; }
  var leaves = tleaf_results_of(&mut t);
  if leaves.len() != 16 { ok = false; }
  if tleaf_lo_of(&mut t, 15) != 15 { ok = false; }
  if tleaf_hi_of(&mut t, 15) != 16 { ok = false; }
  if !tcheck_of(&mut t) { ok = false; }
  return assert(ok, "t=1 splits [0,16) into sixteen singleton leaves at depth 4");
}

fn t8() -> TestResult {
  var ok = limited_err_is(16, 1, 3, "forkjoin: depth limit exceeded");
  if !limited_err_is(5, 2, 1, "forkjoin: depth limit exceeded") { ok = false; }
  var t1 = tree_of(16, 1);
  var full_depth = tdepth_of(&mut t1);
  if full_depth != 4 { ok = false; }
  match fdj_tree_build_limited(16, 1, 4) {
    Ok(t) => {
      var tm = t;
      if tdepth_of(&mut tm) != 4 { ok = false; }
      if tnodes_of(&mut tm) != 31 { ok = false; }
      if !tcheck_of(&mut tm) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  match fdj_tree_build_limited(4, 10, 0) {
    Ok(t) => {
      var tm = t;
      if tnodes_of(&mut tm) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  match fdj_tree_build_limited(5, 2, 2) {
    Ok(t) => {
      var tm = t;
      if tnodes_of(&mut tm) != 5 { ok = false; }
      if tleaves_of(&mut tm) != 3 { ok = false; }
      if tdepth_of(&mut tm) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the depth limit rejects exactly the trees that exceed it");
}

// ---------------------------------------------------------------------------
// Combine tests
// ---------------------------------------------------------------------------

fn t9() -> TestResult {
  let v1 = vec3(1, 2, 3);
  let v2 = empty_ints();
  let v3 = vec3(-5, 2, -1);
  var ok = fdj_combine_sum(&v1) == 6;
  if fdj_combine_sum(&v2) != 0 { ok = false; }
  if fdj_combine_sum(&v3) != -4 { ok = false; }
  let single = vec1(42);
  if fdj_combine_sum(&single) != 42 { ok = false; }
  return assert(ok, "sum reducer combines per-leaf results in order");
}

fn t10() -> TestResult {
  let v1 = vec3(3, 9, 4);
  let v2 = empty_ints();
  let v3 = vec3(-7, -3, -9);
  var ok = max_of(&v1) == 9;
  if !max_none(&v2) { ok = false; }
  if max_of(&v3) != -3 { ok = false; }
  let single = vec1(7);
  if max_of(&single) != 7 { ok = false; }
  return assert(ok, "max reducer returns the largest result and None when empty");
}

fn t11() -> TestResult {
  let chunks = chunks_of(vec2(1, 2), empty_ints(), vec1(3), vec3(4, 5, 6));
  let joined = fdj_concat(&chunks);
  var ok = joined.len() == 6;
  if !int_at(&joined, 0, 1) { ok = false; }
  if !int_at(&joined, 1, 2) { ok = false; }
  if !int_at(&joined, 2, 3) { ok = false; }
  if !int_at(&joined, 3, 4) { ok = false; }
  if !int_at(&joined, 4, 5) { ok = false; }
  if !int_at(&joined, 5, 6) { ok = false; }
  if int_at(&joined, 6, 0) { ok = false; }
  let none = Vec[Vec[Int]].new();
  let j2 = fdj_concat(&none);
  if j2.len() != 0 { ok = false; }
  return assert(ok, "concat joins per-leaf result vectors in leaf order");
}

// ---------------------------------------------------------------------------
// Tree result-slot tests
// ---------------------------------------------------------------------------

fn t12() -> TestResult {
  var t = tree_of(10, 3);
  var i = 0;
  var ok = true;
  while i < 4 {
    let node = tleaf_node_of(&mut t, i);
    if node < 0 { ok = false; }
    if !int_ok_is(tset_result_of(&mut t, node, (i + 1) * 10), (i + 1) * 10) { ok = false; }
    i = i + 1;
  }
  let ordered = tleaf_results_of(&mut t);
  let want = vec4(10, 20, 30, 40);
  if !vec_eq(&ordered, &want) { ok = false; }
  if !int_ok_is(tresult_of(&mut t, 3), 10) { ok = false; }
  if !int_ok_is(tresult_of(&mut t, 0), 0) { ok = false; }
  if !int_err_is(tset_result_of(&mut t, -1, 5), "forkjoin: node index out of range") { ok = false; }
  if !int_err_is(tset_result_of(&mut t, 99, 5), "forkjoin: node index out of range") { ok = false; }
  if !int_err_is(tresult_of(&mut t, -1), "forkjoin: node index out of range") { ok = false; }
  if !int_err_is(tresult_of(&mut t, 7), "forkjoin: node index out of range") { ok = false; }
  return assert(ok, "tree result slots are writable and read back in leaf order");
}

fn t13() -> TestResult {
  var t = tree_of(10, 3);
  var i = 0;
  var ok = true;
  while i < 4 {
    let node = tleaf_node_of(&mut t, i);
    if !int_ok_is(tset_result_of(&mut t, node, i + 1), i + 1) { ok = false; }
    i = i + 1;
  }
  if !int_ok_is(treduce_sum_of(&mut t), 10) { ok = false; }
  if !int_ok_is(tresult_of(&mut t, 0), 10) { ok = false; }
  if !int_ok_is(tresult_of(&mut t, 1), 3) { ok = false; }
  if !int_ok_is(tresult_of(&mut t, 2), 7) { ok = false; }
  var w = tree_of(10, 3);
  var j = 0;
  while j < 4 {
    let node = tleaf_node_of(&mut w, j);
    let lo: Int = w.lo[node];
    let hi: Int = w.hi[node];
    if !int_ok_is(tset_result_of(&mut w, node, hi - lo), hi - lo) { ok = false; }
    j = j + 1;
  }
  if !int_ok_is(treduce_sum_of(&mut w), 10) { ok = false; }
  var et = empty_tree();
  if !int_err_is(treduce_sum_of(&mut et), "forkjoin: tree is empty") { ok = false; }
  return assert(ok, "bottom-up sum reduction fills internal nodes and the root");
}

fn t14() -> TestResult {
  var t = tree_of(10, 3);
  var i = 0;
  var ok = true;
  while i < 4 {
    let node = tleaf_node_of(&mut t, i);
    if !int_ok_is(tset_result_of(&mut t, node, (i + 1) * 10), (i + 1) * 10) { ok = false; }
    i = i + 1;
  }
  if !int_ok_is(treduce_max_of(&mut t), 40) { ok = false; }
  if !int_ok_is(tresult_of(&mut t, 0), 40) { ok = false; }
  var u = tree_of(10, 3);
  var vals = vec4(-5, -1, -9, -3);
  var j = 0;
  while j < 4 {
    let node = tleaf_node_of(&mut u, j);
    if !int_ok_is(tset_result_of(&mut u, node, vals[j]), vals[j]) { ok = false; }
    j = j + 1;
  }
  if !int_ok_is(treduce_max_of(&mut u), -1) { ok = false; }
  var s = tree_of(3, 4);
  if !int_ok_is(tset_result_of(&mut s, 0, 7), 7) { ok = false; }
  if !int_ok_is(treduce_max_of(&mut s), 7) { ok = false; }
  var et = empty_tree();
  if !int_err_is(treduce_max_of(&mut et), "forkjoin: tree is empty") { ok = false; }
  return assert(ok, "bottom-up max reduction handles positives, negatives and a lone leaf");
}

fn t15() -> TestResult {
  var t = tree_of(9, 4);
  var ok = tn_of(&mut t) == 9;
  if tthreshold_of(&mut t) != 4 { ok = false; }
  if tnodes_of(&mut t) != 5 { ok = false; }
  if tleaves_of(&mut t) != 3 { ok = false; }
  if tdepth_of(&mut t) != 2 { ok = false; }
  if tleaf_node_of(&mut t, -1) != -1 { ok = false; }
  if tleaf_node_of(&mut t, 3) != -1 { ok = false; }
  if tleaf_lo_of(&mut t, 3) != -1 { ok = false; }
  if tleaf_hi_of(&mut t, -1) != -1 { ok = false; }
  var three = tleaf_results_of(&mut t);
  if three.len() != 3 { ok = false; }
  if !vec_eq(&three, &vec3(0, 0, 0)) { ok = false; }
  var r = ranges_of(9, 4);
  if rcount_of(&mut r) != 3 { ok = false; }
  if rlo_of(&mut r, 0) != 0 { ok = false; }
  if rhi_of(&mut r, 2) != 9 { ok = false; }
  if rlo_of(&mut r, -1) != -1 { ok = false; }
  if rhi_of(&mut r, 3) != -1 { ok = false; }
  var none = empty_ranges();
  if rcount_of(&mut none) != 0 { ok = false; }
  if rlo_of(&mut none, 0) != -1 { ok = false; }
  return assert(ok, "accessors report counts, bounds and out-of-range sentinels");
}

fn t16() -> TestResult {
  var ok = true;
  var n = 1;
  while n <= 25 {
    var t = 1;
    while t <= 6 {
      var tr = tree_of(n, t);
      if !tcheck_of(&mut tr) { ok = false; }
      t = t + 1;
    }
    n = n + 1;
  }
  var et = empty_tree();
  if tcheck_of(&mut et) { ok = false; }
  var bad_w = tree_of(8, 3);
  bad_w.weight[0] = 999;
  if tcheck_of(&mut bad_w) { ok = false; }
  var bad_leaf = tree_of(8, 3);
  bad_leaf.is_leaf[0] = 1;
  if tcheck_of(&mut bad_leaf) { ok = false; }
  var bad_parent = tree_of(8, 3);
  bad_parent.parent[1] = 3;
  if tcheck_of(&mut bad_parent) { ok = false; }
  return assert(ok, "the tree invariant holds for n<=25, t<=6 and rejects corruption");
}

// ---------------------------------------------------------------------------
// Work-stealing deque tests
// ---------------------------------------------------------------------------

fn t17() -> TestResult {
  var d = fdj_deque_new();
  var ok = dlen_of(&mut d) == 0;
  if fdj_deque_push(&mut d, 1) != 1 { ok = false; }
  if fdj_deque_push(&mut d, 2) != 2 { ok = false; }
  if fdj_deque_push(&mut d, 3) != 3 { ok = false; }
  if dlen_of(&mut d) != 3 { ok = false; }
  if pop_of(&mut d) != 3 { ok = false; }
  if pop_of(&mut d) != 2 { ok = false; }
  if dlen_of(&mut d) != 1 { ok = false; }
  if pop_of(&mut d) != 1 { ok = false; }
  if pop_of(&mut d) != -1 { ok = false; }
  if dlen_of(&mut d) != 0 { ok = false; }
  if dpushes_of(&mut d) != 3 { ok = false; }
  if dpops_of(&mut d) != 3 { ok = false; }
  if dsteals_of(&mut d) != 0 { ok = false; }
  if !streq(dtrace_of(&mut d), "") { ok = false; }
  if !dcheck_of(&mut d) { ok = false; }
  return assert(ok, "owner push/pop is LIFO and pop on empty returns None");
}

fn t18() -> TestResult {
  var d = fdj_deque_new();
  fdj_deque_push(&mut d, 10);
  fdj_deque_push(&mut d, 20);
  fdj_deque_push(&mut d, 30);
  fdj_deque_push(&mut d, 40);
  var ok = steal_of(&mut d, 7) == 10;
  if steal_of(&mut d, 9) != 20 { ok = false; }
  if pop_of(&mut d) != 40 { ok = false; }
  if steal_of(&mut d, 7) != 30 { ok = false; }
  if dlen_of(&mut d) != 0 { ok = false; }
  if dpushes_of(&mut d) != 4 { ok = false; }
  if dpops_of(&mut d) != 1 { ok = false; }
  if dsteals_of(&mut d) != 3 { ok = false; }
  if dtrace_len_of(&mut d) != 3 { ok = false; }
  if !streq(dtrace_of(&mut d), "7:10,9:20,7:30") { ok = false; }
  if !dtrace_is(&mut d, "7:10,9:20,7:30") { ok = false; }
  if dtrace_is(&mut d, "7:10") { ok = false; }
  if dtrace_thief_of(&mut d, 0) != 7 { ok = false; }
  if dtrace_item_of(&mut d, 1) != 20 { ok = false; }
  if dtrace_thief_of(&mut d, -1) != -1 { ok = false; }
  if dtrace_item_of(&mut d, 3) != -1 { ok = false; }
  if dpushes_of(&mut d) != dlen_of(&mut d) + dpops_of(&mut d) + dsteals_of(&mut d) { ok = false; }
  if !dcheck_of(&mut d) { ok = false; }
  return assert(ok, "thieves take the oldest item first and the steal trace is ordered");
}

fn t19() -> TestResult {
  var d = fdj_deque_new();
  var ok = steal_err_is(&mut d, 1, "forkjoin: deque is empty");
  if dlen_of(&mut d) != 0 { ok = false; }
  if dsteals_of(&mut d) != 0 { ok = false; }
  if dtrace_len_of(&mut d) != 0 { ok = false; }
  fdj_deque_push(&mut d, 5);
  if !steal_err_is(&mut d, -1, "forkjoin: thief id must be >= 0") { ok = false; }
  if dlen_of(&mut d) != 1 { ok = false; }
  if dsteals_of(&mut d) != 0 { ok = false; }
  if pop_of(&mut d) != 5 { ok = false; }
  if !dcheck_of(&mut d) { ok = false; }
  return assert(ok, "steal validates the thief id and refuses an empty deque");
}

fn t20() -> TestResult {
  var t = tree_of(9, 4);
  var d = fdj_deque_new();
  var ok = fdj_tree_push_leaves(&t, &mut d) == 3;
  if dlen_of(&mut d) != 3 { ok = false; }
  if dpushes_of(&mut d) != 3 { ok = false; }
  if steal_of(&mut d, 1) != 1 { ok = false; }
  if steal_of(&mut d, 2) != 3 { ok = false; }
  if pop_of(&mut d) != 4 { ok = false; }
  if dlen_of(&mut d) != 0 { ok = false; }
  if !streq(dtrace_of(&mut d), "1:1,2:3") { ok = false; }
  let st = fdj_stats(&t, &d);
  if st.nodes != 5 { ok = false; }
  if st.leaves != 3 { ok = false; }
  if st.max_depth != 2 { ok = false; }
  if st.steals != 2 { ok = false; }
  if !dcheck_of(&mut d) { ok = false; }
  return assert(ok, "leaf node ids feed the deque; stats join tree and deque");
}

fn t21() -> TestResult {
  var t = tree_of(1, 1);
  var d = fdj_deque_new();
  let st = fdj_stats(&t, &d);
  var ok = st.nodes == 1;
  if st.leaves != 1 { ok = false; }
  if st.max_depth != 0 { ok = false; }
  if st.steals != 0 { ok = false; }
  if !dcheck_of(&mut d) { ok = false; }
  fdj_deque_push(&mut d, 1);
  fdj_deque_push(&mut d, 2);
  if dpushes_of(&mut d) != 2 { ok = false; }
  if dlen_of(&mut d) != 2 { ok = false; }
  if dsteals_of(&mut d) != 0 { ok = false; }
  if dpops_of(&mut d) != 0 { ok = false; }
  return assert(ok, "stats of a single leaf tree and of an untouched deque");
}

fn t22() -> TestResult {
  var ok = true;
  var n = 1;
  while n <= 40 {
    var tt = 1;
    while tt <= 6 {
      var t = tree_of(n, tt);
      if !tcheck_of(&mut t) { ok = false; }
      if 2 * tleaves_of(&mut t) - 1 != tnodes_of(&mut t) { ok = false; }
      var r = ranges_of(n, tt);
      if !rcover_of(&mut r, n) { ok = false; }
      if !rwithin_of(&mut r, tt) { ok = false; }
      var leaves = tleaf_results_of(&mut t);
      if fdj_combine_sum(&leaves) != 0 { ok = false; }
      if tdepth_of(&mut t) != 0 {
        if !limited_err_is(n, tt, tdepth_of(&mut t) - 1, "forkjoin: depth limit exceeded") { ok = false; }
      }
      if !limited_err_is(n, tt, -1, "forkjoin: max_depth must be >= 0") { ok = false; }
      tt = tt + 1;
    }
    n = n + 1;
  }
  var d = fdj_deque_new();
  var i = 0;
  while i < 30 {
    fdj_deque_push(&mut d, i);
    if i % 3 == 2 {
      if dlen_of(&mut d) > 1 {
        if steal_of(&mut d, i % 4) < 0 { ok = false; }
      } else {
        if pop_of(&mut d) < 0 { ok = false; }
      }
    }
    if !dcheck_of(&mut d) { ok = false; }
    if dsteals_of(&mut d) != dtrace_len_of(&mut d) { ok = false; }
    i = i + 1;
  }
  if !dcheck_of(&mut d) { ok = false; }
  return assert(ok, "invariants hold across 240 splits and 30 deque transitions");
}

fn main() -> Int {
  io.println("=== xiom.forkjoin conformance tests ===");
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
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.forkjoin: all tests passed");
  } else {
    io.println("xiom.forkjoin: tests failed");
  }
  return failed;
}
