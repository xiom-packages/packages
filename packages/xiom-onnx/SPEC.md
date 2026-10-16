# xiom.onnx -- SPEC

**Phase**: bindings lane (ML/AI wave) | **Priority**: HIGH
**Status**: DELIVERED -- full ONNX Runtime C API binding (95/95 declared entry
points live-verified; suite x2 green, 56/56)
**Depends on**: xiom.ffi + xiom.ffi.dl (stdlib), ONNX Runtime at run time
(load via dlopen/LoadLibrary; typed SKIP when absent)

## What it wraps

ONNX Runtime -- cross-framework ML model inference engine (microsoft/
onnxruntime, MIT). Models from PyTorch, TensorFlow, scikit-learn, etc.
The package binds the **stable ORT C API** (`OrtGetApiBase` + the versioned
`OrtApi` function-pointer table); nothing is compiled into the package and
nothing is linked at build time (system-library path -- see
docs/UPSTREAM-FIRST.md in the repo root).

## Upstream oracle (pinned)

| What | Pin | Evidence |
|------|-----|----------|
| Header oracle | microsoft/onnxruntime **v1.31.0** = commit `402979ac1bef89dcd55add41eaa7277c407599eb` (`include/onnxruntime/core/session/onnxruntime_c_api.h` + `onnxruntime_error_code.h`) | light clone `E:\repos\onnxruntime` (blob-filtered sparse) |
| Runtime binary | official release `onnxruntime-win-x64-1.31.0.zip` (CPU) -> `E:\repos\onnxruntime-bin\onnxruntime-win-x64-1.31.0\lib\onnxruntime.dll` | zip SHA256 `3958D8A44984160692C1B4FFD0DE3CB48F8C39F9D34BB31E433DB06E30B82195` |
| Model schema | onnx/onnx **v1.23.2** = commit `e1ac8e74b620bbdc7ba07f0440806bd93f651a28` (`onnx/onnx.proto3`) | used to craft the fixture model |
| ORT_API_VERSION | `31` at the pinned header (`#define ORT_API_VERSION 31`) | loader constant `ORT_API_VERSION_PIN` |
| Floor | runtime >= **1.14** (every declared member exists at the same table index since 1.14; append-only ABI) | verified: v1.14.1's 239 members are exactly the first 239 of v1.31.0's 428 (parser diff + clang `offsetof` static asserts on all 428 v1.31.0 members) |

## Loader discipline (multi-soname, typed SKIP)

Candidates, in probe order: `XIOM_ONNX_RUNTIME` (explicit path override,
used by the live leg), `onnxruntime.dll` (Windows, also the OS-inbox name
on Windows 11), `libonnxruntime.so`, `libonnxruntime.so.1`,
`libonnxruntime.dylib`.

- No candidate loads -> `ONNX_LOAD_ABSENT` (the typed **SKIP** state; CI
  without a runtime stays green).
- A candidate loads but fails the version/surface check ->
  `ONNX_LOAD_ABI` (FAIL) with the specific reason (first missing entry
  point, older-than-floor version, null `GetApi`).
- Version negotiation: `GetVersionString` names the build (e.g. "1.31.0");
  the minor number **is** the OrtApi version it implements; the loader
  requests `min(ORT_API_VERSION_PIN, minor)`. Table indices are stable
  because ORT only appends members.
- Runtime call errors -> `ONNX_CALL_FAILED` carrying ORT's own
  `OrtErrorCode` name + message (e.g. `[ort invalid_argument]`).

## Declared C API surface (97 entry points; 100% bound + coverage table)

**OrtApiBase (2/2)**: `GetApi`, `GetVersionString`.

**OrtApi (95/95)** -- table index in parentheses; "live" = exercised against
ORT 1.31.0 (pinned binary) and ORT 1.17.1 (Windows inbox) by
`tests/test_conformance.xi`:

| Group | Members | Bound | Live evidence |
|-------|---------|-------|---------------|
| Status | `CreateStatus`(0), `GetErrorCode`(1), `GetErrorMessage`(2), `ReleaseStatus`(93) | 4/4 | 1 test: full roundtrip incl. code+text |
| Env / telemetry / providers | `CreateEnv`(3), `ReleaseEnv`(92), `EnableTelemetryEvents`(5), `DisableTelemetryEvents`(6), `GetAvailableProviders`(125), `ReleaseAvailableProviders`(126) | 6/6 | env create/release, telemetry on+off, provider enumeration (list read back) |
| Session + options + metadata | `CreateSession`(7), `CreateSessionFromArray`(8), `Run`(9), `CreateSessionOptions`(10), `SetSessionExecutionMode`(13), `EnableProfiling`(14), `DisableProfiling`(15), `EnableMemPattern`(16), `DisableMemPattern`(17), `EnableCpuMemArena`(18), `DisableCpuMemArena`(19), `SetSessionLogId`(20), `SetSessionLogVerbosityLevel`(21), `SetSessionLogSeverityLevel`(22), `SetSessionGraphOptimizationLevel`(23), `SetIntraOpNumThreads`(24), `SetInterOpNumThreads`(25), `SessionGetInputCount`(30), `SessionGetOutputCount`(31), `SessionGetInputTypeInfo`(33), `SessionGetOutputTypeInfo`(34), `SessionGetInputName`(36), `SessionGetOutputName`(37), `ReleaseSession`(95), `ReleaseSessionOptions`(100), `SessionGetModelMetadata`(111), `ModelMetadataGetProducerName`(112), `ModelMetadataGetGraphName`(113), `ModelMetadataGetDomain`(114), `ModelMetadataGetVersion`(117), `ReleaseModelMetadata`(118), `AddSessionConfigEntry`(130), `SessionOptionsAppendExecutionProvider`(216) | 33/33 | wide-path session (UTF-16 ORTCHAR_T) + array session; all 13 option setters; names/counts/type info; metadata read (producer/graph/domain/version); generic EP append incl. typed rejection of unknown names |
| Values / tensors / type-info / memory / allocators | `CreateTensorAsOrtValue`(48), `CreateTensorWithDataAsOrtValue`(49), `IsTensor`(50), `GetTensorMutableData`(51), `CastTypeInfoToTensorInfo`(55), `GetOnnxTypeFromTypeInfo`(56), `GetTensorElementType`(60), `GetDimensionsCount`(61), `GetDimensions`(62), `GetSymbolicDimensions`(63), `GetTensorShapeElementCount`(64), `GetTensorTypeAndShape`(65), `GetTypeInfo`(66), `GetValueType`(67), `CreateCpuMemoryInfo`(69), `MemoryInfoGetName`(71), `MemoryInfoGetId`(72), `MemoryInfoGetMemType`(73), `MemoryInfoGetType`(74), `AllocatorAlloc`(75), `AllocatorFree`(76), `AllocatorGetInfo`(77), `GetAllocatorWithDefaultOptions`(78), `GetValue`(80), `GetValueCount`(81), `ReleaseMemoryInfo`(94), `ReleaseValue`(96), `ReleaseTypeInfo`(98), `ReleaseTensorTypeAndShapeInfo`(99), `CreateAllocator`(131), `ReleaseAllocator`(132), `GetTensorMemoryInfo`(194) | 32/32 | allocator-owned tensor write/read exact roundtrip; borrowed-buffer aliasing; type/shape/dtype/dims/symbols; memory-info fields; alloc + free of blocks; session-owned allocator create/release; typed tensor-semantics failures (GetValue/GetValueCount) |
| Run options | `CreateRunOptions`(39), `RunOptionsSetRunLogVerbosityLevel`(40), `RunOptionsSetRunLogSeverityLevel`(41), `RunOptionsSetRunTag`(42), `RunOptionsGetRunLogVerbosityLevel`(43), `RunOptionsGetRunLogSeverityLevel`(44), `RunOptionsGetRunTag`(45), `ReleaseRunOptions`(97) | 8/8 | set + read-back roundtrip (verbosity, severity, tag); run options attached to a live Run |
| IoBinding | `RunWithBinding`(133), `CreateIoBinding`(134), `ReleaseIoBinding`(135), `BindInput`(136), `BindOutput`(137), `BindOutputToDevice`(138), `GetBoundOutputNames`(139), `GetBoundOutputValues`(140), `ClearBoundInputs`(141), `ClearBoundOutputs`(142), `SynchronizeBoundInputs`(202), `SynchronizeBoundOutputs`(203) | 12/12 | device-output binding run ([6,8] read back, names list); preallocated-output aliasing; clear verified (0 after); typed error on unknown bind name |
| **Total** | **97** | **97/97** | suite x2 = **56/56** on the pin; bonus bare-runtime run 56/56 on Windows inbox ORT 1.17.1 |

Notes:
- `ClearBoundInputs`/`ClearBoundOutputs` return **void** (not `OrtStatus*`)
  per the pinned header -- bind accordingly (see AUDIT.md).
- The declared surface is exactly `onnx_surface_slots()` / `onnx_surface_names()`
  in the loader; the loader refuses to load (ABI) unless all 95 OrtApi
  members resolve non-null.

## Modules

| Module | File | Role |
|--------|------|------|
| `xiom.onnx.types` | `src/types.xi` | shared types, ORT constant set (dtypes, codes, levels, mem types), classification + error types |
| `xiom.onnx.loader` | `src/loader.xi` | multi-soname loader, OrtApi table access, the 95-slot declared surface, version negotiation, status decode, typed error helpers |
| `xiom.onnx.env` | `src/env.xi` | env create/release, telemetry, provider enumeration, version string |
| `xiom.onnx.value` | `src/value.xi` | OrtValue tensors, type/shape info, memory info, allocators |
| `xiom.onnx.session` | `src/session.xi` | session + options (+ metadata), run options, Run, IoBinding, high-level `OnnxModel` API |
| `xiom.onnx.tensor` | `src/tensor.xi` | pure-XIOM tensor/config tier (kept from 0.1.0; renamed from `xiom.onnx.io` to free the `io` name for stdlib IO) |

## High-level API (kept 0.1.0 shape, now real)

```xiom
pub fn onnx_load_model(path: Str, config: &OnnxConfig) -> Result[OnnxModel, Str]
pub fn onnx_run(model: &OnnxModel, inputs: &Vec[OnnxTensor]) -> Result[OnnxTensorList, Str]
pub fn onnx_get_input_count(model: &OnnxModel) -> Int
pub fn onnx_get_output_count(model: &OnnxModel) -> Int
pub fn onnx_close(model: &OnnxModel)
```

`onnx_load_model` performs the full runtime bring-up (loader -> env ->
options from config -> session -> IO names -> default allocator); when no
runtime is present it returns `Err("onnx runtime unavailable: ...")` -- the
high-level face of the typed SKIP state. FLOAT tensors cross by name;
outputs come back with shape/dtype read from ORT.

## Test fixture

`tests/fixtures/add_f32.onnx` -- 110 bytes, SHA256
`DE02E0233188E0CA98666D387D075B6A6B3F5F61BF2F0632898909184451B202`.
An `Add` model: inputs `A[2], B[2]` FLOAT, output `C[2]`, opset 14,
ir_version 7, producer "xiom.onnx conformance", graph name "g". Crafted for
this suite from the ONNX protobuf schema (`onnx.proto3` @ v1.23.2) and
cross-validated three ways: Python onnxruntime 1.14.1 computes [6,8]; the
pinned ORT 1.31.0 live leg computes [6,8] (suite); the C smoke oracle reads
matching metadata (producer "xiom.onnx conformance", graph "g", domain "",
version INT64_MAX = ORT's unset sentinel).

## Live-leg recipe (recorded runs)

```powershell
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
$env:XIOM_ONNX_RUNTIME = "E:\repos\onnxruntime-bin\onnxruntime-win-x64-1.31.0\lib\onnxruntime.dll"
.\scripts\port.ps1 -Package xiom.onnx -TimeoutSec 300   # x2
```

Without `XIOM_ONNX_RUNTIME` the suite goes live on the Windows inbox runtime
(`C:\Windows\System32\onnxruntime.dll`, ORT 1.17.1: 56/56). Without any
runtime the live test reports SKIP and the suite stays green.

## Contract coverage target

- Loader: `requires` on every slot read (`api != 0`, `idx >= 0`) and on
  every public function that touches handles.
- Session/value handles: `requires: s != 0` / `v != 0` / `env != 0`.
- Run: `requires: input_names.len() == inputs.len()` plus non-empty vectors.

## Roadmap pointer

Phases delivered/remaining: see ROADMAP.md (Phase 2/3 delivered as the C API
binding; Phase 4 dtype construction lands at the C API level -- FLOAT io is
exercised end-to-end; Phase 5 vision preprocessing remains the stub).
