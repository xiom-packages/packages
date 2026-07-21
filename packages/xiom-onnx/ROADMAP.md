# xiom-onnx — Roadmap

> **Version:** 0.1.0 | **Spec:** SPEC.md | **Audit:** AUDIT.md

## Phase 1: Core Foundation ✓

| Step | Item | Status |
|------|------|--------|
| 1.1 | `OnnxModel` / `OnnxTensor` / `OnnxConfig` structs | ✓ |
| 1.2 | DType constants (`ORT_DTYPE_*`) | ✓ |
| 1.3 | Graph optimization constants (`ORT_GRAPH_OPT_*`) | ✓ |
| 1.4 | Tensor constructors (`from_vec`, `zeros`) | ✓ |
| 1.5 | Tensor accessors (`to_vec`, `get_name`, `set_name`) | ✓ |
| 1.6 | Image preprocessing stub (`onnx_preprocess_image`) | ✓ |
| 1.7 | Session FFI extern declarations | ✓ |
| 1.8 | Session stubs (`load_model`, `run`, `close`, I/O count) | ✓ |
| 1.9 | Requires contracts on public functions | ✓ |
| 1.10 | Conformance test suite (`test_conformance.xi`) | ✓ |

**Deliverables:** `types.xi`, `io.xi`, `session.xi`, `test_conformance.xi`

---

## Phase 2: Native FFI Bridge

| Step | Item | Status |
|------|------|--------|
| 2.1 | Write C bridge (`src/bridge/ort_c_bridge.c`) | ☐ |
| 2.2 | Link `onnxruntime` shared library | ☐ |
| 2.3 | `onnx_load_model` — create real `OrtSession` | ☐ |
| 2.4 | `onnx_run` — execute inference with `Ort::Run` | ☐ |
| 2.5 | `onnx_get_input_count` / `onnx_get_output_count` — query metadata | ☐ |
| 2.6 | `onnx_close` — release session via `Ort::Release` | ☐ |
| 2.7 | Error propagation — convert ORT status codes to `Result::Err(Str)` | ☐ |
| 2.8 | Add `onnx_load_model` `requires: path.len() > 0` (done) | ✓ |
| 2.9 | Add `onnx_run` `requires: model.session != 0` | ☐ |
| 2.10 | Add `onnx_get_input_count` `requires: model.session != 0` | ☐ |
| 2.11 | Add `onnx_get_output_count` `requires: model.session != 0` | ☐ |

**Deliverables:** `src/bridge/`, working inference, contract hardening

---

## Phase 3: Multi-IO & Providers

| Step | Item | Status |
|------|------|--------|
| 3.1 | `onnx_session_input_name(s, idx)` — query input tensor names | ☐ |
| 3.2 | `onnx_session_output_name(s, idx)` — query output tensor names | ☐ |
| 3.3 | `onnx_available_providers()` — enumerate execution providers | ☐ |
| 3.4 | `onnx_session_set_providers(s, providers)` — select EP | ☐ |
| 3.5 | CUDA provider integration | ☐ |
| 3.6 | TensorRT provider integration | ☐ |
| 3.7 | DirectML provider integration | ☐ |
| 3.8 | CoreML provider integration | ☐ |
| 3.9 | Provider validation via `requires: providers ⊆ available_providers()` | ☐ |
| 3.10 | Multi-input model support | ☐ |

**Deliverables:** Multi-I/O API, GPU execution, provider contracts

---

## Phase 4: Advanced I/O & Dtypes

| Step | Item | Status |
|------|------|--------|
| 4.1 | `onnx_tensor_from_vec_int32` — INT32 tensor constructor | ☐ |
| 4.2 | `onnx_tensor_from_vec_int64` — INT64 tensor constructor | ☐ |
| 4.3 | `onnx_tensor_from_vec_double` — DOUBLE tensor constructor | ☐ |
| 4.4 | `onnx_tensor_from_vec_bool` — BOOL tensor constructor | ☐ |
| 4.5 | `onnx_tensor_to_vec_int32` — INT32 tensor extractor | ☐ |
| 4.6 | `onnx_tensor_to_vec_int64` — INT64 tensor extractor | ☐ |
| 4.7 | `onnx_tensor_to_vec_double` — DOUBLE tensor extractor | ☐ |
| 4.8 | `onnx_tensor_to_vec_bool` — BOOL tensor extractor | ☐ |
| 4.9 | `onnx_tensor_dtype(t)` — query dtype at runtime | ☐ |
| 4.10 | Shape inference (`onnx_session_input_shape`) | ☐ |

**Deliverables:** Full dtype matrix, shape metadata

---

## Phase 5: Vision Pipeline

| Step | Item | Status |
|------|------|--------|
| 5.1 | `onnx_preprocess_image` — real resize/normalize (xiom-opencv) | ☐ |
| 5.2 | Normalize via mean/std vectors | ☐ |
| 5.3 | Channel ordering (RGB/BGR) | ☐ |
| 5.4 | Batch preprocessing (N images → NCHW tensor) | ☐ |
| 5.5 | Image decode from file/memory buffer | ☐ |

**Deliverables:** Production-ready image preprocessing

---

## Phase 6: QA & Release

| Step | Item | Status |
|------|------|--------|
| 6.1 | Full contract verification (`xiom-verify`) | ☐ |
| 6.2 | Safety audit (`xiom-audit-safety`) | ☐ |
| 6.3 | Cross-platform CI (Windows, Linux, macOS) | ☐ |
| 6.4 | Performance benchmarks vs raw C API | ☐ |
| 6.5 | Publish to XIOM package registry | ☐ |
| 6.6 | Release v1.0.0 | ☐ |

| Metric | Current | Target |
|--------|---------|--------|
| Contract count | 8 | 20+ |
| Test count | 24 | 50+ |
| Module count | 3 | 5+ |
| FFI hooks | 0 (stubs) | 6 (live) |

**Deliverables:** v1.0.0 with full FFI, multi-IO, GPU support

---

## Module Contract Tracker

| Module | File | Contracts | Status |
|--------|------|-----------|--------|
| `xiom.onnx.types` | `src/types.xi` | 0 | Public types/consts only |
| `xiom.onnx.io` | `src/io.xi` | 4 | `from_vec`(2), `to_vec`(1), `zeros`(1), `preprocess`(2), `get_name`(1) = 7 total |
| `xiom.onnx.session` | `src/session.xi` | 2 | `load_model`(1), `run`(1) = 2 (will grow in Phase 2) |
| **Total** | | **9** | |

---

## Test Coverage

| Module | Tests | Focus |
|--------|-------|-------|
| `types` | 3 | Config defaults, dtype/graph-opt constants |
| `io` | 12 | Tensor creation, roundtrip, no-alias, name ops, preprocessing |
| `session` | 9 | Load, run, I/O count, close, custom config, end-to-end |
| **Total** | **24** | |

```text
test_onnx_config_default_shape          types
test_dtype_constants                    types
test_graph_opt_constants                types
test_onnx_tensor_from_vec_basic          io
test_onnx_tensor_from_vec_no_alias       io
test_onnx_tensor_to_vec_roundtrip        io
test_onnx_tensor_to_vec_no_alias         io
test_onnx_tensor_zeros_1d                io
test_onnx_tensor_zeros_3d                io
test_onnx_tensor_zeros_shape_not_aliased io
test_onnx_tensor_get_name                io
test_onnx_tensor_set_name                io
test_onnx_preprocess_image_shape         io
test_onnx_preprocess_image_all_zeros     io
test_onnx_load_model_ok                  session
test_onnx_load_model_preserves_path      session
test_onnx_load_model_default_session_zero session
test_onnx_run_ok_on_stub                 session
test_onnx_run_returns_empty_on_stub      session
test_onnx_get_input_count_stub           session
test_onnx_get_output_count_stub          session
test_onnx_close_no_panic                 session
test_onnx_load_model_custom_config       session
test_full_pipeline_end_to_end            session
```
