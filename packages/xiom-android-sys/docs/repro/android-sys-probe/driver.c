/* xiom.android-sys -- A12 on-device driver (evidence), 0.2.0 surface.
 * Links the five package bridges (the five bridge C units in
 * packages/xiom-android-sys/src) and runs the same paths
 * the conformance suite takes on Android:
 *   log+sync : load -> core export-set check -> functional liblog head
 *              (write/print/is_loggable) -> libsync typed error path
 *   binder   : class define -> create -> associate/isAlive/isRemote/ping
 *              -> refcount inc/dec -> destroy -> descriptor
 *   nnapi    : device query + offline model build (3 tensors + ADD +
 *              identify + finish) -> compilation create/finish ->
 *              execution create/free
 *   zlib     : version + crc32/adler32 known answers + compress->
 *              uncompress roundtrip + deflate/inflate stream roundtrip
 *   icu      : declared-subset scan + UTF-8<->UTF-16 roundtrip +
 *              u_strlen + case mapping
 *
 * Also cross-checks the transcription against the real NDK r27b headers
 * at BUILD time (_Static_assert): log priorities/ids, SYNC_IOC_*, struct
 * sizes/offsets, binder_status_t, NNAPI operand/op/error/device codes,
 * zlib rc values, UErrorCode values / ICU version.  This is the
 * oracle==bound proof for the constants in the modules.
 *
 * Built with the NDK clang for x86_64-linux-android28 (API 28 so the
 * sysroot zlib.h reports the modern 1.3.0.1-motley pin that API-36
 * devices ship); run via adb on the API-36 emulator (see run-probe.ps1).
 */
#if !defined(__ANDROID_API__) || __ANDROID_API__ < 28
#error "probe targets API 28+: the r27b sysroot zlib.h reports 1.2.8 for lower targets while modern devices ship 1.3.0.1-motley"
#endif
#include <android/NeuralNetworks.h>
#include <android/binder_ibinder.h>
#include <android/binder_status.h>
#include <android/log.h>
#include <android/sync.h>
#include <dlfcn.h>
#include <errno.h>
#include <linux/sync_file.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unicode/uchar.h>
#include <unicode/ustring.h>
#include <unicode/utypes.h>
#include <zlib.h>

/* ---- build-time oracle cross-check (compile fails on any drift) -------- */

/* android_LogPriority (android/log.h) */
_Static_assert(ANDROID_LOG_UNKNOWN == 0, "priority UNKNOWN");
_Static_assert(ANDROID_LOG_DEFAULT == 1, "priority DEFAULT");
_Static_assert(ANDROID_LOG_VERBOSE == 2, "priority VERBOSE");
_Static_assert(ANDROID_LOG_DEBUG == 3, "priority DEBUG");
_Static_assert(ANDROID_LOG_INFO == 4, "priority INFO");
_Static_assert(ANDROID_LOG_WARN == 5, "priority WARN");
_Static_assert(ANDROID_LOG_ERROR == 6, "priority ERROR");
_Static_assert(ANDROID_LOG_FATAL == 7, "priority FATAL");
_Static_assert(ANDROID_LOG_SILENT == 8, "priority SILENT");

/* log_id (android/log.h) */
_Static_assert(LOG_ID_MIN == 0, "log id MIN");
_Static_assert(LOG_ID_MAIN == 0, "log id MAIN");
_Static_assert(LOG_ID_RADIO == 1, "log id RADIO");
_Static_assert(LOG_ID_EVENTS == 2, "log id EVENTS");
_Static_assert(LOG_ID_SYSTEM == 3, "log id SYSTEM");
_Static_assert(LOG_ID_CRASH == 4, "log id CRASH");
_Static_assert(LOG_ID_STATS == 5, "log id STATS");
_Static_assert(LOG_ID_SECURITY == 6, "log id SECURITY");
_Static_assert(LOG_ID_KERNEL == 7, "log id KERNEL");
_Static_assert(LOG_ID_MAX == 8, "log id MAX");
_Static_assert(LOG_ID_DEFAULT == 0x7FFFFFFF, "log id DEFAULT");

/* linux/sync_file.h: struct shapes + the derived ioctl values */
_Static_assert(sizeof(struct sync_merge_data) == 48, "sync_merge_data size");
_Static_assert(sizeof(struct sync_file_info) == 56, "sync_file_info size");
_Static_assert(sizeof(struct sync_fence_info) == 80, "sync_fence_info size");
_Static_assert(sizeof(struct sync_set_deadline) == 16, "sync_set_deadline size");
_Static_assert(offsetof(struct sync_file_info, status) == 32, "sync_file_info.status");
_Static_assert(offsetof(struct sync_file_info, flags) == 36, "sync_file_info.flags");
_Static_assert(offsetof(struct sync_file_info, num_fences) == 40, "sync_file_info.num_fences");
_Static_assert(offsetof(struct sync_fence_info, status) == 64, "sync_fence_info.status");
_Static_assert(SYNC_IOC_MAGIC == '>', "SYNC_IOC_MAGIC");
_Static_assert(SYNC_IOC_MERGE == 0xC0303E03u, "SYNC_IOC_MERGE");
_Static_assert(SYNC_IOC_FILE_INFO == 0xC0383E04u, "SYNC_IOC_FILE_INFO");
_Static_assert(SYNC_IOC_SET_DEADLINE == 0x40103E05u, "SYNC_IOC_SET_DEADLINE");

/* errno family (asm-generic) */
_Static_assert(EBADF == 9, "EBADF");
_Static_assert(EINVAL == 22, "EINVAL");

/* binder_status_t pins (android/binder_status.h vs the bridge constants) */
_Static_assert(STATUS_OK == 0, "STATUS_OK");
_Static_assert(STATUS_UNKNOWN_ERROR == -2147483648, "STATUS_UNKNOWN_ERROR");
_Static_assert(STATUS_NO_MEMORY == -12, "STATUS_NO_MEMORY");
_Static_assert(STATUS_INVALID_OPERATION == -38, "STATUS_INVALID_OPERATION");
_Static_assert(STATUS_BAD_VALUE == -22, "STATUS_BAD_VALUE");
_Static_assert(STATUS_BAD_TYPE == -2147483647, "STATUS_BAD_TYPE");
_Static_assert(STATUS_NAME_NOT_FOUND == -2, "STATUS_NAME_NOT_FOUND");
_Static_assert(STATUS_PERMISSION_DENIED == -1, "STATUS_PERMISSION_DENIED");
_Static_assert(STATUS_NO_INIT == -19, "STATUS_NO_INIT");
_Static_assert(STATUS_ALREADY_EXISTS == -17, "STATUS_ALREADY_EXISTS");
_Static_assert(STATUS_DEAD_OBJECT == -32, "STATUS_DEAD_OBJECT");
_Static_assert(STATUS_FAILED_TRANSACTION == -2147483646, "STATUS_FAILED_TRANSACTION");
_Static_assert(STATUS_BAD_INDEX == -75, "STATUS_BAD_INDEX");
_Static_assert(STATUS_NOT_ENOUGH_DATA == -61, "STATUS_NOT_ENOUGH_DATA");
_Static_assert(STATUS_WOULD_BLOCK == -11, "STATUS_WOULD_BLOCK");
_Static_assert(STATUS_TIMED_OUT == -110, "STATUS_TIMED_OUT");
_Static_assert(STATUS_UNKNOWN_TRANSACTION == -74, "STATUS_UNKNOWN_TRANSACTION");
_Static_assert(STATUS_FDS_NOT_ALLOWED == -2147483641, "STATUS_FDS_NOT_ALLOWED");
_Static_assert(STATUS_UNEXPECTED_NULL == -2147483640, "STATUS_UNEXPECTED_NULL");

/* NNAPI pins (android/NeuralNetworksTypes.h vs the bridge/module) */
_Static_assert(ANEURALNETWORKS_FLOAT32 == 0, "OPERAND FLOAT32");
_Static_assert(ANEURALNETWORKS_INT32 == 1, "OPERAND INT32");
_Static_assert(ANEURALNETWORKS_UINT32 == 2, "OPERAND UINT32");
_Static_assert(ANEURALNETWORKS_TENSOR_FLOAT32 == 3, "OPERAND TENSOR_FLOAT32");
_Static_assert(ANEURALNETWORKS_TENSOR_INT32 == 4, "OPERAND TENSOR_INT32");
_Static_assert(ANEURALNETWORKS_ADD == 0, "OP ADD");
_Static_assert(ANEURALNETWORKS_MUL == 18, "OP MUL");
_Static_assert(ANEURALNETWORKS_NO_ERROR == 0, "ERR NO_ERROR");
_Static_assert(ANEURALNETWORKS_OUT_OF_MEMORY == 1, "ERR OUT_OF_MEMORY");
_Static_assert(ANEURALNETWORKS_INCOMPLETE == 2, "ERR INCOMPLETE");
_Static_assert(ANEURALNETWORKS_UNEXPECTED_NULL == 3, "ERR UNEXPECTED_NULL");
_Static_assert(ANEURALNETWORKS_BAD_DATA == 4, "ERR BAD_DATA");
_Static_assert(ANEURALNETWORKS_OP_FAILED == 5, "ERR OP_FAILED");
_Static_assert(ANEURALNETWORKS_BAD_STATE == 6, "ERR BAD_STATE");
_Static_assert(ANEURALNETWORKS_UNMAPPABLE == 7, "ERR UNMAPPABLE");
_Static_assert(ANEURALNETWORKS_OUTPUT_INSUFFICIENT_SIZE == 8, "ERR OUTPUT_INSUFFICIENT_SIZE");
_Static_assert(ANEURALNETWORKS_UNAVAILABLE_DEVICE == 9, "ERR UNAVAILABLE_DEVICE");
_Static_assert(ANEURALNETWORKS_DEAD_OBJECT == 14, "ERR DEAD_OBJECT");
_Static_assert(ANEURALNETWORKS_DEVICE_UNKNOWN == 0, "DEVICE UNKNOWN");
_Static_assert(ANEURALNETWORKS_DEVICE_OTHER == 1, "DEVICE OTHER");
_Static_assert(ANEURALNETWORKS_DEVICE_CPU == 2, "DEVICE CPU");
_Static_assert(ANEURALNETWORKS_DEVICE_GPU == 3, "DEVICE GPU");
_Static_assert(ANEURALNETWORKS_DEVICE_ACCELERATOR == 4, "DEVICE ACCELERATOR");
_Static_assert(sizeof(ANeuralNetworksOperandType) == 24, "OperandType LP64 size");

/* zlib pins (zlib.h vs the bridge) */
_Static_assert(ZLIB_VERNUM == 0x1301, "ZLIB_VERNUM 1.3.0.1");
_Static_assert(Z_OK == 0, "Z_OK");
_Static_assert(Z_STREAM_END == 1, "Z_STREAM_END");
_Static_assert(Z_STREAM_ERROR == -2, "Z_STREAM_ERROR");
_Static_assert(Z_DATA_ERROR == -3, "Z_DATA_ERROR");
_Static_assert(Z_BUF_ERROR == -5, "Z_BUF_ERROR");
_Static_assert(Z_VERSION_ERROR == -6, "Z_VERSION_ERROR");
_Static_assert(Z_DEFAULT_COMPRESSION == -1, "Z_DEFAULT_COMPRESSION");
_Static_assert(Z_FINISH == 4, "Z_FINISH");
_Static_assert(sizeof(uLong) == 8, "uLong LP64");
_Static_assert(sizeof(z_stream) == 112, "z_stream LP64 layout");

/* ICU pins (unicode headers vs the bridge/module) */
_Static_assert(U_ZERO_ERROR == 0, "U_ZERO_ERROR");
_Static_assert(U_ILLEGAL_ARGUMENT_ERROR == 1, "U_ILLEGAL_ARGUMENT_ERROR");
_Static_assert(U_INVALID_CHAR_FOUND == 10, "U_INVALID_CHAR_FOUND");
_Static_assert(U_TRUNCATED_CHAR_FOUND == 11, "U_TRUNCATED_CHAR_FOUND");
_Static_assert(U_ILLEGAL_CHAR_FOUND == 12, "U_ILLEGAL_CHAR_FOUND");
_Static_assert(U_BUFFER_OVERFLOW_ERROR == 15, "U_BUFFER_OVERFLOW_ERROR");
_Static_assert(U_STRING_NOT_TERMINATED_WARNING == -124, "U_STRING_NOT_TERMINATED_WARNING");
_Static_assert(U_ICU_VERSION_MAJOR_NUM == 75, "ICU major version 75");
_Static_assert(sizeof(UChar) == 2, "UChar 16-bit");
_Static_assert(sizeof(UChar32) == 4, "UChar32 32-bit");

/* ---- bridge contracts (the five bridge C units in src/) ---------------- */

int xs_load(void);
const char* xs_error(void);
int xs_abi_missing_count(void);
const char* xs_abi_missing(void);
int xs_ext_count(void);
int xs_ext_missing_count(void);
const char* xs_ext_missing(void);
int xs_errno(void);
int xs_log_write(int32_t, const char*, const char*);
int xs_log_print(int32_t, const char*, const char*);
int xs_log_is_loggable(int32_t, const char*, int32_t);
int xs_log_is_loggable_len(int32_t, const char*, int64_t, int32_t);
int xs_log_buf_write(int32_t, int32_t, const char*, const char*);
int xs_log_minimum_priority(void);
int64_t xs_sync_file_info(int32_t);
int32_t xs_sync_file_info_status(int64_t);
int32_t xs_sync_file_info_num_fences(int64_t);
const char* xs_sync_file_info_name(int64_t);
void xs_sync_file_info_free(int64_t);
int32_t xs_sync_merge(const char*, int32_t, int32_t);
void xs_unload(void);

int xbn_load(void);
const char* xbn_error(void);
int xbn_core_missing_count(void);
const char* xbn_core_missing(void);
int xbn_ext_count(void);
int xbn_ext_missing_count(void);
const char* xbn_ext_missing(void);
int64_t xbn_class_define(const char*);
const char* xbn_class_descriptor(int64_t);
int64_t xbn_create(int64_t, int64_t);
void xbn_inc_strong(int64_t);
void xbn_dec_strong(int64_t);
int xbn_associate_class(int64_t, int64_t);
int xbn_is_alive(int64_t);
int xbn_is_remote(int64_t);
int xbn_ping(int64_t);
int64_t xbn_get_class(int64_t);
int xbn_debug_ref_count(int64_t);
int64_t xbn_calling_uid(void);
int64_t xbn_calling_pid(void);
int xbn_destroy_count(void);
int xbn_transact_count(void);
const char* xbn_status_name(int);
void xbn_unload(void);

int xnn_load(void);
const char* xnn_error(void);
int xnn_core_missing_count(void);
const char* xnn_core_missing(void);
int xnn_ext_count(void);
int xnn_ext_missing_count(void);
const char* xnn_ext_missing(void);
int64_t xnn_model_create(void);
int xnn_model_add_tensor(int64_t, int, const uint8_t*, int, int, int);
int xnn_model_add_operation(int64_t, int, const uint8_t*, int, const uint8_t*, int);
int xnn_model_identify_io(int64_t, const uint8_t*, int, const uint8_t*, int);
int xnn_model_set_scalar_i32(int64_t, int, int32_t);
int xnn_model_finish(int64_t);
void xnn_model_free(int64_t);
int64_t xnn_compilation_create(int64_t);
int xnn_compilation_finish(int64_t);
void xnn_compilation_free(int64_t);
int64_t xnn_execution_create(int64_t);
void xnn_execution_free(int64_t);
int xnn_device_count(void);
int xnn_device_name(int, uint8_t*, int);
int xnn_device_type(int);
int xnn_device_version(int, uint8_t*, int);
int xnn_device_feature_level(int);
int xnn_runtime_feature_level(void);
const char* xnn_error_name(int);
void xnn_unload(void);

int xzl_load(void);
const char* xzl_error(void);
int xzl_core_missing_count(void);
const char* xzl_core_missing(void);
const char* xzl_version(void);
int64_t xzl_compress_bound(int64_t);
int xzl_compress(const uint8_t*, int64_t, uint8_t*, int64_t, uint8_t*);
int xzl_uncompress(const uint8_t*, int64_t, uint8_t*, int64_t, uint8_t*);
int64_t xzl_crc32(int64_t, const uint8_t*, int64_t);
int64_t xzl_adler32(int64_t, const uint8_t*, int64_t);
int64_t xzl_deflate_begin(int);
int xzl_deflate_input(int64_t, const uint8_t*, int64_t);
int xzl_deflate_step(int64_t, uint8_t*, int64_t, int, uint8_t*);
int xzl_deflate_end(int64_t);
int64_t xzl_inflate_begin(void);
int xzl_inflate_input(int64_t, const uint8_t*, int64_t);
int xzl_inflate_step(int64_t, uint8_t*, int64_t, int, uint8_t*);
int xzl_inflate_end(int64_t);
const char* xzl_rc_name(int);
void xzl_unload(void);

int xic_load(void);
const char* xic_error(void);
int xic_declared_total(void);
int xic_required_missing_count(void);
const char* xic_required_missing(void);
int xic_optional_missing_count(void);
const char* xic_optional_missing(void);
const char* xic_error_name(int);
int xic_strlen(const uint8_t*, int);
int xic_utf8_to_utf16(const uint8_t*, uint8_t*, int, uint8_t*);
int xic_utf16_to_utf8(const uint8_t*, int, uint8_t*, int, uint8_t*);
int xic_toupper(int32_t);
int xic_tolower(int32_t);
void xic_unload(void);

/* ---- independent dlsym export scans (not via the bridges) -------------- */

static const char* k_core[] = {
    "__android_log_write", "__android_log_print", "__android_log_vprint",
    "__android_log_assert", "__android_log_buf_write", "__android_log_buf_print",
    "__android_log_is_loggable", "__android_log_is_loggable_len",
    "sync_merge", "sync_file_info", "sync_file_info_free",
};
static const char* k_ext[] = {
    "__android_log_write_log_message", "__android_log_set_logger",
    "__android_log_logd_logger", "__android_log_stderr_logger",
    "__android_log_set_aborter", "__android_log_call_aborter",
    "__android_log_default_aborter", "__android_log_set_minimum_priority",
    "__android_log_get_minimum_priority", "__android_log_set_default_tag",
};
static const char* k_private[] = {
    "sync_wait", "sync_file_info_is_signaled", "sync_get_fence_info",
    "sync_set_deadline",
};
static const char* k_binder_core[] = {
    "AIBinder_Class_define", "AIBinder_new", "AIBinder_incStrong", "AIBinder_decStrong",
    "AIBinder_associateClass", "AIBinder_isAlive", "AIBinder_isRemote", "AIBinder_ping",
    "AIBinder_getClass", "AIBinder_debugGetRefCount", "AIBinder_getCallingUid",
    "AIBinder_getCallingPid",
};
static const char* k_binder_ext[] = {
    "AIBinder_Class_getDescriptor", "AIBinder_Class_setOnDump",
    "AIBinder_Class_disableInterfaceTokenHeader",
};
static const char* k_nnapi_core[] = {
    "ANeuralNetworksModel_create", "ANeuralNetworksModel_addOperand",
    "ANeuralNetworksModel_addOperation", "ANeuralNetworksModel_identifyInputsAndOutputs",
    "ANeuralNetworksModel_setOperandValue",
    "ANeuralNetworksModel_finish", "ANeuralNetworksModel_free",
    "ANeuralNetworksCompilation_create", "ANeuralNetworksCompilation_finish",
    "ANeuralNetworksCompilation_free", "ANeuralNetworksExecution_create",
    "ANeuralNetworksExecution_free",
};
static const char* k_nnapi_ext[] = {
    "ANeuralNetworks_getDeviceCount", "ANeuralNetworks_getDevice",
    "ANeuralNetworksDevice_getName", "ANeuralNetworksDevice_getType",
    "ANeuralNetworksDevice_getVersion", "ANeuralNetworksDevice_getFeatureLevel",
    "ANeuralNetworks_getRuntimeFeatureLevel",
};
static const char* k_zlib_core[] = {
    "zlibVersion", "compress", "compressBound", "uncompress", "crc32", "adler32",
    "deflateInit_", "deflate", "deflateEnd", "inflateInit_", "inflate", "inflateEnd",
};
static const char* k_icu_required[] = {
    "u_errorName_android", "u_strToUTF8_android", "u_strFromUTF8_android",
    "u_toupper_android", "u_tolower_android",
};
static const char* k_icu_optional[] = {
    "u_strlen_android",
};

static void scan_exports(void* lib_a, void* lib_b, const char* const* names, int count,
                         const char* label, int* fails) {
    int missing = 0;
    for (int i = 0; i < count; i++) {
        void* p = dlsym(lib_a, names[i]);
        if (!p && lib_b != lib_a) p = dlsym(lib_b, names[i]);
        if (!p) {
            missing++;
            printf("INFO %s missing: %s\n", label, names[i]);
        }
    }
    printf("INFO %s exports resolved: %d/%d\n", label, count - missing, count);
    if (missing != 0) (*fails)++;
}

static void put_u32_le(uint8_t* b, uint32_t v) {
    b[0] = (uint8_t)(v & 0xFF);
    b[1] = (uint8_t)((v >> 8) & 0xFF);
    b[2] = (uint8_t)((v >> 16) & 0xFF);
    b[3] = (uint8_t)((v >> 24) & 0xFF);
}

static uint64_t get_u64_le(const uint8_t* b) {
    return (uint64_t)b[0] | ((uint64_t)b[1] << 8) | ((uint64_t)b[2] << 16) |
           ((uint64_t)b[3] << 24) | ((uint64_t)b[4] << 32) | ((uint64_t)b[5] << 40) |
           ((uint64_t)b[6] << 48) | ((uint64_t)b[7] << 56);
}

/* ---- per-lib sections --------------------------------------------------- */

static void probe_log_sync(int* fails) {
    printf("--- log + sync (liblog.so + libsync.so) ---\n");
    void* log_lib = dlopen("liblog.so", RTLD_NOW | RTLD_LOCAL);
    void* sync_lib = dlopen("libsync.so", RTLD_NOW | RTLD_LOCAL);
    printf("INFO dlopen: liblog.so=%s libsync.so=%s\n",
           log_lib ? "ok" : dlerror(), sync_lib ? "ok" : dlerror());
    if (!log_lib || !sync_lib) {
        printf("INFO log+sync: SKIP (runtime absent)\n");
        return;
    }
    scan_exports(log_lib, sync_lib, k_core, (int)(sizeof(k_core) / sizeof(k_core[0])), "core (API 26)", fails);
    scan_exports(log_lib, sync_lib, k_ext, (int)(sizeof(k_ext) / sizeof(k_ext[0])), "ext (API 30)", fails);
    for (size_t i = 0; i < sizeof(k_private) / sizeof(k_private[0]); i++) {
        void* p = dlsym(log_lib, k_private[i]);
        if (!p) p = dlsym(sync_lib, k_private[i]);
        printf("INFO private (NDK-undeclared) %s: %s\n", k_private[i], p ? "present" : "absent");
    }

    int rc = xs_load();
    printf("INFO bridge load rc=%d error=%s\n", rc, xs_error());
    if (rc == 1) {
        printf("INFO log+sync: SKIP (bridge reports absent)\n");
        return;
    }
    if (rc != 0) {
        printf("FAIL log+sync bridge load rc=%d (%s)\n", rc, xs_error());
        (*fails)++;
        return;
    }
    int missing = xs_abi_missing_count();
    printf("OK bridge core export set resolved (missing=%d%s%s)\n",
           missing, missing ? ": " : "", xs_abi_missing());
    if (missing != 0) (*fails)++;
    int ext_total = xs_ext_count();
    int ext_missing = xs_ext_missing_count();
    printf("INFO bridge ext (API 30+): %d/%d present%s%s\n",
           ext_total - ext_missing, ext_total,
           ext_missing ? " missing: " : "", xs_ext_missing());

    int w = xs_log_write(ANDROID_LOG_INFO, "xiom-android-sys",
                         "xiom.android-sys probe: __android_log_write ok");
    printf("INFO log: __android_log_write rc=%d (1=written)\n", w);
    if (w != 1) (*fails)++;
    int lpr = xs_log_print(ANDROID_LOG_INFO, "xiom-android-sys",
                           "xiom.android-sys probe: __android_log_print ok");
    printf("INFO log: __android_log_print rc=%d\n", lpr);
    if (lpr != 1) (*fails)++;
    int lg_info = xs_log_is_loggable(ANDROID_LOG_INFO, "xiom-android-sys", ANDROID_LOG_INFO);
    printf("INFO log: is_loggable(INFO, default INFO)=%d (expect 1)\n", lg_info);
    if (lg_info != 1) (*fails)++;
    int lg_verbose = xs_log_is_loggable(ANDROID_LOG_VERBOSE, "xiom-android-sys", ANDROID_LOG_INFO);
    printf("INFO log: is_loggable(VERBOSE, default INFO)=%d (expect 0 off-list; informational)\n", lg_verbose);
    int lg_len = xs_log_is_loggable_len(ANDROID_LOG_INFO, "xiom-android-sys", 16, ANDROID_LOG_INFO);
    printf("INFO log: is_loggable_len(INFO, len=16, default INFO)=%d (expect 1)\n", lg_len);
    if (lg_len != 1) (*fails)++;
    int bw = xs_log_buf_write(LOG_ID_MAIN, ANDROID_LOG_INFO, "xiom-android-sys",
                              "xiom.android-sys probe: __android_log_buf_write ok");
    printf("INFO log: __android_log_buf_write rc=%d\n", bw);
    if (bw != 1) (*fails)++;
    int mp = xs_log_minimum_priority();
    printf("INFO log: minimum_priority=%d (-1 = API-30 ext absent)\n", mp);

    int64_t h = xs_sync_file_info(-1);
    int e1 = xs_errno();
    printf("INFO sync: sync_file_info(-1) handle=%lld errno=%d (%s)\n",
           (long long)h, e1, e1 == EBADF ? "EBADF" : (e1 == EINVAL ? "EINVAL" : "?"));
    if (h != 0 || !(e1 == EBADF || e1 == EINVAL)) (*fails)++;
    int32_t m = xs_sync_merge("xiom-sys-probe", -1, -1);
    int e2 = xs_errno();
    printf("INFO sync: sync_merge(name,-1,-1) rc=%d errno=%d (%s)\n",
           (int)m, e2, e2 == EBADF ? "EBADF" : (e2 == EINVAL ? "EINVAL" : "?"));
    if (m != -1 || !(e2 == EBADF || e2 == EINVAL)) (*fails)++;
    xs_sync_file_info_free(0); /* null-safe free path */
    xs_unload();
    printf("INFO log+sync bridge unloaded\n");
}

static void probe_binder(int* fails) {
    printf("--- binder (libbinder_ndk.so) ---\n");
    void* lib = dlopen("libbinder_ndk.so", RTLD_NOW | RTLD_LOCAL);
    printf("INFO dlopen: libbinder_ndk.so=%s\n", lib ? "ok" : dlerror());
    if (!lib) {
        printf("INFO binder: SKIP (runtime absent)\n");
        return;
    }
    scan_exports(lib, lib, k_binder_core, (int)(sizeof(k_binder_core) / sizeof(k_binder_core[0])),
                 "binder core (API 29)", fails);
    scan_exports(lib, lib, k_binder_ext, (int)(sizeof(k_binder_ext) / sizeof(k_binder_ext[0])),
                 "binder ext (API 31/33)", fails);

    int rc = xbn_load();
    printf("INFO binder bridge load rc=%d error=%s\n", rc, xbn_error());
    if (rc != 0) {
        printf("FAIL binder bridge load rc=%d (%s)\n", rc, xbn_error());
        (*fails)++;
        return;
    }
    int missing = xbn_core_missing_count();
    printf("OK binder core export set resolved (missing=%d%s%s)\n",
           missing, missing ? ": " : "", xbn_core_missing());
    if (missing != 0) (*fails)++;
    printf("INFO binder ext (API 31/33): %d/%d present%s%s\n",
           xbn_ext_count() - xbn_ext_missing_count(), xbn_ext_count(),
           xbn_ext_missing_count() ? " missing: " : "", xbn_ext_missing());

    int64_t clazz = xbn_class_define("xiom.a12.probe");
    printf("INFO binder: class_define handle=%lld\n", (long long)clazz);
    if (clazz == 0) {
        (*fails)++;
        xbn_unload();
        return;
    }
    const char* desc = xbn_class_descriptor(clazz);
    printf("INFO binder: descriptor=\"%s\" (expect xiom.a12.probe)\n", desc);
    if (strcmp(desc, "xiom.a12.probe") != 0) (*fails)++;

    int64_t b = xbn_create(clazz, 42);
    printf("INFO binder: create handle=%lld\n", (long long)b);
    if (b == 0) {
        (*fails)++;
        xbn_unload();
        return;
    }
    int assoc = xbn_associate_class(b, clazz);
    printf("INFO binder: associateClass=%d (expect 1)\n", assoc);
    if (assoc != 1) (*fails)++;
    int64_t got = xbn_get_class(b);
    printf("INFO binder: getClass identity=%s\n", got == clazz ? "same" : "DIFFERENT");
    if (got != clazz) (*fails)++;
    int alive = xbn_is_alive(b);
    int remote = xbn_is_remote(b);
    printf("INFO binder: isAlive=%d isRemote=%d (expect 1/0)\n", alive, remote);
    if (alive != 1 || remote != 0) (*fails)++;
    int ping = xbn_ping(b);
    printf("INFO binder: ping=%d (%s)\n", ping, xbn_status_name(ping));
    if (ping != STATUS_OK) (*fails)++;
    int rc1 = xbn_debug_ref_count(b);
    xbn_inc_strong(b);
    int rc2 = xbn_debug_ref_count(b);
    xbn_dec_strong(b);
    int rc3 = xbn_debug_ref_count(b);
    printf("INFO binder: refcount %d -> inc -> %d -> dec -> %d (expect 1/2/1)\n", rc1, rc2, rc3);
    if (rc1 != 1 || rc2 != 2 || rc3 != 1) (*fails)++;
    int before = xbn_destroy_count();
    xbn_dec_strong(b); /* last strong ref -> onDestroy */
    int after = xbn_destroy_count();
    printf("INFO binder: onDestroy count %d -> %d (expect +1)\n", before, after);
    if (after != before + 1) (*fails)++;
    printf("INFO binder: calling uid=%lld pid=%lld (own identity outside a transaction)\n",
           (long long)xbn_calling_uid(), (long long)xbn_calling_pid());
    printf("INFO binder: transact callbacks observed=%d (transact/parcel surface delta)\n",
           xbn_transact_count());
    xbn_unload();
    printf("INFO binder bridge unloaded\n");
}

static void probe_nnapi(int* fails) {
    printf("--- nnapi (libneuralnetworks.so) ---\n");
    void* lib = dlopen("libneuralnetworks.so", RTLD_NOW | RTLD_LOCAL);
    printf("INFO dlopen: libneuralnetworks.so=%s\n", lib ? "ok" : dlerror());
    if (!lib) {
        printf("INFO nnapi: SKIP (runtime absent)\n");
        return;
    }
    scan_exports(lib, lib, k_nnapi_core, (int)(sizeof(k_nnapi_core) / sizeof(k_nnapi_core[0])),
                 "nnapi core (API 27)", fails);
    scan_exports(lib, lib, k_nnapi_ext, (int)(sizeof(k_nnapi_ext) / sizeof(k_nnapi_ext[0])),
                 "nnapi ext (API 29)", fails);

    int rc = xnn_load();
    printf("INFO nnapi bridge load rc=%d error=%s\n", rc, xnn_error());
    if (rc != 0) {
        printf("FAIL nnapi bridge load rc=%d (%s)\n", rc, xnn_error());
        (*fails)++;
        return;
    }
    int missing = xnn_core_missing_count();
    printf("OK nnapi core export set resolved (missing=%d%s%s)\n",
           missing, missing ? ": " : "", xnn_core_missing());
    if (missing != 0) (*fails)++;
    printf("INFO nnapi ext (API 29): %d/%d present%s%s\n",
           xnn_ext_count() - xnn_ext_missing_count(), xnn_ext_count(),
           xnn_ext_missing_count() ? " missing: " : "", xnn_ext_missing());

    int dc = xnn_device_count();
    printf("INFO nnapi: device count=%d\n", dc);
    for (int i = 0; i < dc && i < 8; i++) {
        char name[256];
        char version[256];
        int n = xnn_device_name(i, (uint8_t*)name, (int)sizeof(name) - 1);
        if (n < 0) n = 0;
        if (n > (int)sizeof(name) - 1) n = (int)sizeof(name) - 1;
        name[n] = 0;
        int v = xnn_device_version(i, (uint8_t*)version, (int)sizeof(version) - 1);
        if (v < 0) v = 0;
        if (v > (int)sizeof(version) - 1) v = (int)sizeof(version) - 1;
        version[v] = 0;
        printf("INFO nnapi: device[%d] name=\"%s\" type=%d feature=%d version=\"%s\"\n",
               i, name, xnn_device_type(i), xnn_device_feature_level(i), version);
    }
    printf("INFO nnapi: runtime feature level=%d\n", xnn_runtime_feature_level());

    int64_t model = xnn_model_create();
    printf("INFO nnapi: model_create handle=%lld\n", (long long)model);
    if (model == 0) {
        (*fails)++;
        xnn_unload();
        return;
    }
    uint8_t dims[4];
    put_u32_le(dims, 2);
    int o0 = xnn_model_add_tensor(model, ANEURALNETWORKS_TENSOR_FLOAT32, dims, 1, 0, 0);
    int o1 = xnn_model_add_tensor(model, ANEURALNETWORKS_TENSOR_FLOAT32, dims, 1, 0, 0);
    int o2 = xnn_model_add_tensor(model, ANEURALNETWORKS_INT32, dims, 0, 0, 0);
    int o3 = xnn_model_add_tensor(model, ANEURALNETWORKS_TENSOR_FLOAT32, dims, 1, 0, 0);
    printf("INFO nnapi: addOperand rc=%d/%d/%d/%d (float32 {2} x2, int32 scalar act, float32 {2} out)\n",
           o0, o1, o2, o3);
    if (o0 != 0 || o1 != 0 || o2 != 0 || o3 != 0) (*fails)++;
    int fused = xnn_model_set_scalar_i32(model, 2, ANEURALNETWORKS_FUSED_NONE);
    printf("INFO nnapi: setOperandValue(act=FUSED_NONE) rc=%d\n", fused);
    if (fused != 0) (*fails)++;
    uint8_t ins[12];
    uint8_t iio[8];
    uint8_t outs[4];
    put_u32_le(ins, 0);
    put_u32_le(ins + 4, 1);
    put_u32_le(ins + 8, 2);
    put_u32_le(iio, 0);
    put_u32_le(iio + 4, 1);
    put_u32_le(outs, 3);
    int op = xnn_model_add_operation(model, ANEURALNETWORKS_ADD, ins, 3, outs, 1);
    printf("INFO nnapi: addOperation ADD (x,y,act)->out rc=%d (%s)\n", op, xnn_error_name(op));
    if (op != 0) (*fails)++;
    int io = xnn_model_identify_io(model, iio, 2, outs, 1);
    printf("INFO nnapi: identifyInputsAndOutputs ({0,1},{3}) rc=%d\n", io);
    if (io != 0) (*fails)++;
    int fin = xnn_model_finish(model);
    printf("INFO nnapi: model finish rc=%d (%s; offline build)\n", fin, xnn_error_name(fin));
    if (fin != 0) (*fails)++;

    if (fin == 0) {
        int64_t comp = xnn_compilation_create(model);
        printf("INFO nnapi: compilation create handle=%lld\n", (long long)comp);
        if (comp == 0) {
            (*fails)++;
        } else {
            int cfin = xnn_compilation_finish(comp);
            printf("INFO nnapi: compilation finish rc=%d (%s%s)\n", cfin, xnn_error_name(cfin),
                   cfin == 0 ? "; device stage OK" : "; documented device-absent path (informational)");
            if (cfin == 0) {
                int64_t ex = xnn_execution_create(comp);
                printf("INFO nnapi: execution create handle=%lld\n", (long long)ex);
                if (ex == 0) (*fails)++;
                xnn_execution_free(ex);
            }
            xnn_compilation_free(comp);
        }
    }
    xnn_model_free(model);
    xnn_unload();
    printf("INFO nnapi bridge unloaded\n");
}

static void probe_zlib(int* fails) {
    printf("--- zlib (libz.so) ---\n");
    void* lib = dlopen("libz.so", RTLD_NOW | RTLD_LOCAL);
    printf("INFO dlopen: libz.so=%s\n", lib ? "ok" : dlerror());
    if (!lib) {
        printf("INFO zlib: SKIP (runtime absent)\n");
        return;
    }
    scan_exports(lib, lib, k_zlib_core, (int)(sizeof(k_zlib_core) / sizeof(k_zlib_core[0])),
                 "zlib core", fails);

    int rc = xzl_load();
    printf("INFO zlib bridge load rc=%d error=%s\n", rc, xzl_error());
    if (rc != 0) {
        printf("FAIL zlib bridge load rc=%d (%s)\n", rc, xzl_error());
        (*fails)++;
        return;
    }
    int missing = xzl_core_missing_count();
    printf("OK zlib core export set resolved (missing=%d%s%s)\n",
           missing, missing ? ": " : "", xzl_core_missing());
    if (missing != 0) (*fails)++;

    const char* v = xzl_version();
    printf("INFO zlib: version=\"%s\" (header ZLIB_VERSION=\"%s\")\n", v, ZLIB_VERSION);
    if (strcmp(v, ZLIB_VERSION) != 0) (*fails)++;

    const uint8_t nine[] = "123456789";
    uint64_t crc = (uint64_t)xzl_crc32(0, nine, 9);
    uint64_t adl = (uint64_t)xzl_adler32(1, nine, 9);
    printf("INFO zlib: crc32(\"123456789\")=0x%08llX (expect 0xCBF43926)\n", (unsigned long long)crc);
    printf("INFO zlib: adler32(\"123456789\")=0x%08llX (expect 0x091E01DE)\n", (unsigned long long)adl);
    if (crc != 0xCBF43926ull) (*fails)++;
    if (adl != 0x091E01DEull) (*fails)++;

    /* compress -> uncompress roundtrip fixture (4096-byte text). */
    static uint8_t src[4096];
    const char* words = "the quick brown fox jumps over the lazy dog while xiom probes the android system surface for the a12 wave ";
    size_t wl = strlen(words);
    for (size_t i = 0; i < sizeof(src); i++) src[i] = (uint8_t)words[i % wl];
    int64_t bound = xzl_compress_bound((int64_t)sizeof(src));
    static uint8_t comp[8192];
    uint8_t slot[8];
    int cz = xzl_compress(src, (int64_t)sizeof(src), comp, (int64_t)sizeof(comp), slot);
    uint64_t clen = get_u64_le(slot);
    printf("INFO zlib: compress rc=%d (%s) 4096 -> %llu bytes (bound %lld)\n",
           cz, xzl_rc_name(cz), (unsigned long long)clen, (long long)bound);
    if (cz != Z_OK || clen >= sizeof(src)) (*fails)++;
    static uint8_t back[4096];
    if (clen <= sizeof(comp)) {
        int uz = xzl_uncompress(comp, (int64_t)clen, back, (int64_t)sizeof(back), slot);
        uint64_t ulen = get_u64_le(slot);
        int exact = (uz == Z_OK && ulen == sizeof(src) && memcmp(back, src, sizeof(src)) == 0);
        printf("INFO zlib: uncompress rc=%d (%s) -> %llu bytes; roundtrip %s\n",
               uz, xzl_rc_name(uz), (unsigned long long)ulen, exact ? "exact" : "MISMATCH");
        if (!exact) (*fails)++;
    }

    /* Streaming basics: deflateInit_/deflate/deflateEnd via handles. */
    int64_t dh = xzl_deflate_begin(Z_DEFAULT_COMPRESSION);
    printf("INFO zlib: deflate_begin handle=%lld\n", (long long)dh);
    if (dh == 0) {
        (*fails)++;
    } else {
        static uint8_t scomp[8192];
        int si = xzl_deflate_input(dh, src, (int64_t)sizeof(src));
        int sr = xzl_deflate_step(dh, scomp, (int64_t)sizeof(scomp), Z_FINISH, slot);
        uint64_t slen = get_u64_le(slot);
        int se = xzl_deflate_end(dh);
        printf("INFO zlib: deflate stream input=%d step rc=%d (%s) end rc=%d -> %llu bytes\n",
               si, sr, xzl_rc_name(sr), se, (unsigned long long)slen);
        if (si != 0 || sr != Z_STREAM_END || se != Z_OK) (*fails)++;
        int64_t ih = xzl_inflate_begin();
        static uint8_t sback[4096];
        int ii = -1;
        int ir = -1;
        int ie = -1;
        uint64_t ilen = 0;
        if (ih != 0) {
            ii = xzl_inflate_input(ih, scomp, (int64_t)slen);
            ir = xzl_inflate_step(ih, sback, (int64_t)sizeof(sback), Z_FINISH, slot);
            ilen = get_u64_le(slot);
            ie = xzl_inflate_end(ih);
        }
        int sexact = (ih != 0 && ii == 0 && ir == Z_STREAM_END && ie == Z_OK &&
                      ilen == sizeof(src) && memcmp(sback, src, sizeof(src)) == 0);
        printf("INFO zlib: inflate stream handle=%lld input=%d step rc=%d (%s) end rc=%d -> %llu bytes; roundtrip %s\n",
               (long long)ih, ii, ir, xzl_rc_name(ir), ie, (unsigned long long)ilen,
               sexact ? "exact" : "MISMATCH");
        if (!sexact) (*fails)++;
    }
    xzl_unload();
    printf("INFO zlib bridge unloaded\n");
}

static void probe_icu(int* fails) {
    printf("--- icu (libandroidicu.so; declared subset) ---\n");
    /* Android ships the ICU C API as libandroidicu.so (the NDK -licuuc
     * soname); libicuuc.so carries the C++ ICU API only. */
    void* lib = dlopen("libandroidicu.so", RTLD_NOW | RTLD_LOCAL);
    printf("INFO dlopen: libandroidicu.so=%s\n", lib ? "ok" : dlerror());
    if (!lib) {
        printf("INFO icu: SKIP (runtime absent)\n");
        return;
    }
    scan_exports(lib, lib, k_icu_required, (int)(sizeof(k_icu_required) / sizeof(k_icu_required[0])),
                 "icu required subset", fails);
    {
        int opt_scan_fails = 0; /* optional set: reported, never gated */
        scan_exports(lib, lib, k_icu_optional,
                     (int)(sizeof(k_icu_optional) / sizeof(k_icu_optional[0])),
                     "icu optional subset (reported)", &opt_scan_fails);
    }

    int rc = xic_load();
    printf("INFO icu bridge load rc=%d error=%s\n", rc, xic_error());
    if (rc != 0) {
        printf("FAIL icu bridge load rc=%d (%s)\n", rc, xic_error());
        (*fails)++;
        return;
    }
    int req_missing = xic_required_missing_count();
    printf("INFO icu required subset: %d/%d resolved%s%s\n",
           (int)(sizeof(k_icu_required) / sizeof(k_icu_required[0])) - req_missing,
           (int)(sizeof(k_icu_required) / sizeof(k_icu_required[0])),
           req_missing ? " missing: " : "", xic_required_missing());
    int opt_missing = xic_optional_missing_count();
    printf("INFO icu optional subset: %d/%d resolved%s%s (u_strlen: header-announced API 31; not exported by the platform shim)\n",
           (int)(sizeof(k_icu_optional) / sizeof(k_icu_optional[0])) - opt_missing,
           (int)(sizeof(k_icu_optional) / sizeof(k_icu_optional[0])),
           opt_missing ? " missing: " : "", xic_optional_missing());
    if (req_missing != 0) {
        /* Version gate by design (API 31+ subset): explicit SKIP. */
        printf("INFO icu: SKIP (gated) -- required subset requires API 31\n");
        xic_unload();
        return;
    }

    const char* en = xic_error_name(U_ZERO_ERROR);
    printf("INFO icu: errorName(U_ZERO_ERROR)=\"%s\"\n", en);
    if (strcmp(en, "U_ZERO_ERROR") != 0) (*fails)++;

    /* UTF-8 -> UTF-16 -> UTF-8 roundtrip: "caf\xc3\xa9 lab". */
    const char* text = "caf\xc3\xa9 lab";
    uint8_t units[64];
    uint8_t slot[8];
    memset(units, 0, sizeof(units));
    int f = xic_utf8_to_utf16((const uint8_t*)text, units, (int)sizeof(units), slot);
    uint64_t ubytes = get_u64_le(slot);
    int ulen = -1;
    if (opt_missing == 0) {
        ulen = xic_strlen(units, (int)(ubytes / 2));
        printf("INFO icu: utf8_to_utf16 rc=%d -> %llu bytes; u_strlen=%d (expect 8 units)\n",
               f, (unsigned long long)ubytes, ulen);
        if (f != 0 || ubytes != 16 || ulen != 8) (*fails)++;
    } else {
        printf("INFO icu: utf8_to_utf16 rc=%d -> %llu bytes; u_strlen gated (optional symbol absent on this shim)\n",
               f, (unsigned long long)ubytes);
        if (f != 0 || ubytes != 16) (*fails)++;
    }
    char back[64];
    memset(back, 0, sizeof(back));
    int b = xic_utf16_to_utf8(units, (int)(ubytes / 2), (uint8_t*)back, (int)sizeof(back), slot);
    uint64_t blen = get_u64_le(slot);
    int exact = (b == 0 && blen == strlen(text) && memcmp(back, text, strlen(text)) == 0);
    printf("INFO icu: utf16_to_utf8 rc=%d -> \"%s\"; roundtrip %s\n", b, back, exact ? "exact" : "MISMATCH");
    if (!exact) (*fails)++;

    int up_a = xic_toupper(0x61);
    int up_e = xic_toupper(0xE9);
    int lo_z = xic_tolower(0x5A);
    int lo_e = xic_tolower(0xC9);
    printf("INFO icu: case a->0x%X e9->0x%X Z->0x%X C9->0x%X (expect 41/C9/7A/E9)\n",
           up_a, up_e, lo_z, lo_e);
    if (up_a != 0x41 || up_e != 0xC9 || lo_z != 0x7A || lo_e != 0xE9) (*fails)++;
    xic_unload();
    printf("INFO icu bridge unloaded\n");
}

int main(void) {
    int fails = 0;

    printf("=== xiom.android-sys on-device driver (A12 system surface 0.2.0, NDK r27b oracle) ===\n");
    printf("INFO header cross-check: log/sync + binder_status + NNAPI codes + zlib + UErrorCode _Static_assert PASS\n");
    printf("INFO registry: all pinned constant families verified against the r27b headers at build time\n");

    probe_log_sync(&fails);
    probe_binder(&fails);
    probe_nnapi(&fails);
    probe_zlib(&fails);
    probe_icu(&fails);

    if (fails) {
        printf("RESULT: FAIL (%d)\n", fails);
        return 11;
    }
    printf("RESULT: PASS\n");
    return 0;
}
