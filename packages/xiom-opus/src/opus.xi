// xiom.opus -- package facade (pure XIOM; all foreign calls live in
// xiom.opus.ffi).
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Vendored libopus v1.6.1 (BSD-3; see vendor/COPYING and PROVENANCE.md).
//
// This facade covers the everyday paths with typed handles:
//
//   * Encoder  -- create / encode (s16, 24-bit, f32) / ctl set+get / destroy
//   * Decoder  -- create / decode (+ PLC via decode_lost) / ctl / destroy
//   * Repacketizer -- create / cat / out / out_range / destroy
//   * version() / strerror()
//
// The COMPLETE 1:1 surface (multistream encoders/decoders, Opus Custom,
// projection/ambisonics, DRED, packet utilities, padding, soft clip,
// init-over-own-memory) is exposed by `xiom.opus.ffi`; constants and ctl
// request ids (OPUS_*, OPUS_*_REQUEST) live in `xiom.opus.abi`.

module xiom.opus

use xiom.opus.ffi;
use xiom.opus.types;

/// Encoder handle: opaque libopus state plus its configuration.
/// `handle` is owned by this value; call `destroy` when done.
pub type Encoder = {
  handle: Int;
  sample_rate: Int;
  channels: Int;
}

/// Decoder handle.
pub type Decoder = {
  handle: Int;
  sample_rate: Int;
  channels: Int;
}

/// Repacketizer handle.
pub type Repacketizer = {
  handle: Int;
}

// ---------------------------------------------------------------------------
// strings
// ---------------------------------------------------------------------------

/// Upstream version string, e.g. "libopus 1.6.1". Complexity: O(1).
pub fn version() -> Str {
  return ffi.version();
}

/// Upstream error description for a libopus error code. Complexity: O(1).
pub fn strerror(code: Int) -> Str {
  return ffi.strerror(code);
}

// ---------------------------------------------------------------------------
// Encoder
// ---------------------------------------------------------------------------

/// Create an encoder. `application` is one of the OPUS_APPLICATION_*
/// constants in `xiom.opus.abi`. Complexity: O(1).
pub fn Encoder.create(sample_rate: Int, channels: Int, application: Int) -> Result[Encoder, OpusError]
  requires: sample_rate > 0
  requires: channels > 0
{
  let r = ffi.encoder_create(sample_rate, channels, application);
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok(Encoder{ handle: r.value; sample_rate: sample_rate; channels: channels });
}

/// Encode one frame of interleaved signed 16-bit PCM (little-endian bytes),
/// writing the packet into the owned `out` buffer (capacity = out.len()).
/// Returns the encoded byte count. Complexity: O(frame_size * channels).
pub fn Encoder.encode(enc: &Encoder, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError]
  requires: enc.handle != 0
  requires: frame_size > 0
{
  return ffi.encode(enc.handle, pcm, frame_size, out);
}

/// Encode one frame of 24-bit PCM (i32 carrier bytes).
/// Complexity: O(frame_size * channels).
pub fn Encoder.encode24(enc: &Encoder, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError]
  requires: enc.handle != 0
{
  return ffi.encode24(enc.handle, pcm, frame_size, out);
}

/// Encode one frame of f32 PCM (little-endian bytes).
/// Complexity: O(frame_size * channels).
pub fn Encoder.encode_float(enc: &Encoder, pcm: &Vec[UInt8], frame_size: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError]
  requires: enc.handle != 0
{
  return ffi.encode_float(enc.handle, pcm, frame_size, out);
}

/// Apply an encoder ctl (request id + Int value); see `xiom.opus.abi` for
/// the OPUS_*_REQUEST constants. Complexity: O(1).
pub fn Encoder.ctl_set(enc: &Encoder, request: Int, value: Int) -> Result[Unit, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_set(enc.handle, request, value);
}

/// Read an encoder ctl (request id); see `xiom.opus.abi`.
/// Complexity: O(1).
pub fn Encoder.ctl_get(enc: &Encoder, request: Int) -> Result[Int, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_get(enc.handle, request);
}

/// Set the target bitrate in bits/s (OPUS_AUTO / OPUS_BITRATE_MAX allowed).
/// Complexity: O(1).
pub fn Encoder.set_bitrate(enc: &Encoder, bitrate: Int) -> Result[Unit, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_set(enc.handle, 4002, bitrate);
}

/// Current target bitrate in bits/s. Complexity: O(1).
pub fn Encoder.bitrate(enc: &Encoder) -> Result[Int, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_get(enc.handle, 4003);
}

/// Set encoder complexity 0..10. Complexity: O(1).
pub fn Encoder.set_complexity(enc: &Encoder, complexity: Int) -> Result[Unit, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_set(enc.handle, 4010, complexity);
}

/// Set the maximum coding bandwidth (OPUS_BANDWIDTH_*). Complexity: O(1).
pub fn Encoder.set_max_bandwidth(enc: &Encoder, bandwidth: Int) -> Result[Unit, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_set(enc.handle, 4004, bandwidth);
}

/// Number of samples of encoder look-ahead (delay). Complexity: O(1).
pub fn Encoder.lookahead(enc: &Encoder) -> Result[Int, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_get(enc.handle, 4027);
}

/// RNG state after the last encoded packet (OPUS_GET_FINAL_RANGE).
/// Complexity: O(1).
pub fn Encoder.final_range(enc: &Encoder) -> Result[Int, OpusError]
  requires: enc.handle != 0
{
  return ffi.encoder_ctl_get(enc.handle, 4031);
}

/// Release the encoder. Safe to call once; the handle must not be reused.
/// Complexity: O(1).
pub fn Encoder.destroy(enc: &Encoder) {
  ffi.encoder_destroy(enc.handle);
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

/// Create a decoder. Complexity: O(1).
pub fn Decoder.create(sample_rate: Int, channels: Int) -> Result[Decoder, OpusError]
  requires: sample_rate > 0
  requires: channels > 0
{
  let r = ffi.decoder_create(sample_rate, channels);
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok(Decoder{ handle: r.value; sample_rate: sample_rate; channels: channels });
}

/// Decode a packet to interleaved s16 PCM (owned `out`); returns samples
/// per channel. Complexity: O(frame_size * channels).
pub fn Decoder.decode(dec: &Decoder, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError]
  requires: dec.handle != 0
  requires: frame_size > 0
{
  return ffi.decode(dec.handle, packet, out, frame_size, 0);
}

/// Decode with in-band FEC. Complexity: O(frame_size * channels).
pub fn Decoder.decode_fec(dec: &Decoder, packet: &Vec[UInt8], out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError]
  requires: dec.handle != 0
{
  return ffi.decode(dec.handle, packet, out, frame_size, 1);
}

/// Conceal a lost packet (PLC) of `frame_size` samples per channel.
/// Complexity: O(frame_size * channels).
pub fn Decoder.decode_lost(dec: &Decoder, out: &mut Vec[UInt8], frame_size: Int) -> Result[Int, OpusError]
  requires: dec.handle != 0
  requires: frame_size > 0
{
  let empty: Vec[UInt8] = Vec[UInt8].new();
  return ffi.decode(dec.handle, &empty, out, frame_size, 0);
}

/// Apply a decoder ctl (e.g. OPUS_SET_GAIN_REQUEST 4034 / OPUS_RESET_STATE
/// 4028 with a value of 0). Complexity: O(1).
pub fn Decoder.ctl_set(dec: &Decoder, request: Int, value: Int) -> Result[Unit, OpusError]
  requires: dec.handle != 0
{
  return ffi.decoder_ctl_set(dec.handle, request, value);
}

/// Read a decoder ctl (e.g. OPUS_GET_PITCH_REQUEST 4033).
/// Complexity: O(1).
pub fn Decoder.ctl_get(dec: &Decoder, request: Int) -> Result[Int, OpusError]
  requires: dec.handle != 0
{
  return ffi.decoder_ctl_get(dec.handle, request);
}

/// Last packet duration in samples (OPUS_GET_LAST_PACKET_DURATION_REQUEST).
/// Complexity: O(1).
pub fn Decoder.last_packet_duration(dec: &Decoder) -> Result[Int, OpusError]
  requires: dec.handle != 0
{
  return ffi.decoder_ctl_get(dec.handle, 4039);
}

/// Release the decoder. Passing a zero handle is a no-op. Complexity: O(1).
pub fn Decoder.destroy(dec: &Decoder) {
  ffi.decoder_destroy(dec.handle);
}

// ---------------------------------------------------------------------------
// Repacketizer
// ---------------------------------------------------------------------------

/// Allocate a repacketizer. Complexity: O(1).
pub fn Repacketizer.create() -> Result[Repacketizer, OpusError] {
  let r = ffi.repacketizer_create();
  if !r.is_ok {
    return Err(r.error);
  }
  return Ok(Repacketizer{ handle: r.value });
}

/// Append a packet (all packets must share TOC configuration).
/// Complexity: O(1).
pub fn Repacketizer.cat(rp: &Repacketizer, packet: &Vec[UInt8]) -> Result[Unit, OpusError]
  requires: rp.handle != 0
{
  return ffi.repacketizer_cat(rp.handle, packet);
}

/// Number of frames held. Complexity: O(1).
pub fn Repacketizer.frame_count(rp: &Repacketizer) -> Result[Int, OpusError]
  requires: rp.handle != 0
{
  return ffi.repacketizer_get_nb_frames(rp.handle);
}

/// Assemble frames [begin, end) into `out`. Complexity: O(packet).
pub fn Repacketizer.out_range(rp: &Repacketizer, begin: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, OpusError]
  requires: rp.handle != 0
  requires: begin >= 0
  requires: end > begin
{
  return ffi.repacketizer_out_range(rp.handle, begin, end, out);
}

/// Assemble all held frames into `out`. Complexity: O(packet).
pub fn Repacketizer.out(rp: &Repacketizer, out: &mut Vec[UInt8]) -> Result[Int, OpusError]
  requires: rp.handle != 0
{
  return ffi.repacketizer_out(rp.handle, out);
}

/// Release the repacketizer. Complexity: O(1).
pub fn Repacketizer.destroy(rp: &Repacketizer) {
  ffi.repacketizer_destroy(rp.handle);
}

// ---------------------------------------------------------------------------
// packet helpers (facade convenience; full surface in xiom.opus.ffi)
// ---------------------------------------------------------------------------

/// Frames in a packet. Complexity: O(1).
pub fn packet_frame_count(packet: &Vec[UInt8]) -> Result[Int, OpusError] {
  return ffi.packet_get_nb_frames(packet);
}

/// Parsed frame table of a packet. Complexity: O(frames).
pub fn packet_frames(packet: &Vec[UInt8]) -> Result[PacketFrames, OpusError] {
  return ffi.packet_parse(packet);
}

/// Total samples in a packet at `sample_rate`. Complexity: O(1).
pub fn packet_sample_count(packet: &Vec[UInt8], sample_rate: Int) -> Result[Int, OpusError] {
  return ffi.packet_get_nb_samples(packet, sample_rate);
}
