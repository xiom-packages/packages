// xiom.spz conformance suite.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the binding against the vendored spz v3.0.0 (5bf2945d, MIT) compiled
// into the test binary via port.args.json:
//   scripts/port.ps1 -Package xiom.spz -TimeoutSec 900
//
// Coverage (docs/COVERAGE.md):
//   * constants/CoordinateSystem evidence against the compiled bridge;
//   * v4 (zstd/NGSP) pack -> metadata -> unpack round trip with per-field
//     tolerances (quantization is lossy by design; tolerances documented in
//     SPEC.md section 4);
//   * v3 (gzip/smallest-three) and v2 (gzip/first-three) legacy paths;
//   * serialize + gzip == the v3 container byte-for-byte;
//   * packed accessors (at/unpack) against the quantizer's documented bytes;
//   * typed corrupt-input errors (magic/version/header/truncated/decompress);
//   * file save/load (spz + PLY) and nonexistent-path classification;
//   * GaussianCloud methods (data/convertCoordinates/rotate180/medianVolume);
//   * the public math surface (half/norm/quat/vector helpers).

module spz_conformance

use xiom.io;
use xiom.os;
use xiom.convert;
use xiom.spz;
use xiom.spz.math;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn abs_f32(x: Float32) -> Float32 {
  if x < 0.0 { return 0.0 - x; }
  return x;
}

fn close_enough(a: Float32, b: Float32, tol: Float32) -> Bool {
  return abs_f32(a - b) <= tol;
}

fn max_abs_diff(a: &Vec[Float32], b: &Vec[Float32], off_a: Int, off_b: Int, count: Int) -> Float32 {
  var m: Float32 = 0.0;
  var i: Int = 0;
  while i < count {
    let d = abs_f32(a[off_a + i] - b[off_b + i]);
    if d > m { m = d; }
    i = i + 1;
  }
  return m;
}

fn dup_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn take_bytes(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < v.len() && i < n {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn dup_floats(v: &Vec[Float32]) -> Vec[Float32] {
  var out: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if (a[i] as Int) != (b[i] as Int) { return false; }
    i = i + 1;
  }
  return true;
}

fn floats_equal(a: &Vec[Float32], b: &Vec[Float32]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn push_u32_le(b: &mut Vec[UInt8], v: Int) {
  var x = v;
  var k: Int = 0;
  while k < 4 {
    b.push((x % 256) as UInt8);
    x = x / 256;
    k = k + 1;
  }
}

// A 6-point, SH degree 2 fixture.  Positions are exact 12-bit fixed-point
// multiples; scales are exact 1/16 log-space multiples; rotations are
// normalized quaternions (so every round-trip tolerance in SPEC.md section 4
// is dominated by the format's own quantization, not by the fixture).
fn build_fixture() -> Vec[Float32] {
  var w: Vec[Float32] = Vec[Float32].new();
  // positions: 18
  w.push(0.5); w.push(-0.25); w.push(0.125);
  w.push(-0.0625); w.push(0.0078125); w.push(-0.001953125);
  w.push(1.0); w.push(-1.0); w.push(0.0);
  w.push(0.0); w.push(0.5); w.push(-0.5);
  w.push(-0.75); w.push(0.25); w.push(0.375);
  w.push(0.03125); w.push(-0.015625); w.push(0.001953125);
  // scales (log space): 18
  w.push(-9.9375); w.push(-9.875); w.push(-9.9375);
  w.push(-10.0); w.push(-9.8125); w.push(-9.875);
  w.push(-10.0); w.push(-9.9375); w.push(-9.875);
  w.push(-9.8125); w.push(-10.0); w.push(-9.9375);
  w.push(-9.875); w.push(-9.8125); w.push(-10.0);
  w.push(-9.9375); w.push(-9.875); w.push(-9.8125);
  // rotations xyzw: 24
  w.push(0.0); w.push(0.0); w.push(0.0); w.push(1.0);
  w.push(0.6); w.push(0.0); w.push(0.0); w.push(0.8);
  w.push(0.0); w.push(0.8); w.push(0.6); w.push(0.0);
  w.push(0.5); w.push(0.5); w.push(0.5); w.push(0.5);
  w.push(0.0); w.push(0.0); w.push(1.0); w.push(0.0);
  w.push(0.0); w.push(0.6); w.push(0.0); w.push(0.8);
  // alphas: 6
  w.push(-2.0); w.push(-1.0); w.push(0.0); w.push(1.0); w.push(2.0); w.push(0.5);
  // colors: 18
  w.push(0.5); w.push(0.0); w.push(1.0);
  w.push(0.25); w.push(0.75); w.push(-0.1);
  w.push(0.1); w.push(0.2); w.push(0.3);
  w.push(0.9); w.push(0.4); w.push(0.6);
  w.push(0.0); w.push(0.5); w.push(1.0);
  w.push(0.33); w.push(0.66); w.push(0.99);
  // sh: 144, value pattern ((k % 17) - 8) * 0.05 in [-0.4, 0.4]
  var k: Int = 0;
  while k < 144 {
    let iv: Float32 = ((k % 17) - 8) as Float32;
    w.push(iv * 0.05);
    k = k + 1;
  }
  return w;
}

fn build_single_point() -> Vec[Float32] {
  var w: Vec[Float32] = Vec[Float32].new();
  // positions (0,0,0), scales log(0.5) x3, rotation identity, alpha 0, colors 0
  w.push(0.0); w.push(0.0); w.push(0.0);
  w.push(-0.6931472); w.push(-0.6931472); w.push(-0.6931472);
  w.push(0.0); w.push(0.0); w.push(0.0); w.push(1.0);
  w.push(0.0);
  w.push(0.0); w.push(0.0); w.push(0.0);
  return w;
}

fn main() -> Int {
  io.println("=== xiom.spz conformance tests (vendored spz v3.0.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // --- constants / CoordinateSystem evidence --------------------------------
  failed = failed + report(spz_constants_match(),
    "constants: bridge constants match the module constants");
  failed = failed + report(spz_coordinate_values_match(),
    "CoordinateSystem: 9 values are 0..8 in order");
  failed = failed + report(!spz_has_extension_support(),
    "extension support: off in the pinned build");
  failed = failed + report(spz_dim_for_degree(0) == 0 && spz_dim_for_degree(1) == 3
    && spz_dim_for_degree(2) == 8 && spz_dim_for_degree(3) == 15
    && spz_dim_for_degree(4) == 24 && spz_dim_for_degree(5) == -1,
    "dimForDegree: 0/3/8/15/24 and -1 for invalid");
  failed = failed + report(spz_work_size(6, 2) == 228 && spz_work_size(1, 0) == 14,
    "work size: 6 points @ degree 2 = 228 floats; 1 @ 0 = 14");
  failed = failed + report(spz_work_offset(SPZ_STREAM_POSITIONS, 6, 2) == 0
    && spz_work_offset(SPZ_STREAM_SCALES, 6, 2) == 18
    && spz_work_offset(SPZ_STREAM_ROTATIONS, 6, 2) == 36
    && spz_work_offset(SPZ_STREAM_ALPHAS, 6, 2) == 60
    && spz_work_offset(SPZ_STREAM_COLORS, 6, 2) == 66
    && spz_work_offset(SPZ_STREAM_SH, 6, 2) == 84,
    "work offsets: 0/18/36/60/66/84 for 6 points @ degree 2");

  let ax = spz_axes_match(SPZ_COORD_RDF, SPZ_COORD_RUB);
  failed = failed + report(ax.x && !ax.y && !ax.z,
    "axesMatch(RDF, RUB) = {x:true, y:false, z:false}");
  let au = spz_axes_match(SPZ_COORD_UNSPECIFIED, SPZ_COORD_RUB);
  failed = failed + report(au.x && au.y && au.z,
    "axesMatch(UNSPECIFIED, RUB) = all true (no conversion)");

  let cc = spz_coordinate_converter(SPZ_COORD_RDF, SPZ_COORD_RUB);
  if !cc.is_ok {
    failed = failed + report(false, "coordinateConverter(RDF, RUB) failed -- " + cc.error.message);
  } else {
    var flips = cc.value;
    failed = failed + report(flips[0] == 1.0 && flips[1] == -1.0 && flips[2] == -1.0,
      "coordinateConverter(RDF, RUB): flipP = {1, -1, -1}");
  }

  // --- v4 (zstd/NGSP) pack -> meta -> unpack --------------------------------
  var fixture = build_fixture();
  let packed4 = spz_pack(&mut fixture, 6, 2, false, SPZ_LATEST_HEADER_VERSION,
    SPZ_COORD_UNSPECIFIED, SPZ_DEFAULT_SH1_BITS, SPZ_DEFAULT_SH_REST_BITS);
  if !packed4.is_ok {
    failed = failed + report(false, "pack v4 failed -- " + packed4.error.message);
    failed = failed + report(false, "v4 suite aborted");
    io.println("xiom.spz: tests failed");
    return failed;
  }
  var v4: Vec[UInt8] = packed4.value.bytes;
  failed = failed + report(v4.len() > 32 && (v4[0] as Int) == 78 && (v4[1] as Int) == 71 && (v4[2] as Int) == 83 && (v4[3] as Int) == 80,
    "pack v4: NGSP magic bytes");

  let meta4 = spz_load_packed(&mut v4);
  if !meta4.is_ok {
    failed = failed + report(false, "load_packed(v4) failed -- " + meta4.error.message);
  } else {
    let m4 = meta4.value;
    failed = failed + report(m4.version == 4, "v4 metadata: version = 4");
    failed = failed + report(m4.num_points == 6 && m4.sh_degree == 2,
      "v4 metadata: numPoints = 6, shDegree = 2");
    failed = failed + report(m4.fractional_bits == 12, "v4 metadata: fractionalBits = 12");
    failed = failed + report(!m4.antialiased && m4.uses_smallest_three && !m4.uses_float16,
      "v4 metadata: antialiased=false, smallestThree=true, float16=false");

    let un4 = spz_unpack(&mut v4, SPZ_COORD_UNSPECIFIED);
    if !un4.is_ok {
      failed = failed + report(false, "unpack(v4) failed -- " + un4.error.message);
    } else {
      var c4 = un4.value;
      failed = failed + report(c4.num_points == 6 && c4.sh_degree == 2 && !c4.antialiased,
        "v4 unpack: counts and flags match");
      let pos_d = max_abs_diff(&c4.work, &fixture, 0, 0, 18);
      failed = failed + report(pos_d <= 0.0005,
        "v4 round trip: positions within 5e-4 (" + to_string((pos_d * 1000000.0) as Int) + "e-6)");
      let sc_d = max_abs_diff(&c4.work, &fixture, 18, 18, 18);
      failed = failed + report(sc_d <= 0.04,
        "v4 round trip: scales within 4e-2 (" + to_string((sc_d * 1000000.0) as Int) + "e-6)");
      let rot_d = max_abs_diff(&c4.work, &fixture, 36, 36, 24);
      failed = failed + report(rot_d <= 0.012,
        "v4 round trip: rotations within 1.2e-2 (" + to_string((rot_d * 1000000.0) as Int) + "e-6)");
      let al_d = max_abs_diff(&c4.work, &fixture, 60, 60, 6);
      failed = failed + report(al_d <= 0.05,
        "v4 round trip: alphas within 5e-2 (" + to_string((al_d * 1000000.0) as Int) + "e-6)");
      let col_d = max_abs_diff(&c4.work, &fixture, 66, 66, 18);
      failed = failed + report(col_d <= 0.02,
        "v4 round trip: colors within 2e-2 (" + to_string((col_d * 1000000.0) as Int) + "e-6)");
      // SH: degree-1 coefficients (first 9 of each 24-float block) use the
      // sh1Bits bucket; the rest use shRestBits.
      var sh1_d: Float32 = 0.0;
      var shrest_d: Float32 = 0.0;
      var p: Int = 0;
      while p < 6 {
        let d1 = max_abs_diff(&c4.work, &fixture, 84 + p * 24, 84 + p * 24, 9);
        if d1 > sh1_d { sh1_d = d1; }
        let d2 = max_abs_diff(&c4.work, &fixture, 84 + p * 24 + 9, 84 + p * 24 + 9, 15);
        if d2 > shrest_d { shrest_d = d2; }
        p = p + 1;
      }
      failed = failed + report(sh1_d <= 0.032,
        "v4 round trip: SH degree-1 subset within 3.2e-2 (half of bucket 8/128) ("
        + to_string((sh1_d * 1000000.0) as Int) + "e-6)");
      failed = failed + report(shrest_d <= 0.063,
        "v4 round trip: SH rest subset within 6.3e-2 (half of bucket 16/128) ("
        + to_string((shrest_d * 1000000.0) as Int) + "e-6)");

      // --- packed accessors against the documented quantizer bytes ---------
      let g0 = spz_packed_gaussian(&mut v4, 0);
      if !g0.is_ok {
        failed = failed + report(false, "packed_gaussian(0) failed -- " + g0.error.message);
      } else {
        var g = g0.value;
        failed = failed + report(spz_packed_byte(&g, 0) == 0x00 && spz_packed_byte(&g, 1) == 0x08
          && spz_packed_byte(&g, 2) == 0x00
          && spz_packed_byte(&g, 3) == 0x00 && spz_packed_byte(&g, 4) == 0xfc
          && spz_packed_byte(&g, 5) == 0xff
          && spz_packed_byte(&g, 6) == 0x00 && spz_packed_byte(&g, 7) == 0x02
          && spz_packed_byte(&g, 8) == 0x00,
          "packed_gaussian(0): 24-bit fixed point position bytes (0.5, -0.25, 0.125)");
        failed = failed + report(g.raw.len() == SPZ_PACKED_GAUSSIAN_BYTES,
          "packed_gaussian(0): raw record is 92 bytes");
        failed = failed + report(spz_packed_byte(&g, SPZ_PACKED_OFF_ALPHA) == 30,
          "packed_gaussian(0): alpha byte = round(sigmoid(-2) * 255) = 30");
        failed = failed + report(spz_packed_byte(&g, SPZ_PACKED_OFF_SCALE) == 1,
          "packed_gaussian(0): scale byte = (-9.9375 + 10) * 16 = 1");
        failed = failed + report(spz_packed_byte(&g, SPZ_PACKED_OFF_COLOR) == 147,
          "packed_gaussian(0): color byte = round(0.5 * 0.15 * 255 + 127.5) = 147");
      }

      let u0 = spz_packed_gaussian_unpack(&mut v4, 0, SPZ_COORD_UNSPECIFIED);
      if !u0.is_ok {
        failed = failed + report(false, "packed_gaussian_unpack(0) failed -- " + u0.error.message);
      } else {
        var u = u0.value;
        failed = failed + report(u.fields.len() == SPZ_UNPACKED_FLOATS,
          "packed_gaussian_unpack(0): 86 floats");
        var pd: Float32 = 0.0;
        var i: Int = 0;
        while i < 3 {
          let d = abs_f32(spz_unpacked_field(&u, SPZ_UNPACKED_OFF_POSITION + i) - c4.work[i]);
          if d > pd { pd = d; }
          i = i + 1;
        }
        failed = failed + report(pd <= 0.000001,
          "packed_gaussian_unpack(0): position equals the cloud unpack (exact)");
        failed = failed + report(spz_unpacked_field(&u, SPZ_UNPACKED_OFF_ALPHA)
          == c4.work[60],
          "packed_gaussian_unpack(0): alpha equals the cloud unpack (exact)");
        failed = failed + report(spz_unpacked_field(&u, SPZ_UNPACKED_OFF_SHR)
          == c4.work[84],
          "packed_gaussian_unpack(0): shR[0] equals the cloud unpack (exact)");
      }

      let gx = spz_packed_gaussian(&mut v4, 6);
      failed = failed + report(!gx.is_ok && gx.error.code == SPZ_ERR_BAD_ARGS,
        "packed_gaussian(6): out-of-range index -> SPZ_ERR_BAD_ARGS");
    }
  }

  // --- antialiased flag -----------------------------------------------------
  var fixture_a = dup_floats(&fixture);
  let packed_a = spz_pack(&mut fixture_a, 6, 2, true, 4, SPZ_COORD_UNSPECIFIED, 5, 4);
  if !packed_a.is_ok {
    failed = failed + report(false, "pack antialiased failed -- " + packed_a.error.message);
  } else {
    var va: Vec[UInt8] = packed_a.value.bytes;
    let ma = spz_load_packed(&mut va);
    var aok = false;
    if ma.is_ok { aok = ma.value.antialiased; }
    let ua = spz_unpack(&mut va, SPZ_COORD_UNSPECIFIED);
    var b_ok = false;
    if ua.is_ok { b_ok = ua.value.antialiased; }
    failed = failed + report(aok && b_ok, "antialiased flag survives pack -> meta -> unpack");
  }

  // --- legacy v3 (gzip + smallest-three) ------------------------------------
  var fixture3 = dup_floats(&fixture);
  let packed3 = spz_pack(&mut fixture3, 6, 2, false, 3, SPZ_COORD_UNSPECIFIED, 5, 4);
  var v3: Vec[UInt8] = Vec[UInt8].new();
  if !packed3.is_ok {
    failed = failed + report(false, "pack v3 failed -- " + packed3.error.message);
  } else {
    v3 = packed3.value.bytes;
    failed = failed + report(v3.len() > 2 && (v3[0] as Int) == 0x1f && (v3[1] as Int) == 0x8b,
      "pack v3: gzip magic (1f 8b)");
    let m3 = spz_load_packed(&mut v3);
    var m3ok = false;
    var m3v = 0;
    var m3s = false;
    if m3.is_ok {
      m3ok = true;
      m3v = m3.value.version;
      m3s = m3.value.uses_smallest_three;
    }
    failed = failed + report(m3ok && m3v == 3 && m3s,
      "v3 metadata: version = 3, usesQuaternionSmallestThree = true");
    let un3 = spz_unpack(&mut v3, SPZ_COORD_UNSPECIFIED);
    if !un3.is_ok {
      failed = failed + report(false, "unpack(v3) failed -- " + un3.error.message);
    } else {
      var c3 = un3.value;
      let d3 = max_abs_diff(&c3.work, &fixture, 0, 0, 18);
      failed = failed + report(c3.num_points == 6 && d3 <= 0.0005,
        "v3 round trip: 6 points, positions within 5e-4");
    }

    // serialize + gzip must reproduce the v3 container byte-for-byte.
    let ser = spz_serialize_packed(&mut v3);
    if !ser.is_ok {
      failed = failed + report(false, "serialize(v3) failed -- " + ser.error.message);
    } else {
      var ser_b: Vec[UInt8] = ser.value.bytes;
      failed = failed + report(ser_b.len() > 16 && (ser_b[0] as Int) == 78 && (ser_b[1] as Int) == 71,
        "serialize(v3): legacy header carries the NGSP magic");
      let gz = spz_compress_gzipped(&mut ser_b);
      if !gz.is_ok {
        failed = failed + report(false, "compress_gzipped failed -- " + gz.error.message);
      } else {
        var gz_b: Vec[UInt8] = gz.value.bytes;
        failed = failed + report(bytes_equal(&gz_b, &v3),
          "serialize + compressGzipped == the v3 container (byte-exact)");
      }
    }
  }

  // --- legacy v2 (gzip + first-three quaternions) ---------------------------
  var fixture2 = dup_floats(&fixture);
  let packed2 = spz_pack(&mut fixture2, 6, 2, false, 2, SPZ_COORD_UNSPECIFIED, 5, 4);
  if !packed2.is_ok {
    failed = failed + report(false, "pack v2 failed -- " + packed2.error.message);
  } else {
    var v2: Vec[UInt8] = packed2.value.bytes;
    let m2 = spz_load_packed(&mut v2);
    var m2ok = false;
    var m2s = true;
    if m2.is_ok {
      m2ok = m2.value.version == 2;
      m2s = m2.value.uses_smallest_three;
    }
    failed = failed + report(m2ok && !m2s,
      "v2 metadata: version = 2, usesQuaternionSmallestThree = false");
    let un2 = spz_unpack(&mut v2, SPZ_COORD_UNSPECIFIED);
    if !un2.is_ok {
      failed = failed + report(false, "unpack(v2) failed -- " + un2.error.message);
    } else {
      var c2 = un2.value;
      let r2 = max_abs_diff(&c2.work, &fixture, 36, 36, 24);
      failed = failed + report(r2 <= 0.015,
        "v2 round trip: rotations within 1.5e-2 (" + to_string((r2 * 1000000.0) as Int) + "e-6)");
    }
  }

  // --- typed corrupt-input errors -------------------------------------------
  var one_byte: Vec[UInt8] = Vec[UInt8].new();
  one_byte.push(0x4e);
  let e1 = spz_load_packed(&mut one_byte);
  failed = failed + report(!e1.is_ok && e1.error.code == SPZ_ERR_TRUNCATED,
    "corrupt: 1 byte -> SPZ_ERR_TRUNCATED");

  var garbage: Vec[UInt8] = Vec[UInt8].new();
  garbage.push(0xaa); garbage.push(0xaa); garbage.push(0xaa); garbage.push(0xaa);
  let e2 = spz_load_packed(&mut garbage);
  failed = failed + report(!e2.is_ok && e2.error.code == SPZ_ERR_MAGIC,
    "corrupt: unknown 4-byte magic -> SPZ_ERR_MAGIC");

  var bad_ver: Vec[UInt8] = Vec[UInt8].new();
  bad_ver.push(78); bad_ver.push(71); bad_ver.push(83); bad_ver.push(80);
  push_u32_le(&mut bad_ver, 5);
  push_u32_le(&mut bad_ver, 6);
  var pad: Int = 0;
  while pad < 20 { bad_ver.push(0); pad = pad + 1; }
  let e3 = spz_load_packed(&mut bad_ver);
  failed = failed + report(!e3.is_ok && e3.error.code == SPZ_ERR_VERSION,
    "corrupt: NGSP version 5 -> SPZ_ERR_VERSION");

  var zero_pts: Vec[UInt8] = Vec[UInt8].new();
  zero_pts.push(78); zero_pts.push(71); zero_pts.push(83); zero_pts.push(80);
  push_u32_le(&mut zero_pts, 4);
  push_u32_le(&mut zero_pts, 0);
  var pad2: Int = 0;
  while pad2 < 20 { zero_pts.push(0); pad2 = pad2 + 1; }
  let e4 = spz_load_packed(&mut zero_pts);
  failed = failed + report(!e4.is_ok && e4.error.code == SPZ_ERR_BAD_HEADER,
    "corrupt: numPoints = 0 -> SPZ_ERR_BAD_HEADER");

  var huge_pts: Vec[UInt8] = Vec[UInt8].new();
  huge_pts.push(78); huge_pts.push(71); huge_pts.push(83); huge_pts.push(80);
  push_u32_le(&mut huge_pts, 4);
  push_u32_le(&mut huge_pts, 2147483647);
  huge_pts.push(2); huge_pts.push(12); huge_pts.push(0); huge_pts.push(6);
  push_u32_le(&mut huge_pts, 32);
  var pad3: Int = 0;
  while pad3 < 12 { huge_pts.push(0); pad3 = pad3 + 1; }
  let e5 = spz_load_packed(&mut huge_pts);
  failed = failed + report(!e5.is_ok && e5.error.code == SPZ_ERR_BAD_HEADER,
    "corrupt: numPoints = 0x7FFFFFFF -> SPZ_ERR_BAD_HEADER (no allocation attempt)");

  var trunc4 = take_bytes(&v4, 64);
  let e6 = spz_load_packed(&mut trunc4);
  failed = failed + report(!e6.is_ok && e6.error.code == SPZ_ERR_TRUNCATED,
    "corrupt: v4 truncated to 64 bytes -> SPZ_ERR_TRUNCATED");

  var toc_bad = dup_bytes(&v4);
  // TOC entry 0 compressedSize (offset 32..40): 0xFF.. breaks the
  // compressed-offset == file-size check.
  toc_bad[32] = 0xff; toc_bad[33] = 0xff; toc_bad[34] = 0xff; toc_bad[35] = 0xff;
  toc_bad[36] = 0xff; toc_bad[37] = 0xff; toc_bad[38] = 0xff; toc_bad[39] = 0xff;
  let e7 = spz_load_packed(&mut toc_bad);
  failed = failed + report(!e7.is_ok && e7.error.code == SPZ_ERR_DECOMPRESS,
    "corrupt: tampered TOC stream size -> SPZ_ERR_DECOMPRESS");

  // A gzip-body bit flip must fail the inflate/CRC path.
  var gz_bad = dup_bytes(&v3);
  let flip_at = gz_bad.len() / 2;
  gz_bad[flip_at] = (gz_bad[flip_at] as Int ^ 0xff) as UInt8;
  let e8 = spz_load_packed(&mut gz_bad);
  failed = failed + report(!e8.is_ok && e8.error.code == SPZ_ERR_DECOMPRESS,
    "corrupt: flipped gzip body byte -> SPZ_ERR_DECOMPRESS");

  var gz_trunc = take_bytes(&v3, v3.len() / 2);
  let e9 = spz_load_packed(&mut gz_trunc);
  failed = failed + report(!e9.is_ok && e9.error.code == SPZ_ERR_DECOMPRESS,
    "corrupt: truncated gzip container -> SPZ_ERR_DECOMPRESS");

  // --- file round trips -----------------------------------------------------
  let tmp_dir = os.temp_dir();
  let spz_path = io.join_paths(tmp_dir, "xiom_spz_conformance_v4.spz");
  var fixture_f = dup_floats(&fixture);
  let sf = spz_save_file(spz_path, &mut fixture_f, 6, 2, false, 4, SPZ_COORD_UNSPECIFIED, 5, 4);
  if !sf.is_ok {
    failed = failed + report(false, "save_file failed -- " + sf.error.message);
  } else {
    let lf = spz_load_file(spz_path, SPZ_COORD_UNSPECIFIED);
    if !lf.is_ok {
      failed = failed + report(false, "load_file failed -- " + lf.error.message);
    } else {
      var cf = lf.value;
      let df = max_abs_diff(&cf.work, &fixture, 0, 0, 18);
      failed = failed + report(cf.num_points == 6 && df <= 0.0005,
        "file round trip: save_file -> load_file -> 6 points, positions within 5e-4");
    }
    var ig1 = io.remove_file(spz_path);
  }

  let missing_path = io.join_paths(tmp_dir, "xiom_spz_no_such_file.spz");
  let lm = spz_load_file(missing_path, SPZ_COORD_UNSPECIFIED);
  failed = failed + report(!lm.is_ok && lm.error.code == SPZ_ERR_DECOMPRESS,
    "file: nonexistent path -> SPZ_ERR_DECOMPRESS");

  let ply_path = io.join_paths(tmp_dir, "xiom_spz_conformance.ply");
  var fixture_p = dup_floats(&fixture);
  let sp = spz_save_ply(ply_path, &mut fixture_p, 6, 2, false, 4, SPZ_COORD_UNSPECIFIED, 5, 4);
  if !sp.is_ok {
    failed = failed + report(false, "save_ply failed -- " + sp.error.message);
  } else {
    let lp = spz_load_ply(ply_path, SPZ_COORD_UNSPECIFIED);
    if !lp.is_ok {
      failed = failed + report(false, "load_ply failed -- " + lp.error.message);
    } else {
      var cp = lp.value;
      let dp = max_abs_diff(&cp.work, &fixture, 0, 0, 18);
      failed = failed + report(cp.num_points == 6 && dp <= 0.00001,
        "PLY round trip: save_ply -> load_ply -> positions exact (binary_little_endian)");
    }
    var ig2 = io.remove_file(ply_path);
  }

  // --- GaussianCloud methods ------------------------------------------------
  var fixture_d = dup_floats(&fixture);
  let data_r = spz_cloud_data(&mut fixture_d, 6, 2, false);
  if !data_r.is_ok {
    failed = failed + report(false, "cloud_data failed -- " + data_r.error.message);
  } else {
    var cd = data_r.value;
    failed = failed + report(cd.num_points == 6 && cd.work.len() == 228
      && floats_equal(&cd.work, &fixture),
      "cloud_data(): full stream copy is byte-exact (228 floats)");
  }

  var fixture_c = dup_floats(&fixture);
  let conv1 = spz_cloud_convert(&mut fixture_c, 6, 2, SPZ_COORD_RDF, SPZ_COORD_RUB);
  let conv2 = spz_cloud_convert(&mut fixture_c, 6, 2, SPZ_COORD_RUB, SPZ_COORD_RDF);
  var conv_ok = false;
  if conv1.is_ok && conv2.is_ok {
    let dc = max_abs_diff(&fixture_c, &fixture, 0, 0, 18);
    conv_ok = dc <= 0.000001;
  }
  failed = failed + report(conv_ok,
    "convertCoordinates: RDF -> RUB -> RDF restores positions");

  var fixture_r = dup_floats(&fixture);
  let rot1 = spz_cloud_rotate180(&mut fixture_r, 6, 2);
  let rot2 = spz_cloud_rotate180(&mut fixture_r, 6, 2);
  var rot_ok = false;
  if rot1.is_ok && rot2.is_ok {
    let dr = max_abs_diff(&fixture_r, &fixture, 0, 0, 18);
    rot_ok = dr <= 0.000001;
  }
  failed = failed + report(rot_ok, "rotate180DegAboutX: twice = identity");

  var single = build_single_point();
  let med = spz_median_volume(&mut single, 1, 0);
  failed = failed + report(close_enough(med, 0.5235988, 0.0001),
    "medianVolume: log(0.5) single point -> 4/3*pi*0.125 = 0.5235988");

  // --- math surface ---------------------------------------------------------
  failed = failed + report(spz_float_to_half(1.0) == 0x3c00 && spz_half_to_float(0x3c00) == 1.0,
    "math: 1.0 <-> half 0x3C00 round trip");
  failed = failed + report(spz_float_to_half(-2.0) == 0xc000 && spz_half_to_float(0xc000) == -2.0,
    "math: -2.0 <-> half 0xC000 round trip");
  failed = failed + report(spz_norm3(3.0, 4.0, 0.0) == 5.0,
    "math: norm3(3, 4, 0) = 5");
  failed = failed + report(spz_norm4(0.0, 0.0, 0.0, 1.0) == 1.0,
    "math: norm4(0, 0, 0, 1) = 1 (w-first quat)");
  let n3 = spz_normalized3(0.0, 0.0, 2.0);
  failed = failed + report(n3[0] == 0.0 && n3[1] == 0.0 && n3[2] == 1.0,
    "math: normalized3(0, 0, 2) = (0, 0, 1)");
  failed = failed + report(spz_dot3(1.0, 2.0, 3.0, 4.0, 5.0, 6.0) == 32.0,
    "math: dot3((1,2,3),(4,5,6)) = 32");
  failed = failed + report(spz_squared_norm3(1.0, 2.0, 3.0) == 14.0,
    "math: squaredNorm3(1, 2, 3) = 14");
  let tq = spz_times_qv(1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 3.0);
  failed = failed + report(tq[0] == 1.0 && tq[1] == 2.0 && tq[2] == 3.0,
    "math: identity quat * v = v");
  let tqq = spz_times_qq(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0);
  failed = failed + report(close_enough(tqq[0], 0.0, 0.000001) && close_enough(tqq[1], 1.0, 0.000001),
    "math: identity quat * quat = quat");
  let tqs = spz_times_qs(1.0, 2.0, 3.0, 4.0, 2.0);
  failed = failed + report(tqs[0] == 2.0 && tqs[3] == 8.0, "math: quat * scalar");
  let pqq = spz_plus_qq(1.0, 2.0, 3.0, 4.0, 10.0, 20.0, 30.0, 40.0);
  failed = failed + report(pqq[0] == 11.0 && pqq[3] == 44.0, "math: quat + quat");
  let tvs = spz_times_vs(1.0, 2.0, 3.0, 3.0);
  failed = failed + report(tvs[0] == 3.0 && tvs[2] == 9.0, "math: vec * scalar");
  let pvv = spz_plus_vv(1.0, 2.0, 3.0, 10.0, 20.0, 30.0);
  failed = failed + report(pvv[0] == 11.0 && pvv[2] == 33.0, "math: vec + vec");
  let tvv = spz_times_vv(2.0, 3.0, 4.0, 5.0, 6.0, 7.0);
  failed = failed + report(tvv[0] == 10.0 && tvv[2] == 28.0, "math: vec * vec");
  let aaq = spz_axis_angle_quat(0.0, 0.0, 0.0);
  failed = failed + report(close_enough(aaq[0], 1.0, 0.000001) && close_enough(aaq[1], 0.0, 0.000001),
    "math: axisAngleQuat(0, 0, 0) = identity (w = 1)");
  let v3f = spz_vec3f(7.0, 8.0, 9.0);
  failed = failed + report(v3f[0] == 7.0 && v3f[1] == 8.0 && v3f[2] == 9.0,
    "math: vec3f passthrough");
  let q4f = spz_quat4f(1.0, 2.0, 3.0, 4.0);
  failed = failed + report(q4f[0] == 1.0 && q4f[3] == 4.0, "math: quat4f passthrough");
  var csrc: Vec[Float32] = Vec[Float32].new();
  csrc.push(1.25); csrc.push(-2.5); csrc.push(0.0);
  var cdst: Vec[Float32] = Vec[Float32].new();
  cdst.push(0.0); cdst.push(0.0); cdst.push(0.0);
  let cfb = spz_copy_float_buffer(&mut csrc, &mut cdst);
  failed = failed + report(cfb == 0 && cdst[0] == 1.25 && cdst[1] == -2.5 && cdst[2] == 0.0,
    "math: copyFloatBuffer copies count + payload");

  if failed == 0 {
    io.println("xiom.spz: all tests passed");
  } else {
    io.println("xiom.spz: tests failed");
  }
  return failed;
}
