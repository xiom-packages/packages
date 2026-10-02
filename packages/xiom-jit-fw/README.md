# xiom.jit-fw

> **Status:** `incubating` -- conformance-tested (25/25); published at `v0.1.0` on the XIOM registry.
> **Scope:** a deterministic JIT-framework model: source hashing and
> artifact keys, symbolic IR lowered to an instruction stream, a bounded
> dispatch interpreter with call frames, a bounded LRU artifact cache,
> closure/trampoline adapters and a per-site monitor with a deterministic
> tiering policy.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses
> `xiom.string.byte_at` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.jit-fw` packages the bookkeeping and execution-model machinery of a
just-in-time compiler framework, pure XIOM with no FFI, no IO and no native
code generation. **Native machine-code emission is explicitly out of scope:**
"compiled code" is modeled as an instruction table (`JitCode`) that the
dispatch interpreter consumes, so the whole pipeline is integer-only and
byte-for-byte deterministic. See `SPEC.md` for the documented subset and
the full non-goals list.

The framework models six pieces:

1. **Engine pipeline** -- `jit_source_hash` (FNV-1a 32-bit over the source
   bytes), `jit_artifact_key`/`jit_key_for_source` (source hash + compile
   flags -> cache key), `JitIr` (symbolic opcodes/label operands),
   `jit_lower` (labels resolved to program counters, label pseudo-ops become
   NOPs) and `jit_run` (bounded dispatch interpreter).
2. **Exec model** -- `JitMachine` (operand stack, flat memory, call-frame
   stack of return pcs, pc, step count, status) plus `JitCode` as the
   loaded instruction table. Call frames are pushed by `call` and popped by
   `ret`; `ret` on an empty frame stack halts.
3. **Artifact cache** -- `JitCache` maps an artifact key to a caller-owned
   artifact handle with bounded LRU replacement, capacity clamping and
   hit/miss/insert/evict statistics.
4. **Closures and trampolines** -- a closure adapter handle packs
   `(entry pc, env id)` into 32 bits; `JitTrampolines` resolves a bound
   closure handle to a loaded code-table handle (rebinding keeps the slot).
5. **Monitor** -- `JitMonitor` records per-site execution counts, tiers and
   deopt counts, creating a site at `baseline` on first hit.
6. **Tiering policy** -- `JitPolicy` holds `hot`/`rehot`/`max_attempts`
   thresholds; `jit_tier_decide` is a pure deterministic decision and
   `jit_tier_apply` performs the `baseline -> optimized` and
   `deopt -> optimized` transitions.

Everything is total: no `Result`/`Option` and no panics; out-of-range
accessors clamp to documented sentinels (`JIT_NONE`, `0`, `""`) and the
interpreter fails closed with a `JIT_EXIT_*` status.

## API

Constants:

| Item | Description |
|---|---|
| `JIT_NONE` | `-1`; absent/unbound/out-of-range sentinel. |
| `JIT_EXIT_RUNNING` / `HALT` / `STEP_LIMIT` / `BAD_OP` / `BAD_PC` | Machine statuses (`0`..`4`). |
| `JIT_TIER_BASELINE` / `OPTIMIZED` / `DEOPT` | Monitor tiers (`0`..`2`). |
| `JIT_ACTION_STAY` / `COMPILE` / `RECOMPILE` | Deterministic tiering decisions (`0`..`2`). |
| `JIT_OP_LABEL` .. `JIT_OP_NEG` | Opcodes `0`..`15`: `label`, `nop`, `push`, `add`, `sub`, `mul`, `load`, `store`, `jmp`, `jz`, `call`, `ret`, `halt`, `dup`, `swap`, `neg`. |
| `JitIr`, `JitCode`, `JitMachine`, `JitCache`, `JitTrampolines`, `JitMonitor`, `JitPolicy` | The seven value types (all parallel-Vec records). |

Engine and source identity:

| Function | Returns | Description |
|---|---|---|
| `jit_source_hash(src)` | `Int` | FNV-1a 32-bit of the UTF-8 bytes; `""` hashes to `2166136261`. |
| `jit_artifact_key(hash, flags)` | `Int` | Deterministic 32-bit mix of a source hash and a flags word. |
| `jit_key_for_source(src, flags)` | `Int` | `jit_artifact_key(jit_source_hash(src), flags)`. |
| `jit_ir_new()` / `jit_ir_push(ir, op, a, b)` / `jit_ir_len` / `jit_ir_op` / `jit_ir_a` / `jit_ir_b` | IR builder and clamped accessors. |
| `jit_lower(ir)` | `JitCode` | Resolve label ids to pcs; label pseudo-ops become NOPs; unbound labels become `JIT_NONE`. |
| `jit_code_new` / `jit_code_push` / `jit_code_len` / `jit_code_op` / `jit_code_a` / `jit_code_b` / `jit_code_equal` | Instruction-stream builder, accessors and structural equality. |
| `jit_op_name(op)` | `Str` | Mnemonic, or `"op<code>"`. |
| `jit_disasm(code)` | `Str` | Deterministic `<pc>: <mnemonic>` text, one line per instruction. |

Exec model:

| Function | Returns | Description |
|---|---|---|
| `jit_machine_new()` | `JitMachine` | Empty stack/memory/frames, pc 0, status `RUNNING`. |
| `jit_run(code, steps_max)` | `JitMachine` | Bounded dispatch; `HALT`/empty-frame `RET` stop cleanly, the step cap, bad opcodes and out-of-range pcs fail closed. |
| `jit_machine_pc` / `steps` / `status` / `stack_depth` / `top` / `frame_depth` / `mem_len` / `mem_at` | `Int` | Final-state accessors; `top`/`mem_at` clamp to `0`. |

Cache, closures and trampolines:

| Function | Returns | Description |
|---|---|---|
| `jit_cache_new(cap)` | `JitCache` | Capacity clamped to `>= 1`. |
| `jit_cache_get(c, key)` / `jit_cache_put(c, key, handle)` | `Int` | LRU lookup (hit/miss stats) and insert/replace (returns the evicted handle or `JIT_NONE`). |
| `jit_cache_peek(c, key)` | `Int` | Lookup without touching statistics. |
| `jit_cache_len` / `cap` / `hits` / `misses` / `inserts` / `evicts` | `Int` | Statistics accessors. |
| `jit_closure_make(entry, env)` / `jit_closure_entry` / `jit_closure_env` | `Int` | Pack/unpack a 16+16-bit closure adapter handle. |
| `jit_tramp_new()` / `jit_tramp_bind(t, closure, code)` / `jit_tramp_count` / `jit_tramp_code` / `jit_tramp_entry` / `jit_tramp_env` | | Bind/rebind a closure to a code handle; unbound lookups return `JIT_NONE`. |

Monitor and policy:

| Function | Returns | Description |
|---|---|---|
| `jit_mon_new()` | `JitMonitor` | No sites. |
| `jit_mon_hit(m, site)` | `Int` | Count an execution, creating the site at `baseline`. |
| `jit_mon_count` / `tier` / `deopts` / `sites` | `Int` | Accessors (`count`/`deopts` -> 0, `tier` -> `JIT_NONE` for unknown sites). |
| `jit_mon_set_tier(m, site, tier)` | `Int` | Force a tier; returns the previous tier. |
| `jit_mon_deopt(m, site)` | `Int` | tier `DEOPT`, counter reset, deopt count incremented. |
| `jit_policy_new(hot, rehot, max_attempts)` + accessors | `JitPolicy` | Clamped thresholds. |
| `jit_tier_decide(m, site, p)` / `jit_tier_apply(m, site, p)` | `Int` | Deterministic decision and transition. |

## Determinism and bounds

- The same inputs always produce the same output: no clocks, no IO, no
  randomness, no address-dependent behavior.
- `jit_run` always terminates: every iteration either dispatches one
  instruction or stops, and the dispatch count is capped by `steps_max`.
- All scans (`lower`, cache, trampolines, monitor) advance one element per
  iteration; parallel Vecs are pushed together and never drift.
- The LRU victim is the entry with the smallest access stamp; ties break to
  the lowest slot index.

## Build and test

```powershell
& .\scripts\port.ps1 -Package xiom-jit-fw -TimeoutSec 60
```

Expected final line: `port: PASS (program_exit=0)`. The suite
(`tests/test_conformance.xi`, 25 checks) is self-contained and writes no
files.

## License

MIT OR Apache-2.0. See `SPEC.md` for semantics, API signatures, the test
plan and the non-goals.
