# Roadmap -- xiom.tensorrt

## 0.1.0 (shipped, live-verified)

- Loader for `nvinfer_10.dll` with typed `LOAD_ABSENT` / `LOAD_ABI` /
  `VERSION_UNSUPPORTED` classification.
- Builder/runtime factories, application logger plumbing.
- Network definition basics: inputs, identity, Float32 constant, element-wise
  ops, outputs, accessors.
- Builder config: flags, memory pools, tactic sources.
- Build+serialize (`buildSerializedNetwork`), save/load, deserialize from
  memory or file.
- Execution context: `setInputShape`, tensor addresses, `enqueueV3`.
- Engine IO introspection and CUDA driver helpers for a self-contained live
  path.
- Pinned to TensorRT 10.16.1; 8.x acquisition fallback documented but disabled.

## 0.1.x (maintenance)

- Re-pin to 10.16 patch releases after re-verifying the slot map.
- Add a small `trt_engine_io_tensor_info` record helper once the XIOM
  record-with-`Vec` codegen issue is resolved (the shipped helper returns
  names only; per-name accessors cover dtype/mode/location/shape).
- Improve error messages with the TensorRT logger tail on failed builds.
- Add a logger ring buffer (last N messages) instead of only the last message.

## 0.2 (next surface)

- Dynamic shapes with `IOptimizationProfile` creation and multiple profiles.
- ONNX parser (`nvonnxparser_10.dll`) as a separately declared surface.
- Plugin registry enumeration/creator for custom layers.
- Async logger thread and structured severity routing.
- Explicit `setTensorAddress`/`setInputShape` helpers for all IO tensors.

## 0.3 (advanced)

- TensorRT 8.x fallback: `enqueueV2`, `buildEngineWithConfig`,
  `ICudaEngine::serialize`, separate vtable map selected by major/minor.
- Linux: `nvinfer_10.so` loader path and `.so` acquisition docs.
- Refit (`IRefitter`), engine inspector, DLA configuration.
- Multi-device/CUDA context selection and multi-stream execution.
- `IProgressMonitor` for build progress.

## Non-goals

- Bundling or redistributing TensorRT (proprietary SLA).
- Vendoring TensorRT headers, import libraries, or DLLs.
- Reimplementing TensorRT graph compilation or tactic selection in XIOM.
- Cross-vendor GPU abstraction layers.
