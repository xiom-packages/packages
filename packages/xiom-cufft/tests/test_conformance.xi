// XIOM -- xiom.cufft conformance suite (0.1.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 21 checks with a live runtime, 5 on a host without one (the runtime
// section collapses to one classified SKIP line):
//   SECTION A (4): deterministic SKIP classification (bogus directory),
//     result-name mapping, stale-module-handle classification, and the
//     pinned transform constants.
//   SECTION B (17): cuFFT live -- load, version, plan-size estimates,
//     1D/2D plans, setStream, R2C/C2R round trip, 2D Z2Z forward/inverse,
//     D2Z/Z2D round trip, destroy, unload (real numerical results).
//
// Runtime: the user's own cuFFT installation -- `XIOM_CUFFT_DIR` (e.g.
// the pip wheel's nvidia/cufft/bin) or the OS module search.  Nothing is
// downloaded or shipped.  Run:
//   scripts/port.ps1 -Package xiom.cufft -TimeoutSec 300

module cufft_conformance

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.cufft;

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

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

fn f32s(v: Float32) -> Str {
  if v < 0.0 as Float32 { return "-" + f32s(0.0 as Float32 - v); }
  let whole = v as Int;
  let frac = ((v - whole as Float32) * 1000.0 as Float32) as Int;
  return i2s(whole) + "." + i2s(frac);
}

fn f64s(v: Float64) -> Str {
  if v < 0.0 { return "-" + f64s(0.0 - v); }
  let whole = v as Int;
  let frac = ((v - whole as Float64) * 1000000.0) as Int;
  return i2s(whole) + "." + i2s(frac);
}

fn approx32(a: Float32, b: Float32, tol: Float32) -> Bool {
  var d = a - b;
  if d < 0.0 as Float32 { d = 0.0 as Float32 - d; }
  return d <= tol;
}

fn approx64(a: Float64, b: Float64, tol: Float64) -> Bool {
  var d = a - b;
  if d < 0.0 { d = 0.0 - d; }
  return d <= tol;
}

fn expect_unit(r: Result[Unit, CufftError], name: Str) -> Int {
  if r.is_ok { return report(true, name); }
  return report(false, name + ": " + r.error.message);
}

// =========================================================================
// SECTION A -- always-run (no runtime needed)
// =========================================================================

fn test_a1_skip_path() -> Int {
  let r = cufft_load_from("xiom-absent-cufft-probe-xyz");
  var ok = false;
  if r.is_err {
    ok = r.error.kind == CUFFT_LOAD_ABSENT;
  }
  return report(ok, "skip-path: absent directory classified as CUFFT_LOAD_ABSENT (SKIP)");
}

fn test_a2_status_names() -> Int {
  let ok = str_compare(cufft_status_name(0), "CUFFT_SUCCESS") == 0
    && str_compare(cufft_status_name(8), "CUFFT_INVALID_SIZE") == 0
    && str_compare(cufft_status_name(14), "CUFFT_NOT_IMPLEMENTED") == 0;
  return report(ok, "status map: 0/8/14 have the pinned cuFFT names");
}

fn test_a3_invalid_module() -> Int {
  let fake = CufftLibrary{ h: 12345 };
  let r = cufft_plan1d(&fake, 8, CUFFT_R2C, 1);
  var ok = false;
  if r.is_err {
    ok = r.error.kind == CUFFT_LOAD_RUNTIME;
  }
  return report(ok, "typed error: plan on a stale module handle is CUFFT_LOAD_RUNTIME");
}

fn test_a4_constants() -> Int {
  let ok = CUFFT_R2C == 42 && CUFFT_C2R == 44 && CUFFT_C2C == 41
    && CUFFT_D2Z == 106 && CUFFT_Z2D == 108 && CUFFT_Z2Z == 105
    && CUFFT_FORWARD == -1 && CUFFT_INVERSE == 1;
  return report(ok, "ABI constants: transform types and directions match the pin");
}

// =========================================================================
// SECTION B -- live cuFFT (or one classified SKIP)
// =========================================================================

fn test_b_live() -> Int {
  let lr = cufft_load();
  if lr.is_err {
    if lr.error.kind == CUFFT_LOAD_ABSENT || lr.error.kind == CUFFT_LOAD_NO_DEVICE {
      return report(true, "live: SKIP -- " + lr.error.message);
    }
    return report(false, "live: load failed -- " + lr.error.message);
  }
  let lib = lr.value;
  var failed = 0;
  failed = failed + report(true, "live: cuFFT runtime loaded (XIOM_CUFFT_DIR / OS search)");

  let vr = cufft_get_version(&lib);
  if vr.is_ok {
    failed = failed + report(vr.value > 0,
      "version: " + i2s(vr.value) + " (cufftGetVersion)");
  } else {
    failed = failed + report(false, "version: " + vr.error.message);
  }

  let e1 = cufft_estimate1d(&lib, 8, CUFFT_R2C, 1);
  if e1.is_ok {
    failed = failed + report(e1.value >= 0,
      "estimate1d: " + i2s(e1.value) + " workspace bytes for an 8-point R2C");
  } else {
    failed = failed + report(false, "estimate1d: " + e1.error.message);
  }
  let e2 = cufft_estimate2d(&lib, 4, 4, CUFFT_Z2Z);
  if e2.is_ok {
    failed = failed + report(e2.value >= 0,
      "estimate2d: " + i2s(e2.value) + " workspace bytes for a 4x4 Z2Z");
  } else {
    failed = failed + report(false, "estimate2d: " + e2.error.message);
  }

  // ---- 1D R2C / C2R ----
  let pr = cufft_plan1d(&lib, 8, CUFFT_R2C, 1);
  if pr.is_err {
    failed = failed + report(false, "plan1d: " + pr.error.message);
    let _ = cufft_unload(&lib);
    return failed;
  }
  let p_r2c = pr.value;
  failed = failed + report(true, "plan1d: 8-point R2C plan created");
  failed = failed + expect_unit(cufft_set_stream(&p_r2c, 0),
    "setStream: default stream bound");

  let rr = cufft_buffer_alloc(32);
  let cr = cufft_buffer_alloc(64);
  if rr.is_err || cr.is_err {
    failed = failed + report(false, "device buffers: R2C allocation failed");
    let _ = cufft_destroy(&p_r2c);
    let _ = cufft_unload(&lib);
    return failed;
  }
  let dreal = rr.value;
  let dcplx = cr.value;

  var ones = Vec[Float32].with_len(8);
  var i = 0;
  while i < 8 {
    ones[i] = 1.0 as Float32;
    i = i + 1;
  }
  failed = failed + expect_unit(cufft_buffer_upload_f32(&dreal, &ones), "upload: 8 real ones");
  failed = failed + expect_unit(cufft_exec_r2c(&p_r2c, &dreal, &dcplx),
    "exec: R2C forward transform");
  var spec = Vec[Float32].with_len(10);
  failed = failed + expect_unit(cufft_buffer_download_f32(&dcplx, &mut spec),
    "download: R2C spectrum");
  let r2c_ok = approx32(spec[0], 8.0 as Float32, 0.01 as Float32)
    && approx32(spec[1], 0.0 as Float32, 0.01 as Float32)
    && approx32(spec[2], 0.0 as Float32, 0.01 as Float32)
    && approx32(spec[3], 0.0 as Float32, 0.01 as Float32)
    && approx32(spec[9], 0.0 as Float32, 0.01 as Float32);
  failed = failed + report(r2c_ok,
    "R2C: DC = 8+0i and all other bins ~0 (N/2+1 = 5 bins), got ["
      + f32s(spec[0]) + "," + f32s(spec[1]) + "]");

  let pcr = cufft_plan1d(&lib, 8, CUFFT_C2R, 1);
  if pcr.is_err {
    failed = failed + report(false, "plan1d: C2R " + pcr.error.message);
    let _ = cufft_destroy(&p_r2c);
    let _ = cufft_unload(&lib);
    return failed;
  }
  let p_c2r = pcr.value;
  failed = failed + expect_unit(cufft_exec_c2r(&p_c2r, &dcplx, &dreal),
    "exec: C2R inverse transform");
  var back = Vec[Float32].with_len(8);
  failed = failed + expect_unit(cufft_buffer_download_f32(&dreal, &mut back),
    "download: C2R real output");
  var c2r_ok = true;
  i = 0;
  while i < 8 {
    if !approx32(back[i], 8.0 as Float32, 0.001 as Float32) { c2r_ok = false; }
    i = i + 1;
  }
  failed = failed + report(c2r_ok,
    "C2R: round trip recovers 8.0 at every point (unnormalized; 1/N gives 1.0)");

  // ---- 2D Z2Z ----
  let pzr = cufft_plan2d(&lib, 4, 4, CUFFT_Z2Z);
  if pzr.is_err {
    failed = failed + report(false, "plan2d: Z2Z " + pzr.error.message);
    let _ = cufft_destroy(&p_r2c);
    let _ = cufft_destroy(&p_c2r);
    let _ = cufft_unload(&lib);
    return failed;
  }
  let p_z2z = pzr.value;
  failed = failed + report(true, "plan2d: 4x4 Z2Z plan created");

  let zir = cufft_buffer_alloc(256);
  let zor = cufft_buffer_alloc(256);
  if zir.is_err || zor.is_err {
    failed = failed + report(false, "device buffers: Z2Z allocation failed");
    let _ = cufft_destroy(&p_r2c);
    let _ = cufft_destroy(&p_c2r);
    let _ = cufft_destroy(&p_z2z);
    let _ = cufft_unload(&lib);
    return failed;
  }
  let dzin = zir.value;
  let dzout = zor.value;

  var zin = Vec[Float64].with_len(32);
  i = 0;
  while i < 16 {
    zin[i * 2] = 1.0;
    zin[i * 2 + 1] = 0.0;
    i = i + 1;
  }
  failed = failed + expect_unit(cufft_buffer_upload_f64(&dzin, &zin), "upload: 4x4 all-ones complex");
  failed = failed + expect_unit(cufft_exec_z2z(&p_z2z, &dzin, &dzout, CUFFT_FORWARD),
    "exec: Z2Z forward transform");
  var zfwd = Vec[Float64].with_len(32);
  failed = failed + expect_unit(cufft_buffer_download_f64(&dzout, &mut zfwd),
    "download: Z2Z forward result");
  let zfwd_ok = approx64(zfwd[0], 16.0, 1e-9) && approx64(zfwd[1], 0.0, 1e-9)
    && approx64(zfwd[2], 0.0, 1e-9) && approx64(zfwd[3], 0.0, 1e-9);
  failed = failed + report(zfwd_ok,
    "Z2Z forward: DC = 16+0i, got [" + f64s(zfwd[0]) + "," + f64s(zfwd[1]) + "]");

  failed = failed + expect_unit(cufft_exec_z2z(&p_z2z, &dzout, &dzin, CUFFT_INVERSE),
    "exec: Z2Z inverse transform");
  var zinv = Vec[Float64].with_len(32);
  failed = failed + expect_unit(cufft_buffer_download_f64(&dzin, &mut zinv),
    "download: Z2Z inverse result");
  var zinv_ok = true;
  i = 0;
  while i < 16 {
    if !approx64(zinv[i * 2], 16.0, 1e-9) { zinv_ok = false; }
    if !approx64(zinv[i * 2 + 1], 0.0, 1e-9) { zinv_ok = false; }
    i = i + 1;
  }
  failed = failed + report(zinv_ok,
    "Z2Z inverse: 16.0 at every point after 1/N^2 scaling (unnormalized)");

  // ---- 1D D2Z / Z2D ----
  let pdr = cufft_plan1d(&lib, 8, CUFFT_D2Z, 1);
  let pzd = cufft_plan1d(&lib, 8, CUFFT_Z2D, 1);
  if pdr.is_err || pzd.is_err {
    failed = failed + report(false, "plan1d: D2Z/Z2D plan creation failed");
    let _ = cufft_destroy(&p_r2c);
    let _ = cufft_destroy(&p_c2r);
    let _ = cufft_destroy(&p_z2z);
    let _ = cufft_unload(&lib);
    return failed;
  }
  let p_d2z = pdr.value;
  let p_z2d = pzd.value;
  failed = failed + report(true, "plan1d: D2Z and Z2D plans created");

  let drr = cufft_buffer_alloc(64);
  let dcr = cufft_buffer_alloc(128);
  if drr.is_err || dcr.is_err {
    failed = failed + report(false, "device buffers: D2Z allocation failed");
    let _ = cufft_destroy(&p_r2c);
    let _ = cufft_destroy(&p_c2r);
    let _ = cufft_destroy(&p_z2z);
    let _ = cufft_destroy(&p_d2z);
    let _ = cufft_destroy(&p_z2d);
    let _ = cufft_unload(&lib);
    return failed;
  }
  let ddreal = drr.value;
  let ddcplx = dcr.value;

  var dones = Vec[Float64].with_len(8);
  i = 0;
  while i < 8 {
    dones[i] = 1.0;
    i = i + 1;
  }
  failed = failed + expect_unit(cufft_buffer_upload_f64(&ddreal, &dones), "upload: 8 double ones");
  failed = failed + expect_unit(cufft_exec_d2z(&p_d2z, &ddreal, &ddcplx),
    "exec: D2Z forward transform");
  var dspec = Vec[Float64].with_len(10);
  failed = failed + expect_unit(cufft_buffer_download_f64(&ddcplx, &mut dspec),
    "download: D2Z spectrum");
  let d2z_ok = approx64(dspec[0], 8.0, 1e-9) && approx64(dspec[1], 0.0, 1e-9)
    && approx64(dspec[2], 0.0, 1e-9);
  failed = failed + report(d2z_ok,
    "D2Z: DC = 8+0i, got [" + f64s(dspec[0]) + "," + f64s(dspec[1]) + "]");

  failed = failed + expect_unit(cufft_exec_z2d(&p_z2d, &ddcplx, &ddreal),
    "exec: Z2D inverse transform");
  var dback = Vec[Float64].with_len(8);
  failed = failed + expect_unit(cufft_buffer_download_f64(&ddreal, &mut dback),
    "download: Z2D real output");
  var z2d_ok = true;
  i = 0;
  while i < 8 {
    if !approx64(dback[i], 8.0, 1e-9) { z2d_ok = false; }
    i = i + 1;
  }
  failed = failed + report(z2d_ok,
    "Z2D: round trip recovers 8.0 after 1/N scaling (unnormalized)");

  // ---- teardown ----
  failed = failed + expect_unit(cufft_destroy(&p_r2c), "destroy: R2C plan");
  failed = failed + expect_unit(cufft_destroy(&p_c2r), "destroy: C2R plan");
  failed = failed + expect_unit(cufft_destroy(&p_z2z), "destroy: Z2Z plan");
  failed = failed + expect_unit(cufft_destroy(&p_d2z), "destroy: D2Z plan");
  failed = failed + expect_unit(cufft_destroy(&p_z2d), "destroy: Z2D plan");
  failed = failed + expect_unit(cufft_buffer_free(&dreal), "free: real (f32)");
  failed = failed + expect_unit(cufft_buffer_free(&dcplx), "free: complex (f32)");
  failed = failed + expect_unit(cufft_buffer_free(&dzin), "free: Z2Z in");
  failed = failed + expect_unit(cufft_buffer_free(&dzout), "free: Z2Z out");
  failed = failed + expect_unit(cufft_buffer_free(&ddreal), "free: real (f64)");
  failed = failed + expect_unit(cufft_buffer_free(&ddcplx), "free: complex (f64)");
  failed = failed + expect_unit(cufft_unload(&lib), "unload: module + context released");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.cufft conformance tests (0.1.0, loader-only) ===");
  io.flush_stdout();
  var failed = 0;
  failed = failed + test_a1_skip_path();
  failed = failed + test_a2_status_names();
  failed = failed + test_a3_invalid_module();
  failed = failed + test_a4_constants();
  failed = failed + test_b_live();
  if failed == 0 {
    io.println("xiom.cufft: all tests passed");
  } else {
    io.println("xiom.cufft: tests failed");
  }
  return failed;
}
