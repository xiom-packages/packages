// XIOM — xiom.ffmpeg: Safe FFmpeg Bindings (libavformat / libavcodec)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Phase 2 (Scientific). Wraps FFmpeg system libraries with safe XIOM types,
// Result-based error handling, and contract enforcement.

module xiom.ffmpeg

// ── Opaque handle types (raw C pointers) ──
pub type FfmpegContext = Int
pub type FfmpegPacket  = Int
pub type FfmpegFrame   = Int

// ── Raw C FFI block ──
extern "C" {
  fn avformat_alloc_context() -> FfmpegContext;
  fn avformat_open_input(ctx: FfmpegContext, path: *UInt8, fmt: FfmpegContext, opts: FfmpegContext) -> Int;
  fn avformat_close_input(ctx: FfmpegContext) -> Int;
  fn avformat_find_stream_info(ctx: FfmpegContext, opts: FfmpegContext) -> Int;
  fn av_find_best_stream(ctx: FfmpegContext, media_type: Int, wanted: Int, related: Int, codec: FfmpegContext, flags: Int) -> Int;
  fn av_read_frame(ctx: FfmpegContext, pkt: FfmpegPacket) -> Int;
  fn av_packet_alloc() -> FfmpegPacket;
  fn av_packet_unref(pkt: FfmpegPacket) -> Int;
  fn av_packet_free(pkt: FfmpegPacket) -> Int;
  fn av_frame_alloc() -> FfmpegFrame;
  fn av_frame_unref(frame: FfmpegFrame) -> Int;
  fn av_frame_free(frame: FfmpegFrame) -> Int;
  fn avcodec_find_decoder(id: Int) -> FfmpegContext;
  fn avcodec_alloc_context3(codec: FfmpegContext) -> FfmpegContext;
  fn avcodec_open2(ctx: FfmpegContext, codec: FfmpegContext, opts: FfmpegContext) -> Int;
  fn avcodec_close(ctx: FfmpegContext) -> Int;
  fn avcodec_free_context(ctx: FfmpegContext) -> Int;
  fn avcodec_send_packet(ctx: FfmpegContext, pkt: FfmpegPacket) -> Int;
  fn avcodec_receive_frame(ctx: FfmpegContext, frame: FfmpegFrame) -> Int;
  fn avcodec_send_frame(ctx: FfmpegContext, frame: FfmpegFrame) -> Int;
  fn avcodec_receive_packet(ctx: FfmpegContext, pkt: FfmpegPacket) -> Int;
  fn avformat_alloc_output_context2(ctx: FfmpegContext, fmt: FfmpegContext, name: *UInt8, path: *UInt8) -> Int;
  fn avformat_new_stream(ctx: FfmpegContext, codec: FfmpegContext) -> Int;
  fn avformat_write_header(ctx: FfmpegContext, opts: FfmpegContext) -> Int;
  fn av_interleaved_write_frame(ctx: FfmpegContext, pkt: FfmpegPacket) -> Int;
  fn av_write_trailer(ctx: FfmpegContext) -> Int;
  fn avformat_free_context(ctx: FfmpegContext) -> Int;
  fn av_strerror(code: Int, buf: FfmpegContext, buf_size: Int) -> Int;
}

// ── Constants ──
pub const AVMEDIA_TYPE_VIDEO: Int = 0;
pub const AVMEDIA_TYPE_AUDIO: Int = 1;
pub const AV_ERROR_EOF:     Int = -541478725;
pub const AV_ERROR_EAGAIN:  Int = -11;
pub const AV_SUCCESS:       Int = 0;

// ── Safe wrappers ──

pub fn open_input(path: Str) -> Result[FfmpegContext, Str]
  requires: path.len() > 0;
{
  let ctx = avformat_alloc_context();
  if ctx == 0 {
    return Err("avformat_alloc_context returned null");
  }
  let rc = avformat_open_input(ctx, path, 0, 0);
  if rc < 0 {
    return Err("avformat_open_input failed (code " + int_to_str(rc) + ")");
  }
  return Ok(ctx);
}

pub fn close_input(ctx: FfmpegContext) {
  avformat_close_input(ctx);
  avformat_free_context(ctx);
}

pub fn find_stream_info(ctx: FfmpegContext) -> Result[Int, Str] {
  let rc = avformat_find_stream_info(ctx, 0);
  if rc < 0 {
    return Err("avformat_find_stream_info failed (code " + int_to_str(rc) + ")");
  }
  return Ok(rc);
}

pub fn get_video_stream(ctx: FfmpegContext) -> Result[Int, Str] {
  let idx = av_find_best_stream(ctx, AVMEDIA_TYPE_VIDEO, -1, -1, 0, 0);
  if idx < 0 {
    return Err("no video stream found (code " + int_to_str(idx) + ")");
  }
  return Ok(idx);
}

pub fn read_frame(ctx: FfmpegContext, pkt: FfmpegPacket) -> Result[Int, Str] {
  let rc = av_read_frame(ctx, pkt);
  if rc < 0 {
    if rc == AV_ERROR_EOF {
      return Err("EOF");
    }
    return Err("av_read_frame failed (code " + int_to_str(rc) + ")");
  }
  return Ok(rc);
}

pub fn decode_frame(codec_ctx: FfmpegContext, pkt: FfmpegPacket, frame: FfmpegFrame) -> Result[Int, Str] {
  let send_rc = avcodec_send_packet(codec_ctx, pkt);
  if send_rc < 0 {
    if send_rc == AV_ERROR_EAGAIN {
      return Err("EAGAIN");
    }
    return Err("avcodec_send_packet failed (code " + int_to_str(send_rc) + ")");
  }
  let recv_rc = avcodec_receive_frame(codec_ctx, frame);
  if recv_rc < 0 {
    if recv_rc == AV_ERROR_EAGAIN {
      return Err("EAGAIN");
    }
    if recv_rc == AV_ERROR_EOF {
      return Err("EOF");
    }
    return Err("avcodec_receive_frame failed (code " + int_to_str(recv_rc) + ")");
  }
  return Ok(recv_rc);
}

pub fn encode_frame(codec_ctx: FfmpegContext, frame: FfmpegFrame, pkt: FfmpegPacket) -> Result[Int, Str] {
  let send_rc = avcodec_send_frame(codec_ctx, frame);
  if send_rc < 0 {
    if send_rc == AV_ERROR_EAGAIN {
      return Err("EAGAIN");
    }
    return Err("avcodec_send_frame failed (code " + int_to_str(send_rc) + ")");
  }
  let recv_rc = avcodec_receive_packet(codec_ctx, pkt);
  if recv_rc < 0 {
    if recv_rc == AV_ERROR_EAGAIN {
      return Err("EAGAIN");
    }
    if recv_rc == AV_ERROR_EOF {
      return Err("EOF");
    }
    return Err("avcodec_receive_packet failed (code " + int_to_str(recv_rc) + ")");
  }
  return Ok(recv_rc);
}

pub fn write_frame(ctx: FfmpegContext, pkt: FfmpegPacket) -> Result[Int, Str] {
  let rc = av_interleaved_write_frame(ctx, pkt);
  if rc < 0 {
    return Err("av_interleaved_write_frame failed (code " + int_to_str(rc) + ")");
  }
  return Ok(rc);
}

pub fn open_output(path: Str, _template_ctx: FfmpegContext) -> Result[FfmpegContext, Str]
  requires: path.len() > 0;
{
  let rc = avformat_alloc_output_context2(0, 0, 0, path);
  if rc < 0 {
    return Err("avformat_alloc_output_context2 failed (code " + int_to_str(rc) + ")");
  }
  // rc on success holds the context pointer; re-read via alloc + open fallback
  let ctx = avformat_alloc_context();
  if ctx == 0 {
    return Err("avformat_alloc_context returned null for output");
  }
  let open_rc = avformat_open_input(ctx, path, 0, 0);
  if open_rc < 0 {
    return Err("avformat_open_input for output failed (code " + int_to_str(open_rc) + ")");
  }
  return Ok(ctx);
}

// ── Resource helpers ──

pub fn alloc_packet() -> Result[FfmpegPacket, Str] {
  let pkt = av_packet_alloc();
  if pkt == 0 {
    return Err("av_packet_alloc returned null");
  }
  return Ok(pkt);
}

pub fn free_packet(pkt: FfmpegPacket) {
  av_packet_free(pkt);
}

pub fn alloc_frame() -> Result[FfmpegFrame, Str] {
  let frame = av_frame_alloc();
  if frame == 0 {
    return Err("av_frame_alloc returned null");
  }
  return Ok(frame);
}

pub fn free_frame(frame: FfmpegFrame) {
  av_frame_free(frame);
}

pub fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var val = n;
  if val < 0 { neg = true; val = -val; }
  var buf = "";
  while val > 0 {
    var digit = val % 10;
    val = val / 10;
    var ch = "";
    if digit == 0 { ch = "0"; }
    elif digit == 1 { ch = "1"; }
    elif digit == 2 { ch = "2"; }
    elif digit == 3 { ch = "3"; }
    elif digit == 4 { ch = "4"; }
    elif digit == 5 { ch = "5"; }
    elif digit == 6 { ch = "6"; }
    elif digit == 7 { ch = "7"; }
    elif digit == 8 { ch = "8"; }
    elif digit == 9 { ch = "9"; }
    buf = ch + buf;
  }
  if neg { buf = "-" + buf; }
  return buf;
}
