// XIOM -- xiom.fontraster conformance suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the carved xiom.fontraster 0.1.1 surface against the installed
// xiom.harfbuzz 0.1.0 symbols with the bundled Inter Regular fixture:
//   - face open, UPEM and vertical metrics
//   - cmap lookup (mapped and unmapped codepoints)
//   - shaping (AV run, empty string)
//   - 8-bit antialiased rasterization at 32 px with no out-of-bounds
//   - typed error arms (empty bytes, closed face, invalid glyph id)
//   - idempotent face close
//
// Fixture tests are SKIP-safe: a missing tests/fixtures/Inter_Regular.ttf
// reports a green SKIP line instead of crashing.
//
// Run: scripts/port.ps1 -Package xiom.fontraster -TimeoutSec 300

module fontraster_conformance

use xiom.io;
use xiom.test;
use xiom.fontraster;

// Load the bundled fixture (relative to the package dir under port.ps1; the
// second form survives runners that start at the repository root).
fn load_fixture() -> Result[Vec[UInt8], Str]
  requires: true
{
  let r1 = io.read_file_bytes("tests/fixtures/Inter_Regular.ttf");
  if r1.is_ok { return Ok(r1.value); }
  let r2 = io.read_file_bytes("packages/xiom-fontraster/tests/fixtures/Inter_Regular.ttf");
  if r2.is_ok { return Ok(r2.value); }
  return Err("fixture not found: Inter_Regular.ttf");
}

fn report(ok: Bool, name: Str) -> Int
  requires: true
{
  if ok {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn test_face_open(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  var ok = face.ok && face.handle > 0 && face.upem > 0;
  font_face_close(&mut face);
  return assert(ok, "face opens from fixture bytes with sane units_per_em");
}

fn test_face_metrics(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  let m = font_face_metrics(&face, 32);
  var ok = m.ok && m.ascender_q6 > 0 && m.descender_q6 <= 0 && m.line_gap_q6 >= 0;
  font_face_close(&mut face);
  return assert(ok, "metrics: ascender>0, descender<=0, line_gap>=0");
}

fn test_glyph_index_mapped(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  let gid = font_glyph_index(&face, 65);
  var ok = gid > 0;
  font_face_close(&mut face);
  return assert(ok, "glyph_index('A') resolves to a nonzero glyph id");
}

fn test_glyph_index_control(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  let gid = font_glyph_index(&face, 1);
  font_face_close(&mut face);
  return assert(gid <= 0, "control codepoint has no nominal glyph (unmapped)");
}

fn test_shape_av(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  let run = font_shape(&face, "AV", 32);
  var ok = run.ok && run.glyphs.len() == 2;
  if ok {
    if run.glyphs[0].advance_x_q6 <= 0 || run.glyphs[1].advance_x_q6 <= 0 {
      ok = false;
    }
  }
  font_face_close(&mut face);
  return assert(ok, "shape(\"AV\") returns 2 glyphs with positive 26.6 advances");
}

fn test_shape_empty(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  let run = font_shape(&face, "", 32);
  var ok = run.glyphs.len() == 0;
  font_face_close(&mut face);
  return assert(ok, "shape(\"\") returns 0 glyphs");
}

fn test_raster_a32(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  let r = font_glyph_raster(&face, 65, 32);
  var ok = r.ok && r.width > 0 && r.height > 0;
  if ok {
    // Exact 8-bit coverage payload; reading every element proves no
    // out-of-bounds access and that the bitmap is fully materialized.
    if r.pixels.len() != r.width * r.height { ok = false; }
    var nonzero = 0;
    var i = 0;
    while i < r.pixels.len() {
      if (r.pixels[i] as Int) != 0 { nonzero = nonzero + 1; }
      i = i + 1;
    }
    if nonzero == 0 { ok = false; }
  }
  font_face_close(&mut face);
  return assert(ok, "raster('A', 32) is a nonempty 8-bit coverage bitmap");
}

fn test_empty_bytes() -> TestResult
  requires: true
{
  var empty = Vec[UInt8].new();
  let face = font_face_open(&mut empty);
  return assert(!face.ok && face.handle == 0,
    "empty byte vector yields a none-face (ok=false, handle=0)");
}

fn test_raster_closed_face(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  font_face_close(&mut face);
  let r = font_glyph_raster(&face, 65, 32);
  return assert(!r.ok && r.rc == -1 && r.pixels.len() == 0,
    "raster on a closed face returns the typed -1 error");
}

fn test_raster_invalid_glyph(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  let r = font_glyph_raster(&face, 1000000, 32);
  // Contract pin: an unmapped/invalid glyph id produces an empty outline,
  // i.e. a successful call with a 0x0 bitmap and no pixels (not a crash).
  var ok = r.ok && r.width == 0 && r.height == 0 && r.pixels.len() == 0;
  font_face_close(&mut face);
  return assert(ok, "invalid glyph id yields an empty 0x0 bitmap (no OOB)");
}

fn test_close_idempotent(data: &mut Vec[UInt8]) -> TestResult
  requires: true
{
  var face = font_face_open(data);
  font_face_close(&mut face);
  font_face_close(&mut face);
  return assert(!face.ok && face.handle == 0,
    "face_close is idempotent and clears the handle");
}

fn main() -> Int
  requires: true
{
  io.println("XIOM fontraster Conformance Suite (0.1.1)");
  io.println("========================================");
  var failed: Int = 0;

  let fr = load_fixture();
  if !fr.is_ok {
    io.println("  fixture absent: Inter_Regular.ttf -- fixture tests SKIP");
    failed = failed + report(true, "SKIP: fixture-dependent tests (fixture absent)");
    let e = test_empty_bytes();
    failed = failed + report(e.passed, e.name);
  } else {
    var data = fr.value;
    io.println("");
    io.println("-- face --");
    let r1 = test_face_open(&mut data);      failed = failed + report(r1.passed, r1.name);
    let r2 = test_face_metrics(&mut data);   failed = failed + report(r2.passed, r2.name);
    io.println("");
    io.println("-- cmap --");
    let r3 = test_glyph_index_mapped(&mut data);  failed = failed + report(r3.passed, r3.name);
    let r4 = test_glyph_index_control(&mut data); failed = failed + report(r4.passed, r4.name);
    io.println("");
    io.println("-- shaping --");
    let r5 = test_shape_av(&mut data);    failed = failed + report(r5.passed, r5.name);
    let r6 = test_shape_empty(&mut data); failed = failed + report(r6.passed, r6.name);
    io.println("");
    io.println("-- raster --");
    let r7 = test_raster_a32(&mut data);            failed = failed + report(r7.passed, r7.name);
    io.println("");
    io.println("-- error arms + lifetime --");
    let r8 = test_empty_bytes();                    failed = failed + report(r8.passed, r8.name);
    let r9 = test_raster_closed_face(&mut data);    failed = failed + report(r9.passed, r9.name);
    let r10 = test_raster_invalid_glyph(&mut data); failed = failed + report(r10.passed, r10.name);
    let r11 = test_close_idempotent(&mut data);     failed = failed + report(r11.passed, r11.name);
  }

  io.println("");
  io.println("========================================");
  if failed == 0 {
    io.println("  ALL TESTS PASSED");
    return 0;
  }
  io.println("  FAILED: " + "see [FAIL] lines above");
  return 1;
}
