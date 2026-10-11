/* xiom.spirv-tools probe bridge -- MIT OR Apache-2.0, The XIOM Authors.
 *
 * Two-function copy bridge for the B-20 discipline: XIOM never reads
 * through foreign pointers.  The C side (this file) is the only reader of
 * the SPIRV-Tools-owned memory, and it only ever copies out into an
 * XIOM-owned buffer whose address the caller supplies.
 *
 * Deliberately self-contained: no SPIRV-Tools headers, no SDK includes, no
 * link-time dependency on the DLL.  Symbol contract (declared extern "C"
 * in src/st_readout.xi):
 *
 *   void xst_copy(void* dst, const void* src, unsigned long long n);
 *       memcpy dst <- src, no-op when any argument is NULL/0.
 *   unsigned long long xst_strlen(const void* p);
 *       strlen of a foreign C string, 0 for NULL.
 *
 * Compiled into the suite through port.args.json
 * (--c-source ${PACKAGE_DIR}/src/st_probe_bridge.c); the core loader module
 * does not need it.
 */

#include <string.h>

void xst_copy(void* dst, const void* src, unsigned long long n) {
  if (dst != 0 && src != 0 && n > 0) {
    memcpy(dst, src, (size_t)n);
  }
}

unsigned long long xst_strlen(const void* p) {
  if (p == 0) {
    return 0;
  }
  return (unsigned long long)strlen((const char*)p);
}
