// XIOM -- xiom.mediandk: Android NDK media bindings (NDK r27b oracle).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime probe + A7 core media head for libmediandk.so
// (docs/ANDROID-SDK100.md slice A7), backed by the vendored bridge
// `src/mediandk_bridge.c` (compiled with `--c-source`; see
// port.args.json).  The bridge loads libmediandk.so at RUNTIME (dlopen
// on Android/Linux, LoadLibraryA on Windows -- where everything
// classifies ABSENT) and verifies the declared export set of the NDK
// r27b media headers (276 symbols = 133 functions + 143 key data
// symbols):
//
//   NdkMediaCodec.h (+ its NdkMediaCrypto.h include) -- codec/crypto
//   NdkMediaFormat.h -- format functions + AMEDIAFORMAT_KEY_* data
//   NdkMediaExtractor.h -- extractor surface
//   NdkMediaMuxer.h -- muxer surface
//   NdkMediaDataSource.h -- data-source callbacks surface
//   NdkMediaDrm.h -- DRM surface
//
// Functional heads (this wave):
//   AMediaFormat   -- new/delete, set/get Int32, Float, String, Buffer,
//                     toString; exact roundtrips proven on-device
//   AMediaCodec    -- createDecoderByType("audio/opus") + delete probe
// Extractor/Muxer/DRM/DataSource are export-set bound + ABI-checked
// (live use needs real media assets -> later wave).
//
// Classification (the suite maps it to markers):
//   MEDIANDK_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   MEDIANDK_LOAD_ABI    -> FAIL  (present but exports broken; never a
//                                  silent SKIP)
//
// Pointers never cross the boundary (B-25 discipline): format/codec
// handles are Int; buffer payloads cross via a bridge-owned staging
// slot (bytes pushed in, read back one byte at a time out); key data
// symbols are read C-side and copied immediately with Str::from_c_str.
//
// PROVENANCE (key string constants): the AMEDIAFORMAT_KEY_* and
// AMEDIACODEC_KEY_* values are defined by the runtime library, not the
// headers; they were dumped from libmediandk.so on the API-36 x86_64
// emulator (2026-10-16) and are re-verified exhaustively on-device by
// the driver in docs/repro/mediandk-probe/ (keys_expected.h generated
// from this file).  See SPEC.md "Declared-but-unshipped keys" for the
// 16 r27b header exports that no libmediandk.so build ships.

module xiom.mediandk

extern "C" {
  fn xm_load_named(soname: *UInt8) -> Int32;
  fn xm_load() -> Int32;
  fn xm_error() -> *UInt8;
  fn xm_abi_missing_count() -> Int32;
  fn xm_abi_missing() -> *UInt8;
  fn xm_export_count() -> Int32;
  fn xm_key_count() -> Int32;
  fn xm_key_symbol(index: Int32) -> *UInt8;
  fn xm_key_value(index: Int32) -> *UInt8;
  fn xm_key_lookup(symbol: *UInt8) -> *UInt8;
  fn xm_format_new() -> Int64;
  fn xm_format_delete(fmt: Int64) -> Int32;
  fn xm_format_to_string(fmt: Int64) -> *UInt8;
  fn xm_format_set_int32(fmt: Int64, name: *UInt8, value: Int32);
  fn xm_format_get_int32(fmt: Int64, name: *UInt8) -> Int32;
  fn xm_format_slot_int() -> Int64;
  fn xm_format_set_float(fmt: Int64, name: *UInt8, value: Float32);
  fn xm_format_get_float(fmt: Int64, name: *UInt8) -> Int32;
  fn xm_format_slot_float() -> Float32;
  fn xm_format_set_string(fmt: Int64, name: *UInt8, value: *UInt8);
  fn xm_format_get_string(fmt: Int64, name: *UInt8) -> *UInt8;
  fn xm_format_stage_begin(size: Int32) -> Int32;
  fn xm_format_stage_byte(pos: Int32, value: Int32);
  fn xm_format_set_buffer(fmt: Int64, name: *UInt8) -> Int32;
  fn xm_format_get_buffer(fmt: Int64, name: *UInt8) -> Int64;
  fn xm_format_slot_byte(index: Int64) -> Int32;
  fn xm_codec_create_decoder_by_type(mime: *UInt8) -> Int64;
  fn xm_codec_delete(codec: Int64) -> Int32;
  fn xm_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const MEDIANDK_SONAME: Str = "libmediandk.so";

// Probe outcome kinds.
pub const MEDIANDK_LOAD_ABSENT: Int = 0; // runtime lib missing -> SKIP
pub const MEDIANDK_LOAD_ABI: Int = 1;    // present but exports broken -> FAIL

pub type MediaProbeError = {
  kind: Int;
  message: Str;
}

pub type MediaRuntime = {
  missing_exports: Int;
  missing: Str;
  export_count: Int;
}

// =========================================================================
// media_status_t error codes (NdkMediaError.h)
// =========================================================================

pub const AMEDIA_OK: Int = 0;
pub const AMEDIACODEC_ERROR_INSUFFICIENT_RESOURCE: Int = 1100;
pub const AMEDIACODEC_ERROR_RECLAIMED: Int = 1101;
pub const AMEDIA_ERROR_BASE: Int = -10000;
pub const AMEDIA_ERROR_UNKNOWN: Int = -10000;
pub const AMEDIA_ERROR_MALFORMED: Int = -10001;
pub const AMEDIA_ERROR_UNSUPPORTED: Int = -10002;
pub const AMEDIA_ERROR_INVALID_OBJECT: Int = -10003;
pub const AMEDIA_ERROR_INVALID_PARAMETER: Int = -10004;
pub const AMEDIA_ERROR_INVALID_OPERATION: Int = -10005;
pub const AMEDIA_ERROR_END_OF_STREAM: Int = -10006;
pub const AMEDIA_ERROR_IO: Int = -10007;
pub const AMEDIA_ERROR_WOULD_BLOCK: Int = -10008;
pub const AMEDIA_DRM_ERROR_BASE: Int = -20000;
pub const AMEDIA_DRM_NOT_PROVISIONED: Int = -20001;
pub const AMEDIA_DRM_RESOURCE_BUSY: Int = -20002;
pub const AMEDIA_DRM_DEVICE_REVOKED: Int = -20003;
pub const AMEDIA_DRM_SHORT_BUFFER: Int = -20004;
pub const AMEDIA_DRM_SESSION_NOT_OPENED: Int = -20005;
pub const AMEDIA_DRM_TAMPER_DETECTED: Int = -20006;
pub const AMEDIA_DRM_VERIFY_FAILED: Int = -20007;
pub const AMEDIA_DRM_NEED_KEY: Int = -20008;
pub const AMEDIA_DRM_LICENSE_EXPIRED: Int = -20009;
pub const AMEDIA_IMGREADER_ERROR_BASE: Int = -30000;
pub const AMEDIA_IMGREADER_NO_BUFFER_AVAILABLE: Int = -30001;
pub const AMEDIA_IMGREADER_MAX_IMAGES_ACQUIRED: Int = -30002;
pub const AMEDIA_IMGREADER_CANNOT_LOCK_IMAGE: Int = -30003;
pub const AMEDIA_IMGREADER_CANNOT_UNLOCK_IMAGE: Int = -30004;
pub const AMEDIA_IMGREADER_IMAGE_NOT_LOCKED: Int = -30005;

// =========================================================================
// AMediaCodec flags / info / crypto modes (NdkMediaCodec.h)
// =========================================================================

pub const AMEDIACODEC_BUFFER_FLAG_KEY_FRAME: Int = 1;
pub const AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG: Int = 2;
pub const AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM: Int = 4;
pub const AMEDIACODEC_BUFFER_FLAG_PARTIAL_FRAME: Int = 8;
pub const AMEDIACODEC_BUFFER_FLAG_MUXER_DATA: Int = 16;
pub const AMEDIACODEC_BUFFER_FLAG_DECODE_ONLY: Int = 32;
pub const AMEDIACODEC_CONFIGURE_FLAG_ENCODE: Int = 1;
pub const AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED: Int = -3;
pub const AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED: Int = -2;
pub const AMEDIACODEC_INFO_TRY_AGAIN_LATER: Int = -1;
pub const AMEDIACODECRYPTOINFO_MODE_CLEAR: Int = 0;
pub const AMEDIACODECRYPTOINFO_MODE_AES_CTR: Int = 1;
pub const AMEDIACODECRYPTOINFO_MODE_AES_WV: Int = 2;
pub const AMEDIACODECRYPTOINFO_MODE_AES_CBC: Int = 3;

// =========================================================================
// AMediaExtractor seek modes + sample flags (NdkMediaExtractor.h)
// =========================================================================

pub const AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC: Int = 0;
pub const AMEDIAEXTRACTOR_SEEK_NEXT_SYNC: Int = 1;
pub const AMEDIAEXTRACTOR_SEEK_CLOSEST_SYNC: Int = 2;
pub const AMEDIAEXTRACTOR_SAMPLE_FLAG_SYNC: Int = 1;
pub const AMEDIAEXTRACTOR_SAMPLE_FLAG_ENCRYPTED: Int = 2;

// =========================================================================
// AMediaMuxer output formats + append modes (NdkMediaMuxer.h)
// =========================================================================

pub const AMEDIAMUXER_OUTPUT_FORMAT_MPEG_4: Int = 0;
pub const AMEDIAMUXER_OUTPUT_FORMAT_WEBM: Int = 1;
pub const AMEDIAMUXER_OUTPUT_FORMAT_THREE_GPP: Int = 2;
pub const AMEDIAMUXER_OUTPUT_FORMAT_HEIF: Int = 3;
pub const AMEDIAMUXER_OUTPUT_FORMAT_OGG: Int = 4;
pub const AMEDIAMUXER_APPEND_IGNORE_LAST_VIDEO_GOP: Int = 0;
pub const AMEDIAMUXER_APPEND_TO_EXISTING_DATA: Int = 1;

// =========================================================================
// AMediaDrm constants (NdkMediaDrm.h)
// The bare C names (EVENT_*, KEY_TYPE_*, ...) are prefixed AMEDIA_DRM_
// here to avoid generic top-level identifiers; values are the header's.
// =========================================================================

pub const AMEDIA_DRM_EVENT_PROVISION_REQUIRED: Int = 1;
pub const AMEDIA_DRM_EVENT_KEY_REQUIRED: Int = 2;
pub const AMEDIA_DRM_EVENT_KEY_EXPIRED: Int = 3;
pub const AMEDIA_DRM_EVENT_VENDOR_DEFINED: Int = 4;
pub const AMEDIA_DRM_EVENT_SESSION_RECLAIMED: Int = 5;
pub const AMEDIA_DRM_KEY_TYPE_STREAMING: Int = 1;
pub const AMEDIA_DRM_KEY_TYPE_OFFLINE: Int = 2;
pub const AMEDIA_DRM_KEY_TYPE_RELEASE: Int = 3;
pub const AMEDIA_DRM_KEY_REQUEST_TYPE_INITIAL: Int = 0;
pub const AMEDIA_DRM_KEY_REQUEST_TYPE_RENEWAL: Int = 1;
pub const AMEDIA_DRM_KEY_REQUEST_TYPE_RELEASE: Int = 2;
pub const AMEDIA_DRM_KEY_REQUEST_TYPE_NONE: Int = 3;
pub const AMEDIA_DRM_KEY_REQUEST_TYPE_UPDATE: Int = 4;
pub const AMEDIA_DRM_KEY_STATUS_TYPE_USABLE: Int = 0;
pub const AMEDIA_DRM_KEY_STATUS_TYPE_EXPIRED: Int = 1;
pub const AMEDIA_DRM_KEY_STATUS_TYPE_OUTPUTNOTALLOWED: Int = 2;
pub const AMEDIA_DRM_KEY_STATUS_TYPE_STATUSPENDING: Int = 3;
pub const AMEDIA_DRM_KEY_STATUS_TYPE_INTERNALERROR: Int = 4;
pub const AMEDIA_DRM_PROPERTY_VENDOR: Str = "vendor";
pub const AMEDIA_DRM_PROPERTY_VERSION: Str = "version";
pub const AMEDIA_DRM_PROPERTY_DESCRIPTION: Str = "description";
pub const AMEDIA_DRM_PROPERTY_ALGORITHMS: Str = "algorithms";
pub const AMEDIA_DRM_PROPERTY_DEVICE_UNIQUE_ID: Str = "deviceUniqueId";

// =========================================================================
// AMEDIAFORMAT_KEY_* key strings (NdkMediaFormat.h, 136 shipped symbols)
// and AMEDIACODEC_KEY_* key strings (NdkMediaCodec.h, 7).
// Values resolved from libmediandk.so on the API-36 emulator and
// re-verified exhaustively by the on-device driver (see PROVENANCE).
// =========================================================================

pub const AMEDIAFORMAT_KEY_AAC_DRC_ATTENUATION_FACTOR: Str = "aac-drc-cut-level";
pub const AMEDIAFORMAT_KEY_AAC_DRC_BOOST_FACTOR: Str = "aac-drc-boost-level";
pub const AMEDIAFORMAT_KEY_AAC_DRC_HEAVY_COMPRESSION: Str = "aac-drc-heavy-compression";
pub const AMEDIAFORMAT_KEY_AAC_DRC_TARGET_REFERENCE_LEVEL: Str = "aac-target-ref-level";
pub const AMEDIAFORMAT_KEY_AAC_ENCODED_TARGET_LEVEL: Str = "aac-encoded-target-level";
pub const AMEDIAFORMAT_KEY_AAC_MAX_OUTPUT_CHANNEL_COUNT: Str = "aac-max-output-channel_count";
pub const AMEDIAFORMAT_KEY_AAC_PROFILE: Str = "aac-profile";
pub const AMEDIAFORMAT_KEY_AAC_SBR_MODE: Str = "aac-sbr-mode";
pub const AMEDIAFORMAT_KEY_ALBUM: Str = "album";
pub const AMEDIAFORMAT_KEY_ALBUMART: Str = "albumart";
pub const AMEDIAFORMAT_KEY_ALBUMARTIST: Str = "albumartist";
pub const AMEDIAFORMAT_KEY_ALLOW_FRAME_DROP: Str = "allow-frame-drop";
pub const AMEDIAFORMAT_KEY_ARTIST: Str = "artist";
pub const AMEDIAFORMAT_KEY_AUDIO_PRESENTATION_INFO: Str = "audio-presentation-info";
pub const AMEDIAFORMAT_KEY_AUDIO_SESSION_ID: Str = "audio-session-id";
pub const AMEDIAFORMAT_KEY_AUTHOR: Str = "author";
pub const AMEDIAFORMAT_KEY_BIT_RATE: Str = "bitrate";
pub const AMEDIAFORMAT_KEY_BITRATE_MODE: Str = "bitrate-mode";
pub const AMEDIAFORMAT_KEY_BITS_PER_SAMPLE: Str = "bits-per-sample";
pub const AMEDIAFORMAT_KEY_CAPTURE_RATE: Str = "capture-rate";
pub const AMEDIAFORMAT_KEY_CDTRACKNUMBER: Str = "cdtracknum";
pub const AMEDIAFORMAT_KEY_CHANNEL_COUNT: Str = "channel-count";
pub const AMEDIAFORMAT_KEY_CHANNEL_MASK: Str = "channel-mask";
pub const AMEDIAFORMAT_KEY_COLOR_FORMAT: Str = "color-format";
pub const AMEDIAFORMAT_KEY_COLOR_RANGE: Str = "color-range";
pub const AMEDIAFORMAT_KEY_COLOR_STANDARD: Str = "color-standard";
pub const AMEDIAFORMAT_KEY_COLOR_TRANSFER: Str = "color-transfer";
pub const AMEDIAFORMAT_KEY_COMPILATION: Str = "compilation";
pub const AMEDIAFORMAT_KEY_COMPLEXITY: Str = "complexity";
pub const AMEDIAFORMAT_KEY_COMPOSER: Str = "composer";
pub const AMEDIAFORMAT_KEY_CREATE_INPUT_SURFACE_SUSPENDED: Str = "create-input-buffers-suspended";
pub const AMEDIAFORMAT_KEY_CRYPTO_DEFAULT_IV_SIZE: Str = "crypto-default-iv-size";
pub const AMEDIAFORMAT_KEY_CRYPTO_ENCRYPTED_BYTE_BLOCK: Str = "crypto-encrypted-byte-block";
pub const AMEDIAFORMAT_KEY_CRYPTO_ENCRYPTED_SIZES: Str = "crypto-encrypted-sizes";
pub const AMEDIAFORMAT_KEY_CRYPTO_IV: Str = "crypto-iv";
pub const AMEDIAFORMAT_KEY_CRYPTO_KEY: Str = "crypto-key";
pub const AMEDIAFORMAT_KEY_CRYPTO_MODE: Str = "crypto-mode";
pub const AMEDIAFORMAT_KEY_CRYPTO_PLAIN_SIZES: Str = "crypto-plain-sizes";
pub const AMEDIAFORMAT_KEY_CRYPTO_SKIP_BYTE_BLOCK: Str = "crypto-skip-byte-block";
pub const AMEDIAFORMAT_KEY_CSD: Str = "csd";
pub const AMEDIAFORMAT_KEY_CSD_0: Str = "csd-0";
pub const AMEDIAFORMAT_KEY_CSD_1: Str = "csd-1";
pub const AMEDIAFORMAT_KEY_CSD_2: Str = "csd-2";
pub const AMEDIAFORMAT_KEY_CSD_AVC: Str = "csd-avc";
pub const AMEDIAFORMAT_KEY_CSD_HEVC: Str = "csd-hevc";
pub const AMEDIAFORMAT_KEY_D263: Str = "d263";
pub const AMEDIAFORMAT_KEY_DATE: Str = "date";
pub const AMEDIAFORMAT_KEY_DISCNUMBER: Str = "discnum";
pub const AMEDIAFORMAT_KEY_DISPLAY_CROP: Str = "crop";
pub const AMEDIAFORMAT_KEY_DISPLAY_HEIGHT: Str = "display-height";
pub const AMEDIAFORMAT_KEY_DISPLAY_WIDTH: Str = "display-width";
pub const AMEDIAFORMAT_KEY_DURATION: Str = "durationUs";
pub const AMEDIAFORMAT_KEY_ENCODER_DELAY: Str = "encoder-delay";
pub const AMEDIAFORMAT_KEY_ENCODER_PADDING: Str = "encoder-padding";
pub const AMEDIAFORMAT_KEY_ESDS: Str = "esds";
pub const AMEDIAFORMAT_KEY_EXIF_OFFSET: Str = "exif-offset";
pub const AMEDIAFORMAT_KEY_EXIF_SIZE: Str = "exif-size";
pub const AMEDIAFORMAT_KEY_FLAC_COMPRESSION_LEVEL: Str = "flac-compression-level";
pub const AMEDIAFORMAT_KEY_FRAME_COUNT: Str = "frame-count";
pub const AMEDIAFORMAT_KEY_FRAME_RATE: Str = "frame-rate";
pub const AMEDIAFORMAT_KEY_GENRE: Str = "genre";
pub const AMEDIAFORMAT_KEY_GRID_COLUMNS: Str = "grid-cols";
pub const AMEDIAFORMAT_KEY_GRID_ROWS: Str = "grid-rows";
pub const AMEDIAFORMAT_KEY_HAPTIC_CHANNEL_COUNT: Str = "haptic-channel-count";
pub const AMEDIAFORMAT_KEY_HDR_STATIC_INFO: Str = "hdr-static-info";
pub const AMEDIAFORMAT_KEY_HDR10_PLUS_INFO: Str = "hdr10-plus-info";
pub const AMEDIAFORMAT_KEY_HEIGHT: Str = "height";
pub const AMEDIAFORMAT_KEY_I_FRAME_INTERVAL: Str = "i-frame-interval";
pub const AMEDIAFORMAT_KEY_ICC_PROFILE: Str = "icc-profile";
pub const AMEDIAFORMAT_KEY_INTRA_REFRESH_PERIOD: Str = "intra-refresh-period";
pub const AMEDIAFORMAT_KEY_IS_ADTS: Str = "is-adts";
pub const AMEDIAFORMAT_KEY_IS_AUTOSELECT: Str = "is-autoselect";
pub const AMEDIAFORMAT_KEY_IS_DEFAULT: Str = "is-default";
pub const AMEDIAFORMAT_KEY_IS_FORCED_SUBTITLE: Str = "is-forced-subtitle";
pub const AMEDIAFORMAT_KEY_IS_SYNC_FRAME: Str = "is-sync-frame";
pub const AMEDIAFORMAT_KEY_LANGUAGE: Str = "language";
pub const AMEDIAFORMAT_KEY_LAST_SAMPLE_INDEX_IN_CHUNK: Str = "last-sample-index-in-chunk";
pub const AMEDIAFORMAT_KEY_LATENCY: Str = "latency";
pub const AMEDIAFORMAT_KEY_LEVEL: Str = "level";
pub const AMEDIAFORMAT_KEY_LOCATION: Str = "location";
pub const AMEDIAFORMAT_KEY_LOOP: Str = "loop";
pub const AMEDIAFORMAT_KEY_LOW_LATENCY: Str = "low-latency";
pub const AMEDIAFORMAT_KEY_LYRICIST: Str = "lyricist";
pub const AMEDIAFORMAT_KEY_MANUFACTURER: Str = "manufacturer";
pub const AMEDIAFORMAT_KEY_MAX_B_FRAMES: Str = "max-bframes";
pub const AMEDIAFORMAT_KEY_MAX_BIT_RATE: Str = "max-bitrate";
pub const AMEDIAFORMAT_KEY_MAX_FPS_TO_ENCODER: Str = "max-fps-to-encoder";
pub const AMEDIAFORMAT_KEY_MAX_HEIGHT: Str = "max-height";
pub const AMEDIAFORMAT_KEY_MAX_INPUT_SIZE: Str = "max-input-size";
pub const AMEDIAFORMAT_KEY_MAX_PTS_GAP_TO_ENCODER: Str = "max-pts-gap-to-encoder";
pub const AMEDIAFORMAT_KEY_MAX_WIDTH: Str = "max-width";
pub const AMEDIAFORMAT_KEY_MIME: Str = "mime";
pub const AMEDIAFORMAT_KEY_MPEG_USER_DATA: Str = "mpeg-user-data";
pub const AMEDIAFORMAT_KEY_MPEG2_STREAM_HEADER: Str = "mpeg2-stream-header";
pub const AMEDIAFORMAT_KEY_MPEGH_COMPATIBLE_SETS: Str = "mpegh-compatible-sets";
pub const AMEDIAFORMAT_KEY_MPEGH_PROFILE_LEVEL_INDICATION: Str = "mpegh-profile-level-indication";
pub const AMEDIAFORMAT_KEY_MPEGH_REFERENCE_CHANNEL_LAYOUT: Str = "mpegh-reference-channel-layout";
pub const AMEDIAFORMAT_KEY_OPERATING_RATE: Str = "operating-rate";
pub const AMEDIAFORMAT_KEY_PCM_BIG_ENDIAN: Str = "pcm-big-endian";
pub const AMEDIAFORMAT_KEY_PCM_ENCODING: Str = "pcm-encoding";
pub const AMEDIAFORMAT_KEY_PRIORITY: Str = "priority";
pub const AMEDIAFORMAT_KEY_PROFILE: Str = "profile";
pub const AMEDIAFORMAT_KEY_PSSH: Str = "pssh";
pub const AMEDIAFORMAT_KEY_PUSH_BLANK_BUFFERS_ON_STOP: Str = "push-blank-buffers-on-shutdown";
pub const AMEDIAFORMAT_KEY_REPEAT_PREVIOUS_FRAME_AFTER: Str = "repeat-previous-frame-after";
pub const AMEDIAFORMAT_KEY_ROTATION: Str = "rotation-degrees";
pub const AMEDIAFORMAT_KEY_SAMPLE_FILE_OFFSET: Str = "sample-file-offset";
pub const AMEDIAFORMAT_KEY_SAMPLE_RATE: Str = "sample-rate";
pub const AMEDIAFORMAT_KEY_SAMPLE_TIME_BEFORE_APPEND: Str = "sample-time-before-append";
pub const AMEDIAFORMAT_KEY_SAR_HEIGHT: Str = "sar-height";
pub const AMEDIAFORMAT_KEY_SAR_WIDTH: Str = "sar-width";
pub const AMEDIAFORMAT_KEY_SEI: Str = "sei";
pub const AMEDIAFORMAT_KEY_SLICE_HEIGHT: Str = "slice-height";
pub const AMEDIAFORMAT_KEY_SLOW_MOTION_MARKERS: Str = "slow-motion-markers";
pub const AMEDIAFORMAT_KEY_STRIDE: Str = "stride";
pub const AMEDIAFORMAT_KEY_TARGET_TIME: Str = "target-time";
pub const AMEDIAFORMAT_KEY_TEMPORAL_LAYER_COUNT: Str = "temporal-layer-count";
pub const AMEDIAFORMAT_KEY_TEMPORAL_LAYER_ID: Str = "temporal-layer-id";
pub const AMEDIAFORMAT_KEY_TEMPORAL_LAYERING: Str = "ts-schema";
pub const AMEDIAFORMAT_KEY_TEXT_FORMAT_DATA: Str = "text-format-data";
pub const AMEDIAFORMAT_KEY_THUMBNAIL_CSD_AV1C: Str = "thumbnail-csd-av1c";
pub const AMEDIAFORMAT_KEY_THUMBNAIL_CSD_HEVC: Str = "thumbnail-csd-hevc";
pub const AMEDIAFORMAT_KEY_THUMBNAIL_HEIGHT: Str = "thumbnail-height";
pub const AMEDIAFORMAT_KEY_THUMBNAIL_TIME: Str = "thumbnail-time";
pub const AMEDIAFORMAT_KEY_THUMBNAIL_WIDTH: Str = "thumbnail-width";
pub const AMEDIAFORMAT_KEY_TILE_HEIGHT: Str = "tile-height";
pub const AMEDIAFORMAT_KEY_TILE_WIDTH: Str = "tile-width";
pub const AMEDIAFORMAT_KEY_TIME_US: Str = "timeUs";
pub const AMEDIAFORMAT_KEY_TITLE: Str = "title";
pub const AMEDIAFORMAT_KEY_TRACK_ID: Str = "track-id";
pub const AMEDIAFORMAT_KEY_TRACK_INDEX: Str = "track-index";
pub const AMEDIAFORMAT_KEY_VALID_SAMPLES: Str = "valid-samples";
pub const AMEDIAFORMAT_KEY_WIDTH: Str = "width";
pub const AMEDIAFORMAT_KEY_XMP_OFFSET: Str = "xmp-offset";
pub const AMEDIAFORMAT_KEY_XMP_SIZE: Str = "xmp-size";
pub const AMEDIAFORMAT_KEY_YEAR: Str = "year";
pub const AMEDIACODEC_KEY_HDR10_PLUS_INFO: Str = "hdr10-plus-info";
pub const AMEDIACODEC_KEY_LOW_LATENCY: Str = "low-latency";
pub const AMEDIACODEC_KEY_OFFSET_TIME: Str = "time-offset-us";
pub const AMEDIACODEC_KEY_REQUEST_SYNC_FRAME: Str = "request-sync";
pub const AMEDIACODEC_KEY_SUSPEND: Str = "drop-input-frames";
pub const AMEDIACODEC_KEY_SUSPEND_TIME: Str = "drop-start-time-us";
pub const AMEDIACODEC_KEY_VIDEO_BITRATE: Str = "video-bitrate";

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named media library soname.  Useful for tests: a
/// bogus soname exercises the ABSENT/SKIP classification deterministically
/// even on hosts that ship the library.
/// Complexity: O(load + export set).
pub fn mediandk_probe_named(soname: Str) -> Result[MediaRuntime, MediaProbeError]
  requires: soname.len() > 0
{
  let rc = unsafe { xm_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xm_error()) };
    if rc == 1 {
      return Err(MediaProbeError{ kind: MEDIANDK_LOAD_ABSENT; message: msg });
    }
    return Err(MediaProbeError{ kind: MEDIANDK_LOAD_ABI; message: msg });
  }
  let missing_count = unsafe { xm_abi_missing_count() as Int };
  let missing = unsafe { Str::from_c_str(xm_abi_missing()) };
  let export_count = unsafe { xm_export_count() as Int };
  return Ok(MediaRuntime{ missing_exports: missing_count; missing: missing; export_count: export_count });
}

/// Probe the default runtime (libmediandk.so).  On Android this is the
/// platform library; on Windows the probe classifies ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn mediandk_probe() -> Result[MediaRuntime, MediaProbeError]
  requires: true
{
  return mediandk_probe_named(MEDIANDK_SONAME);
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn mediandk_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xm_error()); }
}

/// Release any runtime handle held by the bridge.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn mediandk_unload()
  requires: true
{
  unsafe { xm_unload(); }
}

// =========================================================================
// Key-symbol introspection (declared AMEDIAFORMAT_KEY_* / AMEDIACODEC_KEY_*)
// =========================================================================

/// Number of key data symbols in the declared export set (143).
/// Complexity: O(1).
pub fn mediandk_key_count() -> Int
  requires: true
{
  unsafe { return xm_key_count() as Int; }
}

/// Declared symbol name at index ("" when out of range).
/// Complexity: O(1).
pub fn mediandk_key_symbol(index: Int) -> Str
  requires: index >= 0
{
  let ok = unsafe { xm_key_symbol(index as Int32) != null };
  if !ok { return ""; }
  unsafe { return Str::from_c_str(xm_key_symbol(index as Int32)); }
}

/// Runtime value of the declared data symbol at index.
/// Complexity: O(1).
pub fn mediandk_key_value(index: Int) -> Str
  requires: index >= 0
{
  let ok = unsafe { xm_key_value(index as Int32) != null };
  if !ok { return ""; }
  unsafe { return Str::from_c_str(xm_key_value(index as Int32)); }
}

pub type StrOutcome = {
  found: Bool;
  value: Str;
}

/// Resolve a key symbol by name (e.g. "AMEDIAFORMAT_KEY_MIME") to its
/// runtime string value.  `found` is false when the symbol is not
/// exported by the loaded library.
/// Complexity: O(1).
pub fn mediandk_key_lookup(symbol: Str) -> StrOutcome
  requires: symbol.len() > 0
{
  let ok = unsafe { xm_key_lookup(symbol.c_str()) != null };
  if !ok { return StrOutcome{ found: false; value: "" }; }
  let value = unsafe { Str::from_c_str(xm_key_lookup(symbol.c_str())) };
  return StrOutcome{ found: true; value: value };
}

// =========================================================================
// AMediaFormat functional head
// =========================================================================

pub type MediaFormat = {
  handle: Int;
}

pub type IntOutcome = {
  found: Bool;
  value: Int;
}

pub type FloatOutcome = {
  found: Bool;
  value: Float32;
}

pub type BufferOutcome = {
  found: Bool;
  bytes: Vec[UInt8];
}

/// Create a new empty AMediaFormat.  Delete with `format_delete`.
/// Complexity: O(1).
pub fn format_new() -> Result[MediaFormat, MediaProbeError]
  requires: true
{
  let h = unsafe { xm_format_new() as Int };
  if h == 0 {
    return Err(MediaProbeError{ kind: MEDIANDK_LOAD_ABI; message: mediandk_error() });
  }
  return Ok(MediaFormat{ handle: h });
}

/// Delete the format (rc 0 == AMEDIA_OK).
/// Complexity: O(1).
pub fn format_delete(fmt: MediaFormat) -> Bool
  requires: true
{
  let rc = unsafe { xm_format_delete(fmt.handle as Int64) as Int };
  return rc == 0;
}

/// Human-readable representation; owned by the format (valid until the
/// next toString/getString call or delete), copied into a Str here.
/// Complexity: O(entries).
pub fn format_to_string(fmt: &MediaFormat) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xm_format_to_string(fmt.handle as Int64)); }
}

/// Store an Int32 entry (keys: AMEDIAFORMAT_KEY_*).
/// Complexity: O(1).
pub fn format_set_int32(fmt: &MediaFormat, key: Str, value: Int)
  requires: key.len() > 0
{
  unsafe { xm_format_set_int32(fmt.handle as Int64, key.c_str(), value as Int32); }
}

/// Read an Int32 entry; `found` distinguishes "missing key" from value 0.
/// Complexity: O(1).
pub fn format_get_int32(fmt: &MediaFormat, key: Str) -> IntOutcome
  requires: key.len() > 0
{
  let found = unsafe { xm_format_get_int32(fmt.handle as Int64, key.c_str()) as Int };
  let v = unsafe { xm_format_slot_int() as Int };
  return IntOutcome{ found: found == 1; value: v };
}

/// Store a Float32 entry (AMediaFormat stores float).
/// Complexity: O(1).
pub fn format_set_float(fmt: &MediaFormat, key: Str, value: Float32)
  requires: key.len() > 0
{
  unsafe { xm_format_set_float(fmt.handle as Int64, key.c_str(), value); }
}

/// Read a Float32 entry.
/// Complexity: O(1).
pub fn format_get_float(fmt: &MediaFormat, key: Str) -> FloatOutcome
  requires: key.len() > 0
{
  let found = unsafe { xm_format_get_float(fmt.handle as Int64, key.c_str()) as Int };
  let v = unsafe { xm_format_slot_float() };
  return FloatOutcome{ found: found == 1; value: v };
}

/// Store a string entry (copied into the format by the NDK).
/// Complexity: O(len(value)).
pub fn format_set_string(fmt: &MediaFormat, key: Str, value: Str)
  requires: key.len() > 0
{
  unsafe { xm_format_set_string(fmt.handle as Int64, key.c_str(), value.c_str()); }
}

/// Read a string entry; `found` false when the key is absent.
/// Complexity: O(len(value)).
pub fn format_get_string(fmt: &MediaFormat, key: Str) -> StrOutcome
  requires: key.len() > 0
{
  let ok = unsafe { xm_format_get_string(fmt.handle as Int64, key.c_str()) != null };
  if !ok { return StrOutcome{ found: false; value: "" }; }
  let value = unsafe { Str::from_c_str(xm_format_get_string(fmt.handle as Int64, key.c_str())) };
  return StrOutcome{ found: true; value: value };
}

/// Store a byte-buffer entry (copied into the format by the NDK).  The
/// bytes are staged into a bridge-owned slot; no pointer crosses the
/// boundary.  Cap: 4096 bytes.
/// Complexity: O(len(data)).
pub fn format_set_buffer(fmt: &MediaFormat, key: Str, data: &Vec[UInt8]) -> Bool
  requires: key.len() > 0
  requires: data.len() <= 4096
{
  let rc = unsafe { xm_format_stage_begin(data.len() as Int32) as Int };
  if rc != 0 { return false; }
  var i: Int = 0;
  while i < data.len() {
    unsafe { xm_format_stage_byte(i as Int32, data[i] as Int32); }
    i = i + 1;
  }
  let rc2 = unsafe { xm_format_set_buffer(fmt.handle as Int64, key.c_str()) as Int };
  return rc2 == 0;
}

/// Read a byte-buffer entry; bytes are copied out one at a time from a
/// bridge-owned slot.
/// Complexity: O(size).
pub fn format_get_buffer(fmt: &MediaFormat, key: Str) -> BufferOutcome
  requires: key.len() > 0
{
  let size = unsafe { xm_format_get_buffer(fmt.handle as Int64, key.c_str()) as Int };
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  if size < 0 {
    return BufferOutcome{ found: false; bytes: bytes };
  }
  var i: Int = 0;
  while i < size {
    let b = unsafe { xm_format_slot_byte(i as Int64) as Int };
    bytes.push(b as UInt8);
    i = i + 1;
  }
  return BufferOutcome{ found: true; bytes: bytes };
}

// =========================================================================
// AMediaCodec functional head (create/delete probe)
// =========================================================================

pub type MediaCodec = {
  handle: Int;
}

/// Create a decoder for a MIME type (e.g. "audio/opus").  Err carries the
/// typed failure when the platform provides no such decoder or the
/// runtime is not loaded (NON-FATAL: callers decide).
/// Complexity: O(codec lookup).
pub fn codec_create_decoder(mime: Str) -> Result[MediaCodec, MediaProbeError]
  requires: mime.len() > 0
{
  let h = unsafe { xm_codec_create_decoder_by_type(mime.c_str()) as Int };
  if h == 0 {
    return Err(MediaProbeError{ kind: MEDIANDK_LOAD_ABI; message: mediandk_error() });
  }
  return Ok(MediaCodec{ handle: h });
}

/// Delete the codec (rc 0 == AMEDIA_OK).
/// Complexity: O(1).
pub fn codec_delete(codec: MediaCodec) -> Bool
  requires: true
{
  let rc = unsafe { xm_codec_delete(codec.handle as Int64) as Int };
  return rc == 0;
}
