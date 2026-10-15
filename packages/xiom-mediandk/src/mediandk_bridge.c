/* XIOM -- xiom.mediandk: libmediandk.so runtime bridge (A7 core media head).
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for the Android NDK media library
 * (NDK r27b oracle: media/NdkMediaCodec.h, NdkMediaFormat.h,
 * NdkMediaExtractor.h, NdkMediaMuxer.h, NdkMediaError.h,
 * NdkMediaDataSource.h, NdkMediaDrm.h + the NdkMediaCrypto.h include of
 * the codec header).  No link-time dependency: libmediandk.so is loaded
 * at RUNTIME (dlopen on Android/Linux, LoadLibraryA on Windows -- where
 * everything classifies ABSENT -> SKIP).  The declared export set (133
 * functions + 143 key data symbols = 276) is verified after load; a
 * present-but-broken install maps to ABI -> FAIL, never a silent SKIP.
 *
 * Pointers never cross the boundary (B-25 discipline): format/codec
 * handles are opaque C pointers kept on the C side and passed as Int64;
 * buffer payloads are staged in a bridge-owned byte slot on the way in
 * and read back one byte at a time from a bridge-owned slot on the way
 * out.  Key data symbols are read C-side and returned as C-owned
 * const char* (read immediately with Str::from_c_str on the XIOM side).
 *
 * Contract (flat extern "C", called from module xiom.mediandk):
 *   int32_t     xm_load_named(const char* soname)  0=ok 1=absent 2=abi
 *   int32_t     xm_load(void)                      "libmediandk.so"
 *   const char* xm_error(void)                     last error / missing list
 *   int32_t     xm_abi_missing_count(void)         unresolved export count
 *   const char* xm_abi_missing(void)               comma-joined missing names
 *   int32_t     xm_export_count(void)              declared export set size
 *   int32_t     xm_key_count(void)                 key data symbols (143)
 *   const char* xm_key_symbol(int32_t index)       symbol name or NULL
 *   const char* xm_key_value(int32_t index)        dlsym'd value or NULL
 *   const char* xm_key_lookup(const char* symbol)  by name, NULL if absent
 *   int64_t     xm_format_new(void)                handle; 0 = failed
 *   int32_t     xm_format_delete(int64_t fmt)      media_status_t
 *   const char* xm_format_to_string(int64_t fmt)   format-owned string
 *   void        xm_format_set_int32(int64_t, const char* name, int32_t v)
 *   int32_t     xm_format_get_int32(int64_t, const char* name)   found?
 *   int64_t     xm_format_slot_int(void)           last getInt32 value
 *   void        xm_format_set_float(int64_t, const char* name, float v)
 *   int32_t     xm_format_get_float(int64_t, const char* name)   found?
 *   float       xm_format_slot_float(void)         last getFloat value
 *   void        xm_format_set_string(int64_t, const char* name,
 *                                    const char* value)
 *   const char* xm_format_get_string(int64_t, const char* name)  NULL=missing
 *   int32_t     xm_format_stage_begin(int32_t size)        0=ok
 *   void        xm_format_stage_byte(int32_t pos, int32_t value)
 *   int32_t     xm_format_set_buffer(int64_t, const char* name) 0=ok
 *   int64_t     xm_format_get_buffer(int64_t, const char* name) size; -1
 *   int32_t     xm_format_slot_byte(int64_t index)         byte; -1
 *   int64_t     xm_codec_create_decoder_by_type(const char* mime) 0=NULL
 *   int32_t     xm_codec_delete(int64_t codec)             media_status_t
 *   void        xm_unload(void)
 *
 * Classification (the suite maps it to markers):
 *   XM_LOAD_ABSENT (1) -> SKIP  (runtime absent; CI stays green)
 *   XM_LOAD_ABI    (2) -> FAIL  (present but exports broken; never silent)
 *
 * Documented out-of-export-set facts (verified with llvm-readelf on the
 * API-35 sysroot stub AND the API-36 device lib, 2026-10-16):
 *   - 16 key symbols declared by the r27b headers are exported by NEITHER
 *     (AMEDIAFORMAT_VIDEO_QP_* x8, KEY_AUDIO_PRESENTATION_PRESENTATION_ID,
 *     KEY_AUDIO_PRESENTATION_PROGRAM_ID, KEY_BUFFER_BATCH_MAX_OUTPUT_SIZE,
 *     KEY_BUFFER_BATCH_THRESHOLD_OUTPUT_SIZE, KEY_IMPORTANCE,
 *     KEY_PICTURE_TYPE, KEY_VIDEO_ENCODING_STATISTICS_LEVEL,
 *     KEY_VIDEO_QP_AVERAGE); they are excluded from the export set and the
 *     constant cluster (no runtime oracle for their values).
 *   - The API-36 lib also exports 37 symbols NOT declared by the r27b
 *     headers (AMediaCodecInfo_*, AMediaCodecStore_*, *ForClient,
 *     mangled forms); out of scope by header oracle.
 */

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xm_lib_t;
static xm_lib_t xm_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xm_dlsym(xm_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xm_dlclose(xm_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xm_lib_t;
static xm_lib_t xm_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xm_dlsym(xm_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xm_dlclose(xm_lib_t h) { if (h) dlclose(h); }
#endif

/* Opaque handle types (never dereferenced C-side beyond passing back). */
typedef struct AMediaFormat AMediaFormat;
typedef struct AMediaCodec AMediaCodec;
typedef int32_t media_status_t;

/* -- bridge state -------------------------------------------------------- */

static xm_lib_t g_lib = 0;
static char g_error[512] = {0};
static char g_missing[4096] = {0};
static int g_missing_count = 0;

/* Owned value slots: the bridge keeps every pointer local (B-25). */
static int64_t g_slot_int = 0;
static float g_slot_float = 0.0f;
static const void* g_slot_buf = 0;
static size_t g_slot_buf_len = 0;
#define XM_STAGE_MAX 4096
static uint8_t g_stage[XM_STAGE_MAX];
static size_t g_stage_len = 0;

static void xm_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

/* -- declared export set -------------------------------------------------
 * Sources (NDK r27b, sysroot usr/include/media/): non-inline functions of
 * NdkMediaCodec.h (+ its NdkMediaCrypto.h include), NdkMediaFormat.h,
 * NdkMediaExtractor.h, NdkMediaMuxer.h, NdkMediaDataSource.h,
 * NdkMediaDrm.h; the AMEDIAFORMAT_KEY and AMEDIACODEC_KEY extern data
 * symbols of NdkMediaCodec.h + NdkMediaFormat.h.  Cross-checked
 * 2026-10-16 against the API-35 link stub dynamic symbol table
 * (llvm-readelf: identical 276-symbol intersection).
 */

static const char* k_fn_set[] = {
    /* NdkMediaCodec.h -- AMediaCodec_* (30) */
    "AMediaCodec_configure",
    "AMediaCodec_createCodecByName",
    "AMediaCodec_createDecoderByType",
    "AMediaCodec_createEncoderByType",
    "AMediaCodec_createInputSurface",
    "AMediaCodec_createPersistentInputSurface",
    "AMediaCodec_delete",
    "AMediaCodec_dequeueInputBuffer",
    "AMediaCodec_dequeueOutputBuffer",
    "AMediaCodec_flush",
    "AMediaCodec_getBufferFormat",
    "AMediaCodec_getInputBuffer",
    "AMediaCodec_getInputFormat",
    "AMediaCodec_getName",
    "AMediaCodec_getOutputBuffer",
    "AMediaCodec_getOutputFormat",
    "AMediaCodec_queueInputBuffer",
    "AMediaCodec_queueSecureInputBuffer",
    "AMediaCodec_releaseCrypto",
    "AMediaCodec_releaseName",
    "AMediaCodec_releaseOutputBuffer",
    "AMediaCodec_releaseOutputBufferAtTime",
    "AMediaCodec_setAsyncNotifyCallback",
    "AMediaCodec_setInputSurface",
    "AMediaCodec_setOnFrameRenderedCallback",
    "AMediaCodec_setOutputSurface",
    "AMediaCodec_setParameters",
    "AMediaCodec_signalEndOfInputStream",
    "AMediaCodec_start",
    "AMediaCodec_stop",
    /* NdkMediaCodec.h -- action codes (2) */
    "AMediaCodecActionCode_isRecoverable",
    "AMediaCodecActionCode_isTransient",
    /* NdkMediaCodec.h -- AMediaCodecCryptoInfo_* (9) */
    "AMediaCodecCryptoInfo_delete",
    "AMediaCodecCryptoInfo_getClearBytes",
    "AMediaCodecCryptoInfo_getEncryptedBytes",
    "AMediaCodecCryptoInfo_getIV",
    "AMediaCodecCryptoInfo_getKey",
    "AMediaCodecCryptoInfo_getMode",
    "AMediaCodecCryptoInfo_getNumSubSamples",
    "AMediaCodecCryptoInfo_new",
    "AMediaCodecCryptoInfo_setPattern",
    /* NdkMediaCrypto.h (codec header include set) -- AMediaCrypto_* (4) */
    "AMediaCrypto_delete",
    "AMediaCrypto_isCryptoSchemeSupported",
    "AMediaCrypto_new",
    "AMediaCrypto_requiresSecureDecoderComponent",
    /* NdkMediaFormat.h -- AMediaFormat_* (21) */
    "AMediaFormat_clear",
    "AMediaFormat_copy",
    "AMediaFormat_delete",
    "AMediaFormat_getBuffer",
    "AMediaFormat_getDouble",
    "AMediaFormat_getFloat",
    "AMediaFormat_getInt32",
    "AMediaFormat_getInt64",
    "AMediaFormat_getRect",
    "AMediaFormat_getSize",
    "AMediaFormat_getString",
    "AMediaFormat_new",
    "AMediaFormat_setBuffer",
    "AMediaFormat_setDouble",
    "AMediaFormat_setFloat",
    "AMediaFormat_setInt32",
    "AMediaFormat_setInt64",
    "AMediaFormat_setRect",
    "AMediaFormat_setSize",
    "AMediaFormat_setString",
    "AMediaFormat_toString",
    /* NdkMediaExtractor.h -- AMediaExtractor_* (21) */
    "AMediaExtractor_advance",
    "AMediaExtractor_delete",
    "AMediaExtractor_getCachedDuration",
    "AMediaExtractor_getFileFormat",
    "AMediaExtractor_getPsshInfo",
    "AMediaExtractor_getSampleCryptoInfo",
    "AMediaExtractor_getSampleFlags",
    "AMediaExtractor_getSampleFormat",
    "AMediaExtractor_getSampleSize",
    "AMediaExtractor_getSampleTime",
    "AMediaExtractor_getSampleTrackIndex",
    "AMediaExtractor_getTrackCount",
    "AMediaExtractor_getTrackFormat",
    "AMediaExtractor_new",
    "AMediaExtractor_readSampleData",
    "AMediaExtractor_seekTo",
    "AMediaExtractor_selectTrack",
    "AMediaExtractor_setDataSource",
    "AMediaExtractor_setDataSourceCustom",
    "AMediaExtractor_setDataSourceFd",
    "AMediaExtractor_unselectTrack",
    /* NdkMediaMuxer.h -- AMediaMuxer_* (11) */
    "AMediaMuxer_addTrack",
    "AMediaMuxer_append",
    "AMediaMuxer_delete",
    "AMediaMuxer_getTrackCount",
    "AMediaMuxer_getTrackFormat",
    "AMediaMuxer_new",
    "AMediaMuxer_setLocation",
    "AMediaMuxer_setOrientationHint",
    "AMediaMuxer_start",
    "AMediaMuxer_stop",
    "AMediaMuxer_writeSampleData",
    /* NdkMediaDataSource.h -- AMediaDataSource_* (9) */
    "AMediaDataSource_close",
    "AMediaDataSource_delete",
    "AMediaDataSource_new",
    "AMediaDataSource_newUri",
    "AMediaDataSource_setClose",
    "AMediaDataSource_setGetAvailableSize",
    "AMediaDataSource_setGetSize",
    "AMediaDataSource_setReadAt",
    "AMediaDataSource_setUserdata",
    /* NdkMediaDrm.h -- AMediaDrm_* (26) */
    "AMediaDrm_closeSession",
    "AMediaDrm_createByUUID",
    "AMediaDrm_decrypt",
    "AMediaDrm_encrypt",
    "AMediaDrm_getKeyRequest",
    "AMediaDrm_getKeyRequestWithDefaultUrlAndType",
    "AMediaDrm_getPropertyByteArray",
    "AMediaDrm_getPropertyString",
    "AMediaDrm_getProvisionRequest",
    "AMediaDrm_getSecureStops",
    "AMediaDrm_isCryptoSchemeSupported",
    "AMediaDrm_openSession",
    "AMediaDrm_provideKeyResponse",
    "AMediaDrm_provideProvisionResponse",
    "AMediaDrm_queryKeyStatus",
    "AMediaDrm_release",
    "AMediaDrm_releaseSecureStops",
    "AMediaDrm_removeKeys",
    "AMediaDrm_restoreKeys",
    "AMediaDrm_setOnEventListener",
    "AMediaDrm_setOnExpirationUpdateListener",
    "AMediaDrm_setOnKeysChangeListener",
    "AMediaDrm_setPropertyByteArray",
    "AMediaDrm_setPropertyString",
    "AMediaDrm_sign",
    "AMediaDrm_verify",
};
#define XM_FN_COUNT (sizeof(k_fn_set) / sizeof(k_fn_set[0]))

static const char* k_key_set[] = {
    /* NdkMediaFormat.h -- AMEDIAFORMAT_KEY_* (136) */
    "AMEDIAFORMAT_KEY_AAC_DRC_ATTENUATION_FACTOR",
    "AMEDIAFORMAT_KEY_AAC_DRC_BOOST_FACTOR",
    "AMEDIAFORMAT_KEY_AAC_DRC_HEAVY_COMPRESSION",
    "AMEDIAFORMAT_KEY_AAC_DRC_TARGET_REFERENCE_LEVEL",
    "AMEDIAFORMAT_KEY_AAC_ENCODED_TARGET_LEVEL",
    "AMEDIAFORMAT_KEY_AAC_MAX_OUTPUT_CHANNEL_COUNT",
    "AMEDIAFORMAT_KEY_AAC_PROFILE",
    "AMEDIAFORMAT_KEY_AAC_SBR_MODE",
    "AMEDIAFORMAT_KEY_ALBUM",
    "AMEDIAFORMAT_KEY_ALBUMART",
    "AMEDIAFORMAT_KEY_ALBUMARTIST",
    "AMEDIAFORMAT_KEY_ALLOW_FRAME_DROP",
    "AMEDIAFORMAT_KEY_ARTIST",
    "AMEDIAFORMAT_KEY_AUDIO_PRESENTATION_INFO",
    "AMEDIAFORMAT_KEY_AUDIO_SESSION_ID",
    "AMEDIAFORMAT_KEY_AUTHOR",
    "AMEDIAFORMAT_KEY_BIT_RATE",
    "AMEDIAFORMAT_KEY_BITRATE_MODE",
    "AMEDIAFORMAT_KEY_BITS_PER_SAMPLE",
    "AMEDIAFORMAT_KEY_CAPTURE_RATE",
    "AMEDIAFORMAT_KEY_CDTRACKNUMBER",
    "AMEDIAFORMAT_KEY_CHANNEL_COUNT",
    "AMEDIAFORMAT_KEY_CHANNEL_MASK",
    "AMEDIAFORMAT_KEY_COLOR_FORMAT",
    "AMEDIAFORMAT_KEY_COLOR_RANGE",
    "AMEDIAFORMAT_KEY_COLOR_STANDARD",
    "AMEDIAFORMAT_KEY_COLOR_TRANSFER",
    "AMEDIAFORMAT_KEY_COMPILATION",
    "AMEDIAFORMAT_KEY_COMPLEXITY",
    "AMEDIAFORMAT_KEY_COMPOSER",
    "AMEDIAFORMAT_KEY_CREATE_INPUT_SURFACE_SUSPENDED",
    "AMEDIAFORMAT_KEY_CRYPTO_DEFAULT_IV_SIZE",
    "AMEDIAFORMAT_KEY_CRYPTO_ENCRYPTED_BYTE_BLOCK",
    "AMEDIAFORMAT_KEY_CRYPTO_ENCRYPTED_SIZES",
    "AMEDIAFORMAT_KEY_CRYPTO_IV",
    "AMEDIAFORMAT_KEY_CRYPTO_KEY",
    "AMEDIAFORMAT_KEY_CRYPTO_MODE",
    "AMEDIAFORMAT_KEY_CRYPTO_PLAIN_SIZES",
    "AMEDIAFORMAT_KEY_CRYPTO_SKIP_BYTE_BLOCK",
    "AMEDIAFORMAT_KEY_CSD",
    "AMEDIAFORMAT_KEY_CSD_0",
    "AMEDIAFORMAT_KEY_CSD_1",
    "AMEDIAFORMAT_KEY_CSD_2",
    "AMEDIAFORMAT_KEY_CSD_AVC",
    "AMEDIAFORMAT_KEY_CSD_HEVC",
    "AMEDIAFORMAT_KEY_D263",
    "AMEDIAFORMAT_KEY_DATE",
    "AMEDIAFORMAT_KEY_DISCNUMBER",
    "AMEDIAFORMAT_KEY_DISPLAY_CROP",
    "AMEDIAFORMAT_KEY_DISPLAY_HEIGHT",
    "AMEDIAFORMAT_KEY_DISPLAY_WIDTH",
    "AMEDIAFORMAT_KEY_DURATION",
    "AMEDIAFORMAT_KEY_ENCODER_DELAY",
    "AMEDIAFORMAT_KEY_ENCODER_PADDING",
    "AMEDIAFORMAT_KEY_ESDS",
    "AMEDIAFORMAT_KEY_EXIF_OFFSET",
    "AMEDIAFORMAT_KEY_EXIF_SIZE",
    "AMEDIAFORMAT_KEY_FLAC_COMPRESSION_LEVEL",
    "AMEDIAFORMAT_KEY_FRAME_COUNT",
    "AMEDIAFORMAT_KEY_FRAME_RATE",
    "AMEDIAFORMAT_KEY_GENRE",
    "AMEDIAFORMAT_KEY_GRID_COLUMNS",
    "AMEDIAFORMAT_KEY_GRID_ROWS",
    "AMEDIAFORMAT_KEY_HAPTIC_CHANNEL_COUNT",
    "AMEDIAFORMAT_KEY_HDR_STATIC_INFO",
    "AMEDIAFORMAT_KEY_HDR10_PLUS_INFO",
    "AMEDIAFORMAT_KEY_HEIGHT",
    "AMEDIAFORMAT_KEY_I_FRAME_INTERVAL",
    "AMEDIAFORMAT_KEY_ICC_PROFILE",
    "AMEDIAFORMAT_KEY_INTRA_REFRESH_PERIOD",
    "AMEDIAFORMAT_KEY_IS_ADTS",
    "AMEDIAFORMAT_KEY_IS_AUTOSELECT",
    "AMEDIAFORMAT_KEY_IS_DEFAULT",
    "AMEDIAFORMAT_KEY_IS_FORCED_SUBTITLE",
    "AMEDIAFORMAT_KEY_IS_SYNC_FRAME",
    "AMEDIAFORMAT_KEY_LANGUAGE",
    "AMEDIAFORMAT_KEY_LAST_SAMPLE_INDEX_IN_CHUNK",
    "AMEDIAFORMAT_KEY_LATENCY",
    "AMEDIAFORMAT_KEY_LEVEL",
    "AMEDIAFORMAT_KEY_LOCATION",
    "AMEDIAFORMAT_KEY_LOOP",
    "AMEDIAFORMAT_KEY_LOW_LATENCY",
    "AMEDIAFORMAT_KEY_LYRICIST",
    "AMEDIAFORMAT_KEY_MANUFACTURER",
    "AMEDIAFORMAT_KEY_MAX_B_FRAMES",
    "AMEDIAFORMAT_KEY_MAX_BIT_RATE",
    "AMEDIAFORMAT_KEY_MAX_FPS_TO_ENCODER",
    "AMEDIAFORMAT_KEY_MAX_HEIGHT",
    "AMEDIAFORMAT_KEY_MAX_INPUT_SIZE",
    "AMEDIAFORMAT_KEY_MAX_PTS_GAP_TO_ENCODER",
    "AMEDIAFORMAT_KEY_MAX_WIDTH",
    "AMEDIAFORMAT_KEY_MIME",
    "AMEDIAFORMAT_KEY_MPEG_USER_DATA",
    "AMEDIAFORMAT_KEY_MPEG2_STREAM_HEADER",
    "AMEDIAFORMAT_KEY_MPEGH_COMPATIBLE_SETS",
    "AMEDIAFORMAT_KEY_MPEGH_PROFILE_LEVEL_INDICATION",
    "AMEDIAFORMAT_KEY_MPEGH_REFERENCE_CHANNEL_LAYOUT",
    "AMEDIAFORMAT_KEY_OPERATING_RATE",
    "AMEDIAFORMAT_KEY_PCM_BIG_ENDIAN",
    "AMEDIAFORMAT_KEY_PCM_ENCODING",
    "AMEDIAFORMAT_KEY_PRIORITY",
    "AMEDIAFORMAT_KEY_PROFILE",
    "AMEDIAFORMAT_KEY_PSSH",
    "AMEDIAFORMAT_KEY_PUSH_BLANK_BUFFERS_ON_STOP",
    "AMEDIAFORMAT_KEY_REPEAT_PREVIOUS_FRAME_AFTER",
    "AMEDIAFORMAT_KEY_ROTATION",
    "AMEDIAFORMAT_KEY_SAMPLE_FILE_OFFSET",
    "AMEDIAFORMAT_KEY_SAMPLE_RATE",
    "AMEDIAFORMAT_KEY_SAMPLE_TIME_BEFORE_APPEND",
    "AMEDIAFORMAT_KEY_SAR_HEIGHT",
    "AMEDIAFORMAT_KEY_SAR_WIDTH",
    "AMEDIAFORMAT_KEY_SEI",
    "AMEDIAFORMAT_KEY_SLICE_HEIGHT",
    "AMEDIAFORMAT_KEY_SLOW_MOTION_MARKERS",
    "AMEDIAFORMAT_KEY_STRIDE",
    "AMEDIAFORMAT_KEY_TARGET_TIME",
    "AMEDIAFORMAT_KEY_TEMPORAL_LAYER_COUNT",
    "AMEDIAFORMAT_KEY_TEMPORAL_LAYER_ID",
    "AMEDIAFORMAT_KEY_TEMPORAL_LAYERING",
    "AMEDIAFORMAT_KEY_TEXT_FORMAT_DATA",
    "AMEDIAFORMAT_KEY_THUMBNAIL_CSD_AV1C",
    "AMEDIAFORMAT_KEY_THUMBNAIL_CSD_HEVC",
    "AMEDIAFORMAT_KEY_THUMBNAIL_HEIGHT",
    "AMEDIAFORMAT_KEY_THUMBNAIL_TIME",
    "AMEDIAFORMAT_KEY_THUMBNAIL_WIDTH",
    "AMEDIAFORMAT_KEY_TILE_HEIGHT",
    "AMEDIAFORMAT_KEY_TILE_WIDTH",
    "AMEDIAFORMAT_KEY_TIME_US",
    "AMEDIAFORMAT_KEY_TITLE",
    "AMEDIAFORMAT_KEY_TRACK_ID",
    "AMEDIAFORMAT_KEY_TRACK_INDEX",
    "AMEDIAFORMAT_KEY_VALID_SAMPLES",
    "AMEDIAFORMAT_KEY_WIDTH",
    "AMEDIAFORMAT_KEY_XMP_OFFSET",
    "AMEDIAFORMAT_KEY_XMP_SIZE",
    "AMEDIAFORMAT_KEY_YEAR",
    /* NdkMediaCodec.h -- AMEDIACODEC_KEY_* (7) */
    "AMEDIACODEC_KEY_HDR10_PLUS_INFO",
    "AMEDIACODEC_KEY_LOW_LATENCY",
    "AMEDIACODEC_KEY_OFFSET_TIME",
    "AMEDIACODEC_KEY_REQUEST_SYNC_FRAME",
    "AMEDIACODEC_KEY_SUSPEND",
    "AMEDIACODEC_KEY_SUSPEND_TIME",
    "AMEDIACODEC_KEY_VIDEO_BITRATE",
};
#define XM_KEY_COUNT (sizeof(k_key_set) / sizeof(k_key_set[0]))

/* -- resolved function pointers (functional head) ------------------------ */

typedef AMediaFormat* (*PFN_format_new)(void);
typedef int32_t (*PFN_format_delete)(AMediaFormat*);
typedef const char* (*PFN_format_to_string)(AMediaFormat*);
typedef bool (*PFN_format_get_int32)(AMediaFormat*, const char*, int32_t*);
typedef bool (*PFN_format_get_float)(AMediaFormat*, const char*, float*);
typedef bool (*PFN_format_get_buffer)(AMediaFormat*, const char*, void**, size_t*);
typedef bool (*PFN_format_get_string)(AMediaFormat*, const char*, const char**);
typedef void (*PFN_format_set_int32)(AMediaFormat*, const char*, int32_t);
typedef void (*PFN_format_set_float)(AMediaFormat*, const char*, float);
typedef void (*PFN_format_set_string)(AMediaFormat*, const char*, const char*);
typedef void (*PFN_format_set_buffer)(AMediaFormat*, const char*, const void*, size_t);
typedef AMediaCodec* (*PFN_codec_create_decoder_by_type)(const char*);
typedef int32_t (*PFN_codec_delete)(AMediaCodec*);

static PFN_format_new p_format_new = 0;
static PFN_format_delete p_format_delete = 0;
static PFN_format_to_string p_format_to_string = 0;
static PFN_format_get_int32 p_format_get_int32 = 0;
static PFN_format_get_float p_format_get_float = 0;
static PFN_format_get_buffer p_format_get_buffer = 0;
static PFN_format_get_string p_format_get_string = 0;
static PFN_format_set_int32 p_format_set_int32 = 0;
static PFN_format_set_float p_format_set_float = 0;
static PFN_format_set_string p_format_set_string = 0;
static PFN_format_set_buffer p_format_set_buffer = 0;
static PFN_codec_create_decoder_by_type p_codec_create_decoder_by_type = 0;
static PFN_codec_delete p_codec_delete = 0;

/* -- load / classify ----------------------------------------------------- */

void xm_unload(void); /* defined at the bottom; used by xm_load_named */

static int xm_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    size_t i;
    for (i = 0; i < XM_FN_COUNT; i++) {
        if (!xm_dlsym(g_lib, k_fn_set[i])) {
            size_t used = strlen(g_missing);
            snprintf(g_missing + used, sizeof(g_missing) - used, "%s%s",
                     used ? "," : "", k_fn_set[i]);
            g_missing_count++;
        }
    }
    for (i = 0; i < XM_KEY_COUNT; i++) {
        if (!xm_dlsym(g_lib, k_key_set[i])) {
            size_t used = strlen(g_missing);
            snprintf(g_missing + used, sizeof(g_missing) - used, "%s%s",
                     used ? "," : "", k_key_set[i]);
            g_missing_count++;
        }
    }
    p_format_new = (PFN_format_new)xm_dlsym(g_lib, "AMediaFormat_new");
    p_format_delete = (PFN_format_delete)xm_dlsym(g_lib, "AMediaFormat_delete");
    p_format_to_string = (PFN_format_to_string)xm_dlsym(g_lib, "AMediaFormat_toString");
    p_format_get_int32 = (PFN_format_get_int32)xm_dlsym(g_lib, "AMediaFormat_getInt32");
    p_format_get_float = (PFN_format_get_float)xm_dlsym(g_lib, "AMediaFormat_getFloat");
    p_format_get_buffer = (PFN_format_get_buffer)xm_dlsym(g_lib, "AMediaFormat_getBuffer");
    p_format_get_string = (PFN_format_get_string)xm_dlsym(g_lib, "AMediaFormat_getString");
    p_format_set_int32 = (PFN_format_set_int32)xm_dlsym(g_lib, "AMediaFormat_setInt32");
    p_format_set_float = (PFN_format_set_float)xm_dlsym(g_lib, "AMediaFormat_setFloat");
    p_format_set_string = (PFN_format_set_string)xm_dlsym(g_lib, "AMediaFormat_setString");
    p_format_set_buffer = (PFN_format_set_buffer)xm_dlsym(g_lib, "AMediaFormat_setBuffer");
    p_codec_create_decoder_by_type =
        (PFN_codec_create_decoder_by_type)xm_dlsym(g_lib, "AMediaCodec_createDecoderByType");
    p_codec_delete = (PFN_codec_delete)xm_dlsym(g_lib, "AMediaCodec_delete");
    if (g_missing_count != 0) {
        xm_set_error(g_missing);
        return 2;
    }
    xm_set_error("");
    return 0;
}

static int xm_load_one(const char* soname) {
    xm_unload();
    g_lib = xm_dlopen(soname);
    if (!g_lib) {
        snprintf(g_error, sizeof(g_error), "absent: %s", soname);
        return 1;
    }
    return xm_finish_load();
}

int32_t xm_load_named(const char* soname) {
    if (!soname) {
        xm_set_error("null soname");
        return 2;
    }
    return xm_load_one(soname);
}

int32_t xm_load(void) {
    return xm_load_one("libmediandk.so");
}

const char* xm_error(void) { return g_error; }

int32_t xm_abi_missing_count(void) { return g_missing_count; }

const char* xm_abi_missing(void) { return g_missing; }

int32_t xm_export_count(void) {
    return (int32_t)(XM_FN_COUNT + XM_KEY_COUNT);
}

/* -- declared key data symbols ------------------------------------------- */

int32_t xm_key_count(void) { return (int32_t)XM_KEY_COUNT; }

const char* xm_key_symbol(int32_t index) {
    if (index < 0 || (size_t)index >= XM_KEY_COUNT) return 0;
    return k_key_set[index];
}

const char* xm_key_value(int32_t index) {
    if (!g_lib || index < 0 || (size_t)index >= XM_KEY_COUNT) return 0;
    void* p = xm_dlsym(g_lib, k_key_set[index]);
    if (!p) return 0;
    /* The symbol is a `const char*` data variable: its dlsym address is
     * the address of the pointer; the string is the pointee. */
    return *(const char**)p;
}

const char* xm_key_lookup(const char* symbol) {
    if (!g_lib || !symbol) return 0;
    void* p = xm_dlsym(g_lib, symbol);
    if (!p) return 0;
    return *(const char**)p;
}

/* -- AMediaFormat functional head ---------------------------------------- */

static AMediaFormat* xm_fmt_from_handle(int64_t handle) {
    return (AMediaFormat*)(intptr_t)handle;
}

int64_t xm_format_new(void) {
    if (!p_format_new) { xm_set_error("AMediaFormat_new unresolved"); return 0; }
    AMediaFormat* f = p_format_new();
    if (!f) { xm_set_error("AMediaFormat_new returned NULL (out of memory)"); return 0; }
    return (int64_t)(intptr_t)f;
}

int32_t xm_format_delete(int64_t fmt) {
    if (!p_format_delete) { xm_set_error("AMediaFormat_delete unresolved"); return -1; }
    if (!fmt) { xm_set_error("null format handle"); return -1; }
    int32_t rc = p_format_delete(xm_fmt_from_handle(fmt));
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "AMediaFormat_delete rc=%d", rc);
    }
    return rc;
}

const char* xm_format_to_string(int64_t fmt) {
    if (!p_format_to_string) { xm_set_error("AMediaFormat_toString unresolved"); return 0; }
    if (!fmt) { xm_set_error("null format handle"); return 0; }
    return p_format_to_string(xm_fmt_from_handle(fmt));
}

void xm_format_set_int32(int64_t fmt, const char* name, int32_t value) {
    if (!p_format_set_int32) { xm_set_error("AMediaFormat_setInt32 unresolved"); return; }
    if (!fmt) { xm_set_error("null format handle"); return; }
    p_format_set_int32(xm_fmt_from_handle(fmt), name, value);
}

int32_t xm_format_get_int32(int64_t fmt, const char* name) {
    if (!p_format_get_int32) { xm_set_error("AMediaFormat_getInt32 unresolved"); return 0; }
    if (!fmt) { xm_set_error("null format handle"); return 0; }
    int32_t v = 0;
    bool found = p_format_get_int32(xm_fmt_from_handle(fmt), name, &v);
    g_slot_int = (int64_t)v;
    return found ? 1 : 0;
}

int64_t xm_format_slot_int(void) { return g_slot_int; }

void xm_format_set_float(int64_t fmt, const char* name, float value) {
    if (!p_format_set_float) { xm_set_error("AMediaFormat_setFloat unresolved"); return; }
    if (!fmt) { xm_set_error("null format handle"); return; }
    p_format_set_float(xm_fmt_from_handle(fmt), name, value);
}

int32_t xm_format_get_float(int64_t fmt, const char* name) {
    if (!p_format_get_float) { xm_set_error("AMediaFormat_getFloat unresolved"); return 0; }
    if (!fmt) { xm_set_error("null format handle"); return 0; }
    float v = 0.0f;
    bool found = p_format_get_float(xm_fmt_from_handle(fmt), name, &v);
    g_slot_float = v;
    return found ? 1 : 0;
}

float xm_format_slot_float(void) { return g_slot_float; }

void xm_format_set_string(int64_t fmt, const char* name, const char* value) {
    if (!p_format_set_string) { xm_set_error("AMediaFormat_setString unresolved"); return; }
    if (!fmt) { xm_set_error("null format handle"); return; }
    p_format_set_string(xm_fmt_from_handle(fmt), name, value ? value : "");
}

const char* xm_format_get_string(int64_t fmt, const char* name) {
    if (!p_format_get_string) { xm_set_error("AMediaFormat_getString unresolved"); return 0; }
    if (!fmt) { xm_set_error("null format handle"); return 0; }
    const char* out = 0;
    if (!p_format_get_string(xm_fmt_from_handle(fmt), name, &out)) return 0;
    return out;
}

/* Buffer values: bytes are pushed into a bridge-owned staging slot on the
 * way in; on the way out the bridge keeps the format-owned pointer local
 * and hands bytes back one at a time.  No pointer crosses the boundary. */

int32_t xm_format_stage_begin(int32_t size) {
    if (size < 0 || size > XM_STAGE_MAX) {
        xm_set_error("stage size out of range");
        return -1;
    }
    g_stage_len = (size_t)size;
    return 0;
}

void xm_format_stage_byte(int32_t pos, int32_t value) {
    if (pos < 0 || (size_t)pos >= g_stage_len) {
        xm_set_error("stage position out of range");
        return;
    }
    g_stage[pos] = (uint8_t)value;
}

int32_t xm_format_set_buffer(int64_t fmt, const char* name) {
    if (!p_format_set_buffer) { xm_set_error("AMediaFormat_setBuffer unresolved"); return -1; }
    if (!fmt) { xm_set_error("null format handle"); return -1; }
    p_format_set_buffer(xm_fmt_from_handle(fmt), name, g_stage, g_stage_len);
    return 0;
}

int64_t xm_format_get_buffer(int64_t fmt, const char* name) {
    if (!p_format_get_buffer) { xm_set_error("AMediaFormat_getBuffer unresolved"); return -1; }
    if (!fmt) { xm_set_error("null format handle"); return -1; }
    void* data = 0;
    size_t size = 0;
    if (!p_format_get_buffer(xm_fmt_from_handle(fmt), name, &data, &size)) {
        return -1;
    }
    g_slot_buf = data;
    g_slot_buf_len = size;
    return (int64_t)size;
}

int32_t xm_format_slot_byte(int64_t index) {
    if (!g_slot_buf || index < 0 || (size_t)index >= g_slot_buf_len) return -1;
    return (int32_t)((const uint8_t*)g_slot_buf)[index];
}

/* -- AMediaCodec functional head (create/delete probe) ------------------- */

int64_t xm_codec_create_decoder_by_type(const char* mime) {
    if (!p_codec_create_decoder_by_type) {
        xm_set_error("AMediaCodec_createDecoderByType unresolved");
        return 0;
    }
    AMediaCodec* c = p_codec_create_decoder_by_type(mime ? mime : "");
    if (!c) {
        snprintf(g_error, sizeof(g_error),
                 "AMediaCodec_createDecoderByType(%s) returned NULL",
                 mime ? mime : "");
        return 0;
    }
    return (int64_t)(intptr_t)c;
}

int32_t xm_codec_delete(int64_t codec) {
    if (!p_codec_delete) { xm_set_error("AMediaCodec_delete unresolved"); return -1; }
    if (!codec) { xm_set_error("null codec handle"); return -1; }
    int32_t rc = p_codec_delete((AMediaCodec*)(intptr_t)codec);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "AMediaCodec_delete rc=%d", rc);
    }
    return rc;
}

/* -- teardown ------------------------------------------------------------ */

void xm_unload(void) {
    if (g_lib) { xm_dlclose(g_lib); g_lib = 0; }
    p_format_new = 0;
    p_format_delete = 0;
    p_format_to_string = 0;
    p_format_get_int32 = 0;
    p_format_get_float = 0;
    p_format_get_buffer = 0;
    p_format_get_string = 0;
    p_format_set_int32 = 0;
    p_format_set_float = 0;
    p_format_set_string = 0;
    p_format_set_buffer = 0;
    p_codec_create_decoder_by_type = 0;
    p_codec_delete = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
    g_slot_int = 0;
    g_slot_float = 0.0f;
    g_slot_buf = 0;
    g_slot_buf_len = 0;
    g_stage_len = 0;
}
