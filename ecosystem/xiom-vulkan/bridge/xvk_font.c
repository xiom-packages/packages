#include "xvk_font.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

/* ========================================================================
 * Built-in 8x13 bitmap font (console font, ASCII 32-126, 95 glyphs).
 * Each glyph: 13 rows of 1 byte each (8 pixels wide, MSB = leftmost).
 * Data: glyphs[glyph_index * 13 + row], row 0 = top.
 * ======================================================================== */
static const unsigned char g_font_data[95 * 13] = {
    /* 32 (space) */
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    /* 33 ! */ 0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x00,0x18,0x18,0x00,0x00,0x00,
    /* 34 " */ 0x66,0x66,0x66,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    /* 35 # */ 0x00,0x24,0x24,0x7E,0x24,0x24,0x7E,0x24,0x24,0x00,0x00,0x00,0x00,
    /* 36 $ */ 0x08,0x3E,0x49,0x48,0x3E,0x09,0x49,0x3E,0x08,0x00,0x00,0x00,0x00,
    /* 37 % */ 0x61,0x92,0x94,0x68,0x10,0x2C,0x52,0x92,0x8C,0x00,0x00,0x00,0x00,
    /* 38 & */ 0x38,0x44,0x44,0x28,0x30,0x4A,0x46,0x46,0x3A,0x00,0x00,0x00,0x00,
    /* 39 ' */ 0x18,0x18,0x18,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    /* 40 ( */ 0x0C,0x10,0x20,0x20,0x20,0x20,0x20,0x10,0x0C,0x00,0x00,0x00,0x00,
    /* 41 ) */ 0x30,0x08,0x04,0x04,0x04,0x04,0x04,0x08,0x30,0x00,0x00,0x00,0x00,
    /* 42 * */ 0x00,0x00,0x08,0x49,0x2A,0x1C,0x2A,0x49,0x08,0x00,0x00,0x00,0x00,
    /* 43 + */ 0x00,0x00,0x08,0x08,0x08,0x7F,0x08,0x08,0x08,0x00,0x00,0x00,0x00,
    /* 44 , */ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x08,0x10,0x00,0x00,
    /* 45 - */ 0x00,0x00,0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    /* 46 . */ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x00,
    /* 47 / */ 0x02,0x04,0x04,0x08,0x08,0x10,0x20,0x20,0x40,0x00,0x00,0x00,0x00,
    /* 48 0 */ 0x3C,0x42,0x46,0x4A,0x52,0x62,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 49 1 */ 0x08,0x18,0x38,0x08,0x08,0x08,0x08,0x08,0x3E,0x00,0x00,0x00,0x00,
    /* 50 2 */ 0x3C,0x42,0x02,0x04,0x08,0x10,0x20,0x40,0x7E,0x00,0x00,0x00,0x00,
    /* 51 3 */ 0x3C,0x42,0x02,0x04,0x18,0x04,0x02,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 52 4 */ 0x04,0x0C,0x14,0x24,0x44,0x7E,0x04,0x04,0x04,0x00,0x00,0x00,0x00,
    /* 53 5 */ 0x7E,0x40,0x40,0x7C,0x42,0x02,0x02,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 54 6 */ 0x1C,0x20,0x40,0x40,0x7C,0x42,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 55 7 */ 0x7E,0x02,0x04,0x08,0x10,0x10,0x20,0x20,0x20,0x00,0x00,0x00,0x00,
    /* 56 8 */ 0x3C,0x42,0x42,0x42,0x3C,0x42,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 57 9 */ 0x3C,0x42,0x42,0x42,0x3E,0x02,0x02,0x04,0x38,0x00,0x00,0x00,0x00,
    /* 58 : */ 0x00,0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x00,0x00,
    /* 59 ; */ 0x00,0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x08,0x10,0x00,0x00,0x00,
    /* 60 < */ 0x00,0x04,0x08,0x10,0x20,0x40,0x20,0x10,0x08,0x04,0x00,0x00,0x00,
    /* 61 = */ 0x00,0x00,0x00,0x7E,0x00,0x00,0x7E,0x00,0x00,0x00,0x00,0x00,0x00,
    /* 62 > */ 0x00,0x20,0x10,0x08,0x04,0x02,0x04,0x08,0x10,0x20,0x00,0x00,0x00,
    /* 63 ? */ 0x3C,0x42,0x02,0x04,0x08,0x08,0x00,0x08,0x08,0x00,0x00,0x00,0x00,
    /* 64 @ */ 0x3C,0x42,0x4E,0x52,0x56,0x4A,0x40,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 65 A */ 0x18,0x24,0x42,0x42,0x42,0x7E,0x42,0x42,0x42,0x00,0x00,0x00,0x00,
    /* 66 B */ 0x7C,0x42,0x42,0x42,0x7C,0x42,0x42,0x42,0x7C,0x00,0x00,0x00,0x00,
    /* 67 C */ 0x3C,0x42,0x40,0x40,0x40,0x40,0x40,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 68 D */ 0x78,0x44,0x42,0x42,0x42,0x42,0x42,0x44,0x78,0x00,0x00,0x00,0x00,
    /* 69 E */ 0x7E,0x40,0x40,0x40,0x7C,0x40,0x40,0x40,0x7E,0x00,0x00,0x00,0x00,
    /* 70 F */ 0x7E,0x40,0x40,0x40,0x7C,0x40,0x40,0x40,0x40,0x00,0x00,0x00,0x00,
    /* 71 G */ 0x3C,0x42,0x40,0x40,0x4E,0x42,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 72 H */ 0x42,0x42,0x42,0x42,0x7E,0x42,0x42,0x42,0x42,0x00,0x00,0x00,0x00,
    /* 73 I */ 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x7E,0x00,0x00,0x00,0x00,
    /* 74 J */ 0x1E,0x04,0x04,0x04,0x04,0x04,0x04,0x44,0x38,0x00,0x00,0x00,0x00,
    /* 75 K */ 0x42,0x44,0x48,0x50,0x60,0x50,0x48,0x44,0x42,0x00,0x00,0x00,0x00,
    /* 76 L */ 0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x40,0x7E,0x00,0x00,0x00,0x00,
    /* 77 M */ 0x42,0x66,0x5A,0x5A,0x42,0x42,0x42,0x42,0x42,0x00,0x00,0x00,0x00,
    /* 78 N */ 0x42,0x62,0x52,0x4A,0x46,0x42,0x42,0x42,0x42,0x00,0x00,0x00,0x00,
    /* 79 O */ 0x3C,0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 80 P */ 0x7C,0x42,0x42,0x42,0x7C,0x40,0x40,0x40,0x40,0x00,0x00,0x00,0x00,
    /* 81 Q */ 0x3C,0x42,0x42,0x42,0x42,0x42,0x4A,0x44,0x3A,0x00,0x00,0x00,0x00,
    /* 82 R */ 0x7C,0x42,0x42,0x42,0x7C,0x48,0x44,0x42,0x42,0x00,0x00,0x00,0x00,
    /* 83 S */ 0x3C,0x42,0x40,0x30,0x0C,0x02,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 84 T */ 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x00,0x00,0x00,0x00,
    /* 85 U */ 0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /* 86 V */ 0x42,0x42,0x42,0x42,0x42,0x24,0x24,0x18,0x18,0x00,0x00,0x00,0x00,
    /* 87 W */ 0x42,0x42,0x42,0x42,0x42,0x5A,0x5A,0x66,0x42,0x00,0x00,0x00,0x00,
    /* 88 X */ 0x42,0x42,0x24,0x18,0x18,0x18,0x24,0x42,0x42,0x00,0x00,0x00,0x00,
    /* 89 Y */ 0x42,0x42,0x24,0x18,0x18,0x18,0x18,0x18,0x18,0x00,0x00,0x00,0x00,
    /* 90 Z */ 0x7E,0x02,0x04,0x08,0x10,0x20,0x40,0x40,0x7E,0x00,0x00,0x00,0x00,
    /* 91 [ */ 0x3C,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x3C,0x00,0x00,0x00,0x00,
    /* 92 \ */ 0x40,0x20,0x20,0x10,0x10,0x08,0x04,0x04,0x02,0x00,0x00,0x00,0x00,
    /* 93 ] */ 0x3C,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x3C,0x00,0x00,0x00,0x00,
    /* 94 ^ */ 0x18,0x24,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    /* 95 _ */ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x00,0x00,0x00,0x00,
    /* 96 ` */ 0x30,0x18,0x0C,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    /* 97 a */ 0x00,0x00,0x38,0x04,0x3C,0x44,0x44,0x44,0x3E,0x00,0x00,0x00,0x00,
    /* 98 b */ 0x40,0x40,0x78,0x44,0x42,0x42,0x42,0x44,0x78,0x00,0x00,0x00,0x00,
    /* 99 c */ 0x00,0x00,0x3C,0x42,0x40,0x40,0x40,0x42,0x3C,0x00,0x00,0x00,0x00,
    /*100 d */ 0x02,0x02,0x1E,0x22,0x42,0x42,0x42,0x22,0x1E,0x00,0x00,0x00,0x00,
    /*101 e */ 0x00,0x00,0x3C,0x42,0x42,0x7E,0x40,0x42,0x3C,0x00,0x00,0x00,0x00,
    /*102 f */ 0x0E,0x10,0x10,0x7C,0x10,0x10,0x10,0x10,0x10,0x00,0x00,0x00,0x00,
    /*103 g */ 0x00,0x00,0x3E,0x42,0x42,0x3E,0x02,0x42,0x3C,0x00,0x00,0x00,0x00,
    /*104 h */ 0x40,0x40,0x78,0x44,0x42,0x42,0x42,0x42,0x42,0x00,0x00,0x00,0x00,
    /*105 i */ 0x18,0x00,0x38,0x18,0x18,0x18,0x18,0x18,0x7E,0x00,0x00,0x00,0x00,
    /*106 j */ 0x04,0x00,0x0C,0x04,0x04,0x04,0x04,0x44,0x38,0x00,0x00,0x00,0x00,
    /*107 k */ 0x40,0x40,0x44,0x48,0x70,0x48,0x44,0x42,0x42,0x00,0x00,0x00,0x00,
    /*108 l */ 0x38,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x7E,0x00,0x00,0x00,0x00,
    /*109 m */ 0x00,0x00,0x6C,0x52,0x52,0x52,0x52,0x52,0x52,0x00,0x00,0x00,0x00,
    /*110 n */ 0x00,0x00,0x78,0x44,0x42,0x42,0x42,0x42,0x42,0x00,0x00,0x00,0x00,
    /*111 o */ 0x00,0x00,0x3C,0x42,0x42,0x42,0x42,0x42,0x3C,0x00,0x00,0x00,0x00,
    /*112 p */ 0x00,0x00,0x78,0x44,0x42,0x7C,0x40,0x40,0x40,0x00,0x00,0x00,0x00,
    /*113 q */ 0x00,0x00,0x1E,0x22,0x42,0x3E,0x02,0x02,0x02,0x00,0x00,0x00,0x00,
    /*114 r */ 0x00,0x00,0x5C,0x62,0x40,0x40,0x40,0x40,0x40,0x00,0x00,0x00,0x00,
    /*115 s */ 0x00,0x00,0x3C,0x42,0x30,0x0C,0x02,0x42,0x3C,0x00,0x00,0x00,0x00,
    /*116 t */ 0x10,0x10,0x7C,0x10,0x10,0x10,0x10,0x10,0x0E,0x00,0x00,0x00,0x00,
    /*117 u */ 0x00,0x00,0x42,0x42,0x42,0x42,0x42,0x22,0x1E,0x00,0x00,0x00,0x00,
    /*118 v */ 0x00,0x00,0x42,0x42,0x42,0x24,0x24,0x18,0x18,0x00,0x00,0x00,0x00,
    /*119 w */ 0x00,0x00,0x42,0x42,0x42,0x5A,0x5A,0x5A,0x24,0x00,0x00,0x00,0x00,
    /*120 x */ 0x00,0x00,0x42,0x24,0x18,0x18,0x18,0x24,0x42,0x00,0x00,0x00,0x00,
    /*121 y */ 0x00,0x00,0x42,0x42,0x22,0x1E,0x02,0x42,0x3C,0x00,0x00,0x00,0x00,
    /*122 z */ 0x00,0x00,0x7E,0x04,0x08,0x10,0x20,0x40,0x7E,0x00,0x00,0x00,0x00,
    /*123 { */ 0x0E,0x10,0x10,0x10,0x60,0x10,0x10,0x10,0x0E,0x00,0x00,0x00,0x00,
    /*124 | */ 0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x00,0x00,0x00,0x00,
    /*125 } */ 0x70,0x08,0x08,0x08,0x06,0x08,0x08,0x08,0x70,0x00,0x00,0x00,0x00,
    /*126 ~ */ 0x00,0x00,0x00,0x32,0x4C,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
};

#define GF_SRC_W  8    /* source glyph width in pixels */
#define GF_SRC_H  13   /* source glyph height in pixels */
#define GF_ASCENT 11   /* baseline from top of glyph */

struct XvkFont {
    XvkFontGlyph glyphs[XVK_FONT_GLYPH_COUNT];
    unsigned char atlas[XVK_FONT_ATLAS_SIZE * XVK_FONT_ATLAS_SIZE];
    float px_height;
    float scale;
    float ascender;
    float descender;
    float line_gap;
    int   glyph_cell_w;
    int   glyph_cell_h;
    int   cols;
    int   atlas_w, atlas_h;
    int   is_ttf;          /* 1 = TTF font, 0 = built-in bitmap */
};

/* ---- Helper: pack glyphs into atlas grid ---- */
static void pack_atlas(struct XvkFont* f)
{
    float scale = f->scale;
    int cell_w = (int)ceilf(GF_SRC_W * scale) + 2;   /* +2 for padding */
    int cell_h = (int)ceilf(GF_SRC_H * scale) + 2;
    int cols = XVK_FONT_ATLAS_SIZE / cell_w;
    if (cols < 1) cols = 1;
    if (cols > XVK_FONT_GLYPH_COUNT) cols = XVK_FONT_GLYPH_COUNT;

    f->glyph_cell_w = cell_w;
    f->glyph_cell_h = cell_h;
    f->cols = cols;
    f->atlas_w = cols * cell_w;
    f->atlas_h = ((XVK_FONT_GLYPH_COUNT + cols - 1) / cols) * cell_h;
    if (f->atlas_w > XVK_FONT_ATLAS_SIZE) f->atlas_w = XVK_FONT_ATLAS_SIZE;
    if (f->atlas_h > XVK_FONT_ATLAS_SIZE) f->atlas_h = XVK_FONT_ATLAS_SIZE;

    memset(f->atlas, 0, (size_t)(f->atlas_w * f->atlas_h));

    for (int g = 0; g < XVK_FONT_GLYPH_COUNT; g++) {
        int col = g % cols;
        int row = g / cols;
        int ax = col * cell_w + 1;  /* +1 padding */
        int ay = row * cell_h + 1;

        const unsigned char* src = &g_font_data[g * GF_SRC_H];

        /* Scale the source glyph into the atlas */
        for (int sy = 0; sy < GF_SRC_H; sy++) {
            int dst_y_start = ay + (int)(sy * scale);
            int dst_y_end   = ay + (int)((sy + 1) * scale);
            if (dst_y_end > dst_y_start + 3) dst_y_end = dst_y_start + 3; /* cap */
            if (dst_y_end >= f->atlas_h) break;

            unsigned char row_bits = src[sy];
            for (int sx = 0; sx < GF_SRC_W; sx++) {
                if (!(row_bits & (0x80 >> sx))) continue;

                int dst_x_start = ax + (int)(sx * scale);
                int dst_x_end   = ax + (int)((sx + 1) * scale);
                if (dst_x_end > dst_x_start + 3) dst_x_end = dst_x_start + 3;

                for (int dy = dst_y_start; dy < dst_y_end && dy < f->atlas_h; dy++) {
                    for (int dx = dst_x_start; dx < dst_x_end && dx < f->atlas_w; dx++) {
                        int idx = dy * f->atlas_w + dx;
                        if (idx >= 0 && idx < f->atlas_w * f->atlas_h)
                            f->atlas[idx] = 255;  /* white pixel */
                    }
                }
            }
        }

        /* Fill glyph metrics */
        XvkFontGlyph* gl = &f->glyphs[g];
        gl->codepoint = 32 + g;
        gl->advance   = (float)cell_w;
        gl->bearing_x = 1.0f / f->atlas_w;
        gl->bearing_y = (float)(GF_ASCENT * scale) / (float)f->atlas_h;
        gl->width     = (float)(cell_w - 2) * scale;  /* approximate */
        gl->height    = (float)cell_h;
        gl->uv_x      = (float)(col * cell_w) / (float)f->atlas_w;
        gl->uv_y      = (float)(row * cell_h) / (float)f->atlas_h;
        gl->uv_w      = (float)cell_w / (float)f->atlas_w;
        gl->uv_h      = (float)cell_h / (float)f->atlas_h;
    }
}

/* ---- PUBLIC API ---- */

int64_t xvk_font_create(int64_t font_data, int32_t data_size, float px_height)
{
    (void)font_data; (void)data_size; /* built-in font, ignore external data */

    if (px_height <= 0.0f) { px_height = 13.0f; }
    float scale = px_height / (float)GF_SRC_H;
    if (scale < 0.5f) scale = 0.5f;

    struct XvkFont* f = (struct XvkFont*)calloc(1, sizeof(struct XvkFont));
    if (!f) return 0;

    f->px_height = px_height;
    f->scale     = scale;
    f->ascender  = (float)GF_ASCENT * scale;
    f->descender = -(float)(GF_SRC_H - GF_ASCENT) * scale;
    f->line_gap  = fmaxf(1.0f, scale * 2.0f);

    pack_atlas(f);
    return (int64_t)(intptr_t)f;
}

int32_t xvk_font_get_glyph_count(int64_t font)
{
    if (!font) return 0;
    return XVK_FONT_GLYPH_COUNT;
}

int32_t xvk_font_get_glyph(int64_t font, int32_t codepoint, int64_t out_glyph)
{
    if (!font || !out_glyph) return 0;
    struct XvkFont* f = (struct XvkFont*)(intptr_t)font;
    if (codepoint < 32 || codepoint > 126) return 0;

    int idx = codepoint - 32;
    XvkFontGlyph* dst = (XvkFontGlyph*)(intptr_t)out_glyph;
    memcpy(dst, &f->glyphs[idx], sizeof(XvkFontGlyph));
    return 1;
}

int64_t xvk_font_get_atlas_pixels(int64_t font, int64_t out_width, int64_t out_height)
{
    if (!font) return 0;
    struct XvkFont* f = (struct XvkFont*)(intptr_t)font;

    int32_t* w = (int32_t*)(intptr_t)out_width;
    int32_t* h = (int32_t*)(intptr_t)out_height;
    if (w) *w = f->atlas_w;
    if (h) *h = f->atlas_h;

    return (int64_t)(intptr_t)f->atlas;
}

void xvk_font_get_metrics(int64_t font, int64_t out_metrics)
{
    if (!font || !out_metrics) return;
    struct XvkFont* f = (struct XvkFont*)(intptr_t)font;
    float* m = (float*)(intptr_t)out_metrics;
    m[0] = f->ascender;
    m[1] = f->descender;
    m[2] = f->line_gap;
}

float xvk_font_measure_text(int64_t font, const char* text)
{
    if (!font || !text) return 0.0f;
    struct XvkFont* f = (struct XvkFont*)(intptr_t)font;
    float width = 0.0f;
    float cell_w = (float)f->glyph_cell_w;
    while (*text) {
        width += cell_w;
        text++;
    }
    return width;
}

void xvk_font_destroy(int64_t font)
{
    if (!font) return;
    free((void*)(intptr_t)font);
}

/* ========================================================================
 * Phase 8.3 extension: Text rendering to RGBA8 pixel buffer.
 * Renders a text string into an RGBA8 (4 bytes/pixel) buffer suitable
 * for upload via xvk_texture_create. White text on transparent background.
 * The returned buffer is malloc'd; caller must free it.
 * out_width / out_height receive the rendered pixel dimensions.
 * ======================================================================== */

int64_t xvk_font_render_text(int64_t font, const char* text,
                              int64_t out_width, int64_t out_height)
{
    if (!font || !text) return 0;
    struct XvkFont* f = (struct XvkFont*)(intptr_t)font;

    int text_len = (int)strlen(text);
    if (text_len == 0) return 0;

    /* Determine rendering mode: TTF atlas or built-in bitmap */
    int use_ttf = f->is_ttf;

    int total_w = 0, max_h = 0;

    if (use_ttf) {
        /* Measure total width and height from glyph metrics */
        for (int ci = 0; ci < text_len; ci++) {
            unsigned char ch = (unsigned char)text[ci];
            if (ch < 32 || ch > 126) ch = '?';
            int idx = ch - 32;
            XvkFontGlyph* g = &f->glyphs[idx];
            if (g->width > 0) {
                total_w += (int)(g->advance > 0 ? g->advance : g->width + 2);
                int gh = (int)g->height + 2;
                if (gh > max_h) max_h = gh;
            }
        }
        if (max_h < 8) max_h = (int)(f->px_height * 1.4f);
        if (total_w < 4) total_w = 4;

        int px_w = total_w + 4;
        int px_h = max_h + 4;
        unsigned char* pixels = (unsigned char*)calloc((size_t)(px_w * px_h * 4), 1);
        if (!pixels) return 0;

        /* Render each glyph from the atlas */
        int xpos = 2;
        for (int ci = 0; ci < text_len; ci++) {
            unsigned char ch = (unsigned char)text[ci];
            if (ch < 32 || ch > 126) ch = '?';
            int idx = ch - 32;
            XvkFontGlyph* g = &f->glyphs[idx];
            if (g->width <= 0) { xpos += 4; continue; }

            int dst_x = xpos + (int)g->bearing_x;
            int dst_y = 2;
            int gw = (int)g->width;
            int gh = (int)g->height;

            /* Source region in atlas */
            int src_x = (int)(g->uv_x * (float)f->atlas_w);
            int src_y = (int)(g->uv_y * (float)f->atlas_h);
            int src_w = (int)(g->uv_w * (float)f->atlas_w);

            for (int sy = 0; sy < gh && sy < px_h - dst_y; sy++) {
                for (int sx = 0; sx < gw && sx < px_w - dst_x; sx++) {
                    int atlas_idx = (src_y + sy) * f->atlas_w + (src_x + sx);
                    if (atlas_idx >= 0 && atlas_idx < f->atlas_w * f->atlas_h) {
                        unsigned char a = f->atlas[atlas_idx];
                        if (a > 0) {
                            int pi = ((dst_y + sy) * px_w + (dst_x + sx)) * 4;
                            pixels[pi + 0] = 255;
                            pixels[pi + 1] = 255;
                            pixels[pi + 2] = 255;
                            pixels[pi + 3] = a;
                        }
                    }
                }
            }

            xpos += (int)(g->advance > 0 ? g->advance : gw + 2);
        }

        int32_t* w_ptr = (int32_t*)(intptr_t)out_width;
        int32_t* h_ptr = (int32_t*)(intptr_t)out_height;
        if (w_ptr) *w_ptr = px_w;
        if (h_ptr) *h_ptr = px_h;
        return (int64_t)(intptr_t)pixels;
    }

    /* ── Built-in bitmap fallback ── */
    int cell_w = f->glyph_cell_w;
    int cell_h = f->glyph_cell_h;
    int px_w = cell_w * text_len + 4;
    int px_h = cell_h + 4;
    if (px_w < 4) px_w = 4;
    if (px_h < 4) px_h = 4;

    unsigned char* pixels = (unsigned char*)calloc((size_t)(px_w * px_h * 4), 1);
    if (!pixels) return 0;

    for (int ci = 0; ci < text_len; ci++) {
        unsigned char ch = (unsigned char)text[ci];
        if (ch < 32 || ch > 126) { ch = '?'; }
        int glyph_idx = ch - 32;
        int dst_x = 2 + ci * cell_w;
        int dst_y = 2;
        const unsigned char* src = &g_font_data[glyph_idx * GF_SRC_H];
        float scale = f->scale;
        for (int sy = 0; sy < GF_SRC_H; sy++) {
            unsigned char row = src[sy];
            for (int sx = 0; sx < GF_SRC_W; sx++) {
                if (!(row & (0x80 >> sx))) continue;
                int py_start = dst_y + (int)((float)sy * scale);
                int py_end   = dst_y + (int)((float)(sy + 1) * scale);
                if (py_end > py_start + 3) py_end = py_start + 3;
                int px_start = dst_x + (int)((float)sx * scale);
                int px_end   = dst_x + (int)((float)(sx + 1) * scale);
                if (px_end > px_start + 3) px_end = px_start + 3;
                for (int py = py_start; py < py_end && py < px_h; py++) {
                    for (int px = px_start; px < px_end && px < px_w; px++) {
                        int idx = (py * px_w + px) * 4;
                        pixels[idx + 0] = 255;
                        pixels[idx + 1] = 255;
                        pixels[idx + 2] = 255;
                        pixels[idx + 3] = 255;
                    }
                }
            }
        }
    }

    int32_t* w_ptr = (int32_t*)(intptr_t)out_width;
    int32_t* h_ptr = (int32_t*)(intptr_t)out_height;
    if (w_ptr) *w_ptr = px_w;
    if (h_ptr) *h_ptr = px_h;
    return (int64_t)(intptr_t)pixels;
}

void xvk_font_free_pixels(int64_t pixels)
{
    if (pixels) free((void*)(intptr_t)pixels);
}

/* ========================================================================
 * Procedural texture generators — RGBA8 pixel buffers.
 * Useful for UI backgrounds, button faces, gradients without external files.
 * All returned buffers are malloc'd; caller must free with xvk_free_pixels.
 * ======================================================================== */

int64_t xvk_proc_texture_solid(int32_t width, int32_t height,
                                float r, float g, float b)
{
    if (width <= 0 || height <= 0) return 0;
    int size = width * height * 4;
    unsigned char* px = (unsigned char*)malloc((size_t)size);
    if (!px) return 0;
    unsigned char rb = (unsigned char)(r * 255.0f);
    unsigned char gb = (unsigned char)(g * 255.0f);
    unsigned char bb = (unsigned char)(b * 255.0f);
    for (int i = 0; i < size; i += 4) {
        px[i] = rb; px[i+1] = gb; px[i+2] = bb; px[i+3] = 255;
    }
    return (int64_t)(intptr_t)px;
}

int64_t xvk_proc_texture_gradient(int32_t width, int32_t height,
                                   float r1, float g1, float b1,
                                   float r2, float g2, float b2,
                                   int32_t horizontal)
{
    if (width <= 0 || height <= 0) return 0;
    int size = width * height * 4;
    unsigned char* px = (unsigned char*)malloc((size_t)size);
    if (!px) return 0;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            float t = horizontal ? ((float)x / (float)(width - 1)) :
                                   ((float)y / (float)(height - 1));
            if (t < 0.0f) t = 0.0f;
            if (t > 1.0f) t = 1.0f;
            int idx = (y * width + x) * 4;
            px[idx]   = (unsigned char)((r1 + (r2 - r1) * t) * 255.0f);
            px[idx+1] = (unsigned char)((g1 + (g2 - g1) * t) * 255.0f);
            px[idx+2] = (unsigned char)((b1 + (b2 - b1) * t) * 255.0f);
            px[idx+3] = 255;
        }
    }
    return (int64_t)(intptr_t)px;
}

void xvk_free_pixels(int64_t pixels)
{
    if (pixels) free((void*)(intptr_t)pixels);
}

/* ========================================================================
 * TTF Font loading via stb_truetype (Phase 8.3 extension)
 * ======================================================================== */
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

/* Load a TrueType font from file and bake a bitmap atlas.
 * Replaces the built-in font with the TTF version.
 * Returns: font handle (> 0) or 0 on failure.
 * pixel_height: desired font height in pixels (e.g. 24, 48).
 * The atlas is a 512x512 R8 bitmap suitable for xvk_texture_create. */
int64_t xvk_font_create_from_file(const char* filepath, float px_height,
                                   int64_t out_atlas_w, int64_t out_atlas_h)
{
    if (!filepath || !out_atlas_w || !out_atlas_h) return 0;

    FILE* f = fopen(filepath, "rb");
    if (!f) return 0;

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0 || sz > (32 * 1024 * 1024)) { fclose(f); return 0; }

    unsigned char* ttf_data = (unsigned char*)malloc((size_t)sz);
    if (!ttf_data) { fclose(f); return 0; }
    size_t read = fread(ttf_data, 1, (size_t)sz, f);
    fclose(f);

    if (read != (size_t)sz) { free(ttf_data); return 0; }

    /* Prepare atlas */
    int atlas_w = 512, atlas_h = 512;
    unsigned char* atlas = (unsigned char*)malloc((size_t)(atlas_w * atlas_h));
    if (!atlas) { free(ttf_data); return 0; }

    /* Bake font bitmap for ASCII 32-126 */
    stbtt_bakedchar baked[95];
    int result = stbtt_BakeFontBitmap(ttf_data, 0, px_height,
                                       atlas, atlas_w, atlas_h,
                                       32, 95, baked);
    free(ttf_data);

    if (result <= 0) { free(atlas); return 0; }

    /* Build XvkFontGlyph array from baked chars */
    struct XvkFont* fnt = (struct XvkFont*)calloc(1, sizeof(struct XvkFont));
    if (!fnt) { free(atlas); return 0; }

    fnt->px_height = px_height;
    fnt->is_ttf    = 1;
    fnt->scale     = 1.0f;
    fnt->ascender  = 0.0f;
    fnt->descender = 0.0f;
    fnt->line_gap  = 0.0f;
    fnt->atlas_w   = atlas_w;
    fnt->atlas_h   = atlas_h;
    fnt->glyph_cell_w = 0;
    fnt->glyph_cell_h = 0;
    fnt->cols          = 1;

    /* Copy atlas into font structure */
    memcpy(fnt->atlas, atlas, (size_t)(atlas_w * atlas_h));
    free(atlas);

    /* Fill glyph metrics from baked chars */
    for (int i = 0; i < 95; i++) {
        XvkFontGlyph* gl = &fnt->glyphs[i];
        stbtt_bakedchar* bc = &baked[i];
        gl->codepoint = 32 + i;
        gl->advance   = bc->xadvance;
        gl->bearing_x = bc->xoff;
        gl->bearing_y = bc->yoff;
        gl->width     = (float)(bc->x1 - bc->x0);
        gl->height    = (float)(bc->y1 - bc->y0);
        gl->uv_x      = bc->x0 / (float)atlas_w;
        gl->uv_y      = bc->y0 / (float)atlas_h;
        gl->uv_w      = (bc->x1 - bc->x0) / (float)atlas_w;
        gl->uv_h      = (bc->y1 - bc->y0) / (float)atlas_h;
    }

    int32_t* w_ptr = (int32_t*)(intptr_t)out_atlas_w;
    int32_t* h_ptr = (int32_t*)(intptr_t)out_atlas_h;
    if (w_ptr) *w_ptr = atlas_w;
    if (h_ptr) *h_ptr = atlas_h;

    return (int64_t)(intptr_t)fnt;
}

/* ========================================================================
 * Audio feedback (button clicks, etc.) using Win32 MessageBeep
 * ======================================================================== */
#ifdef _WIN32
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")
void xvk_audio_beep(void) { MessageBeep(0xFFFFFFFF); }
void xvk_audio_play_wav(const char* filepath) { PlaySoundA(filepath, NULL, SND_FILENAME | SND_ASYNC); }
#else
void xvk_audio_beep(void) {}
void xvk_audio_play_wav(const char* filepath) { (void)filepath; }
#endif
