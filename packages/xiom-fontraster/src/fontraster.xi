// XIOM -- fontraster: flat XIOM surface over the C glyph rasterizer.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Ownership: a FontFace holds a HarfBuzz face whose blob points at the
// caller's font bytes. The bytes must stay alive until font_face_close.
// A GlyphRaster owns its coverage pixels (main heap, Vec). The rasterizer
// is stateless per call (a fresh hb_font_t), so one face handle can be
// used from several workers concurrently.
module xiom.fontraster

use xiom.string;

extern "C" {
  fn xfr_face_open(bytes: *mut UInt8, len: Int32) -> Int;
  fn xfr_face_close(handle: Int);
  fn xfr_face_upem(handle: Int) -> Int32;
  fn xfr_face_metrics(handle: Int, px_q6: Int32, slots: *mut Int32) -> Int32;
  fn xfr_glyph_index(handle: Int, codepoint: Int32) -> Int32;
  fn xfr_glyph_raster(handle: Int, glyph: Int32, px_q6: Int32,
                      out: *mut UInt8, out_cap: Int32,
                      slots: *mut Int32) -> Int32;
  fn xfr_shape(handle: Int, utf8: *UInt8, len: Int32, px_q6: Int32,
               out: *mut Int32, cap: Int32, slots: *mut Int32) -> Int32;
}

/// An open face. `handle` is opaque C state; `upem` is design units.
pub type FontFace = {
  ok: Bool;
  rc: Int;
  handle: Int;
  upem: Int;
}

/// Vertical face metrics at a pixel size, in 1/64 px.
pub type FontMetrics = {
  ok: Bool;
  ascender_q6: Int;
  descender_q6: Int;
  line_gap_q6: Int;
  cap_q6: Int;
  xheight_q6: Int;
}

/// One rasterized glyph. Pixels are 8-bit coverage, top-left origin,
/// row-major, exactly width * height bytes. `bearing_x` is the left edge
/// relative to the pen; `bearing_y` is the top edge above the baseline.
pub type GlyphRaster = {
  ok: Bool;
  rc: Int;
  width: Int;
  height: Int;
  bearing_x: Int;
  bearing_y: Int;
  advance_q6: Int;
  pixels: Vec[UInt8];
}

/// Open a face over caller-owned TTF/OTF bytes. The bytes must outlive
/// the face (see the module ownership note).
pub fn font_face_open(data: &mut Vec[UInt8]) -> FontFace {
  var handle = 0;
  if data.len() > 0 {
    unsafe {
      handle = xfr_face_open(data.as_mut_ptr(), data.len() as Int32);
    }
  }
  if handle <= 0 {
    return FontFace{ ok: false; rc: handle; handle: 0; upem: 0 };
  }
  var upem = 0;
  unsafe { upem = xfr_face_upem(handle) as Int; };
  return FontFace{ ok: true; rc: 0; handle: handle; upem: upem };
}

/// Close a face. Safe to call twice.
pub fn font_face_close(face: &mut FontFace) {
  if face.handle > 0 {
    unsafe { xfr_face_close(face.handle); }
    face.handle = 0;
    face.ok = false;
  }
}

/// Vertical metrics at an integer pixel em size.
pub fn font_face_metrics(face: &FontFace, px: Int) -> FontMetrics {
  if !face.ok || face.handle <= 0 || px <= 0 {
    return FontMetrics{ ok: false; ascender_q6: 0; descender_q6: 0;
                        line_gap_q6: 0; cap_q6: 0; xheight_q6: 0 };
  }
  var slots = Vec[Int32].with_len(8);
  var rc = 0;
  unsafe {
    rc = xfr_face_metrics(face.handle, (px * 64) as Int32, slots.as_mut_ptr());
  }
  if rc != 0 {
    return FontMetrics{ ok: false; ascender_q6: 0; descender_q6: 0;
                        line_gap_q6: 0; cap_q6: 0; xheight_q6: 0 };
  }
  return FontMetrics{
    ok: true;
    ascender_q6: slots[0] as Int;
    descender_q6: slots[1] as Int;
    line_gap_q6: slots[2] as Int;
    cap_q6: slots[3] as Int;
    xheight_q6: slots[4] as Int;
  };
}

/// One shaped glyph. Advances/offsets are in 1/64 px.
pub type ShapedGlyph = {
  glyph: Int;
  cluster: Int;
  advance_x_q6: Int;
  advance_y_q6: Int;
  offset_x_q6: Int;
  offset_y_q6: Int;
}

/// A shaped run in visual order. width_q6 sums the x advances.
pub type TextRun = {
  ok: Bool;
  rc: Int;
  direction: Int;
  width_q6: Int;
  glyphs: Vec[ShapedGlyph];
}

/// Shape UTF-8 text with the face's OpenType layout (ligatures, kerning,
/// marks, bidi runs resolved by HarfBuzz).
pub fn font_shape(face: &FontFace, text: Str, px: Int) -> TextRun {
  let n = str_len(text);
  if !face.ok || face.handle <= 0 || n <= 0 || px <= 0 {
    return TextRun{ ok: false; rc: 0 - 1; direction: 0; width_q6: 0;
                    glyphs: Vec[ShapedGlyph].new() };
  }
  var cap = n * 6 + 6;
  var buf = Vec[Int32].with_len(cap);
  var slots = Vec[Int32].with_len(8);
  var rc = 0;
  unsafe {
    rc = xfr_shape(face.handle, text.c_str(), n as Int32, (px * 64) as Int32,
                   buf.as_mut_ptr(), cap as Int32, slots.as_mut_ptr());
  }
  if rc == 0 - 3 {
    cap = slots[1] as Int;
    if cap < 6 { cap = 6; };
    buf = Vec[Int32].with_len(cap);
    unsafe {
      rc = xfr_shape(face.handle, text.c_str(), n as Int32, (px * 64) as Int32,
                     buf.as_mut_ptr(), cap as Int32, slots.as_mut_ptr());
    }
  }
  if rc != 0 {
    return TextRun{ ok: false; rc: rc; direction: 0; width_q6: 0;
                    glyphs: Vec[ShapedGlyph].new() };
  }
  let count = slots[0] as Int;
  var glyphs = Vec[ShapedGlyph].new();
  var width = 0;
  var i = 0;
  while i < count {
    let g = ShapedGlyph{
      glyph: buf[i * 6 + 0] as Int;
      cluster: buf[i * 6 + 1] as Int;
      advance_x_q6: buf[i * 6 + 2] as Int;
      advance_y_q6: buf[i * 6 + 3] as Int;
      offset_x_q6: buf[i * 6 + 4] as Int;
      offset_y_q6: buf[i * 6 + 5] as Int;
    };
    width = width + g.advance_x_q6;
    glyphs.push(g);
    i = i + 1;
  }
  return TextRun{ ok: true; rc: 0; direction: slots[2] as Int;
                  width_q6: width; glyphs: glyphs };
}

/// Nominal glyph id for a codepoint, or -1 when the face has no mapping.
pub fn font_glyph_index(face: &FontFace, codepoint: Int) -> Int {
  if !face.ok || face.handle <= 0 || codepoint < 0 {
    return -1;
  }
  var gid = 0;
  unsafe { gid = xfr_glyph_index(face.handle, codepoint as Int32) as Int; }
  return gid;
}

/// Rasterize one glyph at an integer pixel em size.
pub fn font_glyph_raster(face: &FontFace, glyph: Int, px: Int) -> GlyphRaster {
  if !face.ok || face.handle <= 0 || glyph < 0 || px <= 0 {
    return GlyphRaster{ ok: false; rc: -1; width: 0; height: 0;
                        bearing_x: 0; bearing_y: 0; advance_q6: 0;
                        pixels: Vec[UInt8].new() };
  }
  // A UI glyph fits well inside 2 em plus padding; the rasterizer
  // refuses anything above 4 em. Retry once with the exact requirement
  // if the generous buffer ever falls short.
  let max_px = (px * 2 + 16) * (px * 2 + 16);
  var pix = Vec[UInt8].with_len(max_px);
  var slots = Vec[Int32].with_len(8);
  var rc = 0;
  unsafe {
    rc = xfr_glyph_raster(face.handle, glyph as Int32, (px * 64) as Int32,
                          pix.as_mut_ptr(), max_px as Int32,
                          slots.as_mut_ptr());
  }
  if rc == 0 - 3 {
    let need = slots[5] as Int;
    if need > 0 && need <= 4 * 1024 * 1024 {
      pix = Vec[UInt8].with_len(need);
      unsafe {
        rc = xfr_glyph_raster(face.handle, glyph as Int32, (px * 64) as Int32,
                              pix.as_mut_ptr(), need as Int32,
                              slots.as_mut_ptr());
      }
    }
  }
  let w = slots[0] as Int;
  let h = slots[1] as Int;
  if rc != 0 {
    return GlyphRaster{ ok: false; rc: rc; width: 0; height: 0;
                        bearing_x: 0; bearing_y: 0;
                        advance_q6: slots[4] as Int;
                        pixels: Vec[UInt8].new() };
  }
  if w * h > 0 {
    pix.truncate(w * h);
  } else {
    pix.truncate(0);
  }
  return GlyphRaster{
    ok: true;
    rc: 0;
    width: w;
    height: h;
    bearing_x: slots[2] as Int;
    bearing_y: slots[3] as Int;
    advance_q6: slots[4] as Int;
    pixels: pix;
  };
}
