# SPEC: xiom.rpr -- AMD Radeon ProRender core-API bindings (runtime loader)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.rpr` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | AMD Radeon ProRender SDK -- https://github.com/GPUOpen-LibrariesAndSDKs/RadeonProRenderSDK |
| Upstream pin | tag **v3.1.7.1** = `2edd23c5fdb8eabf40bdf1ba4f6509e203e28c51` (latest release, 2026-09-10) |
| Upstream license | Apache-2.0 (`vendor/rpr/license.txt`; header keeps the AMD copyright) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (`RadeonProRender64.dll` + backend plugins are win-x64 here; the API shape is portable) |
| Compiler pin | v0.64.4 |

## 2. Decision: vendored headers + runtime DLL loader (SKIP-safe) -- NOT full vendoring

Both options are license-compatible (Apache-2.0 allows source and binary
redistribution with the license text).  This package deliberately chooses:

- **Vendored:** the pinned public header `vendor/rpr/RadeonProRender.h` and
  `vendor/rpr/license.txt` (the declaration oracle + license evidence).
- **NOT vendored:** the SDK binaries (`RadeonProRender64.dll`, the backend
  plugins, the import libraries).  The host library is loaded at runtime with
  `LoadLibraryA` and every entry point is resolved with `GetProcAddress`.
  Backends are registered with `rprRegisterPlugin(<path>)`.
- **SKIP-safe:** when the host library or a backend plugin is absent, the
  suite reports a typed SKIP and stays green (G3); the present path runs
  against the upstream SDK placed on PATH / `XIOM_RPR_SDK_DIR` at run time --
  nothing binary is committed (PROVENANCE.md local-sample table).

Reasons (recorded for the coverage audit): (1) the binary set is ~130 MB
across 9 artifacts (Northstar alone is 42 MB) -- committing it into a source
package conflicts with repo hygiene and the provenance audit; (2) the plugin
DLLs carry their own dependency expectations (HIP/OpenCL/Vulkan) that differ
per host, which a runtime loader classifies cleanly instead of failing the
build; (3) the lane precedent for GPU/OS SDKs is the system-lib SKIP path
(cuda, vulkan, ffmpeg).  Nothing the license disallows is shipped: only
Apache-2.0 material is vendored, with the license text.

## 3. G2 pin: header set + entry-point set + local sample

**Header set (SHA256 over stored LF bytes):** `RadeonProRender.h`
158,463 B = `57FF864D1B8DFBD3C754A81413DEC5536AA3D509209A10A8A35D1870FCD5FD20`
(git blob `445fb9e5...`); `license.txt` 1,842 B = `5AF0AD50...` (blob
`0bfb67e8...`).  `tools/surface_rpr.py` fails closed if either hash drifts.

**Resolved entry-point set (34 RPR functions, all GetProcAddress-resolved):**
`rprRegisterPlugin`, `rprCreateContext`, `rprContextSetActivePlugin`,
`rprContextGetInfo`, `rprContextSetScene`, `rprContextSetParameterByKey1u`,
`rprContextSetParameterByKey1f`, `rprContextSetAOV`, `rprContextRender`,
`rprContextResolveFrameBuffer`, `rprContextCreateScene`,
`rprSceneAttachShape`, `rprSceneAttachLight`, `rprSceneSetCamera`,
`rprContextCreateCamera`, `rprCameraLookAt`, `rprCameraSetFocalLength`,
`rprCameraSetSensorSize`, `rprContextCreatePointLight`,
`rprContextCreateDirectionalLight`, `rprLightSetTransform`,
`rprPointLightSetRadiantPower3f`, `rprDirectionalLightSetRadiantPower3f`,
`rprContextCreateMaterialSystem`, `rprMaterialSystemCreateNode`,
`rprMaterialNodeSetInputFByKey`, `rprMaterialNodeSetInputUByKey`,
`rprShapeSetMaterial`, `rprShapeSetTransform`, `rprContextCreateMesh`,
`rprContextCreateFrameBuffer`, `rprFrameBufferClear`,
`rprFrameBufferGetInfo`, `rprObjectDelete`.

**Local sample** (NOT the pin; nothing committed): the clone's `binWin64`
directory -- hashes and per-backend behavior in PROVENANCE.md.

### Re-pin procedure

1. Fetch the new tag into `E:\repos\RadeonProRenderSDK` (checkout with
   `core.autocrlf=false` or extract blobs with `git show`).  A release-asset
   binary set matching the tag is needed only for the local present path.
2. Re-vendor `RadeonProRender/inc/RadeonProRender.h` + `license.txt`; update
   the pins in `tools/surface_rpr.py`, PROVENANCE.md and this SPEC.
3. Re-run `python tools/surface_rpr.py` (fail-closed; regenerates
   docs/COVERAGE.md + docs/surface_rpr.json).
4. Re-run the suite x2 and record; update the sample table if the host
   backends changed.

## 4. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.rpr` | `src/rpr.xi` | public safe API: typed handles, constants, typed errors, all operations (no `unsafe`) |
| `xiom.rpr.ffi` | `src/rpr_ffi.xi` | the ONLY module with `extern "C"`; confined wrappers over the bridge |
| bridge | `src/rpr_bridge.c` | runtime loader (`LoadLibraryA` + 34 `GetProcAddress`) + flat C ABI + object registry (our code, MIT OR Apache-2.0) |

Toolchain v0.64.4 discipline (docs/BINDINGS-COMPILER-FINDINGS.md):

- **Handles never cross as pointers** (B-25): the bridge keeps a 96-slot
  registry with kind tags; XIOM sees `Int` ids (small scalars).  Typed XIOM
  structs (`RprContext`, `RprScene`, ...) make misuse a compile error.
- **No foreign-pointer reads** (B-20): the only foreign data path copies into
  XIOM-owned buffers -- mesh inputs (`Vec[Float32]`/`Vec[Int32]`) and
  framebuffer read-back (`Vec[Float32]` and the byte-indexed `Vec[UInt8]`
  variant); owned buffers are read with plain indexing (B-24).
- **No bare `null` to C** (B-23): every nullable C argument (props,
  cache path, texcoords) is constructed inside the bridge.
- **Scalar/packed returns for driver-heavy calls** (B-11): handles and
  sizes return by value; `rprFrameBufferGetInfo` capacity is checked in the
  bridge before the copy (mismatch -> `-105` typed CAPACITY error).
- One owned slot per out-param; no pointer arithmetic; no `Result[Option[T]]`.
- v0.64.4 workaround: two thin intra-module delegation wrappers
  (`context_set_iterations`, `context_last_error`) hit a C001
  unresolved-symbol codegen shape inside the full module (not reproducible
  standalone); both call the FFI layer directly and are re-visitable at the
  next pin.

Error model (flat records, no nested enum payloads): bridge codes -100..-106
(load/symbol/plugin/handle/args/capacity/table) plus the raw `rpr_status`
(-1..-29) map to `RprError{kind, code, message}`; `error_is_skip()` marks the
SKIP classes.  `rprContextGetInfo(RPR_CONTEXT_LAST_ERROR_MESSAGE)` is exposed
as `context_last_error(ctx)`.

## 5. Backend classification (typed, SKIP-safe -- never FAIL when absent)

| State | Meaning |
|-------|---------|
| `RPR_STATE_RENDERED` | full pipeline succeeded; read-back non-uniform + finite (contract enforced -- violation is a FAIL) |
| `RPR_STATE_SKIP_LOAD` | host library absent (deterministic via a bogus module name) |
| `RPR_STATE_SKIP_PLUGIN` | backend plugin absent/not loadable (deterministic via a bogus plugin path) |
| `RPR_STATE_SKIP_UNUSABLE` | backend present but an `rpr_status` error aborts the pipeline on this host |
| `RPR_STATE_SKIP_NO_OUTPUT` | backend completed every call but wrote a blank frame (GPU backend on a non-supported host GPU) |
| `RPR_STATE_FAILED` | contract violation (non-finite output, cleanup failure, or a bridge bug) |

Recorded 2026-10-14 on the development host (Ryzen 9 3950X + RTX 3070 Ti):
Northstar64 (CPU) RENDERS; Tahoe64 + HybridPro complete the API flow but
write blank frames on the NVIDIA host -> typed SKIP with the device name
reported; the legacy `Hybrid.dll` access-violates on this host and is an
audited non-goal (not in the default probe list; still reachable through
`probe_backend`).

## 6. Test contract

Suite: `tests/test_conformance.xi` -- 35 checks (recorded x2):

- pinned constants + error-model classification;
- deterministic SKIP paths (missing host library, missing plugin);
- full CPU present-path run: register -> context -> scene -> camera
  (look_at/focal/sensor) -> plane mesh (+ normal-less mesh) -> point light
  (+ directional light lifecycle) -> UBER-V2 PBR material -> two 16x16 RGBA
  F32 framebuffers -> AOV colour -> 8 iterations -> render -> resolve ->
  `RPR_FRAMEBUFFER_DESC` read-back -> float read-back (1024) -> byte
  read-back (4096) -> finite + non-uniform + non-negative stats;
- typed error paths: capacity mismatch, live `rpr_status` error (-23),
  invalid handle, bad args;
- full `rprObjectDelete` lifecycle + double-delete classification;
- GPU probes (Tahoe64, HybridPro): RENDERED or typed SKIP (never FAIL).

Command (cwd = package directory; the runner hook adds the C bridge):

```
scripts/port.ps1 -Package xiom.rpr -TimeoutSec 600
```

Present path: `set XIOM_RPR_SDK_DIR=E:\repos\RadeonProRenderSDK\RadeonProRender\binWin64`
(or the binWin64 directory on PATH).  Watchdog: allow >= 600 s (the C TU
compiles at link time; the CPU render is fast, GPU probes compile shaders).

## 7. Re-carve procedure

Same as sec. 3's re-pin procedure; additionally re-run the x2 suite on the
host class (CPU guaranteed; GPU states re-recorded) and refresh the
PROVENANCE local-sample table in the same commit.

## 8. Non-goals (0.1.0)

- `RadeonProRender_v2.h` (v2 object API), `RprLoadStore.h`,
  `ProRenderGLTF.h`, MaterialX, CL/GL/VK/D3D12/Metal interop headers.
- `rprDeprecatedApi.h`; the remaining core-header functions (images, buffers,
  AOV extras, composites, curves, volumes, post effects, subdivision) --
  phase 2 (ROADMAP in COVERAGE.md non-goals).
- Hardware capability guarantees: the package binds the API; whether a
  backend renders depends on the host (typed SKIP states above).
- The legacy `Hybrid.dll` backend is excluded from the default probe list
  (access violation on the test host without its AMD/OpenCL runtime).
