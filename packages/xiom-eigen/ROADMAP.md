# ROADMAP -- xiom-eigen

## Phase 1 -- Core Foundation (CURRENT)

**Status:** In progress -- SPEC layer implemented, stub computations

- [x] Module scaffold (`module xiom.eigen`)
- [x] `pub type EigenMatrix = Int` opaque handle
- [x] Internal pool-based matrix storage (5 parallel Vecs)
- [x] `extern "C"` block: eigen_matrix_create, eigen_matrix_free, eigen_matrix_get, eigen_matrix_set, eigen_matrix_multiply, eigen_matrix_inverse, eigen_matrix_transpose, eigen_matrix_determinant, eigen_solve, eigen_svd, eigen_eigenvalues
- [x] `matrix_create` / `matrix_free` / `matrix_get` / `matrix_set` with contracts
- [x] `matrix_rows` / `matrix_cols` accessors
- [x] Safe wrappers: `matrix_multiply`, `matrix_transpose`, `matrix_determinant`, `matrix_inverse`, `solve` (pure XIOM loop impl)
- [x] Decomposition stubs: `svd`, `eigenvalues` (return identity/zero placeholders)
- [x] 28 conformance tests in `tests/test_conformance.xi`
- [ ] Download Eigen 3.4 headers (`wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz`)
- [ ] Write C bridge (`eigen_bridge.cpp`) -- thin C ABI over Eigen C++ templates
- [ ] Compile bridge `.obj` against Eigen headers
- [ ] Link XIOM module against bridge object
- [ ] Replace pure-XIOM loops with Eigen-native calls through the bridge
- [ ] Replace SVD/eigenvalues stubs with real Eigen::JacobiSVD / Eigen::EigenSolver invocations
- [ ] Run test suite with linked bridge, verify numerical accuracy

**Effort:** ~2 days remaining

## Phase 2 -- Full Eigen Coverage

- [ ] `matrix_add` / `matrix_sub` / `matrix_scale` element-wise operations
- [ ] `matrix_row` / `matrix_col` -- extract single row/column as vector
- [ ] `matrix_block(r, c, rows, cols)` -- sub-matrix views
- [ ] QR decomposition (`Eigen::HouseholderQR`)
- [ ] LU decomposition with partial pivoting (`Eigen::PartialPivLU`)
- [ ] Cholesky decomposition (`Eigen::LLT`, `Eigen::LDLT`)
- [ ] Non-symmetric eigenvalues (`Eigen::EigenSolver`)
- [ ] Least-squares solve (`Eigen::BDCSVD`, `Eigen::CompleteOrthogonalDecomposition`)
- [ ] Condition number estimation

**Effort:** ~3 days

## Phase 3 -- Advanced Linear Algebra

- [ ] Sparse matrix support (`Eigen::SparseMatrix`)
- [ ] Conjugate gradient solver
- [ ] BiCGSTAB solver
- [ ] Sparse LU / Sparse QR
- [ ] Geometry module wrappers (`Eigen::Quaternion`, `Eigen::AngleAxis`)
- [ ] Transform types (`Eigen::Affine3d`, `Eigen::Isometry3d`)
- [ ] Array operations (`Eigen::ArrayWrapper`) -- coefficient-wise math

**Effort:** ~1 week

## Phase 4 -- Performance & Integration

- [ ] SIMD auto-vectorization verification (SSE/AVX/NEON via Eigen)
- [ ] Fixed-size matrix optimization (Matrix2d, Matrix3d, Matrix4d)
- [ ] `package.toml` manifest for `xiom-eigen`
- [ ] CI: matrix of (Linux, macOS, Windows) x (system Eigen headers, vendored headers)
- [ ] Downstream package smoke tests: verify `xiom-robot`, `xiom-cv`, etc. link correctly
- [ ] Benchmark suite: vs NumPy, vs raw C, vs OpenBLAS -- publish in docs/benchmarks.md

**Effort:** ongoing
