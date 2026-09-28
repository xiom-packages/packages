# xiom.dimred -- Specification

Status: `incubating` (implemented, harness-green on compilers 0.62.0 and
0.62.1, not published).
Module: `xiom.dimred` (`src/dimred.xi`). Manifest: `package.xi` (name
`xiom.dimred`, version `0.1.0`). Depends on `xiom.std` for the manifest; the
library imports `xiom.string` and `xiom.convert` and uses no other module.

## Scope

Fixed-point PCA primitives over scalar `Int` arithmetic:

- dense row-major matrices (`DimredMatrix`) with explicit scales;
- column means, mean-centering, sample covariance;
- dominant eigenpair of a symmetric covariance matrix by power iteration,
  with a max-iteration budget and an absolute tolerance;
- deflation to extract subsequent components;
- projection of samples onto components (scores);
- explained-variance ratios in basis points;
- `dimred_pca_fit` / `dimred_pca_transform` convenience wrappers.

Pure and deterministic: no floats, no FFI, no I/O, no clock access, no global
state, no allocation beyond the matrices and vectors involved.

## Non-goals

- t-SNE, UMAP, LDA, ICA, or any manifold-learning method;
- general SVD, general (non-symmetric) eigendecomposition, singular values,
  numerical rank, condition numbers;
- randomized, truncated or incremental decompositions; sparse matrices;
- whitening, score normalization, or reconstruction helpers;
- overflow detection or dynamic rescaling.

## Scaled arithmetic rules

A raw integer `r` with `d` fraction digits denotes `r / 10^d`.

| Quantity | `d` | Notes |
|---|---|---|
| data, means, scores | 3 | caller supplies raw `value * 1000` |
| covariance, eigenvalues | 3 | produced by the module |
| eigenvectors, components | 6 | max entry exactly `1000000`, positive |

Division (`/`) in XIOM v0.62.x truncates toward zero; every rounding step is
implemented explicitly:

- **Column means**: `_div_round(sum, rows)` rounds half away from zero.
- **Covariance**: each row product is truncated once to data scale
  (`a * b / 1000`), accumulated in `Int`, then divided by `n - 1` with
  `_div_round` (half away from zero). The accumulated truncation error is
  below one unit of the covariance scale divided by the sample count; the
  matrix is symmetric because entry `(i, j)` is computed independently for
  every `(i, j)`.
- **Matrix-vector product** (`_mul_div1e6(a, b) = a * b / 1000000`): the
  first factor is split into `a/1000` and `a%1000`, each multiplied by `b`
  and divided by 1000, so the intermediate product cannot overflow inside the
  envelope below. The result truncates twice and can differ from a
  single-step truncation by at most one unit; it is exact when `b == 1000000`
  or `a == 1000000`. Used by `_matvec`, `_project`, `_dot_self` and
  `_deflate_with`.
- **Normalization**: `v_new[i] = w[i] * 1000000 / scale` with
  `scale = max_i |w[i]|` (single truncation, exact at the pivot).
- **Eigenvalue estimate**: `lambda = max_i |(cov * v)[i]|`, the infinity norm.
  No division is involved.
- **Deflation**: `t = v[i]*v[j]/d` (single truncation, `d = v^T v` scaled so
  `t <= 1000000`), then `correction = _mul_div1e6(lambda, t)`; the symmetric
  matrix `cov - correction` is rebuilt row-major.
- **Explained variance**: `_div_round(lambda * 10000, trace)` clamped to
  `[0, 10000]`; `trace(cov)` equals the sum of all eigenvalues of `cov`, so
  no full eigendecomposition is needed.
- **Scores**: `sum_j _mul_div1e6(centered[r, j], component[j])`, one
  truncation per term.

### Safe magnitude envelope

The implementation does not detect overflow; the caller must stay inside the
envelope below (worst-case intermediate magnitudes, `Int` max `2^63 - 1 ~
9.22e18`):

| Constraint | Bound | Worst intermediate |
|---|---|---|
| `|data value|` | `<= 20000` (raw `2e7`) | product `a*b <= 4e14` |
| samples `n` | `<= 1000000` | covariance sum `<= 4e17` |
| features `m` | `<= 16` | matvec sum `<= 6.4e12` |
| derived | `lambda <= 6.4e12` | normalize `w*1e6 <= 6.4e18` |
| deflation | `t <= 1e6` | `_mul_div1e6` high part `<= 6.4e15` |
| bps | | `lambda*10000 <= 6.4e16` |

## Representation

`DimredMatrix` is row-major: `data[r * cols + c]`; `rows` and `cols` are
positive for any matrix produced by `dimred_matrix_new`. `Eigenpair` carries
`value` (covariance scale), `vector` (vector scale, max entry `1000000`,
positive) and `iterations`. `PcaModel` keeps parallel vectors: `means`
(`n_features` data-scale entries), `components` (`n_components` rows of
`n_features` vector-scale entries, row-major), `eigenvalues` (covariance
scale), `explained_bps`, `iterations`, plus `n_features` and
`n_components`. All struct fields are public but internal implementation
detail; use the accessors.

## Power iteration semantics

For a square covariance matrix `A` and a non-zero seed vector:

1. `v(0)` = seed max-normalized to entry magnitude `1000000`.
2. Repeat while `iterations < max_iter`:
   a. `w = A * v / 1e6` (scaled matvec);
   b. `scale = max_i |w[i]|`; if `scale == 0`, stop as a collapse;
   c. `v' = max-normalized w`; if the pivot entry is negative, negate all of
      `v'` (sign convention);
   d. `diff = max_i |v'[i] - v[i]|`; `v = v'`; `lambda = scale`;
      `iterations += 1`;
   e. if `diff <= tol`, stop as converged.
3. Report `Ok(value = lambda, vector = v, iterations)` on convergence.

- `tol` is absolute and expressed in vector-scale raw units (`1000` means
  `0.001` per component). `tol = 0` requires an exact fixed point.
- `max_iter` counts attempted iterations; `max_iter = 0` is rejected.
- `lambda` is the infinity-norm estimate and converges to the dominant
  eigenvalue for a converged vector; during early iterations it is a lower
  bound on the spectral norm.
- Failure modes: `dimred: covariance matrix is zero` (matrix is all zeros),
  `dimred: initial vector is in the null space` (non-zero matrix but the
  iterate collapsed), `dimred: power iteration did not converge` (`max_iter`
  exhausted before `diff <= tol`).

## Deflation

`A' = A - lambda * v * v^T / (v^T v)` is computed in place-element form:
`d = sum_i v[i]^2 / 1e6` (vector scale; `d >= 1e6` for a max-normalized
vector), `t_ij = v[i]*v[j]/d` (`<= 1e6`), `A'[i,j] = A[i,j] -
_mul_div1e6(lambda, t_ij)`. The dominant eigenvalue becomes ~0 and the
others are preserved up to truncation error. A zero eigenvector is rejected.

## pca_fit semantics

1. Validate: `rows >= 2`, `cols >= 1`, `1 <= n_components <= cols`,
   `max_iter >= 1`, `tol >= 0`.
2. `means = dimred_column_means(data)`, `centered = data - means`,
   `cov = dimred_covariance(centered)`, `total = trace(cov)`; a
   non-positive `total` (all rows identical) is an error.
3. For `k = 0..n_components-1`: run power iteration on the working matrix
   (seeded with all-ones) and record the component row, eigenvalue,
   `_explained_bps(lambda, total)` and iteration count; deflate before the
   next component.
4. `dimred_pca_transform` re-centers new samples with the stored means and
   projects them onto every component.

`explained_bps` entries are ratios against the original trace, so they do not
necessarily sum to 10000 when deflation error or non-orthogonal truncation is
present; component 0 is the most reliable.

## API signatures

```xi
pub type DimredMatrix = { rows: Int; cols: Int; data: Vec[Int]; }
pub type Eigenpair = { value: Int; vector: Vec[Int]; iterations: Int; }
pub type PcaModel = {
  means: Vec[Int]; components: Vec[Int]; eigenvalues: Vec[Int];
  explained_bps: Vec[Int]; iterations: Vec[Int];
  n_features: Int; n_components: Int;
}

pub fn dimred_data_decimals() -> Int
pub fn dimred_covariance_decimals() -> Int
pub fn dimred_vector_decimals() -> Int
pub fn dimred_matrix_new(rows: Int, cols: Int, values: &Vec[Int]) -> Result[DimredMatrix, Str]
pub fn dimred_matrix_rows(m: &DimredMatrix) -> Int
pub fn dimred_matrix_cols(m: &DimredMatrix) -> Int
pub fn dimred_matrix_get(m: &DimredMatrix, row: Int, col: Int) -> Int
pub fn dimred_matrix_data(m: &DimredMatrix) -> Vec[Int]
pub fn dimred_column_means(m: &DimredMatrix) -> Result[Vec[Int], Str]
pub fn dimred_center(m: &DimredMatrix, means: &Vec[Int]) -> Result[DimredMatrix, Str]
pub fn dimred_covariance(centered: &DimredMatrix) -> Result[DimredMatrix, Str]
pub fn dimred_power_iteration(cov: &DimredMatrix, init: &Vec[Int], max_iter: Int, tol: Int) -> Result[Eigenpair, Str]
pub fn dimred_deflate(cov: &DimredMatrix, ep: &Eigenpair) -> Result[DimredMatrix, Str]
pub fn dimred_project(centered: &DimredMatrix, component: &Vec[Int]) -> Result[Vec[Int], Str]
pub fn dimred_explained_variance_bps(eigenvalue: Int, cov: &DimredMatrix) -> Result[Int, Str]
pub fn dimred_pca_fit(data: &DimredMatrix, n_components: Int, max_iter: Int, tol: Int) -> Result[PcaModel, Str]
pub fn dimred_pca_transform(model: &PcaModel, data: &DimredMatrix) -> Result[DimredMatrix, Str]
pub fn dimred_pca_n_features(model: &PcaModel) -> Int
pub fn dimred_pca_n_components(model: &PcaModel) -> Int
pub fn dimred_pca_mean(model: &PcaModel, feature: Int) -> Int
pub fn dimred_pca_component(model: &PcaModel, comp: Int) -> Vec[Int]
pub fn dimred_pca_eigenvalue(model: &PcaModel, comp: Int) -> Int
pub fn dimred_pca_explained_bps(model: &PcaModel, comp: Int) -> Int
pub fn dimred_pca_iterations(model: &PcaModel, comp: Int) -> Int
```

## Error catalog

Every `Err` payload has the exact prefix `dimred: `.

| Message | Raised by | Condition |
|---|---|---|
| `dimred: rows must be positive` | `dimred_matrix_new` | `rows <= 0` |
| `dimred: cols must be positive` | `dimred_matrix_new` | `cols <= 0` |
| `dimred: rows*cols overflows` | `dimred_matrix_new` | `rows > Int::MAX / cols` |
| `dimred: values length does not match rows*cols` | `dimred_matrix_new` | length mismatch |
| `dimred: matrix has no rows` | `dimred_column_means`, `dimred_center`, `dimred_power_iteration`, `dimred_deflate`, `dimred_project`, `dimred_explained_variance_bps`, `dimred_pca_transform` | `rows <= 0` |
| `dimred: matrix has no columns` | `dimred_column_means`, `dimred_center`, `dimred_covariance`, `dimred_project` | `cols <= 0` |
| `dimred: means length mismatch` | `dimred_center` | `means.len() != cols` |
| `dimred: covariance needs at least 2 samples` | `dimred_covariance` | `rows < 2` |
| `dimred: covariance matrix must be square` | `dimred_power_iteration`, `dimred_deflate`, `dimred_explained_variance_bps` | `rows != cols` |
| `dimred: initial vector length mismatch` | `dimred_power_iteration` | `init.len() != rows` |
| `dimred: max_iter must be at least 1` | `dimred_power_iteration`, `dimred_pca_fit` | `max_iter < 1` |
| `dimred: tolerance must not be negative` | `dimred_power_iteration`, `dimred_pca_fit` | `tol < 0` |
| `dimred: initial vector must not be all zeros` | `dimred_power_iteration` | zero seed |
| `dimred: covariance matrix is zero` | `dimred_power_iteration`, `dimred_pca_fit` | all-zero working matrix |
| `dimred: initial vector is in the null space` | `dimred_power_iteration`, `dimred_pca_fit` | non-zero matrix, iterate collapsed |
| `dimred: power iteration did not converge` | `dimred_power_iteration`, `dimred_pca_fit` | `max_iter` exhausted |
| `dimred: eigenvector length mismatch` | `dimred_deflate` | `ep.vector.len() != rows` |
| `dimred: eigenvector must not be all zeros` | `dimred_deflate` | `v^T v == 0` |
| `dimred: component length mismatch` | `dimred_project` | `component.len() != cols` |
| `dimred: covariance trace must be positive` | `dimred_explained_variance_bps`, `dimred_pca_fit` | `trace <= 0` |
| `dimred: pca needs at least 2 samples` | `dimred_pca_fit` | `rows < 2` |
| `dimred: number of components must be at least 1` | `dimred_pca_fit` | `n_components < 1` |
| `dimred: number of components exceeds feature count` | `dimred_pca_fit` | `n_components > cols` |
| `dimred: feature count does not match the model` | `dimred_pca_transform` | `data.cols != model.n_features` |
| `dimred: model has no components` | `dimred_pca_transform` | `n_components < 1` |
| `dimred: model components are inconsistent` | `dimred_pca_transform` | truncated `components` vector |

Accessors never fail: `dimred_matrix_get`, `dimred_pca_mean`,
`dimred_pca_eigenvalue`, `dimred_pca_explained_bps` and
`dimred_pca_iterations` return 0 out of range; `dimred_pca_component`
returns an empty vector.

## Complexity

| Operation | Complexity |
|---|---|
| `dimred_matrix_new` / `dimred_matrix_data` | O(rows*cols) |
| `dimred_matrix_get` / rows / cols | O(1) |
| `dimred_column_means` / `dimred_center` | O(rows*cols) |
| `dimred_covariance` | O(cols^2 * rows) |
| `dimred_power_iteration` | O(max_iter * features^2) |
| `dimred_deflate` | O(features^2) |
| `dimred_project` | O(rows * cols) |
| `dimred_explained_variance_bps` | O(features) |
| `dimred_pca_fit` | O(rows*cols^2 + n_components * max_iter * cols^2) |
| `dimred_pca_transform` | O(rows * n_components * cols) |

## Test plan

`tests/test_conformance.xi` (`module dimred_tests`, 28 named checks, a
hello-style `main` that prints `[PASS]`/`[FAIL]` per check, a summary line,
and returns the failure count). Fixtures are built in-test (no files, no
I/O):

1. scale accessors are 3/3/6;
2. `matrix_new` builds a row-major matrix (shape + get + out-of-range 0);
3. `matrix_new` rejects bad dimensions and lengths;
4. `matrix_new` copies the caller values;
5. `column_means` computes exact means;
6. `column_means` rounds halves away from zero (both signs);
7. `column_means` rejects an empty matrix;
8. `center` subtracts the means;
9. `center` rejects a means length mismatch;
10. covariance of a rank-1 centered cloud (known entries);
11. covariance of 2-cluster data is exact (`[[19232, 16], [16, 8]]`);
12. covariance needs at least 2 samples;
13. power iteration on a diagonal covariance (exact eigenvalue/vector);
14. power iteration on a general 2x2 covariance (banded eigenvalue,
    eigenvector direction, iteration budget);
15. power iteration rejects zero covariance and zero init;
16. power iteration validates its parameters;
17. power iteration reports non-convergence (`tol = 0`, 3 iterations);
18. deflation removes the dominant eigenpair (diagonal case, then second
    eigenpair by power iteration);
19. deflation preserves the remaining eigenvalue (2x2 general case, trace
    identity and second eigenpair);
20. deflation validates the eigenvector;
21. projection returns exact scores and a zero sum;
22. projection validates the component length and empty matrices;
23. explained variance is bps of the trace (8000/2000, clamping, zero trace
    error);
24. `pca_fit` recovers the 2-cluster direction (means, component, eigenvalue,
    bps, iterations);
25. `pca_transform` separates the clusters (shape, score signs, orthogonal
    component scores);
26. `pca_fit` validates its parameters;
27. pca accessors are range-safe (out-of-range 0/empty, feature mismatch);
28. `pca_fit` rejects a constant dataset (zero trace).

Run from the repository root:

```
.\scripts\port.ps1 -Package xiom.dimred
```

Last verified: compiler 0.62.0 (repo release) and 0.62.1 (installed),
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)` on both.

## Known limitations

- Fixed scales (3/3/6) and the envelope in "Safe magnitude envelope"; no
  overflow detection, no dynamic rescaling.
- Deflation accumulates truncation error; only a few leading components are
  reliable, and `explained_bps` may not sum to 10000.
- `pca_fit` uses the all-ones seed; a dominant eigenvector orthogonal to it
  can collapse the iteration (reported as an error).
- The eigenvalue estimate is the infinity norm (`||A v||_inf`), not a
  Rayleigh quotient; it converges with the vector but can lag slightly on
  ill-separated spectra.
- No covariance shrinkage, no normalization/whitening, no missing-value
  handling; data must be complete and reasonably scaled by the caller.
- Not thread-safe; no global state.

## Compiler notes (pinned v0.62.0, also green on v0.62.1)

- Free functions only; explicit `&`/`&mut`; no methods.
- `Ok`/`Err` are constructed only in the leaf helpers
  `_ok_matrix`/`_err_matrix`, `_ok_ints`/`_err_ints`, `_ok_int`/`_err_int`,
  `_ok_eigen`/`_err_eigen`, `_ok_model`/`_err_model` (the documented v0.62.0
  code-shape hazard).
- Str equality in the tests goes through
  `xiom.string.compare.str_compare` (BUG 17 family), never `==`.
- All Vec element reads go through typed `let`; all matrices and vectors use
  canonical `Vec[Int]` / `Result[T, Str]` brackets; no `Vec[Float64]`
  anywhere.
- `_mul_div1e6` and `_div_round` implement the rounded/truncated division
  rules; no sign-bit tests or bitfield tricks (unreliable on the pin).
