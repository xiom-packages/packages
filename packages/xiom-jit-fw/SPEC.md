# xiom.jit-fw -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.jit_fw` (`src/jit_fw.xi`). Pure XIOM, no FFI, no IO, no
`Vec[Float64]`, no `Vec[StructType]`, no `Result`/`Option`.

## 1. Scope (documented subset)

A deterministic model of a JIT compiler framework. "Compiled code" is an
instruction table plus call frames -- **native machine-code generation,
assembly emission, ABI layout and executable memory mapping are out of
scope** (section 2), so every operation is an `Int` computation:

- **Engine pipeline.** `jit_source_hash` gives a source text a stable
  32-bit FNV-1a identity; `jit_artifact_key` / `jit_key_for_source` mix it
  with a compile-flags word into a cache key; `JitIr` is a symbolic
  instruction sequence with label operands; `jit_lower` resolves labels to
  instruction indices (program counters); `jit_run` dispatches the lowered
  `JitCode` on a stack machine.
- **Exec model.** `JitCode` is the loaded instruction table; `JitMachine`
  holds the operand stack, flat memory, call-frame stack (return pcs), pc,
  step count and exit status.
- **Artifact cache.** `JitCache` maps keys to caller-owned artifact handles
  with bounded LRU replacement and hit/miss/insert/evict statistics.
- **Closures and trampolines.** A closure adapter handle packs
  `(entry pc, env id)`; `JitTrampolines` resolves bound handles to
  code-table handles.
- **Monitor and tiering.** `JitMonitor` keeps per-site counts, tiers
  (`baseline` / `optimized` / `deopt`) and deopt counts; `JitPolicy` and
  `jit_tier_decide` / `jit_tier_apply` are a deterministic thresholding
  policy.

All functions are total: out-of-range accessors clamp to documented
sentinels and the interpreter fails closed with a `JIT_EXIT_*` status. No
function returns `Result` or `Option` and none can panic by contract.

## 2. Non-goals

- **Native code generation is out of scope.** No machine-code emission, no
  executable memory, no instruction encoding, no registers/calling
  conventions, no relocation. "Loading generated code" is modeled as
  placing a `JitCode` instruction table behind a trampoline binding.
- Source-language parsing/frontends: the IR is the framework's source;
  building `JitIr` (by a hypothetical frontend) is the consumer's job.
- Real optimization passes: the `optimized` tier is bookkeeping; the
  interpreter's semantics do not change with the tier.
- Real deoptimization (frame reconstruction, on-stack replacement) and
  speculative guards: `jit_mon_deopt` only resets counters and the tier.
- Diagnostics/errors as values: misses and out-of-range cases use
  sentinels, and the interpreter reports a status instead of an error
  object.
- Thread safety, locks and concurrent compilation: the model is
  single-threaded and deterministic.

## 3. Constants

Sentinels and statuses:

| Constant | Value | Meaning |
|---|---|---|
| `JIT_NONE` | -1 | Absent/unbound/out-of-range sentinel. |
| `JIT_EXIT_RUNNING` | 0 | Machine not yet stepped (`jit_machine_new`). |
| `JIT_EXIT_HALT` | 1 | `halt`, or `ret` on an empty frame stack. |
| `JIT_EXIT_STEP_LIMIT` | 2 | Step cap reached before halting. |
| `JIT_EXIT_BAD_OP` | 3 | Unknown opcode. |
| `JIT_EXIT_BAD_PC` | 4 | pc left `[0, code_len)` (bad jump/call target or empty code). |
| `JIT_TIER_BASELINE` | 0 | Never-executed/baseline tier. |
| `JIT_TIER_OPTIMIZED` | 1 | Bookkeeping-optimized tier. |
| `JIT_TIER_DEOPT` | 2 | Deoptimized; counter was reset. |
| `JIT_ACTION_STAY` | 0 | No tier transition. |
| `JIT_ACTION_COMPILE` | 1 | baseline -> optimized. |
| `JIT_ACTION_RECOMPILE` | 2 | deopt -> optimized. |

Opcodes (one space for IR and the instruction stream):

| Opcode | Value | Stack effect / meaning |
|---|---|---|
| `JIT_OP_LABEL` | 0 | Pseudo-op (IR only); `argA` = label id. Lowering rewrites it to `nop` at its own pc. |
| `JIT_OP_NOP` | 1 | Nothing. |
| `JIT_OP_PUSH` | 2 | push `argA`. |
| `JIT_OP_ADD` / `SUB` / `MUL` | 3/4/5 | pop b, pop a, push `a+b`, `a-b`, `a*b`. |
| `JIT_OP_LOAD` | 6 | pop addr, push `mem[addr]` (0 out of range). |
| `JIT_OP_STORE` | 7 | pop addr, pop value; `addr == len(mem)` appends one word, `addr < len(mem)` overwrites, anything else is ignored. |
| `JIT_OP_JMP` | 8 | pc = `argA`. |
| `JIT_OP_JZ` | 9 | pop cond; jump to `argA` when cond == 0, else pc + 1. |
| `JIT_OP_CALL` | 10 | push `pc + 1` on the frame stack, then pc = `argA`. |
| `JIT_OP_RET` | 11 | pop a return pc; halt when the frame stack is empty. |
| `JIT_OP_HALT` | 12 | stop with `JIT_EXIT_HALT`. |
| `JIT_OP_DUP` | 13 | push the stack top again (0 when empty). |
| `JIT_OP_SWAP` | 14 | swap the top two entries (no-op with fewer than two). |
| `JIT_OP_NEG` | 15 | pop v, push `0 - v`. |

Stack underflow is not an error: a missing operand defaults to `0`.

## 4. Source identity and artifact keys

1. `jit_source_hash(src)` is FNV-1a 32-bit over the UTF-8 bytes of `src`:
   `h = 2166136261`; for every byte `b`: `h = (h ^ b) * 16777619 mod 2^32`.
   Each byte is read through `string.byte_at` and widened with
   `(x as Int) & 0xFF`. `""` hashes to `2166136261`; `"a"` to `3826002220`;
   `"ab"` to `1294271946`; `"module demo"` to `2665301212`.
2. `jit_artifact_key(hash, flags)` is a deterministic 32-bit mix:
   `h = hash & 0xFFFFFFFF`; `h = h ^ ((flags << 1) & 0xFFFFFFFF)`;
   `h = (h * 16777619) & 0xFFFFFFFF`; `h = (h ^ (h >> 13)) & 0xFFFFFFFF`.
   All intermediate products stay below 2^57, so no overflow is relied on.
3. `jit_key_for_source(src, flags)` composes the two.

## 5. IR and lowering

`JitIr` = `{ ops: Vec[Int]; argA: Vec[Int]; argB: Vec[Int]; }`. Instruction
`i` is `(ops[i], argA[i], argB[i])`; the three Vecs always have the same
length (every push mirrors into all three).

1. `jit_ir_push` appends one instruction; `jit_ir_len` is the count.
2. `jit_ir_op(i)` -> `JIT_NONE`, `jit_ir_a(i)` / `jit_ir_b(i)` -> `0` out of
   range (negative or past the end).
3. In IR, `label`, `jmp`, `jz` and `call` use `argA` as a **label id**;
   `JIT_OP_LABEL` defines the id at its own position.
4. `jit_lower(ir)`:
   - first pass records the pc of every `JIT_OP_LABEL` (a redefined label
     keeps its newest pc);
   - second pass copies every instruction 1:1, rewriting `JIT_OP_LABEL` to
     `JIT_OP_NOP` (so pc mapping is exactly 1:1) and replacing the `argA` of
     `jmp`/`jz`/`call` with the recorded pc;
   - a jump/call to a never-defined label lowers to `JIT_NONE` (-1), which
     makes the interpreter exit `JIT_EXIT_BAD_PC`.
5. `JitCode` has the same record shape with pc operands;
   `jit_code_new`/`jit_code_push`/`jit_code_len`/`jit_code_op`/`jit_code_a`/
   `jit_code_b`/`jit_code_equal` mirror the IR API (accessors clamp the same
   way).
6. `jit_op_name` maps 0..15 to `"label"`, `"nop"`, `"push"`, `"add"`,
   `"sub"`, `"mul"`, `"load"`, `"store"`, `"jmp"`, `"jz"`, `"call"`,
   `"ret"`, `"halt"`, `"dup"`, `"swap"`, `"neg"` and anything else to
   `"op" + decimal code` (`"op99"`, `"op-1"`).
7. `jit_disasm(code)` renders `"<pc>: " + body` per instruction, bodies:
   `label <a>`, `push <a>`, `<jmp|jz|call> -> <a>`, otherwise the mnemonic.
   Every line ends with `'\n'`; empty code renders `""`. The same code
   always renders byte-equal text.

## 6. Exec model and dispatch

`JitMachine` = `{ stack: Vec[Int]; mem: Vec[Int]; frames: Vec[Int]; pc: Int;
steps: Int; status: Int; }`.

1. `jit_machine_new` gives empty stack/memory/frames, pc 0, steps 0,
   status `JIT_EXIT_RUNNING`.
2. `jit_run(code, steps_max)` starts at pc 0. Each iteration:
   - if `steps >= max(steps_max, 0)`: status `JIT_EXIT_STEP_LIMIT`, stop;
   - elif `pc < 0 || pc >= code_len`: status `JIT_EXIT_BAD_PC`, stop;
   - else dispatch the instruction at `pc` and increment `steps` by 1.
3. Dispatch semantics are the opcode table of section 3 with
   `b = pop()`, `a = pop()` operand order for the binary ops. `add`/`sub`/
   `mul` and `neg` are the only arithmetic; there is no division, so no
   division-by-zero case exists.
4. `JIT_OP_HALT`, `JIT_OP_RET` on an empty frame stack and any unknown
   opcode set the status (`HALT`/`HALT`/`BAD_OP`) and stop the loop.
5. Termination is structural: every iteration either dispatches exactly one
   instruction (and `steps` grows) or stops, and the cap bounds the total
   dispatch count. Lowered label NOPs count as dispatched instructions.
6. Accessors: `jit_machine_pc`, `jit_machine_steps`, `jit_machine_status`,
   `jit_machine_stack_depth`, `jit_machine_top` (0 when empty),
   `jit_machine_frame_depth`, `jit_machine_mem_len`, `jit_machine_mem_at`
   (0 out of range).

The exec model mirrors "loading generated code": an executor takes a
`JitCode` table, resolves closure targets through the trampoline table
(section 8) and starts a machine.

## 7. Artifact cache semantics

`JitCache` = `{ keys: Vec[Int]; slots: Vec[Int]; used: Vec[Int]; tick: Int;
cap: Int; hits: Int; misses: Int; inserts: Int; evicts: Int; }`. Entry `i`
maps `keys[i]` to an artifact handle `slots[i]`; `used[i]` is the access
stamp and `tick` is the monotone clock (one tick per get/put call).

1. `jit_cache_new(cap)` clamps `cap` to at least 1 and starts empty with
   all counters at 0.
2. `jit_cache_get(c, key)` scans for the key: on a hit it advances `tick`,
   stamps the entry, counts a hit and returns the handle; on a miss it
   counts a miss and returns `JIT_NONE`.
3. `jit_cache_put(c, key, handle)` advances `tick`; an existing key is
   updated in place (stamp, handle, `inserts++`, returns `JIT_NONE`); a new
   key fills a free slot when `len < cap` (`inserts++`, `JIT_NONE`); with a
   full cache the victim is the entry with the smallest stamp (ties break
   to the lowest slot index), replaced in place (`inserts++`, `evicts++`)
   and its old handle is returned.
4. `jit_cache_peek` is a pure lookup with no counter/stamp changes.
5. Statistics: `jit_cache_len`, `cap`, `hits`, `misses`, `inserts`,
   `evicts`.

## 8. Closures and trampolines

1. `jit_closure_make(entry, env)` masks both operands to 16 bits and packs
   `(entry << 16) | env`; `jit_closure_entry` = `(handle >> 16) & 0xFFFF`
   and `jit_closure_env` = `handle & 0xFFFF` unpack losslessly
   (`jit_closure_make(7, 3) == 458755`).
2. `jit_tramp_new` is an empty table; `jit_tramp_bind(t, closure, code)`
   stores the pair, **rebinding keeps the original slot**, and returns the
   slot index. `jit_tramp_count` is the number of bound closures.
3. `jit_tramp_code(t, closure)` -> the bound code-table handle, or
   `JIT_NONE`. `jit_tramp_entry` / `jit_tramp_env` -> the unpacked handle
   fields, or `JIT_NONE` when the closure is unbound.

## 9. Monitor and tiering policy

`JitMonitor` = parallel Vecs `sites`, `counts`, `tiers`, `deopts`.
`JitPolicy` = `{ hot; rehot; max_attempts; }`.

1. `jit_mon_hit(m, site)` finds or creates the site (created at tier
   `JIT_TIER_BASELINE`, count 1, deopts 0) and increments/returns its count.
2. Accessors: `jit_mon_count` (0 unknown), `jit_mon_tier` (`JIT_NONE`
   unknown), `jit_mon_deopts` (0 unknown), `jit_mon_sites`.
3. `jit_mon_set_tier` returns the previous tier, or `JIT_NONE` for an
   unknown site.
4. `jit_mon_deopt(m, site)` increments the deopt count, sets tier
   `JIT_TIER_DEOPT` and **resets the site counter to 0** (so the policy
   decision after a deopt is bounded and deterministic); returns the new
   deopt count, or `JIT_NONE` for an unknown site.
5. `jit_policy_new(hot, rehot, max_attempts)` clamps `hot >= 1`,
   `rehot >= 1`, `max_attempts >= 0`; accessors expose the fields.
6. `jit_tier_decide(m, site, p)` is pure:
   - unknown site, or `optimized` -> `JIT_ACTION_STAY`;
   - `baseline` with `count >= hot` -> `JIT_ACTION_COMPILE`;
   - `deopt` with `deopts < max_attempts` and `count >= rehot` ->
     `JIT_ACTION_RECOMPILE`;
   - everything else -> `JIT_ACTION_STAY`.
7. `jit_tier_apply(m, site, p)` computes the decision and, for
   `COMPILE`/`RECOMPILE`, sets the site tier to `JIT_TIER_OPTIMIZED`
   (counts and deopt counts are preserved); it returns the action.

## 10. API signatures

```xi
pub const JIT_NONE: Int = -1;
pub const JIT_EXIT_RUNNING: Int = 0;
pub const JIT_EXIT_HALT: Int = 1;
pub const JIT_EXIT_STEP_LIMIT: Int = 2;
pub const JIT_EXIT_BAD_OP: Int = 3;
pub const JIT_EXIT_BAD_PC: Int = 4;
pub const JIT_TIER_BASELINE: Int = 0;
pub const JIT_TIER_OPTIMIZED: Int = 1;
pub const JIT_TIER_DEOPT: Int = 2;
pub const JIT_ACTION_STAY: Int = 0;
pub const JIT_ACTION_COMPILE: Int = 1;
pub const JIT_ACTION_RECOMPILE: Int = 2;
pub const JIT_OP_LABEL: Int = 0;   // .. JIT_OP_NEG: Int = 15

pub type JitIr = { ops: Vec[Int]; argA: Vec[Int]; argB: Vec[Int]; }
pub type JitCode = { ops: Vec[Int]; argA: Vec[Int]; argB: Vec[Int]; }
pub type JitMachine = { stack: Vec[Int]; mem: Vec[Int]; frames: Vec[Int]; pc: Int; steps: Int; status: Int; }
pub type JitCache = { keys: Vec[Int]; slots: Vec[Int]; used: Vec[Int]; tick: Int; cap: Int; hits: Int; misses: Int; inserts: Int; evicts: Int; }
pub type JitTrampolines = { closures: Vec[Int]; codes: Vec[Int]; }
pub type JitMonitor = { sites: Vec[Int]; counts: Vec[Int]; tiers: Vec[Int]; deopts: Vec[Int]; }
pub type JitPolicy = { hot: Int; rehot: Int; max_attempts: Int; }

pub fn jit_source_hash(src: Str) -> Int
pub fn jit_artifact_key(source_hash: Int, flags: Int) -> Int
pub fn jit_key_for_source(src: Str, flags: Int) -> Int

pub fn jit_ir_new() -> JitIr
pub fn jit_ir_push(ir: &mut JitIr, op: Int, a: Int, b: Int)
pub fn jit_ir_len(ir: &JitIr) -> Int
pub fn jit_ir_op(ir: &JitIr, i: Int) -> Int
pub fn jit_ir_a(ir: &JitIr, i: Int) -> Int
pub fn jit_ir_b(ir: &JitIr, i: Int) -> Int
pub fn jit_lower(ir: &JitIr) -> JitCode

pub fn jit_code_new() -> JitCode
pub fn jit_code_push(code: &mut JitCode, op: Int, a: Int, b: Int)
pub fn jit_code_len(code: &JitCode) -> Int
pub fn jit_code_op(code: &JitCode, i: Int) -> Int
pub fn jit_code_a(code: &JitCode, i: Int) -> Int
pub fn jit_code_b(code: &JitCode, i: Int) -> Int
pub fn jit_code_equal(x: &JitCode, y: &JitCode) -> Bool
pub fn jit_op_name(op: Int) -> Str
pub fn jit_disasm(code: &JitCode) -> Str

pub fn jit_machine_new() -> JitMachine
pub fn jit_run(code: &JitCode, steps_max: Int) -> JitMachine
pub fn jit_machine_pc(m: &JitMachine) -> Int
pub fn jit_machine_steps(m: &JitMachine) -> Int
pub fn jit_machine_status(m: &JitMachine) -> Int
pub fn jit_machine_stack_depth(m: &JitMachine) -> Int
pub fn jit_machine_top(m: &JitMachine) -> Int
pub fn jit_machine_frame_depth(m: &JitMachine) -> Int
pub fn jit_machine_mem_len(m: &JitMachine) -> Int
pub fn jit_machine_mem_at(m: &JitMachine, i: Int) -> Int

pub fn jit_cache_new(cap: Int) -> JitCache
pub fn jit_cache_len(c: &JitCache) -> Int
pub fn jit_cache_cap(c: &JitCache) -> Int
pub fn jit_cache_hits(c: &JitCache) -> Int
pub fn jit_cache_misses(c: &JitCache) -> Int
pub fn jit_cache_inserts(c: &JitCache) -> Int
pub fn jit_cache_evicts(c: &JitCache) -> Int
pub fn jit_cache_peek(c: &JitCache, key: Int) -> Int
pub fn jit_cache_get(c: &mut JitCache, key: Int) -> Int
pub fn jit_cache_put(c: &mut JitCache, key: Int, handle: Int) -> Int

pub fn jit_closure_make(entry: Int, env: Int) -> Int
pub fn jit_closure_entry(handle: Int) -> Int
pub fn jit_closure_env(handle: Int) -> Int
pub fn jit_tramp_new() -> JitTrampolines
pub fn jit_tramp_bind(t: &mut JitTrampolines, closure: Int, code: Int) -> Int
pub fn jit_tramp_count(t: &JitTrampolines) -> Int
pub fn jit_tramp_code(t: &JitTrampolines, closure: Int) -> Int
pub fn jit_tramp_entry(t: &JitTrampolines, closure: Int) -> Int
pub fn jit_tramp_env(t: &JitTrampolines, closure: Int) -> Int

pub fn jit_mon_new() -> JitMonitor
pub fn jit_mon_hit(m: &mut JitMonitor, site: Int) -> Int
pub fn jit_mon_count(m: &JitMonitor, site: Int) -> Int
pub fn jit_mon_tier(m: &JitMonitor, site: Int) -> Int
pub fn jit_mon_deopts(m: &JitMonitor, site: Int) -> Int
pub fn jit_mon_sites(m: &JitMonitor) -> Int
pub fn jit_mon_set_tier(m: &mut JitMonitor, site: Int, tier: Int) -> Int
pub fn jit_mon_deopt(m: &mut JitMonitor, site: Int) -> Int
pub fn jit_policy_new(hot: Int, rehot: Int, max_attempts: Int) -> JitPolicy
pub fn jit_policy_hot(p: &JitPolicy) -> Int
pub fn jit_policy_rehot(p: &JitPolicy) -> Int
pub fn jit_policy_max_attempts(p: &JitPolicy) -> Int
pub fn jit_tier_decide(m: &JitMonitor, site: Int, p: &JitPolicy) -> Int
pub fn jit_tier_apply(m: &mut JitMonitor, site: Int, p: &JitPolicy) -> Int
```

Complexity: all constructors and single-slot accessors are O(1); hash and
disasm are O(n); `jit_lower` is O(n + hits * labels); cache get/put and the
monitor/trampoline scans are O(n); `jit_run` is O(steps_max).

## 11. Test plan

`tests/test_conformance.xi` (module `jit_fw_tests`) runs 25 named checks via
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Fixtures: a 2+3 program, a label/JZ program, a call/ret
program, the demo IR used for disassembly, and small ad-hoc programs built
inside each check. No external files are read or written.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | source hash | FNV-1a vectors (empty, `a`, `ab`, `module demo`), determinism (4.1) |
| t2 | ir build | push/len/operands, `JIT_NONE`/0 clamps (5.1-5.2) |
| t3 | lowering | label -> pc, pseudo-op -> nop, unbound -> `JIT_NONE` (5.4) |
| t4 | code builders | push/equal/clamped accessors (5.5) |
| t5 | op names | all 16 mnemonics, `op99`, `op-1` (5.6) |
| t6 | disasm | exact text and empty document (5.7) |
| t7 | arithmetic | add/sub/mul/neg (6.3) |
| t8 | stack ops | dup/swap and empty-stack top (3, 6.6) |
| t9 | memory | load/store, one-word growth, clamped reads (3, 6.3) |
| t10 | jumps | jmp/jz both paths, step counts (6.2-6.3) |
| t11 | calls | call pushes/ret pops a frame, empty-frame ret halts (6.4) |
| t12 | step limit | infinite loop bounded, cap 0 and negative (6.2, 6.5) |
| t13 | fail closed | unknown op, unbound jump, empty code (6.2, 6.4) |
| t14 | machine accessors | fresh state, post-run pc/steps/stack (6.1, 6.6) |
| t15 | cache basics | miss/insert/peek/hit and statistics (7.1-7.2, 7.4) |
| t16 | LRU victim | least-recently-used eviction order (7.3) |
| t17 | cache update | existing key replaced in place (7.3) |
| t18 | capacity clamp | `cap <= 0` clamps to 1 (7.1) |
| t19 | closure packing | (entry, env) 16+16-bit round trip (8.1) |
| t20 | trampolines | bind/rebind/slot stability/unbound sentinels (8.2-8.3) |
| t21 | monitor hits | counting, site creation, unknown defaults (9.1-9.2) |
| t22 | monitor tiers | set_tier return, deopt resets counter (9.3-9.4) |
| t23 | policy compile | clamps, threshold decision, apply (9.5-9.7) |
| t24 | policy deopt | cooldown, recompile, attempt cap (9.4, 9.6) |
| t25 | pipeline | source key + lowering + cache + dispatch end to end (4, 5, 6, 7) |

Determinism: the same inputs always yield equal values and byte-equal text;
no function in this package reads clocks, IO, randomness or addresses.

## 12. Compiler / stdlib notes (pinned v0.62.2)

- FNV hashing reads `Str` bytes with `string.byte_at` and always masks the
  widened value `(x as Int) & 0xFF` (never compare raw `UInt8 >= 128`).
- No `Vec[Str]` is used at all (module-level `Vec[Str].push` mis-lowers):
  the cache key is an `Int` and disassembly is built by `Str` concatenation.
- No `Vec[StructType]`: every record is parallel `Vec[Int]` fields or
  scalar-to-`Str` fields, and every push site mirrors into all siblings.
- No `&mut Int` scalar parameters (write-drop bug): all mutating functions
  take `&mut` struct references, and the VM carries pc/stack state in
  `JitMachine`; helper pops return their value.
- Opcode dispatch is an explicit `if/elif` chain (indexed `Vec[fn]` calls
  miscompile); no `match`, no `self` methods, no indexed dispatch tables.
- Every loop makes structural progress (one element, one instruction or one
  step per iteration); `jit_run` is additionally capped by `steps_max`.
- `jit_run` deliberately has no division, so no zero-divisor case exists.
- Integer division truncation and bit-31 comparisons are avoided entirely;
  the key mix keeps every product below 2^57 and masks to 32 bits.
- `int_to_string` (from `xiom.convert`) is the only integer-to-text path;
  `jit_op_name` owns its `"op<code>"` fallback.
