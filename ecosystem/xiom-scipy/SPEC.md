# xiom-scipy — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi, xiom-numpy (array types), xiom-openblas (BLAS)

## What it wraps
SciPy — scientific computing library. Unlike NumPy (arrays + basic ops),
SciPy provides algorithms: optimization, integration, interpolation, signal processing,
statistics, sparse matrices. Each module wraps existing C/C++/Fortran libraries.

## Dependencies

| Module | Wraps | System dep |
|--------|-------|-----------|
| scipy.optimize | MINPACK (Fortran) | Bundled (small) |
| scipy.integrate | QUADPACK / ODEPACK | Bundled (small) |
| scipy.interpolate | FITPACK (Fortran) | Bundled (small) |
| scipy.signal | FFTPACK | Bundled (small) |
| scipy.sparse | ARPACK, SuperLU | Bundle ARPACK (500KB), system SuperLU |
| scipy.stats | Cephes, statlib | Bundled (small) |
| scipy.spatial | Qhull | System-installed |

## Bundling strategy
**Hybrid.** Small Fortran/C libraries (MINPACK, QUADPACK, FITPACK, FFTPACK, Cephes)
are bundled into the bridge .obj (they're tiny — ~100KB total).
Larger libs (SuperLU, Qhull) are system-installed.

## API surface (key modules)

```xiom
module xiom.scipy

// ── Optimize ──
pub fn minimize_scalar(f: fn(Float64) -> Float64, bracket: (Float64, Float64)) -> Result[OptimizeResult, Str]
pub fn minimize(f: fn(Vec[Float64]) -> Float64, x0: Vec[Float64], method: Str) -> Result[OptimizeResult, Str]
pub fn curve_fit(f: fn(Vec[Float64], Vec[Float64]) -> Float64, x: &NDArray, y: &NDArray, p0: Vec[Float64]) -> Result[Vec[Float64], Str]

// ── Integrate ──
pub fn quad(f: fn(Float64) -> Float64, a: Float64, b: Float64) -> Result[(Float64, Float64), Str]  // (value, error)
pub fn odeint(f: fn(NDArray, Float64) -> NDArray, y0: NDArray, t: NDArray) -> Result[NDArray, Str]

// ── Interpolate ──
pub fn interp1d(x: &NDArray, y: &NDArray, kind: Str) -> Result[Interpolator, Str]
pub fn interp_eval(interp: &Interpolator, x_new: &NDArray) -> Result[NDArray, Str]

// ── Signal ──
pub fn fft(x: &NDArray) -> Result[NDArray, Str]
pub fn ifft(x: &NDArray) -> Result[NDArray, Str]
pub fn convolve(a: &NDArray, b: &NDArray) -> Result[NDArray, Str]
pub fn butter(order: Int, cutoff: Float64, btype: Str) -> Result[(NDArray, NDArray), Str]
pub fn lfilter(b: &NDArray, a: &NDArray, x: &NDArray) -> Result[NDArray, Str]

// ── Stats ──
pub fn norm_pdf(x: &NDArray) -> NDArray
pub fn ttest_ind(a: &NDArray, b: &NDArray) -> Result[(Float64, Float64), Str]
pub fn pearsonr(a: &NDArray, b: &NDArray) -> Result[(Float64, Float64), Str]

// ── Sparse ──
pub fn sparse_csr_from_dense(a: &NDArray) -> Result[SparseMatrix, Str]
pub fn sparse_solve(A: &SparseMatrix, b: &NDArray) -> Result[NDArray, Str]

// ── Spatial ──
pub fn delaunay(points: &NDArray) -> Result[Delaunay, Str]  // 2D triangulation
pub fn convex_hull(points: &NDArray) -> Result[NDArray, Str]
```

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | optimize (minimize, curve_fit) + integrate (quad) | Weekend |
| 2 | signal (FFT, convolve, filter) + interpolate | Weekend |
| 3 | stats + sparse + spatial | Weekend |
| 4 | Full ndimage, special functions, constants | Week |
