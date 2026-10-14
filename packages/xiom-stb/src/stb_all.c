// xiom.stb -- vendored stb_image + stb_image_write with a probe bridge.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// One TU (the miniaudio pattern): both implementations plus the probe
// bridge.  Cached integer results via scalar getters (no out-param slots;
// B-11 family avoidance).  The probe is self-contained: it encodes a 4x4
// RGBA gradient to PNG in memory, decodes it back, and verifies every
// pixel; it also decodes a hardcoded 1x1 24-bit BMP.

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../vendor/stb_image.h"
#include "../vendor/stb_image_write.h"

#include <string.h>

static int g_png_size;
static int g_roundtrip_ok;
static int g_checksum;
static int g_bmp_ok;

// 1x1 24-bit BMP, red pixel (BGR order with row padding).
static const unsigned char k_bmp_1x1_red[58] = {
    0x42, 0x4D, 0x3A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x36, 0x00,
    0x00, 0x00, 0x28, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00
};

// Probe bridges (plain C linkage -- this is a C translation unit).

int stbprobe_version(void) {
  return STBI_VERSION;
}

// Runs the full codec probe; caches the results.  0 on success, negative on
// failure.
int stbprobe_run(void) {
  g_png_size = 0;
  g_roundtrip_ok = 0;
  g_checksum = 0;
  g_bmp_ok = 0;

  // 1. Build a 4x4 RGBA gradient.
  unsigned char pixels[4 * 4 * 4];
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      unsigned char* p = pixels + (y * 4 + x) * 4;
      p[0] = (unsigned char)(x * 60);
      p[1] = (unsigned char)(y * 60);
      p[2] = (unsigned char)((x + y) * 30);
      p[3] = 255;
    }
  }

  // 2. Encode to PNG in memory.
  int len = 0;
  unsigned char* png = stbi_write_png_to_mem(pixels, 4 * 4, 4, 4, 4, &len);
  if (png == 0 || len <= 0) {
    if (png != 0) STBIW_FREE(png);
    return -2;
  }
  g_png_size = len;

  // 3. Decode it back and verify every pixel.
  int w = 0;
  int h = 0;
  int comp = 0;
  unsigned char* decoded = stbi_load_from_memory(png, len, &w, &h, &comp, 4);
  STBIW_FREE(png);
  if (decoded == 0 || w != 4 || h != 4 || comp != 4) {
    if (decoded != 0) stbi_image_free(decoded);
    return -3;
  }
  int ok = 1;
  int checksum = 0;
  for (int i = 0; i < 4 * 4 * 4; i++) {
    checksum += decoded[i];
    if (decoded[i] != pixels[i]) ok = 0;
  }
  stbi_image_free(decoded);
  g_roundtrip_ok = ok;
  g_checksum = checksum;
  if (!ok) return -4;

  // 4. Decode the hardcoded 1x1 red BMP.
  int bw = 0;
  int bh = 0;
  int bcomp = 0;
  unsigned char* bmp = stbi_load_from_memory(k_bmp_1x1_red, (int)sizeof(k_bmp_1x1_red),
                                             &bw, &bh, &bcomp, 0);
  if (bmp == 0) return -5;
  g_bmp_ok = (bw == 1 && bh == 1 && bcomp == 3 && bmp[0] == 255 && bmp[1] == 0 &&
              bmp[2] == 0)
                 ? 1
                 : 0;
  stbi_image_free(bmp);
  if (!g_bmp_ok) return -6;

  return 0;
}

int stbprobe_png_size(void) {
  return g_png_size;
}

int stbprobe_roundtrip_ok(void) {
  return g_roundtrip_ok;
}

int stbprobe_checksum(void) {
  return g_checksum;
}

int stbprobe_bmp_ok(void) {
  return g_bmp_ok;
}

// ===========================================================================
// HDR class bridge (0.3.0) -- stb_image's .hdr-related public entries.
// ===========================================================================
//
// Design: bridge-owned "last loaded image" state + byte-slot copy-out
// (B-20: XIOM never reads through foreign pointers; B-11/B-24: out values
// come back as owned-slot bytes). All load paths and the two *_from_file
// entries are reachable; the *_from_callbacks entries are driven by a
// bridge-provided memory-cursor callback set (user fn-params crossing to C
// are B-13/B-22-broken on the pin, so arbitrary XIOM callbacks are not part
// of the declared surface -- see SPEC.md).
//
// Return codes: 0 = ok, -1 = codec/load failure (stbi_failure_reason()),
// -2 = caller argument error (bad buffer/capacity), -3 = no cached image.

static float *g_img_f32;         // cached float image (stbi_image_free)
static unsigned char *g_img_u8;  // cached 8-bit image (stbi_image_free)
static int g_img_w;
static int g_img_h;
static int g_img_comp_actual;    // channels in `data` (requested or native)
static int g_img_comp_file;      // channels detected in the file
static int g_img_bytes;

static void stbprobe_img_clear(void) {
  if (g_img_f32 != 0) {
    stbi_image_free(g_img_f32);
    g_img_f32 = 0;
  }
  if (g_img_u8 != 0) {
    stbi_image_free(g_img_u8);
    g_img_u8 = 0;
  }
  g_img_w = 0;
  g_img_h = 0;
  g_img_comp_actual = 0;
  g_img_comp_file = 0;
  g_img_bytes = 0;
}

static int stbprobe_cache_f32(float *px, int w, int h, int comp, int wanted) {
  if (px == 0 || w <= 0 || h <= 0 || comp <= 0) {
    if (px != 0) stbi_image_free(px);
    return -1;
  }
  stbprobe_img_clear();
  g_img_f32 = px;
  g_img_w = w;
  g_img_h = h;
  g_img_comp_file = comp;
  g_img_comp_actual = wanted > 0 ? wanted : comp;
  g_img_bytes = w * h * g_img_comp_actual * (int)sizeof(float);
  return 0;
}

static int stbprobe_cache_u8(unsigned char *px, int w, int h, int comp,
                             int wanted) {
  if (px == 0 || w <= 0 || h <= 0 || comp <= 0) {
    if (px != 0) stbi_image_free(px);
    return -1;
  }
  stbprobe_img_clear();
  g_img_u8 = px;
  g_img_w = w;
  g_img_h = h;
  g_img_comp_file = comp;
  g_img_comp_actual = wanted > 0 ? wanted : comp;
  g_img_bytes = w * h * g_img_comp_actual;
  return 0;
}

// Memory-cursor callbacks: cover the stbi_*_from_callbacks entries without
// an XIOM->C fn-param crossing.
typedef struct stbprobe_reader {
  const unsigned char *data;
  int len;
  int pos;
} stbprobe_reader;

static int stbprobe_cb_read(void *user, char *out, int size) {
  stbprobe_reader *r = (stbprobe_reader *)user;
  int nleft = r->len - r->pos;
  int n = nleft < size ? nleft : size;
  if (n <= 0) return 0;
  memcpy(out, r->data + r->pos, (size_t)n);
  r->pos += n;
  return n;
}

static void stbprobe_cb_skip(void *user, int n) {
  stbprobe_reader *r = (stbprobe_reader *)user;
  int nleft = r->len - r->pos;
  if (n > nleft) n = nleft;
  if (n > 0) r->pos += n;
}

static int stbprobe_cb_eof(void *user) {
  stbprobe_reader *r = (stbprobe_reader *)user;
  return r->pos >= r->len;
}

static stbi_io_callbacks g_stbprobe_cbs = {stbprobe_cb_read, stbprobe_cb_skip,
                                           stbprobe_cb_eof};

int stbprobe_loadf_mem(const unsigned char *data, int len, int desired) {
  int w = 0;
  int h = 0;
  int comp = 0;
  float *px;
  if (data == 0 || len <= 0) return -2;
  px = stbi_loadf_from_memory(data, len, &w, &h, &comp, desired);
  return stbprobe_cache_f32(px, w, h, comp, desired);
}

int stbprobe_loadf_callbacks(const unsigned char *data, int len, int desired) {
  int w = 0;
  int h = 0;
  int comp = 0;
  float *px;
  stbprobe_reader r;
  if (data == 0 || len <= 0) return -2;
  r.data = data;
  r.len = len;
  r.pos = 0;
  px = stbi_loadf_from_callbacks(&g_stbprobe_cbs, &r, &w, &h, &comp, desired);
  return stbprobe_cache_f32(px, w, h, comp, desired);
}

int stbprobe_loadf_file(const char *path, int desired) {
  int w = 0;
  int h = 0;
  int comp = 0;
  float *px;
  if (path == 0) return -2;
  px = stbi_loadf(path, &w, &h, &comp, desired);
  return stbprobe_cache_f32(px, w, h, comp, desired);
}

int stbprobe_loadf_from_file(const char *path, int desired) {
  int w = 0;
  int h = 0;
  int comp = 0;
  float *px;
  FILE *f;
  if (path == 0) return -2;
  f = fopen(path, "rb");
  if (f == 0) return -1;
  px = stbi_loadf_from_file(f, &w, &h, &comp, desired);
  fclose(f);
  return stbprobe_cache_f32(px, w, h, comp, desired);
}

int stbprobe_load8_mem(const unsigned char *data, int len, int desired) {
  int w = 0;
  int h = 0;
  int comp = 0;
  unsigned char *px;
  if (data == 0 || len <= 0) return -2;
  px = stbi_load_from_memory(data, len, &w, &h, &comp, desired);
  return stbprobe_cache_u8(px, w, h, comp, desired);
}

int stbprobe_img_w(void) { return g_img_w; }
int stbprobe_img_h(void) { return g_img_h; }
int stbprobe_img_comp(void) { return g_img_comp_actual; }
int stbprobe_img_file_comp(void) { return g_img_comp_file; }
int stbprobe_img_float(void) { return g_img_f32 != 0 ? 1 : 0; }
int stbprobe_img_bytes(void) { return g_img_bytes; }

int stbprobe_img_copy(unsigned char *dst, int cap) {
  if (dst == 0 || cap < 0) return -2;
  if (g_img_bytes <= 0) return -3;
  if (cap < g_img_bytes) return -2;
  if (g_img_f32 != 0) {
    memcpy(dst, g_img_f32, (size_t)g_img_bytes);
    return g_img_bytes;
  }
  if (g_img_u8 != 0) {
    memcpy(dst, g_img_u8, (size_t)g_img_bytes);
    return g_img_bytes;
  }
  return -3;
}

void stbprobe_img_release(void) { stbprobe_img_clear(); }

int stbprobe_hdr_is_mem(const unsigned char *data, int len) {
  if (data == 0 || len <= 0) return 0;
  return stbi_is_hdr_from_memory(data, len);
}

int stbprobe_hdr_is_callbacks(const unsigned char *data, int len) {
  stbprobe_reader r;
  if (data == 0 || len <= 0) return 0;
  r.data = data;
  r.len = len;
  r.pos = 0;
  return stbi_is_hdr_from_callbacks(&g_stbprobe_cbs, &r);
}

int stbprobe_hdr_is_file(const char *path) {
  if (path == 0) return 0;
  return stbi_is_hdr(path);
}

int stbprobe_hdr_is_from_file(const char *path) {
  FILE *f;
  int result;
  if (path == 0) return 0;
  f = fopen(path, "rb");
  if (f == 0) return 0;
  result = stbi_is_hdr_from_file(f);
  fclose(f);
  return result;
}

void stbprobe_hdr_to_ldr_gamma(float gamma) { stbi_hdr_to_ldr_gamma(gamma); }
void stbprobe_hdr_to_ldr_scale(float scale) { stbi_hdr_to_ldr_scale(scale); }
void stbprobe_ldr_to_hdr_gamma(float gamma) { stbi_ldr_to_hdr_gamma(gamma); }
void stbprobe_ldr_to_hdr_scale(float scale) { stbi_ldr_to_hdr_scale(scale); }

const char *stbprobe_failure_reason(void) {
  const char *reason = stbi_failure_reason();
  return reason != 0 ? reason : "";
}
