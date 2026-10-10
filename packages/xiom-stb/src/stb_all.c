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
