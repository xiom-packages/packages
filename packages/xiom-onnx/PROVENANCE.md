# xiom.onnx -- PROVENANCE

Per docs/UPSTREAM-FIRST.md (xiom-packages/packages): record what was used
from upstream, the exact revision, the license, and the evidence. This
package is a **runtime-loaded binding**: no upstream source is compiled,
linked or vendored; upstream artifacts serve as oracles and as the tested
live runtime.

## 1. Header oracle -- microsoft/onnxruntime

| Field | Value |
|-------|-------|
| Upstream | https://github.com/microsoft/onnxruntime |
| License | MIT (LICENSE.txt at repo root; verified 2026-10-16 at the pin) |
| Pin | tag **v1.31.0** = commit `402979ac1bef89dcd55add41eaa7277c407599eb` |
| Clone | `E:\repos\onnxruntime` -- `git clone --depth 1 --branch v1.31.0 --filter=blob:none --sparse` then `sparse-checkout add include/onnxruntime/core/session include/onnxruntime/core/providers/dml onnxruntime/core/session` (C API + DML headers and the provider-registration source used to confirm the DML append path; blob-filtered, light) |
| Files read | `include/onnxruntime/core/session/onnxruntime_c_api.h` (the 428-member `OrtApi` struct order, `OrtApiBase`, enums), `onnxruntime_error_code.h`, `include/onnxruntime/core/providers/dml/dml_provider_factory.h` (`OrtDmlApi` layout + device-id semantics), `VERSION_NUMBER` |
| Use | transcription oracle: every const/index in `src/types.xi` + `src/loader.xi` |
| Verification | 1) mechanical parse of the struct member order; 2) clang `_Static_assert(offsetof(OrtApi, X)/8 == idx)` for **all 428 members** (v1.31.0 header, clang 22, `-fsyntax-only`: 0 errors); 3) append-only cross-check: v1.14.1's 239 members are exactly the first 239 of v1.31.0's list (same parser over the v1.14.1 header); 4) the added `GetExecutionProviderApi` index was re-verified with the same clang offsetof check (`195`) |

## 2. Runtime binary -- official CPU release

| Field | Value |
|-------|-------|
| Artifact | `onnxruntime-win-x64-1.31.0.zip` (official GitHub release asset, tag v1.31.0) |
| License | MIT (same repo) |
| Local | `E:\repos\onnxruntime-bin\onnxruntime-win-x64-1.31.0\lib\onnxruntime.dll` |
| SHA256 (zip) | `3958D8A44984160692C1B4FFD0DE3CB48F8C39F9D34BB31E433DB06E30B82195` |
| Use | CPU live/SKIP leg: `port.ps1` = 59/59 (59 tests; the DirectML leg reports typed SKIP), env -> session -> Run -> [6,8] exact |
| Policy | policy-clean: MIT release binary, fetched from the canonical GitHub release, kept outside the repo in `E:\repos` (registered in `E:\repos\CLEANUP.md`) |

## 3. DirectML runtime -- onnxruntime-directml wheel (0.2.0 leg)

| Field | Value |
|-------|-------|
| Artifact | `onnxruntime_directml-1.24.4-cp312-cp312-win_amd64.whl` (PyPI project `onnxruntime-directml`, Microsoft-published) |
| License | MIT (same upstream repository; wheel ships `LICENSE`/`ThirdPartyNotices`) |
| Local | `E:\repos\onnxruntime-dml\` (wheel, extracted tree; kept outside the repo) |
| Wheel SHA256 | `F2ECB68B7B7B259D2EF3112AE760149F9B5A1E7C0FBB73D539DA6250A648A614` |
| Bytes used | `onnxruntime/capi/onnxruntime.dll` (1.24.4, API 24) + `onnxruntime/capi/DirectML.dll`; the Python `.pyd` is not loaded |
| Runtime probes | `GetVersionString` = `1.24.4`; `GetAvailableProviders` = `DmlExecutionProvider`, `CPUExecutionProvider`; `GetExecutionProviderApi("DML")` returns a non-null `OrtDmlApi` |
| Use | live leg: DML EP append with `device_id=0`, session on the fixture with `session.disable_cpu_ep_fallback=1`, A+B -> C[6,8] exact; suite x2 = 60/60 |
| Host adapter evidence | DXGI `CreateDXGIFactory1`/`EnumAdapters1` enumeration: adapter 0 and 1 = `NVIDIA GeForce RTX 3070 Ti` (vendor `0x10DE`, device `0x2482`, hardware), adapter 2 = `Microsoft Basic Render Driver` (software). DML `device_id` is the 0-based DXGI adapter index, so `device_id=0` targets the RTX 3070 Ti. |
| Policy | policy-clean: MIT wheel fetched from PyPI, extracted outside the repo; nothing vendored or committed |

## 4. Model schema oracle -- onnx/onnx

| Field | Value |
|-------|-------|
| Upstream | https://github.com/onnx/onnx (Apache-2.0) |
| Pin | tag **v1.23.2** = commit `e1ac8e74b620bbdc7ba07f0440806bd93f651a28` |
| File read | `onnx/onnx.proto3` (hosted schema for the fixture model) |
| Use | field numbers/structure for `tests/fixtures/add_f32.onnx` |

## 5. Test fixture -- tests/fixtures/add_f32.onnx

| Field | Value |
|-------|-------|
| Content | 110-byte `Add` model (A[2]+B[2] -> C[2], FLOAT, opset 14, ir_version 7) |
| SHA256 | `DE02E0233188E0CA98666D387D075B6A6B3F5F61BF2F0632898909184451B202` |
| Origin | crafted for this suite from onnx.proto3 @ v1.23.2 (no third-party bytes) |
| Cross-validation | (a) Python onnxruntime **1.14.1** (pre-existing wheel, MIT) loads it and computes [6,8]; (b) the pinned ORT 1.31.0 live leg computes [6,8]; (c) a C smoke oracle (clang 22 + the pinned header) reads metadata producer="xiom.onnx conformance", graph_name="g", domain="", version=INT64_MAX (ORT unset sentinel) |

## 6. Observed third-party runtimes (test environment only, not shipped)

| Runtime | Source | Role |
|---------|--------|------|
| ORT 1.24.4 DirectML | `onnxruntime-directml` wheel (section 3) | primary DML live leg: 60/60 x2 (DML-only session, RTX 3070 Ti) |
| ORT 1.17.1 | Windows 11 inbox `C:\Windows\System32\onnxruntime.dll` (Windows ML) | bare-soname fallback evidence: 60/60 (DML capable) |
| ORT 1.31.0 CPU | official release zip (section 2) | CPU-only SKIP evidence: 59/59 (typed `ONNX_EP_ABSENT`) |
| ORT 1.14.1 | python `onnxruntime` wheel already on the box | fixture cross-validation |

## 7. License check summary

- ONNX Runtime: **MIT** -- loader-only use (no code copied into the
  package; the constant set is factual API metadata). No NOTICE obligations
  triggered by the binding itself; the runtime DLL/wheel stays a
  user-supplied system dependency with its own MIT license.
- onnx/onnx: **Apache-2.0** -- schema consulted only for the fixture byte
  layout; the 110-byte fixture is our own construction.
- No GPL/LGPL/AGPL artifacts were used anywhere in this package.
