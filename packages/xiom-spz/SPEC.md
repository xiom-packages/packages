# SPEC: xiom.spz -- nianticlabs/spz bindings (Gaussian-splat compression)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.spz` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | spz -- https://github.com/nianticlabs/spz |
| Upstream pin | tag **v3.0.0** = `5bf2945de1a003cee07133b1e495fe9c6ffdc7e7` |
| Upstream license | MIT (`vendor/spz/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.4 |

## 2. Vendored path (G2 pin)

`vendor/spz/` holds the six public `src/cc` files at the pin plus the MIT
LICENSE; `vendor/zlib/` holds zlib v1.3.1 (the version spz's CMake pins) and
`vendor/zstd/` the fleet-vendored zstd v1.5.7 single-file amalgamation (same
bytes as `xiom.zstd`, see PROVENANCE.md).  Every file is byte-pinned;
hashes live in `docs/vendor_manifest.json` (regenerate with
`python tools/build_vendor.py`).

Why zlib+zstd are vendored: upstream falls back to CMake `FetchContent`
(zlib 1.3.1, zstd 1.5.6) when the system libraries are absent, and the pin
has no network.  Vendoring replaces both fetches; builds never download.

### Build copy

`vendor/spz/load-spz.build.cc` is the pinned `load-spz.cc` with exactly two
documented include rewrites (`<zlib.h>`/`<zstd.h>` -> quoted relative paths;
the toolchain's `--c-source` has no include-path flag).  The rewrite list and
hashes are in `docs/vendor_manifest.json`.  `src/zstd_all.c` is the
`STATIC_BMI2 0` compile shim for the zstd amalgamation (the same shim
`xiom.zstd` ships).

## 3. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.spz` | `src/spz.xi` | public API: constants, typed errors, pack/unpack/load/save, packed accessors, cloud methods (no `unsafe`) |
| `xiom.spz.ffi` | `src/spz_ffi.xi` | the ONLY module with `extern "C"`; raw `xspz_*` declarations + small confined wrappers |
| `xiom.spz.math` | `src/spz_math.xi` | public math surface wrappers (half/norm/quat/vector helpers) |
| bridge | `src/spz_bridge.cpp` | flat C ABI over the vendored C++ API (our code, MIT OR Apache-2.0) |

Toolchain v0.64.4 discipline (docs/BINDINGS-COMPILER-FINDINGS.md):

- out-params are one XIOM-owned slot per call; slots are read byte-indexed
  (B-24); no pointer arithmetic (B-17); no foreign-pointer reads from XIOM
  (B-20) -- float streams cross as owned `Vec[Float32]` buffers only.
- no `Int as *UInt8` handle casts (B-25) and no bare `null` to C (B-23): the
  bridge takes scalars/buffers and owns every C++ temporary.
- outcome types are flat records (`Result[SpzBytes, SpzError]`), never nested
  enum payloads (B-26); `&mut` is only taken of named locals (B-21).

## 4. Workspace layout and quantizer tolerances

An unpacked cloud is one owned float workspace (`Vec[Float32]`), `n` points,
`dim = dimForDegree(sh_degree)`:

| Stream | Floats | Index |
|--------|--------|-------|
| positions | 3n | `[0, 3n)` |
| scales | 3n | `[3n, 6n)` |
| rotations (xyzw) | 4n | `[6n, 10n)` |
| alphas | n | `[10n, 11n)` |
| colors | 3n | `[11n, 14n)` |
| sh | 3*dim*n | `[14n, 14n+3*dim*n)` |

Total `14n + 3*dim*n` floats (`spz_work_size`).  `PackedGaussian` raw records
are 92 bytes (`SPZ_PACKED_OFF_*`); `PackedGaussian::unpack` yields 86 floats
(`SPZ_UNPACKED_OFF_*`).  Both layouts carry `static_assert`s in the bridge.

Format-imposed round-trip bounds (verified by the suite; fixture values are
exact pre-images so these are dominated by the quantizers in load-spz.cc):

| Field | Storage | Bound |
|-------|---------|-------|
| positions | 24-bit fixed point, 12 fractional bits | 1/8192 = 1.22e-4 (test: 5e-4) |
| scales | uint8, 16 steps/unit | 1/32 = 3.1e-2 (test: 4e-2) |
| rotations | smallest-three 9-bit (v>=3) / first-three 8-bit (v<3) | ~1.4e-2 (test: 1.2e-2 / 1.5e-2) |
| alphas | sigmoid-quantized uint8 (fixture range [-2,2]) | 1.5e-2 (test: 5e-2) |
| colors | uint8 at scale 0.15 | 9.8e-3 (test: 2e-2) |
| sh degree-1 | bucket 2^(8-sh1Bits) = 8/256 | 0.03125 (test: 3.2e-2) |
| sh degree-2+ | bucket 2^(8-shRestBits) = 16/256 | 0.0625 (test: 6.3e-2) |

## 5. Error model

Bridge codes (mirrored as `SPZ_ERR_*`):

| Code | Meaning |
|------|---------|
| 0 | ok |
| -1 | bad arguments (null/undersized buffer, bad index) |
| -2 | not an spz container (bad magic) |
| -3 | unsupported header version (NGSP accepts only 4) |
| -4 | decompression failed (zstd/gzip corruption, stream-size mismatch) |
| -5 | truncated input (header/TOC beyond EOF) |
| -6 | malformed header (point count, sh degree, stream count, no-points) |
| -7 | output capacity too small (needed count returned where documented) |
| -8 | internal error (allocation/serialization) |

The bridge pre-validates the container header (magic/version/point-cap/
TOC-bounds, `kMaxPoints = 50,000,000`) before handing untrusted bytes to
upstream, so corrupt inputs map to the codes above instead of upstream's
"empty result" ambiguity; the legacy gzip path classifies every post-inflate
failure as `SPZ_ERR_DECOMPRESS`.

File loads are **two-phase**: a capacity probe returns the required workspace
size in the slot; the wrapper allocates exactly and loads once more.

## 6. Coverage (100% of the declared surface)

`docs/COVERAGE.md` / `docs/surface_spz.json`, generated fail-closed by
`python tools/surface_spz.py` from the pinned headers:

- **53 declared items: 29 bridged** (bridge symbol + XIOM wrapper),
  **21 modeled** (types/constants), **3 audited non-goals**:
  the `SPZ_BUILD_EXTENSIONS` surface (build flag off; `splat-extensions.h`
  not vendored), `SpzLog` (header-local logging template, no library
  symbol), `PlyExtraElement` (no public function exposes instances).

Pack is included (`saveSpz` both overloads) because the API is clean over the
flat workspace.

## 7. Test matrix (recorded 2026-10-13, compiler v0.64.4)

`scripts/port.ps1 -Package xiom.spz -TimeoutSec 900` -- **74/74 PASS x2**
(counts and commit in STATUS.json):
constants/CoordinateSystem evidence; v4 pack->meta->unpack with per-field
tolerances; packed accessor bytes pinned to the quantizer formulas;
v2/v3 legacy gzip round trips; serialize+gzip byte-exact vs the v3
container; six typed corrupt-input classes; spz/PLY file round trips;
nonexistent-path classification; cloud data/convert/rotate180/medianVolume;
the full math surface.

## 8. Re-pin procedure

1. Fetch the new tag from `github.com/nianticlabs/spz` into `E:\repos\spz`
   (checkout with `core.autocrlf=false` so vendor bytes are LF).
2. Re-vendor `src/cc/*` + LICENSE; run `python tools/build_vendor.py`
   (regenerates the build copy + manifest, verified rewrites).
3. Re-run `python tools/surface_spz.py` and update the coverage table.
4. Re-run the suite x2 and record; update PROVENANCE.md/SPEC.md in the same
   commit.

## 9. Non-goals

- Extension support (`SPZ_BUILD_EXTENSIONS`): not vendored; upstream default
  is OFF and the wave-B scope excludes it.
- Random access/seek inside a container: by design the format is a single
  compressed blob; streaming requires sequential decode (prep doc sec. 4).
- `numpy`/Python bindings: upstream extras, out of scope.
