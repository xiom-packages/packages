# xiom.tensorflow -- ROADMAP

## Phase 1: Core Foundation (CURRENT)
**Status:** SPEC implemented, tests pass, native bridge not yet linked.

| Deliverable | Status |
|---|---|
| `tensorflow.xi` -- types, extern "C" block (16 functions), safe wrappers | Done |
| `tests/test_conformance.xi` -- 34 conformance tests | Done |
| Status management (`status_new`, `status_get_code`, `status_set`, `status_message`) | Done |
| Graph lifecycle (`graph_new`, `graph_delete`, `graph_import_graph_def`) | Done |
| Session lifecycle (`session_new`, `session_close`, `session_delete`) | Done |
| Tensor lifecycle (`tensor_create`, `tensor_delete`, `tensor_data`, `tensor_byte_size`) | Done |
| Session execution (`session_run`) | Done |
| Model loading (`load_model`) -- stub | Done |
| GPU queries (`gpu_available`, `gpu_device_count`) -- stubs | Done |
| Contract enforcement: `requires:` clauses on all safe wrappers | Done |

## Phase 2: Native C Bridge (planned)
- Implement C bridge against `libtensorflow.so` / `tensorflow.dll`
- Resolve extern "C" stubs to real TF C API calls
- `load_model` -- real SavedModel/GraphDef loading from disk
- Full `session_run` with input/output tensor marshalling
- Tensor data extraction (`tensor_data` -> XIOM `Vec[Float32]`)

## Phase 3: High-Level API (planned)
- `op_placeholder`, `op_const`, `op_add`, `op_matmul`, `op_relu`
- `saved_model_load`, `saved_model_run`
- CUDA GPU support via `gpu_available` / `gpu_device_count` detection

## Phase 4: Ecosystem (future)
- TF Lite bindings (xc-xiom-tensorflow-lite)
- TF Serving client
- Model zoo downloader + cache
