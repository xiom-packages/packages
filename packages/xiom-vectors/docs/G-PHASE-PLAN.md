<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVECTOR G phase -- concurrency & scalability plan (P1 design)

Status: design, 2026-10-11 (M-P P1: "concurrency design doc -- writer/
reader model, consistency notes"; `docs/PRODUCTION-PLAN.md`). Gates:
nothing here ships without its slice gates; **the runtime thread gate is
GREEN as of v0.64.5 (2026-10-15; both platforms; acceptance
`docs/repro/xv-thread-abi` -- exit 0, 3 workers exact sums, worker id !=
main, marks `M3: join ok 42`)**. **G-1 is COMPLETE (2026-10-18, v0.64.7):**
`tests/probes/probe_thread_sync.xi` (in both batteries) runs spawn/join +
a mutex-guarded counter + an atomic counter through NATURAL module-level
imported-type globals (XVC-C-17 fixed -- the Int-handle workaround is
retired) and a cross-thread producer/consumer leg (2 real producers x 200
handoffs through a scalar single-slot mailbox under the shared spinlock;
exact totals + per-producer FIFO) -- 14 checks green x2 on Windows + WSL.
The channel keeps its same-thread contract checks; its CROSS-THREAD leg
waits on a handle form (stdlib wishlist `REL-20261018-1518-xvector-2`)
because a module-level container initializer currently hangs the compiler
(XVC-C-19, `REL-20261018-1518-xvector`, repro
`docs/repro/xv-global-init-hang/`).

## 1. Runtime reality (as of 2026-10-16, compiler v0.64.5)

- The engine + service are single-threaded by design (one accept loop,
  one active collection per call, WAL-before-ack).
- `xiom.thread`: **compile-side AND runtime GREEN at v0.64.5** --
  `spawn[T]` + `JoinHandle.join` run REAL OS threads on Windows + WSL
  (the acceptance probe: 3 workers return exact sums, a worker's
  `current_thread_id()` differs from main; the forensics variant's last
  mark moved from `M2: spawn returned` to `M3: join ok 42`). Two stacked
  fixes landed it: the compiler env-cast half (m282 `d6690868`, in
  v0.64.5) and the stdlib halves (wave-131 spawn-buffer main-heap hoist
  + wave-139 trampoline i64 store; stdlib-v0.64.5 `092dfa0`). Verify
  evidence: `REL-20261011-1627-xvector` / `REL-20261012-1402-xvector`
  (items stay `fixed` until the next full-green archive pass closes
  them). G-1 thread + sync legs are IN (see the status note above).
- `xiom.sync` (mutex/condvar/channel/barrier/rwlock/atomics) is
  XIOM-implemented; **first cross-thread acceptance is IN (G-1)**: the
  spinlock (`xiom.sync.mutex`) and atomics (`xiom.sync.atomics`) are
  exact under 4-thread contention (2000 guarded increments, 2000
  fetch_adds, Windows + WSL); the channel is Vec-backed with NO internal
  lock (same-thread contract only today; cross-thread use needs XVC-C-17
  fixed or an explicitly locked wrapper). The sibling
  `xiom.thread.spawn` module is a documented inline SIMULATION -- do not
  build on it.
- **XVC-C-17 bites every natural shared-state pattern**: module-level
  vars of IMPORTED struct types drop pointer fields on assignment
  (`G_M = mutex_new()` -> `locked == null`). Workaround shipped in the
  probe: Int-handle globals + local handle reconstruction. Until fixed,
  shared locks/handles in globals are off-limits.
- Send/Sync enforcement for shared mutable data is still pending
  upstream (engine-lane item); this lane's own history (XVC-C-09
  segfault family while wiring shared maps) says: do not pioneer
  sharing patterns before the runtime enforces them.
- `xiom.async` exists (executor/spawn shapes); its runtime backing is
  unverified -- treat as unproven until a probe says otherwise.

Consequence: in-process threads are a POST-GATE capability. The v1
target below deliberately does not depend on them.

## 2. Target model (v1): single-writer per collection, process-level scale-out

- Each `xvectord` process owns its home (WAL + manifest + segments) and
  is the single writer for it -- the current model, kept as the
  correctness baseline. All ordering properties (WAL-before-ack,
  manifest switches, tombstones) stay single-thread guarantees.
- Parallelism for v1 = collection sharding across processes: N servers,
  each owning a disjoint collection set; the client/router maps name ->
  home. The durable manifest (M-D2) and per-collection routing (M-D3)
  already make homes self-describing, and the benchmark adapters can
  drive N servers today.
- Honest v1 claim to publish: "single-writer, horizontally shardable by
  collection; no in-process concurrency claims" (`docs/BENCHMARKS.md`
  already frames single-thread numbers).

## 3. Post-gate model (v2, only after thread gate + Send/Sync)

Ordered candidate slices, each gated:

- G-1 thread + sync smoke -- **LANDED 2026-10-16 (thread + counter legs)**:
  4 workers x mutex-guarded counter = exact; 4 workers x atomic fetch_add
  = exact; spawn/join acceptance promoted into `tests/probes/` + both
  batteries; Windows 5/5 stress + WSL green). Channel producer/consumer:
  the same-thread FIFO/close contract is pinned in the probe; the
  CROSS-THREAD leg is proved through a scalar mailbox under the shared
  spinlock (2x200 exact) -- a channel handle form is wished to stdlib
  (`REL-20261018-1518-xvector-2`); module-level container initializers
  currently hang the compiler (XVC-C-19).
- G-2 accept-loop threads BEHIND A FLAG (`XVECTORD_THREADS`): accept in
  one thread, handle per connection in workers, ALL engine calls under
  one mutex (coarse, correct-first). Gates: `probe_http_fuzz` + service
  probes x2 unchanged, a new concurrency probe (N clients x
  deterministic ops -> exact results), quick_bench QPS delta recorded
  (expect no regression; gains only for pipelined clients), graceful
  shutdown joins.
- G-3 read snapshots (readers never block writers): requires the
  runtime-enforced sharing story (Send/Sync) + a snapshot handle
  definition; design only after G-2 numbers show the mutex bottleneck.
- G-4 metrics/observability under concurrency: atomic counters or
  per-worker rings merged at scrape; the slow-query log stays ordered
  by wall clock.
- G-5 memory budget + seal/compaction thresholds (M-P P2; NON-GATED --
  can ship before the thread gate): `engine_memory_estimate` + stats
  fields + probe + `docs/OPERATIONS.md` thresholds.

## 4. Consistency notes (single-writer model, normative)

- Acknowledged writes are WAL-durable before ack (fsync still stubbed
  upstream -- the honest durability caveat stays until D5 lands).
- Readers observe prefix-consistent state: any read sees a complete WAL
  record boundary; torn tails are never observable (recovery returns
  the longest valid prefix).
- Manifest switches are atomic (temp+rename); a restart never observes
  a half-written registry.
- Cross-process: sharding keeps each collection owned by exactly ONE
  writer; the router is stateless. Two writers on one home are OUT OF
  CONTRACT (document; fail fast with a lockfile if added later).
- Deletes/updates: last-writer-wins within a collection; tombstones are
  never returned; compaction preserves both.

## 5. Risks / watchlist

- Thread gate slips: the v1 sharding story is independent -- proceed
  there first if needed.
- Send/Sync enforcement semantics (what is shareable) may reshape G-2;
  re-read compiler/stdlib notes at each archive.
- `xiom.async` backing is unverified: a probe is required before any
  async design claims.
- Concurrency regressions in numeric gates: every G slice keeps the
  existing batteries as the floor.

## 6. Slice order recommendation

P2/G-5 (memory budget, done) -> thread gate GREEN (v0.64.5) -> **G-1
COMPLETE** (2026-10-18; natural globals + mailbox leg) -> **G-2**
(flag-gated accept loop; NEXT) -> G-4 ->
(evaluate G-3) -> sharding harness story. Owner-facing claims use the v1
wording until the post-gate slices are green.
