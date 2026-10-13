/* XIOM -- xiom.ktx2 zstd compilation shim (MIT OR Apache-2.0, XIOM Authors).
 *
 * The vendored libktx uses the zstd single-file amalgamation at
 * vendor/ktx/external/basisu/zstd/zstd.c (zstd 1.5.5, BSD-3-Clause; see
 * vendor/ktx/external/basisu/zstd/LICENSE). The xiom link line passes
 * -mavx2 to the C compilation but no -mbmi2, while zstd's static-BMI2
 * autodetection (bits.h) turns on the BMI2 intrinsics path whenever
 * _MSC_VER + _M_X64 + __AVX2__ are set -- which would then fail to compile
 * (like the xiom.zstd package's shim). Pinning STATIC_BMI2 to 0 selects the
 * portable path; every other byte of the vendored file is untouched.
 */

#define STATIC_BMI2 0

#include "../vendor/ktx/external/basisu/zstd/zstd.c"
