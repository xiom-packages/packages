#ifndef XVK_FONT_H_
#define XVK_FONT_H_

#include <stdint.h>

/*
 * Phase 8.3: Font / text rendering module.
 *
 * Provides GPU-accelerated text rendering using a TrueType font atlas.
 * Uses stb_truetype internally for glyph rasterization.
 *
 * Workflow:
 *   1. Load font data from memory: xvk_font_create(font_data, data_size, pixel_height)
 *   2. Upload atlas to GPU:       xvk_font_upload_atlas(font, ...) — creates VkImage
 *   3. Get glyph quad for text:   xvk_font_get_glyph_quad(font, ch, ...) — returns UV+pos
 *   4. Render using quad pipeline  — caller draws quads with atlas texture
 *   5. Destroy:                   xvk_font_destroy(font)
 *
 * Atlas layout: single-channel R8_UNORM texture, 512x512, ASCII 32-126.
 * Each glyph is 8-bit grayscale; caller blends using vertex colors.
 */

/* Font handle — wraps glyph metrics and atlas pixel data. */
typedef struct XvkFont XvkFont;

/* Maximum glyphs in the atlas (ASCII 32-126 = 95 printable characters). */
#define XVK_FONT_GLYPH_COUNT 95

/* Atlas texture dimensions (power of two for compatibility). */
#define XVK_FONT_ATLAS_SIZE 512

/* Glyph metrics for a single character. */
typedef struct {
    int32_t   codepoint;     /* Unicode codepoint */
    float     advance;       /* horizontal advance in pixels */
    float     bearing_x;     /* left side bearing */
    float     bearing_y;     /* top side bearing (ascent) */
    float     width;         /* glyph width in pixels */
    float     height;        /* glyph height in pixels */
    float     uv_x;          /* atlas UV left (0.0 - 1.0) */
    float     uv_y;          /* atlas UV top (0.0 - 1.0) */
    float     uv_w;          /* atlas UV width */
    float     uv_h;          /* atlas UV height */
} XvkFontGlyph;

/* Create a font from TrueType/OpenType font data in memory.
 * font_data:  pointer to raw .ttf/.otf file bytes
 * data_size:  size of font_data in bytes
 * px_height:  target pixel height for glyph rasterization (e.g. 24, 48)
 * Returns:    font handle (> 0) or 0 on failure. */
int64_t xvk_font_create(int64_t font_data, int32_t data_size, float px_height);

/* Get the number of glyphs in the font atlas. */
int32_t xvk_font_get_glyph_count(int64_t font);

/* Get glyph metrics for a specific codepoint (32-126 for ASCII).
 * Returns 1 if glyph found and written to out_glyph, 0 if not found. */
int32_t xvk_font_get_glyph(int64_t font, int32_t codepoint, int64_t out_glyph);

/* Get the atlas raw pixel data (R8, XVK_FONT_ATLAS_SIZE x XVK_FONT_ATLAS_SIZE bytes).
 * out_width, out_height: receives atlas dimensions.
 * Returns: pointer to atlas pixel buffer (owned by font, valid until font is destroyed). */
int64_t xvk_font_get_atlas_pixels(int64_t font, int64_t out_width, int64_t out_height);

/* Get font metrics: ascender, descender, line_gap (in pixels).
 * out_metrics: pointer to float[3] — receives {ascender, descender, line_gap}. */
void xvk_font_get_metrics(int64_t font, int64_t out_metrics);

/* Measure the width of a text string (NUL-terminated UTF-8) in pixels. */
float xvk_font_measure_text(int64_t font, const char* text);

/* Destroy a font and free all associated resources.
 * Does NOT destroy the atlas texture image — caller manages that separately
 * (atlas pixels are obtained via xvk_font_get_atlas_pixels and uploaded
 * by the caller through xvk_texture_create). */
void xvk_font_destroy(int64_t font);

/* Phase 8.3 extension: Render text to RGBA8 pixel buffer.
 * White text on transparent background. Returns malloc'd buffer;
 * caller frees with xvk_font_free_pixels. out_w/out_h receive dimensions. */
int64_t xvk_font_render_text(int64_t font, const char* text,
                              int64_t out_width, int64_t out_height);
void xvk_font_free_pixels(int64_t pixels);

/* Procedural RGBA8 texture generators (malloc'd, free with xvk_free_pixels). */
int64_t xvk_proc_texture_solid(int32_t width, int32_t height,
                                float r, float g, float b);
int64_t xvk_proc_texture_gradient(int32_t width, int32_t height,
                                   float r1, float g1, float b1,
                                   float r2, float g2, float b2,
                                   int32_t horizontal);
void xvk_free_pixels(int64_t pixels);

/* TTF font loading via stb_truetype. Creates a baked font atlas (512x512 R8). */
int64_t xvk_font_create_from_file(const char* filepath, float px_height,
                                   int64_t out_atlas_w, int64_t out_atlas_h);

/* Audio feedback for UI interactions (Win32 MessageBeep or no-op). */
void xvk_audio_beep(void);

#endif
