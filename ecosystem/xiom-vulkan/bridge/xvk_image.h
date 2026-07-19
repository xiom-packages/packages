#ifndef XVK_IMAGE_H_
#define XVK_IMAGE_H_

#include <stdint.h>

/*
 * Thin wrapper over stb_image for loading PNG/JPG/BMP/TGA/etc.
 * into RGBA8 pixel buffers suitable for xvk_texture_create.
 *
 * Supports: PNG, JPEG, BMP, TGA, GIF, PSD, HDR, PIC, PNM.
 * Always returns 4-channel RGBA8 (forced 4 components).
 */

/* Load an image file from disk. Returns malloc'd RGBA8 pixel buffer
 * (width * height * 4 bytes). out_width/out_height receive dimensions
 * (pre-allocated int32_t pointers). Returns 0 on failure.
 * Free with xvk_image_free(). */
int64_t xvk_image_load(const char* filepath,
                        int64_t out_width, int64_t out_height);

/* Free a pixel buffer returned by xvk_image_load. No-op on 0. */
void xvk_image_free(int64_t pixels);

#endif
