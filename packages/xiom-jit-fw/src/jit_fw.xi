// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.jit_fw: a deterministic JIT-framework model.
// Port task: replace the xiom-jit-fw placeholder with a pure-XIOM module.
// No FFI, no IO, no Vec[Float64], no Vec[StructType], no Result/Option and
// no native code generation: everything is an integer model.
//
// Scope: the reusable machinery of a just-in-time compiler framework, not a
// native backend:
//   * the engine pipeline: source identity (hash) -> IR (symbolic labels) ->
//     instruction stream (resolved program counters) -> a bounded dispatch
//     interpreter with a call-frame stack;
//   * the exec model: "loaded generated code" is an instruction table
//     (JitCode) plus call frames, exactly what the interpreter consumes;
//   * the artifact cache: key = source hash + flags, bounded LRU replacement
//     with hit/miss/insert/evict statistics;
//   * trampolines and closure adapters: a closure handle packs (entry, env)
//     and a trampoline table resolves handles to loaded code tables;
//   * the monitor and tiering policy: per-site counters, the baseline /
//     optimized / deopt tiers and a deterministic threshold decision.
//
// Language notes (XIOM v0.62.2): free functions only, every name is prefixed
// (`jit_` public, `_jit_` private); opcode dispatch is an explicit if/elif
// chain (no indexed Vec[fn]); VM state is a struct with parallel Vec fields,
// never a `&mut Int` scalar parameter; all loops make structural progress and
// dispatch is bounded by a step cap; Str values are hashed byte-by-byte with
// `string.byte_at` masked to 0..255.

module xiom.jit_fw

use xiom.string;
use xiom.convert;

// ---------------------------------------------------------------------------
// Sentinels, exit statuses, tiers and actions
// ---------------------------------------------------------------------------

/// "No value": unbound lookup, absent key or out-of-range accessor.
pub const JIT_NONE: Int = -1;

/// The machine has not been stepped yet (jit_machine_new).
pub const JIT_EXIT_RUNNING: Int = 0;

/// The interpreter reached a HALT instruction or returned from the outermost
/// call frame.
pub const JIT_EXIT_HALT: Int = 1;

/// The step cap was reached before the program halted (always terminates).
pub const JIT_EXIT_STEP_LIMIT: Int = 2;

/// The interpreter met an opcode it does not implement.
pub const JIT_EXIT_BAD_OP: Int = 3;

/// The program counter left `[0, code_len)` (bad jump/call target or an
/// empty code table).
pub const JIT_EXIT_BAD_PC: Int = 4;

/// Never-executed or baseline-compiled code tier.
pub const JIT_TIER_BASELINE: Int = 0;

/// Artificially optimized code tier (the interpreter does not change meaning
/// with tier; the tier is bookkeeping for the policy).
pub const JIT_TIER_OPTIMIZED: Int = 1;

/// The site deoptimized; its counter was reset.
pub const JIT_TIER_DEOPT: Int = 2;

/// Tiering decision: no transition.
pub const JIT_ACTION_STAY: Int = 0;

/// Tiering decision: baseline -> optimized.
pub const JIT_ACTION_COMPILE: Int = 1;

/// Tiering decision: deopt -> optimized (a fresh optimization attempt).
pub const JIT_ACTION_RECOMPILE: Int = 2;

// ---------------------------------------------------------------------------
// Engine opcodes (IR and instruction stream share one opcode space)
// ---------------------------------------------------------------------------

/// Pseudo-op: a label definition (IR only; lowering rewrites it to NOP).
pub const JIT_OP_LABEL: Int = 0;

/// No operation.
pub const JIT_OP_NOP: Int = 1;

/// Push the immediate argA.
pub const JIT_OP_PUSH: Int = 2;

/// Pop b, pop a, push a + b.
pub const JIT_OP_ADD: Int = 3;

/// Pop b, pop a, push a - b.
pub const JIT_OP_SUB: Int = 4;

/// Pop b, pop a, push a * b.
pub const JIT_OP_MUL: Int = 5;

/// Pop addr, push mem[addr] (0 when addr is out of range).
pub const JIT_OP_LOAD: Int = 6;

/// Pop addr, pop value, store value at mem[addr]. An address one past the
/// end appends one word; any farther address is ignored.
pub const JIT_OP_STORE: Int = 7;

/// Set pc = argA (IR: a label id; code: an instruction index).
pub const JIT_OP_JMP: Int = 8;

/// Pop cond; jump to argA when cond == 0, else fall through.
pub const JIT_OP_JZ: Int = 9;

/// Push the return pc, then jump to argA.
pub const JIT_OP_CALL: Int = 10;

/// Pop a return pc from the frame stack (halt when the stack is empty).
pub const JIT_OP_RET: Int = 11;

/// Stop the interpreter (status JIT_EXIT_HALT).
pub const JIT_OP_HALT: Int = 12;

/// Push a second copy of the stack top (0 on an empty stack).
pub const JIT_OP_DUP: Int = 13;

/// Swap the top two stack entries (no-op when fewer than two).
pub const JIT_OP_SWAP: Int = 14;

/// Pop a, push 0 - a.
pub const JIT_OP_NEG: Int = 15;

// ---------------------------------------------------------------------------
// Types (parallel Vec fields: XIOM has no Vec[StructType])
// ---------------------------------------------------------------------------

/// Symbolic IR: instruction i is (ops[i], argA[i], argB[i]); jump/call
/// operands are label ids and JIT_OP_LABEL defines them.
pub type JitIr = {
  ops: Vec[Int];
  argA: Vec[Int];
  argB: Vec[Int];
}

/// The instruction stream consumed by the interpreter. Same record shape as
/// JitIr; jump/call operands are instruction indices (program counters).
pub type JitCode = {
  ops: Vec[Int];
  argA: Vec[Int];
  argB: Vec[Int];
}

/// Interpreter state. `stack` is the operand stack, `frames` the return-pc
/// stack, `mem` the flat memory, `steps` the dispatch count and `status` a
/// JIT_EXIT_* code.
pub type JitMachine = {
  stack: Vec[Int];
  mem: Vec[Int];
  frames: Vec[Int];
  pc: Int;
  steps: Int;
  status: Int;
}

/// Bounded LRU artifact cache: entry i maps keys[i] -> slots[i] with an
/// access stamp used[i]; `tick` grows on every access.
pub type JitCache = {
  keys: Vec[Int];
  slots: Vec[Int];
  used: Vec[Int];
  tick: Int;
  cap: Int;
  hits: Int;
  misses: Int;
  inserts: Int;
  evicts: Int;
}

/// Trampoline table: closure handle -> loaded code-table handle, as two
/// parallel Vecs.
pub type JitTrampolines = {
  closures: Vec[Int];
  codes: Vec[Int];
}

/// Per-site execution monitor: parallel Vecs keyed by site id.
pub type JitMonitor = {
  sites: Vec[Int];
  counts: Vec[Int];
  tiers: Vec[Int];
  deopts: Vec[Int];
}

/// Deterministic tiering thresholds. `hot` promotes baseline code,
/// `rehot` re-promotes deoptimized code and `max_attempts` caps the number
/// of reoptimization attempts per site.
pub type JitPolicy = {
  hot: Int;
  rehot: Int;
  max_attempts: Int;
}

// ---------------------------------------------------------------------------
// Source identity and artifact keys
// ---------------------------------------------------------------------------

/// FNV-1a 32-bit hash of a source text, byte-exact and deterministic
/// (UTF-8 bytes, each widened with `& 0xFF`). The empty text hashes to
/// 2166136261. Complexity: O(|src|).
pub fn jit_source_hash(src: Str) -> Int {
  var h: Int = 2166136261;
  var i = 0;
  let n = src.len();
  while i < n {
    let b: Int = (string.byte_at(src, i) as Int) & 0xFF;
    h = h ^ b;
    h = (h * 16777619) & 0xFFFFFFFF;
    i = i + 1;
  }
  return h;
}

/// Artifact cache key for a source hash and a compile-flags word: a
/// deterministic 32-bit mix. Complexity: O(1).
pub fn jit_artifact_key(source_hash: Int, flags: Int) -> Int {
  var h: Int = source_hash & 0xFFFFFFFF;
  h = h ^ ((flags << 1) & 0xFFFFFFFF);
  h = (h * 16777619) & 0xFFFFFFFF;
  h = (h ^ (h >> 13)) & 0xFFFFFFFF;
  return h;
}

/// The artifact key of a source text: jit_artifact_key(jit_source_hash(src),
/// flags). Complexity: O(|src|).
pub fn jit_key_for_source(src: Str, flags: Int) -> Int {
  return jit_artifact_key(jit_source_hash(src), flags);
}

// ---------------------------------------------------------------------------
// IR construction and lowering
// ---------------------------------------------------------------------------

/// An empty symbolic program. Complexity: O(1).
pub fn jit_ir_new() -> JitIr {
  return JitIr{ ops: Vec[Int].new(); argA: Vec[Int].new(); argB: Vec[Int].new(); };
}

/// Append the IR instruction (op, a, b). Complexity: O(1) amortized.
pub fn jit_ir_push(ir: &mut JitIr, op: Int, a: Int, b: Int) {
  ir.ops.push(op);
  ir.argA.push(a);
  ir.argB.push(b);
}

/// Number of IR instructions. Complexity: O(1).
pub fn jit_ir_len(ir: &JitIr) -> Int {
  return ir.ops.len();
}

/// Opcode of IR instruction `i`, or JIT_NONE out of range. O(1).
pub fn jit_ir_op(ir: &JitIr, i: Int) -> Int {
  if i < 0 || i >= ir.ops.len() {
    return JIT_NONE;
  }
  let v: Int = ir.ops[i];
  return v;
}

/// Operand A of IR instruction `i`, or 0 out of range. O(1).
pub fn jit_ir_a(ir: &JitIr, i: Int) -> Int {
  if i < 0 || i >= ir.argA.len() {
    return 0;
  }
  let v: Int = ir.argA[i];
  return v;
}

/// Operand B of IR instruction `i`, or 0 out of range. O(1).
pub fn jit_ir_b(ir: &JitIr, i: Int) -> Int {
  if i < 0 || i >= ir.argB.len() {
    return 0;
  }
  let v: Int = ir.argB[i];
  return v;
}

/// An empty instruction stream. Complexity: O(1).
pub fn jit_code_new() -> JitCode {
  return JitCode{ ops: Vec[Int].new(); argA: Vec[Int].new(); argB: Vec[Int].new(); };
}

/// Append one resolved instruction. Complexity: O(1) amortized.
pub fn jit_code_push(code: &mut JitCode, op: Int, a: Int, b: Int) {
  code.ops.push(op);
  code.argA.push(a);
  code.argB.push(b);
}

/// Number of instructions. Complexity: O(1).
pub fn jit_code_len(code: &JitCode) -> Int {
  return code.ops.len();
}

/// Opcode of instruction `i`, or JIT_NONE out of range. O(1).
pub fn jit_code_op(code: &JitCode, i: Int) -> Int {
  if i < 0 || i >= code.ops.len() {
    return JIT_NONE;
  }
  let v: Int = code.ops[i];
  return v;
}

/// Operand A of instruction `i`, or 0 out of range. O(1).
pub fn jit_code_a(code: &JitCode, i: Int) -> Int {
  if i < 0 || i >= code.argA.len() {
    return 0;
  }
  let v: Int = code.argA[i];
  return v;
}

/// Operand B of instruction `i`, or 0 out of range. O(1).
pub fn jit_code_b(code: &JitCode, i: Int) -> Int {
  if i < 0 || i >= code.argB.len() {
    return 0;
  }
  let v: Int = code.argB[i];
  return v;
}

/// Structural equality across all three fields. Complexity: O(n).
pub fn jit_code_equal(x: &JitCode, y: &JitCode) -> Bool {
  if x.ops.len() != y.ops.len() {
    return false;
  }
  var i = 0;
  while i < x.ops.len() {
    let xo: Int = x.ops[i];
    let yo: Int = y.ops[i];
    if xo != yo {
      return false;
    }
    let xa: Int = x.argA[i];
    let ya: Int = y.argA[i];
    if xa != ya {
      return false;
    }
    let xb: Int = x.argB[i];
    let yb: Int = y.argB[i];
    if xb != yb {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Lower IR to an instruction stream: record every JIT_OP_LABEL as the pc of
/// its instruction, rewrite label pseudo-ops to NOP (pc mapping is 1:1) and
/// resolve jump/call label ids to instruction indices. A jump to an unbound
/// label lowers to JIT_NONE and makes the interpreter exit BAD_PC.
/// Complexity: O(n + |labels|^2) worst case (linear label scan per jump).
pub fn jit_lower(ir: &JitIr) -> JitCode {
  var lids = Vec[Int].new();
  var lpcs = Vec[Int].new();
  let n = jit_ir_len(ir);
  var i = 0;
  while i < n {
    if jit_ir_op(ir, i) == JIT_OP_LABEL {
      _jit_label_bind(&mut lids, &mut lpcs, jit_ir_a(ir, i), i);
    }
    i = i + 1;
  }
  var code = jit_code_new();
  i = 0;
  while i < n {
    let op: Int = jit_ir_op(ir, i);
    let a: Int = jit_ir_a(ir, i);
    let b: Int = jit_ir_b(ir, i);
    if op == JIT_OP_LABEL {
      jit_code_push(&mut code, JIT_OP_NOP, 0, 0);
    } elif op == JIT_OP_JMP || op == JIT_OP_JZ || op == JIT_OP_CALL {
      jit_code_push(&mut code, op, _jit_label_pc(&lids, &lpcs, a), b);
    } else {
      jit_code_push(&mut code, op, a, b);
    }
    i = i + 1;
  }
  return code;
}

/// Lowercase mnemonic of an opcode; unknown opcodes render as "op<code>".
/// Complexity: O(digits).
pub fn jit_op_name(op: Int) -> Str {
  if op == JIT_OP_LABEL {
    return "label";
  }
  if op == JIT_OP_NOP {
    return "nop";
  }
  if op == JIT_OP_PUSH {
    return "push";
  }
  if op == JIT_OP_ADD {
    return "add";
  }
  if op == JIT_OP_SUB {
    return "sub";
  }
  if op == JIT_OP_MUL {
    return "mul";
  }
  if op == JIT_OP_LOAD {
    return "load";
  }
  if op == JIT_OP_STORE {
    return "store";
  }
  if op == JIT_OP_JMP {
    return "jmp";
  }
  if op == JIT_OP_JZ {
    return "jz";
  }
  if op == JIT_OP_CALL {
    return "call";
  }
  if op == JIT_OP_RET {
    return "ret";
  }
  if op == JIT_OP_HALT {
    return "halt";
  }
  if op == JIT_OP_DUP {
    return "dup";
  }
  if op == JIT_OP_SWAP {
    return "swap";
  }
  if op == JIT_OP_NEG {
    return "neg";
  }
  return "op" + int_to_string(op);
}

/// Deterministic disassembly, one line per instruction plus a trailing
/// newline: "<pc>: <mnemonic>" with "push <a>", "jmp/jz/call -> <a>" and
/// "label <a>" carrying their operand. Empty code renders "".
/// Complexity: O(total text).
pub fn jit_disasm(code: &JitCode) -> Str {
  var out = "";
  var i = 0;
  while i < jit_code_len(code) {
    out = out + int_to_string(i) + ": " + _jit_render_instr(jit_code_op(code, i), jit_code_a(code, i)) + "\n";
    i = i + 1;
  }
  return out;
}

// Record a label's pc; the newest definition wins (deterministic).
fn _jit_label_bind(lids: &mut Vec[Int], lpcs: &mut Vec[Int], label: Int, pc: Int) {
  var i = 0;
  while i < lids.len() {
    let l: Int = lids[i];
    if l == label {
      lpcs[i] = pc;
      return;
    }
    i = i + 1;
  }
  lids.push(label);
  lpcs.push(pc);
}

// The pc recorded for `label`, or JIT_NONE when the label was never defined.
fn _jit_label_pc(lids: &Vec[Int], lpcs: &Vec[Int], label: Int) -> Int {
  var i = 0;
  while i < lids.len() {
    let l: Int = lids[i];
    if l == label {
      let pc: Int = lpcs[i];
      return pc;
    }
    i = i + 1;
  }
  return JIT_NONE;
}

// One disassembly line body after "<pc>: ".
fn _jit_render_instr(op: Int, a: Int) -> Str {
  if op == JIT_OP_LABEL {
    return "label " + int_to_string(a);
  }
  if op == JIT_OP_PUSH {
    return "push " + int_to_string(a);
  }
  if op == JIT_OP_JMP || op == JIT_OP_JZ || op == JIT_OP_CALL {
    return jit_op_name(op) + " -> " + int_to_string(a);
  }
  return jit_op_name(op);
}

// ---------------------------------------------------------------------------
// Exec model: machine, dispatch loop and call frames
// ---------------------------------------------------------------------------

/// A fresh machine: empty stack/memory/frames, pc 0, no steps, status
/// JIT_EXIT_RUNNING. Complexity: O(1).
pub fn jit_machine_new() -> JitMachine {
  return JitMachine{ stack: Vec[Int].new(); mem: Vec[Int].new(); frames: Vec[Int].new(); pc: 0; steps: 0; status: JIT_EXIT_RUNNING; };
}

/// Execute `code` from pc 0 until HALT (or RET on an empty frame stack) or
/// until `steps_max` instructions were dispatched; the returned machine
/// carries the final state. Negative caps behave like 0.
/// Complexity: O(steps_max), which bounds the whole computation.
pub fn jit_run(code: &JitCode, steps_max: Int) -> JitMachine {
  var m = jit_machine_new();
  var cap = steps_max;
  if cap < 0 {
    cap = 0;
  }
  let n = jit_code_len(code);
  var running = true;
  while running {
    if m.steps >= cap {
      m.status = JIT_EXIT_STEP_LIMIT;
      running = false;
    } elif m.pc < 0 || m.pc >= n {
      m.status = JIT_EXIT_BAD_PC;
      running = false;
    } else {
      let op: Int = jit_code_op(code, m.pc);
      let a: Int = jit_code_a(code, m.pc);
      m.steps = m.steps + 1;
      if op == JIT_OP_PUSH {
        m.stack.push(a);
        m.pc = m.pc + 1;
      } elif op == JIT_OP_ADD || op == JIT_OP_SUB || op == JIT_OP_MUL {
        _jit_binary(&mut m.stack, op);
        m.pc = m.pc + 1;
      } elif op == JIT_OP_NEG {
        let v = _jit_pop(&mut m.stack, 0);
        m.stack.push(0 - v);
        m.pc = m.pc + 1;
      } elif op == JIT_OP_DUP {
        let v = _jit_peek(&m.stack);
        m.stack.push(v);
        m.pc = m.pc + 1;
      } elif op == JIT_OP_SWAP {
        _jit_swap(&mut m.stack);
        m.pc = m.pc + 1;
      } elif op == JIT_OP_LOAD {
        let addr = _jit_pop(&mut m.stack, 0);
        m.stack.push(_jit_mem_get(&m.mem, addr));
        m.pc = m.pc + 1;
      } elif op == JIT_OP_STORE {
        let addr = _jit_pop(&mut m.stack, 0);
        let val = _jit_pop(&mut m.stack, 0);
        if addr >= 0 && addr < m.mem.len() {
          m.mem[addr] = val;
        } elif addr == m.mem.len() {
          m.mem.push(val);
        }
        m.pc = m.pc + 1;
      } elif op == JIT_OP_JMP {
        m.pc = a;
      } elif op == JIT_OP_JZ {
        let cond = _jit_pop(&mut m.stack, 0);
        if cond == 0 {
          m.pc = a;
        } else {
          m.pc = m.pc + 1;
        }
      } elif op == JIT_OP_CALL {
        m.frames.push(m.pc + 1);
        m.pc = a;
      } elif op == JIT_OP_RET {
        if m.frames.len() > 0 {
          let ret = _jit_pop(&mut m.frames, 0);
          m.pc = ret;
        } else {
          m.status = JIT_EXIT_HALT;
          running = false;
        }
      } elif op == JIT_OP_HALT || op == JIT_OP_NOP {
        if op == JIT_OP_HALT {
          m.status = JIT_EXIT_HALT;
          running = false;
        } else {
          m.pc = m.pc + 1;
        }
      } else {
        m.status = JIT_EXIT_BAD_OP;
        running = false;
      }
    }
  }
  return m;
}

/// Program counter after the run. Complexity: O(1).
pub fn jit_machine_pc(m: &JitMachine) -> Int {
  return m.pc;
}

/// Instructions dispatched. Complexity: O(1).
pub fn jit_machine_steps(m: &JitMachine) -> Int {
  return m.steps;
}

/// Final JIT_EXIT_* status. Complexity: O(1).
pub fn jit_machine_status(m: &JitMachine) -> Int {
  return m.status;
}

/// Operand-stack depth. Complexity: O(1).
pub fn jit_machine_stack_depth(m: &JitMachine) -> Int {
  return m.stack.len();
}

/// Top of the operand stack, or 0 on an empty stack. Complexity: O(1).
pub fn jit_machine_top(m: &JitMachine) -> Int {
  return _jit_peek(&m.stack);
}

/// Call-frame depth (number of pending return addresses). O(1).
pub fn jit_machine_frame_depth(m: &JitMachine) -> Int {
  return m.frames.len();
}

/// Flat memory size. Complexity: O(1).
pub fn jit_machine_mem_len(m: &JitMachine) -> Int {
  return m.mem.len();
}

/// mem[i], or 0 out of range. Complexity: O(1).
pub fn jit_machine_mem_at(m: &JitMachine, i: Int) -> Int {
  return _jit_mem_get(&m.mem, i);
}

// Pop the stack top, or `fallback` when the stack is empty.
fn _jit_pop(s: &mut Vec[Int], fallback: Int) -> Int {
  let n = s.len();
  if n == 0 {
    return fallback;
  }
  let v: Int = s[n - 1];
  s.pop();
  return v;
}

// Top of the stack, or 0 when empty.
fn _jit_peek(s: &Vec[Int]) -> Int {
  let n = s.len();
  if n == 0 {
    return 0;
  }
  let v: Int = s[n - 1];
  return v;
}

// Pop b, pop a, push the result of the binary op (0 for missing operands).
fn _jit_binary(s: &mut Vec[Int], op: Int) {
  let b = _jit_pop(s, 0);
  let a = _jit_pop(s, 0);
  if op == JIT_OP_ADD {
    s.push(a + b);
  } elif op == JIT_OP_SUB {
    s.push(a - b);
  } else {
    s.push(a * b);
  }
}

// Swap the top two entries (no-op with fewer than two).
fn _jit_swap(s: &mut Vec[Int]) {
  let n = s.len();
  if n < 2 {
    return;
  }
  let b: Int = s[n - 1];
  let a: Int = s[n - 2];
  s[n - 1] = a;
  s[n - 2] = b;
}

// mem[i], or 0 out of range.
fn _jit_mem_get(mem: &Vec[Int], i: Int) -> Int {
  if i < 0 || i >= mem.len() {
    return 0;
  }
  let v: Int = mem[i];
  return v;
}

// ---------------------------------------------------------------------------
// Artifact cache: bounded LRU with statistics
// ---------------------------------------------------------------------------

/// A cache with capacity `cap` (clamped to at least 1), empty statistics and
/// tick 0. Complexity: O(1).
pub fn jit_cache_new(cap: Int) -> JitCache {
  var c: Int = cap;
  if c < 1 {
    c = 1;
  }
  return JitCache{ keys: Vec[Int].new(); slots: Vec[Int].new(); used: Vec[Int].new(); tick: 0; cap: c; hits: 0; misses: 0; inserts: 0; evicts: 0; };
}

/// Number of cached entries. Complexity: O(1).
pub fn jit_cache_len(c: &JitCache) -> Int {
  return c.keys.len();
}

/// Configured capacity (>= 1). Complexity: O(1).
pub fn jit_cache_cap(c: &JitCache) -> Int {
  return c.cap;
}

/// Hit count. Complexity: O(1).
pub fn jit_cache_hits(c: &JitCache) -> Int {
  return c.hits;
}

/// Miss count. Complexity: O(1).
pub fn jit_cache_misses(c: &JitCache) -> Int {
  return c.misses;
}

/// Insert count (new keys and replacements). Complexity: O(1).
pub fn jit_cache_inserts(c: &JitCache) -> Int {
  return c.inserts;
}

/// Eviction count. Complexity: O(1).
pub fn jit_cache_evicts(c: &JitCache) -> Int {
  return c.evicts;
}

/// Look up `key` without touching any counter or stamp; the cached artifact
/// handle, or JIT_NONE. Complexity: O(n).
pub fn jit_cache_peek(c: &JitCache, key: Int) -> Int {
  var i = 0;
  while i < c.keys.len() {
    let k: Int = c.keys[i];
    if k == key {
      let h: Int = c.slots[i];
      return h;
    }
    i = i + 1;
  }
  return JIT_NONE;
}

/// Cache lookup: a hit stamps the entry with a fresh tick, counts a hit and
/// returns the artifact handle; a miss counts a miss and returns JIT_NONE.
/// Complexity: O(n).
pub fn jit_cache_get(c: &mut JitCache, key: Int) -> Int {
  var i = 0;
  while i < c.keys.len() {
    let k: Int = c.keys[i];
    if k == key {
      c.tick = c.tick + 1;
      c.used[i] = c.tick;
      c.hits = c.hits + 1;
      let h: Int = c.slots[i];
      return h;
    }
    i = i + 1;
  }
  c.misses = c.misses + 1;
  return JIT_NONE;
}

/// Insert or replace `key -> handle`. An existing key is updated in place;
/// otherwise a free slot is used, or the least-recently-used entry is
/// evicted (ties break to the lowest slot index). Returns the evicted
/// artifact handle, or JIT_NONE when nothing was evicted.
/// Complexity: O(n).
pub fn jit_cache_put(c: &mut JitCache, key: Int, handle: Int) -> Int {
  c.tick = c.tick + 1;
  var i = 0;
  while i < c.keys.len() {
    let k: Int = c.keys[i];
    if k == key {
      c.slots[i] = handle;
      c.used[i] = c.tick;
      c.inserts = c.inserts + 1;
      return JIT_NONE;
    }
    i = i + 1;
  }
  if c.keys.len() < c.cap {
    c.keys.push(key);
    c.slots.push(handle);
    c.used.push(c.tick);
    c.inserts = c.inserts + 1;
    return JIT_NONE;
  }
  let victim = _jit_lru_slot(c);
  let old: Int = c.slots[victim];
  c.keys[victim] = key;
  c.slots[victim] = handle;
  c.used[victim] = c.tick;
  c.inserts = c.inserts + 1;
  c.evicts = c.evicts + 1;
  return old;
}

// Slot of the least-recently-used entry (smallest stamp; ties -> lowest
// index). Requires a non-empty cache.
fn _jit_lru_slot(c: &mut JitCache) -> Int {
  var best = 0;
  var i = 1;
  while i < c.used.len() {
    let u: Int = c.used[i];
    let bu: Int = c.used[best];
    if u < bu {
      best = i;
    }
    i = i + 1;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Closures and trampolines
// ---------------------------------------------------------------------------

/// Pack a closure adapter handle from (entry pc, environment id); both are
/// masked to 16 bits, so the handle is (entry << 16) | env and can be
/// unpacked losslessly. Complexity: O(1).
pub fn jit_closure_make(entry: Int, env: Int) -> Int {
  return ((entry & 0xFFFF) << 16) | (env & 0xFFFF);
}

/// Entry pc stored in a closure handle. Complexity: O(1).
pub fn jit_closure_entry(handle: Int) -> Int {
  return (handle >> 16) & 0xFFFF;
}

/// Environment id stored in a closure handle. Complexity: O(1).
pub fn jit_closure_env(handle: Int) -> Int {
  return handle & 0xFFFF;
}

/// An empty trampoline table. Complexity: O(1).
pub fn jit_tramp_new() -> JitTrampolines {
  return JitTrampolines{ closures: Vec[Int].new(); codes: Vec[Int].new(); };
}

/// Bind (or rebind) a closure handle to a loaded code-table handle. Returns
/// the slot index (stable across rebinds). Complexity: O(n).
pub fn jit_tramp_bind(t: &mut JitTrampolines, closure: Int, code: Int) -> Int {
  var i = 0;
  while i < t.closures.len() {
    let c: Int = t.closures[i];
    if c == closure {
      t.codes[i] = code;
      return i;
    }
    i = i + 1;
  }
  t.closures.push(closure);
  t.codes.push(code);
  return t.closures.len() - 1;
}

/// Number of bound closures. Complexity: O(1).
pub fn jit_tramp_count(t: &JitTrampolines) -> Int {
  return t.closures.len();
}

/// Code-table handle bound to `closure`, or JIT_NONE. Complexity: O(n).
pub fn jit_tramp_code(t: &JitTrampolines, closure: Int) -> Int {
  let idx = _jit_tramp_slot(t, closure);
  if idx < 0 {
    return JIT_NONE;
  }
  let h: Int = t.codes[idx];
  return h;
}

/// Entry pc of a bound closure (from its packed handle), or JIT_NONE when
/// the closure is unbound. Complexity: O(n).
pub fn jit_tramp_entry(t: &JitTrampolines, closure: Int) -> Int {
  if _jit_tramp_slot(t, closure) < 0 {
    return JIT_NONE;
  }
  return jit_closure_entry(closure);
}

/// Environment id of a bound closure, or JIT_NONE when unbound.
/// Complexity: O(n).
pub fn jit_tramp_env(t: &JitTrampolines, closure: Int) -> Int {
  if _jit_tramp_slot(t, closure) < 0 {
    return JIT_NONE;
  }
  return jit_closure_env(closure);
}

// Slot of `closure`, or JIT_NONE.
fn _jit_tramp_slot(t: &JitTrampolines, closure: Int) -> Int {
  var i = 0;
  while i < t.closures.len() {
    let c: Int = t.closures[i];
    if c == closure {
      return i;
    }
    i = i + 1;
  }
  return JIT_NONE;
}

// ---------------------------------------------------------------------------
// Monitor and tiering policy
// ---------------------------------------------------------------------------

/// An empty monitor (no sites). Complexity: O(1).
pub fn jit_mon_new() -> JitMonitor {
  return JitMonitor{ sites: Vec[Int].new(); counts: Vec[Int].new(); tiers: Vec[Int].new(); deopts: Vec[Int].new(); };
}

/// Record one execution of `site`, creating it at tier JIT_TIER_BASELINE on
/// first sight. Returns the new per-site count. Complexity: O(n).
pub fn jit_mon_hit(m: &mut JitMonitor, site: Int) -> Int {
  let idx = _jit_mon_idx_rw(m, site);
  if idx < 0 {
    m.sites.push(site);
    m.counts.push(1);
    m.tiers.push(JIT_TIER_BASELINE);
    m.deopts.push(0);
    return 1;
  }
  m.counts[idx] = m.counts[idx] + 1;
  let c: Int = m.counts[idx];
  return c;
}

/// Per-site execution count, or 0 for an unknown site. Complexity: O(n).
pub fn jit_mon_count(m: &JitMonitor, site: Int) -> Int {
  let idx = _jit_mon_idx_ro(m, site);
  if idx < 0 {
    return 0;
  }
  let c: Int = m.counts[idx];
  return c;
}

/// Per-site tier, or JIT_NONE for an unknown site. Complexity: O(n).
pub fn jit_mon_tier(m: &JitMonitor, site: Int) -> Int {
  let idx = _jit_mon_idx_ro(m, site);
  if idx < 0 {
    return JIT_NONE;
  }
  let t: Int = m.tiers[idx];
  return t;
}

/// Per-site deopt count, or 0 for an unknown site. Complexity: O(n).
pub fn jit_mon_deopts(m: &JitMonitor, site: Int) -> Int {
  let idx = _jit_mon_idx_ro(m, site);
  if idx < 0 {
    return 0;
  }
  let d: Int = m.deopts[idx];
  return d;
}

/// Number of known sites. Complexity: O(1).
pub fn jit_mon_sites(m: &JitMonitor) -> Int {
  return m.sites.len();
}

/// Force a site's tier; returns the previous tier, or JIT_NONE for an
/// unknown site. Complexity: O(n).
pub fn jit_mon_set_tier(m: &mut JitMonitor, site: Int, tier: Int) -> Int {
  let idx = _jit_mon_idx_rw(m, site);
  if idx < 0 {
    return JIT_NONE;
  }
  let prev: Int = m.tiers[idx];
  m.tiers[idx] = tier;
  return prev;
}

/// Deoptimize a site: tier JIT_TIER_DEOPT, counter reset to 0 and the deopt
/// counter incremented. Returns the new deopt count, or JIT_NONE for an
/// unknown site. Complexity: O(n).
pub fn jit_mon_deopt(m: &mut JitMonitor, site: Int) -> Int {
  let idx = _jit_mon_idx_rw(m, site);
  if idx < 0 {
    return JIT_NONE;
  }
  m.deopts[idx] = m.deopts[idx] + 1;
  m.tiers[idx] = JIT_TIER_DEOPT;
  m.counts[idx] = 0;
  let d: Int = m.deopts[idx];
  return d;
}

/// A policy with clamped thresholds: hot >= 1, rehot >= 1, max_attempts >= 0.
/// Complexity: O(1).
pub fn jit_policy_new(hot: Int, rehot: Int, max_attempts: Int) -> JitPolicy {
  var h = hot;
  if h < 1 {
    h = 1;
  }
  var r = rehot;
  if r < 1 {
    r = 1;
  }
  var m = max_attempts;
  if m < 0 {
    m = 0;
  }
  return JitPolicy{ hot: h; rehot: r; max_attempts: m; };
}

/// Baseline->optimized threshold. Complexity: O(1).
pub fn jit_policy_hot(p: &JitPolicy) -> Int {
  return p.hot;
}

/// Deopt->optimized threshold. Complexity: O(1).
pub fn jit_policy_rehot(p: &JitPolicy) -> Int {
  return p.rehot;
}

/// Reoptimization attempt cap. Complexity: O(1).
pub fn jit_policy_max_attempts(p: &JitPolicy) -> Int {
  return p.max_attempts;
}

/// The deterministic tiering decision for one site:
///   * unknown site -> JIT_ACTION_STAY;
///   * baseline and count >= hot -> JIT_ACTION_COMPILE;
///   * optimized -> JIT_ACTION_STAY;
///   * deopt with deopts < max_attempts and count >= rehot ->
///     JIT_ACTION_RECOMPILE, else JIT_ACTION_STAY.
/// Complexity: O(n).
pub fn jit_tier_decide(m: &JitMonitor, site: Int, p: &JitPolicy) -> Int {
  let tier = jit_mon_tier(m, site);
  if tier == JIT_NONE {
    return JIT_ACTION_STAY;
  }
  let count = jit_mon_count(m, site);
  if tier == JIT_TIER_BASELINE {
    if count >= p.hot {
      return JIT_ACTION_COMPILE;
    }
    return JIT_ACTION_STAY;
  }
  if tier == JIT_TIER_OPTIMIZED {
    return JIT_ACTION_STAY;
  }
  let deopts = jit_mon_deopts(m, site);
  if deopts < p.max_attempts && count >= p.rehot {
    return JIT_ACTION_RECOMPILE;
  }
  return JIT_ACTION_STAY;
}

/// Decide and apply the transition: COMPILE/RECOMPILE move the site to
/// JIT_TIER_OPTIMIZED and return the action; STAY leaves everything
/// untouched. Complexity: O(n).
pub fn jit_tier_apply(m: &mut JitMonitor, site: Int, p: &JitPolicy) -> Int {
  let action = jit_tier_decide(m, site, p);
  if action == JIT_ACTION_COMPILE || action == JIT_ACTION_RECOMPILE {
    let idx = _jit_mon_idx_rw(m, site);
    if idx >= 0 {
      m.tiers[idx] = JIT_TIER_OPTIMIZED;
    }
  }
  return action;
}

// Slot of `site` through a mutable monitor reference.
fn _jit_mon_idx_rw(m: &mut JitMonitor, site: Int) -> Int {
  var i = 0;
  while i < m.sites.len() {
    let s: Int = m.sites[i];
    if s == site {
      return i;
    }
    i = i + 1;
  }
  return JIT_NONE;
}

// Slot of `site` through an immutable monitor reference.
fn _jit_mon_idx_ro(m: &JitMonitor, site: Int) -> Int {
  var i = 0;
  while i < m.sites.len() {
    let s: Int = m.sites[i];
    if s == site {
      return i;
    }
    i = i + 1;
  }
  return JIT_NONE;
}
