/* XIOM -- xiom.ffmpeg: XIOM-side bridge (dynamic-loader model preserved).
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * This file is OUR code, not FFmpeg code: nothing is copied from FFmpeg and
 * nothing links against FFmpeg at build time.  It exists because the v0.64.4
 * FFI discipline (findings B-20/B-24/B-25) cannot perform two operations
 * from XIOM-owned memory safely:
 *
 *   1. packet_from_bytes -- build an AVPacket whose payload is a copy of an
 *      XIOM-owned Vec[UInt8]: the two required functions are resolved at
 *      RUNTIME via GetProcAddress on the module handles XIOM already loaded
 *      (`av_packet_alloc`, `av_packet_from_data` from libavcodec; `av_malloc`,
 *      `av_free` from libavutil).  Handles cross the ABI as int64 and are
 *      cast to pointers in C only (B-25).
 *
 *   2. frame_info -- copy the AVFrame head fields (width/height/format) into
 *      an XIOM-owned out-slot.  XIOM never reads through the foreign AVFrame
 *      pointer (B-20/B-24); it reads the owned slot byte-indexed.
 *
 *   3. 0.4.0 demux copy-outs -- format_info (nb_streams), stream_info
 *      (codecpar codec id/type + width/height + stream time base) and
 *      packet_info / packet_bytes (payload copy-out plus PTS/DTS/flags/
 *      size/pos).  Same rule: every foreign read happens in C into an
 *      XIOM-owned slot or buffer; the generation-dependent AVStream /
 *      AVCodecParameters prefix offsets are parameters selected in ffmpeg.xi
 *      from the loaded generation's packed versions.
 *
 * AVFrame head layout (public ABI, libavutil/frame.h): data[8] at 0,
 * linesize[8] at 64, extended_data at 96, width at 104, height at 108,
 * nb_samples at 112, format at 116.  The prefix has been unchanged across
 * FFmpeg 4.x-8.x; the conformance suite verifies the decoded width/height
 * against the IVF header of the fixture, which fails loudly on any drift.
 */

#include <windows.h>
#include <stdint.h>
#include <string.h>

#define FFMPEG_BRIDGE_PADDING 64 /* AV_INPUT_BUFFER_PADDING_SIZE (4.x-8.x) */

typedef void* (__cdecl *ffmpeg_packet_alloc_fn)(void);
typedef int (__cdecl *ffmpeg_packet_from_data_fn)(void* pkt, uint8_t* data, int size);
typedef void (__cdecl *ffmpeg_packet_free_fn)(void** pkt);
typedef void* (__cdecl *ffmpeg_malloc_fn)(size_t size);
typedef void (__cdecl *ffmpeg_free_fn)(void* ptr);

/* Build an AVPacket carrying a copy of `src[offset .. offset+size)`.
 * Returns the AVPacket pointer as int64, or 0 on any failure.
 * The packet is freed by the caller with av_packet_free (via XIOM's
 * `ffmpeg_packet_free`), which also releases the av_malloc'ed payload. */
int64_t __cdecl ffmpeg_bridge_packet_from_bytes(
    int64_t codec_mod, int64_t util_mod,
    const uint8_t* src, int64_t offset, int64_t size)
{
  HMODULE h_codec;
  HMODULE h_util;
  ffmpeg_packet_alloc_fn p_alloc;
  ffmpeg_packet_from_data_fn p_from_data;
  ffmpeg_packet_free_fn p_free;
  ffmpeg_malloc_fn p_malloc;
  ffmpeg_free_fn p_av_free;
  void* pkt;
  uint8_t* buf;
  int rc;

  if (src == 0 || offset < 0 || size <= 0 || size > 0x7FFFFF00) return 0;
  h_codec = (HMODULE)(uintptr_t)codec_mod;
  h_util = (HMODULE)(uintptr_t)util_mod;
  if (h_codec == 0 || h_util == 0) return 0;

  p_alloc = (ffmpeg_packet_alloc_fn)(void*)GetProcAddress(h_codec, "av_packet_alloc");
  p_from_data = (ffmpeg_packet_from_data_fn)(void*)GetProcAddress(h_codec, "av_packet_from_data");
  p_free = (ffmpeg_packet_free_fn)(void*)GetProcAddress(h_codec, "av_packet_free");
  p_malloc = (ffmpeg_malloc_fn)(void*)GetProcAddress(h_util, "av_malloc");
  p_av_free = (ffmpeg_free_fn)(void*)GetProcAddress(h_util, "av_free");
  if (!p_alloc || !p_from_data || !p_free || !p_malloc || !p_av_free) return 0;

  pkt = p_alloc();
  if (pkt == 0) return 0;
  buf = (uint8_t*)p_malloc((size_t)size + FFMPEG_BRIDGE_PADDING);
  if (buf == 0) {
    p_free(&pkt);
    return 0;
  }
  memcpy(buf, src + (size_t)offset, (size_t)size);
  memset(buf + (size_t)size, 0, FFMPEG_BRIDGE_PADDING);
  rc = p_from_data(pkt, buf, (int)size);
  if (rc < 0) {
    p_av_free(buf);
    p_free(&pkt);
    return 0;
  }
  return (int64_t)(uintptr_t)pkt;
}

/* Copy AVFrame head fields into an XIOM-owned 12-byte out-slot, little-endian:
 * [0..3]=width, [4..7]=height, [8..11]=format (AVPixelFormat).
 * Returns 0 on success, -1 on bad arguments, -2 when the head values are
 * implausible (negative), which would indicate ABI drift. */
int32_t __cdecl ffmpeg_bridge_frame_info(int64_t frame, uint8_t* out_slot)
{
  uint8_t* base;
  int32_t width;
  int32_t height;
  int32_t format;

  if (frame == 0 || out_slot == 0) return -1;
  base = (uint8_t*)(uintptr_t)frame;

  memcpy(&width, base + 104, 4);
  memcpy(&height, base + 108, 4);
  memcpy(&format, base + 116, 4);
  if (width < 0 || height < 0 || format < 0) return -2;

  memcpy(out_slot + 0, &width, 4);
  memcpy(out_slot + 4, &height, 4);
  memcpy(out_slot + 8, &format, 4);
  return 0;
}

/* ---------------------------------------------------------------------------
 * 0.4.0 container demux copy-outs (same discipline as frame_info: the C
 * bridge performs every read through a foreign pointer; XIOM only reads its
 * own out-slots byte-indexed, B-20/B-24).
 *
 * ABI facts encoded here (public headers at the pinned oracle commit; see
 * PROVENANCE.md -- interface layout, not copied code):
 *
 *   AVFormatContext (x64): av_class 0, iformat 8, oformat 16, priv_data 24,
 *     pb 32, ctx_flags 40, nb_streams 44 (u32), streams 48 (AVStream**).
 *     Unchanged across lavf 58-62 (FFmpeg 4.x-8.x).
 *   AVStream (x64): `stream_base` prefix (8 when AVStream.av_class exists --
 *     added at lavf 60 / FFmpeg 6.0 -- else 0), then index +0, id +4,
 *     codecpar +8, priv_data +16, time_base +24 (num) / +28 (den), all
 *     relative to `stream_base`.
 *   AVCodecParameters (x64): codec_type 0, codec_id 4; width at `wh_off`
 *     (72 once lavc 61 / FFmpeg 7.0 inserted coded_side_data before
 *     `format`; 56 on lavc 60.x and earlier, where coded_side_data -- added
 *     at lavc 60.30 -- sat at the struct end), height at `wh_off` + 4.
 *   AVPacket (x64): buf 0, pts 8, dts 16, data 24, size 32 (int),
 *     stream_index 36, flags 40, side_data 48, side_data_elems 56,
 *     duration 64, pos 72.  Prefix stable across lavc 58-62.
 *
 * The generation-dependent values (stream_base, wh_off) are selected in
 * ffmpeg.xi from the loaded generation's packed versions and verified every
 * run by the conformance suite against the fixture's known header (64x48,
 * time_base 1/4, the AV1 codec id -- which the suite resolves by codec NAME,
 * since the numeric AVCodecID shifts across FFmpeg majors: 226 on lavc 60.x,
 * 225 on lavc 61.x); any drift fails loudly.
 * ------------------------------------------------------------------------ */

/* AVFormatContext -> nb_streams.  Out-slot: [0..3]=nb_streams (u32).
 * Returns 0 on success, -1 on bad arguments, -2 on implausible count. */
int32_t __cdecl ffmpeg_bridge_format_info(int64_t fmt_ctx, uint8_t* out_slot)
{
  uint8_t* base;
  uint32_t nb_streams;

  if (fmt_ctx == 0 || out_slot == 0) return -1;
  base = (uint8_t*)(uintptr_t)fmt_ctx;

  memcpy(&nb_streams, base + 44, 4);
  if (nb_streams == 0 || nb_streams > 0x10000) return -2;

  memcpy(out_slot, &nb_streams, 4);
  return 0;
}

/* AVFormatContext.streams[index] -> codecpar head + stream time base.
 * Out-slot (28 bytes, little-endian): [0..3]=codec_type, [4..7]=codec_id,
 * [8..11]=width, [12..15]=height, [16..19]=time_base.num,
 * [20..23]=time_base.den, [24..27]=stream index.
 * Returns 0 on success; -1 bad arguments; -2/-3/-4 null traversal;
 * -5 implausible field values (ABI drift indicator). */
int32_t __cdecl ffmpeg_bridge_stream_info(int64_t fmt_ctx, int64_t index,
                                          int64_t stream_base, int64_t wh_off,
                                          uint8_t* out_slot)
{
  uint8_t* fmt;
  uint8_t* streams;
  uint8_t* st;
  uint8_t* par;
  int32_t codec_type;
  int32_t codec_id;
  int32_t width;
  int32_t height;
  int32_t tb_num;
  int32_t tb_den;
  int32_t sidx;

  if (fmt_ctx == 0 || out_slot == 0) return -1;
  if (index < 0 || stream_base < 0 || wh_off < 0) return -1;
  fmt = (uint8_t*)(uintptr_t)fmt_ctx;

  memcpy(&streams, fmt + 48, 8);
  if (streams == 0) return -2;
  memcpy(&st, streams + (size_t)index * 8, 8);
  if (st == 0) return -3;
  st += (size_t)stream_base;

  memcpy(&sidx, st + 0, 4);
  memcpy(&par, st + 8, 8);
  memcpy(&tb_num, st + 24, 4);
  memcpy(&tb_den, st + 28, 4);
  if (par == 0) return -4;

  memcpy(&codec_type, par + 0, 4);
  memcpy(&codec_id, par + 4, 4);
  memcpy(&width, par + (size_t)wh_off, 4);
  memcpy(&height, par + (size_t)wh_off + 4, 4);
  if (codec_type < -1 || codec_type > 6 || codec_id < 0) return -5;
  if (width < 0 || height < 0) return -5;

  memcpy(out_slot + 0, &codec_type, 4);
  memcpy(out_slot + 4, &codec_id, 4);
  memcpy(out_slot + 8, &width, 4);
  memcpy(out_slot + 12, &height, 4);
  memcpy(out_slot + 16, &tb_num, 4);
  memcpy(out_slot + 20, &tb_den, 4);
  memcpy(out_slot + 24, &sidx, 4);
  return 0;
}

/* AVPacket head -> metadata.  Out-slot (48 bytes, little-endian):
 * [0..3]=stream_index, [4..7]=flags, [8..15]=size (widened int64),
 * [16..23]=pts, [24..31]=dts, [32..39]=duration, [40..47]=pos.
 * Returns 0 on success, -1 on bad arguments, -2 on implausible values. */
int32_t __cdecl ffmpeg_bridge_packet_info(int64_t pkt, uint8_t* out_slot)
{
  uint8_t* base;
  int32_t size;
  int32_t stream_index;
  int32_t flags;
  int64_t pts;
  int64_t dts;
  int64_t duration;
  int64_t pos;
  int64_t size64;

  if (pkt == 0 || out_slot == 0) return -1;
  base = (uint8_t*)(uintptr_t)pkt;

  memcpy(&pts, base + 8, 8);
  memcpy(&dts, base + 16, 8);
  memcpy(&size, base + 32, 4);
  memcpy(&stream_index, base + 36, 4);
  memcpy(&flags, base + 40, 4);
  memcpy(&duration, base + 64, 8);
  memcpy(&pos, base + 72, 8);
  if (size < 0 || stream_index < 0 || flags < 0) return -2;

  size64 = (int64_t)size;
  memcpy(out_slot + 0, &stream_index, 4);
  memcpy(out_slot + 4, &flags, 4);
  memcpy(out_slot + 8, &size64, 8);
  memcpy(out_slot + 16, &pts, 8);
  memcpy(out_slot + 24, &dts, 8);
  memcpy(out_slot + 32, &duration, 8);
  memcpy(out_slot + 40, &pos, 8);
  return 0;
}

/* Copy an AVPacket's payload into an XIOM-owned buffer of capacity `cap`.
 * Returns the copied size (> 0), -1 on bad arguments/empty payload, -2 when
 * the payload does not fit the caller-provided capacity. */
int32_t __cdecl ffmpeg_bridge_packet_bytes(int64_t pkt, uint8_t* dst, int64_t cap)
{
  uint8_t* base;
  uint8_t* data;
  int32_t size;

  if (pkt == 0 || dst == 0 || cap <= 0) return -1;
  base = (uint8_t*)(uintptr_t)pkt;

  memcpy(&data, base + 24, 8);
  memcpy(&size, base + 32, 4);
  if (data == 0 || size <= 0) return -1;
  if ((int64_t)size > cap) return -2;

  memcpy(dst, data, (size_t)size);
  return size;
}
