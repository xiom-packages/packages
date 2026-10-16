# xiom.numpy -- SPEC

**Phase**: 2a (Core Storage) | **Priority**: CRITICAL
**Status**: Phase 3b GREEN -- 130/130 conformance checks x2 (compiler v0.64.6, 2026-10-16); reductions (sum/mean/max/min, axis-aware) + `array_inv` landed (Phase-3a 103/103 was v0.64.6); Phase-1 link bridge retained at `bridge/numpy_bridge.c` as the acceleration seam (not called by the module)
**Depends on**: xiom.ffi (stdlib), xiom.openblas (BLAS/LAPACK backend) -- consumed as a PATH dep (`xiom.toml`) for the Phase-2b `dot`/`matmul` compute path.

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

## Phase-2a design note: native storage over the PyArray sketch (2026-10-16)
- Decision: the core storage leg uses **native pure-XIOM storage**, not the
  earlier `PyArray_*` C-bridge sketch. Registry consumers cannot assume a
  Python + NumPy install, so the core type must not depend on a Python runtime.
  `NDArray` stays an opaque `Int` handle; the bytes it names live in a
  module-level handle registry inside `src/numpy.xi` (parallel flat arenas:
  `Vec[Float64]` value buffer with per-slot base/size, flat shape arena with
  per-slot offset/ndim, dtype, and a liveness flag). No FFI is used on any
  creation, property, indexing, or free path.
- Handles are `1 + slot index`; handle `0` is always invalid. Slots are
  append-only, and `array_free` marks a slot dead without reusing it, so a
  stale handle can never silently alias a later allocation (handle
  independence and free semantics are conformance-checked).
- The C-bridge seam is preserved, not removed: `bridge/numpy_bridge.c` +
  `port.args.json` still link the element-wise (`add/sub/mul/div`) and
  linear-algebra (`dot/matmul`) entry points. A future PyArray / real-BLAS
  acceleration would be linked behind this same seam without changing the
  `NDArray` surface; the module itself no longer calls it.

## Phase-2b design note: element-wise + linear algebra on native storage (2026-10-16)
- Element-wise `array_add`/`array_sub`/`array_mul`/`array_div` are pure-XIOM
  loops over the Phase-2a arena. Same-shape rule: operands must have identical
  `ndim` and identical extents on every axis, else typed
  `Err("numpy: <op> shape mismatch")`. The result is a fresh array (same shape,
  same dtype as the left operand) in new arena slots; operands are never
  aliased or mutated.
- Division policy (fail-closed): `array_div` treats any zero divisor element as
  an error. The first `b[k] == 0.0` aborts the whole op with
  `Err("numpy: array_div division by zero")`; no partial result is committed.
  This is deliberate: no IEEE `inf`/`NaN` is produced.
- `array_dot`/`array_matmul` delegate to the `xiom.openblas` declared surface
  (`dot` for 1-D inner products, `gemm` for 2-D products). The openblas pool is
  row-major with `index = row * cols + col`, the same layout as this arena, so
  no transpose/marshal is needed. `array_dot` accepts 1-D . 1-D (inner product,
  returned as shape `[1]`) or 2-D . 2-D (matrix product, identical to
  `array_matmul`); any other rank pair fails with `Err`. `array_matmul` is
  strictly 2-D x 2-D with a matching inner dimension. All rank/shape violations
  are typed `Err`.
- `xiom.openblas` is wired as a PATH dependency in `xiom.toml` (the
  `xiom-llm` precedent); the legacy `package.xi` `deps:` block lists it too.
- Surface deltas from the Phase-1 sketch in the API block below: `get`/`set`
  now return typed `Result[Float64, Str]` / `Result[(), Str]` so out-of-bounds
  and rank errors are typed (bounds are runtime facts, not static contracts);
  `array_dtype` is exposed so the stored dtype metadata is observable.
- Shape guard: a negative dimension, or an element product above the
  documented `ND_MAX_ELEMS` (1000000), fails closed with `Err`.

## Phase-3a design note: broadcasting, N-D strides, reshape/transpose (2026-10-16)
- Element-wise `array_add`/`array_sub`/`array_mul`/`array_div` now broadcast
  (NumPy rule: operands align from the right; on each axis the extents must be
  equal or one of them is 1, else typed
  `Err("numpy: <op> shape mismatch")`). The result carries the broadcast shape
  and the left operand's dtype; identical-shape operands reduce exactly to the
  Phase-2b same-shape loop. The div fail-closed policy is unchanged.
- N-D over the flat f64 arena: row-major strides are derived per axis
  (`_nd_strides_of_shape`); a broadcast operand uses stride 0 on stretched axes
  (`_nd_bc_stride`). No new storage mode is added -- reshape/transpose copy into
  fresh arena slots, so no operated array is aliased or mutated.
- `array_reshape(arr, new_shape)`: C-order reshape; the element count must match
  exactly, else `Err`. `array_transpose(arr)`: reverses the axis order (NumPy
  semantics); 2-D gives `out[j, i] == in[i, j]`, 1-D is identity, N-D reverses
  all axes. Both return copies (view semantics deferred).
- Surface additions: `array_reshape`, `array_transpose` (typed
  `Result[NDArray, Str]`). The Phase-2b same-shape-only misfit assertion in the
  suite was replaced by a broadcast-incompatible case, because broadcasting now
  makes `[2]` with `[2,2]` legal.
- Suite: 103/103 conformance checks GREEN x2 (v0.64.6, 2026-10-16).

## Phase-3b design note: reductions + matrix inverse (2026-10-16)
- Reductions `array_sum` / `array_mean` / `array_max` / `array_min` are pure-XIOM
  passes over the flat f64 arena, built on the Phase-3a row-major stride helper
  (`_nd_strides_of_shape`) and the same slot-allocation path as every other op.
  `axis == -1` is the full-array reduction ("axis omitted") and yields shape
  `[1]` (the `dot` inner-product convention); `axis` in `[0, ndim)` reduces that
  axis only and drops it from the result shape (a 1-D input reduced on axis 0
  yields `[1]`). Any other axis, an invalid handle, or an empty input fails
  closed with a typed `Err`. Reductions never alias or mutate the operand.
  (Names carry the module's `array_` prefix, matching `array_add`/`array_reshape`
  rather than the bare `sum`/`mean`/`max` of the original API sketch.)
- `array_inv` is a self-contained Gauss-Jordan elimination with partial pivoting
  over the f64 arena, so it is correct on the offline leg with no live
  BLAS/LAPACK. Rationale: `xiom.openblas` ships only stub `solve`/`svd`
  (identity/zero placeholders) and no `inv` symbol, so routing the inverse
  through that seam could not yield correct values offline; the openblas/LAPACK
  path remains the documented acceleration target behind the same `NDArray`
  surface. Fail-closed: a non-2-D operand, a non-square matrix, a matrix whose
  augmented buffer would exceed `ND_MAX_ELEMS`, or a singular matrix (no pivot
  above `ND_INV_PIVOT_EPS` while eliminating a column) all return a typed `Err`;
  no partial result is returned.
- `svd` is deferred: Gauss-Jordan is not trivially extendable to SVD (SVD needs
  a one-sided Jacobi / eigen routine), and the `xiom.openblas.svd` seam is still
  a Phase-1 stub. Documented as remaining Phase-3 work (see ROADMAP.md).
- Suite: 130/130 conformance checks GREEN x2 (v0.64.6, 2026-10-16); 27 new
  checks (14 reduction goldens/error-paths, 8 inverse goldens/error-paths, 5
  contract markers).

## Phase-1 status and provenance (2026-10-16)
- The conformance suite (`tests/test_conformance.xi`, 30 checks) links the
  package-local Phase-1 bridge `bridge/numpy_bridge.c` via `port.args.json`
  (`--c-source ${PACKAGE_DIR}/bridge/numpy_bridge.c`; the sqlite/stb/cuda
  house pattern). The bridge defines all 17 `numpy_c_*` symbols (ABI:
  Int = i64, Float64 = double), validates arguments, and reports the NumPy
  backend unavailable until the Phase-2 `PyArray_*` linkage lands; the safe
  wrappers collapse every `<= 0` handle to `Err`, which is exactly what the
  twelve wrapper error-path checks assert.
- No third-party code is vendored for Phase 1: nothing was cloned or
  extracted, no NumPy headers, no Python runtime, no OpenBLAS binaries. The
  bridge is first-party C under the package license (MIT OR Apache-2.0),
  calls no NumPy/Python/OpenBLAS entry points, and allocates no memory.
- NumPy headers (Phase 2 only): `numpy/core/include/numpy/` ships under
  BSD-3-Clause (compatible with this package's license). When Phase 2 starts,
  use a shallow clone, record the exact commit hash in this file, and stay
  within the house bundling policy (headers only, never the full tree).
- BLAS: no Phase-1 check requires xiom.openblas. The later linear-algebra
  surface from the API section (`dot`, `matmul` in Phase 2; `svd`, `inv` in
  Phase 3) is where xiom.openblas and the NumPy C API become hard dependencies.

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
pub fn array_dtype(arr: &NDArray) -> DType
pub fn array_ndim(arr: &NDArray) -> Int
pub fn array_shape(arr: &NDArray) -> Vec[Int]
pub fn array_size(arr: &NDArray) -> Int

// Indexing (typed Err on invalid handle / rank / bounds)
pub fn array_get(arr: &NDArray, indices: &Vec[Int]) -> Result[Float64, Str]
pub fn array_set(arr: &mut NDArray, indices: &Vec[Int], val: Float64) -> Result[(), Str]

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

### Implemented surface deltas from the sketch above
- All ops carry the `array_` prefix (`array_add`, `array_reshape`, ...), matching
  the Phase-2b/3a implementation rather than the bare names in the sketch.
- Reductions are implemented as `array_sum`, `array_mean`, `array_max`,
  `array_min` (Phase-3b). `array_min` is added beyond the sketch's `max`/`mean`.
  `axis == -1` is the full-array reduction; `axis` in `[0, ndim)` drops that axis.
- `array_inv` is implemented (Phase-3b, self-contained Gauss-Jordan, fail-closed).
  `svd` remains unimplemented (see the Phase-3b design note).

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
