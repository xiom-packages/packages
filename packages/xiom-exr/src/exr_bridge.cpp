// xiom.exr -- C bridge over the vendored tinyexr C API (v3.2.0, BSD-3).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// One C++ TU (the single-TU pattern): TINYEXR_IMPLEMENTATION + the vendored
// miniz (separate vendor/tinyexr/miniz.c TU) + this bridge.  The bridge uses
// only tinyexr's public extern "C" API; it keeps ONE loaded image (session)
// and the last saved buffer C-side, and copies everything into XIOM-owned
// byte slots (B-20/B-24: no foreign-pointer reads; B-11: one owned slot per
// out-param; B-25: no handle casts -- the session is never an XIOM value).
//
// Channel data is exposed as planar float32 little-endian: HALF/FLOAT
// channels load as FLOAT (tinyexr's requested_pixel_types conversion); UINT
// channels stay UINT inside tinyexr (its loader rejects FLOAT requests for
// them) and the copy-out casts uint32->float32.  `pixel_type` metadata
// always reports the DECLARED file type from EXRChannelInfo.
//
// Error state: the last tinyexr error code + a copied message string; the
// XIOM side reads them after a negative return (typed ExrError).

#include <cstdio>
#include <cstdlib>
#include <cstring>

#define TINYEXR_IMPLEMENTATION
#define TINYEXR_USE_MINIZ 1
#include "../vendor/tinyexr/tinyexr.h"

#define EXRPROBE_MAX_CHANNELS 32
#define EXRPROBE_ERROR_MAX 511

namespace {

struct ExrProbeSession {
  bool header_active;
  bool image_active;
  EXRHeader header;
  EXRImage image;
  unsigned char *saved;
  long saved_size;
  int error_code;
  char error_message[EXRPROBE_ERROR_MAX + 1];
};

ExrProbeSession g;

void exrprobe_set_error(int code, const char *message) {
  g.error_code = code;
  if (message == 0) message = "";
  strncpy(g.error_message, message, EXRPROBE_ERROR_MAX);
  g.error_message[EXRPROBE_ERROR_MAX] = 0;
}

// Consumes (frees) the tinyexr-allocated error string.
void exrprobe_take_error(int code, const char *error) {
  exrprobe_set_error(code, error != 0 ? error : "exr: unknown error");
  if (error != 0) FreeEXRErrorMessage(error);
}

void exrprobe_clear_saved(void) {
  if (g.saved != 0) {
    free(g.saved);
    g.saved = 0;
  }
  g.saved_size = 0;
}

void exrprobe_clear_image(void) {
  if (g.image_active) {
    FreeEXRImage(&g.image);
    g.image_active = false;
  }
  if (g.header_active) {
    FreeEXRHeader(&g.header);
    g.header_active = false;
  }
}

void exrprobe_clear_all(void) {
  exrprobe_clear_saved();
  exrprobe_clear_image();
}

bool exrprobe_need_session(void) {
  if (!g.image_active || !g.header_active) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT, "exr: no image loaded");
    return false;
  }
  return true;
}

// HALF/FLOAT declared channels request FLOAT data (tinyexr converts half to
// float); UINT requests stay UINT for the loader and are cast at copy time.
void exrprobe_normalize_requests(void) {
  for (int c = 0; c < g.header.num_channels; c++) {
    int declared = g.header.channels[c].pixel_type;
    if (declared == TINYEXR_PIXELTYPE_HALF ||
        declared == TINYEXR_PIXELTYPE_FLOAT) {
      g.header.requested_pixel_types[c] = TINYEXR_PIXELTYPE_FLOAT;
    }
  }
}

int exrprobe_finish_load_memory(const EXRVersion *version,
                                const unsigned char *data, int size) {
  InitEXRHeader(&g.header);
  g.header_active = true;
  const char *error = 0;
  int rc = ParseEXRHeaderFromMemory(&g.header, version, data, (size_t)size,
                                    &error);
  if (rc != TINYEXR_SUCCESS) {
    exrprobe_take_error(rc, error);
    exrprobe_clear_image();
    return rc;
  }
  exrprobe_normalize_requests();
  InitEXRImage(&g.image);
  g.image_active = true;
  error = 0;
  rc = LoadEXRImageFromMemory(&g.image, &g.header, data, (size_t)size, &error);
  if (rc != TINYEXR_SUCCESS) {
    exrprobe_take_error(rc, error);
    exrprobe_clear_image();
    return rc;
  }
  exrprobe_set_error(TINYEXR_SUCCESS, "");
  return TINYEXR_SUCCESS;
}

int exrprobe_finish_load_file(const EXRVersion *version, const char *path) {
  InitEXRHeader(&g.header);
  g.header_active = true;
  const char *error = 0;
  int rc = ParseEXRHeaderFromFile(&g.header, version, path, &error);
  if (rc != TINYEXR_SUCCESS) {
    exrprobe_take_error(rc, error);
    exrprobe_clear_image();
    return rc;
  }
  exrprobe_normalize_requests();
  InitEXRImage(&g.image);
  g.image_active = true;
  error = 0;
  rc = LoadEXRImageFromFile(&g.image, &g.header, path, &error);
  if (rc != TINYEXR_SUCCESS) {
    exrprobe_take_error(rc, error);
    exrprobe_clear_image();
    return rc;
  }
  exrprobe_set_error(TINYEXR_SUCCESS, "");
  return TINYEXR_SUCCESS;
}

}  // namespace

extern "C" {

// ---- detection ------------------------------------------------------------

int exrprobe_is_exr_mem(const unsigned char *data, int size) {
  if (data == 0 || size <= 0) return 0;
  return IsEXRFromMemory(data, (size_t)size) == TINYEXR_SUCCESS ? 1 : 0;
}

int exrprobe_is_exr_file(const char *path) {
  if (path == 0) return 0;
  return IsEXR(path) == TINYEXR_SUCCESS ? 1 : 0;
}

// ---- load -----------------------------------------------------------------

int exrprobe_load_mem(const unsigned char *data, int size) {
  if (data == 0 || size <= 0) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT, "exr: empty buffer");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  exrprobe_clear_all();
  EXRVersion version;
  memset(&version, 0, sizeof(version));
  int rc = ParseEXRVersionFromMemory(&version, data, (size_t)size);
  if (rc != TINYEXR_SUCCESS) {
    exrprobe_set_error(rc, "exr: not an OpenEXR stream (magic/version)");
    return rc;
  }
  return exrprobe_finish_load_memory(&version, data, size);
}

int exrprobe_load_file(const char *path) {
  if (path == 0) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT, "exr: empty path");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  exrprobe_clear_all();
  EXRVersion version;
  memset(&version, 0, sizeof(version));
  int rc = ParseEXRVersionFromFile(&version, path);
  if (rc != TINYEXR_SUCCESS) {
    exrprobe_set_error(rc, "exr: cannot open/parse file (magic/version)");
    return rc;
  }
  return exrprobe_finish_load_file(&version, path);
}

// ---- metadata (session getters) -------------------------------------------

int exrprobe_width(void) { return g.image_active ? g.image.width : 0; }
int exrprobe_height(void) { return g.image_active ? g.image.height : 0; }
int exrprobe_channels(void) { return g.image_active ? g.image.num_channels : 0; }
int exrprobe_compression(void) {
  return g.header_active ? g.header.compression_type : -1;
}
int exrprobe_window_min_x(void) {
  return g.header_active ? g.header.data_window.min_x : 0;
}
int exrprobe_window_min_y(void) {
  return g.header_active ? g.header.data_window.min_y : 0;
}
int exrprobe_window_max_x(void) {
  return g.header_active ? g.header.data_window.max_x : 0;
}
int exrprobe_window_max_y(void) {
  return g.header_active ? g.header.data_window.max_y : 0;
}

int exrprobe_channel_pixel_type(int index) {
  if (!exrprobe_need_session()) return TINYEXR_ERROR_INVALID_ARGUMENT;
  if (index < 0 || index >= g.header.num_channels) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: channel index out of range");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  return g.header.channels[index].pixel_type;
}

int exrprobe_channel_name_len(int index) {
  if (!exrprobe_need_session()) return TINYEXR_ERROR_INVALID_ARGUMENT;
  if (index < 0 || index >= g.header.num_channels) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: channel index out of range");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  return (int)strlen(g.header.channels[index].name);
}

// Copies name + NUL into dst; returns the name length (excluding NUL) or a
// negative error code.
int exrprobe_channel_name_copy(int index, unsigned char *dst, int cap) {
  if (!exrprobe_need_session()) return TINYEXR_ERROR_INVALID_ARGUMENT;
  if (dst == 0 || cap <= 0) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: invalid name target");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  if (index < 0 || index >= g.header.num_channels) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: channel index out of range");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  int len = (int)strlen(g.header.channels[index].name);
  if (cap < len + 1) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: name target too small");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  memcpy(dst, g.header.channels[index].name, (size_t)len + 1);
  return len;
}

// Total owned-data size for the loaded image: width*height*4 per channel.
int exrprobe_image_bytes(void) {
  if (!exrprobe_need_session()) return TINYEXR_ERROR_INVALID_ARGUMENT;
  long pixels = (long)g.image.width * (long)g.image.height;
  return (int)(pixels * 4L * (long)g.header.num_channels);
}

// Copies ALL channels planar into dst (channel 0 plane first), each pixel
// widened to float32 little-endian.  Returns bytes copied or a negative code.
int exrprobe_image_copy(unsigned char *dst, int cap) {
  if (!exrprobe_need_session()) return TINYEXR_ERROR_INVALID_ARGUMENT;
  if (dst == 0 || cap <= 0) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: invalid copy target");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  long pixels = (long)g.image.width * (long)g.image.height;
  int need = (int)(pixels * 4L * (long)g.header.num_channels);
  if (cap < need) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: copy target too small");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  float *out = reinterpret_cast<float *>(dst);
  for (int c = 0; c < g.header.num_channels; c++) {
    float *plane = out + (long)c * pixels;
    if (g.image.images[c] == 0) {
      exrprobe_set_error(TINYEXR_ERROR_INVALID_DATA,
                         "exr: channel has no pixel data");
      return TINYEXR_ERROR_INVALID_DATA;
    }
    if (g.header.channels[c].pixel_type == TINYEXR_PIXELTYPE_UINT) {
      const unsigned int *src =
          reinterpret_cast<const unsigned int *>(g.image.images[c]);
      for (long k = 0; k < pixels; k++) {
        plane[k] = (float)src[k];
      }
    } else {
      memcpy(plane, g.image.images[c], (size_t)(pixels * 4L));
    }
  }
  return need;
}

// ---- save (tinyexr's own writer) ------------------------------------------

// Builds and caches an EXR blob from planar float32 data.
// names is a NUL-separated blob ("R\0G\0B\0"), channels = its name count.
// fp16 != 0 writes HALF channels (tinyexr converts float->half on save).
int exrprobe_save(const unsigned char *planar_f32, int data_len, int width,
                  int height, int channels, int fp16,
                  const unsigned char *names, int names_len) {
  if (planar_f32 == 0 || data_len <= 0 || width <= 0 || height <= 0 ||
      channels <= 0 || channels > EXRPROBE_MAX_CHANNELS) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT, "exr: bad save spec");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  if (names == 0 || names_len <= 0) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT, "exr: no channel names");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  long need = (long)width * (long)height * (long)channels * 4L;
  if ((long)data_len != need) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: planar data size mismatch");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }

  exrprobe_clear_all();

  EXRHeader header;
  InitEXRHeader(&header);
  header.num_channels = channels;
  header.compression_type = TINYEXR_COMPRESSIONTYPE_NONE;
  header.channels =
      static_cast<EXRChannelInfo *>(malloc(sizeof(EXRChannelInfo) * (size_t)channels));
  header.pixel_types = static_cast<int *>(malloc(sizeof(int) * (size_t)channels));
  header.requested_pixel_types =
      static_cast<int *>(malloc(sizeof(int) * (size_t)channels));
  if (header.channels == 0 || header.pixel_types == 0 ||
      header.requested_pixel_types == 0) {
    FreeEXRHeader(&header);
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT, "exr: out of memory");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  memset(header.channels, 0, sizeof(EXRChannelInfo) * (size_t)channels);

  int pos = 0;
  for (int c = 0; c < channels; c++) {
    int start = pos;
    while (pos < names_len && names[pos] != 0) pos++;
    int len = pos - start;
    if (pos >= names_len || len <= 0 || len > 255) {
      FreeEXRHeader(&header);
      exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                         "exr: malformed channel name blob");
      return TINYEXR_ERROR_INVALID_ARGUMENT;
    }
    memcpy(header.channels[c].name, names + start, (size_t)len);
    header.channels[c].name[len] = 0;  // bounded: len <= 255, buffer is 256
    header.channels[c].pixel_type = TINYEXR_PIXELTYPE_FLOAT;
    header.channels[c].x_sampling = 1;
    header.channels[c].y_sampling = 1;
    header.pixel_types[c] = TINYEXR_PIXELTYPE_FLOAT;
    header.requested_pixel_types[c] =
        fp16 != 0 ? TINYEXR_PIXELTYPE_HALF : TINYEXR_PIXELTYPE_FLOAT;
    pos++;  // skip the NUL
  }

  unsigned char **planes =
      static_cast<unsigned char **>(malloc(sizeof(unsigned char *) * (size_t)channels));
  if (planes == 0) {
    FreeEXRHeader(&header);
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT, "exr: out of memory");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  EXRImage image;
  InitEXRImage(&image);
  image.num_channels = channels;
  image.width = width;
  image.height = height;
  for (int c = 0; c < channels; c++) {
    planes[c] = const_cast<unsigned char *>(planar_f32) +
                (long)c * (long)width * (long)height * 4L;
  }
  image.images = planes;

  const char *error = 0;
  unsigned char *memory = 0;
  size_t size = SaveEXRImageToMemory(&image, &header, &memory, &error);
  free(planes);
  if (size == 0 || memory == 0) {
    exrprobe_take_error(TINYEXR_ERROR_SERIALIZATION_FAILED, error);
    FreeEXRHeader(&header);
    return TINYEXR_ERROR_SERIALIZATION_FAILED;
  }
  FreeEXRHeader(&header);
  g.saved = memory;
  g.saved_size = (long)size;
  exrprobe_set_error(TINYEXR_SUCCESS, "");
  return TINYEXR_SUCCESS;
}

int exrprobe_saved_size(void) { return (int)g.saved_size; }

int exrprobe_saved_copy(unsigned char *dst, int cap) {
  if (dst == 0 || cap < 0 || g.saved == 0 || g.saved_size <= 0) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: no saved buffer");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  if ((long)cap < g.saved_size) {
    exrprobe_set_error(TINYEXR_ERROR_INVALID_ARGUMENT,
                       "exr: saved target too small");
    return TINYEXR_ERROR_INVALID_ARGUMENT;
  }
  memcpy(dst, g.saved, (size_t)g.saved_size);
  return (int)g.saved_size;
}

// ---- error state / release ------------------------------------------------

int exrprobe_error_code(void) { return g.error_code; }

const char *exrprobe_error_message(void) { return g.error_message; }

void exrprobe_release(void) {
  exrprobe_clear_all();
  exrprobe_set_error(TINYEXR_SUCCESS, "");
}

}  // extern "C"
