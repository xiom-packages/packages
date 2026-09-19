# xiom.libtorch -- SPEC

**Phase**: 1 (Core Foundation) | **Priority**: CRITICAL
**Status**: Phase 1 implemented -- module `xiom.libtorch` with 18 safe wrappers, 18 extern "C" decls, 16 conformance tests
**Depends on**: xiom.ffi (stdlib)

## What it wraps
LibTorch -- PyTorch C++ API. Full ML/DL framework with CUDA support.
Used directly by PyTorch's C++ frontend.

## Dependencies

| What | How | Size |
|------|-----|------|
| LibTorch | Download from pytorch.org. Set `LIBTORCH_DIR`. | ~2GB (CPU) / ~3GB (CUDA) |
| CUDA Toolkit | System-installed (for GPU). `nvidia-smi` to check. | ~3GB |
| C++ compiler | clang++ or MSVC for C++ bridge | -- |

## Bundling strategy
**System-installed only.** LibTorch is 2-3GB. Never bundle.
User downloads from pytorch.org and sets `LIBTORCH_DIR`.

## API surface

```xiom
module xiom.libtorch

// Tensor creation
pub fn tensor_new(shape: Vec[Int]) -> Result[Tensor, Str]
pub fn tensor_from_data(data: &Vec[Float32], shape: Vec[Int]) -> Result[Tensor, Str]
pub fn tensor_free(t: Tensor)
pub fn tensor_to_vec(t: &Tensor) -> Vec[Float32]

// Tensor ops
pub fn tensor_add(a: &Tensor, b: &Tensor) -> Result[Tensor, Str]
pub fn tensor_mul(a: &Tensor, b: &Tensor) -> Result[Tensor, Str]
pub fn tensor_matmul(a: &Tensor, b: &Tensor) -> Result[Tensor, Str]
pub fn tensor_relu(t: &Tensor) -> Tensor
pub fn tensor_softmax(t: &Tensor, dim: Int) -> Tensor

// Module loading
pub fn jit_load(path: Str) -> Result[Module, Str]
pub fn module_forward(m: &Module, input: &Tensor) -> Result[Tensor, Str]
pub fn module_free(m: Module)

// GPU
pub fn cuda_is_available() -> Bool
pub fn tensor_to_cuda(t: &Tensor) -> Tensor
pub fn tensor_to_cpu(t: &Tensor) -> Tensor

// Training
pub fn optimizer_sgd(params: Vec[Tensor], lr: Float32) -> Optimizer
pub fn optimizer_step(opt: &mut Optimizer)
pub fn optimizer_zero_grad(opt: &mut Optimizer)
```

## Contract coverage target
- Shape compatibility: runtime dimension checks
- CUDA availability: `requires: cuda_is_available()` for GPU ops
- Memory: `Result` for allocation failures
- Module file: `requires: io.file_exists(path)` for jit_load

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Tensor create/free, basic ops (add, mul, matmul) | Weekend |
| 2 | JIT model loading, forward pass, GPU support | Weekend |
| 3 | Autograd, optimizers, training loop | Week |
| 4 | DataLoader, Datasets, Transforms | Week |
