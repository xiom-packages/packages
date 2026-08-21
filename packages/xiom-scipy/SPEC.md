# xiom-scipy -- SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: Phase 1 partially implemented -- FFI declarations + pure-XIOM stats done; C bridge compilation pending
**Depends on**: xiom.ffi, xiom.math (for pure-XIOM stats), xiom-numpy (future), xiom-openblas (future)

## What it wraps
SciPy -- scientific computing library. Unlike NumPy (arrays + basic ops),
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
are bundled into the bridge .obj (they're tiny -- ~100KB total).
Larger libs (SuperLU, Qhull) are system-installed.

## Files

| File | Purpose |
|------|---------|
| `scipy.xi` | Main module (`xiom.scipy`): types, extern "C" block (10 functions), pure-XIOM stats wrappers, safe wrappers with contracts |
| `tests/test_conformance.xi` | 25 conformance tests: types, norm_pdf, norm_cdf, norm_ppf, vectorized stats, contract validation, FFI stubs, edge cases |
| `ROADMAP.md` | Phased implementation plan |
| `SPEC.md` | This file -- architecture and API surface |

## API surface (implemented in Phase 1)

```xiom
module xiom.scipy

// -- Types --
pub type ScipyResult = { x: Vec[Float64]; fun: Float64; nit: Int; success: Bool }
pub type QuadResult = { value: Float64; error: Float64 }
pub type Interpolator = { x: Vec[Float64]; y: Vec[Float64]; kind: Int; coeffs: Vec[Float64] }

// -- extern "C" (10 functions) --
// optimize_minimize, integrate_quad, integrate_odeint,
// signal_convolve, signal_fft, signal_ifft,
// stats_norm_pdf, stats_norm_cdf,
// interpolate_linear, interpolate_cubic

// -- Pure-XIOM stats (no FFI) --
pub fn norm_pdf(x: Float64) -> Float64       // phi(x) = (1/sqrt(2pi)) - e^(-x2/2)
pub fn norm_cdf(x: Float64) -> Float64       // Phi(x) via erf series
pub fn norm_ppf(p: Float64) -> Float64       // Quantile (probit) via rational approx + Newton refinement
pub fn norm_pdf_vec(x: &Vec[Float64]) -> Vec[Float64]
pub fn norm_cdf_vec(x: &Vec[Float64]) -> Vec[Float64]

// -- Safe wrappers with requires contracts --
pub fn minimize_scalar(f: fn(Float64) -> Float64, a: Float64, b: Float64) -> Result[ScipyResult, Str]
  requires: a < b
pub fn quad(f: fn(Float64) -> Float64, a: Float64, b: Float64) -> Result[QuadResult, Str]
  requires: a <= b
pub fn convolve_vec(a: &Vec[Float64], b: &Vec[Float64]) -> Result[Vec[Float64], Str]
pub fn fft_vec(data: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: data.len() > 0 && data.len() % 2 == 0
pub fn ifft_vec(data: &Vec[Float64]) -> Result[Vec[Float64], Str]
  requires: data.len() > 0 && data.len() % 2 == 0
pub fn interp_linear(x: &Vec[Float64], y: &Vec[Float64], x_new: Float64) -> Result[Float64, Str]
  requires: x.len() == y.len() && x.len() > 1 && x_new >= x[0] && x_new <= x[x.len()-1]
pub fn interp_cubic(x: &Vec[Float64], y: &Vec[Float64], x_new: Float64) -> Result[Float64, Str]
  requires: x.len() == y.len() && x.len() > 2 && x_new >= x[0] && x_new <= x[x.len()-1]

// -- Utility --
pub fn result_converged(r: &ScipyResult) -> Bool
pub fn scipy_result_default() -> ScipyResult
```

## Future API (Phase 2-4)

```xiom
// -- Optimize --
pub fn minimize(f: fn(Vec[Float64]) -> Float64, x0: Vec[Float64], method: Str) -> Result[OptimizeResult, Str]
pub fn curve_fit(f: fn(Vec[Float64], Vec[Float64]) -> Float64, x: &NDArray, y: &NDArray, p0: Vec[Float64]) -> Result[Vec[Float64], Str]

// -- Integrate --
pub fn odeint(f: fn(NDArray, Float64) -> NDArray, y0: NDArray, t: NDArray) -> Result[NDArray, Str]

// -- Interpolate --
pub fn interp1d(x: &NDArray, y: &NDArray, kind: Str) -> Result[Interpolator, Str]
pub fn interp_eval(interp: &Interpolator, x_new: &NDArray) -> Result[NDArray, Str]

// -- Signal --
pub fn butter(order: Int, cutoff: Float64, btype: Str) -> Result[(NDArray, NDArray), Str]
pub fn lfilter(b: &NDArray, a: &NDArray, x: &NDArray) -> Result[NDArray, Str]

// -- Stats --
pub fn ttest_ind(a: &NDArray, b: &NDArray) -> Result[(Float64, Float64), Str]
pub fn pearsonr(a: &NDArray, b: &NDArray) -> Result[(Float64, Float64), Str]

// -- Sparse --
pub fn sparse_csr_from_dense(a: &NDArray) -> Result[SparseMatrix, Str]
pub fn sparse_solve(A: &SparseMatrix, b: &NDArray) -> Result[NDArray, Str]

// -- Spatial --
pub fn delaunay(points: &NDArray) -> Result[Delaunay, Str]  // 2D triangulation
pub fn convex_hull(points: &NDArray) -> Result[NDArray, Str]
```

## Phased roadmap

| Phase | What | Effort | Status |
|-------|------|--------|--------|
| 1 | FFI declarations (10 C functions) + pure-XIOM stats + safe wrappers + conformance tests | Weekend | [OK] Implemented |
| 1 (bridge) | C bridge compilation (MINPACK, QUADPACK, FFTPACK, FITPACK, Cephes -> .obj) | 1 day | [ ] Pending |
| 2 | signal (butter, lfilter) + interpolate (interp1d) + odeint | Weekend | [ ] Planned |
| 3 | stats (ttest, pearsonr) + sparse + spatial | Weekend | [ ] Planned |
| 4 | Full ndimage, special functions, constants | Week | [ ] Planned |
