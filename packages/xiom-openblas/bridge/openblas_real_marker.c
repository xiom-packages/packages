/* openblas_real_marker.c -- leg marker for the real-linked xiom.openblas leg.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Compiled ONLY on the real leg, together with the system OpenBLAS import
 * library:
 *   xiom --run tests/test_conformance.xi \
 *       --c-source bridge/openblas_real_marker.c \
 *       --link-path <openblas>/lib --link libopenblas
 *
 * This file deliberately defines NO cblas or LAPACK symbol -- those come from
 * OpenBLAS. The stub link-seam (openblas_bridge.c) must never be linked
 * together with this marker: the two legs are separate artifacts.
 */

int xiom_openblas_backend(void) {
  return 1;
}
