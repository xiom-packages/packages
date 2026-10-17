// XIOM -- xiom.nvenc: NVIDIA hardware video encode (NVENC) + decode
// (NVDEC/cuvid) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing is vendored**.  `nvEncodeAPI64.dll`
// and `nvcuvid.dll` ship with the NVIDIA display driver; `nvcuda.dll` supplies
// the CUDA context both APIs need.  All three are loaded at run time with
// LoadLibraryA and every entry point is resolved with GetProcAddress.  The
// package links no import library and no upstream code; `src/nvenc_bridge.c`
// is original XIOM-side code encoding only the public struct layouts from the
// pinned nv-codec-headers (PROVENANCE.md).
//
// Classification: loader/device/codec absent -> SKIP-capable typed errors;
// a present driver that rejects a declared operation -> FAIL.  The
// deterministic SKIP path is exercisable on every host by passing a bogus
// DLL name to `nvenc_probe_named` / `nvdec_probe_named`.
//
// Handles are small integer slots owned by the C bridge; foreign pointers
// never cross the FFI (B-20/B-23/B-25).  The declared surface is exactly the
// subset documented in SPEC.md and covered by tests/test_conformance.xi.

module xiom.nvenc

use xiom.string;

extern "C" {
  fn nvb_nvenc_probe_run(dll: *UInt8) -> Int32;
  fn nvb_nvenc_probe_api_major() -> Int32;
  fn nvb_nvenc_probe_api_minor() -> Int32;
  fn nvb_nvenc_probe_guid_count() -> Int32;
  fn nvb_nvenc_probe_h264() -> Int32;
  fn nvb_nvenc_probe_hevc() -> Int32;
  fn nvb_nvenc_probe_width_max() -> Int32;
  fn nvb_nvenc_probe_height_max() -> Int32;
  fn nvb_nvenc_probe_num_engines() -> Int32;

  fn nvb_nvenc_open_session(codec: Int32) -> Int32;
  fn nvb_nvenc_initialize(handle: Int32, width: Int32, height: Int32, fps_num: Int32,
                      fps_den: Int32, preset: Int32) -> Int32;
  fn nvb_nvenc_register_resource(handle: Int32) -> Int32;
  fn nvb_nvenc_fill_frame(handle: Int32) -> Int32;
  fn nvb_nvenc_create_bitstream(handle: Int32) -> Int32;
  fn nvb_nvenc_encode_frame(handle: Int32, force_idr: Int32) -> Int32;
  fn nvb_nvenc_lock_bitstream(handle: Int32) -> Int32;
  fn nvb_nvenc_locked_size(handle: Int32) -> Int32;
  fn nvb_nvenc_locked_picture_type(handle: Int32) -> Int32;
  fn nvb_nvenc_copy_bitstream(handle: Int32, out: *UInt8, capacity: Int32) -> Int32;
  fn nvb_nvenc_unlock_bitstream(handle: Int32) -> Int32;
  fn nvb_nvenc_destroy(handle: Int32) -> Int32;

  fn nvb_nvdec_probe_run(dll: *UInt8) -> Int32;
  fn nvb_nvdec_probe_h264() -> Int32;
  fn nvb_nvdec_probe_hevc() -> Int32;
  fn nvb_nvdec_probe_h264_max_width() -> Int32;
  fn nvb_nvdec_probe_h264_max_height() -> Int32;
  fn nvb_nvdec_probe_h264_num_decoders() -> Int32;
  fn nvb_nvdec_probe_hevc_max_width() -> Int32;
  fn nvb_nvdec_probe_hevc_max_height() -> Int32;
  fn nvb_nvdec_probe_hevc_num_decoders() -> Int32;

  fn nvb_nvdec_create(codec: Int32, width: Int32, height: Int32, surfaces: Int32) -> Int32;
  fn nvb_nvdec_parse(handle: Int32, data: *UInt8, length: Int32) -> Int32;
  fn nvb_nvdec_sequence_count(handle: Int32) -> Int32;
  fn nvb_nvdec_decoded_count(handle: Int32) -> Int32;
  fn nvb_nvdec_display_count(handle: Int32) -> Int32;
  fn nvb_nvdec_last_picture_index(handle: Int32) -> Int32;
  fn nvb_nvdec_coded_width(handle: Int32) -> Int32;
  fn nvb_nvdec_coded_height(handle: Int32) -> Int32;
  fn nvb_nvdec_chroma_format(handle: Int32) -> Int32;
  fn nvb_nvdec_bit_depth(handle: Int32) -> Int32;
  fn nvb_nvdec_frame_width(handle: Int32) -> Int32;
  fn nvb_nvdec_frame_height(handle: Int32) -> Int32;
  fn nvb_nvdec_map(handle: Int32, picture_index: Int32) -> Int32;
  fn nvb_nvdec_copy_frame(handle: Int32, out: *UInt8, capacity: Int32) -> Int32;
  fn nvb_nvdec_unmap(handle: Int32) -> Int32;
  fn nvb_nvdec_destroy(handle: Int32) -> Int32;

  fn nvb_nv_last_error_text() -> *UInt8;
  fn nvb_nv_last_error_stage() -> Int32;
  fn nvb_nv_last_error_code() -> Int32;
}

// ---- error kinds ----------------------------------------------------------

pub const NVE_LOAD_ABSENT: Int = 0;        // driver DLL missing -> SKIP
pub const NVE_NO_DEVICE: Int = 1;          // no GPU / no CUDA device -> SKIP
pub const NVE_UNSUPPORTED: Int = 2;        // codec/API not supported -> SKIP
pub const NVE_BAD_HANDLE: Int = 3;         // invalid integer handle -> FAIL
pub const NVE_STATE: Int = 4;              // call-order / argument error -> FAIL
pub const NVE_ABI: Int = 5;                // entry point missing -> FAIL
pub const NVE_API_FAILED: Int = 6;         // driver rejected the call -> FAIL
pub const NVE_BUFFER_TOO_SMALL: Int = 7;   // caller buffer too small -> FAIL
pub const NVE_INTERNAL: Int = 8;           // bridge allocation/other -> FAIL

pub type NvError = {
  kind: Int;
  stage: Int;
  code: Int;
  message: Str;
}

// ---- declared codecs / presets -------------------------------------------

pub const NVE_CODEC_H264: Int = 0;
pub const NVE_CODEC_HEVC: Int = 1;
pub const NVE_PRESET_P1: Int = 1;  // fastest
pub const NVE_PRESET_P2: Int = 2;
pub const NVE_PRESET_P3: Int = 3;
pub const NVE_PRESET_P4: Int = 4;
pub const NVE_PRESET_P5: Int = 5;
pub const NVE_PRESET_P6: Int = 6;
pub const NVE_PRESET_P7: Int = 7;  // slowest / best quality

// ---- capability / outcome records ----------------------------------------

pub type NvencCaps = {
  api_major: Int;        // NVENC API major (13 on the header pin)
  api_minor: Int;        // NVENC API minor (1 on the header pin)
  guid_count: Int;       // encoder GUIDs advertised by the driver
  h264: Bool;
  hevc: Bool;
  width_max: Int;
  height_max: Int;
  num_engines: Int;
}

pub type NvencLock = {
  size: Int;             // locked bitstream size in bytes
  picture_type: Int;     // NV_ENC_PIC_TYPE (3 = IDR on a forced key frame)
}

pub type NvdecCaps = {
  h264: Bool;
  hevc: Bool;
  h264_max_width: Int;
  h264_max_height: Int;
  h264_num_decoders: Int;
  hevc_max_width: Int;
  hevc_max_height: Int;
  hevc_num_decoders: Int;
}

pub type NvdecInfo = {
  sequence_count: Int;       // parser sequence callbacks
  decoded_count: Int;        // cuvidDecodePicture successes
  display_count: Int;        // parser display callbacks
  last_picture_index: Int;
  coded_width: Int;
  coded_height: Int;
  chroma_format: Int;        // cudaVideoChromaFormat (1 = 4:2:0)
  bit_depth: Int;
}

pub type NvdecFrame = {
  bytes: Int;                // compact NV12 bytes copied (w*h*3/2)
  width: Int;
  height: Int;
}

// ---- internals ------------------------------------------------------------

fn nv_kind_code(neg: Int) -> Int
  requires: neg < 0
{
  if neg == -100 || neg == -115 { return NVE_LOAD_ABSENT; }
  if neg == -101 || neg == -104 { return NVE_NO_DEVICE; }
  if neg == -103 || neg == -105 || neg == -106 || neg == -116 { return NVE_UNSUPPORTED; }
  if neg == -108 { return NVE_BAD_HANDLE; }
  if neg == -109 || neg == -121 || neg == -122 { return NVE_STATE; }
  if neg == -102 { return NVE_ABI; }
  if neg == -114 { return NVE_BUFFER_TOO_SMALL; }
  if neg == -123 { return NVE_INTERNAL; }
  return NVE_API_FAILED;
}

fn nv_error(neg: Int) -> NvError
  requires: neg < 0
{
  var msg = "";
  unsafe {
    let p = nvb_nv_last_error_text();
    if (p as Int) != 0 {
      msg = Str::from_c_str(p);
    }
  }
  return NvError{
    kind: nv_kind_code(neg);
    stage: unsafe { nvb_nv_last_error_stage() as Int };
    code: unsafe { nvb_nv_last_error_code() as Int };
    message: msg;
  };
}

/// Whether `err` is a SKIP-classification (loader/device/codec absent).
/// Complexity: O(1).
pub fn nvenc_is_skip(err: &NvError) -> Bool {
  if err.kind == NVE_LOAD_ABSENT { return true; }
  if err.kind == NVE_NO_DEVICE { return true; }
  if err.kind == NVE_UNSUPPORTED { return true; }
  return false;
}

fn nv_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
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
  return buf;
}

// ---- NVENC probe ----------------------------------------------------------

fn nvenc_probe_with(dll: Str) -> Result[NvencCaps, NvError]
  requires: dll.len() > 0
{
  let rc = unsafe { nvb_nvenc_probe_run(dll.c_str()) as Int };
  if rc < 0 {
    return Err(nv_error(rc));
  }
  return Ok(NvencCaps{
    api_major: unsafe { nvb_nvenc_probe_api_major() as Int };
    api_minor: unsafe { nvb_nvenc_probe_api_minor() as Int };
    guid_count: unsafe { nvb_nvenc_probe_guid_count() as Int };
    h264: unsafe { nvb_nvenc_probe_h264() as Int } != 0;
    hevc: unsafe { nvb_nvenc_probe_hevc() as Int } != 0;
    width_max: unsafe { nvb_nvenc_probe_width_max() as Int };
    height_max: unsafe { nvb_nvenc_probe_height_max() as Int };
    num_engines: unsafe { nvb_nvenc_probe_num_engines() as Int };
  });
}

/// Probe the default NVENC loader: API version negotiation
/// (`NvEncodeAPIGetMaxSupportedVersion` + `NvEncodeAPICreateInstance`), a
/// session open on a fresh CUDA context, the codec GUID list, and the
/// H.264/HEVC width/height/engine caps.  Loader absent, no device and
/// unsupported codec are SKIP-class typed errors.
/// Complexity: O(probe).
pub fn nvenc_probe() -> Result[NvencCaps, NvError] {
  return nvenc_probe_with("nvEncodeAPI64.dll");
}

/// Same probe against an explicitly named loader module -- the
/// deterministic SKIP path (pass a bogus name on any host).
/// Complexity: O(probe).
pub fn nvenc_probe_named(dll: Str) -> Result[NvencCaps, NvError]
  requires: dll.len() > 0
{
  return nvenc_probe_with(dll);
}

// ---- NVENC session lifecycle ---------------------------------------------

/// Open an encode session on a fresh CUDA context.  `codec` is
/// `NVE_CODEC_H264` or `NVE_CODEC_HEVC`; the driver GUID list is checked so
/// an unsupported codec is `NVE_UNSUPPORTED` (SKIP), not a late failure.
/// Returns an opaque integer session handle; release with `nvenc_destroy`.
/// Complexity: O(session).
pub fn nvenc_open(codec: Int) -> Result[Int, NvError]
  requires: codec == NVE_CODEC_H264 || codec == NVE_CODEC_HEVC
{
  let h = unsafe { nvb_nvenc_open_session(codec as Int32) as Int };
  if h < 0 { return Err(nv_error(h)); }
  return Ok(h);
}

/// Initialize the encoder with a preset codec configuration (P1..P7,
/// low-latency tuning, NV12 input).  `fps_num/fps_den` is the frame rate.
/// Complexity: O(initialize).
pub fn nvenc_initialize(session: Int, width: Int, height: Int, fps_num: Int, fps_den: Int,
                        preset: Int) -> Result[Unit, NvError]
  requires: session > 0
  requires: width >= 16 && height >= 16
  requires: fps_num > 0 && fps_den > 0
  requires: preset >= NVE_PRESET_P1 && preset <= NVE_PRESET_P7
{
  let rc = unsafe {
    nvb_nvenc_initialize(session as Int32, width as Int32, height as Int32,
                     fps_num as Int32, fps_den as Int32, preset as Int32) as Int
  };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Allocate the input resource: a pitched CUDA device buffer for one NV12
/// frame, registered with NVENC as `CUDADEVICEPTR`.  Complexity: O(1).
pub fn nvenc_register_resource(session: Int) -> Result[Unit, NvError]
  requires: session > 0
{
  let rc = unsafe { nvb_nvenc_register_resource(session as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Upload the deterministic test frame (Y = (x+y)&0xFF, UV = 96) into the
/// registered resource.  Exposed so callers can drive a real encode without
/// a foreign frame surface.  Complexity: O(width*height).
pub fn nvenc_fill_frame(session: Int) -> Result[Unit, NvError]
  requires: session > 0
{
  let rc = unsafe { nvb_nvenc_fill_frame(session as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Create the output bitstream buffer.  Complexity: O(1).
pub fn nvenc_create_bitstream(session: Int) -> Result[Unit, NvError]
  requires: session > 0
{
  let rc = unsafe { nvb_nvenc_create_bitstream(session as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Encode one frame.  `force_idr` requests a key frame.  Complexity:
/// O(frame).
pub fn nvenc_encode_frame(session: Int, force_idr: Bool) -> Result[Unit, NvError]
  requires: session > 0
{
  let flag: Int32 = if force_idr { 1 } else { 0 };
  let rc = unsafe { nvb_nvenc_encode_frame(session as Int32, flag) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Lock the encoded bitstream (the driver blocks until the frame is done).
/// The bridge keeps the lock and exposes size/type getters; call
/// `nvenc_copy_bitstream` then `nvenc_unlock_bitstream`.
/// Complexity: O(1).
pub fn nvenc_lock_bitstream(session: Int) -> Result[NvencLock, NvError]
  requires: session > 0
{
  let rc = unsafe { nvb_nvenc_lock_bitstream(session as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(NvencLock{
    size: unsafe { nvb_nvenc_locked_size(session as Int32) as Int };
    picture_type: unsafe { nvb_nvenc_locked_picture_type(session as Int32) as Int };
  });
}

/// Copy the locked bitstream into an XIOM-owned buffer.  `capacity` is the
/// physical length of `out`; a short buffer is `NVE_BUFFER_TOO_SMALL`.
/// Returns the number of bytes copied.  Complexity: O(size).
pub fn nvenc_copy_bitstream(session: Int, out: &Vec[UInt8], capacity: Int)
    -> Result[Int, NvError]
  requires: session > 0
  requires: capacity >= 0
  requires: out.len() >= capacity
{
  if capacity == 0 {
    return Err(NvError{ kind: NVE_BUFFER_TOO_SMALL; stage: 9; code: 0;
                        message: "copy buffer is empty" });
  }
  let rc = unsafe {
    nvb_nvenc_copy_bitstream(session as Int32, out.as_mut_ptr(), capacity as Int32) as Int
  };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(rc);
}

/// Release the bitstream lock.  Complexity: O(1).
pub fn nvenc_unlock_bitstream(session: Int) -> Result[Unit, NvError]
  requires: session > 0
{
  let rc = unsafe { nvb_nvenc_unlock_bitstream(session as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Destroy the encode session and every resource it owns (lock, mapped
/// input, registered resource, bitstream, encoder, CUDA context).
/// Complexity: O(session).
pub fn nvenc_destroy(session: Int) -> Result[Unit, NvError]
  requires: session > 0
{
  let rc = unsafe { nvb_nvenc_destroy(session as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

// ---- NVDEC ----------------------------------------------------------------

fn nvdec_probe_with(dll: Str) -> Result[NvdecCaps, NvError]
  requires: dll.len() > 0
{
  let rc = unsafe { nvb_nvdec_probe_run(dll.c_str()) as Int };
  if rc < 0 {
    return Err(nv_error(rc));
  }
  return Ok(NvdecCaps{
    h264: unsafe { nvb_nvdec_probe_h264() as Int } != 0;
    hevc: unsafe { nvb_nvdec_probe_hevc() as Int } != 0;
    h264_max_width: unsafe { nvb_nvdec_probe_h264_max_width() as Int };
    h264_max_height: unsafe { nvb_nvdec_probe_h264_max_height() as Int };
    h264_num_decoders: unsafe { nvb_nvdec_probe_h264_num_decoders() as Int };
    hevc_max_width: unsafe { nvb_nvdec_probe_hevc_max_width() as Int };
    hevc_max_height: unsafe { nvb_nvdec_probe_hevc_max_height() as Int };
    hevc_num_decoders: unsafe { nvb_nvdec_probe_hevc_num_decoders() as Int };
  });
}

/// Probe the default NVDEC loader (`nvcuvid.dll`) through a fresh CUDA
/// context: `cuvidGetDecoderCaps` for H.264/HEVC 4:2:0 8-bit.  Loader
/// absent, no device and unsupported codec are SKIP-class typed errors.
/// Complexity: O(probe).
pub fn nvdec_probe() -> Result[NvdecCaps, NvError] {
  return nvdec_probe_with("nvcuvid.dll");
}

/// Same probe against an explicitly named loader module -- the
/// deterministic SKIP path.  Complexity: O(probe).
pub fn nvdec_probe_named(dll: Str) -> Result[NvdecCaps, NvError]
  requires: dll.len() > 0
{
  return nvdec_probe_with(dll);
}

/// Create a hardware decoder (CUDA context + context lock + decoder) for
/// H.264 or HEVC, NV12 output at `width`x`height`.  `surfaces` is the
/// internal decode-surface count (0 -> 8, clamped to 32).  Returns an
/// opaque integer handle; release with `nvdec_destroy`.
/// Complexity: O(decoder).
pub fn nvdec_create(codec: Int, width: Int, height: Int, surfaces: Int)
    -> Result[Int, NvError]
  requires: codec == NVE_CODEC_H264 || codec == NVE_CODEC_HEVC
  requires: width >= 16 && height >= 16
  requires: surfaces >= 0
{
  let h = unsafe {
    nvb_nvdec_create(codec as Int32, width as Int32, height as Int32, surfaces as Int32) as Int
  };
  if h < 0 { return Err(nv_error(h)); }
  return Ok(h);
}

/// Parse one Annex-B access unit with the cuvid video parser and decode
/// every picture the parser emits.  Returns the post-parse counters and the
/// sequence geometry read from the parser callback.  Complexity: O(stream).
pub fn nvdec_parse(decoder: Int, data: &Vec[UInt8], length: Int)
    -> Result[NvdecInfo, NvError]
  requires: decoder > 0
  requires: length > 0
  requires: data.len() >= length
{
  let rc = unsafe {
    nvb_nvdec_parse(decoder as Int32, data.as_mut_ptr(), length as Int32) as Int
  };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(NvdecInfo{
    sequence_count: unsafe { nvb_nvdec_sequence_count(decoder as Int32) as Int };
    decoded_count: unsafe { nvb_nvdec_decoded_count(decoder as Int32) as Int };
    display_count: unsafe { nvb_nvdec_display_count(decoder as Int32) as Int };
    last_picture_index: unsafe { nvb_nvdec_last_picture_index(decoder as Int32) as Int };
    coded_width: unsafe { nvb_nvdec_coded_width(decoder as Int32) as Int };
    coded_height: unsafe { nvb_nvdec_coded_height(decoder as Int32) as Int };
    chroma_format: unsafe { nvb_nvdec_chroma_format(decoder as Int32) as Int };
    bit_depth: unsafe { nvb_nvdec_bit_depth(decoder as Int32) as Int };
  });
}

/// Map a decoded picture (`picture_index` from the parser) for CUDA access.
/// The mapping stays owned by the bridge until `nvdec_unmap`.
/// Complexity: O(1).
pub fn nvdec_map(decoder: Int, picture_index: Int) -> Result[Unit, NvError]
  requires: decoder > 0
  requires: picture_index >= 0
{
  let rc = unsafe { nvb_nvdec_map(decoder as Int32, picture_index as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Copy the mapped frame into an XIOM-owned compact NV12 buffer
/// (`width*height*3/2` bytes: Y plane then interleaved UV plane).
/// `capacity` is the physical length of `out`.  Complexity: O(frame).
pub fn nvdec_copy_frame(decoder: Int, out: &Vec[UInt8], capacity: Int)
    -> Result[NvdecFrame, NvError]
  requires: decoder > 0
  requires: capacity >= 0
  requires: out.len() >= capacity
{
  if capacity == 0 {
    return Err(NvError{ kind: NVE_BUFFER_TOO_SMALL; stage: 14; code: 0;
                        message: "frame buffer is empty" });
  }
  let rc = unsafe {
    nvb_nvdec_copy_frame(decoder as Int32, out.as_mut_ptr(), capacity as Int32) as Int
  };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(NvdecFrame{
    bytes: rc;
    width: unsafe { nvb_nvdec_frame_width(decoder as Int32) as Int };
    height: unsafe { nvb_nvdec_frame_height(decoder as Int32) as Int };
  });
}

/// Unmap the mapped picture.  Complexity: O(1).
pub fn nvdec_unmap(decoder: Int) -> Result[Unit, NvError]
  requires: decoder > 0
{
  let rc = unsafe { nvb_nvdec_unmap(decoder as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Destroy the decoder: unmaps any live mapping, then releases the parser,
/// decoder, context lock and CUDA context.  Complexity: O(decoder).
pub fn nvdec_destroy(decoder: Int) -> Result[Unit, NvError]
  requires: decoder > 0
{
  let rc = unsafe { nvb_nvdec_destroy(decoder as Int32) as Int };
  if rc < 0 { return Err(nv_error(rc)); }
  return Ok(());
}

/// Developer-facing summary line for a probe (handy in logs).
/// Complexity: O(1).
pub fn nvenc_caps_summary(caps: &NvencCaps) -> Str
  requires: caps.api_major > 0
{
  var s = "NVENC " + nv_i2s(caps.api_major) + "." + nv_i2s(caps.api_minor);
  s = s + " codecs=";
  if caps.h264 { s = s + "h264"; }
  if caps.hevc {
    if caps.h264 { s = s + "+"; }
    s = s + "hevc";
  }
  s = s + " max=" + nv_i2s(caps.width_max) + "x" + nv_i2s(caps.height_max);
  return s;
}
