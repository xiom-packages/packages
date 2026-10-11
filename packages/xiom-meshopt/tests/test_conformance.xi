// XIOM -- meshopt Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 0.2.0 (pool drive): the suite exercises the VENDORED meshoptimizer
// (v1.2 @ f843aae0, compiled via port.args.json) with real runtime probes
// plus the 16 compile-time constant checks.  Probe out-params come back
// through XIOM-owned 4-byte slots read little-endian; the index-buffer
// direction (C writes into an XIOM-owned byte slot, read byte-indexed)
// stays on the B-16/B-17/B-20-safe path.
//
// 0.3.0 (Phase 3 item 1): adds the owned-buffer wrapper checks -- remap,
// in-place cache optimize, and simplify over caller-owned byte meshes
// (f32 positions stride 12, u32 indices), all in the same safe direction.
//
// 0.4.0 (Phase 3 item 2): adds codec-family checks -- index sequence codec
// (byte-exact order preserved), the quat/exp/color filter family, and the
// meshlet codec (typed 4/3 decode round trip).
//
// Run: scripts/port.ps1 -Package xiom.meshopt (the port.args.json --c-source
// list compiles the bridge + the 20 vendored TUs).

module meshopt_conformance
use xiom.io;
use xiom.test;
use xiom.meshopt;

// =========================================================================
// Helpers
// =========================================================================

fn int_to_str(n: Int) -> Str {
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

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

/// n zero bytes in an XIOM-owned slot.
fn probe_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Little-endian u32 read from an XIOM-owned byte slot (byte-indexed).
fn probe_rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Little-endian u32 write into an XIOM-owned byte slot (byte-indexed).
fn probe_wr_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  buf[off + 0] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
  buf[off + 2] = ((v >> 16) & 255) as UInt8;
  buf[off + 3] = ((v >> 24) & 255) as UInt8;
}

// =========================================================================
// SECTION 1 -- Constant verification (16 tests)
// =========================================================================

fn run_const_simplify_lock_border() -> Int {
  if MESHOPT_SIMPLIFY_LOCK_BORDER == 1 as Int32 { return 0; }
  return 1;
}

fn test_const_simplify_lock_border() -> TestResult {
  let rc = run_const_simplify_lock_border();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_LOCK_BORDER == 1"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_LOCK_BORDER == 1");
}

fn run_const_simplify_sparse() -> Int {
  if MESHOPT_SIMPLIFY_SPARSE == 2 as Int32 { return 0; }
  return 1;
}

fn test_const_simplify_sparse() -> TestResult {
  let rc = run_const_simplify_sparse();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_SPARSE == 2"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_SPARSE == 2");
}

fn run_const_simplify_error_absolute() -> Int {
  if MESHOPT_SIMPLIFY_ERROR_ABSOLUTE == 4 as Int32 { return 0; }
  return 1;
}

fn test_const_simplify_error_absolute() -> TestResult {
  let rc = run_const_simplify_error_absolute();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_ERROR_ABSOLUTE == 4"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_ERROR_ABSOLUTE == 4");
}

fn run_const_simplify_prune() -> Int {
  if MESHOPT_SIMPLIFY_PRUNE == 8 as Int32 { return 0; }
  return 1;
}

fn test_const_simplify_prune() -> TestResult {
  let rc = run_const_simplify_prune();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_PRUNE == 8"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_PRUNE == 8");
}

fn run_const_simplify_regularize() -> Int {
  if MESHOPT_SIMPLIFY_REGULARIZE == 16 as Int32 { return 0; }
  return 1;
}

fn test_const_simplify_regularize() -> TestResult {
  let rc = run_const_simplify_regularize();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_REGULARIZE == 16"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_REGULARIZE == 16");
}

fn run_const_simplify_permissive() -> Int {
  if MESHOPT_SIMPLIFY_PERMISSIVE == 32 as Int32 { return 0; }
  return 1;
}

fn test_const_simplify_permissive() -> TestResult {
  let rc = run_const_simplify_permissive();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_PERMISSIVE == 32"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_PERMISSIVE == 32");
}

fn run_const_simplify_regularize_light() -> Int {
  if MESHOPT_SIMPLIFY_REGULARIZE_LIGHT == 64 as Int32 { return 0; }
  return 1;
}

fn test_const_simplify_regularize_light() -> TestResult {
  let rc = run_const_simplify_regularize_light();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_REGULARIZE_LIGHT == 64"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_REGULARIZE_LIGHT == 64");
}

fn run_const_vertex_lock() -> Int {
  if MESHOPT_SIMPLIFY_VERTEX_LOCK == 1 as Int32 { return 0; }
  return 1;
}

fn test_const_vertex_lock() -> TestResult {
  let rc = run_const_vertex_lock();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_VERTEX_LOCK == 1"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_VERTEX_LOCK == 1");
}

fn run_const_vertex_protect() -> Int {
  if MESHOPT_SIMPLIFY_VERTEX_PROTECT == 2 as Int32 { return 0; }
  return 1;
}

fn test_const_vertex_protect() -> TestResult {
  let rc = run_const_vertex_protect();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_VERTEX_PROTECT == 2"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_VERTEX_PROTECT == 2");
}

fn run_const_vertex_priority() -> Int {
  if MESHOPT_SIMPLIFY_VERTEX_PRIORITY == 4 as Int32 { return 0; }
  return 1;
}

fn test_const_vertex_priority() -> TestResult {
  let rc = run_const_vertex_priority();
  if rc == 0 { return assert(true, "const: MESHOPT_SIMPLIFY_VERTEX_PRIORITY == 4"); }
  return assert(false, "const: MESHOPT_SIMPLIFY_VERTEX_PRIORITY == 4");
}

fn run_const_encode_exp_separate() -> Int {
  if MESHOPT_ENCODE_EXP_SEPARATE == 0 as Int32 { return 0; }
  return 1;
}

fn test_const_encode_exp_separate() -> TestResult {
  let rc = run_const_encode_exp_separate();
  if rc == 0 { return assert(true, "const: MESHOPT_ENCODE_EXP_SEPARATE == 0"); }
  return assert(false, "const: MESHOPT_ENCODE_EXP_SEPARATE == 0");
}

fn run_const_encode_exp_shared_vector() -> Int {
  if MESHOPT_ENCODE_EXP_SHARED_VECTOR == 1 as Int32 { return 0; }
  return 1;
}

fn test_const_encode_exp_shared_vector() -> TestResult {
  let rc = run_const_encode_exp_shared_vector();
  if rc == 0 { return assert(true, "const: MESHOPT_ENCODE_EXP_SHARED_VECTOR == 1"); }
  return assert(false, "const: MESHOPT_ENCODE_EXP_SHARED_VECTOR == 1");
}

fn run_const_encode_exp_shared_component() -> Int {
  if MESHOPT_ENCODE_EXP_SHARED_COMPONENT == 2 as Int32 { return 0; }
  return 1;
}

fn test_const_encode_exp_shared_component() -> TestResult {
  let rc = run_const_encode_exp_shared_component();
  if rc == 0 { return assert(true, "const: MESHOPT_ENCODE_EXP_SHARED_COMPONENT == 2"); }
  return assert(false, "const: MESHOPT_ENCODE_EXP_SHARED_COMPONENT == 2");
}

fn run_const_encode_exp_clamped() -> Int {
  if MESHOPT_ENCODE_EXP_CLAMPED == 3 as Int32 { return 0; }
  return 1;
}

fn test_const_encode_exp_clamped() -> TestResult {
  let rc = run_const_encode_exp_clamped();
  if rc == 0 { return assert(true, "const: MESHOPT_ENCODE_EXP_CLAMPED == 3"); }
  return assert(false, "const: MESHOPT_ENCODE_EXP_CLAMPED == 3");
}

fn run_const_tangent_compatible() -> Int {
  if MESHOPT_TANGENT_COMPATIBLE == 1 as Int32 { return 0; }
  return 1;
}

fn test_const_tangent_compatible() -> TestResult {
  let rc = run_const_tangent_compatible();
  if rc == 0 { return assert(true, "const: MESHOPT_TANGENT_COMPATIBLE == 1"); }
  return assert(false, "const: MESHOPT_TANGENT_COMPATIBLE == 1");
}

fn run_const_tangent_zero_fallback() -> Int {
  if MESHOPT_TANGENT_ZERO_FALLBACK == 2 as Int32 { return 0; }
  return 1;
}

fn test_const_tangent_zero_fallback() -> TestResult {
  let rc = run_const_tangent_zero_fallback();
  if rc == 0 { return assert(true, "const: MESHOPT_TANGENT_ZERO_FALLBACK == 2"); }
  return assert(false, "const: MESHOPT_TANGENT_ZERO_FALLBACK == 2");
}

// =========================================================================
// SECTION 2 -- Vendored runtime probes (12 tests)
// =========================================================================

fn test_probe_version() -> TestResult {
  let v = meshopt_version();
  return assert(v == 1020, "probe: MESHOPTIMIZER_VERSION == 1020 (v1.2)");
}

fn test_probe_remap() -> TestResult {
  let p = meshopt_remap_probe();
  return assert(p.unique == 4 && p.valid,
    "probe: duplicated quad remaps to 4 unique vertices (mapped indices valid)");
}

fn test_probe_cache() -> TestResult {
  let p = meshopt_cache_probe();
  return assert(p.acmr_after_milli < p.acmr_before_milli
      && p.acmr_after_milli >= 400 && p.acmr_after_milli <= 2000
      && p.transformed_after < p.transformed_before,
    "probe: optimizeVertexCache lowers ACMR and transformed-vertex count");
}

fn test_probe_fetch() -> TestResult {
  let p = meshopt_fetch_probe();
  return assert(p.bytes_fetched > 0 && p.overfetch_milli >= 1000,
    "probe: analyzeVertexFetch reports bytes fetched and overfetch >= 1.0");
}

fn test_probe_simplify() -> TestResult {
  let p = meshopt_simplify_probe();
  return assert(p.out_count % 3 == 0 && p.out_count <= 102 && p.out_count >= 84
      && p.err_milli <= 50,
    "probe: simplify reaches ~100 indices at <= 5% relative error");
}

fn test_probe_index_codec() -> TestResult {
  let p = meshopt_index_codec_probe();
  return assert(p.enc_size > 0 && p.dec_rc == 0 && p.equal,
    "probe: index codec round trip preserves the triangle set (corner rotations allowed)");
}

fn test_probe_vertex_codec() -> TestResult {
  let p = meshopt_vertex_codec_probe();
  return assert(p.enc_size > 0 && p.dec_rc == 0 && p.equal,
    "probe: vertex codec round trip is byte-exact");
}

fn test_probe_strip() -> TestResult {
  let p = meshopt_strip_probe();
  return assert(p.strip_count > 0 && p.set_equal && p.unstrip_triangles == 98,
    "probe: stripify/unstripify preserves the 98-triangle set");
}

fn test_probe_quant() -> TestResult {
  let p = meshopt_quant_probe();
  return assert(p.half_one == 15360 && p.half_neg_two == 49152 && p.back_one_milli == 1000,
    "probe: fp16 patterns (1.0 -> 0x3C00, -2.0 -> 0xC000) and dequantize round trip");
}

fn test_probe_sphere_bounds() -> TestResult {
  let p = meshopt_sphere_bounds_probe();
  return assert(p.center_x_milli == 1000 && p.center_y_milli == 1000
      && p.radius_milli >= 1410 && p.radius_milli <= 1420,
    "probe: enclosing sphere of the 2x2 planar square (center 1,1; r = sqrt(2))");
}

fn test_probe_meshlet() -> TestResult {
  let p = meshopt_meshlet_probe();
  return assert(p.meshlet_count >= 1 && p.triangle_sum == p.input_triangles
      && p.input_triangles == 98,
    "probe: buildMeshlets conserves all 98 triangles");
}

fn test_probe_oct_filter() -> TestResult {
  let e = meshopt_oct_filter_probe();
  return assert(e <= 20, "probe: 8-bit octahedral normal error <= 0.02");
}

// =========================================================================
// SECTION 3 -- XIOM-owned buffer direction (2 tests)
// =========================================================================

fn test_owned_buffer_roundtrip() -> TestResult {
  var buf = probe_slot(MESHOPT_PROBE_INDEX_BYTES);
  let built = meshopt_probe_build_indices(&mut buf);
  if built != MESHOPT_PROBE_INDEX_COUNT {
    return assert(false, "probe: C writes the 294-index grid into an XIOM-owned slot");
  }
  let cs0 = meshopt_probe_checksum(&mut buf);
  let ok = meshopt_probe_optimize_inplace(&mut buf);
  let cs1 = meshopt_probe_checksum(&mut buf);
  return assert(ok && cs1 != cs0,
    "probe: in-place optimize preserves the triangle set and reorders (checksum changes)");
}

fn test_owned_buffer_readback() -> TestResult {
  var buf = probe_slot(MESHOPT_PROBE_INDEX_BYTES);
  let built = meshopt_probe_build_indices(&mut buf);
  let ok = meshopt_probe_optimize_inplace(&mut buf);
  var all_ok = built == MESHOPT_PROBE_INDEX_COUNT && ok;
  var i = 0;
  while i < MESHOPT_PROBE_INDEX_COUNT {
    let v = probe_rd_u32(&buf, i * 4);
    if v >= MESHOPT_PROBE_VERTEX_COUNT { all_ok = false; }
    i = i + 1;
  }
  return assert(all_ok,
    "probe: byte-indexed readback of optimized indices stays < vertex_count");
}

// =========================================================================
// SECTION 4 -- owned-buffer wrappers (3 tests)
// =========================================================================

fn test_wrapper_remap() -> TestResult {
  // 6 vertices x 12 bytes: four distinct corners with two duplicates
  // (tags 0,1,2,3,0,1); u32 indices 0..5.
  var verts = probe_slot(6 * 12);
  verts[0] = 0 as UInt8;
  verts[12] = 1 as UInt8;
  verts[24] = 2 as UInt8;
  verts[36] = 3 as UInt8;
  verts[48] = 0 as UInt8;
  verts[60] = 1 as UInt8;
  var idx = probe_slot(6 * 4);
  var i = 0;
  while i < 6 {
    probe_wr_u32(&mut idx, i * 4, i);
    i = i + 1;
  }
  var outv = probe_slot(4 * 12);
  let r = meshopt_remap_mesh(&mut verts, 6, 12, &mut idx, 6, &mut outv);
  var ok = false;
  if r.is_ok && r.value == 4 {
    var all_in = true;
    var j = 0;
    while j < 6 {
      if probe_rd_u32(&idx, j * 4) >= 4 { all_in = false; }
      j = j + 1;
    }
    ok = all_in && outv[0] == 0 as UInt8 && outv[12] == 1 as UInt8
      && outv[24] == 2 as UInt8 && outv[36] == 3 as UInt8;
  }
  return assert(ok, "wrappers: remap quad -> 4 unique, indices rewritten, vertices copied out");
}

fn test_wrapper_optimize() -> TestResult {
  var gpos = probe_slot(64 * 12);
  var gidx = probe_slot(294 * 4);
  let filled = meshopt_fill_grid(8, 8, 25000, &mut gpos, &mut gidx);
  let cs0 = meshopt_probe_checksum(&mut gidx);
  let ok_opt = meshopt_optimize_mesh(&mut gidx, 294, 64);
  let cs1 = meshopt_probe_checksum(&mut gidx);
  var all_in = true;
  var i = 0;
  while i < 294 {
    if probe_rd_u32(&gidx, i * 4) >= 64 { all_in = false; }
    i = i + 1;
  }
  return assert(filled == 294 && ok_opt && cs1 != cs0 && all_in,
    "wrappers: in-place optimize on the filled grid (triangle set preserved, order changed)");
}

fn test_wrapper_simplify() -> TestResult {
  var spos = probe_slot(121 * 12);
  var sidx = probe_slot(600 * 4);
  var sout = probe_slot(600 * 4);
  let filled = meshopt_fill_grid(11, 11, 20000, &mut spos, &mut sidx);
  let r = meshopt_simplify_mesh(&mut spos, 121, 12, &mut sidx, 600, 100, 50, &mut sout);
  var ok = false;
  if filled == 600 && r.is_ok {
    ok = r.value.index_count % 3 == 0 && r.value.index_count <= 102
      && r.value.index_count >= 84 && r.value.error_milli <= 50;
    var i = 0;
    while i < r.value.index_count {
      if probe_rd_u32(&sout, i * 4) >= 121 { ok = false; }
      i = i + 1;
    }
  }
  return assert(ok, "wrappers: simplify the 11x11 grid (count ~100, error <= 5%, indices in range)");
}

// =========================================================================
// SECTION 5 -- codec family (5 tests)
// =========================================================================

fn test_codec_index_sequence() -> TestResult {
  let p = meshopt_index_sequence_probe();
  var ok = false;
  if p.is_ok {
    ok = p.value.enc_size > 0 && p.value.dec_rc == 0 && p.value.equal;
  }
  return assert(ok, "codec: index sequence round trip is byte-exact (order preserved)");
}

fn test_codec_filter_quat() -> TestResult {
  let e = meshopt_filter_quat_probe();
  return assert(e <= 100, "codec: quat filter round trip (16-bit, max err <= 100 micro)");
}

fn test_codec_filter_exp() -> TestResult {
  let e = meshopt_filter_exp_probe();
  return assert(e <= 200, "codec: exp filter round trip (16-bit, max rel err <= 200 micro)");
}

fn test_codec_filter_color() -> TestResult {
  let e = meshopt_filter_color_probe();
  return assert(e <= 20000, "codec: color filter round trip (8-bit YCoCg, max err <= 0.02)");
}

fn test_codec_meshlet() -> TestResult {
  let p = meshopt_meshlet_codec_probe();
  var ok = false;
  if p.is_ok {
    ok = p.value.vertex_count >= 1 && p.value.triangle_count >= 1
      && p.value.enc_size > 0 && p.value.dec_rc == 0 && p.value.equal;
  }
  return assert(ok, "codec: meshlet round trip (vertex refs exact; triangle corners may rotate)");
}

// =========================================================================
// Main -- manual test dispatch
// =========================================================================

pub fn main() -> Int {
  io.println("XIOM meshopt Conformance Suite (0.4.0 vendored)");
  io.println("==============================================");
  var total: Int = 0;
  var failed: Int = 0;

  io.println("");
  io.println("-- SECTION 1: Constants (16) --");

  let r0  = test_const_simplify_lock_border();        total = total + 1; failed = failed + report(r0.passed,  r0.name);
  let r1  = test_const_simplify_sparse();              total = total + 1; failed = failed + report(r1.passed,  r1.name);
  let r2  = test_const_simplify_error_absolute();      total = total + 1; failed = failed + report(r2.passed,  r2.name);
  let r3  = test_const_simplify_prune();               total = total + 1; failed = failed + report(r3.passed,  r3.name);
  let r4  = test_const_simplify_regularize();          total = total + 1; failed = failed + report(r4.passed,  r4.name);
  let r5  = test_const_simplify_permissive();          total = total + 1; failed = failed + report(r5.passed,  r5.name);
  let r6  = test_const_simplify_regularize_light();    total = total + 1; failed = failed + report(r6.passed,  r6.name);
  let r7  = test_const_vertex_lock();                  total = total + 1; failed = failed + report(r7.passed,  r7.name);
  let r8  = test_const_vertex_protect();               total = total + 1; failed = failed + report(r8.passed,  r8.name);
  let r9  = test_const_vertex_priority();              total = total + 1; failed = failed + report(r9.passed,  r9.name);
  let r10 = test_const_encode_exp_separate();          total = total + 1; failed = failed + report(r10.passed, r10.name);
  let r11 = test_const_encode_exp_shared_vector();     total = total + 1; failed = failed + report(r11.passed, r11.name);
  let r12 = test_const_encode_exp_shared_component();  total = total + 1; failed = failed + report(r12.passed, r12.name);
  let r13 = test_const_encode_exp_clamped();           total = total + 1; failed = failed + report(r13.passed, r13.name);
  let r14 = test_const_tangent_compatible();           total = total + 1; failed = failed + report(r14.passed, r14.name);
  let r15 = test_const_tangent_zero_fallback();        total = total + 1; failed = failed + report(r15.passed, r15.name);

  io.println("");
  io.println("-- SECTION 2: vendored runtime probes (12) --");

  let q0  = test_probe_version();         total = total + 1; failed = failed + report(q0.passed,  q0.name);
  let q1  = test_probe_remap();           total = total + 1; failed = failed + report(q1.passed,  q1.name);
  let q2  = test_probe_cache();           total = total + 1; failed = failed + report(q2.passed,  q2.name);
  let q3  = test_probe_fetch();           total = total + 1; failed = failed + report(q3.passed,  q3.name);
  let q4  = test_probe_simplify();        total = total + 1; failed = failed + report(q4.passed,  q4.name);
  let q5  = test_probe_index_codec();     total = total + 1; failed = failed + report(q5.passed,  q5.name);
  let q6  = test_probe_vertex_codec();    total = total + 1; failed = failed + report(q6.passed,  q6.name);
  let q7  = test_probe_strip();           total = total + 1; failed = failed + report(q7.passed,  q7.name);
  let q8  = test_probe_quant();           total = total + 1; failed = failed + report(q8.passed,  q8.name);
  let q9  = test_probe_sphere_bounds();   total = total + 1; failed = failed + report(q9.passed,  q9.name);
  let q10 = test_probe_meshlet();         total = total + 1; failed = failed + report(q10.passed, q10.name);
  let q11 = test_probe_oct_filter();      total = total + 1; failed = failed + report(q11.passed, q11.name);

  io.println("");
  io.println("-- SECTION 3: XIOM-owned buffer direction (2) --");

  let b0 = test_owned_buffer_roundtrip(); total = total + 1; failed = failed + report(b0.passed, b0.name);
  let b1 = test_owned_buffer_readback();  total = total + 1; failed = failed + report(b1.passed, b1.name);

  io.println("");
  io.println("-- SECTION 4: owned-buffer wrappers (3) --");

  let w0 = test_wrapper_remap();     total = total + 1; failed = failed + report(w0.passed, w0.name);
  let w1 = test_wrapper_optimize();  total = total + 1; failed = failed + report(w1.passed, w1.name);
  let w2 = test_wrapper_simplify();  total = total + 1; failed = failed + report(w2.passed, w2.name);

  io.println("");
  io.println("-- SECTION 5: codec family (5) --");

  let c0 = test_codec_index_sequence();  total = total + 1; failed = failed + report(c0.passed, c0.name);
  let c1 = test_codec_filter_quat();     total = total + 1; failed = failed + report(c1.passed, c1.name);
  let c2 = test_codec_filter_exp();      total = total + 1; failed = failed + report(c2.passed, c2.name);
  let c3 = test_codec_filter_color();    total = total + 1; failed = failed + report(c3.passed, c3.name);
  let c4 = test_codec_meshlet();         total = total + 1; failed = failed + report(c4.passed, c4.name);

  io.println("");
  io.println("==============================================");
  if failed == 0 {
    io.println("  ALL " + int_to_str(total) + " TESTS PASSED");
    io.println("  Vendored: meshoptimizer v1.2 (commit f843aae0)");
    return 0;
  }
  io.println("  TESTS:  " + int_to_str(total));
  io.println("  FAILED: " + int_to_str(failed));
  return 1;
}
