// probe_real_libarrow.xi -- optional REAL-libarrow probe (SKIP-safe).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of port.ps1 (the conformance suite stays offline via the
// deterministic Phase-1 stub leg of bridge/arrow_bridge.c). This probe
// exercises the two Phase-1 bridge legs that the suite does not:
//
//   1. REAL LIBRARY LEG: the bridge loader scans PATH, XIOM_ARROW_LIB,
//      ARROW_HOME, the Python site-packages (pyarrow bundles libarrow),
//      vcpkg and the standard library directories for libarrow.dll /
//      arrow.dll (Windows) or libarrow.so[.NNNN] / libarrow[.NNNN].dylib
//      (POSIX), and LoadLibraryA/dlopen-loads the first hit. Present ->
//      [PASS] with name/path/version; absent -> [SKIP] (never [FAIL]).
//   2. C DATA INTERFACE LEG (always runs, no libarrow needed): the pinned
//      ArrowArray/ArrowSchema 64-bit layout (72/80 bytes) is checked and a
//      real producer-side int64 column (5 values, null at index 2) is
//      built, consumed and released, verifying the release contract the
//      pandas/pyarrow side depends on (see SPEC.md "Arrow C Data
//      Interface boundary").
//
// Invocation (from the repo root, no system-wide install needed):
//   xiom --run packages\xiom-arrow\tests\probe_real_libarrow.xi `
//       --c-source packages\xiom-arrow\bridge\arrow_bridge.c
// Exit code = number of failures (SKIPs are not failures).
//
// No headers are needed to build this probe: the C Data Interface layout
// is transcribed in bridge/arrow_bridge.c from apache/arrow
// cpp/src/arrow/c/abi.h (Apache-2.0); the full header clone protocol
// (light clone under %TEMP%\kilo, pinned commit) is noted in SPEC.md for
// the Phase-2 real bridge that will need them.
module arrow_real_libarrow_probe

use xiom.arrow;
use xiom.io;
use xiom.convert;

extern "C" {
  fn xiom_arrow_lib_probe() -> Int;
  fn xiom_arrow_lib_candidates() -> Int;
  fn xiom_arrow_lib_name() -> *UInt8;
  fn xiom_arrow_lib_path() -> *UInt8;
  fn xiom_arrow_lib_version() -> *UInt8;
  fn xiom_arrow_lib_unload() -> Int;
  fn xiom_arrow_cdi_layout_check() -> Int;
  fn xiom_arrow_cdi_roundtrip() -> Int;
  fn xiom_arrow_cdi_detail() -> *UInt8;
}

pub fn main() -> Int {
  io.println("=== xiom.arrow real-libarrow probe (SKIP-safe) ===");
  io.println("");
  var fails = 0;

  // -- 1. Package surface sanity (stub leg of the linked bridge). --------
  let v = version();
  if v == "0.1.0" {
    io.println("[PASS] package surface: version=" + v + " (stub bridge linked)");
  } else {
    io.println("[FAIL] package surface: unexpected version " + v);
    fails = fails + 1;
  };

  // -- 2. Real-library leg. ----------------------------------------------
  let present = unsafe { xiom_arrow_lib_probe() };
  let tried = unsafe { xiom_arrow_lib_candidates() };
  if present == 1 {
    let name = unsafe { Str::from_c_str(xiom_arrow_lib_name()) };
    let path = unsafe { Str::from_c_str(xiom_arrow_lib_path()) };
    let ver = unsafe { Str::from_c_str(xiom_arrow_lib_version()) };
    io.println("[PASS] real libarrow loaded: " + name);
    io.println("       path:    " + path);
    if ver.len() > 0 {
      io.println("       version: " + ver);
    };
    let unload_rc = unsafe { xiom_arrow_lib_unload() };
    if unload_rc == 0 {
      io.println("[PASS] real libarrow unloaded cleanly");
    } else {
      io.println("[FAIL] real libarrow unload returned " + convert.to_string(unload_rc));
      fails = fails + 1;
    };
  } else {
    io.println("[SKIP] real libarrow absent (" + convert.to_string(tried) + " candidates tried:");
    io.println("       libarrow.dll/arrow.dll/libarrow.so[.N]/libarrow[.N].dylib in PATH,");
    io.println("       XIOM_ARROW_LIB, ARROW_HOME, System32, Python site-packages, vcpkg,");
    io.println("       /usr/lib*, /usr/local/lib, /opt/homebrew/lib)");
    io.println("       Install libarrow or set XIOM_ARROW_LIB to exercise the real leg.");
  };

  // -- 3. Arrow C Data Interface boundary (deterministic; no lib needed). -
  let lay = unsafe { xiom_arrow_cdi_layout_check() };
  let lay_detail = unsafe { Str::from_c_str(xiom_arrow_cdi_detail()) };
  if lay == 0 {
    io.println("[PASS] C Data Interface layout: " + lay_detail);
  } elif lay == 2 {
    io.println("[SKIP] C Data Interface layout: " + lay_detail);
  } else {
    io.println("[FAIL] C Data Interface layout: " + lay_detail);
    fails = fails + 1;
  };

  let rt = unsafe { xiom_arrow_cdi_roundtrip() };
  let rt_detail = unsafe { Str::from_c_str(xiom_arrow_cdi_detail()) };
  if rt == 0 {
    io.println("[PASS] C Data Interface round-trip: " + rt_detail);
  } else {
    io.println("[FAIL] C Data Interface round-trip (code " + convert.to_string(rt) + "): " + rt_detail);
    fails = fails + 1;
  };

  io.println("");
  var lib_leg = "SKIP";
  if present == 1 { lib_leg = "PASS"; };
  if fails == 0 {
    io.println("probe: OK (real-lib leg " + lib_leg + ")");
  } else {
    io.println("probe: FAILED (" + convert.to_string(fails) + " failures)");
  };
  return fails;
}
