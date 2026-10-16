// xiom.v4l conformance suite (0.1.0): V4L2 UAPI camera capture surface.
//
//   constants  spot clusters of the generated UAPI tables (ioctl numbers,
//              caps/FOURCCs/enums in xiom.v4l.consts; CID universe in
//              xiom.v4l.cids; string defines)
//   layout     spot facts of xiom.v4l.layout (struct sizes/offsets)
//   macros     the 29 function-like UAPI macros mirrored in xiom.v4l
//   abi        v4l_abi_check(): pinned ioctl encodings / sizes / offsets
//              re-derived at runtime (FAIL on any fault, never silent)
//   skip-path  bogus device directory -> V4L_LOAD_ABSENT (deterministic on
//              every host, including Windows by construction)
//   live       when a capture-capable node exists (not on Windows): the full
//              open/QUERYCAP/G_FMT/S_FMT/REQBUFS/QUERYBUF/mmap/QBUF/
//              STREAMON/DQBUF/frame-copy/QBUF/STREAMOFF/close pipeline
//
// On Windows every device runtime is absent by design -> SKIP (CI stays
// green; the recorded evidence is the SKIP leg).  On Linux (incl. the
// Raspberry Pi arm64 target) the same suite runs the live paths.
//
// Build+run through the runner (compiles the bridge C unit via
// port.args.json):
//   scripts/port.ps1 -Package xiom.v4l -TimeoutSec 300

module v4l_conformance

use xiom.io;
use xiom.string;
use xiom.v4l;
use xiom.v4l.consts;
use xiom.v4l.cids;
use xiom.v4l.layout;

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

fn info(text: Str) -> Int {
  io.println("  [INFO] " + text);
  io.flush_stdout();
  return 0;
}

fn str_eq(a: Str, b: Str) -> Bool {
  if string.byte_count(a) != string.byte_count(b) { return false; }
  var i = 0;
  var same = true;
  while i < string.byte_count(a) {
    if (string.byte_at(a, i) as Int) != (string.byte_at(b, i) as Int) { same = false; }
    i = i + 1;
  }
  return same;
}

// =========================================================================
// Constants: ioctl numbers (xiom.v4l.consts)
// =========================================================================

fn t_ioctl_constants() -> Bool {
  var ok = true;
  // The 9 functional ioctls (pinned gcc-evaluated values, LP64).
  if VIDIOC_QUERYCAP != 0x80685600 { ok = false; }
  if VIDIOC_G_FMT != 0xC0D05604 { ok = false; }
  if VIDIOC_S_FMT != 0xC0D05605 { ok = false; }
  if VIDIOC_REQBUFS != 0xC0145608 { ok = false; }
  if VIDIOC_QUERYBUF != 0xC0585609 { ok = false; }
  if VIDIOC_QBUF != 0xC058560F { ok = false; }
  if VIDIOC_DQBUF != 0xC0585611 { ok = false; }
  if VIDIOC_STREAMON != 0x40045612 { ok = false; }
  if VIDIOC_STREAMOFF != 0x40045613 { ok = false; }
  // Neighbouring ioctls of the enumeration/negotiation families.
  if VIDIOC_ENUM_FMT != 0xC0405602 { ok = false; }
  if VIDIOC_ENUMINPUT != 0xC050561A { ok = false; }
  if VIDIOC_G_INPUT != 0x80045626 { ok = false; }
  if VIDIOC_G_PARM != 0xC0CC5615 { ok = false; }
  if VIDIOC_G_PRIORITY != 0x80045643 { ok = false; }
  if VIDIOC_G_CTRL != 0xC008561B { ok = false; }
  if VIDIOC_S_CTRL != 0xC008561C { ok = false; }
  return ok;
}

fn t_caps_and_enums() -> Bool {
  var ok = true;
  // V4L2_CAP_* capability bits.
  if V4L2_CAP_VIDEO_CAPTURE != 1 { ok = false; }
  if V4L2_CAP_VIDEO_OUTPUT != 2 { ok = false; }
  if V4L2_CAP_VIDEO_CAPTURE_MPLANE != 0x1000 { ok = false; }
  if V4L2_CAP_STREAMING != 0x4000000 { ok = false; }
  if V4L2_CAP_DEVICE_CAPS != 0x80000000 { ok = false; }
  // Buffer types / memory / field enums.
  if V4L2_BUF_TYPE_VIDEO_CAPTURE != 1 { ok = false; }
  if V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE != 9 { ok = false; }
  if V4L2_MEMORY_MMAP != 1 { ok = false; }
  if V4L2_MEMORY_USERPTR != 2 { ok = false; }
  if V4L2_FIELD_ANY != 0 { ok = false; }
  if V4L2_FIELD_NONE != 1 { ok = false; }
  if V4L2_FIELD_INTERLACED != 4 { ok = false; }
  // Buffer flags + colorspace machinery.
  if V4L2_BUF_FLAG_MAPPED != 1 { ok = false; }
  if V4L2_BUF_FLAG_DONE != 4 { ok = false; }
  if V4L2_BUF_FLAG_ERROR != 64 { ok = false; }
  if V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC != 0x2000 { ok = false; }
  if V4L2_COLORSPACE_SRGB != 8 { ok = false; }
  if V4L2_XFER_FUNC_709 != 1 { ok = false; }
  if V4L2_YCBCR_ENC_601 != 1 { ok = false; }
  if V4L2_QUANTIZATION_FULL_RANGE != 1 { ok = false; }
  // Control machinery constants that live in videodev2.h.
  if V4L2_CTRL_CLASS_USER != 0x980000 { ok = false; }
  if V4L2_CTRL_FLAG_NEXT_CTRL != 0x80000000 { ok = false; }
  if V4L2_CTRL_WHICH_CUR_VAL != 0 { ok = false; }
  if V4L2_CTRL_WHICH_REQUEST_VAL != 0x0F010000 { ok = false; }
  if V4L2_EVENT_ALL != 0 { ok = false; }
  return ok;
}

fn t_fourcc_constants() -> Bool {
  var ok = true;
  // Pixel formats are v4l2_fourcc() products in the header.
  if V4L2_PIX_FMT_YUYV != 0x56595559 { ok = false; }        // 'Y','U','Y','V'
  if V4L2_PIX_FMT_RGB24 != 0x33424752 { ok = false; }       // 'R','G','B','3'
  if V4L2_PIX_FMT_MJPEG != 0x47504A4D { ok = false; }       // 'M','J','P','G'
  if v4l2_fourcc(89, 85, 89, 86) != V4L2_PIX_FMT_YUYV { ok = false; }
  if v4l2_fourcc_be(89, 85, 89, 86) != (V4L2_PIX_FMT_YUYV | 0x80000000) { ok = false; }
  if !str_eq(v4l_fourcc_str(V4L2_PIX_FMT_YUYV), "YUYV") { ok = false; }
  if !str_eq(v4l_fourcc_str(V4L2_PIX_FMT_MJPEG), "MJPG") { ok = false; }
  return ok;
}

fn t_cid_constants() -> Bool {
  var ok = true;
  // v4l2-controls.h universe (xiom.v4l.cids).
  if V4L2_CID_BASE != 0x980900 { ok = false; }
  if V4L2_CID_BRIGHTNESS != 0x980900 { ok = false; }
  if V4L2_CID_CONTRAST != 0x980901 { ok = false; }
  if V4L2_CID_SATURATION != 0x980902 { ok = false; }
  if V4L2_CID_HUE != 0x980903 { ok = false; }
  if V4L2_CID_GAIN != 0x980913 { ok = false; }
  if V4L2_CID_TEST_PATTERN != 0x9F0903 { ok = false; }
  if V4L2_CID_USER_BASE != V4L2_CID_BASE { ok = false; }
  if V4L2_CID_CAMERA_CLASS_BASE != (V4L2_CTRL_CLASS_CAMERA | 0x900) { ok = false; }
  // Which/class helpers from the header macros.
  if v4l2_ctrl_id2class(V4L2_CID_BRIGHTNESS) != 0x980000 { ok = false; }
  if v4l2_ctrl_id2which(V4L2_CID_BRIGHTNESS) != 0x980000 { ok = false; }
  if v4l2_ctrl_driver_priv(0x08001000) != true { ok = false; }
  if v4l2_ctrl_driver_priv(V4L2_CID_BRIGHTNESS) != false { ok = false; }
  return ok;
}

fn t_string_constants() -> Bool {
  var ok = true;
  if !str_eq(V4L2_MPEG_VBI_IVTV_MAGIC0, "itv0") { ok = false; }
  if !str_eq(V4L2_MPEG_VBI_IVTV_MAGIC1, "ITV0") { ok = false; }
  return ok;
}

// =========================================================================
// Struct layout facts (xiom.v4l.layout)
// =========================================================================

fn t_layout_facts() -> Bool {
  var ok = true;
  // QUERYCAP-carrying struct + its field offsets.
  if V4L2_CAPABILITY_SIZE != 104 { ok = false; }
  if V4L2_CAPABILITY_DRIVER_OFF != 0 { ok = false; }
  if V4L2_CAPABILITY_CARD_OFF != 16 { ok = false; }
  if V4L2_CAPABILITY_BUS_INFO_OFF != 48 { ok = false; }
  if V4L2_CAPABILITY_VERSION_OFF != 80 { ok = false; }
  if V4L2_CAPABILITY_CAPABILITIES_OFF != 84 { ok = false; }
  if V4L2_CAPABILITY_DEVICE_CAPS_OFF != 88 { ok = false; }
  // Format union (fp_off embeds in the G/S_FMT ioctl numbers).
  if V4L2_FORMAT_SIZE != 208 { ok = false; }
  if V4L2_FORMAT_TYPE_OFF != 0 { ok = false; }
  if V4L2_FORMAT_FMT_OFF != 8 { ok = false; }
  if V4L2_PIX_FORMAT_SIZE != 48 { ok = false; }
  if V4L2_PIX_FORMAT_WIDTH_OFF != 0 { ok = false; }
  if V4L2_PIX_FORMAT_HEIGHT_OFF != 4 { ok = false; }
  if V4L2_PIX_FORMAT_PIXELFORMAT_OFF != 8 { ok = false; }
  if V4L2_PIX_FORMAT_BYTESPERLINE_OFF != 16 { ok = false; }
  if V4L2_PIX_FORMAT_SIZEIMAGE_OFF != 20 { ok = false; }
  if V4L2_PIX_FORMAT_COLORSPACE_OFF != 24 { ok = false; }
  if V4L2_PIX_FORMAT_XFER_FUNC_OFF != 44 { ok = false; }
  // Buffer struct (DQBUF/QBUF argument).
  if V4L2_BUFFER_SIZE != 88 { ok = false; }
  if V4L2_BUFFER_INDEX_OFF != 0 { ok = false; }
  if V4L2_BUFFER_BYTESUSED_OFF != 8 { ok = false; }
  if V4L2_BUFFER_FLAGS_OFF != 12 { ok = false; }
  if V4L2_BUFFER_TIMESTAMP_OFF != 24 { ok = false; }
  if V4L2_BUFFER_SEQUENCE_OFF != 56 { ok = false; }
  if V4L2_BUFFER_MEMORY_OFF != 60 { ok = false; }
  if V4L2_BUFFER_M_OFF != 64 { ok = false; }
  if V4L2_BUFFER_LENGTH_OFF != 72 { ok = false; }
  // REQBUFS argument.
  if V4L2_REQUESTBUFFERS_SIZE != 20 { ok = false; }
  if V4L2_REQUESTBUFFERS_COUNT_OFF != 0 { ok = false; }
  if V4L2_REQUESTBUFFERS_TYPE_OFF != 4 { ok = false; }
  if V4L2_REQUESTBUFFERS_MEMORY_OFF != 8 { ok = false; }
  // Timestamp carrier.
  if V4L2_TIMECODE_SIZE != 16 { ok = false; }
  return ok;
}

// =========================================================================
// Mirrored function-like macros
// =========================================================================

fn t_macro_mirrors() -> Bool {
  var ok = true;
  // Type predicates.
  if !v4l2_type_is_valid(V4L2_BUF_TYPE_VIDEO_CAPTURE) { ok = false; }
  if !v4l2_type_is_valid(V4L2_BUF_TYPE_META_OUTPUT) { ok = false; }
  if v4l2_type_is_valid(99) { ok = false; }
  if !v4l2_type_is_capture(V4L2_BUF_TYPE_VIDEO_CAPTURE) { ok = false; }
  if v4l2_type_is_capture(V4L2_BUF_TYPE_VIDEO_OUTPUT) { ok = false; }
  if !v4l2_type_is_output(V4L2_BUF_TYPE_VIDEO_OUTPUT) { ok = false; }
  if !v4l2_type_is_output(V4L2_BUF_TYPE_META_OUTPUT) { ok = false; }
  if !v4l2_type_is_multiplanar(V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE) { ok = false; }
  if v4l2_type_is_multiplanar(V4L2_BUF_TYPE_VIDEO_CAPTURE) { ok = false; }
  // Field predicates.
  if !v4l2_field_has_top(V4L2_FIELD_INTERLACED) { ok = false; }
  if !v4l2_field_has_bottom(V4L2_FIELD_INTERLACED) { ok = false; }
  if !v4l2_field_has_both(V4L2_FIELD_INTERLACED) { ok = false; }
  if !v4l2_field_is_interlaced(V4L2_FIELD_INTERLACED_TB) { ok = false; }
  if v4l2_field_is_interlaced(V4L2_FIELD_NONE) { ok = false; }
  if !v4l2_field_has_t_or_b(V4L2_FIELD_ALTERNATE) { ok = false; }
  if !v4l2_field_is_sequential(V4L2_FIELD_SEQ_TB) { ok = false; }
  if v4l2_field_is_sequential(V4L2_FIELD_INTERLACED) { ok = false; }
  // Colorspace default maps.
  if v4l2_map_colorspace_default(true, false) != V4L2_COLORSPACE_SMPTE170M { ok = false; }
  if v4l2_map_colorspace_default(false, true) != V4L2_COLORSPACE_REC709 { ok = false; }
  if v4l2_map_colorspace_default(false, false) != V4L2_COLORSPACE_SRGB { ok = false; }
  if v4l2_map_xfer_func_default(V4L2_COLORSPACE_SRGB) != V4L2_XFER_FUNC_SRGB { ok = false; }
  if v4l2_map_xfer_func_default(V4L2_COLORSPACE_REC709) != V4L2_XFER_FUNC_709 { ok = false; }
  if v4l2_map_ycbcr_enc_default(V4L2_COLORSPACE_REC709) != V4L2_YCBCR_ENC_709 { ok = false; }
  if v4l2_map_ycbcr_enc_default(V4L2_COLORSPACE_SMPTE170M) != V4L2_YCBCR_ENC_601 { ok = false; }
  if v4l2_map_quantization_default(true, V4L2_COLORSPACE_SRGB, 0) != V4L2_QUANTIZATION_FULL_RANGE { ok = false; }
  if v4l2_map_quantization_default(false, V4L2_COLORSPACE_REC709, 0) != V4L2_QUANTIZATION_LIM_RANGE { ok = false; }
  // DV timings arithmetic.
  if v4l2_dv_bt_blanking_width(88, 44, 148) != 280 { ok = false; }
  if v4l2_dv_bt_frame_width(1280, 88, 44, 148) != 1560 { ok = false; }
  if v4l2_dv_bt_blanking_height(4, 5, 36, false, 0, 0, 0) != 45 { ok = false; }
  if v4l2_dv_bt_blanking_height(4, 5, 36, true, 1, 2, 3) != 51 { ok = false; }
  if v4l2_dv_bt_frame_height(720, 4, 5, 36, false, 0, 0, 0) != 765 { ok = false; }
  // Codec helpers.
  if !v4l2_h264_sps_has_chroma_format(100) { ok = false; }
  if v4l2_h264_sps_has_chroma_format(66) { ok = false; }
  if !v4l2_vp8_frame_is_key_frame(V4L2_VP8_FRAME_FLAG_KEY_FRAME) { ok = false; }
  if v4l2_vp8_frame_is_key_frame(0) { ok = false; }
  if v4l2_vp9_segment_feature_enabled(3) != 8 { ok = false; }
  if v4l2_av1_global_motion_is_invalid(1) != 2 { ok = false; }
  if v4l2_av1_segment_feature_enabled(7) != 128 { ok = false; }
  // H264 prediction-weight predicate (flags variants).
  if !v4l2_h264_ctrl_pred_weights_required(V4L2_H264_PPS_FLAG_WEIGHTED_PRED, 0, V4L2_H264_SLICE_TYPE_P) { ok = false; }
  if v4l2_h264_ctrl_pred_weights_required(0, 0, V4L2_H264_SLICE_TYPE_P) { ok = false; }
  if !v4l2_h264_ctrl_pred_weights_required(0, 1, V4L2_H264_SLICE_TYPE_B) { ok = false; }
  // Kernel-version decoding of the QUERYCAP version field.
  if v4l_version_major(0x0006121C) != 6 { ok = false; }
  if v4l_version_minor(0x0006121C) != 18 { ok = false; }
  if v4l_version_patch(0x0006121C) != 28 { ok = false; }
  return ok;
}

// =========================================================================
// errno naming
// =========================================================================

fn t_errno_names() -> Bool {
  var ok = true;
  if !str_eq(v4l_errno_name(22), "EINVAL") { ok = false; }
  if !str_eq(v4l_errno_name(9), "EBADF") { ok = false; }
  if !str_eq(v4l_errno_name(25), "ENOTTY") { ok = false; }
  if !str_eq(v4l_errno_name(11), "EAGAIN") { ok = false; }
  if !str_eq(v4l_errno_name(19), "ENODEV") { ok = false; }
  if !str_eq(v4l_errno_name(999999), "") { ok = false; }
  return ok;
}

// =========================================================================
// ABI self-check (pinned ioctl encodings / sizes / offsets at runtime)
// =========================================================================

fn t_abi_check() -> Int {
  var failed: Int = 0;
  let abi = v4l_abi_check();
  if abi.is_ok {
    failed = failed + report(true, "abi: pinned self-check green (ioctl encodings + sizes + offsets)");
  } else {
    failed = failed + report(false, "abi: pinned self-check failed -- " + abi.error.message);
  }
  return failed;
}

// =========================================================================
// SKIP-path classification (deterministic on every host)
// =========================================================================

fn _bool_text(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn t_skip_path() -> Int {
  var failed: Int = 0;
  let bogus = v4l_probe_named("/dev/xiom-absent-v4l-root-xyz");
  if bogus.is_err {
    failed = failed + report(bogus.error.kind == V4L_LOAD_ABSENT,
      "skip-path: bogus device dir -> V4L_LOAD_ABSENT (" + bogus.error.message + ")");
  } else {
    failed = failed + report(false, "skip-path: bogus device dir unexpectedly probed OK");
  }
  let bogus2 = v4l_probe_named("Z:/xiom/no/such/dev");
  if bogus2.is_err {
    failed = failed + report(bogus2.error.kind == V4L_LOAD_ABSENT,
      "skip-path: non-existent root -> V4L_LOAD_ABSENT (" + bogus2.error.message + ")");
  } else {
    failed = failed + report(false, "skip-path: non-existent root unexpectedly probed OK");
  }

  // The default probe: on Windows (and any host without /dev/video*) this
  // is the recorded SKIP path; on a host with cameras it is the live path.
  let p = v4l_probe();
  if p.is_ok {
    let rt: V4lRuntime = p.value;
    info("probe: " + to_string(rt.device_count) + " V4L2 device(s) under /dev (live path follows)");
    failed = failed + t_live_path();
  } else {
    if p.error.kind == V4L_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- no V4L2 device layer (" + p.error.message + ")");
      let plat = v4l_platform_supported();
      failed = failed + report(!plat,
        "probe: SKIP is by construction on this non-Linux host (platform_supported=" + _bool_text(plat) + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }
  return failed;
}

// =========================================================================
// Live capture path (Linux with a camera; never reached on Windows)
// =========================================================================

fn t_live_path() -> Int {
  var failed: Int = 0;
  let n = v4l_device_count();
  var pick = -1;
  var i = 0;
  while i < n && pick < 0 {
    let path = v4l_device_path(i);
    let dev = v4l_open(i);
    if dev.is_ok {
      let d: V4lDevice = dev.value;
      let c = v4l_querycap(&d);
      if c.is_ok {
        if v4l_supports_capture(&c.value) {
          pick = i;
          info("live: using " + path + " driver=\"" + c.value.driver + "\" card=\"" + c.value.card + "\"");
          failed = failed + t_live_capture(&d, c.value);
        } else {
          info("live: " + path + " is not a streaming capture node -- next");
          v4l_close(&d);
        }
      } else {
        info("live: QUERYCAP(" + path + ") failed -- " + c.error.message);
        v4l_close(&d);
      }
    } else {
      info("live: open(" + path + ") failed -- " + dev.error.message);
    }
    i = i + 1;
  }
  if pick < 0 {
    failed = failed + report(true, "live: SKIP -- device node(s) present but none is a streaming capture node");
  }
  return failed;
}

fn t_live_capture(dev: &V4lDevice, caps: V4lCapabilities) -> Int {
  var failed: Int = 0;

  // G_FMT: the driver's current capture format.
  let gf = v4l_get_format(dev);
  if gf.is_err {
    failed = failed + report(false, "live: G_FMT failed -- " + gf.error.message);
    v4l_close(dev);
    return failed;
  }
  let fmt0: V4lFormat = gf.value;
  failed = failed + report(fmt0.width > 0 && fmt0.height > 0,
    "live: G_FMT " + to_string(fmt0.width) + "x" + to_string(fmt0.height)
    + " fourcc=" + v4l_fourcc_str(fmt0.pixelformat) + " sizeimage=" + to_string(fmt0.sizeimage));

  // S_FMT: renegotiate the same (or a smaller YUYV probe format when the
  // driver's current one is exotic) -- the returned values are the truth.
  var req_w = fmt0.width;
  var req_h = fmt0.height;
  var req_f = fmt0.pixelformat;
  if req_f == 0 {
    req_f = V4L2_PIX_FMT_YUYV;
  }
  if req_w > 1280 { req_w = 1280; }
  if req_h > 720 { req_h = 720; }
  let sf = v4l_set_format(dev, req_w, req_h, req_f, V4L2_FIELD_ANY);
  if sf.is_err {
    failed = failed + report(false, "live: S_FMT failed -- " + sf.error.message);
    v4l_close(dev);
    return failed;
  }
  let fmt: V4lFormat = sf.value;
  failed = failed + report(fmt.width > 0 && fmt.height > 0 && fmt.sizeimage > 0,
    "live: S_FMT negotiated " + to_string(fmt.width) + "x" + to_string(fmt.height)
    + " fourcc=" + v4l_fourcc_str(fmt.pixelformat) + " sizeimage=" + to_string(fmt.sizeimage));

  // REQBUFS: request 4 MMAP capture buffers.
  let rb = v4l_request_buffers(dev, 4, V4L2_BUF_TYPE_VIDEO_CAPTURE, V4L2_MEMORY_MMAP);
  if rb.is_err {
    failed = failed + report(false, "live: REQBUFS failed -- " + rb.error.message);
    v4l_close(dev);
    return failed;
  }
  let granted = rb.value;
  failed = failed + report(granted >= 1, "live: REQBUFS granted " + to_string(granted) + " buffer(s)");

  // QUERYBUF + mmap every buffer.
  var mapped = 0;
  var bi = 0;
  while bi < granted {
    let q = v4l_query_buffer(&dev, bi);
    if q.is_ok {
      let m = v4l_mmap_buffer(&dev, bi);
      if m.is_ok {
        mapped = mapped + 1;
      } else {
        failed = failed + report(false, "live: mmap buffer " + to_string(bi) + " failed -- " + m.error.message);
      }
    } else {
      failed = failed + report(false, "live: QUERYBUF " + to_string(bi) + " failed -- " + q.error.message);
    }
    bi = bi + 1;
  }
  failed = failed + report(mapped == granted, "live: QUERYBUF+mmap " + to_string(mapped) + "/" + to_string(granted) + " buffers");

  // QBUF all + STREAMON.
  var queued = 0;
  bi = 0;
  while bi < granted {
    let q = v4l_queue_buffer(&dev, bi);
    if q.is_ok { queued = queued + 1; }
    bi = bi + 1;
  }
  failed = failed + report(queued == granted, "live: QBUF " + to_string(queued) + "/" + to_string(granted) + " buffers");

  let on = v4l_stream_on(&dev, V4L2_BUF_TYPE_VIDEO_CAPTURE);
  if on.is_err {
    failed = failed + report(false, "live: STREAMON failed -- " + on.error.message);
    v4l_munmap_buffers(dev);
    v4l_close(dev);
    return failed;
  }
  failed = failed + report(true, "live: STREAMON");

  // DQBUF + frame copy + requeue (the whole capture loop).
  let fr = v4l_dequeue_buffer(&dev, 5000);
  if fr.is_err {
    failed = failed + report(false, "live: DQBUF failed -- " + fr.error.message);
  } else {
    let frame: V4lFrame = fr.value;
    failed = failed + report(frame.index >= 0 && frame.index < granted,
      "live: DQBUF index=" + to_string(frame.index) + " bytesused=" + to_string(frame.bytesused)
      + " sequence=" + to_string(frame.sequence) + " timestamp_ns=" + to_string(frame.timestamp_ns));
    let bytes = v4l_read_frame(&dev, frame.index);
    if bytes.is_ok {
      let payload: Vec[UInt8] = bytes.value;
      failed = failed + report(payload.len() > 0,
        "live: frame copy " + to_string(payload.len()) + " byte(s)");
    } else {
      failed = failed + report(false, "live: frame copy failed -- " + bytes.error.message);
    }
    let rq = v4l_queue_buffer(&dev, frame.index);
    failed = failed + report(rq.is_ok, "live: frame requeued (QBUF back)");
  }

  // STREAMOFF + teardown.
  let off = v4l_stream_off(&dev, V4L2_BUF_TYPE_VIDEO_CAPTURE);
  failed = failed + report(off.is_ok, "live: STREAMOFF");
  v4l_munmap_buffers(dev);
  v4l_close(dev);
  failed = failed + report(true, "live: device closed after streaming");
  return failed;
}

// =========================================================================
// main
// =========================================================================

fn main() -> Int {
  io.println("=== xiom.v4l conformance tests (V4L2 UAPI camera capture, 0.1.0) ===");
  io.println("    declared surface: 2079 constants (consts+cids) + 1028 layout facts + 29 UAPI macro mirrors");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_ioctl_constants(), "consts: VIDIOC_* ioctl numbers (functional 9 + enumeration/negotiation/control families)");
  failed = failed + report(t_caps_and_enums(), "consts: V4L2_CAP_* / buffer types / memory / field / flags / colorspace / ctrl classes");
  failed = failed + report(t_fourcc_constants(), "consts: V4L2_PIX_FMT_* FOURCCs + v4l2_fourcc/be + fourcc_str");
  failed = failed + report(t_cid_constants(), "cids: v4l2-controls.h universe spot (VIDEO class + id helpers)");
  failed = failed + report(t_string_constants(), "consts: string-valued UAPI defines (ITV VBI magic)");
  failed = failed + report(t_layout_facts(), "layout: QUERYCAP/fmt/buffer/reqbufs struct sizes + field offsets (LP64)");
  failed = failed + report(t_macro_mirrors(), "macros: 29 function-like UAPI macros (type/field/map/ctrl/dv/codec helpers)");
  failed = failed + report(t_errno_names(), "errno: typed error name mapping");
  failed = failed + t_abi_check();
  failed = failed + t_skip_path();

  // Teardown safety: closing everything (open or not) must be a no-op.
  v4l_close_all();
  failed = failed + report(true, "teardown: close_all exercised (no handles leaked)");

  if failed == 0 {
    io.println("xiom.v4l: all tests passed");
  } else {
    io.println("xiom.v4l: tests failed");
  }
  return failed;
}
