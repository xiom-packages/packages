/* xiom.android -- A1 window-core bridge, on-device driver (W2a evidence).
 * Links the package bridge (packages/xiom-android/src/android_bridge.c)
 * and runs the same path the conformance suite takes on Android:
 * load -> export-set check -> functional AHardwareBuffer roundtrip.
 * Built with the NDK clang for x86_64-linux-android26; run via adb on
 * the API-36 emulator (see run-probe.ps1).
 */
#include <stdint.h>
#include <stdio.h>

/* Bridge contract (see packages/xiom-android/src/android_bridge.c). */
int xa_load(void);
const char* xa_error(void);
int xa_abi_missing_count(void);
const char* xa_abi_missing(void);
int xa_hwb_is_supported(int32_t, int32_t, int32_t, int64_t);
int64_t xa_hwb_alloc(int32_t, int32_t, int32_t, int64_t);
int32_t xa_hwb_width(int64_t);
int32_t xa_hwb_height(int64_t);
int32_t xa_hwb_format(int64_t);
int32_t xa_hwb_stride(int64_t);
int32_t xa_hwb_layers(int64_t);
int32_t xa_hwb_write_pixel(int64_t, int32_t, int32_t, int32_t);
int64_t xa_hwb_read_pixel(int64_t, int32_t, int32_t);
void xa_hwb_release(int64_t);
int64_t xa_shm_create(const char*, int64_t);
int64_t xa_shm_get_size(int64_t);
int32_t xa_shm_set_prot(int64_t, int32_t);
int32_t xa_shm_write_probe(int64_t, int32_t);
int64_t xa_shm_read_probe(int64_t);
int32_t xa_fd_close(int64_t);
void xa_unload(void);

int main(void) {
    int fails = 0;
    int rc = xa_load();
    printf("INFO load rc=%d error=%s\n", rc, xa_error());
    if (rc == 1) {
        printf("RESULT: SKIP (runtime absent)\n");
        return 2;
    }
    if (rc != 0) {
        printf("FAIL load rc=%d (%s)\n", rc, xa_error());
        return 10;
    }
    int missing = xa_abi_missing_count();
    printf("OK load (missing_exports=%d)\n", missing);
    if (missing != 0) {
        printf("FAIL missing exports: %s\n", xa_abi_missing());
        fails++;
    }

    /* AHardwareBuffer roundtrip: RGBA8 64x64, CPU read+write. */
    int64_t usage = 3 + 0x30;
    int sup = xa_hwb_is_supported(64, 64, 1, usage);
    printf("INFO is_supported=%d\n", sup);
    if (sup != 1) {
        printf("FAIL isSupported != 1\n");
        fails++;
    }
    int64_t h = xa_hwb_alloc(64, 64, 1, usage);
    if (!h) {
        printf("FAIL alloc: %s\n", xa_error());
        return 11;
    }
    printf("OK alloc\n");
    printf("INFO w=%d h=%d fmt=%d stride=%d layers=%d\n",
           xa_hwb_width(h), xa_hwb_height(h), xa_hwb_format(h),
           xa_hwb_stride(h), xa_hwb_layers(h));
    if (xa_hwb_width(h) != 64 || xa_hwb_height(h) != 64 ||
        xa_hwb_format(h) != 1 || xa_hwb_layers(h) != 1 ||
        xa_hwb_stride(h) < 64) {
        printf("FAIL describe\n");
        fails++;
    }
    if (xa_hwb_write_pixel(h, 7, 5, 0x11223344) != 0) {
        printf("FAIL write: %s\n", xa_error());
        fails++;
    }
    int64_t got = xa_hwb_read_pixel(h, 7, 5);
    printf("INFO read=%lld\n", (long long)got);
    if (got != 0x11223344) {
        printf("FAIL pixel roundtrip\n");
        fails++;
    }
    xa_hwb_release(h);

    /* ASharedMemory roundtrip (W2b): memfd 4096, RW, probe write/read. */
    int64_t fd = xa_shm_create("xiom-core-probe", 4096);
    printf("INFO shm fd=%lld\n", (long long)fd);
    if (fd < 0) {
        printf("FAIL shm create: %s\n", xa_error());
        fails++;
    } else {
        int64_t sz = xa_shm_get_size(fd);
        printf("INFO shm size=%lld\n", (long long)sz);
        if (sz != 4096) {
            printf("FAIL shm size\n");
            fails++;
        }
        if (xa_shm_set_prot(fd, 3) != 0) {
            printf("FAIL shm setProt: %s\n", xa_error());
            fails++;
        }
        if (xa_shm_write_probe(fd, 0x11223344) != 0) {
            printf("FAIL shm write: %s\n", xa_error());
            fails++;
        }
        int64_t got2 = xa_shm_read_probe(fd);
        printf("INFO shm read=%lld\n", (long long)got2);
        if (got2 != 0x11223344) {
            printf("FAIL shm roundtrip\n");
            fails++;
        }
        xa_fd_close(fd);
    }

    xa_unload();

    if (fails) {
        printf("RESULT: FAIL (%d)\n", fails);
    } else {
        printf("RESULT: PASS\n");
    }
    return fails ? 10 : 0;
}
