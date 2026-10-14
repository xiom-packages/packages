# PROVENANCE -- xiom.openpgl

Owner policy: docs/UPSTREAM-FIRST.md (upstream-first, 100% coverage of the
declared surface). Package version 0.1.0.

- **Upstream project:** Intel Open Path Guiding Library (Open PGL) --
  https://github.com/RenderKit/openpgl (Apache-2.0; the license text is
  vendored unmodified at `vendor/openpgl/LICENSE.txt`).
- **Declared pin (G2):** tag **v0.7.1** = commit
  `5c50cd7a331647a69e28cc8a19ff204039cbe78d` (commit date 2025-06-18;
  GitHub release published 2025-07-31).  Every vendored openpgl file comes
  from a shallow clone of that tag (`git clone --depth 1 --branch v0.7.1`).
- **Secondary vendored dependency:** oneTBB -- https://github.com/oneapi-src/oneTBB
  (Apache-2.0; license vendored at `vendor/openpgl/oneTBB/LICENSE.txt`), tag
  **v2021.13.0** = commit `1c4c93fc5398c4a1acb3492c02db4699f3048dea`, the
  exact version Open PGL's own superbuild pins
  (`superbuild/CMakeLists.txt`, BUILD_TBB_FROM_SOURCE).  Open PGL requires
  TBB at link time; the port vendors the runtime sources so the package is
  self-contained.

## Vendored artifact and generator

`tools/vendor.py` (original to this package) mirrors the two pinned trees
into `vendor/openpgl/` and emits the per-TU wrappers the xiom link line needs
(`--c-source` only; there is no `-I` passthrough, so quoted includes resolve
through the compiler's include stack with a single chain root):

```
vendor/openpgl/
  api/ data/ device/ directional/ field/ imagespace/ spatial/
  include/openpgl/ openpgl_common.h third-party/embreeSrc/ third-party/nanoflann/
  oneapi/            (oneTBB include/oneapi: tbb.h + tbb/**)
  tbb/               (oneTBB include/tbb compat headers)
  oneTBB/src/tbb/    (oneTBB runtime sources)
  pgl_tu_*.cpp       (5 openpgl library TUs)
  third-party/embreeSrc/embree_tu_*.cpp  (8 embreeSrc common TUs)
  tbb_tu_*.cpp       (32 oneTBB runtime TUs)
  LICENSE.txt, third-party-programs*.txt, oneTBB/LICENSE.txt
```

Transforms applied by the generator (all mechanical and counted; no other
upstream edits):

- **T0 LF normalization** (391 files): the pinned artifact is stored LF-only
  so a re-carve hashes identically on Windows checkouts with
  `core.autocrlf=true`; binary files are untouched.
- **T1 include rewrite** (angle-bracket -> quoted only, for the chain
  resolution): `embreeSrc/...` x17, `tbb/...` x12, `nanoflann` x1.
- **T2 two portability gates** (asserted exactly-once, literal):
  - `oneapi/tbb/detail/_config.h`: `__TBB_TSX_INTRINSICS_PRESENT` gains
    `&& !defined(__clang__)` — clang >= 20 requires the `rtm` target feature
    for the MSVC-visible `_xbegin` intrinsics and the port link line passes
    no `-m` flags; TBB then takes its documented non-TSX fallback.
  - `oneTBB/src/tbb/scheduler_common.h`: the `waitpkg` `_tpause` gate gains
    `&& !defined(__clang__)` for the same reason (non-WAITPKG fallback).
- **Generated (not upstream):** `include/openpgl/defines.h` and
  `include/openpgl/version.h` (upstream CMake configure_file templates,
  baked with the same all-optional-features-off defaults), plus the 45 TU
  wrappers.  The TU preamble defines `BUILD_STATIC`,
  `OPENPGL_DEVICE_TYPE_CPU_4`, the version macros and
  `__TBB_NO_IMPLICIT_LINKAGE` (suppresses the MSVC `#pragma comment(lib,
  "tbb12.lib")` autolink; the runtime is linked as objects).
- **Not vendored:** tinyexr and Open Image Denoise (referenced only by the
  optional image-space guiding buffer, `OPENPGL_IMAGE_SPACE_GUIDING_BUFFER`
  stays off); the `openpgl/include/openpgl/cpp/` convenience C++ wrappers
  are vendored byte-exact but not compiled.

**Generated tree sha256** (generator `tree_hash`: sha256 over sorted
relative paths + file bytes; LICENSE file names excluded, wrappers and
generated headers included), re-verified read-only after the last green run:

`daadd981a677949b898a4d15c2ccdadf65fff4c3744612a4884bcc8e65762d56`

Re-carve procedure: `SPEC.md` section 7.

## Source study clones

- `E:\repos\openpgl` -- shallow at v0.7.1 (this package; registered in
  `E:\repos\CLEANUP.md`, review-after 2026-12-01).
- `E:\repos\oneTBB` -- shallow at v2021.13.0 (this package; CLEANUP row,
  review-after 2026-12-01).

The vendored tree is regenerated only from these clean checkouts; the
generator's `--hash-only` check makes a dirty source tree visible.

## Declared surface (31/103 upstream C symbols bound; 0 open declarations)

The port binds every entry point of the five declared families; entries
outside the families are declared-skipped (header oracle gap list in
SPEC.md section 1). Bridge entry points (all `pglb_*`, 29) and their XIOM
wrappers:

| Bridge symbol | XIOM wrapper |
|---|---|
| `pglb_device_new` | `device_create` |
| `pglb_device_release` | `device_destroy` |
| `pglb_field_new` | `field_create` |
| `pglb_field_release` | `field_destroy` |
| `pglb_field_iteration` | `field_iteration` / `field_train` |
| `pglb_field_set_scene_bounds` | `field_set_scene_bounds` |
| `pglb_field_get_scene_bounds` | `field_scene_bounds` |
| `pglb_field_validate` | `field_validate` |
| `pglb_field_update` | `field_train` |
| `pglb_field_surface_stats` | `statistics_snapshot` |
| `pglb_storage_new` | `storage_create` |
| `pglb_storage_release` | `storage_destroy` |
| `pglb_storage_reserve` | `storage_reserve` |
| `pglb_storage_clear` | `storage_clear` |
| `pglb_storage_add_samples` | `storage_add_samples` |
| `pglb_storage_size_surface` | `storage_size_surface` |
| `pglb_storage_size_volume` | `storage_size_volume` |
| `pglb_surface_dist_new` | `sampling_distribution_create` |
| `pglb_surface_dist_release` | `sampling_distribution_destroy` |
| `pglb_surface_dist_init` | `sampling_distribution_init` |
| `pglb_surface_dist_sample` | `sampling_distribution_sample` |
| `pglb_surface_dist_pdf` | `sampling_distribution_pdf` |
| `pglb_surface_dist_sample_pdf` | `sampling_distribution_sample_pdf` |
| `pglb_surface_dist_validate` | `sampling_distribution_validate` |
| `pglb_surface_dist_id` | `sampling_distribution_id` |
| `pglb_stats_release` | `statistics_destroy` |
| `pglb_stats_string` | `statistics_text` / `statistics_text_into` |
| `pglb_stats_csv_header` | `statistics_csv_header` |
| `pglb_stats_csv` | `statistics_csv` |

The upstream wrappers used internally by the bridge
(`pglFieldArgumentsSetDefaults`, `pglSampleStorageAddSamples`,
`pglReleaseString`) are part of the bound set.

## Derived vs independent

`vendor/openpgl/**` is upstream code (compiled after the documented
transforms only).  `src/pgl_bridge.cpp`, `tools/vendor.py`,
`src/openpgl_ffi.xi`, `src/openpgl.xi`, `tests/` and the package docs are
original to this package.  The bridge was written against the vendored
public headers (`openpgl/include/openpgl/*.h`) and the upstream
`examples/` call order (device -> field -> sample storage -> update ->
surface sampling distribution); no upstream code was copied into the XIOM
modules.

## Boundary discipline (v0.64.4, B-20..B-26)

- Handles are bridge registry indices (Int32); no pointer ever crosses as
  an integer (B-20/B-25).  Stale handles are rejected typed.
- No bare `null` reaches C (B-23): every buffer is an XIOM-owned
  `Vec[Float32]`/`Vec[UInt8]` with a contract-checked length.
- XIOM never reads or aliases foreign memory (B-24): the bridge copies
  `PGLString` and `pgl_vec3f` values into XIOM-owned buffers itself; the
  XIOM side reads those buffers byte/element-indexed.
- No pointer arithmetic in XIOM; no pointer casts; one owned slot per
  out-param; no `Result[Option[T]]`; string equality via
  `string.str_compare` (B-26).

## Link model

Static: the vendored C++ is compiled at port time via `--c-source` with
`--cxx-standard 17` (the port.args.json list: 1 bridge + 5 openpgl + 8
embree + 32 oneTBB TUs).  No DLL, no dl-load, no runtime probe.  The core
is built at the x86-64 SSE2 baseline; the AVX2 (CPU_8) device is not
compiled (see SPEC.md section 1, ISA policy).

## License

`vendor/openpgl/**` is Apache-2.0 (Open PGL; notices retained, including
`third-party-programs*.txt`).  Everything outside `vendor/` is
MIT OR Apache-2.0.  oneTBB is Apache-2.0 (notice retained).

## Evidence

`tests/test_conformance.xi` -- 14 checks, deterministic training pipeline,
typed misuse errors, byte-indexed statistics reads; x2 green on the pinned
v0.64.4 toolchain.  The run record (run_by/commit/checked) lives in
`STATUS.json`.
