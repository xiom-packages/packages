xiom-torch: XIOM LibTorch Bindings v0.1.0

== Overview ==

xiom-torch provides XIOM bindings to the LibTorch C++ API for PyTorch model
inference. The package is organized into three layers:

  - xiom.torch.types: Core tensor types, device abstractions, and data type
    enums that form the foundation for all tensor operations.
  - xiom.torch.ffi: LibTorch C API stubs via `extern "C"`. All FFI functions
    return stubbed results until the native LibTorch shared library is linked.
  - xiom.torch.nn: Pure XIOM neural network building blocks (Linear, Conv2d,
    BatchNorm2d, activations, Sequential). Data structures are fully defined;
    forward passes are stubbed pending tensor math primitives in xiom-std.

Layer: 3.5 (Ecosystem Libraries)
Package: xiom-torch
Namespace: xiom.torch.*

== LibTorch Runtime Dependency ==

The FFI tier (xiom.torch.ffi) requires the LibTorch C++ shared library.

=== Linux (Ubuntu/Debian) ===

  Download the LibTorch C++ distribution from https://pytorch.org:
    wget https://download.pytorch.org/libtorch/cpu/libtorch-shared-with-deps-2.4.0%2Bcpu.zip
    unzip libtorch-shared-with-deps-2.4.0+cpu.zip -d /opt/libtorch

  Set environment variables:
    export LIBTORCH=/opt/libtorch
    export LD_LIBRARY_PATH=$LIBTORCH/lib:$LD_LIBRARY_PATH

=== Linux (Fedora/RHEL) ===

  Same as Ubuntu -- download the LibTorch distribution.

=== macOS ===

  wget https://download.pytorch.org/libtorch/cpu/libtorch-macos-2.4.0.zip
  unzip libtorch-macos-2.4.0.zip -d /opt/libtorch
  export LIBTORCH=/opt/libtorch
  export DYLD_LIBRARY_PATH=$LIBTORCH/lib:$DYLD_LIBRARY_PATH

=== Windows ===

  Download from https://pytorch.org. Extract to C:\libtorch.

  Build with XIOM:
    set LIBTORCH=C:\libtorch
    set PATH=%LIBTORCH%\lib;%PATH%

=== XIOM Build Integration ===

  xiom myprogram.xi -L $LIBTORCH/lib -l torch -l c10 -I $LIBTORCH/include

== Module Specifications ==

=== 1. xiom.torch.types -- Tensor & Device Types ===

Core data types for tensor representation.

Types:
  Tensor:       { data: Vec[Float32]; shape: Vec[Int]; strides: Vec[Int];
                  device: Device; dtype: DType; }
  DType:        Float32 | Float64 | Int32 | Int64 | UInt8 | Bool
  Device:       CPU | CUDA(device_id: Int)
  TensorOptions:{ dtype: DType; device: Device; requires_grad: Bool; }
  ModuleDef:    { name: Str; params: Vec[Tensor]; buffers: Vec[Tensor]; }

Functions:
  tensor_new(shape: &Vec[Int], options: &TensorOptions) -> Tensor
    Creates a zero-initialized tensor with the given shape and options.
    Computes strides automatically in row-major (C-contiguous) order.
    requires: shape.len() > 0

  tensor_zeros(shape: &Vec[Int]) -> Tensor
    Convenience: tensor_new with Float32, CPU, no grad.

  tensor_ones(shape: &Vec[Int]) -> Tensor
    Creates a tensor filled with 1.0.

  tensor_shape(t: &Tensor) -> Vec[Int]
    Returns a clone of the shape vector.

  tensor_reshape(t: &Tensor, shape: &Vec[Int]) -> Tensor
    Returns a new tensor with the given shape. Total element count must
    match the original. Returns an empty tensor with zero-length shape on
    mismatch. Data is shared (cloned). Strides are recomputed.

=== 2. xiom.torch.ffi -- LibTorch C API Stubs ===

All functions are currently stubbed for development. Full implementation
requires linking against the system LibTorch installation.

Functions:
  torch_load_model(path: Str) -> Result[ModuleDef, Str]      STUB
  torch_forward(module: &ModuleDef, input: &Tensor) -> Result[Tensor, Str] STUB
  torch_save_model(module: &ModuleDef, path: Str) -> Result[Unit, Str]  STUB
  torch_is_cuda_available() -> Bool                            STUB (returns false)

FFI symbols (extern "C"):
  torch_c_load_model(path_ptr, path_len) -> *UInt8
  torch_c_forward(module_ptr, input_ptr, input_len) -> *UInt8
  torch_c_save_model(module_ptr, path_ptr, path_len) -> Int
  torch_c_is_cuda_available() -> Int
  torch_c_free(ptr)

=== 3. xiom.torch.nn -- Neural Network Building Blocks ===

Pure XIOM types for constructing neural network architectures. Forward
passes are stubbed (zero-output) until tensor operations are available.

Types:
  Linear:       { weight: Tensor; bias: Tensor; in_features: Int;
                  out_features: Int; }
  Conv2d:       { weight: Tensor; bias: Tensor; in_ch: Int; out_ch: Int;
                  kernel: Int; stride: Int; padding: Int; }
  BatchNorm2d:  { gamma: Tensor; beta: Tensor; running_mean: Tensor;
                  running_var: Tensor; eps: Float32; }
  ReLU:         {}
  Sigmoid:      {}
  Tanh:         {}
  Softmax:      { dim: Int; }
  Sequential:   { layers: Vec[LayerType]; }
  LayerType:    LinearLayer(Linear) | Conv2dLayer(Conv2d) |
                BatchNorm2dLayer(BatchNorm2d) |
                ReLULayer | SigmoidLayer | TanhLayer |
                SoftmaxLayer(dim: Int)

Constructors:
  linear_new(in_features, out_features) -> Linear
    Creates weight tensor [out_features, in_features] and bias [out_features],
    both zero-initialized.
    requires: in_features > 0, out_features > 0

  conv2d_new(in_ch, out_ch, kernel, stride, padding) -> Conv2d
    Creates weight [out_ch, in_ch, kernel, kernel] and bias [out_ch].
    requires: in_ch > 0, out_ch > 0, kernel > 0, stride > 0, padding >= 0

  batchnorm2d_new(num_features, eps) -> BatchNorm2d
    Initializes gamma to ones, beta and running_mean to zeros,
    running_var to ones.
    requires: num_features > 0, eps > 0.0

  sequential_new() -> Sequential
    Creates an empty sequential container.

  sequential_add(seq, layer)
    Appends a layer to the sequential container.

Forward passes:
  linear_forward(layer: &Linear, input: &Tensor) -> Tensor      STUB
    Expected: y = x * W^T + b. Returns zero tensor with shape
    [batch_size, out_features].

== Limitations ==

1. FFI Stubs: All LibTorch C API calls return dummy values. Requires native
   library linkage and runtime bridge intrinsics.
2. No CUDA: Even with FFI, CUDA tensor operations require CUDA toolkit and
   GPU driver. torch_is_cuda_available() always returns false.
3. Pure CPU Tensors: The types module only supports Float32 CPU tensors.
   Other dtypes and devices are defined but not implemented.
4. No Automatic Differentiation: Tensors have requires_grad field but no
   autograd engine exists.
5. Stub Forward Passes: nn.forward functions return zero-filled tensors.
   Actual computation requires tensor math primitives (matmul, conv2d, etc.)
6. No Serialization: torch_save_model is a stub. PyTorch .pt/.pth files
   cannot be loaded without full LibTorch FFI.

== API Conventions ==

- Constructor functions: `type_new(args) -> Type` with requires contracts.
- Forward functions: `type_forward(&Type, &Tensor) -> Tensor`.
- Tensor functions: `tensor_*(shape) -> Tensor` with explicit dtype/device.
- FFI functions: return `Result[T, Str]` for fallible operations.
- Layer container: `sequential_add(&mut Sequential, LayerType)`.

== Production Readiness ==

| Feature                          | Status  | Notes                        |
|----------------------------------|---------|------------------------------|
| Tensor types                     | Complete| Struct/enum definitions      |
| Device/DType enums               | Complete| CPU, CUDA; all dtypes        |
| Tensor constructors              | Complete| zeros, ones, new             |
| Tensor reshape                   | Complete| Pure XIOM                    |
| LibTorch FFI stubs               | Complete| extern "C" declarations      |
| Model load/save FFI              | Stub    | Needs native LibTorch        |
| CUDA detection                   | Stub    | Returns false                |
| Linear layer type                | Complete| Type + constructor           |
| Conv2d layer type                | Complete| Type + constructor           |
| BatchNorm2d type                 | Complete| Type + constructor           |
| Activation types                 | Complete| ReLU, Sigmoid, Tanh, Softmax |
| Sequential container             | Complete| Type + constructor           |
| Forward passes                   | Stub    | Needs tensor math primitives |
| GPU/CUDA support                 | Not yet | Needs CUDA toolkit           |
| Autograd engine                  | Not yet | Needs compiler support       |

== What's Left for v1.0 ==

1. **LibTorch FFI bridge** -- Implement xiom_torch_bridge.c for all extern "C"
   symbols using the LibTorch C++ API.
2. **Tensor math primitives** -- matmul, elementwise ops, convolutions in
   xiom-std or xiom-blas.
3. **Real forward passes** -- Use tensor math to implement linear_forward,
   conv2d_forward, batch normalization, and activation functions.
4. **Model serialization** -- Load/save PyTorch model files (.pt, .pth).
5. **GPU support** -- CUDA tensor allocation and device transfer.
6. **Autograd** -- Automatic differentiation for training.
