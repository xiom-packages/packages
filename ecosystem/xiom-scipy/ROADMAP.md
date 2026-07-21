# xiom-scipy — Implementation Roadmap

**Status**: Phase 1 in progress
**Last updated**: 2026-07-21

## Phase 1: Core Foundation (current)

- [x] Module skeleton (`module xiom.scipy`)
- [x] Core types: `ScipyResult`, `QuadResult`, `Interpolator`
- [x] `extern "C"` declarations for all 10 SciPy C functions
- [x] Pure-XIOM statistics: `norm_pdf`, `norm_cdf`, `norm_ppf`
- [x] Vectorized stats: `norm_pdf_vec`, `norm_cdf_vec`
- [x] Safe wrappers with `requires` contracts: `minimize_scalar`, `quad`, `convolve_vec`, `fft_vec`, `ifft_vec`, `interp_linear`, `interp_cubic`
- [x] 25 conformance tests (focus on pure-XIOM paths + FFI error contracts)
- [x] Utility functions: `result_converged`, `scipy_result_default`

### Phase 1 remaining

| Task | Effort | Depends on |
|------|--------|------------|
| C bridge compilation (MINPACK, QUADPACK, FFTPACK, FITPACK, Cephes → .obj) | 1 day | Build system |
| Link FFI symbols to actual C libraries | 1 day | Bridge .obj |
| Enable full FFI-path tests (currently stubs) | 0.5 day | Linked symbols |
| `minimize_scalar` golden-path tests | 0.5 day | Linked symbols |
| `quad` golden-path tests | 0.5 day | Linked symbols |
| `fft_vec` / `ifft_vec` golden-path tests | 0.5 day | Linked symbols |
| `interp_linear` / `interp_cubic` golden-path tests | 0.5 day | Linked symbols |

## Phase 2: Signal + Interpolate (planned)

| Task | Effort |
|------|--------|
| `signal.butter` (Butterworth filter design) | 0.5 day |
| `signal.lfilter` (linear filter apply) | 0.5 day |
| `interpolate.interp1d` object with `eval` method | 1 day |
| `odeint` wrapper + tests | 1 day |

## Phase 3: Stats + Sparse + Spatial (planned)

| Task | Effort |
|------|--------|
| `stats.ttest_ind` (two-sample t-test) | 1 day |
| `stats.pearsonr` (Pearson correlation) | 0.5 day |
| `sparse.csr_from_dense` + `sparse.solve` | 2 days |
| `spatial.delaunay` (2D triangulation) | 1 day |
| `spatial.convex_hull` | 0.5 day |

## Phase 4: Full Suite (planned)

| Task | Effort |
|------|--------|
| `ndimage` submodule (filters, morphology) | 2 days |
| `special` functions (Bessel, gamma, etc.) | 2 days |
| `constants` submodule | 0.5 day |
| `optimize.curve_fit` | 1 day |
