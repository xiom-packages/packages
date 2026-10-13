/* xiom.spz compile shim for the vendored zstd single-file amalgamation --
 * MIT OR Apache-2.0 (this file), XIOM Authors.
 *
 * The xiom link line compiles C sources with baseline x86-64 features; zstd's
 * bits.h would otherwise take the BMI2 intrinsics path (STATIC_BMI2 defaults
 * on when the compiler advertises AVX2/BMI2 macros) and fail to inline
 * `_bzhi_u64` without a `-mbmi2` target.  Pinning STATIC_BMI2 to 0 keeps the
 * portable bit helpers; the properly `target("bmi2")`-attributed paths in the
 * decompressor stay available at their own compile sites.
 *
 * Same shim as xiom.zstd (src/zstd_all.c); the vendored zstd.c is unmodified
 * (byte pin in docs/vendor_manifest.json + PROVENANCE.md).
 */
#define STATIC_BMI2 0
#include "../vendor/zstd/zstd.c"
