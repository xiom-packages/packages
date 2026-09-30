# xiom.codegen-fw -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.codegen_fw` (`src/codegen_fw.xi`). Pure XIOM, no FFI, no IO,
no `Vec[Float64]`, no `Vec[StructType]`, no `Result`/`Option`.

## 1. Scope

A deterministic framework for target-agnostic code generation:

- `SymTab`: scoped `Str -> Int` bindings (parallel `Vec[Str]` names,
  `Vec[Int]` values, `Vec[Int]` scopes) with a monotone generation counter;
- `LabelAlloc`: fresh/commit/rollback label ids with the invariant
  `next == committed + pending`;
- `IrProgram`: a linear instruction sequence as parallel Vec fields
  `opcodes`, `argA`, `argB` (an opcode plus two `Int` operands), with label
  ids from `LabelAlloc`;
- `Emitter`: append-only text lines with indent depth, a configurable indent
  unit, per-line comments and exact newline-terminated rendering;
- `PeepholeRules` / `peep_apply`: first-match-wins rewrite rules over opcode
  windows of length 1 or 2, with constant operand guards, zero-or-one
  instruction replacement and operand forwarding;
- `cg_render_module`: the deterministic module text renderer built on the
  emitter.

All functions are total: out-of-range accessors clamp to documented
sentinels and no function returns `Result` or panics by contract.

## 2. Non-goals

- Target semantics: opcodes and operands are uninterpreted `Int`s; label
  uniqueness, operand liveness and ABI layout are the consumer's job.
- Register allocation, liveness analysis, dataflow, scheduling, SSA.
- Multi-pass peephole fixpoints (a single pass is applied; run it again to
  iterate) and rule DSLs/regex.
- Two-for-two window rewrites, operand-to-operand equality guards.
- Error types: every operation is defined for every input.

Complementarity: `xiom.lexer-fw` reads source text into tokens; this package
turns in-memory instructions into deterministic target text. Neither knows
the other's data model.

## 3. Sentinels and opcodes

| Constant | Value | Meaning |
|---|---|---|
| `CG_NONE` | -1 | "No value": lookup miss, out-of-range `Int` accessor. |
| `CG_WILD` | -1 | Wildcard pattern/guard slot (matches anything). |
| `CG_PAT_END` | -2 | The rule's window ends after its first instruction. |
| `CG_ERASE` | -3 | The replacement deletes the matched window. |
| `CG_FWD_A` | -4 | Replacement operand: copy argA of the window's first instruction. |
| `CG_FWD_B` | -5 | Replacement operand: copy argB of the window's first instruction. |

| Opcode | Value | Intended meaning (not enforced) |
|---|---|---|
| `CG_OP_LABEL` | 0 | Label definition; argA = label id. |
| `CG_OP_NOP` | 1 | No operation. |
| `CG_OP_MOV` | 2 | `argA := argB`. |
| `CG_OP_ADD` | 3 | `argA := argA + argB`. |
| `CG_OP_SUB` | 4 | `argA := argA - argB`. |
| `CG_OP_MUL` | 5 | `argA := argA * argB`. |
| `CG_OP_LOAD` | 6 | `argA := mem[argB]`. |
| `CG_OP_STORE` | 7 | `mem[argB] := argA`. |
| `CG_OP_JMP` | 8 | Jump to label argA. |
| `CG_OP_JZ` | 9 | Jump to label argA when argB == 0. |
| `CG_OP_CALL` | 10 | Call label argA. |
| `CG_OP_RET` | 11 | Return. |

`ir_op_name` maps the twelve opcodes to `"label"`, `"nop"`, `"mov"`,
`"add"`, `"sub"`, `"mul"`, `"load"`, `"store"`, `"jmp"`, `"jz"`, `"call"`,
`"ret"` and anything else to `"op" + decimal code` (`"op99"`, `"op-1"`).

## 4. Symbol table semantics

`SymTab` = `{ names: Vec[Str]; values: Vec[Int]; scopes: Vec[Int]; depth:
Int; generation: Int; }`. Binding `i` is the triple at index `i`; it is
visible while its recorded scope depth is `<= depth`.

1. **new.** `symtab_new` gives depth 0, generation 0, no bindings.
2. **push/pop.** `symtab_push` increments `depth` and returns it.
   `symtab_pop` removes the trailing run of bindings whose `scopes[i] ==
   depth`, decrements `depth` and returns the number removed; at depth 0 it
   is a no-op returning 0 (the outermost scope is permanent). Each removal
   pops one entry from all three Vecs, so a pop loop always makes progress.
3. **bind.** `symtab_bind` appends (name, value, depth) and increments
   `generation`; it returns the new generation. A duplicate name binds again
   and shadows the earlier binding; both stay in the table.
4. **lookup.** `symtab_lookup` scans from the newest binding backwards and
   returns the value of the first exact text match (`str_compare`), or
   `CG_NONE`. `symtab_find_depth` is the same scan returning the scope depth.
   Names are byte-exact and case-sensitive; the empty name is a legal name.
5. **generation.** Monotone: pop never decrements it, so generation numbers
   are stable handles for "the table's history".
6. **accessors.** `symtab_name(i)` -> `""`, `symtab_value(i)` -> `0`,
   `symtab_scope(i)` -> `CG_NONE` when `i` is negative or past the end.

## 5. Label allocator semantics

`LabelAlloc` = `{ next: Int; committed: Int; pending: Int; }` with the
invariant `next == committed + pending` after every call.

1. `label_fresh` returns `next`, increments `next` and `pending`. Ids are
   0-based and strictly increasing while uncommitted.
2. `label_commit` moves `pending` into `committed`, resets `pending` to 0 and
   returns the new `committed`. Committed ids are never revoked.
3. `label_rollback` resets `next` to `committed` and `pending` to 0, then
   returns `next`; the discarded ids are handed out again by later
   `label_fresh` calls.
4. Empty allocator: `label_commit` returns 0, `label_rollback` returns 0,
   `label_fresh` returns 0.
5. `label_text(id)` = `"L" + int_to_string(id)`; negative ids keep their
   sign (`"L-1"`).

## 6. Instruction model

`IrProgram` = `{ opcodes: Vec[Int]; argA: Vec[Int]; argB: Vec[Int]; }`.
Instruction `i` is `(opcodes[i], argA[i], argB[i])`; the three Vecs always
have the same length (every push mirrors into all three).

- `ir_push` appends one instruction.
- `ir_len` is the instruction count.
- `ir_opcode(p, i)` -> `CG_NONE`, `ir_a(p, i)` / `ir_b(p, i)` -> 0 out of
  range (negative or past the end).
- `ir_set` overwrites `(op, a, b)` in range and is a silent no-op out of
  range.
- `ir_equal` is structural equality over all three Vecs.

## 7. Peephole semantics

`PeepholeRules` = seven parallel Vecs (`m0`, `m1`, `guardA`, `guardB`,
`outOp`, `outA`, `outB`); rule `i` occupies index `i` in each.

`peep_rule_add(r, m0, m1, guard_a, guard_b, out_op, out_a, out_b)` registers:

- **window.** If `m1 == CG_PAT_END` the window is the single instruction at
  the scan position. Otherwise the window is the instruction at the scan
  position plus its successor, and `m1` is the successor's opcode
  requirement. `CG_WILD` in `m0`/`m1` matches any opcode.
- **guards.** `guard_a`/`guard_b` constrain argA/argB of the window's *first*
  instruction: `CG_WILD` = no constraint, otherwise the operand must equal
  the constant.
- **replacement.** `out_op == CG_ERASE` emits nothing; otherwise exactly one
  instruction `(out_op, out_a, out_b)` is emitted, where `out_a`/`out_b`
  equal to `CG_FWD_A`/`CG_FWD_B` are replaced by argA/argB of the matched
  window's first instruction (constants are emitted verbatim; other sentinel
  values are treated as constants).

`peep_apply(prog, rules)` makes **one** left-to-right pass:

1. At position `i`, try rules in registration order; the first rule whose
   window and guards match wins.
2. On a match, emit the replacement, then advance `i` by the window length
   (1 for `CG_PAT_END`, else 2).
3. Without a match, copy instruction `i` and advance by 1.
4. A two-instruction window never matches at the last instruction (no
   successor); a one-instruction window does.
5. Behaviour: every iteration consumes one or two input instructions, so the
   pass terminates structurally; the input is never mutated; the output is a
   fresh `IrProgram`; no position is revisited, so a rewrite never exposes
   an already-passed position to the same pass.

## 8. Emitter semantics

`Emitter` = `{ lines: Vec[Str]; depth: Int; unit: Str; }`.

1. `emitter_new` gives depth 0 and unit `"  "` (two spaces).
2. `emitter_indent` / `emitter_dedent` adjust depth by one; dedent clamps at
   0. `emitter_set_unit` replaces the per-level unit (any `Str`, including
   `""` and `"\t"`).
3. `emitter_line(e, text)` appends `unit * depth + text`; the stored line has
   no newline.
4. `emitter_line_comment(e, text, comment)` appends `unit * depth + text +
   " ; " + comment`.
5. `emitter_blank` appends `""` (no indent).
6. `emitter_line_at(e, i)` returns the stored line, or `""` out of range.
7. `emitter_text(e)` concatenates `line + "\n"` for every line; an empty
   emitter renders `""` (so a document only ends with a newline when it has
   lines).

## 9. Renderer

`cg_render_module(name, prog)` = emitter document with:

1. first line `"module " + name`, or `"module <anonymous>"` when `name` is
   empty;
2. every instruction at indent depth 1 (two spaces, the default unit):
   - `LABEL` -> `"<label>:"` (e.g. `L0:`);
   - `JMP`/`JZ`/`CALL` -> `"<op> <label>"` (e.g. `jz L1`);
   - `NOP`/`RET` -> `"<op>"`, operands ignored;
   - `MOV`/`ADD`/`SUB`/`MUL`/`LOAD`/`STORE` -> `"<op> <a>, <b>"`;
   - unknown opcodes -> `"op<code> <a>, <b>"`.
3. The result always ends with `'\n'`; an empty program renders the header
   line only.

Rendering is deterministic: the same `(name, prog)` always yields byte-equal
text.

## 10. API signatures

```xi
pub const CG_NONE: Int = -1;
pub const CG_WILD: Int = -1;
pub const CG_PAT_END: Int = -2;
pub const CG_ERASE: Int = -3;
pub const CG_FWD_A: Int = -4;
pub const CG_FWD_B: Int = -5;

pub const CG_OP_LABEL: Int = 0;
pub const CG_OP_NOP: Int = 1;
pub const CG_OP_MOV: Int = 2;
pub const CG_OP_ADD: Int = 3;
pub const CG_OP_SUB: Int = 4;
pub const CG_OP_MUL: Int = 5;
pub const CG_OP_LOAD: Int = 6;
pub const CG_OP_STORE: Int = 7;
pub const CG_OP_JMP: Int = 8;
pub const CG_OP_JZ: Int = 9;
pub const CG_OP_CALL: Int = 10;
pub const CG_OP_RET: Int = 11;

pub type SymTab = { names: Vec[Str]; values: Vec[Int]; scopes: Vec[Int]; depth: Int; generation: Int; }
pub type LabelAlloc = { next: Int; committed: Int; pending: Int; }
pub type IrProgram = { opcodes: Vec[Int]; argA: Vec[Int]; argB: Vec[Int]; }
pub type Emitter = { lines: Vec[Str]; depth: Int; unit: Str; }
pub type PeepholeRules = { m0: Vec[Int]; m1: Vec[Int]; guardA: Vec[Int]; guardB: Vec[Int]; outOp: Vec[Int]; outA: Vec[Int]; outB: Vec[Int]; }

pub fn symtab_new() -> SymTab
pub fn symtab_depth(t: &SymTab) -> Int
pub fn symtab_len(t: &SymTab) -> Int
pub fn symtab_generation(t: &SymTab) -> Int
pub fn symtab_push(t: &mut SymTab) -> Int
pub fn symtab_pop(t: &mut SymTab) -> Int
pub fn symtab_bind(t: &mut SymTab, name: Str, value: Int) -> Int
pub fn symtab_lookup(t: &SymTab, name: Str) -> Int
pub fn symtab_find_depth(t: &SymTab, name: Str) -> Int
pub fn symtab_name(t: &SymTab, i: Int) -> Str
pub fn symtab_value(t: &SymTab, i: Int) -> Int
pub fn symtab_scope(t: &SymTab, i: Int) -> Int

pub fn label_alloc_new() -> LabelAlloc
pub fn label_fresh(a: &mut LabelAlloc) -> Int
pub fn label_commit(a: &mut LabelAlloc) -> Int
pub fn label_rollback(a: &mut LabelAlloc) -> Int
pub fn label_next(a: &LabelAlloc) -> Int
pub fn label_committed(a: &LabelAlloc) -> Int
pub fn label_pending(a: &LabelAlloc) -> Int
pub fn label_text(id: Int) -> Str

pub fn ir_new() -> IrProgram
pub fn ir_push(p: &mut IrProgram, op: Int, a: Int, b: Int)
pub fn ir_len(p: &IrProgram) -> Int
pub fn ir_opcode(p: &IrProgram, i: Int) -> Int
pub fn ir_a(p: &IrProgram, i: Int) -> Int
pub fn ir_b(p: &IrProgram, i: Int) -> Int
pub fn ir_set(p: &mut IrProgram, i: Int, op: Int, a: Int, b: Int)
pub fn ir_equal(x: &IrProgram, y: &IrProgram) -> Bool
pub fn ir_op_name(op: Int) -> Str

pub fn emitter_new() -> Emitter
pub fn emitter_len(e: &Emitter) -> Int
pub fn emitter_depth(e: &Emitter) -> Int
pub fn emitter_set_unit(e: &mut Emitter, unit: Str)
pub fn emitter_indent(e: &mut Emitter)
pub fn emitter_dedent(e: &mut Emitter)
pub fn emitter_line(e: &mut Emitter, text: Str)
pub fn emitter_line_comment(e: &mut Emitter, text: Str, comment: Str)
pub fn emitter_blank(e: &mut Emitter)
pub fn emitter_line_at(e: &Emitter, i: Int) -> Str
pub fn emitter_text(e: &Emitter) -> Str

pub fn peep_rules_new() -> PeepholeRules
pub fn peep_rule_add(r: &mut PeepholeRules, m0: Int, m1: Int, guard_a: Int, guard_b: Int, out_op: Int, out_a: Int, out_b: Int)
pub fn peep_rule_count(r: &PeepholeRules) -> Int
pub fn peep_apply(prog: &IrProgram, rules: &PeepholeRules) -> IrProgram

pub fn cg_render_module(name: Str, prog: &IrProgram) -> Str
```

Complexity: all accessors are O(1); `symtab_lookup`/`symtab_find_depth` are
O(|table| * |name|); `symtab_pop` is O(removed); `ir_equal` and
`cg_render_module` are O(n); `emitter_text` is O(total text);
`peep_apply` is O(n * |rules|).

## 11. Test plan

`tests/test_conformance.xi` (module `codegen_tests`) runs 23 named checks via
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Fixtures: a three-binding shadowing symbol table, a
five-rule peephole set and a four-instruction program exercising erase,
rewrite-with-forwarding and copy.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | label fresh | 0-based ids, next/pending/committed counters (5.1) |
| t2 | label commit | pending promoted, counter monotone (5.2) |
| t3 | label rollback | pending discarded, ids reused, committed kept (5.3) |
| t4 | label empty edges | commit/rollback/fresh on a fresh allocator (5.4) |
| t5 | label text | `L0`/`L7`/`L42`/`L-1` (5.5) |
| t6 | symtab bind/lookup | generation 1,2; misses `CG_NONE` (4.3-4.5) |
| t7 | symtab shadowing | inner scope wins, `find_depth` exact (4.4) |
| t8 | symtab pop | removed count, visibility restored, generation kept (4.2, 4.5) |
| t9 | symtab accessors | name/value/scope by index, clamped out of range (4.6) |
| t10 | symtab same-scope shadow | latest bind wins (4.3) |
| t11 | ir build | push/len/fields, `CG_NONE`/0 defaults (6) |
| t12 | ir set | in-range overwrite, out-of-range no-op (6) |
| t13 | op names | all twelve mnemonics, `op99`, `op-1` (3) |
| t14 | emitter indent | depth accumulates, dedent, exact prefixes (8.1-8.3) |
| t15 | emitter comments | `" ; "` suffix, blank line, custom unit, exact text (8.4-8.7) |
| t16 | emitter clamps | dedent at 0, empty document, out-of-range line (8.2, 8.6-8.7) |
| t17 | peephole 1-window | erase and rewrite with forwarding in one pass (7.1-7.3) |
| t18 | peephole 2-window | pair erase, pair replace, guard rejection (7.1-7.2) |
| t19 | first-match-wins | registration order decides (7.1) |
| t20 | peephole identity | non-matching copy, empty input, determinism (7.3-7.5) |
| t21 | peephole tail | 1-window matches at end, 2-window does not (7.4) |
| t22 | render exact | labels, operands, unknown ops, empty name/program (9) |
| t23 | pipeline | labels + IR + peephole + render, end-to-end determinism (5, 7, 9) |

Determinism: the same inputs always yield byte-equal text and structurally
equal programs; no function in this package reads clocks, IO or randomness.

## 12. Compiler / stdlib notes (pinned v0.62.2)

- `Str` values read from `Vec[Str]` elements are compared with
  `str_compare` (BUG 17); `Vec[Int]`/`Vec[Str]` element reads use typed
  locals.
- No `Vec[StructType]`: `SymTab`/`PeepholeRules`/`IrProgram` are parallel
  Vec fields and every push site mirrors into all fields.
- No indexed `Vec[fn]` dispatch, no `[T,U]` callbacks, no `self` methods, no
  `Vec[Float64]`.
- Free functions only, all names prefixed (`symtab_`, `label_`, `ir_`,
  `emitter_`, `peep_`, `cg_`) so no stdlib free function is shadowed.
- `emitter_line`/`emitter_line_comment` read the indent through the
  `&mut`-taking `_indent_prefix` helper so no `&` borrow mixes with a `&mut`
  field access on the same local (advisory E001).
- Every loop makes progress: `symtab_pop` pops one binding per iteration,
  `peep_apply` advances by at least one instruction per iteration, and all
  other loops are bounded by a Vec length or an indent depth.
- `int_to_string` (from `xiom.convert`) is the only integer-to-text path; no
  byte-buffer building, so NUL-safety concerns cannot arise.
