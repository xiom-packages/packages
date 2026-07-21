# xiom-tensorflow — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC implemented — TESTS GREEN (34 conformance tests), C bridge not linked
**Depends on**: xiom.ffi (stdlib)

## What it wraps
TensorFlow C API (libtensorflow) — Google's ML framework.
Alternative to PyTorch/LibTorch. Larger ecosystem, TF Serving, TF Lite.

## Dependencies

| What | How | Size |
|------|-----|------|
| TensorFlow C library | Download from tensorflow.org. Set `TF_DIR`. | ~500MB |
| CUDA Toolkit (optional) | System-installed for GPU | ~3GB |
| C++ compiler | For building bridge | — |

## Bundling strategy
**System-installed only.** Never bundle (500MB+).

## Implementation status

| File | Purpose | Status |
|------|---------|--------|
| `tensorflow.xi` | Main module — types, extern "C" (16 funcs), safe wrappers, contracts | Done |
| `tests/test_conformance.xi` | 34 conformance tests (types, constants, contracts, stubs, error paths) | Done |
| `ROADMAP.md` | Phased implementation plan | Done |
| C bridge (`tensorflow_bridge.c`) | Native libtensorflow linkage | TODO (Phase 2) |

## API surface (Phase 1 — implemented)

### Types
- `pub type TfSession = Int`
- `pub type TfGraph = Int`
- `pub type TfTensor = Int`
- `pub type TfStatus = Int`

### extern "C" (16 TF C API functions)
`TF_NewSession`, `TF_CloseSession`, `TF_DeleteSession`, `TF_NewGraph`, `TF_DeleteGraph`,
`TF_GraphImportGraphDef`, `TF_NewTensor`, `TF_DeleteTensor`, `TF_TensorData`, `TF_TensorByteSize`,
`TF_SessionRun`, `TF_NewStatus`, `TF_DeleteStatus`, `TF_SetStatus`, `TF_GetCode`, `TF_Message`

### Safe Wrappers with `requires:` contracts
| Function | Contract |
|----------|----------|
| `session_new(graph: TfGraph) -> Result[TfSession, Str]` | `requires: graph != 0` |
| `session_close(session: TfSession)` | `requires: session != 0` |
| `session_delete(session: TfSession)` | `requires: session != 0` |
| `graph_new() -> TfGraph` | `ensures: result != 0` |
| `graph_delete(g: TfGraph)` | `requires: g != 0` |
| `graph_import_graph_def(g, buffer, status) -> Result[Unit, Str]` | `requires: g != 0, buffer != 0, status != 0` |
| `tensor_create(dtype, shape, data) -> Result[TfTensor, Str]` | `requires: data.len()>0, shape.len()>0` |
| `tensor_delete(t: TfTensor)` | `requires: t != 0` |
| `tensor_data(t: TfTensor) -> Int` | `requires: t != 0` |
| `tensor_byte_size(t: TfTensor) -> Int` | `requires: t != 0` |
| `session_run(session, inputs, outputs) -> Result[Vec[TfTensor], Str]` | `requires: session!=0, inputs.len()>0, outputs.len()>0` |
| `load_model(session, path) -> Result[Unit, Str]` | `requires: session!=0, path.len()>0` |
| `status_new() -> TfStatus` | `ensures: result != 0` |
| `status_delete(s: TfStatus)` | `requires: s != 0` |
| `status_get_code(s: TfStatus) -> Int` | `requires: s != 0` |
| `status_is_ok(s: TfStatus) -> Bool` | `requires: s != 0` |
| `status_message(s: TfStatus) -> Str` | `requires: s != 0` |
| `status_set(s, code, msg)` | `requires: s!=0, msg.len()>0` |
| `gpu_available() -> Bool` | stub |
| `gpu_device_count() -> Int` | stub |

### Test Coverage (34 tests)
- **Section 1-2**: Type definitions (4) + error code constants (4)
- **Section 3**: Data type constants (4)
- **Section 4-5**: Status wrappers (3) + Graph wrappers (2)
- **Section 6**: Session wrappers (3)
- **Section 7-8**: Tensor contract enforcement (3) + Session run contracts (2)
- **Section 9**: Model loading contracts (2)
- **Section 10-11**: GPU stubs (2) + Utility (2)
- **Section 12**: Status error paths (3)

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Session, graph, tensor create/run, status, contracts, 34 tests | Done |
| 2 | Native C bridge, SavedModel loading, full op set | Weekend |
| 3 | TF Lite, GPU delegation, TF Serving client | Week |
