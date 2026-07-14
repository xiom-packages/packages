xiom-onnx: XIOM ONNX Runtime Bindings v0.1.0

== Overview ==

xiom-onnx provides XIOM bindings to the ONNX Runtime C API, enabling
cross-framework model inference. Models exported from PyTorch, TensorFlow,
scikit-learn, and other frameworks can be loaded and executed through
a unified API.

Three modules:
  - xiom.onnx.types: Core types (OnnxModel, OnnxTensor, OnnxConfig) and
    ONNX Runtime dtype/optimization level constants.
  - xiom.onnx.session: Session management via `extern "C"` stubs. All FFI
    functions return stubbed results until the ONNX Runtime shared library
    is linked.
  - xiom.onnx.io: Tensor construction, conversion, and image preprocessing
    utilities in pure XIOM.

Layer: 3.5 (Ecosystem Libraries)
Package: xiom-onnx
Namespace: xiom.onnx.*

== ONNX Runtime Installation ==

=== Linux (Ubuntu/Debian) ===

  wget https://github.com/microsoft/onnxruntime/releases/download/v1.18.0/
        onnxruntime-linux-x64-1.18.0.tgz
  tar xzf onnxruntime-linux-x64-1.18.0.tgz -C /opt
  export LD_LIBRARY_PATH=/opt/onnxruntime-linux-x64-1.18.0/lib:$LD_LIBRARY_PATH

=== macOS ===

  wget https://github.com/microsoft/onnxruntime/releases/download/v1.18.0/
        onnxruntime-osx-universal2-1.18.0.tgz
  tar xzf onnxruntime-osx-universal2-1.18.0.tgz -C /opt
  export DYLD_LIBRARY_PATH=/opt/onnxruntime-osx-universal2-1.18.0/lib:$DYLD_LIBRARY_PATH

=== Windows ===

  Download from https://github.com/microsoft/onnxruntime/releases
  Extract to C:\onnxruntime.
  set PATH=C:\onnxruntime\lib;%PATH%

=== XIOM Build Integration ===

  xiomc myprogram.xi -L $ONNX_RUNTIME_DIR/lib -l onnxruntime

== Module Specifications ==

=== 1. xiom.onnx.types — Core Types ===

Types:
  OnnxModel:    { path: Str; session: Int; input_names: Vec[Str];
                  output_names: Vec[Str]; }
    Represents a loaded ONNX model. `session` is 0 when the FFI stub
    is not linked; else it holds the native session pointer.
  OnnxTensor:   { name: Str; data: Vec[Float32]; shape: Vec[Int];
                  dtype: Int; }
    Input/output tensor. dtype follows ONNX Runtime type enum values.
  OnnxConfig:   { num_threads: Int; graph_optimization_level: Int;
                  enable_profiling: Bool; }
    Session configuration. num_threads controls intra-op parallelism.

Constants:
  ORT_DTYPE_FLOAT      = 1     Float32
  ORT_DTYPE_DOUBLE     = 11    Float64
  ORT_DTYPE_INT32      = 6     Int32
  ORT_DTYPE_INT64      = 7     Int64
  ORT_DTYPE_UINT8      = 2     UInt8
  ORT_DTYPE_BOOL       = 9     Bool
  ORT_GRAPH_OPT_DISABLE   = 0
  ORT_GRAPH_OPT_BASIC     = 1
  ORT_GRAPH_OPT_EXTENDED  = 2
  ORT_GRAPH_OPT_ALL       = 99

Functions:
  onnx_config_default() -> OnnxConfig
    Returns { num_threads: 4, graph_optimization_level: 1,
              enable_profiling: false }.

=== 2. xiom.onnx.session — Session Management ===

All functions are stubbed until the native ONNX Runtime library is linked.

extern "C" FFI symbols:
  ort_c_create_session(path_ptr, path_len, config_ptr) -> *UInt8
  ort_c_run(session_ptr, input_ptr, input_count) -> *UInt8
  ort_c_get_input_count(session_ptr) -> Int
  ort_c_get_output_count(session_ptr) -> Int
  ort_c_close_session(session_ptr)
  ort_c_free(ptr)

Functions:
  onnx_load_model(path: Str, config: &OnnxConfig) -> Result[OnnxModel, Str]
    STUB — Returns an empty model. Will call ort_c_create_session.

  onnx_run(model: &OnnxModel, inputs: &Vec[OnnxTensor]) -> Result[Vec[OnnxTensor], Str]
    STUB — Returns empty vector. Will call ort_c_run.

  onnx_get_input_count(model: &OnnxModel) -> Int
    STUB — Returns 0. Will call ort_c_get_input_count.

  onnx_get_output_count(model: &OnnxModel) -> Int
    STUB — Returns 0. Will call ort_c_get_output_count.

  onnx_close(model: OnnxModel)
    STUB — No-op. Will call ort_c_close_session.

=== 3. xiom.onnx.io — Tensor I/O ===

Pure XIOM utilities for tensor creation, conversion, and preprocessing.

Functions:
  onnx_tensor_from_vec(data: &Vec[Float32], shape: &Vec[Int]) -> OnnxTensor
    Wraps a Vec[Float32] into an OnnxTensor with dtype ORT_DTYPE_FLOAT.
    requires: data.len() > 0, shape.len() > 0

  onnx_tensor_to_vec(t: &OnnxTensor) -> Vec[Float32]
    Extracts the data vector from an OnnxTensor (clones).

  onnx_preprocess_image(data: &Vec[Int], target_size: Int) -> OnnxTensor
    STUB — Creates a zero-filled NCHW tensor with shape [1, 3, H, W].
    Intended to be replaced with actual resize/normalize pipeline
    once xiom-opencv or equivalent image processing is available.
    requires: data.len() > 0, target_size > 0

  onnx_tensor_zeros(name: Str, shape: &Vec[Int]) -> OnnxTensor
    Convenience: creates a zero-filled OnnxTensor with the given name.
    requires: shape.len() > 0

  onnx_tensor_get_name(t: &OnnxTensor) -> Str
    Returns the tensor name.

  onnx_tensor_set_name(t: &mut OnnxTensor, name: Str)
    Sets the tensor name in-place.

== Limitations ==

1. FFI Stubs: All ONNX Runtime C API calls return dummy values. Requires
   native library linkage and the ONNX Runtime C bridge.
2. Float32 Only: Input/Output tensors are Vec[Float32]. Other dtypes are
   defined as constants but not implemented for construction or conversion.
3. No GPU Execution: The session config does not include execution provider
   selection (CUDA, TensorRT, DirectML).
4. Single Input/Output: The stub API assumes single input/output tensors.
   Multi-input models require the FFI tier to be implemented.
5. Preprocessing Stub: onnx_preprocess_image returns zeros. Actual resize/
   normalize/mean-std pipeline needs image processing support.
6. No Dynamic Shapes: Shape inference at load time is not implemented.

== API Conventions ==

- Session functions: `onnx_load_model`, `onnx_run` return `Result[T, Str]`.
- Tensor constructors: `onnx_tensor_from_vec`, `onnx_tensor_zeros`.
- I/O utilities: `onnx_tensor_to_vec` for extraction.
- All FFI calls go through `extern "C"` declarations in xiom.onnx.session.
- Configuration uses `onnx_config_default()` with sensible defaults.

== Production Readiness ==

| Feature                          | Status  | Notes                        |
|----------------------------------|---------|------------------------------|
| OnnxModel/OnnxTensor types       | Complete| Struct definitions           |
| OnnxConfig type                  | Complete| With sensible defaults       |
| Dtype constants                  | Complete| All ORT dtype values         |
| Optimization level constants     | Complete| DISABLE to ALL               |
| ONNX Runtime FFI stubs           | Complete| extern "C" declarations      |
| Session create/run/close         | Stub    | Needs native onnxruntime lib |
| Tensor from/to Vec               | Complete| Pure XIOM                    |
| Tensor zeros constructor         | Complete| Pure XIOM                    |
| Image preprocessing              | Stub    | Needs xiom-opencv            |
| GPU execution providers          | Not yet | Needs CUDA/TensorRT config   |
| Dynamic shapes                   | Not yet | Needs shape inference        |
| Multi-I/O models                 | Not yet | Needs full FFI bridge        |

== What's Left for v1.0 ==

1. **ONNX Runtime FFI bridge** — Native C bridge for ort_c_* symbols.
2. **Execution providers** — CUDA, TensorRT, DirectML, CoreML configuration.
3. **Multi-I/O support** — Handle models with multiple inputs/outputs.
4. **Dtype support** — Construction for INT32, INT64, DOUBLE, BOOL tensors.
5. **Image preprocessing pipeline** — Integrate with xiom-opencv for
   resize, normalize, mean-std subtraction.
6. **Shape inference** — Query model metadata for input/output shapes.
7. **Batching** — Efficient batched inference with memory reuse.
