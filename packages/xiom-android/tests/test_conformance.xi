// xiom.android conformance suite -- platform-core (libandroid.so +
// libnativewindow.so) loader/probe for the A1 window-core head.
//
// The probe never FAILs on a missing runtime:
//   present runtime -> export-set ABI check + functional AHardwareBuffer
//                      roundtrip (isSupported/allocate/describe/write/
//                      read/release)
//   missing libs    -> ANDROID_LOAD_ABSENT (SKIP; exercised
//                      deterministically below with bogus sonames)
//   broken install  -> ANDROID_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime is absent by design -> SKIP (CI stays green).
// On an Android device/emulator the same suite runs the live path.
//
// Build+run through the runner (compiles src/android_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.android

module android_conformance

use xiom.io;
use xiom.android;

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

fn t_constants() -> Bool {
  var ok = true;
  if ANDROID_LOAD_ABSENT != 0 || ANDROID_LOAD_ABI != 1 { ok = false; }
  if WINDOW_FORMAT_RGBA_8888 != 1 || WINDOW_FORMAT_RGBX_8888 != 2 || WINDOW_FORMAT_RGB_565 != 4 { ok = false; }
  if ANATIVEWINDOW_TRANSFORM_IDENTITY != 0 || ANATIVEWINDOW_TRANSFORM_ROTATE_90 != 4 { ok = false; }
  if ANATIVEWINDOW_TRANSFORM_ROTATE_180 != 3 || ANATIVEWINDOW_TRANSFORM_ROTATE_270 != 7 { ok = false; }
  if AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM != 1 || AHARDWAREBUFFER_FORMAT_R5G6B5_UNORM != 4 { ok = false; }
  if AHARDWAREBUFFER_FORMAT_R16G16B16A16_FLOAT != 0x16 || AHARDWAREBUFFER_FORMAT_BLOB != 0x21 { ok = false; }
  if AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN != 3 || AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN != 0x30 { ok = false; }
  if AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE != 0x100 || AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER != 0x200 { ok = false; }
  return ok;
}

fn t_hwb_functional() -> Int {
  var failed: Int = 0;
  // Small-value sum (no bitwise ops on the flagship values; B-29 discipline).
  let usage = AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN + AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN;
  let supported = hwb_is_supported(64, 64, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM, usage);
  failed = failed + report(supported, "hwb: 64x64 RGBA8 with CPU read/write isSupported");
  if !supported {
    return failed;
  }
  let a = hwb_alloc(64, 64, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM, usage);
  if a.is_ok {
    let buf: HwbBuffer = a.value;
    failed = failed + report(hwb_width(&buf) == 64 && hwb_height(&buf) == 64,
      "hwb: describe 64x64 (got " + to_string(hwb_width(&buf)) + "x" + to_string(hwb_height(&buf)) + ")");
    failed = failed + report(hwb_format(&buf) == AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM,
      "hwb: describe format RGBA8");
    failed = failed + report(hwb_stride(&buf) >= 64 && hwb_layers(&buf) == 1,
      "hwb: stride >= 64 (got " + to_string(hwb_stride(&buf)) + "), layers = 1");
    failed = failed + report(hwb_write_pixel(&buf, 7, 5, 0x11223344), "hwb: write pixel (7,5)");
    let got = hwb_read_pixel(&buf, 7, 5);
    failed = failed + report(got == 0x11223344, "hwb: read pixel roundtrip (got " + to_string(got) + ")");
    hwb_release(buf);
    failed = failed + report(true, "hwb: released");
  } else {
    failed = failed + report(false, "hwb: allocate failed -- " + a.error.message);
  }
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.android conformance tests (platform-core loader/probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: kinds + window/HWB formats + usage flags");

  // SKIP-path classification, deterministic on every host (bogus pair).
  let missing = android_probe_named("xiom-absent-libandroid-xyz.so", "xiom-absent-libnativewindow-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus pair unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == ANDROID_LOAD_ABSENT,
      "skip-path: absent pair classified as ANDROID_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = android_probe();
  if p.is_ok {
    let rt: AndroidRuntime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: declared export set fully resolved (" + to_string(rt.missing_exports) + " missing)");
    failed = failed + t_hwb_functional();
  } else {
    if p.error.kind == ANDROID_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- android runtime not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  android_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.android: all tests passed");
  } else {
    io.println("xiom.android: tests failed");
  }
  return failed;
}
