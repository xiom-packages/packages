// xiom.opus -- safe FFI wrappers over the generated bridge ABI.
//
// G5 confinement: this is the ONE module in the package that contains
// `unsafe` blocks.  Every foreign call is wrapped here; all other modules
// are pure XIOM and call these typed wrappers.
//
// Library: vendored libopus v1.6.1 (BSD-3), compiled into the test binary
// from vendor/opus via the unity units in src/opus_vendor_*.c
// (see SPEC.md for the pin and the re-pin procedure).
//
// Discipline (compiler v0.64.4 findings B-11..B-26):
//   * handles are Int values produced by the C bridge (never x as *UInt8);
//   * out-params read from dedicated owned Vec[UInt8] slots, byte-indexed,
//     little-endian (no ffi.ptr_read_*, no pointer arithmetic);
//   * input buffers pass .as_ptr(), output buffers .as_mut_ptr();
//   * no bare `null` reaches C -- NULL-requiring calls (PLC) are expressed
//     as an EMPTY packet Vec, where upstream treats len==0 as the lost-packet
//     concealment path (verified in opus_decoder.c: `if (len==0 || data==NULL)`);
//   * init-over-own-memory functions take the owned Vec as `mem` and return
//     the same address as the handle; keep the Vec alive and do not
//     push/realloc it while the handle is in use;
//   * flat outcome structs only -- never Result[Option[T]] (B-26).
//
// Error mapping: any negative libopus return becomes
// Err(OpusError{code, message}) with message from opus_strerror.

module xiom.opus.ffi

use xiom.opus.types;

// >>> GENERATED-EXTERNS-BEGIN (tools/gen_opus.py)
extern "C" {
  fn xo_encoder_get_size(p0: Int) -> Int;
  fn xo_encoder_create(p0: Int, p1: Int, p2: Int, p3: *UInt8) -> Int;
  fn xo_encoder_init(mem: *UInt8, mem_capacity: Int, Fs: Int, channels: Int, application: Int, err_out: *UInt8) -> Int;
  fn xo_encode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_encode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_encode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_encoder_destroy(p0: Int) -> Int;
  fn xo_encoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_encoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_decoder_get_size(p0: Int) -> Int;
  fn xo_decoder_create(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_decoder_init(mem: *UInt8, mem_capacity: Int, Fs: Int, channels: Int, err_out: *UInt8) -> Int;
  fn xo_decode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_decode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_decode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_decoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_decoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_decoder_destroy(p0: Int) -> Int;
  fn xo_dred_decoder_get_size() -> Int;
  fn xo_dred_decoder_create(p0: *UInt8) -> Int;
  fn xo_dred_decoder_init(mem: *UInt8, mem_capacity: Int, err_out: *UInt8) -> Int;
  fn xo_dred_decoder_destroy(p0: Int) -> Int;
  fn xo_dred_decoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_dred_decoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_dred_get_size() -> Int;
  fn xo_dred_alloc(p0: *UInt8) -> Int;
  fn xo_dred_free(p0: Int) -> Int;
  fn xo_dred_parse(p0: Int, p1: Int, p2: *UInt8, p3: Int, p4: Int, p5: Int, p6: *UInt8, p7: Int) -> Int;
  fn xo_dred_process(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_decoder_dred_decode(p0: Int, p1: Int, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_decoder_dred_decode24(p0: Int, p1: Int, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_decoder_dred_decode_float(p0: Int, p1: Int, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_packet_parse(data: *UInt8, len: Int, toc_out: *UInt8, sizes_out: *UInt8, offsets_out: *UInt8, out_capacity: Int, payload_offset_out: *UInt8) -> Int;
  fn xo_packet_get_bandwidth(p0: *UInt8) -> Int;
  fn xo_packet_get_samples_per_frame(p0: *UInt8, p1: Int) -> Int;
  fn xo_packet_get_nb_channels(p0: *UInt8) -> Int;
  fn xo_packet_get_nb_frames(p0: *UInt8, p1: Int) -> Int;
  fn xo_packet_get_nb_samples(p0: *UInt8, p1: Int, p2: Int) -> Int;
  fn xo_packet_has_lbrr(p0: *UInt8, p1: Int) -> Int;
  fn xo_decoder_get_nb_samples(p0: Int, p1: *UInt8, p2: Int) -> Int;
  fn xo_pcm_soft_clip(p0: *UInt8, p1: Int, p2: Int, p3: *UInt8) -> Int;
  fn xo_repacketizer_get_size() -> Int;
  fn xo_repacketizer_init(mem: *UInt8, mem_capacity: Int, err_out: *UInt8) -> Int;
  fn xo_repacketizer_create() -> Int;
  fn xo_repacketizer_destroy(p0: Int) -> Int;
  fn xo_repacketizer_cat(p0: Int, p1: *UInt8, p2: Int) -> Int;
  fn xo_repacketizer_out_range(p0: Int, p1: Int, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_repacketizer_get_nb_frames(p0: Int) -> Int;
  fn xo_repacketizer_out(p0: Int, p1: *UInt8, p2: Int) -> Int;
  fn xo_packet_pad(p0: *UInt8, p1: Int, p2: Int) -> Int;
  fn xo_packet_unpad(p0: *UInt8, p1: Int) -> Int;
  fn xo_multistream_packet_pad(p0: *UInt8, p1: Int, p2: Int, p3: Int) -> Int;
  fn xo_multistream_packet_unpad(p0: *UInt8, p1: Int, p2: Int) -> Int;
  fn xo_strerror(code: Int, out: *UInt8, capacity: Int) -> Int;
  fn xo_get_version_string(out: *UInt8, capacity: Int) -> Int;
  fn xo_multistream_encoder_get_size(p0: Int, p1: Int) -> Int;
  fn xo_multistream_surround_encoder_get_size(p0: Int, p1: Int) -> Int;
  fn xo_multistream_encoder_create(p0: Int, p1: Int, p2: Int, p3: Int, p4: *UInt8, p5: Int, p6: *UInt8) -> Int;
  fn xo_multistream_surround_encoder_create(Fs: Int, channels: Int, mapping_family: Int, streams_out: *UInt8, coupled_streams_out: *UInt8, mapping_out: *UInt8, mapping_capacity: Int, application: Int, err_out: *UInt8) -> Int;
  fn xo_multistream_encoder_init(mem: *UInt8, mem_capacity: Int, Fs: Int, channels: Int, streams: Int, coupled_streams: Int, mapping: *UInt8, application: Int, err_out: *UInt8) -> Int;
  fn xo_multistream_surround_encoder_init(mem: *UInt8, mem_capacity: Int, Fs: Int, channels: Int, mapping_family: Int, streams_out: *UInt8, coupled_streams_out: *UInt8, mapping_out: *UInt8, mapping_capacity: Int, application: Int, err_out: *UInt8) -> Int;
  fn xo_multistream_encode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_multistream_encode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_multistream_encode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_multistream_encoder_destroy(p0: Int) -> Int;
  fn xo_multistream_encoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_multistream_encoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_multistream_decoder_get_size(p0: Int, p1: Int) -> Int;
  fn xo_multistream_decoder_create(p0: Int, p1: Int, p2: Int, p3: Int, p4: *UInt8, p5: *UInt8) -> Int;
  fn xo_multistream_decoder_init(mem: *UInt8, mem_capacity: Int, Fs: Int, channels: Int, streams: Int, coupled_streams: Int, mapping: *UInt8, err_out: *UInt8) -> Int;
  fn xo_multistream_decode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_multistream_decode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_multistream_decode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_multistream_decoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_multistream_decoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_multistream_decoder_destroy(p0: Int) -> Int;
  fn xo_custom_mode_create(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_custom_mode_destroy(p0: Int) -> Int;
  fn xo_custom_encoder_get_size(p0: Int, p1: Int) -> Int;
  fn xo_custom_encoder_init(mem: *UInt8, mem_capacity: Int, mode: Int, channels: Int, err_out: *UInt8) -> Int;
  fn xo_custom_encoder_create(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_custom_encoder_destroy(p0: Int) -> Int;
  fn xo_custom_encode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_custom_encode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_custom_encode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_custom_encoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_custom_encoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_custom_decoder_get_size(p0: Int, p1: Int) -> Int;
  fn xo_custom_decoder_init(mem: *UInt8, mem_capacity: Int, mode: Int, channels: Int, err_out: *UInt8) -> Int;
  fn xo_custom_decoder_create(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_custom_decoder_destroy(p0: Int) -> Int;
  fn xo_custom_decode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_custom_decode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_custom_decode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_custom_decoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_custom_decoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_projection_ambisonics_encoder_get_size(p0: Int, p1: Int) -> Int;
  fn xo_projection_ambisonics_encoder_create(Fs: Int, channels: Int, mapping_family: Int, streams_out: *UInt8, coupled_streams_out: *UInt8, application: Int, err_out: *UInt8) -> Int;
  fn xo_projection_ambisonics_encoder_init(mem: *UInt8, mem_capacity: Int, Fs: Int, channels: Int, mapping_family: Int, streams_out: *UInt8, coupled_streams_out: *UInt8, application: Int, err_out: *UInt8) -> Int;
  fn xo_projection_encode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_projection_encode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_projection_encode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int) -> Int;
  fn xo_projection_encoder_destroy(p0: Int) -> Int;
  fn xo_projection_encoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_projection_encoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_projection_decoder_get_size(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_projection_decoder_create(p0: Int, p1: Int, p2: Int, p3: Int, p4: *UInt8, p5: Int, p6: *UInt8) -> Int;
  fn xo_projection_decoder_init(mem: *UInt8, mem_capacity: Int, Fs: Int, channels: Int, streams: Int, coupled_streams: Int, demixing_matrix: *UInt8, demixing_matrix_size: Int, err_out: *UInt8) -> Int;
  fn xo_projection_decode(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_projection_decode24(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_projection_decode_float(p0: Int, p1: *UInt8, p2: Int, p3: *UInt8, p4: Int, p5: Int) -> Int;
  fn xo_projection_decoder_ctl_set(p0: Int, p1: Int, p2: Int) -> Int;
  fn xo_projection_decoder_ctl_get(p0: Int, p1: Int, p2: *UInt8) -> Int;
  fn xo_projection_decoder_destroy(p0: Int) -> Int;
  // ctl pointer-argument companions (documented extensions)
  fn xo_encoder_ctl_set_dnn_blob(enc: Int, blob: *UInt8, size: Int) -> Int;
  fn xo_multistream_decoder_ctl_get_state(st: Int, stream_index: Int, out_slot: *UInt8) -> Int;
  fn xo_multistream_encoder_ctl_get_state(st: Int, stream_index: Int, out_slot: *UInt8) -> Int;
  fn xo_projection_encoder_ctl_get_matrix(st: Int, out: *UInt8, capacity: Int) -> Int;
}
// <<< GENERATED-EXTERNS-END

// ---------------------------------------------------------------------------
// internal helpers (leaf constructors: Results are built here only)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, OpusError] {
  return Ok(v);
}

fn _err_int(code: Int) -> Result[Int, OpusError] {
  return Err(OpusError{ code: code; message: strerror(code) });
}

fn _ok_unit() -> Result[Unit, OpusError] {
  return Ok({});
}

fn _err_unit(code: Int) -> Result[Unit, OpusError] {
  return Err(OpusError{ code: code; message: strerror(code) });
}

fn _ok_frames(v: PacketFrames) -> Result[PacketFrames, OpusError] {
  return Ok(v);
}

fn _err_frames(code: Int) -> Result[PacketFrames, OpusError] {
  return Err(OpusError{ code: code; message: strerror(code) });
}

fn _ok_encoder_out(v: EncoderOutcome) -> Result[EncoderOutcome, OpusError] {
  return Ok(v);
}

fn _err_encoder_out(code: Int) -> Result[EncoderOutcome, OpusError] {
  return Err(OpusError{ code: code; message: strerror(code) });
}

/// 4-byte zeroed owned slot for one scalar out-param.
fn slot4() -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// n-byte zeroed owned buffer.
fn buf_zero(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Little-endian i32 from an owned slot at `pos` (sign-extended).
fn read_i32_at(buf: &Vec[UInt8], pos: Int) -> Int {
  let b0 = buf[pos] as Int;
  let b1 = buf[pos + 1] as Int;
  let b2 = buf[pos + 2] as Int;
  let b3 = buf[pos + 3] as Int;
  let raw = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  if b3 >= 128 {
    return raw - 4294967296;
  }
  return raw;
}

fn read_i32_le(buf: &Vec[UInt8]) -> Int {
  return read_i32_at(buf, 0);
}

/// Little-endian i16 from owned bytes at `pos` (sign-extended).
fn read_i16_at(buf: &Vec[UInt8], pos: Int) -> Int {
  let b0 = buf[pos] as Int;
  let b1 = buf[pos + 1] as Int;
  let raw = b0 | (b1 << 8);
  if b1 >= 128 {
    return raw - 65536;
  }
  return raw;
}

/// Little-endian 64-bit handle from owned bytes at `pos`.  Windows user-mode
/// pointers fit in the low 48 bits, so byte 7 is scaled by 2^56 (never a
/// shifting overflow) and must be < 128 (documented assumption).
fn read_ptr_at(buf: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 7 {
    v = v + ((buf[pos + i] as Int) << (8 * i));
    i = i + 1;
  }
  v = v + (buf[pos + 7] as Int) * 72057594037927936;
  return v;
}

/// Copy the first `n` bytes of an owned slot into a fresh Str.
fn str_from_slot(buf: &Vec[UInt8], n: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(buf[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

fn enc_out(handle: Int, streams: Int, coupled: Int) -> EncoderOutcome {
  return EncoderOutcome{ handle: handle; streams: streams; coupled_streams: coupled };
}

fn create_result(slot: &Vec[UInt8], handle: Int, alloc_code: Int) -> Result[Int, OpusError] {
  let rc = read_i32_le(slot);
  if rc != 0 {
    return _err_int(rc);
  }
  if handle == 0 {
    return _err_int(alloc_code);
  }
  return _ok_int(handle);
}

// ---------------------------------------------------------------------------
// version / error strings
// ---------------------------------------------------------------------------

/// Upstream version string, e.g. "libopus 1.6.1". Complexity: O(1).
pub fn version() -> Str {
  var slot = buf_zero(64);
  var n: Int = 0;
  unsafe {
    n = xo_get_version_string(slot.as_mut_ptr(), 64);
  }
  return str_from_slot(&slot, n);
}

/// Upstream error description for a libopus error code. Complexity: O(1).
pub fn strerror(code: Int) -> Str {
  var slot = buf_zero(64);
  var n: Int = 0;
  unsafe {
    n = xo_strerror(code, slot.as_mut_ptr(), 64);
  }
  return str_from_slot(&slot, n);
}

// ---------------------------------------------------------------------------
// packet inspection (all operate on an owned packet Vec)
// ---------------------------------------------------------------------------

/// Number of frames in an opus packet; Err on a malformed packet.
/// Complexity: O(1).
pub fn packet_get_nb_frames(packet: &Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_get_nb_frames(packet.as_ptr(), packet.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Samples per frame for the packet at the given sampling rate.
/// Complexity: O(1).
pub fn packet_get_samples_per_frame(packet: &Vec[UInt8], sample_rate: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_get_samples_per_frame(packet.as_ptr(), sample_rate);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Total samples in the packet at the given sampling rate.
/// Complexity: O(1).
pub fn packet_get_nb_samples(packet: &Vec[UInt8], sample_rate: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_get_nb_samples(packet.as_ptr(), packet.len(), sample_rate);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Number of channels coded in the packet (1 or 2). Complexity: O(1).
pub fn packet_get_nb_channels(packet: &Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_get_nb_channels(packet.as_ptr());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Bandwidth of the packet (OPUS_BANDWIDTH_*). Complexity: O(1).
pub fn packet_get_bandwidth(packet: &Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_get_bandwidth(packet.as_ptr());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// 1 when the packet carries LBRR frames, else 0. Complexity: O(1).
pub fn packet_has_lbrr(packet: &Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_has_lbrr(packet.as_ptr(), packet.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Parse the frame table of an opus packet (toc byte, per-frame sizes and
/// byte offsets, payload offset). Complexity: O(frames).
pub fn packet_parse(packet: &Vec[UInt8]) -> Result[PacketFrames, OpusError] {
  var sizes = buf_zero(48 * 4);
  var offsets = buf_zero(48 * 4);
  var toc = buf_zero(1);
  var poff = slot4();
  var nb: Int = 0;
  unsafe {
    nb = xo_packet_parse(packet.as_ptr(), packet.len(), toc.as_mut_ptr(), sizes.as_mut_ptr(),
                             offsets.as_mut_ptr(), 48, poff.as_mut_ptr());
  }
  if nb < 0 {
    return _err_frames(nb);
  }
  var sv: Vec[Int] = Vec[Int].new();
  var ov: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < nb {
    sv.push(read_i32_at(&sizes, i * 4));
    ov.push(read_i32_at(&offsets, i * 4));
    i = i + 1;
  }
  let frames = PacketFrames{
    count: nb;
    toc: toc[0] as Int;
    payload_offset: read_i32_le(&poff);
    sizes: sv;
    offsets: ov;
  };
  return _ok_frames(frames);
}

/// Pad `packet` in place to `new_len` bytes (returns the new length).
/// The Vec must already have at least `new_len` capacity bytes.
/// Complexity: O(new_len).
pub fn packet_pad(packet: &mut Vec[UInt8], len: Int, new_len: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_pad(packet.as_mut_ptr(), len, new_len);
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(new_len);
}

/// Remove padding from `packet` in place; returns the unpadded length.
/// Complexity: O(len).
pub fn packet_unpad(packet: &mut Vec[UInt8], len: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_packet_unpad(packet.as_mut_ptr(), len);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Multistream pad: pad `packet` in place for `nb_streams` streams.
/// Complexity: O(new_len).
pub fn multistream_packet_pad(packet: &mut Vec[UInt8], len: Int, new_len: Int, nb_streams: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_packet_pad(packet.as_mut_ptr(), len, new_len, nb_streams);
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(new_len);
}

/// Multistream unpad; returns the unpadded length. Complexity: O(len).
pub fn multistream_packet_unpad(packet: &mut Vec[UInt8], len: Int, nb_streams: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_packet_unpad(packet.as_mut_ptr(), len, nb_streams);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

// ---------------------------------------------------------------------------
// encoder
// ---------------------------------------------------------------------------

/// Encoder state size in bytes for `channels`. Complexity: O(1).
pub fn encoder_get_size(channels: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_encoder_get_size(channels);
  }
  return rc;
}

/// Create a mono/stereo encoder (application: OPUS_APPLICATION_*).
/// Complexity: O(1).
pub fn encoder_create(sample_rate: Int, channels: Int, application: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_encoder_create(sample_rate, channels, application, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Initialize an encoder in caller-owned memory of at least
/// encoder_get_size(channels) bytes; returns the memory address as handle.
/// Complexity: O(1).
pub fn encoder_init_over(mem: &mut Vec[UInt8], sample_rate: Int, channels: Int, application: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_encoder_init(mem.as_mut_ptr(), mem.len(), sample_rate, channels, application, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Encode one frame of interleaved signed 16-bit PCM (little-endian bytes
/// in `pcm`, frame_size samples per channel); the packet is written into the
/// owned `out` buffer (capacity = out.len()) and the byte count returned.
/// Complexity: O(frame_size * channels).
pub fn encode(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_encode(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one frame of interleaved 24-bit PCM (signed, little-endian i32
/// carrier bytes). Complexity: O(frame_size * channels).
pub fn encode24(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_encode24(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one frame of interleaved f32 PCM (little-endian bytes).
/// Complexity: O(frame_size * channels).
pub fn encode_float(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_encode_float(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Release an encoder created by encoder_create/encoder_init_over.
/// Passing 0 is a no-op. Complexity: O(1).
pub fn encoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_encoder_destroy(handle);
    }
  }
}

/// Encoder ctl setter (request: OPUS_*_REQUEST, value: Int).
/// Complexity: O(1).
pub fn encoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_encoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Encoder ctl getter (request: OPUS_GET_*_REQUEST). Complexity: O(1).
pub fn encoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_encoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

/// Load a DNN weights blob (OPUS_SET_DNN_BLOB, request 4052): pointer+length
/// ctl companion.  The default upstream build (no weights file support)
/// returns an error.  Complexity: O(1).
pub fn encoder_ctl_set_dnn_blob(handle: Int, blob: &Vec[UInt8]) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_encoder_ctl_set_dnn_blob(handle, blob.as_ptr(), blob.len());
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

// ---------------------------------------------------------------------------
// decoder
// ---------------------------------------------------------------------------

/// Decoder state size in bytes for `channels`. Complexity: O(1).
pub fn decoder_get_size(channels: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_decoder_get_size(channels);
  }
  return rc;
}

/// Create a mono/stereo decoder. Complexity: O(1).
pub fn decoder_create(sample_rate: Int, channels: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_decoder_create(sample_rate, channels, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Initialize a decoder in caller-owned memory (decoder_get_size bytes).
/// Complexity: O(1).
pub fn decoder_init_over(mem: &mut Vec[UInt8], sample_rate: Int, channels: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_decoder_init(mem.as_mut_ptr(), mem.len(), sample_rate, channels, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Decode an opus packet into interleaved s16 PCM (owned `out`, capacity
/// out.len()); returns decoded samples per channel.  An EMPTY packet Vec
/// triggers packet-loss concealment (upstream len==0 path).
/// Complexity: O(frame_size * channels).
pub fn decode(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decode(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode into interleaved 24-bit PCM (i32 carrier bytes in `out`).
/// Complexity: O(frame_size * channels).
pub fn decode24(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decode24(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode into interleaved f32 PCM (little-endian bytes in `out`).
/// Complexity: O(frame_size * channels).
pub fn decode_float(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decode_float(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Release a decoder. Passing 0 is a no-op. Complexity: O(1).
pub fn decoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_decoder_destroy(handle);
    }
  }
}

/// Decoder ctl setter. Complexity: O(1).
pub fn decoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Decoder ctl getter. Complexity: O(1).
pub fn decoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_decoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

/// Samples the decoder would produce for this packet; Err on malformed.
/// Complexity: O(1).
pub fn decoder_get_nb_samples(handle: Int, packet: &Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decoder_get_nb_samples(handle, packet.as_ptr(), packet.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Soft-clip in place: interleaved f32 samples in `pcm` (frame_size *
/// channels floats), `softclip_mem` holds channels * 2 f32 floats.
/// Complexity: O(frame_size * channels).
pub fn pcm_soft_clip(pcm: &mut Vec[UInt8], frame_size: Int, channels: Int, softclip_mem: &mut Vec[UInt8]) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_pcm_soft_clip(pcm.as_mut_ptr(), frame_size, channels, softclip_mem.as_mut_ptr());
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

// ---------------------------------------------------------------------------
// DRED (deep redundancy).  The default upstream build compiles the entry
// points but not the model; they return OPUS_UNIMPLEMENTED (-5) until a
// build with ENABLE_DRED + model data is used.  Bound 1:1 regardless.
// ---------------------------------------------------------------------------

/// DRED decoder state size. Complexity: O(1).
pub fn dred_decoder_get_size() -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_dred_decoder_get_size();
  }
  return rc;
}

/// Allocate a DRED decoder (Err OPUS_UNIMPLEMENTED without ENABLE_DRED).
/// Complexity: O(1).
pub fn dred_decoder_create() -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_dred_decoder_create(slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Initialize a DRED decoder in caller-owned memory. Complexity: O(1).
pub fn dred_decoder_init_over(mem: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_dred_decoder_init(mem.as_mut_ptr(), mem.len(), slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Release a DRED decoder. Complexity: O(1).
pub fn dred_decoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_dred_decoder_destroy(handle);
    }
  }
}

/// DRED decoder ctl setter. Complexity: O(1).
pub fn dred_decoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_dred_decoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// DRED decoder ctl getter. Complexity: O(1).
pub fn dred_decoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_dred_decoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

/// DRED state size. Complexity: O(1).
pub fn dred_get_size() -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_dred_get_size();
  }
  return rc;
}

/// Allocate a DRED state (Err OPUS_UNIMPLEMENTED without ENABLE_DRED).
/// Complexity: O(1).
pub fn dred_alloc() -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_dred_alloc(slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Release a DRED state. Complexity: O(1).
pub fn dred_free(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_dred_free(handle);
    }
  }
}

/// Parse DRED redundancy from a packet into `dred` (Err OPUS_UNIMPLEMENTED
/// without ENABLE_DRED). Complexity: O(packet).
pub fn dred_parse(dred_dec: Int, dred: Int, packet: &Vec[UInt8], max_dred_samples: Int, sample_rate: Int, defer_processing: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_dred_parse(dred_dec, dred, packet.as_ptr(), packet.len(), max_dred_samples, sample_rate, slot.as_mut_ptr(), defer_processing);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Finish deferred DRED processing. Complexity: O(1).
pub fn dred_process(dred_dec: Int, src: Int, dst: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_dred_process(dred_dec, src, dst);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode DRED audio (s16) at a redundancy offset. Complexity: O(frame).
pub fn decoder_dred_decode(handle: Int, dred: Int, dred_offset: Int, out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decoder_dred_decode(handle, dred, dred_offset, out.as_mut_ptr(), frame_size);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode DRED audio (24-bit carrier). Complexity: O(frame).
pub fn decoder_dred_decode24(handle: Int, dred: Int, dred_offset: Int, out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decoder_dred_decode24(handle, dred, dred_offset, out.as_mut_ptr(), frame_size);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode DRED audio (f32 carrier). Complexity: O(frame).
pub fn decoder_dred_decode_float(handle: Int, dred: Int, dred_offset: Int, out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_decoder_dred_decode_float(handle, dred, dred_offset, out.as_mut_ptr(), frame_size);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

// ---------------------------------------------------------------------------
// repacketizer
// ---------------------------------------------------------------------------

/// Repacketizer state size. Complexity: O(1).
pub fn repacketizer_get_size() -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_repacketizer_get_size();
  }
  return rc;
}

/// Initialize a repacketizer in caller-owned memory. Complexity: O(1).
pub fn repacketizer_init_over(mem: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_repacketizer_init(mem.as_mut_ptr(), mem.len(), slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Allocate a repacketizer. Complexity: O(1).
pub fn repacketizer_create() -> Result[Int, OpusError] {
  var h: Int = 0;
  unsafe {
    h = xo_repacketizer_create();
  }
  if h == 0 {
    return _err_int(-7);
  }
  return _ok_int(h);
}

/// Release a repacketizer. Passing 0 is a no-op. Complexity: O(1).
pub fn repacketizer_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_repacketizer_destroy(handle);
    }
  }
}

/// Append a packet to the repacketizer (packets must share TOC/samples).
/// Complexity: O(1).
pub fn repacketizer_cat(handle: Int, packet: &Vec[UInt8]) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_repacketizer_cat(handle, packet.as_ptr(), packet.len());
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Number of frames currently held. Complexity: O(1).
pub fn repacketizer_get_nb_frames(handle: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_repacketizer_get_nb_frames(handle);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Assemble frames [begin, end) into one packet in the owned `out` buffer.
/// Complexity: O(packet).
pub fn repacketizer_out_range(handle: Int, begin: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_repacketizer_out_range(handle, begin, end, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Assemble all held frames into one packet. Complexity: O(packet).
pub fn repacketizer_out(handle: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_repacketizer_out(handle, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

// ---------------------------------------------------------------------------
// multistream (encoder)
// ---------------------------------------------------------------------------

/// Multistream encoder state size. Complexity: O(1).
pub fn multistream_encoder_get_size(streams: Int, coupled_streams: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_encoder_get_size(streams, coupled_streams);
  }
  return rc;
}

/// Surround encoder state size for a channel count + mapping family.
/// Complexity: O(1).
pub fn multistream_surround_encoder_get_size(channels: Int, mapping_family: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_surround_encoder_get_size(channels, mapping_family);
  }
  return rc;
}

/// Create a multistream encoder with an explicit stream mapping.
/// Complexity: O(1).
pub fn multistream_encoder_create(sample_rate: Int, channels: Int, streams: Int, coupled_streams: Int, mapping: &Vec[UInt8], application: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_multistream_encoder_create(sample_rate, channels, streams, coupled_streams, mapping.as_ptr(), application, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Create a surround multistream encoder; the channel mapping is written
/// into the owned `mapping` buffer (channels bytes) and the chosen
/// stream layout is returned flat.
/// Complexity: O(1).
pub fn multistream_surround_encoder_create(sample_rate: Int, channels: Int, mapping_family: Int, mapping: &mut Vec[UInt8], application: Int) -> Result[EncoderOutcome, OpusError] {
  var streams_slot = slot4();
  var coupled_slot = slot4();
  var err_slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_multistream_surround_encoder_create(sample_rate, channels, mapping_family, streams_slot.as_mut_ptr(), coupled_slot.as_mut_ptr(), mapping.as_mut_ptr(), mapping.len(), application, err_slot.as_mut_ptr());
  }
  let rc = read_i32_le(&err_slot);
  if rc != 0 {
    return _err_encoder_out(rc);
  }
  if h == 0 {
    return _err_encoder_out(-7);
  }
  return _ok_encoder_out(enc_out(h, read_i32_le(&streams_slot), read_i32_le(&coupled_slot)));
}

/// Initialize a multistream encoder in caller-owned memory.
/// Complexity: O(1).
pub fn multistream_encoder_init_over(mem: &mut Vec[UInt8], sample_rate: Int, channels: Int, streams: Int, coupled_streams: Int, mapping: &Vec[UInt8], application: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_multistream_encoder_init(mem.as_mut_ptr(), mem.len(), sample_rate, channels, streams, coupled_streams, mapping.as_ptr(), application, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Initialize a surround multistream encoder in caller-owned memory.
/// Complexity: O(1).
pub fn multistream_surround_encoder_init_over(mem: &mut Vec[UInt8], sample_rate: Int, channels: Int, mapping_family: Int, mapping: &mut Vec[UInt8], application: Int) -> Result[EncoderOutcome, OpusError] {
  var streams_slot = slot4();
  var coupled_slot = slot4();
  var err_slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_multistream_surround_encoder_init(mem.as_mut_ptr(), mem.len(), sample_rate, channels, mapping_family, streams_slot.as_mut_ptr(), coupled_slot.as_mut_ptr(), mapping.as_mut_ptr(), mapping.len(), application, err_slot.as_mut_ptr());
  }
  let rc = read_i32_le(&err_slot);
  if rc != 0 {
    return _err_encoder_out(rc);
  }
  if h == 0 {
    return _err_encoder_out(-7);
  }
  return _ok_encoder_out(enc_out(h, read_i32_le(&streams_slot), read_i32_le(&coupled_slot)));
}

/// Encode one multistream frame from interleaved s16 PCM.
/// Complexity: O(frame_size * channels).
pub fn multistream_encode(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_encode(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one multistream frame from 24-bit carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn multistream_encode24(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_encode24(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one multistream frame from f32 carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn multistream_encode_float(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_encode_float(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Release a multistream encoder. Passing 0 is a no-op. Complexity: O(1).
pub fn multistream_encoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_multistream_encoder_destroy(handle);
    }
  }
}

/// Multistream encoder ctl setter. Complexity: O(1).
pub fn multistream_encoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_encoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Multistream encoder ctl getter. Complexity: O(1).
pub fn multistream_encoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_encoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

/// Handle of the sub-encoder for one stream
/// (OPUS_MULTISTREAM_GET_ENCODER_STATE, request 5120). Complexity: O(1).
pub fn multistream_encoder_ctl_get_state(handle: Int, stream_index: Int) -> Result[Int, OpusError] {
  var slot = buf_zero(8);
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_encoder_ctl_get_state(handle, stream_index, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_ptr_at(&slot, 0));
}

// ---------------------------------------------------------------------------
// multistream (decoder)
// ---------------------------------------------------------------------------

/// Multistream decoder state size. Complexity: O(1).
pub fn multistream_decoder_get_size(streams: Int, coupled_streams: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_decoder_get_size(streams, coupled_streams);
  }
  return rc;
}

/// Create a multistream decoder with an explicit stream mapping.
/// Complexity: O(1).
pub fn multistream_decoder_create(sample_rate: Int, channels: Int, streams: Int, coupled_streams: Int, mapping: &Vec[UInt8]) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_multistream_decoder_create(sample_rate, channels, streams, coupled_streams, mapping.as_ptr(), slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Initialize a multistream decoder in caller-owned memory.
/// Complexity: O(1).
pub fn multistream_decoder_init_over(mem: &mut Vec[UInt8], sample_rate: Int, channels: Int, streams: Int, coupled_streams: Int, mapping: &Vec[UInt8]) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_multistream_decoder_init(mem.as_mut_ptr(), mem.len(), sample_rate, channels, streams, coupled_streams, mapping.as_ptr(), slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Decode one multistream packet to interleaved s16 PCM.
/// Complexity: O(frame_size * channels).
pub fn multistream_decode(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_decode(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode one multistream packet to 24-bit carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn multistream_decode24(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_decode24(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode one multistream packet to f32 carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn multistream_decode_float(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_decode_float(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Release a multistream decoder. Passing 0 is a no-op. Complexity: O(1).
pub fn multistream_decoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_multistream_decoder_destroy(handle);
    }
  }
}

/// Multistream decoder ctl setter. Complexity: O(1).
pub fn multistream_decoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_decoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Multistream decoder ctl getter. Complexity: O(1).
pub fn multistream_decoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_decoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

/// Handle of the sub-decoder for one stream
/// (OPUS_MULTISTREAM_GET_DECODER_STATE, request 5122). Complexity: O(1).
pub fn multistream_decoder_ctl_get_state(handle: Int, stream_index: Int) -> Result[Int, OpusError] {
  var slot = buf_zero(8);
  var rc: Int = 0;
  unsafe {
    rc = xo_multistream_decoder_ctl_get_state(handle, stream_index, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_ptr_at(&slot, 0));
}

// ---------------------------------------------------------------------------
// custom modes (CUSTOM_MODES build)
// ---------------------------------------------------------------------------

/// Create a custom mode (parent of custom encoder/decoder). Complexity: O(1).
pub fn custom_mode_create(sample_rate: Int, frame_size: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_custom_mode_create(sample_rate, frame_size, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Destroy a custom mode (after all users). Complexity: O(1).
pub fn custom_mode_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_custom_mode_destroy(handle);
    }
  }
}

/// Custom encoder state size. Complexity: O(1).
pub fn custom_encoder_get_size(mode: Int, channels: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_encoder_get_size(mode, channels);
  }
  return rc;
}

/// Initialize a custom encoder in caller-owned memory. Complexity: O(1).
pub fn custom_encoder_init_over(mem: &mut Vec[UInt8], mode: Int, channels: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_custom_encoder_init(mem.as_mut_ptr(), mem.len(), mode, channels, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Create a custom encoder for a mode. Complexity: O(1).
pub fn custom_encoder_create(mode: Int, channels: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_custom_encoder_create(mode, channels, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Release a custom encoder. Passing 0 is a no-op. Complexity: O(1).
pub fn custom_encoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_custom_encoder_destroy(handle);
    }
  }
}

/// Encode one frame from interleaved s16 PCM into the owned `out`.
/// Complexity: O(frame_size * channels).
pub fn custom_encode(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_encode(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one frame from 24-bit carrier PCM. Complexity: O(frame_size * channels).
pub fn custom_encode24(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_encode24(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one frame from f32 carrier PCM. Complexity: O(frame_size * channels).
pub fn custom_encode_float(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_encode_float(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Custom encoder ctl setter. Complexity: O(1).
pub fn custom_encoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_encoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Custom encoder ctl getter. Complexity: O(1).
pub fn custom_encoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_encoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

/// Custom decoder state size. Complexity: O(1).
pub fn custom_decoder_get_size(mode: Int, channels: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_decoder_get_size(mode, channels);
  }
  return rc;
}

/// Initialize a custom decoder in caller-owned memory. Complexity: O(1).
pub fn custom_decoder_init_over(mem: &mut Vec[UInt8], mode: Int, channels: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_custom_decoder_init(mem.as_mut_ptr(), mem.len(), mode, channels, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Create a custom decoder for a mode. Complexity: O(1).
pub fn custom_decoder_create(mode: Int, channels: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_custom_decoder_create(mode, channels, slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Release a custom decoder. Passing 0 is a no-op. Complexity: O(1).
pub fn custom_decoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_custom_decoder_destroy(handle);
    }
  }
}

/// Decode one custom-frame packet to interleaved s16 PCM.
/// Complexity: O(frame_size * channels).
pub fn custom_decode(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_decode(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode one custom-frame packet to 24-bit carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn custom_decode24(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_decode24(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode one custom-frame packet to f32 carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn custom_decode_float(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_decode_float(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Custom decoder ctl setter. Complexity: O(1).
pub fn custom_decoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_decoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Custom decoder ctl getter. Complexity: O(1).
pub fn custom_decoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_custom_decoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

// ---------------------------------------------------------------------------
// projection (ambisonics)
// ---------------------------------------------------------------------------

/// Projection encoder state size. Complexity: O(1).
pub fn projection_ambisonics_encoder_get_size(channels: Int, mapping_family: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_ambisonics_encoder_get_size(channels, mapping_family);
  }
  return rc;
}

/// Create an ambisonics projection encoder. Complexity: O(1).
pub fn projection_ambisonics_encoder_create(sample_rate: Int, channels: Int, mapping_family: Int, application: Int) -> Result[EncoderOutcome, OpusError] {
  var streams_slot = slot4();
  var coupled_slot = slot4();
  var err_slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_projection_ambisonics_encoder_create(sample_rate, channels, mapping_family, streams_slot.as_mut_ptr(), coupled_slot.as_mut_ptr(), application, err_slot.as_mut_ptr());
  }
  let rc = read_i32_le(&err_slot);
  if rc != 0 {
    return _err_encoder_out(rc);
  }
  if h == 0 {
    return _err_encoder_out(-7);
  }
  return _ok_encoder_out(enc_out(h, read_i32_le(&streams_slot), read_i32_le(&coupled_slot)));
}

/// Initialize an ambisonics projection encoder in caller-owned memory.
/// Complexity: O(1).
pub fn projection_ambisonics_encoder_init_over(mem: &mut Vec[UInt8], sample_rate: Int, channels: Int, mapping_family: Int, application: Int) -> Result[EncoderOutcome, OpusError] {
  var streams_slot = slot4();
  var coupled_slot = slot4();
  var err_slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_projection_ambisonics_encoder_init(mem.as_mut_ptr(), mem.len(), sample_rate, channels, mapping_family, streams_slot.as_mut_ptr(), coupled_slot.as_mut_ptr(), application, err_slot.as_mut_ptr());
  }
  let rc = read_i32_le(&err_slot);
  if rc != 0 {
    return _err_encoder_out(rc);
  }
  if h == 0 {
    return _err_encoder_out(-7);
  }
  return _ok_encoder_out(enc_out(h, read_i32_le(&streams_slot), read_i32_le(&coupled_slot)));
}

/// Encode one ambisonics frame from interleaved s16 PCM.
/// Complexity: O(frame_size * channels).
pub fn projection_encode(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_encode(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one ambisonics frame from 24-bit carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn projection_encode24(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_encode24(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Encode one ambisonics frame from f32 carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn projection_encode_float(handle: Int, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_encode_float(handle, pcm.as_ptr(), frame_size, out.as_mut_ptr(), out.len());
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Release a projection encoder. Passing 0 is a no-op. Complexity: O(1).
pub fn projection_encoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_projection_encoder_destroy(handle);
    }
  }
}

/// Projection encoder ctl setter. Complexity: O(1).
pub fn projection_encoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_encoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Projection encoder ctl getter. Complexity: O(1).
pub fn projection_encoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_encoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}

/// Copy the demixing matrix out of a projection encoder
/// (OPUS_PROJECTION_GET_DEMIXING_MATRIX, request 6005): pointer+length ctl
/// companion.  Size the buffer with ctl_get(6003).
/// Complexity: O(matrix size).
pub fn projection_encoder_ctl_get_matrix(handle: Int, out: &mut Vec[UInt8]) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_encoder_ctl_get_matrix(handle, out.as_mut_ptr(), out.len());
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Projection decoder state size. Complexity: O(1).
pub fn projection_decoder_get_size(channels: Int, streams: Int, coupled_streams: Int) -> Int {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_decoder_get_size(channels, streams, coupled_streams);
  }
  return rc;
}

/// Create a projection decoder from a demixing matrix (owned bytes).
/// Complexity: O(1).
pub fn projection_decoder_create(sample_rate: Int, channels: Int, streams: Int, coupled_streams: Int, demixing_matrix: &Vec[UInt8]) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_projection_decoder_create(sample_rate, channels, streams, coupled_streams, demixing_matrix.as_ptr(), demixing_matrix.len(), slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Initialize a projection decoder in caller-owned memory.
/// Complexity: O(1).
pub fn projection_decoder_init_over(mem: &mut Vec[UInt8], sample_rate: Int, channels: Int, streams: Int, coupled_streams: Int, demixing_matrix: &Vec[UInt8]) -> Result[Int, OpusError] {
  var slot = slot4();
  var h: Int = 0;
  unsafe {
    h = xo_projection_decoder_init(mem.as_mut_ptr(), mem.len(), sample_rate, channels, streams, coupled_streams, demixing_matrix.as_ptr(), demixing_matrix.len(), slot.as_mut_ptr());
  }
  return create_result(&slot, h, -7);
}

/// Decode one projection packet to interleaved s16 PCM.
/// Complexity: O(frame_size * channels).
pub fn projection_decode(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_decode(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode one projection packet to 24-bit carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn projection_decode24(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_decode24(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Decode one projection packet to f32 carrier PCM.
/// Complexity: O(frame_size * channels).
pub fn projection_decode_float(handle: Int, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int, decode_fec: Int) -> Result[Int, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_decode_float(handle, packet.as_ptr(), packet.len(), out.as_mut_ptr(), frame_size, decode_fec);
  }
  if rc < 0 {
    return _err_int(rc);
  }
  return _ok_int(rc);
}

/// Release a projection decoder. Passing 0 is a no-op. Complexity: O(1).
pub fn projection_decoder_destroy(handle: Int) {
  if handle != 0 {
    unsafe {
      let ignored = xo_projection_decoder_destroy(handle);
    }
  }
}

/// Projection decoder ctl setter. Complexity: O(1).
pub fn projection_decoder_ctl_set(handle: Int, request: Int, value: Int) -> Result[Unit, OpusError] {
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_decoder_ctl_set(handle, request, value);
  }
  if rc != 0 {
    return _err_unit(rc);
  }
  return _ok_unit();
}

/// Projection decoder ctl getter. Complexity: O(1).
pub fn projection_decoder_ctl_get(handle: Int, request: Int) -> Result[Int, OpusError] {
  var slot = slot4();
  var rc: Int = 0;
  unsafe {
    rc = xo_projection_decoder_ctl_get(handle, request, slot.as_mut_ptr());
  }
  if rc != 0 {
    return _err_int(rc);
  }
  return _ok_int(read_i32_le(&slot));
}
