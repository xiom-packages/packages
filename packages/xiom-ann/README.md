# xiom.ann

ANN indexes for XIOM: the `AnnIndexKind` dispatch type with stable on-disk
codes (1/2/3), `AnnParams` + validation (m <= 512), the exact flat-scan
oracle, and a multi-layer HNSW graph over flat parallel arrays -- build with
deterministic levels and diversified `m`-nearest connect, best-first search,
tombstones/compaction, and a strict `Vec[Int]` codec. Extracted from XVECTOR;
pure XIOM on `xiom.std` + `xiom.vectors`.

> **Status:** `incubating` -- conformance suite green on the pin (v0.64.3):
> **24/24 x2** plus the recall probe GREEN x2 (recall@10 ef=64 **1.000**,
> ef=8 **0.9867**, 35/35 checks). Not published yet (ops scope + native-lane
> allowlist append pending).

## Consumer snippet

```xiom
use xiom.vectors;
use xiom.ann;
use xiom.ann.hnsw;

var g = hnsw_new(16, 4.0);
var v = Vector.new(3);
v.set(0, 1.0); v.set(1, 0.0); v.set(2, 0.0);
hnsw_insert(&mut g, 7, v, DistanceMetric.Euclidean);

var q = Vector.new(3);
q.set(0, 1.0); q.set(1, 0.0); q.set(2, 0.0);
let hits = hnsw_search(&g, &q, 10, 64, DistanceMetric.Euclidean);  // up to 10 nearest

let p = ann_params_default();          // m=16 ef_construction=200 ef_search=64
let ok = ann_params_valid(&p);         // true
let code = ann_kind_code(AnnIndexKind.Hnsw);   // 2 (on-disk code)

// exact oracle over parallel arrays: flat_search(&vecs, &ids, &q, 10, metric)
```

## API

| Function | Result |
| --- | --- |
| `AnnIndexKind { Flat, Hnsw, Ivf }` | index-kind enum; `ann_index_kind_name(&k)` -> `"flat"`/`"hnsw"`/`"ivf"` |
| `ann_kind_code(k)` / `ann_kind_from_code(c)` | on-disk codes 1/2/3; unknown -> `Ivf` |
| `ann_params_default()` / `ann_params_valid(&p)` | defaults m=16 efC=200 efS=64; m in 1..512, ef >= 1 |
| `flat_search(&vectors, &ids, &q, k, metric)` | exact k-NN oracle; ascending, id tie-break |
| `hnsw_new(m, ml)` / `hnsw_layer_capacity()` | empty graph; fixed 8-layer capacity |
| `hnsw_insert(&mut g, id, vec, metric)` / `hnsw_insert_ref(&mut g, id, &vec, metric)` | insert/update in place; revives tombstones |
| `hnsw_search(&g, &q, k, ef, metric)` | up to k ascending neighbors (`ef` = beam width); empty on cold/dim mismatch |
| `hnsw_search_visited` / `hnsw_build_ops` / `hnsw_size` / `hnsw_live_count` | work/stats proxies |
| `hnsw_find_node_pos(&g, id)` / `hnsw_level_of(&g, pos)` | O(log n) id -> position (-1 absent) / level |
| `hnsw_delete(&mut g, id)` / `hnsw_compact(&g, metric)` | tombstone / rebuild from live nodes |
| `hnsw_set_ef_construction(&mut g, ef)` | < 1 ignored; build clamps to >= m |
| `hnsw_encode(&g)` / `hnsw_decode(&words)` | deterministic codec; strict decode -> `None` on malformed |

Notes: the kind codes are part of the on-disk format (shared with XVECTOR's
WAL manifest records); the HNSW graph is a fixed-capacity flat-array layout
(`deg`/`adj`), so updates and rebuilds are reproducible. `flat_search` is the
small local addition over the reference (the published oracle; XVECTOR's flat
index is a dead stub and the engine is out of scope). No engine, no
store/query services here.

## Tests

- `tests/test_conformance.xi` -- 24 checks (kinds/params, flat oracle,
  HNSW build/search/update/delete/compact, codec); run with
  `.\scripts\port.ps1 -Package xiom-ann -TimeoutSec 120`. Green x2 on
  v0.64.3 (2026-10-10): PASS 24/24 both runs.
- `tests/probes/probe_hnsw_recall.xi` -- acceptance harness vs the local
  flat oracle: deterministic LCG dataset, recall@10 ef=64/ef=8, ef sweep,
  cosine run, n=800 scaling, updates, tombstones/compaction, structural
  invariants; exit = failed checks. GREEN x2 (35/35, recall 300/300 at
  ef=64, 296/300 at ef=8).
