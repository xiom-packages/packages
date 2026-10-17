// xiom.nvenc conformance suite -- NVENC encode + NVDEC/cuvid decode via
// the NVIDIA display-driver DLLs (nothing vendored).
//
// CI WITHOUT AN NVIDIA GPU stays green: the deterministic skip paths pass a
// bogus DLL name (LOAD_ABSENT), and every live group reports SKIP when the
// loader/device/codec is absent.  On the pinned RTX 3070 Ti host the suite
// runs a real H.264 and HEVC encode, then feeds the bitstream to NVDEC,
// maps/copies the decoded NV12 frame and checks the synthetic pattern.
//
// Build+run (the bridge C source rides in port.args.json):
//   scripts/port.ps1 -Package xiom.nvenc -TimeoutSec 300

module nvenc_conformance

use xiom.io;
use xiom.test;
use xiom.nvenc;

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}
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

fn skip_or_fail(err: &NvError, name: Str) -> Int {
  if nvenc_is_skip(err) {
    return report(true, name + ": SKIP -- " + err.message);
  }
  return report(false, name + ": " + err.message);
}

fn h264_sps_first(b: &Vec[UInt8]) -> Bool
  requires: b.len() >= 0
{
  if b.len() < 5 { return false; }
  if (b[0] as Int) != 0 { return false; }
  if (b[1] as Int) != 0 { return false; }
  if (b[2] as Int) != 0 { return false; }
  if (b[3] as Int) != 1 { return false; }
  return ((b[4] as Int) & 0x1F) == 7;
}

fn hevc_sps_first(b: &Vec[UInt8]) -> Bool
  requires: b.len() >= 0
{
  if b.len() < 5 { return false; }
  if (b[0] as Int) != 0 { return false; }
  if (b[1] as Int) != 0 { return false; }
  if (b[2] as Int) != 0 { return false; }
  if (b[3] as Int) != 1 { return false; }
  let nal_type = ((b[4] as Int) >> 1) & 0x3F;
  return nal_type == 32 || nal_type == 33;
}

fn has_variation(b: &Vec[UInt8], n: Int) -> Bool
  requires: n >= 0
  requires: b.len() >= n
{
  if n <= 0 { return false; }
  let first = b[0];
  var i = 1;
  while i < n {
    if b[i] != first { return true; }
    i = i + 1;
  }
  return false;
}

/// One full codec pipeline: NVENC session -> initialize -> register ->
/// fill -> bitstream -> encode -> lock/copy/unlock -> destroy, then NVDEC
/// create -> parse/decode -> map -> copy -> unmap -> destroy.
fn run_pipeline(codec: Int, label: Str, decode_available: Bool) -> Int {
  var failed = 0;

  let r_open = nvenc_open(codec);
  if !r_open.is_ok {
    return skip_or_fail(&r_open.error, label + " open session");
  }
  let session = r_open.value;

  let r_init = nvenc_initialize(session, 320, 240, 30, 1, NVE_PRESET_P1);
  if !r_init.is_ok {
    failed = failed + report(false, label + " initialize: " + r_init.error.message);
    nvenc_destroy(session);
    return failed;
  }
  failed = failed + report(true, label + " initialize (P1, 320x240, NV12)");

  let r_res = nvenc_register_resource(session);
  if !r_res.is_ok {
    failed = failed + report(false, label + " register resource: " + r_res.error.message);
    nvenc_destroy(session);
    return failed;
  }
  failed = failed + report(true, label + " register CUDA device resource");

  let r_fill = nvenc_fill_frame(session);
  if !r_fill.is_ok {
    failed = failed + report(false, label + " fill frame: " + r_fill.error.message);
    nvenc_destroy(session);
    return failed;
  }
  failed = failed + report(true, label + " upload deterministic NV12 frame");

  let r_bs = nvenc_create_bitstream(session);
  if !r_bs.is_ok {
    failed = failed + report(false, label + " create bitstream: " + r_bs.error.message);
    nvenc_destroy(session);
    return failed;
  }
  failed = failed + report(true, label + " create bitstream buffer");

  let r_enc = nvenc_encode_frame(session, true);
  if !r_enc.is_ok {
    failed = failed + report(false, label + " encode frame: " + r_enc.error.message);
    nvenc_destroy(session);
    return failed;
  }
  failed = failed + report(true, label + " encode one forced-IDR frame");

  let r_lock = nvenc_lock_bitstream(session);
  if !r_lock.is_ok {
    failed = failed + report(false, label + " lock bitstream: " + r_lock.error.message);
    nvenc_destroy(session);
    return failed;
  }
  let nbytes = r_lock.value.size;
  failed = failed + report(nbytes > 100, label + " lock bitstream: " + i2s(nbytes) + " bytes");
  failed = failed + report(r_lock.value.picture_type == 3,
    label + " forced IDR picture type (3)");

  var bs: Vec[UInt8] = Vec[UInt8].with_len(nbytes);
  let tiny: Vec[UInt8] = Vec[UInt8].with_len(4);
  let r_small = nvenc_copy_bitstream(session, &tiny, 4);
  if r_small.is_ok {
    failed = failed + report(false, label + " short copy unexpectedly succeeded");
  } else {
    failed = failed + report(r_small.error.kind == NVE_BUFFER_TOO_SMALL,
      label + " short copy classified NVE_BUFFER_TOO_SMALL");
  }

  let r_copy = nvenc_copy_bitstream(session, &bs, nbytes);
  if !r_copy.is_ok {
    failed = failed + report(false, label + " copy bitstream: " + r_copy.error.message);
    let ru = nvenc_unlock_bitstream(session);
    nvenc_destroy(session);
    return failed;
  }
  failed = failed + report(r_copy.value == nbytes, label + " copy bitstream bytes");

  var sps_ok = false;
  if codec == NVE_CODEC_H264 {
    sps_ok = h264_sps_first(&bs);
  } else {
    sps_ok = hevc_sps_first(&bs);
  }
  failed = failed + report(sps_ok, label + " Annex-B start code + parameter-set NAL first");

  let r_unlock = nvenc_unlock_bitstream(session);
  failed = failed + report(r_unlock.is_ok, label + " unlock bitstream");
  let r_destroy = nvenc_destroy(session);
  failed = failed + report(r_destroy.is_ok, label + " destroy encode session");

  if !decode_available {
    failed = failed + report(true, label + " decode: SKIP -- NVDEC unavailable");
    return failed;
  }

  let r_dec = nvdec_create(codec, 320, 240, 8);
  if !r_dec.is_ok {
    failed = failed + skip_or_fail(&r_dec.error, label + " create decoder");
    return failed;
  }
  let dec = r_dec.value;
  failed = failed + report(true, label + " create NVDEC decoder");

  let r_parse = nvdec_parse(dec, &bs, nbytes);
  if !r_parse.is_ok {
    failed = failed + skip_or_fail(&r_parse.error, label + " parse/decode");
    nvdec_destroy(dec);
    return failed;
  }
  let info = r_parse.value;
  failed = failed + report(info.sequence_count >= 1, label + " parser sequence callback");
  failed = failed + report(info.decoded_count == 1, label + " decode picture count == 1");
  failed = failed + report(info.display_count == 1, label + " display picture count == 1");
  failed = failed + report(info.coded_width == 320, label + " coded width 320");
  failed = failed + report(info.coded_height >= 240, label + " coded height >= 240");
  failed = failed + report(info.chroma_format == 1, label + " chroma format 4:2:0");
  failed = failed + report(info.bit_depth == 8, label + " bit depth 8");

  let r_map = nvdec_map(dec, info.last_picture_index);
  if !r_map.is_ok {
    failed = failed + report(false, label + " map frame: " + r_map.error.message);
    nvdec_destroy(dec);
    return failed;
  }
  failed = failed + report(true, label + " map decoded frame");

  let frame_bytes = 320 * 240 * 3 / 2;
  var frame: Vec[UInt8] = Vec[UInt8].with_len(frame_bytes);
  let r_frame = nvdec_copy_frame(dec, &frame, frame_bytes);
  if !r_frame.is_ok {
    failed = failed + report(false, label + " copy frame: " + r_frame.error.message);
    let ru = nvdec_unmap(dec);
    nvdec_destroy(dec);
    return failed;
  }
  failed = failed + report(r_frame.value.bytes == frame_bytes,
    label + " compact NV12 frame bytes (" + i2s(frame_bytes) + ")");
  failed = failed + report((frame[320 * 240] as Int) == 96 && (frame[320 * 240 + 1] as Int) == 96,
    label + " chroma plane carries the neutral 96 value");
  failed = failed + report(has_variation(&frame, 320 * 240),
    label + " luma plane is non-constant");

  let r_unmap = nvdec_unmap(dec);
  failed = failed + report(r_unmap.is_ok, label + " unmap frame");
  let r_dec_destroy = nvdec_destroy(dec);
  failed = failed + report(r_dec_destroy.is_ok, label + " destroy decoder");
  return failed;
}


fn main() -> Int {
  io.println("=== xiom.nvenc conformance tests (NVENC + NVDEC, runtime loaders) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // 1. Deterministic typed-error paths (no driver required).
  let miss = nvenc_probe_named("xiom-absent-nvenc-probe-xyz.dll");
  if miss.is_ok {
    failed = failed + report(false, "skip-path: bogus NVENC loader unexpectedly succeeded");
  } else {
    failed = failed + report(miss.error.kind == NVE_LOAD_ABSENT,
      "skip-path: missing NVENC loader -> NVE_LOAD_ABSENT");
  }
  let dmiss = nvdec_probe_named("xiom-absent-nvdec-probe-xyz.dll");
  if dmiss.is_ok {
    failed = failed + report(false, "skip-path: bogus NVDEC loader unexpectedly succeeded");
  } else {
    failed = failed + report(dmiss.error.kind == NVE_LOAD_ABSENT,
      "skip-path: missing NVDEC loader -> NVE_LOAD_ABSENT");
  }
  let bad_enc = nvenc_destroy(99);
  if bad_enc.is_ok {
    failed = failed + report(false, "bad handle: nvenc_destroy(99) unexpectedly succeeded");
  } else {
    failed = failed + report(bad_enc.error.kind == NVE_BAD_HANDLE,
      "typed error: invalid encoder handle -> NVE_BAD_HANDLE");
  }
  let bad_dec = nvdec_destroy(99);
  if bad_dec.is_ok {
    failed = failed + report(false, "bad handle: nvdec_destroy(99) unexpectedly succeeded");
  } else {
    failed = failed + report(bad_dec.error.kind == NVE_BAD_HANDLE,
      "typed error: invalid decoder handle -> NVE_BAD_HANDLE");
  }
  let skip_err = NvError{ kind: NVE_LOAD_ABSENT; stage: 0; code: 0; message: "x" };
  failed = failed + report(nvenc_is_skip(&skip_err), "skip classifier: LOAD_ABSENT is SKIP");
  let api_err = NvError{ kind: NVE_API_FAILED; stage: 3; code: 1; message: "x" };
  failed = failed + report(!nvenc_is_skip(&api_err), "skip classifier: API failure is not SKIP");

  // 2. NVENC probe (live or SKIP).
  var nvenc_ok = false;
  var hevc_ok = false;
  let caps = nvenc_probe();
  if caps.is_ok {
    nvenc_ok = true;
    hevc_ok = caps.value.hevc;
    failed = failed + report(caps.value.api_major >= 13,
      "nvenc probe: API " + i2s(caps.value.api_major) + "." + i2s(caps.value.api_minor));
    failed = failed + report(caps.value.guid_count >= 2, "nvenc probe: GUID count >= 2");
    failed = failed + report(caps.value.h264, "nvenc probe: H.264 encode advertised");
    failed = failed + report(caps.value.width_max >= 320 && caps.value.height_max >= 240,
      "nvenc probe: max " + i2s(caps.value.width_max) + "x" + i2s(caps.value.height_max));
    failed = failed + report(caps.value.num_engines >= 1, "nvenc probe: encoder engines >= 1");
    failed = failed + report(nvenc_caps_summary(&caps.value).len() > 0,
      "nvenc probe: summary " + nvenc_caps_summary(&caps.value));
  } else {
    failed = failed + skip_or_fail(&caps.error, "nvenc probe");
  }

  // 3. NVDEC probe (live or SKIP).
  var nvdec_ok = false;
  let dcaps = nvdec_probe();
  if dcaps.is_ok {
    nvdec_ok = true;
    failed = failed + report(dcaps.value.h264, "nvdec probe: H.264 decode advertised");
    failed = failed + report(dcaps.value.h264_max_width >= 320 && dcaps.value.h264_max_height >= 240,
      "nvdec probe: H.264 max " + i2s(dcaps.value.h264_max_width) + "x"
        + i2s(dcaps.value.h264_max_height));
    failed = failed + report(dcaps.value.h264_num_decoders >= 1, "nvdec probe: NVDEC engines >= 1");
  } else {
    failed = failed + skip_or_fail(&dcaps.error, "nvdec probe");
  }

  // 4. Full pipelines (encode -> decode) where the host supports them.
  if nvenc_ok {
    failed = failed + run_pipeline(NVE_CODEC_H264, "h264", nvdec_ok);
    if hevc_ok {
      failed = failed + run_pipeline(NVE_CODEC_HEVC, "hevc", nvdec_ok);
    } else {
      failed = failed + report(true, "hevc pipeline: SKIP -- HEVC encode unsupported");
    }
  } else {
    failed = failed + report(true, "encode/decode pipelines: SKIP -- NVENC unavailable");
  }

  if failed == 0 {
    io.println("xiom.nvenc: all tests passed");
  } else {
    io.println("xiom.nvenc: tests failed");
  }
  return failed;
}
