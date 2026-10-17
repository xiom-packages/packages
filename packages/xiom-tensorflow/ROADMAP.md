# xiom.tensorflow -- ROADMAP

## Phase 1: Core Foundation -- DONE (superseded by the loader delivery)

The original stub-phase plan (16 `extern "C"` placeholders, 34 tests, "native
bridge not yet linked") is **superseded**: the package now binds a declared
**109-entry** TensorFlow C API surface through a real multi-soname loader and
the conformance suite proves it live against libtensorflow 2.18.1 CPU
(74/74 x2; SKIP leg 17/17). See SPEC.md for the coverage table.

| Deliverable | Status |
|---|---|
| Multi-soname loader (`tf_load`: override + dll/so/so.2/dylib; typed SKIP/ABI/FAIL kinds) | Done |
| Status protocol (`TF_New/Delete/SetStatus`, `GetCode`, `Message`) | Done |
| Named surface resolution (109/109, first-missing named, TF 2.x floor) | Done |
| Graph lifecycle + tensor-shape introspection (`TF_NewGraph`..`GraphSetTensorShape`) | Done |
| Operation construction (`TF_NewOperation`, input/control edges, all `SetAttr*` incl. ValueProto/Placeholder) | Done |
| Operation introspection (names/arity/edges/control/attrs incl. ValueProto/NodeDef) | Done |
| GraphDef export/import (+ options: prefix/device/uniquify/return sets; results tier; input mapping) | Done |
| Tensor lifecycle + typed data (allocate/borrow/bitcast/set-shape/create/read; alignment oracle) | Done |
| Session lifecycle (options incl. ConfigProto, new/close/delete/extend, SavedModel entry) | Done |
| Session execution (`TF_SessionRun` with packed TF_Output/TF_Tensor arrays; exact-FP live) | Done |
| Partial runs (`TF_SessionPRunSetup`/`PRun`/`DeletePRunHandle`) | Done |
| Device enumeration (`TF_SessionListDevices` + 7 readers) | Done |
| ABI seam adapters (16-byte `TF_Output` by value/return per platform; AUDIT) | Done |
| Contract/test discipline: 74 live + 17 SKIP tests, x2 recorded, no silent failures | Done |

## Phase 2: Native integration -- DONE (replaces the "C bridge" plan)

The bridge is the **runtime loader itself** (system-library path, matching
`xiom.ssl` / `xiom.onnx`): nothing is compiled into the package.

- [x] Real resolution of the declared surface against libtensorflow
- [x] `tf_session_load_saved_model` (typed-absent path verified; fixture-based
      success path deferred, see AUDIT residual risks)
- [x] Full `session_run` marshalling (inputs/outputs, targets slot reserved)
- [x] Tensor data extraction (`tf_tensor_read_f32`/`_i32`, plus typed
      `tf_tensor_create_*` writers)

## Phase 3: High-Level API -- DONE

- [x] `op_placeholder`, `op_const_f32`/`_i32`, `op_add`, `op_matmul`, `op_relu`
      (plus `op_identity`; all live-verified with exact values, incl. `AddN`,
      `Unpack`, `Conv2D`, `LeakyRelu`, `Neg` via the graph tier)
- [x] `saved_model_load` entry point (typed contract; success needs a fixture)
- [ ] `saved_model_run` convenience (fetch/serve signature discovery) -- open
- [ ] GPU detection beyond `TF_SessionListDevices` type strings -- open

## Phase 4: Ecosystem (future)

- TF Lite bindings (separate package)
- TF Serving client (gRPC)
- Model zoo downloader + cache
