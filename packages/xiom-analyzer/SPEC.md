# xiom.analyzer -- Specification

Status: `incubating` (implemented, harness-green on compiler 0.62.2 /
stdlib-perf1, not published).
Module: `xiom.analyzer` (`src/analyzer.xi`, 1518 lines). Manifest:
`package.xi` (name `xiom.analyzer`, version `0.1.0`). Depends on `xiom.std`
for the manifest; the library imports only `xiom.convert` (for
`int_to_string`).

## Scope

A deterministic, pure static-analysis framework over a caller-supplied
instruction list. In order of the public pipeline:

- a generic IR (`Prog`): opcode + two register operands + jump target per
  instruction (no parser, no bytecode format);
- basic-block construction from leaders (entry, jump targets, fallthrough
  boundaries);
- a CFG with typed edges (fallthrough / branch / conditional) and
  successor/predecessor queries;
- forward reachability with unreachable-block detection;
- dominator sets by iterative intersection fixpoint over reachable blocks,
  and immediate dominators;
- block-level register liveness by worklist fixpoint, with upward-exposed
  use tables, def tables and interference pairs;
- one deterministic text report.

## Non-goals

- Parsing or decoding any instruction format, SSA construction, type
  analysis, alias analysis, loop classification.
- Writing files or printing: `az_report` returns a `Str`; the caller owns all
  I/O.
- Error results: every function is total, absent values are `AZ_NONE` (`-1`)
  and out-of-range accessors clamp (documented per accessor below).

## Data model

```xi
pub type Prog = { opcodes: Vec[Int]; argA: Vec[Int]; argB: Vec[Int]; targets: Vec[Int]; }
pub type Cfg = {
  starts: Vec[Int]; ends: Vec[Int]; owner: Vec[Int];
  edgeFrom: Vec[Int]; edgeTo: Vec[Int]; edgeKind: Vec[Int];
  head: Vec[Int]; nextEdge: Vec[Int];
}
pub type Reach = { flags: Vec[Int]; order: Vec[Int]; iterations: Int; }
pub type Doms = { n: Int; has: Vec[Int]; idom: Vec[Int]; iterations: Int; boundHit: Int; }
pub type Live = {
  blocks: Int; regs: Int;
  inBits: Vec[Int]; outBits: Vec[Int]; useBits: Vec[Int]; defBits: Vec[Int];
  pairs: Vec[Int]; pairCount: Int; iterations: Int; boundHit: Int;
}
```

Mirrored `Vec[Int]` fields replace `Vec[StructType]`, which the pinned
compiler does not support. Instruction `i` is
`(opcodes[i], argA[i], argB[i], targets[i])`.

## Sentinels

`AZ_NONE = -1` means: no jump target, no edge, no predecessor, no immediate
dominator, out-of-range accessor result, and `az_prog_op` miss.
`az_prog_a`/`az_prog_b` return `0` out of range (register 0 is a valid
register, so no sentinel is possible); the Boolean predicates return `false`.
`az_cfg_succ_count`/`az_cfg_pred_count` return `0` out of range.

## Instruction model

Opcodes are Ints `0..10`. Use/def table (`az_instr_uses_a`,
`az_instr_uses_b`, `az_instr_defs_a`):

| Opcode | Value | uses A | uses B | defines A | fallthrough |
|---|---|---|---|---|---|
| `nop` | 0 | no | no | no | yes |
| `mov` | 1 | no | yes | yes | yes |
| `add` | 2 | yes | yes | yes | yes |
| `sub` | 3 | yes | yes | yes | yes |
| `mul` | 4 | yes | yes | yes | yes |
| `load` | 5 | no | yes | yes | yes |
| `store` | 6 | yes | yes | no | yes |
| `jmp` | 7 | no | no | no | no (target) |
| `jz` | 8 | yes | no | no | yes (+ target) |
| `jnz` | 9 | yes | no | no | yes (+ target) |
| `ret` | 10 | no | no | no | no |

Any other opcode is unknown: it is treated as a plain instruction (no uses,
no defs, fallthrough), named `op<value>` by `az_op_name`, and never emitted
as a branch.

## Basic blocks

Leaders are computed in a single scan:

1. instruction 0 (entry; a non-empty program always has block 0);
2. every instruction `t` with `0 <= t < n` that is the target of a
   `JMP`/`JZ`/`JNZ` instruction;
3. every instruction `i + 1 < n` where instruction `i` is a branch
   (`JMP`/`JZ`/`JNZ`) or `RET` (the fallthrough boundary; after `JMP`/`RET`
   this can start an unreachable block).

Blocks are the maximal runs between consecutive leaders: block `k` spans
`[starts[k], ends[k])` with `ends[k] = starts[k+1]` or `n`. `owner[i]` is the
block containing instruction `i`. An empty program has zero blocks.

## CFG edges

For each block `k`, let `last = ends[k] - 1`, `op = opcode(last)`,
`t = target(last)`:

- `JMP` with `0 <= t < n`: one `BRANCH` edge `k -> owner[t]`; an invalid
  target emits no edge (and, being `JMP`, no fallthrough edge either);
- `JZ`/`JNZ`: one `FALL` edge `k -> owner[last + 1]` when `last + 1 < n`,
  then, when `0 <= t < n`, one `COND` edge `k -> owner[t]`; invalid targets
  emit no conditional edge;
- `RET`: no edge;
- every other opcode: one `FALL` edge `k -> owner[last + 1]` when
  `last + 1 < n`.

Edge kinds are `AZ_EDGE_FALL = 0`, `AZ_EDGE_BRANCH = 1`, `AZ_EDGE_COND = 2`;
`az_edge_kind_name` renders `fallthrough`, `branch`, `conditional`, else
`unknown`.

Adjacency is a singly linked list per block (`head`, `nextEdge`) built by
head insertion. `az_cfg_succ_edge(c, b, k)` therefore enumerates successors
newest-first: for a conditional that is the taken (`COND`) edge first, then
the `FALL` edge; other blocks have a single edge. `az_cfg_pred_count` /
`az_cfg_pred_at` scan edges by id, so predecessor order is ascending edge id.

## Reachability

`az_reach_build` runs an explicit LIFO DFS from block 0 (no work for an empty
program). A block is flagged and pushed at most once; pushes overwrite the
stale slot at the logical top when the backing Vec is longer than the live
stack, so the top is always `stack[sp - 1]`. `order` records the pop order
(DFS pre-order); `iterations` equals the number of pops (== number of
reachable blocks). Unreachable blocks are those with `flags[b] == 0`, exposed
ascending by `az_reach_unreachable_count` / `az_reach_unreachable_at`.

Progress: each iteration pops exactly one block; a block is pushed only when
its flag changes 0 -> 1; therefore at most one push and one pop per block.

## Dominators

Computed over all blocks, using reachability:

- `dom(0) = {0}`.
- For a reachable non-entry block `b`, the initial set is all reachable
  blocks (the universe); for an unreachable block `b`, `dom(b) = {b}` and it
  is never updated.
- Fixpoint, passes `iter = 0..n-1` over blocks `1..n-1` in ascending order,
  updating in place:
  `dom(b) := {b} union (intersection of dom(p) over reachable predecessors p)`.
  Reachable non-entry blocks always have at least one predecessor (the
  intersection is otherwise the self-only set as a defensive fallback).
- `has[b * n + x]` is 1 iff `x` dominates `b`; `az_dom_size` is the row
  cardinality; out-of-range reads return `false` / `0`.

Fixpoint bound: each pass either changes at least one set (each changed set
strictly shrinks) or performs no change and ends the loop. At most `n` passes
are executed (`while iter < n`); a chain of `n` blocks converges in `n - 1`
passes, so the bound is exact for the worst case. If the `n`-th pass still
changed something, `boundHit` is set to 1 (defensive; not reachable for
well-formed CFGs because the longest dependency chain among `n` blocks is
`n - 1` updates).

Immediate dominator: `az_dom_idom(b)` is the dominator of `b` other than `b`
with the largest dom-set cardinality (dominators of a block are totally
ordered by inclusion, so the deepest one is unique). It is `AZ_NONE` for the
entry, for unreachable blocks, and out of range.

## Liveness

Register count: `max(register mentioned by the use/def table) + 1`, or 0 when
no instruction mentions a register. Rows are flattened at `b * regs`.

Block use/def: scan each block in instruction order. A use joins `useBits`
only when that register is not defined earlier in the same block
(upward-exposed use); every def joins `defBits`. The tables cover all blocks,
reachable or not.

Live sets are computed only for reachable blocks; unreachable rows remain
empty. Worklist equations:

```
live_out(b) = union of live_in(s) over successors s
live_in(b)  = use(b) union (live_out(b) minus def(b))
```

The worklist starts with every reachable block (in ascending id order) and is
a FIFO over an append-only Vec with a head cursor; a `queued` flag
deduplicates pushes. When a block's sets change, its predecessors are
re-queued. `iterations` counts worklist pops; the initial pass over every
reachable block counts as one pop each even when nothing changes.

Fixpoint bound: each set only grows; each iteration pops one entry and only a
changed iteration can push entries, and a changed iteration adds at least one
bit to one of the 2 * blocks * regs live bits. Therefore pushes <= 2 * cells
and iterations <= blocks + 2 * cells, where `cells = blocks * regs`. The
explicit cap is `2 * cells + blocks + 2`; if it is ever reached, `boundHit` is
set to 1 and the loop stops (defensive; not observed on the suite, including
the back-edge fixture).

Interference: registers `a < b` interfere when both are live-out at the same
block. Pairs are collected block-ascending then `a`-ascending, deduplicated
by linear scan, and flattened into `pairs` as consecutive `(a, b)`.
`az_live_pair_count` is the number of pairs; `az_live_pair_a_at` /
`az_live_pair_b_at` return `AZ_NONE` out of range.

## Report format

`az_report(&p)` runs the whole pipeline and returns LF-terminated lines in
this fixed order (always ending with `\n`):

```
xiom.analyzer report
instructions: <n>
blocks: <nb>
edges: <ne>
block <k> [<start>,<end>) succ: <dest>/<kind> <dest>/<kind> ... | (none)
edge <e>: <from>-><to> <kind>
reachable: <ids ascending, space-joined | (none)>
unreachable: <ids ascending, space-joined | (none)>
dom <k>: {<ids ascending, comma-joined>}
idom <k>: <id | -1>
dom iterations: <passes>[ (bound hit)]
live regs: <regs>
live-in <k>: {<ids ascending, comma-joined>}
live-out <k>: {<ids ascending, comma-joined>}
live iterations: <pops>[ (bound hit)]
interference: (<a>,<b>) ... | (none)
```

Per-block and per-edge sections are skipped when there are no blocks/edges
(empty program), so the empty report has exactly the header, counts,
reachable/unreachable, both iteration lines and interference. Determinism:
no maps, no clock, no allocation-order dependence; `az_report(&p)` twice
returns byte-identical strings.

## Accessor contract

All accessors are total and range-safe: scalar queries return `AZ_NONE`
(`az_cfg_block_start/end/of_instr`, `az_cfg_edge_*`, `az_cfg_succ_edge`,
`az_cfg_succ`, `az_cfg_pred_at`, `az_reach_order_at`,
`az_reach_unreachable_at`, `az_dom_idom`, `az_live_pair_*`), `0` for counts
(`az_cfg_succ_count`/`az_cfg_pred_count`), or `false` for predicates
(`az_dom_has`, `az_reach_is_reachable`, `az_live_in/out/use/def`,
`az_dom_bound_hit`, `az_live_bound_hit`).

## Determinism and purity

No FFI, no file or console I/O in the library, no clock, no randomness, no
global state. Every list is a mirrored `Vec[Int]`; every Vec element read is
bound to a typed local. `Str` equality is never used in the library (the
report is built only by concatenation), so the `Str ==` pointer-comparison
trap does not apply.

## Conformance

`tests/test_conformance.xi` -- 23 checks. Fixtures are built in-test
(diamond, diamond + dead tail, jump chain, wide split, back edge, single
RET, empty program). Coverage:

| Checks | Area |
|---|---|
| t1-t4 | program model, classification, use/def table, names |
| t5-t6 | block leaders, ranges, owner map, dead tail, single instruction |
| t7-t8 | edge list/kinds, successor order, predecessors |
| t9-t10 | reachability, DFS order, unreachable detection, empty program |
| t11-t13 | dominators: chain, diamond, unreachable singleton, loop header, idom, pass count |
| t14-t16 | liveness: wide split rows, use/def kills, back-edge fixpoint, cap |
| t17-t18 | interference pairs: order, dedup, loop interval, diamond pair |
| t19-t21 | byte-exact reports: empty, single RET, diamond |
| t22-t23 | report determinism/dead markers and the sentinel contract |

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.analyzer
```

Expected: 23 `[PASS]` lines, `xiom.analyzer: all tests passed`,
`port: PASS (passed=23 failed=0 ...)`, exit 0.
