/* XIOM -- xiom.v4l repro probe: pinned-ABI gate + live-path classification.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * Builds the bridge against the REAL pinned kernel UAPI headers, so the two
 * compile-time gates run before anything executes:
 *
 *   1. the bridge's own _Static_asserts (pinned ioctl numbers / sizes /
 *      offsets against its local struct definitions), and
 *   2. the generated 3107-fact gate (docs/repro/gen/v4l2_const_asserts.h,
 *      #included by the bridge under -DXV_USE_REAL_UAPI) against the actual
 *      pinned header text -- every declared constant, every struct size and
 *      every field offset must equal what the pin produces.
 *
 * Then it runs the runtime classification on this host:
 *   - xv_abi_fail_count()/xv_abi_fail_names(): the runtime ABI self-check
 *     (ioctl encodings re-derived from the pinned dir/type/nr/size
 *     quadruples; 0 = full cover, FAIL-able, never silent);
 *   - xv_probe():                     the default /dev scan;
 *   - xv_probe_named(bogus dir):      the deterministic ABSENT (SKIP) path;
 *   - xv_platform():                  0 = Linux device layer reachable.
 *
 * Run on Linux (WSL here; the Pi is the same recipe with arm64 gcc):
 *   gcc -DXV_USE_REAL_UAPI -D__EXPORTED_HEADERS__ \
 *       -I ../uapi-shim -I <kernel>/include/uapi -I <kernel>/arch/x86/include/uapi \
 *       -I gen -o v4l2_abi_probe v4l2_abi_probe.c ../src/v4l2_bridge.c
 *   ./v4l2_abi_probe
 *
 * Exit code: 0 when the ABI self-check is clean and the probe classified
 * cleanly (device found or absent); 2 on ABI faults.
 */

#include <stdio.h>

int xv_platform(void);
int xv_abi_fail_count(void);
const char* xv_abi_fail_names(void);
int xv_probe(void);
int xv_probe_named(const char* dev_dir);
const char* xv_error(void);
int xv_device_count(void);
const char* xv_device_path(int idx);

int main(void) {
  int fails = xv_abi_fail_count();
  int rc;
  printf("xiom.v4l repro probe (bridge built against the pinned UAPI headers)\n");
  printf("  platform           : %s\n", xv_platform() == 0 ? "linux (device layer reachable)" : "non-linux (no device access)");
  printf("  abi_fail_count     : %d\n", fails);
  printf("  abi_fail_names     : %s\n", xv_abi_fail_names());
  if (fails != 0) {
    printf("ABI SELF-CHECK FAILED -- pinned facts drifted\n");
    return 2;
  }
  printf("  abi self-check     : green (ioctl encodings + struct sizes + key offsets re-derived)\n");

  rc = xv_probe_named("/dev/xiom-absent-v4l-root");
  printf("  probe bogus dir    : rc=%d (%s)\n", rc, xv_error());
  if (rc != 1) {
    printf("EXPECTED ABSENT CLASSIFICATION FOR A BOGUS DIR\n");
    return 2;
  }
  printf("  skip-path          : ABSENT classification OK (the suite's deterministic SKIP leg)\n");

  rc = xv_probe();
  if (rc == 0) {
    int i;
    printf("  probe /dev         : rc=0, %d device(s) -- live path available\n", xv_device_count());
    for (i = 0; i < xv_device_count(); i++) {
      printf("    device[%d]        : %s\n", i, xv_device_path(i));
    }
  } else if (rc == 1) {
    printf("  probe /dev         : rc=1 (%s)\n", xv_error());
    printf("  live path          : SKIP -- no V4L2 device layer on this host (recorded)\n");
  } else {
    printf("  probe /dev         : rc=%d (%s)\n", rc, xv_error());
    printf("ABI FAULT DETECTED AT PROBE\n");
    return 2;
  }
  printf("probe done\n");
  return 0;
}
