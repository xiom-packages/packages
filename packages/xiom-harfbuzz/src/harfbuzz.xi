// XIOM -- xiom.harfbuzz: harfbuzz 14.6.0 text shaping + subsetting bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C++ (the xiom.meshopt pattern).  The byte-pinned
// harfbuzz 14.6.0 amalgam `vendor/harfbuzz/src/harfbuzz-subset.cc`
// (commit c7a7457b7385f33178e8cf87615ca077a810bbe7, "Old MIT") is compiled
// as one TU through port.args.json together with `src/hb_bridge.cpp` (the
// probe bridge) and `src/hb_symbols_gen.c` (address-of table over 100% of
// the declared surface).
//
// The generated modules `xiom.harfbuzz.gen.*` carry the full declared
// surface: every HB_EXTERN function of the hb.h + hb-ot.h + hb-subset.h +
// hb-version.h include closure (582 functions) as an `extern \"C\"`
// declaration, plus 594 value constants.  Regenerate with
// `python tools/gen_harfbuzz.py`; `--check` fails on drift.
//
// FFI discipline (v0.64.4, docs/BINDINGS-COMPILER-FINDINGS.md):
//   * pointers/handles cross as Int; never `Int as *UInt8` (B-25)
//   * no bare `null` to C (B-23); nullable args are produced inside C
//   * no reads through foreign pointers from XIOM (B-20/B-24): C writes
//     results into XIOM-owned 4-byte slots, read little-endian below
//   * flat outcome structs only (B-26); no Result[Option[T]] shapes
//
// Out of declared scope (not reachable from the four roots; documented in
// SPEC.md section 2): hb-ft.h (FreeType), hb-gobject.h (GObject),
// hb-icu.h (ICU), hb-cairo.h (cairo) -- all require external dependencies
// the package deliberately does not link.

module xiom.harfbuzz

use xiom.harfbuzz.gen.hb;
use xiom.harfbuzz.gen.blob;
use xiom.harfbuzz.gen.buffer;
use xiom.harfbuzz.gen.common;
use xiom.harfbuzz.gen.deprecated;
use xiom.harfbuzz.gen.draw;
use xiom.harfbuzz.gen.face;
use xiom.harfbuzz.gen.font;
use xiom.harfbuzz.gen.map;
use xiom.harfbuzz.gen.ot;
use xiom.harfbuzz.gen.ot_color;
use xiom.harfbuzz.gen.ot_deprecated;
use xiom.harfbuzz.gen.ot_fetch;
use xiom.harfbuzz.gen.ot_font;
use xiom.harfbuzz.gen.ot_layout;
use xiom.harfbuzz.gen.ot_math;
use xiom.harfbuzz.gen.ot_meta;
use xiom.harfbuzz.gen.ot_metrics;
use xiom.harfbuzz.gen.ot_name;
use xiom.harfbuzz.gen.ot_shape;
use xiom.harfbuzz.gen.ot_var;
use xiom.harfbuzz.gen.paint;
use xiom.harfbuzz.gen.script_list;
use xiom.harfbuzz.gen.set;
use xiom.harfbuzz.gen.shape;
use xiom.harfbuzz.gen.shape_plan;
use xiom.harfbuzz.gen.style;
use xiom.harfbuzz.gen.subset;
use xiom.harfbuzz.gen.subset_depend;
use xiom.harfbuzz.gen.subset_serialize;
use xiom.harfbuzz.gen.surface;
use xiom.harfbuzz.gen.unicode;
use xiom.harfbuzz.gen.version;

// =========================================================================
// Pin identity (canonical values live in xiom.harfbuzz.gen.surface)
// =========================================================================

/// Upstream harfbuzz release pin (SPEC.md section 2).
pub fn hb_pin_version() -> Str
  requires: true
{
  return surface.HB_PIN_VERSION;
}

/// Upstream commit pin (shallow clone `E:\repos\harfbuzz`, tag 14.6.0).
pub fn hb_pin_commit() -> Str
  requires: true
{
  return surface.HB_PIN_COMMIT;
}

// =========================================================================
// Bridge externs (src/hb_bridge.cpp + src/hb_symbols_gen.c)
// =========================================================================

extern "C" {
  fn xhb_version_pin() -> Int32;
  fn xhb_version_string_ok() -> Int32;
  fn xhb_version_atleast_ok() -> Int32;
  fn xhb_face_probe(bytes: *UInt8, len: Int32, s_upem: *UInt8, s_glyph_count: *UInt8, s_glyph_a: *UInt8, s_glyph_v: *UInt8, s_face_count: *UInt8) -> Int32;
  fn xhb_shape_probe(bytes: *UInt8, len: Int32, text_sel: Int32, s_glyph_count: *UInt8, s_direction: *UInt8, s_glyph0: *UInt8, s_cluster0: *UInt8, s_advance0: *UInt8, s_advance_sum: *UInt8, s_upem: *UInt8) -> Int32;
  fn xhb_subset_probe(bytes: *UInt8, len: Int32, out: *UInt8, out_cap: Int32, s_size: *UInt8, s_glyph_count: *UInt8, s_unicode_count: *UInt8) -> Int32;
  fn xhb_face_open(bytes: *UInt8, len: Int32) -> Int;
  fn xhb_face_close(face: Int);
  fn xhb_font_open(face: Int) -> Int;
  fn xhb_font_close(font: Int);
  fn xhb_symbol_count() -> Int32;
  fn xhb_symbol_null_count() -> Int32;
  fn xhb_symbol_name_hash() -> UInt32;
  fn xhb_face_table_len(face: Int, tag: UInt32) -> Int32;
}

// =========================================================================
// Flat outcome structs (B-26: no nested enum payloads)
// =========================================================================

/// Outcome of a shaping probe.  `ok` is the bridge status; the fields are
/// the buffer/first-glyph scalars read from XIOM-owned slots.
pub type HbshapeOutcome = {
  ok: Bool;
  rc: Int;
  glyph_count: Int;
  direction: Int;
  first_glyph: Int;
  cluster0: Int;
  advance0: Int;
  advance_sum: Int;
  upem: Int;
}

/// Outcome of a face introspection probe.
pub type HbfaceOutcome = {
  ok: Bool;
  rc: Int;
  upem: Int;
  glyph_count: Int;
  glyph_a: Int;
  glyph_v: Int;
  face_count: Int;
}

/// Outcome of a subset probe (serialized size + subset face stats).
pub type HbsubsetOutcome = {
  ok: Bool;
  rc: Int;
  size: Int;
  glyph_count: Int;
  unicode_count: Int;
}

// =========================================================================
// Surface bookkeeping
// =========================================================================

/// Declared functions in the pinned public-header closure (generation
/// oracle; 582 at harfbuzz 14.6.0).
pub fn hb_surface_declared() -> Int
  requires: true
{
  return surface.HB_SURFACE_TOTAL;
}

/// FNV-1a 32 of the ordered declared names (generator oracle).
pub fn hb_surface_hash() -> Int
  requires: true
{
  return surface.HB_SURFACE_NAME_HASH;
}

/// Functions linked in the built artifact (C address-of table size).
pub fn hb_surface_bound() -> Int
  requires: true
{
  return unsafe { xhb_symbol_count() } as Int;
}

/// Hash over the linked symbol names (C side; must equal the oracle).
/// Masked to 32 bits: the C value is uint32 and may arrive sign-extended.
pub fn hb_surface_bound_hash() -> Int
  requires: true
{
  return (unsafe { xhb_symbol_name_hash() } as Int) & 0xFFFFFFFF;
}

/// Null slots in the linked symbol table (0 == full linkage).
pub fn hb_surface_bound_nulls() -> Int
  requires: true
{
  return unsafe { xhb_symbol_null_count() } as Int;
}

/// Generated module count (sum of per-module markers; proves every
/// generated module compiles).
pub fn hb_gen_module_count() -> Int
  requires: true
{
  return hb.HB_GEN_HB_MODULE + blob.HB_GEN_BLOB_MODULE + buffer.HB_GEN_BUFFER_MODULE
    + common.HB_GEN_COMMON_MODULE + deprecated.HB_GEN_DEPRECATED_MODULE + draw.HB_GEN_DRAW_MODULE
    + face.HB_GEN_FACE_MODULE + font.HB_GEN_FONT_MODULE + map.HB_GEN_MAP_MODULE
    + ot.HB_GEN_OT_MODULE + ot_color.HB_GEN_OT_COLOR_MODULE + ot_deprecated.HB_GEN_OT_DEPRECATED_MODULE
    + ot_fetch.HB_GEN_OT_FETCH_MODULE + ot_font.HB_GEN_OT_FONT_MODULE + ot_layout.HB_GEN_OT_LAYOUT_MODULE
    + ot_math.HB_GEN_OT_MATH_MODULE + ot_meta.HB_GEN_OT_META_MODULE + ot_metrics.HB_GEN_OT_METRICS_MODULE
    + ot_name.HB_GEN_OT_NAME_MODULE + ot_shape.HB_GEN_OT_SHAPE_MODULE + ot_var.HB_GEN_OT_VAR_MODULE
    + paint.HB_GEN_PAINT_MODULE + script_list.HB_GEN_SCRIPT_LIST_MODULE + set.HB_GEN_SET_MODULE
    + shape.HB_GEN_SHAPE_MODULE + shape_plan.HB_GEN_SHAPE_PLAN_MODULE + style.HB_GEN_STYLE_MODULE
    + subset.HB_GEN_SUBSET_MODULE + subset_depend.HB_GEN_SUBSET_DEPEND_MODULE
    + subset_serialize.HB_GEN_SUBSET_SERIALIZE_MODULE + surface.HB_GEN_SURFACE_MODULE
    + unicode.HB_GEN_UNICODE_MODULE + version.HB_GEN_VERSION_MODULE;
}

// =========================================================================
// Version pin
// =========================================================================

/// Runtime major*10000+minor*100+micro of the linked harfbuzz.
pub fn hb_version_pin() -> Int
  requires: true
{
  return unsafe { xhb_version_pin() } as Int;
}

/// True when hb_version_string() == "14.6.0" (C-side compare).
pub fn hb_version_string_ok() -> Bool
  requires: true
{
  return (unsafe { xhb_version_string_ok() } as Int) == 1;
}

/// hb_version_atleast(14, 6, 0) through the vendored library.
pub fn hb_version_atleast_pin() -> Bool
  requires: true
{
  return (unsafe { xhb_version_atleast_ok() } as Int) == 1;
}

// =========================================================================
// Probes over XIOM-owned byte buffers
// =========================================================================

/// Introspect a font from caller-owned bytes (Vec kept alive by caller).
pub fn hb_face_probe(font_bytes: &mut Vec[UInt8], size: Int) -> HbfaceOutcome
  requires: size > 0
  requires: font_bytes.len() >= size
{
  var s_upem = hb_slot4();
  var s_gc = hb_slot4();
  var s_ga = hb_slot4();
  var s_gv = hb_slot4();
  var s_fc = hb_slot4();
  let rc = unsafe {
    xhb_face_probe(font_bytes.as_mut_ptr(), size as Int32,
      s_upem.as_mut_ptr(), s_gc.as_mut_ptr(), s_ga.as_mut_ptr(),
      s_gv.as_mut_ptr(), s_fc.as_mut_ptr()) as Int
  };
  return HbfaceOutcome{
    ok: rc == 0; rc: rc;
    upem: hb_rd_u32(&s_upem); glyph_count: hb_rd_u32(&s_gc);
    glyph_a: hb_rd_u32(&s_ga); glyph_v: hb_rd_u32(&s_gv);
    face_count: hb_rd_u32(&s_fc);
  };
}

/// Shape a fixed probe text (0 = "AV" LTR, 1 = "A" LTR, 2 = Arabic alef
/// RTL) over caller-owned font bytes `size` bytes long.
pub fn hb_shape_probe(font_bytes: &mut Vec[UInt8], size: Int, text_sel: Int) -> HbshapeOutcome
  requires: size > 0
  requires: font_bytes.len() >= size
  requires: text_sel >= 0
  requires: text_sel <= 2
{
  var s_count = hb_slot4();
  var s_dir = hb_slot4();
  var s_g0 = hb_slot4();
  var s_cl0 = hb_slot4();
  var s_a0 = hb_slot4();
  var s_asum = hb_slot4();
  var s_upem = hb_slot4();
  let rc = unsafe {
    xhb_shape_probe(font_bytes.as_mut_ptr(), size as Int32, text_sel as Int32,
      s_count.as_mut_ptr(), s_dir.as_mut_ptr(), s_g0.as_mut_ptr(),
      s_cl0.as_mut_ptr(), s_a0.as_mut_ptr(), s_asum.as_mut_ptr(),
      s_upem.as_mut_ptr()) as Int
  };
  return HbshapeOutcome{
    ok: rc == 0; rc: rc;
    glyph_count: hb_rd_u32(&s_count); direction: hb_rd_u32(&s_dir);
    first_glyph: hb_rd_u32(&s_g0); cluster0: hb_rd_u32(&s_cl0);
    advance0: hb_rd_u32(&s_a0); advance_sum: hb_rd_u32(&s_asum);
    upem: hb_rd_u32(&s_upem);
  };
}

/// Subset caller-owned font bytes to U+0041 and serialize into the
/// caller-owned `out` buffer (C writes; XIOM reads back byte-indexed).
pub fn hb_subset_probe(font_bytes: &mut Vec[UInt8], size: Int, out: &mut Vec[UInt8]) -> HbsubsetOutcome
  requires: size > 0
  requires: font_bytes.len() >= size
  requires: out.len() >= 65536
{
  var s_size = hb_slot4();
  var s_gc = hb_slot4();
  var s_uc = hb_slot4();
  let rc = unsafe {
    xhb_subset_probe(font_bytes.as_mut_ptr(), size as Int32,
      out.as_mut_ptr(), 65536 as Int32,
      s_size.as_mut_ptr(), s_gc.as_mut_ptr(), s_uc.as_mut_ptr()) as Int
  };
  return HbsubsetOutcome{
    ok: rc == 0; rc: rc;
    size: hb_rd_u32(&s_size); glyph_count: hb_rd_u32(&s_gc);
    unicode_count: hb_rd_u32(&s_uc);
  };
}

// =========================================================================
// Persistent face/font handles + generated-surface calls
// =========================================================================

/// Open an hb_face_t over caller-owned bytes; returns the handle as Int.
pub fn hb_face_open_probe(font_bytes: &mut Vec[UInt8], size: Int) -> Int
  requires: size > 0
  requires: font_bytes.len() >= size
{
  return unsafe { xhb_face_open(font_bytes.as_mut_ptr(), size as Int32) };
}

/// Destroy a face handle from ::hb_face_open_probe.
pub fn hb_face_close_probe(face: Int)
  requires: face != 0
{
  unsafe { xhb_face_close(face); }
}

/// Create a font for a face handle; returns the handle as Int.
pub fn hb_font_open_probe(face: Int) -> Int
  requires: face != 0
{
  return unsafe { xhb_font_open(face) };
}

/// Destroy a font handle from ::hb_font_open_probe.
pub fn hb_font_close_probe(font: Int)
  requires: font != 0
{
  unsafe { xhb_font_close(font); }
}

/// Byte length of an sfnt table through the vendored hb surface
/// (hb_face_reference_table + hb_blob_get_length + hb_blob_destroy on the
/// C side).  Returns -1 when the table is absent, -2 for a null handle.
pub fn hb_face_table_len(face_h: Int, tag: UInt32) -> Int
  requires: face_h != 0
{
  return unsafe { xhb_face_table_len(face_h, tag) } as Int;
}

// =========================================================================
// internals
// =========================================================================

/// Four zero bytes in an XIOM-owned slot.
fn hb_slot4() -> Vec[UInt8]
  requires: true
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  s.push(0 as UInt8);
  s.push(0 as UInt8);
  s.push(0 as UInt8);
  s.push(0 as UInt8);
  return s;
}

/// Little-endian u32 read from an XIOM-owned byte slot (byte-indexed).
fn hb_rd_u32(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}
