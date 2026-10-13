# PROVENANCE: xiom.oidn

Upstream-first doctrine: `docs/UPSTREAM-FIRST.md` (xiom-packages/packages).
This file records what was studied, what was vendored, and what is derived
for the xiom.oidn binding.

## Upstream

| Item | Value |
|------|-------|
| Project | Intel Open Image Denoise -- https://github.com/RenderKit/oidn |
| License | Apache-2.0 (verified: `E:\repos\oidn\LICENSE.txt` = Apache License 2.0, vendored as `vendor/LICENSE.txt`) |
| Clone | `E:\repos\oidn` (owner-provided shared clone space), shallow at tag `v2.5.1` |
| Pin | tag `v2.5.1`, commit `6602ee2ca38a1a2a02135beed8f6e68eed630180` (2026-08-14) |
| Vendored path | `vendor/include/OpenImageDenoise/oidn.h` (tree blob at the pin, canonical LF, byte-exact) + `vendor/include/OpenImageDenoise/config.h` (upstream-CMake-generated at v2.5.1, bytes as shipped by the official Windows release archive) + `vendor/LICENSE.txt` (tree blob, canonical LF); per-file bytes + SHA256 pins in `SPEC.md` section 2 |
| Verification | `git hash-object vendor/... == git rev-parse HEAD:<path>` against the clone at the pin for `oidn.h`/`LICENSE.txt`; `config.h` hash-pinned against the official archive extraction |
| Link model | loader tier: `src/oidn_bridge.cpp` resolves `OpenImageDenoise.dll` at runtime; the bridge is compiled by the suite (`--c-source`); the runtime binary is a documented local sample (never committed) |
| Runtime sample | official release `oidn-2.5.1.x64.windows.zip` (SHA256 `F11F91BC...396F`), CPU-only DLL subset staged at `E:\repos\oidn-release\cpu`; per-file SHA256 in `SPEC.md` section 2.1 |

## Studied surface

- `include/OpenImageDenoise/oidn.h` (v2.5.1) -- the public C API: 67
  functions, 5 opaque handle types, 4 enums, 2 typedefs, 2 sizes. The
  declared surface is this header (100% bound; `SPEC.md` section 4).
- `api/api.cpp` -- entry-point semantics: every call runs through the
  device/context error channel (`oidnGetDeviceError` returns the FIRST
  pending error and clears it; `oidnNewDevice` without a device reports
  through the global channel), which the bridge's drain-then-call-then-fetch
  error model mirrors.
- `core/device.cpp`, `core/filter.cpp`, `core/unet_filter.cpp`,
  `core/rt_filter.cpp` -- parameter semantics used by the typed-error
  checks: unknown device *get* parameter throws `InvalidArgument`, unknown
  device *set* parameter warns only; unknown filter type throws; invalid
  `quality` throws; unknown filter *get* parameter throws while unknown
  filter *set* warns; commit validates image presence ("input image not
  specified"); a device can be committed only once.
- `devices/cpu/**` -- the CPU device (ISPC kernels + oneTBB tasking): the
  reason the runtime is load-tier instead of compile-tier in this pipeline
  (see `SPEC.md` section 2.1).
- `doc/` (`README.md`, `CHANGELOG.md`) of the release -- filter types
  ("RT", "RTLightmap"), formats, and the device-module layout.

## Derived vs independent

- `oidn.xi` (constants, loader, typed wrappers), `src/oidn_bridge.cpp`
  (loader + FFI + owned-buffer helpers + analysis helpers) and
  `tests/test_conformance.xi` are original XIOM/C++ work for this package.
  No upstream XIOM port exists and no upstream code was copied beyond the
  vendored header set.
- The fixture images in the suite are generated in-test from an LCG as
  exact IEEE-754 bit patterns (values k/128); no upstream golden files or
  sample images were imported.
- The `OidnF32Stats` / byte-diff analysis helpers are package-local test
  support shipped in the bridge and module (usable by downstream users for
  buffer inspection); they are not upstream API.

## Re-carve procedure

Per `SPEC.md` section 2: advance `E:\repos\oidn` to the new tag, re-extract
`vendor/include/OpenImageDenoise/oidn.h` + `vendor/LICENSE.txt` via
`git cat-file blob HEAD:<path>` (canonical LF bytes), refresh `config.h`
from the matching official release archive, recompute both SPEC tables,
re-run `scripts/port.ps1 -Package xiom.oidn -TimeoutSec 240` x2 (present
profile with the refreshed runtime on PATH + absent profile), update the
version rows (SPEC/README/AUDIT/ROADMAP), record, wrap, publish.
