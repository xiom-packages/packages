// XIOM -- xiom.analyzer: deterministic static analysis over a generic IR
// Port task: promote the xiom.analyzer placeholder to a real, tested,
// pure-XIOM package -- a static-analysis *framework*, not a compiler front
// end. The caller supplies an instruction list (opcode Int + two operand
// Ints + jump target instruction index); the module computes basic blocks,
// CFG edges, forward reachability, dominator sets with immediate dominators,
// register liveness with interference pairs, and a deterministic text report.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Compatibility notes (XIOM v0.62.2, stdlib-perf1):
//   * Every list is a struct of mirrored Vec[Int] fields: Vec[StructType] is
//     unsupported, so Prog, Cfg, Reach, Doms and Live are flattened.
//   * Every Vec element read is bound to a typed local first; no Str ever
//     enters a Vec (the report is built by concatenation).
//   * No Result/Option values are produced or consumed: sentinels (AZ_NONE)
//     and total predicates keep every function defined for every input.
//   * Free functions only; no `&mut Int` parameters (scalars are threaded by
//     return values); every loop has an explicit, finite progress argument
//     (see SPEC.md "Progress and bounds").
//   * Public names are az_-prefixed; private helpers are _az_-prefixed.

module xiom.analyzer

use xiom.convert;

// ---------------------------------------------------------------------------
// Sentinels, opcodes, edge kinds
// ---------------------------------------------------------------------------

/// "No value": absent target, absent dominator, out-of-range accessor result.
pub const AZ_NONE: Int = -1;

/// No operation; no uses, no defs, falls through.
pub const AZ_OP_NOP: Int = 0;

/// dst := src; uses B, defines A.
pub const AZ_OP_MOV: Int = 1;

/// A := A + B; uses A and B, defines A.
pub const AZ_OP_ADD: Int = 2;

/// A := A - B; uses A and B, defines A.
pub const AZ_OP_SUB: Int = 3;

/// A := A * B; uses A and B, defines A.
pub const AZ_OP_MUL: Int = 4;

/// A := mem[B]; uses B, defines A.
pub const AZ_OP_LOAD: Int = 5;

/// mem[B] := A; uses A and B, defines nothing.
pub const AZ_OP_STORE: Int = 6;

/// Unconditional jump to `target`; no uses, no defs.
pub const AZ_OP_JMP: Int = 7;

/// Jump to `target` when A == 0; uses A, no defs.
pub const AZ_OP_JZ: Int = 8;

/// Jump to `target` when A != 0; uses A, no defs.
pub const AZ_OP_JNZ: Int = 9;

/// Return; no uses, no defs, no successors.
pub const AZ_OP_RET: Int = 10;

/// CFG edge kind: plain fallthrough (also the not-taken edge of a branch).
pub const AZ_EDGE_FALL: Int = 0;

/// CFG edge kind: unconditional branch (only emitted by JMP).
pub const AZ_EDGE_BRANCH: Int = 1;

/// CFG edge kind: conditional branch taken edge (JZ/JNZ).
pub const AZ_EDGE_COND: Int = 2;

// ---------------------------------------------------------------------------
// Types (all lists are flattened parallel Vec[Int] fields)
// ---------------------------------------------------------------------------

/// Generic instruction sequence: instruction i is
/// (opcodes[i], argA[i], argB[i], targets[i]). `targets[i]` is a jump target
/// instruction index for JMP/JZ/JNZ and AZ_NONE otherwise; operands are
/// register ids exactly where the use/def table says so (az_instr_uses_a,
/// az_instr_uses_b, az_instr_defs_a).
pub type Prog = {
  opcodes: Vec[Int];
  argA: Vec[Int];
  argB: Vec[Int];
  targets: Vec[Int];
}

/// Basic blocks and the CFG. Block k spans instructions [starts[k], ends[k]).
/// `owner[i]` is the block containing instruction i (always in range, one
/// entry per instruction). Edges are (edgeFrom[e], edgeTo[e], edgeKind[e]);
/// block adjacency is a linked list: head[b] is the first outgoing edge id
/// (AZ_NONE when the block has none) and nextEdge[e] the next outgoing edge
/// id of the same source block.
pub type Cfg = {
  starts: Vec[Int];
  ends: Vec[Int];
  owner: Vec[Int];
  edgeFrom: Vec[Int];
  edgeTo: Vec[Int];
  edgeKind: Vec[Int];
  head: Vec[Int];
  nextEdge: Vec[Int];
}

/// Forward reachability: flags[b] == 1 iff block b is reachable from block 0.
/// `order` is the DFS pop order of reachable blocks; `iterations` counts the
/// blocks popped (== the number of reachable blocks).
pub type Reach = {
  flags: Vec[Int];
  order: Vec[Int];
  iterations: Int;
}

/// Dominator sets over reachable blocks: has[b * n + x] == 1 iff x dominates
/// b. Unreachable blocks get the singleton {b}. idom[b] is the immediate
/// dominator, or AZ_NONE for the entry and for unreachable blocks.
/// `iterations` counts executed fixpoint passes; `boundHit` is 1 if the last
/// allowed pass still changed something (never observed, see SPEC.md).
pub type Doms = {
  n: Int;
  has: Vec[Int];
  idom: Vec[Int];
  iterations: Int;
  boundHit: Int;
}

/// Register liveness. Rows are flattened: row b of a matrix is at b * regs.
/// inBits/outBits are the live-in/live-out sets, useBits the upward-exposed
/// uses and defBits the definitions (use/def tables cover every block;
/// live sets are computed for reachable blocks only). `pairs` stores
/// interference pairs flattened as consecutive (a, b) with a < b; pairCount
/// is the number of pairs. `iterations` counts worklist pops; `boundHit` is 1
/// if the explicit worklist cap was reached (never observed, see SPEC.md).
pub type Live = {
  blocks: Int;
  regs: Int;
  inBits: Vec[Int];
  outBits: Vec[Int];
  useBits: Vec[Int];
  defBits: Vec[Int];
  pairs: Vec[Int];
  pairCount: Int;
  iterations: Int;
  boundHit: Int;
}

// ---------------------------------------------------------------------------
// Program construction and scalar accessors
// ---------------------------------------------------------------------------

/// An empty program. Complexity: O(1).
pub fn az_prog_new() -> Prog {
  return Prog{ opcodes: Vec[Int].new(); argA: Vec[Int].new(); argB: Vec[Int].new(); targets: Vec[Int].new(); };
}

/// Append instruction (op, a, b, target). Complexity: O(1) amortized.
pub fn az_prog_push(p: &mut Prog, op: Int, a: Int, b: Int, target: Int) {
  p.opcodes.push(op);
  p.argA.push(a);
  p.argB.push(b);
  p.targets.push(target);
}

/// Instruction count. Complexity: O(1).
pub fn az_prog_len(p: &Prog) -> Int {
  return p.opcodes.len();
}

/// Opcode of instruction i, or AZ_NONE out of range. Complexity: O(1).
pub fn az_prog_op(p: &Prog, i: Int) -> Int {
  if i < 0 || i >= p.opcodes.len() {
    return AZ_NONE;
  }
  let v: Int = p.opcodes[i];
  return v;
}

/// Operand A of instruction i, or 0 out of range. Complexity: O(1).
pub fn az_prog_a(p: &Prog, i: Int) -> Int {
  if i < 0 || i >= p.argA.len() {
    return 0;
  }
  let v: Int = p.argA[i];
  return v;
}

/// Operand B of instruction i, or 0 out of range. Complexity: O(1).
pub fn az_prog_b(p: &Prog, i: Int) -> Int {
  if i < 0 || i >= p.argB.len() {
    return 0;
  }
  let v: Int = p.argB[i];
  return v;
}

/// Jump target of instruction i, or AZ_NONE out of range. Complexity: O(1).
pub fn az_prog_target(p: &Prog, i: Int) -> Int {
  if i < 0 || i >= p.targets.len() {
    return AZ_NONE;
  }
  let v: Int = p.targets[i];
  return v;
}

// ---------------------------------------------------------------------------
// Instruction classification and use/def tables
// ---------------------------------------------------------------------------

/// True for the three branch opcodes (JMP, JZ, JNZ). Complexity: O(1).
pub fn az_is_branch(op: Int) -> Bool {
  return op == AZ_OP_JMP || op == AZ_OP_JZ || op == AZ_OP_JNZ;
}

/// True for conditional branches (JZ, JNZ). Complexity: O(1).
pub fn az_is_cond(op: Int) -> Bool {
  return op == AZ_OP_JZ || op == AZ_OP_JNZ;
}

/// True for instructions that can end a block without falling through into
/// the next instruction (JMP, RET). Complexity: O(1).
pub fn az_is_terminator(op: Int) -> Bool {
  return op == AZ_OP_JMP || op == AZ_OP_RET;
}

/// True when instruction `op` reads argA as a register: ADD, SUB, MUL, STORE
/// and the conditional branches. Complexity: O(1).
pub fn az_instr_uses_a(op: Int) -> Bool {
  if op == AZ_OP_ADD || op == AZ_OP_SUB || op == AZ_OP_MUL {
    return true;
  }
  if op == AZ_OP_STORE {
    return true;
  }
  return az_is_cond(op);
}

/// True when instruction `op` reads argB as a register: MOV, ADD, SUB, MUL,
/// LOAD and STORE. Complexity: O(1).
pub fn az_instr_uses_b(op: Int) -> Bool {
  if op == AZ_OP_MOV {
    return true;
  }
  if op == AZ_OP_ADD || op == AZ_OP_SUB || op == AZ_OP_MUL {
    return true;
  }
  return op == AZ_OP_LOAD || op == AZ_OP_STORE;
}

/// True when instruction `op` writes argA as a register: MOV, ADD, SUB, MUL
/// and LOAD. Complexity: O(1).
pub fn az_instr_defs_a(op: Int) -> Bool {
  if op == AZ_OP_MOV {
    return true;
  }
  if op == AZ_OP_ADD || op == AZ_OP_SUB || op == AZ_OP_MUL {
    return true;
  }
  return op == AZ_OP_LOAD;
}

/// Lowercase mnemonic for an opcode; unknown opcodes render as "op<code>".
/// Complexity: O(digits).
pub fn az_op_name(op: Int) -> Str {
  if op == AZ_OP_NOP {
    return "nop";
  }
  if op == AZ_OP_MOV {
    return "mov";
  }
  if op == AZ_OP_ADD {
    return "add";
  }
  if op == AZ_OP_SUB {
    return "sub";
  }
  if op == AZ_OP_MUL {
    return "mul";
  }
  if op == AZ_OP_LOAD {
    return "load";
  }
  if op == AZ_OP_STORE {
    return "store";
  }
  if op == AZ_OP_JMP {
    return "jmp";
  }
  if op == AZ_OP_JZ {
    return "jz";
  }
  if op == AZ_OP_JNZ {
    return "jnz";
  }
  if op == AZ_OP_RET {
    return "ret";
  }
  return "op" + int_to_string(op);
}

/// Stable name of an edge kind: fallthrough, branch, conditional, unknown.
/// Complexity: O(1).
pub fn az_edge_kind_name(kind: Int) -> Str {
  if kind == AZ_EDGE_FALL {
    return "fallthrough";
  }
  if kind == AZ_EDGE_BRANCH {
    return "branch";
  }
  if kind == AZ_EDGE_COND {
    return "conditional";
  }
  return "unknown";
}

// ---------------------------------------------------------------------------
// Basic blocks and CFG construction
// ---------------------------------------------------------------------------

/// Append one edge to the CFG and link it into the source block's adjacency
/// list (head insertion, so a block's successors enumerate newest-first).
/// Complexity: O(1).
fn _az_edge_add(c: &mut Cfg, from: Int, to: Int, kind: Int) {
  let e = c.edgeFrom.len();
  c.edgeFrom.push(from);
  c.edgeTo.push(to);
  c.edgeKind.push(kind);
  let prev: Int = c.head[from];
  c.nextEdge.push(prev);
  c.head[from] = e;
}

/// Build basic blocks and the CFG from `p`.
///
/// Leaders are (1) instruction 0 (entry), (2) every valid jump target, and
/// (3) every instruction that follows a branch or RET (the fallthrough
/// boundary; for JMP/RET the following instruction starts a fresh, possibly
/// unreachable block). Block k is then [starts[k], ends[k]).
///
/// Edge rules on a block's last instruction `t`:
///   * JMP with a valid target      -> one BRANCH edge;
///   * JZ/JNZ with a valid target   -> one COND edge, plus one FALL edge to
///     the next block when t + 1 exists;
///   * RET                          -> no edge;
///   * any other opcode             -> one FALL edge to the next block when
///     t + 1 exists.
/// Invalid or missing targets emit no branch edge.
///
/// Params: p - the instruction list (never mutated).
/// Returns: the Cfg (block 0 is the entry when the program is non-empty).
/// Complexity: O(n + blocks + edges); the leader scan and block fill each
/// visit every instruction exactly once.
pub fn az_cfg_build(p: &Prog) -> Cfg {
  var c = Cfg{
    starts: Vec[Int].new();
    ends: Vec[Int].new();
    owner: Vec[Int].new();
    edgeFrom: Vec[Int].new();
    edgeTo: Vec[Int].new();
    edgeKind: Vec[Int].new();
    head: Vec[Int].new();
    nextEdge: Vec[Int].new();
  };
  let n = az_prog_len(p);
  if n == 0 {
    return c;
  }
  var isLeader = Vec[Int].new();
  var i = 0;
  while i < n {
    isLeader.push(0);
    i = i + 1;
  }
  isLeader[0] = 1;
  i = 0;
  while i < n {
    let op = az_prog_op(p, i);
    let t = az_prog_target(p, i);
    if az_is_branch(op) {
      if t >= 0 && t < n {
        isLeader[t] = 1;
      }
      if i + 1 < n {
        isLeader[i + 1] = 1;
      }
    } elif op == AZ_OP_RET {
      if i + 1 < n {
        isLeader[i + 1] = 1;
      }
    }
    i = i + 1;
  }
  var b = 0;
  while b < n {
    let lf: Int = isLeader[b];
    if lf == 1 {
      c.starts.push(b);
    }
    b = b + 1;
  }
  let nb = c.starts.len();
  var k = 0;
  while k < nb {
    let st: Int = c.starts[k];
    var en = n;
    if k + 1 < nb {
      en = c.starts[k + 1];
    }
    c.ends.push(en);
    k = k + 1;
  }
  i = 0;
  while i < n {
    c.owner.push(AZ_NONE);
    i = i + 1;
  }
  k = 0;
  while k < nb {
    let st: Int = c.starts[k];
    let en: Int = c.ends[k];
    i = st;
    while i < en {
      c.owner[i] = k;
      i = i + 1;
    }
    k = k + 1;
  }
  k = 0;
  while k < nb {
    c.head.push(AZ_NONE);
    k = k + 1;
  }
  k = 0;
  while k < nb {
    let en: Int = c.ends[k];
    let last = en - 1;
    let op = az_prog_op(p, last);
    let t = az_prog_target(p, last);
    if op == AZ_OP_JMP {
      if t >= 0 && t < n {
        let tb: Int = c.owner[t];
        _az_edge_add(&mut c, k, tb, AZ_EDGE_BRANCH);
      }
    } elif az_is_cond(op) {
      if last + 1 < n {
        let fb: Int = c.owner[last + 1];
        _az_edge_add(&mut c, k, fb, AZ_EDGE_FALL);
      }
      if t >= 0 && t < n {
        let tb: Int = c.owner[t];
        _az_edge_add(&mut c, k, tb, AZ_EDGE_COND);
      }
    } elif op != AZ_OP_RET {
      if last + 1 < n {
        let fb: Int = c.owner[last + 1];
        _az_edge_add(&mut c, k, fb, AZ_EDGE_FALL);
      }
    }
    k = k + 1;
  }
  return c;
}

/// Number of basic blocks (0 for an empty program). Complexity: O(1).
pub fn az_cfg_block_count(c: &Cfg) -> Int {
  return c.starts.len();
}

/// First instruction index of block b, or AZ_NONE out of range. O(1).
pub fn az_cfg_block_start(c: &Cfg, b: Int) -> Int {
  if b < 0 || b >= c.starts.len() {
    return AZ_NONE;
  }
  let v: Int = c.starts[b];
  return v;
}

/// One-past-last instruction index of block b, or AZ_NONE out of range. O(1).
pub fn az_cfg_block_end(c: &Cfg, b: Int) -> Int {
  if b < 0 || b >= c.ends.len() {
    return AZ_NONE;
  }
  let v: Int = c.ends[b];
  return v;
}

/// Block containing instruction i, or AZ_NONE out of range. Complexity: O(1).
pub fn az_cfg_block_of_instr(c: &Cfg, i: Int) -> Int {
  if i < 0 || i >= c.owner.len() {
    return AZ_NONE;
  }
  let b: Int = c.owner[i];
  return b;
}

/// Number of CFG edges. Complexity: O(1).
pub fn az_cfg_edge_count(c: &Cfg) -> Int {
  return c.edgeFrom.len();
}

/// Source block of edge e, or AZ_NONE out of range. Complexity: O(1).
pub fn az_cfg_edge_from(c: &Cfg, e: Int) -> Int {
  if e < 0 || e >= c.edgeFrom.len() {
    return AZ_NONE;
  }
  let v: Int = c.edgeFrom[e];
  return v;
}

/// Destination block of edge e, or AZ_NONE out of range. Complexity: O(1).
pub fn az_cfg_edge_to(c: &Cfg, e: Int) -> Int {
  if e < 0 || e >= c.edgeTo.len() {
    return AZ_NONE;
  }
  let v: Int = c.edgeTo[e];
  return v;
}

/// Kind of edge e, or AZ_NONE out of range. Complexity: O(1).
pub fn az_cfg_edge_kind(c: &Cfg, e: Int) -> Int {
  if e < 0 || e >= c.edgeKind.len() {
    return AZ_NONE;
  }
  let v: Int = c.edgeKind[e];
  return v;
}

/// Number of outgoing edges of block b. Complexity: O(out-degree).
pub fn az_cfg_succ_count(c: &Cfg, b: Int) -> Int {
  if b < 0 || b >= c.head.len() {
    return 0;
  }
  var e: Int = c.head[b];
  var n = 0;
  while e >= 0 {
    let nx: Int = c.nextEdge[e];
    e = nx;
    n = n + 1;
  }
  return n;
}

/// Edge id of the k-th outgoing edge of block b in enumeration order
/// (newest-first linked list; for a conditional that is the taken edge, then
/// the fallthrough edge), or AZ_NONE. Complexity: O(k).
pub fn az_cfg_succ_edge(c: &Cfg, b: Int, k: Int) -> Int {
  if b < 0 || b >= c.head.len() || k < 0 {
    return AZ_NONE;
  }
  var e: Int = c.head[b];
  var i = 0;
  while e >= 0 && i < k {
    let nx: Int = c.nextEdge[e];
    e = nx;
    i = i + 1;
  }
  return e;
}

/// Destination block of the k-th outgoing edge of block b, or AZ_NONE.
/// Complexity: O(k).
pub fn az_cfg_succ(c: &Cfg, b: Int, k: Int) -> Int {
  let e = az_cfg_succ_edge(c, b, k);
  if e < 0 {
    return AZ_NONE;
  }
  let to: Int = c.edgeTo[e];
  return to;
}

/// Number of incoming edges of block b. Complexity: O(edges).
pub fn az_cfg_pred_count(c: &Cfg, b: Int) -> Int {
  var n = 0;
  var e = 0;
  while e < c.edgeTo.len() {
    let to: Int = c.edgeTo[e];
    if to == b {
      n = n + 1;
    }
    e = e + 1;
  }
  return n;
}

/// Source block of the k-th incoming edge of block b (edge-id ascending), or
/// AZ_NONE. Complexity: O(edges).
pub fn az_cfg_pred_at(c: &Cfg, b: Int, k: Int) -> Int {
  if k < 0 {
    return AZ_NONE;
  }
  var seen = 0;
  var e = 0;
  while e < c.edgeTo.len() {
    let to: Int = c.edgeTo[e];
    if to == b {
      if seen == k {
        let from: Int = c.edgeFrom[e];
        return from;
      }
      seen = seen + 1;
    }
    e = e + 1;
  }
  return AZ_NONE;
}

// ---------------------------------------------------------------------------
// Forward reachability
// ---------------------------------------------------------------------------

/// DFS from block 0 (when the program has blocks). Every reachable block is
/// pushed at most once and every iteration pops exactly one block, so the
/// loop terminates after at most one pop per block.
///
/// Params: c - the CFG (never mutated).
/// Returns: reachability flags, pop order and the number of pops.
/// Complexity: O(blocks + edges).
pub fn az_reach_build(c: &Cfg) -> Reach {
  var r = Reach{ flags: Vec[Int].new(); order: Vec[Int].new(); iterations: 0; };
  let nb = az_cfg_block_count(c);
  var i = 0;
  while i < nb {
    r.flags.push(0);
    i = i + 1;
  }
  if nb == 0 {
    return r;
  }
  // Explicit LIFO stack with a logical top `sp`. Pushes overwrite the slot at
  // `sp` when it already exists (a previous pop left it stale) so the top is
  // always stack[sp - 1].
  var stack = Vec[Int].new();
  var sp = 0;
  stack.push(0);
  sp = 1;
  r.flags[0] = 1;
  while sp > 0 {
    let b: Int = stack[sp - 1];
    sp = sp - 1;
    r.order.push(b);
    r.iterations = r.iterations + 1;
    let sc = az_cfg_succ_count(c, b);
    var k = 0;
    while k < sc {
      let s = az_cfg_succ(c, b, k);
      if s >= 0 && s < nb {
        let f: Int = r.flags[s];
        if f == 0 {
          r.flags[s] = 1;
          if sp < stack.len() {
            stack[sp] = s;
          } else {
            stack.push(s);
          }
          sp = sp + 1;
        }
      }
      k = k + 1;
    }
  }
  return r;
}

/// Number of blocks tracked (== CFG block count). Complexity: O(1).
pub fn az_reach_block_count(r: &Reach) -> Int {
  return r.flags.len();
}

/// True when block b is reachable from block 0. Complexity: O(1).
pub fn az_reach_is_reachable(r: &Reach, b: Int) -> Bool {
  if b < 0 || b >= r.flags.len() {
    return false;
  }
  let f: Int = r.flags[b];
  return f == 1;
}

/// Number of reachable blocks. Complexity: O(blocks).
pub fn az_reach_count(r: &Reach) -> Int {
  var n = 0;
  var i = 0;
  while i < r.flags.len() {
    let f: Int = r.flags[i];
    n = n + f;
    i = i + 1;
  }
  return n;
}

/// Number of DFS pop-order entries. Complexity: O(1).
pub fn az_reach_order_count(r: &Reach) -> Int {
  return r.order.len();
}

/// Pop-order entry i, or AZ_NONE out of range. Complexity: O(1).
pub fn az_reach_order_at(r: &Reach, i: Int) -> Int {
  if i < 0 || i >= r.order.len() {
    return AZ_NONE;
  }
  let v: Int = r.order[i];
  return v;
}

/// Number of blocks popped by the DFS. Complexity: O(1).
pub fn az_reach_iterations(r: &Reach) -> Int {
  return r.iterations;
}

/// Number of unreachable blocks. Complexity: O(blocks).
pub fn az_reach_unreachable_count(r: &Reach) -> Int {
  var n = 0;
  var i = 0;
  while i < r.flags.len() {
    let f: Int = r.flags[i];
    if f == 0 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Id of the i-th unreachable block in ascending order, or AZ_NONE.
/// Complexity: O(blocks).
pub fn az_reach_unreachable_at(r: &Reach, i: Int) -> Int {
  if i < 0 {
    return AZ_NONE;
  }
  var seen = 0;
  var b = 0;
  while b < r.flags.len() {
    let f: Int = r.flags[b];
    if f == 0 {
      if seen == i {
        return b;
      }
      seen = seen + 1;
    }
    b = b + 1;
  }
  return AZ_NONE;
}

// ---------------------------------------------------------------------------
// Dominators (iterative intersection fixpoint over reachable blocks)
// ---------------------------------------------------------------------------

/// Build dominator sets and immediate dominators.
///
/// Initialization: dom(0) = {0}; for every reachable non-entry block b,
/// dom(b) = all reachable blocks; for unreachable b, dom(b) = {b}.
///
/// Fixpoint per reachable b != 0:
///   dom(b) = {b} union (intersection of dom(p) over reachable predecessors p)
/// Each pass visits blocks 1..n-1 in ascending order and updates in place.
///
/// Progress and bound: every dom set only shrinks (from the reachable
/// universe toward the intersection); a pass either removes at least one
/// element from at least one set or performs no change. At most n passes are
/// executed (`while iter < n`), so the fixpoint is bounded by the block
/// count; a chain of n blocks converges in n-1 passes. If the n-th pass still
/// changed something, boundHit is set to 1 (defensive; not reachable for
/// well-formed CFGs, see SPEC.md).
///
/// Immediate dominator: the dominator of b other than b with the largest
/// dom-set cardinality (dominators of b are totally ordered by inclusion, so
/// the deepest one is unique and is the immediate dominator).
///
/// Params: c - the CFG; r - reachability of c.
/// Returns: the Doms.
/// Complexity: O(n^3) worst case (n passes x n blocks x n preds/row width).
pub fn az_dom_build(c: &Cfg, r: &Reach) -> Doms {
  let n = az_cfg_block_count(c);
  var d = Doms{ n: n; has: Vec[Int].new(); idom: Vec[Int].new(); iterations: 0; boundHit: 0; };
  var i = 0;
  while i < n * n {
    d.has.push(0);
    i = i + 1;
  }
  i = 0;
  while i < n {
    d.idom.push(AZ_NONE);
    i = i + 1;
  }
  if n == 0 {
    return d;
  }
  d.has[0] = 1;
  var b = 1;
  while b < n {
    let f: Int = r.flags[b];
    if f == 1 {
      var x = 0;
      while x < n {
        let xf: Int = r.flags[x];
        if xf == 1 {
          d.has[b * n + x] = 1;
        }
        x = x + 1;
      }
    } else {
      d.has[b * n + b] = 1;
    }
    b = b + 1;
  }
  var row = Vec[Int].new();
  i = 0;
  while i < n {
    row.push(0);
    i = i + 1;
  }
  var iter = 0;
  var done = 0;
  while iter < n {
    var changed = 0;
    b = 1;
    while b < n {
      let f: Int = r.flags[b];
      if f == 1 {
        var z = 0;
        while z < n {
          row[z] = 0;
          z = z + 1;
        }
        var first = 1;
        let pc = az_cfg_pred_count(c, b);
        var pi = 0;
        while pi < pc {
          let p = az_cfg_pred_at(c, b, pi);
          let pf: Int = r.flags[p];
          if pf == 1 {
            if first == 1 {
              var x = 0;
              while x < n {
                let hv: Int = d.has[p * n + x];
                row[x] = hv;
                x = x + 1;
              }
              first = 0;
            } else {
              var x = 0;
              while x < n {
                let hv: Int = d.has[p * n + x];
                if hv == 0 {
                  row[x] = 0;
                }
                x = x + 1;
              }
            }
          }
          pi = pi + 1;
        }
        if first == 1 {
          var x = 0;
          while x < n {
            row[x] = 0;
            x = x + 1;
          }
        }
        row[b] = 1;
        var x = 0;
        while x < n {
          let ov: Int = d.has[b * n + x];
          let nv: Int = row[x];
          if ov != nv {
            changed = 1;
            d.has[b * n + x] = nv;
          }
          x = x + 1;
        }
      }
      b = b + 1;
    }
    d.iterations = d.iterations + 1;
    iter = iter + 1;
    if changed == 0 {
      done = 1;
    }
    if done == 1 {
      break;
    }
  }
  if done == 0 {
    d.boundHit = 1;
  }
  if n > 0 {
    d.idom[0] = AZ_NONE;
  }
  b = 1;
  while b < n {
    let f: Int = r.flags[b];
    if f == 1 {
      var best = AZ_NONE;
      var bestSize = -1;
      var x = 0;
      while x < n {
        let hv: Int = d.has[b * n + x];
        if hv == 1 && x != b {
          var sz = 0;
          var y = 0;
          while y < n {
            let hx: Int = d.has[x * n + y];
            sz = sz + hx;
            y = y + 1;
          }
          if sz > bestSize {
            bestSize = sz;
            best = x;
          }
        }
        x = x + 1;
      }
      d.idom[b] = best;
    }
    b = b + 1;
  }
  return d;
}

/// Number of blocks covered by the dominator sets. Complexity: O(1).
pub fn az_dom_block_count(d: &Doms) -> Int {
  return d.n;
}

/// True when x dominates b. Complexity: O(1).
pub fn az_dom_has(d: &Doms, b: Int, x: Int) -> Bool {
  if b < 0 || b >= d.n || x < 0 || x >= d.n {
    return false;
  }
  let v: Int = d.has[b * d.n + x];
  return v == 1;
}

/// Cardinality of dom(b), or 0 out of range. Complexity: O(n).
pub fn az_dom_size(d: &Doms, b: Int) -> Int {
  if b < 0 || b >= d.n {
    return 0;
  }
  var n = 0;
  var x = 0;
  while x < d.n {
    let v: Int = d.has[b * d.n + x];
    n = n + v;
    x = x + 1;
  }
  return n;
}

/// Immediate dominator of b: AZ_NONE for the entry, for unreachable blocks
/// and out of range. Complexity: O(1).
pub fn az_dom_idom(d: &Doms, b: Int) -> Int {
  if b < 0 || b >= d.n {
    return AZ_NONE;
  }
  let v: Int = d.idom[b];
  return v;
}

/// Number of fixpoint passes executed. Complexity: O(1).
pub fn az_dom_iterations(d: &Doms) -> Int {
  return d.iterations;
}

/// True when the explicit pass bound was exhausted while still changing.
/// Complexity: O(1).
pub fn az_dom_bound_hit(d: &Doms) -> Bool {
  return d.boundHit == 1;
}

// ---------------------------------------------------------------------------
// Liveness and interference
// ---------------------------------------------------------------------------

/// Read one bit of the use/def tables: which 1 = use, 0 = def. Complexity: O(1).
fn _az_live_table(lv: &Live, b: Int, r: Int, which: Int) -> Int {
  if b < 0 || b >= lv.blocks {
    return 0;
  }
  if r < 0 || r >= lv.regs {
    return 0;
  }
  if which == 1 {
    let v: Int = lv.useBits[b * lv.regs + r];
    return v;
  }
  let v2: Int = lv.defBits[b * lv.regs + r];
  return v2;
}

/// Read one bit of the live sets: which 1 = in, 0 = out. Complexity: O(1).
fn _az_live_bit(lv: &Live, b: Int, r: Int, which: Int) -> Int {
  if b < 0 || b >= lv.blocks {
    return 0;
  }
  if r < 0 || r >= lv.regs {
    return 0;
  }
  if which == 1 {
    let v: Int = lv.inBits[b * lv.regs + r];
    return v;
  }
  let v2: Int = lv.outBits[b * lv.regs + r];
  return v2;
}

/// Build block-level use/def tables, live-in/live-out sets and the
/// interference pairs.
///
/// Register count is max(register mentioned by the use/def tables) + 1
/// (0 when no instruction mentions a register). Block use/def: scanning each
/// block in instruction order, a use joins useBits only when the register has
/// not been defined earlier in the block (upward-exposed use); every def
/// joins defBits. Both tables are computed for all blocks.
///
/// Live sets are computed only for reachable blocks (an unreachable block is
/// dead by definition, so its sets stay empty). Worklist equations:
///   live_out(b) = union of live_in(s) over successors s
///   live_in(b)  = use(b) union (live_out(b) minus def(b))
/// The worklist starts with every reachable block; a block whose sets changed
/// re-queues its predecessors (deduplicated by a queued flag).
///
/// Progress and bound: every set only grows; each iteration pops one worklist
/// entry and only a changed iteration can push entries, so pushes <= total
/// bits added <= 2 * blocks * regs and iterations <= blocks + 2 * cells.
/// The explicit cap is `2 * cells + blocks + 2`; on exhaustion boundHit is set
/// to 1 (defensive, see SPEC.md).
///
/// Interference: registers a < b interfere when both are live-out at the same
/// block; pairs are collected block-ascending then a-ascending, deduplicated,
/// and flattened into `pairs`.
///
/// Params: p - the program; c - the CFG of p; r - reachability of c.
/// Returns: the Live.
/// Complexity: O(iterations * regs + blocks * regs^2).
pub fn az_live_build(p: &Prog, c: &Cfg, r: &Reach) -> Live {
  let nb = az_cfg_block_count(c);
  let n = az_prog_len(p);
  var maxr = -1;
  var i = 0;
  while i < n {
    let op = az_prog_op(p, i);
    let a = az_prog_a(p, i);
    let b = az_prog_b(p, i);
    if az_instr_uses_a(op) {
      if a > maxr {
        maxr = a;
      }
    }
    if az_instr_uses_b(op) {
      if b > maxr {
        maxr = b;
      }
    }
    if az_instr_defs_a(op) {
      if a > maxr {
        maxr = a;
      }
    }
    i = i + 1;
  }
  var regs = maxr + 1;
  if regs < 0 {
    regs = 0;
  }
  var lv = Live{
    blocks: nb;
    regs: regs;
    inBits: Vec[Int].new();
    outBits: Vec[Int].new();
    useBits: Vec[Int].new();
    defBits: Vec[Int].new();
    pairs: Vec[Int].new();
    pairCount: 0;
    iterations: 0;
    boundHit: 0;
  };
  let cells = nb * regs;
  i = 0;
  while i < cells {
    lv.inBits.push(0);
    lv.outBits.push(0);
    lv.useBits.push(0);
    lv.defBits.push(0);
    i = i + 1;
  }
  var bk = 0;
  while bk < nb {
    let st: Int = az_cfg_block_start(c, bk);
    let en: Int = az_cfg_block_end(c, bk);
    i = st;
    while i < en {
      let op = az_prog_op(p, i);
      let a = az_prog_a(p, i);
      let b = az_prog_b(p, i);
      if az_instr_uses_a(op) {
        if a >= 0 && a < regs {
          let idxA = bk * regs + a;
          let dvA: Int = lv.defBits[idxA];
          if dvA == 0 {
            lv.useBits[idxA] = 1;
          }
        }
      }
      if az_instr_uses_b(op) {
        if b >= 0 && b < regs {
          let idxB = bk * regs + b;
          let dvB: Int = lv.defBits[idxB];
          if dvB == 0 {
            lv.useBits[idxB] = 1;
          }
        }
      }
      if az_instr_defs_a(op) {
        if a >= 0 && a < regs {
          lv.defBits[bk * regs + a] = 1;
        }
      }
      i = i + 1;
    }
    bk = bk + 1;
  }
  var queue = Vec[Int].new();
  var queued = Vec[Int].new();
  bk = 0;
  while bk < nb {
    queued.push(0);
    let rf: Int = r.flags[bk];
    if rf == 1 {
      queue.push(bk);
      queued[bk] = 1;
    }
    bk = bk + 1;
  }
  var head = 0;
  let cap = 2 * cells + nb + 2;
  while head < queue.len() {
    if lv.iterations >= cap {
      lv.boundHit = 1;
      break;
    }
    let blk: Int = queue[head];
    head = head + 1;
    queued[blk] = 0;
    var changed = 0;
    let sc = az_cfg_succ_count(c, blk);
    var si = 0;
    while si < sc {
      let sb = az_cfg_succ(c, blk, si);
      if sb >= 0 && sb < nb {
        var rx = 0;
        while rx < regs {
          let iv: Int = lv.inBits[sb * regs + rx];
          let ov: Int = lv.outBits[blk * regs + rx];
          if iv == 1 && ov == 0 {
            lv.outBits[blk * regs + rx] = 1;
            changed = 1;
          }
          rx = rx + 1;
        }
      }
      si = si + 1;
    }
    var rj = 0;
    while rj < regs {
      var want = 0;
      let uv: Int = lv.useBits[blk * regs + rj];
      if uv == 1 {
        want = 1;
      } else {
        let ov2: Int = lv.outBits[blk * regs + rj];
        let dv2: Int = lv.defBits[blk * regs + rj];
        if ov2 == 1 && dv2 == 0 {
          want = 1;
        }
      }
      let cur: Int = lv.inBits[blk * regs + rj];
      if cur != want {
        lv.inBits[blk * regs + rj] = want;
        changed = 1;
      }
      rj = rj + 1;
    }
    if changed == 1 {
      let pc = az_cfg_pred_count(c, blk);
      var pi = 0;
      while pi < pc {
        let pb = az_cfg_pred_at(c, blk, pi);
        let qf: Int = queued[pb];
        if qf == 0 {
          queued[pb] = 1;
          queue.push(pb);
        }
        pi = pi + 1;
      }
    }
    lv.iterations = lv.iterations + 1;
  }
  _az_live_pairs(&mut lv);
  return lv;
}

/// Collect deduplicated interference pairs from the live-out sets (see
/// az_live_build). Complexity: O(blocks * regs^2 + pairs^2).
fn _az_live_pairs(lv: &mut Live) {
  let nb = lv.blocks;
  let regs = lv.regs;
  if nb == 0 || regs < 2 {
    return;
  }
  var bk = 0;
  while bk < nb {
    var r1 = 0;
    while r1 < regs {
      let o1: Int = lv.outBits[bk * regs + r1];
      if o1 == 1 {
        var r2 = r1 + 1;
        while r2 < regs {
          let o2: Int = lv.outBits[bk * regs + r2];
          if o2 == 1 {
            var dup = 0;
            let pc = lv.pairCount;
            var pi = 0;
            while pi < pc {
              let pa: Int = lv.pairs[pi * 2];
              let pb: Int = lv.pairs[pi * 2 + 1];
              if pa == r1 && pb == r2 {
                dup = 1;
              }
              pi = pi + 1;
            }
            if dup == 0 {
              lv.pairs.push(r1);
              lv.pairs.push(r2);
              lv.pairCount = lv.pairCount + 1;
            }
          }
          r2 = r2 + 1;
        }
      }
      r1 = r1 + 1;
    }
    bk = bk + 1;
  }
}

/// Number of blocks tracked. Complexity: O(1).
pub fn az_live_block_count(lv: &Live) -> Int {
  return lv.blocks;
}

/// Number of registers tracked (max mentioned register + 1). Complexity: O(1).
pub fn az_live_reg_count(lv: &Live) -> Int {
  return lv.regs;
}

/// True when register r is live-in at block b. Complexity: O(1).
pub fn az_live_in(lv: &Live, b: Int, r: Int) -> Bool {
  return _az_live_bit(lv, b, r, 1) == 1;
}

/// True when register r is live-out at block b. Complexity: O(1).
pub fn az_live_out(lv: &Live, b: Int, r: Int) -> Bool {
  return _az_live_bit(lv, b, r, 0) == 1;
}

/// True when register r is an upward-exposed use of block b. Complexity: O(1).
pub fn az_live_use(lv: &Live, b: Int, r: Int) -> Bool {
  return _az_live_table(lv, b, r, 1) == 1;
}

/// True when register r is defined in block b. Complexity: O(1).
pub fn az_live_def(lv: &Live, b: Int, r: Int) -> Bool {
  return _az_live_table(lv, b, r, 0) == 1;
}

/// Cardinality of live-in at block b. Complexity: O(regs).
pub fn az_live_in_count(lv: &Live, b: Int) -> Int {
  if b < 0 || b >= lv.blocks {
    return 0;
  }
  var n = 0;
  var r = 0;
  while r < lv.regs {
    let v: Int = lv.inBits[b * lv.regs + r];
    n = n + v;
    r = r + 1;
  }
  return n;
}

/// Cardinality of live-out at block b. Complexity: O(regs).
pub fn az_live_out_count(lv: &Live, b: Int) -> Int {
  if b < 0 || b >= lv.blocks {
    return 0;
  }
  var n = 0;
  var r = 0;
  while r < lv.regs {
    let v: Int = lv.outBits[b * lv.regs + r];
    n = n + v;
    r = r + 1;
  }
  return n;
}

/// Number of interference pairs. Complexity: O(1).
pub fn az_live_pair_count(lv: &Live) -> Int {
  return lv.pairCount;
}

/// Lower register of pair i, or AZ_NONE out of range. Complexity: O(1).
pub fn az_live_pair_a_at(lv: &Live, i: Int) -> Int {
  if i < 0 || i >= lv.pairCount {
    return AZ_NONE;
  }
  let v: Int = lv.pairs[i * 2];
  return v;
}

/// Higher register of pair i, or AZ_NONE out of range. Complexity: O(1).
pub fn az_live_pair_b_at(lv: &Live, i: Int) -> Int {
  if i < 0 || i >= lv.pairCount {
    return AZ_NONE;
  }
  let v: Int = lv.pairs[i * 2 + 1];
  return v;
}

/// Number of worklist pops executed. Complexity: O(1).
pub fn az_live_iterations(lv: &Live) -> Int {
  return lv.iterations;
}

/// True when the explicit worklist cap was exhausted. Complexity: O(1).
pub fn az_live_bound_hit(lv: &Live) -> Bool {
  return lv.boundHit == 1;
}

// ---------------------------------------------------------------------------
// Deterministic text report
// ---------------------------------------------------------------------------

/// Space-joined ids of blocks with flags[b] == 1, or "(none)".
fn _az_flag_list(r: &Reach) -> Str {
  var out = "";
  var first = 1;
  var i = 0;
  while i < r.flags.len() {
    let f: Int = r.flags[i];
    if f == 1 {
      if first == 0 {
        out = out + " ";
      }
      out = out + int_to_string(i);
      first = 0;
    }
    i = i + 1;
  }
  if first == 1 {
    return "(none)";
  }
  return out;
}

/// Space-joined ids of blocks with flags[b] == 0, or "(none)".
fn _az_off_list(r: &Reach) -> Str {
  var out = "";
  var first = 1;
  var i = 0;
  while i < r.flags.len() {
    let f: Int = r.flags[i];
    if f == 0 {
      if first == 0 {
        out = out + " ";
      }
      out = out + int_to_string(i);
      first = 0;
    }
    i = i + 1;
  }
  if first == 1 {
    return "(none)";
  }
  return out;
}

/// "{x,y,...}" for dom(b). Complexity: O(n).
fn _az_dom_text(d: &Doms, b: Int) -> Str {
  var out = "{";
  var first = 1;
  var x = 0;
  while x < d.n {
    let hv: Int = d.has[b * d.n + x];
    if hv == 1 {
      if first == 0 {
        out = out + ",";
      }
      out = out + int_to_string(x);
      first = 0;
    }
    x = x + 1;
  }
  return out + "}";
}

/// "{r,...}" for the live-in (which 1) or live-out (which 0) set of block b.
fn _az_live_text(lv: &Live, b: Int, which: Int) -> Str {
  var out = "{";
  var first = 1;
  var r = 0;
  while r < lv.regs {
    let v = _az_live_bit(lv, b, r, which);
    if v == 1 {
      if first == 0 {
        out = out + ",";
      }
      out = out + int_to_string(r);
      first = 0;
    }
    r = r + 1;
  }
  return out + "}";
}

/// "(a,b) (c,d) ..." for the interference pairs, or "(none)".
fn _az_pairs_text(lv: &Live) -> Str {
  var out = "";
  var first = 1;
  var i = 0;
  while i < lv.pairCount {
    let a: Int = lv.pairs[i * 2];
    let b: Int = lv.pairs[i * 2 + 1];
    if first == 0 {
      out = out + " ";
    }
    out = out + "(" + int_to_string(a) + "," + int_to_string(b) + ")";
    first = 0;
    i = i + 1;
  }
  if first == 1 {
    return "(none)";
  }
  return out;
}

/// One deterministic text report for `p`: instruction/block/edge counts,
/// block ranges with successors (`<dest>/<kind>` per successor), the edge
/// list (edge-id order), reachable/unreachable block ids, dominator sets,
/// immediate dominators, fixpoint pass counts and the liveness rows with the
/// interference pairs. Every line is LF-terminated; the report always ends
/// with a newline. Complexity: O(n^3) dominated by dominators.
pub fn az_report(p: &Prog) -> Str {
  let c = az_cfg_build(p);
  let r = az_reach_build(&c);
  let d = az_dom_build(&c, &r);
  let lv = az_live_build(p, &c, &r);
  let nb = az_cfg_block_count(&c);
  let ne = az_cfg_edge_count(&c);
  var out = "xiom.analyzer report\n";
  out = out + "instructions: " + int_to_string(az_prog_len(p)) + "\n";
  out = out + "blocks: " + int_to_string(nb) + "\n";
  out = out + "edges: " + int_to_string(ne) + "\n";
  var bk = 0;
  while bk < nb {
    out = out + "block " + int_to_string(bk) + " [" + int_to_string(az_cfg_block_start(&c, bk)) + "," + int_to_string(az_cfg_block_end(&c, bk)) + ") succ:";
    let sc = az_cfg_succ_count(&c, bk);
    if sc == 0 {
      out = out + " (none)";
    }
    var si = 0;
    while si < sc {
      let eb = az_cfg_succ_edge(&c, bk, si);
      out = out + " " + int_to_string(az_cfg_succ(&c, bk, si)) + "/" + az_edge_kind_name(az_cfg_edge_kind(&c, eb));
      si = si + 1;
    }
    out = out + "\n";
    bk = bk + 1;
  }
  var ei = 0;
  while ei < ne {
    out = out + "edge " + int_to_string(ei) + ": " + int_to_string(az_cfg_edge_from(&c, ei)) + "->" + int_to_string(az_cfg_edge_to(&c, ei)) + " " + az_edge_kind_name(az_cfg_edge_kind(&c, ei)) + "\n";
    ei = ei + 1;
  }
  out = out + "reachable: " + _az_flag_list(&r) + "\n";
  out = out + "unreachable: " + _az_off_list(&r) + "\n";
  bk = 0;
  while bk < nb {
    out = out + "dom " + int_to_string(bk) + ": " + _az_dom_text(&d, bk) + "\n";
    bk = bk + 1;
  }
  bk = 0;
  while bk < nb {
    out = out + "idom " + int_to_string(bk) + ": " + int_to_string(az_dom_idom(&d, bk)) + "\n";
    bk = bk + 1;
  }
  out = out + "dom iterations: " + int_to_string(az_dom_iterations(&d));
  if az_dom_bound_hit(&d) {
    out = out + " (bound hit)";
  }
  out = out + "\n";
  out = out + "live regs: " + int_to_string(az_live_reg_count(&lv)) + "\n";
  bk = 0;
  while bk < nb {
    out = out + "live-in " + int_to_string(bk) + ": " + _az_live_text(&lv, bk, 1) + "\n";
    out = out + "live-out " + int_to_string(bk) + ": " + _az_live_text(&lv, bk, 0) + "\n";
    bk = bk + 1;
  }
  out = out + "live iterations: " + int_to_string(az_live_iterations(&lv));
  if az_live_bound_hit(&lv) {
    out = out + " (bound hit)";
  }
  out = out + "\n";
  out = out + "interference: " + _az_pairs_text(&lv) + "\n";
  return out;
}
