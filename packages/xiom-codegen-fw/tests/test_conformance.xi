// XIOM -- xiom.codegen-fw conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.codegen_fw module against its SPEC.md:
// label allocation, scoped symbol tables, the instruction model, the text
// emitter, the peephole window rewriter and the module renderer.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module codegen_tests
use xiom.io; use xiom.test; use xiom.codegen_fw;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every text check
// below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// x=1 and y=2 at depth 0, then depth 1 with a shadowing x=9 (3 bindings).
fn fixture_tab() -> SymTab {
  var t = symtab_new();
  symtab_bind(&mut t, "x", 1);
  symtab_bind(&mut t, "y", 2);
  symtab_push(&mut t);
  symtab_bind(&mut t, "x", 9);
  return t;
}

// Five rules: identity add erase, identity mul erase, mul-by-zero to mov with
// operand forwarding, dead mov (argA=7) before ret, nop-pair erase.
fn fixture_rules() -> PeepholeRules {
  var r = peep_rules_new();
  peep_rule_add(&mut r, CG_OP_ADD, CG_PAT_END, CG_WILD, 0, CG_ERASE, 0, 0);
  peep_rule_add(&mut r, CG_OP_MUL, CG_PAT_END, CG_WILD, 1, CG_ERASE, 0, 0);
  peep_rule_add(&mut r, CG_OP_MUL, CG_PAT_END, CG_WILD, 0, CG_OP_MOV, CG_FWD_A, 0);
  peep_rule_add(&mut r, CG_OP_MOV, CG_OP_RET, 7, CG_WILD, CG_OP_RET, 0, 0);
  peep_rule_add(&mut r, CG_OP_NOP, CG_OP_NOP, CG_WILD, CG_WILD, CG_ERASE, 0, 0);
  return r;
}

// [ADD 5,0; ADD 6,1; MUL 7,1; MUL 8,0]: rule 0 erases the first, rule 1
// erases the third, rule 2 rewrites the fourth, the second is untouched.
fn fixture_prog() -> IrProgram {
  var p = ir_new();
  ir_push(&mut p, CG_OP_ADD, 5, 0);
  ir_push(&mut p, CG_OP_ADD, 6, 1);
  ir_push(&mut p, CG_OP_MUL, 7, 1);
  ir_push(&mut p, CG_OP_MUL, 8, 0);
  return p;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var a = label_alloc_new();
  let l0 = label_fresh(&mut a);
  let l1 = label_fresh(&mut a);
  var ok = l0 == 0 && l1 == 1;
  if label_next(&a) != 2 { ok = false; }
  if label_pending(&a) != 2 { ok = false; }
  if label_committed(&a) != 0 { ok = false; }
  return assert(ok, "labels: fresh hands out 0-based ids and tracks pending");
}

fn t2() -> TestResult {
  var a = label_alloc_new();
  let x0 = label_fresh(&mut a);
  let x1 = label_fresh(&mut a);
  let c = label_commit(&mut a);
  var ok = c == 2 && x0 == 0 && x1 == 1;
  if label_committed(&a) != 2 { ok = false; }
  if label_pending(&a) != 0 { ok = false; }
  if label_next(&a) != 2 { ok = false; }
  let x2 = label_fresh(&mut a);
  if x2 != 2 { ok = false; }
  return assert(ok, "labels: commit promotes pending and keeps the counter monotone");
}

fn t3() -> TestResult {
  var a = label_alloc_new();
  let first = label_fresh(&mut a);
  let c0 = label_commit(&mut a);
  let second = label_fresh(&mut a);
  let third = label_fresh(&mut a);
  let back = label_rollback(&mut a);
  var ok = first == 0 && c0 == 1 && second == 1 && third == 2 && back == 1;
  if label_pending(&a) != 0 { ok = false; }
  if label_committed(&a) != 1 { ok = false; }
  if label_next(&a) != 1 { ok = false; }
  let reused = label_fresh(&mut a);
  if reused != 1 { ok = false; }
  return assert(ok, "labels: rollback discards pending ids and rewinds for reuse");
}

fn t4() -> TestResult {
  var a = label_alloc_new();
  let c = label_commit(&mut a);
  let n = label_rollback(&mut a);
  var ok = c == 0 && n == 0;
  if label_next(&a) != 0 { ok = false; }
  if label_pending(&a) != 0 { ok = false; }
  let l = label_fresh(&mut a);
  if l != 0 { ok = false; }
  return assert(ok, "labels: commit/rollback on an empty allocator are no-ops");
}

fn t5() -> TestResult {
  var ok = streq(label_text(0), "L0");
  if !streq(label_text(7), "L7") { ok = false; }
  if !streq(label_text(42), "L42") { ok = false; }
  if !streq(label_text(-1), "L-1") { ok = false; }
  return assert(ok, "labels: label_text renders L + decimal id");
}

fn t6() -> TestResult {
  var t = symtab_new();
  var ok = symtab_len(&t) == 0 && symtab_depth(&t) == 0 && symtab_generation(&t) == 0;
  if symtab_lookup(&t, "x") != CG_NONE { ok = false; }
  let g1 = symtab_bind(&mut t, "x", 1);
  let g2 = symtab_bind(&mut t, "y", 2);
  if g1 != 1 || g2 != 2 { ok = false; }
  if symtab_lookup(&t, "x") != 1 { ok = false; }
  if symtab_lookup(&t, "y") != 2 { ok = false; }
  if symtab_lookup(&t, "z") != CG_NONE { ok = false; }
  if symtab_len(&t) != 2 { ok = false; }
  if symtab_generation(&t) != 2 { ok = false; }
  return assert(ok, "symtab: bind/lookup/generation on the outer scope");
}

fn t7() -> TestResult {
  let t = fixture_tab();
  var ok = symtab_lookup(&t, "x") == 9;
  if symtab_lookup(&t, "y") != 2 { ok = false; }
  if symtab_find_depth(&t, "x") != 1 { ok = false; }
  if symtab_find_depth(&t, "y") != 0 { ok = false; }
  if symtab_find_depth(&t, "z") != CG_NONE { ok = false; }
  if symtab_depth(&t) != 1 { ok = false; }
  return assert(ok, "symtab: inner scope shadows and find_depth reports the scope");
}

fn t8() -> TestResult {
  var t = fixture_tab();
  let removed = symtab_pop(&mut t);
  var ok = removed == 1;
  if symtab_depth(&t) != 0 { ok = false; }
  if symtab_len(&t) != 2 { ok = false; }
  if symtab_lookup(&t, "x") != 1 { ok = false; }
  if symtab_generation(&t) != 3 { ok = false; }
  let again = symtab_pop(&mut t);
  if again != 0 { ok = false; }
  if symtab_lookup(&t, "y") != 2 { ok = false; }
  return assert(ok, "symtab: pop removes the scope's bindings and keeps generation");
}

fn t9() -> TestResult {
  let t = fixture_tab();
  var ok = streq(symtab_name(&t, 0), "x");
  if symtab_value(&t, 0) != 1 { ok = false; }
  if symtab_scope(&t, 0) != 0 { ok = false; }
  if !streq(symtab_name(&t, 1), "y") { ok = false; }
  if symtab_scope(&t, 1) != 0 { ok = false; }
  if !streq(symtab_name(&t, 2), "x") { ok = false; }
  if symtab_value(&t, 2) != 9 { ok = false; }
  if symtab_scope(&t, 2) != 1 { ok = false; }
  if !streq(symtab_name(&t, 3), "") { ok = false; }
  if !streq(symtab_name(&t, -1), "") { ok = false; }
  if symtab_value(&t, 3) != 0 { ok = false; }
  if symtab_scope(&t, 3) != CG_NONE { ok = false; }
  if symtab_scope(&t, -5) != CG_NONE { ok = false; }
  return assert(ok, "symtab: accessors expose name/value/scope and clamp out of range");
}

fn t10() -> TestResult {
  var t = symtab_new();
  let g1 = symtab_bind(&mut t, "x", 1);
  let g2 = symtab_bind(&mut t, "x", 2);
  var ok = g1 == 1 && g2 == 2;
  if symtab_lookup(&t, "x") != 2 { ok = false; }
  if symtab_len(&t) != 2 { ok = false; }
  if symtab_find_depth(&t, "x") != 0 { ok = false; }
  return assert(ok, "symtab: a later bind shadows an earlier one in the same scope");
}

fn t11() -> TestResult {
  var p = ir_new();
  var ok = ir_len(&p) == 0;
  ir_push(&mut p, CG_OP_MOV, 1, 2);
  ir_push(&mut p, CG_OP_ADD, 3, 4);
  ir_push(&mut p, CG_OP_RET, 0, 0);
  if ir_len(&p) != 3 { ok = false; }
  if ir_opcode(&p, 0) != CG_OP_MOV { ok = false; }
  if ir_a(&p, 0) != 1 { ok = false; }
  if ir_b(&p, 0) != 2 { ok = false; }
  if ir_opcode(&p, 1) != CG_OP_ADD { ok = false; }
  if ir_a(&p, 1) != 3 { ok = false; }
  if ir_b(&p, 1) != 4 { ok = false; }
  if ir_opcode(&p, 2) != CG_OP_RET { ok = false; }
  if ir_opcode(&p, 3) != CG_NONE { ok = false; }
  if ir_opcode(&p, -1) != CG_NONE { ok = false; }
  if ir_a(&p, 9) != 0 { ok = false; }
  if ir_b(&p, -2) != 0 { ok = false; }
  return assert(ok, "ir: push/len/opcode/operands and out-of-range defaults");
}

fn t12() -> TestResult {
  var p = fixture_prog();
  ir_set(&mut p, 1, CG_OP_SUB, 30, 40);
  var ok = ir_opcode(&p, 1) == CG_OP_SUB;
  if ir_a(&p, 1) != 30 { ok = false; }
  if ir_b(&p, 1) != 40 { ok = false; }
  ir_set(&mut p, 9, CG_OP_NOP, 0, 0);
  ir_set(&mut p, -1, CG_OP_NOP, 0, 0);
  if ir_len(&p) != 4 { ok = false; }
  if ir_opcode(&p, 3) != CG_OP_MUL { ok = false; }
  if ir_b(&p, 0) != 0 { ok = false; }
  return assert(ok, "ir: ir_set overwrites in range and ignores out of range");
}

fn t13() -> TestResult {
  var ok = streq(ir_op_name(CG_OP_LABEL), "label");
  if !streq(ir_op_name(CG_OP_NOP), "nop") { ok = false; }
  if !streq(ir_op_name(CG_OP_MOV), "mov") { ok = false; }
  if !streq(ir_op_name(CG_OP_ADD), "add") { ok = false; }
  if !streq(ir_op_name(CG_OP_SUB), "sub") { ok = false; }
  if !streq(ir_op_name(CG_OP_MUL), "mul") { ok = false; }
  if !streq(ir_op_name(CG_OP_LOAD), "load") { ok = false; }
  if !streq(ir_op_name(CG_OP_STORE), "store") { ok = false; }
  if !streq(ir_op_name(CG_OP_JMP), "jmp") { ok = false; }
  if !streq(ir_op_name(CG_OP_JZ), "jz") { ok = false; }
  if !streq(ir_op_name(CG_OP_CALL), "call") { ok = false; }
  if !streq(ir_op_name(CG_OP_RET), "ret") { ok = false; }
  if !streq(ir_op_name(99), "op99") { ok = false; }
  if !streq(ir_op_name(CG_NONE), "op-1") { ok = false; }
  return assert(ok, "ir: ir_op_name covers every opcode and falls back to op<code>");
}

fn t14() -> TestResult {
  var e = emitter_new();
  emitter_line(&mut e, "head");
  emitter_indent(&mut e);
  emitter_line(&mut e, "body");
  emitter_indent(&mut e);
  emitter_line(&mut e, "deep");
  emitter_dedent(&mut e);
  emitter_line(&mut e, "body2");
  emitter_dedent(&mut e);
  emitter_dedent(&mut e);
  emitter_line(&mut e, "tail");
  var ok = emitter_len(&e) == 5;
  if emitter_depth(&e) != 0 { ok = false; }
  if !streq(emitter_line_at(&e, 0), "head") { ok = false; }
  if !streq(emitter_line_at(&e, 1), "  body") { ok = false; }
  if !streq(emitter_line_at(&e, 2), "    deep") { ok = false; }
  if !streq(emitter_line_at(&e, 3), "  body2") { ok = false; }
  if !streq(emitter_line_at(&e, 4), "tail") { ok = false; }
  return assert(ok, "emitter: indent/dedent prefixes lines with the indent unit");
}

fn t15() -> TestResult {
  var e = emitter_new();
  emitter_line(&mut e, "mov 1, 2");
  emitter_line_comment(&mut e, "add 1, 3", "folded");
  emitter_blank(&mut e);
  emitter_indent(&mut e);
  emitter_line_comment(&mut e, "ret", "epilogue");
  let want = "mov 1, 2\nadd 1, 3 ; folded\n\n  ret ; epilogue\n";
  var ok = streq(emitter_text(&e), want);
  if !streq(emitter_line_at(&e, 2), "") { ok = false; }
  if !streq(emitter_line_at(&e, 3), "  ret ; epilogue") { ok = false; }
  emitter_set_unit(&mut e, "\t");
  emitter_line(&mut e, "x");
  if !streq(emitter_line_at(&e, 4), "\tx") { ok = false; }
  return assert(ok, "emitter: per-line comments, blanks, custom unit and exact text");
}

fn t16() -> TestResult {
  var e = emitter_new();
  emitter_dedent(&mut e);
  emitter_dedent(&mut e);
  var ok = emitter_depth(&e) == 0 && emitter_len(&e) == 0;
  if !streq(emitter_text(&e), "") { ok = false; }
  if !streq(emitter_line_at(&e, 0), "") { ok = false; }
  if !streq(emitter_line_at(&e, -1), "") { ok = false; }
  return assert(ok, "emitter: empty document and out-of-range/dedent clamps");
}

fn t17() -> TestResult {
  let rules = fixture_rules();
  let p = fixture_prog();
  let out = peep_apply(&p, &rules);
  var ok = peep_rule_count(&rules) == 5;
  if ir_len(&out) != 2 { ok = false; }
  if ir_opcode(&out, 0) != CG_OP_ADD { ok = false; }
  if ir_a(&out, 0) != 6 { ok = false; }
  if ir_b(&out, 0) != 1 { ok = false; }
  if ir_opcode(&out, 1) != CG_OP_MOV { ok = false; }
  if ir_a(&out, 1) != 8 { ok = false; }
  if ir_b(&out, 1) != 0 { ok = false; }
  return assert(ok, "peephole: one-instruction windows erase and rewrite");
}

fn t18() -> TestResult {
  let rules = fixture_rules();
  var na = ir_new();
  ir_push(&mut na, CG_OP_NOP, 0, 0);
  ir_push(&mut na, CG_OP_NOP, 0, 0);
  ir_push(&mut na, CG_OP_RET, 0, 0);
  let outa = peep_apply(&na, &rules);
  var ok = ir_len(&outa) == 1;
  if ir_opcode(&outa, 0) != CG_OP_RET { ok = false; }
  var nb = ir_new();
  ir_push(&mut nb, CG_OP_MOV, 7, 9);
  ir_push(&mut nb, CG_OP_RET, 0, 0);
  let outb = peep_apply(&nb, &rules);
  if ir_len(&outb) != 1 { ok = false; }
  if ir_opcode(&outb, 0) != CG_OP_RET { ok = false; }
  var nc = ir_new();
  ir_push(&mut nc, CG_OP_MOV, 8, 9);
  ir_push(&mut nc, CG_OP_RET, 0, 0);
  let outc = peep_apply(&nc, &rules);
  if ir_len(&outc) != 2 { ok = false; }
  return assert(ok, "peephole: two-instruction windows replace or erase");
}

fn t19() -> TestResult {
  var p = ir_new();
  ir_push(&mut p, CG_OP_ADD, 5, 0);
  var r1 = peep_rules_new();
  peep_rule_add(&mut r1, CG_OP_ADD, CG_PAT_END, CG_WILD, 0, CG_OP_MOV, CG_FWD_A, 0);
  peep_rule_add(&mut r1, CG_OP_ADD, CG_PAT_END, CG_WILD, 0, CG_ERASE, 0, 0);
  let out1 = peep_apply(&p, &r1);
  var ok = ir_len(&out1) == 1;
  if ir_opcode(&out1, 0) != CG_OP_MOV { ok = false; }
  if ir_a(&out1, 0) != 5 { ok = false; }
  var r2 = peep_rules_new();
  peep_rule_add(&mut r2, CG_OP_ADD, CG_PAT_END, CG_WILD, 0, CG_ERASE, 0, 0);
  peep_rule_add(&mut r2, CG_OP_ADD, CG_PAT_END, CG_WILD, 0, CG_OP_MOV, CG_FWD_A, 0);
  let out2 = peep_apply(&p, &r2);
  if ir_len(&out2) != 0 { ok = false; }
  return assert(ok, "peephole: first-match-wins respects registration order");
}

fn t20() -> TestResult {
  let rules = fixture_rules();
  var p = ir_new();
  ir_push(&mut p, CG_OP_MOV, 1, 2);
  ir_push(&mut p, CG_OP_ADD, 3, 4);
  let out1 = peep_apply(&p, &rules);
  var ok = ir_equal(&p, &out1);
  let out2 = peep_apply(&p, &rules);
  if !ir_equal(&out1, &out2) { ok = false; }
  var empty = ir_new();
  let oute = peep_apply(&empty, &rules);
  if ir_len(&oute) != 0 { ok = false; }
  return assert(ok, "peephole: non-matching programs are copied unchanged; deterministic");
}

fn t21() -> TestResult {
  let rules = fixture_rules();
  var p = ir_new();
  ir_push(&mut p, CG_OP_ADD, 5, 0);
  let out1 = peep_apply(&p, &rules);
  var ok = ir_len(&out1) == 0;
  var q = ir_new();
  ir_push(&mut q, CG_OP_MOV, 7, 9);
  let out2 = peep_apply(&q, &rules);
  if ir_len(&out2) != 1 { ok = false; }
  if ir_opcode(&out2, 0) != CG_OP_MOV { ok = false; }
  if !ir_equal(&q, &out2) { ok = false; }
  return assert(ok, "peephole: one-instruction rules match at the program tail, two do not");
}

fn t22() -> TestResult {
  var a = label_alloc_new();
  let l0 = label_fresh(&mut a);
  let l1 = label_fresh(&mut a);
  let c = label_commit(&mut a);
  var p = ir_new();
  ir_push(&mut p, CG_OP_LABEL, l0, 0);
  ir_push(&mut p, CG_OP_MOV, 1, 2);
  ir_push(&mut p, CG_OP_ADD, 1, 3);
  ir_push(&mut p, CG_OP_JZ, l1, 0);
  ir_push(&mut p, CG_OP_RET, 0, 0);
  let want = "module demo\n  L0:\n  mov 1, 2\n  add 1, 3\n  jz L1\n  ret\n";
  var ok = c == 2 && streq(cg_render_module("demo", &p), want);
  let empty = ir_new();
  if !streq(cg_render_module("", &empty), "module <anonymous>\n") { ok = false; }
  var u = ir_new();
  ir_push(&mut u, 99, 1, 2);
  if !streq(cg_render_module("u", &u), "module u\n  op99 1, 2\n") { ok = false; }
  if !streq(cg_render_module("demo", &p), want) { ok = false; }
  return assert(ok, "render: exact module text, labels, unknown ops and empty program");
}

fn t23() -> TestResult {
  var a = label_alloc_new();
  let l0 = label_fresh(&mut a);
  let l1 = label_fresh(&mut a);
  let c = label_commit(&mut a);
  var p = ir_new();
  ir_push(&mut p, CG_OP_LABEL, l0, 0);
  ir_push(&mut p, CG_OP_MUL, 5, 1);
  ir_push(&mut p, CG_OP_MOV, 3, 4);
  ir_push(&mut p, CG_OP_JZ, l1, 0);
  ir_push(&mut p, CG_OP_LABEL, l1, 0);
  ir_push(&mut p, CG_OP_RET, 0, 0);
  let rules = fixture_rules();
  let out = peep_apply(&p, &rules);
  let text = cg_render_module("pipeline", &out);
  let want = "module pipeline\n  L0:\n  mov 3, 4\n  jz L1\n  L1:\n  ret\n";
  var ok = c == 2 && streq(text, want);
  if label_committed(&a) != 2 { ok = false; }
  if label_pending(&a) != 0 { ok = false; }
  let out2 = peep_apply(&p, &rules);
  if !ir_equal(&out, &out2) { ok = false; }
  if !streq(cg_render_module("pipeline", &out2), want) { ok = false; }
  if !streq(label_text(l0), "L0") { ok = false; }
  return assert(ok, "pipeline: labels + IR + peephole + render end to end, deterministic");
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
  io.println("=== xiom.codegen-fw conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.codegen-fw: all tests passed");
  } else {
    io.println("xiom.codegen-fw: tests failed");
  }
  return failed;
}
