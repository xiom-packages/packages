// xiom.opus -- shared types (pure XIOM, no unsafe, no externs).
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Flat outcome structs only (finding B-26: never Result[Option[T]]).

module xiom.opus.types

/// Error raised by the opus.opus.* wrappers: `code` is the libopus error
/// code (OPUS_BAD_ARG = -1 ... OPUS_ALLOC_FAIL = -7) and `message` is the
/// upstream `opus_strerror` text for that code.
pub type OpusError = {
  code: Int;
  message: Str;
}

/// Result of `packet_parse`: frame count, TOC byte, payload offset and the
/// per-frame sizes/offsets within the packet (up to 48 frames, the RFC 6716
/// maximum of 120 ms). Pure XIOM values, copied out of the owned C slots.
pub type PacketFrames = {
  count: Int;
  toc: Int;
  payload_offset: Int;
  sizes: Vec[Int];
  offsets: Vec[Int];
}

/// Stream layout reported by the surround/ambisonics encoder creators.
pub type StreamLayout = {
  streams: Int;
  coupled_streams: Int;
}

/// Flat result of the surround/ambisonics encoder creators/initializers:
/// the encoder handle plus the chosen stream layout.
pub type EncoderOutcome = {
  handle: Int;
  streams: Int;
  coupled_streams: Int;
}
