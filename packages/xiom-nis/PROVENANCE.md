# PROVENANCE: xiom.nis

Owner policy: `docs/UPSTREAM-FIRST.md` (upstream-first, 100% of the declared
surface). This package vendors the upstream SDK **verbatim** (MIT) and binds
its CPU-visible surface; the XIOM modules are independent code written
against the vendored headers.

## 1. Upstream + pin

| Field | Value |
|-------|-------|
| Project | NVIDIA Image Scaling SDK -- `https://github.com/NVIDIAGameWorks/NVIDIAImageScaling` |
| License | **MIT** (`licence.txt` at the repo root: "The MIT License(MIT), Copyright(c) 2022 NVIDIA CORPORATION & AFFILIATES") |
| Delivered pin | tag `v1.0.3` -- commit `35e13ba316c98eeecf16f37eae70ce88019911f6` (2022-08-22; latest release at clone time) |
| Study clone | `E:\repos\NVIDIAImageScaling` (shallow, tag `v1.0.3`; registered in `E:\repos\CLEANUP.md`, review-after 2026-12-01) |
| Vendored scope | the SDK core `NIS/` directory (4 files) + the repo-root `licence.txt`; **nothing else** from the repository (no samples, no third-party sample dependencies, no binaries) |

The per-directory check: the vendored `NIS/` files carry the MIT header
inline, and the repo-root `licence.txt` is the same MIT text. The repository's
sample tree references third-party projects (glfw, imgui, stb, tinyexr, DXC)
via `third_party_licenses.txt`; none of those files are vendored here, so
that notice does not apply to this package.

## 2. Vendored artifact (G2 pin)

Byte-exact upstream blobs (LF-normalized; the clone's working tree is CRLF
via `core.autocrlf=true`), extracted with `git cat-file blob HEAD:<path>` at
the pinned commit. Full byte table (bytes + SHA256): `SPEC.md` section 2;
re-pin procedure: `SPEC.md` section 2.

Upstream reads: `NIS/NIS_Config.h` (config/optimizer/coefficient surface),
`NIS/NIS_Scaler.h` (shader entry points, verified for the GPU-path
classification), `NIS/NIS_Main.hlsl` / `NIS/NIS_Main.glsl` (dispatch files).
The samples were read only to confirm the intended usage pattern
(`sizeof(NISConfig)` constant-buffer size; `NVScalerUpdateConfig` call
shape) -- no sample code is vendored or copied.

## 3. What was studied; derived vs independent

**Upstream (vendored, unmodified, MIT):** `vendor/NIS/**` + `vendor/LICENSE.txt`.

**Independent (XIOM-authored, MIT OR Apache-2.0):**

- `nis.xi` -- the whole module: extern declarations, constants
  (HDR modes, GPU architectures, field indices, selector/geometry pins),
  the owned-buffer lifecycle (`nis_config_new`), typed wrappers, and the
  GPU-path descriptor. No upstream code, tables, or generated files are
  copied into the module.
- `src/nis_bridge.cpp` -- our C++ bridge: it includes the vendored header
  and exposes a small `extern "C"` surface. It encodes only interface facts
  (the `NISConfig` field count/order for the scalar accessors, the HDR-mode
  value set, the four coefficient tables) -- facts read from the vendored
  header, not copied code.
- The check values in `tests/test_conformance.xi` (scale ratios, sharpness
  mapping results, HDR constant sets, optimizer geometry, coefficient rows)
  are computed expectations from the vendored implementation's own formulas
  and tables, so the suite fails loudly on any re-pin drift.

## 4. Test vectors / golden data

No upstream test vectors exist for this SDK (it is a header-only
integration); none were imported. The suite is the verification: it runs the
real vendored builders and asserts their outputs, including byte-level reads
of the coefficient tables.

## 5. Declared surface (100% implemented)

The declared surface is **100% of the CPU-visible NIS v1.0.3 API**: the 11
declarations of `NIS_Config.h` (struct/enums/optimizer/getters/update
functions/geometry pins/coefficient tables) are all bound -- inventory and
mapping table: `SPEC.md` section 4 (11/11, 0 skips). The GPU pixel path is a
typed SKIP state (`nis_gpu_path`), not a coverage gap: v1.0.3 ships no
CPU/scalar pixel implementation, and the suite checks the shader API surface
at source level instead.

## 6. Link model

Static: `port.args.json` passes
`--c-source ${PACKAGE_DIR}/src/nis_bridge.cpp --cxx-standard 17` at port
time. No upstream binary, no system library, no dl-load. License split:
`vendor/` is MIT; everything outside `vendor/` is MIT OR Apache-2.0.

## 7. Evidence

`tests/test_conformance.xi` run through `scripts/port.ps1 -Package xiom.nis`;
the recorded x2 run (toolchain v0.64.4, counts + commit) lives in
`STATUS.json`, with the design notes in `AUDIT.md`.
