# xiom.vectors 0.1.0 -- specification

Dense-vector primitives extracted from XVECTOR (`E:\xiom-projects\xiom-xvector`):
the vector type + dot/magnitude/normalize, the cosine/dot/L2 distance metrics
with their stable on-disk codes, the neighbor edge, the dimension value object,
the bounded top-K collector, and the WAL value codec + decode-replay loop.
Pure XIOM, `xiom.std` only. No contracts/clauses in this package (new packages
ship clean); no externs; no `unsafe`. No engine, no indexes, no
payload/segment/query code (those stay `xiom.ann` / `xiom.db` territory).

## 1. Scope, surface and guarantees

**Public API** (names kept from the reference; `Vector.new/set/get` keep the
reference's method syntax):

| Function | Result |
| --- | --- |
| `Vector.new(dimension)` | `Vector` zero-filled to `dimension` |
| `Vector.set(index, value)` / `Vector.get(index)` | method on the receiver vector |
| `vector_dot(&a, &b)` | `Float32` raw dot product |
| `vector_magnitude(&v)` | `Float32` L2 norm (`xiom.math.sqrt`) |
| `vector_normalize(&v)` | `Vector` unit-length copy; zero vector stays zero |
| `dot_product_distance(&a, &b)` | `Float32` = `-sum` (negative dot, reference semantics) |
| `cosine_distance(&a, &b)` | `Float32` `1 - similarity`; zero magnitude -> `1.0` |
| `euclidean_distance(&a, &b)` | `Float32` L2 distance |
| `vector_distance(&a, &b, metric)` | dispatch over `DistanceMetric` |
| `metric_code(m)` / `metric_from_code(c)` | on-disk code 1/2/3 round-trip; unknown -> Euclidean |
| `Neighbor { id: UInt64; distance: Float32 }` + `neighbor_new` | graph edge value |
| `Dimension { value }` + `dimension` / `dimension_value` / `dimension_eq` / `dimension_is_valid` / `dimension_within_limit` | dimension value object; limits 1..65536 |
| `TopKHeap { capacity; items }` + `topk_new` / `topk_push` / `topk_len` / `topk_is_full` / `topk_worst` | bounded collector, ascending distance |
| `vector_encode(&v)` | `Vec[Int]` WAL value payload `[dim, bits0, ...]` |
| `vector_decode(&payload)` | `Option[Vector]`; strict, malformed -> `None` |
| `vectors_replay_into(&payloads)` | `Vec[Vector]`; decode-replay loop, torn records skipped |

Guarantees:

- `Dimension` validity is `1..65536` (`dimension_is_valid` mirrors
  `within_limit`); `Vector.new` zero-fills exactly `dimension` slots.
- Metric codes are stable wire/on-disk format: 1 = Cosine, 2 = DotProduct,
  3 = Euclidean; shared with the WAL collection-manifest record and the
  durable manifest file (D2) in the reference.
- `topk_push` keeps `items.len() <= capacity` after every push and keeps items
  in ascending distance order (insertion-sort then truncate); `topk_worst` is
  the last item, the eviction candidate.
- `vector_decode` rejects empty buffers, invalid dims (outside 1..65536) and
  length mismatches with `None`, so replay can skip torn records.
- `vectors_replay_into` is order-preserving and skips every payload that
  decodes to `None` (torn-tail tolerance, the reference `recover_store`
  semantics at value level).

## 2. Pins and format

### 2.1 Extraction pins (2026-10-10)

SHA256 of each extracted source file at extraction time:

| Source (XVECTOR `src/`) | SHA256 |
| --- | --- |
| `types/dense_vector.xi` | `02ed09a1d610346442187b6462ac06493ce670d8c1b92ca2a7d43e3a4f3ea1df` |
| `types/metric.xi` | `af18ae1cd75a3100c7661304720a25d46e562cf158a36e394dd0084150694f36` |
| `types/neighbor.xi` | `ba6d9ade65da8f19e08fd5926bf43ace8e64225c1d2e150bf31672d491cd5548` |
| `types/dimension.xi` | `9c1e7e33da0305375d830c5071758759782aa22c25e94158eaea941ea308bf12` |
| `query/topk_heap.xi` | `5a2863a08ae9cc5736dd67d568c953cc9a0187a898ae8da7c7907f5e10976844` |
| `storage/vector_store.xi` (codec, L156/L169) | `d20f5c26e6c42013f1928bef2f5de0b9caa5e68ec37be3e384655a1ddc670e25` |

Reference-only files (patterns carried, not extracted): `durability/recovery.xi`
(`c679de806879c050f2f9764f21be03311783735dba8c5e4e3b4748296b2f186d`, replay
loop), `tests/probes/probe_floatval_roundtrip.xi`
(`45c44b3f58f1815468b72c3ce4a3f8e8f5955cd2576c9394c1db470674dd1d56`, probe
template), `tests/test_conformance.xi`
(`684ec5ee2ec729e62e58ed968ccd47a71045a022252f7b9a921428acd75af968`,
acceptance sections).

XVECTOR commit at extraction time:
`8a8b0ff` (`8a8b0ff9bf4efdd4439bb8f696c9e495310c1d46`, 2026-10-10 20:47:44
+0300, "docs: xiom.rate adoption wrap -- pins, v0.64.3 release noted,
readiness"). The extraction brief referenced `6519f3a` ("manifest file registry
+ open-from-file (M-D2)"); it is a verified ancestor of `8a8b0ff`, and the
carve set was re-verified against `8a8b0ff` at dispatch (codec still at
`storage/vector_store.xi` L156/L169).

### 2.2 Metric code table (on-disk)

| Code | Variant |
| --- | --- |
| 1 | `DistanceMetric.Cosine` |
| 2 | `DistanceMetric.DotProduct` |
| 3 | `DistanceMetric.Euclidean` |

`metric_from_code` falls back to Euclidean for unknown codes (reference
semantics). The codes are part of the on-disk format and must not be
renumbered.

### 2.3 WAL value codec layout

```
payload = [dim, bits0, bits1, ..., bits(dim-1)]
```

- `dim` is an `Int` and must satisfy `1 <= dim <= 65536`.
- `bitsN = float.float_bits(v.data[N] as Float64)`: `Float32 -> Float64 ->
  IEEE-754 bits` is exact (every Float32 is exactly representable in
  Float64; `float_bits` lowers to a true LLVM bitcast since v0.64.0/m194).
- Decode is strict: `payload.len() < 1 -> None`, invalid `dim -> None`,
  `payload.len() != dim + 1 -> None`; otherwise `bits_to_float(bits) as
  Float32` per element.
- Round-trips are bit-exact, including `-0.0`, subnormals and infinities;
  `encode(decode(encode(v)))` equals `encode(v)` elementwise.

### 2.4 Replay loop

`vectors_replay_into(payloads)` rebuilds `Vec[Vector]` from a sequence of WAL
value payloads in order. Malformed/torn payloads decode to `None` and are
skipped; later records are still replayed (the reference `recover_store`
torn-tail tolerance, value level only). The WAL file layer itself is
`xiom.wal`'s single home; this helper never touches files.

### 2.5 Recorded evidence (2026-10-10, official v0.64.3 bits)

| Check | Command | Result |
| --- | --- | --- |
| conformance x2 | `.\scripts\port.ps1 -Package xiom-vectors -TimeoutSec 90` | PASS passed=37 failed=0 program_exit=0 exit=0 (run 1), identical (run 2) |
| codec probe x2 | `xiom --run tests/probes/probe_codec_roundtrip.xi` | GREEN, exit 0 (twice; 4/4 elements bit-exact + idempotence + torn rejected) |
| bracket scan | five legacy angle-bracket shapes over `packages/xiom-vectors` | 0 raw hits |

## 3. Additions over the reference

Two small, explicitly-marked additions (the rest of the surface is kept
exactly):

1. `vector_normalize(&v) -> Vector` -- the reference normalizes inline in
   cosine and has no standalone helper. Divides by `vector_magnitude`; the
   zero vector stays zero (unit length is undefined there). Cosine distance
   between normalized vectors is unchanged (test-covered).
2. `vectors_replay_into(&payloads)` -- the documented decode-replay loop
   distilled from `durability/recovery.xi` (the full record-type replay
   stays with the WAL engine that owns record kinds).

## 4. Layout

```
packages/xiom-vectors/
  package.xi                  manifest (xiom.vectors 0.1.0, xiom.std dep)
  src/vectors.xi              single root module `xiom.vectors`
  tests/test_conformance.xi   37 checks, [PASS]/[FAIL] per check
  tests/probes/probe_codec_roundtrip.xi  codec bit-exactness probe
  SPEC.md README.md ROADMAP.md STATUS.json .gitignore
```

Single root module (well under the ~600-line split threshold); no sibling
modules needed. `distance/{cosine,dot,l2}.xi` in the reference are DEAD STUBS
("MERGED into xiom.vector.engine") and were not used: the metric
implementations come from `types/metric.xi`.

## 5. Provenance and XVECTOR reconciliation

This package was carved read-only from XVECTOR at commit `8a8b0ff` (pins in
2.1). This package does NOT modify XVECTOR: XVECTOR owns the reference tree
until its consumption step. At that step, XVECTOR's fold-in target is its
`src/types/{dense_vector,metric,neighbor,dimension}.xi`,
`src/query/topk_heap.xi` and the codec portion of
`src/storage/vector_store.xi`; the WAL file layer is `xiom.wal`'s home, and
the flat `VectorIndex` store plus everything else in `vector_store.xi` is
`xiom.ann` territory (not extracted here -- the frozen surface has no
indexes). The full `recover_store`/`engine` machinery stays with its owners.

## 6. Toolchain notes (v0.64.3)

- Verified with the official v0.64.3 bits
  (`%LOCALAPPDATA%\xiom.new.0643\bin\xiom.exe`); the canonical install swap
  was pending a file lock at extraction time (`STATUS.json` still names the
  repo pin v0.64.2).
- Method syntax kept: `pub fn Vector.new/set/get` (implicit receiver fields
  in `set`/`get`), as in the reference.
- Enum variants are qualified (`DistanceMetric.Cosine`, ...) at construction,
  comparison and match-arm sites.
- No contracts/clauses and no `unsafe` in this package.
- Byte-level bracket scan clean: the five legacy C-style angle-bracket
  generic shapes named in the extraction brief (openers for Vec-of,
  Result-of, Option-of, and both close-bracket forms) all return 0 matches
  across `packages/xiom-vectors`.
