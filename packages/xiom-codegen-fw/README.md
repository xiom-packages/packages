# xiom.codegen-fw

> **Status:** `incubating` -- conformance-tested (23/23); not yet published on the XIOM registry.
> **Scope:** a deterministic code-generation framework: scoped symbol tables,
> a rollback-safe label allocator, an opcode/operand IR model, an indenting
> text emitter, a first-match-wins peephole window rewriter and a module text
> renderer.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.codegen-fw` packages the reusable machinery of a target-agnostic code
generator, pure XIOM with no FFI and no IO. It deliberately stops before any
real target: you get the bookkeeping and the text plumbing, and you define
what the opcodes and operands mean for your backend.

Five pieces, all in `xiom.codegen_fw`:

1. **`SymTab`** -- scoped `Str -> Int` bindings as three parallel Vecs
   (`names`, `values`, `scopes`) plus a monotone `generation` counter. Push a
   scope, bind names, look up the newest binding, pop the scope: popped
   bindings disappear, committed generation numbers never do.
2. **`LabelAlloc`** -- fresh/commit/rollback label ids. Emit a speculative
   block, then either commit its labels or roll the counter back so the same
   ids are handed out again. The invariant `next == committed + pending`
   holds after every call.
3. **`IrProgram`** -- instructions as three parallel Vecs `opcodes`, `argA`,
   `argB` (no `Vec[StructType]` exists in XIOM). Labels are label ids from
   `LabelAlloc` and jump/call operands reference them.
4. **`Emitter`** -- append-only text lines with an indent depth, a
   configurable indent unit (default two spaces), per-line ` ; comment`
   suffixes, blank lines and exact newline-terminated rendering.
5. **Peephole + renderer** -- `PeepholeRules` registers first-match-wins
   rules over windows of one or two instructions (constant operand guards,
   replacement of zero or one instruction, operand forwarding), and
   `cg_render_module` renders a program as deterministic module text.

Everything is total: no `Result`, no error cases; out-of-range accessors
clamp to documented sentinels (`CG_NONE`, `""`, `0`). See `SPEC.md` for the
full semantics, API signatures and test plan.

## API

Values and constants:

| Item | Description |
|---|---|
| `CG_NONE` | `-1`; lookup miss / out-of-range sentinel. |
| `CG_WILD` | `-1`; wildcard pattern/guard slot. |
| `CG_PAT_END` | `-2`; pattern window ends after the first instruction. |
| `CG_ERASE` | `-3`; replacement deletes the matched window. |
| `CG_FWD_A` / `CG_FWD_B` | `-4` / `-5`; replacement operand copies argA/argB of the window's first instruction. |
| `CG_OP_LABEL` .. `CG_OP_RET` | Opcode constants: `label`, `nop`, `mov`, `add`, `sub`, `mul`, `load`, `store`, `jmp`, `jz`, `call`, `ret`. |
| `SymTab`, `LabelAlloc`, `IrProgram`, `Emitter`, `PeepholeRules` | The five value types (all parallel-Vec records). |

Symbol table:

| Function | Returns | Description |
|---|---|---|
| `symtab_new()` | `SymTab` | Empty table at depth 0, generation 0. |
| `symtab_depth(t)` / `symtab_len(t)` / `symtab_generation(t)` | `Int` | Current scope depth / live bindings / monotone bind counter. |
| `symtab_push(t)` / `symtab_pop(t)` | `Int` | Enter a scope (returns depth) / leave it (returns removed bindings; no-op at depth 0). |
| `symtab_bind(t, name, value)` | `Int` | Bind at the current depth; returns the new generation. Duplicates shadow. |
| `symtab_lookup(t, name)` | `Int` | Newest binding's value, or `CG_NONE`. |
| `symtab_find_depth(t, name)` | `Int` | Scope depth of the newest binding, or `CG_NONE`. |
| `symtab_name(t, i)` / `symtab_value(t, i)` / `symtab_scope(t, i)` | `Str` / `Int` / `Int` | Bind-order accessors (`""` / `0` / `CG_NONE` out of range). |

Labels, instructions, emitter, peephole, renderer:

| Function | Returns | Description |
|---|---|---|
| `label_alloc_new()` | `LabelAlloc` | No ids handed out, none committed. |
| `label_fresh(a)` | `Int` | Hand out the next pending id. |
| `label_commit(a)` / `label_rollback(a)` | `Int` | Commit pending ids / discard and rewind them (returns the next id). |
| `label_next(a)` / `label_committed(a)` / `label_pending(a)` | `Int` | Allocator state. |
| `label_text(id)` | `Str` | `"L" + id` (`"L0"`, `"L-1"`). |
| `ir_new()` | `IrProgram` | Empty sequence. |
| `ir_push(p, op, a, b)` | nothing | Append an instruction. |
| `ir_len(p)` | `Int` | Instruction count. |
| `ir_opcode(p, i)` / `ir_a(p, i)` / `ir_b(p, i)` | `Int` | Field of instruction `i` (`CG_NONE` / `0` / `0` out of range). |
| `ir_set(p, i, op, a, b)` | nothing | Overwrite; out-of-range is a no-op. |
| `ir_equal(x, y)` | `Bool` | Structural equality over all three Vecs. |
| `ir_op_name(op)` | `Str` | Lowercase mnemonic, or `"op<code>"` for unknown opcodes. |
| `emitter_new()` | `Emitter` | No lines, depth 0, unit `"  "`. |
| `emitter_indent(e)` / `emitter_dedent(e)` | nothing | Depth +-1 (dedent clamps at 0). |
| `emitter_set_unit(e, unit)` | nothing | Replace the per-level indent unit. |
| `emitter_line(e, text)` / `emitter_line_comment(e, text, comment)` / `emitter_blank(e)` | nothing | Append a line (indented; comment form adds `" ; " + comment`; blank adds ""). |
| `emitter_line_at(e, i)` / `emitter_text(e)` | `Str` | Stored line / whole document, every line followed by `'\n'` (`""` when empty). |
| `peep_rules_new()` | `PeepholeRules` | Empty rule set. |
| `peep_rule_add(r, m0, m1, guard_a, guard_b, out_op, out_a, out_b)` | nothing | Register a rule (see `SPEC.md` section 6). |
| `peep_rule_count(r)` | `Int` | Number of rules. |
| `peep_apply(prog, rules)` | `IrProgram` | One left-to-right pass, first-match-wins. |
| `cg_render_module(name, prog)` | `Str` | Deterministic module text ending in a newline. |

## Usage

```xi
use xiom.codegen_fw;

fn main() -> Int {
  var labels = label_alloc_new();
  let loop = label_fresh(&mut labels);
  let done = label_fresh(&mut labels);
  let committed = label_commit(&mut labels);      // 2

  var prog = ir_new();
  ir_push(&mut prog, CG_OP_LABEL, loop, 0);
  ir_push(&mut prog, CG_OP_ADD, 1, 0);            // identity add
  ir_push(&mut prog, CG_OP_JZ, done, 0);
  ir_push(&mut prog, CG_OP_JMP, loop, 0);
  ir_push(&mut prog, CG_OP_LABEL, done, 0);
  ir_push(&mut prog, CG_OP_RET, 0, 0);

  var rules = peep_rules_new();
  peep_rule_add(&mut rules, CG_OP_ADD, CG_PAT_END, CG_WILD, 0, CG_ERASE, 0, 0);
  let out = peep_apply(&prog, &rules);
  io.print(cg_render_module("demo", &out));
  // module demo
  //   L0:
  //   jz L1
  //   jmp L0
  //   L1:
  //   ret
  return 0;
}
```

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom.codegen-fw -TimeoutSec 60
```

Expected tail: 23 `[PASS]` lines, `xiom.codegen-fw: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No target semantics.** Opcodes and operands are uninterpreted `Int`s; the
  framework never checks that a `mov` source is defined or that a label id is
  defined exactly once. Consumers keep their own invariants.
- **Single-pass peephole.** `peep_apply` makes exactly one left-to-right pass
  (no fixpoint iteration), so a rewrite can expose a match the pass has
  already skipped; run it again to iterate, or order rules accordingly.
- **One replacement instruction.** A rule replaces its window (one or two
  instructions) with zero or one instruction; two-for-two rewrites need two
  rules or a different pass.
- **Constant guards only.** Guards compare operand A/B of the window's first
  instruction against constants (or `CG_WILD`); operand-to-operand equality
  (e.g. `jmp L; L:`) is not expressible.
- **No register allocation, no liveness, no dataflow.** The symbol table
  maps names to single `Int` values; it is not a register allocator.
- **Rendering is one style.** `cg_render_module` emits one fixed text format;
  there are no renderer options beyond the emitter's indent unit.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
