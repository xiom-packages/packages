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
