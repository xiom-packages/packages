// XIOM -- xiom.analyzer conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.analyzer module against its SPEC.md:
// basic-block construction, CFG edges and adjacency, forward reachability
// with unreachable detection, dominator sets with immediate dominators,
// register liveness with use/def tables and interference pairs, the
// deterministic text report, and the range-safe accessor contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module analyzer_tests
use xiom.io; use xiom.test; use xiom.analyzer;
use xiom.string;

// All Str equality goes through string.str_compare: `==` on Str values read
// from Vec[Str] elements is lowered as a pointer comparison (BUG 17), so
// every text check below is routed through streq instead of `==`.
fn streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// A diamond: JZ r0 -> 3, then r1 := r2, JMP 4, r3 := r4, RET.
// Leaders: 0 (entry), 1 (fallthrough after JZ), 3 (target), 4 (target and
// fallthrough after JMP). Blocks 0=[0,1), 1=[1,3), 2=[3,4), 3=[4,5).
fn f_diamond() -> Prog {
  var p = az_prog_new();
  az_prog_push(&mut p, AZ_OP_JZ, 0, 0, 3);
  az_prog_push(&mut p, AZ_OP_MOV, 1, 2, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_JMP, 0, 0, 4);
  az_prog_push(&mut p, AZ_OP_MOV, 3, 4, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_RET, 0, 0, AZ_NONE);
  return p;
}

// The diamond plus a dead tail after RET: instruction 5 starts a fresh block
// [5,7) (MOV + RET) that no edge reaches.
fn f_dead() -> Prog {
  var p = f_diamond();
  az_prog_push(&mut p, AZ_OP_MOV, 9, 9, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_RET, 0, 0, AZ_NONE);
  return p;
}

// A three-block jump chain: JMP 1; JMP 2; RET. Block k is [k, k+1).
fn f_chain() -> Prog {
  var p = az_prog_new();
  az_prog_push(&mut p, AZ_OP_JMP, 0, 0, 1);
  az_prog_push(&mut p, AZ_OP_JMP, 0, 0, 2);
  az_prog_push(&mut p, AZ_OP_RET, 0, 0, AZ_NONE);
  return p;
}

// A conditional/fallthrough split that needs several live registers:
// r1 := r0; JZ r5 -> 3; r2 := r3; r4 := r4 + r1; RET.
// Blocks 0=[0,2) (MOV, JZ), 1=[2,3) (MOV), 2=[3,5) (ADD, RET).
fn f_wide() -> Prog {
  var p = az_prog_new();
  az_prog_push(&mut p, AZ_OP_MOV, 1, 0, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_JZ, 5, 0, 3);
  az_prog_push(&mut p, AZ_OP_MOV, 2, 3, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_ADD, 4, 1, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_RET, 0, 0, AZ_NONE);
  return p;
}

// A back edge: r0 := r1; JZ r2 -> 4; r3 := r0; JMP 1; RET.
// Blocks 0=[0,1), 1=[1,2), 2=[2,4) (MOV, JMP -> 1), 3=[4,5). The CFG has
// the cycle 1 -> 2 -> 1 and the exit edge 1 -> 3.
fn f_loop() -> Prog {
  var p = az_prog_new();
  az_prog_push(&mut p, AZ_OP_MOV, 0, 1, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_JZ, 2, 0, 4);
  az_prog_push(&mut p, AZ_OP_MOV, 3, 0, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_JMP, 0, 0, 1);
  az_prog_push(&mut p, AZ_OP_RET, 0, 0, AZ_NONE);
  return p;
}

// One instruction, one block, no edges.
fn f_ret() -> Prog {
  var p = az_prog_new();
  az_prog_push(&mut p, AZ_OP_RET, 0, 0, AZ_NONE);
  return p;
}

// ---------------------------------------------------------------------------
// Exact report texts (byte-for-byte, LF-terminated)
// ---------------------------------------------------------------------------

fn report_empty() -> Str {
  var w = "xiom.analyzer report\n";
  w = w + "instructions: 0\n";
  w = w + "blocks: 0\n";
  w = w + "edges: 0\n";
  w = w + "reachable: (none)\n";
  w = w + "unreachable: (none)\n";
  w = w + "dom iterations: 0\n";
  w = w + "live regs: 0\n";
  w = w + "live iterations: 0\n";
  w = w + "interference: (none)\n";
  return w;
}

fn report_ret() -> Str {
  var w = "xiom.analyzer report\n";
  w = w + "instructions: 1\n";
  w = w + "blocks: 1\n";
  w = w + "edges: 0\n";
  w = w + "block 0 [0,1) succ: (none)\n";
  w = w + "reachable: 0\n";
  w = w + "unreachable: (none)\n";
  w = w + "dom 0: {0}\n";
  w = w + "idom 0: -1\n";
  w = w + "dom iterations: 1\n";
  w = w + "live regs: 0\n";
  w = w + "live-in 0: {}\n";
  w = w + "live-out 0: {}\n";
  w = w + "live iterations: 1\n";
  w = w + "interference: (none)\n";
  return w;
}

fn report_diamond() -> Str {
  var w = "xiom.analyzer report\n";
  w = w + "instructions: 5\n";
  w = w + "blocks: 4\n";
  w = w + "edges: 4\n";
  w = w + "block 0 [0,1) succ: 2/conditional 1/fallthrough\n";
  w = w + "block 1 [1,3) succ: 3/branch\n";
  w = w + "block 2 [3,4) succ: 3/fallthrough\n";
  w = w + "block 3 [4,5) succ: (none)\n";
  w = w + "edge 0: 0->1 fallthrough\n";
  w = w + "edge 1: 0->2 conditional\n";
  w = w + "edge 2: 1->3 branch\n";
  w = w + "edge 3: 2->3 fallthrough\n";
  w = w + "reachable: 0 1 2 3\n";
  w = w + "unreachable: (none)\n";
  w = w + "dom 0: {0}\n";
  w = w + "dom 1: {0,1}\n";
  w = w + "dom 2: {0,2}\n";
  w = w + "dom 3: {0,3}\n";
  w = w + "idom 0: -1\n";
  w = w + "idom 1: 0\n";
  w = w + "idom 2: 0\n";
  w = w + "idom 3: 0\n";
  w = w + "dom iterations: 2\n";
  w = w + "live regs: 5\n";
  w = w + "live-in 0: {0,2,4}\n";
  w = w + "live-out 0: {2,4}\n";
  w = w + "live-in 1: {2}\n";
  w = w + "live-out 1: {}\n";
  w = w + "live-in 2: {4}\n";
  w = w + "live-out 2: {}\n";
  w = w + "live-in 3: {}\n";
  w = w + "live-out 3: {}\n";
  w = w + "live iterations: 5\n";
  w = w + "interference: (2,4)\n";
  return w;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let e = az_prog_new();
  var ok = az_prog_len(&e) == 0;
  var p = az_prog_new();
  az_prog_push(&mut p, AZ_OP_MOV, 1, 2, AZ_NONE);
  az_prog_push(&mut p, AZ_OP_JMP, 0, 0, 4);
  az_prog_push(&mut p, AZ_OP_RET, 0, 0, AZ_NONE);
  if az_prog_len(&p) != 3 { ok = false; }
  if az_prog_op(&p, 0) != AZ_OP_MOV { ok = false; }
  if az_prog_a(&p, 1) != 0 { ok = false; }
  if az_prog_b(&p, 0) != 2 { ok = false; }
  if az_prog_target(&p, 1) != 4 { ok = false; }
  if az_prog_target(&p, 0) != AZ_NONE { ok = false; }
  if az_prog_op(&p, -1) != AZ_NONE { ok = false; }
  if az_prog_op(&p, 3) != AZ_NONE { ok = false; }
  if az_prog_a(&p, 99) != 0 { ok = false; }
  if az_prog_b(&p, -99) != 0 { ok = false; }
  if az_prog_target(&p, 99) != AZ_NONE { ok = false; }
  return assert(ok, "prog: push/len and range-safe typed accessors");
}

fn t2() -> TestResult {
  var ok = az_is_branch(AZ_OP_JMP) && az_is_branch(AZ_OP_JZ) && az_is_branch(AZ_OP_JNZ);
  if az_is_branch(AZ_OP_NOP) || az_is_branch(AZ_OP_RET) || az_is_branch(99) { ok = false; }
  if az_is_cond(AZ_OP_JMP) || !az_is_cond(AZ_OP_JZ) || !az_is_cond(AZ_OP_JNZ) { ok = false; }
  if az_is_cond(99) { ok = false; }
  if !az_is_terminator(AZ_OP_JMP) || !az_is_terminator(AZ_OP_RET) { ok = false; }
  if az_is_terminator(AZ_OP_JZ) || az_is_terminator(99) { ok = false; }
  return assert(ok, "classify: branch/conditional/terminator predicates");
}

fn t3() -> TestResult {
  var ok = !az_instr_uses_a(AZ_OP_NOP) && !az_instr_uses_b(AZ_OP_NOP) && !az_instr_defs_a(AZ_OP_NOP);
  if !az_instr_uses_b(AZ_OP_MOV) || az_instr_uses_a(AZ_OP_MOV) || !az_instr_defs_a(AZ_OP_MOV) { ok = false; }
  if !az_instr_uses_a(AZ_OP_ADD) || !az_instr_uses_b(AZ_OP_ADD) || !az_instr_defs_a(AZ_OP_ADD) { ok = false; }
  if !az_instr_uses_a(AZ_OP_SUB) || !az_instr_uses_b(AZ_OP_SUB) || !az_instr_defs_a(AZ_OP_SUB) { ok = false; }
  if !az_instr_uses_a(AZ_OP_MUL) || !az_instr_uses_b(AZ_OP_MUL) || !az_instr_defs_a(AZ_OP_MUL) { ok = false; }
  if !az_instr_uses_b(AZ_OP_LOAD) || az_instr_uses_a(AZ_OP_LOAD) || !az_instr_defs_a(AZ_OP_LOAD) { ok = false; }
  if !az_instr_uses_a(AZ_OP_STORE) || !az_instr_uses_b(AZ_OP_STORE) || az_instr_defs_a(AZ_OP_STORE) { ok = false; }
  if !az_instr_uses_a(AZ_OP_JZ) || az_instr_uses_b(AZ_OP_JZ) || az_instr_defs_a(AZ_OP_JZ) { ok = false; }
  if !az_instr_uses_a(AZ_OP_JNZ) || az_instr_uses_b(AZ_OP_JNZ) { ok = false; }
  if az_instr_uses_a(AZ_OP_JMP) || az_instr_uses_b(AZ_OP_JMP) || az_instr_defs_a(AZ_OP_JMP) { ok = false; }
  if az_instr_uses_a(AZ_OP_RET) || az_instr_uses_b(AZ_OP_RET) || az_instr_defs_a(AZ_OP_RET) { ok = false; }
  if az_instr_uses_a(99) || az_instr_uses_b(99) || az_instr_defs_a(99) { ok = false; }
  return assert(ok, "use/def: per-opcode register table");
}

fn t4() -> TestResult {
  var ok = streq(az_op_name(AZ_OP_NOP), "nop");
  if !streq(az_op_name(AZ_OP_MOV), "mov") { ok = false; }
  if !streq(az_op_name(AZ_OP_ADD), "add") { ok = false; }
  if !streq(az_op_name(AZ_OP_SUB), "sub") { ok = false; }
  if !streq(az_op_name(AZ_OP_MUL), "mul") { ok = false; }
  if !streq(az_op_name(AZ_OP_LOAD), "load") { ok = false; }
  if !streq(az_op_name(AZ_OP_STORE), "store") { ok = false; }
  if !streq(az_op_name(AZ_OP_JMP), "jmp") { ok = false; }
  if !streq(az_op_name(AZ_OP_JZ), "jz") { ok = false; }
  if !streq(az_op_name(AZ_OP_JNZ), "jnz") { ok = false; }
  if !streq(az_op_name(AZ_OP_RET), "ret") { ok = false; }
  if !streq(az_op_name(99), "op99") { ok = false; }
  if !streq(az_op_name(-3), "op-3") { ok = false; }
  if !streq(az_edge_kind_name(AZ_EDGE_FALL), "fallthrough") { ok = false; }
  if !streq(az_edge_kind_name(AZ_EDGE_BRANCH), "branch") { ok = false; }
  if !streq(az_edge_kind_name(AZ_EDGE_COND), "conditional") { ok = false; }
  if !streq(az_edge_kind_name(7), "unknown") { ok = false; }
  return assert(ok, "names: opcode mnemonics and edge kind names");
}

fn t5() -> TestResult {
  let p = f_diamond();
  let c = az_cfg_build(&p);
  var ok = az_cfg_block_count(&c) == 4;
  if az_cfg_block_start(&c, 0) != 0 || az_cfg_block_start(&c, 1) != 1 { ok = false; }
  if az_cfg_block_start(&c, 2) != 3 || az_cfg_block_start(&c, 3) != 4 { ok = false; }
  if az_cfg_block_end(&c, 0) != 1 || az_cfg_block_end(&c, 1) != 3 { ok = false; }
  if az_cfg_block_end(&c, 2) != 4 || az_cfg_block_end(&c, 3) != 5 { ok = false; }
  if az_cfg_block_of_instr(&c, 0) != 0 || az_cfg_block_of_instr(&c, 1) != 1 { ok = false; }
  if az_cfg_block_of_instr(&c, 2) != 1 || az_cfg_block_of_instr(&c, 3) != 2 { ok = false; }
  if az_cfg_block_of_instr(&c, 4) != 3 { ok = false; }
  if az_cfg_block_of_instr(&c, -1) != AZ_NONE || az_cfg_block_of_instr(&c, 5) != AZ_NONE { ok = false; }
  if az_cfg_block_start(&c, 9) != AZ_NONE || az_cfg_block_end(&c, -2) != AZ_NONE { ok = false; }
  return assert(ok, "blocks: diamond leaders, ranges and owner map");
}

fn t6() -> TestResult {
  let p = f_dead();
  let c = az_cfg_build(&p);
  var ok = az_cfg_block_count(&c) == 5;
  if az_cfg_block_start(&c, 4) != 5 || az_cfg_block_end(&c, 4) != 7 { ok = false; }
  if az_cfg_block_of_instr(&c, 5) != 4 || az_cfg_block_of_instr(&c, 6) != 4 { ok = false; }
  let q = f_chain();
  let cq = az_cfg_build(&q);
  if az_cfg_block_count(&cq) != 3 { ok = false; }
  if az_cfg_block_start(&cq, 1) != 1 || az_cfg_block_start(&cq, 2) != 2 { ok = false; }
  if az_cfg_block_end(&cq, 0) != 1 || az_cfg_block_end(&cq, 2) != 3 { ok = false; }
  let r = f_ret();
  let cr = az_cfg_build(&r);
  if az_cfg_block_count(&cr) != 1 { ok = false; }
  if az_cfg_block_start(&cr, 0) != 0 || az_cfg_block_end(&cr, 0) != 1 { ok = false; }
  return assert(ok, "blocks: dead tail after RET and single-instruction program");
}

fn t7() -> TestResult {
  let p = f_diamond();
  let c = az_cfg_build(&p);
  var ok = az_cfg_edge_count(&c) == 4;
  if az_cfg_edge_from(&c, 0) != 0 || az_cfg_edge_to(&c, 0) != 1 || az_cfg_edge_kind(&c, 0) != AZ_EDGE_FALL { ok = false; }
  if az_cfg_edge_from(&c, 1) != 0 || az_cfg_edge_to(&c, 1) != 2 || az_cfg_edge_kind(&c, 1) != AZ_EDGE_COND { ok = false; }
  if az_cfg_edge_from(&c, 2) != 1 || az_cfg_edge_to(&c, 2) != 3 || az_cfg_edge_kind(&c, 2) != AZ_EDGE_BRANCH { ok = false; }
  if az_cfg_edge_from(&c, 3) != 2 || az_cfg_edge_to(&c, 3) != 3 || az_cfg_edge_kind(&c, 3) != AZ_EDGE_FALL { ok = false; }
  if az_cfg_succ_count(&c, 0) != 2 || az_cfg_succ_count(&c, 1) != 1 { ok = false; }
  if az_cfg_succ_count(&c, 2) != 1 || az_cfg_succ_count(&c, 3) != 0 { ok = false; }
  if az_cfg_succ(&c, 0, 0) != 2 || az_cfg_succ(&c, 0, 1) != 1 { ok = false; }
  if az_cfg_succ_edge(&c, 0, 0) != 1 || az_cfg_succ_edge(&c, 0, 1) != 0 { ok = false; }
  if az_cfg_edge_kind(&c, az_cfg_succ_edge(&c, 0, 0)) != AZ_EDGE_COND { ok = false; }
  if az_cfg_succ(&c, 1, 0) != 3 || az_cfg_succ(&c, 3, 0) != AZ_NONE { ok = false; }
  if az_cfg_succ_count(&c, -1) != 0 || az_cfg_succ_edge(&c, 0, -1) != AZ_NONE { ok = false; }
  if az_cfg_succ(&c, 0, 9) != AZ_NONE { ok = false; }
  return assert(ok, "cfg: diamond edge list, kinds and successor enumeration");
}

fn t8() -> TestResult {
  let p = f_diamond();
  let c = az_cfg_build(&p);
  var ok = az_cfg_pred_count(&c, 3) == 2;
  if az_cfg_pred_at(&c, 3, 0) != 1 || az_cfg_pred_at(&c, 3, 1) != 2 { ok = false; }
  if az_cfg_pred_count(&c, 0) != 0 { ok = false; }
  if az_cfg_pred_at(&c, 0, 0) != AZ_NONE { ok = false; }
  if az_cfg_pred_count(&c, 1) != 1 || az_cfg_pred_at(&c, 1, 0) != 0 { ok = false; }
  if az_cfg_pred_at(&c, 3, -1) != AZ_NONE || az_cfg_pred_at(&c, 3, 5) != AZ_NONE { ok = false; }
  return assert(ok, "cfg: predecessor scan in edge-id order");
}

fn t9() -> TestResult {
  let p = f_diamond();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  var ok = az_reach_block_count(&r) == 4 && az_reach_count(&r) == 4;
  if !az_reach_is_reachable(&r, 0) || !az_reach_is_reachable(&r, 1) { ok = false; }
  if !az_reach_is_reachable(&r, 2) || !az_reach_is_reachable(&r, 3) { ok = false; }
  if az_reach_is_reachable(&r, -1) || az_reach_is_reachable(&r, 9) { ok = false; }
  if az_reach_order_count(&r) != 4 || az_reach_iterations(&r) != 4 { ok = false; }
  if az_reach_order_at(&r, 0) != 0 || az_reach_order_at(&r, 1) != 1 { ok = false; }
  if az_reach_order_at(&r, 2) != 3 || az_reach_order_at(&r, 3) != 2 { ok = false; }
  if az_reach_unreachable_count(&r) != 0 { ok = false; }
  if az_reach_unreachable_at(&r, 0) != AZ_NONE { ok = false; }
  return assert(ok, "reach: diamond DFS pre-order and zero unreachable blocks");
}

fn t10() -> TestResult {
  let p = f_dead();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  var ok = az_reach_count(&r) == 4 && az_reach_block_count(&r) == 5;
  if az_reach_is_reachable(&r, 4) { ok = false; }
  if az_reach_unreachable_count(&r) != 1 { ok = false; }
  if az_reach_unreachable_at(&r, 0) != 4 { ok = false; }
  if az_reach_unreachable_at(&r, 1) != AZ_NONE { ok = false; }
  if az_reach_unreachable_at(&r, -1) != AZ_NONE { ok = false; }
  let e = az_prog_new();
  let ce = az_cfg_build(&e);
  let re = az_reach_build(&ce);
  if az_reach_count(&re) != 0 || az_reach_block_count(&re) != 0 { ok = false; }
  if az_reach_order_count(&re) != 0 || az_reach_iterations(&re) != 0 { ok = false; }
  if az_reach_is_reachable(&re, 0) { ok = false; }
  return assert(ok, "reach: dead block after RET and empty program");
}

fn t11() -> TestResult {
  let p = f_chain();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let d = az_dom_build(&c, &r);
  var ok = az_reach_count(&r) == 3 && az_dom_block_count(&d) == 3;
  if az_dom_size(&d, 0) != 1 || az_dom_size(&d, 1) != 2 || az_dom_size(&d, 2) != 3 { ok = false; }
  if !az_dom_has(&d, 2, 0) || !az_dom_has(&d, 2, 1) || !az_dom_has(&d, 2, 2) { ok = false; }
  if az_dom_has(&d, 2, 3) || az_dom_has(&d, 1, 2) { ok = false; }
  if az_dom_idom(&d, 0) != AZ_NONE || az_dom_idom(&d, 1) != 0 || az_dom_idom(&d, 2) != 1 { ok = false; }
  if az_dom_iterations(&d) != 2 || az_dom_bound_hit(&d) { ok = false; }
  return assert(ok, "dom: chain triples, immediate dominators, pass count");
}

fn t12() -> TestResult {
  let p = f_diamond();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let d = az_dom_build(&c, &r);
  var ok = az_dom_size(&d, 0) == 1 && az_dom_size(&d, 1) == 2;
  if az_dom_size(&d, 2) != 2 || az_dom_size(&d, 3) != 2 { ok = false; }
  if !az_dom_has(&d, 1, 0) || !az_dom_has(&d, 1, 1) || az_dom_has(&d, 1, 2) { ok = false; }
  if !az_dom_has(&d, 2, 0) || !az_dom_has(&d, 2, 2) || az_dom_has(&d, 2, 1) { ok = false; }
  if !az_dom_has(&d, 3, 0) || !az_dom_has(&d, 3, 3) { ok = false; }
  if az_dom_has(&d, 3, 1) || az_dom_has(&d, 3, 2) { ok = false; }
  if az_dom_idom(&d, 1) != 0 || az_dom_idom(&d, 2) != 0 || az_dom_idom(&d, 3) != 0 { ok = false; }
  if az_dom_idom(&d, 0) != AZ_NONE { ok = false; }
  if az_dom_iterations(&d) != 2 || az_dom_bound_hit(&d) { ok = false; }
  if az_dom_has(&d, -1, 0) || az_dom_has(&d, 0, 9) { ok = false; }
  if az_dom_size(&d, 9) != 0 || az_dom_idom(&d, 9) != AZ_NONE { ok = false; }
  return assert(ok, "dom: diamond join and range-safe accessors");
}

fn t13() -> TestResult {
  let p = f_dead();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let d = az_dom_build(&c, &r);
  var ok = az_dom_block_count(&d) == 5;
  if !az_dom_has(&d, 3, 0) || !az_dom_has(&d, 3, 3) || az_dom_has(&d, 3, 4) { ok = false; }
  if az_dom_size(&d, 4) != 1 { ok = false; }
  if !az_dom_has(&d, 4, 4) || az_dom_has(&d, 4, 0) { ok = false; }
  if az_dom_idom(&d, 3) != 0 || az_dom_idom(&d, 4) != AZ_NONE { ok = false; }
  let q = f_loop();
  let cq = az_cfg_build(&q);
  let rq = az_reach_build(&cq);
  let dq = az_dom_build(&cq, &rq);
  if az_reach_count(&rq) != 4 { ok = false; }
  if !az_dom_has(&dq, 1, 0) || !az_dom_has(&dq, 2, 1) || !az_dom_has(&dq, 3, 1) { ok = false; }
  if az_dom_idom(&dq, 2) != 1 || az_dom_idom(&dq, 3) != 1 { ok = false; }
  if az_dom_iterations(&dq) != 2 || az_dom_bound_hit(&dq) { ok = false; }
  return assert(ok, "dom: unreachable singleton and loop header over two predecessors");
}

fn t14() -> TestResult {
  let p = f_wide();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let lv = az_live_build(&p, &c, &r);
  var ok = az_live_block_count(&lv) == 3 && az_live_reg_count(&lv) == 6;
  if az_live_in_count(&lv, 0) != 4 || az_live_out_count(&lv, 0) != 3 { ok = false; }
  if !az_live_in(&lv, 0, 0) || !az_live_in(&lv, 0, 3) { ok = false; }
  if !az_live_in(&lv, 0, 4) || !az_live_in(&lv, 0, 5) { ok = false; }
  if az_live_in(&lv, 0, 1) || az_live_in(&lv, 0, 2) { ok = false; }
  if !az_live_out(&lv, 0, 1) || !az_live_out(&lv, 0, 3) || !az_live_out(&lv, 0, 4) { ok = false; }
  if az_live_out(&lv, 0, 0) || az_live_out(&lv, 0, 5) { ok = false; }
  if az_live_in_count(&lv, 1) != 3 || az_live_out_count(&lv, 1) != 2 { ok = false; }
  if !az_live_in(&lv, 1, 1) || !az_live_in(&lv, 1, 3) || !az_live_in(&lv, 1, 4) { ok = false; }
  if !az_live_out(&lv, 1, 1) || !az_live_out(&lv, 1, 4) { ok = false; }
  if az_live_in_count(&lv, 2) != 2 || az_live_out_count(&lv, 2) != 0 { ok = false; }
  if !az_live_in(&lv, 2, 1) || !az_live_in(&lv, 2, 4) { ok = false; }
  if az_live_iterations(&lv) != 6 || az_live_bound_hit(&lv) { ok = false; }
  return assert(ok, "live: wide split fixpoint rows and register count");
}

fn t15() -> TestResult {
  let p = f_wide();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let lv = az_live_build(&p, &c, &r);
  var ok = az_live_use(&lv, 0, 0) && az_live_use(&lv, 0, 5);
  if az_live_use(&lv, 0, 1) { ok = false; }
  if !az_live_def(&lv, 0, 1) || az_live_def(&lv, 0, 0) { ok = false; }
  if !az_live_use(&lv, 1, 3) || !az_live_def(&lv, 1, 2) { ok = false; }
  if !az_live_use(&lv, 2, 1) || !az_live_use(&lv, 2, 4) || !az_live_def(&lv, 2, 4) { ok = false; }
  if az_live_use(&lv, 2, 2) || az_live_def(&lv, 2, 1) { ok = false; }
  if az_live_use(&lv, -1, 0) || az_live_use(&lv, 0, 99) { ok = false; }
  if az_live_def(&lv, 9, 0) || az_live_def(&lv, 0, -1) { ok = false; }
  if az_live_in(&lv, 9, 0) || az_live_out(&lv, 0, 99) { ok = false; }
  if az_live_in_count(&lv, 9) != 0 || az_live_out_count(&lv, -1) != 0 { ok = false; }
  return assert(ok, "live: upward-exposed uses, defs and range-safe accessors");
}

fn t16() -> TestResult {
  let p = f_loop();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let lv = az_live_build(&p, &c, &r);
  var ok = az_live_reg_count(&lv) == 4 && az_live_block_count(&lv) == 4;
  if az_live_in_count(&lv, 0) != 2 || !az_live_in(&lv, 0, 1) || !az_live_in(&lv, 0, 2) { ok = false; }
  if az_live_in(&lv, 0, 0) || az_live_out_count(&lv, 0) != 2 { ok = false; }
  if !az_live_out(&lv, 0, 0) || !az_live_out(&lv, 0, 2) { ok = false; }
  if az_live_in_count(&lv, 1) != 2 || !az_live_in(&lv, 1, 0) || !az_live_in(&lv, 1, 2) { ok = false; }
  if az_live_out_count(&lv, 1) != 2 || !az_live_out(&lv, 1, 0) || !az_live_out(&lv, 1, 2) { ok = false; }
  if az_live_in_count(&lv, 2) != 2 || az_live_out_count(&lv, 2) != 2 { ok = false; }
  if az_live_in_count(&lv, 3) != 0 || az_live_out_count(&lv, 3) != 0 { ok = false; }
  if az_live_iterations(&lv) != 9 || az_live_bound_hit(&lv) { ok = false; }
  return assert(ok, "live: back-edge fixpoint reaches fixed point within the cap");
}

fn t17() -> TestResult {
  let p = f_wide();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let lv = az_live_build(&p, &c, &r);
  var ok = az_live_pair_count(&lv) == 3;
  if az_live_pair_a_at(&lv, 0) != 1 || az_live_pair_b_at(&lv, 0) != 3 { ok = false; }
  if az_live_pair_a_at(&lv, 1) != 1 || az_live_pair_b_at(&lv, 1) != 4 { ok = false; }
  if az_live_pair_a_at(&lv, 2) != 3 || az_live_pair_b_at(&lv, 2) != 4 { ok = false; }
  var i = 0;
  while i < az_live_pair_count(&lv) {
    if az_live_pair_a_at(&lv, i) >= az_live_pair_b_at(&lv, i) { ok = false; }
    i = i + 1;
  }
  if az_live_pair_a_at(&lv, 3) != AZ_NONE || az_live_pair_b_at(&lv, -1) != AZ_NONE { ok = false; }
  return assert(ok, "interference: wide split pairs are deduplicated and ordered");
}

fn t18() -> TestResult {
  let lp = f_loop();
  let lc = az_cfg_build(&lp);
  let lr = az_reach_build(&lc);
  let llv = az_live_build(&lp, &lc, &lr);
  var ok = az_live_pair_count(&llv) == 1;
  if az_live_pair_a_at(&llv, 0) != 0 || az_live_pair_b_at(&llv, 0) != 2 { ok = false; }
  let dp = f_diamond();
  let dc = az_cfg_build(&dp);
  let dr = az_reach_build(&dc);
  let dlv = az_live_build(&dp, &dc, &dr);
  if az_live_pair_count(&dlv) != 1 { ok = false; }
  if az_live_pair_a_at(&dlv, 0) != 2 || az_live_pair_b_at(&dlv, 0) != 4 { ok = false; }
  return assert(ok, "interference: loop interval and diamond pair");
}

fn t19() -> TestResult {
  let e = az_prog_new();
  return assert(streq(az_report(&e), report_empty()), "report: empty program is byte-exact");
}

fn t20() -> TestResult {
  let p = f_ret();
  return assert(streq(az_report(&p), report_ret()), "report: single RET is byte-exact");
}

fn t21() -> TestResult {
  let p = f_diamond();
  return assert(streq(az_report(&p), report_diamond()), "report: diamond is byte-exact");
}

fn t22() -> TestResult {
  let p = f_diamond();
  let r1 = az_report(&p);
  let r2 = az_report(&p);
  var ok = streq(r1, r2);
  if !streq(string.str_slice(r1, 0, 20), "xiom.analyzer report") { ok = false; }
  let d = f_dead();
  let rd = az_report(&d);
  let hit = assert_contains(rd, "unreachable: 4\n", "dead marker");
  if !hit.passed { ok = false; }
  let lp = f_loop();
  let rl = az_report(&lp);
  if !streq(string.str_slice(rl, rl.len() - 20, rl.len()), "interference: (0,2)\n") { ok = false; }
  return assert(ok, "report: deterministic, marks dead blocks and loop pairs");
}

fn t23() -> TestResult {
  let p = f_ret();
  let c = az_cfg_build(&p);
  let r = az_reach_build(&c);
  let d = az_dom_build(&c, &r);
  let lv = az_live_build(&p, &c, &r);
  var ok = az_cfg_block_start(&c, -1) == AZ_NONE && az_cfg_block_end(&c, 9) == AZ_NONE;
  if az_cfg_edge_from(&c, 9) != AZ_NONE || az_cfg_edge_to(&c, -1) != AZ_NONE { ok = false; }
  if az_cfg_edge_kind(&c, 99) != AZ_NONE || az_cfg_pred_count(&c, -1) != 0 { ok = false; }
  if az_reach_order_at(&r, -1) != AZ_NONE || az_reach_order_at(&r, 99) != AZ_NONE { ok = false; }
  if az_dom_has(&d, -1, 0) || az_dom_size(&d, 99) != 0 { ok = false; }
  if az_live_in(&lv, 99, 0) || az_live_out(&lv, 0, 99) { ok = false; }
  if az_live_pair_a_at(&lv, 99) != AZ_NONE || az_live_pair_b_at(&lv, 99) != AZ_NONE { ok = false; }
  return assert(ok, "accessors: sentinel contract across CFG, reach, dom and live");
}

// ---------------------------------------------------------------------------

fn emit(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.analyzer conformance tests ===");
  var failed: Int = 0;
  failed = failed + emit(t1());
  failed = failed + emit(t2());
  failed = failed + emit(t3());
  failed = failed + emit(t4());
  failed = failed + emit(t5());
  failed = failed + emit(t6());
  failed = failed + emit(t7());
  failed = failed + emit(t8());
  failed = failed + emit(t9());
  failed = failed + emit(t10());
  failed = failed + emit(t11());
  failed = failed + emit(t12());
  failed = failed + emit(t13());
  failed = failed + emit(t14());
  failed = failed + emit(t15());
  failed = failed + emit(t16());
  failed = failed + emit(t17());
  failed = failed + emit(t18());
  failed = failed + emit(t19());
  failed = failed + emit(t20());
  failed = failed + emit(t21());
  failed = failed + emit(t22());
  failed = failed + emit(t23());
  if failed == 0 {
    io.println("xiom.analyzer: all tests passed");
  } else {
    io.println("xiom.analyzer: tests failed");
  }
  return failed;
}
