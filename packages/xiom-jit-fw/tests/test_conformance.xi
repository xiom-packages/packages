// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.jit-fw conformance tests (25 checks).
// Port task: prove the pure-XIOM xiom.jit_fw module against its SPEC.md:
// source hashing and artifact keys, IR lowering, the dispatch interpreter,
// the bounded LRU artifact cache, closure/trampoline adapters and the
// monitor/tiering policy.

module jit_fw_tests
use xiom.io; use xiom.test; use xiom.jit_fw;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every text
// check below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// 2 + 3: [push 2, push 3, add, halt].
fn fixture_add_ir() -> JitIr {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_PUSH, 2, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 3, 0);
  jit_ir_push(&mut ir, JIT_OP_ADD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  return ir;
}

fn fixture_add_code() -> JitCode {
  let ir = fixture_add_ir();
  return jit_lower(&ir);
}

// [label 0, push 7, label 1, jz -> label 1, halt]; label 1 lands on pc 2.
fn fixture_demo_ir() -> JitIr {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_LABEL, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 7, 0);
  jit_ir_push(&mut ir, JIT_OP_LABEL, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_JZ, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  return ir;
}

// Main pushes 1, calls the function at label 1, adds 10 to its result: the
// callee pushes 7 and returns, so the top is 17.
fn fixture_call_ir() -> JitIr {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_PUSH, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_CALL, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 10, 0);
  jit_ir_push(&mut ir, JIT_OP_ADD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_LABEL, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 7, 0);
  jit_ir_push(&mut ir, JIT_OP_RET, 0, 0);
  return ir;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = jit_source_hash("") == 2166136261;
  if jit_source_hash("a") != 3826002220 { ok = false; }
  if jit_source_hash("ab") != 1294271946 { ok = false; }
  if jit_source_hash("module demo") != 2665301212 { ok = false; }
  if jit_source_hash("hello") != jit_source_hash("hello") { ok = false; }
  if jit_source_hash("a") == jit_source_hash("b") { ok = false; }
  return assert(ok, "source hash: FNV-1a 32-bit vectors and determinism");
}

fn t2() -> TestResult {
  var ir = jit_ir_new();
  var ok = jit_ir_len(&ir) == 0;
  jit_ir_push(&mut ir, JIT_OP_PUSH, 1, 2);
  jit_ir_push(&mut ir, JIT_OP_ADD, 3, 4);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  if jit_ir_len(&ir) != 3 { ok = false; }
  if jit_ir_op(&ir, 0) != JIT_OP_PUSH { ok = false; }
  if jit_ir_a(&ir, 0) != 1 { ok = false; }
  if jit_ir_b(&ir, 0) != 2 { ok = false; }
  if jit_ir_op(&ir, 1) != JIT_OP_ADD { ok = false; }
  if jit_ir_a(&ir, 1) != 3 { ok = false; }
  if jit_ir_b(&ir, 1) != 4 { ok = false; }
  if jit_ir_op(&ir, 3) != JIT_NONE { ok = false; }
  if jit_ir_op(&ir, -1) != JIT_NONE { ok = false; }
  if jit_ir_a(&ir, 9) != 0 { ok = false; }
  if jit_ir_b(&ir, -2) != 0 { ok = false; }
  return assert(ok, "ir: push/len/opcode/operands and out-of-range defaults");
}

fn t3() -> TestResult {
  let ir = fixture_demo_ir();
  let code = jit_lower(&ir);
  var ok = jit_code_len(&code) == 5;
  if jit_code_op(&code, 0) != JIT_OP_NOP { ok = false; }
  if jit_code_op(&code, 1) != JIT_OP_PUSH { ok = false; }
  if jit_code_op(&code, 3) != JIT_OP_JZ { ok = false; }
  if jit_code_a(&code, 3) != 2 { ok = false; }
  if jit_code_op(&code, 4) != JIT_OP_HALT { ok = false; }
  var bad = jit_ir_new();
  jit_ir_push(&mut bad, JIT_OP_JMP, 7, 0);
  let badcode = jit_lower(&bad);
  if jit_code_a(&badcode, 0) != JIT_NONE { ok = false; }
  return assert(ok, "lower: labels resolve to pcs, pseudo-ops become nop, unbound is none");
}

fn t4() -> TestResult {
  var code = jit_code_new();
  var ok = jit_code_len(&code) == 0;
  jit_code_push(&mut code, JIT_OP_PUSH, 5, 0);
  jit_code_push(&mut code, JIT_OP_HALT, 0, 0);
  var copy = jit_code_new();
  jit_code_push(&mut copy, JIT_OP_PUSH, 5, 0);
  jit_code_push(&mut copy, JIT_OP_HALT, 0, 0);
  if !jit_code_equal(&code, &copy) { ok = false; }
  jit_code_push(&mut copy, JIT_OP_NOP, 0, 0);
  if jit_code_equal(&code, &copy) { ok = false; }
  if jit_code_op(&code, 9) != JIT_NONE { ok = false; }
  if jit_code_a(&code, 9) != 0 { ok = false; }
  if jit_code_b(&code, -1) != 0 { ok = false; }
  return assert(ok, "code: builders, structural equality and clamped accessors");
}

fn t5() -> TestResult {
  var ok = streq(jit_op_name(JIT_OP_LABEL), "label");
  if !streq(jit_op_name(JIT_OP_NOP), "nop") { ok = false; }
  if !streq(jit_op_name(JIT_OP_PUSH), "push") { ok = false; }
  if !streq(jit_op_name(JIT_OP_ADD), "add") { ok = false; }
  if !streq(jit_op_name(JIT_OP_SUB), "sub") { ok = false; }
  if !streq(jit_op_name(JIT_OP_MUL), "mul") { ok = false; }
  if !streq(jit_op_name(JIT_OP_LOAD), "load") { ok = false; }
  if !streq(jit_op_name(JIT_OP_STORE), "store") { ok = false; }
  if !streq(jit_op_name(JIT_OP_JMP), "jmp") { ok = false; }
  if !streq(jit_op_name(JIT_OP_JZ), "jz") { ok = false; }
  if !streq(jit_op_name(JIT_OP_CALL), "call") { ok = false; }
  if !streq(jit_op_name(JIT_OP_RET), "ret") { ok = false; }
  if !streq(jit_op_name(JIT_OP_HALT), "halt") { ok = false; }
  if !streq(jit_op_name(JIT_OP_DUP), "dup") { ok = false; }
  if !streq(jit_op_name(JIT_OP_SWAP), "swap") { ok = false; }
  if !streq(jit_op_name(JIT_OP_NEG), "neg") { ok = false; }
  if !streq(jit_op_name(99), "op99") { ok = false; }
  if !streq(jit_op_name(JIT_NONE), "op-1") { ok = false; }
  return assert(ok, "op names: every opcode mnemonic and the op<code> fallback");
}

fn t6() -> TestResult {
  let ir = fixture_demo_ir();
  let code = jit_lower(&ir);
  let want = "0: nop\n1: push 7\n2: nop\n3: jz -> 2\n4: halt\n";
  var ok = streq(jit_disasm(&code), want);
  var empty = jit_code_new();
  if !streq(jit_disasm(&empty), "") { ok = false; }
  if !streq(jit_disasm(&code), want) { ok = false; }
  return assert(ok, "disasm: exact deterministic text and empty rendering");
}

fn t7() -> TestResult {
  let addcode = fixture_add_code();
  let madd = jit_run(&addcode, 100);
  var ok = jit_machine_top(&madd) == 5 && jit_machine_status(&madd) == JIT_EXIT_HALT;
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_PUSH, 10, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 3, 0);
  jit_ir_push(&mut ir, JIT_OP_SUB, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 4, 0);
  jit_ir_push(&mut ir, JIT_OP_MUL, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_NEG, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  let code = jit_lower(&ir);
  let m = jit_run(&code, 100);
  if jit_machine_status(&m) != JIT_EXIT_HALT { ok = false; }
  if jit_machine_top(&m) != -28 { ok = false; }
  if jit_machine_stack_depth(&m) != 1 { ok = false; }
  return assert(ok, "run: add, sub, mul and neg stack semantics");
}

fn t8() -> TestResult {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_PUSH, 5, 0);
  jit_ir_push(&mut ir, JIT_OP_DUP, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 9, 0);
  jit_ir_push(&mut ir, JIT_OP_SWAP, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_MUL, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_ADD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  let code = jit_lower(&ir);
  let m = jit_run(&code, 100);
  var ok = jit_machine_status(&m) == JIT_EXIT_HALT;
  if jit_machine_top(&m) != 50 { ok = false; }
  if jit_machine_stack_depth(&m) != 1 { ok = false; }
  var empty = jit_machine_new();
  if jit_machine_top(&empty) != 0 { ok = false; }
  return assert(ok, "run: dup and swap on the operand stack");
}

fn t9() -> TestResult {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_PUSH, 42, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_STORE, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_LOAD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 7, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 9, 0);
  jit_ir_push(&mut ir, JIT_OP_STORE, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 9, 0);
  jit_ir_push(&mut ir, JIT_OP_LOAD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_ADD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 3, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_STORE, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_LOAD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_ADD, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  let code = jit_lower(&ir);
  let m = jit_run(&code, 200);
  var ok = jit_machine_status(&m) == JIT_EXIT_HALT;
  if jit_machine_top(&m) != 45 { ok = false; }
  if jit_machine_mem_len(&m) != 2 { ok = false; }
  if jit_machine_mem_at(&m, 0) != 42 { ok = false; }
  if jit_machine_mem_at(&m, 1) != 3 { ok = false; }
  if jit_machine_mem_at(&m, 2) != 0 { ok = false; }
  return assert(ok, "run: load/store, lazy one-word growth and clamped reads");
}

fn t10() -> TestResult {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_PUSH, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_JZ, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 10, 0);
  jit_ir_push(&mut ir, JIT_OP_JMP, 2, 0);
  jit_ir_push(&mut ir, JIT_OP_LABEL, 1, 0);
  jit_ir_push(&mut ir, JIT_OP_PUSH, 99, 0);
  jit_ir_push(&mut ir, JIT_OP_LABEL, 2, 0);
  jit_ir_push(&mut ir, JIT_OP_HALT, 0, 0);
  let code = jit_lower(&ir);
  let m = jit_run(&code, 100);
  var ok = jit_machine_status(&m) == JIT_EXIT_HALT && jit_machine_top(&m) == 10;
  var ir0 = jit_ir_new();
  jit_ir_push(&mut ir0, JIT_OP_PUSH, 0, 0);
  jit_ir_push(&mut ir0, JIT_OP_JZ, 1, 0);
  jit_ir_push(&mut ir0, JIT_OP_PUSH, 10, 0);
  jit_ir_push(&mut ir0, JIT_OP_JMP, 2, 0);
  jit_ir_push(&mut ir0, JIT_OP_LABEL, 1, 0);
  jit_ir_push(&mut ir0, JIT_OP_PUSH, 99, 0);
  jit_ir_push(&mut ir0, JIT_OP_LABEL, 2, 0);
  jit_ir_push(&mut ir0, JIT_OP_HALT, 0, 0);
  let code0 = jit_lower(&ir0);
  let m0 = jit_run(&code0, 100);
  if jit_machine_top(&m0) != 99 { ok = false; }
  if jit_machine_steps(&m0) != 6 { ok = false; }
  return assert(ok, "run: unconditional and conditional jumps, both paths");
}

fn t11() -> TestResult {
  let ir = fixture_call_ir();
  let code = jit_lower(&ir);
  let m = jit_run(&code, 100);
  var ok = jit_machine_status(&m) == JIT_EXIT_HALT;
  if jit_machine_top(&m) != 17 { ok = false; }
  if jit_machine_frame_depth(&m) != 0 { ok = false; }
  if jit_machine_steps(&m) != 8 { ok = false; }
  var ir2 = jit_ir_new();
  jit_ir_push(&mut ir2, JIT_OP_PUSH, 3, 0);
  jit_ir_push(&mut ir2, JIT_OP_RET, 0, 0);
  let code2 = jit_lower(&ir2);
  let m2 = jit_run(&code2, 100);
  if jit_machine_status(&m2) != JIT_EXIT_HALT { ok = false; }
  if jit_machine_top(&m2) != 3 { ok = false; }
  return assert(ok, "run: call pushes a frame, ret pops it, empty-frame ret halts");
}

fn t12() -> TestResult {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, JIT_OP_LABEL, 0, 0);
  jit_ir_push(&mut ir, JIT_OP_JMP, 0, 0);
  let code = jit_lower(&ir);
  let m = jit_run(&code, 10);
  var ok = jit_machine_status(&m) == JIT_EXIT_STEP_LIMIT;
  if jit_machine_steps(&m) != 10 { ok = false; }
  let m0 = jit_run(&code, 0);
  if jit_machine_status(&m0) != JIT_EXIT_STEP_LIMIT { ok = false; }
  if jit_machine_steps(&m0) != 0 { ok = false; }
  let mn = jit_run(&code, -5);
  if jit_machine_status(&mn) != JIT_EXIT_STEP_LIMIT { ok = false; }
  if jit_machine_steps(&mn) != 0 { ok = false; }
  return assert(ok, "run: the step cap bounds an infinite loop (0 and negative too)");
}

fn t13() -> TestResult {
  var ir = jit_ir_new();
  jit_ir_push(&mut ir, 99, 1, 2);
  let code = jit_lower(&ir);
  let m = jit_run(&code, 100);
  var ok = jit_machine_status(&m) == JIT_EXIT_BAD_OP && jit_machine_steps(&m) == 1;
  var ir2 = jit_ir_new();
  jit_ir_push(&mut ir2, JIT_OP_JMP, 7, 0);
  let code2 = jit_lower(&ir2);
  let m2 = jit_run(&code2, 100);
  if jit_machine_status(&m2) != JIT_EXIT_BAD_PC { ok = false; }
  if jit_machine_steps(&m2) != 1 { ok = false; }
  let empty = jit_code_new();
  let m3 = jit_run(&empty, 100);
  if jit_machine_status(&m3) != JIT_EXIT_BAD_PC { ok = false; }
  return assert(ok, "run: unknown opcode, unbound jump target and empty code fail closed");
}

fn t14() -> TestResult {
  let fresh = jit_machine_new();
  var ok = jit_machine_status(&fresh) == JIT_EXIT_RUNNING;
  if jit_machine_pc(&fresh) != 0 { ok = false; }
  if jit_machine_steps(&fresh) != 0 { ok = false; }
  if jit_machine_stack_depth(&fresh) != 0 { ok = false; }
  if jit_machine_frame_depth(&fresh) != 0 { ok = false; }
  if jit_machine_mem_len(&fresh) != 0 { ok = false; }
  let code = fixture_add_code();
  let m = jit_run(&code, 100);
  if jit_machine_pc(&m) != 3 { ok = false; }
  if jit_machine_steps(&m) != 4 { ok = false; }
  if jit_machine_stack_depth(&m) != 1 { ok = false; }
  if jit_machine_top(&m) != 5 { ok = false; }
  return assert(ok, "machine: fresh state and post-run accessors");
}

fn t15() -> TestResult {
  var c = jit_cache_new(4);
  var ok = jit_cache_len(&c) == 0 && jit_cache_cap(&c) == 4;
  if jit_cache_get(&mut c, 100) != JIT_NONE { ok = false; }
  let ev1 = jit_cache_put(&mut c, 100, 7);
  if ev1 != JIT_NONE { ok = false; }
  if jit_cache_peek(&c, 100) != 7 { ok = false; }
  if jit_cache_get(&mut c, 100) != 7 { ok = false; }
  if jit_cache_len(&c) != 1 { ok = false; }
  if jit_cache_hits(&c) != 1 { ok = false; }
  if jit_cache_misses(&c) != 1 { ok = false; }
  if jit_cache_inserts(&c) != 1 { ok = false; }
  if jit_cache_evicts(&c) != 0 { ok = false; }
  if jit_cache_peek(&c, 101) != JIT_NONE { ok = false; }
  return assert(ok, "cache: miss, insert, peek and hit statistics");
}

fn t16() -> TestResult {
  var c = jit_cache_new(2);
  jit_cache_put(&mut c, 10, 1);
  jit_cache_put(&mut c, 20, 2);
  var ok = jit_cache_get(&mut c, 10) == 1;
  let ev = jit_cache_put(&mut c, 30, 3);
  if ev != 2 { ok = false; }
  if jit_cache_get(&mut c, 20) != JIT_NONE { ok = false; }
  if jit_cache_get(&mut c, 10) != 1 { ok = false; }
  if jit_cache_get(&mut c, 30) != 3 { ok = false; }
  if jit_cache_len(&c) != 2 { ok = false; }
  if jit_cache_evicts(&c) != 1 { ok = false; }
  if jit_cache_misses(&c) != 1 { ok = false; }
  return assert(ok, "cache: LRU evicts the least recently used entry");
}

fn t17() -> TestResult {
  var c = jit_cache_new(2);
  jit_cache_put(&mut c, 10, 1);
  jit_cache_put(&mut c, 20, 2);
  let ev = jit_cache_put(&mut c, 10, 9);
  var ok = ev == JIT_NONE;
  if jit_cache_peek(&c, 10) != 9 { ok = false; }
  if jit_cache_len(&c) != 2 { ok = false; }
  if jit_cache_inserts(&c) != 3 { ok = false; }
  if jit_cache_evicts(&c) != 0 { ok = false; }
  if jit_cache_get(&mut c, 20) != 2 { ok = false; }
  return assert(ok, "cache: an existing key is replaced in place");
}

fn t18() -> TestResult {
  var c = jit_cache_new(0);
  var ok = jit_cache_cap(&c) == 1;
  jit_cache_put(&mut c, 1, 100);
  let ev = jit_cache_put(&mut c, 2, 200);
  if ev != 100 { ok = false; }
  if jit_cache_len(&c) != 1 { ok = false; }
  if jit_cache_peek(&c, 1) != JIT_NONE { ok = false; }
  if jit_cache_peek(&c, 2) != 200 { ok = false; }
  var n = jit_cache_new(-5);
  if jit_cache_cap(&n) != 1 { ok = false; }
  return assert(ok, "cache: capacity clamps to at least one");
}

fn t19() -> TestResult {
  var ok = jit_closure_make(7, 3) == 458755;
  if jit_closure_entry(458755) != 7 { ok = false; }
  if jit_closure_env(458755) != 3 { ok = false; }
  if jit_closure_make(65537, 2) != 65538 { ok = false; }
  if jit_closure_entry(65538) != 1 { ok = false; }
  if jit_closure_env(65538) != 2 { ok = false; }
  return assert(ok, "closure: (entry, env) packs losslessly into 32 bits");
}

fn t20() -> TestResult {
  var t = jit_tramp_new();
  let closure = jit_closure_make(7, 3);
  let s0 = jit_tramp_bind(&mut t, closure, 1);
  var ok = s0 == 0 && jit_tramp_count(&t) == 1;
  if jit_tramp_code(&t, closure) != 1 { ok = false; }
  if jit_tramp_entry(&t, closure) != 7 { ok = false; }
  if jit_tramp_env(&t, closure) != 3 { ok = false; }
  let s1 = jit_tramp_bind(&mut t, closure, 2);
  if s1 != 0 { ok = false; }
  if jit_tramp_count(&t) != 1 { ok = false; }
  if jit_tramp_code(&t, closure) != 2 { ok = false; }
  let unbound = jit_closure_make(9, 9);
  if jit_tramp_code(&t, unbound) != JIT_NONE { ok = false; }
  if jit_tramp_entry(&t, unbound) != JIT_NONE { ok = false; }
  if jit_tramp_env(&t, unbound) != JIT_NONE { ok = false; }
  return assert(ok, "trampolines: bind, rebind, resolve and unbound sentinels");
}

fn t21() -> TestResult {
  var m = jit_mon_new();
  var ok = jit_mon_sites(&m) == 0;
  if jit_mon_count(&m, 5) != 0 { ok = false; }
  if jit_mon_tier(&m, 5) != JIT_NONE { ok = false; }
  if jit_mon_hit(&mut m, 5) != 1 { ok = false; }
  if jit_mon_hit(&mut m, 5) != 2 { ok = false; }
  if jit_mon_hit(&mut m, 5) != 3 { ok = false; }
  if jit_mon_count(&m, 5) != 3 { ok = false; }
  if jit_mon_tier(&m, 5) != JIT_TIER_BASELINE { ok = false; }
  if jit_mon_sites(&m) != 1 { ok = false; }
  if jit_mon_deopts(&m, 5) != 0 { ok = false; }
  if jit_mon_hit(&mut m, 7) != 1 { ok = false; }
  if jit_mon_sites(&m) != 2 { ok = false; }
  if jit_mon_deopts(&m, 9) != 0 { ok = false; }
  return assert(ok, "monitor: hit counting, site creation and unknown-site defaults");
}

fn t22() -> TestResult {
  var m = jit_mon_new();
  jit_mon_hit(&mut m, 1);
  jit_mon_hit(&mut m, 1);
  let prev = jit_mon_set_tier(&mut m, 1, JIT_TIER_OPTIMIZED);
  var ok = prev == JIT_TIER_BASELINE;
  if jit_mon_tier(&m, 1) != JIT_TIER_OPTIMIZED { ok = false; }
  if jit_mon_set_tier(&mut m, 2, JIT_TIER_OPTIMIZED) != JIT_NONE { ok = false; }
  if jit_mon_deopt(&mut m, 1) != 1 { ok = false; }
  if jit_mon_tier(&m, 1) != JIT_TIER_DEOPT { ok = false; }
  if jit_mon_count(&m, 1) != 0 { ok = false; }
  if jit_mon_hit(&mut m, 1) != 1 { ok = false; }
  if jit_mon_deopt(&mut m, 1) != 2 { ok = false; }
  if jit_mon_deopts(&m, 1) != 2 { ok = false; }
  if jit_mon_deopt(&mut m, 3) != JIT_NONE { ok = false; }
  return assert(ok, "monitor: tier override and deopt resets the site counter");
}

fn t23() -> TestResult {
  var p = jit_policy_new(3, 2, 2);
  var ok = jit_policy_hot(&p) == 3 && jit_policy_rehot(&p) == 2 && jit_policy_max_attempts(&p) == 2;
  var q = jit_policy_new(0, -1, -1);
  if jit_policy_hot(&q) != 1 { ok = false; }
  if jit_policy_rehot(&q) != 1 { ok = false; }
  if jit_policy_max_attempts(&q) != 0 { ok = false; }
  var m = jit_mon_new();
  if jit_tier_decide(&m, 1, &p) != JIT_ACTION_STAY { ok = false; }
  jit_mon_hit(&mut m, 1);
  jit_mon_hit(&mut m, 1);
  if jit_tier_decide(&m, 1, &p) != JIT_ACTION_STAY { ok = false; }
  if jit_mon_hit(&mut m, 1) != 3 { ok = false; }
  if jit_tier_decide(&m, 1, &p) != JIT_ACTION_COMPILE { ok = false; }
  if jit_tier_apply(&mut m, 1, &p) != JIT_ACTION_COMPILE { ok = false; }
  if jit_mon_tier(&m, 1) != JIT_TIER_OPTIMIZED { ok = false; }
  if jit_tier_decide(&m, 1, &p) != JIT_ACTION_STAY { ok = false; }
  if jit_mon_count(&m, 1) != 3 { ok = false; }
  return assert(ok, "policy: threshold clamping and the baseline->optimized transition");
}

fn t24() -> TestResult {
  let p = jit_policy_new(3, 2, 2);
  var m = jit_mon_new();
  jit_mon_hit(&mut m, 4);
  jit_mon_hit(&mut m, 4);
  jit_mon_hit(&mut m, 4);
  jit_tier_apply(&mut m, 4, &p);
  var ok = jit_mon_tier(&m, 4) == JIT_TIER_OPTIMIZED;
  if jit_mon_deopt(&mut m, 4) != 1 { ok = false; }
  if jit_tier_decide(&m, 4, &p) != JIT_ACTION_STAY { ok = false; }
  jit_mon_hit(&mut m, 4);
  if jit_tier_decide(&m, 4, &p) != JIT_ACTION_STAY { ok = false; }
  if jit_mon_hit(&mut m, 4) != 2 { ok = false; }
  if jit_tier_decide(&m, 4, &p) != JIT_ACTION_RECOMPILE { ok = false; }
  if jit_tier_apply(&mut m, 4, &p) != JIT_ACTION_RECOMPILE { ok = false; }
  if jit_mon_tier(&m, 4) != JIT_TIER_OPTIMIZED { ok = false; }
  if jit_mon_deopt(&mut m, 4) != 2 { ok = false; }
  jit_mon_hit(&mut m, 4);
  jit_mon_hit(&mut m, 4);
  if jit_tier_decide(&m, 4, &p) != JIT_ACTION_STAY { ok = false; }
  return assert(ok, "policy: deopt cooldown, recompile and the attempt cap");
}

fn t25() -> TestResult {
  let src = "module demo";
  let h = jit_source_hash(src);
  let key = jit_key_for_source(src, 3);
  var ok = h == 2665301212 && key == jit_artifact_key(h, 3);
  var cache = jit_cache_new(2);
  if jit_cache_get(&mut cache, key) != JIT_NONE { ok = false; }
  let ir = fixture_add_ir();
  let code = jit_lower(&ir);
  let m = jit_run(&code, 100);
  if jit_machine_top(&m) != 5 { ok = false; }
  let ev = jit_cache_put(&mut cache, key, 0);
  if ev != JIT_NONE { ok = false; }
  if jit_cache_get(&mut cache, key) != 0 { ok = false; }
  let code2 = jit_lower(&ir);
  if !jit_code_equal(&code, &code2) { ok = false; }
  var ir2 = fixture_add_ir();
  let code3 = jit_lower(&ir2);
  if !jit_code_equal(&code, &code3) { ok = false; }
  if jit_cache_hits(&cache) != 1 { ok = false; }
  if jit_cache_misses(&cache) != 1 { ok = false; }
  if jit_cache_inserts(&cache) != 1 { ok = false; }
  let m2 = jit_run(&code2, 100);
  if jit_machine_top(&m2) != 5 { ok = false; }
  return assert(ok, "pipeline: source key + lowering + cache + dispatch, deterministic");
}

// ---------------------------------------------------------------------------

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.jit-fw conformance tests ===");
  var failed: Int = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  failed = failed + report(t21());
  failed = failed + report(t22());
  failed = failed + report(t23());
  failed = failed + report(t24());
  failed = failed + report(t25());
  if failed == 0 {
    io.println("xiom.jit-fw: all tests passed");
  } else {
    io.println("xiom.jit-fw: tests failed");
  }
  return failed;
}
