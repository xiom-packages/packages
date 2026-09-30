// XIOM -- xiom.smartcontract: deterministic pure-XIOM contract stack VM
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A tiny deterministic stack VM for a documented contract-bytecode subset,
// plus an assembler and a disassembler for a compact textual instruction
// format. Nothing here does IO, touches the network, spawns threads, or uses
// FFI: a program is a Vec[UInt8], execution is a pure function of
// (program, gas_limit), and every produced byte, trace record and error text
// is reproducible on every run.
//
//   * Instructions. Each instruction is one opcode byte; PUSH, JUMP, JUMPI
//     and LABEL carry an 8-byte big-endian two's-complement Int operand.
//     Labels are inline no-op markers with an explicit Int id; a jump names
//     its target label and the VM resolves it against the label table built
//     at load time. Programs stay position-independent and the assembler /
//     disassembler round-trips are exact.
//
//   * Stack. One Vec[Int] stack of signed 64-bit words, capped at
//     sc_max_stack() entries; every pop is bounds checked (underflow) and
//     every push is capped (overflow). All arithmetic is checked: overflow
//     and division/modulo by zero abort the execution instead of wrapping.
//
//   * Memory. A keyed Int-to-Int map stored as parallel Vec[Int] key/value
//     vectors; MLOAD of an unset slot is an error, MSTORE on an existing key
//     overwrites its value. Keys are arbitrary Int values.
//
//   * Gas. Every opcode has a fixed cost (sc_gas_cost); an instruction is
//     charged only when it completes, so a trapped instruction is neither
//     charged nor traced. Running out of gas aborts the execution.
//
//   * Traces. Every completed instruction appends one record to eight
//     parallel trace vectors (pc, opcode, operand, gas before/after, stack
//     depth, stack top); vm_trace_line and vm_trace_text render them.
//
//   * Outcomes. vm_run returns Err only when the program itself is invalid
//     (empty, truncated, unknown opcode, duplicate label, unknown jump
//     target) or the gas limit is negative. Execution traps -- stack
//     underflow/overflow, arithmetic overflow, division/modulo by zero,
//     uninitialized memory, out of gas, running past the end -- are reported
//     as a trapped VmOutcome so the partial gas usage and trace stay
//     observable.
//
// v0.62.x discipline that shaped this module: free functions only; every
// Vec[Int]/Vec[UInt8] element read is bound to a typed local first; byte
// reads are widened with `(b as Int) & 0xFF`; Ok/Err for struct payloads are
// built only in the tiny leaf helpers below; `&struct.field` is never passed
// as a `&Vec` argument (fields are indexed in place); mixed binary operators
// are parenthesized.

module xiom.smartcontract

use xiom.string;
use xiom.string.compare;
use xiom.convert;
use xiom.serialize.endian;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Decoded program metadata: the bytecode plus one record per instruction
/// (pc, opcode, operand, operand-presence flag) and the label/jump tables.
/// All vectors are parallel; there is one entry per instruction/label/jump.
type _Program = {
  code: Vec[UInt8];
  insn_pc: Vec[Int];
  insn_op: Vec[Int];
  insn_arg: Vec[Int];
  insn_has_arg: Vec[Int];
  label_id: Vec[Int];
  label_idx: Vec[Int];
  jump_pc: Vec[Int];
  jump_label: Vec[Int];
}

/// The full result of one execution.
///
/// `status` is one of `sc_status_stopped()`, `sc_status_reverted()` or
/// `sc_status_trapped()`; `error` is empty unless the execution trapped.
/// `exit_code` is 0 for STOP and the popped code for REVERT. `return_value`
/// is the top of the stack at STOP (0 when the stack is empty) and 0
/// otherwise. `gas_used` counts the costs of completed instructions only;
/// `steps` equals the trace length. The eight `trace_*` vectors are parallel
/// and hold one record per completed instruction; `mem_*` are the parallel
/// key/value vectors of the final memory map, in insertion order.
pub type VmOutcome = {
  status: Int;
  exit_code: Int;
  return_value: Int;
  error: Str;
  gas_used: Int;
  steps: Int;
  trace_pc: Vec[Int];
  trace_op: Vec[Int];
  trace_arg: Vec[Int];
  trace_has_arg: Vec[Int];
  trace_gas_before: Vec[Int];
  trace_gas_after: Vec[Int];
  trace_depth: Vec[Int];
  trace_top: Vec[Int];
  mem_keys: Vec[Int];
  mem_vals: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors
// --------------------------------------------------

// Ok(v) for Result[_Program, Str].
fn _ok_prog(v: _Program) -> Result[_Program, Str] {
  return Ok(v);
}

// Err(m) for Result[_Program, Str].
fn _err_prog(m: Str) -> Result[_Program, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[VmOutcome, Str].
fn _ok_outcome(v: VmOutcome) -> Result[VmOutcome, Str] {
  return Ok(v);
}

// Err(m) for Result[VmOutcome, Str].
fn _err_outcome(m: Str) -> Result[VmOutcome, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Opcodes
// --------------------------------------------------

/// STOP: halt successfully; the top of the stack (if any) is the result.
pub fn sc_op_stop() -> Int {
  return 0;
}

/// PUSH imm64: push the signed 64-bit immediate operand.
pub fn sc_op_push() -> Int {
  return 1;
}

/// ADD: pop `b`, pop `a`, push `a + b` (checked).
pub fn sc_op_add() -> Int {
  return 2;
}

/// SUB: pop `b`, pop `a`, push `a - b` (checked).
pub fn sc_op_sub() -> Int {
  return 3;
}

/// MUL: pop `b`, pop `a`, push `a * b` (checked).
pub fn sc_op_mul() -> Int {
  return 4;
}

/// DIV: pop `b`, pop `a`, push `a / b`, truncating toward zero (checked).
pub fn sc_op_div() -> Int {
  return 5;
}

/// MOD: pop `b`, pop `a`, push `a % b`; the sign follows the dividend.
pub fn sc_op_mod() -> Int {
  return 6;
}

/// CMP: pop `b`, pop `a`, push -1 when `a < b`, 0 when equal, 1 when `a > b`.
pub fn sc_op_cmp() -> Int {
  return 7;
}

/// JUMP label: continue at the instruction after `LABEL label`.
pub fn sc_op_jump() -> Int {
  return 8;
}

/// JUMPI label: pop `c`; jump when `c != 0`, otherwise fall through.
pub fn sc_op_jumpi() -> Int {
  return 9;
}

/// LABEL id: no-op marker that anchors a jump target.
pub fn sc_op_label() -> Int {
  return 10;
}

/// DUP: push a copy of the top stack item.
pub fn sc_op_dup() -> Int {
  return 11;
}

/// SWAP: exchange the top two stack items.
pub fn sc_op_swap() -> Int {
  return 12;
}

/// POP: discard the top stack item.
pub fn sc_op_pop() -> Int {
  return 13;
}

/// MLOAD: pop the key, push memory[key]; an unset slot traps.
pub fn sc_op_mload() -> Int {
  return 14;
}

/// MSTORE: pop the key, pop the value, set memory[key] = value.
pub fn sc_op_mstore() -> Int {
  return 15;
}

/// REVERT: pop the exit code and halt with status `reverted`.
pub fn sc_op_revert() -> Int {
  return 16;
}

/// Mnemonic of an opcode, or "" for an unknown opcode byte.
pub fn sc_op_name(op: Int) -> Str {
  if op == sc_op_stop() { return "STOP"; }
  if op == sc_op_push() { return "PUSH"; }
  if op == sc_op_add() { return "ADD"; }
  if op == sc_op_sub() { return "SUB"; }
  if op == sc_op_mul() { return "MUL"; }
  if op == sc_op_div() { return "DIV"; }
  if op == sc_op_mod() { return "MOD"; }
  if op == sc_op_cmp() { return "CMP"; }
  if op == sc_op_jump() { return "JUMP"; }
  if op == sc_op_jumpi() { return "JUMPI"; }
  if op == sc_op_label() { return "LABEL"; }
  if op == sc_op_dup() { return "DUP"; }
  if op == sc_op_swap() { return "SWAP"; }
  if op == sc_op_pop() { return "POP"; }
  if op == sc_op_mload() { return "MLOAD"; }
  if op == sc_op_mstore() { return "MSTORE"; }
  if op == sc_op_revert() { return "REVERT"; }
  return "";
}

/// True when the opcode carries an 8-byte operand (PUSH, JUMP, JUMPI, LABEL).
pub fn sc_has_operand(op: Int) -> Bool {
  if op == sc_op_push() { return true; }
  if op == sc_op_jump() { return true; }
  if op == sc_op_jumpi() { return true; }
  if op == sc_op_label() { return true; }
  return false;
}

/// Fixed gas cost of an opcode, or -1 for an unknown opcode byte.
pub fn sc_gas_cost(op: Int) -> Int {
  if op == sc_op_stop() { return 0; }
  if op == sc_op_push() { return 1; }
  if op == sc_op_add() { return 1; }
  if op == sc_op_sub() { return 1; }
  if op == sc_op_mul() { return 2; }
  if op == sc_op_div() { return 2; }
  if op == sc_op_mod() { return 2; }
  if op == sc_op_cmp() { return 1; }
  if op == sc_op_jump() { return 2; }
  if op == sc_op_jumpi() { return 3; }
  if op == sc_op_label() { return 0; }
  if op == sc_op_dup() { return 1; }
  if op == sc_op_swap() { return 1; }
  if op == sc_op_pop() { return 1; }
  if op == sc_op_mload() { return 2; }
  if op == sc_op_mstore() { return 3; }
  if op == sc_op_revert() { return 0; }
  return -1;
}

/// Operand width in bytes carried by PUSH/JUMP/JUMPI/LABEL.
pub fn sc_operand_bytes() -> Int {
  return 8;
}

/// Maximum stack depth; the 1025th push traps with `vm: stack overflow`.
pub fn sc_max_stack() -> Int {
  return 1024;
}

/// Status code of a normal STOP halt.
pub fn sc_status_stopped() -> Int {
  return 0;
}

/// Status code of a REVERT halt.
pub fn sc_status_reverted() -> Int {
  return 1;
}

/// Status code of an aborted execution (a trap).
pub fn sc_status_trapped() -> Int {
  return 2;
}

/// Smallest signed 64-bit value; the lower bound of checked arithmetic.
pub fn sc_int_min() -> Int {
  return 0 - 9223372036854775807 - 1;
}

/// Largest signed 64-bit value; the upper bound of checked arithmetic.
pub fn sc_int_max() -> Int {
  return 9223372036854775807;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte `pos` of a decoded program widened to an Int in 0..255.
fn _cb(p: &_Program, pos: Int) -> Int {
  let x: UInt8 = p.code[pos];
  return (x as Int) & 0xFF;
}

// Length of the program bytecode.
fn _code_len(p: &_Program) -> Int {
  return p.code.len();
}

// Append `v` as 8 big-endian two's-complement bytes (canonical
// xiom.serialize.endian writer).
fn _push_s64(out: &mut Vec[UInt8], v: Int) {
  endian.write_u64_be(out, v as UInt64);
}

// Read 8 big-endian two's-complement bytes at `pos` (caller checked bounds);
// the UInt64 reinterpretation is exact for the whole signed 64-bit range.
fn _read_s64(v: &Vec[UInt8], pos: Int) -> Int {
  let u: UInt64 = endian.read_u64_be(v, pos);
  return u as Int;
}

// --------------------------------------------------
//  Checked arithmetic (the VM never wraps silently)
// --------------------------------------------------

// True when a + b leaves the signed 64-bit range.
fn _add_overflows(a: Int, b: Int) -> Bool {
  if b > 0 {
    return a > (sc_int_max() - b);
  }
  if b < 0 {
    return a < (sc_int_min() - b);
  }
  return false;
}

// True when a - b leaves the signed 64-bit range.
fn _sub_overflows(a: Int, b: Int) -> Bool {
  if b > 0 {
    return a < (sc_int_min() + b);
  }
  if b < 0 {
    return a > (sc_int_max() + b);
  }
  return false;
}

// True when a * b leaves the signed 64-bit range.
fn _mul_overflows(a: Int, b: Int) -> Bool {
  if a == 0 || b == 0 { return false; }
  if a == 1 || b == 1 { return false; }
  if a == -1 { return b == sc_int_min(); }
  if b == -1 { return a == sc_int_min(); }
  // INT64_MIN times anything with |other| >= 2 overflows (0, 1, -1 handled).
  if a == sc_int_min() || b == sc_int_min() { return true; }
  var aa = a;
  if aa < 0 { aa = 0 - aa; }
  var bb = b;
  if bb < 0 { bb = 0 - bb; }
  return aa > (sc_int_max() / bb);
}

// True when a / b leaves the signed 64-bit range (only INT64_MIN / -1).
fn _div_overflows(a: Int, b: Int) -> Bool {
  return a == sc_int_min() && b == -1;
}

// --------------------------------------------------
//  Program decoding and validation
// --------------------------------------------------

// Walk the bytecode and collect the instruction/label/jump tables. Rejects
// an empty program, an unknown opcode byte, and a truncated operand.
fn _decode(code: &Vec[UInt8]) -> Result[_Program, Str] {
  let n = code.len();
  if n == 0 {
    return _err_prog("program: empty bytecode");
  }
  var code_copy = Vec[UInt8].new();
  var ci = 0;
  while ci < n {
    code_copy.push(code[ci]);
    ci = ci + 1;
  }
  var p = _Program{
    code: code_copy;
    insn_pc: Vec[Int].new();
    insn_op: Vec[Int].new();
    insn_arg: Vec[Int].new();
    insn_has_arg: Vec[Int].new();
    label_id: Vec[Int].new();
    label_idx: Vec[Int].new();
    jump_pc: Vec[Int].new();
    jump_label: Vec[Int].new();
  };
  var pc = 0;
  while pc < n {
    let op: Int = _cb(&p, pc);
    if op > sc_op_revert() {
      return _err_prog("program: unknown opcode " + convert.int_to_string(op) + " at pc " + convert.int_to_string(pc));
    }
    let has = sc_has_operand(op);
    var arg: Int = 0;
    if has {
      if (pc + 9) > n {
        return _err_prog("program: truncated instruction at pc " + convert.int_to_string(pc));
      }
      arg = _read_s64(code, pc + 1);
    }
    p.insn_pc.push(pc);
    p.insn_op.push(op);
    if has {
      p.insn_arg.push(arg);
      p.insn_has_arg.push(1);
    } else {
      p.insn_arg.push(0);
      p.insn_has_arg.push(0);
    }
    let insn_i: Int = p.insn_pc.len() - 1;
    if op == sc_op_label() {
      p.label_id.push(arg);
      p.label_idx.push(insn_i);
    }
    if (op == sc_op_jump()) || (op == sc_op_jumpi()) {
      p.jump_pc.push(pc);
      p.jump_label.push(arg);
    }
    var step = 1;
    if has { step = 1 + sc_operand_bytes(); }
    pc = pc + step;
  }
  return _ok_prog(p);
}

// Reject duplicate label ids and jumps to labels that do not exist.
// Returns the instruction count on success.
fn _validate(p: &_Program) -> Result[Int, Str] {
  var i = 0;
  while i < p.label_id.len() {
    let id: Int = p.label_id[i];
    var j = i + 1;
    while j < p.label_id.len() {
      let other: Int = p.label_id[j];
      if other == id {
        return _err_int("program: duplicate label id " + convert.int_to_string(id));
      }
      j = j + 1;
    }
    i = i + 1;
  }
  i = 0;
  while i < p.jump_label.len() {
    let want: Int = p.jump_label[i];
    var found = false;
    var k = 0;
    while k < p.label_id.len() {
      let have: Int = p.label_id[k];
      if have == want { found = true; }
      k = k + 1;
    }
    if !found {
      let at: Int = p.jump_pc[i];
      return _err_int("program: unknown label " + convert.int_to_string(want) + " at pc " + convert.int_to_string(at));
    }
    i = i + 1;
  }
  return _ok_int(p.insn_pc.len());
}

/// Decode and validate a program; returns the instruction count on success.
/// Errors: `program: empty bytecode`, `program: unknown opcode N at pc N`,
/// `program: truncated instruction at pc N`,
/// `program: duplicate label id N`, `program: unknown label N at pc N`.
pub fn sc_validate(program: &Vec[UInt8]) -> Result[Int, Str] {
  let dr = _decode(program);
  if !dr.is_ok {
    return _err_int(dr.error);
  }
  let p: _Program = dr.value;
  return _validate(&p);
}

// --------------------------------------------------
//  Execution
// --------------------------------------------------

// Instruction index of the label `id`, or -1 (validation rules this out).
fn _label_index(p: &_Program, id: Int) -> Int {
  var i = 0;
  while i < p.label_id.len() {
    let have: Int = p.label_id[i];
    if have == id {
      let idx: Int = p.label_idx[i];
      return idx;
    }
    i = i + 1;
  }
  return -1;
}

// Index of `key` in the parallel memory key vector, or -1.
fn _mem_find_idx(keys: &Vec[Int], key: Int) -> Int {
  var i = 0;
  while i < keys.len() {
    let k: Int = keys[i];
    if k == key {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Trap text for a stack underflow at `pc`.
fn _underflow(pc: Int) -> Str {
  return "vm: stack underflow at pc " + convert.int_to_string(pc);
}

// Trap text for a stack overflow at `pc`.
fn _overflow(pc: Int) -> Str {
  return "vm: stack overflow at pc " + convert.int_to_string(pc);
}

// Trap text for checked-arithmetic overflow at `pc`.
fn _arith_overflow(pc: Int) -> Str {
  return "vm: arithmetic overflow at pc " + convert.int_to_string(pc);
}

// Execute a validated program. The caller guarantees the program passed
// `_decode` + `_validate` and that `gas_limit >= 0`.
fn _run(p: &_Program, gas_limit: Int) -> VmOutcome {
  var stack = Vec[Int].new();
  var mem_keys = Vec[Int].new();
  var mem_vals = Vec[Int].new();
  var t_pc = Vec[Int].new();
  var t_op = Vec[Int].new();
  var t_arg = Vec[Int].new();
  var t_has = Vec[Int].new();
  var t_gb = Vec[Int].new();
  var t_ga = Vec[Int].new();
  var t_depth = Vec[Int].new();
  var t_top = Vec[Int].new();
  var gas_used: Int = 0;
  var idx: Int = 0;
  var status: Int = -1;
  var exit_code: Int = 0;
  var err: Str = "";
  let insn_count = p.insn_pc.len();
  let max_stack = sc_max_stack();
  while status < 0 {
    if idx >= insn_count {
      status = sc_status_trapped();
      err = "vm: execution ran past the end of the program at pc " + convert.int_to_string(_code_len(p));
      break;
    }
    let pc: Int = p.insn_pc[idx];
    let op: Int = p.insn_op[idx];
    let arg: Int = p.insn_arg[idx];
    let has: Int = p.insn_has_arg[idx];
    let cost: Int = sc_gas_cost(op);
    if cost > (gas_limit - gas_used) {
      status = sc_status_trapped();
      err = "vm: out of gas at pc " + convert.int_to_string(pc) + " (need " + convert.int_to_string(cost) + ", have " + convert.int_to_string(gas_limit - gas_used) + ")";
      break;
    }
    let gas_before: Int = gas_used;
    var trap: Str = "";
    var halted: Int = 0;
    var outcome_status: Int = sc_status_stopped();
    var next_idx: Int = idx + 1;
    if op == sc_op_stop() {
      halted = 1;
      outcome_status = sc_status_stopped();
    } elif op == sc_op_revert() {
      if stack.len() < 1 {
        trap = _underflow(pc);
      } else {
        let code: Int = stack[stack.len() - 1];
        stack.pop();
        halted = 1;
        outcome_status = sc_status_reverted();
        exit_code = code;
      }
    } elif op == sc_op_push() {
      if stack.len() >= max_stack {
        trap = _overflow(pc);
      } else {
        stack.push(arg);
      }
    } elif op == sc_op_pop() {
      if stack.len() < 1 {
        trap = _underflow(pc);
      } else {
        stack.pop();
      }
    } elif op == sc_op_dup() {
      if stack.len() < 1 {
        trap = _underflow(pc);
      } elif stack.len() >= max_stack {
        trap = _overflow(pc);
      } else {
        let v: Int = stack[stack.len() - 1];
        stack.push(v);
      }
    } elif op == sc_op_swap() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let a: Int = stack[stack.len() - 2];
        let b: Int = stack[stack.len() - 1];
        stack[stack.len() - 2] = b;
        stack[stack.len() - 1] = a;
      }
    } elif op == sc_op_add() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let a: Int = stack[stack.len() - 2];
        let b: Int = stack[stack.len() - 1];
        if _add_overflows(a, b) {
          trap = _arith_overflow(pc);
        } else {
          stack[stack.len() - 2] = a + b;
          stack.pop();
        }
      }
    } elif op == sc_op_sub() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let a: Int = stack[stack.len() - 2];
        let b: Int = stack[stack.len() - 1];
        if _sub_overflows(a, b) {
          trap = _arith_overflow(pc);
        } else {
          stack[stack.len() - 2] = a - b;
          stack.pop();
        }
      }
    } elif op == sc_op_mul() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let a: Int = stack[stack.len() - 2];
        let b: Int = stack[stack.len() - 1];
        if _mul_overflows(a, b) {
          trap = _arith_overflow(pc);
        } else {
          stack[stack.len() - 2] = a * b;
          stack.pop();
        }
      }
    } elif op == sc_op_div() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let a: Int = stack[stack.len() - 2];
        let b: Int = stack[stack.len() - 1];
        if b == 0 {
          trap = "vm: division by zero at pc " + convert.int_to_string(pc);
        } elif _div_overflows(a, b) {
          trap = _arith_overflow(pc);
        } else {
          stack[stack.len() - 2] = a / b;
          stack.pop();
        }
      }
    } elif op == sc_op_mod() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let a: Int = stack[stack.len() - 2];
        let b: Int = stack[stack.len() - 1];
        if b == 0 {
          trap = "vm: modulo by zero at pc " + convert.int_to_string(pc);
        } elif b == -1 {
          // a % -1 is mathematically 0 for every a; special-cased so
          // INT64_MIN % -1 never reaches an overflowing division.
          stack[stack.len() - 2] = 0;
          stack.pop();
        } else {
          stack[stack.len() - 2] = a % b;
          stack.pop();
        }
      }
    } elif op == sc_op_cmp() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let a: Int = stack[stack.len() - 2];
        let b: Int = stack[stack.len() - 1];
        var r: Int = 0;
        if a < b { r = -1; } elif a > b { r = 1; }
        stack[stack.len() - 2] = r;
        stack.pop();
      }
    } elif op == sc_op_jump() {
      next_idx = _label_index(p, arg);
    } elif op == sc_op_jumpi() {
      if stack.len() < 1 {
        trap = _underflow(pc);
      } else {
        let c: Int = stack[stack.len() - 1];
        stack.pop();
        if c != 0 {
          next_idx = _label_index(p, arg);
        }
      }
    } elif op == sc_op_label() {
      next_idx = idx + 1;
    } elif op == sc_op_mload() {
      if stack.len() < 1 {
        trap = _underflow(pc);
      } else {
        let key: Int = stack[stack.len() - 1];
        let mi = _mem_find_idx(&mem_keys, key);
        if mi < 0 {
          trap = "vm: memory slot " + convert.int_to_string(key) + " is not initialized at pc " + convert.int_to_string(pc);
        } else {
          let v: Int = mem_vals[mi];
          stack[stack.len() - 1] = v;
        }
      }
    } elif op == sc_op_mstore() {
      if stack.len() < 2 {
        trap = _underflow(pc);
      } else {
        let key: Int = stack[stack.len() - 1];
        let value: Int = stack[stack.len() - 2];
        stack.pop();
        stack.pop();
        let mi = _mem_find_idx(&mem_keys, key);
        if mi < 0 {
          mem_keys.push(key);
          mem_vals.push(value);
        } else {
          mem_vals[mi] = value;
        }
      }
    } else {
      trap = "vm: unknown opcode at pc " + convert.int_to_string(pc);
    }
    if trap != "" {
      status = sc_status_trapped();
      err = trap;
    } else {
      gas_used = gas_used + cost;
      var top: Int = 0;
      if stack.len() > 0 {
        top = stack[stack.len() - 1];
      }
      t_pc.push(pc);
      t_op.push(op);
      t_arg.push(arg);
      t_has.push(has);
      t_gb.push(gas_before);
      t_ga.push(gas_used);
      t_depth.push(stack.len());
      t_top.push(top);
      idx = next_idx;
      if halted == 1 {
        status = outcome_status;
      }
    }
  }
  var ret: Int = 0;
  if status == sc_status_stopped() && stack.len() > 0 {
    ret = stack[stack.len() - 1];
  }
  return VmOutcome{
    status: status;
    exit_code: exit_code;
    return_value: ret;
    error: err;
    gas_used: gas_used;
    steps: t_pc.len();
    trace_pc: t_pc;
    trace_op: t_op;
    trace_arg: t_arg;
    trace_has_arg: t_has;
    trace_gas_before: t_gb;
    trace_gas_after: t_ga;
    trace_depth: t_depth;
    trace_top: t_top;
    mem_keys: mem_keys;
    mem_vals: mem_vals;
  };
}

/// Execute `program` with `gas_limit` gas and return the outcome.
/// Err only for an invalid program (`program: ...` texts) or a negative gas
/// limit (`vm: negative gas limit`); execution traps come back as a
/// VmOutcome with `sc_status_trapped()` and the `vm: ...` text in `error`.
pub fn vm_run(program: &Vec[UInt8], gas_limit: Int) -> Result[VmOutcome, Str] {
  if gas_limit < 0 {
    return _err_outcome("vm: negative gas limit");
  }
  let dr = _decode(program);
  if !dr.is_ok {
    return _err_outcome(dr.error);
  }
  let p: _Program = dr.value;
  let vr = _validate(&p);
  if !vr.is_ok {
    return _err_outcome(vr.error);
  }
  return _ok_outcome(_run(&p, gas_limit));
}

// --------------------------------------------------
//  Outcome accessors
// --------------------------------------------------

/// Status code: 0 stopped, 1 reverted, 2 trapped.
pub fn vm_status(o: &VmOutcome) -> Int {
  return o.status;
}

/// Status code 0 (STOP) predicate.
pub fn vm_stopped(o: &VmOutcome) -> Bool {
  return o.status == sc_status_stopped();
}

/// Status code 1 (REVERT) predicate.
pub fn vm_reverted(o: &VmOutcome) -> Bool {
  return o.status == sc_status_reverted();
}

/// Status code 2 (trap) predicate.
pub fn vm_trapped(o: &VmOutcome) -> Bool {
  return o.status == sc_status_trapped();
}

/// Trap text; "" when the execution did not trap.
pub fn vm_error(o: &VmOutcome) -> Str {
  return o.error;
}

/// Exit code: 0 for STOP, the popped code for REVERT, 0 on a trap.
pub fn vm_exit_code(o: &VmOutcome) -> Int {
  return o.exit_code;
}

/// Top of stack at STOP (0 when the stack was empty); 0 otherwise.
pub fn vm_return_value(o: &VmOutcome) -> Int {
  return o.return_value;
}

/// Gas charged for completed instructions.
pub fn vm_gas_used(o: &VmOutcome) -> Int {
  return o.gas_used;
}

/// Number of completed instructions (equals the trace length).
pub fn vm_steps(o: &VmOutcome) -> Int {
  return o.steps;
}

/// Number of trace records.
pub fn vm_trace_len(o: &VmOutcome) -> Int {
  return o.trace_pc.len();
}

/// Byte pc of trace record `i`, or -1 out of range.
pub fn vm_trace_pc(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.trace_pc.len() {
    return -1;
  }
  let v: Int = o.trace_pc[i];
  return v;
}

/// Opcode of trace record `i`, or -1 out of range.
pub fn vm_trace_op(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.trace_op.len() {
    return -1;
  }
  let v: Int = o.trace_op[i];
  return v;
}

/// Operand of trace record `i` (0 when the instruction has none).
pub fn vm_trace_arg(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.trace_arg.len() {
    return 0;
  }
  let v: Int = o.trace_arg[i];
  return v;
}

/// True when the instruction of trace record `i` carries an operand.
pub fn vm_trace_has_arg(o: &VmOutcome, i: Int) -> Bool {
  if i < 0 || i >= o.trace_has_arg.len() {
    return false;
  }
  let v: Int = o.trace_has_arg[i];
  return v == 1;
}

/// Gas level before trace record `i`, or -1 out of range.
pub fn vm_trace_gas_before(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.trace_gas_before.len() {
    return -1;
  }
  let v: Int = o.trace_gas_before[i];
  return v;
}

/// Gas level after trace record `i`, or -1 out of range.
pub fn vm_trace_gas_after(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.trace_gas_after.len() {
    return -1;
  }
  let v: Int = o.trace_gas_after[i];
  return v;
}

/// Stack depth after trace record `i`, or -1 out of range.
pub fn vm_trace_depth(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.trace_depth.len() {
    return -1;
  }
  let v: Int = o.trace_depth[i];
  return v;
}

/// Stack top after trace record `i` (0 when the stack is empty).
pub fn vm_trace_top(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.trace_top.len() {
    return 0;
  }
  let v: Int = o.trace_top[i];
  return v;
}

/// Canonical text of trace record `i`: `pc N OP [arg] gas A->B depth D [top T]`,
/// or "" when `i` is out of range.
pub fn vm_trace_line(o: &VmOutcome, i: Int) -> Str {
  if i < 0 || i >= o.trace_pc.len() {
    return "";
  }
  let pc: Int = o.trace_pc[i];
  let op: Int = o.trace_op[i];
  let gb: Int = o.trace_gas_before[i];
  let ga: Int = o.trace_gas_after[i];
  let d: Int = o.trace_depth[i];
  let t: Int = o.trace_top[i];
  var line = "pc " + convert.int_to_string(pc) + " " + sc_op_name(op);
  if vm_trace_has_arg(o, i) {
    line = line + " " + convert.int_to_string(vm_trace_arg(o, i));
  }
  line = line + " gas " + convert.int_to_string(gb) + "->" + convert.int_to_string(ga);
  line = line + " depth " + convert.int_to_string(d);
  if d > 0 {
    line = line + " top " + convert.int_to_string(t);
  }
  return line;
}

/// The whole trace as text, one `vm_trace_line` per line (each line ends with
/// a newline); "" when nothing executed.
pub fn vm_trace_text(o: &VmOutcome) -> Str {
  var acc: Str = "";
  var i = 0;
  while i < o.trace_pc.len() {
    acc = acc + vm_trace_line(o, i) + "\n";
    i = i + 1;
  }
  return acc;
}

/// Number of memory slots written during the execution.
pub fn vm_mem_len(o: &VmOutcome) -> Int {
  return o.mem_keys.len();
}

/// Key of memory slot `i` in insertion order, or 0 out of range.
pub fn vm_mem_key(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.mem_keys.len() {
    return 0;
  }
  let v: Int = o.mem_keys[i];
  return v;
}

/// Value of memory slot `i` in insertion order, or 0 out of range.
pub fn vm_mem_value(o: &VmOutcome, i: Int) -> Int {
  if i < 0 || i >= o.mem_vals.len() {
    return 0;
  }
  let v: Int = o.mem_vals[i];
  return v;
}

/// True when `key` was written during the execution.
pub fn vm_mem_has(o: &VmOutcome, key: Int) -> Bool {
  var i = 0;
  while i < o.mem_keys.len() {
    let k: Int = o.mem_keys[i];
    if k == key { return true; }
    i = i + 1;
  }
  return false;
}

/// Index of `key` in the final memory map, or -1.
pub fn vm_mem_find(o: &VmOutcome, key: Int) -> Int {
  var i = 0;
  while i < o.mem_keys.len() {
    let k: Int = o.mem_keys[i];
    if k == key { return i; }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Assembler
// --------------------------------------------------

// Byte value of a character used by the text scanner.
fn _sbyte(text: Str, pos: Int) -> Int {
  let b: UInt8 = string.byte_at(text, pos);
  return (b as Int) & 0xFF;
}

// True for the whitespace bytes the assembler accepts (space, tab, CR).
fn _is_space(b: Int) -> Bool {
  if b == 32 { return true; }
  if b == 9 { return true; }
  if b == 13 { return true; }
  return false;
}

// The newline byte.
fn _nl() -> Int {
  return 10;
}

// The comment introducer byte.
fn _semi() -> Int {
  return 59;
}

// Decimal operand parser covering the whole signed 64-bit range, INT64_MIN
// included. xiom.convert.parse.parse_int accumulates the magnitude as a
// positive Int, so it rejects 9223372036854775808 and therefore cannot parse
// "-9223372036854775808"; this parser accumulates the negative value instead
// and is the assembler's only operand path. Returns Err with a local marker
// (the assembler maps any failure to its own error text).
fn _parse_operand(s: Str) -> Result[Int, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_int("asm: empty operand");
  }
  var i = 0;
  var neg = false;
  let c0: Int = _sbyte(s, 0);
  if c0 == 45 {
    neg = true;
    i = 1;
  } elif c0 == 43 {
    i = 1;
  }
  if i >= n {
    return _err_int("asm: no digits");
  }
  var acc: Int = 0;
  while i < n {
    let c: Int = _sbyte(s, i);
    if c < 48 || c > 57 {
      return _err_int("asm: invalid digit");
    }
    let d: Int = c - 48;
    if acc < ((sc_int_min() + d) / 10) {
      return _err_int("asm: operand overflow");
    }
    acc = (acc * 10) - d;
    i = i + 1;
  }
  if !neg {
    if acc == sc_int_min() {
      return _err_int("asm: operand overflow");
    }
    acc = 0 - acc;
  }
  return _ok_int(acc);
}

// Textual comparison used by the mnemonic table.
fn _mnem_is(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True for the mnemonics that take no operand.
fn _is_zero_operand_mnemonic(m: Str) -> Bool {
  if _mnem_is(m, "STOP") { return true; }
  if _mnem_is(m, "ADD") { return true; }
  if _mnem_is(m, "SUB") { return true; }
  if _mnem_is(m, "MUL") { return true; }
  if _mnem_is(m, "DIV") { return true; }
  if _mnem_is(m, "MOD") { return true; }
  if _mnem_is(m, "CMP") { return true; }
  if _mnem_is(m, "DUP") { return true; }
  if _mnem_is(m, "SWAP") { return true; }
  if _mnem_is(m, "POP") { return true; }
  if _mnem_is(m, "MLOAD") { return true; }
  if _mnem_is(m, "MSTORE") { return true; }
  if _mnem_is(m, "REVERT") { return true; }
  return false;
}

// Assemble one source line (already delimited by `start`/`end`, newline not
// included) into its bytecode. Blank lines and `;` comments assemble to
// nothing.
fn _asm_line(text: Str, start: Int, end: Int, line_no: Int) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < end && _is_space(_sbyte(text, i)) {
    i = i + 1;
  }
  if i >= end {
    return _ok_bytes(out);
  }
  if _sbyte(text, i) == _semi() {
    return _ok_bytes(out);
  }
  let t1s = i;
  while i < end && !_is_space(_sbyte(text, i)) {
    i = i + 1;
  }
  let t1e = i;
  var has_t2 = 0;
  var t2s = i;
  var t2e = i;
  while i < end && _is_space(_sbyte(text, i)) {
    i = i + 1;
  }
  if i < end && _sbyte(text, i) != _semi() {
    has_t2 = 1;
    t2s = i;
    while i < end && !_is_space(_sbyte(text, i)) {
      i = i + 1;
    }
    t2e = i;
    while i < end && _is_space(_sbyte(text, i)) {
      i = i + 1;
    }
    if i < end && _sbyte(text, i) != _semi() {
      return _err_bytes("asm: unexpected operand at line " + convert.int_to_string(line_no));
    }
  }
  let mnem = string.str_slice(text, t1s, t1e);
  if has_t2 == 0 {
    if _mnem_is(mnem, "STOP") {
      out.push(sc_op_stop() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "ADD") {
      out.push(sc_op_add() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "SUB") {
      out.push(sc_op_sub() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "MUL") {
      out.push(sc_op_mul() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "DIV") {
      out.push(sc_op_div() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "MOD") {
      out.push(sc_op_mod() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "CMP") {
      out.push(sc_op_cmp() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "DUP") {
      out.push(sc_op_dup() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "SWAP") {
      out.push(sc_op_swap() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "POP") {
      out.push(sc_op_pop() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "MLOAD") {
      out.push(sc_op_mload() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "MSTORE") {
      out.push(sc_op_mstore() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "REVERT") {
      out.push(sc_op_revert() as UInt8);
      return _ok_bytes(out);
    }
    if _mnem_is(mnem, "PUSH") || _mnem_is(mnem, "JUMP") || _mnem_is(mnem, "JUMPI") || _mnem_is(mnem, "LABEL") {
      return _err_bytes("asm: missing operand at line " + convert.int_to_string(line_no));
    }
    return _err_bytes("asm: unknown mnemonic '" + mnem + "' at line " + convert.int_to_string(line_no));
  }
  var opcode: Int = -1;
  if _mnem_is(mnem, "PUSH") {
    opcode = sc_op_push();
  } elif _mnem_is(mnem, "JUMP") {
    opcode = sc_op_jump();
  } elif _mnem_is(mnem, "JUMPI") {
    opcode = sc_op_jumpi();
  } elif _mnem_is(mnem, "LABEL") {
    opcode = sc_op_label();
  } else {
    if _is_zero_operand_mnemonic(mnem) {
      return _err_bytes("asm: unexpected operand at line " + convert.int_to_string(line_no));
    }
    return _err_bytes("asm: unknown mnemonic '" + mnem + "' at line " + convert.int_to_string(line_no));
  }
  let opstr = string.str_slice(text, t2s, t2e);
  let ov = _parse_operand(opstr);
  if !ov.is_ok {
    return _err_bytes("asm: operand is not an integer at line " + convert.int_to_string(line_no));
  }
  let v: Int = ov.value;
  out.push(opcode as UInt8);
  _push_s64(&mut out, v);
  return _ok_bytes(out);
}

/// Assemble textual bytecode into a program.
///
/// The format is one instruction per line: `PUSH n`, `JUMP x`, `JUMPI x` and
/// `LABEL x` where x is a signed 64-bit decimal label id, plus `STOP`, `ADD`,
/// `SUB`, `MUL`, `DIV`, `MOD`, `CMP`, `DUP`, `SWAP`, `POP`, `MLOAD`,
/// `MSTORE`, `REVERT`. Blank lines are skipped; `;` starts a comment that
/// runs to the end of the line. Text containing a NUL byte is rejected.
/// Errors: `asm: text contains a NUL byte`,
/// `asm: unknown mnemonic 'X' at line N`, `asm: missing operand at line N`,
/// `asm: unexpected operand at line N`, `asm: operand is not an integer at
/// line N`. Blank/comment-only text assembles to an empty program, which the
/// VM then rejects with `program: empty bytecode`.
pub fn sc_assemble(text: Str) -> Result[Vec[UInt8], Str] {
  let n = string.str_len(text);
  var i = 0;
  while i < n {
    if _sbyte(text, i) == 0 {
      return _err_bytes("asm: text contains a NUL byte");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  var line_start = 0;
  var line_no = 1;
  while line_start <= n {
    var line_end = line_start;
    while line_end < n && _sbyte(text, line_end) != _nl() {
      line_end = line_end + 1;
    }
    let lr = _asm_line(text, line_start, line_end, line_no);
    if !lr.is_ok {
      return _err_bytes(lr.error);
    }
    let piece: Vec[UInt8] = lr.value;
    var j = 0;
    while j < piece.len() {
      out.push(piece[j]);
      j = j + 1;
    }
    if line_end >= n {
      break;
    }
    line_start = line_end + 1;
    line_no = line_no + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Disassembler
// --------------------------------------------------

/// Render a program as canonical assembly text: one instruction per line,
/// operands in signed decimal, each line (including the last) newline
/// terminated. `sc_assemble(sc_disassemble(p))` reproduces the bytes of any
/// program this function accepts. Errors are the `program: ...` decode texts
/// (`program: empty bytecode`, `program: unknown opcode N at pc N`,
/// `program: truncated instruction at pc N`).
pub fn sc_disassemble(program: &Vec[UInt8]) -> Result[Str, Str] {
  let dr = _decode(program);
  if !dr.is_ok {
    return _err_str(dr.error);
  }
  let p: _Program = dr.value;
  var acc: Str = "";
  var i = 0;
  while i < p.insn_pc.len() {
    let op: Int = p.insn_op[i];
    let has: Int = p.insn_has_arg[i];
    acc = acc + sc_op_name(op);
    if has == 1 {
      let arg: Int = p.insn_arg[i];
      acc = acc + " " + convert.int_to_string(arg);
    }
    acc = acc + "\n";
    i = i + 1;
  }
  return _ok_str(acc);
}
