/* xiom.opus -- C bridge over the vendored libopus v1.6.1 (flat tree).
 *
 * MIT OR Apache-2.0 (this file only), XIOM Authors.  The vendored upstream
 * sources under vendor/opus are BSD-3-Clause (see vendor/COPYING).
 *
 * ABI contract (generated in src/opus_abi_protos.h; discipline B-11..B-26):
 *   - handles cross as int64_t and are cast to their pointer type HERE;
 *     XIOM never casts a pointer (B-25).  A handle==0 always returns
 *     OPUS_BAD_ARG / OPUS_ALLOC_FAIL instead of dereferencing.
 *   - byte buffers cross as XIOM-owned Vec[UInt8] pointers: the bridge reads
 *     inputs and writes outputs; XIOM reads owned slots byte-indexed (B-20).
 *   - scalar out-params get a dedicated caller-owned 4-byte slot written
 *     little-endian by put_i32 (one slot per out-param, B-11/B-16/B-17).
 *   - variadic ctl functions are exposed as _set (request, int value) and
 *     _get (request, slot) pairs; no varargs cross the boundary.
 *   - string-returning functions COPY into a caller-owned slot and return
 *     the byte count (no foreign pointer is ever read from XIOM).
 *   - every entry point returns int64_t so negative opus error codes keep
 *     their sign (no narrow-return widening ambiguity).
 *
 * Buffer capacities are caller-provided and validated where upstream does
 * not (packet_parse frame arrays, surround mapping, string copies).
 */

/* Consumers of a CUSTOM_MODES-build must define it before including
 * opus_custom.h to see the custom-mode declarations (upstream rule). */
#define CUSTOM_MODES 1

#include "opus_abi_protos.h"

#include "../vendor/opus/opus.h"
#include "../vendor/opus/opus_multistream.h"
#include "../vendor/opus/opus_custom.h"
#include "../vendor/opus/opus_projection.h"

#include <stdint.h>
#include <string.h>

/* Little-endian 4-byte scalar into a caller-owned slot. */
static void put_i32(unsigned char* slot, int32_t v)
{
  uint32_t u = (uint32_t)v;
  slot[0] = (unsigned char)(u & 0xFF);
  slot[1] = (unsigned char)((u >> 8) & 0xFF);
  slot[2] = (unsigned char)((u >> 16) & 0xFF);
  slot[3] = (unsigned char)((u >> 24) & 0xFF);
}

/* Copy a NUL-terminated C string into a caller-owned slot; returns the
 * number of bytes copied (NUL excluded, truncated to capacity). */
static int64_t copy_cstr(const char* s, unsigned char* out, int32_t capacity)
{
  int64_t n = 0;
  if (s == 0 || out == 0 || capacity <= 0) {
    return 0;
  }
  while (s[n] != 0 && n < (int64_t)capacity) {
    out[n] = (unsigned char)s[n];
    n = n + 1;
  }
  return n;
}

/* ======================================================================== */
/* opus.h -- encoder                                                        */
/* ======================================================================== */

int64_t xo_encoder_get_size(int32_t p0)
{
  return (int64_t)opus_encoder_get_size((int)p0);
}

int64_t xo_encoder_create(int32_t p0, int32_t p1, int32_t p2, unsigned char* p3)
{
  int err = 0;
  OpusEncoder* st = opus_encoder_create((opus_int32)p0, (int)p1, (int)p2, &err);
  put_i32(p3, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_encoder_init(unsigned char* mem, int32_t mem_capacity, int32_t Fs, int32_t channels,
                        int32_t application, unsigned char* err_out)
{
  int rc;
  int64_t need = (int64_t)opus_encoder_get_size((int)channels);
  if (mem == 0 || need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_encoder_init((OpusEncoder*)mem, (opus_int32)Fs, (int)channels, (int)application);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_encode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_encode((OpusEncoder*)(intptr_t)p0, (const opus_int16*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_encode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_encode24((OpusEncoder*)(intptr_t)p0, (const opus_int32*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_encode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_encode_float((OpusEncoder*)(intptr_t)p0, (const float*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_encoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_encoder_destroy((OpusEncoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_encoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_encoder_ctl((OpusEncoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_encoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_encoder_ctl((OpusEncoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

/* Companion for OPUS_SET_DNN_BLOB(data, len): the value arguments are a
 * pointer + length, which the generic _set (int value) shape cannot carry.
 * In the default build (no USE_WEIGHTS_FILE) upstream returns OPUS_BAD_ARG;
 * the entry point is bound so a DRED-enabled build drops in unchanged. */
int64_t xo_encoder_ctl_set_dnn_blob(int64_t enc, const unsigned char* blob, int32_t size)
{
  if (enc == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_encoder_ctl((OpusEncoder*)(intptr_t)enc, OPUS_SET_DNN_BLOB_REQUEST,
                                   (const void*)blob, (opus_int32)size);
}

/* ======================================================================== */
/* opus.h -- decoder                                                        */
/* ======================================================================== */

int64_t xo_decoder_get_size(int32_t p0)
{
  return (int64_t)opus_decoder_get_size((int)p0);
}

int64_t xo_decoder_create(int32_t p0, int32_t p1, unsigned char* p2)
{
  int err = 0;
  OpusDecoder* st = opus_decoder_create((opus_int32)p0, (int)p1, &err);
  put_i32(p2, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_decoder_init(unsigned char* mem, int32_t mem_capacity, int32_t Fs, int32_t channels,
                        unsigned char* err_out)
{
  int rc;
  int64_t need = (int64_t)opus_decoder_get_size((int)channels);
  if (mem == 0 || need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_decoder_init((OpusDecoder*)mem, (opus_int32)Fs, (int)channels);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_decode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decode((OpusDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (opus_int16*)p3, (int)p4, (int)p5);
}

int64_t xo_decode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decode24((OpusDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (opus_int32*)p3, (int)p4, (int)p5);
}

int64_t xo_decode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decode_float((OpusDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (float*)p3, (int)p4, (int)p5);
}

int64_t xo_decoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_decoder_destroy((OpusDecoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_decoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decoder_ctl((OpusDecoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_decoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_decoder_ctl((OpusDecoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

/* ======================================================================== */
/* opus.h -- DRED (present in the default build; OPUS_UNIMPLEMENTED without */
/* ENABLE_DRED, which upstream defaults OFF)                                */
/* ======================================================================== */

int64_t xo_dred_decoder_get_size(void)
{
  return (int64_t)opus_dred_decoder_get_size();
}

int64_t xo_dred_decoder_create(unsigned char* p0)
{
  int err = 0;
  OpusDREDDecoder* st = opus_dred_decoder_create(&err);
  put_i32(p0, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_dred_decoder_init(unsigned char* mem, int32_t mem_capacity, unsigned char* err_out)
{
  int rc;
  int64_t need = (int64_t)opus_dred_decoder_get_size();
  if (mem == 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_dred_decoder_init((OpusDREDDecoder*)mem);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_dred_decoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_dred_decoder_destroy((OpusDREDDecoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_dred_decoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_dred_decoder_ctl((OpusDREDDecoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_dred_decoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_dred_decoder_ctl((OpusDREDDecoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

int64_t xo_dred_get_size(void)
{
  return (int64_t)opus_dred_get_size();
}

int64_t xo_dred_alloc(unsigned char* p0)
{
  int err = 0;
  OpusDRED* st = opus_dred_alloc(&err);
  put_i32(p0, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_dred_free(int64_t p0)
{
  if (p0 != 0) {
    opus_dred_free((OpusDRED*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_dred_parse(int64_t p0, int64_t p1, const unsigned char* p2, int32_t p3, int32_t p4, int32_t p5, unsigned char* p6, int32_t p7)
{
  int dred_end = 0;
  int rc;
  if (p0 == 0 || p1 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_dred_parse((OpusDREDDecoder*)(intptr_t)p0, (OpusDRED*)(intptr_t)p1, p2, (opus_int32)p3,
                       (opus_int32)p4, (opus_int32)p5, &dred_end, (int)p7);
  put_i32(p6, (int32_t)dred_end);
  return (int64_t)rc;
}

int64_t xo_dred_process(int64_t p0, int64_t p1, int64_t p2)
{
  if (p0 == 0 || p1 == 0 || p2 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_dred_process((OpusDREDDecoder*)(intptr_t)p0, (const OpusDRED*)(intptr_t)p1, (OpusDRED*)(intptr_t)p2);
}

int64_t xo_decoder_dred_decode(int64_t p0, int64_t p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0 || p1 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decoder_dred_decode((OpusDecoder*)(intptr_t)p0, (const OpusDRED*)(intptr_t)p1, (opus_int32)p2, (opus_int16*)p3, (opus_int32)p4);
}

int64_t xo_decoder_dred_decode24(int64_t p0, int64_t p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0 || p1 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decoder_dred_decode24((OpusDecoder*)(intptr_t)p0, (const OpusDRED*)(intptr_t)p1, (opus_int32)p2, (opus_int32*)p3, (opus_int32)p4);
}

int64_t xo_decoder_dred_decode_float(int64_t p0, int64_t p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0 || p1 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decoder_dred_decode_float((OpusDecoder*)(intptr_t)p0, (const OpusDRED*)(intptr_t)p1, (opus_int32)p2, (float*)p3, (opus_int32)p4);
}

/* ======================================================================== */
/* opus.h -- packet parsing and helpers                                     */
/* ======================================================================== */

int64_t xo_packet_parse(const unsigned char* p0, int32_t p1, unsigned char* toc_out,
                        unsigned char* sizes_out, unsigned char* offsets_out,
                        int32_t out_capacity, unsigned char* payload_offset_out)
{
  const unsigned char* frames[48];
  opus_int16 size[48];
  unsigned char toc = 0;
  int payload_offset = 0;
  int nb;
  int i;
  int n;

  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  nb = opus_packet_parse(p0, (opus_int32)p1, &toc, frames, size, &payload_offset);
  if (toc_out != 0) {
    toc_out[0] = toc;
  }
  if (payload_offset_out != 0) {
    put_i32(payload_offset_out, (int32_t)payload_offset);
  }
  if (nb > 0 && sizes_out != 0 && offsets_out != 0 && out_capacity > 0) {
    n = nb < out_capacity ? nb : out_capacity;
    for (i = 0; i < n; ++i) {
      put_i32(sizes_out + (i * 4), (int32_t)size[i]);
      put_i32(offsets_out + (i * 4), (int32_t)(frames[i] - p0));
    }
  }
  return (int64_t)nb;
}

int64_t xo_packet_get_bandwidth(const unsigned char* p0)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_get_bandwidth(p0);
}

int64_t xo_packet_get_samples_per_frame(const unsigned char* p0, int32_t p1)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_get_samples_per_frame(p0, (opus_int32)p1);
}

int64_t xo_packet_get_nb_channels(const unsigned char* p0)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_get_nb_channels(p0);
}

int64_t xo_packet_get_nb_frames(const unsigned char* p0, int32_t p1)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_get_nb_frames(p0, (opus_int32)p1);
}

int64_t xo_packet_get_nb_samples(const unsigned char* p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_get_nb_samples(p0, (opus_int32)p1, (opus_int32)p2);
}

int64_t xo_packet_has_lbrr(const unsigned char* p0, int32_t p1)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_has_lbrr(p0, (opus_int32)p1);
}

int64_t xo_decoder_get_nb_samples(int64_t p0, const unsigned char* p1, int32_t p2)
{
  if (p0 == 0 || p1 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_decoder_get_nb_samples((const OpusDecoder*)(intptr_t)p0, p1, (opus_int32)p2);
}

int64_t xo_pcm_soft_clip(unsigned char* p0, int32_t p1, int32_t p2, unsigned char* p3)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  opus_pcm_soft_clip((float*)p0, (int)p1, (int)p2, (float*)p3);
  return 0;
}

/* ======================================================================== */
/* opus.h -- repacketizer                                                   */
/* ======================================================================== */

int64_t xo_repacketizer_get_size(void)
{
  return (int64_t)opus_repacketizer_get_size();
}

int64_t xo_repacketizer_init(unsigned char* mem, int32_t mem_capacity, unsigned char* err_out)
{
  int64_t need = (int64_t)opus_repacketizer_get_size();
  if (mem == 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  opus_repacketizer_init((OpusRepacketizer*)mem);
  put_i32(err_out, (int32_t)OPUS_OK);
  return (int64_t)(intptr_t)mem;
}

int64_t xo_repacketizer_create(void)
{
  return (int64_t)(intptr_t)opus_repacketizer_create();
}

int64_t xo_repacketizer_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_repacketizer_destroy((OpusRepacketizer*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_repacketizer_cat(int64_t p0, const unsigned char* p1, int32_t p2)
{
  if (p0 == 0 || p1 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_repacketizer_cat((OpusRepacketizer*)(intptr_t)p0, p1, (opus_int32)p2);
}

int64_t xo_repacketizer_out_range(int64_t p0, int32_t p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_repacketizer_out_range((OpusRepacketizer*)(intptr_t)p0, (int)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_repacketizer_get_nb_frames(int64_t p0)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_repacketizer_get_nb_frames((OpusRepacketizer*)(intptr_t)p0);
}

int64_t xo_repacketizer_out(int64_t p0, unsigned char* p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_repacketizer_out((OpusRepacketizer*)(intptr_t)p0, p1, (opus_int32)p2);
}

int64_t xo_packet_pad(unsigned char* p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_pad(p0, (opus_int32)p1, (opus_int32)p2);
}

int64_t xo_packet_unpad(unsigned char* p0, int32_t p1)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_packet_unpad(p0, (opus_int32)p1);
}

int64_t xo_multistream_packet_pad(unsigned char* p0, int32_t p1, int32_t p2, int32_t p3)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_packet_pad(p0, (opus_int32)p1, (opus_int32)p2, (int)p3);
}

int64_t xo_multistream_packet_unpad(unsigned char* p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_packet_unpad(p0, (opus_int32)p1, (int)p2);
}

/* ======================================================================== */
/* opus_defines.h -- error strings and version                              */
/* ======================================================================== */

int64_t xo_strerror(int32_t p0, unsigned char* p1, int32_t p2)
{
  return copy_cstr(opus_strerror((int)p0), p1, p2);
}

int64_t xo_get_version_string(unsigned char* p0, int32_t p1)
{
  return copy_cstr(opus_get_version_string(), p0, p1);
}

/* ======================================================================== */
/* opus_multistream.h                                                       */
/* ======================================================================== */

int64_t xo_multistream_encoder_get_size(int32_t p0, int32_t p1)
{
  return (int64_t)opus_multistream_encoder_get_size((int)p0, (int)p1);
}

int64_t xo_multistream_surround_encoder_get_size(int32_t p0, int32_t p1)
{
  return (int64_t)opus_multistream_surround_encoder_get_size((int)p0, (int)p1);
}

int64_t xo_multistream_encoder_create(int32_t p0, int32_t p1, int32_t p2, int32_t p3,
                                      const unsigned char* p4, int32_t p5, unsigned char* p6)
{
  int err = 0;
  OpusMSEncoder* st;
  if (p4 == 0) {
    put_i32(p6, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  st = opus_multistream_encoder_create((opus_int32)p0, (int)p1, (int)p2, (int)p3, p4, (int)p5, &err);
  put_i32(p6, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_multistream_surround_encoder_create(int32_t Fs, int32_t channels, int32_t mapping_family,
                                               unsigned char* streams_out, unsigned char* coupled_streams_out,
                                               unsigned char* mapping_out, int32_t mapping_capacity,
                                               int32_t application, unsigned char* err_out)
{
  int streams = 0;
  int coupled_streams = 0;
  int err = 0;
  OpusMSEncoder* st;
  if (mapping_out == 0 || mapping_capacity < channels) {
    put_i32(streams_out, 0);
    put_i32(coupled_streams_out, 0);
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  st = opus_multistream_surround_encoder_create((opus_int32)Fs, (int)channels, (int)mapping_family,
                                                &streams, &coupled_streams, mapping_out, (int)application, &err);
  put_i32(streams_out, (int32_t)streams);
  put_i32(coupled_streams_out, (int32_t)coupled_streams);
  put_i32(err_out, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_multistream_encoder_init(unsigned char* mem, int32_t mem_capacity, int32_t Fs, int32_t channels,
                                    int32_t streams, int32_t coupled_streams, const unsigned char* mapping,
                                    int32_t application, unsigned char* err_out)
{
  int rc;
  int64_t need;
  if (mem == 0 || mapping == 0) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  need = (int64_t)opus_multistream_encoder_get_size((int)streams, (int)coupled_streams);
  if (need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_multistream_encoder_init((OpusMSEncoder*)mem, (opus_int32)Fs, (int)channels, (int)streams,
                                     (int)coupled_streams, mapping, (int)application);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_multistream_surround_encoder_init(unsigned char* mem, int32_t mem_capacity, int32_t Fs, int32_t channels,
                                             int32_t mapping_family, unsigned char* streams_out,
                                             unsigned char* coupled_streams_out, unsigned char* mapping_out,
                                             int32_t mapping_capacity, int32_t application, unsigned char* err_out)
{
  int streams = 0;
  int coupled_streams = 0;
  int rc;
  int64_t need;
  if (mem == 0 || mapping_out == 0 || mapping_capacity < channels) {
    put_i32(streams_out, 0);
    put_i32(coupled_streams_out, 0);
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  need = (int64_t)opus_multistream_surround_encoder_get_size((int)channels, (int)mapping_family);
  if (need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(streams_out, 0);
    put_i32(coupled_streams_out, 0);
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_multistream_surround_encoder_init((OpusMSEncoder*)mem, (opus_int32)Fs, (int)channels,
                                              (int)mapping_family, &streams, &coupled_streams, mapping_out,
                                              (int)application);
  put_i32(streams_out, (int32_t)streams);
  put_i32(coupled_streams_out, (int32_t)coupled_streams);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_multistream_encode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_encode((OpusMSEncoder*)(intptr_t)p0, (const opus_int16*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_multistream_encode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_encode24((OpusMSEncoder*)(intptr_t)p0, (const opus_int32*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_multistream_encode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_encode_float((OpusMSEncoder*)(intptr_t)p0, (const float*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_multistream_encoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_multistream_encoder_destroy((OpusMSEncoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_multistream_encoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_encoder_ctl((OpusMSEncoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_multistream_encoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_multistream_encoder_ctl((OpusMSEncoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

/* Companion for OPUS_MULTISTREAM_GET_ENCODER_STATE(stream_index, &state):
 * writes the sub-encoder handle as int64 little-endian into the owned slot. */
int64_t xo_multistream_encoder_ctl_get_state(int64_t st, int32_t stream_index, unsigned char* out_slot)
{
  OpusEncoder* sub = 0;
  int rc;
  int64_t bits;
  if (st == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_multistream_encoder_ctl((OpusMSEncoder*)(intptr_t)st,
                                    OPUS_MULTISTREAM_GET_ENCODER_STATE_REQUEST, (opus_int32)stream_index, &sub);
  bits = (int64_t)(intptr_t)sub;
  out_slot[0] = (unsigned char)(bits & 0xFF);
  out_slot[1] = (unsigned char)((bits >> 8) & 0xFF);
  out_slot[2] = (unsigned char)((bits >> 16) & 0xFF);
  out_slot[3] = (unsigned char)((bits >> 24) & 0xFF);
  out_slot[4] = (unsigned char)((bits >> 32) & 0xFF);
  out_slot[5] = (unsigned char)((bits >> 40) & 0xFF);
  out_slot[6] = (unsigned char)((bits >> 48) & 0xFF);
  out_slot[7] = (unsigned char)((bits >> 56) & 0xFF);
  return (int64_t)rc;
}

int64_t xo_multistream_decoder_get_size(int32_t p0, int32_t p1)
{
  return (int64_t)opus_multistream_decoder_get_size((int)p0, (int)p1);
}

int64_t xo_multistream_decoder_create(int32_t p0, int32_t p1, int32_t p2, int32_t p3,
                                      const unsigned char* p4, unsigned char* p5)
{
  int err = 0;
  OpusMSDecoder* st;
  if (p4 == 0) {
    put_i32(p5, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  st = opus_multistream_decoder_create((opus_int32)p0, (int)p1, (int)p2, (int)p3, p4, &err);
  put_i32(p5, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_multistream_decoder_init(unsigned char* mem, int32_t mem_capacity, int32_t Fs, int32_t channels,
                                    int32_t streams, int32_t coupled_streams, const unsigned char* mapping,
                                    unsigned char* err_out)
{
  int rc;
  int64_t need;
  if (mem == 0 || mapping == 0) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  need = (int64_t)opus_multistream_decoder_get_size((int)streams, (int)coupled_streams);
  if (need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_multistream_decoder_init((OpusMSDecoder*)mem, (opus_int32)Fs, (int)channels, (int)streams,
                                     (int)coupled_streams, mapping);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_multistream_decode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_decode((OpusMSDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (opus_int16*)p3, (int)p4, (int)p5);
}

int64_t xo_multistream_decode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_decode24((OpusMSDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (opus_int32*)p3, (int)p4, (int)p5);
}

int64_t xo_multistream_decode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_decode_float((OpusMSDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (float*)p3, (int)p4, (int)p5);
}

int64_t xo_multistream_decoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_multistream_decoder_destroy((OpusMSDecoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_multistream_decoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_multistream_decoder_ctl((OpusMSDecoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_multistream_decoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_multistream_decoder_ctl((OpusMSDecoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

/* Companion for OPUS_MULTISTREAM_GET_DECODER_STATE(stream_index, &state). */
int64_t xo_multistream_decoder_ctl_get_state(int64_t st, int32_t stream_index, unsigned char* out_slot)
{
  OpusDecoder* sub = 0;
  int rc;
  int64_t bits;
  if (st == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_multistream_decoder_ctl((OpusMSDecoder*)(intptr_t)st,
                                    OPUS_MULTISTREAM_GET_DECODER_STATE_REQUEST, (opus_int32)stream_index, &sub);
  bits = (int64_t)(intptr_t)sub;
  out_slot[0] = (unsigned char)(bits & 0xFF);
  out_slot[1] = (unsigned char)((bits >> 8) & 0xFF);
  out_slot[2] = (unsigned char)((bits >> 16) & 0xFF);
  out_slot[3] = (unsigned char)((bits >> 24) & 0xFF);
  out_slot[4] = (unsigned char)((bits >> 32) & 0xFF);
  out_slot[5] = (unsigned char)((bits >> 40) & 0xFF);
  out_slot[6] = (unsigned char)((bits >> 48) & 0xFF);
  out_slot[7] = (unsigned char)((bits >> 56) & 0xFF);
  return (int64_t)rc;
}

/* ======================================================================== */
/* opus_custom.h (built with CUSTOM_MODES, matching an upstream            */
/* --enable-custom-modes build)                                             */
/* ======================================================================== */

int64_t xo_custom_mode_create(int32_t p0, int32_t p1, unsigned char* p2)
{
  int err = 0;
  OpusCustomMode* mode = opus_custom_mode_create((opus_int32)p0, (int)p1, &err);
  put_i32(p2, (int32_t)err);
  return (int64_t)(intptr_t)mode;
}

int64_t xo_custom_mode_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_custom_mode_destroy((OpusCustomMode*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_custom_encoder_get_size(int64_t p0, int32_t p1)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_encoder_get_size((const OpusCustomMode*)(intptr_t)p0, (int)p1);
}

int64_t xo_custom_encoder_init(unsigned char* mem, int32_t mem_capacity, int64_t mode, int32_t channels,
                               unsigned char* err_out)
{
  int rc;
  int64_t need;
  if (mem == 0 || mode == 0) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  need = (int64_t)opus_custom_encoder_get_size((const OpusCustomMode*)(intptr_t)mode, (int)channels);
  if (need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_custom_encoder_init((OpusCustomEncoder*)mem, (const OpusCustomMode*)(intptr_t)mode, (int)channels);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_custom_encoder_create(int64_t p0, int32_t p1, unsigned char* p2)
{
  int err = 0;
  OpusCustomEncoder* st;
  if (p0 == 0) {
    put_i32(p2, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  st = opus_custom_encoder_create((const OpusCustomMode*)(intptr_t)p0, (int)p1, &err);
  put_i32(p2, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_custom_encoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_custom_encoder_destroy((OpusCustomEncoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_custom_encode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_encode_float((OpusCustomEncoder*)(intptr_t)p0, (const float*)p1, (int)p2, p3, (int)p4);
}

int64_t xo_custom_encode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_encode((OpusCustomEncoder*)(intptr_t)p0, (const opus_int16*)p1, (int)p2, p3, (int)p4);
}

int64_t xo_custom_encode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_encode24((OpusCustomEncoder*)(intptr_t)p0, (const opus_int32*)p1, (int)p2, p3, (int)p4);
}

int64_t xo_custom_encoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_encoder_ctl((OpusCustomEncoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_custom_encoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_custom_encoder_ctl((OpusCustomEncoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

int64_t xo_custom_decoder_get_size(int64_t p0, int32_t p1)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_decoder_get_size((const OpusCustomMode*)(intptr_t)p0, (int)p1);
}

int64_t xo_custom_decoder_init(unsigned char* mem, int32_t mem_capacity, int64_t mode, int32_t channels,
                               unsigned char* err_out)
{
  int rc;
  int64_t need;
  if (mem == 0 || mode == 0) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  need = (int64_t)opus_custom_decoder_get_size((const OpusCustomMode*)(intptr_t)mode, (int)channels);
  if (need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_custom_decoder_init((OpusCustomDecoder*)mem, (const OpusCustomMode*)(intptr_t)mode, (int)channels);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_custom_decoder_create(int64_t p0, int32_t p1, unsigned char* p2)
{
  int err = 0;
  OpusCustomDecoder* st;
  if (p0 == 0) {
    put_i32(p2, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  st = opus_custom_decoder_create((const OpusCustomMode*)(intptr_t)p0, (int)p1, &err);
  put_i32(p2, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_custom_decoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_custom_decoder_destroy((OpusCustomDecoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_custom_decode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_decode_float((OpusCustomDecoder*)(intptr_t)p0, p1, (int)p2, (float*)p3, (int)p4);
}

int64_t xo_custom_decode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_decode((OpusCustomDecoder*)(intptr_t)p0, p1, (int)p2, (opus_int16*)p3, (int)p4);
}

int64_t xo_custom_decode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_decode24((OpusCustomDecoder*)(intptr_t)p0, p1, (int)p2, (opus_int32*)p3, (int)p4);
}

int64_t xo_custom_decoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_custom_decoder_ctl((OpusCustomDecoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_custom_decoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_custom_decoder_ctl((OpusCustomDecoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

/* ======================================================================== */
/* opus_projection.h                                                        */
/* ======================================================================== */

int64_t xo_projection_ambisonics_encoder_get_size(int32_t p0, int32_t p1)
{
  return (int64_t)opus_projection_ambisonics_encoder_get_size((int)p0, (int)p1);
}

int64_t xo_projection_ambisonics_encoder_create(int32_t Fs, int32_t channels, int32_t mapping_family,
                                                unsigned char* streams_out, unsigned char* coupled_streams_out,
                                                int32_t application, unsigned char* err_out)
{
  int streams = 0;
  int coupled_streams = 0;
  int err = 0;
  OpusProjectionEncoder* st = opus_projection_ambisonics_encoder_create((opus_int32)Fs, (int)channels,
                                                                        (int)mapping_family, &streams,
                                                                        &coupled_streams, (int)application, &err);
  put_i32(streams_out, (int32_t)streams);
  put_i32(coupled_streams_out, (int32_t)coupled_streams);
  put_i32(err_out, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_projection_ambisonics_encoder_init(unsigned char* mem, int32_t mem_capacity, int32_t Fs, int32_t channels,
                                              int32_t mapping_family, unsigned char* streams_out,
                                              unsigned char* coupled_streams_out, int32_t application,
                                              unsigned char* err_out)
{
  int streams = 0;
  int coupled_streams = 0;
  int rc;
  int64_t need;
  if (mem == 0) {
    put_i32(streams_out, 0);
    put_i32(coupled_streams_out, 0);
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  need = (int64_t)opus_projection_ambisonics_encoder_get_size((int)channels, (int)mapping_family);
  if (need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(streams_out, 0);
    put_i32(coupled_streams_out, 0);
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_projection_ambisonics_encoder_init((OpusProjectionEncoder*)mem, (opus_int32)Fs, (int)channels,
                                               (int)mapping_family, &streams, &coupled_streams, (int)application);
  put_i32(streams_out, (int32_t)streams);
  put_i32(coupled_streams_out, (int32_t)coupled_streams);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_projection_encode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_encode((OpusProjectionEncoder*)(intptr_t)p0, (const opus_int16*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_projection_encode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_encode24((OpusProjectionEncoder*)(intptr_t)p0, (const opus_int32*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_projection_encode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_encode_float((OpusProjectionEncoder*)(intptr_t)p0, (const float*)p1, (int)p2, p3, (opus_int32)p4);
}

int64_t xo_projection_encoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_projection_encoder_destroy((OpusProjectionEncoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_projection_encoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_encoder_ctl((OpusProjectionEncoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_projection_encoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_projection_encoder_ctl((OpusProjectionEncoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}

/* Companion for OPUS_PROJECTION_GET_DEMIXING_MATRIX(matrix, size): the value
 * arguments are a pointer + length.  The caller sizing comes from
 * OPUS_PROJECTION_GET_DEMIXING_MATRIX_SIZE_REQUEST (int ctl). */
int64_t xo_projection_encoder_ctl_get_matrix(int64_t st, unsigned char* out, int32_t capacity)
{
  if (st == 0 || out == 0 || capacity <= 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_encoder_ctl((OpusProjectionEncoder*)(intptr_t)st,
                                              OPUS_PROJECTION_GET_DEMIXING_MATRIX_REQUEST, out,
                                              (opus_int32)capacity);
}

int64_t xo_projection_decoder_get_size(int32_t p0, int32_t p1, int32_t p2)
{
  return (int64_t)opus_projection_decoder_get_size((int)p0, (int)p1, (int)p2);
}

int64_t xo_projection_decoder_create(int32_t p0, int32_t p1, int32_t p2, int32_t p3,
                                     const unsigned char* p4, int32_t p5, unsigned char* p6)
{
  int err = 0;
  OpusProjectionDecoder* st;
  if (p4 == 0) {
    put_i32(p6, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  st = opus_projection_decoder_create((opus_int32)p0, (int)p1, (int)p2, (int)p3, (unsigned char*)p4, (opus_int32)p5, &err);
  put_i32(p6, (int32_t)err);
  return (int64_t)(intptr_t)st;
}

int64_t xo_projection_decoder_init(unsigned char* mem, int32_t mem_capacity, int32_t Fs, int32_t channels,
                                   int32_t streams, int32_t coupled_streams, const unsigned char* demixing_matrix,
                                   int32_t demixing_matrix_size, unsigned char* err_out)
{
  int rc;
  int64_t need;
  if (mem == 0 || demixing_matrix == 0) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  need = (int64_t)opus_projection_decoder_get_size((int)channels, (int)streams, (int)coupled_streams);
  if (need <= 0 || (int64_t)mem_capacity < need) {
    put_i32(err_out, (int32_t)OPUS_BAD_ARG);
    return 0;
  }
  rc = opus_projection_decoder_init((OpusProjectionDecoder*)mem, (opus_int32)Fs, (int)channels, (int)streams,
                                    (int)coupled_streams, (unsigned char*)demixing_matrix, (opus_int32)demixing_matrix_size);
  put_i32(err_out, (int32_t)rc);
  return rc == OPUS_OK ? (int64_t)(intptr_t)mem : 0;
}

int64_t xo_projection_decode(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_decode((OpusProjectionDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (opus_int16*)p3, (int)p4, (int)p5);
}

int64_t xo_projection_decode24(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_decode24((OpusProjectionDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (opus_int32*)p3, (int)p4, (int)p5);
}

int64_t xo_projection_decode_float(int64_t p0, const unsigned char* p1, int32_t p2, unsigned char* p3, int32_t p4, int32_t p5)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_decode_float((OpusProjectionDecoder*)(intptr_t)p0, p1, (opus_int32)p2, (float*)p3, (int)p4, (int)p5);
}

int64_t xo_projection_decoder_destroy(int64_t p0)
{
  if (p0 != 0) {
    opus_projection_decoder_destroy((OpusProjectionDecoder*)(intptr_t)p0);
  }
  return 0;
}

int64_t xo_projection_decoder_ctl_set(int64_t p0, int32_t p1, int32_t p2)
{
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  return (int64_t)opus_projection_decoder_ctl((OpusProjectionDecoder*)(intptr_t)p0, (int)p1, (int)p2);
}

int64_t xo_projection_decoder_ctl_get(int64_t p0, int32_t p1, unsigned char* p2)
{
  int value = 0;
  int rc;
  if (p0 == 0) {
    return (int64_t)OPUS_BAD_ARG;
  }
  rc = opus_projection_decoder_ctl((OpusProjectionDecoder*)(intptr_t)p0, (int)p1, &value);
  put_i32(p2, (int32_t)value);
  return (int64_t)rc;
}
