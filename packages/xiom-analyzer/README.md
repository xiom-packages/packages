# xiom.analyzer

> **Status:** `incubating` -- conformance-tested (23/23); not yet published on the XIOM registry.
> **Scope:** deterministic static-analysis framework over a caller-supplied
> instruction list: basic blocks, CFG edges, forward reachability, dominator
> sets with immediate dominators, register liveness with interference pairs,
> and a text report. Generic IR; there is no parser.
> **Deps:** `xiom.std` (the library imports `xiom.convert`; the tests add
> `xiom.test`, `xiom.io` and `xiom.string`).

## What it is

`xiom.analyzer` is a pure-XIOM framework, not a compiler front end. The
caller builds a `Prog` (opcode + two operands + jump target per instruction)
and asks the module for the classic post-parse analyses. Everything is
deterministic: same input, same output, byte for byte. There is no FFI, no
file I/O, no clock access, no global state.

Every function is total: results are values, absent results are sentinels
(`AZ_NONE`), and out-of-range accessors clamp instead of trapping. The caller
owns all I/O.

## Instruction model

Instruction `i` is `(opcodes[i], argA[i], argB[i], targets[i])`. `targets[i]`
is a jump target instruction index for `JMP`/`JZ`/`JNZ` and `AZ_NONE`
otherwise.

| Opcode | Constant | Uses | Defines | Successors |
|---|---|---|---|---|
| `nop` | `AZ_OP_NOP` | - | - | fallthrough |
| `mov` | `AZ_OP_MOV` | B | A | fallthrough |
| `add` | `AZ_OP_ADD` | A, B | A | fallthrough |
| `sub` | `AZ_OP_SUB` | A, B | A | fallthrough |
| `mul` | `AZ_OP_MUL` | A, B | A | fallthrough |
| `load` | `AZ_OP_LOAD` | B | A | fallthrough |
| `store` | `AZ_OP_STORE` | A, B | - | fallthrough |
| `jmp` | `AZ_OP_JMP` | - | - | target |
| `jz` | `AZ_OP_JZ` | A | - | target, fallthrough |
| `jnz` | `AZ_OP_JNZ` | A | - | target, fallthrough |
| `ret` | `AZ_OP_RET` | - | - | none |

## API (summary)

| Group | Functions |
|---|---|
| Program | `az_prog_new`, `az_prog_push`, `az_prog_len`, `az_prog_op`, `az_prog_a`, `az_prog_b`, `az_prog_target` |
| Classification | `az_is_branch`, `az_is_cond`, `az_is_terminator`, `az_instr_uses_a`, `az_instr_uses_b`, `az_instr_defs_a`, `az_op_name`, `az_edge_kind_name` |
| Blocks / CFG | `az_cfg_build`, `az_cfg_block_count`, `az_cfg_block_start`, `az_cfg_block_end`, `az_cfg_block_of_instr`, `az_cfg_edge_count`, `az_cfg_edge_from`, `az_cfg_edge_to`, `az_cfg_edge_kind`, `az_cfg_succ_count`, `az_cfg_succ`, `az_cfg_succ_edge`, `az_cfg_pred_count`, `az_cfg_pred_at` |
| Reachability | `az_reach_build`, `az_reach_block_count`, `az_reach_is_reachable`, `az_reach_count`, `az_reach_order_count`, `az_reach_order_at`, `az_reach_iterations`, `az_reach_unreachable_count`, `az_reach_unreachable_at` |
| Dominators | `az_dom_build`, `az_dom_block_count`, `az_dom_has`, `az_dom_size`, `az_dom_idom`, `az_dom_iterations`, `az_dom_bound_hit` |
| Liveness | `az_live_build`, `az_live_block_count`, `az_live_reg_count`, `az_live_in`, `az_live_out`, `az_live_use`, `az_live_def`, `az_live_in_count`, `az_live_out_count`, `az_live_pair_count`, `az_live_pair_a_at`, `az_live_pair_b_at`, `az_live_iterations`, `az_live_bound_hit` |
| Report | `az_report` |

The pipeline is `az_prog_new`/`az_prog_push` -> `az_cfg_build` ->
`az_reach_build` -> `az_dom_build` + `az_live_build` -> `az_report`.
`az_dom_build` and `az_live_build` consume the reachability result, so
unreachable blocks get singleton dominator sets and empty live sets.

## Report

`az_report(&prog)` renders a fixed line order: counts, per-block ranges and
successors (`<dest>/<kind>`), the edge list, reachable/unreachable ids,
dominator sets, immediate dominators, fixpoint pass counts, liveness rows and
the interference pairs. Example for a five-instruction diamond:

```
xiom.analyzer report
instructions: 5
blocks: 4
edges: 4
block 0 [0,1) succ: 2/conditional 1/fallthrough
...
interference: (2,4)
```

`SPEC.md` states the format byte-exactly; `tests/test_conformance.xi` checks
three reports against exact strings.

## Tests

`tests/test_conformance.xi` -- 23 named checks with in-test fixtures (no
files, no I/O): program model, classification, use/def tables, names, diamond
and dead-tail block construction, CFG edges/adjacency/predecessors,
reachability and unreachable detection, dominators and immediate dominators
on a chain/diamond/loop, liveness (wide split, back edge, use/def kills,
interference), exact reports, and the sentinel contract. Run from the
repository root:

```
.\scripts\port.ps1 -Package xiom.analyzer
```

Expected: 23 `[PASS]` lines, then `xiom.analyzer: all tests passed`, exit 0.

## Limitations

- No parser: the IR is caller-supplied; operand meaning is fixed by the
  use/def table above (registers are plain non-negative Ints).
- Dominators are only meaningful for reachable blocks; unreachable blocks get
  `{b}` and `idom = AZ_NONE` by construction.
- Liveness is computed for reachable blocks only; use/def tables cover all
  blocks. Interference uses live-out sets only.
- Complexity is quadratic/cubic in block count (`Doms` stores an n x n
  matrix); intended for per-function analysis scale.
- No loop-depth/reducibility classification, no SSA construction, no
  iterative dataflow beyond liveness.
- Not thread-safe (no global state; every call is self-contained).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
