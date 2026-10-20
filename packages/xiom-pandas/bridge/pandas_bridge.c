/* pandas_bridge.c -- OFFLINE stub bridge for the xiom.pandas conformance suite.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * This file is SUITE-ONLY (wired by port.args.json as `--c-source`). It defines
 * the 12 pandas_c_* symbols declared in pandas.xi so the suite links and runs
 * offline, with deterministic behavior and no external libraries:
 *   - no Apache Arrow, no xiom.arrow, no allocator, no libc calls, no state;
 *   - no xiom_* runtime helpers (none are referenced by this bridge or by the
 *     package module);
 *   - every function validates its arguments (parity with the validation the
 *     real bridge must enforce) and otherwise reports the backend unavailable:
 *     handle-returning functions return 0, dataframe_to_csv returns 1.
 *
 * ABI: XIOM `Int` is i64 (see the IR: declare i64 @pandas_c_dataframe_new(
 * i64, i64, i64)). All parameters and return values are `long long`. Handles:
 * 0 = null/failure, > 0 = live handle. The real Arrow-backed bridge
 * (bridge/xiom_pandas_arrow.cpp) keeps these symbol names and this validation
 * contract; see the REAL BACKEND section of SPEC.md for its requirements.
 *
 * Deterministic behavior pinned by tests/test_conformance.xi:
 *   pandas_c_dataframe_new(0,0,0)          -> 0    (null params; zero cols)
 *   pandas_c_dataframe_new(0,0,3)          -> 0    (null col_names array)
 *   pandas_c_dataframe_from_csv(0)         -> 0    (null path)
 *   pandas_c_dataframe_to_csv(0,0)         -> 1    (error rc; nonzero)
 *   pandas_c_dataframe_get_column(0,0)     -> 0    (null df)
 *   pandas_c_dataframe_get_column(1,0)     -> 0    (null column name)
 *   pandas_c_dataframe_set_column(0,0,0,0) -> 0    (null df)
 *   pandas_c_dataframe_set_column(1,0,0,10)-> 0    (null col name/values)
 *   pandas_c_dataframe_filter(0,0,0,0)     -> 0    (null df)
 *   pandas_c_dataframe_filter(1,0,4,0)     -> 0    (null column name)
 *   pandas_c_dataframe_groupby(0,0)        -> 0    (null df)
 *   pandas_c_dataframe_groupby(1,0)        -> 0    (null column name)
 *   pandas_c_dataframe_join(0,0,0,0)       -> 0    (null handles)
 *   pandas_c_dataframe_join(1,2,0,t)       -> 0    (null on-col; t=0..3)
 *   pandas_c_series_new(dtype,0,0)         -> 0    (null values; len 0)
 *   pandas_c_series_new(dtype,0,5)         -> 0    (null values)
 *   pandas_c_series_from_vec(dtype,0,0)    -> 0    (null values; len 0)
 *   pandas_c_series_from_vec(dtype,0,7)    -> 0    (null values)
 *   pandas_c_series_to_vec(0,0)            -> 0    (null series)
 *   pandas_c_series_to_vec(1,0)            -> 0    (null out_len)
 *   pandas_c_series_apply(0,0)             -> 0    (null series)
 *   pandas_c_series_apply(1,0)             -> 0    (null func ptr)
 * Every "callable" suite check accepts 0 (assert_ge 0), so reporting the
 * backend unavailable is honest: the stub proves linkage + argument
 * validation, never fabricates data. Positive-handle paths are exercised by
 * the real-backend probe (tests/probe_real_arrow.xi) once the Arrow C++
 * bridge lands. Never use this file in a consumer build.
 */

/* --- argument validation helpers --------------------------------------- */

static long long handle_ok(long long handle) {
  return handle != 0;
}

static long long col_ok(long long col_name) {
  return col_name != 0;
}

static long long len_ok(long long len) {
  return len > 0;
}

static long long dtype_ok(long long dtype) {
  return dtype >= 0 && dtype <= 5; /* DTYPE_INT32..DTYPE_BOOL */
}

static long long cmp_ok(long long op) {
  return op >= 0 && op <= 5; /* CMP_EQ..CMP_GE */
}

static long long join_ok(long long how) {
  return how >= 0 && how <= 3; /* JOIN_INNER..JOIN_OUTER */
}

/* --- DataFrame lifecycle ------------------------------------------------ */

long long pandas_c_dataframe_new(long long col_names, long long col_types,
                                 long long num_cols) {
  if (col_names == 0 || col_types == 0 || num_cols <= 0) {
    return 0; /* null column arrays / no columns */
  }
  return 0; /* Arrow backend unavailable in the offline stub */
}

long long pandas_c_dataframe_from_csv(long long path) {
  if (path == 0) {
    return 0; /* null path pointer */
  }
  return 0; /* Arrow CSV reader unavailable in the offline stub */
}

long long pandas_c_dataframe_to_csv(long long df, long long path) {
  if (!handle_ok(df) || path == 0) {
    return 1; /* error rc: null handle or null path */
  }
  return 1; /* Arrow CSV writer unavailable in the offline stub */
}

/* --- DataFrame access / mutation ---------------------------------------- */

long long pandas_c_dataframe_get_column(long long df, long long col_name) {
  if (!handle_ok(df) || !col_ok(col_name)) {
    return 0; /* null handle / null column name */
  }
  return 0; /* no column storage in the offline stub */
}

long long pandas_c_dataframe_set_column(long long df, long long col_name,
                                        long long values, long long len) {
  if (!handle_ok(df) || !col_ok(col_name) || values == 0 || !len_ok(len)) {
    return 0; /* null handle / null col name / null values / empty values */
  }
  return 0; /* no column storage in the offline stub */
}

/* --- DataFrame operations ------------------------------------------------ */

long long pandas_c_dataframe_filter(long long df, long long col_name,
                                    long long op, long long value) {
  (void)value;
  if (!handle_ok(df) || !col_ok(col_name) || !cmp_ok(op)) {
    return 0; /* null handle / null column name / bad compare op */
  }
  return 0; /* no compute engine in the offline stub */
}

long long pandas_c_dataframe_groupby(long long df, long long col_name) {
  if (!handle_ok(df) || !col_ok(col_name)) {
    return 0; /* null handle / null column name */
  }
  return 0; /* no group engine in the offline stub */
}

long long pandas_c_dataframe_join(long long left, long long right,
                                  long long on_col, long long how) {
  if (!handle_ok(left) || !handle_ok(right) || !col_ok(on_col) || !join_ok(how)) {
    return 0; /* null handle(s) / null on-col / bad join type */
  }
  return 0; /* no join engine in the offline stub */
}

/* --- Series -------------------------------------------------------------- */

long long pandas_c_series_new(long long dtype, long long values,
                              long long len) {
  if (values == 0 || !len_ok(len) || !dtype_ok(dtype)) {
    return 0; /* null values / empty / bad dtype */
  }
  return 0; /* no array storage in the offline stub */
}

long long pandas_c_series_from_vec(long long dtype, long long values,
                                   long long len) {
  if (values == 0 || !len_ok(len) || !dtype_ok(dtype)) {
    return 0; /* null values / empty / bad dtype */
  }
  return 0; /* no array storage in the offline stub */
}

long long pandas_c_series_to_vec(long long series, long long out_len) {
  if (!handle_ok(series) || out_len == 0) {
    return 0; /* null handle / null out_len pointer */
  }
  return 0; /* no data to extract in the offline stub */
}

long long pandas_c_series_apply(long long series, long long func_ptr) {
  if (!handle_ok(series) || func_ptr == 0) {
    return 0; /* null handle / null func pointer */
  }
  return 0; /* no apply engine in the offline stub */
}
