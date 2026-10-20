/* probe_real_arrow_callback.c -- test-only C callback for series_apply.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The owner-pinned series_apply ABI is `double (*)(double)`. XIOM does not
 * expose a C-ABI function-pointer cast, so the evidence probe links this tiny
 * helper and reads the address through `xiom_pandas_probe_double_addr`.
 * This file is NOT part of the package ABI and is never used by the suite.
 */

#include <stdint.h>

double xiom_pandas_probe_double(double x) { return x * 2.0; }

long long xiom_pandas_probe_double_addr(void) {
  return (long long)(intptr_t)&xiom_pandas_probe_double;
}
