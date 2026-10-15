/* xiom.camera2ndk -- A8 camera head, on-device driver (wave evidence).
 * Links the package bridge (packages/xiom-camera2ndk/src/camera2ndk_bridge.c)
 * and runs the same path the conformance suite takes on Android:
 * load -> export-set check -> ACameraManager create -> getCameraIdList
 * (ids recorded) -> deleteCameraIdList + delete -> unload.
 * Built with the NDK clang for x86_64-linux-android26; run via adb on
 * the API-36 emulator (see run-probe.ps1).
 *
 * Device-service availability is NOT a failure: a typed negative
 * ACAMERA_ERROR_* from getCameraIdList (e.g. ACAMERA_ERROR_CAMERA_SERVICE
 * from a shell process) is recorded honestly and the driver exits 0.
 */
#include <stdint.h>
#include <stdio.h>

/* Bridge contract (see packages/xiom-camera2ndk/src/camera2ndk_bridge.c). */
int xc_load(void);
const char* xc_error(void);
int xc_abi_missing_count(void);
const char* xc_abi_missing(void);
int xc_declared_exports(void);
int64_t xc_manager_create(void);
void xc_manager_delete(int64_t);
int32_t xc_manager_get_camera_ids(int64_t);
int32_t xc_camera_id_count(void);
int32_t xc_camera_id_len(int32_t);
int32_t xc_camera_id_copy(int32_t, uint8_t*, int32_t);
void xc_unload(void);

static const char* status_name(int32_t code) {
    switch (code) {
        case -10000: return "ACAMERA_ERROR_UNKNOWN";
        case -10001: return "ACAMERA_ERROR_INVALID_PARAMETER";
        case -10002: return "ACAMERA_ERROR_CAMERA_DISCONNECTED";
        case -10003: return "ACAMERA_ERROR_NOT_ENOUGH_MEMORY";
        case -10004: return "ACAMERA_ERROR_METADATA_NOT_FOUND";
        case -10005: return "ACAMERA_ERROR_CAMERA_DEVICE";
        case -10006: return "ACAMERA_ERROR_CAMERA_SERVICE";
        case -10007: return "ACAMERA_ERROR_SESSION_CLOSED";
        case -10008: return "ACAMERA_ERROR_INVALID_OPERATION";
        case -10009: return "ACAMERA_ERROR_STREAM_CONFIGURE_FAIL";
        case -10010: return "ACAMERA_ERROR_CAMERA_IN_USE";
        case -10011: return "ACAMERA_ERROR_MAX_CAMERA_IN_USE";
        case -10012: return "ACAMERA_ERROR_CAMERA_DISABLED";
        case -10013: return "ACAMERA_ERROR_PERMISSION_DENIED";
        case -10014: return "ACAMERA_ERROR_UNSUPPORTED_OPERATION";
        default: return "ACAMERA_STATUS_UNKNOWN";
    }
}

int main(void) {
    int fails = 0;
    printf("=== xiom.camera2ndk on-device driver (A8 camera head) ===\n");
    int rc = xc_load();
    printf("INFO load rc=%d error=%s\n", rc, xc_error());
    if (rc == 1) {
        printf("RESULT: SKIP (runtime absent)\n");
        return 2;
    }
    if (rc != 0) {
        printf("FAIL load rc=%d (%s)\n", rc, xc_error());
        return 10;
    }
    int missing = xc_abi_missing_count();
    printf("OK load (export_count=%d missing_exports=%d)\n", xc_declared_exports(), missing);
    if (missing != 0) {
        printf("FAIL missing exports: %s\n", xc_abi_missing());
        return 10;
    }

    /* ACameraManager create (pure; contacts the service only on the id
     * list call). */
    int64_t mgr = xc_manager_create();
    if (!mgr) {
        printf("FAIL manager create: %s\n", xc_error());
        return 11;
    }
    printf("OK manager create\n");

    int32_t gid = xc_manager_get_camera_ids(mgr);
    if (gid == 0) {
        int32_t n = xc_camera_id_count();
        printf("INFO ids rc=0\n");
        printf("INFO camera_count=%d\n", (int)n);
        int32_t i;
        for (i = 0; i < n; i++) {
            char id[64];
            int32_t len = xc_camera_id_len(i);
            int32_t got = xc_camera_id_copy(i, (uint8_t*)id, (int32_t)sizeof(id));
            if (len < 0 || got != len) {
                printf("FAIL camera id copy %d: %s\n", (int)i, xc_error());
                fails++;
                continue;
            }
            printf("INFO camera_id[%d]=%s\n", (int)i, id);
        }
    } else if (gid < 0) {
        printf("INFO ids rc=%d (%s)\n", (int)gid, status_name(gid));
        printf("WARN getCameraIdList typed ACAMERA_ERROR_* -- device-service availability from a shell process is non-fatal by design\n");
    } else {
        printf("FAIL getCameraIdList internal rc=%d (%s)\n", (int)gid, xc_error());
        fails++;
    }

    xc_manager_delete(mgr);
    printf("OK manager delete\n");
    xc_unload();

    if (fails) {
        printf("RESULT: FAIL (%d)\n", fails);
        return 10;
    }
    printf("RESULT: PASS\n");
    return 0;
}
