# xiom.tensorrt -- Specification 0.1.0

Status: incubating; live-verified 2026-10-17 on Windows x64.
Package namespace: `xiom.tensorrt`. Module: `xiom.tensorrt`. Compiler: v0.64.6.

## 1. Identity and scope

`xiom.tensorrt` exposes the essentials of the NVIDIA TensorRT inference
workflow to XIOM:

1. create an inference builder and runtime;
2. install an application logger;
3. define a network (inputs, identity/constant/element-wise layers, outputs);
4. configure the builder (flags, memory pools, tactic sources);
5. build and serialize a plan;
6. deserialize a plan into an engine;
7. create an execution context, bind tensor addresses, enqueue `V3`, and query
   versions/IO metadata.

The package is **loader-only**. It ships no NVIDIA header, import library,
DLL, or other NVIDIA artifact. The runtime is user-supplied under the NVIDIA
SLA. The loader resolves `nvinfer_10.dll` at run time; the C++ bridge contains
independent declarations of the pinned TensorRT 10.16 interface facts.

## 2. Version pin

| Item | Pin |
|---|---|
| TensorRT major | **10** (10.16.x only in 0.1.0) |
| Runtime wheel | `tensorrt-cu12-libs` **10.16.1.11** (Windows x64, 2,206,065,494 bytes) |
| Runtime version returned by `getInferLibVersion` | `101601` = 10.16.1 |
| ABI/source headers | `NVIDIA/TensorRT` tag `v10.16`, commit `52399f555c2f80cb690a4a558b604e1a5f227e7c`, headers version 10.16.0.72 (reference only) |
| Bridge language | C++17, compiled by the XIOM toolchain (`--cxx-standard 17`) |
| Compiler | v0.64.6 |
| Stdlib range | `>=0.60.0 <1.0.0` |
| CUDA UMD on the verified host | 13.4 (driver 616.92), GPU compute capability 8.6 |

The runtime loader checks the major **and** minor and returns
`TRT_VERSION_UNSUPPORTED` for anything other than 10.16.x. The 8.x
`enqueueV2` fallback is a documented acquisition alternative, not an enabled
code path in 0.1.0.

## 3. Pinned ABI facts (TensorRT 10.16)

TensorRT 10.16 public interfaces are **non-virtual wrappers**. Each returned
interface pointer points at:

```
+------+----------------------------+
| vptr | apiv::V* mImpl  (byte 8)   |
+------+----------------------------+
```

`mImpl` is read at byte 8; the bridge then dispatches pure virtual methods on
the implementation vtable. The wrapper is released with `operator delete`
(the 10.16 headers document `operator delete`, not `destroy()`). Slot 0 is the
virtual destructor inherited from `VRoot`; the first declared method is slot 1.

Two ABI details are easy to get wrong and are fixed here:

- **Large by-value returns.** `Dims` is 72 bytes (`int32 nbDims` + 8 × `int64`
  extents). A member function returning it uses **RCX = this, RDX = hidden
  return slot** in the MSVC x64 ABI. The bridge declares such calls as
  `void (*)(void* self, Dims* out, ...)` so the register assignment matches.
  This applies to `VTensor::getDimensions` and `VCudaEngine::getTensorShape`.
- **`Weights` field order.** `Weights` is `{ DataType type; void const* values;
  int64_t count; }` (24 bytes), not `{values, type, count}`.

### 3.1 C entry points

Resolved with `GetProcAddress`:

| Symbol | Signature |
|---|---|
| `getInferLibVersion` | `int32_t()` |
| `createInferBuilder_INTERNAL` | `void*(void* logger, int32_t version)` |
| `createInferRuntime_INTERNAL` | `void*(void* logger, int32_t version)` |

The application logger is a C++ object whose vtable slot 0 is
`log(int32_t severity, char const* message)`. Slots 1+ (destructor) are never
called by TensorRT. Logging is mutex-protected and bounded to the last message.

### 3.2 Vtable slot map

All indices below are pinned to 10.16.1 and verified by the live suite.

| Interface | Method | Slot |
|---|---|---:|
| VBuilder | `platformHasFastFp16` | 1 |
| VBuilder | `platformHasFastInt8` | 2 |
| VBuilder | `createBuilderConfig` | 6 |
| VBuilder | `createNetworkV2` | 7 |
| VBuilder | `platformHasTf32` | 12 |
| VBuilder | `buildSerializedNetwork` | 13 |
| VNetworkDefinition | `addInput` | 1 |
| VNetworkDefinition | `markOutput` | 2 |
| VNetworkDefinition | `addElementWise` | 8 |
| VNetworkDefinition | `getNbLayers` | 11 |
| VNetworkDefinition | `getLayer` | 12 |
| VNetworkDefinition | `getNbInputs` | 13 |
| VNetworkDefinition | `getInput` | 14 |
| VNetworkDefinition | `getNbOutputs` | 15 |
| VNetworkDefinition | `getOutput` | 16 |
| VNetworkDefinition | `addConstant` | 22 |
| VNetworkDefinition | `addIdentity` | 23 |
| VBuilderConfig | `clearFlag` (void) | 9 |
| VBuilderConfig | `setFlag` (void) | 10 |
| VBuilderConfig | `getFlag` (bool) | 11 |
| VBuilderConfig | `setTacticSources` | 37 |
| VBuilderConfig | `getTacticSources` | 38 |
| VBuilderConfig | `setMemoryPoolLimit` | 42 |
| VBuilderConfig | `getMemoryPoolLimit` | 43 |
| VHostMemory | `data` | 1 |
| VHostMemory | `size` | 2 |
| VHostMemory | `type` | 3 |
| VRuntime | `deserializeCudaEngine(void const*, size_t)` | 3 |
| VCudaEngine | `createExecutionContext` | 4 |
| VCudaEngine | `getTensorShape` (sret) | 18 |
| VCudaEngine | `getTensorDataType` | 19 |
| VCudaEngine | `getTensorLocation` | 20 |
| VCudaEngine | `getTensorIOMode` | 22 |
| VCudaEngine | `getNbIOTensors` | 29 |
| VCudaEngine | `getIOTensorName` | 30 |
| VExecutionContext | `allInputDimensionsSpecified` | 11 |
| VExecutionContext | `setInputShape` | 20 |
| VExecutionContext | `setTensorAddress` | 23 |
| VExecutionContext | `getTensorAddress` | 24 |
| VExecutionContext | `enqueueV3` | 36 |
| VTensor | `setName` | 1 |
| VTensor | `getName` | 2 |
| VTensor | `getDimensions` (sret) | 4 |
| VTensor | `getType` | 6 |
| VTensor | `isNetworkInput` | 8 |
| VTensor | `isNetworkOutput` | 9 |
| VLayer | `getType` | 1 |
| VLayer | `getName` | 3 |
| VLayer | `getOutput` | 7 |

Note that `IBuilderConfig::setFlag(flag, bool)` does **not** exist in 10.16:
the implementation exposes `setFlag(flag)` and `clearFlag(flag)` as separate
void methods. The XIOM API keeps the boolean form and dispatches to the correct
method.

## 4. Declared surface (88 public functions)

Handles are opaque `Int` values (> 0). Tensors/layers are borrowed; all other
handles are owned and must be destroyed. Fallible calls return
`Result[T, TrtError]`.

### 4.1 Loader / version (5)

```
trt_probe() -> Result[TrtInfo, TrtError]
trt_probe_named(dll: Str) -> Result[TrtInfo, TrtError]
trt_close() -> Int
trt_loaded() -> Bool
trt_version() -> Result[TrtVersion, TrtError]
```

`TrtInfo` = `{ dll, abi, enqueue, version: TrtVersion, symbols_resolved,
symbols_required }`; `TrtVersion` = `{ raw, major, minor, patch, build }`.

### 4.2 Logger plumbing (7)

```
trt_logger_create(severity) -> Result[Int, TrtError]
trt_logger_destroy(id)
trt_logger_set_severity(id, severity) -> Result[Int, TrtError]
trt_logger_severity(id) -> Result[Int, TrtError]
trt_logger_message_count(id) -> Result[Int, TrtError]
trt_logger_last_message(id) -> Result[Str, TrtError]
trt_logger_last_severity(id) -> Result[Int, TrtError]
```

Severity constants: `TRT_SEVERITY_INTERNAL_ERROR` (0) .. `TRT_SEVERITY_VERBOSE`
(4).

### 4.3 Builder (8)

```
trt_builder_create(logger) -> Result[Int, TrtError]
trt_builder_destroy(id)
trt_builder_platform_has_fp16(id) -> Result[Bool, TrtError]
trt_builder_platform_has_int8(id) -> Result[Bool, TrtError]
trt_builder_platform_has_tf32(id) -> Result[Bool, TrtError]
trt_builder_create_network(id) -> Result[Int, TrtError]
trt_builder_create_config(id) -> Result[Int, TrtError]
trt_builder_build_serialized(builder, network, config) -> Result[Int, TrtError]
```

`build_serialized` is the TensorRT 10 build+serialize path; it returns an
`IHostMemory` plan handle.

### 4.4 Network definition (14)

```
trt_network_add_input(net, name, dtype, d0..d7, ndim) -> Result[Int, TrtError]
trt_network_add_input_2d(net, name, dtype, d0, d1) -> Result[Int, TrtError]
trt_network_add_identity(net, input) -> Result[Int, TrtError]
trt_network_add_constant_f32(net, value, d0..d7, ndim) -> Result[Int, TrtError]
trt_network_add_constant_f32_2d(net, value, d0, d1) -> Result[Int, TrtError]
trt_network_add_elementwise(net, op, a, b) -> Result[Int, TrtError]
trt_network_mark_output(net, tensor) -> Result[Int, TrtError]
trt_network_nb_layers(net) -> Result[Int, TrtError]
trt_network_nb_inputs(net) -> Result[Int, TrtError]
trt_network_nb_outputs(net) -> Result[Int, TrtError]
trt_network_input(net, index) -> Result[Int, TrtError]
trt_network_output(net, index) -> Result[Int, TrtError]
trt_network_layer(net, index) -> Result[Int, TrtError]
trt_network_destroy(net)
```

`add_identity`/`add_constant_f32`/`add_elementwise` return the layer's output
tensor. The bridge keeps constant weights alive until the network is destroyed
(TensorRT holds weights by reference until build). `ndim` is 0..8; `-1` marks a
dynamic extent. `TRT_ELEMENTWISE_*` covers SUM..FLOOR_DIV (0..7).

### 4.5 Tensor / layer (10)

```
trt_tensor_set_name(tensor, name) -> Result[Int, TrtError]
trt_tensor_name(tensor) -> Result[Str, TrtError]
trt_tensor_dtype(tensor) -> Result[Int, TrtError]
trt_tensor_ndim(tensor) -> Result[Int, TrtError]
trt_tensor_dim(tensor, index) -> Result[Int, TrtError]
trt_tensor_dims(tensor) -> Result[Vec[Int], TrtError]
trt_tensor_is_input(tensor) -> Result[Bool, TrtError]
trt_tensor_is_output(tensor) -> Result[Bool, TrtError]
trt_layer_type(layer) -> Result[Int, TrtError]
trt_layer_name(layer) -> Result[Str, TrtError]
```

### 4.6 Builder config (7)

```
trt_config_set_flag(config, flag, value: Bool) -> Result[Int, TrtError]
trt_config_get_flag(config, flag) -> Result[Bool, TrtError]
trt_config_set_memory_pool_limit(config, pool, bytes) -> Result[Int, TrtError]
trt_config_memory_pool_limit(config, pool) -> Result[Int, TrtError]
trt_config_set_tactic_sources(config, mask) -> Result[Int, TrtError]
trt_config_tactic_sources(config) -> Result[Int, TrtError]
trt_config_destroy(config)
```

`TRT_FLAG_*` (0..7) and `TRT_POOL_*` (0..4) constants are exported. `set_flag`
with `value=false` calls `clearFlag`; this distinction is required on 10.16.

### 4.7 Serialized plans (5)

```
trt_host_memory_size(host) -> Result[Int, TrtError]
trt_host_memory_data(host) -> Result[Int, TrtError]
trt_host_memory_save(host, path) -> Result[Int, TrtError]
trt_host_memory_load(path) -> Result[Int, TrtError]
trt_host_memory_destroy(host)
```

`data` is a borrowed address valid until the handle is destroyed. `load`
returns a file-backed handle that can be passed to
`trt_runtime_deserialize_memory`.

### 4.8 Runtime / engine (15)

```
trt_runtime_create(logger) -> Result[Int, TrtError]
trt_runtime_destroy(runtime)
trt_runtime_deserialize(runtime, data_addr, size) -> Result[Int, TrtError]
trt_runtime_deserialize_memory(runtime, host) -> Result[Int, TrtError]
trt_engine_destroy(engine)
trt_engine_nb_io_tensors(engine) -> Result[Int, TrtError]
trt_engine_io_tensor_name(engine, index) -> Result[Str, TrtError]
trt_engine_tensor_dtype(engine, name) -> Result[Int, TrtError]
trt_engine_tensor_location(engine, name) -> Result[Int, TrtError]
trt_engine_tensor_io_mode(engine, name) -> Result[Int, TrtError]
trt_engine_tensor_ndim(engine, name) -> Result[Int, TrtError]
trt_engine_tensor_dim(engine, name, index) -> Result[Int, TrtError]
trt_engine_tensor_dims(engine, name) -> Result[Vec[Int], TrtError]
trt_engine_create_context(engine) -> Result[Int, TrtError]
trt_engine_io_tensor_names(engine) -> Result[Vec[Str], TrtError]
```

### 4.9 Execution context (6)

```
trt_context_destroy(ctx)
trt_context_set_input_shape(ctx, name, d0..d7, ndim) -> Result[Int, TrtError]
trt_context_set_tensor_address(ctx, name, addr) -> Result[Int, TrtError]
trt_context_tensor_address(ctx, name) -> Result[Int, TrtError]
trt_context_all_input_dims_specified(ctx) -> Result[Bool, TrtError]
trt_context_enqueue(ctx, stream) -> Result[Int, TrtError]
```

`trt_context_enqueue` dispatches `enqueueV3` on 10.16. The stream argument is a
handle from `trt_cuda_stream_create`, not a raw `cudaStream_t`.

### 4.10 CUDA driver helpers (11)

```
trt_cuda_init() -> Result[Int, TrtError]
trt_cuda_shutdown() -> Int
trt_cuda_alloc(bytes) -> Result[Int, TrtError]
trt_cuda_free(ptr)
trt_cuda_upload(dev, src, bytes) -> Result[Int, TrtError]
trt_cuda_download(dst, dev, bytes) -> Result[Int, TrtError]
trt_cuda_stream_create() -> Result[Int, TrtError]
trt_cuda_stream_destroy(stream)
trt_cuda_stream_sync(stream) -> Result[Int, TrtError]
trt_cuda_device_name() -> Result[Str, TrtError]
trt_cuda_device_count() -> Result[Int, TrtError]
```

`trt_cuda_init` must run **before** `trt_builder_create`: TensorRT executes on
the current CUDA context. The helper retains and activates the primary context
and re-activates it before builder/deserialize/context/enqueue calls.

## 5. Error model

`TrtError` = `{ kind: Int; message: Str }`.

| Kind | Meaning | Test treatment |
|---|---|---|
| `TRT_OK` (0) | no error | -- |
| `TRT_LOAD_ABSENT` (1) | loader/module missing | SKIP |
| `TRT_LOAD_ABI` (2) | module present, entry points missing | FAIL |
| `TRT_VERSION_UNSUPPORTED` (3) | runtime is not 10.16.x | SKIP/FAIL, explicit |
| `TRT_NO_DEVICE` (4) | `cuInit`/device unavailable | SKIP |
| `TRT_CALL_FAILED` (5) | TensorRT returned null/false | FAIL |
| `TRT_BAD_HANDLE` (6) | stale/foreign handle | FAIL |
| `TRT_INVALID_ARG` (7) | bridge-level argument rejection | FAIL |
| `TRT_IO_FAILED` (8) | plan file read/write | FAIL |
| `TRT_CUDA_FAILED` (9) | CUDA driver call failed | SKIP on init, FAIL later |
| `TRT_UNSUPPORTED` (10) | reserved for disabled paths | FAIL |

No C++ exception escapes the C ABI: every bridge entry point is wrapped in
`try/catch (...)`. `trt_last_error_kind`/`trt_last_error_message` are cleared at
the start of each bridge call; XIOM wrappers translate a non-zero kind into
`Err` before inspecting sentinel values.

## 6. Safety and ownership boundary

- All `extern "C"` declarations and every `unsafe` block are confined to
  `tensorrt.xi`; public callers never see a raw pointer.
- The bridge is one C++17 translation unit (`src/trt_bridge.cpp`), built by the
  toolchain as `--c-source`; it includes no NVIDIA header and links no NVIDIA
  import library.
- Handle registry: monotonic ids, kind-checked, owner-tracked for borrowed
  tensors/layers. `trt_close` destroys contexts → engines → host buffers →
  configs → networks → builders → runtimes → loggers → streams.
- Logger lifetime: builders/runtimes hold a `shared_ptr` to the logger, so
  `trt_logger_destroy` cannot leave a dangling callback.
- Weights lifetime: constant weights are stored in the network entry until the
  network is destroyed.
- CUDA lifetime: allocations and streams are tracked; `trt_cuda_shutdown`
  frees leftovers and releases the primary context.
- `trt_close` releases TensorRT objects and unloads the module; CUDA has its
  own `trt_cuda_shutdown`. Call both at the end.

## 7. Out of scope (0.1.0)

- ONNX parser (`nvonnxparser`), UFF parser, plugin registry/creator.
- Optimization profile creation and multi-profile dynamic shapes.
- Refit, DLA, multi-device, graph safety, progress monitors.
- `enqueueV2` / TensorRT 8.x; 8.x is documented as an acquisition fallback only.
- Linux/macOS loader paths (`nvinfer_10.so`); the bridge is Windows x64 only.
- Thread safety per handle set.

## 8. Test contract

`tests/test_conformance.xi` always runs the deterministic SKIP-path check
(`trt_probe_named` with a bogus DLL name). It then initialises CUDA; if CUDA or
the TensorRT module is absent, it prints a typed SKIP and exits 0. On a live
host it performs 55 checks:

- loader: version 10.16.1, 3/3 entry points, `enqueue == "v3"`, loaded flag;
- logger: severity round trip, message capture, last message;
- builder: FP16/INT8/TF32 platform queries;
- network: input [1,4], constant 2.0, element-wise PROD, output naming,
  layer/input/output counts and accessors;
- config: DEBUG flag set/clear, workspace pool default/set, tactic sources;
- build: plan > 0 bytes, save/load size equality;
- runtime: deserialize from memory and from the file-backed plan;
- engine: 2 IO tensors, names, dtype/mode/location, [1,4] shapes;
- context: all-input-dims, `setInputShape`, address set/get;
- live: device buffers, H2D, `enqueueV3`, sync, D2H, result `[2,4,6,8]` exactly;
- cleanup: ordered teardown, module unloaded.

Evidence: 55/55 live twice on 2026-10-17; 2/2 SKIP without
`XIOM_TENSORRT_DIR`. See [`AUDIT.md`](AUDIT.md).

## 9. Re-pinning procedure

1. Fetch the new runtime wheel and record its SHA-256 in `PROVENANCE.md`.
2. Fetch the matching `NVIDIA/TensorRT` headers; verify the wrapper layout,
   `Dims`/`Weights` layout, and every slot in §3.2 against the new
   `NvInferImpl.h`.
3. Update `slot::` constants and the version gate in `src/trt_bridge.cpp`.
4. Update the pin table here and in `README.md`.
5. Run `scripts/port.ps1 -Package xiom.tensorrt -TimeoutSec 300` twice on a live
   host and once without the runtime (SKIP gate).
6. Update `STATUS.json` with the new commit and counts.

## 10. License

Package: MIT OR Apache-2.0. TensorRT runtime: NVIDIA Software License
Agreement (proprietary, user-supplied, not redistributed). TensorRT reference
headers: Apache-2.0, not redistributed. See [`PROVENANCE.md`](PROVENANCE.md).
