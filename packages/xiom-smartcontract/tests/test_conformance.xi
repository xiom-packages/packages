// XIOM -- xiom.smartcontract conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixture-driven, deterministic conformance suite. Every program is built
// in-test (through the assembler, or as raw bytes for malformed cases), and
// every expected value -- return value, gas, step count, trap text, trace
// line -- is a literal in this file. Covers: assembler encoding and the asm
// error catalog, canonical disassembly and both round-trip directions,
// arithmetic (including negative division/modulo and checked overflow),
// branches (JUMP/JUMPI taken and not taken, REVERT), gas accounting and
// exhaustion, stack underflow/overflow, memory slots, label validation,
// malformed-program rejection, past-the-end traps, and trace determinism.
//
// Harness style mirrors xiom.hello / xiom.ethereum: one fn tN() -> TestResult
// per check, called directly from main (no fn tables); main prints
// [PASS]/[FAIL] and returns the failure count. Str payloads are compared with
// compare.str_compare (BUG 17 discipline: `==` on Str values read from a
// Vec lowers to a pointer comparison), and Vec[Int]/Vec[UInt8] element reads
// are bound to typed locals first.

module smartcontract_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.smartcontract;

// --------------------------------------------------
//  Fixture helpers
// --------------------------------------------------

// Bytes of a Str, byte-for-byte.
fn ab(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if ((x as Int) & 0xFF) != ((y as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Byte `i` of a byte vector widened to an Int (0..255).
fn bv(v: &Vec[UInt8], i: Int) -> Int {
  let b: UInt8 = v[i];
  return (b as Int) & 0xFF;
}

fn str_is(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn raw1(a: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  return v;
}

fn raw2(a: Int, b: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  return v;
}

fn raw3(a: Int, b: Int, c: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(a as UInt8);
  v.push(b as UInt8);
  v.push(c as UInt8);
  return v;
}

// Assemble, or an empty program on assembler error (the test then fails on
// the byte/return comparison).
fn asm(text: Str) -> Vec[UInt8] {
  let r = sc_assemble(text);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

// Assembler error text, or "" when assembly succeeded.
fn asm_err(text: Str) -> Str {
  let r = sc_assemble(text);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn asm_err_is(text: Str, want: Str) -> Bool {
  return str_is(asm_err(text), want);
}

fn asm_err_prefix(text: Str, prefix: Str) -> Bool {
  let e = asm_err(text);
  if str_is(e, "") {
    return false;
  }
  return string.str_starts_with(e, prefix);
}

// Disassembly text, or "" on decode error.
fn dis(prog: &Vec[UInt8]) -> Str {
  let r = sc_disassemble(prog);
  if !r.is_ok {
    return "";
  }
  let s: Str = r.value;
  return s;
}

// Instruction count from sc_validate, or -1 on error.
fn val(prog: &Vec[UInt8]) -> Int {
  let r = sc_validate(prog);
  if !r.is_ok {
    return -1;
  }
  let n: Int = r.value;
  return n;
}

// A never-produced outcome so a failed program build stays a soft test
// failure instead of touching an Err payload.
fn sentinel() -> VmOutcome {
  return VmOutcome{
    status: -1;
    exit_code: 0;
    return_value: 0;
    error: "";
    gas_used: 0;
    steps: 0;
    trace_pc: Vec[Int].new();
    trace_op: Vec[Int].new();
    trace_arg: Vec[Int].new();
    trace_has_arg: Vec[Int].new();
    trace_gas_before: Vec[Int].new();
    trace_gas_after: Vec[Int].new();
    trace_depth: Vec[Int].new();
    trace_top: Vec[Int].new();
    mem_keys: Vec[Int].new();
    mem_vals: Vec[Int].new();
  };
}

// Run an (assumed valid) program, or the sentinel on Err.
fn run_get(prog: Vec[UInt8], gas: Int) -> VmOutcome {
  let r = vm_run(&prog, gas);
  if r.is_ok {
    let o: VmOutcome = r.value;
    return o;
  }
  return sentinel();
}

// Return value of a program expected to STOP, or -999999 otherwise.
fn run_val(prog: Vec[UInt8]) -> Int {
  let o = run_get(prog, 1000000);
  if !vm_stopped(&o) {
    return -999999;
  }
  return vm_return_value(&o);
}

// vm_run error text, or "" when the run returned an outcome.
fn run_err(prog: &Vec[UInt8], gas: Int) -> Str {
  let r = vm_run(prog, gas);
  if r.is_ok {
    return "";
  }
  return r.error;
}

fn err_is(prog: &Vec[UInt8], gas: Int, want: Str) -> Bool {
  let e = run_err(prog, gas);
  if str_is(e, "") {
    return false;
  }
  return str_is(e, want);
}

// True when the execution traps with exactly `want` as the error text.
fn trap_is(prog: &Vec[UInt8], gas: Int, want: Str) -> Bool {
  let r = vm_run(prog, gas);
  if !r.is_ok {
    return false;
  }
  let o: VmOutcome = r.value;
  if !vm_trapped(&o) {
    return false;
  }
  return str_is(vm_error(&o), want);
}

// --------------------------------------------------
//  Assembler / disassembler
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let p = asm("PUSH 5\nSTOP\n");
  if p.len() != 10 { ok = false; }
  if bv(&p, 0) != sc_op_push() { ok = false; }
  if bv(&p, 1) != 0 { ok = false; }
  if bv(&p, 7) != 0 { ok = false; }
  if bv(&p, 8) != 5 { ok = false; }
  if bv(&p, 9) != sc_op_stop() { ok = false; }
  let n: Int = val(&p);
  if n != 2 { ok = false; }
  let q = asm("POP\nDUP\nSWAP\nADD\nSUB\nMUL\nDIV\nMOD\nCMP\nMLOAD\nMSTORE\nREVERT\nSTOP\n");
  if q.len() != 13 { ok = false; }
  if bv(&q, 0) != sc_op_pop() { ok = false; }
  if bv(&q, 11) != sc_op_revert() { ok = false; }
  if bv(&q, 12) != sc_op_stop() { ok = false; }
  if !str_is(sc_op_name(sc_op_push()), "PUSH") { ok = false; }
  if !str_is(sc_op_name(sc_op_revert()), "REVERT") { ok = false; }
  if !str_is(sc_op_name(99), "") { ok = false; }
  if sc_gas_cost(sc_op_label()) != 0 { ok = false; }
  if sc_gas_cost(sc_op_mstore()) != 3 { ok = false; }
  if sc_gas_cost(200) != -1 { ok = false; }
  return assert(ok, "assembler encodes PUSH/operand and zero-operand opcodes; metadata agrees");
}

fn t2() -> TestResult {
  let text = "LABEL 1\nPUSH 7\nDUP\nCMP\nJUMPI 1\nPUSH 9\nSTOP\n";
  let p = asm(text);
  var ok = true;
  if p.len() != (9 + 9 + 1 + 1 + 9 + 9 + 1) { ok = false; }
  let d = dis(&p);
  if !str_is(d, text) { ok = false; }
  let p2 = asm(d);
  if !bytes_equal(p, p2) { ok = false; }
  let d2 = dis(&p2);
  if !str_is(d2, text) { ok = false; }
  let n: Int = val(&p);
  if n != 7 { ok = false; }
  return assert(ok, "canonical disassembly text round-trips byte-for-byte");
}

fn t3() -> TestResult {
  let text = "PUSH -1\nSTOP\n";
  let p = asm(text);
  var ok = p.len() == 10;
  let d = dis(&p);
  if !str_is(d, text) { ok = false; }
  if !bytes_equal(asm(d), p) { ok = false; }
  // A second text -> bytecode -> text -> bytecode pass on a label-rich program.
  let text2 = "PUSH 1\nJUMPI 10\nPUSH 111\nREVERT\nLABEL 10\nPUSH 222\nSTOP\n";
  let bc = asm(text2);
  let t1 = dis(&bc);
  if !str_is(t1, text2) { ok = false; }
  if !bytes_equal(asm(t1), bc) { ok = false; }
  return assert(ok, "assemble/disassemble round-trip on negative operands and labels");
}

// --------------------------------------------------
//  Arithmetic, stack, branches
// --------------------------------------------------

fn t4() -> TestResult {
  let p = asm("PUSH 2\nPUSH 3\nADD\nPUSH 4\nMUL\nSTOP\n");
  var ok = true;
  let o = run_get(p, 100);
  if !vm_stopped(&o) { ok = false; }
  if vm_return_value(&o) != 20 { ok = false; }
  if vm_exit_code(&o) != 0 { ok = false; }
  if !str_is(vm_error(&o), "") { ok = false; }
  if vm_gas_used(&o) != 6 { ok = false; }
  if vm_steps(&o) != 6 { ok = false; }
  if vm_trace_len(&o) != 6 { ok = false; }
  if vm_trace_pc(&o, 0) != 0 { ok = false; }
  if vm_trace_pc(&o, 2) != 18 { ok = false; }
  if vm_trace_pc(&o, 5) != 29 { ok = false; }
  if vm_trace_op(&o, 1) != sc_op_push() { ok = false; }
  if vm_trace_arg(&o, 1) != 3 { ok = false; }
  if !vm_trace_has_arg(&o, 1) { ok = false; }
  if vm_trace_has_arg(&o, 2) { ok = false; }
  if vm_trace_depth(&o, 1) != 2 { ok = false; }
  if vm_trace_top(&o, 4) != 20 { ok = false; }
  if vm_trace_gas_before(&o, 2) != 2 { ok = false; }
  if vm_trace_gas_after(&o, 2) != 3 { ok = false; }
  if vm_trace_pc(&o, 6) != -1 { ok = false; }
  return assert(ok, "ADD/MUL: return value, gas, step count and trace records");
}

fn t5() -> TestResult {
  var ok = true;
  if run_val(asm("PUSH 10\nPUSH 3\nSUB\nSTOP\n")) != 7 { ok = false; }
  if run_val(asm("PUSH 7\nPUSH 2\nDIV\nSTOP\n")) != 3 { ok = false; }
  if run_val(asm("PUSH -7\nPUSH 2\nDIV\nSTOP\n")) != -3 { ok = false; }
  if run_val(asm("PUSH 7\nPUSH 2\nMOD\nSTOP\n")) != 1 { ok = false; }
  if run_val(asm("PUSH -7\nPUSH 2\nMOD\nSTOP\n")) != -1 { ok = false; }
  if run_val(asm("PUSH 7\nPUSH -2\nMOD\nSTOP\n")) != 1 { ok = false; }
  if run_val(asm("PUSH 5\nPUSH 5\nCMP\nSTOP\n")) != 0 { ok = false; }
  if run_val(asm("PUSH 4\nPUSH 5\nCMP\nSTOP\n")) != -1 { ok = false; }
  if run_val(asm("PUSH 5\nPUSH 4\nCMP\nSTOP\n")) != 1 { ok = false; }
  return assert(ok, "SUB/DIV/MOD (truncation toward zero, sign of dividend) and CMP");
}

fn t6() -> TestResult {
  var ok = true;
  if run_val(asm("PUSH 5\nDUP\nADD\nSTOP\n")) != 10 { ok = false; }
  if run_val(asm("PUSH 1\nPUSH 2\nSWAP\nSUB\nSTOP\n")) != 1 { ok = false; }
  if run_val(asm("PUSH 1\nPUSH 2\nPOP\nSTOP\n")) != 1 { ok = false; }
  let o = run_get(asm("PUSH 8\nDUP\nSTOP\n"), 100);
  if vm_trace_depth(&o, 1) != 2 { ok = false; }
  if vm_trace_top(&o, 1) != 8 { ok = false; }
  let o2 = run_get(asm("PUSH 1\nPUSH 2\nPOP\nSTOP\n"), 100);
  if vm_trace_depth(&o2, 2) != 1 { ok = false; }
  return assert(ok, "DUP/SWAP/POP stack effects");
}

fn t7() -> TestResult {
  var ok = true;
  let text = "PUSH 1\nJUMPI 10\nPUSH 111\nREVERT\nLABEL 10\nPUSH 222\nSTOP\n";
  let o = run_get(asm(text), 100);
  if !vm_stopped(&o) { ok = false; }
  if vm_return_value(&o) != 222 { ok = false; }
  if vm_steps(&o) != 5 { ok = false; }
  if vm_gas_used(&o) != 5 { ok = false; }
  if vm_trace_pc(&o, 0) != 0 { ok = false; }
  if vm_trace_pc(&o, 1) != 9 { ok = false; }
  if vm_trace_pc(&o, 2) != 28 { ok = false; }
  if vm_trace_pc(&o, 3) != 37 { ok = false; }
  if vm_trace_pc(&o, 4) != 46 { ok = false; }
  let text0 = "PUSH 0\nJUMPI 10\nPUSH 111\nREVERT\nLABEL 10\nPUSH 222\nSTOP\n";
  let o0 = run_get(asm(text0), 100);
  if !vm_reverted(&o0) { ok = false; }
  if vm_exit_code(&o0) != 111 { ok = false; }
  if vm_return_value(&o0) != 0 { ok = false; }
  if !str_is(vm_error(&o0), "") { ok = false; }
  if vm_steps(&o0) != 4 { ok = false; }
  if vm_trace_pc(&o0, 3) != 27 { ok = false; }
  return assert(ok, "JUMPI: taken branch jumps, zero falls through into REVERT");
}

fn t8() -> TestResult {
  let p = asm("JUMP 5\nPUSH 1\nSTOP\nLABEL 5\nPUSH 42\nSTOP\n");
  var ok = true;
  let n: Int = val(&p);
  if n != 6 { ok = false; }
  let o = run_get(p, 100);
  if !vm_stopped(&o) { ok = false; }
  if vm_return_value(&o) != 42 { ok = false; }
  if vm_steps(&o) != 4 { ok = false; }
  if vm_gas_used(&o) != 3 { ok = false; }
  if !str_is(vm_trace_line(&o, 0), "pc 0 JUMP 5 gas 0->2 depth 0") { ok = false; }
  if !str_is(vm_trace_line(&o, 1), "pc 19 LABEL 5 gas 2->2 depth 0") { ok = false; }
  if !str_is(vm_trace_line(&o, 2), "pc 28 PUSH 42 gas 2->3 depth 1 top 42") { ok = false; }
  if !str_is(vm_trace_line(&o, 3), "pc 37 STOP gas 3->3 depth 1 top 42") { ok = false; }
  if !str_is(vm_trace_line(&o, 4), "") { ok = false; }
  return assert(ok, "JUMP to a label; LABEL is a zero-gas traceable no-op");
}

// --------------------------------------------------
//  Gas
// --------------------------------------------------

fn t9() -> TestResult {
  var ok = true;
  let p = asm("PUSH 1\nPUSH 2\nADD\nSTOP\n");
  if !trap_is(&p, 2, "vm: out of gas at pc 18 (need 1, have 0)") { ok = false; }
  let o2 = run_get(p, 2);
  if !vm_trapped(&o2) { ok = false; }
  if vm_status(&o2) != sc_status_trapped() { ok = false; }
  if vm_steps(&o2) != 2 { ok = false; }
  if vm_gas_used(&o2) != 2 { ok = false; }
  if !str_is(vm_error(&o2), "vm: out of gas at pc 18 (need 1, have 0)") { ok = false; }
  let p3 = asm("PUSH 2\nPUSH 3\nADD\nSTOP\n");
  let o3 = run_get(p3, 3);
  if !vm_stopped(&o3) { ok = false; }
  if vm_return_value(&o3) != 5 { ok = false; }
  if vm_gas_used(&o3) != 3 { ok = false; }
  if vm_steps(&o3) != 4 { ok = false; }
  if !trap_is(&p3, 0, "vm: out of gas at pc 0 (need 1, have 0)") { ok = false; }
  let rn = vm_run(&p3, -1);
  if rn.is_ok { ok = false; } else if !str_is(rn.error, "vm: negative gas limit") { ok = false; }
  return assert(ok, "gas metering: exhaustion, exact fit, zero budget, negative limit");
}

fn t10() -> TestResult {
  var ok = true;
  if !trap_is(&asm("ADD\nSTOP\n"), 100, "vm: stack underflow at pc 0") { ok = false; }
  if !trap_is(&asm("POP\nSTOP\n"), 100, "vm: stack underflow at pc 0") { ok = false; }
  if !trap_is(&asm("REVERT\n"), 100, "vm: stack underflow at pc 0") { ok = false; }
  if !trap_is(&asm("PUSH 1\nSWAP\nSTOP\n"), 100, "vm: stack underflow at pc 9") { ok = false; }
  let o = run_get(asm("ADD\nSTOP\n"), 100);
  if !vm_trapped(&o) { ok = false; }
  if vm_steps(&o) != 0 { ok = false; }
  if vm_gas_used(&o) != 0 { ok = false; }
  return assert(ok, "stack underflow aborts without charging or tracing the instruction");
}

fn t11() -> TestResult {
  var text: Str = "";
  var i = 0;
  while i < 1025 {
    text = text + "PUSH 1\n";
    i = i + 1;
  }
  text = text + "STOP\n";
  let p = asm(text);
  var ok = p.len() == (1025 * 9 + 1);
  let o = run_get(p, 2000);
  if !vm_trapped(&o) { ok = false; }
  if vm_steps(&o) != 1024 { ok = false; }
  if vm_gas_used(&o) != 1024 { ok = false; }
  if !str_is(vm_error(&o), "vm: stack overflow at pc 9216") { ok = false; }
  if sc_max_stack() != 1024 { ok = false; }
  return assert(ok, "stack overflow at the 1025th push (cap 1024)");
}

fn t12() -> TestResult {
  let o = run_get(asm("PUSH 7\nREVERT\n"), 100);
  var ok = true;
  if !vm_reverted(&o) { ok = false; }
  if vm_exit_code(&o) != 7 { ok = false; }
  if vm_return_value(&o) != 0 { ok = false; }
  if !str_is(vm_error(&o), "") { ok = false; }
  if vm_gas_used(&o) != 1 { ok = false; }
  if vm_steps(&o) != 2 { ok = false; }
  if !str_is(vm_trace_line(&o, 1), "pc 9 REVERT gas 1->1 depth 0") { ok = false; }
  return assert(ok, "REVERT halts with the popped exit code and is traceable");
}

// --------------------------------------------------
//  Memory
// --------------------------------------------------

fn t13() -> TestResult {
  var ok = true;
  let o = run_get(asm("PUSH 42\nPUSH 7\nMSTORE\nPUSH 7\nMLOAD\nSTOP\n"), 100);
  if !vm_stopped(&o) { ok = false; }
  if vm_return_value(&o) != 42 { ok = false; }
  if vm_mem_len(&o) != 1 { ok = false; }
  if vm_mem_key(&o, 0) != 7 { ok = false; }
  if vm_mem_value(&o, 0) != 42 { ok = false; }
  if !vm_mem_has(&o, 7) { ok = false; }
  if vm_mem_has(&o, 8) { ok = false; }
  if vm_mem_find(&o, 7) != 0 { ok = false; }
  if vm_mem_find(&o, 8) != -1 { ok = false; }
  if vm_mem_key(&o, 5) != 0 { ok = false; }
  // Overwrite keeps one slot; a second key adds a slot in insertion order.
  let o2 = run_get(asm("PUSH 1\nPUSH 7\nMSTORE\nPUSH 2\nPUSH 7\nMSTORE\nPUSH 7\nMLOAD\nSTOP\n"), 100);
  if vm_mem_len(&o2) != 1 { ok = false; }
  if vm_mem_value(&o2, 0) != 2 { ok = false; }
  if vm_return_value(&o2) != 2 { ok = false; }
  let o3 = run_get(asm("PUSH 5\nPUSH 1\nMSTORE\nPUSH 6\nPUSH 2\nMSTORE\nPUSH 2\nMLOAD\nPUSH 1\nMLOAD\nADD\nSTOP\n"), 100);
  if vm_mem_len(&o3) != 2 { ok = false; }
  if vm_mem_key(&o3, 0) != 1 { ok = false; }
  if vm_mem_key(&o3, 1) != 2 { ok = false; }
  if vm_mem_value(&o3, 0) != 5 { ok = false; }
  if vm_mem_value(&o3, 1) != 6 { ok = false; }
  if vm_return_value(&o3) != 11 { ok = false; }
  return assert(ok, "MSTORE/MLOAD: keyed slots, overwrite, insertion order, accessors");
}

fn t14() -> TestResult {
  let p = asm("PUSH 3\nMLOAD\nSTOP\n");
  var ok = trap_is(&p, 100, "vm: memory slot 3 is not initialized at pc 9");
  let o = run_get(p, 100);
  if !vm_trapped(&o) { ok = false; }
  if vm_steps(&o) != 1 { ok = false; }
  if vm_mem_len(&o) != 0 { ok = false; }
  return assert(ok, "MLOAD of an unset memory slot aborts");
}

// --------------------------------------------------
//  Validation and malformed programs
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = true;
  let p = asm("LABEL 1\nSTOP\nLABEL 1\nSTOP\n");
  if !err_is(&p, 100, "program: duplicate label id 1") { ok = false; }
  let vr = sc_validate(&p);
  if vr.is_ok { ok = false; } else if !str_is(vr.error, "program: duplicate label id 1") { ok = false; }
  let p2 = asm("LABEL 1\nLABEL 2\nSTOP\n");
  if val(&p2) != 3 { ok = false; }
  return assert(ok, "duplicate label ids are rejected; distinct labels validate");
}

fn t16() -> TestResult {
  var ok = true;
  let p = asm("JUMP 2\nSTOP\n");
  if !err_is(&p, 100, "program: unknown label 2 at pc 0") { ok = false; }
  let vr = sc_validate(&p);
  if vr.is_ok { ok = false; } else if !str_is(vr.error, "program: unknown label 2 at pc 0") { ok = false; }
  // Decoding does not need jump targets: the disassembler still renders it.
  if !str_is(dis(&p), "JUMP 2\nSTOP\n") { ok = false; }
  return assert(ok, "jumps to undefined labels are rejected by validate/run, not by decode");
}

fn t17() -> TestResult {
  var ok = true;
  let p = raw1(17);
  if !err_is(&p, 100, "program: unknown opcode 17 at pc 0") { ok = false; }
  let p2 = raw1(255);
  if !err_is(&p2, 100, "program: unknown opcode 255 at pc 0") { ok = false; }
  let dr = sc_disassemble(&p);
  if dr.is_ok { ok = false; } else if !str_is(dr.error, "program: unknown opcode 17 at pc 0") { ok = false; }
  let vr = sc_validate(&p);
  if vr.is_ok { ok = false; } else if !str_is(vr.error, "program: unknown opcode 17 at pc 0") { ok = false; }
  return assert(ok, "unknown opcode bytes are rejected by run, validate and disassemble");
}

fn t18() -> TestResult {
  var ok = true;
  let p = raw2(sc_op_push(), 0);
  if !err_is(&p, 100, "program: truncated instruction at pc 0") { ok = false; }
  let p2 = raw1(sc_op_label());
  if !err_is(&p2, 100, "program: truncated instruction at pc 0") { ok = false; }
  let p3 = raw3(sc_op_stop(), sc_op_jump(), 0);
  if !err_is(&p3, 100, "program: truncated instruction at pc 1") { ok = false; }
  return assert(ok, "truncated 8-byte operands are rejected with the exact pc");
}

// --------------------------------------------------
//  Checked arithmetic edge cases
// --------------------------------------------------

fn t19() -> TestResult {
  var ok = true;
  if !trap_is(&asm("PUSH 9223372036854775807\nPUSH 1\nADD\nSTOP\n"), 100, "vm: arithmetic overflow at pc 18") { ok = false; }
  if !trap_is(&asm("PUSH -9223372036854775808\nPUSH 1\nSUB\nSTOP\n"), 100, "vm: arithmetic overflow at pc 18") { ok = false; }
  if !trap_is(&asm("PUSH 9223372036854775807\nPUSH 2\nMUL\nSTOP\n"), 100, "vm: arithmetic overflow at pc 18") { ok = false; }
  if !trap_is(&asm("PUSH -9223372036854775808\nPUSH -1\nDIV\nSTOP\n"), 100, "vm: arithmetic overflow at pc 18") { ok = false; }
  if run_val(asm("PUSH -9223372036854775808\nPUSH -1\nMOD\nSTOP\n")) != 0 { ok = false; }
  if run_val(asm("PUSH -9223372036854775808\nSTOP\n")) != sc_int_min() { ok = false; }
  let pmin = asm("PUSH -9223372036854775808\nSTOP\n");
  if !str_is(dis(&pmin), "PUSH -9223372036854775808\nSTOP\n") { ok = false; }
  if !bytes_equal(asm(dis(&pmin)), pmin) { ok = false; }
  if run_val(asm("PUSH 9223372036854775807\nSTOP\n")) != sc_int_max() { ok = false; }
  if run_val(asm("PUSH -2\nPUSH 3\nMUL\nSTOP\n")) != -6 { ok = false; }
  if run_val(asm("PUSH -9223372036854775807\nPUSH -1\nMUL\nSTOP\n")) != 9223372036854775807 { ok = false; }
  return assert(ok, "checked ADD/SUB/MUL/DIV bounds, INT64_MIN edge cases, exact operands");
}

fn t20() -> TestResult {
  var ok = true;
  if !trap_is(&asm("PUSH 1\nPUSH 0\nDIV\nSTOP\n"), 100, "vm: division by zero at pc 18") { ok = false; }
  if !trap_is(&asm("PUSH 1\nPUSH 0\nMOD\nSTOP\n"), 100, "vm: modulo by zero at pc 18") { ok = false; }
  let o = run_get(asm("PUSH 5\nPUSH 0\nDIV\nSTOP\n"), 100);
  if !vm_trapped(&o) { ok = false; }
  if vm_gas_used(&o) != 2 { ok = false; }
  if vm_steps(&o) != 2 { ok = false; }
  return assert(ok, "division and modulo by zero abort with distinct texts");
}

// --------------------------------------------------
//  Past-the-end, trace determinism, assembler errors
// --------------------------------------------------

fn t21() -> TestResult {
  var ok = true;
  let p = asm("PUSH 1\n");
  let o = run_get(p, 100);
  if !vm_trapped(&o) { ok = false; }
  if !str_is(vm_error(&o), "vm: execution ran past the end of the program at pc 9") { ok = false; }
  if vm_steps(&o) != 1 { ok = false; }
  if vm_gas_used(&o) != 1 { ok = false; }
  let pa = asm("PUSH 2\nPUSH 3\nADD\nPUSH 4\nMUL\nSTOP\n");
  let oa = run_get(pa, 1000);
  let ob = run_get(pa, 1000);
  let ta = vm_trace_text(&oa);
  let tb = vm_trace_text(&ob);
  if !str_is(ta, tb) { ok = false; }
  let want = "pc 0 PUSH 2 gas 0->1 depth 1 top 2\npc 9 PUSH 3 gas 1->2 depth 2 top 3\npc 18 ADD gas 2->3 depth 1 top 5\npc 19 PUSH 4 gas 3->4 depth 2 top 4\npc 28 MUL gas 4->6 depth 1 top 20\npc 29 STOP gas 6->6 depth 1 top 20\n";
  if !str_is(ta, want) { ok = false; }
  return assert(ok, "falling past the last instruction traps; traces are byte-identical across runs");
}

fn t22() -> TestResult {
  var ok = true;
  if !asm_err_is("PUSH x\n", "asm: operand is not an integer at line 1") { ok = false; }
  if !asm_err_is("PUSH\n", "asm: missing operand at line 1") { ok = false; }
  if !asm_err_is("JUMP\n", "asm: missing operand at line 1") { ok = false; }
  if !asm_err_is("ADD 1\n", "asm: unexpected operand at line 1") { ok = false; }
  if !asm_err_is("STOP 2\n", "asm: unexpected operand at line 1") { ok = false; }
  if !asm_err_is("PUSH 1 2\n", "asm: unexpected operand at line 1") { ok = false; }
  if !asm_err_is("FROB 3\n", "asm: unknown mnemonic 'FROB' at line 1") { ok = false; }
  if !asm_err_prefix("PUSH 1\nNOPE\nSTOP\n", "asm: unknown mnemonic 'NOPE' at line 2") { ok = false; }
  if !asm_err_is("\n; c\nPUSH x\n", "asm: operand is not an integer at line 3") { ok = false; }
  if !asm_err_is("PUSH 9223372036854775808\n", "asm: operand is not an integer at line 1") { ok = false; }
  if !asm_err_is("PUSH -9223372036854775809\n", "asm: operand is not an integer at line 1") { ok = false; }
  let p = asm("  ; header\n\nPUSH 3  ; three\n\tSTOP\n; trailer");
  var ok2 = p.len() == 10;
  if !str_is(dis(&p), "PUSH 3\nSTOP\n") { ok2 = false; }
  if !bytes_equal(asm(dis(&p)), p) { ok2 = false; }
  let e = asm("; nothing\n\n");
  if e.len() != 0 { ok2 = false; }
  if !err_is(&e, 10, "program: empty bytecode") { ok2 = false; }
  let ve = sc_validate(&e);
  if ve.is_ok { ok2 = false; } else if !str_is(ve.error, "program: empty bytecode") { ok2 = false; }
  if !ok { ok2 = false; }
  return assert(ok2, "assembler error catalog, comments/blank lines, empty program rejection");
}

fn main() -> Int {
  io.println("=== xiom.smartcontract conformance tests ===");
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
    io.println("xiom.smartcontract: all tests passed");
  } else {
    io.println("xiom.smartcontract: tests failed");
  }
  return failed;
}
