# xiom.onnx -- Roadmap

> **Version:** 0.1.0 (unreleased) | **Spec:** SPEC.md | **Audit:** AUDIT.md
> **Lane:** bindings (ML/AI wave 2026-10-16) | **Compiler pin:** v0.64.5

## Phase 1: Core Foundation [DONE]

| Step | Item | Status |
|------|------|--------|
| 1.1 | `OnnxModel` / `OnnxTensor` / `OnnxConfig` structs | [DONE] |
| 1.2 | DType constants (`ORT_DTYPE_*`, full 0..26 oracle set) | [DONE] |
| 1.3 | Graph optimization constants (`ORT_GRAPH_OPT_*` incl. LAYOUT) | [DONE] |
| 1.4 | Tensor constructors (`from_vec`, `zeros`) | [DONE] |
| 1.5 | Tensor accessors (`to_vec`, `get_name`, `set_name`) | [DONE] |
| 1.6 | Image preprocessing stub (`onnx_preprocess_image`) | [DONE] (stub tier kept; real resize is Phase 5) |
| 1.7 | Session FFI extern declarations | [DONE] (replaced by the dl-based loader) |
| 1.8 | Session stubs (`load_model`, `run`, `close`, I/O count) | [DONE] (now real -- see Phase 2) |
| 1.9 | Requires contracts on public functions | [DONE] |
| 1.10 | Conformance test suite (`test_conformance.xi`) | [DONE] |

## Phase 2: Native FFI Bridge [DONE -- as a pure-XIOM C API binding]

Design deviation (docs/UPSTREAM-FIRST.md): instead of a hand-written C
bridge compiled per platform, the package binds the **stable ORT C API**
directly through `xiom.ffi.dl` + the versioned `OrtApi` table
(`OrtGetApiBase` -> `GetApi`). Same outcomes, no bridge object, no
build-time linking, typed SKIP when the runtime is absent.

| Step | Item | Status |
|------|------|--------|
| 2.1 | C bridge (`src/bridge/ort_c_bridge.c`) | NOT NEEDED -- superseded by the API-table binding (loader.xi) |
| 2.2 | Link `onnxruntime` shared library | NOT NEEDED -- `dlopen`/`LoadLibrary` at run time (multi-soname candidate list) |
| 2.3 | `onnx_load_model` -- create real OrtSession | [DONE] (wide-path + from-array paths) |
| 2.4 | `onnx_run` -- execute inference | [DONE] (`Run` + `RunWithBinding`, exact [6,8] on the fixture) |
| 2.5 | `onnx_get_input_count` / `onnx_get_output_count` | [DONE] |
| 2.6 | `onnx_close` -- release session | [DONE] (session -> env -> dl handle) |
| 2.7 | Error propagation -- ORT status codes to `Result::Err` | [DONE] (`ONNX_CALL_FAILED` carries OrtErrorCode name + message) |
| 2.8 | `requires: path.len() > 0` on `onnx_load_model` | [DONE] |
| 2.9-2.11 | Handle contracts on run/IO count | [DONE] (`requires: model.session != 0`) |

## Phase 3: Multi-IO & Providers [DONE -- at the C API level]

| Step | Item | Status |
|------|------|--------|
| 3.1 | `onnx_session_input_name(s, idx)` | [DONE] (+ bulk `onnx_session_input_names`) |
| 3.2 | `onnx_session_output_name(s, idx)` | [DONE] (+ bulk `onnx_session_output_names`) |
| 3.3 | `onnx_available_providers()` | [DONE] (`onnx_available_providers(lib)`) |
| 3.4 | `onnx_session_set_providers(s, providers)` | [DONE] as `onnx_options_append_provider` (generic EP appender; typed rejection of unknown names) |
| 3.5-3.8 | CUDA / TensorRT / DML / CoreML integration | VIA RUNTIME -- selectable by name when the runtime build ships the EP; the CPU package is the pinned live leg |
| 3.9 | Provider validation | [DONE] (unknown name -> typed error; available list readable) |
| 3.10 | Multi-input model support | [DONE] (fixture is 2-input `Add`; `Run` takes name+value vectors) |

## Phase 4: Advanced I/O & Dtypes [PARTIAL -- binding level delivered]

| Step | Item | Status |
|------|------|--------|
| 4.1-4.8 | INT32/INT64/DOUBLE/BOOL tensor constructors/extractors | PARTIAL -- the C API tensor layer (`onnx_value_tensor_new`/`from_data`, `onnx_value_read_f32`/`write_f32`, dtype parameter) already spans dtypes; dedicated typed Vec helpers for INT/DOUBLE/BOOL remain |
| 4.9 | `onnx_tensor_dtype(t)` | [DONE] (`onnx_tensor_info_element_type`, `onnx_value_type`) |
| 4.10 | Shape inference | [DONE -- read side] (`onnx_tensor_info_dims` / `_dims_count` / `_symbolic_dims` / `_shape_count`) |

## Phase 5: Vision Pipeline [FUTURE]

| Step | Item | Status |
|------|------|--------|
| 5.1 | Real resize/normalize (xiom.opencv) | [ ] |
| 5.2-5.5 | mean/std, channel order, batching, decode | [ ] |

## Phase 6: QA & Release [PARTIAL]

| Step | Item | Status |
|------|------|--------|
| 6.1 | Full contract verification (`xiom-verify`) | [ ] (deferred to the release wave) |
| 6.2 | Safety audit | PARTIAL -- unsafe confined to call sites; see AUDIT.md |
| 6.3 | Cross-platform CI | WINDOWS live-verified (2 runtime versions); Linux/macOS sonames in the loader candidate list |
| 6.4 | Performance benchmarks | [ ] |
| 6.5 | Publish to XIOM registry | [ ] |
| 6.6 | Release v1.0.0 | [ ] |

| Metric | 0.1.0 stub | Now | Target |
|--------|-----------|-----|--------|
| Declared C API coverage | 0 (stubs) | 97/97 (95 OrtApi + 2 OrtApiBase) | 97/97 |
| Contracts (`requires:`) | 9 | 254 | 260+ |
| Test count | 24 | 56 (x2 green) | 50+ |
| Module count | 3 | 6 | 5+ |
| FFI hooks | 0 (stubs) | 97 live table slots | 97 |

## Module Contract Tracker

| Module | File | Contracts (`requires:`) | Status |
|--------|------|------------------------|--------|
| `xiom.onnx.types` | `src/types.xi` | 0 | Public types/consts only (pure) |
| `xiom.onnx.loader` | `src/loader.xi` | 22 | 14 pub fns; multi-soname loader + 95-slot surface |
| `xiom.onnx.env` | `src/env.xi` | 9 | 6 pub fns; env + telemetry + providers |
| `xiom.onnx.value` | `src/value.xi` | 70 | 34 pub fns; values/tensors/type-info/memory/allocators |
| `xiom.onnx.session` | `src/session.xi` | 146 | 61 pub fns; options/session/metadata/run-options/Run/IoBinding/high-level |
| `xiom.onnx.tensor` | `src/tensor.xi` | 7 | 6 pub fns; pure-XIOM tier (was `xiom.onnx.io`) |
| **Total** | | **254** | 124 public functions |

## Test Coverage

| Suite section | Tests | Focus |
|---------------|-------|-------|
| `types` | 6 | config, dtype table (0..26), graph-opt/levels, error codes, sizes, names |
| `tensor` (pure) | 11 | constructors, no-alias, roundtrips, name ops, preprocessing stub |
| `loader` | 4 | surface alignment (95), version parsing, candidate order, deterministic SKIP probe |
| `live: env/status/providers` | 4 | probe (version/api/surface), status trio, telemetry, provider enumeration |
| `live: memory/allocators` | 3 | cpu memory info fields, allocator info, alloc/free blocks |
| `live: tensors` | 5 | create/is/data-ptr, write/read exact, value semantics + typed failures, type/shape info, borrowed-buffer aliasing |
| `live: session/options/metadata` | 10 | 13 option setters, config+EP append (typed rejection), wide-path + array sessions, counts/names (per-index + bulk), type info, metadata |
| `live: run` | 3 | run options roundtrip, exact Add [6,8], typed bogus-input error |
| `live: io-binding` | 2 | device-output roundtrip + clear, preallocated-output aliasing + typed error |
| `live: session-owned allocator` | 1 | CreateAllocator alloc/free + release |
| `live: error paths` | 2 | corrupted model bytes typed error, fixture byte-count check |
| `live: high-level API` | 4 | load_model + counts/names, onnx_run exact, missing-file error, end close |
| **Total** | **56** | `port.ps1` x2 = 56/56 (pinned ORT 1.31.0) + bare ORT 1.17.1 56/56 |
