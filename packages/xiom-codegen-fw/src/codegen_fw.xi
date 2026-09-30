// XIOM -- xiom.codegen_fw: a deterministic code-generation framework
// Port task: replace the xiom.codegen-fw placeholder with a pure-XIOM module
// (no FFI, no IO, no Vec[Float64], no Vec[StructType], no Result).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the reusable machinery of a target-agnostic code generator, not a
// backend. Five pieces:
//   * SymTab: scoped name -> Int bindings (parallel Vec[Str] names, Vec[Int]
//     values, Vec[Int] scopes) with a monotone generation counter;
//   * LabelAlloc: fresh/commit/rollback label allocation so speculative
//     emission can be abandoned without leaking label ids;
//   * IrProgram: instructions as three parallel Vecs (opcodes, argA, argB) --
//     an opcode-plus-two-operands record model; labels and jump targets are
//     label ids allocated by LabelAlloc and rendered as "L<id>";
//   * Emitter: append-only text lines with an indent depth, an indent unit,
//     per-line comments and exact newline-terminated rendering;
//   * PeepholeRules/peep_apply: a first-match-wins rewriter over opcode
//     windows of length 1 or 2 (constant operand guards on the first
//     instruction, replacement of zero or one instruction, operand
//     forwarding), plus cg_render_module, the deterministic module text
//     renderer built on the Emitter.
//
// Language notes (XIOM v0.62.2): free functions only; Str values read from
// Vec[Str] elements are compared with str_compare (BUG 17); Vec element reads
// go through typed locals; no indexed Vec[fn] dispatch and no Vec[StructType]
// (IrProgram/PeepholeRules are parallel Vec fields); no Result/Option values
// are produced or consumed by this module -- every function is total and
// documents its clamping rules instead. Every loop makes progress:
// symtab_pop pops one binding per iteration, peep_apply advances by at least
// one instruction per iteration, and a peephole pass never revisits a
// position.

module xiom.codegen_fw

use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Sentinels
// ---------------------------------------------------------------------------

/// "No value": lookup miss and out-of-range Int accessors.
pub const CG_NONE: Int = -1;

/// Wildcard for pattern/guard slots: matches any opcode or operand value.
pub const CG_WILD: Int = -1;

/// Pattern terminator: the rule's window is one instruction long.
pub const CG_PAT_END: Int = -2;

/// Replacement marker: the matched window is deleted (emits nothing).
pub const CG_ERASE: Int = -3;

/// Replacement operand forwarding: copy argA of the window's first
/// instruction into this replacement operand slot.
pub const CG_FWD_A: Int = -4;

/// Replacement operand forwarding: copy argB of the window's first
/// instruction into this replacement operand slot.
pub const CG_FWD_B: Int = -5;

// ---------------------------------------------------------------------------
// Opcodes (Int constants; unknown opcodes are renderable but never match a
// rule unless the rule uses CG_WILD)
// ---------------------------------------------------------------------------

/// Pseudo-op: a label definition (argA = label id).
pub const CG_OP_LABEL: Int = 0;

/// No operation.
pub const CG_OP_NOP: Int = 1;

/// dst := src (argA = dst, argB = src).
pub const CG_OP_MOV: Int = 2;

/// argA := argA + argB.
pub const CG_OP_ADD: Int = 3;

/// argA := argA - argB.
pub const CG_OP_SUB: Int = 4;

/// argA := argA * argB.
pub const CG_OP_MUL: Int = 5;

/// argA := mem[argB].
pub const CG_OP_LOAD: Int = 6;

/// mem[argB] := argA.
pub const CG_OP_STORE: Int = 7;

/// Unconditional jump to the label argA.
pub const CG_OP_JMP: Int = 8;

/// Jump to the label argA when argB == 0.
pub const CG_OP_JZ: Int = 9;

/// Call the label argA.
pub const CG_OP_CALL: Int = 10;

/// Return.
pub const CG_OP_RET: Int = 11;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Scoped symbol table. Binding i is (names[i], values[i], scopes[i]) and is
/// invisible once its scope is popped. `depth` is the current scope depth
/// (0 = outermost) and `generation` counts binds (monotone, never reset).
pub type SymTab = {
  names: Vec[Str];
  values: Vec[Int];
  scopes: Vec[Int];
  depth: Int;
  generation: Int;
}

/// Label-id allocator with speculative (pending) allocation. Invariant:
/// `next == committed + pending`.
pub type LabelAlloc = {
  next: Int;
  committed: Int;
  pending: Int;
}

/// A linear program as three parallel Vec fields; instruction i is
/// (opcodes[i], argA[i], argB[i]). There is no Vec[StructType] in XIOM, so
/// the record model is flattened.
pub type IrProgram = {
  opcodes: Vec[Int];
  argA: Vec[Int];
  argB: Vec[Int];
}

/// Append-only text emitter: finished lines, the current indent depth and
/// the per-level indent unit (default two spaces).
pub type Emitter = {
  lines: Vec[Str];
  depth: Int;
  unit: Str;
}

/// Peephole rule set as seven parallel Vecs; rule i is
/// (m0[i], m1[i], guardA[i], guardB[i], outOp[i], outA[i], outB[i]).
pub type PeepholeRules = {
  m0: Vec[Int];
  m1: Vec[Int];
  guardA: Vec[Int];
  guardB: Vec[Int];
  outOp: Vec[Int];
  outA: Vec[Int];
  outB: Vec[Int];
}

// ---------------------------------------------------------------------------
// Symbol table
// ---------------------------------------------------------------------------

/// A fresh table at scope depth 0 with no bindings and generation 0.
/// Complexity: O(1).
pub fn symtab_new() -> SymTab {
  return SymTab{ names: Vec[Str].new(); values: Vec[Int].new(); scopes: Vec[Int].new(); depth: 0; generation: 0; };
}

/// Current scope depth (0 = outermost). Complexity: O(1).
pub fn symtab_depth(t: &SymTab) -> Int {
  return t.depth;
}

/// Number of live bindings across all scopes. Complexity: O(1).
pub fn symtab_len(t: &SymTab) -> Int {
  return t.names.len();
}

/// Monotone bind counter: +1 per symtab_bind, never reset by symtab_pop.
/// Complexity: O(1).
pub fn symtab_generation(t: &SymTab) -> Int {
  return t.generation;
}

/// Enter a new scope.
/// Returns: the new scope depth.
/// Complexity: O(1).
pub fn symtab_push(t: &mut SymTab) -> Int {
  t.depth = t.depth + 1;
  return t.depth;
}

/// Leave the current scope, removing every trailing binding created at that
/// depth. At depth 0 this is a no-op (the outermost scope is permanent).
/// Returns: the number of bindings removed.
/// Complexity: O(removed); every iteration pops one binding, so the loop
/// always makes progress.
pub fn symtab_pop(t: &mut SymTab) -> Int {
  if t.depth <= 0 {
    return 0;
  }
  var removed = 0;
  while t.scopes.len() > 0 {
    let s: Int = t.scopes[t.scopes.len() - 1];
    if s != t.depth {
      break;
    }
    t.names.pop();
    t.values.pop();
    t.scopes.pop();
    removed = removed + 1;
  }
  t.depth = t.depth - 1;
  return removed;
}

/// Bind `name` to `value` at the current depth. A duplicate name shadows the
/// earlier binding (lookups return the newest).
/// Returns: the new generation counter value.
/// Complexity: O(1).
pub fn symtab_bind(t: &mut SymTab, name: Str, value: Int) -> Int {
  t.names.push(name);
  t.values.push(value);
  t.scopes.push(t.depth);
  t.generation = t.generation + 1;
  return t.generation;
}

/// The value of the newest binding of `name`, or CG_NONE when unbound.
/// Complexity: O(|table| * |name|).
pub fn symtab_lookup(t: &SymTab, name: Str) -> Int {
  var i = t.names.len() - 1;
  while i >= 0 {
    let n: Str = t.names[i];
    if compare.str_compare(n, name) == 0 {
      let v: Int = t.values[i];
      return v;
    }
    i = i - 1;
  }
  return CG_NONE;
}

/// The scope depth holding the newest binding of `name`, or CG_NONE.
/// Complexity: O(|table| * |name|).
pub fn symtab_find_depth(t: &SymTab, name: Str) -> Int {
  var i = t.names.len() - 1;
  while i >= 0 {
    let n: Str = t.names[i];
    if compare.str_compare(n, name) == 0 {
      let s: Int = t.scopes[i];
      return s;
    }
    i = i - 1;
  }
  return CG_NONE;
}

/// Name of binding `i` in bind order, or "" out of range. Complexity: O(1).
pub fn symtab_name(t: &SymTab, i: Int) -> Str {
  if i < 0 || i >= t.names.len() {
    return "";
  }
  let n: Str = t.names[i];
  return n;
}

/// Value of binding `i` in bind order, or 0 out of range. Complexity: O(1).
pub fn symtab_value(t: &SymTab, i: Int) -> Int {
  if i < 0 || i >= t.values.len() {
    return 0;
  }
  let v: Int = t.values[i];
  return v;
}

/// Scope depth of binding `i` in bind order, or CG_NONE out of range.
/// Complexity: O(1).
pub fn symtab_scope(t: &SymTab, i: Int) -> Int {
  if i < 0 || i >= t.scopes.len() {
    return CG_NONE;
  }
  let s: Int = t.scopes[i];
  return s;
}

// ---------------------------------------------------------------------------
// Label allocator
// ---------------------------------------------------------------------------

/// A fresh allocator: no labels handed out, none committed.
/// Complexity: O(1).
pub fn label_alloc_new() -> LabelAlloc {
  return LabelAlloc{ next: 0; committed: 0; pending: 0; };
}

/// Hand out a fresh, not yet committed label id (0-based, monotone while
/// uncommitted). The id is only reserved by label_commit or freed again by
/// label_rollback.
/// Returns: the new label id.
/// Complexity: O(1).
pub fn label_fresh(a: &mut LabelAlloc) -> Int {
  let id = a.next;
  a.next = a.next + 1;
  a.pending = a.pending + 1;
  return id;
}

/// Commit every pending label ("the speculative block is real").
/// Returns: the committed count after the commit.
/// Complexity: O(1).
pub fn label_commit(a: &mut LabelAlloc) -> Int {
  a.committed = a.committed + a.pending;
  a.pending = 0;
  return a.committed;
}

/// Discard every pending label and rewind the id counter to the committed
/// count ("the speculative block was abandoned"); discarded ids are handed
/// out again by later label_fresh calls.
/// Returns: the next label id after the rollback (== the committed count).
/// Complexity: O(1).
pub fn label_rollback(a: &mut LabelAlloc) -> Int {
  a.next = a.committed;
  a.pending = 0;
  return a.next;
}

/// The id the next label_fresh call will return. Complexity: O(1).
pub fn label_next(a: &LabelAlloc) -> Int {
  return a.next;
}

/// Number of committed labels. Complexity: O(1).
pub fn label_committed(a: &LabelAlloc) -> Int {
  return a.committed;
}

/// Number of fresh-but-uncommitted labels. Complexity: O(1).
pub fn label_pending(a: &LabelAlloc) -> Int {
  return a.pending;
}

/// Text form of a label id: "L" + decimal id ("L0", "L12"; a negative id
/// keeps its sign, "L-1").
/// Complexity: O(digits).
pub fn label_text(id: Int) -> Str {
  return "L" + int_to_string(id);
}

// ---------------------------------------------------------------------------
// Instruction model
// ---------------------------------------------------------------------------

/// An empty instruction sequence. Complexity: O(1).
pub fn ir_new() -> IrProgram {
  return IrProgram{ opcodes: Vec[Int].new(); argA: Vec[Int].new(); argB: Vec[Int].new(); };
}

/// Append the instruction (op, a, b).
/// Complexity: O(1) amortized.
pub fn ir_push(p: &mut IrProgram, op: Int, a: Int, b: Int) {
  p.opcodes.push(op);
  p.argA.push(a);
  p.argB.push(b);
}

/// Number of instructions. Complexity: O(1).
pub fn ir_len(p: &IrProgram) -> Int {
  return p.opcodes.len();
}

/// Opcode of instruction `i`, or CG_NONE out of range. Complexity: O(1).
pub fn ir_opcode(p: &IrProgram, i: Int) -> Int {
  if i < 0 || i >= p.opcodes.len() {
    return CG_NONE;
  }
  let v: Int = p.opcodes[i];
  return v;
}

/// Operand A of instruction `i`, or 0 out of range. Complexity: O(1).
pub fn ir_a(p: &IrProgram, i: Int) -> Int {
  if i < 0 || i >= p.argA.len() {
    return 0;
  }
  let v: Int = p.argA[i];
  return v;
}

/// Operand B of instruction `i`, or 0 out of range. Complexity: O(1).
pub fn ir_b(p: &IrProgram, i: Int) -> Int {
  if i < 0 || i >= p.argB.len() {
    return 0;
  }
  let v: Int = p.argB[i];
  return v;
}

/// Overwrite instruction `i`; out-of-range indices are a no-op.
/// Complexity: O(1).
pub fn ir_set(p: &mut IrProgram, i: Int, op: Int, a: Int, b: Int) {
  if i < 0 || i >= p.opcodes.len() {
    return;
  }
  p.opcodes[i] = op;
  p.argA[i] = a;
  p.argB[i] = b;
}

/// Structural equality across all three parallel fields. Complexity: O(n).
pub fn ir_equal(x: &IrProgram, y: &IrProgram) -> Bool {
  if x.opcodes.len() != y.opcodes.len() {
    return false;
  }
  var i = 0;
  while i < x.opcodes.len() {
    let xo: Int = x.opcodes[i];
    let yo: Int = y.opcodes[i];
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

/// Lowercase mnemonic for an opcode; unknown opcodes render as "op<code>"
/// ("op99", "op-1").
/// Complexity: O(digits).
pub fn ir_op_name(op: Int) -> Str {
  if op == CG_OP_LABEL {
    return "label";
  }
  if op == CG_OP_NOP {
    return "nop";
  }
  if op == CG_OP_MOV {
    return "mov";
  }
  if op == CG_OP_ADD {
    return "add";
  }
  if op == CG_OP_SUB {
    return "sub";
  }
  if op == CG_OP_MUL {
    return "mul";
  }
  if op == CG_OP_LOAD {
    return "load";
  }
  if op == CG_OP_STORE {
    return "store";
  }
  if op == CG_OP_JMP {
    return "jmp";
  }
  if op == CG_OP_JZ {
    return "jz";
  }
  if op == CG_OP_CALL {
    return "call";
  }
  if op == CG_OP_RET {
    return "ret";
  }
  return "op" + int_to_string(op);
}

// ---------------------------------------------------------------------------
// Text emitter
// ---------------------------------------------------------------------------

/// A fresh emitter: no lines, indent depth 0, indent unit "  " (two spaces).
/// Complexity: O(1).
pub fn emitter_new() -> Emitter {
  return Emitter{ lines: Vec[Str].new(); depth: 0; unit: "  "; };
}

/// Number of finished lines. Complexity: O(1).
pub fn emitter_len(e: &Emitter) -> Int {
  return e.lines.len();
}

/// Current indent depth. Complexity: O(1).
pub fn emitter_depth(e: &Emitter) -> Int {
  return e.depth;
}

/// Replace the per-level indent unit (default "  "). Complexity: O(1).
pub fn emitter_set_unit(e: &mut Emitter, unit: Str) {
  e.unit = unit;
}

/// Increase the indent depth by one. Complexity: O(1).
pub fn emitter_indent(e: &mut Emitter) {
  e.depth = e.depth + 1;
}

/// Decrease the indent depth by one; clamped at 0. Complexity: O(1).
pub fn emitter_dedent(e: &mut Emitter) {
  if e.depth > 0 {
    e.depth = e.depth - 1;
  }
}

/// Append `text` prefixed by depth copies of the indent unit. The stored
/// line carries no trailing newline (emitter_text adds it).
/// Complexity: O(depth + |text|).
pub fn emitter_line(e: &mut Emitter, text: Str) {
  let ln = _indent_prefix(e) + text;
  e.lines.push(ln);
}

/// Append `text` prefixed by the indent, then " ; " and `comment`.
/// Complexity: O(depth + |text| + |comment|).
pub fn emitter_line_comment(e: &mut Emitter, text: Str, comment: Str) {
  let ln = _indent_prefix(e) + text + " ; " + comment;
  e.lines.push(ln);
}

/// Append a blank line (no indent, no text). Complexity: O(1).
pub fn emitter_blank(e: &mut Emitter) {
  e.lines.push("");
}

/// Finished line `i` as stored (indent included, no newline), or "" out of
/// range. Complexity: O(1).
pub fn emitter_line_at(e: &Emitter, i: Int) -> Str {
  if i < 0 || i >= e.lines.len() {
    return "";
  }
  let ln: Str = e.lines[i];
  return ln;
}

/// The whole document: every line followed by '\n'; "" for an empty emitter.
/// Complexity: O(total text).
pub fn emitter_text(e: &Emitter) -> Str {
  var out = "";
  var i = 0;
  while i < e.lines.len() {
    let ln: Str = e.lines[i];
    out = out + ln + "\n";
    i = i + 1;
  }
  return out;
}

// Depth copies of the indent unit. A &mut helper so emitter_line and
// emitter_line_comment never mix a `&` borrow with a `&mut` field access on
// the same local (advisory E001).
fn _indent_prefix(e: &mut Emitter) -> Str {
  var out = "";
  var i = 0;
  while i < e.depth {
    out = out + e.unit;
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Peephole engine
// ---------------------------------------------------------------------------

/// An empty rule set; the lowest matching rule index wins.
/// Complexity: O(1).
pub fn peep_rules_new() -> PeepholeRules {
  return PeepholeRules{
    m0: Vec[Int].new();
    m1: Vec[Int].new();
    guardA: Vec[Int].new();
    guardB: Vec[Int].new();
    outOp: Vec[Int].new();
    outA: Vec[Int].new();
    outB: Vec[Int].new();
  };
}

/// Register a rule matching a window of one or two instructions:
///   * m1 == CG_PAT_END: the window is the single instruction at the scan
///     position (it matches even at the end of the program);
///   * otherwise the window is two adjacent instructions and m1 is the
///     second instruction's opcode. CG_WILD matches any opcode.
/// The window's first instruction must also satisfy argA == guard_a and
/// argB == guard_b (CG_WILD = no constraint).
/// On a match the whole window is replaced by:
///   * nothing when out_op == CG_ERASE;
///   * else one instruction (out_op, out_a, out_b), where the replacement
///     operands CG_FWD_A / CG_FWD_B forward argA / argB of the window's
///     first instruction.
/// Complexity: O(1).
pub fn peep_rule_add(r: &mut PeepholeRules, m0: Int, m1: Int, guard_a: Int, guard_b: Int, out_op: Int, out_a: Int, out_b: Int) {
  r.m0.push(m0);
  r.m1.push(m1);
  r.guardA.push(guard_a);
  r.guardB.push(guard_b);
  r.outOp.push(out_op);
  r.outA.push(out_a);
  r.outB.push(out_b);
}

/// Number of registered rules. Complexity: O(1).
pub fn peep_rule_count(r: &PeepholeRules) -> Int {
  return r.m0.len();
}

/// Rewrite `prog` in a single left-to-right pass: at each position the first
/// rule (lowest index) whose window matches is applied, otherwise the
/// instruction is copied. A window of two consumes two instructions even when
/// both are erased, so every iteration advances by one or two instructions
/// (termination is structural, no fixpoint loop).
/// Params: prog - the input (never mutated); rules - the rule set.
/// Returns: the rewritten program.
/// Complexity: O(n * |rules|).
pub fn peep_apply(prog: &IrProgram, rules: &PeepholeRules) -> IrProgram {
  var out = ir_new();
  let n = ir_len(prog);
  var i = 0;
  while i < n {
    let op0 = ir_opcode(prog, i);
    let a0 = ir_a(prog, i);
    let b0 = ir_b(prog, i);
    var has_second = false;
    var op1 = CG_NONE;
    if i + 1 < n {
      has_second = true;
      op1 = ir_opcode(prog, i + 1);
    }
    let ri = _peep_match(rules, op0, op1, a0, b0, has_second);
    if ri < 0 {
      ir_push(&mut out, op0, a0, b0);
      i = i + 1;
    } else {
      let want1: Int = rules.m1[ri];
      var span = 2;
      if want1 == CG_PAT_END {
        span = 1;
      }
      let oop: Int = rules.outOp[ri];
      if oop != CG_ERASE {
        var oa: Int = rules.outA[ri];
        var ob: Int = rules.outB[ri];
        if oa == CG_FWD_A {
          oa = a0;
        } elif oa == CG_FWD_B {
          oa = b0;
        }
        if ob == CG_FWD_A {
          ob = a0;
        } elif ob == CG_FWD_B {
          ob = b0;
        }
        ir_push(&mut out, oop, oa, ob);
      }
      i = i + span;
    }
  }
  return out;
}

// Index of the first rule matching (op0, op1, a0, b0), or CG_NONE. A rule
// with m1 != CG_PAT_END needs has_second; guards are checked on the window's
// first instruction only.
fn _peep_match(rules: &PeepholeRules, op0: Int, op1: Int, a0: Int, b0: Int, has_second: Bool) -> Int {
  var i = 0;
  while i < rules.m0.len() {
    let want0: Int = rules.m0[i];
    let want1: Int = rules.m1[i];
    let gA: Int = rules.guardA[i];
    let gB: Int = rules.guardB[i];
    var ok = true;
    if want0 != CG_WILD && want0 != op0 {
      ok = false;
    }
    if ok {
      if want1 != CG_PAT_END {
        if !has_second {
          ok = false;
        } elif want1 != CG_WILD && want1 != op1 {
          ok = false;
        }
      }
    }
    if ok && gA != CG_WILD && gA != a0 {
      ok = false;
    }
    if ok && gB != CG_WILD && gB != b0 {
      ok = false;
    }
    if ok {
      return i;
    }
    i = i + 1;
  }
  return CG_NONE;
}

// ---------------------------------------------------------------------------
// Module text renderer
// ---------------------------------------------------------------------------

/// Render an IR program as deterministic module text:
///   * line 1: "module <name>", or "module <anonymous>" for an empty name;
///   * then every instruction indented one level (two spaces):
///       LABEL         -> "<label>:"
///       JMP/JZ/CALL   -> "<op> <label>"
///       NOP/RET       -> "<op>" (operands ignored)
///       MOV/ADD/SUB/MUL/LOAD/STORE -> "<op> <a>, <b>"
///       unknown op    -> "op<code> <a>, <b>"
/// The result always ends with a trailing newline.
/// Complexity: O(total text).
pub fn cg_render_module(name: Str, prog: &IrProgram) -> Str {
  var e = emitter_new();
  if name.len() == 0 {
    emitter_line(&mut e, "module <anonymous>");
  } else {
    emitter_line(&mut e, "module " + name);
  }
  emitter_indent(&mut e);
  var i = 0;
  while i < ir_len(prog) {
    emitter_line(&mut e, _render_op(ir_opcode(prog, i), ir_a(prog, i), ir_b(prog, i)));
    i = i + 1;
  }
  return emitter_text(&e);
}

// One rendered instruction line, without indentation.
fn _render_op(op: Int, a: Int, b: Int) -> Str {
  if op == CG_OP_LABEL {
    return label_text(a) + ":";
  }
  if op == CG_OP_JMP || op == CG_OP_JZ || op == CG_OP_CALL {
    return ir_op_name(op) + " " + label_text(a);
  }
  if op == CG_OP_NOP || op == CG_OP_RET {
    return ir_op_name(op);
  }
  if op == CG_OP_MOV || op == CG_OP_ADD || op == CG_OP_SUB || op == CG_OP_MUL || op == CG_OP_LOAD || op == CG_OP_STORE {
    return ir_op_name(op) + " " + int_to_string(a) + ", " + int_to_string(b);
  }
  return "op" + int_to_string(op) + " " + int_to_string(a) + ", " + int_to_string(b);
}
