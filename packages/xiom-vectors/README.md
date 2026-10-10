# xiom.vectors

Dense vectors for XIOM: the vector primitive with dot/magnitude/normalize,
cosine/dot/L2 distance with stable on-disk metric codes (1/2/3), the neighbor
edge and dimension value object, a bounded top-K collector, and the WAL value
codec (`[dim, ieee754-bits...]`, bit-exact) with a torn-tolerant decode-replay
loop. Extracted from XVECTOR; pure XIOM, standard library only (`xiom.std`).

## Consumer snippet

```xiom
use xiom.vectors;

var q = Vector.new(3);
q.set(0, 1.0); q.set(1, 0.0); q.set(2, 0.0);

let d = cosine_distance(&q, &q);          // 0.0
let unit = vector_normalize(&q);          // (1,0,0)

let payload = vector_encode(&q);          // [3, bits(1.0), bits(0.0), bits(0.0)]
match vector_decode(&payload) {
  Some(v) => { /* bit-exact rebuild */ }
  None => { /* torn payload */ }
}
```

## API

| Function | Result |
| --- | --- |
| `Vector.new(dimension)` | `Vector` zero-filled to `dimension` |
| `Vector.set(index, value)` / `Vector.get(index)` | receiver method |
| `vector_dot(&a, &b)` | `Float32` raw dot product |
| `vector_magnitude(&v)` | `Float32` L2 norm |
| `vector_normalize(&v)` | `Vector` unit-length copy; zero stays zero |
| `cosine_distance(&a, &b)` | `Float32`; zero-magnitude -> `1.0` |
| `dot_product_distance(&a, &b)` | `Float32` = `-sum` (reference semantics) |
| `euclidean_distance(&a, &b)` | `Float32` L2 distance |
| `vector_distance(&a, &b, metric)` | dispatch over `DistanceMetric` |
| `metric_code(m)` / `metric_from_code(c)` | on-disk codes 1/2/3; unknown -> Euclidean |
| `neighbor_new(id, distance)` | `Neighbor { id: UInt64; distance: Float32 }` |
| `dimension(v)` / `dimension_value(&d)` / `dimension_eq(&a, &b)` | `Dimension` value object |
| `dimension_is_valid(v)` / `dimension_within_limit(v)` | limits 1..65536 |
| `topk_new(capacity)` / `topk_push(&mut, n)` / `topk_len` / `topk_is_full` / `topk_worst` | bounded top-K, ascending distance |
| `vector_encode(&v)` | `Vec[Int]` WAL value payload `[dim, bits...]` |
| `vector_decode(&payload)` | `Option[Vector]`; malformed -> `None` |
| `vectors_replay_into(&payloads)` | `Vec[Vector]`; torn records skipped |

Notes: metric codes are part of the on-disk format (shared with the reference
WAL manifest records); the codec is bit-exact for every `Float32` including
`-0.0`, subnormals and infinities. `vector_normalize` and
`vectors_replay_into` are the two small additions over the XVECTOR reference
(see `SPEC.md` section 3). No indexes/engine here: the flat store and ANN
suite are `xiom.ann` territory.

## Tests

- `tests/test_conformance.xi` -- 37 checks (types, distance, normalize, top-K,
  codec/replay, determinism); run with
  `.\scripts\port.ps1 -Package xiom-vectors -TimeoutSec 90`. Green x2 on
  v0.64.3 (2026-10-10): PASS 37/37 both runs.
- `tests/probes/probe_codec_roundtrip.xi` -- codec bit-exactness/idempotence/
  torn-rejection probe (exit 0 = green); GREEN x2 on v0.64.3.
