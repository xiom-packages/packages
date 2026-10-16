/* XIOM -- xiom.brotli bridge over the vendored brotli v1.2.0 C API.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * This file: MIT OR Apache-2.0 (XIOM Authors). The vendored upstream
 * sources under vendor/brotli are MIT (Copyright (c) 2009, 2010, 2013-2016
 * by the Brotli Authors; see vendor/brotli/LICENSE).
 *
 * This bridge supplies only what XIOM cannot express on toolchain v0.64.5,
 * under the lane's binding discipline (B-11..B-32):
 *   - creation with real NULL allocator/free/opaque arguments (no bare
 *     `null` is ever materialized on the XIOM side, B-23);
 *   - the pointer-to-pointer stream cursors and size_t in/out parameters of
 *     BrotliDecoderDecompressStream / BrotliEncoderCompressStream (cursors
 *     and pointer arithmetic stay in C, B-17);
 *   - the in/out `size_t*` of the one-shot BrotliDecoderDecompress /
 *     BrotliEncoderCompress (result size written to a caller-owned 8-byte
 *     LE slot, one slot per out-param);
 *   - BrotliEncoderTakeOutput pointer acquisition: the bytes are COPIED into
 *     the caller's owned buffer here; XIOM never reads through a foreign
 *     pointer (B-20/B-24);
 *   - BrotliDecoderErrorString: copied into a caller-owned buffer;
 *   - BrotliDecoderGetErrorCode: returned as int64_t so negative error
 *     codes keep their sign across the ABI.
 *
 * Every function returns int64_t (handles, byte counts, or upstream result
 * codes); no pointer is ever handed back to XIOM. Handles are opaque state
 * addresses as int64_t, cast to their pointer type HERE.
 */

#include "../vendor/brotli/include/brotli/decode.h"
#include "../vendor/brotli/include/brotli/encode.h"

#include <stdint.h>
#include <string.h>

/* Little-endian 8-byte scalar into a caller-owned slot. */
static void xb_write_u64_le(uint8_t* p, uint64_t v) {
  int i;
  for (i = 0; i < 8; ++i) {
    p[i] = (uint8_t)((v >> (8 * i)) & 0xffu);
  }
}

/* ====================================================================== */
/* decoder                                                                */
/* ====================================================================== */

/* Create a decoder with the default memory manager (NULL,NULL,NULL). */
int64_t xb_decoder_create(void) {
  BrotliDecoderState* s = BrotliDecoderCreateInstance(NULL, NULL, NULL);
  return (int64_t)(intptr_t)s;
}

/* One BrotliDecoderDecompressStream call. Input is the caller's owned
 * buffer plus an offset (the bridge advances the C-side cursor); the
 * number of bytes consumed and the number of bytes written into `out` are
 * reported through two caller-owned 8-byte LE slots. Returns the raw
 * BrotliDecoderResult (0..3), or -1 when the state handle is 0. */
int64_t xb_decoder_stream(int64_t state, const uint8_t* src, int64_t src_len,
                          int64_t src_offset, uint8_t* out, int64_t out_cap,
                          uint8_t* consumed_slot, uint8_t* written_slot) {
  BrotliDecoderState* s = (BrotliDecoderState*)(intptr_t)state;
  size_t avail_in;
  const uint8_t* next_in;
  size_t avail_out;
  uint8_t* next_out;
  size_t total_out = 0;
  BrotliDecoderResult r;
  if (s == NULL || src == NULL || consumed_slot == NULL || written_slot == NULL) {
    return -1;
  }
  avail_in = (size_t)(src_len - src_offset);
  next_in = src + src_offset;
  avail_out = (out_cap > 0) ? (size_t)out_cap : 0;
  next_out = (out_cap > 0) ? out : NULL;
  r = BrotliDecoderDecompressStream(s, &avail_in, &next_in, &avail_out,
                                    &next_out, &total_out);
  xb_write_u64_le(consumed_slot, (uint64_t)((size_t)(src_len - src_offset) - avail_in));
  xb_write_u64_le(written_slot, (uint64_t)((size_t)(out_cap > 0 ? out_cap : 0) - avail_out));
  return (int64_t)r;
}

/* One-shot BrotliDecoderDecompress. Writes the produced byte count to the
 * caller-owned 8-byte LE `size_slot`; returns the raw result (ERROR=0 /
 * SUCCESS=1) or -1 for bridge-level invalid arguments. */
int64_t xb_decoder_decompress_oneshot(const uint8_t* src, int64_t src_len,
                                      uint8_t* dst, int64_t dst_cap,
                                      uint8_t* size_slot) {
  size_t decoded_size;
  BrotliDecoderResult r;
  if (src == NULL || dst == NULL || size_slot == NULL || src_len <= 0 || dst_cap <= 0) {
    return -1;
  }
  decoded_size = (size_t)dst_cap;
  r = BrotliDecoderDecompress((size_t)src_len, src, &decoded_size, dst);
  xb_write_u64_le(size_slot, (uint64_t)decoded_size);
  return (int64_t)r;
}

/* brotli.h enum, as int64_t (negative codes keep their sign). */
int64_t xb_decoder_error_code(int64_t state) {
  BrotliDecoderState* s = (BrotliDecoderState*)(intptr_t)state;
  if (s == NULL) {
    return 0; /* BROTLI_DECODER_NO_ERROR */
  }
  return (int64_t)BrotliDecoderGetErrorCode(s);
}

/* Copy BrotliDecoderErrorString(code) into the caller-owned buffer `out`
 * (capacity `cap`); returns the copied byte count (no NUL). Never returns a
 * foreign pointer. */
int64_t xb_decoder_error_string(int64_t code, uint8_t* out, int64_t cap) {
  const char* s = BrotliDecoderErrorString((BrotliDecoderErrorCode)code);
  size_t n;
  if (s == NULL || out == NULL || cap <= 0) {
    return 0;
  }
  n = strlen(s);
  if ((int64_t)n > cap) {
    n = (size_t)cap;
  }
  if (n > 0) {
    memcpy(out, s, n);
  }
  return (int64_t)n;
}

/* ====================================================================== */
/* encoder                                                                */
/* ====================================================================== */

/* Create an encoder with the default memory manager and set the three
 * core parameters. Returns the handle, or 0 when creation or any parameter
 * assignment fails (the XIOM wrapper validates ranges first). */
int64_t xb_encoder_create(int64_t quality, int64_t lgwin, int64_t mode) {
  BrotliEncoderState* s = BrotliEncoderCreateInstance(NULL, NULL, NULL);
  if (s == NULL) {
    return 0;
  }
  if (!BrotliEncoderSetParameter(s, BROTLI_PARAM_QUALITY, (uint32_t)quality) ||
      !BrotliEncoderSetParameter(s, BROTLI_PARAM_LGWIN, (uint32_t)lgwin) ||
      !BrotliEncoderSetParameter(s, BROTLI_PARAM_MODE, (uint32_t)mode)) {
    BrotliEncoderDestroyInstance(s);
    return 0;
  }
  return (int64_t)(intptr_t)s;
}

/* One BrotliEncoderCompressStream call; same cursor/slot contract as
 * xb_decoder_stream. Returns BROTLI_TRUE/FALSE (1/0) or -1 on a 0 handle. */
int64_t xb_encoder_stream(int64_t state, int64_t op, const uint8_t* src,
                          int64_t src_len, int64_t src_offset, uint8_t* out,
                          int64_t out_cap, uint8_t* consumed_slot,
                          uint8_t* written_slot) {
  BrotliEncoderState* s = (BrotliEncoderState*)(intptr_t)state;
  size_t avail_in;
  const uint8_t* next_in;
  size_t avail_out;
  uint8_t* next_out;
  size_t total_out = 0;
  BROTLI_BOOL ok;
  if (s == NULL || src == NULL || consumed_slot == NULL || written_slot == NULL) {
    return -1;
  }
  avail_in = (size_t)(src_len - src_offset);
  next_in = src + src_offset;
  avail_out = (out_cap > 0) ? (size_t)out_cap : 0;
  next_out = (out_cap > 0) ? out : NULL;
  ok = BrotliEncoderCompressStream(s, (BrotliEncoderOperation)op, &avail_in,
                                   &next_in, &avail_out, &next_out, &total_out);
  xb_write_u64_le(consumed_slot, (uint64_t)((size_t)(src_len - src_offset) - avail_in));
  xb_write_u64_le(written_slot, (uint64_t)((size_t)(out_cap > 0 ? out_cap : 0) - avail_out));
  return (int64_t)ok;
}

/* Drain buffered encoder output: BrotliEncoderTakeOutput is called with
 * *size = dst_cap, the `n` bytes it hands out are COPIED into `dst`, and
 * `n` is returned (0 when nothing is buffered). */
int64_t xb_encoder_take_output(int64_t state, uint8_t* dst, int64_t dst_cap) {
  BrotliEncoderState* s = (BrotliEncoderState*)(intptr_t)state;
  size_t n;
  const uint8_t* p;
  if (s == NULL || dst == NULL || dst_cap <= 0) {
    return 0;
  }
  n = (size_t)dst_cap;
  p = BrotliEncoderTakeOutput(s, &n);
  if (n > 0 && p != NULL) {
    memcpy(dst, p, n);
  }
  return (int64_t)n;
}

/* One-shot BrotliEncoderCompress. Writes the produced byte count to the
 * caller-owned 8-byte LE `size_slot`; returns BROTLI_TRUE/FALSE or -1 for
 * bridge-level invalid arguments. src_len == 0 is legal (empty stream);
 * `src` must still be a valid address and `dst_cap >= 1`. */
int64_t xb_encoder_compress_oneshot(int64_t quality, int64_t lgwin,
                                    int64_t mode, const uint8_t* src,
                                    int64_t src_len, uint8_t* dst,
                                    int64_t dst_cap, uint8_t* size_slot) {
  size_t encoded_size;
  BROTLI_BOOL ok;
  if (src == NULL || dst == NULL || size_slot == NULL || src_len < 0 || dst_cap <= 0) {
    return -1;
  }
  encoded_size = (size_t)dst_cap;
  ok = BrotliEncoderCompress((int)quality, (int)lgwin, (BrotliEncoderMode)mode,
                             (size_t)src_len, src, &encoded_size, dst);
  xb_write_u64_le(size_slot, (uint64_t)encoded_size);
  return (int64_t)ok;
}
