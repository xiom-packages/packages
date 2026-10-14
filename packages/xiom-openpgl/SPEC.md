# SPEC -- xiom.openpgl 0.1.0

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
SPDX-License-Identifier: MIT OR Apache-2.0

Intel Open Path Guiding Library (Open PGL) v0.7.1 (pin
`5c50cd7a331647a69e28cc8a19ff204039cbe78d`, Apache-2.0), vendored C++ core
with the oneTBB v2021.13.0 runtime sources (pin
`1c4c93fc5398c4a1acb3492c02db4699f3048dea`, Apache-2.0) compiled into the
test binary at port time.  See PROVENANCE.md for the artifact hash and
transforms.

## 1. Declared surface and coverage

Upstream `openpgl/api/api.cpp` exports **103** C API symbols at the pin.
This package declares a five-family subset and binds **31/103** (100% of
the declared surface; 72 symbols declared-skipped, see the gap list
below).

| Family (upstream C header) | Upstream symbols | Bound | Skipped | Notes |
|---|---|---|---|---|
| Device lifecycle (`device.h`) | 2 | 2 | 0 | CPU_4 only (section 5) |
| Guiding field core (`field.h`, minus dist create/init) | 16 | 9 | 7 | skipped: file I/O, compare, reset, volume-only update, volume statistics |
| Surface sampling distribution (`surfacesamplingdistribution.h` + field-side create/init/release) | 16 | 8 | 8 | skipped: cosine-product/radiance integrators, capability flag, clear, region accessor |
| Sample storage (`samplestorage.h`) | 23 | 7 | 16 | skipped: zero-value samples, merge, compare, per-sample getters, clear-surface/volume, file I/O, validate |
| Field statistics + string (`fieldstatistics.h`, `common.h`) | 5 | 5 | 0 | timings inside are wall-clock (section 6) |
| Volume sampling distribution (`volumesamplingdistribution.h` + field-side) | 16 | 0 | 16 | declared-skipped (surface-only port) |
| Path segment storage (`pathsegmentstorage.h`) | 16 | 0 | 16 | declared-skipped; the port trains from sample storage |
| Image-space guiding buffer (`imagespaceguidingbuffer.h` + field-side) | 9 | 0 | 9 | declared-skipped; upstream feature also off in the build |
| **Total** | **103** | **31** | **72** | |

Bound upstream symbols, exactly: `pglNewDevice`, `pglReleaseDevice`,
`pglDeviceNewField`, `pglFieldArgumentsSetDefaults`, `pglFieldGetIteration`,
`pglFieldSetSceneBounds`, `pglFieldGetSceneBounds`, `pglFieldValidate`,
`pglFieldUpdate`, `pglFieldGetSurfaceStatistics`, `pglReleaseField`,
`pglNewSampleStorage`, `pglReleaseSampleStorage`, `pglSampleStorageReserve`,
`pglSampleStorageClear`, `pglSampleStorageAddSamples`,
`pglSampleStorageGetSizeSurface`, `pglSampleStorageGetSizeVolume`,
`pglFieldNewSurfaceSamplingDistribution`,
`pglFieldInitSurfaceSamplingDistribution`,
`pglSurfaceSamplingDistributionSample`, `pglSurfaceSamplingDistributionPDF`,
`pglSurfaceSamplingDistributionSamplePDF`,
`pglSurfaceSamplingDistributionValidate`,
`pglSurfaceSamplingDistributionGetId`,
`pglReleaseSurfaceSamplingDistribution`, `pglFieldStatisticsToString`,
`pglFieldStatisticsHeaderCSVString`, `pglFieldStatisticsToCSVString`,
`pglReleaseFieldStatistics`, `pglReleaseString`.

### Declared-skipped families (v0.1.0)

- Path segment storage (`pglNewPathSegmentStorage` ... `pglPathSegmentGetMaxDistance`,
  16 symbols): the canonical Open PGL training feed is path segment
  propagation; this port trains from the direct sample storage feed, which
  is the same `SampleContainer` on the inside.  Planned for 0.2.0.
- Volume sampling distribution (15 symbols): the port trains and queries
  the surface field only; volume samples may be *fed* (flag bit 0) but no
  volume distribution query is exposed yet.
- Image-space guiding buffer (9 symbols): upstream optional feature,
  off in this build.
- Sample-storage extras (zero-value samples, merge/compare, per-sample
  getters, file serialization, validate): file I/O and bulk utilities are
  not part of the declared surface.
- Surface distribution extras (cosine-product/radiance integrators,
  capability flag, clear, region accessor): not part of the declared
  sample/PDF query surface.
- Field extras (file load/store, compare, reset, volume-only statistics):
  not part of the declared surface.

## 2. Declared pin rationale

v0.7.1 is the latest GitHub release of RenderKit/openpgl (published
2025-07-31; commit 2025-06-18).  The oneTBB pin is the exact version the
Open PGL superbuild downloads (`TBB_VERSION 2021.13.0`).  Nothing in
`vendor/` is regenerated from a dirty checkout; `tools/vendor.py
--hash-only` re-checks the tree hash.

## 3. Architecture

```
tests/test_conformance.xi      conformance suite (module openpgl_conformance)
src/openpgl.xi                 xiom.openpgl -- safe API, typed errors, no unsafe
src/openpgl_ffi.xi             xiom.openpgl.ffi -- the ONLY module with extern "C"
src/pgl_bridge.cpp             reviewable C++ bridge (our code) over the C API
vendor/openpgl/**              pinned upstream (Open PGL + oneTBB + embreeSrc)
```

Call flow: `device_create` -> `field_create` -> `storage_create` ->
`storage_reserve` -> `storage_add_samples` (xN) -> `field_train` (xN) ->
`sampling_distribution_create` -> `sampling_distribution_init` ->
`sampling_distribution_sample` / `_pdf` / `_sample_pdf` ->
`statistics_snapshot` -> `statistics_*` -> release in reverse order.
Distributions and statistics snapshots are owned by the field and must be
released before `field_destroy` (upstream contract).

## 4. Interop model (owned-buffer crossing, no pointer round-trips)

- Sample feed: one XIOM-owned `Vec[Float32]`, `PGL_SAMPLE_FLOATS = 10`
  floats per sample: `[px py pz dx dy dz weight pdf distance flags]`.
  `flags` bit 0 (`EInsideVolume`) routes the sample to the volume
  container, bit 1 is `EDirectLight`; values 0..3.
- Query read-backs: XIOM-owned `Vec[Float32]` slots (3 floats for a
  direction, 6 for scene bounds).
- Statistics: XIOM-owned `Vec[UInt8]` slot; the text is copied by the
  bridge into the slot and read **byte-indexed** on the XIOM side
  (`statistics_text_into` exposes the raw slot; `statistics_text` builds a
  `Str` through `xiom.string.builder`).
- The bridge validates every feed row against the upstream `SampleData`
  contract (finite components, `weight >= 0`, `pdf > 0`, `distance > 0`,
  flags 0..3) before any row enters the storage: a bad row rejects the
  whole call atomically.
- `Vec[Float32]` element values are single-precision; `flags` crosses as
  an exactly-representable float and is truncated bridge-side.

## 5. ISA policy (why CPU_4 only)

Upstream CMake compiles the openpgl core with `-msse2 -msse4.1` and the
AVX2 device TU with `-mavx2 -mfma ...`.  The xiom compile pipeline passes
no `-m` flags (only `--c-source`/`--cxx-standard`), and clang's
per-function `target` attributes — the only no-flag lever — do **not**
apply to lambda bodies, which upstream uses pervasively
(`tbb::parallel_for` bodies, field update lambdas).  Verified on the
pinned clang: attributed `always_inline` intrinsics inside un-attributed
lambdas fail with "always_inline function ... requires target feature".
The port therefore compiles the whole core at the x86-64 **SSE2 baseline**
and exposes only the **CPU_4** (4-wide) device; the `PGL_DEVICE_CPU_8`
constant exists for API completeness but `device_create(8, ...)` returns a
typed `PGL_ERR_INVALID_ARG`.  Semantics of the 4-wide path are unchanged
(SSE2 vs SSE4.1 differ only in instruction selection, not in results that
reach the API).

## 6. Determinism

`field_create(dev, deterministic = true, max_samples_per_leaf)` and
`device_create(4, 1)` (one thread) make training and queries
bit-reproducible: the suite runs the full pipeline twice and compares the
PDFs, sampled directions and distribution ids bitwise.  Exceptions that
are **not** content: the statistics text and CSV rows embed upstream
wall-clock timing fields (`timeLastUpdate*`); the CSV *header* is
byte-stable and is checked with `string.str_compare`.

## 7. Re-carve / re-pin procedure

```
git clone --depth 1 --branch v0.7.1    https://github.com/RenderKit/openpgl.git E:\repos\openpgl
git clone --depth 1 --branch v2021.13.0 https://github.com/oneapi-src/oneTBB.git E:\repos\oneTBB
cd packages/xiom-openpgl
python tools/vendor.py --openpgl E:\repos\openpgl --tbb E:\repos\oneTBB
python tools/vendor.py --openpgl E:\repos\openpgl --tbb E:\repos\oneTBB --hash-only
```

The regenerated tree must hash to the PROVENANCE.md value (it also
rewrites `port.args.json`).  Then run
`scripts/port.ps1 -Package xiom.openpgl -TimeoutSec 1500` twice and record
with `scripts/status.ps1 -Action update`.

## 8. Build and run

```
scripts/port.ps1 -Package xiom.openpgl -TimeoutSec 1500
```

The suite compiles 46 vendored C++ TUs plus the bridge (C++17) and runs 14
checks; wall time is dominated by the one-time compile (~5-7 minutes on
the reference machine), the training itself is sub-second for 256 samples
x 3 iterations.

## 9. Error codes

`0` ok, `-1` invalid/stale handle, `-2` invalid argument (incl.
unsupported device type), `-3` buffer capacity too small, `-4` upstream
creation failed, `-5` registry full, `-6` upstream returned false
(position not covered by the trained field / distribution not ready),
`-7` empty sample storage, `-8` internal error.  The public module maps
them to typed `PglError{ code, message }` values; PDF queries use `-1.0f`
as their error sentinel because a PDF is never negative.
