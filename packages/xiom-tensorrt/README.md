# xiom.tensorrt 0.1.0

NVIDIA TensorRT 10.x bindings for XIOM. **Loader-only:** nothing from NVIDIA
is vendored, linked at build time, or shipped. The user supplies the TensorRT
runtime; the package resolves it at run time and classifies absence as a typed
SKIP.

- **Pinned runtime:** TensorRT **10.16.1** (pip wheel `tensorrt-cu12-libs`
  **10.16.1.11**, Windows x64)
- **Pinned ABI:** TensorRT 10.16 public interface facts (vtable slot map in
  [`SPEC.md`](SPEC.md) §3)
- **Headers:** not required to build this package. `NVIDIA/TensorRT` tag
  `v10.16` (10.16.0.72) is the reference used to derive the interface facts.
- **Status:** incubating, live-verified on an RTX 3070 Ti (driver 616.92 /
  CUDA UMD 13.4), 55/55 checks, suites run twice.

The 8.x fallback is documented in [`ROADMAP.md`](ROADMAP.md) but **not enabled**
in 0.1.0: the 10.x wheel is available and works, so the bridge pins 10.16 and
rejects other majors/minors instead of guessing an incompatible vtable.

## What you get

| Group | Functions |
|---|---|
| Loader / version | `trt_probe`, `trt_probe_named`, `trt_version`, `trt_loaded`, `trt_close` |
| Logger plumbing | create/destroy, severity, message count, last message/severity |
| Builder | create/destroy, FP16/INT8/TF32 platform queries, network/config creation, build+serialize |
| Network definition | addInput (0..8-D), identity, Float32 constant, element-wise op, markOutput, input/output/layer accessors |
| Builder config | flags (set/clear via `value: Bool`), memory-pool limits, tactic sources |
| Serialized plans | size/data, save/load, destroy |
| Runtime / engine | create/destroy, deserialize from memory or file plan, IO tensor names/types/modes/locations/shapes, create execution context |
| Execution context | setInputShape, set/get tensor address, all-input-dims query, `enqueueV3` |
| CUDA helpers | init/shutdown, device alloc/free, H2D/D2H copy, stream create/destroy/sync, device name/count |

All 88 public functions are documented in [`SPEC.md`](SPEC.md) §4. Every
fallible call returns `Result[..., TrtError]`; errors are typed by
`TRT_LOAD_ABSENT`, `TRT_LOAD_ABI`, `TRT_VERSION_UNSUPPORTED`, `TRT_NO_DEVICE`,
`TRT_CALL_FAILED`, `TRT_BAD_HANDLE`, `TRT_INVALID_ARG`, `TRT_IO_FAILED`,
`TRT_CUDA_FAILED`, and `TRT_UNSUPPORTED`.

## Acquiring the runtime (user-supplied; NVIDIA EULA)

TensorRT is proprietary NVIDIA software under the **NVIDIA Software License
Agreement**. The package does not redistribute it. Download and accept the
license yourself:

```powershell
# 2.2 GB wheel; Windows x64, TensorRT 10.16.1
curl.exe -L -o E:\repos\tensorrt\tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl `
  https://pypi.nvidia.com/tensorrt-cu12-libs/tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl
tar -xf E:\repos\tensorrt\tensorrt_cu12_libs-10.16.1.11-py3-none-win_amd64.whl -C E:\repos\tensorrt\wheel

$env:XIOM_TENSORRT_DIR = "E:\repos\tensorrt\wheel\tensorrt_libs"
```

`XIOM_TENSORRT_DIR` may be a directory (the bridge appends `nvinfer_10.dll`) or
a full DLL path. Without it the loader tries `nvinfer_10.dll`, then
`nvinfer.dll` on the normal search path. A missing module is reported as
`TRT_LOAD_ABSENT` (SKIP), not as a test failure.

The wheel is headerless. The ABI reference headers were fetched separately from
[`NVIDIA/TensorRT` `v10.16`](https://github.com/NVIDIA/TensorRT/tree/v10.16/include)
(Apache-2.0) into `E:\repos\tensorrt\include` for study only; they are **not**
vendored and are **not** needed to build this package. See
[`PROVENANCE.md`](PROVENANCE.md) for hashes and the derivation.

## Quick start

```xiom
use xiom.tensorrt;

let cu = trt_cuda_init();                 // before the builder: current context
let p = trt_probe();                       // typed SKIP if the runtime is absent
let logger = trt_logger_create(TRT_SEVERITY_WARNING).value;
let builder = trt_builder_create(logger).value;
let network = trt_builder_create_network(builder).value;
let config = trt_builder_create_config(builder).value;

let input = trt_network_add_input_2d(network, "input", TRT_DTYPE_FLOAT, 1, 4).value;
let constant = trt_network_add_constant_f32_2d(network, 2.0, 1, 4).value;
let output = trt_network_add_elementwise(network, TRT_ELEMENTWISE_PROD, input, constant).value;
let _ = trt_tensor_set_name(output, "output");
let _ = trt_network_mark_output(network, output);

let plan = trt_builder_build_serialized(builder, network, config).value;
let runtime = trt_runtime_create(logger).value;
let engine = trt_runtime_deserialize_memory(runtime, plan).value;
let ctx = trt_engine_create_context(engine).value;

let din = trt_cuda_alloc(16).value;
let dout = trt_cuda_alloc(16).value;
let _ = trt_context_set_tensor_address(ctx, "input", din);
let _ = trt_context_set_tensor_address(ctx, "output", dout);
let stream = trt_cuda_stream_create().value;
let _ = trt_context_enqueue(ctx, stream);
let _ = trt_cuda_stream_sync(stream);
```

See [`tests/test_conformance.xi`](tests/test_conformance.xi) for the full
end-to-end path, including host staging with `xiom.ffi`, file save/load, and
ordered teardown.

## Lifecycle

```
trt_cuda_init
  -> trt_probe
  -> logger -> builder -> network + config
  -> build_serialized -> plan
  -> runtime -> deserialize -> engine -> execution context
  -> cuda buffers + stream -> set addresses -> enqueue -> sync -> download
  -> context -> engine -> runtime -> plan -> config -> network -> builder -> logger
  -> cuda shutdown -> trt_close
```

Builders/runtimes hold a shared reference to their logger, so destroying the
logger handle before them is safe. Tensors and layers are borrowed from a
network and become invalid when the network is destroyed. Handles are
single-threaded; use one thread per handle set.

## Tests

```powershell
$env:XIOM_TENSORRT_DIR = "E:\repos\tensorrt\wheel\tensorrt_libs"
.\scripts\port.ps1 -Package xiom.tensorrt -TimeoutSec 300
```

- Live host: **55 passed / 0 failed**, twice in a row.
- Without the runtime: **2 passed / 0 failed** (deterministic SKIP-path check +
  CUDA check) and an explicit `live leg SKIP` line.
- Covered: loader identity/version, logger plumbing, builder capabilities,
  network basics, constant + element-wise Mul, config flags/pools/tactics,
  build+serialize, file save/load, deserialize from both plan sources, engine
  IO introspection, execution context shape/address plumbing, `enqueueV3`, and
  the live result `[2,4,6,8]`.

## Limits (0.1.0)

No ONNX parser, optimization-profile creation, plugin registry, refit, DLA,
multi-device scheduling, or Linux `.so` support. `enqueueV2` / TensorRT 8.x is
not enabled. Dynamic shapes require `trt_context_set_input_shape` with a static
profile (no multi-profile API yet). See [`SPEC.md`](SPEC.md) §7.

## License

Package code: MIT OR Apache-2.0. TensorRT itself is governed by the NVIDIA SLA
and is **not** redistributed. TensorRT reference headers are Apache-2.0 and are
not redistributed either. Full details: [`PROVENANCE.md`](PROVENANCE.md).
