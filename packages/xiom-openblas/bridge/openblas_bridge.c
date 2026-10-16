/* openblas_bridge.c -- offline link-seam bridge for xiom.openblas (Phase 1).
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * STUB BUILD -- this file is NOT OpenBLAS. It provides the extern "C" surface
 * declared in openblas.xi (cblas_* and dgesvd_/dsyev_/dgesv_) so the package
 * links and its conformance suite runs on machines with no system OpenBLAS
 * installed. The module's Phase-1 computations run through the pure-XIOM
 * reference loops in openblas.xi and never call these symbols; this bridge is
 * the offline leg of the two-leg split (see SPEC.md / README.md).
 *
 * ABI: matches the declarations in openblas.xi exactly -- blasint is int32_t
 * (standard LP64 OpenBLAS build), doubles are double, pointers are raw. The
 * real library is intentionally NOT linked here: linking a real OpenBLAS
 * together with this stub would be a duplicate-symbol error. The real leg
 * (tests/probe_real_openblas.xi + tests/probe_openblas_shim.c) loads a system
 * OpenBLAS at runtime and exercises cblas_ddot/cblas_dgemm against it.
 *
 * Stub semantics (documented, deterministic):
 *   - every entry point validates its pointer arguments; a null pointer is
 *     an immediate no-op (BLAS) / leaves *info = STUB_INFO (LAPACK);
 *   - a valid BLAS call is a NO-OP and returns 0.0 from cblas_ddot -- the
 *     stub computes nothing and must not be used as a computation source;
 *   - a valid LAPACK call writes STUB_INFO (-999, "backend not linked") to
 *     *info when info is non-null.
 *
 * Wired into the suite run via port.args.json:
 *   xiom --run tests/test_conformance.xi --c-source <pkg>/bridge/openblas_bridge.c
 *
 * Phase 2 replaces this seam with real linkage: build without --c-source
 * bridge/openblas_bridge.c and link the system OpenBLAS import library
 * (see ROADMAP.md Phase 1 remaining items).
 */

#include <stdint.h>

#define OBLAS_STUB_INFO (-999)

/* ---- BLAS Level 1 ------------------------------------------------------ */

double cblas_ddot(int32_t n, const double* x, int32_t incx, const double* y, int32_t incy) {
  (void)incx;
  (void)incy;
  if (n <= 0 || x == 0 || y == 0) return 0.0;
  return 0.0; /* stub: computes nothing */
}

void cblas_daxpy(int32_t n, double alpha, const double* x, int32_t incx, double* y, int32_t incy) {
  (void)n;
  (void)alpha;
  (void)incx;
  (void)incy;
  if (x == 0 || y == 0) return;
  /* stub: computes nothing */
}

/* ---- BLAS Level 2 ------------------------------------------------------ */

void cblas_dgemv(int32_t order, int32_t trans, int32_t m, int32_t n,
                 double alpha, const double* a, int32_t lda,
                 const double* x, int32_t incx, double beta, double* y, int32_t incy) {
  (void)order;
  (void)trans;
  (void)m;
  (void)n;
  (void)alpha;
  (void)lda;
  (void)incx;
  (void)beta;
  (void)incy;
  if (a == 0 || x == 0 || y == 0) return;
  /* stub: computes nothing */
}

/* ---- BLAS Level 3 ------------------------------------------------------ */

void cblas_dgemm(int32_t order, int32_t transa, int32_t transb, int32_t m, int32_t n, int32_t k,
                 double alpha, const double* a, int32_t lda,
                 const double* b, int32_t ldb, double beta, double* c, int32_t ldc) {
  (void)order;
  (void)transa;
  (void)transb;
  (void)m;
  (void)n;
  (void)k;
  (void)alpha;
  (void)lda;
  (void)ldb;
  (void)beta;
  (void)ldc;
  if (a == 0 || b == 0 || c == 0) return;
  /* stub: computes nothing */
}

/* ---- LAPACK (Fortran int32 linkage) ------------------------------------ */

void dgesvd_(unsigned char* jobu, unsigned char* jobvt, int32_t* m, int32_t* n,
             double* a, int32_t* lda, double* s, double* u, int32_t* ldu,
             double* vt, int32_t* ldvt, double* work, int32_t* lwork, int32_t* info) {
  (void)jobu;
  (void)jobvt;
  (void)m;
  (void)n;
  (void)a;
  (void)lda;
  (void)s;
  (void)u;
  (void)ldu;
  (void)vt;
  (void)ldvt;
  (void)work;
  (void)lwork;
  if (info == 0) return;
  *info = OBLAS_STUB_INFO;
}

void dsyev_(unsigned char* jobz, unsigned char* uplo, int32_t* n,
            double* a, int32_t* lda, double* w, double* work, int32_t* lwork, int32_t* info) {
  (void)jobz;
  (void)uplo;
  (void)n;
  (void)a;
  (void)lda;
  (void)w;
  (void)work;
  (void)lwork;
  if (info == 0) return;
  *info = OBLAS_STUB_INFO;
}

void dgesv_(int32_t* n, int32_t* nrhs, double* a, int32_t* lda,
            int32_t* ipiv, double* b, int32_t* ldb, int32_t* info) {
  (void)n;
  (void)nrhs;
  (void)a;
  (void)lda;
  (void)ipiv;
  (void)b;
  (void)ldb;
  if (info == 0) return;
  *info = OBLAS_STUB_INFO;
}
