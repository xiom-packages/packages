# AUDIT -- xiom.openpgl 0.1.0

Scope: the v0.64.4 boundary discipline (B-20..B-26), the G5 FFI-confinement
rule, the upstream-first provenance rules and the conformance evidence.
Companion documents: SPEC.md (surface + interop), PROVENANCE.md (pins +
transforms).

## 1. FFI confinement (G5)

- `extern "C"` declarations exist in exactly one module:
  `src/openpgl_ffi.xi` (`xiom.openpgl.ffi`).  `src/openpgl.xi`
  (`xiom.openpgl`) has no `unsafe` and no externs; every foreign call goes
  through a typed ffi wrapper.
- `tests/test_conformance.xi` imports only the two package modules plus
  stdlib and contains no `unsafe`.
- The bridge (`src/pgl_bridge.cpp`) is original reviewable code; it is the
  only compiled artifact outside `vendor/` apart from the TUs that
  `#include` upstream sources.

## 2. Boundary discipline checklist

| Rule | Where enforced | Evidence |
|---|---|---|
| B-20 no pointer casts of handles | handles are registry indices; `Registry<T>` in `src/pgl_bridge.cpp` stores `T*` slots, never converts to/from integers | bridge `Registry::add/get/take`; public types `PglDevice{handle: Int}` etc. |
| B-23 no bare null to C | every C pointer argument is an XIOM-owned `Vec` buffer (`as_mut_ptr`, contract-checked length) or a bridge-side object; the bridge also guards `buf == nullptr`/`out == nullptr` defensively | ffi `requires` contracts; bridge guards return `-2` |
| B-24 no foreign-pointer reads | XIOM never dereferences a foreign pointer; `pgl_vec3f`/`PGLString` results are copied into XIOM-owned slots by the bridge and read element/byte-indexed on the XIOM side | `pglb_copy_pglstring`, `pglb_field_get_scene_bounds`, `pglb_surface_dist_*`; suite `slot[i]` loop |
| B-25 one owned slot per out-param | each out-param is a separate XIOM-owned `Vec` slot; no aliasing, no scratch reuse across calls | `blank_floats`/`blank_bytes` allocate per call site |
| B-26 no `Result[Option[T]]`; `Str` equality via `string.str_compare` | public API returns `Result[T, PglError]` or plain values; the suite compares the statistics CSV header with `string.str_compare` | `src/openpgl.xi`; suite `same_header` |
| No pointer arithmetic in XIOM | no arithmetic on `*T` values; only `Vec` indexing | `src/openpgl_ffi.xi` (grep: no `+`/`-` applied to pointers) |
| Input validation before FFI | sample rows validated against the upstream `SampleData` contract; positions/directions finite-checked; device type/size args range-checked | bridge `pglb_storage_add_samples`, `pglb_surface_dist_init`, `pglb_device_new` |
| Atomic misuse rejection | an invalid row in a multi-sample feed rejects the whole call (nothing enters the storage) | suite misuse case 4 asserts the size stays 0 |
| Typed errors | negative codes map to `PglError{code, message}`; PDF sentinel `-1.0f` documented | SPEC.md section 9 |

## 3. Upstream-first compliance

- Pins: Open PGL v0.7.1 (`5c50cd7a...`) and oneTBB v2021.13.0
  (`1c4c93fc...`); both shallow clones clean at audit time, both
  Apache-2.0, license texts vendored.
- Transforms: LF normalization, angle->quoted include rewrite, two
  clang-portability gates, generated `defines.h`/`version.h` and TU
  wrappers.  No other upstream edits; all counted in the generator output
  and documented in PROVENANCE.md.
- Generated-tree sha256 `daadd981...` re-verified read-only after the
  green runs.
- Declared surface: 31/103 upstream C symbols, all five declared families
  100% bound; 72 declared-skipped with per-family reasons (SPEC.md
  section 1).
- ISA reduction (CPU_4/SSE2 baseline; CPU_8 not built) is declared with
  the root cause and the clang evidence (SPEC.md section 5) — not silently
  inherited from an environment quirk.

## 4. Conformance evidence

`tests/test_conformance.xi`, 14 checks, x2 green (see STATUS.json for the
recorded run):

- pipeline: scene bounds contain the query position (owned-buffer
  read-back); 3 training iterations recorded;
- query: fixed-direction PDF in range; sampled direction unit length;
  sampled-direction PDF in range; PDF and SamplePDF agree; distribution
  id present; statistics text non-empty;
- determinism: repeat run bit-identical (PDFs/directions/ids);
- misuse: typed errors — invalid device types (incl. the unbuilt CPU_8),
  stale device/storage handles, empty-storage training, invalid sample
  row (atomic rejection), uncovered position, statistics capacity;
- stats: text non-empty and ASCII; CSV header byte-stable across
  snapshots (`string.str_compare`); CSV row non-empty.

## 5. Known limitations (accepted)

- Statistics text/CSV rows embed upstream wall-clock timings; they are not
  bit-reproducible by design (the CSV *header* is).
- CPU_8/AVX2 kernels are not compiled (SPEC.md section 5).
- `pglFieldUpdate` catches upstream exceptions internally and reports via
  `std::cout`; the bridge pre-validates every misuse path it exposes, but
  a hypothetical exception inside training would surface as a no-op with
  upstream's console message rather than a typed error.
- Handle slots are recycled after release; a stale handle can alias a
  newly created object of the same kind (double-release and cross-kind
  misuse are rejected).  Generation counters are a 0.2.x hardening item if
  needed.
