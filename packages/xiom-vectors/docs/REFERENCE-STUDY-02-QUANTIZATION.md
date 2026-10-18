<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Reference study 02 -- quantization mechanics vs. xvector (2026-10-11)

Owner-granted study area (`E:\repos`); sources are MIT/Apache-2.0 (licenses
verified in-clone): FAISS (`Copyright (c) Meta Platforms, Inc.`),
sqlite-vec (MIT/Apache-2.0). **No code is vendored and no build dependency
is added**: everything below is ideas/patterns to re-implement in our
module tree under our license, each gated by our probes. Citations are
`faiss/<path>:<line>` and `sqlite-vec/<path>:<line>` at the shallow clones
(`--depth 1`, 2026-10-11). Scope: scan-size / segment-size reduction
(D4/D6 territory) with an **explicit error-bound story**, because
`probe_reference_oracle` keeps our fidelity claims honest (kernel
deviations at Float32-ulp scale, ranked paths vs an independent Float64
oracle).

## What was examined

| Area | Source | xvector today |
|---|---|---|
| Scalar quantization (SQ) | `faiss/impl/ScalarQuantizer.h:26-57` (QT_8bit, QT_4bit, *_uniform, fp16, 8bit_direct; newer tqmse/eden variants); range stats `:61-74` (RS_minmax / meanstd / quantiles / optim) | full-precision Float32 store (package `xiom.vectors`); no quantization |
| SQ code formula | `faiss/impl/sq_fastscan_utils.h:91-95` `code = clamp(int((x - vmin)/vdiff * 255), 0, 255)`; trained `[vmin (d), vdiff (d)]` per dimension `:99-121`; one code split into scan bits + rerank bits `:123-154` | word codec = dim + f32 bit pattern per component (4 bytes/component) |
| Product quantization (PQ) | `faiss/impl/ProductQuantizer.h:29-126` (M slices, ksub = 2^nbits, ADC API); per-slice L2 k-means `ProductQuantizer.cpp:130-190`; distance tables `:443-507` | none |
| int8 quantization | `sqlite-vec/sqlite-vec.c:1687-1729` (`vec_quantize_int8`, fixed `[-1,1]` step `2/255`); kernels `:427` `distance_l2_sqr_int8`, `:451` `distance_l1_int8`, `:635` `distance_cosine_int8` | none |
| Binary quantization | `sqlite-vec/sqlite-vec.c:1618-1685` (sign bit per dimension, packed u8); Hamming kernels `:659-826` (NEON/AVX2/popcount64/scalar) | none |
| Two-tier rescore | `sqlite-vec/sqlite-vec-rescore.c:7-10` (quantized `_rescore_chunks` + float `_rescore_vectors` shadow tables); oversample default 8, cap 4096 `:345-359`; exact phase-2 rerank by rowid `:333-344` | exact scan IS the only tier; sealed segments (D4) store f32 |
| Graph-side quantization | `sqlite-vec/sqlite-vec-diskann.c:139-226` (quantize neighbour vectors, binary/int8 per `sqlite-vec.c:2625-2628`); query pre-quantized once `:749-753`; traversal uses quantized distances `:785-795` | HNSW graph stores full-precision vectors (flat arrays, m0-strided rows) |

## Findings (ranked; no adoption in this slice)

**F1 -- SQ8 with TRAINED per-dimension ranges is the natural first tier.**
FAISS `QT_8bit` trains `[vmin, vdiff]` per dimension and encodes
`clamp(int((x - vmin)/vdiff * 255))` (`sq_fastscan_utils.h:91-95`); decode
is `vmin + code/255 * vdiff`, so the per-component round-trip error is at
most `vdiff/255` with truncation (`vdiff/510` if round-to-nearest is
used instead). 8 bits/component = 4x smaller than f32. sqlite-vec's
`vec_quantize_int8` is the same 8-bit idea with a **fixed `[-1, 1]` range**
(`step = 2/255`, `sqlite-vec.c:1719`) -- i.e. it *assumes unit-range data*
(normalized cosine corpora). Our engine serves euclidean/dot/cosine on
arbitrary ranges (the harness corpora sit in `[-2, 2]`), so an adopted
int8 tier must train ranges (FAISS style) or carry a per-vector scale; the
fixed unit scale would clip.

**F2 -- The rescore pattern is the honesty device.** sqlite-vec never
returns quantized distances as final results: phase 1 scans the quantized
chunks for `k * oversample` candidates (default oversample 8, capped at
4096), phase 2 recomputes exact float distances from a rowid-keyed float
shadow table and sorts (`sqlite-vec-rescore.c:337-359`; the rowid-keyed
lookup is deliberate, `:342-344`). Quantization can therefore only cost
recall when the coarse tier drops a true neighbour out of the oversampled
candidate set. For our oracle gate this means: a quantized scan path must
either (a) keep an exact tier for re-ranking -- ranked results stay
bit-identical to the exact scan -- or (b) declare and gate a bound.

**F3 -- Binary + Hamming is a coarse-only tier.** One sign bit per
dimension, packed (`sqlite-vec.c:1618-1685`), 32x smaller than f32;
Hamming distance relates to angular distance for normalized vectors
(sign-flip probability ~ theta/pi). sqlite-vec uses it both for DiskANN
neighbour vectors and for the rescore phase-1 scan (`:480-483`) and never
lets it produce final cosine-quality results on its own.

**F4 -- PQ is the extreme-compression option, with training debt.**
FAISS PQ splits d into M slices of `dsub = d/M`, trains `ksub = 2^nbits`
centroids per slice by L2 k-means (`ProductQuantizer.cpp:130-190`), and
stores `M * nbits` bits per vector (d=128, M=16, nbits=8 -> 16 B/vector,
32x vs f32). ADC scores a query by one `M * ksub` distance table plus one
lookup per code (`:443-507`). Error is the per-slice reconstruction error
(needs its own budget); adoption also needs a **deterministic k-means**
(pinned seed / init / iteration budget) because our gates are per-build
numeric assertions.

**F5 -- Within-code two-tier (fast-scan split) is a cheaper variant.**
FAISS's SQ fast-scan path splits one code into top bits scanned by the
SIMD kernel and the rest kept for rerank (`sq_fastscan_utils.h:123-154`):
coarse+fine inside a single artifact, no second storage tier. Applicable
if a later slice wants coarse+fine without sqlite-vec's shadow-table
pair.

**F6 -- Graph-side quantization (DiskANN pattern) is a memory play, not
a storage one.** Quantize the NEIGHBOUR vectors only and pre-quantize the
query once per search (`sqlite-vec-diskann.c:749-753`); traversal ranks
with the quantized metric (`:785-795`). For our HNSW, adjacency (8 layers
x m0 words x 8 bytes) rivals vectors at high dimensions; quantized
neighbour vectors would cut graph memory but belong to M-P's memory
budget work. Deferred.

## Error-bound story (required before any adoption)

For a trained `[vmin_d, vmax_d]` per dimension with `vdiff_d = vmax_d -
vmin_d`, the codec round trip gives `|x_d - xhat_d| <= e_d` with
`e_d = vdiff_d/255` (truncation) or `<= vdiff_d/510` (round-to-nearest).
Derived bounds for a candidate pair (q, x) vs the decoded `xhat`:

- **dot:** `|q.x - q.xhat| <= sum_d |q_d| * e_d`
- **L2^2:** `|d2(q,x) - d2(q,xhat)| <= sum_d e_d * (2|x_d| + e_d + 2|q_d|)`
- **cosine:** our distance is `1 - (q.x)/(|q||x|)`; the perturbation is
  bounded by the dot bound divided by `|q||x|`, plus a norm-drift term
  from `|xhat|` vs `|x|` (both computable from the codes).

These bounds are conservative; like `probe_reference_oracle` does for
kernel deviations, the gate must PIN the measured maximum on the gate
corpora, not just the formula. A quantized path may only claim exactness
when its re-rank tier is exact (F2a); everything else declares a gated
bound -- this is the condition the oracle probe imposes on any future
quantized mode.

## Ranked proposals

**Q-a (first candidate) -- SQ8 quantized scan tier + exact f32 rescore
for sealed segments (D4/D6).** Segment codec v-next (`xvector-segment 2`)
gains a quantized section (int8 codes per component + trained ranges in
the meta); the existing f32 section stays as the rescore tier. Scan phase
1 over codes, phase 2 exact from f32 with a bounded oversample (default
8, absolute cap). Rationale: 4x fewer bytes scanned, both references
converge on this shape, and it is the prerequisite for D5/D6 retention
dropping the f32 tier only when an operator accepts the documented bound.
Gates (new `probe_quantization`): (1) range training determinism
(bit-identical across runs/platforms); (2) encode/decode bound: measured
`max_d |x_d - xhat_d| <= vdiff_d/255 + 1 ulp`; (3) quantized-scan +
rescore results bit-identical to the exact scan on the standard corpora
(recall@10 == oracle); (4) coarse-tier-only deviation <= the pinned
documented bound; (5) segment byte delta measured (bytes/vector table);
(6) torn-tail / versioning behavior unchanged; plus the suite mirror and
the full batteries. Hazards: cursor semantics (`after_id` must stay
exact), manifest/registry versioning, and the oracle probe staying the
single fidelity reference.
**Status 2026-10-11 (66th pass): Q-a1 DONE** -- the quantization module
(`src/index/quantize.xi`: trained ranges, truncation codec, query tables,
the two-tier rescore scan) + `probe_quantization` (17 checks;
bit-identical rescore for 10 queries x 3 metrics; measured error bounds
pinned) + suite Section 16 (6 checks) are in and green on both platforms.
**Q-a2a DONE (67th pass):** the segment artifact half -- `SealedSegment`
gains `has_sq/sq/codes` + `sealed_segment_enable_sq`, the codec gains
**version 2** (`q` ranges + `c` code records after the graph; written only
when armed, so v1 output is byte-identical) and the loader accepts both
versions with torn-section drop semantics; artifact gates added to
`probe_quantization` (roundtrip, rescore over the loaded segment == exact
for 10 queries, torn q/c keeps the vectors, byte delta 35 B/vector in the
text codec vs the future binary 8 B). Q-a2b (the read-path wiring that
consumes the codes) lands with D5's multi-segment reads and consumes study
03's record layout. This slice also
surfaced compiler finding XVC-C-15 (literal stores into `Vec[Float32]`
slots skip narrowing; repro `docs/repro/xv-f32-slot-literal-write/`,
filed on the bus).

**Q-b -- binary coarse tier** (very large sealed sets): 1 bit/dimension +
Hamming pre-filter, exact rescore; gate floors after rescore on the
standard corpora. Probabilistic error story (F3) -- coarse-only.

**Q-c -- PQ compaction (v1.1 / M-P track):** only after a deterministic
k-means (pinned seed/budget) and a reconstruction-error budget; the gate
extends the oracle probe with a quantized-mode error assertion.

**Q-d -- quantized HNSW neighbour vectors (M-P):** defer until the memory
budget slice; DiskANN's "quantize neighbours, pre-quantize the query"
is the reference shape.

## Explicit non-actions

- No lossy-only result path: every quantized search either re-ranks
  exactly or declares a gated bound.
- No PQ before deterministic training + a reconstruction-error budget.
- No fixed unit-range int8 on arbitrary-range euclidean/dot data.
- No quantization on the oracle/reference path itself (the independent
  Float64 oracle stays Float64).
- No vendoring: adopted patterns land as original implementations with
  our probes; the commit notes this study as the source.

## Next

1. **Q-a1 DONE 2026-10-11**; **Q-a2** (segment codec v-next + read-path
   wiring; consumes study 03's record-layout input) is queued behind D5's
   multi-segment reads.
2. Study 03: DiskANN SSD layout + quantized-graph notes -> design input
   for D5 delta segments + P5 mmap (second reference: the sqlite-vec
   diskann file above).
3. Study item 3 from the original backlog (sqlite-vec quantized
   brute-force kernels vs our flat scan) is largely covered by F1-F3
   here; nothing further queued under it.
