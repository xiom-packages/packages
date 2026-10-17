<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Checklist -- ORBITDB production release track

> Companion to `docs/PRODUCTION-PLAN.md`. Check items as evidence lands; the
> scoreboard (`docs/PRODUCTION-READINESS.md`) records the numbers.
> Convention: `[x]` done with committed evidence; `[~]` in progress/blocked
> with a named dependency; `[ ]` not started.
> Reference protocol (2026-10-17): every slice starts with a crawl recorded
> in `docs/REFERENCE-MATRIX.md` (file:line + adopt/adapt/avoid); blockers go
> through the relay bus and are re-tested on the next release/publish.

## M1 -- Storage spine

- [x] NodeStore behind the B-tree (get/put + page identity + dirty tracking)
- [x] Checkpoint flushes only dirty nodes (bounded-delta test in suite)
- [ ] Lazy node load (no whole-snapshot residency requirement)
- [ ] Bounded node cache with clock eviction + write-back (C4 semantics)
- [ ] 1M-key soak with memory plateau (needs stdlib byte IO for speed)
- [x] Byte-packed page format v2 design (generation-stamped pages) --
      `docs/BYTE-PAGE-FORMAT-V2.md`, slices in `docs/checklists/byte-page-v2.md`
- [ ] Page format v2 codec + KATs -- S1 is unblocked (pure codec, no IO);
      store slices S2-S4 run against the byte-IO shim until the stdlib rows land

## M2 -- Recovery & durability

- [ ] Real fsync wired into `wal_file_flush` / `page_file_sync` (blocked: stdlib fsync stub)
- [ ] Group commit (one fsync per commit group)
- [ ] Fault injection at the fsync seam (power-loss simulator)
- [ ] Kill-at-every-step matrix (extend crash harnesses to byte/page v2)
- [ ] Checkpoint policy: age/size thresholds + pause budget

## M3 -- Concurrency / MVCC

- [x] In-process reader/writer coordination (snapshot pins + COW writes; M3.1 2026-10-11, `docs/MVCC.md`)
- [ ] Multi-process advisory locks (blocked: stdlib file_lock stub)
- [x] MVCC design doc (version chains, txids, visibility, GC) -- `docs/MVCC.md` adapts: pins + COW, no per-page chains
- [x] MVCC minimal implementation + snapshot tests (pins + savepoints; suite x2 both, `probe_mvcc` 36 checks x2, fuzz (l) x2)
- [ ] Version GC tied to checkpoint compaction (M1.1b free list; hook `db_file_min_pinned_lsn`)

## M4 -- Query & indexes

- [x] Semantics decision recorded: additive `query_key_range` (key range -> value conditions -> offset -> limit)
- [x] Planner: key-range pushdown + point lookup + cost estimate
- [x] Executor uses index paths; results equal brute-force model (200-case seeded property)
- [x] Secondary indexes (catalog-driven) + fuzz vs model
      (`src/secondary_index.xi`; `IndexDef` tie-in; fuzz section (g))
- [x] ORDER/LIMIT execution (`query_order` 0/1/2; ordering before
      offset/limit; index + scan paths)

## M5 -- Types & codecs

- [x] Typed value model (int/float/text/blob) documented (FORMATS 5A, 2026-10-11)
- [x] Tuple v2 codec + fuzz round-trip over all types (suite x4 + fuzz (h), 2026-10-11)
- [x] Schema-driven storage; migration notes in FORMATS.md (schema layer +
      container decision + engine persistence DONE 2026-10-11: `schema_row`
      + `db_file_put_typed`/`get_typed` + node pages v2 + WAL subtype-1
      records + budget; suite/fuzz (j)/fault E; legacy artifacts load
      unchanged. Typed-column query/index predicates remain (S4).)

## M6 -- API & bindings

- [x] App build helper embeds `assets/orbitdb.ico` (`--icon`, verified on v0.64.2)
- [ ] Cursor API + prepared statements
- [ ] Stable error taxonomy (`docs/API.md`)
- [ ] C-ABI surface + binding package spike
- [ ] Binding smoke tests in CI

## M7 -- Performance & memory

- [ ] Benchmark workloads defined (YCSB-like, TPC-B-ish, recovery time)
- [ ] Local bench baseline at 1M keys
- [ ] Owner benchmark harness adapter
- [ ] Published numbers + regression gate (>10% blocks)

## M8 -- Security & release engineering

- [ ] Fuzz budget in CI (continuous cadence, F3)
- [ ] Fault-injection suite green (power-loss)
- [ ] Threat notes (file-access attacker model)
- [ ] Format compatibility matrix + migration policy
- [ ] Docs complete: API/RUNBOOK/FORMATS/ISOLATION + readiness
- [ ] **Release signal sent to owner: "ORBITDB is ready for public release."**

## Owner actions (after the signal)

- [ ] Public repo + CI matrix (PULSE pattern)
- [ ] Registry publish (`xiom.db`, `xiom.wal`, `xiom.btree`)
- [ ] Add ORBITDB to the owner benchmark suite; share harness contract
- [ ] Pin/rollback policy when lanes move
