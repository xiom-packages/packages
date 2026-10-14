/* XIOM -- xiom.lz4 bridge helpers over the vendored lz4 v1.10.0 C API.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The 1:1 surface in src/lz4_ffi.xi calls the vendored symbols directly (the
 * vendored sources are plain C, no name mangling); this bridge supplies only
 * what XIOM cannot express on toolchain v0.64.4:
 *   * a real NULL pointer (B-23: XIOM must never materialize `null`);
 *   * string copies out of foreign const char* (B-20/B-24: XIOM never reads
 *     through a foreign pointer);
 *   * LZ4F struct construction/decoding over caller-owned byte slots (the
 *     C struct layout stays on the C side; XIOM sees documented u64 LE fields);
 *   * the LZ4F_CustomMem-by-value advanced creators (struct-by-value ABI);
 *   * one decompression loop (advancing the input pointer requires pointer
 *     arithmetic, which is confined to C per B-17).
 *
 * Slot sizes (pinned by static asserts below): frameInfo 32, preferences 56,
 * compressOptions 16, decompressOptions 16, CustomMem 32.
 */

#define LZ4F_STATIC_LINKING_ONLY
#include "../vendor/lz4/lz4frame.h"
#include "../vendor/lz4/lz4.h"

#include <stdint.h>
#include <string.h>

#if defined(_MSC_VER)
#define XLZ4_STATIC_ASSERT(cond, msg) typedef char xlz4_static_assert_##msg[(cond) ? 1 : -1]
#else
#define XLZ4_STATIC_ASSERT(cond, msg) _Static_assert(cond, #msg)
#endif

XLZ4_STATIC_ASSERT(sizeof(LZ4F_frameInfo_t) == 32, frame_info_32);
XLZ4_STATIC_ASSERT(sizeof(LZ4F_preferences_t) == 56, prefs_56);
XLZ4_STATIC_ASSERT(sizeof(LZ4F_compressOptions_t) == 16, compress_options_16);
XLZ4_STATIC_ASSERT(sizeof(LZ4F_decompressOptions_t) == 16, decompress_options_16);
XLZ4_STATIC_ASSERT(sizeof(LZ4F_CustomMem) == 32, custom_mem_32);

static void xlz4_write_u64_le(uint8_t *p, uint64_t v) {
  for (int i = 0; i < 8; ++i) p[i] = (uint8_t)((v >> (8 * i)) & 0xff);
}

void *xlz4_null(void) { return NULL; }

int32_t xlz4_version_string(uint8_t *out, int64_t cap) {
  const char *s = LZ4_versionString();
  if (s == NULL) return 0;
  const int64_t n = (int64_t)strlen(s);
  const int64_t take = (n < cap) ? n : cap;
  if (take > 0) memcpy(out, s, (size_t)take);
  return (int32_t)take;
}

int32_t xlz4f_error_name(int64_t code, uint8_t *out, int64_t cap) {
  const char *s = LZ4F_getErrorName((size_t)code);
  if (s == NULL) return 0;
  const int64_t n = (int64_t)strlen(s);
  const int64_t take = (n < cap) ? n : cap;
  if (take > 0) memcpy(out, s, (size_t)take);
  return (int32_t)take;
}

int32_t xlz4f_prefs_default(uint8_t *slot) {
  if (slot == NULL) return -1;
  LZ4F_preferences_t p;
  memset(&p, 0, sizeof(p));
  p.frameInfo.blockSizeID = LZ4F_default;
  p.frameInfo.blockMode = LZ4F_blockLinked;
  p.frameInfo.contentChecksumFlag = LZ4F_noContentChecksum;
  p.frameInfo.frameType = LZ4F_frame;
  p.frameInfo.blockChecksumFlag = LZ4F_noBlockChecksum;
  memcpy(slot, &p, sizeof(p));
  return 0;
}

int32_t xlz4f_prefs_set(uint8_t *slot, int64_t block_size_id, int64_t block_mode,
                        int64_t content_checksum, int64_t frame_type, int64_t content_size,
                        int64_t dict_id, int64_t block_checksum, int64_t compression_level,
                        int64_t auto_flush, int64_t favor_dec_speed) {
  if (slot == NULL) return -1;
  LZ4F_preferences_t p;
  memset(&p, 0, sizeof(p));
  p.frameInfo.blockSizeID = (LZ4F_blockSizeID_t)block_size_id;
  p.frameInfo.blockMode = (LZ4F_blockMode_t)block_mode;
  p.frameInfo.contentChecksumFlag = (LZ4F_contentChecksum_t)content_checksum;
  p.frameInfo.frameType = (LZ4F_frameType_t)frame_type;
  p.frameInfo.contentSize = (unsigned long long)content_size;
  p.frameInfo.dictID = (unsigned)dict_id;
  p.frameInfo.blockChecksumFlag = (LZ4F_blockChecksum_t)block_checksum;
  p.compressionLevel = (int)compression_level;
  p.autoFlush = (unsigned)auto_flush;
  p.favorDecSpeed = (unsigned)favor_dec_speed;
  memcpy(slot, &p, sizeof(p));
  return 0;
}

int32_t xlz4f_prefs_get(uint8_t *slot, uint8_t *out) {
  if (slot == NULL || out == NULL) return -1;
  LZ4F_preferences_t p;
  memcpy(&p, slot, sizeof(p));
  xlz4_write_u64_le(out + 0, (uint64_t)p.frameInfo.blockSizeID);
  xlz4_write_u64_le(out + 8, (uint64_t)p.frameInfo.blockMode);
  xlz4_write_u64_le(out + 16, (uint64_t)p.frameInfo.contentChecksumFlag);
  xlz4_write_u64_le(out + 24, (uint64_t)p.frameInfo.frameType);
  xlz4_write_u64_le(out + 32, (uint64_t)p.frameInfo.contentSize);
  xlz4_write_u64_le(out + 40, (uint64_t)p.frameInfo.dictID);
  xlz4_write_u64_le(out + 48, (uint64_t)p.frameInfo.blockChecksumFlag);
  xlz4_write_u64_le(out + 56, (uint64_t)(int64_t)p.compressionLevel);
  xlz4_write_u64_le(out + 64, (uint64_t)p.autoFlush);
  xlz4_write_u64_le(out + 72, (uint64_t)p.favorDecSpeed);
  return 0;
}

int32_t xlz4f_frame_info_default(uint8_t *slot) {
  if (slot == NULL) return -1;
  LZ4F_frameInfo_t f;
  memset(&f, 0, sizeof(f));
  f.blockSizeID = LZ4F_default;
  f.blockMode = LZ4F_blockLinked;
  f.contentChecksumFlag = LZ4F_noContentChecksum;
  f.frameType = LZ4F_frame;
  f.blockChecksumFlag = LZ4F_noBlockChecksum;
  memcpy(slot, &f, sizeof(f));
  return 0;
}

int32_t xlz4f_frame_info_get(uint8_t *slot, uint8_t *out) {
  if (slot == NULL || out == NULL) return -1;
  LZ4F_frameInfo_t f;
  memcpy(&f, slot, sizeof(f));
  xlz4_write_u64_le(out + 0, (uint64_t)f.blockSizeID);
  xlz4_write_u64_le(out + 8, (uint64_t)f.blockMode);
  xlz4_write_u64_le(out + 16, (uint64_t)f.contentChecksumFlag);
  xlz4_write_u64_le(out + 24, (uint64_t)f.frameType);
  xlz4_write_u64_le(out + 32, (uint64_t)f.contentSize);
  xlz4_write_u64_le(out + 40, (uint64_t)f.dictID);
  xlz4_write_u64_le(out + 48, (uint64_t)f.blockChecksumFlag);
  return 0;
}

int32_t xlz4f_compress_options_default(uint8_t *slot) {
  if (slot == NULL) return -1;
  LZ4F_compressOptions_t o;
  memset(&o, 0, sizeof(o));
  memcpy(slot, &o, sizeof(o));
  return 0;
}

int32_t xlz4f_compress_options_set(uint8_t *slot, int64_t stable_src) {
  if (slot == NULL) return -1;
  LZ4F_compressOptions_t o;
  memcpy(&o, slot, sizeof(o));
  o.stableSrc = (unsigned)stable_src;
  memcpy(slot, &o, sizeof(o));
  return 0;
}

int32_t xlz4f_decompress_options_default(uint8_t *slot) {
  if (slot == NULL) return -1;
  LZ4F_decompressOptions_t o;
  memset(&o, 0, sizeof(o));
  memcpy(slot, &o, sizeof(o));
  return 0;
}

int32_t xlz4f_decompress_options_set(uint8_t *slot, int64_t stable_dst, int64_t skip_checksums) {
  if (slot == NULL) return -1;
  LZ4F_decompressOptions_t o;
  memcpy(&o, slot, sizeof(o));
  o.stableDst = (unsigned)stable_dst;
  o.skipChecksums = (unsigned)skip_checksums;
  memcpy(slot, &o, sizeof(o));
  return 0;
}

int32_t xlz4f_custom_mem_default(uint8_t *slot) {
  if (slot == NULL) return -1;
  LZ4F_CustomMem m;
  memset(&m, 0, sizeof(m));
  memcpy(slot, &m, sizeof(m));
  return 0;
}

int64_t xlz4f_create_cctx_advanced(const uint8_t *mem_slot, int64_t version) {
  if (mem_slot == NULL) return 0;
  LZ4F_CustomMem m;
  memcpy(&m, mem_slot, sizeof(m));
  return (int64_t)(intptr_t)LZ4F_createCompressionContext_advanced(m, (unsigned)version);
}

int64_t xlz4f_create_dctx_advanced(const uint8_t *mem_slot, int64_t version) {
  if (mem_slot == NULL) return 0;
  LZ4F_CustomMem m;
  memcpy(&m, mem_slot, sizeof(m));
  return (int64_t)(intptr_t)LZ4F_createDecompressionContext_advanced(m, (unsigned)version);
}

int64_t xlz4f_create_cdict_advanced(const uint8_t *mem_slot, const uint8_t *dict_buffer,
                                    int64_t dict_size) {
  if (mem_slot == NULL) return 0;
  LZ4F_CustomMem m;
  memcpy(&m, mem_slot, sizeof(m));
  return (int64_t)(intptr_t)LZ4F_createCDict_advanced(m, dict_buffer, (size_t)dict_size);
}

/* One complete-frame decompression: LZ4F_decompress is looped until the frame
 * ends.  Returns the decompressed byte count, or an LZ4F error code as a
 * negative int64 (LZ4F_isError-compatible):
 *   - ERROR_dstMaxSize_tooSmall when the destination cannot make progress,
 *   - ERROR_decompressionFailed / ERROR_frameHeader_incomplete when the input
 *     ends before the frame completes (the raw API would keep returning a
 *     non-zero hint; a convenience whole-frame call reports a typed error). */
int64_t xlz4f_decompress_all(int64_t dctx, const uint8_t *src, int64_t src_size, uint8_t *dst,
                             int64_t dst_capacity) {
  if (dctx == 0 || src == NULL || dst == NULL) return -(int64_t)LZ4F_ERROR_parameter_null;
  if (src_size <= 0) return -(int64_t)LZ4F_ERROR_frameHeader_incomplete;
  LZ4F_dctx *d = (LZ4F_dctx *)(intptr_t)dctx;
  size_t src_pos = 0;
  size_t dst_pos = 0;
  size_t hint = 1;
  while (src_pos < (size_t)src_size) {
    size_t src_avail = (size_t)src_size - src_pos;
    size_t dst_avail = (size_t)dst_capacity - dst_pos;
    hint = LZ4F_decompress(d, dst + dst_pos, &dst_avail, src + src_pos, &src_avail, NULL);
    if (LZ4F_isError(hint)) return (int64_t)hint;
    if (src_avail == 0 && dst_avail == 0) return -(int64_t)LZ4F_ERROR_dstMaxSize_tooSmall;
    src_pos += src_avail;
    dst_pos += dst_avail;
    if (hint == 0) break;
  }
  if (hint != 0) {
    return -(int64_t)((dst_pos == 0) ? LZ4F_ERROR_frameHeader_incomplete
                                     : LZ4F_ERROR_decompressionFailed);
  }
  return (int64_t)dst_pos;
}
