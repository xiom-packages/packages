# xiom.dimred

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.1` on the XIOM registry.
> **Scope:** fixed-point PCA primitives (mean-centering, sample covariance,
> power iteration, deflation, projection, explained variance) on scaled
> integers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.string` and
> `xiom.convert`; tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`).

## What it is

`xiom.dimred` computes principal components **without floating point**. Every
real number is carried as a 64-bit scaled integer (raw value / 10^decimals),
so results are deterministic and reproducible across machines. The module
covers the classical PCA pipeline in miniature:

- dense row-major matrices over `Vec[Int]` with data scale 3;
- column means and mean-centering;
- sample covariance (denominator `n - 1`) in scaled integer arithmetic;
- dominant eigenpair by power iteration with `max_iter` / `tol` and an `Err`
  on non-convergence;
- deflation (`A - lambda*v*v^T/(v^T v)`) to extract the next component;
- projection of samples onto components (PCA scores);
- explained-variance ratios in basis points;
- `dimred_pca_fit` convenience returning means + components + explained
  variance, plus `dimred_pca_transform` for new samples.

There is no `Float64`, no FFI, no I/O and no global state. See `SPEC.md` for
the exact scaling, rounding and overflow rules.

## Scales

| Quantity | Fraction digits | Raw representation |
|---|---|---|
| Input data, means, scores | 3 | `value * 1000` |
| Covariance, eigenvalues | 3 | `value * 1000` |
| Eigenvectors / components | 6 | `value * 1000000` |

Components are max-normalized: the largest-magnitude entry is `1000000`
(1.000000) and is positive, which removes the sign ambiguity. The eigenvalue
estimate is the infinity norm of `cov * v` for that normalized `v`.

## API

| Function | Returns | Description |
|---|---|---|
| `dimred_data_decimals()` | `Int` | Data/score scale (3). |
| `dimred_covariance_decimals()` | `Int` | Covariance scale (3). |
| `dimred_vector_decimals()` | `Int` | Component scale (6). |
| `dimred_matrix_new(rows, cols, &values)` | `Result[DimredMatrix, Str]` | Row-major matrix; copies `values`; validates shape. |
| `dimred_matrix_rows(m)` / `dimred_matrix_cols(m)` | `Int` | Shape. |
| `dimred_matrix_get(m, row, col)` | `Int` | Entry, or 0 when out of range. |
| `dimred_matrix_data(m)` | `Vec[Int]` | Copy of the flat row-major data. |
| `dimred_column_means(&m)` | `Result[Vec[Int], Str]` | Per-column mean, rounded half away from zero. |
| `dimred_center(&m, &means)` | `Result[DimredMatrix, Str]` | `m[r, c] - means[c]`. |
| `dimred_covariance(&centered)` | `Result[DimredMatrix, Str]` | Symmetric `m x m` sample covariance (`n - 1` denominator). |
| `dimred_power_iteration(&cov, &init, max_iter, tol)` | `Result[Eigenpair, Str]` | Dominant eigenpair; `Err` on non-convergence. |
| `dimred_deflate(&cov, &ep)` | `Result[DimredMatrix, Str]` | Remove one eigenpair from a symmetric matrix. |
| `dimred_project(&centered, &component)` | `Result[Vec[Int], Str]` | One score per sample (data scale). |
| `dimred_explained_variance_bps(eigenvalue, &cov)` | `Result[Int, Str]` | Basis points of the covariance trace, clamped to [0, 10000]. |
| `dimred_pca_fit(&data, n_components, max_iter, tol)` | `Result[PcaModel, Str]` | Means, components, eigenvalues, explained bps, iterations. |
| `dimred_pca_transform(&model, &data)` | `Result[DimredMatrix, Str]` | `n x n_components` scores for new samples. |
| `dimred_pca_n_features(&model)` / `dimred_pca_n_components(&model)` | `Int` | Model shape. |
| `dimred_pca_mean(&model, feature)` | `Int` | Data-scale mean, or 0 when out of range. |
| `dimred_pca_component(&model, comp)` | `Vec[Int]` | Copy of one component; empty when out of range. |
| `dimred_pca_eigenvalue(&model, comp)` | `Int` | Covariance-scale eigenvalue, or 0. |
| `dimred_pca_explained_bps(&model, comp)` | `Int` | Basis points, or 0. |
| `dimred_pca_iterations(&model, comp)` | `Int` | Power iterations spent, or 0. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.dimred;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // Two features, values in thousandths: 1.000 is raw 1000.
  var vals = Vec[Int].new();
  vals.push(1000); vals.push(0);
  vals.push(1200); vals.push(100);
  vals.push(800);  vals.push(-100);
  vals.push(9000); vals.push(0);
  vals.push(9200); vals.push(100);
  vals.push(8800); vals.push(-100);
  match dimred_matrix_new(6, 2, &vals) {
    Ok(data) => {
      match dimred_pca_fit(&data, 2, 500, 5) {
        Ok(model) => {
          io.println(convert.int_to_string(dimred_pca_mean(&model, 0)));        // 5000
          io.println(convert.int_to_string(dimred_pca_explained_bps(&model, 0))); // ~9996
        },
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.dimred
```

Expected tail: 28 `[PASS]` lines, `xiom.dimred: all tests passed`, then
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`. Verified with both
the pinned compiler 0.62.0 (repo release) and 0.62.1 (installed).

## Limitations

- **Fixed scale, fixed envelope:** data/means/scores use 3 fraction digits,
  covariance 3, components 6. The safe magnitude envelope is `|value| <=
  20000`, `samples <= 1000000` and `features <= 16`; outside it, intermediate
  `Int` products can silently overflow (see `SPEC.md` for the arithmetic
  bounds). There is no dynamic rescaling and no overflow detection.
- **PCA only:** power iteration finds the dominant eigenpair of a symmetric
  matrix; components beyond the first are obtained by deflation, which
  accumulates truncation error. This is fine for a handful of leading
  components of well-separated spectra, not a general eigensolver.
- **No full SVD / no rank checks:** singular values, condition numbers and
  numerical rank are not exposed.
- **Seed choice:** `dimred_pca_fit` seeds each power iteration with the
  all-ones vector; a dominant eigenvector exactly orthogonal to it (or a
  positive-semidefinite matrix with a null all-ones direction) can make the
  fit fail with `dimred: initial vector is in the null space`. Call
  `dimred_power_iteration` with your own seed for such inputs.
- **Convergence is data-dependent:** `tol` is an absolute vector-scale
  tolerance; a spectrum with `|lambda1|` close to `|lambda2|` needs more
  iterations and may return `dimred: power iteration did not converge`.
- **Out of scope (future work):** t-SNE, UMAP, general SVD, LDA, ICA,
  randomized/truncated decompositions, sparse matrices, incremental PCA.
- Not thread-safe; the types are plain values with no internal locking.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
