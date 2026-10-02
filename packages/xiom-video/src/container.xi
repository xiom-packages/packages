// XIOM -- xiom.video.container: format-agnostic demux/mux dispatch
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The format-agnostic entry points of the xiom.video package. `video_demux`
// sniffs the buffer and dispatches to the AVI reader (xiom.video.avi) or
// the raw proof reader (xiom.video.raw); Matroska/WebM, MP4 and Ogg are
// recognised by magic but there is no demuxer for them in this package
// (Err("video: unsupported format")), and anything unrecognised is
// Err("video: unknown format"). `video_mux` serialises a store into the
// requested format; `video_mux_avi` / `video_mux_raw` are the direct
// counterparts of the two readers.
//
// Compiler-v0.62.2 notes: free functions only, Ok/Err only in the leaf
// helpers, no unused state; this module depends on xiom.video,
// xiom.video.avi and xiom.video.raw (no cycles).

module xiom.video.container

use xiom.video;
use xiom.video.avi;
use xiom.video.raw;

fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _err_stream(m: Str) -> Result[VideoStream, Str] { return Err(m); }

/// Demux any supported buffer into a VideoStream. AVI and XRAW are parsed;
/// Matroska/WebM, MP4 and Ogg are sniffed but unsupported here. Errors:
/// "video: truncated header", "video: unsupported format", "video: unknown
/// format", or any reader-specific error. Complexity: that of the selected
/// reader.
pub fn video_demux(data: &Vec[UInt8]) -> Result[VideoStream, Str] {
  if data.len() < 4 {
    return _err_stream("video: truncated header");
  }
  let f = video_sniff(data);
  if f == VIDEO_FMT_AVI { return avi_demux(data); }
  if f == VIDEO_FMT_RAW { return raw_demux(data); }
  if f == VIDEO_FMT_MKV || f == VIDEO_FMT_MP4 || f == VIDEO_FMT_OGG {
    return _err_stream("video: unsupported format");
  }
  return _err_stream("video: unknown format");
}

/// Mux a store into `format` (VIDEO_FMT_AVI or VIDEO_FMT_RAW). Errors:
/// "video: unsupported format" plus the selected muxer's errors.
pub fn video_mux(s: &VideoStream, format: Int) -> Result[Vec[UInt8], Str] {
  if format == VIDEO_FMT_AVI { return avi_mux(s); }
  if format == VIDEO_FMT_RAW { return raw_mux(s); }
  return _err_bytes("video: unsupported format");
}

/// Mux a store into a minimal RIFF/AVI container. See avi_mux.
pub fn video_mux_avi(s: &VideoStream) -> Result[Vec[UInt8], Str] {
  return avi_mux(s);
}

/// Mux a store into the XRAW proof stream. See raw_mux.
pub fn video_mux_raw(s: &VideoStream) -> Result[Vec[UInt8], Str] {
  return raw_mux(s);
}
