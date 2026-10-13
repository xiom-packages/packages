// XIOM -- xiom.harfbuzz probe bridge (MIT OR Apache-2.0, XIOM Authors).
//
// The vendored harfbuzz 14.6.0 amalgam
// (vendor/harfbuzz/src/harfbuzz-subset.cc) is compiled as one C++ TU via
// port.args.json; this file adds the `extern "C"` probe/objective surface
// the XIOM modules call.  Direction of data (docs discipline v0.64.4):
//
//   * C WRITES results into XIOM-owned 4-byte slots (B-20/B-24 safe path);
//     the XIOM side reads them little-endian byte-indexed.
//   * C READS the font bytes from an XIOM-owned Vec handed in as a pointer
//     (memory keeps a READONLY hb_blob during the call; callers keep the
//     Vec alive for the probe duration).
//   * handles that must survive across calls (the face/font open-close
//     probe) cross as opaque pointers <-> Int values; the Int-param path
//     is the faithful one on this compiler pin (B-25).
//   * no bare null ever crosses from XIOM; every nullable argument here is
//     produced inside C.
//
// Every probe returns 0 on success or a negative error code.

#include "../vendor/harfbuzz/src/hb.h"
#include "../vendor/harfbuzz/src/hb-ot.h"
#include "../vendor/harfbuzz/src/hb-subset.h"

#include <cstdint>
#include <cstring>

namespace {

void wr_u32(uint8_t *slot, uint32_t v)
{
  memcpy(slot, &v, sizeof(v));
}

hb_blob_t *readonly_blob(const uint8_t *bytes, int32_t len)
{
  if (!bytes || len <= 0)
    return nullptr;
  // NO copy: the caller owns the memory for the duration of the call.
  return hb_blob_create(reinterpret_cast<const char *>(bytes),
                        static_cast<unsigned int>(len),
                        HB_MEMORY_MODE_READONLY, nullptr, nullptr);
}

} // namespace

extern "C" {

// ---- version pin ---------------------------------------------------------

int32_t xhb_version_pin(void)
{
  unsigned int major = 0, minor = 0, micro = 0;
  hb_version(&major, &minor, &micro);
  return static_cast<int32_t>(major * 10000u + minor * 100u + micro);
}

int32_t xhb_version_string_ok(void)
{
  return std::strcmp(hb_version_string(), "14.6.0") == 0 ? 1 : 0;
}

int32_t xhb_version_atleast_ok(void)
{
  return hb_version_atleast(14, 6, 0) ? 1 : 0;
}

// ---- face/font introspection --------------------------------------------

// Writes: upem, glyph_count, nominal glyph for 'A' and 'V', face count.
int32_t xhb_face_probe(const uint8_t *bytes, int32_t len,
                       uint8_t *s_upem, uint8_t *s_glyph_count,
                       uint8_t *s_glyph_a, uint8_t *s_glyph_v,
                       uint8_t *s_face_count)
{
  hb_blob_t *blob = readonly_blob(bytes, len);
  if (!blob)
    return -1;
  hb_face_t *face = hb_face_create(blob, 0);
  if (!face)
  {
    hb_blob_destroy(blob);
    return -2;
  }
  unsigned int upem = hb_face_get_upem(face);
  if (upem == 0)
  {
    hb_face_destroy(face);
    hb_blob_destroy(blob);
    return -3;
  }
  hb_font_t *font = hb_font_create(face);
  if (!font)
  {
    hb_face_destroy(face);
    hb_blob_destroy(blob);
    return -4;
  }
  hb_codepoint_t gA = 0, gV = 0;
  hb_font_get_nominal_glyph(font, 0x41, &gA);
  hb_font_get_nominal_glyph(font, 0x56, &gV);
  wr_u32(s_upem, upem);
  wr_u32(s_glyph_count, hb_face_get_glyph_count(face));
  wr_u32(s_glyph_a, gA);
  wr_u32(s_glyph_v, gV);
  wr_u32(s_face_count, hb_face_count(blob));
  hb_font_destroy(font);
  hb_face_destroy(face);
  hb_blob_destroy(blob);
  return 0;
}

// ---- shaping -------------------------------------------------------------

// text_sel: 0 = "AV" (LTR), 1 = "A" (LTR), 2 = U+0627 Arabic alef (RTL).
// Writes: glyph count, direction, first glyph id, first cluster,
// first advance, summed advances, upem.
int32_t xhb_shape_probe(const uint8_t *bytes, int32_t len, int32_t text_sel,
                        uint8_t *s_glyph_count, uint8_t *s_direction,
                        uint8_t *s_glyph0, uint8_t *s_cluster0,
                        uint8_t *s_advance0, uint8_t *s_advance_sum,
                        uint8_t *s_upem)
{
  const char *text = nullptr;
  int tlen = 0;
  switch (text_sel)
  {
    case 0: text = "AV"; tlen = 2; break;
    case 1: text = "A"; tlen = 1; break;
    case 2: text = "\xD8\xA7"; tlen = 2; break; // U+0627
    default: return -1;
  }
  hb_blob_t *blob = readonly_blob(bytes, len);
  if (!blob)
    return -2;
  hb_face_t *face = hb_face_create(blob, 0);
  hb_font_t *font = face ? hb_font_create(face) : nullptr;
  hb_buffer_t *buffer = hb_buffer_create();
  if (!face || !font || !hb_buffer_allocation_successful(buffer))
  {
    if (buffer) hb_buffer_destroy(buffer);
    if (font) hb_font_destroy(font);
    if (face) hb_face_destroy(face);
    hb_blob_destroy(blob);
    return -3;
  }
  hb_buffer_add_utf8(buffer, text, tlen, 0, tlen);
  hb_buffer_guess_segment_properties(buffer);
  hb_shape(font, buffer, nullptr, 0);

  unsigned int count = 0;
  hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buffer, &count);
  hb_glyph_position_t *pos = hb_buffer_get_glyph_positions(buffer, nullptr);
  int64_t adv_sum = 0;
  for (unsigned int i = 0; i < count; i++)
    adv_sum += pos[i].x_advance;

  wr_u32(s_glyph_count, count);
  wr_u32(s_direction, static_cast<uint32_t>(hb_buffer_get_direction(buffer)));
  wr_u32(s_glyph0, count > 0 ? info[0].codepoint : 0xFFFFFFFFu);
  wr_u32(s_cluster0, count > 0 ? info[0].cluster : 0xFFFFFFFFu);
  wr_u32(s_advance0, count > 0 ? static_cast<uint32_t>(pos[0].x_advance) : 0);
  wr_u32(s_advance_sum, static_cast<uint32_t>(adv_sum));
  wr_u32(s_upem, hb_face_get_upem(face));

  hb_buffer_destroy(buffer);
  hb_font_destroy(font);
  hb_face_destroy(face);
  hb_blob_destroy(blob);
  return 0;
}

// ---- subsetting ----------------------------------------------------------

// Subsets the font to the single unicode U+0041 ('A'), serializes the result
// into the XIOM-owned `out` buffer.  Writes: serialized size, subset glyph
// count, retained unicode population (== 1).
int32_t xhb_subset_probe(const uint8_t *bytes, int32_t len,
                         uint8_t *out, int32_t out_cap,
                         uint8_t *s_size, uint8_t *s_glyph_count,
                         uint8_t *s_unicode_count)
{
  if (!out || out_cap <= 0)
    return -1;
  hb_blob_t *blob = readonly_blob(bytes, len);
  if (!blob)
    return -2;
  hb_face_t *face = hb_face_create(blob, 0);
  hb_subset_input_t *input = hb_subset_input_create_or_fail();
  if (!face || !input)
  {
    if (input) hb_subset_input_destroy(input);
    if (face) hb_face_destroy(face);
    hb_blob_destroy(blob);
    return -3;
  }
  hb_set_t *unicodes = hb_subset_input_unicode_set(input);
  hb_set_clear(unicodes);
  hb_set_add(unicodes, 0x41);

  hb_face_t *sub = hb_subset_or_fail(face, input);
  if (!sub)
  {
    hb_subset_input_destroy(input);
    hb_face_destroy(face);
    hb_blob_destroy(blob);
    return -4;
  }
  hb_blob_t *sblob = hb_face_reference_blob(sub);
  unsigned int size = hb_blob_get_length(sblob);
  if (size == 0 || size > static_cast<unsigned int>(out_cap))
  {
    hb_blob_destroy(sblob);
    hb_face_destroy(sub);
    hb_subset_input_destroy(input);
    hb_face_destroy(face);
    hb_blob_destroy(blob);
    return -5;
  }
  memcpy(out, hb_blob_get_data(sblob, nullptr), size);
  wr_u32(s_size, size);
  wr_u32(s_glyph_count, hb_face_get_glyph_count(sub));
  wr_u32(s_unicode_count, hb_set_get_population(unicodes));

  hb_blob_destroy(sblob);
  hb_face_destroy(sub);
  hb_subset_input_destroy(input);
  hb_face_destroy(face);
  hb_blob_destroy(blob);
  return 0;
}

// ---- sfnt table lookup (generated externs kept on the C side) ------------

// Byte length of an sfnt table: hb_face_reference_table ->
// hb_blob_get_length -> hb_blob_destroy.  Returns -1 when the table is
// absent, else the length (>= 0).
int32_t xhb_face_table_len(hb_face_t *face, uint32_t tag)
{
  if (!face)
    return -2;
  hb_blob_t *blob = hb_face_reference_table(face, (hb_tag_t) tag);
  if (!blob)
    return -1;
  unsigned int len = hb_blob_get_length(blob);
  hb_blob_destroy(blob);
  return (int32_t) len;
}

// ---- persistent face/font handles (open/close probe) ---------------------

hb_face_t *xhb_face_open(const uint8_t *bytes, int32_t len)
{
  hb_blob_t *blob = readonly_blob(bytes, len);
  if (!blob)
    return nullptr;
  hb_face_t *face = hb_face_create(blob, 0);
  hb_blob_destroy(blob); // the face holds its own reference
  return face;
}

void xhb_face_close(hb_face_t *face)
{
  if (face)
    hb_face_destroy(face);
}

hb_font_t *xhb_font_open(hb_face_t *face)
{
  return face ? hb_font_create(face) : nullptr;
}

void xhb_font_close(hb_font_t *font)
{
  if (font)
    hb_font_destroy(font);
}

} // extern "C"
