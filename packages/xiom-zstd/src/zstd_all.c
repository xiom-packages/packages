/* xiom.zstd compile shim -- MIT OR Apache-2.0, XIOM Authors.
 *
 * The xiom link line compiles C sources with baseline x86-64 features; zstd's
 * bits.h would otherwise take the BMI2 intrinsics path (STATIC_BMI2 defaults
 * on when the compiler advertises AVX2/BMI2 macros) and fail to inline
 * `_bzhi_u64` without a `-mbmi2` target.  Pinning STATIC_BMI2 to 0 keeps the
 * portable bit helpers; the properly `target("bmi2")`-attributed paths in the
 * decompressor stay available at their own compile sites.
 *
 * The vendored file itself is unmodified (G2 pin in SPEC.md covers it).
 */
#define STATIC_BMI2 0
#include "../vendor/zstd.c"
