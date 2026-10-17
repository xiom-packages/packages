/* numpy_bridge.c -- Phase-1 link bridge for xiom.numpy.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Phase 1 scope (see SPEC.md): the extern "C" surface declared in src/numpy.xi
 * and tests/test_conformance.xi must resolve and link so the conformance suite
 * can run. The NumPy C API layer (PyArray_*) is NOT linked yet -- that is
 * Phase 2 (see ROADMAP.md), which requires the NumPy core headers plus
 * xiom.openblas for the BLAS/LAPACK-backed operations. This file therefore
 * calls no NumPy, Python, or OpenBLAS entry points and allocates no memory.
 *
 * ABI: XIOM Int is 64-bit and Float64 is double; every entry point below uses
 * (long long, double) so it matches the extern "C" declarations exactly.
 *
 * Return contract for handle-returning entry points:
 *    0  backend unavailable -- Phase 1 behavior for every otherwise-valid
 *       creation/operation request (the safe wrappers collapse <= 0 to Err)
 *   -1  invalid argument (null pointer, ndim <= 0, unknown dtype, step == 0)
 * The accessors return documented neutral values (0 / 0.0) and the void
 * entry points are safe no-ops, because no array storage exists in Phase 1.
 *
 * Phase 2 replaces this file with the PyArray-backed bridge (numpy_c_bridge.c
 * per ROADMAP.md): same 17 symbols, same signatures, real arrays. The
 * conformance suite then flips its twelve "returns Err" checks to validate
 * runtime results (ROADMAP Phase 2 deliverables).
 *
 * Wired into the suite run via port.args.json:
 *   xiom --run tests/test_conformance.xi --c-source <pkg>/bridge/numpy_bridge.c
 */

/* Dtype codes -- must match src/numpy.xi DTYPE_* constants. */
#define NUMPY_C_DTYPE_INT32 0
#define NUMPY_C_DTYPE_INT64 1
#define NUMPY_C_DTYPE_FLOAT32 2
#define NUMPY_C_DTYPE_FLOAT64 3

static int numpy_c_valid_dtype(long long dtype) {
  return dtype >= NUMPY_C_DTYPE_INT32 && dtype <= NUMPY_C_DTYPE_FLOAT64;
}

long long numpy_c_array_new(long long shape_ptr, long long ndim, long long dtype) {
  if (shape_ptr == 0 || ndim <= 0) return -1;
  if (!numpy_c_valid_dtype(dtype)) return -1;
  return 0;
}

long long numpy_c_array_from_data(long long data_ptr, long long data_len,
                                  long long shape_ptr, long long ndim) {
  if (data_ptr == 0 || data_len <= 0) return -1;
  if (shape_ptr == 0 || ndim <= 0) return -1;
  return 0;
}

long long numpy_c_array_zeros(long long shape_ptr, long long ndim, long long dtype) {
  if (shape_ptr == 0 || ndim <= 0) return -1;
  if (!numpy_c_valid_dtype(dtype)) return -1;
  return 0;
}

long long numpy_c_array_ones(long long shape_ptr, long long ndim, long long dtype) {
  if (shape_ptr == 0 || ndim <= 0) return -1;
  if (!numpy_c_valid_dtype(dtype)) return -1;
  return 0;
}

long long numpy_c_array_arange(double start, double stop, double step) {
  if (step == 0.0) return -1;
  if (step > 0.0 && !(stop > start)) return -1;
  if (step < 0.0 && !(stop < start)) return -1;
  return 0;
}

void numpy_c_array_free(long long arr) {
  /* No storage exists in Phase 1; safe no-op for any handle. */
  (void)arr;
}

double numpy_c_array_get(long long arr, long long indices_ptr, long long ndim) {
  /* No storage exists in Phase 1; documented neutral value. */
  (void)arr;
  (void)indices_ptr;
  (void)ndim;
  return 0.0;
}

void numpy_c_array_set(long long arr, long long indices_ptr, long long ndim, double val) {
  /* No storage exists in Phase 1; safe no-op. */
  (void)arr;
  (void)indices_ptr;
  (void)ndim;
  (void)val;
}

long long numpy_c_array_ndim(long long arr) {
  /* No storage exists in Phase 1; documented neutral value. */
  (void)arr;
  return 0;
}

void numpy_c_array_shape(long long arr, long long out_ptr, long long out_len) {
  /* No storage exists in Phase 1; writes nothing. */
  (void)arr;
  (void)out_ptr;
  (void)out_len;
}

long long numpy_c_array_size(long long arr) {
  /* No storage exists in Phase 1; documented neutral value. */
  (void)arr;
  return 0;
}

static long long numpy_c_binary_op(long long a, long long b) {
  if (a <= 0 || b <= 0) return -1;
  return 0;
}

long long numpy_c_array_add(long long a, long long b) { return numpy_c_binary_op(a, b); }
long long numpy_c_array_sub(long long a, long long b) { return numpy_c_binary_op(a, b); }
long long numpy_c_array_mul(long long a, long long b) { return numpy_c_binary_op(a, b); }
long long numpy_c_array_div(long long a, long long b) { return numpy_c_binary_op(a, b); }
long long numpy_c_array_dot(long long a, long long b) { return numpy_c_binary_op(a, b); }
long long numpy_c_array_matmul(long long a, long long b) { return numpy_c_binary_op(a, b); }
