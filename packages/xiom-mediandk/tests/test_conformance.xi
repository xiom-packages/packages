// xiom.mediandk conformance suite -- libmediandk.so runtime loader/probe
// for the A7 core media head (codec/format/extractor/muxer/DRM/dataSource).
//
// The probe never FAILs on a missing runtime:
//   present runtime -> export-set ABI check (276 symbols) + AMediaFormat
//                      functional roundtrips + audio/opus decoder probe
//   missing lib     -> MEDIANDK_LOAD_ABSENT (SKIP; exercised
//                      deterministically below with a bogus soname)
//   broken install  -> MEDIANDK_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime is absent by design -> SKIP (CI stays green).
// On an Android device/emulator the same suite runs the live path; until
// the compiler android target (G1) the on-device driver under
// docs/repro/mediandk-probe/ carries the live evidence.
//
// Build+run through the runner (compiles src/mediandk_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.mediandk

module mediandk_conformance

use xiom.io;
use xiom.mediandk;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn t_constants() -> Bool {
  var ok = true;
  if MEDIANDK_LOAD_ABSENT != 0 || MEDIANDK_LOAD_ABI != 1 { ok = false; }
  // media_status_t cluster (NdkMediaError.h).
  if AMEDIA_OK != 0 || AMEDIA_ERROR_BASE != -10000 || AMEDIA_ERROR_UNKNOWN != -10000 { ok = false; }
  if AMEDIA_ERROR_MALFORMED != -10001 || AMEDIA_ERROR_UNSUPPORTED != -10002 { ok = false; }
  if AMEDIA_ERROR_INVALID_OBJECT != -10003 || AMEDIA_ERROR_INVALID_PARAMETER != -10004 { ok = false; }
  if AMEDIA_ERROR_INVALID_OPERATION != -10005 || AMEDIA_ERROR_END_OF_STREAM != -10006 { ok = false; }
  if AMEDIA_ERROR_IO != -10007 || AMEDIA_ERROR_WOULD_BLOCK != -10008 { ok = false; }
  if AMEDIACODEC_ERROR_INSUFFICIENT_RESOURCE != 1100 || AMEDIACODEC_ERROR_RECLAIMED != 1101 { ok = false; }
  if AMEDIA_DRM_ERROR_BASE != -20000 || AMEDIA_DRM_NOT_PROVISIONED != -20001 { ok = false; }
  if AMEDIA_DRM_LICENSE_EXPIRED != -20009 { ok = false; }
  if AMEDIA_IMGREADER_ERROR_BASE != -30000 || AMEDIA_IMGREADER_IMAGE_NOT_LOCKED != -30005 { ok = false; }
  // codec flags / info / crypto modes (NdkMediaCodec.h).
  if AMEDIACODEC_BUFFER_FLAG_KEY_FRAME != 1 || AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG != 2 { ok = false; }
  if AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM != 4 || AMEDIACODEC_BUFFER_FLAG_PARTIAL_FRAME != 8 { ok = false; }
  if AMEDIACODEC_BUFFER_FLAG_MUXER_DATA != 16 || AMEDIACODEC_BUFFER_FLAG_DECODE_ONLY != 32 { ok = false; }
  if AMEDIACODEC_CONFIGURE_FLAG_ENCODE != 1 { ok = false; }
  if AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED != -3 || AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED != -2 { ok = false; }
  if AMEDIACODEC_INFO_TRY_AGAIN_LATER != -1 { ok = false; }
  if AMEDIACODECRYPTOINFO_MODE_CLEAR != 0 || AMEDIACODECRYPTOINFO_MODE_AES_CTR != 1 { ok = false; }
  if AMEDIACODECRYPTOINFO_MODE_AES_WV != 2 || AMEDIACODECRYPTOINFO_MODE_AES_CBC != 3 { ok = false; }
  // extractor seek modes + sample flags (NdkMediaExtractor.h).
  if AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC != 0 || AMEDIAEXTRACTOR_SEEK_NEXT_SYNC != 1 { ok = false; }
  if AMEDIAEXTRACTOR_SEEK_CLOSEST_SYNC != 2 { ok = false; }
  if AMEDIAEXTRACTOR_SAMPLE_FLAG_SYNC != 1 || AMEDIAEXTRACTOR_SAMPLE_FLAG_ENCRYPTED != 2 { ok = false; }
  // muxer output formats + append modes (NdkMediaMuxer.h).
  if AMEDIAMUXER_OUTPUT_FORMAT_MPEG_4 != 0 || AMEDIAMUXER_OUTPUT_FORMAT_WEBM != 1 { ok = false; }
  if AMEDIAMUXER_OUTPUT_FORMAT_THREE_GPP != 2 || AMEDIAMUXER_OUTPUT_FORMAT_HEIF != 3 { ok = false; }
  if AMEDIAMUXER_OUTPUT_FORMAT_OGG != 4 { ok = false; }
  if AMEDIAMUXER_APPEND_IGNORE_LAST_VIDEO_GOP != 0 || AMEDIAMUXER_APPEND_TO_EXISTING_DATA != 1 { ok = false; }
  // DRM clusters (NdkMediaDrm.h).
  if AMEDIA_DRM_EVENT_PROVISION_REQUIRED != 1 || AMEDIA_DRM_EVENT_KEY_REQUIRED != 2 { ok = false; }
  if AMEDIA_DRM_EVENT_KEY_EXPIRED != 3 || AMEDIA_DRM_EVENT_VENDOR_DEFINED != 4 { ok = false; }
  if AMEDIA_DRM_EVENT_SESSION_RECLAIMED != 5 { ok = false; }
  if AMEDIA_DRM_KEY_TYPE_STREAMING != 1 || AMEDIA_DRM_KEY_TYPE_OFFLINE != 2 || AMEDIA_DRM_KEY_TYPE_RELEASE != 3 { ok = false; }
  if AMEDIA_DRM_KEY_REQUEST_TYPE_INITIAL != 0 || AMEDIA_DRM_KEY_REQUEST_TYPE_RENEWAL != 1 { ok = false; }
  if AMEDIA_DRM_KEY_REQUEST_TYPE_RELEASE != 2 || AMEDIA_DRM_KEY_REQUEST_TYPE_NONE != 3 { ok = false; }
  if AMEDIA_DRM_KEY_REQUEST_TYPE_UPDATE != 4 { ok = false; }
  if AMEDIA_DRM_KEY_STATUS_TYPE_USABLE != 0 || AMEDIA_DRM_KEY_STATUS_TYPE_EXPIRED != 1 { ok = false; }
  if AMEDIA_DRM_KEY_STATUS_TYPE_OUTPUTNOTALLOWED != 2 || AMEDIA_DRM_KEY_STATUS_TYPE_STATUSPENDING != 3 { ok = false; }
  if AMEDIA_DRM_KEY_STATUS_TYPE_INTERNALERROR != 4 { ok = false; }
  if AMEDIA_DRM_PROPERTY_VENDOR != "vendor" || AMEDIA_DRM_PROPERTY_VERSION != "version" { ok = false; }
  if AMEDIA_DRM_PROPERTY_DESCRIPTION != "description" || AMEDIA_DRM_PROPERTY_ALGORITHMS != "algorithms" { ok = false; }
  if AMEDIA_DRM_PROPERTY_DEVICE_UNIQUE_ID != "deviceUniqueId" { ok = false; }
  // key string spot checks (all 143 proven on-device against the runtime).
  if AMEDIAFORMAT_KEY_MIME != "mime" || AMEDIAFORMAT_KEY_WIDTH != "width" { ok = false; }
  if AMEDIAFORMAT_KEY_HEIGHT != "height" || AMEDIAFORMAT_KEY_MAX_INPUT_SIZE != "max-input-size" { ok = false; }
  if AMEDIAFORMAT_KEY_COLOR_FORMAT != "color-format" || AMEDIAFORMAT_KEY_COLOR_RANGE != "color-range" { ok = false; }
  if AMEDIAFORMAT_KEY_COLOR_STANDARD != "color-standard" || AMEDIAFORMAT_KEY_COLOR_TRANSFER != "color-transfer" { ok = false; }
  if AMEDIAFORMAT_KEY_DURATION != "durationUs" || AMEDIAFORMAT_KEY_FRAME_RATE != "frame-rate" { ok = false; }
  if AMEDIAFORMAT_KEY_SAMPLE_RATE != "sample-rate" || AMEDIAFORMAT_KEY_CHANNEL_COUNT != "channel-count" { ok = false; }
  if AMEDIAFORMAT_KEY_BIT_RATE != "bitrate" || AMEDIAFORMAT_KEY_CSD_0 != "csd-0" { ok = false; }
  if AMEDIAFORMAT_KEY_STRIDE != "stride" || AMEDIAFORMAT_KEY_SLICE_HEIGHT != "slice-height" { ok = false; }
  if AMEDIACODEC_KEY_VIDEO_BITRATE != "video-bitrate" || AMEDIACODEC_KEY_REQUEST_SYNC_FRAME != "request-sync" { ok = false; }
  if AMEDIACODEC_KEY_LOW_LATENCY != "low-latency" || AMEDIACODEC_KEY_SUSPEND != "drop-input-frames" { ok = false; }
  return ok;
}

fn t_key_cluster() -> Int {
  var failed: Int = 0;
  failed = failed + report(mediandk_key_count() == 143,
    "keys: declared key data symbols count = 143 (got " + to_string(mediandk_key_count()) + ")");
  return failed;
}

fn t_format_functional() -> Int {
  var failed: Int = 0;
  let nf = format_new();
  if !nf.is_ok {
    failed = failed + report(false, "format: new failed -- " + nf.error.message);
    return failed;
  }
  let fmt: MediaFormat = nf.value;

  format_set_int32(&fmt, AMEDIAFORMAT_KEY_COLOR_FORMAT, 21);
  let i1 = format_get_int32(&fmt, AMEDIAFORMAT_KEY_COLOR_FORMAT);
  failed = failed + report(i1.found && i1.value == 21,
    "format: int32 roundtrip color-format=21 (got " + to_string(i1.value) + ")");

  format_set_int32(&fmt, AMEDIAFORMAT_KEY_WIDTH, 640);
  let i2 = format_get_int32(&fmt, AMEDIAFORMAT_KEY_WIDTH);
  failed = failed + report(i2.found && i2.value == 640,
    "format: int32 roundtrip width=640 (got " + to_string(i2.value) + ")");

  let absent = format_get_int32(&fmt, "xiom-absent-key");
  failed = failed + report(!absent.found, "format: getInt32 absent key reports found=false");

  format_set_string(&fmt, AMEDIAFORMAT_KEY_MIME, "audio/opus");
  let s1 = format_get_string(&fmt, AMEDIAFORMAT_KEY_MIME);
  failed = failed + report(s1.found && s1.value == "audio/opus",
    "format: string roundtrip mime=audio/opus (got " + s1.value + ")");

  format_set_float(&fmt, AMEDIAFORMAT_KEY_FRAME_RATE, 2.5);
  let f1 = format_get_float(&fmt, AMEDIAFORMAT_KEY_FRAME_RATE);
  failed = failed + report(f1.found && f1.value == 2.5,
    "format: float roundtrip frame-rate=2.5");

  var data: Vec[UInt8] = Vec[UInt8].new();
  data.push(0x12 as UInt8);
  data.push(0x34 as UInt8);
  data.push(0x56 as UInt8);
  data.push(0x78 as UInt8);
  failed = failed + report(format_set_buffer(&fmt, AMEDIAFORMAT_KEY_CSD_0, &data),
    "format: setBuffer csd-0 (4 bytes)");
  let b = format_get_buffer(&fmt, AMEDIAFORMAT_KEY_CSD_0);
  failed = failed + report(b.found && b.bytes.len() == 4 && b.bytes[0] == (0x12 as UInt8)
    && b.bytes[1] == (0x34 as UInt8) && b.bytes[2] == (0x56 as UInt8)
    && b.bytes[3] == (0x78 as UInt8), "format: buffer roundtrip 12345678 exact");

  let ts = format_to_string(&fmt);
  failed = failed + report(ts.len() > 0, "format: toString non-empty");

  failed = failed + report(format_delete(fmt), "format: delete rc==AMEDIA_OK");
  return failed;
}

fn t_codec_probe() -> Int {
  var failed: Int = 0;
  let c = codec_create_decoder("audio/opus");
  if c.is_ok {
    let codec: MediaCodec = c.value;
    failed = failed + report(codec_delete(codec),
      "codec: audio/opus decoder created + deleted (verdict: PRESENT)");
  } else {
    failed = failed + report(true,
      "codec: audio/opus decoder unavailable -- typed failure recorded (NON-FATAL): " + c.error.message);
  }
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.mediandk conformance tests (libmediandk.so loader/probe, A7 core media head) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(),
    "constants: AMEDIA_* error codes + codec/extractor/muxer/DRM clusters + key strings");
  failed = failed + t_key_cluster();

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = mediandk_probe_named("xiom-absent-libmediandk-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == MEDIANDK_LOAD_ABSENT,
      "skip-path: absent soname classified as MEDIANDK_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = mediandk_probe();
  if p.is_ok {
    let rt: MediaRuntime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: declared export set fully resolved (" + to_string(rt.export_count) + " symbols, "
      + to_string(rt.missing_exports) + " missing)");
    failed = failed + t_format_functional();
    failed = failed + t_codec_probe();
  } else {
    if p.error.kind == MEDIANDK_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- libmediandk.so not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  mediandk_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.mediandk: all tests passed");
  } else {
    io.println("xiom.mediandk: tests failed");
  }
  return failed;
}
