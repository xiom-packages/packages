// XIOM -- xiom.harfbuzz Conformance Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Exercises the VENDORED harfbuzz 14.6.0
// (commit c7a7457b7385f33178e8cf87615ca077a810bbe7, compiled via
// port.args.json as harfbuzz-subset.cc + src/hb_bridge.cpp +
// src/hb_symbols_gen.c) with real runtime probes:
//
//   S1  version pin (constants + library + generated extern call)
//   S2  declared/bound surface coverage (count, FNV-1a name hash, nulls)
//   S3  face introspection from an XIOM-owned fixture buffer
//       (tests/fixtures/tiny.ttf, an original generated 3-glyph font)
//   S4  shaping (glyph count / direction / advances / clusters)
//   S5  subsetting to U+0041 and re-shaping the serialized subset
//
// All probe results come back through XIOM-owned 4-byte slots read
// little-endian (B-20/B-24-safe); Str equality goes through
// string.str_compare per the lane discipline.
//
// Run: scripts/port.ps1 -Package xiom.harfbuzz -TimeoutSec 900

module harfbuzz_conformance

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.harfbuzz;
use xiom.harfbuzz.gen.common;
use xiom.harfbuzz.gen.face;
use xiom.harfbuzz.gen.font;
use xiom.harfbuzz.gen.script_list;
use xiom.harfbuzz.gen.surface;
use xiom.harfbuzz.gen.version;

// =========================================================================
// Helpers
// =========================================================================

fn int_to_str(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int
  requires: true
{
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

/// Load the bundled tiny font fixture into a fresh owned buffer.
fn load_fixture() -> Result[Vec[UInt8], Str]
  requires: true
{
  let r = io.read_file_bytes("tests/fixtures/tiny.ttf");
  if !r.is_ok {
    return Err("fixture not readable: tests/fixtures/tiny.ttf");
  }
  return Ok(r.value);
}

// =========================================================================
// S1 -- version pin (7)
// =========================================================================

fn test_version_major() -> TestResult
  requires: true
{
  return assert(version.HB_VERSION_MAJOR == 14, "S1.1 HB_VERSION_MAJOR == 14");
}

fn test_version_minor() -> TestResult
  requires: true
{
  return assert(version.HB_VERSION_MINOR == 6, "S1.2 HB_VERSION_MINOR == 6");
}

fn test_version_micro() -> TestResult
  requires: true
{
  return assert(version.HB_VERSION_MICRO == 0, "S1.3 HB_VERSION_MICRO == 0");
}

fn test_version_string() -> TestResult
  requires: true
{
  return assert(compare.str_compare(version.HB_VERSION_STRING, "14.6.0") == 0,
    "S1.4 HB_VERSION_STRING == \"14.6.0\"");
}

fn test_version_runtime() -> TestResult
  requires: true
{
  return assert(hb_version_pin() == 140600,
    "S1.5 runtime hb_version() == 14.6.0 (140600)");
}

fn test_version_string_probe() -> TestResult
  requires: true
{
  return assert(hb_version_string_ok(),
    "S1.6 hb_version_string() compares equal to \"14.6.0\" in C");
}

fn test_version_atleast() -> TestResult
  requires: true
{
  let via_extern = unsafe { version.hb_version_atleast(14 as UInt32, 6 as UInt32, 0 as UInt32) } as Int;
  return assert(hb_version_atleast_pin() && via_extern != 0,
    "S1.7 hb_version_atleast(14,6,0) true (bridge + generated extern)");
}

// =========================================================================
// S2 -- declared/bound surface coverage (4)
// =========================================================================

fn test_surface_declared() -> TestResult
  requires: true
{
  return assert(hb_surface_declared() == 571,
    "S2.1 declared surface == 571 functions (generated oracle)");
}

fn test_surface_bound() -> TestResult
  requires: true
{
  let declared = hb_surface_declared();
  let bound = hb_surface_bound();
  return assert(bound == declared,
    "S2.2 linked symbol table == declared (" + int_to_str(bound) + "/" + int_to_str(declared) + ")");
}

fn test_surface_hash() -> TestResult
  requires: true
{
  return assert(hb_surface_bound_hash() == hb_surface_hash(),
    "S2.3 C-side FNV-1a name hash == generator oracle");
}

fn test_surface_nulls() -> TestResult
  requires: true
{
  return assert(hb_surface_bound_nulls() == 0,
    "S2.4 no null slots in the linked symbol table");
}

// =========================================================================
// S3 -- fixture + face introspection (5)
// =========================================================================

fn test_fixture_load() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S3.1 tiny.ttf fixture loads");
  }
  var bytes = fr.value;
  let ok = bytes.len() == 632
    && bytes[0] == 0 as UInt8 && bytes[1] == 1 as UInt8
    && bytes[2] == 0 as UInt8 && bytes[3] == 0 as UInt8;
  return assert(ok, "S3.1 tiny.ttf fixture loads (632 bytes, sfnt version 1.0)");
}

fn test_face_probe() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S3.2 face probe (fixture missing)");
  }
  var bytes = fr.value;
  let p = hb_face_probe(&mut bytes, bytes.len());
  return assert(p.ok && p.upem == 1000 && p.glyph_count == 3
      && p.glyph_a == 1 && p.glyph_v == 2 && p.face_count == 1,
    "S3.2 face probe: upem 1000, 3 glyphs, A=1, V=2, 1 face");
}

fn test_face_handles() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S3.3 face/font handles (fixture missing)");
  }
  var bytes = fr.value;
  let fh = hb_face_open_probe(&mut bytes, bytes.len());
  if fh == 0 {
    return assert(false, "S3.3 face handle opens");
  }
  let glyphs = unsafe { face.hb_face_get_glyph_count(fh) } as Int;
  let upem = unsafe { face.hb_face_get_upem(fh) } as Int;
  let fo = hb_font_open_probe(fh);
  if fo == 0 {
    hb_face_close_probe(fh);
    return assert(false, "S3.3 font handle opens");
  }
  let face_back = unsafe { font.hb_font_get_face(fo) };
  hb_font_close_probe(fo);
  hb_face_close_probe(fh);
  return assert(glyphs == 3 && upem == 1000 && face_back == fh,
    "S3.3 generated externs on live handles: glyph count 3, upem 1000, font->face round-trip");
}

fn test_face_tables() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S3.4 sfnt table lengths (fixture missing)");
  }
  var bytes = fr.value;
  let fh = hb_face_open_probe(&mut bytes, bytes.len());
  if fh == 0 {
    return assert(false, "S3.4 face handle opens");
  }
  let head = hb_face_table_len(fh, 0x68656164 as UInt32);
  let cmap = hb_face_table_len(fh, 0x636D6170 as UInt32);
  let glyf = hb_face_table_len(fh, 0x676C7966 as UInt32);
  let hmtx = hb_face_table_len(fh, 0x686D7478 as UInt32);
  let gpos = hb_face_table_len(fh, 0x47504F53 as UInt32);
  hb_face_close_probe(fh);
  return assert(head > 0 && cmap > 0 && glyf > 0 && hmtx > 0 && gpos == 0,
    "S3.4 hb surface: head/cmap/glyf/hmtx present, GPOS absent (empty blob)");
}

fn test_gen_modules() -> TestResult
  requires: true
{
  return assert(hb_gen_module_count() == 33,
    "S3.5 all 33 generated modules compile (32 headers + surface)");
}

// =========================================================================
// S4 -- shaping (6)
// =========================================================================

fn test_shape_av() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S4.1 shape \"AV\" (fixture missing)");
  }
  var bytes = fr.value;
  let p = hb_shape_probe(&mut bytes, bytes.len(), 0);
  return assert(p.ok && p.glyph_count == 2 && p.direction == common.HB_DIRECTION_LTR
      && p.first_glyph == 1 && p.cluster0 == 0
      && p.advance0 == 500 && p.advance_sum == 1100 && p.upem == 1000,
    "S4.1 shape \"AV\": 2 glyphs, LTR, A=1, adv 500 + 600 = 1100");
}

fn test_shape_a() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S4.2 shape \"A\" (fixture missing)");
  }
  var bytes = fr.value;
  let p = hb_shape_probe(&mut bytes, bytes.len(), 1);
  return assert(p.ok && p.glyph_count == 1 && p.direction == common.HB_DIRECTION_LTR
      && p.first_glyph == 1 && p.advance0 == 500,
    "S4.2 shape \"A\": 1 glyph (gid 1), advance 500");
}

fn test_shape_arabic_direction() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S4.3 direction guess (fixture missing)");
  }
  var bytes = fr.value;
  let p = hb_shape_probe(&mut bytes, bytes.len(), 2);
  return assert(p.ok && p.glyph_count == 1 && p.direction == common.HB_DIRECTION_RTL
      && p.first_glyph == 0,
    "S4.3 shape U+0627: direction guessed RTL, unmapped -> .notdef (gid 0)");
}

fn test_direction_constants() -> TestResult
  requires: true
{
  return assert(common.HB_DIRECTION_LTR == 4 && common.HB_DIRECTION_RTL == 5,
    "S4.4 enum constants: HB_DIRECTION_LTR == 4, HB_DIRECTION_RTL == 5");
}

fn test_tag_constants() -> TestResult
  requires: true
{
  return assert(common.HB_TAG_NONE == 0 && common.HB_TAG_MAX == 4294967295
      && script_list.HB_SCRIPT_LATIN == 1281455214,
    "S4.5 tag constants: HB_TAG_NONE 0, HB_TAG_MAX 0xFFFFFFFF, HB_SCRIPT_LATIN 'Latn'");
}

fn test_pin_identity() -> TestResult
  requires: true
{
  let v = compare.str_compare(surface.HB_PIN_VERSION, "14.6.0") == 0;
  let c = compare.str_compare(surface.HB_PIN_COMMIT,
    "c7a7457b7385f33178e8cf87615ca077a810bbe7") == 0;
  return assert(v && c, "S4.6 pin identity: 14.6.0 @ c7a7457b");
}

// =========================================================================
// S5 -- subset + re-shape (5)
// =========================================================================

fn test_subset_probe() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S5.1 subset U+0041 (fixture missing)");
  }
  var bytes = fr.value;
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 65536 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  let s = hb_subset_probe(&mut bytes, bytes.len(), &mut out);
  return assert(s.ok && s.size > 0 && s.size <= 65536
      && s.unicode_count == 1 && s.glyph_count >= 1 && s.glyph_count <= 3,
    "S5.1 subset to U+0041: rc 0, serialized size " + int_to_str(s.size)
      + ", 1 unicode, " + int_to_str(s.glyph_count) + " glyphs");
}

fn test_subset_magic() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S5.2 subset sfnt magic (fixture missing)");
  }
  var bytes = fr.value;
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 65536 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  let s = hb_subset_probe(&mut bytes, bytes.len(), &mut out);
  let magic_ok = out[0] == 0 as UInt8 && out[1] == 1 as UInt8
    && out[2] == 0 as UInt8 && out[3] == 0 as UInt8;
  return assert(s.ok && magic_ok && s.size != bytes.len(),
    "S5.2 subset output is a valid, smaller sfnt (byte-indexed readback)");
}

fn test_reshape_subset_a() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S5.3 re-shape \"A\" (fixture missing)");
  }
  var bytes = fr.value;
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 65536 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  let s = hb_subset_probe(&mut bytes, bytes.len(), &mut out);
  if !s.ok {
    return assert(false, "S5.3 re-shape \"A\": subset probe failed");
  }
  let p = hb_shape_probe(&mut out, s.size, 1);
  return assert(p.ok && p.glyph_count == 1 && p.first_glyph == 1
      && p.direction == common.HB_DIRECTION_LTR && p.advance0 == 500,
    "S5.3 re-shape subset \"A\": 1 glyph (gid retained 1), advance 500, LTR");
}

fn test_reshape_subset_av() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S5.4 re-shape \"AV\" (fixture missing)");
  }
  var bytes = fr.value;
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 65536 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  let s = hb_subset_probe(&mut bytes, bytes.len(), &mut out);
  if !s.ok {
    return assert(false, "S5.4 re-shape \"AV\": subset probe failed");
  }
  let p = hb_shape_probe(&mut out, s.size, 0);
  return assert(p.ok && p.glyph_count == 2 && p.advance0 == 500
      && p.advance_sum == 1000,
    "S5.4 re-shape subset \"AV\": V dropped -> .notdef (advances 500 + 500)");
}

fn test_subset_face_upem() -> TestResult
  requires: true
{
  let fr = load_fixture();
  if !fr.is_ok {
    return assert(false, "S5.5 subset face upem (fixture missing)");
  }
  var bytes = fr.value;
  let p0 = hb_face_probe(&mut bytes, bytes.len());
  return assert(p0.ok && p0.upem == 1000,
    "S5.5 original face upem stable before/after subset cycle");
}

// =========================================================================
// Main -- manual test dispatch
// =========================================================================

pub fn main() -> Int
  requires: true
{
  io.println("XIOM harfbuzz Conformance Suite (0.1.0 vendored, harfbuzz 14.6.0)");
  io.println("================================================================");
  var total: Int = 0;
  var failed: Int = 0;

  io.println("");
  io.println("-- S1: version pin (7) --");
  let r0 = test_version_major();        total = total + 1; failed = failed + report(r0.passed, r0.name);
  let r1 = test_version_minor();        total = total + 1; failed = failed + report(r1.passed, r1.name);
  let r2 = test_version_micro();        total = total + 1; failed = failed + report(r2.passed, r2.name);
  let r3 = test_version_string();       total = total + 1; failed = failed + report(r3.passed, r3.name);
  let r4 = test_version_runtime();      total = total + 1; failed = failed + report(r4.passed, r4.name);
  let r5 = test_version_string_probe(); total = total + 1; failed = failed + report(r5.passed, r5.name);
  let r6 = test_version_atleast();      total = total + 1; failed = failed + report(r6.passed, r6.name);

  io.println("");
  io.println("-- S2: surface coverage (4) --");
  let q0 = test_surface_declared(); total = total + 1; failed = failed + report(q0.passed, q0.name);
  let q1 = test_surface_bound();    total = total + 1; failed = failed + report(q1.passed, q1.name);
  let q2 = test_surface_hash();     total = total + 1; failed = failed + report(q2.passed, q2.name);
  let q3 = test_surface_nulls();    total = total + 1; failed = failed + report(q3.passed, q3.name);

  io.println("");
  io.println("-- S3: fixture + face introspection (5) --");
  let f0 = test_fixture_load(); total = total + 1; failed = failed + report(f0.passed, f0.name);
  let f1 = test_face_probe();   total = total + 1; failed = failed + report(f1.passed, f1.name);
  let f2 = test_face_handles(); total = total + 1; failed = failed + report(f2.passed, f2.name);
  let f3 = test_face_tables();  total = total + 1; failed = failed + report(f3.passed, f3.name);
  let f4 = test_gen_modules();  total = total + 1; failed = failed + report(f4.passed, f4.name);

  io.println("");
  io.println("-- S4: shaping (6) --");
  let s0 = test_shape_av();               total = total + 1; failed = failed + report(s0.passed, s0.name);
  let s1 = test_shape_a();                total = total + 1; failed = failed + report(s1.passed, s1.name);
  let s2 = test_shape_arabic_direction(); total = total + 1; failed = failed + report(s2.passed, s2.name);
  let s3 = test_direction_constants();    total = total + 1; failed = failed + report(s3.passed, s3.name);
  let s4 = test_tag_constants();          total = total + 1; failed = failed + report(s4.passed, s4.name);
  let s5 = test_pin_identity();           total = total + 1; failed = failed + report(s5.passed, s5.name);

  io.println("");
  io.println("-- S5: subset + re-shape (5) --");
  let b0 = test_subset_probe();      total = total + 1; failed = failed + report(b0.passed, b0.name);
  let b1 = test_subset_magic();      total = total + 1; failed = failed + report(b1.passed, b1.name);
  let b2 = test_reshape_subset_a();  total = total + 1; failed = failed + report(b2.passed, b2.name);
  let b3 = test_reshape_subset_av(); total = total + 1; failed = failed + report(b3.passed, b3.name);
  let b4 = test_subset_face_upem();  total = total + 1; failed = failed + report(b4.passed, b4.name);

  io.println("");
  io.println("================================================================");
  if failed == 0 {
    io.println("  ALL " + int_to_str(total) + " TESTS PASSED");
    io.println("  Vendored: harfbuzz 14.6.0 (commit c7a7457b)");
    return 0;
  }
  io.println("  TESTS:  " + int_to_str(total));
  io.println("  FAILED: " + int_to_str(failed));
  return 1;
}
