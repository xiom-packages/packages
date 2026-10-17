# xiom-onnx -- System Dependency Audit

> **Version:** 0.2.0 (unreleased) | **Compiler:** xiom v0.64.6 (pin) |
> **Status:** all modules compile clean; suite x2 green (60/60, DirectML
> wheel 1.24.4 live leg on the RTX 3070 Ti) + 59/59 CPU-only SKIP path
> (pinned ORT 1.31.0) + 60/60 bare-runtime run (Windows inbox ORT 1.17.1).

## Compiler compatibility (v0.64.6)

All module files pass `xiom --check` / `--emit-ir`; the whole package
type-checks and runs as one unit via `tests/test_conformance.xi`
(`port.ps1`). Namespace check: 7 modules, 0 conflicts.

### Compiler findings (v0.64.6)

Two codegen defects were hit and worked around inside this package; both
reproduced with minimal scratch modules outside the package (report to the
compiler lane):

| # | Finding | Minimal repro | Workaround used |
|---|---------|---------------|-----------------|
| 1 | A bare `Vec[Str]` or `Vec[Float32]` as a **Result payload** loses its elements at the call boundary: the caller observes pointer-values-as-Ints (e.g. `'"1901871365616"'`) instead of the strings; `Vec[Int]` is fine, and returning the same Vec **without** a Result wrapper is fine. | `fn f() -> Result[Vec[Str], Str] { ... return Ok(v); }` -> caller iterates `r.value` -> elements are decimal addresses | Struct-wrapper the payload: `OnnxStrList { items: Vec[Str] }` / `OnnxF32List` / `OnnxTensorList` (round-trips correctly). |
| 2 | Passing a **struct by value** into a function call can mis-lower: the callee expects `%struct.X` but the call site passes a pointer -> clang verification failure (`'%tmp4' defined with type 'ptr' but expected '%struct.OnnxModel ...'`). | `fn close(m: MyStruct)` called with a struct local | Take `&MyStruct` (borrow) on all struct parameters. |

Also observed (not defects, but pinned-runtime semantics worth recording):

- `Str::from_c_str(p)` yields a **view** of the foreign bytes: a string
  read out of ORT-owned memory dangles once ORT frees it (e.g.
  `ReleaseAvailableProviders`). The package copies through
  `loader.own_c_str` (bounded SafePtr byte scan) everywhere the source can
  be freed.
- `Str::from_utf8(Vec[UInt8])` copies (verified with heap churn); it is the
  safe constructor used by `own_c_str` and `read_bytes`.

## System dependency: ONNX Runtime

The whole package is now a **runtime-loaded** binding: `xiom.onnx.loader`
finds a runtime via its candidate list (`XIOM_ONNX_RUNTIME` override, then
`onnxruntime.dll`, `libonnxruntime.so`, `libonnxruntime.so.1`,
`libonnxruntime.dylib`). No build-time flags, no `-l onnxruntime`.

### Install / pin (live leg)

```
DirectML (primary, 0.2.0):
  PyPI wheel onnxruntime_directml-1.24.4-cp312-cp312-win_amd64.whl
  (SHA256 F2ECB68B7B7B259D2EF3112AE760149F9B5A1E7C0FBB73D539DA6250A648A614)
  Extract to: E:\repos\onnxruntime-dml
  $env:XIOM_ONNX_RUNTIME = "E:\repos\onnxruntime-dml\onnxruntime\capi\onnxruntime.dll"
  $env:PATH = "E:\repos\onnxruntime-dml\onnxruntime\capi;" + $env:PATH  # DirectML.dll
  .\scripts\port.ps1 -Package xiom.onnx -TimeoutSec 300   # x2 = 60/60

CPU-only SKIP path:
  Official release onnxruntime-win-x64-1.31.0.zip
  (zip SHA256 3958D8A44984160692C1B4FFD0DE3CB48F8C39F9D34BB31E433DB06E30B82195)
  Extract to: E:\repos\onnxruntime-bin\onnxruntime-win-x64-1.31.0
  $env:XIOM_ONNX_RUNTIME = "E:\repos\onnxruntime-bin\onnxruntime-win-x64-1.31.0\lib\onnxruntime.dll"
  .\scripts\port.ps1 -Package xiom.onnx -TimeoutSec 300   # 59/59, typed SKIP
```

Linux/macOS use the same tarballs (see the release page); the loader
sonames are already in the candidate list.

### Without ONNX Runtime

- `xiom.onnx.types` and `xiom.onnx.tensor` work with no dependency (pure
  XIOM).
- `xiom.onnx.loader.onnx_load()` returns `Err(ONNX_LOAD_ABSENT)` -- the
  typed SKIP state; the live test reports SKIP and the suite stays green.
- A present-but-too-old runtime (< 1.14) or a surface mismatch is
  `ONNX_LOAD_ABI` (FAIL), never a silent fallback.

## Runtime version behavior (observed, windows-x64)

| Runtime | Source | Suite result |
|---------|--------|--------------|
| ORT 1.24.4 (DirectML) | `onnxruntime-directml` 1.24.4 wheel | 60/60 x2 -- providers = DML + CPU; `OrtDmlApi` append with `device_id=0`; DML-only session (CPU fallback disabled) gives [6,8] exact on the RTX 3070 Ti |
| ORT 1.31.0 CPU (pinned header) | official release zip | 59/59 -- providers = Azure + CPU; the DML probe/append classify as typed `ONNX_EP_ABSENT` (SKIP) |
| ORT 1.17.1 | Windows inbox (`C:\Windows\System32\onnxruntime.dll`) | 60/60 -- providers = DML + CPU; DML leg also live; generic appender rejects "CPUExecutionProvider" with its own "Unknown provider name" oracle (accepted by the suite) |
| (probe) ORT 1.14.1 | python onnxruntime 1.14.1 wheel | used to cross-validate the fixture model (produces [6,8]) |

All declared table indices exist unchanged in 1.17.1, 1.24.4 and 1.31.0
(verified: v1.14.1 member list is exactly the v1.31.0 prefix).

### DirectML DmlApi layout note

`OrtDmlApi` is append-only, but the table length tracks the ORT build:
ORT 1.17.1 exposes slots 0-5 only, while `GetDMLDevice` (slot 6) exists in
newer builds. The package calls slot 0
(`SessionOptionsAppendExecutionProvider_DML`) only, which every DML build
exposes; an earlier unconditional slot-6 probe faulted against the 1.17.1
inbox runtime and was removed. Do not probe later DmlApi slots without a
capability signal.

## GPU execution providers

DirectML is live in 0.2.0 (`onnx_options_append_directml`): the wrapper
resolves `OrtDmlApi` via `GetExecutionProviderApi("DML")` and appends the EP
with a DXGI adapter index. Other GPU providers (CUDA / TensorRT / CoreML /
...) remain available through `SessionOptionsAppendExecutionProvider` by
name when the runtime build ships them; the loader path is
provider-agnostic. The DML device-id mapping (adapter 0 = RTX 3070 Ti) is
recorded in PROVENANCE.md; a CPU-only build is a typed SKIP, never a
crash.

## Production readiness

| Module | Compiles | Runtime needed |
|--------|----------|----------------|
| `xiom.onnx.types` | Yes | No |
| `xiom.onnx.tensor` | Yes | No |
| `xiom.onnx.loader` | Yes | No (classification only) |
| `xiom.onnx.env` | Yes | Yes |
| `xiom.onnx.value` | Yes | Yes |
| `xiom.onnx.session` | Yes | Yes |
