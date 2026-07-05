# xiom-vector

> Vector database library for XIOM — similarity search, indexing, and HNSW graph navigation.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-vector provides vector math operations, similarity search (KNN + range), a flat index, and an HNSW (Hierarchical Navigable Small World) graph structure — all in pure XIOM with safety contracts.

## Installation
```bash
xiom install xiom-vector
```

## Quick Start
```xiom
use xiom.vector.types;
use xiom.vector.index;
use xiom.vector.search;

fn main() -> Int {
  var v1 = Vector.new(3);
  v1.set(0, 1.0); v1.set(1, 0.0); v1.set(2, 0.0);
  var v2 = Vector.new(3);
  v2.set(0, 0.0); v2.set(1, 1.0); v2.set(2, 0.0);
  var dist = cosine_distance(&v1, &v2);
  return 0;
}
```

## API Reference

### Vector Math (`xiom.vector.types`)
| Function | Description |
|----------|-------------|
| `Vector.new(dim)` | Create zero vector |
| `Vector.set(i, val)` | Set dimension |
| `Vector.get(i)` | Get dimension |
| `vector_dot(a, b)` | Dot product |
| `vector_magnitude(v)` | Euclidean magnitude |
| `vector_normalize(v)` | Unit vector |
| `vector_add/sub/scale` | Arithmetic |
| `vector_distance(a, b, metric)` | Distance (Cosine/DotProduct/Euclidean) |

### Index (`xiom.vector.index`)
| Function | Description |
|----------|-------------|
| `index_new(dim)` | Create index |
| `index_add(idx, id, vec)` | Insert vector |
| `index_remove(idx, id)` | Remove by ID |
| `index_get(idx, id)` | Get by ID |
| `index_size(idx)` | Count |

### Search (`xiom.vector.search`)
| Function | Description |
|----------|-------------|
| `search_knn(idx, query, k, metric)` | Top-K nearest neighbors |
| `search_range(idx, query, radius, metric)` | Radius search |

### HNSW (`xiom.vector.hnsw`)
| Function | Description |
|----------|-------------|
| `hnsw_new(max_neighbors, ml)` | Create HNSW graph |
| `hnsw_insert(graph, id, vec)` | Insert vector |
| `hnsw_search(graph, query, k)` | Greedy hierarchical search |
| `hnsw_layer_count(graph)` | Layer count |
| `hnsw_node_count(graph)` | Node count |

## Production Readiness
| Feature | Status |
|---------|--------|
| Vector math (dot/cosine/euclidean) | ✅ Complete |
| Flat index (CRUD) | ✅ Complete |
| KNN brute-force search | ✅ Complete |
| Range search | ✅ Complete |
| HNSW graph structure | ✅ Complete |
| HNSW insert with neighbor selection | ✅ Complete |
| HNSW greedy search | ✅ Complete |
| GPU acceleration | ❌ Not yet |
| IVF/PQ quantization | ❌ Not yet |
| Disk-backed storage | ❌ Not yet |
| Batch insertion | ❌ Not yet |

### What's Left
1. **HNSW performance optimization** — heuristic neighbor selection
2. **IVF index** — inverted file for billion-scale
3. **Product quantization** — memory-efficient vectors
4. **Disk persistence** — mmap-backed index
5. **SIMD acceleration** — blocked on compiler intrinsics

## Build & Run

```bash
xiomc --run myprogram.xi
```

## Dependencies: None (Pure XIOM)
## Links: [github.com/xiom-lang](https://github.com/xiom-lang) | [XIOM](https://github.com/xiom-lang/XIOM)
## License: MIT OR Apache-2.0
