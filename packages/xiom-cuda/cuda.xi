// XIOM -- xiom.cuda: NVIDIA CUDA driver-API bindings (runtime loader).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing is vendored**.  `nvcuda.dll`
// (the CUDA *driver* API library, a system component on any machine with an
// NVIDIA driver) is loaded at runtime; every entry point is resolved with
// GetProcAddress.  The module calls an integer-only C bridge
// (src/cuda_bridge.c) that runs one full probe and caches the results;
// scalar/packed returns avoid out-param slots (finding B-11 applies to
// driver-heavy calls).
//
// All `unsafe`/`extern "C"` live in this single module (G5).
//
// Classification: loader missing / no device -> SKIP; step failures ->
// FAIL.  The deterministic SKIP path is exercisable on any host via
// `cuda_probe_named` with a bogus module name.
//
// G2 pin (SPEC.md): soname `nvcuda.dll` + entry-point set + constants +
// local sample (System32 version/hash).  The full probe covers cuInit,
// driver version, device count/name, compute capability, and a real host ->
// device -> host memory round trip on a fresh context.

module xiom.cuda

extern "C" {
  fn cuprobe_run(dll: *UInt8) -> Int32;
  fn cuprobe_device_name() -> *UInt8;
  fn cuprobe_compute_capability() -> Int32;
  fn cuprobe_memtest_ok() -> Int32;
}

pub const CU_LOAD_ABSENT: Int = 0;   // loader module missing -> SKIP
pub const CU_NO_DEVICE: Int = 1;     // no CUDA device -> SKIP
pub const CU_PROBE_FAILED: Int = 2;  // a probe step failed -> FAIL

pub type CudaLoadError = {
  kind: Int;
  message: Str;
}

pub type CudaInfo = {
  driver_version: Int;      // CUDA driver API version, e.g. 12040 = 12.4
  device_count: Int;
  device_name: Str;         // device 0
  compute_capability: Int;  // e.g. 860 = 8.6
  memtest_ok: Bool;         // host -> device -> host pattern round trip
}

/// Run the full probe against the default loader (`nvcuda.dll`): version,
/// device count/name, compute capability, and a real memory round trip on a
/// fresh context.  Complexity: O(probe).
pub fn cuda_probe() -> Result[CudaInfo, CudaLoadError]
  requires: true
{
  return cuda_probe_named("nvcuda.dll");
}

/// Same probe against an explicitly named loader module -- the deterministic
/// SKIP classification path (pass a bogus name on any host).
/// Complexity: O(probe).
pub fn cuda_probe_named(dll: Str) -> Result[CudaInfo, CudaLoadError]
  requires: dll.len() > 0
{
  let packed = unsafe { cuprobe_run(dll.c_str()) as Int };
  if packed < 0 {
    return Err(cuda_classify(0 - packed));
  }
  var name = "";
  unsafe {
    let p = cuprobe_device_name();
    if (p as Int) != 0 {
      name = Str::from_c_str(p);
    }
  }
  return Ok(CudaInfo{
    driver_version: packed >> 8;
    device_count: packed & 255;
    device_name: name;
    compute_capability: unsafe { cuprobe_compute_capability() as Int };
    memtest_ok: unsafe { cuprobe_memtest_ok() as Int } != 0;
  });
}

// ---- internals -----------------------------------------------------------

fn cuda_classify(code: Int) -> CudaLoadError
  requires: code > 0
{
  if code == 100 {
    return CudaLoadError{ kind: CU_LOAD_ABSENT; message: "nvcuda.dll not found"; };
  }
  if code == 101 {
    return CudaLoadError{ kind: CU_NO_DEVICE; message: "no CUDA device"; };
  }
  return CudaLoadError{ kind: CU_PROBE_FAILED; message: "probe step code=" + cuda_i2s(code) };
}

fn cuda_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
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
  return buf;
}
