<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Reference study 01 -- FAISS HNSW mechanics vs. xvector (2026-10-11)

Owner-granted study area (`E:\repos`); FAISS is MIT (LICENSE verified
in-clone, `Copyright (c) Facebook, Inc.`). **No code is vendored and no
build dependency is added**: everything below is ideas/patterns to
re-implement in `src/index/hnsw.xi` under our license, each gated by our
own probes. Citations are `faiss/<path>:<line>` at the shallow-clone
revision (`--depth 1`, 2026-10-11).

## What was examined

| Area | FAISS source | xvector today |
|---|---|---|
| Level assignment | `faiss/impl/HNSW.cpp:63` `set_default_probas(M, 1.0/log(M))`; `:67` `random_level()` draws from a precomputed `assign_probas` table (float subtract loop) | deterministic per-insert LCG seeded by node position; `p(level >= l) ~ ml^-l`, fixed layer capacity 0..7 (documented in `src/index/hnsw.xi`) |
| Visited set | `faiss/impl/VisitedTable.h` + `:428` (subclass + comparator, `vt.set/advance` inlined; generation-tag reuse) | per-search visited tracking in the beam loop (re-allocated per call) |
| Neighbor selection | `faiss/impl/HNSW.cpp:245` `shrink_neighbor_list` (relative-neighborhood diversify; `keep_max_size_level0` keeps level-0 degree >= 2*M); `:89` level-0 storage is `2*M`; `HNSW.h:148` `prune_headroom = 0.2` | diversified pruning at build; **P-a applied: level-0 capacity `2*m` + 0.2 headroom**; levels >= 1 cap at `m` (tombstones excluded) |
| Memory mapping / zero-copy IO | `faiss/impl/mapped_io.h`, `zerocopy_io.h`, `io.h` (`IO_FLAG_MMAP` read path) | none (P5 gated on stdlib mmap) |
| Quantization | `faiss/impl/ProductQuantizer.*`, `ScalarQuantizer.*` | none (full-precision store + Float64 WAL codec) |

## Findings and proposals (ranked; F1 applied 2026-10-11 in the first slice)

**F1 -- Level-0 degree generosity (`keep_max_size_level0`). [APPLIED
2026-10-11, P-a]** FAISS gives level 0 `2*M` slots (`set_default_probas`,
`faiss/impl/HNSW.cpp:89`) and prunes full blocks with `prune_headroom`
0.2 (`HNSW.h:148`: "leave room for more neighbors to avoid O(n^2) costs
and lock contention on frequently-pruned nodes"), so a saturated block is
not re-pruned on every incoming edge; the optional
`keep_max_size_level0` fill tops a level-0 block back up with the nearest
diversification-rejected candidates. *Ours was:* level-0 pruned like every
layer (bounded by `m`). *Adopted* (re-implemented in `src/index/hnsw.xi`,
no vendoring): level-0 capacity `m0 = 2*m`; a full level-0 block prunes to
80% of `m0` (the headroom) and refills by appends; adjacency rows stride
`m0`; codec v3 carries `m0` (v2, `m0 = m`, still decodes). *Measured*
(`probe_hnsw_recall`, 2026-10-11, compiler v0.64.3, Windows + WSL
bit-identical; hard corpus = n=300 dim=16, 6 clusters, midpoint queries at
ef=8): legacy control (`hnsw_new_full` with `m0 = m`) **275/300**,
generous **285/300**; n=200 ef=8 296/300 -> 297/300; build work 62,129 ->
60,852 distance ops (the headroom pays for the extra capacity); visited
+10-25% at n=200, +20% at n=800. The FAISS `keep_max_size_level0` fill
arm was measured too: same hard-corpus win (285/300) but ~2.5x build work
(150,716 ops) and ~40% more visited -> **not adopted** (selection stays
good-only, matching FAISS's default `keep_max_size_level0=false`).

**F2 -- Generation-tag visited sets.** FAISS reuses one `VisitedTable`
per thread with tag increments, avoiding allocation per search; also
templates the table type + comparator for inlined checks
(`HNSW.cpp:428`). *Ours:* beam loop tracks visited per call. *Proposal
P-b:* an integer "visit epoch" array on the graph (no free-list clears)
before any concurrency work (M-P); gate: behavior-identical results on
`probe_engine_hnsw` + latency delta in the bench.

**F3 -- Precomputed cumulative level table.** *Ours:* per-node LCG with a
geometric draw is already deterministic and cheap; FAISS's table is a
micro-optimization. *Proposal P-c (low):* only if insert micro-benchmarks
(the per-build work counter exists) show the draw as material.

**F4 -- mmap/zero-copy IO design notes.** `mapped_io.h` documents the read
path (mmap + alignment + fallback), directly reusable as *design input*
for P5 once stdlib mmap lands. *Proposal P-d:* capture in the P5 slice's
design; do not pre-build.

**F5 -- Quantization path.** FAISS's SQ/PQ split (per-vector scalar codes
vs product codebooks + ADC tables) is the reference for compaction work
(study item 2). *Proposal P-e:* next study slice compares
`ScalarQuantizer`/`ProductQuantizer` against `sqlite-vec`'s quantized
brute-force kernels and writes a proposal for segment-size reduction
(D4/D6 territory; must keep `probe_reference_oracle` fidelity claims
honest under quantization error bounds).

**F6 -- Search templating (informational).** Compile-time dispatch over
distance comparators keeps FAISS's inner loops monomorphic. XIOM generics
are limited; noted as a reason our kernels stay simple scalar loops until
the compiler grows (no action).

## Explicit non-actions

- No PQ/SQ adoption before a quantized-fidelity story exists (our oracle
  gate demands documented error bounds).
- No lock-free/thread code (single-threaded engine; M-P owns concurrency).
- No vendoring: any adopted pattern lands as an original implementation in
  our tree with the usual probe gates, LICENSE unchanged, commit noting
  this study as the source.

## Next

1. **P-a DONE 2026-10-11** (F1 above): implemented behind the existing API
   (`m0 = 2*m`, headroom 0.2, codec v3), gated by `probe_hnsw_recall`
   (generosity + control gates), per-ef table refreshed in
   `docs/BENCHMARKS.md`/`docs/hnsw-design.md`; both batteries green.
2. Study item 2: quantization reconnaissance (FAISS SQ/PQ + sqlite-vec)
   **DONE 2026-10-11** -> `docs/REFERENCE-STUDY-02-QUANTIZATION.md`
   (ranked proposals Q-a..Q-d; Q-a = SQ8 quantized scan tier + exact
   rescore for sealed segments is the first adoption candidate).
3. Study items 3-4 (sqlite-vec kernels, DiskANN layout) remain queued
   (item 3 is largely covered by study 02 F1-F3; study 03 = DiskANN
   layout for D5/P5).
