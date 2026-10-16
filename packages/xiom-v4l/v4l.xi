// XIOM -- xiom.v4l: Video4Linux2 (V4L2) camera capture bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: V4L2 is a Linux-only ioctl(2) UAPI (include/uapi/linux/videodev2.h)
// with no runtime library.  This module is the functional head over the
// self-contained bridge `src/v4l2_bridge.c` (compiled with --c-source; see
// port.args.json), which owns the live syscall path:
//
//   probe     scan /dev/videoN, QUERYCAP-verify every node
//             (xv_probe / xv_probe_named -- deterministic SKIP on a bogus
//             directory; Windows has no device layer at all -> blank SKIP)
//   capture   open -> QUERYCAP -> G_FMT / S_FMT -> REQBUFS -> QUERYBUF ->
//             mmap -> QBUF -> STREAMON -> DQBUF(poll) -> frame copy ->
//             QBUF -> STREAMOFF -> close (single-planar VIDEO_CAPTURE;
//             V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE is a declared constant and
//             rides the roadmap)
//
// Classification (the suite maps it to markers):
//   V4L_LOAD_ABSENT -> SKIP  (no V4L2 device layer; CI stays green)
//   V4L_LOAD_ABI    -> FAIL  (pinned ABI facts failed; never a silent SKIP)
//   V4L_CALL        -> Err   (live ioctl failure, errno captured/named)
//
// Declared UAPI surface (values/layouts evaluated from the pinned kernel
// text by docs/repro/gen-v4l2-consts.ps1; dump + assert gate under
// docs/repro/gen/):
//   xiom.v4l.consts   video2dev.h + v4l2-common.h constants (841: all
//                     VIDIOC_* ioctl numbers incl. the 9 functional ones,
//                     V4L2_CAP_*, V4L2_PIX_FMT_* FOURCCs, enums, ...)
//   xiom.v4l.cids     v4l2-controls.h CID universe (1238)
//   xiom.v4l.layout   every v4l2_* struct size + field offset (1028 facts
//                     over 122 structs, LP64)
//   this module       the 29 function-like UAPI macros (v4l2_fourcc,
//                     V4L2_TYPE_IS_*, V4L2_FIELD_*, V4L2_MAP_*, ...) as
//                     pure XIOM functions
//
// Pointers never cross the boundary (B-25 discipline): devices are opaque
// Int handles, mapped addresses are opaque Ints, frame bytes move through
// caller-owned Vec[UInt8] buffers via v4l_read_frame.

module xiom.v4l

use xiom.string;
use xiom.v4l.consts;
use xiom.v4l.cids;

extern "C" {
  fn xv_platform() -> Int32;
  fn xv_probe_named(dev_dir: *UInt8) -> Int32;
  fn xv_probe() -> Int32;
  fn xv_error() -> *UInt8;
  fn xv_last_errno() -> Int32;
  fn xv_abi_fail_count() -> Int32;
  fn xv_abi_fail_names() -> *UInt8;
  fn xv_device_count() -> Int32;
  fn xv_device_path(idx: Int32) -> *UInt8;
  fn xv_open(idx: Int32) -> Int32;
  fn xv_open_path(path: *UInt8) -> Int32;
  fn xv_close(h: Int32);
  fn xv_querycap(h: Int32) -> Int32;
  fn xv_cap_driver(h: Int32) -> *UInt8;
  fn xv_cap_card(h: Int32) -> *UInt8;
  fn xv_cap_bus_info(h: Int32) -> *UInt8;
  fn xv_cap_version(h: Int32) -> Int64;
  fn xv_cap_capabilities(h: Int32) -> Int64;
  fn xv_cap_device_caps(h: Int32) -> Int64;
  fn xv_g_fmt(h: Int32) -> Int32;
  fn xv_s_fmt(h: Int32, width: Int64, height: Int64, fourcc: Int64, field: Int64) -> Int32;
  fn xv_fmt_width(h: Int32) -> Int64;
  fn xv_fmt_height(h: Int32) -> Int64;
  fn xv_fmt_pixelformat(h: Int32) -> Int64;
  fn xv_fmt_field(h: Int32) -> Int64;
  fn xv_fmt_bytesperline(h: Int32) -> Int64;
  fn xv_fmt_sizeimage(h: Int32) -> Int64;
  fn xv_fmt_colorspace(h: Int32) -> Int64;
  fn xv_fmt_flags(h: Int32) -> Int64;
  fn xv_reqbufs(h: Int32, count: Int64, ty: Int64, memory: Int64) -> Int32;
  fn xv_reqbufs_count(h: Int32) -> Int64;
  fn xv_querybuf(h: Int32, idx: Int64) -> Int32;
  fn xv_buf_length(h: Int32, idx: Int64) -> Int64;
  fn xv_buf_offset(h: Int32, idx: Int64) -> Int64;
  fn xv_mmap(h: Int32, idx: Int64) -> Int32;
  fn xv_buf_ptr(h: Int32, idx: Int64) -> Int64;
  fn xv_munmap_all(h: Int32);
  fn xv_qbuf(h: Int32, idx: Int64) -> Int32;
  fn xv_dqbuf(h: Int32, timeout_ms: Int64) -> Int32;
  fn xv_dq_flags(h: Int32) -> Int64;
  fn xv_dq_bytesused(h: Int32) -> Int64;
  fn xv_dq_sequence(h: Int32) -> Int64;
  fn xv_dq_timestamp_ns(h: Int32) -> Int64;
  fn xv_frame_copy(h: Int32, idx: Int64, dst: *UInt8, cap: Int64) -> Int32;
  fn xv_streamon(h: Int32, ty: Int64) -> Int32;
  fn xv_streamoff(h: Int32, ty: Int64) -> Int32;
  fn xv_close_all();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const V4L_LOAD_ABSENT: Int = 0; // no V4L2 device layer -> SKIP
pub const V4L_LOAD_ABI: Int = 1;    // pinned ABI facts broken -> FAIL
pub const V4L_CALL: Int = 2;        // live call failed (errno family)

const XV_TIMEOUT: Int = -3;         // bridge DQBUF timeout sentinel (EAGAIN)

pub type V4lError = {
  kind: Int;       // V4L_LOAD_ABSENT | V4L_LOAD_ABI | V4L_CALL
  errno_code: Int; // captured errno for CALL failures; 0 otherwise
  message: Str;
}

pub type V4lRuntime = {
  device_count: Int;    // V4L2 nodes found by the probe
  abi_fail: Int;        // failed pinned ABI facts (0 = full cover)
  abi_fail_names: Str;  // comma-joined failed fact names
}

pub type V4lDevice = {
  handle: Int; // opaque bridge handle
}

pub type V4lCapabilities = {
  driver: Str;          // 16-byte field
  card: Str;            // 32-byte field
  bus_info: Str;        // 32-byte field
  version: Int;         // KERNEL_VERSION-encoded
  capabilities: Int;    // physical-device capability bits (V4L2_CAP_*)
  device_caps: Int;     // per-node capability bits (0 when V4L2_CAP_DEVICE_CAPS unset)
}

pub type V4lFormat = {
  width: Int;
  height: Int;
  pixelformat: Int;   // FOURCC (v4l2_fourcc / V4L2_PIX_FMT_*)
  field: Int;         // enum v4l2_field
  bytesperline: Int;
  sizeimage: Int;
  colorspace: Int;
  flags: Int;
}

pub type V4lBuffer = {
  index: Int;
  length: Int; // buffer size in bytes (QUERYBUF)
  offset: Int; // mmap offset (QUERYBUF m.offset)
}

pub type V4lFrame = {
  index: Int;        // buffer index to copy/requeue
  bytesused: Int;    // payload bytes (payload for compressed; image size otherwise)
  flags: Int;        // V4L2_BUF_FLAG_* (TIMESTAMP_*, ERROR, ...)
  sequence: Int;     // frame counter
  timestamp_ns: Int; // frame timestamp in ns (timeval -> ns, header inline semantics)
}

// =========================================================================
// Probe / classification
// =========================================================================

fn _v4l_result_err(rc: Int, fallback_kind: Int) -> V4lError {
  let msg = v4l_error();
  let e = unsafe { xv_last_errno() as Int };
  if rc == -2 {
    return V4lError{ kind: V4L_LOAD_ABI, errno_code: e, message: msg };
  }
  return V4lError{ kind: fallback_kind, errno_code: e, message: msg };
}

/// Probe an explicitly named device directory (e.g. "/dev").  A bogus
/// directory exercises the ABSENT/SKIP classification deterministically on
/// every host.
/// Complexity: O(devices * open+QUERYCAP).
pub fn v4l_probe_named(dev_dir: Str) -> Result[V4lRuntime, V4lError]
  requires: dev_dir.len() > 0
{
  let rc = unsafe { xv_probe_named(dev_dir.c_str()) as Int };
  let fails = unsafe { xv_abi_fail_count() as Int };
  if rc == 2 {
    return Err(V4lError{ kind: V4L_LOAD_ABI, errno_code: 0, message: v4l_error() });
  }
  if rc == 1 {
    return Err(V4lError{ kind: V4L_LOAD_ABSENT, errno_code: 0, message: v4l_error() });
  }
  let count = unsafe { xv_device_count() as Int };
  let names = unsafe { Str::from_c_str(xv_abi_fail_names()) };
  return Ok(V4lRuntime{ device_count: count, abi_fail: fails, abi_fail_names: names });
}

/// Probe the default device directory ("/dev").  On a host without a V4L2
/// device layer the probe classifies ABSENT (SKIP); Windows is ABSENT by
/// construction.
/// Complexity: O(devices * open+QUERYCAP).
pub fn v4l_probe() -> Result[V4lRuntime, V4lError]
  requires: true
{
  return v4l_probe_named("/dev");
}

/// The last bridge message (probe classification text / ioctl error).
/// Complexity: O(1).
pub fn v4l_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xv_error()); }
}

/// errno captured by the last failing bridge call (0 when none).
/// Complexity: O(1).
pub fn v4l_last_errno() -> Int
  requires: true
{
  unsafe { return xv_last_errno() as Int; }
}

/// Whether the bridge can reach a device layer on this host (true on
/// Linux, false elsewhere).
/// Complexity: O(1).
pub fn v4l_platform_supported() -> Bool
  requires: true
{
  unsafe { return (xv_platform() as Int) == 0; }
}

/// Pinned-ABI self-check (ioctl encodings, struct sizes, key offsets
/// re-derived at runtime).  Err(V4L_LOAD_ABI) carries the failed fact
/// names -- never a silent pass.
/// Complexity: O(pinned facts).
pub fn v4l_abi_check() -> Result[Int, V4lError]
  requires: true
{
  let fails = unsafe { xv_abi_fail_count() as Int };
  if fails != 0 {
    let names = unsafe { Str::from_c_str(xv_abi_fail_names()) };
    return Err(V4lError{ kind: V4L_LOAD_ABI, errno_code: 0, message: "pinned ABI self-check failed: " + names });
  }
  return Ok(fails);
}

/// Devices found by the last probe.
/// Complexity: O(1).
pub fn v4l_device_count() -> Int
  requires: true
{
  unsafe { return xv_device_count() as Int; }
}

/// The device path of probe result `idx` ("" when out of range).
/// Complexity: O(1).
pub fn v4l_device_path(idx: Int) -> Str
  requires: idx >= 0
{
  unsafe { return Str::from_c_str(xv_device_path(idx as Int32)); }
}

// =========================================================================
// Device lifecycle + QUERYCAP
// =========================================================================

fn _v4l_open_with(h: Int) -> Result[V4lDevice, V4lError] {
  if h <= 0 {
    return Err(_v4l_result_err(-1, V4L_CALL));
  }
  return Ok(V4lDevice{ handle: h });
}

/// Open the probe result at `idx`.
/// Complexity: O(open + QUERYCAP).
pub fn v4l_open(idx: Int) -> Result[V4lDevice, V4lError]
  requires: idx >= 0
{
  let h = unsafe { xv_open(idx as Int32) as Int };
  return _v4l_open_with(h);
}

/// Open an explicit device path ("/dev/video0").
/// Complexity: O(open + QUERYCAP).
pub fn v4l_open_path(path: Str) -> Result[V4lDevice, V4lError]
  requires: path.len() > 0
{
  let h = unsafe { xv_open_path(path.c_str()) as Int };
  return _v4l_open_with(h);
}

/// Close a device (idempotent; unmaps any mapped buffers first).
/// Complexity: O(mapped buffers).
pub fn v4l_close(dev: &V4lDevice)
  requires: true
{
  unsafe { xv_close(dev.handle as Int32); }
}

/// VIDIOC_QUERYCAP on an open device.
/// Complexity: O(1) + kernel query.
pub fn v4l_querycap(dev: &V4lDevice) -> Result[V4lCapabilities, V4lError]
  requires: true
{
  let rc = unsafe { xv_querycap(dev.handle as Int32) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  let driver = unsafe { Str::from_c_str(xv_cap_driver(dev.handle as Int32)) };
  let card = unsafe { Str::from_c_str(xv_cap_card(dev.handle as Int32)) };
  let bus = unsafe { Str::from_c_str(xv_cap_bus_info(dev.handle as Int32)) };
  let version = unsafe { xv_cap_version(dev.handle as Int32) as Int };
  let caps = unsafe { xv_cap_capabilities(dev.handle as Int32) as Int };
  let dcaps = unsafe { xv_cap_device_caps(dev.handle as Int32) as Int };
  return Ok(V4lCapabilities{
    driver: driver, card: card, bus_info: bus,
    version: version, capabilities: caps, device_caps: dcaps,
  });
}

/// The capability bits that apply to this node: `device_caps` when the
/// driver sets V4L2_CAP_DEVICE_CAPS, else the physical `capabilities`
/// (the QUERYCAP rule from the UAPI docs).
/// Complexity: O(1).
pub fn v4l_effective_caps(caps: &V4lCapabilities) -> Int
  requires: true
{
  return v4l_effective_caps_of(caps.capabilities, caps.device_caps);
}

/// As `v4l_effective_caps`, from raw QUERYCAP fields.
/// Complexity: O(1).
pub fn v4l_effective_caps_of(capabilities: Int, device_caps: Int) -> Int
  requires: true
{
  if (capabilities & V4L2_CAP_DEVICE_CAPS) != 0 {
    return device_caps;
  }
  return capabilities;
}

/// Whether the effective caps advertise streaming single/multi-planar
/// capture (what the mmap capture pipeline needs).
/// Complexity: O(1).
pub fn v4l_supports_capture(caps: &V4lCapabilities) -> Bool
  requires: true
{
  let eff = v4l_effective_caps(caps);
  if (eff & V4L2_CAP_STREAMING) == 0 { return false; }
  if (eff & V4L2_CAP_VIDEO_CAPTURE) != 0 { return true; }
  return (eff & V4L2_CAP_VIDEO_CAPTURE_MPLANE) != 0;
}

/// Decode the KERNEL_VERSION-encoded `version` field (major, minor, patch).
/// Complexity: O(1).
pub fn v4l_version_major(version: Int) -> Int
  requires: true
{
  return (version >> 16) & 0xFF;
}

/// See `v4l_version_major`.
/// Complexity: O(1).
pub fn v4l_version_minor(version: Int) -> Int
  requires: true
{
  return (version >> 8) & 0xFF;
}

/// See `v4l_version_major`.
/// Complexity: O(1).
pub fn v4l_version_patch(version: Int) -> Int
  requires: true
{
  return version & 0xFF;
}

// =========================================================================
// Format negotiation
// =========================================================================

fn _v4l_format_snapshot(h: Int) -> V4lFormat {
  return V4lFormat{
    width: unsafe { xv_fmt_width(h) as Int },
    height: unsafe { xv_fmt_height(h) as Int },
    pixelformat: unsafe { xv_fmt_pixelformat(h) as Int },
    field: unsafe { xv_fmt_field(h) as Int },
    bytesperline: unsafe { xv_fmt_bytesperline(h) as Int },
    sizeimage: unsafe { xv_fmt_sizeimage(h) as Int },
    colorspace: unsafe { xv_fmt_colorspace(h) as Int },
    flags: unsafe { xv_fmt_flags(h) as Int },
  };
}

/// VIDIOC_G_FMT for single-planar video capture (type
/// V4L2_BUF_TYPE_VIDEO_CAPTURE).
/// Complexity: O(1) + kernel query.
pub fn v4l_get_format(dev: &V4lDevice) -> Result[V4lFormat, V4lError]
  requires: true
{
  let rc = unsafe { xv_g_fmt(dev.handle as Int32) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  return Ok(_v4l_format_snapshot(dev.handle as Int32));
}

/// VIDIOC_S_FMT: request `width x height` in `fourcc` with `field`
/// (V4L2_FIELD_ANY lets the driver pick).  Ok carries the negotiated
/// result -- drivers may adjust all fields.
/// Complexity: O(1) + kernel negotiation.
pub fn v4l_set_format(dev: &V4lDevice, width: Int, height: Int, fourcc: Int, field: Int) -> Result[V4lFormat, V4lError]
  requires: width > 0
  requires: height > 0
{
  let rc = unsafe { xv_s_fmt(dev.handle as Int32, width as Int64, height as Int64, fourcc as Int64, field as Int64) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  return Ok(_v4l_format_snapshot(dev.handle as Int32));
}

/// The last G_FMT/S_FMT result without hitting the device (all fields -1
/// before the first negotiation).
/// Complexity: O(1).
pub fn v4l_format(dev: &V4lDevice) -> V4lFormat
  requires: true
{
  return _v4l_format_snapshot(dev.handle as Int32);
}

// =========================================================================
// Buffer I/O (mmap streaming)
// =========================================================================

/// VIDIOC_REQBUFS: request `count` MMAP buffers of `type`.  Ok(granted) =
/// the count the driver actually allocated (may differ; 0 means the
/// driver freed all buffers).
/// Complexity: O(requested buffers).
pub fn v4l_request_buffers(dev: &V4lDevice, count: Int, ty: Int, memory: Int) -> Result[Int, V4lError]
  requires: count > 0
{
  let rc = unsafe { xv_reqbufs(dev.handle as Int32, count as Int64, ty as Int64, memory as Int64) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  let granted = unsafe { xv_reqbufs_count(dev.handle as Int32) as Int };
  return Ok(granted);
}

/// VIDIOC_QUERYBUF: length/offset of buffer `idx` (after REQBUFS).
/// Complexity: O(1) + kernel query.
pub fn v4l_query_buffer(dev: &V4lDevice, idx: Int) -> Result[V4lBuffer, V4lError]
  requires: idx >= 0
{
  let rc = unsafe { xv_querybuf(dev.handle as Int32, idx as Int64) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  let len = unsafe { xv_buf_length(dev.handle as Int32, idx as Int64) as Int };
  let off = unsafe { xv_buf_offset(dev.handle as Int32, idx as Int64) as Int };
  return Ok(V4lBuffer{ index: idx, length: len, offset: off });
}

/// mmap buffer `idx` (QUERYBUF first).  The address stays C-side; it is
/// surfaced as an opaque Int for diagnostics only.
/// Complexity: O(mmap).
pub fn v4l_mmap_buffer(dev: &V4lDevice, idx: Int) -> Result[Int, V4lError]
  requires: idx >= 0
{
  let rc = unsafe { xv_mmap(dev.handle as Int32, idx as Int64) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  let p = unsafe { xv_buf_ptr(dev.handle as Int32, idx as Int64) as Int };
  return Ok(p);
}

/// Unmap every mapped buffer of the device (idempotent; also done by
/// `v4l_close`).
/// Complexity: O(mapped buffers).
pub fn v4l_munmap_buffers(dev: &V4lDevice)
  requires: true
{
  unsafe { xv_munmap_all(dev.handle as Int32); }
}

/// VIDIOC_QBUF: hand buffer `idx` back to the driver.
/// Complexity: O(1) + kernel queue.
pub fn v4l_queue_buffer(dev: &V4lDevice, idx: Int) -> Result[Int, V4lError]
  requires: idx >= 0
{
  let rc = unsafe { xv_qbuf(dev.handle as Int32, idx as Int64) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  return Ok(0);
}

/// poll + VIDIOC_DQBUF with `timeout_ms` (negative = block).  Ok = the
/// dequeued frame metadata; Err(V4L_CALL, errno=EAGAIN) on timeout.
/// Complexity: O(poll + kernel dequeue).
pub fn v4l_dequeue_buffer(dev: &V4lDevice, timeout_ms: Int) -> Result[V4lFrame, V4lError]
  requires: true
{
  let idx = unsafe { xv_dqbuf(dev.handle as Int32, timeout_ms as Int64) as Int };
  if idx == XV_TIMEOUT {
    return Err(V4lError{ kind: V4L_CALL, errno_code: v4l_last_errno(), message: v4l_error() });
  }
  if idx < 0 {
    return Err(_v4l_result_err(idx, V4L_CALL));
  }
  let flags = unsafe { xv_dq_flags(dev.handle as Int32) as Int };
  let used = unsafe { xv_dq_bytesused(dev.handle as Int32) as Int };
  let seq = unsafe { xv_dq_sequence(dev.handle as Int32) as Int };
  let ts = unsafe { xv_dq_timestamp_ns(dev.handle as Int32) as Int };
  return Ok(V4lFrame{ index: idx, bytesused: used, flags: flags, sequence: seq, timestamp_ns: ts });
}

/// Copy the dequeued frame bytes of buffer `idx` into a fresh Vec (B-25:
/// bytes move through caller-owned buffers).  Prefer the DQBUF-reported
/// bytesused; falls back to the QUERYBUF length.
/// Complexity: O(frame bytes).
pub fn v4l_read_frame(dev: &V4lDevice, idx: Int) -> Result[Vec[UInt8], V4lError]
  requires: idx >= 0
{
  let len = unsafe { xv_buf_length(dev.handle as Int32, idx as Int64) as Int };
  if len <= 0 {
    return Err(V4lError{ kind: V4L_CALL, errno_code: 22, message: "read_frame: buffer length unknown (QUERYBUF first)" });
  }
  let used = unsafe { xv_dq_bytesused(dev.handle as Int32) as Int };
  var cap = len;
  if used > 0 && used < len { cap = used; }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < cap {
    out.push(0 as UInt8);
    i = i + 1;
  }
  let n = unsafe { xv_frame_copy(dev.handle as Int32, idx as Int64, out.as_mut_ptr(), cap as Int64) as Int };
  if n < 0 {
    return Err(_v4l_result_err(n, V4L_CALL));
  }
  if n < cap {
    var trimmed: Vec[UInt8] = Vec[UInt8].new();
    var j = 0;
    while j < n {
      trimmed.push(out[j]);
      j = j + 1;
    }
    return Ok(trimmed);
  }
  return Ok(out);
}

/// VIDIOC_STREAMON for `ty` (V4L2_BUF_TYPE_VIDEO_CAPTURE).
/// Complexity: O(1) + kernel start.
pub fn v4l_stream_on(dev: &V4lDevice, ty: Int) -> Result[Int, V4lError]
  requires: true
{
  let rc = unsafe { xv_streamon(dev.handle as Int32, ty as Int64) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  return Ok(0);
}

/// VIDIOC_STREAMOFF for `ty` (also returns every queued buffer).
/// Complexity: O(1) + kernel stop.
pub fn v4l_stream_off(dev: &V4lDevice, ty: Int) -> Result[Int, V4lError]
  requires: true
{
  let rc = unsafe { xv_streamoff(dev.handle as Int32, ty as Int64) as Int };
  if rc != 0 {
    return Err(_v4l_result_err(rc, V4L_CALL));
  }
  return Ok(0);
}

/// Dequeue one frame, copy its bytes, and requeue the buffer in one call --
/// the whole capture loop for the common case.
/// Complexity: O(frame bytes).
pub fn v4l_grab_frame(dev: &V4lDevice, timeout_ms: Int) -> Result[Vec[UInt8], V4lError]
  requires: true
{
  let f = v4l_dequeue_buffer(dev, timeout_ms);
  if f.is_err {
    return Err(f.error);
  }
  let frame: V4lFrame = f.value;
  let bytes = v4l_read_frame(dev, frame.index);
  let rq = v4l_queue_buffer(dev, frame.index);
  if bytes.is_err {
    return Err(bytes.error);
  }
  if rq.is_err {
    return Err(rq.error);
  }
  return Ok(bytes.value);
}

// =========================================================================
// errno naming (typed error messages)
// =========================================================================

/// Human name of a Linux errno value ("EINVAL", ...; "" when unknown).
/// The mapping is the asm-generic errno table (same values on x86_64 and
/// arm64 for the entries below).
/// Complexity: O(1).
pub fn v4l_errno_name(code: Int) -> Str
  requires: true
{
  if code == 1 { return "EPERM"; }
  if code == 2 { return "ENOENT"; }
  if code == 4 { return "EINTR"; }
  if code == 5 { return "EIO"; }
  if code == 6 { return "ENXIO"; }
  if code == 9 { return "EBADF"; }
  if code == 11 { return "EAGAIN"; }
  if code == 12 { return "ENOMEM"; }
  if code == 13 { return "EACCES"; }
  if code == 16 { return "EBUSY"; }
  if code == 19 { return "ENODEV"; }
  if code == 22 { return "EINVAL"; }
  if code == 23 { return "ENFILE"; }
  if code == 25 { return "ENOTTY"; }
  if code == 28 { return "ENOSPC"; }
  if code == 29 { return "ESPIPE"; }
  if code == 32 { return "EPIPE"; }
  if code == 38 { return "ENOSYS"; }
  if code == 75 { return "EOVERFLOW"; }
  if code == 88 { return "ENOTSOCK"; }
  if code == 95 { return "EOPNOTSUPP"; }
  if code == 110 { return "ETIMEDOUT"; }
  return "";
}

// =========================================================================
// UAPI function-like macros, mirrored as functions
// (bodies transcribed from the pinned headers; verified by the repro gate)
// =========================================================================

/// v4l2_fourcc(a, b, c, d): pack four ASCII chars into a FOURCC
/// ((a) | (b)<<8 | (c)<<16 | (d)<<24).
/// Complexity: O(1).
pub fn v4l2_fourcc(a: Int, b: Int, c: Int, d: Int) -> Int
  requires: a >= 0
  requires: a <= 255
  requires: b >= 0
  requires: b <= 255
  requires: c >= 0
  requires: c <= 255
  requires: d >= 0
  requires: d <= 255
{
  return (a | (b << 8) | (c << 16) | (d << 24)) & 0xFFFFFFFF;
}

/// v4l2_fourcc_be(a, b, c, d): v4l2_fourcc with the big-endian bit set.
/// Complexity: O(1).
pub fn v4l2_fourcc_be(a: Int, b: Int, c: Int, d: Int) -> Int
  requires: true
{
  return (v4l2_fourcc(a, b, c, d) | (1 << 31)) & 0xFFFFFFFF;
}

/// Four printable chars of a FOURCC (non-printable bytes rendered as ".").
/// Complexity: O(1).
pub fn v4l_fourcc_str(fourcc: Int) -> Str
  requires: true
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var shift = 0;
  while shift < 32 {
    let c = (fourcc >> shift) & 0xFF;
    if c >= 32 && c <= 126 {
      v.push(c as UInt8);
    } else {
      v.push(46 as UInt8);
    }
    shift = shift + 8;
  }
  return Str::from_utf8(v);
}

/// V4L2_TYPE_IS_VALID(type): type within the enum v4l2_buf_type range.
/// Complexity: O(1).
pub fn v4l2_type_is_valid(ty: Int) -> Bool
  requires: true
{
  return ty >= V4L2_BUF_TYPE_VIDEO_CAPTURE && ty <= V4L2_BUF_TYPE_META_OUTPUT;
}

/// V4L2_TYPE_IS_MULTIPLANAR(type).
/// Complexity: O(1).
pub fn v4l2_type_is_multiplanar(ty: Int) -> Bool
  requires: true
{
  return ty == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE || ty == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
}

/// V4L2_TYPE_IS_OUTPUT(type).
/// Complexity: O(1).
pub fn v4l2_type_is_output(ty: Int) -> Bool
  requires: true
{
  if ty == V4L2_BUF_TYPE_VIDEO_OUTPUT { return true; }
  if ty == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE { return true; }
  if ty == V4L2_BUF_TYPE_VIDEO_OUTPUT_OVERLAY { return true; }
  if ty == V4L2_BUF_TYPE_VBI_OUTPUT { return true; }
  if ty == V4L2_BUF_TYPE_SLICED_VBI_OUTPUT { return true; }
  if ty == V4L2_BUF_TYPE_SDR_OUTPUT { return true; }
  if ty == V4L2_BUF_TYPE_META_OUTPUT { return true; }
  return false;
}

/// V4L2_TYPE_IS_CAPTURE(type).
/// Complexity: O(1).
pub fn v4l2_type_is_capture(ty: Int) -> Bool
  requires: true
{
  return v4l2_type_is_valid(ty) && !v4l2_type_is_output(ty);
}

/// V4L2_FIELD_HAS_TOP(field).
/// Complexity: O(1).
pub fn v4l2_field_has_top(field: Int) -> Bool
  requires: true
{
  if field == V4L2_FIELD_TOP { return true; }
  if field == V4L2_FIELD_INTERLACED { return true; }
  if field == V4L2_FIELD_INTERLACED_TB { return true; }
  if field == V4L2_FIELD_INTERLACED_BT { return true; }
  if field == V4L2_FIELD_SEQ_TB { return true; }
  if field == V4L2_FIELD_SEQ_BT { return true; }
  return false;
}

/// V4L2_FIELD_HAS_BOTTOM(field).
/// Complexity: O(1).
pub fn v4l2_field_has_bottom(field: Int) -> Bool
  requires: true
{
  if field == V4L2_FIELD_BOTTOM { return true; }
  if field == V4L2_FIELD_INTERLACED { return true; }
  if field == V4L2_FIELD_INTERLACED_TB { return true; }
  if field == V4L2_FIELD_INTERLACED_BT { return true; }
  if field == V4L2_FIELD_SEQ_TB { return true; }
  if field == V4L2_FIELD_SEQ_BT { return true; }
  return false;
}

/// V4L2_FIELD_HAS_BOTH(field).
/// Complexity: O(1).
pub fn v4l2_field_has_both(field: Int) -> Bool
  requires: true
{
  if field == V4L2_FIELD_INTERLACED { return true; }
  if field == V4L2_FIELD_INTERLACED_TB { return true; }
  if field == V4L2_FIELD_INTERLACED_BT { return true; }
  if field == V4L2_FIELD_SEQ_TB { return true; }
  if field == V4L2_FIELD_SEQ_BT { return true; }
  return false;
}

/// V4L2_FIELD_HAS_T_OR_B(field).
/// Complexity: O(1).
pub fn v4l2_field_has_t_or_b(field: Int) -> Bool
  requires: true
{
  if field == V4L2_FIELD_BOTTOM { return true; }
  if field == V4L2_FIELD_TOP { return true; }
  if field == V4L2_FIELD_ALTERNATE { return true; }
  return false;
}

/// V4L2_FIELD_IS_INTERLACED(field).
/// Complexity: O(1).
pub fn v4l2_field_is_interlaced(field: Int) -> Bool
  requires: true
{
  if field == V4L2_FIELD_INTERLACED { return true; }
  if field == V4L2_FIELD_INTERLACED_TB { return true; }
  if field == V4L2_FIELD_INTERLACED_BT { return true; }
  return false;
}

/// V4L2_FIELD_IS_SEQUENTIAL(field).
/// Complexity: O(1).
pub fn v4l2_field_is_sequential(field: Int) -> Bool
  requires: true
{
  return field == V4L2_FIELD_SEQ_TB || field == V4L2_FIELD_SEQ_BT;
}

/// V4L2_MAP_COLORSPACE_DEFAULT(is_sdtv, is_hdtv).
/// Complexity: O(1).
pub fn v4l2_map_colorspace_default(is_sdtv: Bool, is_hdtv: Bool) -> Int
  requires: true
{
  if is_sdtv { return V4L2_COLORSPACE_SMPTE170M; }
  if is_hdtv { return V4L2_COLORSPACE_REC709; }
  return V4L2_COLORSPACE_SRGB;
}

/// V4L2_MAP_XFER_FUNC_DEFAULT(colsp).
/// Complexity: O(1).
pub fn v4l2_map_xfer_func_default(colsp: Int) -> Int
  requires: true
{
  if colsp == V4L2_COLORSPACE_OPRGB { return V4L2_XFER_FUNC_OPRGB; }
  if colsp == V4L2_COLORSPACE_SMPTE240M { return V4L2_XFER_FUNC_SMPTE240M; }
  if colsp == V4L2_COLORSPACE_DCI_P3 { return V4L2_XFER_FUNC_DCI_P3; }
  if colsp == V4L2_COLORSPACE_RAW { return V4L2_XFER_FUNC_NONE; }
  if colsp == V4L2_COLORSPACE_SRGB || colsp == V4L2_COLORSPACE_JPEG { return V4L2_XFER_FUNC_SRGB; }
  return V4L2_XFER_FUNC_709;
}

/// V4L2_MAP_YCBCR_ENC_DEFAULT(colsp).
/// Complexity: O(1).
pub fn v4l2_map_ycbcr_enc_default(colsp: Int) -> Int
  requires: true
{
  if colsp == V4L2_COLORSPACE_REC709 || colsp == V4L2_COLORSPACE_DCI_P3 { return V4L2_YCBCR_ENC_709; }
  if colsp == V4L2_COLORSPACE_BT2020 { return V4L2_YCBCR_ENC_BT2020; }
  if colsp == V4L2_COLORSPACE_SMPTE240M { return V4L2_YCBCR_ENC_SMPTE240M; }
  return V4L2_YCBCR_ENC_601;
}

/// V4L2_MAP_QUANTIZATION_DEFAULT(is_rgb_or_hsv, colsp, ycbcr_enc).
/// The ycbcr_enc argument is unused by the pinned definition (kept for
/// signature parity with the header macro).
/// Complexity: O(1).
pub fn v4l2_map_quantization_default(is_rgb_or_hsv: Bool, colsp: Int, ycbcr_enc: Int) -> Int
  requires: true
{
  if is_rgb_or_hsv || colsp == V4L2_COLORSPACE_JPEG { return V4L2_QUANTIZATION_FULL_RANGE; }
  return V4L2_QUANTIZATION_LIM_RANGE;
}

/// V4L2_CTRL_ID2CLASS(id).
/// Complexity: O(1).
pub fn v4l2_ctrl_id2class(id: Int) -> Int
  requires: true
{
  return id & 0x0FFF0000;
}

/// V4L2_CTRL_ID2WHICH(id).
/// Complexity: O(1).
pub fn v4l2_ctrl_id2which(id: Int) -> Int
  requires: true
{
  return id & 0x0FFF0000;
}

/// V4L2_CTRL_DRIVER_PRIV(id): the low 16 bits are a private control ID.
/// Complexity: O(1).
pub fn v4l2_ctrl_driver_priv(id: Int) -> Bool
  requires: true
{
  return (id & 0xFFFF) >= 0x1000;
}

/// V4L2_DV_BT_BLANKING_WIDTH(hfrontporch, hsync, hbackporch).
/// Complexity: O(1).
pub fn v4l2_dv_bt_blanking_width(hfrontporch: Int, hsync: Int, hbackporch: Int) -> Int
  requires: true
{
  return hfrontporch + hsync + hbackporch;
}

/// V4L2_DV_BT_FRAME_WIDTH(width, hfrontporch, hsync, hbackporch).
/// Complexity: O(1).
pub fn v4l2_dv_bt_frame_width(width: Int, hfrontporch: Int, hsync: Int, hbackporch: Int) -> Int
  requires: true
{
  return width + v4l2_dv_bt_blanking_width(hfrontporch, hsync, hbackporch);
}

/// V4L2_DV_BT_BLANKING_HEIGHT(vfrontporch, vsync, vbackporch, interlaced,
/// il_vfrontporch, il_vsync, il_vbackporch).
/// Complexity: O(1).
pub fn v4l2_dv_bt_blanking_height(vfrontporch: Int, vsync: Int, vbackporch: Int,
                                 interlaced: Bool, il_vfrontporch: Int, il_vsync: Int,
                                 il_vbackporch: Int) -> Int
  requires: true
{
  var h = vfrontporch + vsync + vbackporch;
  if interlaced {
    h = h + il_vfrontporch + il_vsync + il_vbackporch;
  }
  return h;
}

/// V4L2_DV_BT_FRAME_HEIGHT(height, vfrontporch, vsync, vbackporch,
/// interlaced, il_vfrontporch, il_vsync, il_vbackporch).
/// Complexity: O(1).
pub fn v4l2_dv_bt_frame_height(height: Int, vfrontporch: Int, vsync: Int, vbackporch: Int,
                               interlaced: Bool, il_vfrontporch: Int, il_vsync: Int,
                               il_vbackporch: Int) -> Int
  requires: true
{
  return height + v4l2_dv_bt_blanking_height(vfrontporch, vsync, vbackporch,
                                             interlaced, il_vfrontporch, il_vsync, il_vbackporch);
}

/// V4L2_H264_SPS_HAS_CHROMA_FORMAT(sps->profile_idc).
/// Complexity: O(1).
pub fn v4l2_h264_sps_has_chroma_format(profile_idc: Int) -> Bool
  requires: true
{
  if profile_idc == 100 || profile_idc == 110 || profile_idc == 122 || profile_idc == 244 { return true; }
  if profile_idc == 44 || profile_idc == 83 || profile_idc == 86 || profile_idc == 118 { return true; }
  if profile_idc == 128 || profile_idc == 138 || profile_idc == 139 || profile_idc == 134 { return true; }
  if profile_idc == 135 { return true; }
  return false;
}

/// V4L2_H264_CTRL_PRED_WEIGHTS_REQUIRED(pps->flags, pps->weighted_bipred_idc,
/// slice->slice_type).
/// Complexity: O(1).
pub fn v4l2_h264_ctrl_pred_weights_required(pps_flags: Int, weighted_bipred_idc: Int,
                                            slice_type: Int) -> Bool
  requires: true
{
  let has_wp = (pps_flags & V4L2_H264_PPS_FLAG_WEIGHTED_PRED) != 0;
  if has_wp && (slice_type == V4L2_H264_SLICE_TYPE_P || slice_type == V4L2_H264_SLICE_TYPE_SP) {
    return true;
  }
  if weighted_bipred_idc == 1 && slice_type == V4L2_H264_SLICE_TYPE_B { return true; }
  return false;
}

/// V4L2_VP8_FRAME_IS_KEY_FRAME(hdr->flags).
/// Complexity: O(1).
pub fn v4l2_vp8_frame_is_key_frame(hdr_flags: Int) -> Bool
  requires: true
{
  return (hdr_flags & V4L2_VP8_FRAME_FLAG_KEY_FRAME) != 0;
}

/// V4L2_VP9_SEGMENT_FEATURE_ENABLED(id) -> (1 << id).
/// Complexity: O(1).
pub fn v4l2_vp9_segment_feature_enabled(id: Int) -> Int
  requires: id >= 0
  requires: id < 32
{
  return 1 << id;
}

/// V4L2_AV1_GLOBAL_MOTION_IS_INVALID(ref) -> (1 << ref).
/// Complexity: O(1).
pub fn v4l2_av1_global_motion_is_invalid(motion_ref: Int) -> Int
  requires: motion_ref >= 0
  requires: motion_ref < 32
{
  return 1 << motion_ref;
}

/// V4L2_AV1_SEGMENT_FEATURE_ENABLED(id) -> (1 << id).
/// Complexity: O(1).
pub fn v4l2_av1_segment_feature_enabled(id: Int) -> Int
  requires: id >= 0
  requires: id < 32
{
  return 1 << id;
}

/// Release every open device handle (test/teardown convenience).
/// Complexity: O(handles).
pub fn v4l_close_all()
  requires: true
{
  unsafe { xv_close_all(); }
}
