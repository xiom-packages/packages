# xiom.numpy -- SPEC

**Phase**: 1 (Core Foundation) | **Priority**: CRITICAL
**Status**: Phase 1 implemented -- types, extern C FFI, safe wrappers with contracts, 30 conformance tests
**Depends on**: xiom.ffi (stdlib), xiom.openblas (BLAS/LAPACK backend)

## What it wraps
NumPy C API -- the fundamental array computing library for scientific Python.
ND-array operations, broadcasting, linear algebra, FFT, random numbers.

NumPy's C API sits on top of OpenBLAS (or MKL). We wrap the C layer directly,
bypassing Python entirely. This is what Cython/C extensions do internally.

## Dependencies

| What | How | Size |
|------|-----|------|
| NumPy source | Clone `github.com/numpy/numpy`. Extract `numpy/core/include/` headers. | ~5MB headers |
| OpenBLAS | System-installed (via xiom.openblas) | ~30MB |
| C compiler | For building bridge .obj | -- |

## Bundling strategy
**Headers only from NumPy source.** Compile the C API bridge against system OpenBLAS.
NumPy's `numpy/core/include/numpy/` contains the public C API headers.
We compile a thin C bridge that calls `PyArray_*` functions (which are C, not Python).

## API surface

```xiom
module xiom.numpy

pub type NDArray = Int  // opaque handle, wraps PyArrayObject*

// Array creation
pub fn array_new(shape: Vec[Int], dtype: DType) -> Result[NDArray, Str]
pub fn array_from_data(data: &Vec[Float64], shape: Vec[Int]) -> Result[NDArray, Str]
pub fn array_zeros(shape: Vec[Int], dtype: DType) -> Result[NDArray, Str]
pub fn array_ones(shape: Vec[Int], dtype: DType) -> Result[NDArray, Str]
pub fn array_arange(start: Float64, stop: Float64, step: Float64) -> Result[NDArray, Str]
pub fn array_free(arr: NDArray)

// Properties
pub fn ndim(arr: &NDArray) -> Int
pub fn shape(arr: &NDArray) -> Vec[Int]
pub fn dtype(arr: &NDArray) -> DType
pub fn size(arr: &NDArray) -> Int

// Indexing
pub fn get(arr: &NDArray, indices: Vec[Int]) -> Float64
pub fn set(arr: &mut NDArray, indices: Vec[Int], val: Float64)

// Element-wise ops
pub fn add(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
pub fn sub(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
pub fn mul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
pub fn div(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]

// Linear algebra (delegates to OpenBLAS)
pub fn dot(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
pub fn matmul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
pub fn svd(a: &NDArray) -> Result[(NDArray, NDArray, NDArray), Str]
pub fn inv(a: &NDArray) -> Result[NDArray, Str]

// Reductions
pub fn sum(arr: &NDArray, axis: Int) -> Result[NDArray, Str]
pub fn mean(arr: &NDArray, axis: Int) -> Result[NDArray, Str]
pub fn max(arr: &NDArray, axis: Int) -> Result[NDArray, Str]

// Broadcasting + reshaping
pub fn reshape(arr: &NDArray, new_shape: Vec[Int]) -> Result[NDArray, Str]
pub fn transpose(arr: &NDArray) -> Result[NDArray, Str]
```

## Contract coverage target
- Shape compatibility: `requires: a.ndim == b.ndim` for elementwise ops
- Broadcasting rules enforced at runtime with clear error messages
- Memory: `Result` for all allocation paths
- Null arrays: `requires: arr != 0`

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Array create/free, basic properties, element-wise ops | Weekend |
| 2 | Linear algebra (dot, matmul, svd), reductions | Weekend |
| 3 | Broadcasting, advanced indexing, FFT, random | Week |
| 4 | Interop with xiom.libtorch (zero-copy tensor sharing) | Weekend |

## Relationship to other packages
- `xiom.openblas`: NumPy delegates BLAS/LAPACK to OpenBLAS.
- `xiom.libtorch`: NumPy arrays can be converted to LibTorch tensors.
- `xiom.pandas`: Depends on NumPy for the underlying array storage.
- `xiom.scipy`: Depends on NumPy for array types.
