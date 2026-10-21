// XIOM -- fontraster C surface. See package.xi for ownership rules.
// Coordinates from HarfBuzz are in 1/64 pixel (px_q6 scale); the raster
// output is an 8-bit coverage bitmap, top-left origin, non-zero winding,
// 8 vertical sub-scanlines and exact horizontal span coverage.

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// ---- minimal HarfBuzz ABI (symbols come from xiom.harfbuzz) ---------------

typedef struct hb_blob_t hb_blob_t;
typedef struct hb_face_t hb_face_t;
typedef struct hb_font_t hb_font_t;
typedef struct hb_draw_funcs_t hb_draw_funcs_t;
typedef void (*hb_destroy_func_t)(void *);

typedef struct hb_draw_state_t {
    int32_t path_open;
    float path_start_x;
    float path_start_y;
    float current_x;
    float current_y;
} hb_draw_state_t;

typedef struct {
    int32_t x_bearing;
    int32_t y_bearing;
    int32_t width;
    int32_t height;
} hb_glyph_extents_t;

typedef struct {
    int32_t ascender;
    int32_t descender;
    int32_t line_gap;
    // HarfBuzz private reserved slots (hb-font.h); the C function writes
    // the whole struct, so a short definition would smash the stack.
    int32_t reserved9;
    int32_t reserved8;
    int32_t reserved7;
    int32_t reserved6;
    int32_t reserved5;
    int32_t reserved4;
    int32_t reserved3;
    int32_t reserved2;
    int32_t reserved1;
} hb_font_extents_t;

extern hb_blob_t *hb_blob_create(const char *data, unsigned int length,
                                 int mode, void *user_data,
                                 hb_destroy_func_t destroy);
extern hb_face_t *hb_face_create(hb_blob_t *blob, unsigned int index);
extern unsigned int hb_face_get_upem(const hb_face_t *face);
extern void hb_face_destroy(hb_face_t *face);
extern void hb_blob_destroy(hb_blob_t *blob);

extern hb_font_t *hb_font_create(hb_face_t *face);
extern void hb_font_destroy(hb_font_t *font);
extern void hb_font_set_scale(hb_font_t *font, int x_scale, int y_scale);
extern int hb_font_get_glyph_h_advance(hb_font_t *font, uint32_t glyph);
extern int hb_font_get_glyph_extents(hb_font_t *font, uint32_t glyph,
                                     hb_glyph_extents_t *extents);
extern int hb_font_get_h_extents(hb_font_t *font, hb_font_extents_t *extents);
extern int hb_font_get_nominal_glyph(hb_font_t *font, uint32_t unicode,
                                     uint32_t *glyph);
extern void hb_font_draw_glyph(hb_font_t *font, uint32_t glyph,
                               hb_draw_funcs_t *dfuncs, void *draw_data);

extern hb_draw_funcs_t *hb_draw_funcs_create(void);
extern void hb_draw_funcs_destroy(hb_draw_funcs_t *dfuncs);
extern void hb_draw_funcs_make_immutable(hb_draw_funcs_t *dfuncs);
extern void hb_draw_funcs_set_move_to_func(hb_draw_funcs_t *dfuncs,
                                           void (*func)(hb_draw_funcs_t *, void *,
                                                        hb_draw_state_t *, float, float, void *),
                                           void *user_data, hb_destroy_func_t destroy);
extern void hb_draw_funcs_set_line_to_func(hb_draw_funcs_t *dfuncs,
                                           void (*func)(hb_draw_funcs_t *, void *,
                                                        hb_draw_state_t *, float, float, void *),
                                           void *user_data, hb_destroy_func_t destroy);
extern void hb_draw_funcs_set_quadratic_to_func(hb_draw_funcs_t *dfuncs,
                                                void (*func)(hb_draw_funcs_t *, void *,
                                                             hb_draw_state_t *, float, float,
                                                             float, float, void *),
                                                void *user_data, hb_destroy_func_t destroy);
extern void hb_draw_funcs_set_cubic_to_func(hb_draw_funcs_t *dfuncs,
                                            void (*func)(hb_draw_funcs_t *, void *,
                                                         hb_draw_state_t *, float, float,
                                                         float, float, float, float, void *),
                                            void *user_data, hb_destroy_func_t destroy);
extern void hb_draw_funcs_set_close_path_func(hb_draw_funcs_t *dfuncs,
                                              void (*func)(hb_draw_funcs_t *, void *,
                                                           hb_draw_state_t *, void *),
                                              void *user_data, hb_destroy_func_t destroy);

extern int hb_ot_metrics_get_position(hb_font_t *font, uint32_t tag,
                                      int *position);

typedef struct hb_buffer_t hb_buffer_t;
typedef struct {
    uint32_t codepoint;
    uint32_t mask;
    uint32_t cluster;
    uint32_t var1;
    uint32_t var2;
} hb_glyph_info_t;
typedef struct {
    int32_t x_advance;
    int32_t y_advance;
    int32_t x_offset;
    int32_t y_offset;
    uint32_t var;
} hb_glyph_position_t;

extern hb_buffer_t *hb_buffer_create(void);
extern int hb_buffer_allocation_successful(hb_buffer_t *buffer);
extern void hb_buffer_destroy(hb_buffer_t *buffer);
extern void hb_buffer_add_utf8(hb_buffer_t *buffer, const char *text,
                               int text_length, unsigned int item_offset,
                               int item_length);
extern void hb_buffer_guess_segment_properties(hb_buffer_t *buffer);
extern void hb_shape(hb_font_t *font, hb_buffer_t *buffer,
                     const void *features, unsigned int num_features);
extern hb_glyph_info_t *hb_buffer_get_glyph_infos(hb_buffer_t *buffer,
                                                  unsigned int *length);
extern hb_glyph_position_t *hb_buffer_get_glyph_positions(hb_buffer_t *buffer,
                                                          unsigned int *length);
extern int hb_buffer_get_direction(hb_buffer_t *buffer);

// ---- builder ----------------------------------------------------------------

#define FR_MAX_POINTS 16384
#define FR_MAX_CONTOURS 1024
#define FR_SUBSCANLINES 8
#define FR_CURVE_TOLERANCE 0.15f

typedef struct {
    float x;
    float y;
} fr_point;

typedef struct {
    fr_point *pts;
    int32_t count;
    int32_t *contour_start;
    int32_t contour_count;
    int32_t overflow;
    // Draw coordinates arrive in 26.6 px; scale converts them to pixels.
    float scale;
    float cur_x;
    float cur_y;
    float start_x;
    float start_y;
} fr_builder;

static void fr_push(fr_builder *b, float x, float y)
{
    if (b->count >= FR_MAX_POINTS) {
        b->overflow = 1;
        return;
    }
    if (b->count > 0) {
        fr_point last = b->pts[b->count - 1];
        float dx = x - last.x;
        float dy = y - last.y;
        if (dx * dx + dy * dy < 0.000001f)
            return;
    }
    b->pts[b->count].x = x;
    b->pts[b->count].y = y;
    b->count++;
}

static int fr_quad_steps(float x0, float y0, float cx, float cy,
                         float x1, float y1)
{
    float ddx = x0 - 2.0f * cx + x1;
    float ddy = y0 - 2.0f * cy + y1;
    float d = sqrtf(ddx * ddx + ddy * ddy);
    int n = (int)ceilf(sqrtf(d / FR_CURVE_TOLERANCE));
    if (n < 2) n = 2;
    if (n > 24) n = 24;
    return n;
}

static int fr_cubic_steps(float x0, float y0, float c1x, float c1y,
                          float c2x, float c2y, float x1, float y1)
{
    float d1x = x0 - 2.0f * c1x + c2x;
    float d1y = y0 - 2.0f * c1y + c2y;
    float d2x = c1x - 2.0f * c2x + x1;
    float d2y = c1y - 2.0f * c2y + y1;
    float d = sqrtf(d1x * d1x + d1y * d1y);
    float e = sqrtf(d2x * d2x + d2y * d2y);
    if (e > d) d = e;
    int n = (int)ceilf(sqrtf(d / FR_CURVE_TOLERANCE));
    if (n < 3) n = 3;
    if (n > 32) n = 32;
    return n;
}

static void fr_move_to(hb_draw_funcs_t *dfuncs, void *draw_data,
                       hb_draw_state_t *st, float x, float y, void *user_data)
{
    (void)dfuncs; (void)st; (void)user_data;
    fr_builder *b = (fr_builder *)draw_data;
    x = x * b->scale;
    y = y * b->scale;
    if (b->contour_count >= FR_MAX_CONTOURS) {
        b->overflow = 1;
        return;
    }
    b->contour_start[b->contour_count++] = b->count;
    b->cur_x = x;
    b->cur_y = y;
    b->start_x = x;
    b->start_y = y;
    fr_push(b, x, y);
}

static void fr_line_to(hb_draw_funcs_t *dfuncs, void *draw_data,
                       hb_draw_state_t *st, float x, float y, void *user_data)
{
    (void)dfuncs; (void)st; (void)user_data;
    fr_builder *b = (fr_builder *)draw_data;
    x = x * b->scale;
    y = y * b->scale;
    fr_push(b, x, y);
    b->cur_x = x;
    b->cur_y = y;
}

static void fr_quadratic_to(hb_draw_funcs_t *dfuncs, void *draw_data,
                            hb_draw_state_t *st, float cx, float cy,
                            float x, float y, void *user_data)
{
    (void)dfuncs; (void)st; (void)user_data;
    fr_builder *b = (fr_builder *)draw_data;
    float x0 = b->cur_x;
    float y0 = b->cur_y;
    int n;
    cx = cx * b->scale;
    cy = cy * b->scale;
    x = x * b->scale;
    y = y * b->scale;
    n = fr_quad_steps(x0, y0, cx, cy, x, y);
    int i;
    for (i = 1; i <= n; i++) {
        float t = (float)i / (float)n;
        float mt = 1.0f - t;
        float px = mt * mt * x0 + 2.0f * mt * t * cx + t * t * x;
        float py = mt * mt * y0 + 2.0f * mt * t * cy + t * t * y;
        fr_push(b, px, py);
    }
    b->cur_x = x;
    b->cur_y = y;
}

static void fr_cubic_to(hb_draw_funcs_t *dfuncs, void *draw_data,
                        hb_draw_state_t *st, float c1x, float c1y,
                        float c2x, float c2y, float x, float y,
                        void *user_data)
{
    (void)dfuncs; (void)st; (void)user_data;
    fr_builder *b = (fr_builder *)draw_data;
    float x0 = b->cur_x;
    float y0 = b->cur_y;
    int n;
    c1x = c1x * b->scale;
    c1y = c1y * b->scale;
    c2x = c2x * b->scale;
    c2y = c2y * b->scale;
    x = x * b->scale;
    y = y * b->scale;
    n = fr_cubic_steps(x0, y0, c1x, c1y, c2x, c2y, x, y);
    int i;
    for (i = 1; i <= n; i++) {
        float t = (float)i / (float)n;
        float mt = 1.0f - t;
        float a = mt * mt * mt;
        float bb = 3.0f * mt * mt * t;
        float c = 3.0f * mt * t * t;
        float d = t * t * t;
        float px = a * x0 + bb * c1x + c * c2x + d * x;
        float py = a * y0 + bb * c1y + c * c2y + d * y;
        fr_push(b, px, py);
    }
    b->cur_x = x;
    b->cur_y = y;
}

static void fr_close_path(hb_draw_funcs_t *dfuncs, void *draw_data,
                          hb_draw_state_t *st, void *user_data)
{
    (void)dfuncs; (void)st; (void)user_data;
    fr_builder *b = (fr_builder *)draw_data;
    b->cur_x = b->start_x;
    b->cur_y = b->start_y;
}

// ---- raster ----------------------------------------------------------------

typedef struct {
    float x0, y0, x1, y1;
} fr_edge;

typedef struct {
    float x;
    int32_t dir;
} fr_cross;

static void fr_add_span(float *cov, int32_t w, float xa, float xb)
{
    int32_t ia, ib, i;
    if (xb <= xa)
        return;
    if (xa < 0.0f) xa = 0.0f;
    if (xb > (float)w) xb = (float)w;
    if (xb <= xa)
        return;
    ia = (int32_t)floorf(xa);
    ib = (int32_t)floorf(xb);
    if (ia < 0) ia = 0;
    if (ib >= w) ib = w - 1;
    if (ia == ib) {
        cov[ia] += xb - xa;
        return;
    }
    cov[ia] += (float)(ia + 1) - xa;
    for (i = ia + 1; i < ib; i++)
        cov[i] += 1.0f;
    cov[ib] += xb - (float)ib;
}

static void fr_sort_cross(fr_cross *xs, int32_t n)
{
    int32_t i, j;
    for (i = 1; i < n; i++) {
        fr_cross key = xs[i];
        j = i - 1;
        while (j >= 0 && xs[j].x > key.x) {
            xs[j + 1] = xs[j];
            j--;
        }
        xs[j + 1] = key;
    }
}

static int32_t fr_rasterize(fr_builder *b, uint8_t *out, int32_t out_cap,
                            int32_t px_q6, int32_t *slots)
{
    float minx = 1e30f, miny = 1e30f, maxx = -1e30f, maxy = -1e30f;
    int32_t i, c, edge_count = 0, edge_cap;
    int32_t x0, x1, top, bottom, w, h;
    fr_edge *edges = NULL;
    fr_cross *cross = NULL;
    float *cov = NULL;

    if (b->overflow)
        return -4;
    if (b->count < 3 || b->contour_count < 1)
        return 0; // empty glyph (space)

    for (i = 0; i < b->count; i++) {
        float x = b->pts[i].x;
        float y = b->pts[i].y;
        if (x < minx) minx = x;
        if (x > maxx) maxx = x;
        if (y < miny) miny = y;
        if (y > maxy) maxy = y;
    }
    if (!(maxx > minx) || !(maxy > miny))
        return 0;

    x0 = (int32_t)floorf(minx) - 1;
    x1 = (int32_t)ceilf(maxx) + 1;
    top = (int32_t)ceilf(maxy) + 1;
    bottom = (int32_t)floorf(miny) - 1;
    w = x1 - x0;
    h = top - bottom;
    if (w <= 0 || h <= 0)
        return 0;

    slots[0] = w;
    slots[1] = h;
    slots[2] = x0;
    slots[3] = top;
    slots[5] = w * h;

    // A glyph larger than 4 em square is malformed for UI text; refuse
    // instead of allocating an attacker-sized bitmap.
    {
        int64_t em = (int64_t)px_q6 / 64;
        int64_t cap = (em * 4 + 16) * (em * 4 + 16);
        if ((int64_t)w * (int64_t)h > cap)
            return -5;
    }
    if (w * h > out_cap || !out)
        return -3;

    edge_cap = b->count + b->contour_count;
    edges = (fr_edge *)malloc(sizeof(fr_edge) * (size_t)edge_cap);
    cross = (fr_cross *)malloc(sizeof(fr_cross) * (size_t)edge_cap);
    cov = (float *)calloc((size_t)w, sizeof(float));
    if (!edges || !cross || !cov) {
        free(edges); free(cross); free(cov);
        return -6;
    }

    // Build edges in bitmap space (y down).
    for (c = 0; c < b->contour_count; c++) {
        int32_t start = b->contour_start[c];
        int32_t end = (c + 1 < b->contour_count) ? b->contour_start[c + 1] : b->count;
        int32_t k;
        if (end - start < 3) continue;
        for (k = start; k < end; k++) {
            int32_t nk = (k + 1 < end) ? (k + 1) : start;
            float ax = b->pts[k].x - (float)x0;
            float ay = (float)top - b->pts[k].y;
            float bx = b->pts[nk].x - (float)x0;
            float by = (float)top - b->pts[nk].y;
            if (ay == by) continue;
            edges[edge_count].x0 = ax;
            edges[edge_count].y0 = ay;
            edges[edge_count].x1 = bx;
            edges[edge_count].y1 = by;
            edge_count++;
        }
    }

    memset(out, 0, (size_t)(w * h));
    for (int32_t row = 0; row < h; row++) {
        for (int32_t sub = 0; sub < FR_SUBSCANLINES; sub++) {
            float sy = (float)row + ((float)sub + 0.5f) / (float)FR_SUBSCANLINES;
            int32_t n = 0;
            int32_t winding = 0;
            for (i = 0; i < edge_count; i++) {
                float ay = edges[i].y0;
                float by = edges[i].y1;
                if ((ay <= sy && by > sy) || (by <= sy && ay > sy)) {
                    float t = (sy - ay) / (by - ay);
                    cross[n].x = edges[i].x0 + t * (edges[i].x1 - edges[i].x0);
                    cross[n].dir = (by > ay) ? 1 : -1;
                    n++;
                }
            }
            fr_sort_cross(cross, n);
            for (int32_t k = 0; k + 1 < n; k++) {
                winding += cross[k].dir;
                if (winding != 0)
                    fr_add_span(cov, w, cross[k].x, cross[k + 1].x);
            }
        }
        for (int32_t x = 0; x < w; x++) {
            float v = cov[x] * (255.0f / (float)FR_SUBSCANLINES);
            int32_t iv = (int32_t)(v + 0.5f);
            if (iv < 0) iv = 0;
            if (iv > 255) iv = 255;
            out[row * w + x] = (uint8_t)iv;
        }
        memset(cov, 0, sizeof(float) * (size_t)w);
    }

    free(edges);
    free(cross);
    free(cov);
    return 0;
}

// ---- public C surface -------------------------------------------------------

int64_t xfr_face_open(const uint8_t *bytes, int32_t len)
{
    hb_blob_t *blob;
    hb_face_t *face;
    if (!bytes || len <= 0)
        return -1;
    // HB_MEMORY_MODE_READONLY == 1. The caller's bytes must outlive the
    // face; hb_face_create keeps its own blob reference.
    blob = hb_blob_create((const char *)bytes, (unsigned int)len, 1, NULL, NULL);
    if (!blob)
        return -1;
    face = hb_face_create(blob, 0);
    hb_blob_destroy(blob);
    if (!face || hb_face_get_upem(face) == 0) {
        if (face) hb_face_destroy(face);
        return -2;
    }
    return (int64_t)(intptr_t)face;
}

void xfr_face_close(int64_t handle)
{
    if (handle > 0)
        hb_face_destroy((hb_face_t *)(intptr_t)handle);
}

int32_t xfr_face_upem(int64_t handle)
{
    if (handle <= 0)
        return 0;
    return (int32_t)hb_face_get_upem((hb_face_t *)(intptr_t)handle);
}

int32_t xfr_face_metrics(int64_t handle, int32_t px_q6, int32_t *slots)
{
    hb_face_t *face;
    hb_font_t *font;
    hb_font_extents_t ext;
    int cap = 0, xh = 0;
    if (handle <= 0 || !slots || px_q6 <= 0)
        return -1;
    face = (hb_face_t *)(intptr_t)handle;
    font = hb_font_create(face);
    if (!font)
        return -2;
    hb_font_set_scale(font, px_q6, px_q6);
    if (hb_font_get_h_extents(font, &ext)) {
        slots[0] = ext.ascender;
        slots[1] = ext.descender;
        slots[2] = ext.line_gap;
    } else {
        // Conservative fallback in 1/64 px: 80% ascent, 20% descent.
        slots[0] = (int32_t)((int64_t)px_q6 * 8 / 10);
        slots[1] = -(int32_t)((int64_t)px_q6 * 2 / 10);
        slots[2] = 0;
    }
    // hb_ot_metrics tags: 'cpht' / 'xhgt' (hb-ot-metrics.h enum).
    if (!hb_ot_metrics_get_position(font, 0x63706874u, &cap)) cap = 0;
    if (!hb_ot_metrics_get_position(font, 0x78686774u, &xh)) xh = 0;
    slots[3] = cap;
    slots[4] = xh;
    hb_font_destroy(font);
    return 0;
}

int32_t xfr_glyph_index(int64_t handle, int32_t codepoint)
{
    hb_face_t *face;
    hb_font_t *font;
    uint32_t glyph = 0;
    int ok;
    if (handle <= 0)
        return -1;
    face = (hb_face_t *)(intptr_t)handle;
    font = hb_font_create(face);
    if (!font)
        return -1;
    ok = hb_font_get_nominal_glyph(font, (uint32_t)codepoint, &glyph);
    hb_font_destroy(font);
    return ok ? (int32_t)glyph : -1;
}

// Shape UTF-8 into glyphs. `out` carries 6 int32 per glyph:
// glyph, cluster, x_advance, y_advance, x_offset, y_offset. slots:
// [0]=glyph count, [1]=required ints, [2]=hb direction.
int32_t xfr_shape(int64_t handle, const uint8_t *utf8, int32_t len,
                  int32_t px_q6, int32_t *out, int32_t cap, int32_t *slots)
{
    hb_face_t *face;
    hb_font_t *font;
    hb_buffer_t *buffer;
    hb_glyph_info_t *info;
    hb_glyph_position_t *pos;
    unsigned int count = 0;
    int32_t i;

    if (!slots || handle <= 0 || !utf8 || len < 0 || px_q6 <= 0)
        return -1;
    slots[0] = 0; slots[1] = 0; slots[2] = 0;

    face = (hb_face_t *)(intptr_t)handle;
    font = hb_font_create(face);
    if (!font)
        return -2;
    hb_font_set_scale(font, px_q6, px_q6);

    buffer = hb_buffer_create();
    if (!buffer || !hb_buffer_allocation_successful(buffer)) {
        if (buffer) hb_buffer_destroy(buffer);
        hb_font_destroy(font);
        return -2;
    }
    hb_buffer_add_utf8(buffer, (const char *)utf8, len, 0, len);
    hb_buffer_guess_segment_properties(buffer);
    hb_shape(font, buffer, NULL, 0);

    info = hb_buffer_get_glyph_infos(buffer, &count);
    pos = hb_buffer_get_glyph_positions(buffer, &count);
    slots[0] = (int32_t)count;
    slots[1] = (int32_t)count * 6;
    slots[2] = hb_buffer_get_direction(buffer);

    if ((int32_t)count * 6 > cap || (!out && count > 0)) {
        hb_buffer_destroy(buffer);
        hb_font_destroy(font);
        return -3;
    }
    for (i = 0; i < (int32_t)count; i++) {
        out[i * 6 + 0] = (int32_t)info[i].codepoint;
        out[i * 6 + 1] = (int32_t)info[i].cluster;
        out[i * 6 + 2] = pos[i].x_advance;
        out[i * 6 + 3] = pos[i].y_advance;
        out[i * 6 + 4] = pos[i].x_offset;
        out[i * 6 + 5] = pos[i].y_offset;
    }
    hb_buffer_destroy(buffer);
    hb_font_destroy(font);
    return 0;
}

int32_t xfr_glyph_raster(int64_t handle, int32_t glyph, int32_t px_q6,
                         uint8_t *out, int32_t out_cap, int32_t *slots)
{
    hb_face_t *face;
    hb_font_t *font;
    hb_draw_funcs_t *dfuncs;
    fr_builder *b;
    int32_t rc;
    int adv;

    if (!slots || handle <= 0 || px_q6 <= 0)
        return -1;
    slots[0] = 0; slots[1] = 0; slots[2] = 0; slots[3] = 0; slots[4] = 0; slots[5] = 0;

    face = (hb_face_t *)(intptr_t)handle;
    font = hb_font_create(face);
    if (!font)
        return -2;
    hb_font_set_scale(font, px_q6, px_q6);
    adv = hb_font_get_glyph_h_advance(font, (uint32_t)glyph);
    slots[4] = adv;

    b = (fr_builder *)calloc(1, sizeof(fr_builder));
    if (!b) {
        hb_font_destroy(font);
        return -6;
    }
    // hb_font_draw_glyph emits coordinates in 26.6 px (the font scale is
    // already applied); convert to whole pixels. (The old px/upem factor
    // double-scaled, making small glyphs tiny and large glyphs huge.)
    b->scale = 1.0f / 64.0f;
    b->pts = (fr_point *)malloc(sizeof(fr_point) * (size_t)FR_MAX_POINTS);
    b->contour_start = (int32_t *)malloc(sizeof(int32_t) * (size_t)FR_MAX_CONTOURS);
    if (!b->pts || !b->contour_start) {
        free(b->pts); free(b->contour_start); free(b);
        hb_font_destroy(font);
        return -6;
    }

    dfuncs = hb_draw_funcs_create();
    if (!dfuncs) {
        free(b->pts); free(b->contour_start); free(b);
        hb_font_destroy(font);
        return -6;
    }
    hb_draw_funcs_set_move_to_func(dfuncs, fr_move_to, NULL, NULL);
    hb_draw_funcs_set_line_to_func(dfuncs, fr_line_to, NULL, NULL);
    hb_draw_funcs_set_quadratic_to_func(dfuncs, fr_quadratic_to, NULL, NULL);
    hb_draw_funcs_set_cubic_to_func(dfuncs, fr_cubic_to, NULL, NULL);
    hb_draw_funcs_set_close_path_func(dfuncs, fr_close_path, NULL, NULL);
    hb_draw_funcs_make_immutable(dfuncs);

    hb_font_draw_glyph(font, (uint32_t)glyph, dfuncs, b);

    rc = fr_rasterize(b, out, out_cap, px_q6, slots);

    hb_draw_funcs_destroy(dfuncs);
    free(b->pts);
    free(b->contour_start);
    free(b);
    hb_font_destroy(font);
    return rc;
}
