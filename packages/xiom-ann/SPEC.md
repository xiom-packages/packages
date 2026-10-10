# xiom.ann 0.1.0 -- specification

ANN index surface extracted from XVECTOR (`E:\xiom-projects\xiom-xvector`):
the `AnnIndexKind` dispatch type with its stable on-disk codes, `AnnParams` +
validation, the local exact flat-scan oracle, and the multi-layer HNSW graph
over flat parallel arrays (build, search, tombstone/compact, and the word
codec). Pure XIOM, `xiom.std` + `xiom.vectors` 0.1.0 only. No contracts/
clauses in this package (new packages ship clean); no externs; no `unsafe`.
The engine, payload/segment/query services and the flat `VectorIndex` store
are OUT (XVECTOR / future `xiom.db` territory).

## 1. Scope, surface and guarantees

**Public API** (names kept from the reference):

| Function | Result |
| --- | --- |
| `AnnIndexKind { Flat, Hnsw, Ivf }` | index-kind dispatch enum |
| `ann_index_kind_name(&k)` | `Str`: `"flat"` / `"hnsw"` / `"ivf"` |
| `ann_kind_code(k)` / `ann_kind_from_code(c)` | on-disk codes 1/2/3; unknown code -> `Ivf` |
| `AnnParams { m; ef_construction; ef_search }` + `ann_params_default()` | defaults `m=16`, `ef_construction=200`, `ef_search=64` |
| `ann_params_valid(&p)` | `Bool`; `m` in 1..512 (`max_graph_degree`), both ef fields >= 1 |
| `flat_search(&vectors, &ids, &q, k, metric)` | exact brute-force k-NN over parallel arrays; the oracle (addition, section 3) |
| `hnsw_new(m, ml)` | empty `HNSWGraph` |
| `hnsw_layer_capacity()` | fixed layer capacity 8 (verbatim) |
| `hnsw_insert(&mut g, id, vec, metric)` / `hnsw_insert_ref(&mut g, id, &vec, metric)` | insert/update in place (revives tombstones; dimension mismatch ignored) |
| `hnsw_search(&g, &q, k, ef, metric)` | up to k ascending neighbors; empty on cold graph or dim mismatch |
| `hnsw_search_visited(&g, &q, k, ef, metric)` | visited-node count of the last search shape (latency proxy) |
| `hnsw_size` / `hnsw_live_count` / `hnsw_level_of` / `hnsw_find_node_pos` | graph stats + O(log n) id -> position lookup (-1 when absent) |
| `hnsw_delete(&mut g, id)` | tombstone (idempotent; `false` for unknown/already-deleted) |
| `hnsw_compact(&g, metric)` | fresh graph rebuilt from live nodes only |
| `hnsw_build_ops(&g)` | distance-computation work proxy from the build path |
| `hnsw_set_ef_construction(&mut g, ef)` | values < 1 ignored; build clamps to >= m |
| `hnsw_encode(&g)` / `hnsw_decode(&words)` | deterministic `Vec[Int]` codec; strict decode (`None` on malformed) |

Guarantees:

- Kind codes are stable wire/on-disk format: 1 = `Flat`, 2 = `Hnsw`,
  3 = `Ivf`; `ann_kind_from_code` falls back to `Ivf` for unknown codes
  (reference semantics). The codes are shared with the XVECTOR WAL
  collection-manifest record and durable manifest file (D2) and must not be
  renumbered.
- `ann_params_valid` enforces `1 <= m <= 512` and both ef fields `>= 1`;
  `max_graph_degree` stays module-private (verbatim; the 512 cap is the
  reference's sanctioned max graph degree and matches `hnsw_decode`).
- `hnsw_search` results are distance-ascending (bounded-insert order), at
  most k entries, never tombstoned ids; empty graph or dimension mismatch
  returns empty without trapping (the reference's `requires: k > 0` /
  `ensures: result.len() <= k` clauses are stripped by the no-contracts
  policy; the behavior they described is preserved by construction).
- Levels are assigned deterministically (LCG seeded by node position, high
  bits tested); the graph is a fixed 8-layer-capacity flat-array layout, so
  rebuilds/updates are reproducible.
- `hnsw_delete` tombstones only (nodes stay as routers); `hnsw_compact`
  rebuilds from live nodes preserving insertion order and reclaiming
  tombstones.
- `hnsw_decode` is strict: wrong version, bad `m` (`<= 0` or `> 512`),
  non-positive `ml`, `ef < 1`, unknown layer capacity, out-of-range
  levels/degrees/positions, vector decode failure and any truncated/malformed
  shape return `None` (torn-record tolerance).
- `flat_search` is exact: it scans every entry, skips entries whose dimension
  differs from the query, and returns results distance-ascending with
  id-ascending tie-breaks, capped at k.

## 2. Pins and format

### 2.1 Extraction pins (2026-10-10)

SHA256 of each extracted source file at extraction time:

| Source (XVECTOR) | SHA256 |
| --- | --- |
| `src/index/ann_index.xi` | `0ca3ea3cad7fae29dea99c079c4812ddecb12ca26bd595f7eb2345c79ca9b510` |
| `src/index/hnsw.xi` | `ed6e2838bbb635ec885700be94ce9872b541ba7554f1fcb5ea9882b2c3795731` |
| `tests/probes/probe_hnsw_recall.xi` | `aeef192c58ed47bf043006a142563135c659d42eb1f2040c90c8817e54a1d8b9` |

XVECTOR commit at extraction time:
`8a8b0ff` (`8a8b0ff9bf4efdd4439bb8f696c9e495310c1d46`, 2026-10-10 20:47:44
+0300, "docs: xiom.rate adoption wrap -- pins, v0.64.3 release noted,
readiness"). The carve set was re-verified against this commit at dispatch
(all three files clean in the worktree apart from two pre-existing bracket
artifacts, section 3.3).

### 2.2 Index-kind code table (on-disk)

| Code | Variant |
| --- | --- |
| 1 | `AnnIndexKind.Flat` |
| 2 | `AnnIndexKind.Hnsw` |
| 3 | `AnnIndexKind.Ivf` |

`ann_kind_from_code` falls back to `Ivf` for unknown codes (reference
semantics, mirroring the metric-code fallback in `xiom.vectors`).

### 2.3 HNSW graph layout and codec

Flat parallel-array layout (from the reference, unchanged):

```
row(pos, layer) = pos * hnsw_layer_capacity() + layer   (into `deg`)
adj row base    = row(pos, layer) * m                    (into `adj`)
```

Levels 0..7 per node; live adjacency slots are `0 .. deg[row]`; levels are
assigned deterministically per insert (LCG seeded by node position, high-bit
sampling). Build connects the `m` nearest layer members per layer with
farthest-edge pruning over a full block (diversified selection); search does
greedy descent above layer 0 then a best-first beam on layer 0 with breadth
`max(k, ef)`.

Codec words (`hnsw_encode` / `hnsw_decode`, version 2):

```
[version=2, m, ml_bits(Float64), ef_construction, layer_capacity, entry,
 node_count, per node: id, level, deleted(0|1), vector_words_len,
 vector words..., per layer (0..capacity): degree, neighbor positions...]
```

Vector words are `xiom.vectors.vector_encode` payloads (dim + f32 bits;
bit-exact). Decode is strict (section 1 guarantees).

### 2.4 Recorded evidence (2026-10-10, official v0.64.3 bits)

| Check | Command | Result |
| --- | --- | --- |
| conformance x2 | `.\scripts\port.ps1 -Package xiom-ann -TimeoutSec 120` | PASS passed=24 failed=0 program_exit=0 exit=0 (run 1, 21.9 s wall), identical (run 2, 18.1 s wall); no watchdog widening needed |
| recall probe x2 | `xiom --run tests/probes/probe_hnsw_recall.xi` | GREEN x2, exit 0, 35/35 checks, 0 warnings both runs |
| recall@10 ef=64 | same probe | 300/300 = 1.000 both runs |
| recall@10 ef=8 | same probe | 296/300 = 0.9867 both runs (beam-width effect, avg_visited 170/200 at ef=64) |
| cosine sanity | same probe | 100/100; n=800 run 200/200; update path 200/200; post-delete 300/300; compacted 200/200 |
| bracket scan | five bracket shapes over `packages/xiom-ann` (all .xi files) | 0 raw hits |

## 3. Additions and deviations over the reference

1. `flat_search(&vectors, &ids, &q, k, metric) -> Vec[Neighbor]` -- a small
   local addition (the published oracle surface). XVECTOR's `flat_index.xi`
   is a dead stub (merged into `engine.xi`) and the engine is out of scope;
   the probe harness needs an exact oracle, so the brute-force scan lives
   here (~30 lines incl. two private helpers). Same distance functions
   (`vector_distance` over `xiom.vectors`); distance-ascending, id-ascending
   on ties; dim-mismatched entries are skipped.
2. `src/hnsw.xi` import repoints only: module renamed `xiom.ann.hnsw`; the
   three `xiom.vector.types.{dense_vector,metric,neighbor}` imports collapse
   into `use xiom.vectors;`; the `xiom.vector.storage.vector_store` import is
   dropped (only a codec comment referenced it; the comment now names
   `xiom.vectors.vector_encode`). The `requires`/`ensures` clauses on
   `hnsw_new` / `hnsw_search` / `hnsw_search_visited` are stripped by the
   package no-contracts policy; the described behavior is preserved and
   test-covered. No shims were needed: every private helper's dependency
   (`Vector`, `Neighbor`, `DistanceMetric`, `vector_distance`,
   `vector_encode`, `vector_decode`, `float_bits`/`bits_to_float`) has a
   public equivalent in `xiom.vectors` / `xiom.num.float`.
3. Two bracket artifacts in the XVECTOR source were normalized in the port:
   `src/index/hnsw.xi` L39 and L41 use a legacy opening angle bracket in the
   `Vec`-of shape for the `levels`/`deg` fields of `HNSWGraph` (real hits of
   the scan's open-angle shape, pre-existing in the clean worktree).
   v0.64.3 accepts the artifact form (verified with an isolated probe), but
   this package ships the canonical bracket form (scan-clean policy); no
   semantic change.
4. `src/ann_index.xi` is verbatim apart from the module name (`xiom.ann`)
   and variant-qualified enum sites: the `match` arms in
   `ann_index_kind_name` are `AnnIndexKind.Flat` / `.Hnsw` / `.Ivf` (the
   source used bare variant names). `max_graph_degree` stays module-private.
5. The acceptance harness `tests/probes/probe_hnsw_recall.xi` is adapted
   from XVECTOR's probe: the `vector_store` VectorIndex + `search_service`
   oracle is replaced by the local `flat_search` over the probe's own
   parallel arrays (`flat_upsert`/`flat_remove` mirror the store's
   upsert/remove-by-id semantics; `hit_count` drops the reference's unused
   `k` parameter). The deterministic LCG dataset, recall@10 for ef=64/ef=8,
   the ef sweep, the cosine run, n=800 scaling, updates, deletes/revive,
   compaction and the structural invariants (len <= k, ascending, unique
   ids, empty graph, dimension mismatch) are kept; exit = failed checks.

## 4. Layout

```
packages/xiom-ann/
  package.xi                  manifest (xiom.ann 0.1.0, xiom.std + xiom.vectors deps)
  xiom.toml                   dependency-root manifest for the v0.64.3 resolver
  src/ann.xi                  module `xiom.ann` (kinds/params + flat_search)
  src/hnsw.xi                 module `xiom.ann.hnsw` (the 24 KB flat-array HNSW)
  tests/test_conformance.xi   24 checks, [PASS]/[FAIL] per check
  tests/probes/probe_hnsw_recall.xi  recall/acceptance harness vs the local oracle
  SPEC.md README.md ROADMAP.md STATUS.json .gitignore
```

Two root modules (ann.xi 109 lines, hnsw.xi 762 lines); the HNSW file is a
single cohesive port kept whole (same cohesion argument as the reference).

## 5. Provenance and XVECTOR reconciliation

This package was carved read-only from XVECTOR at commit `8a8b0ff` (pins in
2.1). This package does NOT modify XVECTOR: XVECTOR owns the reference tree
until its consumption step. At that step, XVECTOR's fold-in targets are
`src/index/ann_index.xi` and `src/index/hnsw.xi`; the engine, payload/
segment/query services and the flat `VectorIndex` store stay with their
owners (the store half is `xiom.ann` / `xiom.db` territory, not extracted
here -- the frozen surface has no store). XVECTOR's own
`tests/probes/probe_hnsw_recall.xi` is referenced here as the adaptation
source; the package carries the oracle-adapted copy.

## 6. Toolchain notes (v0.64.3)

- Verified with the official v0.64.3 bits (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`,
  the dispatch pin); `xiom.toml [dependencies] xiom.vectors = "0.1.0"`
  resolves the installed package root under `%LOCALAPPDATA%\xiom\packages`
  (verified with an isolated pre-build dependency probe before packaging).
- Enum variants are qualified at construction, comparison and match-arm
  sites; no contracts/clauses and no `unsafe` anywhere in the package.
- Both probe runs and both suite runs are warning-free (an early
  `flat_upsert` reshape emitted a benign moved-value note; the final shape
  has a single use-site per value and compiles clean).
- Byte-level bracket scan clean: the five legacy bracket shapes named in the
  extraction brief (open-angle openers for Vec-of, Result-of, Option-of, and
  both close-bracket forms) all return 0 matches across `packages/xiom-ann`.
